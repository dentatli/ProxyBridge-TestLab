"""Join two selected NBL snapshots with the original native query; no root-cause claim."""
import hashlib
from pathlib import Path
import re
from pb_endpoint_send_gate import correlate as send_correlate
from pb_target_retrieve_report import parse
from pb_selected_nbl_profile import policy,PROFILE_SHA


def correlate(text,read_limit=16):
    r=send_correlate(text,True)
    r.update(config=None,send_state=None,receive=None,receive_state=None,done=None,
        kernel_accept_status_observed=False,root_cause_proven=False)
    step=0
    for line in text.splitlines():
        try:
            if step and line.startswith('PBSD '):raise ValueError('NBL_SOURCE_EVENT_AFTER_SNAPSHOT')
            if re.search(r'(?i)(Error:|Exception thrown|JavaScript.*failed)',line):raise ValueError('NBL_DEBUGGER_ERROR')
            if line.startswith('PBN INCOMPLETE '):raise ValueError('NBL_CAPTURE_INCOMPLETE')
            if not line.startswith('PBN '):continue
            if line.startswith('PBN CONFIG '):
                if step or r['config']:raise ValueError('NBL_CONFIG_ORDER')
                r['config']=parse(line,'PBN CONFIG ','model get retrieve_return accept_return'.split())
                if r['config']['model']!=0 or not all(r['config'][k] for k in ('get','retrieve_return','accept_return')):raise ValueError('NBL_RUNTIME_CONFIG_INVALID')
            elif line.startswith('PBN STATE '):
                match=re.fullmatch(r'PBN STATE stage=(send|receive) (.*) key5=(present|absent) (.*)',line)
                if not match:raise ValueError('NBL_STATE_FORMAT')
                stage,head,state,tail=match.groups()
                if (stage=='send' and (step!=0 or not r['config'])) or (stage=='receive' and step!=2):raise ValueError('NBL_STATE_ORDER')
                v=parse(head+' '+tail,'','nbl info_raw info root value record_match nodes'.split());v['key5']=state
                if not r['sends'] or v['nbl']!=r['sends'][-1]['nbl'] or not 0<=v['nodes']<=8 or v['info']!=(v['info_raw']&~3):raise ValueError('NBL_STATE_IDENTITY')
                if state=='present':
                    if not v['info'] or not v['root'] or not v['nodes'] or v['record_match']!=int(v['value']==r['track']['record']):raise ValueError('NBL_PRESENT_INVALID')
                elif v['value'] or v['record_match']:raise ValueError('NBL_ABSENT_INVALID')
                r[stage+'_state']=v;step+=1
            elif line.startswith('PBN ARMED '):
                a=parse(line,'PBN ARMED ','nbl address limit'.split())
                if step!=1 or a['nbl']!=r['send_state']['nbl'] or a['address']!=a['nbl']+0xe0 or a['limit']!=read_limit:raise ValueError('NBL_ARM_INVALID')
                step=2
            elif line.startswith('PBN RECEIVE '):
                v=parse(line,'PBN RECEIVE ','nbl ep raw key consume'.split())
                if step!=2 or r['receive'] or v['nbl']!=r['send_state']['nbl'] or not v['ep'] or not 1<=v['raw']<=read_limit or (v['key'],v['consume'])!=(5,1):raise ValueError('NBL_RECEIVE_INVALID')
                r['receive']=v
            elif line.startswith('PBN DONE '):
                d=parse(line,'PBN DONE ',['nbl'])
                if step!=3 or not r['receive'] or d['nbl']!=r['receive']['nbl']:raise ValueError('NBL_DONE_INVALID')
                r['done']=d;step=4
            else:raise ValueError('NBL_UNKNOWN_EVENT')
        except (ValueError,OverflowError,KeyError,TypeError) as e:r['errors'].append(str(e))
    if step!=4 or not all(r[k] for k in ('config','send_state','receive','receive_state','done')):r['errors'].append('NBL_REQUIRED_OBSERVATION_MISSING')
    if not r['skip_observed'] or not r['repeated_syn_observed'] or (r['sends'] and r['sends'][0]['flags_reg']&0x200000):r['errors'].append('NBL_SKIP_SEQUENCE_INCOMPLETE')
    if not r['errors']:
        r['state_transition']=r['send_state']['key5']+'->'+r['receive_state']['key5']
        r['status']='SELECTED_NBL_CONTEXT_OBSERVATIONS_COLLECTED'
    else:r['status']='INCOMPLETE'
    return r


def evaluate(capture,console):
    from pb_kd_session import read,checked
    from pb_target_accept_report import evaluate as native_evaluate
    capture,console=Path(capture),Path(console)
    p=read(capture/'runtime-plan.json');run=read(capture/'diagnostic-run.json')
    nbl64=p['policy'].get('endpoint_nbl64_context') is True
    expected_sha=PROFILE_SHA;expected_policy=policy()
    if nbl64:
        from pb_selected_nbl64_profile import PROFILE_SHA as expected_sha,policy as policy64
        expected_policy=policy64()
    sha=hashlib.sha256((capture/'runtime-plan.json').read_bytes()).hexdigest()
    checked(p['debugger_profile'],expected_sha)
    if p['policy']!=expected_policy or run.get('debugger_observer') is not True or run.get('flow_registration_acknowledged') is not True or run.get('plan_sha256','').lower()!=sha:raise ValueError('NBL_CAPTURE_BINDING_INVALID')
    raw=console.read_bytes()
    if nbl64:
        from pb_selected_nbl64_report import correlate as correlate64
        r=correlate64(raw.decode('utf-8-sig'))
    else:r=correlate(raw.decode('utf-8-sig'))
    n=native_evaluate(capture)
    controls=[c for c in n['matches'] if c['role']=='control']
    r.update(plan_sha256=sha,console_sha256=hashlib.sha256(raw).hexdigest(),native_status=n['status'],native_errors=n['errors'],automatic_capture_scope_verified=False)
    if n['errors'] or len(controls)!=1 or controls[0]['peer']!='127.0.0.1:42201' or not controls[0]['original_api_failure']:r['errors'].append('NBL_NATIVE_FAILURE_JOIN_INCOMPLETE')
    if not r['errors']:r['status']='SELECTED_NBL_CONTEXT_AND_NATIVE_FAILURE_OBSERVED'
    else:r['status']='INCOMPLETE'
    return r
