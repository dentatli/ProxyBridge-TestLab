"""Strict case capture audit; TCP trace correlation remains a separate required analysis."""
import argparse, hashlib, json, re
from pathlib import Path
from pb_tcp_connections_report import read
from pb_tcp_kernel_context_report import evaluate as evaluate_kernel

CASES=('original','backlog1024','backlog1024-delay650')

def validate_selection(text, case, timing):
    lines=re.findall(r'\[ROUTECASE\] ([^\r\n]+)',text)
    expected=f'case={case} backlog={2147483647 if case=="original" else -1024} delay_ms={650 if case.endswith("delay650") else 0}'
    if lines!=[expected]: raise ValueError('ROUTE_CASE_RUNTIME_SELECTION_DIFFERS')
    delays=re.findall(r'\[ROUTEDELAY\] start_qpc=(\d+) end_qpc=(\d+) frequency=(\d+) requested_ms=650',text)
    if len(delays)!=(1 if case.endswith('delay650') else 0): raise ValueError('ROUTE_DELAY_COUNT_DIFFERS')
    result=dict(actual_case=case,listener_argument=2147483647 if case=='original' else -1024,delay_count=len(delays))
    if delays:
        start,end,freq=map(int,delays[0])
        if not 0<start<end or freq<=0 or not 600<=(end-start)*1000/freq<=3000: raise ValueError('ROUTE_DELAY_DURATION_UNCONFIRMED')
        from pb_tcp_kernel_timing_report import parse
        records=parse(text)
        if any(t['frequency']!=freq or t['accept_qpc']<end for t in records): raise ValueError('ROUTE_DELAY_ACCEPT_ORDER_DIFFERS')
        result.update(start_qpc=start,end_qpc=end,frequency=freq,actual_wait_ms=(end-start)*1000/freq,
            delayed_owned_connection_proven=False,requires_owned_SYN_and_accept_trace_correlation=True)
    if not timing or timing['records']!=968: raise ValueError('ROUTE_TIMING_CAPTURE_INCOMPLETE')
    return result

def evaluate(path):
    result=dict(method='listener-route-matrix-v1',diagnostic_only=True,performance_comparable=False,
        status='DIAGNOSTIC_ROUTE_MATRIX_CAPTURE_INCOMPLETE',errors=[],cases=[],
        trace_correlation_checked=False,root_cause_proven=False,internal_table_overflow_proven=False)
    try:
        manifest=read(path/'matrix-manifest.json');build=read(path/'diagnostic-build.json');freeze=read(path/'runtime-plan.json')
        if manifest['method']!=result['method'] or manifest['diagnostic_only'] is not True or manifest['performance_comparable'] is not False or manifest['status']!='COMPLETED': raise ValueError('ROUTE_MATRIX_NOT_COMPLETED')
        if [c['id'] for c in manifest['cases']]!=list(CASES) or any(c['directory']!=c['id'] or c['status']!='CONTROLLER_RETURNED' for c in manifest['cases']): raise ValueError('ROUTE_CASE_SET_DIFFERS')
        if freeze['experiment_set']!='RouteMatrix' or freeze['matrix_cases']!=list(CASES) or build['route_matrix_policy']['cases']!=list(CASES): raise ValueError('ROUTE_MATRIX_FREEZE_DIFFERS')
        for case in CASES:
            local=path/case
            report=evaluate_kernel(local)
            item=dict(id=case,status=report['status'],native_failed=report.get('native_failed'),errors=report['errors'])
            result['cases'].append(item)
            if item['errors']: raise ValueError(case+': INCOMPLETE_KERNEL_OR_WORKLOAD_CAPTURE')
            cm=read(local/'comparison-manifest.json')
            if cm.get('route_case')!=case or cm.get('route_matrix_policy')!=build['route_matrix_policy']: raise ValueError('ROUTE_CASE_MANIFEST_BINDING_DIFFERS')
            cli=read(local/'proxy/cli-lifecycle.json')
            item['selection']=validate_selection(cli['stdout'],case,report.get('kernel_timing'))
            from pb_tcp_route_legs import evaluate as evaluate_legs
            item['route_legs']=evaluate_legs(cli['stdout'],report,read(local/'proxy/run-receipt.json')['phases'])
            item['kernel_records']=report['kernel_observations']['records']
            item['allocation_null']=report['kernel_observations']['allocation_null']
        result['status']='DIAGNOSTIC_ROUTE_MATRIX_METADATA_CORRELATED_TRACE_PENDING'
    except (OSError,KeyError,ValueError,TypeError) as error: result['errors'].append(str(error))
    result['hypotheses']=[
        dict(id='allocation-or-apply',evidence='kernel allocation, statuses, actions, original/rewritten tuples and unique original query',verdict='SEE_CASE_EVIDENCE_NO_WINDOWS_RETENTION_PROOF'),
        dict(id='listener-pause-SYN-retry',evidence='original vs backlog1024; TCPIP SYN/drop30/retry/connect/accept by owned PID/tuple/QPC',verdict='PENDING_TRACE_CORRELATION'),
        dict(id='context-wait-expiry',evidence='backlog1024-delay650; wait QPC plus original query and setup drop/retry exclusion',verdict='PENDING_TRACE_CORRELATION'),
        dict(id='fixture-or-target-leg',evidence='TCPIP CLI-to-SOCKS and SOCKS-to-receiver; fixture GUID/data/native/cleanup',verdict='PENDING_TRACE_CORRELATION')]
    return result

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--evidence-directory',type=Path,required=True);a=ap.parse_args();r=evaluate(a.evidence_directory)
    (a.evidence_directory/'route-matrix-report.json').write_text(json.dumps(r,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
    lines=['# Диагностика нескольких гипотез',r['status'],'','| Вариант | Отказы native | Записи ядра | Выделение NULL |','|---|---:|---:|---:|']
    lines += [f"| {c['id']} | {c.get('native_failed','—')} | {c.get('kernel_records','—')} | {c.get('allocation_null','—')} |" for c in r['cases']]
    lines += ['','Сопоставление общей TCP-трассы ещё обязательно: потери, часы, PID/tuple/фазы и время жизни TCB.','Задержка считается проверенной для нужного соединения только после его связывания с SYN/accept.','Полнота метаданных не означает отсутствие дефекта или доказательство внутреннего переполнения.']+r['errors']
    (a.evidence_directory/'route-matrix-summary.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print(json.dumps(dict(status=r['status'],diagnostic_only=True,errors=r['errors'])))
    return bool(r['errors'])
if __name__=='__main__': raise SystemExit(main())
