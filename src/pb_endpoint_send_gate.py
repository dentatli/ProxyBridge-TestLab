"""Selected endpoint read watch: observe the send flag gate without a global send trap."""
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import sys
from pb_endpoint_watch_candidate import quoted,CLEAR,STOP

PROFILE='scripts/debugger/pb-kd-selected-endpoint-send-gate-profile-20261020.json'
STAGE='scripts/debugger/pb-kd-selected-endpoint-send-gate-disabled-20261020.wdbg'
PROFILE_SHA='22febf6a90774473a9618f655c38ab5c854b6ee627cbcaaaa3e4aefe459eb3ba'
GATE='tcpip!WfpTlShimInspectFastLoopbackSendDatagram+0x30'


def guard(condition,body,bad):
    return '.if ('+condition+') { '+body+' } .else { '+bad+' }; '


def packet_action():
    """Only one contiguous mapped MDL; TCP header or unfragmented IPv4/TCP, no payload."""
    bad=''
    emit=('.printf "PBSD SEND_HEADER send=%I64x nbl=%p header=%p flags=%x h0=%I64x h1=%I64x h2=%x\\n", '
          '@$t6, @rbp, @$t12, by(@$t12+0xd), poi(@$t12), poi(@$t12+8), dwo(@$t12+0x10); r @$t17 = 1;')
    emit=guard('(@$t12 != 0) and ($vvalid(@$t12,0x14) == 1)',
        guard('(wo(@$t12) == 0xd9a4) and (wo(@$t12+2) == 0xda84) and ((by(@$t12+0xc) & 0xf0) >= 0x50) and ((by(@$t12+0xd) & 0x17) == 2)',emit,bad),bad)
    ip=('r @$t15 = (by(@$t11) & 0xf) * 4; '+guard(
        '((by(@$t11) & 0xf0) == 0x40) and (by(@$t11+9) == 6) and (@$t15 >= 0x14) and (@$t15 <= 0x3c) and '
        '((wo(@$t11+6) & 0xff3f) == 0) and (dwo(@$t11+0xc) == 0x100007f) and (dwo(@$t11+0x10) == 0x100007f) and '
        '(@$t13 >= @$t15+0x14) and (dwo(@$t10+0x28) >= @$t14+@$t15+0x14)',
        'r @$t12 = @$t11 + @$t15;',bad))
    body='r @$t12 = 0; '+guard('(wo(@$t11) == 0xd9a4) and (wo(@$t11+2) == 0xda84)','r @$t12 = @$t11;',ip)+emit
    body=guard('$vvalid(@$t11,0x14) == 1',body,bad)
    body=('r @$t11 = poi(@$t10+0x18) + @$t14; '+body)
    body=guard('((wo(@$t10+0xa) & 5) != 0) and (poi(@$t10+0x18) != 0) and (@$t13 >= 0x14) and (dwo(@$t10+0x28) >= @$t14+0x14)',body,bad)
    body=guard('$vvalid(@$t10,0x30) == 1',body,bad)
    body='r @$t10 = poi(@$t9+8); r @$t13 = dwo(@$t9+0x18); r @$t14 = dwo(@$t9+0x10); '+body
    body=guard('$vvalid(@$t9,0x20) == 1',body,bad)
    body='r @$t9 = poi(@rbp+8); '+body
    return ('r @$t17 = 0; '+guard('$vvalid(@rbp+8,8) == 1',body,bad)+
        '.if (@$t17 == 0) { '+STOP+' .printf "PBSD_UNREADABLE event=SEND_HEADER capture=incomplete\\n"; }; ')


def read_action():
    bad=STOP+' .printf "PBSD_IDENTITY_CHANGED capture=incomplete\\n";'
    body=('r @$t6 = @$t6 + 1; r @$t7 = @eax; '
        '.printf "PBSD SEND_GATE send=%I64x raw=%I64x thread=%p ep=%p record=%p nbl=%p flags_reg=%x family=%x ip=%p\\n", '
        '@$t6, @$t4, @$thread, @$t2, @$t1, @rbp, @$t7, @r14w, @rip; '+packet_action()+
        '.if ((@$t7 & 0x200000) != 0) { '+CLEAR+' } .else { .if (@$t6 >= 4) { '+STOP+' .printf "PBSD_LIMIT point=3 stage=send_count capture=incomplete\\n"; } }; ')
    body=guard('($vvalid(@$t2+0x1c0,8) == 1) and (@r14w == 2)',guard('poi(@$t2+0x1c0) == @$t1',body,bad),bad)
    return ('r @$t4 = @$t4 + 1; '
        '.if ((@rip == '+GATE+') and (@rcx == @$t2) and (@rbx == @$t2)) { '+body+' }; '
        '.if ((@$t8 != 0) and (@$t4 >= 0x40)) { '+STOP+' .printf "PBSD_LIMIT point=3 stage=raw_reads capture=incomplete\\n"; }; gc;')


def create_action():
    bad=STOP+' .printf "PBSD_UNREADABLE event=CREATE capture=incomplete\\n";'
    body=('bd2; r @$t1 = @rax; r @$t2 = @rdi; r @$t4 = 0; r @$t6 = 0; '
        '.printf "PBSD TRACK ep=%p record=%p context=%p size=%I64x refs=%x flags30=%x\\n", '
        '@$t2, @$t1, poi(@$t1+0x1e0), poi(@$t1+0x1e8), dwo(@$t1+0x1f0), dwo(@$t2+0x30); '
        'r @$t8 = 1; ba3 r4 (@$t2+0x30) '+quoted(read_action())+'; be4; '
        '.printf "PBSD ARMED address=%p access=r4 accept=4\\n", @$t2+0x30;')
    body=guard('($vvalid(@rdi+0x30,4) == 1) and ($vvalid(@rdi+0x1c0,8) == 1) and '
        '($vvalid(@rax+0x1e0,0x14) == 1) and (@rax != 0) and ((@rdi & 3) == 0)',body,bad)
    body=guard('(wo(@r14) == 2) and (wo(@r14+2) == 0xd9a4)',body,'')
    body=guard('$vvalid(@r14,4) == 1',body,bad)
    return ('r @$t3 = @$t3 + 1; .if (@$t3 >= 0x10) { '+STOP+
        ' .printf "PBSD_LIMIT point=2 capture=incomplete\\n"; } .else { '+body+' }; gc;')


def accept_action():
    bad=STOP+' .printf "PBSD_UNREADABLE event=ACCEPT capture=incomplete\\n";'
    emit=(STOP+' .printf "PBSD ACCEPT ep=%p nbl=%p local_raw=%x peer_raw=%x status=%x output_raw=%p reads=%I64x sends=%I64x\\n", '
        '@rdi, @rbx, wo(@rbp-0x7c), wo(@rbp-0x7a), @eax, poi(@rbp-0x28), @$t4, @$t6;')
    body=guard('$vvalid(@rbp-0x28,8) == 1',emit,bad)
    body=guard('(wo(@rbp-0x7c) == 0xda84) and (wo(@rbp-0x7a) == 0xd9a4)',body,'')
    body=guard('$vvalid(@rbp-0x7c,4) == 1',body,bad)
    return ('r @$t5 = @$t5 + 1; .if (@$t5 >= 0x40) { '+STOP+
        ' .printf "PBSD_LIMIT point=4 capture=incomplete\\n"; } .else { '+body+' }; gc;')


def profile():
    return dict(method='kd-selected-endpoint-send-gate-20261020-v1',registered_point_ids=[2,4],dynamic_point_ids=[3],active_point_ids=[],
        host_enable_point_ids=[2],automatic_enable_point_ids=[4],watch_access='r',watch_size=4,raw_hit_limits_per_point={'2':16,'3':64,'4':64},
        max_total_raw_hits=144,points=[dict(id=i,target=t,action=a) for i,t,a in (
            (2,'tcpip!AlepCreateRedirectRecord+0x396',create_action()),(3,'dynamic-selected-endpoint+0x30',read_action()),
            (4,'tcpip!WfpAleAuthorizeAccept+0xcaf',accept_action()))],automatic_disable=True,automatic_enable=True,
        limits=['Only selected endpoint reads/writes trigger point3; stop after first observed skip or 64 accesses.',
            'A clear bit only proves eligibility for the association path, not completed association.',
            'SYN header capture supports one contiguous already mapped MDL, raw TCP or unfragmented IPv4/TCP.',
            'No complete NBL lifetime or Windows-versus-driver fault attribution.'])


def policy(target=True):
    from pb_endpoint_watch_profile import policy as base
    p=base(target)
    p.update(endpoint_send_gate=True,debugger_points=[2,3,4],initial_debugger_points=[] if target else [2],
        host_enable_debugger_points=[2],inactive_debugger_points=[],automatic_debugger_enable_after_create=[3,4],
        automatic_debugger_install_after_create=[3],watch_access='r',raw_hit_limits_per_point={'2':16,'3':64,'4':64},
        max_total_raw_hits=144,selected_snapshot_limits_per_point={'2':1,'3':4,'4':1},stack_count_max=0,
        packet_header_bytes=20,packet_header_count_max=4)
    return p


def registration(profile_path,receipt_path,receipt_sha,boot):
    from pb_kd_session import read,checked,boot_identity
    p=read(checked(profile_path,PROFILE_SHA));r=read(checked(receipt_path,receipt_sha))
    if p!=profile() or (r['method']!='target-flow-prepared-commands-v1' or r['source']!='prepared-command-awaiting-user-attestation' or
        r['profile_sha256']!=PROFILE_SHA or r['expected_disabled_ids']!=[2,4] or r['expected_absent_ids']!=[3] or
        r['host_registration_observed'] is not False or boot_identity(r['boot'])!=boot_identity(boot)):
        raise ValueError('SEND_GATE_REGISTRATION_DIFFERS')
    return p


def correlate(text):
    from pb_target_retrieve_report import parse,DEBUGGER_ERROR
    r=dict(status='INCOMPLETE',errors=[],track=None,armed=None,sends=[],headers=[],accept=None,
        skip_observed=False,repeated_syn_observed=False,nbl_pointer_match=False,root_cause_proven=False,trap_coverage_verified=False)
    for line in text.splitlines():
        try:
            if DEBUGGER_ERROR.search(line):raise ValueError('DEBUGGER_ERROR')
            if line.startswith(('PBSD_LIMIT','PBSD_UNREADABLE','PBSD_IDENTITY_CHANGED')):raise ValueError('SEND_CAPTURE_INCOMPLETE')
            if line.startswith('PBSD TRACK '):
                t=parse(line,'PBSD TRACK ','ep record context size refs flags30'.split())
                if r['track'] or not all(t[k] for k in ('ep','record','context','refs')) or t['size']!=32:raise ValueError('SEND_TRACK_INVALID')
                r['track']=t
            elif line.startswith('PBSD ARMED '):
                if r['armed'] or not r['track'] or 'access=r4 accept=4' not in line:raise ValueError('SEND_ARM_INVALID')
                a=parse(line.split(' access=')[0],'PBSD ARMED ',['address'])
                if a['address']!=r['track']['ep']+0x30:raise ValueError('SEND_ARM_ADDRESS_DIFFERS')
                r['armed']=a
            elif line.startswith('PBSD SEND_GATE '):
                s=parse(line,'PBSD SEND_GATE ','send raw thread ep record nbl flags_reg family ip'.split())
                if not r['armed'] or r['accept'] or r['skip_observed'] or len(r['sends'])!=len(r['headers']) or s['send']!=len(r['sends'])+1 or s['send']>4 or not 1<=s['raw']<=64:raise ValueError('SEND_GATE_ORDER_INVALID')
                if (s['ep'],s['record'])!=(r['track']['ep'],r['track']['record']) or s['family']!=2 or not s['nbl']:raise ValueError('SEND_GATE_IDENTITY_INVALID')
                if r['sends'] and s['raw']<=r['sends'][-1]['raw']:raise ValueError('SEND_RAW_COUNT_INVALID')
                r['sends'].append(s);r['skip_observed']=bool(s['flags_reg']&0x200000)
            elif line.startswith('PBSD SEND_HEADER '):
                h=parse(line,'PBSD SEND_HEADER ','send nbl header flags h0 h1 h2'.split())
                if len(r['headers'])+1!=len(r['sends']) or h['send']!=len(r['sends']) or h['nbl']!=r['sends'][-1]['nbl']:raise ValueError('SEND_HEADER_ORDER_INVALID')
                raw=h['h0'].to_bytes(8,'little')+h['h1'].to_bytes(8,'little')+h['h2'].to_bytes(4,'little')
                if raw[:4]!=bytes.fromhex('a4d984da') or raw[13]!=h['flags'] or raw[12]>>4<5 or h['flags']&0x17!=2 or not h['header']:raise ValueError('SEND_HEADER_INVALID')
                h['sequence']=int.from_bytes(raw[4:8],'big');r['headers'].append(h)
            elif line.startswith('PBSD ACCEPT '):
                a=parse(line,'PBSD ACCEPT ','ep nbl local_raw peer_raw status output_raw reads sends'.split())
                if r['accept'] or not r['headers'] or len(r['headers'])!=len(r['sends']) or (a['local_raw'],a['peer_raw'])!=(0xda84,0xd9a4) or a['sends']!=len(r['sends']) or not r['sends'][-1]['raw']<=a['reads']<=64:raise ValueError('SEND_ACCEPT_INVALID')
                r['accept']=a
        except (ValueError,OverflowError) as e:r['errors'].append(str(e))
    if not all((r['track'],r['armed'],r['sends'],r['headers'],r['accept'])) or len(r['sends'])!=len(r['headers']):r['errors'].append('SEND_REQUIRED_OBSERVATION_MISSING')
    if r['headers']:
        r['repeated_syn_observed']=len(r['headers'])>=2 and len({h['sequence'] for h in r['headers']})==1
    if r['accept'] and r['sends']:r['nbl_pointer_match']=r['accept']['nbl']==r['sends'][-1]['nbl']
    if not r['errors']:r['status']='SEND_SKIP_AND_ACCEPT_MISS_OBSERVED' if r['skip_observed'] and r['repeated_syn_observed'] and not r['sends'][0]['flags_reg']&0x200000 and r['accept']['status']==0xc0000225 else 'SEND_GATE_OBSERVATIONS_COLLECTED'
    return r


def evaluate(capture,console):
    from pb_kd_session import read
    from pb_target_accept_report import evaluate as native_evaluate
    capture,console=Path(capture),Path(console);p=read(capture/'runtime-plan.json');run=read(capture/'diagnostic-run.json')
    probe=p['policy'].get('workload')=='flag-four-probe';sha=hashlib.sha256((capture/'runtime-plan.json').read_bytes()).hexdigest()
    if p['policy']!=policy(not probe) or run.get('debugger_observer') is not True or run.get('flow_registration_acknowledged') is not True or run['plan_sha256'].lower()!=sha:raise ValueError('SEND_CAPTURE_BINDING_INVALID')
    raw=console.read_bytes();r=correlate(raw.decode('utf-8-sig'));n=native_evaluate(capture)
    c=[m for m in n['matches'] if m['role']=='control']
    r.update(native_status=n['status'],native_errors=n['errors'],plan_sha256=sha,console_sha256=hashlib.sha256(raw).hexdigest(),automatic_capture_scope_verified=False)
    if n['errors'] or len(c)!=1 or c[0]['peer']!='127.0.0.1:42201':r['errors'].append('SEND_NATIVE_CONTROL_INCOMPLETE')
    if probe:
        if r['skip_observed'] or not r['accept'] or r['accept']['status']!=0 or not r['track'] or r['accept']['output_raw']!=r['track']['record'] or len(c)!=1 or c[0]['original_api_failure']:r['errors'].append('SEND_HEALTHY_PROBE_INCOMPLETE')
        if not r['errors']:r['status']='SEND_GATE_HEALTHY_CONTROL_OBSERVED'
    elif len(c)!=1 or not c[0]['original_api_failure']:r['errors'].append('SEND_TARGET_API_FAILURE_NOT_REPRODUCED')
    if r['errors']:r['status']='INCOMPLETE'
    return r
