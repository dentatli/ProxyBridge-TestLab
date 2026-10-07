"""Correlate diagnostic Core query metadata with owned native connections, not speed."""
import argparse
import collections
import hashlib
import json
from pathlib import Path
import re
from pb_tcp_connections_report import read, csv_rows, jsonl

FIELDS = ('seq socket relay_pid thread qpc frequency api_return api_error wsa_after bytes required complete '
          'family protocol ctx_pid local_addr local_port local_error peer_addr peer_port peer_error').split()

def parse_queries(stdout):
    records = []
    for line in stdout.splitlines():
        if '[CTXDIAG]' not in line: continue
        tokens=line.split('[CTXDIAG]',1)[1].split()
        if len(tokens)!=len(FIELDS): raise ValueError('QUERY_LINE_INCOMPLETE')
        row=dict(token.split('=',1) for token in tokens)
        if set(row)!=set(FIELDS): raise ValueError('QUERY_FIELDS_INVALID')
        row={k:(v if k.endswith('_addr') else int(v)) for k,v in row.items()}
        if row['frequency']<=0 or row['seq']<=0 or row['required']<=0: raise ValueError('QUERY_NUMBERS_INVALID')
        row['qpc_ms']=row['qpc']*1000/row['frequency']
        if row['api_return']!=0: row['category']='API_FAILED'
        elif row['bytes']<row['required']: row['category']='CONTEXT_SHORT'
        elif row['family']!=2: row['category']='FAMILY_NOT_IPV4'
        else: row['category']='IPV4_CONTEXT_AVAILABLE'
        if row['complete']!=int(row['api_return']==0 and row['bytes']>=row['required']): raise ValueError('QUERY_VERDICT_INCONSISTENT')
        if row['api_error']!=(row['wsa_after'] if row['api_return']==-1 else 0): raise ValueError('QUERY_ERROR_INCONSISTENT')
        records.append(row)
    if len(records)>2000 or len({r['seq'] for r in records})!=len(records): raise ValueError('QUERY_COUNT_OR_SEQUENCE_INVALID')
    return records

def evaluate(path, *, diagnostic_method='tcp-redirect-context-diagnostic-v1', report_method='redirect-context-logging-v1',
             distinguish_unidentified_connect_failures=False, target_ip='127.0.0.1', receiver_evaluator=None):
    errors=[];source={str(p.relative_to(path)):hashlib.sha256(p.read_bytes()).hexdigest() for p in path.rglob('*')
        if p.is_file() and p.name not in ('redirect-context-report.json','redirect-context-summary.md','diagnostic-run.json')}
    result=dict(schema_version=1,method=report_method,diagnostic_only=True,performance_comparable=False,
        correctness='NOT_ASSESSED',table_overflow_proven=False,kernel_root_cause_proven=False,errors=errors,phases=[],source_sha256=source)
    try:
        manifest=read(path/'comparison-manifest.json')
        if manifest['method']!=diagnostic_method or manifest['diagnostic_only'] is not True or manifest['performance_comparable'] is not False:
            raise ValueError('DIAGNOSTIC_MANIFEST_REQUIRED')
        mode=read(path/'proxy/run-receipt.json')
        if manifest['status']=='FAILED' and mode['status']=='FAILED' and not mode['phases'] and not (path/'proxy/cli-lifecycle.json').exists():
            result['status']='DIAGNOSTIC_NOT_STARTED'
            errors.append(mode.get('error') or manifest.get('error') or 'FAILED_BEFORE_CLI')
            observed=path/'proxy/interception-before.json'
            result['preflight_observations_saved']=observed.exists()
            if observed.exists():
                state=read(observed)
                result['preflight']=dict(blocking_reasons=state['blocking_reasons'],wfp_status=state['wfp']['status'],
                    service_state=state['wfp']['service_state'],windivert_status=state['windivert']['status'])
            return result
        cli=read(path/'proxy/cli-lifecycle.json')
        fixture=read(path/'proxy/proxy-process.json')
        result['fixture_callback_error']='Exception in callback' in fixture['stderr']
        if fixture['exit_code']!=0 or fixture['forced_stop'] or not fixture['output_capture_complete'] or result['fixture_callback_error']:
            errors.append('FIXTURE_COMPLETION_OR_CALLBACK_ERROR')
        events=jsonl(path/'proxy/proxy.jsonl')
        if any(e['event']=='ERROR' for e in events) or not any(e['event']=='STOPPED' and e['shutdown_reason']=='STDIN_STOP' for e in events):
            errors.append('FIXTURE_LIFECYCLE_UNCONFIRMED')
        queries=parse_queries(cli['stdout'])
        if not queries: errors.append('NO_QUERY_METADATA')
        result['query_count']=len(queries)
        if any(q['relay_pid']!=cli['pid'] for q in queries):errors.append('QUERY_RELAY_PID_DIFFERS')
        if not all(cli[k] for k in ('ready','graceful_stop','post_stop_verified','output_capture_complete')) or cli['forced_stop'] or cli['error']:
            errors.append('PRODUCT_LIFECYCLE_INCOMPLETE')
        if manifest['status']!='COMPLETED' or mode['status']!='COMPLETED' or not mode['workers_stopped'] or not mode['driver_stop_observed']:
            errors.append('RUN_OR_CLEANUP_INCOMPLETE')
        assigned=[]
        for phase in mode['phases']:
            p=path/'proxy'/phase['id'];rows=csv_rows(p/'client.csv')
            receiver=receiver_evaluator(p,phase) if receiver_evaluator else csv_rows(p/'receiver.csv')
            captured=[q for q in queries if phase['start_qpc_ms']<=q['qpc_ms']<=phase['end_qpc_ms']]
            index=collections.defaultdict(list)
            for q in captured:index[f"{q['peer_addr']}:{q['peer_port']}"].append(q)
            unidentified=[]
            match_rows=rows
            if distinguish_unidentified_connect_failures:
                # A failed connect can have no socket endpoints/GUID in CTS CSV.
                # It is an unmatched native failure, never a duplicate address or a context failure.
                unidentified=[r for r in rows if not r['LocalAddress'] and not r['RemoteAddress'] and not r['ConnectionId']
                    and r['Result'].startswith('10061:') and int(r['SendBytes'])==0 and int(r['RecvBytes'])==0
                    and float(r['TimeMs'])==0]
                match_rows=[r for r in rows if r not in unidentified]
                if unidentified:errors.append(phase['id']+': UNIDENTIFIED_NATIVE_CONNECT_FAILURE_10061: '+str(len(unidentified)))
            native_index={row['LocalAddress']:row for row in match_rows}
            if len(native_index)!=len(match_rows):errors.append(phase['id']+': DUPLICATE_NATIVE_ENDPOINT')
            phase_errors=[];matched=[]
            for row in match_rows:
                events=index.get(row['LocalAddress'],[])
                if len(events)!=1:phase_errors.append('NATIVE_QUERY_MATCH_NOT_UNIQUE');continue
                q=dict(events[0]);assigned.append(q['seq'])
                if row['RemoteAddress']!=target_ip+':54122' or (row['Result']=='Succeeded' and q['category']!='IPV4_CONTEXT_AVAILABLE'):
                    phase_errors.append('NATIVE_QUERY_VERDICT_OR_DESTINATION_DIFFERS')
                q['native_pid']=phase['client_pid'];q['native_result']=row['Result'];q['native_connection_id']=row['ConnectionId']
                q['native_send_bytes']=int(row['SendBytes']);q['native_recv_bytes']=int(row['RecvBytes']);matched.append(q)
                if (target_ip=='127.0.0.1' and q['local_addr']!='127.0.0.1') or q['local_port']!=34010 or q['local_error'] or q['peer_error']:
                    phase_errors.append('QUERY_ENDPOINT_UNCONFIRMED')
                if q['category']=='IPV4_CONTEXT_AVAILABLE' and (q['ctx_pid']!=phase['client_pid'] or q['protocol']!=6):
                    phase_errors.append('RETURNED_CONTEXT_PID_OR_PROTOCOL_DIFFERS')
            if len(captured)!=len(match_rows) or len(rows)!=phase['requested_connections']:phase_errors.append('QUERY_NATIVE_COUNT_DIFFERS')
            failures=[row for row in rows if row['Result']!='Succeeded']
            succeeded=[row for row in rows if row['Result']=='Succeeded']
            receiver_index={row['ConnectionId']:row for row in receiver}
            if len(receiver_index)!=len(receiver) or set(receiver_index)!={row['ConnectionId'] for row in succeeded}:
                phase_errors.append('SUCCESS_RECEIVER_GUID_DIFFERS')
            if any(int(row['SendBytes'])!=phase['hold_seconds']*65536 or receiver_index.get(row['ConnectionId'],{}).get('Result')!='Succeeded'
                or int(receiver_index.get(row['ConnectionId'],{}).get('RecvBytes','-1'))!=int(row['SendBytes']) for row in succeeded):
                phase_errors.append('SUCCESS_DATA_NOT_VERIFIED')
            result['phases'].append(dict(id=phase['id'],requested=phase['requested_connections'],successful=len(succeeded),failed=len(failures),
                query_categories=dict(collections.Counter(q['category'] for q in captured)),
                api_errors=dict(collections.Counter(str(q['api_error']) for q in captured if q['category']=='API_FAILED')),
                matched_queries=matched,errors=sorted(set(phase_errors))))
            if distinguish_unidentified_connect_failures:
                result['phases'][-1].update(accepted_query_count=len(captured),unidentified_native_connect_failures=unidentified,
                    unidentified_native_connect_failure_count=len(unidentified),unidentified_failures_correlated_to_socket=False)
            errors.extend(phase['id']+': '+e for e in sorted(set(phase_errors)))
        if len(assigned)!=len(queries):errors.append('UNASSIGNED_OR_DUPLICATE_QUERY_METADATA')
        result['native_failed']=sum(p['failed'] for p in result['phases'])
        result['root_cause_scope']='API return/size/family observed; kernel allocation/context assignment not observed'
    except (OSError,KeyError,ValueError,TypeError) as exc:
        errors.append('INCOMPLETE_DIAGNOSTIC_EVIDENCE: '+str(exc))
    result['status']='DIAGNOSTIC_CAPTURE_INCOMPLETE' if errors else 'DIAGNOSTIC_METADATA_CORRELATED'
    return result

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--evidence-directory',type=Path,required=True);args=parser.parse_args()
    result=evaluate(args.evidence_directory)
    (args.evidence_directory/'redirect-context-report.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    lines=['# Диагностика WFP-контекста', '', result['status'], '', 'Диагностическая копия Core; не результат сравнения скорости и не PASS корректности.', '',
        '| Фаза | Запрошено | Успешные передачи | Отказ | Категории запроса |', '|---|---:|---:|---:|---|']
    for p in result['phases']:lines.append(f"| {p['id']} | {p['requested']} | {p['successful']} | {p['failed']} | {p['query_categories']} |")
    lines+=['','Занятость таблицы и точная причина в ядре не наблюдались.']+result['errors']
    (args.evidence_directory/'redirect-context-summary.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print(json.dumps(dict(status=result['status'],diagnostic_only=True,native_failed=result.get('native_failed'),errors=result['errors'])))
    return bool(result['errors'])

if __name__=='__main__':raise SystemExit(main())
