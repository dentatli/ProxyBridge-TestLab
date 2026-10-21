"""One endpoint write-watch plus source-at-ACCEPT; no shared SEND trap."""
import hashlib,json
from pathlib import Path
from pb_source_accept_profile import profile as base_profile,policy as base_policy,SCRIPT,SCRIPT_SHA
PROFILE='scripts/debugger/pb-kd-receive-accept-profile-20261021.json'
STAGE='scripts/debugger/pb-kd-receive-accept-update-20261021.wdbg'
PINS=' and '.join('(dwo(tcpip!WfpTlShimInspectRecvTcpDatagram+'+o+') == '+v+')' for o,v in (('0x190','0x304b81f0'),('0x194','0x00200000'),('0x198','0x64247c8b'),('0x27','0xb8b58b48')))
BAD='.printf "PBT INCOMPLETE reason=WATCH_IDENTITY_OR_HEADER\\n"; !pbcabort;'
def watch_action():
    return ('r @$t13 = @$t13 + 1; '
        '.if (($vvalid(@$t10+0x30,4) == 1) and ($vvalid(@$t10+0x1c0,8) == 1)) { '
        '.if (poi(@$t10+0x1c0) == @$t11) { r @$t14 = dwo(@$t10+0x30); '
        '.if (((@$t12 & 0x200000) == 0) and ((@$t14 & 0x200000) != 0)) { bd3; '
        '.if ((@rip == tcpip!WfpTlShimInspectRecvTcpDatagram+0x198) and (@rbx == @$t10) and ($vvalid(@rsi,0x58) == 1)) { '
        'r @$t15 = poi(@rsi+0x50); .if (($vvalid(@$t15,0x14) == 1) and ($vvalid(@$t11+0x1e0,0x10) == 1)) { '
        '.if ((wo(@$t15) == 0xda84) and (wo(@$t15+2) == 0xd9a4) and ((by(@$t15+0xc) & 0xf0) >= 0x50)) { '
        '.printf "PBT RECEIVE ep=%p record=%p context=%p size=%I64x old=%x new=%x ip=%p nbl=%p header=%p src_raw=%x dst_raw=%x tcp_flags=%x seq_raw=%x ack_raw=%x writes=%I64x\\n", '
        '@$t10, @$t11, poi(@$t11+0x1e0), poi(@$t11+0x1e8), @$t12, @$t14, @rip, poi(@rsi+8), @$t15, wo(@$t15), wo(@$t15+2), by(@$t15+0xd), dwo(@$t15+4), dwo(@$t15+8), @$t13; '
        '} .else { '+BAD+' } } .else { '+BAD+' } } .else { '+BAD+' }; '
        '} .else { .if (@$t13 >= 0x10) { .printf "PBT INCOMPLETE reason=WATCH_LIMIT\\n"; !pbcabort; } }; '
        'r @$t12 = @$t14; } .else { '+BAD+' } } .else { '+BAD+' }; gc;')
def profile():
    p=base_profile();p.update(method='kd-receive-accept-20261021-v1',registration='manual-receive-accept-actions',dynamic_point_ids=[3],inactive_point_ids=[],proposed_active_point_ids=[2,3,4],automatic_enable_point_ids=[3,4],raw_hit_limits_per_point={'2':32,'3':16,'4':512},max_total_raw_hits=560,selected_events_per_point={'2':1,'3':1,'4':1},receive_writer_pin=PINS)
    arm='.if (($vvalid(@$t10+0x30,4) == 1) and ((@$t10 & 3) == 0)) { r @$t12 = dwo(@$t10+0x30); r @$t13 = 0; .if ((@$t12 & 0x200000) == 0) { bc3; ba3 w4 (@$t10+0x30) '+json.dumps(watch_action())+'; be4; } .else { .printf "PBT INCOMPLETE reason=BIT_ALREADY_SET\\n"; !pbcabort; }; } .else { '+BAD+' };'
    p['points'][0]['action']='r @$t0 = @$t0 + 1; .if (@$t0 >= 0x20) { !pbcabort; } .else { .if ($vvalid(@r14,4) == 1) { .if ((wo(@r14) == 2) and (wo(@r14+2) == 0xd9a4)) { r @$t11 = @rax; !pbccreate @r14, @rdi, @rax; .if (@$t10 != 0) { '+arm+' } } } }; gc;'
    p['points'][1]=dict(id=3,target='tcpip!WfpTlShimInspectRecvTcpDatagram+0x198',action='gc;',initial_state='disabled-placeholder',dynamic_action=watch_action(),access='w4',dynamic_address='selected_source_ep+0x30',disable_on_transition=True)
    p['limits']=['Point3 is replaced by a selected-address w4 watch, never a shared SEND breakpoint.','At most16 selected-address writes; disable3 at first bit21 transition, retain4 until selected ACCEPT.','Same-source receive and ACCEPT evidence does not prove physical packet identity or fault ownership.']
    return p
def encoded():return (json.dumps(profile(),indent=2)+'\n').encode()
PROFILE_SHA=hashlib.sha256(encoded()).hexdigest()
def policy(target=True):
    p=base_policy(target);p.pop('source_accept_snapshot',None)
    p.update(receive_accept_snapshot=True,debugger_points=[2,3,4],inactive_debugger_points=[],automatic_debugger_enable_after_create=[3,4],dynamic_watch_point_ids=[3],receive_writer_pin=PINS,raw_hit_limits_per_point={'2':32,'3':16,'4':512},max_total_raw_hits=560,selected_events_per_point={'2':1,'3':1,'4':1},packet_header_bytes=20,packet_header_count_max=1)
    return p
def registration(profile_path,receipt_path,receipt_sha,boot):
    from pb_kd_session import read,checked,boot_identity
    p=read(checked(profile_path,PROFILE_SHA));r=read(checked(receipt_path,receipt_sha))
    if p!=profile() or r.get('method')!='target-flow-prepared-commands-v1' or r.get('profile_sha256')!=PROFILE_SHA or r.get('source')!='prepared-command-awaiting-user-attestation' or r.get('expected_disabled_ids')!=[2,3,4] or r.get('host_registration_observed') is not False or r.get('script_sha256')!=SCRIPT_SHA or boot_identity(r['boot'])!=boot_identity(boot):raise ValueError('RECEIVE_ACCEPT_REGISTRATION_INVALID')
    return p
def parser_proof(path):
    from pb_receive_accept_fixture import CASES,FIXTURE
    from pb_kd_session import read,checked,inventory
    path=Path(path);r=read(path);root=Path(__file__).resolve().parents[1];checked(root/SCRIPT,SCRIPT_SHA)
    if r.get('method')!='receive-accept-cdb-proof-v1' or r.get('profile_sha256')!=PROFILE_SHA or r.get('script_sha256')!=SCRIPT_SHA or r.get('passed') is not True or any(r.get(k) is not False for k in ('kernel_connection','product_started','traffic_generated')) or [c['case'] for c in r['cases']]!=list(CASES) or any(not c['passed'] or c['exit_code'] for c in r['cases']):raise ValueError('RECEIVE_ACCEPT_PROOF_INVALID')
    if read(path.parent/'candidate.json')!=profile():raise ValueError('RECEIVE_ACCEPT_CANDIDATE_DIFFERS')
    files=[path,path.parent/'candidate.json',root/SCRIPT]
    for case in CASES:
        child=path.parent/case
        if (child/'target.py').read_text()!=FIXTURE.replace('CASE',repr(case)):raise ValueError('RECEIVE_ACCEPT_FIXTURE_DIFFERS')
        files += [child/n for n in ('target.py','commands.wdbg','setup.wdbg','stdout.txt','stderr.txt')]
    return dict(path=str(path),sha256=hashlib.sha256(path.read_bytes()).hexdigest(),files=inventory(files))
def write(root):
    root=Path(root);(root/PROFILE).write_bytes(encoded())
    body=' '.join('bp'+str(v['id'])+' '+v['target']+' '+json.dumps(v['action'])+'; bd'+str(v['id'])+';' for v in profile()['points'])
    text='.if ('+PINS+') { '+body+' .printf "PBT CONFIG writer=%p watch_limit=10 version=1\\n", tcpip!WfpTlShimInspectRecvTcpDatagram+0x198; } .else { .printf "PBT CODE_PIN_FAILED no_runtime\\n"; };\n'
    (root/STAGE).write_bytes(text.encode());return PROFILE_SHA
