"""Exact bindings for the capped flag observer; legacy profiles remain frozen."""
import json
from pathlib import Path
from pb_kd_session import read, checked, inventory, boot_identity
from pb_prepare_kd_baseline import digest, plain

PROFILE_SHA='c1fb07110f92188237fa3a32436e30cd31fa2fd7ba8590d442241d1fca1da75a'
STAGE='scripts/debugger/pb-kd-target-flag-fresh-disabled-20261020.wdbg'
ARMED_PROFILE_SHA='ca1ecd5c335b6864259bb92a9d94dfeda0fc8bf2f655ff273cd59616cbb3f237'
ARMED_STAGE='scripts/debugger/pb-kd-target-flag-create-armed-update-20261020.wdbg'


def policy(target=True, create_armed=False):
    from pb_target_accept_plan import create_policy
    p=dict(create_policy(target,target),observer='etw+kd-target-flag',
        workload='flag-target-201-staged' if target else 'flag-four-probe',
        debugger_points=[2,3,4] if target else [2,4],
        inactive_debugger_points=[] if target else [3],
        automatic_debugger_control=False,automatic_debugger_disable=True,
        registration_confirmation='user-run-argument-no-independent-host-proof',
        raw_hit_limit_per_point=16,max_total_raw_hits=48 if target else 32,
        selected_snapshots_per_point=1,stack_count_max=1 if target else 0)
    if create_armed:
        if not target:raise ValueError('FLAG_CREATE_ARMED_REQUIRES_TARGET')
        p.update(host_enable_debugger_points=[2,4],automatic_debugger_enable_after_create=[3],
                 automatic_enable_authorization='user-explicit-exception-20261020')
    return p


def registration(profile_path,receipt_path,receipt_sha,boot):
    armed=digest(Path(profile_path))==ARMED_PROFILE_SHA
    sha=ARMED_PROFILE_SHA if armed else PROFILE_SHA
    p=read(checked(profile_path,sha));r=read(checked(receipt_path,receipt_sha))
    if (p['method']!=('kd-target-flag-create-armed-20261020-v1' if armed else 'kd-target-flag-disabled-candidate-20261020-v1') or p['active_point_ids']!=[] or
        p['registered_point_ids']!=[2,3,4] or
        p['proposed_active_point_ids']!=[2,3,4] or p['raw_hit_limit_per_point']!=16 or
        not p['automatic_disable'] or p['automatic_enable']!=armed):raise ValueError('FLAG_PROFILE_INVALID')
    if armed and (p['host_enable_point_ids']!=[2,4] or p['automatic_enable_point_ids']!=[3]):
        raise ValueError('FLAG_CREATE_ARMED_PROFILE_INVALID')
    if (r['method']!='target-flow-prepared-commands-v1' or
        r['source']!='prepared-command-awaiting-user-attestation' or
        r['profile_sha256']!=sha or r['expected_disabled_ids']!=[2,3,4] or
        r['host_registration_observed'] is not False or
        boot_identity(r['boot'])!=boot_identity(boot)):raise ValueError('FLAG_REGISTRATION_OR_BOOT_DIFFERS')
    return p


def parser_proof(path,create_armed=False):
    if create_armed:return armed_parser_proof(path)
    path=plain(Path(path));r=read(path)
    if (r.get('method')!='cdb-safe-bounded-flag-candidate-v1' or
        any(r.get(k) is not False for k in ('kernel_connection','product_started','traffic_generated')) or
        r.get('passed') is not True or [c.get('name') for c in r.get('cases',[])]!=
        ['selected','nonselected','unreadable','limit'] or
        any(c.get('exit_code')!=0 or c.get('passed') is not True or c.get('checks')!=[True]*3 or
            c.get('disable_checks')!=[True]*3 for c in r['cases'])):raise ValueError('FLAG_PARSER_PROOF_INVALID')
    # Proof includes its exact fixture actions. Refuse a different candidate.
    candidate=path.parent/'candidate.json'
    runtime=Path(__file__).resolve().parents[1]/'scripts/debugger/pb-kd-target-flag-disabled-profile-20261020.json'
    if (digest(candidate)!='9c04426bc904c7df49aafab526f1a15b7e5f0719697f4a81b9d44d110edc66c4' or
        read(candidate)['points']!=read(checked(runtime,PROFILE_SHA))['points']):raise ValueError('FLAG_PARSER_PROFILE_DIFFERS')
    files=[path,candidate]+[path.parent/(c['name']+s) for c in r['cases'] for s in ('.wdbg','.stdout.txt','.stderr.txt')]
    return dict(path=str(path),sha256=digest(path),files=inventory(files))


def armed_parser_proof(path):
    path=plain(Path(path));r=read(path)
    names=['selected','nonselected','unreadable','limit']
    expected=[{'2':True,'3':False,'4':False},{'2':False,'3':True,'4':False},
              {'2':True,'3':True,'4':True},{'2':True,'3':True,'4':True}]
    if (r.get('method')!='cdb-create-armed-flag-candidate-v1' or r.get('passed') is not True or
        any(r.get(k) is not False for k in ('kernel_connection','product_started','traffic_generated','runtime_authorized')) or
        [c.get('name') for c in r.get('cases',[])]!=names or
        any(c.get('passed') is not True or c.get('values_verified') is not True or c.get('disabled')!=state
            for c,state in zip(r['cases'],expected)) or r.get('all_actions_proof')!='all-actions/parser-check.json'):
        raise ValueError('FLAG_ARMED_PARSER_PROOF_INVALID')
    full=path.parent/'all-actions/parser-check.json';f=read(full)
    if (f.get('method')!='cdb-safe-bounded-flag-candidate-v1' or f.get('passed') is not True or
        any(f.get(k) is not False for k in ('kernel_connection','product_started','traffic_generated')) or
        [c.get('name') for c in f.get('cases',[])]!=names or
        any(c.get('exit_code')!=0 or c.get('passed') is not True or c.get('checks')!=[True]*3 or
            c.get('disable_checks')!=[True]*3 for c in f['cases'])):
        raise ValueError('FLAG_ARMED_ALL_ACTIONS_PROOF_INVALID')
    runtime=Path(__file__).resolve().parents[1]/'scripts/debugger/pb-kd-target-flag-create-armed-profile-20261020.json'
    candidate=path.parent/'candidate.json';full_candidate=full.parent/'candidate.json'
    if read(candidate)['points']!=read(checked(runtime,ARMED_PROFILE_SHA))['points'] or digest(candidate)!=digest(full_candidate):
        raise ValueError('FLAG_ARMED_PARSER_PROFILE_DIFFERS')
    files=[path,candidate,full,full_candidate]
    files += [parent/(name+suffix) for parent in (path.parent,full.parent) for name in names
              for suffix in ('.wdbg','.stdout.txt','.stderr.txt')]
    return dict(path=str(path),sha256=digest(path),files=inventory(files))
