"""Per-SEND observations; never promote a stale NBL address or claim root cause."""
import hashlib
from pathlib import Path
import re
from pb_target_retrieve_report import parse,DEBUGGER_ERROR
from pb_retry_epochs_profile import policy,PROFILE_SHA


def correlate(text):
    r=dict(status='INCOMPLETE',errors=[],config=None,policy=None,track=None,epochs=[],final=None,
        root_cause_proven=False,accepted_endpoint_socket_join_verified=False,trap_coverage_verified=False)
    samples=0
    skips=0
    for line in text.splitlines():
        try:
            if DEBUGGER_ERROR.search(line) or re.search(r'(?i)(Error:|Exception thrown)',line):raise ValueError('DEBUGGER_ERROR')
            if not line.startswith('PBR '):continue
            if line.startswith('PBR INCOMPLETE '):raise ValueError('PER_SEND_CAPTURE_INCOMPLETE')
            if r['final']:raise ValueError('EVENT_AFTER_FINAL')
            e=r['epochs'][-1] if r['epochs'] else None
            if line.startswith('PBR CONFIG '):
                c=parse(line,'PBR CONFIG ','model get retrieve_return accept_return'.split())
                if r['config'] or r['track'] or c['model']!=0 or not all(c[k] for k in ('get','retrieve_return','accept_return')):raise ValueError('CONFIG_INVALID')
                r['config']=c
            elif line.startswith('PBR POLICY '):
                p=parse(line,'PBR POLICY ','source_limit packet_limit total_limit send_limit version'.split())
                if not r['config'] or r['policy'] or p!=dict(source_limit=128,packet_limit=64,total_limit=512,send_limit=8,version=6):raise ValueError('POLICY_INVALID')
                r['policy']=p
            elif line.startswith('PBR TRACK '):
                t=parse(line,'PBR TRACK ','ep record context size'.split())
                if not r['policy'] or r['track'] or not all(t[k] for k in ('ep','record','context')) or t['size']!=32:raise ValueError('TRACK_INVALID')
                r['track']=t
            elif line.startswith('PBR SEND '):
                s=parse(line,'PBR SEND ','epoch nbl flags nb mdl header seq_raw'.split())
                if not r['track'] or (e and not e['end']) or s['epoch']!=len(r['epochs'])+1 or s['epoch']>8 or not all(s[k] for k in ('nbl','nb','mdl','header')):raise ValueError('SEND_ORDER_INVALID')
                if e and s['seq_raw']!=e['send']['seq_raw']:raise ValueError('SEQUENCE_CHANGED')
                r['epochs'].append(dict(send=s,send_state=None,send_buffer=None,selector=None,selected=None,selected_state=None,selected_buffer=None,receive=None,receive_state=None,end=None))
            elif line.startswith('PBR STATE '):
                m=re.fullmatch(r'PBR STATE stage=(send|selected|receive) (.*) key5=(present|absent) (.*)',line)
                if not m or not e or e['end']:raise ValueError('STATE_ORDER_INVALID')
                stage,head,state,tail=m.groups();v=parse(head+' '+tail,'','epoch nbl info_raw info root value record_match nodes'.split());v['key5']=state
                if e[stage+'_state'] or v['epoch']!=e['send']['epoch'] or v['nbl']!=e['send']['nbl'] or not 0<=v['nodes']<=8 or v['info']!=(v['info_raw']&~3):raise ValueError('STATE_IDENTITY_INVALID')
                if stage=='receive' and not e['receive']:raise ValueError('RECEIVE_STATE_ORDER')
                if stage=='selected' and not e['selected']:raise ValueError('SELECTED_STATE_ORDER')
                if state=='present' and (not v['info'] or not v['root'] or not v['nodes'] or v['record_match']!=int(v['value']==r['track']['record'])):raise ValueError('PRESENT_STATE_INVALID')
                if state=='absent' and (v['value'] or v['record_match']):raise ValueError('ABSENT_STATE_INVALID')
                e[stage+'_state']=v
            elif line.startswith('PBR SELECTED '):
                v=parse(line,'PBR SELECTED ','epoch ep nbl raw'.split())
                if not e or e['end'] or e['selected'] or not e['send_buffer'] or not e['selector'] or v['epoch']!=e['send']['epoch'] or v['nbl']!=e['send']['nbl'] or not 1<=v['raw']<=64 or not v['ep'] or e['selector']['ep']!=v['ep'] or (e['selector']['local_raw'],e['selector']['peer_raw'])!=(0xda84,0xd9a4):raise ValueError('SELECTED_FLOW_INVALID')
                e['selected']=v
            elif line.startswith('PBR BUFFER '):
                m=re.fullmatch(r'PBR BUFFER stage=(send|selected) (.*)',line)
                if not m or not e or e['end']:raise ValueError('BUFFER_ORDER_INVALID')
                stage,tail=m.groups();v=parse(tail,'','epoch nb current_mdl current_offset length nb20_raw nb28_raw saved_header header_readable header_match'.split())
                if e[stage+'_buffer'] or not e[stage+'_state'] or v['epoch']!=e['send']['epoch'] or not v['nb'] or v['saved_header']!=e['send']['header'] or any(not 0<=v[k]<=0xffffffff for k in ('current_offset','length','nb28_raw')) or v['header_readable'] not in (0,1) or v['header_match'] not in (0,1) or v['header_match']>v['header_readable']:raise ValueError('BUFFER_INVALID')
                if stage=='send' and ((v['nb'],v['current_mdl'])!=(e['send']['nb'],e['send']['mdl']) or not v['header_match']):raise ValueError('SEND_BUFFER_INVALID')
                e[stage+'_buffer']=v
            elif line.startswith('PBR RECEIVE '):
                v=parse(line,'PBR RECEIVE ','epoch ep nbl raw'.split())
                if not e or not e['send_state'] or e['receive'] or e['end'] or v['epoch']!=e['send']['epoch'] or v['nbl']!=e['send']['nbl'] or not v['ep'] or not 1<=v['raw']<=64:raise ValueError('RECEIVE_INVALID')
                if not e['selector'] or e['selector']['ep']!=v['ep'] or e['selector']['local_raw']!=0xda84 or e['selector']['peer_raw']!=0xd9a4:raise ValueError('RECEIVE_SELECTOR_INVALID')
                if not e['selected_buffer'] or e['selected']!=v:raise ValueError('RECEIVE_WITHOUT_SELECTED_SNAPSHOT')
                e['receive']=v
            elif line.startswith('PBR SELECTOR '):
                v=parse(line,'PBR SELECTOR ','epoch frame ep local_raw peer_raw'.split())
                if not e or e['end'] or e['selector'] or v['epoch']!=e['send']['epoch'] or not v['frame'] or not 0<=v['local_raw']<=65535 or not 0<=v['peer_raw']<=65535:raise ValueError('SELECTOR_INVALID')
                e['selector']=v
            elif line.startswith('PBR SKIP '):
                v=parse(line,'PBR SKIP reason=NON_SYN ','nbl flags'.split());skips+=1
                if not r['track'] or skips>4 or not v['nbl'] or not 0<=v['flags']<=255 or v['flags']&0x17==2:raise ValueError('NON_SYN_SKIP_INVALID')
            elif line.startswith('PBR END '):
                m=re.fullmatch(r'PBR END epoch=(\S+) reason=([A-Z_]+) reads=(\S+)',line)
                if not m or not e or e['end'] or int(m[1],16)!=e['send']['epoch'] or not e['send_state'] or not 0<=int(m[3],16)<=64:raise ValueError('END_INVALID')
                end=dict(reason=m[2],reads=int(m[3],16))
                if end['reason']=='MATCH' and (not e['receive_state'] or end['reads']!=e['receive']['raw']):raise ValueError('MATCH_INCOMPLETE')
                if end['reason']=='OTHER_TUPLE' and (not e['selector'] or (e['selector']['local_raw']==0xda84 and e['selector']['peer_raw']==0xd9a4 and e['selector']['ep'])):raise ValueError('OTHER_TUPLE_UNEXPLAINED')
                e['end']=end
            elif line.startswith('PBR REJECT '):
                m=re.fullmatch(r'PBR REJECT epoch=(\S+) reason=([A-Z_]+) ip=(\S+)',line);samples+=1
                if not m or not e or e['end'] or samples>4 or int(m[1],16)!=e['send']['epoch']:raise ValueError('REJECT_INVALID')
            elif line.startswith('PBR STORAGE '):
                v=parse(line,'PBR STORAGE ','epoch old_nb nb old_mdl mdl'.split())
                if not e or v['epoch']!=e['send']['epoch'] or (v['old_nb'],v['old_mdl'])!=(e['send']['nb'],e['send']['mdl']) or (v['nb'],v['mdl'])==(v['old_nb'],v['old_mdl']):raise ValueError('STORAGE_DIAGNOSTIC_INVALID')
            elif line.startswith('PBR FINAL '):
                f=parse(line,'PBR FINAL ','creates source_reads sends reads pairs error'.split())
                if not e or not e['end'] or not 1<=f['creates']<16 or not 1<=f['source_reads']<128 or f['sends']!=len(r['epochs']) or f['reads']!=sum(x['end']['reads'] for x in r['epochs']) or f['reads']>512 or f['pairs']!=sum(x['end']['reason']=='MATCH' for x in r['epochs']) or f['error']:raise ValueError('FINAL_COUNTS_INVALID')
                r['final']=f
            else:raise ValueError('UNKNOWN_PER_SEND_EVENT')
        except (ValueError,TypeError,KeyError,OverflowError) as ex:r['errors'].append(str(ex))
    if not r['final'] or not r['epochs'] or r['epochs'][-1]['end'] is None or r['epochs'][-1]['end']['reason']!='MATCH':r['errors'].append('LAST_SEND_RECEIVE_PAIR_MISSING')
    if r['epochs'] and not r['epochs'][-1]['send']['flags']&0x200000:r['errors'].append('LAST_SEND_SKIP_NOT_OBSERVED')
    r['earlier_gaps']=[x['send']['epoch'] for x in r['epochs'] if x['end'] and x['end']['reason']!='MATCH']
    r['selected_flow_snapshot_count']=sum(x['selected_state'] is not None for x in r['epochs'])
    if not r['errors']:r['status']='PER_SEND_OBSERVATIONS_COLLECTED'
    return r


def evaluate(capture,console):
    from pb_kd_session import read,checked
    from pb_target_accept_report import evaluate as native
    capture,console=Path(capture),Path(console);plan=capture/'runtime-plan.json'
    p=read(plan);run=read(capture/'diagnostic-run.json');sha=hashlib.sha256(plan.read_bytes()).hexdigest()
    checked(p['debugger_profile'],PROFILE_SHA)
    if p['policy']!=policy() or run.get('debugger_observer') is not True or run.get('flow_registration_acknowledged') is not True or run.get('plan_sha256','').lower()!=sha:raise ValueError('PER_SEND_BINDING_INVALID')
    raw=console.read_bytes();r=correlate(raw.decode('utf-8-sig'));n=native(capture);c=[x for x in n['matches'] if x['role']=='control']
    r.update(native_status=n['status'],native_errors=n['errors'],plan_sha256=sha,console_sha256=hashlib.sha256(raw).hexdigest())
    if n['errors'] or len(c)!=1 or c[0]['peer']!='127.0.0.1:42201' or not c[0]['original_api_failure']:r['errors'].append('NATIVE_CONTROL_JOIN_INCOMPLETE')
    r['status']='INCOMPLETE' if r['errors'] else 'PER_SEND_OBSERVATIONS_AND_NATIVE_FAILURE_OBSERVED'
    return r
