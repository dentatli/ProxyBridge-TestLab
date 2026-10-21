"""A selected CREATE, branch-condition snapshot and accepted NBL snapshot."""
import hashlib,json,re
from pathlib import Path
SCRIPT='scripts/debugger/pb_retry_chain.js'
PROFILE='scripts/debugger/pb-kd-retry-chain-profile-20261021.json'
STAGE='scripts/debugger/pb-kd-retry-chain-update-20261021.wdbg'
SCRIPT_SHA='2939e8f76354652b6cbecda6c62bcd97d48450781b50a82a286ab3f47d9d61da'
LIMITS={'2':32,'3':512,'4':512}
def actions():
    text=(Path(__file__).resolve().parents[1]/SCRIPT).read_text()
    return {i:re.search(r"var PBC_"+name+r"_ACTION='(.*)';",text).group(1) for i,name in ((2,'CREATE'),(3,'SKIP'),(4,'ACCEPT'))}
def profile():
    a=actions()
    return dict(method='kd-retry-chain-20261021-v1',registered_point_ids=[2,3,4],active_point_ids=[],dynamic_point_ids=[],host_enable_point_ids=[2,3,4],
        script=SCRIPT,script_sha256=SCRIPT_SHA,model_required=0,initialization='pbcInitKernel',registration='pbcRegister',
        raw_hit_limits_per_point=LIMITS,max_total_raw_hits=sum(LIMITS.values()),selected_events_per_point=1,
        automatic_enable=False,automatic_disable=True,
        points=[dict(id=i,target=t,action=a[i]) for i,t in ((2,'tcpip!AlepCreateRedirectRecord+0x396'),(3,'tcpip!WfpTlShimInspectFastLoopbackSendDatagram+0x34'),(4,'tcpip!WfpAleAuthorizeAccept+0xcaf'))],
        recovery=['bd2','bd3','bd4','dx @$scriptContents.pbcStop()','g'],
        limits=['Software traps include background calls; only selected events call snapshot helpers.',
                'SKIP records carry-set branch condition before jb, not a separate instruction trace.',
                'NBL address equality is not physical packet lifetime proof; no independent SOCKET join.'])
def encoded():return (json.dumps(profile(),indent=2)+'\n').encode()
PROFILE_SHA=hashlib.sha256(encoded()).hexdigest()
def policy(target=True):
    if not target:raise ValueError('RETRY_CHAIN_TARGET_ONLY_USE_EXISTING_HEALTHY')
    from pb_target_accept_plan import create_policy
    return dict(create_policy(True,True),observer='etw+kd-target-flag',workload='flag-target-201-staged',
        endpoint_retry_chain=True,debugger_points=[2,3,4],host_enable_debugger_points=[2,3,4],inactive_debugger_points=[],
        automatic_debugger_control=False,automatic_debugger_disable=True,registration_confirmation='user-run-argument-no-independent-host-proof',
        nbl_script_sha256=SCRIPT_SHA,model_required=0,raw_hit_limits_per_point=LIMITS,max_total_raw_hits=sum(LIMITS.values()),selected_events_per_point=1,
        physical_packet_lifetime_verified=False,independent_socket_join_verified=False)
def registration(profile_path,receipt_path,receipt_sha,boot):
    from pb_kd_session import read,checked,boot_identity
    p=read(checked(profile_path,PROFILE_SHA));r=read(checked(receipt_path,receipt_sha))
    if p!=profile() or r.get('method')!='target-flow-prepared-commands-v1' or r.get('profile_sha256')!=PROFILE_SHA or r.get('source')!='prepared-command-awaiting-user-attestation' or r.get('expected_disabled_ids')!=[2,3,4] or r.get('host_registration_observed') is not False or r.get('script_sha256')!=SCRIPT_SHA or boot_identity(r['boot'])!=boot_identity(boot):raise ValueError('RETRY_CHAIN_REGISTRATION_INVALID')
    return p
def parser_proof(path):
    from pb_retry_chain_fixture import CASES,FIXTURE
    from pb_kd_session import read,checked,inventory
    path=Path(path);r=read(path);root=Path(__file__).resolve().parents[1];checked(root/SCRIPT,SCRIPT_SHA)
    if r.get('script_sha256')!=SCRIPT_SHA or r.get('passed') is not True or r.get('method')!='retry-chain-cdb-proof-v1' or any(r.get(k) is not False for k in ('kernel_connection','traffic_generated','product_started')) or [c['case'] for c in r['cases']]!=list(CASES) or any(not c['passed'] or c['exit_code'] for c in r['cases']):raise ValueError('RETRY_CHAIN_PROOF_INVALID')
    files=[path,root/SCRIPT]
    for case in CASES:
        child=path.parent/case
        if (child/'target.py').read_text()!=FIXTURE.replace('CASE',repr(case)):raise ValueError('RETRY_CHAIN_FIXTURE_DIFFERS')
        files += [child/n for n in ('target.py','commands.wdbg','setup.wdbg','stdout.txt','stderr.txt')]
    return dict(path=str(path),sha256=hashlib.sha256(path.read_bytes()).hexdigest(),files=inventory(files))
def write(root):
    root=Path(root);(root/PROFILE).write_bytes(encoded());(root/STAGE).write_bytes(b'dx @$scriptContents.pbcRegister()\n');return PROFILE_SHA
