"""Same-source receive transition and ACCEPT, without claiming one physical packet."""
import hashlib
from pathlib import Path
from pb_source_accept_report import correlate as source_correlate
from pb_target_retrieve_report import parse
from pb_receive_accept_profile import PROFILE_SHA,policy
def correlate(text):
    lines=[];config=None;receive=None;errors=[];create_seen=False;accept_seen=False;source_seen=False
    for line in text.splitlines():
        if line.startswith('PBC CREATE '):create_seen=True
        if line.startswith('PBC ACCEPT '):accept_seen=True
        if line.startswith('PBC SOURCE '):source_seen=True
        if not line.startswith('PBT '):lines.append(line);continue
        try:
            if line.startswith('PBT CONFIG '):
                c=parse(line,'PBT CONFIG ','writer watch_limit version'.split())
                if config or create_seen or not c['writer'] or c['watch_limit']!=16 or c['version']!=1:raise ValueError('RECEIVE_CONFIG_INVALID')
                config=c
            elif line.startswith('PBT RECEIVE '):
                c=parse(line,'PBT RECEIVE ','ep record context size old new ip nbl header src_raw dst_raw tcp_flags seq_raw ack_raw writes'.split())
                if not config or not create_seen or source_seen or accept_seen or receive or c['ip']!=config['writer'] or c['old']&0x200000 or not c['new']&0x200000 or c['src_raw']!=0xda84 or c['dst_raw']!=0xd9a4 or not 1<=c['writes']<=16 or not c['nbl'] or not c['header']:raise ValueError('RECEIVE_TRANSITION_INVALID')
                receive=c
            else:raise ValueError('RECEIVE_CAPTURE_INCOMPLETE')
        except (ValueError,KeyError,TypeError) as e:errors.append(str(e))
    r=source_correlate('\n'.join(lines));r['errors']+=errors;r.update(receive_config=config,receive_transition=receive)
    if not config:r['errors'].append('RECEIVE_CONFIG_MISSING')
    if receive and r['create'] and any(receive[k]!=r['create'][k] for k in ('ep','record','context','size')):r['errors'].append('RECEIVE_SOURCE_JOIN_INVALID')
    r['status']='INCOMPLETE' if r['errors'] else 'RECEIVE_ACCEPT_COLLECTED';return r
def evaluate(capture,console):
    from pb_kd_session import read,checked
    from pb_target_accept_report import evaluate as native
    capture,console=Path(capture),Path(console);p=read(capture/'runtime-plan.json');run=read(capture/'diagnostic-run.json');sha=hashlib.sha256((capture/'runtime-plan.json').read_bytes()).hexdigest();checked(p['debugger_profile'],PROFILE_SHA)
    if p['policy']!=policy() or run.get('flow_registration_acknowledged') is not True or run.get('debugger_observer') is not True or run.get('plan_sha256','').lower()!=sha:raise ValueError('RECEIVE_ACCEPT_BINDING_INVALID')
    raw=console.read_bytes();r=correlate(raw.decode('utf-8-sig'));n=native(capture);controls=[m for m in n['matches'] if m['role']=='control'];r.update(native_status=n['status'],native_errors=n['errors'],plan_sha256=sha,console_sha256=hashlib.sha256(raw).hexdigest(),send_skip_observed_in_this_run=False)
    if n['errors'] or len(controls)!=1:r['errors'].append('NATIVE_JOIN_INCOMPLETE')
    r['status']='INCOMPLETE'
    if not r['errors']:
        v,s,c,a=r['receive_transition'],r['source_at_accept'],r['create'],r['accept']
        if v and v['tcp_flags']&0x17==0x14 and s['record_now']==c['record'] and s['context']==c['context'] and s['size']==32 and s['flags30']&0x200000 and not a['key5'] and a['status']==0xc0000225 and controls[0]['original_api_failure'] and n['status']=='TARGET_FAILURE_REPRODUCED':r['status']='RST_RECEIVE_TRANSITION_AND_ACCEPT_CONTEXT_MISS_OBSERVED'
        else:r['status']='RECEIVE_ACCEPT_INCONCLUSIVE'
    return r
