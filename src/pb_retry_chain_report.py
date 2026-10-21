"""Bind the three selected observations; never equate address equality with lifetime."""
import hashlib
from pathlib import Path
from pb_target_retrieve_report import parse,DEBUGGER_ERROR
from pb_retry_chain_profile import policy,PROFILE_SHA
def correlate(text):
    r=dict(status='INCOMPLETE',errors=[],config=None,create=None,skip=None,accept=None,final=None,root_cause_proven=False,physical_packet_lifetime_verified=False,independent_socket_join_verified=False)
    for line in text.splitlines():
        try:
            if DEBUGGER_ERROR.search(line):raise ValueError('DEBUGGER_ERROR')
            if not line.startswith('PBC '):continue
            if line.startswith('PBC INCOMPLETE '):raise ValueError('CAPTURE_INCOMPLETE')
            if r['final']:raise ValueError('EVENT_AFTER_FINAL')
            kind=line.split()[1]
            if kind=='CONFIG':
                c=parse(line,'PBC CONFIG ','model create skip accept create_limit skip_limit accept_limit version'.split())
                if r['config'] or c['model']!=0 or c['version']!=1 or (c['create_limit'],c['skip_limit'],c['accept_limit'])!=(32,512,512) or not all(c[k] for k in ('create','skip','accept')):raise ValueError('CONFIG_INVALID')
                r['config']=c
            elif kind=='CREATE':
                c=parse(line,'PBC CREATE ','ep record context size refs'.split())
                if not r['config'] or r['create'] or not all(c[k] for k in ('ep','record','context','refs')) or c['size']!=32:raise ValueError('CREATE_INVALID')
                r['create']=c
            elif kind in ('SKIP','ACCEPT'):
                fields='ep record context size flags30 nbl header seq_raw tcp_flags' if kind=='SKIP' else 'ep nbl status output_raw skip_seen skip_nbl_match'
                c=parse(line,'PBC '+kind+' ',(fields+' info_raw info root key5 value nodes').split())
                if not r['create'] or r[kind.lower()] or not c['ep'] or not c['nbl'] or c['info']!=(c['info_raw']&~3) or c['key5'] not in (0,1) or not 0<=c['nodes']<=8:raise ValueError('SNAPSHOT_INVALID')
                if c['key5'] and not all(c[k] for k in ('info','root','value','nodes')):raise ValueError('PRESENT_INVALID')
                if not c['key5'] and c['value']:raise ValueError('ABSENT_INVALID')
                if kind=='SKIP':
                    if r['accept'] or any(c[k]!=r['create'][k] for k in ('ep','record','context','size')) or not (c['flags30']&0x200000) or not c['header'] or c['tcp_flags']&0x17!=2:raise ValueError('SKIP_INVALID')
                else:
                    c['status']&=0xffffffff
                    if c['skip_seen']!=int(r['skip'] is not None) or c['skip_nbl_match']!=int(r['skip'] is not None and c['nbl']==r['skip']['nbl']):raise ValueError('SKIP_JOIN_INVALID')
                r[kind.lower()]=c
            elif kind=='FINAL':
                c=parse(line,'PBC FINAL ','create skip accept error'.split())
                if not r['accept'] or c!=dict(create=1,skip=int(r['skip'] is not None),accept=1,error=0):raise ValueError('FINAL_INVALID')
                r['final']=c
            else:raise ValueError('UNKNOWN_EVENT')
        except (ValueError,TypeError,KeyError,OverflowError) as e:r['errors'].append(str(e))
    if not r['final']:r['errors'].append('CHAIN_INCOMPLETE')
    if not r['errors']:r['status']='RETRY_CHAIN_COLLECTED'
    return r
def evaluate(capture,console):
    from pb_kd_session import read,checked
    from pb_target_accept_report import evaluate as native
    capture,console=Path(capture),Path(console);p=read(capture/'runtime-plan.json');run=read(capture/'diagnostic-run.json')
    if p['policy'].get('retry_chain_create_armed') is True:
        from pb_retry_chain_armed_profile import policy as expected_policy,PROFILE_SHA as expected_sha
    else:expected_policy,expected_sha=policy,PROFILE_SHA
    sha=hashlib.sha256((capture/'runtime-plan.json').read_bytes()).hexdigest();checked(p['debugger_profile'],expected_sha)
    if p['policy']!=expected_policy() or run.get('flow_registration_acknowledged') is not True or run.get('debugger_observer') is not True or run.get('plan_sha256','').lower()!=sha:raise ValueError('CHAIN_BINDING_INVALID')
    raw=console.read_bytes();r=correlate(raw.decode('utf-8-sig'));n=native(capture);controls=[m for m in n['matches'] if m['role']=='control']
    r.update(native_status=n['status'],native_errors=n['errors'],plan_sha256=sha,console_sha256=hashlib.sha256(raw).hexdigest())
    if n['errors'] or len(controls)!=1:r['errors'].append('NATIVE_JOIN_INCOMPLETE')
    r['status']='INCOMPLETE'
    if not r['errors']:
        s,a=r['skip'],r['accept']
        if s and not s['key5'] and a['skip_nbl_match'] and not a['key5'] and a['status']==0xc0000225 and controls[0]['original_api_failure'] and n['status']=='TARGET_FAILURE_REPRODUCED':r['status']='RETRY_SKIP_GATE_AND_ACCEPT_MISS_OBSERVED'
        else:r['status']='RETRY_CHAIN_INCONCLUSIVE'
    return r
