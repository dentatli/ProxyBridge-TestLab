"""Paired local/Linux destination control; metadata correlation is not root-cause proof."""
import argparse
import hashlib
import json
from pathlib import Path
from pb_tcp_connections_report import read, jsonl
from pb_tcp_kernel_context_report import evaluate as kernel_evaluate
from pb_tcp_external_receiver_evidence import policy_for, receiver_rows, require
from pb_tcp_route_legs import evaluate as route_evaluate

def evaluate_case(path):
    try:
        policy, case=policy_for(path)
        target=policy['host'] if case=='linux' else '127.0.0.1'
        receiver=(lambda folder, phase: receiver_rows(folder, phase, policy)) if case=='linux' else None
        result=kernel_evaluate(path,target_ip=target,receiver_evaluator=receiver)
        result['source_sha256']={name:digest for name,digest in result.get('source_sha256',{}).items()
                               if Path(name).name not in ('external-receiver-report.json','external-receiver-summary.md')}
        result.update(receiver_case=case,original_target_ip=target,topology_method=policy['method'],
                      cross_machine_clock_correlation_used=False,translation_mechanism_verified=False,
                      tcp_trigger_and_ntstatus_trace_correlation_pending=True)
        config=read(path/'proxy/benchmark-config.json')
        require(config['receiver_case']==case and read(path/'comparison-manifest.json')['route_case']=='original', 'EXTERNAL_CONFIG_DIFFERS')
        freeze=read(path.parent/'runtime-plan.json')
        require(freeze['experiment_set']=='ExternalReceiverPair' and freeze['matrix_cases']==['local','linux'] and
                any(f['path']==policy['connection_file'] and f['sha256']==policy['connection_sha256'] for f in freeze['files']),
                'EXTERNAL_FROZEN_CONNECTION_DIFFERS')
        cli=read(path/'proxy/cli-lifecycle.json')
        selectors=[line.split('[ROUTECASE]',1)[1].strip() for line in cli['stdout'].splitlines() if '[ROUTECASE]' in line]
        require(selectors==['case=original backlog=2147483647 delay_ms=0'] and '[ROUTEDELAY]' not in cli['stdout'], 'EXTERNAL_ORIGINAL_QUEUE_UNCONFIRMED')
        if not result['errors']:
            result['route_legs']=route_evaluate(cli['stdout'],result,read(path/'proxy/run-receipt.json')['phases'])
        fixture=jsonl(path/'proxy/proxy.jsonl')
        flows=[e for e in fixture if e['event']=='TCP_CONNECTED']
        require(all(e['destination_ip']==target and e['destination_port']==54122 for e in flows), 'EXTERNAL_PROXY_DESTINATION_DIFFERS')
        expected=sum(p['successful'] for p in result['phases'])
        require(len(flows)==expected and len({e['connection_id'] for e in flows})==expected, 'EXTERNAL_PROXY_FLOW_COUNT_DIFFERS')
        for flow in flows:
            closed=[e for e in fixture if e['event']=='FLOW_CLOSED' and e['connection_id']==flow['connection_id']]
            require(len(closed)==1 and closed[0]['protocol']=='tcp' and closed[0]['bytes_up']==524288 and
                    closed[0]['bytes_down']>=41, 'EXTERNAL_PROXY_DATA_OR_CLOSE_DIFFERS')
        result['root_cause_scope']='Original queue, local SOCKS5, destination varied only. SYN refusal/retry and original NTSTATUS require loss-free Windows raw-QPC trace matching; remote clocks are not aligned.'
    except (OSError,ValueError,KeyError,TypeError) as error:
        if 'result' not in locals(): result=dict(schema_version=1,method='local-linux-receiver-case-v1',diagnostic_only=True,performance_comparable=False,errors=[],phases=[])
        result['errors'].append('INCOMPLETE_EXTERNAL_EVIDENCE: '+str(error))
    result['method']='local-linux-receiver-case-v1'
    result['status']='DIAGNOSTIC_CAPTURE_INCOMPLETE' if result['errors'] else 'DIAGNOSTIC_EXTERNAL_METADATA_CORRELATED_TRACE_PENDING'
    result['kernel_root_cause_proven']=False
    return result

def evaluate_pair(path):
    result=dict(schema_version=1,method='local-linux-receiver-pair-v1',diagnostic_only=True,performance_comparable=False,
                kernel_root_cause_proven=False,errors=[],cases=[],tcp_trigger_and_ntstatus_trace_correlation_pending=True)
    try:
        manifest=read(path/'matrix-manifest.json')
        require(manifest['method']==result['method'] and manifest['diagnostic_only'] is True and
                manifest['performance_comparable'] is False and [(c['id'],c['directory']) for c in manifest['cases']]==[('local','local'),('linux','linux')], 'EXTERNAL_MATRIX_DIFFERS')
        require(manifest['status']=='COMPLETED','EXTERNAL_MATRIX_NOT_COMPLETED')
        for entry in manifest['cases']:
            require(entry['status']=='CONTROLLER_RETURNED','EXTERNAL_CASE_NOT_RETURNED')
            case=evaluate_case(path/entry['directory']);result['cases'].append(case)
            result['errors'].extend(entry['id']+': '+e for e in case['errors'])
    except (OSError,ValueError,KeyError,TypeError) as error: result['errors'].append(str(error))
    result['status']='DIAGNOSTIC_PAIR_CAPTURE_INCOMPLETE' if result['errors'] else 'DIAGNOSTIC_PAIR_METADATA_CORRELATED_TRACE_PENDING'
    return result

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--evidence-directory',type=Path,required=True)
    parser.add_argument('--case',action='store_true');args=parser.parse_args()
    result=evaluate_case(args.evidence_directory) if args.case else evaluate_pair(args.evidence_directory)
    (args.evidence_directory/'external-receiver-report.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (args.evidence_directory/'external-receiver-summary.md').write_text('# Local/Linux receiver control\n\n'+result['status']+'\n\n'+
        'TCP trigger and original NTSTATUS trace correlation pending. No root-cause, fix or capacity verdict.\n\n'+
        '\n'.join('- '+e for e in result['errors'])+'\n',encoding='utf-8')
    print(json.dumps(dict(status=result['status'],diagnostic_only=True,errors=result['errors'])))
    return 2 if result['errors'] else 0

if __name__=='__main__':raise SystemExit(main())
