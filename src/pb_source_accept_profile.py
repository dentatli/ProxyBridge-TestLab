"""Compare source-record references with accepted-NBL state in one stopped snapshot."""
import hashlib,json
from pathlib import Path
from pb_retry_history_profile import SCRIPT,SCRIPT_SHA,profile as base_profile,policy as base_policy
PROFILE='scripts/debugger/pb-kd-source-accept-profile-20261021.json'
STAGE='scripts/debugger/pb-kd-source-accept-update-20261021.wdbg'
SOURCE_ACTION=(
    '.if (($vvalid(@$t10+0x30,4) == 1) and ($vvalid(@$t10+0x1c0,8) == 1)) { '
    '.if (poi(@$t10+0x1c0) == 0) { '
    '.printf "PBC SOURCE source_ep=%p expected_record=%p record_now=0 context=0 size=0 flags30=%x accept_ep=%p accept_nbl=%p\\n", @$t10, @$t11, dwo(@$t10+0x30), @rdi, @rbx; '
    '} .else { .if ($vvalid(poi(@$t10+0x1c0)+0x1e0,0x10) == 1) { '
    '.printf "PBC SOURCE source_ep=%p expected_record=%p record_now=%p context=%p size=%I64x flags30=%x accept_ep=%p accept_nbl=%p\\n", @$t10, @$t11, poi(@$t10+0x1c0), poi(poi(@$t10+0x1c0)+0x1e0), poi(poi(@$t10+0x1c0)+0x1e8), dwo(@$t10+0x30), @rdi, @rbx; '
    '} .else { .printf "PBC SOURCE_UNREADABLE reason=RECORD\\n"; } } '
    '} .else { .printf "PBC SOURCE_UNREADABLE reason=EP\\n"; }; '
)
def profile():
    p=base_profile();p.update(method='kd-source-accept-20261021-v1',proposed_active_point_ids=[2,4],inactive_point_ids=[3],automatic_enable_point_ids=[4],registration='manual-existing-helper-source-accept-actions',raw_hit_limits_per_point={'2':32,'4':512},max_total_raw_hits=544,selected_events_per_point={'2':1,'3':0,'4':1})
    p.pop('skip_snapshot_limit',None)
    a=p['points'][0]['action'];assert a.count('be3; be4;')==1
    p['points'][0]['action']=a.replace('be3; be4;','r @$t11 = @rax; be4;')
    a=p['points'][2]['action'];call='!pbcaccept @rbx, @rbp, @rdi, @eax;';assert a.count(call)==1
    p['points'][2]['action']=a.replace(call,SOURCE_ACTION+call)
    p['limits']=['No SEND breakpoint is enabled. Point3 remains registered only for unchanged helper cleanup.',
        'Source references and accepted NBL are read during the same debugger stop; pointers do not prove allocation lifetime.',
        'No instruction-level proof of propagation or independent kernel-to-SOCKET join.']
    return p
def encoded():return (json.dumps(profile(),indent=2)+'\n').encode()
PROFILE_SHA=hashlib.sha256(encoded()).hexdigest()
def policy(target=True):
    p=base_policy(target)
    for k in ('endpoint_retry_history','retry_chain_create_armed','skip_snapshot_limit'):p.pop(k,None)
    p.update(source_accept_snapshot=True,debugger_points=[2,4],inactive_debugger_points=[3],automatic_debugger_enable_after_create=[4],raw_hit_limits_per_point={'2':32,'4':512},max_total_raw_hits=544,selected_events_per_point={'2':1,'3':0,'4':1})
    return p
def registration(profile_path,receipt_path,receipt_sha,boot):
    from pb_kd_session import read,checked,boot_identity
    p=read(checked(profile_path,PROFILE_SHA));r=read(checked(receipt_path,receipt_sha))
    if p!=profile() or r.get('method')!='target-flow-prepared-commands-v1' or r.get('profile_sha256')!=PROFILE_SHA or r.get('source')!='prepared-command-awaiting-user-attestation' or r.get('expected_disabled_ids')!=[2,3,4] or r.get('host_registration_observed') is not False or r.get('script_sha256')!=SCRIPT_SHA or boot_identity(r['boot'])!=boot_identity(boot):raise ValueError('SOURCE_ACCEPT_REGISTRATION_INVALID')
    return p
def parser_proof(path):
    from pb_source_accept_fixture import CASES,FIXTURE
    from pb_kd_session import read,checked,inventory
    path=Path(path);r=read(path);root=Path(__file__).resolve().parents[1];checked(root/SCRIPT,SCRIPT_SHA)
    if r.get('method')!='source-accept-cdb-proof-v1' or r.get('profile_sha256')!=PROFILE_SHA or r.get('script_sha256')!=SCRIPT_SHA or r.get('passed') is not True or any(r.get(k) is not False for k in ('kernel_connection','product_started','traffic_generated')) or [c['case'] for c in r['cases']]!=list(CASES) or any(not c['passed'] or c['exit_code'] for c in r['cases']):raise ValueError('SOURCE_ACCEPT_PROOF_INVALID')
    if read(path.parent/'candidate.json')!=profile():raise ValueError('SOURCE_ACCEPT_CANDIDATE_DIFFERS')
    files=[path,path.parent/'candidate.json',root/SCRIPT]
    for case in CASES:
        child=path.parent/case
        if (child/'target.py').read_text()!=FIXTURE.replace('CASE',repr(case)):raise ValueError('SOURCE_ACCEPT_FIXTURE_DIFFERS')
        files += [child/n for n in ('target.py','commands.wdbg','setup.wdbg','stdout.txt','stderr.txt')]
    return dict(path=str(path),sha256=hashlib.sha256(path.read_bytes()).hexdigest(),files=inventory(files))
def write(root):
    root=Path(root);(root/PROFILE).write_bytes(encoded());p=profile()
    (root/STAGE).write_bytes(('\n'.join('bp'+str(v['id'])+' '+v['target']+' '+json.dumps(v['action'])+'\nbd'+str(v['id']) for v in (p['points'][0],p['points'][2]))+'\nbd3\n').encode());return PROFILE_SHA
