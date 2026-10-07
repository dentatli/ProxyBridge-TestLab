"""Correlate positive controls, delayed contexts and non-mutating socket metadata."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
from pb_prepare_redirect_context_probes import POLICY, METHOD
from pb_tcp_redirect_context_matrix_report import evaluate_case
from pb_tcp_redirect_context_report import read

RUN_METHOD='tcp-redirect-context-probes-v3'
FIELDS={
 'CONTROL':'seq socket relay_pid qpc_before qpc_after api_return api_error bytes capacity'.split(),
 'LATE':('seq socket relay_pid target_ms qpc_before qpc_after api_return api_error bytes capacity '
         'complete family protocol ctx_pid destination_addr destination_port').split(),
 'SOCKET':('seq socket relay_pid target_ms qpc type_return type_error type_bytes socket_type '
           'local_addr local_port local_error peer_addr peer_port peer_error').split()}

def parse(stdout,kind):
    rows=[];marker='[CTXDIAG_'+kind+']'
    for line in stdout.splitlines():
        if marker not in line:continue
        tokens=line.split(marker,1)[1].split()
        if len(tokens)!=len(FIELDS[kind]):raise ValueError('PROBE_LINE_LENGTH: '+kind)
        row=dict(t.split('=',1) for t in tokens)
        if set(row)!=set(FIELDS[kind]):raise ValueError('PROBE_FIELDS: '+kind)
        row={k:(v if k.endswith('_addr') else int(v)) for k,v in row.items()}
        if row['seq']<=0 or row['socket']<0 or row['relay_pid']<=0:raise ValueError('PROBE_IDENTITY_INVALID')
        if kind!='SOCKET':
            if row['capacity']!=1024 or row['api_return'] not in (0,-1) or row['api_error']<0 or row['bytes']<0:
                raise ValueError('PROBE_API_INVALID')
            if row['api_return']==0 and row['api_error']!=0:raise ValueError('PROBE_API_ERROR_INCONSISTENT')
            if row['qpc_before']<=0 or row['qpc_after']<row['qpc_before']:raise ValueError('PROBE_CLOCK_INVALID')
            if kind=='CONTROL' and row['api_return']==0 and not 0<row['bytes']<=1024:raise ValueError('CONTROL_SIZE_INVALID')
            if kind=='LATE':
                if row['target_ms'] not in POLICY['delayed_targets_ms']:raise ValueError('LATE_TARGET_INVALID')
                if row['complete']!=int(row['api_return']==0 and 32<=row['bytes']<=1024):raise ValueError('LATE_COMPLETE_INVALID')
                if not row['complete'] and (any(row[k] for k in ('family','protocol','ctx_pid','destination_port')) or row['destination_addr']!='unavailable'):
                    raise ValueError('LATE_INCOMPLETE_CONTEXT_DECODED')
        else:
            if row['target_ms'] not in (0,5,25,100) or row['qpc']<=0 or row['type_return'] not in (0,-1) or any(row[k]<0 for k in ('type_error','type_bytes','local_error','peer_error')):
                raise ValueError('SOCKET_METADATA_INVALID')
            if row['type_return']==0 and row['type_error']!=0:raise ValueError('SOCKET_TYPE_ERROR_INCONSISTENT')
            if (row['type_return']!=0 or row['type_bytes']!=4) and row['socket_type']!=0:raise ValueError('SOCKET_INCOMPLETE_TYPE_DECODED')
        rows.append(row)
    limit={'CONTROL':16,'LATE':3000,'SOCKET':4000}[kind]
    keys=[(r['seq'],r.get('target_ms',0)) for r in rows]
    if len(rows)>limit or len(keys)!=len(set(keys)):raise ValueError('PROBE_COUNT_OR_DUPLICATE: '+kind)
    return rows

def correlate(result,stdout):
    originals={q['seq']:q for p in result['phases'] for q in p['matched_queries']}
    controls=parse(stdout,'CONTROL');late=parse(stdout,'LATE');sockets=parse(stdout,'SOCKET')
    expected_controls=sorted(q['seq'] for q in originals.values() if q['complete'] and q['family']==2 and
                              (q['seq']<=4 or q['seq']%128==0))[:16]
    failed=sorted(q['seq'] for q in originals.values() if q['category']=='API_FAILED')[:1000]
    if [r['seq'] for r in controls]!=expected_controls:raise ValueError('POSITIVE_CONTROL_SELECTION_DIFFERS')
    if [(r['seq'],r['target_ms']) for r in late]!=[(seq,t) for seq in failed for t in (5,25,100)]:raise ValueError('DELAYED_SELECTION_OR_ORDER_DIFFERS')
    if [(r['seq'],r['target_ms']) for r in sockets]!=[(seq,t) for seq in failed for t in (0,5,25,100)]:raise ValueError('SOCKET_SELECTION_OR_ORDER_DIFFERS')
    for rows in (controls,late,sockets):
        for row in rows:
            original=originals[row['seq']]
            if any(row[k]!=original[k] for k in ('socket','relay_pid')):raise ValueError('PROBE_ORIGINAL_IDENTITY_DIFFERS')
            stamp=row.get('qpc_before',row.get('qpc'))
            if stamp<original['qpc']:raise ValueError('PROBE_PRECEDES_ORIGINAL')
            row['elapsed_ms']=(stamp-original['qpc'])*1000/original['frequency']
            row['native_result']=original['native_result'];row['native_pid']=original['native_pid']
    late_by_seq={}
    for row in late:
        original=originals[row['seq']]
        if row['elapsed_ms']<row['target_ms']:raise ValueError('LATE_PROBE_TOO_EARLY')
        prior=late_by_seq.setdefault(row['seq'],[])
        if prior and row['qpc_before']<prior[-1]['qpc_after']:raise ValueError('LATE_CLOCK_ORDER_INVALID')
        prior.append(row)
        row['owned_ipv4_tcp_context']=bool(row['complete'] and row['family']==2 and row['protocol']==6 and
            row['ctx_pid']==original['native_pid'] and row['destination_addr']=='127.0.0.1' and row['destination_port']==54122)
        row['observation']=('OWNED_CONTEXT_RETURNED_LATER' if row['owned_ipv4_tcp_context'] else
            'OTHER_CONTEXT_RETURNED_LATER' if row['complete'] else 'CONTEXT_BUFFER_LIMIT_LATER' if row['bytes']>1024 else
            'CONTEXT_SHORT_LATER' if row['api_return']==0 else 'CONTEXT_QUERY_FAILED_LATER')
    socket_groups={}
    for row in sockets:
        original=originals[row['seq']];group=socket_groups.setdefault(row['seq'],[])
        if group and row['qpc']<group[-1]['qpc']:raise ValueError('SOCKET_CLOCK_ORDER_INVALID')
        group.append(row)
        if row['target_ms']:
            probe=next(r for r in late_by_seq[row['seq']] if r['target_ms']==row['target_ms'])
            if row['qpc']!=probe['qpc_after']:raise ValueError('SOCKET_LATE_CLOCK_DIFFERS')
        row['same_stream_endpoints']=bool(row['type_return']==0 and row['type_bytes']==4 and row['socket_type']==1 and
            not row['local_error'] and not row['peer_error'] and all(row[k]==original[k] for k in ('local_addr','local_port','peer_addr','peer_port')))
    for seq,group in late_by_seq.items():
        if socket_groups[seq][0]['qpc']>group[0]['qpc_before']:raise ValueError('SOCKET_INITIAL_CLOCK_ORDER_INVALID')
    result.update(positive_controls=controls,positive_control_count=len(controls),
        positive_records_returned=sum(r['api_return']==0 for r in controls),delayed_probes=late,socket_observations=sockets,
        delayed_observations=dict(Counter(r['observation'] for r in late)),
        delayed_owned_context_sockets=len({r['seq'] for r in late if r['owned_ipv4_tcp_context']}),
        unchanged_socket_metadata_sockets=sum(all(r['same_stream_endpoints'] for r in rows) for rows in socket_groups.values()),
        records_positive_control_observed=any(r['api_return']==0 for r in controls),
        probe_policy=POLICY,original_failure_verdict_preserved=True,
        kernel_context_absence_proven=False,socket_tcp_state_observed=False)
    return result

def evaluate(path):
    result=evaluate_case(path,diagnostic_method=RUN_METHOD)
    if result['status']=='DIAGNOSTIC_NOT_STARTED':return result
    try:
        manifest=read(path/'comparison-manifest.json');config=read(path/'proxy/benchmark-config.json')
        receipt=read(path.parent/'diagnostic-build.json');freeze=read(path.parent/'runtime-plan.json')
        if receipt['method']!=METHOD or receipt['status']!='DIAGNOSTIC_BUILD_PREPARED' or receipt['probe_policy']!=POLICY:
            raise ValueError('PROBE_BUILD_POLICY_DIFFERS')
        if not receipt['diagnostic_only'] or receipt['performance_comparable'] or not receipt['original_verdict_preserved'] or not receipt['followup_only_after_api_failure'] or receipt['followup_buffer_capacity']!=1024 or receipt['followup_queries_per_failure']!=3 or receipt['followup_payload_recorded']:
            raise ValueError('PROBE_BUILD_CONTRACT_INVALID')
        frozen={Path(f['path']).name:f['sha256'].lower() for f in freeze['files']}
        if frozen['redirect-context-diagnostic.json']!=hashlib.sha256((path.parent/'diagnostic-build.json').read_bytes()).hexdigest() or manifest['diagnostic_build_receipt_sha256']!=frozen['redirect-context-diagnostic.json']:
            raise ValueError('PROBE_BUILD_FREEZE_DIFFERS')
        if freeze['experiment_set']!='Single' or freeze['matrix_cases'] or manifest['probe_policy']!=POLICY or config['probe_policy']!=POLICY:
            raise ValueError('PROBE_RUNTIME_POLICY_DIFFERS')
        if manifest['diagnostic_connection_case']!=dict(id='connectex-32',connect_method='ConnectEx',pending_limit=32):raise ValueError('PROBE_CASE_DIFFERS')
        correlate(result,read(path/'proxy/cli-lifecycle.json')['stdout'])
        phases=read(path/'proxy/run-receipt.json')['phases']
        ends={q['seq']:phase['end_qpc_ms'] for phase,p in zip(phases,result['phases']) for q in p['matched_queries']}
        originals={q['seq']:q for p in result['phases'] for q in p['matched_queries']}
        for row in result['positive_controls']+result['delayed_probes']+result['socket_observations']:
            stamp=row.get('qpc_after',row.get('qpc'))
            if stamp*1000/originals[row['seq']]['frequency']>ends[row['seq']]:raise ValueError('PROBE_OUTSIDE_OWNED_PHASE')
        result['interpretation']='Delays and extra queries change accept timing. Original failed transfers stay failed. Same endpoints/type are socket metadata, not wire or TCP-state proof. No kernel cause, performance change or fix is established.'
    except (OSError,KeyError,ValueError,TypeError) as error:
        result['errors'].append('INCOMPLETE_PROBE_EVIDENCE: '+str(error))
    result['status']='DIAGNOSTIC_CAPTURE_INCOMPLETE' if result['errors'] else 'DIAGNOSTIC_METADATA_CORRELATED'
    return result

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--evidence-directory',type=Path,required=True)
    args=parser.parse_args();result=evaluate(args.evidence_directory)
    (args.evidence_directory/'redirect-context-report.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    lines=['# Контекст WFP: три проверки за один запуск','',result['status'],'',
      'Исходные отказы сохраняются. Поздние запросы меняют время accept; это не сравнение скорости и не исправление.',
      '', '| Фаза | Запрошено | Успешные передачи | Исходные отказы |','|---|---:|---:|---:|']
    for p in result['phases']:lines.append(f"| {p['id']} | {p['requested']} | {p['successful']} | {p['failed']} |")
    lines+=['',f"Положительный контроль RECORDS: {result.get('positive_records_returned','—')}/{result.get('positive_control_count','—')} успешных запросов.",
      f"Поздний контекст с подтверждённым PID и назначением: {result.get('delayed_owned_context_sockets','—')} исходно отказавших сокетов.",
      f"Тип и адреса сохранялись во всех наблюдениях: {result.get('unchanged_socket_metadata_sockets','—')} сокетов.",
      'Все поздние отказы не доказывают отсутствие контекста в ядре. Тип и адреса не подтверждают состояние TCP или доставку на проводе.']+result['errors']
    (args.evidence_directory/'redirect-context-summary.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print(json.dumps(dict(status=result['status'],diagnostic_only=True,native_failed=result.get('native_failed'),
         positive_records_returned=result.get('positive_records_returned'),delayed_owned_context_sockets=result.get('delayed_owned_context_sockets'),errors=result['errors'])))
    return bool(result['errors'])

if __name__=='__main__':raise SystemExit(main())
