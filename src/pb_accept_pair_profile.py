"""Two bounded, tuple-filtered accept call sites; no per-NBL memory watches."""
import hashlib,json
from pathlib import Path
SCRIPT='scripts/debugger/pb_accept_pair.js'
PROFILE='scripts/debugger/pb-kd-accept-pair-profile-20261021.json'
STAGE='scripts/debugger/pb-kd-accept-pair-update-20261021.wdbg'
SCRIPT_SHA='f6b159e7ed3b5251932ab2371eb15f73d98c32be4ffe6a6e213d738d4aea140e'
PROFILE_SHA='839029a01ba1bb53e98c145900e9fee770c9ce508d4be32f0ad6c8a0d881fb3b'
def action(point):
    count='$t0' if point==2 else '$t1'
    call='!pbapre @rcx, @rbp, @rdi, @rsp' if point==2 else '!pbapost @rbx, @rbp, @rdi, @rsp, @eax'
    return ('r @'+count+' = @'+count+' + 1; .if (@'+count+' >= 0x100) { bd2; bd3; .printf "PBA INCOMPLETE reason=RAW_LIMIT\\n"; } .else { '
            '.if ($vvalid(@rbp-0x7c,4) == 1) { .if ((wo(@rbp-0x7c) == 0xda84) and (wo(@rbp-0x7a) == 0xd9a4)) { '+call+'; } } '
            '.else { bd2; bd3; .printf "PBA INCOMPLETE reason=SELECTOR_UNREADABLE\\n"; } }; gc;')
def profile():
    return dict(method='kd-accept-pair-20261021-v1',registered_point_ids=[2,3],active_point_ids=[],dynamic_point_ids=[],
        host_enable_point_ids=[2,3],script=SCRIPT,script_sha256=SCRIPT_SHA,model_required=0,initialization='pbaInitKernel',
        raw_hit_limits_per_point={'2':256,'3':256},max_total_raw_hits=512,selected_pairs=1,
        points=[dict(id=i,target='tcpip!WfpAleAuthorizeAccept+'+('0xcaa' if i==2 else '0xcaf'),action=action(i)) for i in (2,3)],
        automatic_enable=False,automatic_disable=True,registration='pbaRegister',recovery=['bd2','bd3','dx @$scriptContents.pbaStop()','g'],
        limits=['Software breakpoints still see other accepts; MASM filters before JavaScript.',
                'Only one selected pre/post pair is captured; no source endpoint or physical packet lifetime claim.'])
def policy(target=True):
    from pb_target_accept_plan import create_policy
    return dict(create_policy(target,target),observer='etw+kd-target-flag',workload='flag-target-201-staged' if target else 'flag-four-probe',
        fillers=200 if target else 0,filler_ports=[42001,42200] if target else [],single_probe=not target,
        endpoint_accept_pair=True,debugger_points=[2,3],host_enable_debugger_points=[2,3],
        inactive_debugger_points=[],automatic_debugger_control=False,automatic_debugger_disable=True,
        registration_confirmation='user-run-argument-no-independent-host-proof',
        nbl_script_sha256=SCRIPT_SHA,model_required=0,raw_hit_limits_per_point={'2':256,'3':256},max_total_raw_hits=512,
        selected_pairs=1,source_endpoint_observed=False,physical_packet_lifetime_verified=False)
def registration(profile_path,receipt_path,receipt_sha,boot):
    from pb_kd_session import read,checked,boot_identity
    p=read(checked(profile_path,PROFILE_SHA));r=read(checked(receipt_path,receipt_sha))
    if p!=profile() or r.get('method')!='target-flow-prepared-commands-v1' or r.get('profile_sha256')!=PROFILE_SHA or r.get('source')!='prepared-command-awaiting-user-attestation' or r.get('expected_disabled_ids')!=[2,3] or r.get('expected_absent_ids')!=[4] or r.get('host_registration_observed') is not False or r.get('script_sha256')!=SCRIPT_SHA or boot_identity(r['boot'])!=boot_identity(boot):raise ValueError('ACCEPT_PAIR_REGISTRATION_INVALID')
    return p
def parser_proof(path):
    from pb_accept_pair_fixture import CASES,FIXTURE
    from pb_kd_session import read,checked,inventory
    from pb_prepare_kd_baseline import plain
    path=plain(Path(path));r=read(path);root=Path(__file__).resolve().parents[1]
    checked(root/SCRIPT,SCRIPT_SHA)
    if r.get('script_sha256')!=SCRIPT_SHA or r.get('passed') is not True or r.get('method')!='accept-pair-cdb-proof-v1' or any(r.get(k) is not False for k in ('kernel_connection','traffic_generated','product_started')) or [c['case'] for c in r['cases']]!=list(CASES) or any(not c['passed'] or c['exit_code'] for c in r['cases']):raise ValueError('ACCEPT_PAIR_PROOF_INVALID')
    files=[path,root/SCRIPT]
    for case in CASES:
        child=path.parent/case
        if (child/'target.py').read_text()!=FIXTURE.replace('CASE',repr(case)):raise ValueError('ACCEPT_PAIR_FIXTURE_DIFFERS')
        files += [child/n for n in ('target.py','commands.wdbg','setup.wdbg','stdout.txt','stderr.txt')]
    return dict(path=str(path),sha256=hashlib.sha256(path.read_bytes()).hexdigest(),files=inventory(files))
def write(root):
    root=Path(root);raw=(json.dumps(profile(),indent=2)+'\n').encode()
    (root/PROFILE).write_bytes(raw)
    (root/STAGE).write_bytes(b'dx @$scriptContents.pbaRegister()\n')
    return hashlib.sha256(raw).hexdigest()
