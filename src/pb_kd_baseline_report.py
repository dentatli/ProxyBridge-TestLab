"""Validate four native connections and original Core queries; KD coverage stays pending."""
import argparse
import json
from pathlib import Path
from pb_tcp_connections_report import read
from pb_tcp_redirect_context_report import evaluate as evaluate_native, parse_queries
from pb_tcp_kernel_timing_report import parse as parse_timing
from pb_prepare_kd_baseline import POLICY

def evaluate(path):
    result=evaluate_native(path,diagnostic_method='tcp-kd-baseline-v1',report_method='redirect-kd-baseline-v5')
    for name in ('kd-baseline-report.json','summary.md'):
        result['source_sha256'].pop(name,None)
    errors=result['errors']
    result.update(debugger_coverage_verified=False, private_lifecycle_proven=False,
                  root_cause_proven=False, maximum_capacity_verified=False)
    try:
        manifest=read(path/'comparison-manifest.json');mode=read(path/'proxy/run-receipt.json')
        config=read(path/'proxy/benchmark-config.json')
        if manifest['kd_baseline_policy']!=POLICY or config['kd_baseline_policy']!=POLICY:
            raise ValueError('KD_BASELINE_POLICY_DIFFERS')
        if len(mode['phases'])!=1 or mode['phases'][0]['id']!='baseline' or mode['phases'][0]['requested_connections']!=4 or mode['phases'][0]['hold_seconds']!=8:
            raise ValueError('KD_BASELINE_PHASES_DIFFERS')
        if config['workload_preset']['levels'] or config['workload_preset']['minimum_available_bytes']!=536870912:
            raise ValueError('KD_BASELINE_RESOURCE_OR_LEVELS_DIFFERS')
        if not mode['phases'][0]['snapshot_complete']:
            raise ValueError('KD_BASELINE_CONCURRENT_SOCKET_SNAPSHOT_INCOMPLETE')
        cli=read(path/'proxy/cli-lifecycle.json');queries=parse_queries(cli['stdout']);timing=parse_timing(cli['stdout'])
        if len(queries)!=4 or len(timing)!=4 or len(result['phases'])!=1 or result['phases'][0]['successful']!=4 or result['native_failed']!=0:
            raise ValueError('KD_BASELINE_FOUR_SUCCESSFUL_QUERIES_REQUIRED')
        if '[ROUTECASE] case=original backlog=2147483647 delay_ms=0' not in cli['stdout']:
            raise ValueError('KD_BASELINE_ORIGINAL_LISTENER_NOT_OBSERVED')
        by_seq={t['seq']:t for t in timing}
        if set(by_seq)!={q['seq'] for q in queries}:
            raise ValueError('KD_BASELINE_TIMING_SET_DIFFERS')
        for q in queries:
            t=by_seq[q['seq']]
            if t['valid']!=1 or t['exit_qpc']!=q['qpc'] or not 0<t['accept_qpc']<=t['entry_qpc']<=t['exit_qpc']:
                raise ValueError('KD_BASELINE_TIMING_ORDER_DIFFERS')
            if any(t[k]!=q[k] for k in ('socket','relay_pid','thread','frequency','api_return','api_error','bytes')):
                raise ValueError('KD_BASELINE_TIMING_QUERY_IDENTITY_DIFFERS')
        result['query_timing']=timing
        result['verified_native_connections']=4
        result['verified_data_bytes']=4*8*65536
    except (OSError,KeyError,ValueError,TypeError) as exc:
        errors.append('INCOMPLETE_KD_BASELINE: '+str(exc))
    result['status']='KD_BASELINE_CAPTURE_INCOMPLETE' if errors else 'KD_BASELINE_NATIVE_METADATA_CONFIRMED_DEBUGGER_PENDING'
    return result

def main():
    p=argparse.ArgumentParser();p.add_argument('--evidence-directory',type=Path,required=True);a=p.parse_args()
    result=evaluate(a.evidence_directory)
    (a.evidence_directory/'kd-baseline-report.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    lines=['# Четыре соединения для проверки kernel logger','',result['status'],'',
           'Данные CTS/Core и очистка проверяются отдельно. Журнал физического WinDbg ещё не сопоставлен.',
           'Не доказательство причины сбросов, ёмкости или производительности.','']+result['errors']
    (a.evidence_directory/'summary.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print(json.dumps(dict(status=result['status'],connections=result.get('verified_native_connections',0),
                         debugger_coverage_verified=False,errors=result['errors'])))
    return bool(result['errors'])

if __name__=='__main__':
    raise SystemExit(main())
