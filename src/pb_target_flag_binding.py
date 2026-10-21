"""Exact bindings for the capped flag observer; legacy profiles remain frozen."""
import json
from pathlib import Path
from pb_kd_session import read, checked, inventory, boot_identity
from pb_prepare_kd_baseline import digest, plain

PROFILE_SHA='c1fb07110f92188237fa3a32436e30cd31fa2fd7ba8590d442241d1fca1da75a'
STAGE='scripts/debugger/pb-kd-target-flag-fresh-disabled-20261020.wdbg'
ARMED_PROFILE_SHA='ca1ecd5c335b6864259bb92a9d94dfeda0fc8bf2f655ff273cd59616cbb3f237'
ARMED_STAGE='scripts/debugger/pb-kd-target-flag-create-armed-update-20261020.wdbg'
ACCEPT64_PROFILE_SHA='748d942dd4252dfc79c7461f44cabeebcbeb0151db171d0a964c93eb41317687'
ACCEPT64_STAGE='scripts/debugger/pb-kd-target-flag-create-armed-accept64-update-20261020.wdbg'
HEALTHY_PROFILE_SHA='5487823dc3ffd10ce8fbf089de15932d33ee6329035dc09b69963c48c7fefcb7'
HEALTHY_STAGE='scripts/debugger/pb-kd-target-flag-healthy-setter-update-20261020.wdbg'


def profile_sha(create_armed=False,accept64=False,healthy=False,endpoint_watch=False):
    if endpoint_watch=='chainarmed':
        from pb_retry_chain_armed_profile import PROFILE_SHA as sha
        return sha
    if endpoint_watch=='chain':
        from pb_retry_chain_profile import PROFILE_SHA as sha
        return sha
    if endpoint_watch=='pair':
        from pb_accept_pair_profile import PROFILE_SHA as sha
        return sha
    if endpoint_watch=='epochs':
        from pb_retry_epochs_profile import PROFILE_SHA as sha
        return sha
    if endpoint_watch=='nbl512':
        from pb_selected_nbl512_profile import PROFILE_SHA as nbl_sha
        return nbl_sha
    if endpoint_watch=='nbl64':
        from pb_selected_nbl64_profile import PROFILE_SHA as nbl_sha
        return nbl_sha
    if endpoint_watch=='nbl':
        from pb_selected_nbl_profile import PROFILE_SHA as nbl_sha
        return nbl_sha
    if endpoint_watch in ('send','send256','sendnative'):
        from pb_endpoint_send_gate import PROFILE_SHA as send_sha,ACCEPT256_SHA,NATIVE_SHA
        return NATIVE_SHA if endpoint_watch=='sendnative' else ACCEPT256_SHA if endpoint_watch=='send256' else send_sha
    if endpoint_watch=='packet':
        from pb_endpoint_packet_watch import PROFILE_SHA as packet_sha
        return packet_sha
    if endpoint_watch:
        from pb_endpoint_watch_profile import PROFILE_SHA as watch_sha
        return watch_sha
    return HEALTHY_PROFILE_SHA if healthy else ACCEPT64_PROFILE_SHA if accept64 else ARMED_PROFILE_SHA if create_armed else PROFILE_SHA


def policy(target=True, create_armed=False,accept64=False,healthy=False,endpoint_watch=False):
    if endpoint_watch:
        if not (create_armed and accept64) or healthy!=(not target):raise ValueError('ENDPOINT_WATCH_POLICY_INVALID')
        if endpoint_watch=='chainarmed':
            from pb_retry_chain_armed_profile import policy as chain_policy
            return chain_policy(target)
        if endpoint_watch=='chain':
            from pb_retry_chain_profile import policy as chain_policy
            return chain_policy(target)
        if endpoint_watch=='pair':
            from pb_accept_pair_profile import policy as pair_policy
            return pair_policy(target)
        if endpoint_watch=='epochs':
            from pb_retry_epochs_profile import policy as per_send_policy
            return per_send_policy(target)
        if endpoint_watch=='nbl512':
            from pb_selected_nbl512_profile import policy as nbl_policy
            return nbl_policy(target)
        if endpoint_watch=='nbl64':
            from pb_selected_nbl64_profile import policy as nbl_policy
            return nbl_policy(target)
        if endpoint_watch=='nbl':
            from pb_selected_nbl_profile import policy as nbl_policy
            return nbl_policy(target)
        if endpoint_watch in ('send','send256','sendnative'):
            from pb_endpoint_send_gate import policy as send_policy
            return send_policy(target,0 if endpoint_watch=='sendnative' else 256 if endpoint_watch=='send256' else 64)
        if endpoint_watch=='packet':
            from pb_endpoint_packet_watch import policy as packet_policy
            return packet_policy(target)
        from pb_endpoint_watch_profile import policy as watch_policy
        return watch_policy(target)
    from pb_target_accept_plan import create_policy
    p=dict(create_policy(target,target),observer='etw+kd-target-flag',
        workload='flag-target-201-staged' if target else 'flag-four-probe',
        debugger_points=[2,3,4] if target else [2,4],
        inactive_debugger_points=[] if target else [3],
        automatic_debugger_control=False,automatic_debugger_disable=True,
        registration_confirmation='user-run-argument-no-independent-host-proof',
        raw_hit_limit_per_point=16,max_total_raw_hits=48 if target else 32,
        selected_snapshots_per_point=1,stack_count_max=1 if target else 0)
    if healthy:
        if target or not (create_armed and accept64):raise ValueError('FLAG_HEALTHY_REQUIRES_ARMED_FOUR')
        p.update(healthy_setter_probe=True,debugger_points=[2,3,4],inactive_debugger_points=[],stack_count_max=1)
    if create_armed:
        if not (target or healthy):raise ValueError('FLAG_CREATE_ARMED_REQUIRES_TARGET')
        p.update(host_enable_debugger_points=[2,4],automatic_debugger_enable_after_create=[3],
                 automatic_enable_authorization='user-explicit-exception-20261020')
    if accept64:
        if not create_armed:raise ValueError('FLAG_ACCEPT64_REQUIRES_CREATE_ARMED')
        p.update(raw_hit_limits_per_point={'2':16,'3':16,'4':64},max_total_raw_hits=96)
        del p['raw_hit_limit_per_point']
    return p


def registration(profile_path,receipt_path,receipt_sha,boot):
    from pb_retry_chain_armed_profile import PROFILE_SHA as chain_armed_sha,registration as chain_armed_registration
    if digest(Path(profile_path))==chain_armed_sha:return chain_armed_registration(profile_path,receipt_path,receipt_sha,boot)
    from pb_retry_chain_profile import PROFILE_SHA as chain_sha,registration as chain_registration
    if digest(Path(profile_path))==chain_sha:return chain_registration(profile_path,receipt_path,receipt_sha,boot)
    from pb_accept_pair_profile import PROFILE_SHA as pair_sha,registration as pair_registration
    if digest(Path(profile_path))==pair_sha:return pair_registration(profile_path,receipt_path,receipt_sha,boot)
    from pb_retry_epochs_profile import PROFILE_SHA as epochs_sha,registration as epochs_registration
    if digest(Path(profile_path))==epochs_sha:return epochs_registration(profile_path,receipt_path,receipt_sha,boot)
    from pb_selected_nbl512_profile import PROFILE_SHA as nbl512_sha,registration as nbl512_registration
    if digest(Path(profile_path))==nbl512_sha:return nbl512_registration(profile_path,receipt_path,receipt_sha,boot)
    from pb_selected_nbl64_profile import PROFILE_SHA as nbl64_sha,registration as nbl64_registration
    if digest(Path(profile_path))==nbl64_sha:return nbl64_registration(profile_path,receipt_path,receipt_sha,boot)
    from pb_selected_nbl_profile import PROFILE_SHA as nbl_sha,registration as nbl_registration
    if digest(Path(profile_path))==nbl_sha:return nbl_registration(profile_path,receipt_path,receipt_sha,boot)
    from pb_endpoint_send_gate import PROFILE_SHA as send_sha,ACCEPT256_SHA,NATIVE_SHA,registration as send_registration
    if digest(Path(profile_path)) in (send_sha,ACCEPT256_SHA,NATIVE_SHA):return send_registration(profile_path,receipt_path,receipt_sha,boot)
    from pb_endpoint_packet_watch import PROFILE_SHA as packet_sha,registration as packet_registration
    if digest(Path(profile_path))==packet_sha:return packet_registration(profile_path,receipt_path,receipt_sha,boot)
    from pb_endpoint_watch_profile import PROFILE_SHA as watch_sha,registration as watch_registration
    if digest(Path(profile_path))==watch_sha:return watch_registration(profile_path,receipt_path,receipt_sha,boot)
    healthy=digest(Path(profile_path))==HEALTHY_PROFILE_SHA
    accept64=healthy or digest(Path(profile_path))==ACCEPT64_PROFILE_SHA
    armed=accept64 or digest(Path(profile_path))==ARMED_PROFILE_SHA
    sha=profile_sha(armed,accept64,healthy)
    p=read(checked(profile_path,sha));r=read(checked(receipt_path,receipt_sha))
    if (p['method']!=('kd-target-flag-healthy-setter-20261020-v1' if healthy else 'kd-target-flag-create-armed-accept64-20261020-v1' if accept64 else 'kd-target-flag-create-armed-20261020-v1' if armed else 'kd-target-flag-disabled-candidate-20261020-v1') or p['active_point_ids']!=[] or
        p['registered_point_ids']!=[2,3,4] or
        p['proposed_active_point_ids']!=[2,3,4] or
        (p.get('raw_hit_limits_per_point')!={'2':16,'3':16,'4':64} if accept64 else p.get('raw_hit_limit_per_point')!=16) or
        not p['automatic_disable'] or p['automatic_enable']!=armed):raise ValueError('FLAG_PROFILE_INVALID')
    if armed and (p['host_enable_point_ids']!=[2,4] or p['automatic_enable_point_ids']!=[3]):
        raise ValueError('FLAG_CREATE_ARMED_PROFILE_INVALID')
    if (r['method']!='target-flow-prepared-commands-v1' or
        r['source']!='prepared-command-awaiting-user-attestation' or
        r['profile_sha256']!=sha or r['expected_disabled_ids']!=[2,3,4] or
        r['host_registration_observed'] is not False or
        boot_identity(r['boot'])!=boot_identity(boot)):raise ValueError('FLAG_REGISTRATION_OR_BOOT_DIFFERS')
    return p


def parser_proof(path,create_armed=False,accept64=False,healthy=False,endpoint_watch=False):
    if endpoint_watch=='chainarmed':
        from pb_retry_chain_armed_profile import parser_proof as chain_proof
        return chain_proof(path)
    if endpoint_watch=='chain':
        from pb_retry_chain_profile import parser_proof as chain_proof
        return chain_proof(path)
    if endpoint_watch=='pair':
        from pb_accept_pair_profile import parser_proof as pair_proof
        return pair_proof(path)
    if endpoint_watch=='epochs':
        from pb_retry_epochs_profile import parser_proof as per_send_proof
        return per_send_proof(path)
    if endpoint_watch=='nbl512':
        from pb_selected_nbl512_profile import parser_proof as nbl_proof
        return nbl_proof(path)
    if endpoint_watch=='nbl64':
        from pb_selected_nbl64_profile import parser_proof as nbl_proof
        return nbl_proof(path)
    if endpoint_watch=='nbl':
        from pb_selected_nbl_profile import parser_proof as nbl_proof
        return nbl_proof(path)
    if endpoint_watch in ('send','send256','sendnative'):
        from pb_endpoint_send_gate_fixture import parser_proof as send_proof
        return send_proof(path,0 if endpoint_watch=='sendnative' else 256 if endpoint_watch=='send256' else 64)
    if endpoint_watch=='packet':
        from pb_endpoint_packet_watch import parser_proof as packet_proof
        return packet_proof(path)
    if endpoint_watch:
        from pb_endpoint_watch_profile import parser_proof as watch_proof
        return watch_proof(path)
    if healthy and not (create_armed and accept64):raise ValueError('FLAG_HEALTHY_REQUIRES_ARMED_FOUR')
    if accept64 and not create_armed:raise ValueError('FLAG_ACCEPT64_REQUIRES_CREATE_ARMED')
    if create_armed:return armed_parser_proof(path,accept64,healthy)
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


def armed_parser_proof(path,accept64=False,healthy=False):
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
    runtime=Path(__file__).resolve().parents[1]/('scripts/debugger/pb-kd-target-flag-healthy-setter-profile-20261020.json' if healthy else 'scripts/debugger/pb-kd-target-flag-create-armed-accept64-profile-20261020.json' if accept64 else 'scripts/debugger/pb-kd-target-flag-create-armed-profile-20261020.json')
    candidate=path.parent/'candidate.json';full_candidate=full.parent/'candidate.json'
    if read(candidate)['points']!=read(checked(runtime,profile_sha(True,accept64,healthy)))['points'] or digest(candidate)!=digest(full_candidate):
        raise ValueError('FLAG_ARMED_PARSER_PROFILE_DIFFERS')
    files=[path,candidate,full,full_candidate]
    files += [parent/(name+suffix) for parent in (path.parent,full.parent) for name in names
              for suffix in ('.wdbg','.stdout.txt','.stderr.txt')]
    if accept64:
        if r.get('accept64_boundary_checks')!=[True]*3:raise ValueError('FLAG_ACCEPT64_BOUNDARY_PROOF_INVALID')
        files += [path.parent/('accept64-boundary'+suffix) for suffix in ('.wdbg','.stdout.txt','.stderr.txt')]
    if healthy:
        if r.get('healthy_accept_preserves_setter') is not True:raise ValueError('FLAG_HEALTHY_SETTER_DISABLED_BY_ACCEPT')
        files += [path.parent/('healthy-accept'+suffix) for suffix in ('.wdbg','.stdout.txt','.stderr.txt')]
    return dict(path=str(path),sha256=digest(path),files=inventory(files))
