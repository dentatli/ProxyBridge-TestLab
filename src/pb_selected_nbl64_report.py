"""Validate bounded reject diagnostics before using selected-NBL observations."""
import re
from pb_target_retrieve_report import parse
from pb_selected_nbl_report import correlate as base

REASONS={'IP':'ip','OBJECT':'object','KEY':'key','CONSUME':'consume','RETRIEVE_CALLER':'retrieve','ACCEPT_CALLER':'accept'}


def correlate(text):
    keep=[];samples=[];summary=None;policy=None;errors=[];armed=False;received=False;finished=False
    for line in text.splitlines():
        try:
            if line.startswith('PBN POLICY '):
                p=parse(line,'PBN POLICY ','read_limit sample_limit version'.split())
                if policy or armed or p!=dict(read_limit=64,sample_limit=4,version=2):raise ValueError('NBL64_POLICY_INVALID')
                policy=p
            elif line.startswith('PBN REJECT '):
                m=re.fullmatch(r'(PBN REJECT sample=\S+ read=\S+) reason=([A-Z_]+) (.*)',line)
                if not m:raise ValueError('NBL64_REJECT_FORMAT')
                head,reason,tail=m.groups()
                p=parse(head+' '+tail,'PBN REJECT ','sample read ip nbl_reg key consume retrieve_return accept_return'.split())
                if not armed or received or summary or finished or len(samples)>=4 or reason not in REASONS or p['sample']!=len(samples)+1 or not 1<=p['read']<=64 or (samples and p['read']<=samples[-1]['read']):raise ValueError('NBL64_REJECT_ORDER')
                p['reason']=reason;samples.append(p)
            elif line.startswith('PBN SUMMARY '):
                p=parse(line,'PBN SUMMARY ','total ip object key consume retrieve accept samples'.split())
                if not armed or summary or finished or not 1<=p['total']<=64 or p['samples']!=len(samples) or sum(p[k] for k in REASONS.values())>p['total']:raise ValueError('NBL64_SUMMARY_INVALID')
                summary=p
            else:
                if line.startswith('PBN ARMED '):armed=True
                if line.startswith('PBN RECEIVE '):received=True
                if line.startswith('PBN DONE '):finished=True
                keep.append(line)
        except (ValueError,TypeError,KeyError) as e:errors.append(str(e))
    r=base('\n'.join(keep),64)
    if not policy or not summary:errors.append('NBL64_DIAGNOSTICS_MISSING')
    if summary:
        if r['receive'] and (summary['total']!=r['receive']['raw'] or sum(summary[k] for k in REASONS.values())!=summary['total']-1):errors.append('NBL64_REJECT_COUNTS_DIFFER')
        for reason,field in REASONS.items():
            if sum(s['reason']==reason for s in samples)>summary[field]:errors.append('NBL64_SAMPLE_COUNTS_DIFFER')
    r.update(reject_samples=samples,reject_summary=summary,read_policy=policy)
    r['errors']+=errors
    if r['errors']:r['status']='INCOMPLETE'
    return r
