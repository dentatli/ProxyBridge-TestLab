"""Same-source receive transition and query NULL branch, with a native PID/TID join."""
import hashlib
from pathlib import Path
from pb_target_retrieve_report import parse, DEBUGGER_ERROR
from pb_receive_query_profile import PROFILE_SHA, policy


def correlate(text):
    r=dict(status='INCOMPLETE',errors=[],config=None,receive_config=None,query_config=None,
           create=None,receive_transition=None,query_null=None,final=None,
           root_cause_proven=False,physical_packet_identity_proven=False,
           independent_socket_lifetime_proven=False,accepted_nbl_observed=False,
           query_return_ntstatus_observed=False,
           correlation_source='user-associated-console-with-native-pid-tid-join')
    specs={
        'PBC CONFIG ':('config','model create skip accept create_limit skip_limit accept_limit skip_snapshots version'),
        'PBT CONFIG ':('receive_config','writer watch_limit version'),
        'PBQ CONFIG ':('query_config','query_null query_limit version'),
        'PBC CREATE ':('create','ep record context size refs'),
        'PBT RECEIVE ':('receive_transition','ep record context size old new ip nbl header src_raw dst_raw tcp_flags seq_raw ack_raw writes'),
        'PBQ NULL ':('query_null','ep record_reg ioctl pid tid source_ep source_record context size flags30'),
        'PBC FINAL ':('final','create skip skip_limit_reached accept error')}
    for line in text.splitlines():
        if DEBUGGER_ERROR.search(line):r['errors'].append('DEBUGGER_ERROR')
        if not line.startswith(('PBC ','PBT ','PBQ ')):continue
        try:
            prefix=next((p for p in specs if line.startswith(p)),None)
            if prefix is None:raise ValueError('CAPTURE_INCOMPLETE_OR_UNEXPECTED_EVENT')
            key,fields=specs[prefix];v=parse(line,prefix,fields.split())
            if r[key] is not None:raise ValueError('DUPLICATE_'+key.upper())
            if r['final']:raise ValueError('EVENT_AFTER_FINAL')
            if key.endswith('config'):
                if r['create']:raise ValueError('CONFIG_AFTER_CREATE')
                if key=='config' and (v['model']!=0 or v['version']!=2 or not all(v[k] for k in ('create','skip','accept')) or [v[k] for k in ('create_limit','skip_limit','accept_limit','skip_snapshots')]!=[32,512,512,8]):raise ValueError('HELPER_CONFIG_INVALID')
                if key=='receive_config' and (not v['writer'] or v['watch_limit']!=16 or v['version']!=1):raise ValueError('RECEIVE_CONFIG_INVALID')
                if key=='query_config' and (not v['query_null'] or v['query_limit']!=16 or v['version']!=1):raise ValueError('QUERY_CONFIG_INVALID')
            elif key=='create':
                if not all(r[k] for k in ('config','receive_config','query_config')) or not all(v[k] for k in ('ep','record','context','refs')) or v['size']!=32:raise ValueError('CREATE_INVALID')
            elif key=='receive_transition':
                c=r['create'];cfg=r['receive_config']
                if not c or r['query_null'] or any(v[k]!=c[k] for k in ('ep','record','context','size')) or v['ip']!=cfg['writer'] or v['old']&0x200000 or not v['new']&0x200000 or v['src_raw']!=0xda84 or v['dst_raw']!=0xd9a4 or not 1<=v['writes']<=16 or not v['nbl'] or not v['header']:raise ValueError('RECEIVE_JOIN_INVALID')
            elif key=='query_null':
                c=r['create']
                if not c or v['record_reg'] or v['ioctl']!=0x980000dd or not all(v[k] for k in ('ep','pid','tid')) or v['source_ep']!=c['ep'] or v['source_record']!=c['record'] or v['context']!=c['context'] or v['size']!=c['size']:raise ValueError('QUERY_SOURCE_JOIN_INVALID')
            elif key=='final':
                if not r['create'] or v!=dict(create=1,skip=0,skip_limit_reached=0,accept=0,error=0):raise ValueError('FINAL_INVALID')
            r[key]=v
        except (ValueError,KeyError,TypeError) as e:r['errors'].append(str(e))
    if not all(r[k] for k in ('config','receive_config','query_config','create','final')):r['errors'].append('CAPTURE_REQUIRED_EVENTS_MISSING')
    r['status']='INCOMPLETE' if r['errors'] else 'RECEIVE_QUERY_COLLECTED'
    return r


def join_native(r,n):
    controls=[m for m in n['matches'] if m['role']=='control']
    r.update(native_status=n['status'],native_errors=n['errors'],native_pid_tid_joined=False)
    if n['errors'] or len(controls)!=1:r['errors'].append('NATIVE_JOIN_INCOMPLETE')
    q=r['query_null']
    if q and len(controls)==1:
        original=controls[0]['query']
        if q['pid']!=original['relay_pid'] or q['tid']!=original['thread']:r['errors'].append('NATIVE_QUERY_PID_TID_DIFFERS')
        else:r['native_pid_tid_joined']=True
    r['status']='INCOMPLETE'
    if not r['errors']:
        v=r['receive_transition']
        unique_failure=sum(bool(m['original_api_failure']) for m in n['matches'])==1
        if q and v and v['tcp_flags']&0x17==0x14 and q['flags30']&0x200000 and r['native_pid_tid_joined'] and unique_failure and controls[0]['original_api_failure'] and n['status']=='TARGET_FAILURE_REPRODUCED':r['status']='RST_TRANSITION_AND_SELECTED_QUERY_NULL_OBSERVED'
        else:r['status']='RECEIVE_QUERY_INCONCLUSIVE'
    return r


def evaluate(capture,console):
    from pb_kd_session import read,checked
    from pb_target_accept_report import evaluate as native
    capture,console=Path(capture),Path(console);p=read(capture/'runtime-plan.json');run=read(capture/'diagnostic-run.json');sha=hashlib.sha256((capture/'runtime-plan.json').read_bytes()).hexdigest()
    checked(p['debugger_profile'],PROFILE_SHA)
    if p['policy']!=policy() or run.get('flow_registration_acknowledged') is not True or run.get('debugger_observer') is not True or run.get('plan_sha256','').lower()!=sha:raise ValueError('RECEIVE_QUERY_BINDING_INVALID')
    raw=console.read_bytes();r=correlate(raw.decode('utf-8-sig'));r.update(plan_sha256=sha,console_sha256=hashlib.sha256(raw).hexdigest())
    return join_native(r,native(capture))
