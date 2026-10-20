"""Selected retry NBL snapshot candidate. No product execution in this module."""
import hashlib
import json
from pathlib import Path
from pb_endpoint_send_gate import create_action as source_create, read_action as source_read
from pb_endpoint_watch_candidate import CLEAR, quoted

PROFILE='scripts/debugger/pb-kd-selected-nbl-context-profile-20261020.json'
STAGE='scripts/debugger/pb-kd-selected-nbl-context-update-20261020.wdbg'
SCRIPT='scripts/debugger/pb_nbl_context.js'
SCRIPT_SHA='a596999c104cbb049dfa73fa7602dd047a30bd5b0248a05e23c5ad5a46576236'
PROFILE_SHA='88403355b93398e39a9068305c720e90ad84dc9f54c67f918b49abbe731b3398'


def read_action():
    original=source_read()
    old='.if ((@$t7 & 0x200000) != 0) { '+CLEAR+' }'
    new=('.if ((@$t7 & 0x200000) != 0) { .if (@$t17 == 1) { r @$t19 = 1; '
         'dx @$scriptContents.pbNblArm(@rbp,@$t1,@$t2); }; }')
    if original.count(old)!=1:raise ValueError('NBL_SOURCE_ACTION_CHANGED')
    return ('r @$t19 = 0; '+original.replace(old,new).replace(
        '(@$t8 != 0) and (@$t4 >= 0x40)',
        '(@$t19 == 0) and (@$t8 != 0) and (@$t4 >= 0x40)'))


def create_action():
    original=source_create(True)
    old=quoted(source_read())
    if original.count(old)!=1:raise ValueError('NBL_SOURCE_CREATE_CHANGED')
    return original.replace(old,quoted(read_action()))


def profile():
    return dict(method='kd-selected-nbl-context-20261020-v1',
        registered_point_ids=[2,4],dynamic_point_ids=[3],active_point_ids=[],
        host_enable_point_ids=[2],automatic_enable_point_ids=[3],inactive_point_ids=[4],
        script=SCRIPT,script_sha256=SCRIPT_SHA,initialization='pbNblInitKernel',
        model_required=0,source_watch=dict(access='r',size=4,offset=0x30,limit=64),
        nbl_watch=dict(access='r',size=8,offset=0xe0,limit=16),
        max_total_raw_hits=96,list_node_limit=8,
        points=[dict(id=2,target='tcpip!AlepCreateRedirectRecord+0x396',action=create_action()),
                dict(id=3,target='dynamic-selected-source-then-selected-nbl',action=read_action())],
        automatic_disable=True,automatic_enable=True,
        recovery=['bd2','dx @$scriptContents.pbNblStop()',CLEAR,'bd4','g'],
        limits=['No global ACCEPT point; receive is selected by caller frames and tuple.',
                'No target writes or target function calls.',
                'Missing receive, changed identity, unreadable data or a limit means INCOMPLETE.',
                'No complete NBL lifetime, clone coverage or root cause verdict.'])


def write(root):
    root=Path(root)
    raw=(json.dumps(profile(),indent=2)+'\n').encode('utf-8')
    (root/PROFILE).write_bytes(raw)
    commands=['bd4','bc2','bp2 tcpip!AlepCreateRedirectRecord+0x396 '+quoted(create_action()),'bd2']
    if max(map(len,commands))>=4096:raise ValueError('NBL_COMMAND_TOO_LONG')
    (root/STAGE).write_bytes(('\n'.join(commands)+'\n').encode('ascii'))
    return hashlib.sha256(raw).hexdigest()


def policy(target=True):
    from pb_endpoint_send_gate import policy as base
    if not target:raise ValueError('NBL_CONTEXT_REQUIRES_TARGET')
    p=base(True,0)
    p.update(endpoint_nbl_context=True,nbl_script_sha256=SCRIPT_SHA,nbl_model=0,
        max_total_raw_hits=96,raw_hit_limits_per_point={'2':16,'3':80},
        watch_field='selected-source-endpoint+0x30-then-selected-nbl+0xe0',
        source_watch_limit=64,nbl_watch_limit=16,nbl_watch_size=8,list_node_limit=8,
        selected_snapshot_limits_per_point={'2':1,'3':6})
    return p


def registration(profile_path,receipt_path,receipt_sha,boot):
    from pb_kd_session import read,checked,boot_identity
    p=read(checked(profile_path,PROFILE_SHA));r=read(checked(receipt_path,receipt_sha))
    if (p!=profile() or r.get('method')!='target-flow-prepared-commands-v1' or
        r.get('source')!='prepared-command-awaiting-user-attestation' or
        r.get('profile_sha256')!=PROFILE_SHA or r.get('expected_disabled_ids')!=[2,4] or
        r.get('expected_absent_ids')!=[3] or r.get('host_registration_observed') is not False or
        r.get('script_sha256')!=SCRIPT_SHA or r.get('script_model')!=0 or
        boot_identity(r['boot'])!=boot_identity(boot)):
        raise ValueError('NBL_REGISTRATION_DIFFERS')
    return p


def parser_proof(path):
    from pb_kd_session import read,checked,inventory
    from pb_prepare_kd_baseline import plain,digest
    from pb_selected_nbl_fixture import CASES,source
    from pb_nbl_context_fixture import CASES as helper_cases
    from pb_endpoint_send_gate_fixture import transform
    path=plain(Path(path));r=read(path)
    if (r.get('method')!='selected-nbl-integrated-cdb-proof-v1' or r.get('passed') is not True or
        r.get('profile_sha256')!=PROFILE_SHA or r.get('script_sha256')!=SCRIPT_SHA or
        any(r.get(k) is not False for k in ('kernel_connection','product_started','traffic_generated')) or
        any(r.get(k) is not True for k in ('guard_expressions_replaced_with_true','kernel_thread_replaced_with_tid','gate_symbol_replaced_with_fixture_address')) or
        [c['case'] for c in r['cases']]!=list(CASES) or any(c.get('passed') is not True or c.get('exit_code')!=0 for c in r['cases'])):
        raise ValueError('NBL_INTEGRATION_PROOF_INVALID')
    root=Path(__file__).resolve().parents[1];checked(root/SCRIPT,SCRIPT_SHA)
    checked(path.parent/'candidate.json',PROFILE_SHA)
    binding=path.parent/'helper-proof-binding.json';b=read(binding)
    helper=checked(b['path'],b['sha256']);h=read(helper)
    if (h.get('method')!='selected-nbl-js-cdb-proof-v1' or h.get('passed') is not True or h.get('script_sha256')!=SCRIPT_SHA or
        any(h.get(k) is not False for k in ('kernel_connection','product_started','traffic_generated')) or
        any(h.get(k) is not True for k in ('real_cpu_stack_frames','real_memory_watch','real_watch_replacement_from_callback','real_js_provider')) or
        [c['case'] for c in h['cases']]!=list(helper_cases) or any(c.get('passed') is not True or c.get('exit_code')!=0 for c in h['cases'])):
        raise ValueError('NBL_HELPER_PROOF_INVALID')
    files=[path,path.parent/'candidate.json',binding,helper,root/SCRIPT]
    for case in CASES:
        child=path.parent/case
        if (child/'target.py').read_text()!=source(case):raise ValueError('NBL_PROOF_FIXTURE_DIFFERS')
        expected='bp2 (@rsi+0x1800) '+quoted(transform(create_action()))
        if (child/'setup.wdbg').read_text().splitlines()[-4:]!=[expected,'bd2','be2','g']:raise ValueError('NBL_PROOF_ACTION_DIFFERS')
        files += [child/n for n in ('target.py','setup.wdbg','proof.wdbg','stdout.txt','stderr.txt')]
    for case in helper_cases:
        files += [helper.parent/case/n for n in ('target.py','setup.wdbg','proof.wdbg','stdout.txt','stderr.txt')]
    return dict(path=str(path),sha256=digest(path),files=inventory(files))
