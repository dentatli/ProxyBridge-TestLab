"""Controlled TCP echo RTT: full response, current route evidence, warmup excluded."""
import argparse
from datetime import datetime
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import re
import statistics

from pb_tcp_benchmark_report import read, jsonl


def metrics(values):
    ordered = sorted(values)
    return dict(p50_ms=statistics.median(ordered),
                p95_ms=ordered[math.ceil(.95*len(ordered))-1],
                p99_ms=ordered[math.ceil(.99*len(ordered))-1],
                max_ms=ordered[-1], responses_above_20ms=sum(v>20 for v in values))


def evaluate_run(path):
    errors = []
    cfg = read(path/'benchmark-config.json')
    receipt = read(path/'run-receipt.json')
    mode = receipt['mode']
    three_modes = cfg.get('comparison_stage') in ('three_modes_readiness_v1', 'three_modes_workload_v1')
    if mode not in ('OFF', 'PROXY') and not (mode == 'UNRULED' and three_modes):
        errors.append('Unsupported RTT mode or missing three-mode method')
    contract = cfg.get('product_contract', 'driver')
    product = read(path/'product-build.json')
    paired_driver=contract=='driver' and cfg.get('version_rtt_stage')=='repeat_rtt_v1'
    if contract not in ('driver', 'v4.0.0') or (contract=='v4.0.0' and (product['selected_contract'] != contract or not product['files_verified'])):
        errors.append('Selected product contract or files not confirmed')
    processes = {name:read(path/(name+'-process.json')) for name in ('client','receiver','proxy','sampler')}
    load = cfg.get('load')
    if load:
        processes.update({name:read(path/(name+'-process.json')) for name in ('load-client','load-receiver')})
    if receipt['status']!='COMPLETED' or not all(receipt[k] for k in ('workers_stopped','driver_stop_observed','receiver_identity_verified')):
        errors.append('Run or owned-resource cleanup incomplete')
    for name, process in processes.items():
        if process['exit_code']!=0 or process.get('forced_stop') or process.get('timed_out') or not process['output_capture_complete']:
            errors.append(name+': process completion not confirmed')
    if 'Exception in callback' in processes['proxy']['stderr']:
        errors.append('Proxy Python event-loop callback failed')
    native = jsonl(path/'client.jsonl')
    endpoint = jsonl(path/'receiver.jsonl')
    proxy = jsonl(path/'proxy.jsonl')
    total = cfg['echo_count']+cfg['warmup_count']
    if len(native)!=total or [r['sequence'] for r in native]!=list(range(1,total+1)):
        errors.append('Requested echo sequence incomplete')
    for row in native:
        identity = f"PB_NET|test_id=local_tcp_echo_rtt|run_id={cfg['run_id']}|sequence={row['sequence']}|phase=stream_{row['sequence']}|protocol=TCP\n".encode()
        payload = identity+b'X'*(cfg['message_bytes']-len(identity))
        expected_sha = hashlib.sha256(payload).hexdigest()
        if (len(payload)!=cfg['message_bytes'] or row['run_id']!=cfg['run_id'] or row['test_id']!='local_tcp_echo_rtt' or
            row['protocol']!='TCP' or row['phase']!=f"stream_{row['sequence']}" or
            row['process_id']!=processes['client']['pid'] or row['actual_result']!='pass' or row['wsa_error']!=0 or
            row['expected_action']!=('PROXY' if mode=='PROXY' else 'DIRECT') or
            row['bytes_sent']!=cfg['message_bytes'] or row['bytes_received']!=cfg['message_bytes'] or row['response_count']!=1 or
            row['payload_sha256']!=expected_sha or row['response_sha256']!=expected_sha or not row['tcp_nodelay'] or
            not (row['tcp_receive_qpc_ms']>=row['tcp_send_qpc_ms']>0) or
            row['requested_remote_ip']!='127.0.0.1' or row['requested_remote_port']!=cfg['receiver_port'] or
            row['actual_local_ip']!='127.0.0.1' or row['actual_local_port']<=0):
            errors.append('Native payload/identity/RTT/socket verification failed');break
    sockets={(r['socket_id'],r['actual_local_ip'],r['actual_local_port'],r['actual_remote_ip'],r['actual_remote_port']) for r in native}
    if len(sockets)!=1 or any(r['socket_id']<=0 for r in native):
        errors.append('One persistent native TCP socket not confirmed')
    if any(b['tcp_send_qpc_ms']<a['tcp_receive_qpc_ms'] for a,b in zip(native,native[1:])):
        errors.append('Sequential request/response timing invalid')
    accepts=[r for r in endpoint if r['event']=='ACCEPTED']
    received=[r for r in endpoint if r['event']=='MESSAGE_RECEIVED']
    echoed=[r for r in endpoint if r['event']=='ECHOED']
    if any(r['event'] in ('CLIENT_ERROR','SERVER_ERROR','SEND_ERROR','RECV_ERROR','ACCEPT_ERROR','REJECTED','RESET_BY_PEER') for r in endpoint):
        errors.append('Receiver error observed')
    if not any(r['event']=='STOPPED' and not r['error'] for r in endpoint):
        errors.append('Receiver orderly stop missing')
    if len(accepts)!=1 or not accepts[0].get('tcp_nodelay'):
        errors.append('Receiver TCP_NODELAY/one connection not observed')
    expected_records=Counter((r['sequence'],f"stream_{r['sequence']}",r['payload_sha256'],cfg['message_bytes']) for r in native)
    for rows in (received,echoed):
        observed=Counter((r['sequence'],r['phase'],r['sha256'],r['bytes']) for r in rows)
        if observed!=expected_records or len(rows)!=total or any(
                r['run_id']!=cfg['run_id'] or r['test_id']!='local_tcp_echo_rtt' or r['protocol']!='TCP' or
                r['family']!='IPv4' or r['local_ip']!='127.0.0.1' or r['local_port']!=cfg['receiver_port'] or
                r['process_id']!=cfg['receiver_pid'] or r['log_flush_mode']!='BUFFERED' for r in rows):
            errors.append('Receiver per-message identity/hash/volume evidence differs')
    flows=[r for r in proxy if r['event']=='TCP_CONNECTED']
    closes=[r for r in proxy if r['event']=='FLOW_CLOSED']
    if load:
        allowed={cfg['receiver_port'],load['receiver_port']}
        if not any(r['event']=='LISTENING' and set(r.get('receiver_ports',[]))==allowed for r in proxy):
            errors.append('Two configured receiver ports not observed')
        if any(r['destination_port'] not in allowed for r in flows):
            errors.append('Proxy destination outside loaded RTT scenario')
        if mode=='PROXY':
            rtt_flows=[r for r in flows if r['destination_port']==cfg['receiver_port']]
            ids={r['connection_id'] for r in rtt_flows}
            flows=rtt_flows
            closes=[r for r in closes if r['connection_id'] in ids]
    if any(r['event']=='ERROR' for r in proxy) or not any(r['event']=='STOPPED' and r['shutdown_reason']=='STDIN_STOP' for r in proxy):
        errors.append('Proxy error or unconfirmed orderly stop')
    if not any(r['event']=='LISTENING' and r.get('event_loop')==cfg['proxy_event_loop'] for r in proxy):
        errors.append('Configured proxy event loop not observed')
    lifecycle = read(path/'cli-lifecycle.json') if mode in ('PROXY','UNRULED') else None
    if native and accepts:
        destination=('127.0.0.1',cfg['receiver_port'])
        peer=(native[0]['actual_remote_ip'],native[0]['actual_remote_port'])
        receiver_peer=(accepts[0]['remote_ip'],accepts[0]['remote_port'])
        if mode in ('OFF','UNRULED'):
            if flows or closes or peer!=destination or receiver_peer!=(native[0]['actual_local_ip'],native[0]['actual_local_port']):
                errors.append('Direct path socket evidence mismatch')
        else:
            if (len(flows)!=1 or len(closes)!=1 or
                receiver_peer!=(flows[0]['outbound_local_ip'],flows[0]['outbound_local_port']) or
                (flows[0]['destination_ip'],flows[0]['destination_port'])!=destination or
                closes[0]['connection_id']!=flows[0]['connection_id'] or closes[0]['protocol']!='tcp' or
                closes[0]['bytes_up']!=total*(cfg['message_bytes']+4) or closes[0]['bytes_down']!=total*cfg['message_bytes']):
                errors.append('Owned proxy socket/flow/volume evidence mismatch')
            listeners=read(path/'product-tcp-listeners.json')
            if isinstance(listeners,dict): listeners=[listeners]
            owned_ports={r['LocalPort'] for r in listeners if r['OwningProcess']==lifecycle['pid']}
            if peer!=destination and not (peer[0]=='127.0.0.1' and peer[1] in owned_ports):
                errors.append('Native peer is neither destination nor observed CLI listener')
    if lifecycle:
        if not all(lifecycle[k] for k in ('ready','graceful_stop','post_stop_verified','output_capture_complete')) or lifecycle['forced_stop'] or lifecycle['error']:
            errors.append('CLI lifecycle incomplete')
    if lifecycle and mode=='PROXY':
        routes=read(path/'route-observations.json')
        if isinstance(routes,dict):routes=[routes]
        settings=re.search(r'\[1\]\s+SOCKS5\s+127\.0\.0\.1:54123\s+\(id=(\d+)\)',lifecycle['stdout'])
        if contract == 'v4.0.0':
            route_found = any(r['event']=='ROUTE_DECISION' and r['pid']==processes['client']['pid'] and
                r['process'].lower()=='pb_tcp_rtt_client.exe' and r['destination_ip']=='127.0.0.1' and
                r['destination_port']==cfg['receiver_port'] and r['action']=='PROXY' and
                r['route_detail']=='Proxy SOCKS5://127.0.0.1:54123' for r in routes)
            connections = read(path/'product-proxy-connections.json')
            if isinstance(connections, dict): connections = [connections]
            if len(flows)!=1 or not any(c['OwningProcess']==lifecycle['pid'] and
                c['RemoteAddress']=='127.0.0.1' and c['RemotePort']==cfg['proxy_port'] and
                (c['LocalAddress'],c['LocalPort'])==(flows[0]['inbound_peer_ip'],flows[0]['inbound_peer_port']) for c in connections):
                errors.append('Legacy CLI ownership of controlled SOCKS5 data flow not confirmed')
        else:
            route_found = any(r['event']=='RELAY_ACCEPTED_REDIRECT' and r['pid']==processes['client']['pid'] and
                r['destination_ip']=='127.0.0.1' and r['destination_port']==cfg['receiver_port'] and
                r['action']=='PROXY' and settings and r['proxy_config_id']==int(settings.group(1)) for r in routes)
        if not settings or not route_found:
            errors.append('Product route observation missing')
    before,after=[read(path/('loaded-drivers-'+s+'.json')) for s in ('before','after')]
    if paired_driver:
        context=read(path/'version-context.json')
        if (product['selected_contract']!='driver' or not product['files_verified'] or context['product_contract']!='driver' or
            context['version_rtt_stage']!='repeat_rtt_v1' or not context['reboot_between_versions_observed'] or context['version_switch_ready'] or
            context['boot_identity']['machine_guid']!=context['legacy_boot_identity']['machine_guid'] or
            context['boot_identity']['os_build']!=context['legacy_boot_identity']['os_build'] or
            datetime.fromisoformat(context['boot_identity']['boot_time_utc'])<=datetime.fromisoformat(context['legacy_boot_identity']['boot_time_utc'])):
            errors.append('Bound Driver version/boot reference not confirmed')
        if ((cfg['echo_count'],cfg['warmup_count'],cfg['message_bytes'],cfg['pause_ms'])!=(1000,200,512,20) or
            cfg['live_socket_observation_policy']!='owned-socket-snapshot-before-measurement-v1' or
            context['route_profile_sha256'].lower()!=cfg['route_profile_sha256'].lower()):
            errors.append('Bound Driver traffic/profile/socket policy differs')
        if mode=='PROXY' and hashlib.sha256((path/'route.pbprofile').read_bytes()).hexdigest().lower()!=cfg['route_profile_sha256'].lower():
            errors.append('Pinned Driver route profile changed')
        observation=read(path/'live-socket-observation.json')
        owner=lifecycle['pid'] if mode=='PROXY' else processes['client']['pid']
        target=cfg['proxy_port'] if mode=='PROXY' else cfg['receiver_port']
        if observation['owner_pid']!=owner or observation['target_port']!=target or observation['capture_completed_qpc_ms']<observation['start_qpc_ms']:
            errors.append('Bound Driver live socket observation scope differs')
        connections=read(path/('product-proxy-connections.json' if mode=='PROXY' else 'generator-direct-connections.json'))
        if isinstance(connections,dict):connections=[connections]
        peer=(flows[0]['inbound_peer_ip'],flows[0]['inbound_peer_port']) if mode=='PROXY' and len(flows)==1 else ((native[0]['actual_local_ip'],native[0]['actual_local_port']) if mode=='OFF' and native else None)
        if peer is None or not any(c['OwningProcess']==owner and (c['LocalAddress'],c['LocalPort'])==peer and
            c['RemoteAddress']=='127.0.0.1' and c['RemotePort']==target for c in connections):
            errors.append('Bound Driver owned controlled connection not confirmed')
        for phase in ('before','after','active') if mode=='PROXY' else ('before','after'):
            state=read(path/('interception-'+phase+'.json'));observer=state['windivert']
            if (state['wfp']['status']!='SERVICE_FILE_VERIFIED' or state['wfp']['service_state']!=('Running' if phase=='active' else 'Stopped') or
                (phase!='active' and (not state['wfp_detachment_observed'] or state['boot_identity']!=context['boot_identity'])) or
                not observer['files_verified'] or not observer['capture_complete'] or observer['status']!='NO_HANDLES_OBSERVED' or
                observer['observed_handle_count']!=0 or observer['handles'] or
                observer['observer_sha256']!='f27980b00d97e3f6a590cf4fad04f30f4c61c72324d52af2442afdcf69f31765' or
                observer['observer_dll_sha256']!='c1e060ee19444a259b2162f8af0f3fe8c4428a1c6f694dce20de194ac8d7d9a2'):
                errors.append('Bound Driver '+phase+': WinDivert/WFP/boot observation incomplete')
    if contract == 'v4.0.0':
        context = read(path/'version-context.json')
        if context['product_contract']!=contract or not context['readiness_only'] or not context['reboot_required_before_other_version'] or context['version_switch_ready']:
            errors.append('Legacy readiness/version boundary not confirmed')
        stage=cfg.get('legacy_rtt_stage','smoke_readiness_v1')
        expected={'smoke_readiness_v1':(128,16,'owned-socket-snapshot-smoke-v1'),
                  'repeat_rtt_v1':(1000,200,'owned-socket-snapshot-before-measurement-v1')}.get(stage)
        if (not expected or (cfg['echo_count'],cfg['warmup_count'],cfg['live_socket_observation_policy'])!=expected or
            cfg['message_bytes']!=512 or cfg['pause_ms']!=20):
            errors.append('Legacy readiness traffic or socket observation policy differs')
        observation=read(path/'live-socket-observation.json')
        owner=lifecycle['pid'] if mode=='PROXY' else processes['client']['pid']
        target=cfg['proxy_port'] if mode=='PROXY' else cfg['receiver_port']
        if observation['owner_pid']!=owner or observation['target_port']!=target or observation['capture_completed_qpc_ms']<observation['start_qpc_ms']:
            errors.append('Legacy live socket observation scope differs')
        if mode=='OFF':
            direct=read(path/'generator-direct-connections.json')
            if isinstance(direct,dict): direct=[direct]
            if not native or not any(c['OwningProcess']==owner and
                (c['LocalAddress'],c['LocalPort'])==(native[0]['actual_local_ip'],native[0]['actual_local_port']) and
                c['RemoteAddress']=='127.0.0.1' and c['RemotePort']==cfg['receiver_port'] for c in direct):
                errors.append('Legacy OFF: owned direct connection not confirmed')
        profile = path/'route.pbprofile'
        if mode=='PROXY' and hashlib.sha256(profile.read_bytes()).hexdigest().lower()!=cfg['route_profile_sha256'].lower():
            errors.append('Pinned legacy route profile changed')
        if context['route_profile_sha256'].lower()!=cfg['route_profile_sha256'].lower():
            errors.append('Legacy profile differs from version context')
        stopped_inventory_ok = all(r['query_complete'] and not r['selected_driver_loaded'] and
            all(n.lower()=='windivert64.sys' for n in r['known_interception_drivers']) for r in (before,after))
        for phase in ('before','after'):
            state = read(path/('interception-'+phase+'.json'))
            observer = state['windivert']
            if (state['boot_identity']!=context['boot_identity'] or not state['wfp_detachment_observed'] or not state['wfp_objects']['query_complete'] or
                state['wfp']['status']!='SERVICE_FILE_VERIFIED' or state['wfp']['service_state']!='Stopped' or
                not observer['files_verified'] or not observer['capture_complete'] or observer['status']!='NO_HANDLES_OBSERVED' or
                observer['observed_handle_count']!=0 or observer['handles'] or
                observer['observer_sha256']!='f27980b00d97e3f6a590cf4fad04f30f4c61c72324d52af2442afdcf69f31765' or
                observer['observer_dll_sha256']!='c1e060ee19444a259b2162f8af0f3fe8c4428a1c6f694dce20de194ac8d7d9a2'):
                errors.append('Legacy '+phase+': scoped idle interception not confirmed')
    else:
        stopped_inventory_ok = all(r['query_complete'] and r['known_interception_driver_names_absent'] for r in (before,after))
    if not stopped_inventory_ok or before['other_driver_names_sha256']!=after['other_driver_names_sha256']:
        errors.append('Stopped driver inventory differs or incomplete')
    if mode in ('PROXY','UNRULED'):
        active=read(path/'loaded-drivers-active.json')
        if contract == 'v4.0.0':
            state=read(path/'interception-active.json'); observer=state['windivert']; handles=observer['handles']
            active_ok = (not active['selected_driver_loaded'] and [n.lower() for n in active['known_interception_drivers']]==['windivert64.sys'] and
                state['wfp_detachment_observed'] and state['wfp']['status']=='SERVICE_FILE_VERIFIED' and state['wfp']['service_state']=='Stopped' and
                observer['files_verified'] and observer['capture_complete'] and observer['status']=='HANDLES_OBSERVED' and
                observer['observed_handle_count']==1 and len(handles)==1 and handles[0]['pid']==lifecycle['pid'] and
                handles[0]['layer']=='NETWORK' and handles[0]['flags']=='0' and
                observer['observer_sha256']=='f27980b00d97e3f6a590cf4fad04f30f4c61c72324d52af2442afdcf69f31765' and
                observer['observer_dll_sha256']=='c1e060ee19444a259b2162f8af0f3fe8c4428a1c6f694dce20de194ac8d7d9a2')
        else:
            active_ok = active['selected_driver_loaded'] and len(active['known_interception_drivers'])==1
        if not active['query_complete'] or not active_ok or active['other_driver_names_sha256']!=before['other_driver_names_sha256']:
            errors.append('Active selected driver not confirmed')
    measured=native[cfg['warmup_count']:]
    pc={};system=None;rtt=None;start=None;end=None
    if len(measured)==cfg['echo_count'] and measured:
        start,end=measured[0]['tcp_send_qpc_ms'],measured[-1]['tcp_receive_qpc_ms']
        if (contract=='v4.0.0' and cfg.get('legacy_rtt_stage')=='repeat_rtt_v1') or paired_driver:
            observation=read(path/'live-socket-observation.json')
            if observation['capture_completed_qpc_ms']>=start:
                errors.append('Live socket observation overlapped measured RTT; comparison not confirmed')
        rtt=metrics([r['tcp_receive_qpc_ms']-r['tcp_send_qpc_ms'] for r in measured])
        samples=jsonl(path/'pc-samples.jsonl')
        full=[s for s in samples if s['event']=='SAMPLE' and s['interval_start_qpc_ms']>=start and s['qpc_ms']<=end]
        coverage=sum(s['qpc_ms']-s['interval_start_qpc_ms'] for s in full)
        if len(full)<3 or coverage<.65*(end-start):errors.append('Insufficient system sampling coverage')
        if coverage:
            system=dict(cpu_pct_mean=sum(s['system_cpu_pct']*(s['qpc_ms']-s['interval_start_qpc_ms']) for s in full)/coverage,
                        used_memory_mib_mean=statistics.mean(s['system_memory_used_bytes'] for s in full)/1048576,coverage_ms=coverage)
        roles=dict(receiver=cfg['receiver_pid'],proxy=cfg['proxy_pid'],generator=processes['client']['pid'])
        if load:
            roles.update(load_receiver=load['receiver_pid'],load_generator=processes['load-client']['pid'])
        if lifecycle:roles['proxybridge_cli']=lifecycle['pid']
        for role,pid in roles.items():
            if not any(s['event']=='WATCHED' and s['role']==role and s['pid']==pid for s in samples):
                errors.append(role+': actual identity not watched')
            values=[(p,s['qpc_ms']) for s in full for p in s['processes'] if p['role']==role and p['pid']==pid and p['status']=='OBSERVED' and p['interval_start_qpc_ms']>=start]
            weights=[t-p['interval_start_qpc_ms'] for p,t in values];coverage=sum(weights)
            if len(values)<3 or coverage<.65*(end-start):errors.append(role+': insufficient sampling coverage')
            pc[role]=dict(samples=len(values),coverage_ms=coverage,
                          cpu_pct_machine_mean=sum(p['cpu_pct_machine']*w for (p,_),w in zip(values,weights))/coverage if coverage else None,
                          private_mib_mean=statistics.mean(p['private_bytes'] for p,_ in values)/1048576 if values else None)
    result=dict(schema_version=1,status='INCONCLUSIVE' if errors else 'MEASURED',correctness='INCONCLUSIVE' if errors else 'PASS',errors=errors,
                mode=mode,config=cfg,attempted_echoes=len(native),verified_echoes=sum(r['actual_result']=='pass' for r in native),
                failed_echoes=sum(r['actual_result']!='pass' for r in native),measured_echoes=len(measured),rtt=rtt,pc=pc,system=system,
                measurement_start_qpc_ms=start,measurement_end_qpc_ms=end,
                bundle_sha256=read(path/'product-build.json')['bundle_sha256'],other_driver_names_sha256=before['other_driver_names_sha256'],
                version_switch_ready=False,connection_setup_measured=False)
    if three_modes:
        from pb_tcp_three_mode_report import validate_run
        errors.extend(validate_run(path, cfg, receipt, native, processes, lifecycle, start))
        if errors:
            result.update(status='INCONCLUSIVE', correctness='INCONCLUSIVE')
    if cfg.get('workload_preset') is not None:
        from pb_workload import check_rtt_workload
        check_rtt_workload(cfg, errors)
        if contract != 'driver' or load or paired_driver:
            errors.append('Workload RTT requires standalone driver method')
        observation = read(path/'live-socket-observation.json')
        owner = lifecycle['pid'] if mode == 'PROXY' else processes['client']['pid']
        target = cfg['proxy_port'] if mode == 'PROXY' else cfg['receiver_port']
        if (observation['owner_pid'] != owner or observation['target_port'] != target or
                not (0 < observation['start_qpc_ms'] <= observation['capture_completed_qpc_ms'] < start)):
            errors.append('Workload socket capture did not finish before measured RTT')
        connections = read(path/('product-proxy-connections.json' if mode == 'PROXY' else 'generator-direct-connections.json'))
        if isinstance(connections, dict):
            connections = [connections]
        peer = (flows[0]['inbound_peer_ip'], flows[0]['inbound_peer_port']) if mode == 'PROXY' and len(flows) == 1 else ((native[0]['actual_local_ip'], native[0]['actual_local_port']) if native else None)
        if peer is None or not any(row['OwningProcess'] == owner and (row['LocalAddress'], row['LocalPort']) == peer and
                row['RemoteAddress'] == '127.0.0.1' and row['RemotePort'] == target for row in connections):
            errors.append('Workload owned controlled flow not confirmed')
        result.update(workload_preset=cfg['workload_preset'], readiness_only=False)
        if errors:
            result.update(status='INCONCLUSIVE', correctness='INCONCLUSIVE')
    return result


def run_report(path):
    result=evaluate_run(path)
    (path/'tcp-rtt-report.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    errors=result['errors']
    print(json.dumps(dict(status=result['status'],errors=errors)))
    return not errors


def comparison(path):
    manifest=read(path/'comparison-manifest.json');runs=[];conditions=[];errors=[];pairs=[]
    for entry in manifest['runs']:
        report=read(path/entry['directory']/'tcp-rtt-report.json')
        if entry['status']!='COMPLETED' or report['status']!='MEASURED' or report['errors'] or report['mode']!=entry['mode']:
            errors.append(entry['directory']+': measurement not confirmed')
        cfg={k:v for k,v in report['config'].items() if k not in ('run_id','receiver_pid','proxy_pid','sampler_pid')}
        for key in ('echo_count','warmup_count','message_bytes','pause_ms'):
            if cfg[key]!=manifest[key]:errors.append(entry['directory']+': requested traffic differs')
        conditions.append((cfg,report['bundle_sha256'],report['other_driver_names_sha256']))
        runs.append(dict(**entry,report=report))
    if manifest['status']!='COMPLETED' or len(runs)!=manifest['pair_count']*2 or not conditions or any(c!=conditions[0] for c in conditions[1:]):
        errors.append('Series incomplete or traffic/tool/product/driver conditions differ')
    if len({r['report']['config']['run_id'] for r in runs})!=len(runs):errors.append('Run identities reused')
    for number in range(1,manifest['pair_count']+1):
        group=[r for r in runs if r['pair']==number]
        if [r['mode'] for r in group]!=(['OFF','PROXY'] if number%2 else ['PROXY','OFF']):
            errors.append('Pair order incomplete');continue
        off,on=[next(r['report']['rtt'] for r in group if r['mode']==mode) for mode in ('OFF','PROXY')]
        if off and on:pairs.append(dict(pair=number,**{k:on[k]-off[k] for k in ('p50_ms','p95_ms','p99_ms')}))
    result=dict(status='INCONCLUSIVE' if errors else 'LIMITED_COMPARISON',errors=errors,runs=runs,pairs=pairs,version_switch_ready=False)
    lines=['# Задержка TCP-запроса и ответа / TCP request and response latency','', '**'+result['status']+'**','',
           f"{manifest['echo_count']} измеренных обменов + {manifest['warmup_count']} исключённых прогревочных на запуск; сообщение {manifest['message_bytes']} байт, пауза {manifest['pause_ms']} мс после ответа. / Measured echoes, excluded warmup, pause after reply.", '',
           '| Режим / Mode | p50, ms | p95, ms | p99, ms | Max, ms | CLI CPU, % ПК | CLI RAM, MiB |','|---|---:|---:|---:|---:|---:|---:|']
    if not errors:
        for mode in ('OFF','PROXY'):
            group=[r['report'] for r in runs if r['mode']==mode]
            v={k:statistics.median(r['rtt'][k] for r in group) for k in ('p50_ms','p95_ms','p99_ms')}
            maximum=max(r['rtt']['max_ms'] for r in group)
            cpu=f"{statistics.median(r['pc']['proxybridge_cli']['cpu_pct_machine_mean'] for r in group):.2f}" if mode=='PROXY' else '—'
            mem=f"{statistics.median(r['pc']['proxybridge_cli']['private_mib_mean'] for r in group):.2f}" if mode=='PROXY' else '—'
            lines.append(f"| {mode} | {v['p50_ms']:.3f} | {v['p95_ms']:.3f} | {v['p99_ms']:.3f} | {maximum:.3f} | {cpu} | {mem} |")
        lines+=['','p50/p95/p99 в таблице — медианы показателей отдельных прогонов; Max — максимум всей серии. / Median of run quantiles, maximum across runs.','',
                '| Пара / Pair | Δ p50, ms | Δ p95, ms | Δ p99, ms |','|---|---:|---:|---:|']
        lines.extend(f"| {p['pair']} | {p['p50_ms']:+.3f} | {p['p95_ms']:+.3f} | {p['p99_ms']:+.3f} |" for p in pairs)
        lines+=['',f"Ошибки обменов / Echo failures: {sum(r['report']['failed_echoes'] for r in runs)}; подтверждено вместе с прогревом / verified incl. warmup: {sum(r['report']['verified_echoes'] for r in runs)}."]
    contract=conditions[0][0].get('product_contract','driver') if conditions else 'unknown'
    paired_driver=bool(conditions and conditions[0][0].get('version_rtt_stage')=='repeat_rtt_v1')
    repeated=bool(conditions and conditions[0][0].get('legacy_rtt_stage')=='repeat_rtt_v1')
    scope = (('Выбранный комплект4.0.0, три пары прямого/SOCKS5 RTT, 200 warmup; socket snapshot исключён из измеряемого окна. WinDivert snapshots только совместимого семейства; перед Driver требуется reboot. Это ещё не A/B версий. / Repeated legacy RTT; no version comparison yet.' if repeated else
              'Выбранный комплект4.0.0, только SMOKE готовности: один короткий прямой/SOCKS5 pair, WinDivert snapshots совместимого семейства; перед Driver требуется reboot. Это не A/B версий. / Legacy readiness only; no version comparison.')
             if contract=='v4.0.0' else 'Выбранный Driver kit, local loopback IPv4 only; upstream HEAD/4.0.0 A-B/remote/global cleanup/version switching не подтверждены. / Limited configuration only.')
    if paired_driver:
        scope='Выбранный Driver63be0eb связан с указанной серией4.0.0: общие правила/инструменты, 200warmup и socket snapshot до измерения, новая загрузкаWindows. Итоговое A/B требует проверки обеих серий; глобальная очистка/latestHEAD/remote не подтверждены. / Bound Driver series; cross-version comparison remains pending.'
    lines+=['','QPC: от начала отправки кадра до полного ответа; подключение, клиентские SHA/JSON и пауза вне RTT. Полный путь включает перехват/ProxyBridge, SOCKS5 helper и работу получателя с проверкой/журналом. / Full application round trip; not driver-only latency.', '',
            'Один постоянный TCP-сокет, один запрос в полёте, TCP_NODELAY у клиента/получателя; длина кадра +4 байта, ответ — payload. Receiver BUFFERED 256KiB; generator flush unchanged. / Persistent sequential framed echo, buffered receiver evidence.', '',
            'Это не ICMP ping, односторонняя задержка, время установки соединения, высокая/фиксированная интенсивность или доказательство игровой/длительной стабильности. Низкий темп ограничивает выводы о хвостовых задержках. / No ICMP/one-way/setup/capacity/game-stability claim.', '',
            'CPU/RAM: окно после прогрева, выборки внутри границ; нулевые CPU samples не доказывают отсутствие нагрузки. Driver-only/watts не измерены. SOCKS5 helper Windows SelectorEventLoop ограничен512 sockets. Отрицательная delta не доказывает ускорение. / Sampled resources, no driver-only or power attribution; zero samples/negative deltas do not prove zero cost or acceleration.', '',
            scope,'']
    if contract=='v4.0.0':
        lines+=['OFF: CLI не запущен, совместимых WinDivert handles нет; файл драйвера может оставаться загружен. / OFF may retain an idle loaded WinDivert driver.','']
        if repeated:
            lines+=['Дельты относятся к полному локальному пути SOCKS5 относительно наблюдаемого OFF. Для A/B нужен новый Driver-прогон с теми же правилами, прогревом и методикой; старые серии не объединять. / Local full-path deltas only; fresh equivalent Driver evidence required.','']
        else:
            lines+=['Во время обоих запусков снимается socket snapshot; короткие дельты диагностические. Это не строгая оценка накладных расходов. / Live socket observation may affect timings; diagnostic deltas only.','']
    lines.extend('- '+e for e in errors)
    (path/'comparison-report.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    (path/'summary.md').write_text('\n'.join(lines),encoding='utf-8')
    print(json.dumps(dict(status=result['status'],errors=errors)))
    return not errors


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    group=parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--run-directory',type=Path)
    group.add_argument('--evidence-directory',type=Path)
    args=parser.parse_args()
    raise SystemExit(0 if (run_report(args.run_directory) if args.run_directory else comparison(args.evidence_directory)) else 1)
