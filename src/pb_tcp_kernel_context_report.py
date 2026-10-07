"""Unique kernel classify/Core/native correlation; no speed or capacity verdict."""
import argparse
import collections
import hashlib
import json
from pathlib import Path
import socket
import struct
from datetime import datetime
from pb_kernel_context_collector import Header,Event,MAGIC,VERSION,CAPACITY
from pb_tcp_connections_report import read,jsonl,csv_rows
from pb_tcp_redirect_context_matrix_report import evaluate_case

METHOD='tcp-redirect-kernel-context-v4'

def ip(value):return socket.inet_ntoa(struct.pack('<I',value))

def validate_header(h):
    if set(h)!={name for name,_ in Header._fields_} or any(type(v) is not int or v<0 for v in h.values()):raise ValueError('KERNEL_HEADER_FIELDS_INVALID')
    if (h['magic'],h['version'],h['record_size'],h['capacity'],h['reserved'])!=(MAGIC,VERSION,152,CAPACITY,0):raise ValueError('KERNEL_HEADER_ABI_DIFFERS')
    if not h['frequency'] or h['count']>64 or h['remaining']>CAPACITY or h['overwritten']>h['written'] or h['count']+h['remaining']+h['overwritten']>h['written']:
        raise ValueError('KERNEL_HEADER_COUNTERS_INVALID')

def validate_binding(path):
    freeze=read(path.parent/'runtime-plan.json');build=read(path.parent/'diagnostic-build.json')
    config=read(path/'proxy/benchmark-config.json');installation=read(path/'proxy/kernel-installation.json')
    identity=read(path/'proxy/product-build.json');binding=read(path/'proxy/diagnostic-driver-binding.json')
    frozen=freeze['files']
    def frozen_hash(name,value):
        return sum(Path(f['path']).name.lower()==name.lower() and f['sha256'].lower()==value.lower() for f in frozen)==1
    build_hash=hashlib.sha256((path.parent/'diagnostic-build.json').read_bytes()).hexdigest()
    install_hash=hashlib.sha256((path/'proxy/kernel-installation.json').read_bytes()).hexdigest()
    plan_hash=hashlib.sha256((path.parent/'runtime-plan.json').read_bytes()).hexdigest()
    if build['method']!='redirect-kernel-context-v4' or not build['diagnostic_only'] or build['performance_comparable'] or build['source_commit']!='63be0ebf9bec92bfba95ef3d6729c375aa9af84e':raise ValueError('KERNEL_BUILD_CONTRACT_DIFFERS')
    policy=build['observation_policy']
    if not all(policy[k] is True for k in ('original_actions_preserved','original_query_only','no_delayed_queries','apply_return_is_void')) or policy['payload_recorded'] or policy['raw_kernel_pointers_recorded'] or policy['ring_capacity']!=CAPACITY:
        raise ValueError('KERNEL_OBSERVATION_POLICY_DIFFERS')
    if build['signing']['authenticode_status']!='Valid' or build['signing']['certificate_thumbprint']!='4544323109A45FC4761819E079BBDBD5E0BFE8D6':raise ValueError('KERNEL_SIGNING_RECEIPT_DIFFERS')
    components={c['name']:c['sha256'] for c in build['components']}
    if len(components)!=3 or len(identity['components'])!=3 or {c['file_name'] for c in identity['components']}!=set(components) or not identity['files_verified'] or any(c['sha256']!=components[c['file_name']] or c['status']!='HASH_MATCH' for c in identity['components']):raise ValueError('KERNEL_PRODUCT_IDENTITY_DIFFERS')
    if not all(frozen_hash(name,value) for name,value in components.items()) or not frozen_hash('redirect-context-diagnostic.json',build_hash) or not frozen_hash('pb_kernel_context_collector.py',config['kernel_collector_sha256']):
        raise ValueError('KERNEL_FROZEN_BUILD_OR_COLLECTOR_DIFFERS')
    manifest=read(path/'comparison-manifest.json')
    if manifest['diagnostic_build_receipt_sha256']!=build_hash or config['kernel_installation_sha256']!=install_hash or installation['build_receipt_sha256']!=build_hash or installation['runtime_plan_sha256']!=plan_hash:
        raise ValueError('KERNEL_INSTALLATION_RECEIPT_DIFFERS')
    if installation['status']!='INSTALLED_REBOOT_REQUIRED' or installation['service_name']!='ProxyBridgeDrv' or installation['baseline_sha256']!='3cd79cfc2a9ec6e45a11b2c225d11cb18c504fec3535e3ef1cb730e0e7732c9e' or installation['candidate_sha256']!=components['ProxyBridgeDrv.sys']:
        raise ValueError('KERNEL_INSTALLATION_STATE_DIFFERS')
    if binding['registered_driver_path']!=installation['candidate_path'] or binding['kit_driver_path']!=installation['candidate_path'] or binding['expected_driver_sha256']!=installation['candidate_sha256'] or binding['registered_via_diagnostic_installation'] is not True or binding['installation_receipt_sha256']!=install_hash:
        raise ValueError('KERNEL_REGISTERED_PATH_DIFFERS')
    if datetime.fromisoformat(config['kernel_boot_time_utc'])<=datetime.fromisoformat(installation['installed_at_utc']):raise ValueError('KERNEL_FRESH_BOOT_UNCONFIRMED')
    for stage in ('before','active','after'):
        state=read(path/'proxy'/('interception-'+stage+'.json'))
        if state['wfp']['status']!='SERVICE_FILE_VERIFIED' or state['wfp']['file_path']!=installation['candidate_path'] or state['wfp']['observed_file_sha256']!=installation['candidate_sha256']:
            raise ValueError('KERNEL_SAVED_SERVICE_IDENTITY_DIFFERS')

def correlate(queries,events):
    matched=[];unconfirmed=[]
    for q in queries:
        eligible=[e for e in events if e['reason']==13 and e['pid']==q['native_pid'] and
            ('phase_id' not in q or e.get('phase_id')==q['phase_id']) and
            e['local_port']>0 and e['local_port']==q['peer_port'] and
            (ip(e['local_v4'])==q['peer_addr'] or (e['local_v4']==0 and q['peer_addr']=='127.0.0.1' and
             q.get('native_endpoint_verified') is True and q.get('native_local_endpoint')==f"{q['peer_addr']}:{q['peer_port']}" and
             q.get('native_remote_endpoint')=='127.0.0.1:54122')) and
            ip(e['remote_v4'])=='127.0.0.1' and e['remote_port']==54122 and
            ip(e['new_v4'])==q['local_addr'] and e['new_port']==q['local_port'] and
            e['start_qpc']*1000/e['frequency']<=q['qpc_ms']]
        if len(eligible)!=1:
            unconfirmed.append(dict(query_seq=q['seq'],native_pid=q['native_pid'],eligible_count=len(eligible)));continue
        e=eligible[0]
        if (any(e[k]!=1 for k in ('enabled','acquire_called','writable_called','req_present','allocation_attempted','apply_called','apply_returned','handle_present')) or not e['target_pid'] or
            e['acquire_status']&0x80000000 or e['writable_status']&0x80000000 or not e['rights_in']&1 or e['rights_out']&1 or e['action_out']!=0x1002):
            raise ValueError('KERNEL_APPLY_FIELDS_INVALID')
        if e['allocation_present'] and (e['context_size']!=32 or e['context_family']!=2 or e['context_protocol']!=6 or e['context_pid']!=q['native_pid']):
            raise ValueError('KERNEL_CONTEXT_FIELDS_INVALID')
        if not e['allocation_present'] and e['context_size']!=0:raise ValueError('KERNEL_NULL_SIZE_DIFFERS')
        matched.append(dict(query_seq=q['seq'],kernel_seq=e['seq'],native_pid=q['native_pid'],query_category=q['category'],
            query_api_error=q['api_error'],allocation_present=bool(e['allocation_present']),context_size=e['context_size'],
            apply_call_observed=True,apply_commit_success_proven=False,kernel_local_address=ip(e['local_v4']),
            endpoint_binding=('UNSPECIFIED_LOCAL_ADDRESS_BOUND_BY_NATIVE_CSV' if e['local_v4']==0 else 'EXACT_LOCAL_ADDRESS'),
            observation=('NULL_CONTEXT_SUBMITTED' if not e['allocation_present'] else 'CONTEXT_SUBMITTED_QUERY_FAILED' if q['category']=='API_FAILED' else 'CONTEXT_SUBMITTED_QUERY_AVAILABLE')))
    if len({m['kernel_seq'] for m in matched})!=len(matched):raise ValueError('KERNEL_EVENT_REUSED')
    return matched,unconfirmed

def bind_native_endpoints(path,phase,queries):
    # Re-read the owned client's CSV: never replace an unspecified address by order or time proximity.
    rows=csv_rows(path/'proxy'/phase['id']/'client.csv')
    bound=[]
    for q in queries:
        candidates=[r for r in rows if r['LocalAddress']==f"{q['peer_addr']}:{q['peer_port']}" and
            r['RemoteAddress']=='127.0.0.1:54122' and r['Result']==q['native_result'] and
            r['ConnectionId']==q['native_connection_id'] and int(r['SendBytes'])==q['native_send_bytes'] and
            int(r['RecvBytes'])==q['native_recv_bytes']]
        if len(candidates)!=1:raise ValueError('KERNEL_NATIVE_ENDPOINT_BINDING_NOT_UNIQUE')
        bound.append(dict(q,phase_id=phase['id'],native_endpoint_verified=True,
            native_local_endpoint=candidates[0]['LocalAddress'],native_remote_endpoint=candidates[0]['RemoteAddress']))
    return bound

def evaluate(path):
    result=evaluate_case(path,diagnostic_method=METHOD)
    result['method']='redirect-kernel-context-v4';result['kernel_root_cause_proven']=False
    if result['status']=='DIAGNOSTIC_NOT_STARTED':return result
    try:
        validate_binding(path)
        process=read(path/'proxy/kernel-collector-process.json')
        if process['exit_code']!=0 or process['forced_stop'] or not process['output_capture_complete'] or process['stderr']:
            raise ValueError('KERNEL_COLLECTOR_NOT_CLEAN')
        rows=jsonl(path/'proxy/kernel-context.jsonl')
        ready=[r for r in rows if r['event']=='LISTENING'];stopped=[r for r in rows if r['event']=='STOPPED']
        events=[r['record'] for r in rows if r['event']=='CLASSIFY']
        if len(ready)!=1 or len(stopped)!=1 or ready[0]['method']!='redirect-kernel-context-v4' or ready[0]['pid']!=process['pid'] or stopped[0]['pid']!=process['pid'] or stopped[0]['requested'] is not True:
            raise ValueError('KERNEL_COLLECTOR_LIFECYCLE_INVALID')
        final=stopped[0]['header']
        validate_header(ready[0]['header']);validate_header(final)
        if ready[0]['header']['frequency']!=final['frequency'] or ready[0]['header']['written'] or ready[0]['header']['overwritten']:raise ValueError('KERNEL_INITIAL_RING_NOT_EMPTY')
        if ready[0]['initial_backlog'] or final['overwritten'] or final['remaining'] or final['written']!=len(events) or stopped[0]['records']!=len(events):
            raise ValueError('KERNEL_CAPTURE_MISSING_OR_PREEXISTING_EVENTS')
        if [r['event'] for r in rows]!=['LISTENING']+['CLASSIFY']*len(events)+['STOPPED']:raise ValueError('KERNEL_EVENT_ORDER_OR_KIND_INVALID')
        if [e['seq'] for e in events]!=list(range(1,len(events)+1)) or not events:raise ValueError('KERNEL_SEQUENCE_NOT_COMPLETE')
        for e in events:
            if set(e)!={name for name,_ in Event._fields_} or any(type(v) is not int or v<0 for v in e.values()):raise ValueError('KERNEL_EVENT_FIELDS_INVALID')
        if any(e['frequency']!=final['frequency'] or e['end_qpc']<e['start_qpc'] or e['reason'] not in range(1,14) for e in events):raise ValueError('KERNEL_RECORD_INVALID')
        queries=[q for phase in result['phases'] for q in bind_native_endpoints(path,phase,phase['matched_queries'])]
        cli=read(path/'proxy/cli-lifecycle.json')
        phases=read(path/'proxy/run-receipt.json')['phases'];native_pids={p['client_pid'] for p in phases}
        if any(e['pid'] not in native_pids for e in events):raise ValueError('KERNEL_UNOWNED_NATIVE_PID')
        for e in events:
            owned=[p for p in phases if p['client_pid']==e['pid'] and p['start_qpc_ms']<=e['start_qpc']*1000/e['frequency']<=e['end_qpc']*1000/e['frequency']<=p['end_qpc_ms']]
            if len(owned)!=1:raise ValueError('KERNEL_PHASE_TIME_OUTSIDE_OWNED_WINDOW')
            e['phase_id']=owned[0]['id']
        matched,unconfirmed=correlate(queries,events)
        if any(e['target_pid']!=cli['pid'] for e in events if e['reason']==13):raise ValueError('KERNEL_TARGET_PID_DIFFERS')
        if any(q['category']=='IPV4_CONTEXT_AVAILABLE' and not m['allocation_present'] for q in queries for m in matched if m['query_seq']==q['seq']):
            raise ValueError('KERNEL_CORE_CONTEXT_CONTRADICTION')
        result['kernel_observations']=dict(records=len(events),branch_counts=dict(collections.Counter(str(e['reason']) for e in events)),
            allocation_attempts=sum(e['allocation_attempted'] for e in events),allocation_null=sum(e['allocation_attempted'] and not e['allocation_present'] for e in events),
            local_port_zero=sum(e['local_port']==0 for e in events),matched=matched,unconfirmed=unconfirmed,overwritten=final['overwritten'])
        result['kernel_observations']['matched_categories']=dict(collections.Counter(m['observation'] for m in matched))
        result['kernel_observations']['endpoint_binding_counts']=dict(collections.Counter(m['endpoint_binding'] for m in matched))
        result['kernel_matching_policy']='owned-native-csv-unspecified-local-address-v1'
        build=read(path.parent/'diagnostic-build.json')
        if 'timing_policy' in build:
            from pb_tcp_kernel_timing_report import POLICY,evaluate as evaluate_timing
            if build['timing_policy']!=POLICY or read(path/'proxy/benchmark-config.json').get('kernel_timing_policy')!=POLICY:
                raise ValueError('KERNEL_TIMING_POLICY_DIFFERS')
            result['kernel_timing']=evaluate_timing(cli['stdout'],queries,events,matched,phases)
        if unconfirmed:result['errors'].append('KERNEL_QUERY_MATCH_NOT_UNIQUE: '+str(len(unconfirmed)))
        result['root_cause_scope']='Observed allocation, attachment arguments and void Apply boundary; unique matches only. Missing context after Apply does not alone identify a Windows/kernel defect.'
    except (OSError,KeyError,ValueError,TypeError,OverflowError,struct.error) as error:result['errors'].append('INCOMPLETE_KERNEL_EVIDENCE: '+str(error))
    result['source_sha256']={str(f.relative_to(path)):hashlib.sha256(f.read_bytes()).hexdigest() for f in path.rglob('*') if f.is_file() and f.name not in ('redirect-context-report.json','redirect-context-summary.md')}
    result['status']='DIAGNOSTIC_CAPTURE_INCOMPLETE' if result['errors'] else 'DIAGNOSTIC_KERNEL_METADATA_CORRELATED'
    return result

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--evidence-directory',type=Path,required=True);a=p.parse_args();r=evaluate(a.evidence_directory)
    (a.evidence_directory/'redirect-context-report.json').write_text(json.dumps(r,ensure_ascii=False,indent=2),encoding='utf-8')
    k=r.get('kernel_observations',{})
    lines=['# Контекст перенаправления: kernel → Core',r['status'],'',
        'Диагностическая сборка; не сравнение скорости, не PASS и не доказательство переполнения таблицы.',
        f"Записей ядра: {k.get('records','—')}; NULL при выделении: {k.get('allocation_null','—')}; уникально связанных запросов: {len(k.get('matched',[]))}; неоднозначных: {len(k.get('unconfirmed',[]))}.",
        'Apply возвращает void: наблюдение вызова не подтверждает сохранение контекста Windows. Отказы без адресов остаются несопоставленными.']+r['errors']
    (a.evidence_directory/'redirect-context-summary.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print(json.dumps(dict(status=r['status'],diagnostic_only=True,native_failed=r.get('native_failed'),kernel_records=k.get('records'),errors=r['errors'])))
    return bool(r['errors'])

if __name__=='__main__':raise SystemExit(main())
