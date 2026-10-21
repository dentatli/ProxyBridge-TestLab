"""Correlate bounded observations, keeping packet-lifetime claims explicitly false."""
import hashlib
from pathlib import Path
from pb_target_retrieve_report import parse,DEBUGGER_ERROR
from pb_retry_history_profile import policy,PROFILE_SHA
def correlate(text):
    r=dict(status='INCOMPLETE',errors=[],config=None,create=None,skips=[],accept=None,final=None,root_cause_proven=False,physical_packet_lifetime_verified=False,independent_socket_join_verified=False)
    for line in text.splitlines():
        try:
            if DEBUGGER_ERROR.search(line):raise ValueError('DEBUGGER_ERROR')
            if not line.startswith('PBC '):continue
            if line.startswith('PBC INCOMPLETE '):raise ValueError('CAPTURE_INCOMPLETE')
            if r['final']:raise ValueError('EVENT_AFTER_FINAL')
            kind=line.split()[1]
            if kind=='CONFIG':
                c=parse(line,'PBC CONFIG ','model create skip accept create_limit skip_limit accept_limit skip_snapshots version'.split())
                if r['config'] or c['model']!=0 or c['version']!=2 or (c['create_limit'],c['skip_limit'],c['accept_limit'],c['skip_snapshots'])!=(32,512,512,8) or not all(c[k] for k in ('create','skip','accept')):raise ValueError('CONFIG_INVALID')
                r['config']=c
            elif kind=='CREATE':
                c=parse(line,'PBC CREATE ','ep record context size refs'.split())
                if not r['config'] or r['create'] or not all(c[k] for k in ('ep','record','context','refs')) or c['size']!=32:raise ValueError('CREATE_INVALID')
                r['create']=c
            elif kind in ('SKIP','ACCEPT'):
                fields='hit ep record context size flags30 nbl header seq_raw tcp_flags' if kind=='SKIP' else 'ep nbl status output_raw skip_count match_hit match_count'
                c=parse(line,'PBC '+kind+' ',(fields+' info_raw info root key5 value nodes').split())
                if not r['create'] or r['accept'] or not c['ep'] or not c['nbl'] or c['info']!=(c['info_raw']&~3) or c['key5'] not in (0,1) or not 0<=c['nodes']<=8:raise ValueError('SNAPSHOT_INVALID')
                if c['key5'] and not all(c[k] for k in ('info','root','value','nodes')):raise ValueError('PRESENT_INVALID')
                if not c['key5'] and c['value']:raise ValueError('ABSENT_INVALID')
                if kind=='SKIP':
                    if len(r['skips'])>=8 or c['hit']!=len(r['skips'])+1 or any(c[k]!=r['create'][k] for k in ('ep','record','context','size')) or not c['flags30']&0x200000 or not c['header'] or c['tcp_flags']&0x17!=2:raise ValueError('SKIP_INVALID')
                    if r['skips'] and c['seq_raw']!=r['skips'][0]['seq_raw']:raise ValueError('SYN_SEQUENCE_CHANGED')
                    r['skips'].append(c)
                else:
                    matches=[s['hit'] for s in r['skips'] if s['nbl']==c['nbl']]
                    if c['skip_count']!=len(r['skips']) or c['match_count']!=len(matches) or c['match_hit']!=(matches[-1] if matches else 0):raise ValueError('HISTORY_JOIN_INVALID')
                    c['status']&=0xffffffff;r['accept']=c
            elif kind=='FINAL':
                c=parse(line,'PBC FINAL ','create skip skip_limit_reached accept error'.split())
                if not r['accept'] or c!=dict(create=1,skip=len(r['skips']),skip_limit_reached=int(len(r['skips'])==8),accept=1,error=0):raise ValueError('FINAL_INVALID')
                r['final']=c
            else:raise ValueError('UNKNOWN_EVENT')
        except (ValueError,TypeError,KeyError,OverflowError) as e:r['errors'].append(str(e))
    if not r['final']:r['errors'].append('HISTORY_INCOMPLETE')
    if not r['errors']:r['status']='RETRY_HISTORY_COLLECTED'
    return r
def evaluate(capture,console):
    from pb_kd_session import read,checked
    from pb_target_accept_report import evaluate as native
    capture,console=Path(capture),Path(console);p=read(capture/'runtime-plan.json');run=read(capture/'diagnostic-run.json')
    sha=hashlib.sha256((capture/'runtime-plan.json').read_bytes()).hexdigest();checked(p['debugger_profile'],PROFILE_SHA)
    if p['policy']!=policy() or run.get('flow_registration_acknowledged') is not True or run.get('debugger_observer') is not True or run.get('plan_sha256','').lower()!=sha:raise ValueError('HISTORY_BINDING_INVALID')
    raw=console.read_bytes();r=correlate(raw.decode('utf-8-sig'));n=native(capture);controls=[m for m in n['matches'] if m['role']=='control']
    r.update(native_status=n['status'],native_errors=n['errors'],plan_sha256=sha,console_sha256=hashlib.sha256(raw).hexdigest())
    if n['errors'] or len(controls)!=1:r['errors'].append('NATIVE_JOIN_INCOMPLETE')
    r['status']='INCOMPLETE'
    if not r['errors']:
        a=r['accept'];matches=[s for s in r['skips'] if s['nbl']==a['nbl']]
        if matches and all(s['key5']==0 for s in matches) and a['key5']==0 and a['status']==0xc0000225 and controls[0]['original_api_failure'] and n['status']=='TARGET_FAILURE_REPRODUCED':r['status']='RETRY_HISTORY_NBL_MATCH_AND_ACCEPT_MISS_OBSERVED'
        else:r['status']='RETRY_HISTORY_INCONCLUSIVE'
    return r
