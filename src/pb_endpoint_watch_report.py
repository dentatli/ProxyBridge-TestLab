"""Read selected flags writes; do not infer complete lifetime or traffic causation."""
import hashlib
from pathlib import Path
import re
from pb_kd_session import read
from pb_target_retrieve_report import parse,DEBUGGER_ERROR


def correlate(text):
    r=dict(status='INCOMPLETE',errors=[],track=None,armed=None,writes=[],retrieve=None,frames=[],
           post_write_observed=False,transition_observed=False,root_cause_proven=False,trap_coverage_verified=False,packet_header=None)
    in_stack=False;done=False;stack_lines=0
    for line in text.splitlines():
        try:
            if DEBUGGER_ERROR.search(line):raise ValueError('DEBUGGER_ERROR')
            if line.startswith(('PBW_LIMIT','PBW_UNREADABLE','PBW_IDENTITY_CHANGED')):raise ValueError('WATCH_CAPTURE_INCOMPLETE')
            if line=='PBW TRANSITION_BEGIN':
                if in_stack or done or not r['transition_observed']:raise ValueError('WATCH_STACK_BEGIN_INVALID')
                in_stack=True
            elif line=='PBW TRANSITION_END':
                if not in_stack or not r['frames']:raise ValueError('WATCH_STACK_END_INVALID')
                in_stack=False;done=True
            elif in_stack:
                stack_lines+=1
                if stack_lines>32:raise ValueError('WATCH_STACK_OUTPUT_LIMIT')
                if re.match(r'^\s*[0-9a-fA-F]{2}\s+[0-9a-fA-F`]{8,17}\s+',line):
                    r['frames'].append(line)
                    if len(r['frames'])>8:raise ValueError('WATCH_STACK_FRAME_LIMIT')
            elif line.startswith('PBW TRACK '):
                if r['track']:raise ValueError('WATCH_REPEATED_TRACK')
                r['track']=parse(line,'PBW TRACK ','ep record context size refs flags30'.split())
                if not all(r['track'][k] for k in ('ep','record','context','refs')) or r['track']['size']!=32:raise ValueError('WATCH_TRACK_INVALID')
            elif line.startswith('PBW ARMED '):
                if not r['track'] or r['armed']:raise ValueError('WATCH_ARM_INVALID')
                r['armed']=parse(line,'PBW ARMED ',['address'])
                if r['armed']['address']!=r['track']['ep']+0x30:raise ValueError('WATCH_ARM_ADDRESS_DIFFERS')
            elif line.startswith('PBW WRITE '):
                w=parse(line,'PBW WRITE ','hit thread ep record old new ip'.split())
                if not r['track'] or not r['armed'] or w['hit']!=len(r['writes'])+1 or w['hit']>16:raise ValueError('WATCH_SEQUENCE_INVALID')
                if (w['ep'],w['record'])!=(r['track']['ep'],r['track']['record']):raise ValueError('WATCH_IDENTITY_DIFFERS')
                if w['old']!=(r['writes'][-1]['new'] if r['writes'] else r['track']['flags30']):raise ValueError('WATCH_FLAGS_SEQUENCE_DIFFERS')
                if r['transition_observed']:raise ValueError('WATCH_WRITE_AFTER_ONE_SHOT')
                r['writes'].append(w);r['post_write_observed']=True
                if not w['old']&0x200000 and w['new']&0x200000:r['transition_observed']=True
            elif line.startswith('PBW RECEIVE_HEADER '):
                h=parse(line,'PBW RECEIVE_HEADER ','ep record nbl header src_raw dst_raw flags h0 h1 h2'.split())
                if r['packet_header'] or not r['transition_observed'] or (h['ep'],h['record'])!=(r['track']['ep'],r['track']['record']):raise ValueError('WATCH_PACKET_IDENTITY_OR_ORDER_INVALID')
                raw=h['h0'].to_bytes(8,'little')+h['h1'].to_bytes(8,'little')+h['h2'].to_bytes(4,'little')
                if (h['src_raw'],h['dst_raw'])!=(0xda84,0xd9a4) or raw[:4]!=bytes.fromhex('84daa4d9') or h['flags']!=raw[13] or raw[12]>>4<5 or not h['nbl'] or not h['header']:raise ValueError('WATCH_PACKET_HEADER_INVALID')
                r['packet_header']=h
            elif line.startswith('PBW RETRIEVE '):
                if r['retrieve'] or not r['track']:raise ValueError('WATCH_RETRIEVE_INVALID')
                r['retrieve']=parse(line,'PBW RETRIEVE ','ep nbl status output_raw'.split())
        except (ValueError,OverflowError) as exc:r['errors'].append(str(exc))
    if in_stack or (r['transition_observed'] and not done):r['errors'].append('WATCH_STACK_MISSING')
    if not r['errors']:
        r['status']='ENDPOINT_FLAG_TRANSITION_OBSERVED' if r['transition_observed'] else 'ENDPOINT_WATCH_COVERAGE_UNPROVEN'
    return r


def evaluate(capture,console):
    from pb_endpoint_watch_profile import policy
    from pb_target_accept_report import evaluate as native_evaluate
    capture=Path(capture);console=Path(console)
    p=read(capture/'runtime-plan.json');run=read(capture/'diagnostic-run.json')
    if p['policy'].get('endpoint_send_gate') is True:
        from pb_endpoint_send_gate import evaluate as send_evaluate
        return send_evaluate(capture,console)
    probe=p['policy'].get('workload')=='flag-four-probe'
    packet=p['policy'].get('endpoint_packet_header') is True
    if packet:
        from pb_endpoint_packet_watch import policy
    sha=hashlib.sha256((capture/'runtime-plan.json').read_bytes()).hexdigest()
    if (p['policy']!=policy(not probe) or run.get('debugger_observer') is not True or
        run.get('flow_registration_acknowledged') is not True or run['plan_sha256'].lower()!=sha):raise ValueError('ENDPOINT_WATCH_CAPTURE_BINDING_INVALID')
    raw=console.read_bytes();r=correlate(raw.decode('utf-8-sig'));native=native_evaluate(capture)
    r.update(native_status=native['status'],native_errors=native['errors'],plan_sha256=sha,
             console_sha256=hashlib.sha256(raw).hexdigest(),automatic_capture_scope_verified=False)
    controls=[m for m in native['matches'] if m['role']=='control']
    if packet and not r['packet_header']:r['errors'].append('ENDPOINT_PACKET_HEADER_MISSING')
    if native['errors'] or len(controls)!=1 or controls[0]['peer']!='127.0.0.1:42201':r['errors'].append('NATIVE_CONTROL_INCOMPLETE')
    if probe:
        a=r['retrieve'];t=r['track']
        if not t or not r['armed'] or not a or a['status']!=0 or a['output_raw']!=t['record'] or len(controls)!=1 or controls[0]['original_api_failure']:
            r['errors'].append('ENDPOINT_WATCH_POSITIVE_PROBE_INCOMPLETE')
        if not r['errors']:r['status']='ENDPOINT_WATCH_NATIVE_SUCCESS_OBSERVED'
    if r['errors']:r['status']='INCOMPLETE'
    return r
