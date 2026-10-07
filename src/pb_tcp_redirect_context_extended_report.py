"""Correlate bounded follow-up metadata without converting original failures to passes."""
import argparse
from collections import Counter
import json
from pathlib import Path
from pb_tcp_redirect_context_report import evaluate as evaluate_base, read

FIELDS=('seq socket relay_pid records_return records_error records_bytes records_capacity '
        'size_return size_error size_bytes wide_return wide_error wide_bytes wide_capacity '
        'wide_complete wide_family wide_protocol wide_ctx_pid').split()

def parse_followups(stdout):
    rows=[]
    for line in stdout.splitlines():
        if '[CTXDIAG_EXTRA]' not in line:continue
        tokens=line.split('[CTXDIAG_EXTRA]',1)[1].split()
        if len(tokens)!=len(FIELDS):raise ValueError('FOLLOWUP_LINE_INCOMPLETE')
        row=dict(token.split('=',1) for token in tokens)
        if set(row)!=set(FIELDS):raise ValueError('FOLLOWUP_FIELDS_INVALID')
        row={k:int(v) for k,v in row.items()}
        if row['seq']<=0 or row['records_capacity']!=1024 or row['wide_capacity']!=1024:raise ValueError('FOLLOWUP_LIMIT_OR_SEQUENCE_INVALID')
        for operation in ('records','size','wide'):
            if row[operation+'_return'] not in (0,-1) or row[operation+'_bytes']<0 or row[operation+'_error']<0:raise ValueError('FOLLOWUP_NUMBERS_INVALID')
            if row[operation+'_return']==0 and row[operation+'_error']!=0:raise ValueError('FOLLOWUP_ERROR_INCONSISTENT')
        if row['wide_complete']!=int(row['wide_return']==0 and 32<=row['wide_bytes']<=1024):raise ValueError('FOLLOWUP_COMPLETE_INCONSISTENT')
        if not row['wide_complete'] and any(row[k] for k in ('wide_family','wide_protocol','wide_ctx_pid')):raise ValueError('FOLLOWUP_INCOMPLETE_CONTEXT_DECODED')
        if row['records_return']==0 and not 0<row['records_bytes']<=1024:raise ValueError('FOLLOWUP_RECORD_LENGTH_INVALID')
        rows.append(row)
    if len(rows)>2000 or len({r['seq'] for r in rows})!=len(rows):raise ValueError('FOLLOWUP_COUNT_OR_SEQUENCE_INVALID')
    return rows

def evaluate(path, *, diagnostic_method='tcp-redirect-context-diagnostic-v2', report_method='redirect-context-followup-v2',
             distinguish_unidentified_connect_failures=False):
    result=evaluate_base(path,diagnostic_method=diagnostic_method,report_method=report_method,
        distinguish_unidentified_connect_failures=distinguish_unidentified_connect_failures)
    result.update(original_failure_verdict_preserved=True,followup_buffer_capacity=1024,kernel_context_absence_proven=False)
    if result['status']=='DIAGNOSTIC_NOT_STARTED':return result
    try:
        rows=parse_followups(read(path/'proxy/cli-lifecycle.json')['stdout'])
        failed={q['seq']:q for p in result['phases'] for q in p['matched_queries'] if q['category']=='API_FAILED'}
        if set(failed)!={r['seq'] for r in rows}:raise ValueError('FOLLOWUP_ORIGINAL_FAILURE_SET_DIFFERS')
        for row in rows:
            original=failed[row['seq']]
            if row['socket']!=original['socket'] or row['relay_pid']!=original['relay_pid']:raise ValueError('FOLLOWUP_SOCKET_OR_PID_DIFFERS')
            row['records_observation']=('RECORDS_RETURNED' if row['records_return']==0 else
                'RECORDS_BUFFER_LIMIT' if row['records_bytes']>1024 else 'RECORDS_QUERY_FAILED')
            row['context_observation']=('CONTEXT_RETURNED_ON_FOLLOWUP' if row['wide_complete'] else
                'CONTEXT_BUFFER_LIMIT' if row['wide_bytes']>1024 else
                'CONTEXT_SHORT_ON_FOLLOWUP' if row['wide_return']==0 else 'CONTEXT_QUERY_FAILED_ON_FOLLOWUP')
            if row['wide_complete']:
                row['context_matches_owned_ipv4_tcp']=(row['wide_family']==2 and row['wide_protocol']==6 and row['wide_ctx_pid']==original['native_pid'])
            row['original_api_return']=original['api_return'];row['original_api_error']=original['api_error']
            row['native_pid']=original['native_pid'];row['native_result']=original['native_result']
        result['followup_count']=len(rows);result['followups']=rows
        result['records_observations']=dict(Counter(r['records_observation'] for r in rows))
        result['context_observations']=dict(Counter(r['context_observation'] for r in rows))
        result['interpretation']='Later metadata queries may change timing; original failures remain failures. Failed queries do not prove an absent kernel context.'
    except (OSError,KeyError,ValueError,TypeError) as error:
        result['errors'].append('INCOMPLETE_FOLLOWUP_EVIDENCE: '+str(error))
    result['status']='DIAGNOSTIC_CAPTURE_INCOMPLETE' if result['errors'] else 'DIAGNOSTIC_METADATA_CORRELATED'
    return result

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--evidence-directory',type=Path,required=True);args=parser.parse_args()
    result=evaluate(args.evidence_directory)
    (args.evidence_directory/'redirect-context-report.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    lines=['# Дополнительная диагностика контекста WFP','',result['status'],'',
        'Исходные API-отказы сохраняются. Дополнительные запросы не исправляют продукт и не являются сравнением скорости.','',
        '| Фаза | Запрошено | Успешные передачи | Исходные отказы |','|---|---:|---:|---:|']
    for phase in result['phases']:lines.append(f"| {phase['id']} | {phase['requested']} | {phase['successful']} | {phase['failed']} |")
    lines+=['','Records: '+str(result.get('records_observations',{})),
        'Context, buffer 1024 bytes: '+str(result.get('context_observations',{})),
        'Успешный поздний запрос не доказывает причину исходного отказа. Отказ позднего запроса не доказывает отсутствие контекста в ядре.']+result['errors']
    (args.evidence_directory/'redirect-context-summary.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print(json.dumps(dict(status=result['status'],diagnostic_only=True,native_failed=result.get('native_failed'),followup_count=result.get('followup_count'),errors=result['errors'])))
    return bool(result['errors'])

if __name__=='__main__':raise SystemExit(main())
