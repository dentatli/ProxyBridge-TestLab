"""Targeted accept experiment: exact native role/PID/tuple joins, no clock guessing."""
import argparse
from collections import Counter, defaultdict
from datetime import datetime
import json
from pathlib import Path
import xml.etree.ElementTree as ET

from pb_tcp_connections_report import csv_rows
from pb_tcp_redirect_context_report import parse_queries
from pb_etw_redirect_report import evaluate as evaluate_etw, NS, PROVIDER
from pb_target_accept_plan import create_policy, retrieve_policy, flow_policy


def correlate(roles, queries, receiver, relay_pid):
    errors, matches = [], []
    index = defaultdict(list)
    for q in queries:
        index[f"{q['peer_addr']}:{q['peer_port']}"].append(q)
    seen, assigned = set(), []
    successful = []
    if len({r['pid'] for r in roles.values()}) != 2:
        errors.append('ROLE_PID_NOT_DISTINCT')
    for role, spec in roles.items():
        rows = spec['rows']
        if len(rows) != len(spec['ports']):
            errors.append(role + ':NATIVE_COUNT_DIFFERS')
        actual_ports = []
        for row in rows:
            peer = row['LocalAddress']
            try:
                host, port = peer.rsplit(':', 1)
                port = int(port)
                if host != '127.0.0.1' or port not in spec['ports']:
                    raise ValueError()
                actual_ports.append(port)
            except (ValueError, TypeError):
                errors.append(role + ':NATIVE_ENDPOINT_UNOWNED')
                continue
            if peer in seen:
                errors.append('NATIVE_TUPLE_REUSED')
            seen.add(peer)
            captured = index[peer]
            if len(captured) != 1:
                errors.append(role + ':QUERY_NOT_UNIQUE')
                continue
            q = captured[0]
            assigned.append(q['seq'])
            if (q['relay_pid'] != relay_pid or q['local_addr'] != '127.0.0.1' or
                    q['local_port'] != 34010 or q['local_error'] or q['peer_error'] or
                    row['RemoteAddress'] != '127.0.0.1:54122'):
                errors.append(role + ':QUERY_ENDPOINT_OR_RELAY_DIFFERS')
            good = row['Result'] == 'Succeeded'
            original_failure = (q['api_return'] == -1 and q['api_error'] == 10022 and
                                q['bytes'] == 0 and not good and
                                int(row['SendBytes']) == 0 and int(row['RecvBytes']) == 0)
            if good:
                successful.append(row)
                if (q['category'] != 'IPV4_CONTEXT_AVAILABLE' or q['ctx_pid'] != spec['pid'] or
                        q['protocol'] != 6 or q['bytes'] != 32 or int(row['SendBytes']) != 524288):
                    errors.append(role + ':SUCCESS_CONTEXT_OR_BYTES_DIFFERS')
            elif not original_failure:
                errors.append(role + ':OTHER_NATIVE_FAILURE')
            matches.append(dict(role=role, native_pid=spec['pid'], peer=peer,
                                query=q, native=row, original_api_failure=original_failure))
        if Counter(actual_ports) != Counter(spec['ports']):
            errors.append(role + ':NATIVE_PORT_SET_DIFFERS')
    if Counter(assigned) != Counter(q['seq'] for q in queries):
        errors.append('UNASSIGNED_OR_DUPLICATE_QUERIES')
    expected = Counter(r['ConnectionId'] for r in successful)
    if (any(not guid or count != 1 for guid, count in expected.items()) or
            Counter(r['ConnectionId'] for r in receiver) != expected or
            any(r['Result'] != 'Succeeded' or int(r['RecvBytes']) != 524288 for r in receiver)):
        errors.append('RECEIVER_GUID_OR_DATA_DIFFERS')
    return matches, sorted(set(errors))


def control_events(xml, peer):
    """Use explicit full sockaddr pairs only. No global TCB pointer joins."""
    result = []
    server = '127.0.0.1:34010'
    for _, event in ET.iterparse(xml, events=('end',)):
        if event.tag != '{' + NS['e'] + '}Event':
            continue
        s = event.find('e:System', NS)
        if s.find('e:Provider', NS).get('Guid', '').strip('{}').lower() == PROVIDER:
            eid = int(s.findtext('e:EventID', namespaces=NS))
            d = {v.get('Name'): (v.text or '').strip() for v in event.findall('e:EventData/e:Data', NS)}
            pair = ((d.get('RemoteAddress'), d.get('LocalAddress')) if eid == 1186 else
                    (d.get('LocalSockAddr'), d.get('RemoteSockAddr')))
            if eid in (1186, 1214, 1553) and pair == (server, peer):
                result.append(dict(event_id=eid, version=s.findtext('e:Version', namespaces=NS), data=d,
                                   time=s.find('e:TimeCreated', NS).get('SystemTime'),
                                   message=event.findtext('e:RenderingInfo/e:Message', namespaces=NS)))
        event.clear()
    return result


def evaluate(path):
    read = lambda p: json.loads(p.read_text(encoding='utf-8-sig'))
    errors, matches, events = [], [], []
    result = dict(method='target-accept-report-v1', status='INCOMPLETE', errors=errors,
                  root_cause_proven=False, kernel_ntstatus_observed=False,
                  clock_alignment_verified=False, matches=matches, control_events=events)
    try:
        run, cli, cohort = [read(path / name) for name in ('diagnostic-run.json', 'cli-lifecycle.json', 'cohort.json')]
        observer = run.get('debugger_observer', False)
        probe = False
        staged = False
        if observer:
            policy = read(path / 'runtime-plan.json')['policy']
            retrieve = policy.get('observer') == 'etw+kd-target-retrieve'
            removal = policy.get('observer') == 'etw+kd-target-removal'
            retry = policy.get('observer') == 'etw+kd-target-retry'
            flag=policy.get('observer')=='etw+kd-target-flag'
            flow = flag or retry or removal or policy.get('observer') == 'etw+kd-target-flow'
            probe = policy.get('workload') in ('create-four-probe','retrieve-four-probe','flag-four-probe')
            staged = policy.get('workload') in ('create-target-201-staged','retrieve-target-201-staged','flow-target-201-staged','removal-target-201-staged','retry-target-201-staged','flag-target-201-staged')
            if flow and (run.get('flow_registration_acknowledged') is not True):
                errors.append('FLOW_REGISTRATION_ACK_MISSING')
            if flag:
                from pb_target_flag_binding import policy as flag_policy
                watch=('sendnative' if policy.get('endpoint_send_native_query') is True else 'send256' if policy.get('endpoint_send_accept_limit')==256 else 'send') if policy.get('endpoint_send_gate') is True else 'packet' if policy.get('endpoint_packet_header') is True else policy.get('endpoint_data_watch') is True
                if policy.get('endpoint_nbl_context') is True:watch='nbl'
                if policy.get('endpoint_nbl64_context') is True:watch='nbl64'
                if policy.get('endpoint_nbl512_context') is True:watch='nbl512'
                if policy.get('endpoint_retry_epochs') is True:watch='epochs'
                if policy.get('endpoint_accept_pair') is True:watch='pair'
                if policy.get('endpoint_retry_chain') is True:watch='chain'
                if policy.get('retry_chain_create_armed') is True:watch='chainarmed'
                if policy.get('endpoint_retry_history') is True:watch='history'
                if policy.get('source_accept_snapshot') is True:watch='sourceaccept'
                if policy.get('receive_accept_snapshot') is True:watch='receiveaccept'
                if policy.get('receive_query_snapshot') is True:watch='receivequery'
                armed=policy.get('automatic_debugger_enable_after_create') in ([3],[3,4])
                accept64=policy.get('endpoint_send_native_query') is True or policy.get('raw_hit_limits_per_point')==({'2':16,'3':64,'4':policy.get('endpoint_send_accept_limit',64)} if watch in ('send','send256') else {'2':16,'3':16,'4':64})
                if watch=='receivequery':
                    from pb_receive_query_profile import policy as query_policy
                    if policy!=query_policy(not probe):errors.append('RECEIVE_QUERY_POLICY_INVALID')
                elif watch=='receiveaccept':
                    from pb_receive_accept_profile import policy as receive_policy
                    if policy!=receive_policy(not probe):errors.append('RECEIVE_ACCEPT_POLICY_INVALID')
                elif watch=='sourceaccept':
                    from pb_source_accept_profile import policy as source_policy
                    if policy!=source_policy(not probe):errors.append('SOURCE_ACCEPT_POLICY_INVALID')
                elif watch=='history':
                    from pb_retry_history_profile import policy as history_policy
                    if policy!=history_policy(not probe):errors.append('RETRY_HISTORY_POLICY_INVALID')
                elif watch=='chainarmed':
                    from pb_retry_chain_armed_profile import policy as chain_policy
                    if policy!=chain_policy(not probe):errors.append('RETRY_CHAIN_ARMED_POLICY_INVALID')
                elif watch=='chain':
                    from pb_retry_chain_profile import policy as chain_policy
                    if policy!=chain_policy(not probe):errors.append('RETRY_CHAIN_POLICY_INVALID')
                elif watch=='pair':
                    from pb_accept_pair_profile import policy as pair_policy
                    if policy!=pair_policy(not probe):errors.append('ACCEPT_PAIR_POLICY_INVALID')
                elif policy!=flag_policy(not probe,armed,accept64,policy.get('healthy_setter_probe') is True,watch):errors.append('FLAG_OBSERVER_POLICY_INVALID')
            elif probe and policy != (retrieve_policy(False) if retrieve else create_policy()):
                errors.append('CREATE_FOUR_OBSERVER_POLICY_INVALID')
            elif not probe and policy != (flow_policy(removal, retry) if flow else (retrieve_policy() if retrieve else create_policy(True, staged))):
                errors.append('CREATE_TARGET_OBSERVER_POLICY_INVALID')
        single=observer and policy.get('endpoint_accept_pair') is True and policy.get('single_probe') is True
        filler_count = 0 if single else 3 if probe else 200
        control_stage = 'control-established' if probe else 'control-synsent'
        expected_stages = ['fillers-established', control_stage, 'release-request']
        if staged:
            expected_stages.insert(1, 'host-confirmed')
        if run['status'] != 'COLLECTED':
            errors.append('RUN_CONTROLLER_STATUS_NOT_COLLECTED')
        if run['cleanup_errors'] or not run['resident_disabled_after']:
            errors.append('RESIDENT_OR_HELPER_CLEANUP_INCOMPLETE')
        if (not all(cli[k] for k in ('ready', 'graceful_stop', 'post_stop_verified', 'output_capture_complete')) or
                cli['forced_stop'] or cli['error']):
            errors.append('CLI_LIFECYCLE_INCOMPLETE')
        if cohort['status'] != 'COLLECTED' or not cohort['native_processes_stopped'] or cohort['cleanup_errors']:
            errors.append('COHORT_INCOMPLETE')
        stages = [o['stage'] for o in cohort['observations']]
        if stages != expected_stages:
            errors.append('TARGET_OBSERVATION_SEQUENCE_INCOMPLETE')
        else:
            fill, syn, release = [o for o in cohort['observations'] if o['stage'] != 'host-confirmed']
            if staged:
                host = cohort['observations'][1]
                window = cohort['host_window']
                if (not fill['qpc'] < host['qpc'] < syn['qpc'] or
                        not 0 <= window['opened_ms'] <= window['confirmed_ms'] <= host['elapsed_ms'] < 15000 or
                        window['deadline_ms'] != 15000 or window['source'] != 'user-console-C-after-host-g'):
                    errors.append('TARGET_HOST_CONFIRMATION_INVALID')
            if (not fill['qpc'] < syn['qpc'] < release['qpc'] or len(fill['sockets']) != filler_count or
                    {s['LocalPort'] for s in fill['sockets']} != set(range(42001, 42001+filler_count)) or
                    any(s['Pid'] != fill['pid'] or s['State'] != 5 for s in fill['sockets']) or
                    len(syn['sockets']) != 1 or syn['sockets'][0]['LocalPort'] != 42201 or
                    syn['sockets'][0]['Pid'] != syn['pid'] or syn['sockets'][0]['State'] != (5 if probe else 3)):
                errors.append('TARGET_OWNED_SOCKET_OBSERVATION_INVALID')
        gate_ready = [line for line in cli['stdout'].splitlines() if '[TARGETGATE] stage=ready ' in line]
        gate_exit = [line for line in cli['stdout'].splitlines() if '[TARGETGATE] stage=exit ' in line]
        if len(gate_ready) != 1 or len(gate_exit) != 1 or 'released=1 wait_result=0' not in gate_exit[0]:
            errors.append('TARGET_CORE_GATE_RELEASE_UNCONFIRMED')
        proxy = read(path / 'proxy-process.json')
        if proxy['exit_code'] != 0 or 'Exception in callback' in proxy['stderr']:
            errors.append('PROXY_CLEANUP_INCOMPLETE')
        receiver_process = read(path / 'receiver-process.json')
        if not receiver_process['output_capture_complete'] or receiver_process['timed_out']:
            errors.append('RECEIVER_CAPTURE_INCOMPLETE')
        roles = {}
        for role, ports in (('fillers', list(range(42001, 42001+filler_count))), ('control', [42201])):
            if single and role=='fillers':
                roles[role]=dict(pid=0,ports=[],rows=[])
                continue
            launch = read(path / (role + '-launch.json'))
            process = read(path / (role + '-process.json'))
            if process['pid'] != launch['pid'] or not process['output_capture_complete']:
                errors.append(role + ':PROCESS_IDENTITY_OR_CAPTURE_INCOMPLETE')
            roles[role] = dict(pid=launch['pid'], ports=ports, rows=csv_rows(path / (role + '.csv')))
            if stages == expected_stages:
                observed_pid = cohort['observations'][0 if role == 'fillers' else (2 if staged else 1)]['pid']
                if observed_pid != launch['pid']:
                    errors.append(role + ':SOCKET_OWNER_DIFFERS')
        matches, native_errors = correlate(roles, parse_queries(cli['stdout']), csv_rows(path / 'receiver.csv'), cli['pid'])
        result['matches'] = matches
        errors.extend(native_errors)
        etw = evaluate_etw(path / 'etw')
        result['etw_counters'] = etw['final_counters']
        errors.extend(etw['errors'])
        events = control_events(path / 'etw/events.xml', '127.0.0.1:42201')
        result['control_events'] = events
        drops = [e for e in events if e['event_id'] == 1214 and e['data'].get('Reason') == '30']
        retries = [e for e in events if e['event_id'] == 1186]
        accepts = [e for e in events if e['event_id'] == 1553 and e['data'].get('Succeeded') == '1']
        controls = [m for m in matches if m['role'] == 'control']
        ordered = bool(drops and retries and accepts and
                       datetime.fromisoformat(drops[0]['time']) < datetime.fromisoformat(retries[0]['time']) <=
                       datetime.fromisoformat(accepts[-1]['time']))
        result['target_trigger_observed'] = ordered
        result['control_original_api_failure'] = len(controls) == 1 and controls[0]['original_api_failure']
        if probe and any(m['native']['Result'] != 'Succeeded' for m in matches):
            errors.append('CREATE_FOUR_PROBE_NATIVE_FAILURE')
        result['status'] = ('INCOMPLETE' if errors else
                            'CREATE_PROBE_NATIVE_SUCCESS_DEBUGGER_PENDING' if probe else
                            'TARGET_FAILURE_REPRODUCED' if ordered and result['control_original_api_failure'] else
                            'INCONCLUSIVE_TARGET_NOT_REPRODUCED')
    except (OSError, ValueError, TypeError, KeyError, ET.ParseError) as exc:
        errors.append('INCOMPLETE_EVIDENCE:' + str(exc))
    return result


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--evidence-directory', type=Path, required=True)
    p.add_argument('--output-directory', type=Path)
    args = p.parse_args()
    directory = args.evidence_directory
    report = evaluate(directory)
    output = args.output_directory or directory
    output.mkdir(parents=True, exist_ok=True)
    with (output / 'target-report.json').open('x', encoding='utf-8') as stream:
        json.dump(report, stream, indent=2)
        stream.write('\n')
    print(json.dumps({k: report[k] for k in ('status', 'errors')}))
    raise SystemExit(bool(report['errors']))
