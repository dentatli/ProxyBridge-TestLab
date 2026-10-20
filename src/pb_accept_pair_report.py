"""Exact pre/post accept snapshots, kept separate from root-cause attribution."""
import hashlib,re
from pathlib import Path
from pb_target_retrieve_report import parse,DEBUGGER_ERROR
from pb_accept_pair_profile import policy,PROFILE_SHA
def correlate(text):
 r=dict(status='INCOMPLETE',errors=[],config=None,pre=None,post=None,final=None,root_cause_proven=False,physical_packet_lifetime_verified=False,independent_socket_join_verified=False)
 for line in text.splitlines():
  try:
   if DEBUGGER_ERROR.search(line) or re.search(r'(?i)(Error:|Exception thrown)',line):raise ValueError('DEBUGGER_ERROR')
   if not line.startswith('PBA '):continue
   if line.startswith('PBA INCOMPLETE '):raise ValueError('CAPTURE_INCOMPLETE')
   if r['final']:raise ValueError('EVENT_AFTER_FINAL')
   if line.startswith('PBA CONFIG '):
    c=parse(line,'PBA CONFIG ','model pre post limit version'.split())
    if r['config'] or c['model']!=0 or c['version']!=1 or c['limit']!=256 or not c['pre'] or not c['post']:raise ValueError('CONFIG_INVALID')
    r['config']=c
   elif line.startswith('PBA PRE '):
    v=parse(line,'PBA PRE ','tid scope frame ep nbl info_raw info root key5 value nodes'.split())
    if not r['config'] or r['pre'] or not all(v[k] for k in ('tid','scope','frame','ep','nbl')) or v['info']!=(v['info_raw']&~3) or v['key5'] not in (0,1) or not 0<=v['nodes']<=8:raise ValueError('PRE_INVALID')
    if v['key5'] and (not all(v[k] for k in ('info','root','value','nodes'))):raise ValueError('PRE_PRESENT_INVALID')
    if not v['key5'] and v['value']:raise ValueError('PRE_ABSENT_INVALID')
    r['pre']=v
   elif line.startswith('PBA POST '):
    v=parse(line,'PBA POST ','tid scope frame ep nbl status record context size'.split())
    if not r['pre'] or r['post'] or any(v[k]!=r['pre'][k] for k in ('tid','scope','frame','ep','nbl')):raise ValueError('PAIR_IDENTITY_INVALID')
    v['status']&=0xffffffff;r['post']=v
   elif line.startswith('PBA FINAL '):
    f=parse(line,'PBA FINAL ','pre post error'.split())
    if not r['post'] or f!=dict(pre=1,post=1,error=0):raise ValueError('FINAL_INVALID')
    r['final']=f
   else:raise ValueError('UNKNOWN_EVENT')
  except (ValueError,TypeError,KeyError,OverflowError) as e:r['errors'].append(str(e))
 if not r['final']:r['errors'].append('PAIR_INCOMPLETE')
 if not r['errors']:r['status']='ACCEPT_PAIR_COLLECTED'
 return r
def evaluate(capture,console):
 from pb_kd_session import read,checked
 from pb_target_accept_report import evaluate as native
 capture,console=Path(capture),Path(console);p=read(capture/'runtime-plan.json');run=read(capture/'diagnostic-run.json')
 sha=hashlib.sha256((capture/'runtime-plan.json').read_bytes()).hexdigest()
 single=p['policy'].get('single_probe') is True
 checked(p['debugger_profile'],PROFILE_SHA)
 if p['policy']!=policy(not single) or run.get('flow_registration_acknowledged') is not True or run.get('debugger_observer') is not True or run.get('plan_sha256','').lower()!=sha:raise ValueError('PAIR_BINDING_INVALID')
 raw=console.read_bytes();r=correlate(raw.decode('utf-8-sig'));n=native(capture);controls=[m for m in n['matches'] if m['role']=='control']
 r.update(native_status=n['status'],native_errors=n['errors'],plan_sha256=sha,console_sha256=hashlib.sha256(raw).hexdigest())
 if n['errors'] or len(controls)!=1:r['errors'].append('NATIVE_JOIN_INCOMPLETE')
 r['status']='INCOMPLETE'
 if not r['errors']:
  pre,post=r['pre'],r['post'];q=controls[0]['query']
  if single:
   if post['status'] or not pre['key5'] or post['record']!=pre['value'] or not post['context'] or post['size']!=32 or q['api_return']!=0 or q['bytes']!=32:r['errors'].append('HEALTHY_CONTROL_DIFFERS')
   else:r['status']='ACCEPT_PAIR_HEALTHY_OBSERVED'
  elif pre['key5']==0 and post['status']==0xc0000225 and controls[0]['original_api_failure'] and n['status']=='TARGET_FAILURE_REPRODUCED':r['status']='ACCEPT_PAIR_CONTEXT_MISSING_OBSERVED'
  else:r['status']='ACCEPT_PAIR_INCONCLUSIVE'
 return r
