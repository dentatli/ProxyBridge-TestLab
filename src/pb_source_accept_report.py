"""A distinct endpoint-reference question; no relaxation of the previous NBL join."""
import hashlib
from pathlib import Path
from pb_retry_history_report import correlate as history_correlate
from pb_target_retrieve_report import parse
from pb_source_accept_profile import policy,PROFILE_SHA
def correlate(text):
    filtered=[];sources=[];errors=[];seen_accept=False
    for line in text.splitlines():
        if line.startswith('PBC ACCEPT '):seen_accept=True
        if line.startswith('PBC SOURCE_UNREADABLE '):errors.append('SOURCE_UNREADABLE');continue
        if line.startswith('PBC SOURCE '):
            try:
                if seen_accept:raise ValueError('SOURCE_AFTER_ACCEPT')
                sources.append(parse(line,'PBC SOURCE ','source_ep expected_record record_now context size flags30 accept_ep accept_nbl'.split()))
            except (ValueError,KeyError,TypeError) as e:errors.append(str(e))
        else:filtered.append(line)
    r=history_correlate('\n'.join(filtered));r['errors']+=errors;r['source_at_accept']=sources[0] if len(sources)==1 else None
    if r['skips']:r['errors'].append('SOURCE_MODE_SKIPS_OBSERVED')
    if len(sources)!=1:r['errors'].append('SOURCE_SNAPSHOT_INCOMPLETE')
    elif r['create'] and r['accept']:
        s,c,a=sources[0],r['create'],r['accept']
        if s['source_ep']!=c['ep'] or s['expected_record']!=c['record'] or s['accept_ep']!=a['ep'] or s['accept_nbl']!=a['nbl']:r['errors'].append('SOURCE_JOIN_INVALID')
    r['status']='INCOMPLETE' if r['errors'] else 'SOURCE_ACCEPT_COLLECTED';return r
def evaluate(capture,console):
    from pb_kd_session import read,checked
    from pb_target_accept_report import evaluate as native
    capture,console=Path(capture),Path(console);p=read(capture/'runtime-plan.json');run=read(capture/'diagnostic-run.json');sha=hashlib.sha256((capture/'runtime-plan.json').read_bytes()).hexdigest();checked(p['debugger_profile'],PROFILE_SHA)
    if p['policy']!=policy() or run.get('flow_registration_acknowledged') is not True or run.get('debugger_observer') is not True or run.get('plan_sha256','').lower()!=sha:raise ValueError('SOURCE_ACCEPT_BINDING_INVALID')
    raw=console.read_bytes();r=correlate(raw.decode('utf-8-sig'));n=native(capture);controls=[m for m in n['matches'] if m['role']=='control'];r.update(native_status=n['status'],native_errors=n['errors'],plan_sha256=sha,console_sha256=hashlib.sha256(raw).hexdigest())
    if n['errors'] or len(controls)!=1:r['errors'].append('NATIVE_JOIN_INCOMPLETE')
    r['status']='INCOMPLETE'
    if not r['errors']:
        s,c,a=r['source_at_accept'],r['create'],r['accept']
        if s['record_now']==c['record'] and s['context']==c['context'] and s['size']==32 and s['flags30']&0x200000 and not a['key5'] and a['status']==0xc0000225 and controls[0]['original_api_failure'] and n['status']=='TARGET_FAILURE_REPRODUCED':r['status']='SOURCE_RECORD_REFERENCED_ACCEPT_CONTEXT_MISSING'
        else:r['status']='SOURCE_ACCEPT_INCONCLUSIVE'
    return r
