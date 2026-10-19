"""Correlate selected send/inspect/association/retrieval snapshots, without coverage claims."""
import argparse
import hashlib
import json
from pathlib import Path
from pb_target_retrieve_report import parse, DEBUGGER_ERROR
from pb_target_accept_plan import flow_policy
from pb_target_accept_report import evaluate as native_evaluate

FIELDS = dict(TRACK='thread source_ep record context size refs',
    SEND='thread scope tcb nbl source_ep local_raw peer_raw',
    INSPECT='thread scope source_ep nbl family flags30 flags34 record',
    ASSOC_RETURN='thread scope source_ep nbl result_raw',
    RETRIEVE='thread scope ep nbl local_raw peer_raw status output_raw')


def correlate(text):
    result=dict(status='INCOMPLETE',errors=[],events=[],association_pairs=[],
        trap_coverage_verified=False,root_cause_proven=False,retry_clock_alignment_verified=False)
    track=None; pending={}
    for line in text.splitlines():
        if DEBUGGER_ERROR.search(line) or line.startswith(('PBRT_UNREADABLE','PBRT_DUPLICATE')):
            result['errors'].append('DEBUGGER_CAPTURE_INCOMPLETE')
        for kind,fields in FIELDS.items():
            if not line.startswith('PBRT '+kind+' '):continue
            try:
                event=parse(line,'PBRT '+kind+' ',fields.split())
                if not event['thread']:raise ValueError('ZERO_THREAD')
                if kind=='TRACK':
                    if track or not all(event.values()) or event['size']!=32:raise ValueError('TRACK_INVALID_OR_REPEATED')
                    track=event
                elif not track:raise ValueError('EVENT_BEFORE_TRACK')
                elif kind=='SEND':
                    if event['local_raw']!=0xd9a4 or event['peer_raw']!=0xda84:raise ValueError('SEND_TUPLE_DIFFERS')
                    event['source_matches_create']=event['source_ep']==track['source_ep']
                elif kind in ('INSPECT','ASSOC_RETURN'):
                    if event['source_ep']!=track['source_ep']:raise ValueError('ENDPOINT_DIFFERS')
                    # Live prologue: three pushes (0x18) plus sub rsp,0x50.
                    key=(event['thread'],event['scope']-(0x68 if kind=='INSPECT' else 0),event['nbl'])
                    if kind=='INSPECT':
                        event['record_matches_create']=event['record']==track['record']
                        event['skip_bit21']=bool(event['flags30']&(1<<21))
                        event['associate_bit13']=bool(event['flags34']&(1<<13))
                        event['association_branch_eligible']=not event['skip_bit21'] and event['associate_bit13']
                        if key in pending:raise ValueError('INSPECT_SCOPE_REUSED_BEFORE_RETURN')
                        pending[key]=event
                    else:
                        before=pending.pop(key,None)
                        if before is None:raise ValueError('ASSOC_RETURN_WITHOUT_INSPECT')
                        result['association_pairs'].append(dict(inspect=before,returned=event))
                elif kind=='RETRIEVE':
                    if event['local_raw']!=0xda84 or event['peer_raw']!=0xd9a4:raise ValueError('ACCEPT_TUPLE_DIFFERS')
                    event['returned_record_matches_create']=(event['status']==0 and event['output_raw']==track['record'])
                result['events'].append(dict(kind=kind,**event))
            except ValueError as exc:result['errors'].append(str(exc))
    result['counts']={k:sum(e['kind']==k for e in result['events']) for k in FIELDS}
    # Unmatched entry can be a legitimate bit-controlled skip. Never call it a
    # lost callback, nor call a second SEND a retransmission by output order.
    result['inspect_without_observed_return']=list(pending.values())
    if not result['errors']:
        result['status']='SELECTED_CHAIN_SNAPSHOTS_OBSERVED' if all(result['counts'].values()) else 'CHAIN_INCOMPLETE_COVERAGE_UNPROVEN'
    result['limitation']='No complete trap coverage, object lifetime/reuse proof, exact packet identity, or automatic ETW clock alignment. Failed retrieval output is raw only.'
    return result


def evaluate(capture, console):
    read=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
    plan,run=read(capture/'runtime-plan.json'),read(capture/'diagnostic-run.json')
    sha=hashlib.sha256((capture/'runtime-plan.json').read_bytes()).hexdigest()
    if (plan['policy']!=flow_policy(retry=True) or run.get('debugger_observer') is not True or
        run.get('flow_registration_acknowledged') is not True or sha!=run['plan_sha256'].lower()):
        raise ValueError('RETRY_CAPTURE_BINDING_INVALID')
    raw=console.read_bytes();result=correlate(raw.decode('utf-8-sig'));native=native_evaluate(capture)
    controls=[m for m in native['matches'] if m['role']=='control']
    result.update(plan_sha256=sha,console_sha256=hashlib.sha256(raw).hexdigest(),native_status=native['status'],
        native_errors=native['errors'],correlation_source='user-associated-latest-run-and-control-port-selector',
        automatic_capture_scope_verified=False)
    if native['errors'] or len(controls)!=1 or controls[0]['peer']!='127.0.0.1:42201':
        result['errors'].append('NATIVE_CONTROL_INCOMPLETE');result['status']='INCOMPLETE'
    else:result['control']=controls[0]
    return result


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--capture-directory',type=Path,required=True)
    p.add_argument('--console',type=Path,required=True);p.add_argument('--output-directory',type=Path,required=True)
    a=p.parse_args();r=evaluate(a.capture_directory,a.console);a.output_directory.mkdir(parents=True,exist_ok=True)
    with (a.output_directory/'retry-report.json').open('x',encoding='utf-8') as f:json.dump(r,f,indent=2)
    print(json.dumps({k:r[k] for k in ('status','errors','native_status')}));raise SystemExit(bool(r['errors']))
