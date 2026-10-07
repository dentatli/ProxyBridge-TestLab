"""Owned accept/query timestamps; durations distinguish stages, never prove an internal cause."""
import collections,re,statistics
POLICY={'method':'accept-query-qpc-v1','points':['accept-return','query-entry','query-exit'],
        'logging_after_original_query':True,'original_single_query_preserved':True,'payload_recorded':False}
FIELDS='seq socket relay_pid thread accept_qpc entry_qpc exit_qpc frequency valid api_return api_error bytes'.split()

def parse(text):
    records=[]
    for line in text.splitlines():
        if '[CTXTIMING]' not in line:continue
        match=re.search(r'\[CTXTIMING\] (.*)$',line)
        if not match:raise ValueError('TIMING_LINE_INVALID')
        pairs=[word.split('=',1) for word in match[1].split()]
        if any(len(p)!=2 for p in pairs) or [p[0] for p in pairs]!=FIELDS:raise ValueError('TIMING_FIELDS_INVALID')
        try:record={k:int(v) for k,v in pairs}
        except ValueError:raise ValueError('TIMING_VALUE_INVALID') from None
        if any(v<0 or v>2**63-1 for k,v in record.items() if k!='api_return') or record['api_return'] not in (-1,0):raise ValueError('TIMING_VALUE_OUT_OF_RANGE')
        records.append(record)
    if not records:raise ValueError('TIMING_METADATA_MISSING')
    if len({r['seq'] for r in records})!=len(records):raise ValueError('TIMING_SEQUENCE_DUPLICATE')
    return records

def summarize(values):
    ordered=sorted(values)
    return dict(count=len(values),minimum_ms=min(values),median_ms=statistics.median(values),maximum_ms=max(values),
                p95_ms=ordered[max(0,(len(values)*95+99)//100-1)])

def evaluate(text,queries,events,matches,phases):
    records=parse(text);by_seq={r['seq']:r for r in records}
    if set(by_seq)!={q['seq'] for q in queries}:raise ValueError('TIMING_QUERY_SET_DIFFERS')
    event_by_seq={e['seq']:e for e in events};matched={m['query_seq']:m for m in matches}
    if set(matched)!=set(by_seq):raise ValueError('TIMING_REQUIRES_UNIQUE_KERNEL_QUERY_MATCHES')
    phase_by_id={p['id']:p for p in phases};metrics=[]
    for q in queries:
        t=by_seq[q['seq']];e=event_by_seq[matched[q['seq']]['kernel_seq']];p=phase_by_id[q['phase_id']]
        if t['valid']!=1 or t['frequency']<=0 or any(t[k]!=q[k] for k in ('socket','relay_pid','thread','frequency','api_return','api_error','bytes')):
            raise ValueError('TIMING_QUERY_IDENTITY_DIFFERS')
        if t['exit_qpc']!=q['qpc'] or not 0<t['accept_qpc']<=t['entry_qpc']<=t['exit_qpc']:raise ValueError('TIMING_ORDER_OR_COMPLETION_DIFFERS')
        ms=lambda tick:tick*1000/t['frequency']
        if t['frequency']!=e['frequency'] or not p['start_qpc_ms']<=ms(t['accept_qpc'])<=ms(t['exit_qpc'])<=p['end_qpc_ms']:
            raise ValueError('TIMING_OUTSIDE_OWNED_PHASE')
        metrics.append(dict(query_seq=q['seq'],kernel_seq=e['seq'],phase_id=q['phase_id'],category=q['category'],
            accept_return_minus_kernel_finish_ms=ms(t['accept_qpc'])-ms(e['end_qpc']),
            pre_query_after_accept_ms=ms(t['entry_qpc']-t['accept_qpc']),
            query_api_duration_ms=ms(t['exit_qpc']-t['entry_qpc']),
            query_entry_minus_kernel_finish_ms=ms(t['entry_qpc'])-ms(e['end_qpc']),
            kernel_finish_is_after_release_not_exact_apply_return=True))
    groups=collections.defaultdict(list)
    for m in metrics:groups[m['category']].append(m)
    names=['accept_return_minus_kernel_finish_ms','pre_query_after_accept_ms','query_api_duration_ms','query_entry_minus_kernel_finish_ms']
    return dict(method=POLICY['method'],records=len(records),metrics=metrics,
        by_query_category={category:{name:summarize([m[name] for m in group]) for name in names} for category,group in groups.items()},
        timing_association_is_root_cause_proof=False,packet_or_tcp_handshake_events_observed=False)
