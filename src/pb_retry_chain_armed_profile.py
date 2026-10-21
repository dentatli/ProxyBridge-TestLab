"""Cold-start the existing chain helper; only CREATE is host-enabled."""
import hashlib,json
from pathlib import Path
from pb_retry_chain_profile import SCRIPT,SCRIPT_SHA,profile as base_profile,policy as base_policy
PROFILE='scripts/debugger/pb-kd-retry-chain-create-armed-profile-20261021.json'
STAGE='scripts/debugger/pb-kd-retry-chain-create-armed-update-20261021.wdbg'
def create_action():
    old=base_profile()['points'][0]['action'];needle='{ !pbccreate @r14, @rdi, @rax; }'
    if old.count(needle)!=1:raise ValueError('CREATE_ACTION_SHAPE_DIFFERS')
    # Kernel remains halted between be3/be4 and validation. Any helper validation
    # failure executes pbcStop(), disabling all three before gc resumes it.
    return old.replace(needle,'{ be3; be4; !pbccreate @r14, @rdi, @rax; }')
def profile():
    p=base_profile();p.update(method='kd-retry-chain-create-armed-20261021-v1',host_enable_point_ids=[2],automatic_enable=True,automatic_enable_point_ids=[3,4],registration='manual-existing-helper-plus-create-action')
    p['points'][0]['action']=create_action()
    p['limits'].append('SKIP and ACCEPT stay disabled until the selected CREATE tuple; unchanged helper validation can disable them on error.')
    return p
def encoded():return (json.dumps(profile(),indent=2)+'\n').encode()
PROFILE_SHA=hashlib.sha256(encoded()).hexdigest()
def policy(target=True):
    p=base_policy(target);p.update(retry_chain_create_armed=True,host_enable_debugger_points=[2],automatic_debugger_enable_after_create=[3,4],automatic_enable_authorization='user-explicit-exception-20261020')
    return p
def registration(profile_path,receipt_path,receipt_sha,boot):
    from pb_kd_session import read,checked,boot_identity
    p=read(checked(profile_path,PROFILE_SHA));r=read(checked(receipt_path,receipt_sha))
    if p!=profile() or r.get('method')!='target-flow-prepared-commands-v1' or r.get('profile_sha256')!=PROFILE_SHA or r.get('source')!='prepared-command-awaiting-user-attestation' or r.get('expected_disabled_ids')!=[2,3,4] or r.get('host_registration_observed') is not False or r.get('script_sha256')!=SCRIPT_SHA or boot_identity(r['boot'])!=boot_identity(boot):raise ValueError('RETRY_CHAIN_ARMED_REGISTRATION_INVALID')
    return p
def parser_proof(path):
    from pb_retry_chain_armed_fixture import CASES,FIXTURE
    from pb_kd_session import read,checked,inventory
    path=Path(path);r=read(path);root=Path(__file__).resolve().parents[1];checked(root/SCRIPT,SCRIPT_SHA)
    if r.get('method')!='retry-chain-create-armed-cdb-proof-v1' or r.get('profile_sha256')!=PROFILE_SHA or r.get('passed') is not True or r.get('script_sha256')!=SCRIPT_SHA or any(r.get(k) is not False for k in ('kernel_connection','product_started','traffic_generated')) or [c['case'] for c in r['cases']]!=list(CASES) or any(not c['passed'] or c['exit_code'] for c in r['cases']):raise ValueError('RETRY_CHAIN_ARMED_PROOF_INVALID')
    if read(path.parent/'candidate.json')!=profile():raise ValueError('RETRY_CHAIN_ARMED_CANDIDATE_DIFFERS')
    files=[path,path.parent/'candidate.json',root/SCRIPT]
    for case in CASES:
        child=path.parent/case
        if (child/'target.py').read_text()!=FIXTURE.replace('CASE',repr(case)):raise ValueError('RETRY_CHAIN_ARMED_FIXTURE_DIFFERS')
        files += [child/n for n in ('target.py','commands.wdbg','setup.wdbg','stdout.txt','stderr.txt')]
    return dict(path=str(path),sha256=hashlib.sha256(path.read_bytes()).hexdigest(),files=inventory(files))
def write(root):
    root=Path(root);(root/PROFILE).write_bytes(encoded())
    text='bp2 tcpip!AlepCreateRedirectRecord+0x396 '+json.dumps(create_action())+'\nbd2\nbd3\nbd4\n'
    (root/STAGE).write_bytes(text.encode());return PROFILE_SHA
