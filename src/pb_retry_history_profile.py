"""Keep a bounded history of selected SYN observations until accepted-NBL lookup."""
import hashlib,json,re
from pathlib import Path
from pb_retry_chain_armed_profile import profile as base_profile,policy as base_policy
SCRIPT='scripts/debugger/pb_retry_history.js'
SCRIPT_SHA='47c72a600ddeaf089f8ee8d4f454fe4d431ab00e0770ade1e174ed2f58008a76'
PROFILE='scripts/debugger/pb-kd-retry-history-profile-20261021.json'
STAGE='scripts/debugger/pb-kd-retry-history-update-20261021.wdbg'
def profile():
    p=base_profile();text=(Path(__file__).resolve().parents[1]/SCRIPT).read_text()
    p.update(method='kd-retry-history-20261021-v1',script=SCRIPT,script_sha256=SCRIPT_SHA,helper_version=2,skip_snapshot_limit=8,selected_events_per_point={'2':1,'3':8,'4':1},registration='pbcRegister')
    for point,name in zip(p['points'],('CREATE','SKIP','ACCEPT')):point['action']=re.search(r"var PBC_"+name+r"_ACTION='(.*)';",text).group(1)
    p['limits'].append('Eight selected SYN observations, including possible repeated calls for the same packet; no physical packet-count claim.')
    return p
def encoded():return (json.dumps(profile(),indent=2)+'\n').encode()
PROFILE_SHA=hashlib.sha256(encoded()).hexdigest()
def policy(target=True):
    p=base_policy(target);p.update(endpoint_retry_history=True,nbl_script_sha256=SCRIPT_SHA,helper_version=2,skip_snapshot_limit=8,selected_events_per_point={'2':1,'3':8,'4':1})
    return p
def registration(profile_path,receipt_path,receipt_sha,boot):
    from pb_kd_session import read,checked,boot_identity
    p=read(checked(profile_path,PROFILE_SHA));r=read(checked(receipt_path,receipt_sha))
    if p!=profile() or r.get('method')!='target-flow-prepared-commands-v1' or r.get('profile_sha256')!=PROFILE_SHA or r.get('source')!='prepared-command-awaiting-user-attestation' or r.get('expected_disabled_ids')!=[2,3,4] or r.get('host_registration_observed') is not False or r.get('script_sha256')!=SCRIPT_SHA or boot_identity(r['boot'])!=boot_identity(boot):raise ValueError('RETRY_HISTORY_REGISTRATION_INVALID')
    return p
def parser_proof(path):
    from pb_retry_history_fixture import CASES,FIXTURE
    from pb_kd_session import read,checked,inventory
    path=Path(path);r=read(path);root=Path(__file__).resolve().parents[1];checked(root/SCRIPT,SCRIPT_SHA)
    if r.get('method')!='retry-history-cdb-proof-v1' or r.get('profile_sha256')!=PROFILE_SHA or r.get('script_sha256')!=SCRIPT_SHA or r.get('passed') is not True or any(r.get(k) is not False for k in ('kernel_connection','product_started','traffic_generated')) or [c['case'] for c in r['cases']]!=list(CASES) or any(not c['passed'] or c['exit_code'] for c in r['cases']):raise ValueError('RETRY_HISTORY_PROOF_INVALID')
    if read(path.parent/'candidate.json')!=profile():raise ValueError('RETRY_HISTORY_CANDIDATE_DIFFERS')
    files=[path,path.parent/'candidate.json',root/SCRIPT]
    for case in CASES:
        child=path.parent/case
        if (child/'target.py').read_text()!=FIXTURE.replace('CASE',repr(case)):raise ValueError('RETRY_HISTORY_FIXTURE_DIFFERS')
        files += [child/n for n in ('target.py','commands.wdbg','setup.wdbg','stdout.txt','stderr.txt')]
    return dict(path=str(path),sha256=hashlib.sha256(path.read_bytes()).hexdigest(),files=inventory(files))
def write(root):
    root=Path(root);(root/PROFILE).write_bytes(encoded());(root/STAGE).write_bytes(b'dx @$scriptContents.pbcRegister()\n');return PROFILE_SHA
