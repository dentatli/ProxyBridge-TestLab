"""Exact bindings for the capped flag observer; legacy profiles remain frozen."""
import json
from pathlib import Path
from pb_kd_session import read, checked, inventory, boot_identity
from pb_prepare_kd_baseline import digest, plain

PROFILE_SHA='c1fb07110f92188237fa3a32436e30cd31fa2fd7ba8590d442241d1fca1da75a'
STAGE='scripts/debugger/pb-kd-target-flag-fresh-disabled-20261020.wdbg'


def policy(target=True):
    from pb_target_accept_plan import create_policy
    p=dict(create_policy(target,target),observer='etw+kd-target-flag',
        workload='flag-target-201-staged' if target else 'flag-four-probe',
        debugger_points=[2,3,4] if target else [2,4],
        inactive_debugger_points=[] if target else [3],
        automatic_debugger_control=False,automatic_debugger_disable=True,
        registration_confirmation='user-run-argument-no-independent-host-proof',
        raw_hit_limit_per_point=16,max_total_raw_hits=48 if target else 32,
        selected_snapshots_per_point=1,stack_count_max=1 if target else 0)
    return p


def registration(profile_path,receipt_path,receipt_sha,boot):
    p=read(checked(profile_path,PROFILE_SHA));r=read(checked(receipt_path,receipt_sha))
    if (p['method']!='kd-target-flag-disabled-candidate-20261020-v1' or p['active_point_ids']!=[] or
        p['registered_point_ids']!=[2,3,4] or
        p['proposed_active_point_ids']!=[2,3,4] or p['raw_hit_limit_per_point']!=16 or
        not p['automatic_disable'] or p['automatic_enable']):raise ValueError('FLAG_PROFILE_INVALID')
    if (r['method']!='target-flow-prepared-commands-v1' or
        r['source']!='prepared-command-awaiting-user-attestation' or
        r['profile_sha256']!=PROFILE_SHA or r['expected_disabled_ids']!=[2,3,4] or
        r['host_registration_observed'] is not False or
        boot_identity(r['boot'])!=boot_identity(boot)):raise ValueError('FLAG_REGISTRATION_OR_BOOT_DIFFERS')
    return p


def parser_proof(path):
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
