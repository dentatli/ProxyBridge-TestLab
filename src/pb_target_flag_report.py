"""Read capped flag snapshots; never infer a write or complete lifetime from a pre-write trap."""
import argparse
import hashlib
import json
from pathlib import Path
import re
from pb_target_retrieve_report import parse, DEBUGGER_ERROR
from pb_target_flag_binding import policy

FIELDS=dict(TRACK='ep record context size refs',SET_PRE='thread ep flags30 flags34 record classify_raw arg12_raw arg13_raw arg15_raw',RETRIEVE='ep nbl status output_raw')


def correlate(text):
    r=dict(status='INCOMPLETE',errors=[],events=[],stack_lines=[],frames=[],
        trap_coverage_verified=False,root_cause_proven=False,post_write_observed=False)
    track=None;stack=False;stack_done=False
    for line in text.splitlines():
        if DEBUGGER_ERROR.search(line):r['errors'].append('DEBUGGER_ERROR')
        if line.startswith(('PBFG_LIMIT','PBFG_UNREADABLE')):r['errors'].append('BOUNDED_CAPTURE_INCOMPLETE')
        try:
            if line=='PBFG STACK_BEGIN':
                if stack or stack_done or not any(e['kind']=='SET_PRE' for e in r['events']):raise ValueError('STACK_BEGIN_INVALID')
                stack=True
            elif line=='PBFG STACK_END':
                if not stack or not r['frames']:raise ValueError('STACK_END_INVALID')
                stack=False;stack_done=True
            elif stack:
                if len(r['stack_lines'])>=32:raise ValueError('STACK_OUTPUT_UNBOUNDED')
                r['stack_lines'].append(line)
                if re.match(r'^\s*[0-9a-fA-F]{2}\s+[0-9a-fA-F`]{8,17}\s+',line):
                    r['frames'].append(line)
                    if len(r['frames'])>8:raise ValueError('STACK_FRAME_LIMIT_EXCEEDED')
            else:
                for kind,fields in FIELDS.items():
                    if not line.startswith('PBFG '+kind+' '):continue
                    event=parse(line,'PBFG '+kind+' ',fields.split())
                    if any(e['kind']==kind for e in r['events']):raise ValueError('REPEATED_ONE_SHOT_EVENT')
                    if kind=='TRACK':
                        if not all(event.values()) or event['size']!=32:raise ValueError('TRACK_INVALID')
                        track=event
                    elif track is None:raise ValueError('TRACK_MISSING')
                    elif kind=='SET_PRE':
                        if event['ep']!=track['ep'] or event['record']!=track['record']:raise ValueError('SETTER_IDENTITY_DIFFERS')
                        event['bit20_before']=bool(event['flags30']&(1<<20))
                        event['bit21_before']=bool(event['flags30']&(1<<21))
                    r['events'].append(dict(kind=kind,**event))
        except ValueError as exc:r['errors'].append(str(exc))
    if stack:r['errors'].append('STACK_END_MISSING')
    r['counts']={k:sum(e['kind']==k for e in r['events']) for k in FIELDS}
    if not r['errors']:r['status']='BOUNDED_FLAG_SNAPSHOTS_OBSERVED' if all(r['counts'].values()) and stack_done else 'BOUNDED_FLAG_COVERAGE_UNPROVEN'
    return r


def evaluate(capture,console):
    from pb_target_accept_report import evaluate as native_evaluate
    read=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
    p,run=read(capture/'runtime-plan.json'),read(capture/'diagnostic-run.json')
    if p['policy'].get('endpoint_data_watch') is True:
        from pb_endpoint_watch_report import evaluate as watch_evaluate
        return watch_evaluate(capture,console)
    probe=p['policy'].get('workload')=='flag-four-probe'
    armed=p['policy'].get('automatic_debugger_enable_after_create')==[3]
    accept64=p['policy'].get('raw_hit_limits_per_point')=={'2':16,'3':16,'4':64}
    healthy=p['policy'].get('healthy_setter_probe') is True
    sha=hashlib.sha256((capture/'runtime-plan.json').read_bytes()).hexdigest()
    if (p['policy']!=policy(not probe,armed,accept64,healthy) or run.get('debugger_observer') is not True or
        run.get('flow_registration_acknowledged') is not True or sha!=run['plan_sha256'].lower()):raise ValueError('FLAG_CAPTURE_BINDING_INVALID')
    raw=console.read_bytes();r=correlate(raw.decode('utf-8-sig'));native=native_evaluate(capture)
    r.update(plan_sha256=sha,console_sha256=hashlib.sha256(raw).hexdigest(),native_status=native['status'],
        native_errors=native['errors'],automatic_capture_scope_verified=False,
        correlation_source='user-associated-latest-run-and-control-port-selector')
    controls=[m for m in native['matches'] if m['role']=='control']
    if native['errors'] or len(controls)!=1 or controls[0]['peer']!='127.0.0.1:42201':r['errors'].append('NATIVE_CONTROL_INCOMPLETE')
    if probe:
        track=next((e for e in r['events'] if e['kind']=='TRACK'),{})
        accept=next((e for e in r['events'] if e['kind']=='RETRIEVE'),{})
        expected_counts={'TRACK':1,'SET_PRE':r['counts']['SET_PRE'] if healthy else 0,'RETRIEVE':1}
        if (r['counts']!=expected_counts or (healthy and r['counts']['SET_PRE']>1) or not accept or
            accept['status']!=0 or accept['output_raw']!=track.get('record') or
            len(controls)!=1 or controls[0]['original_api_failure']):r['errors'].append('FLAG_POSITIVE_PROBE_INCOMPLETE')
        if not r['errors']:r['status']='FLAG_PROBE_SUCCESS_OBSERVED'
        if healthy:
            r['setter_pre_observed']=r['counts']['SET_PRE']==1
            r['setter_absence_proven']=False
            if r['setter_pre_observed'] and not r['frames']:r['errors'].append('FLAG_HEALTHY_SETTER_STACK_MISSING')
            if not r['errors']:r['status']='FLAG_HEALTHY_PROBE_NATIVE_SUCCESS_OBSERVED'
    if r['errors']:r['status']='INCOMPLETE'
    return r


if __name__=='__main__':
    a=argparse.ArgumentParser(description=__doc__);a.add_argument('--capture-directory',type=Path,required=True)
    a.add_argument('--console',type=Path,required=True);a.add_argument('--output-directory',type=Path,required=True)
    opt=a.parse_args();r=evaluate(opt.capture_directory,opt.console);opt.output_directory.mkdir(parents=True,exist_ok=True)
    with (opt.output_directory/'flag-report.json').open('x',encoding='utf-8') as f:json.dump(r,f,indent=2)
    print(json.dumps({k:r[k] for k in ('status','errors','native_status')}));raise SystemExit(bool(r['errors']))
