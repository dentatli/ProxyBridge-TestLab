"""Seal/validate an isolated target-accept plan; never execute a product."""
import argparse
from pathlib import Path
from pb_kd_session import read, save, checked, inventory, check_files, validate_assets, boot_identity
from pb_prepare_kd_baseline import plain, digest
from pb_target_retry_profile import PROFILE_SHA as RETRY_PROFILE_SHA, validate_parser_proof as validate_retry_parser_proof
from pb_target_flag_binding import PROFILE_SHA as FLAG_PROFILE_SHA, policy as flag_policy, registration as flag_registration, parser_proof as flag_parser_proof, STAGE as FLAG_STAGE
from pb_target_flag_binding import ARMED_PROFILE_SHA as FLAG_ARMED_PROFILE_SHA, ARMED_STAGE as FLAG_ARMED_STAGE
from pb_target_flag_binding import ACCEPT64_PROFILE_SHA as FLAG_ACCEPT64_PROFILE_SHA, ACCEPT64_STAGE as FLAG_ACCEPT64_STAGE
from pb_target_flag_binding import HEALTHY_PROFILE_SHA as FLAG_HEALTHY_PROFILE_SHA, HEALTHY_STAGE as FLAG_HEALTHY_STAGE, profile_sha as flag_profile_sha
from pb_endpoint_watch_profile import PROFILE_SHA as FLAG_WATCH_PROFILE_SHA, STAGE as FLAG_WATCH_STAGE
from pb_endpoint_packet_watch import PROFILE_SHA as FLAG_PACKET_PROFILE_SHA, STAGE as FLAG_PACKET_STAGE
from pb_endpoint_send_gate import PROFILE_SHA as FLAG_SEND_PROFILE_SHA, STAGE as FLAG_SEND_STAGE, ACCEPT256_SHA as FLAG_SEND256_PROFILE_SHA, ACCEPT256_STAGE as FLAG_SEND256_STAGE, NATIVE_SHA as FLAG_SEND_NATIVE_SHA, NATIVE_STAGE as FLAG_SEND_NATIVE_STAGE
from pb_selected_nbl_profile import PROFILE_SHA as FLAG_NBL_SHA, STAGE as FLAG_NBL_STAGE, SCRIPT as FLAG_NBL_SCRIPT
from pb_selected_nbl64_profile import PROFILE_SHA as FLAG_NBL64_SHA, SCRIPT as FLAG_NBL64_SCRIPT
from pb_selected_nbl512_profile import PROFILE_SHA as FLAG_NBL512_SHA, SCRIPT as FLAG_NBL512_SCRIPT
from pb_retry_epochs_profile import PROFILE_SHA as FLAG_EPOCHS_SHA, SCRIPT as FLAG_EPOCHS_SCRIPT, STAGE as FLAG_EPOCHS_STAGE

from pb_accept_pair_profile import PROFILE_SHA as FLAG_PAIR_SHA, SCRIPT as FLAG_PAIR_SCRIPT, STAGE as FLAG_PAIR_STAGE
from pb_retry_chain_profile import PROFILE_SHA as FLAG_CHAIN_SHA, SCRIPT as FLAG_CHAIN_SCRIPT, STAGE as FLAG_CHAIN_STAGE

ASSETS = '81fc33a6288b324dcb9880735728e0699729c5c804292fb07a2791c9db4f3a24.json'
ASSETS_SHA = 'f14a2fadc257c3167655264c7c11ab2d5ae2d1561c197164ad4abfddd945e52d'
CORE = 'e04fc3e39092328b8cb5a7edabf040dcf3f0906f39f88371b04eb3ea9111b720'
POLICY = dict(fillers=200, filler_ports=[42001, 42200], control_port=42201,
              control_connections=1, hold_ms=100, original_single_query=True,
              debugger_points=[], driver_installation=False, driver_lifecycle='resident-disabled')
CREATE_PROFILE_SHA = '42f1426e0a5c6ba0f98794692598e30ed22c30ae6416c194e66c5c12d2fa5aa5'
RETRIEVE_PROFILE_SHA = '19490d337a14b149c275d5d801f12ddb7c86290b5357b76b9639c369083be35c'
FLOW_PROFILE_SHA = 'f6f5fe5140bad4653e44c90f77b60e7458f04039ac878581247506e03e7f2de2'
REMOVAL_PROFILE_SHA = '01ce15520ea2f4f40db9fbd41cb65001ce77c656427f5959c34695280e8a0041'
REMOVAL_R2_PROFILE_SHA = '9594e63cb2723f07ba8731ca2289224c395a8f3f85966c0c3e4e9a86367d0c9c'


def create_policy(target=False, staged=False):
    if staged and not target:
        raise ValueError('TARGET_STAGED_REQUIRES_201')
    policy = dict(POLICY, fillers=200 if target else 3,
                filler_ports=[42001, 42200 if target else 42003],
                workload='create-target-201' if target else 'create-four-probe',
                debugger_points=[2], observer='etw+kd-target-create',
                automatic_debugger_control=False, debugger_console_required=True)
    if staged:
        policy.update(workload='create-target-201-staged', initial_debugger_points=[],
                      host_confirmation='user-console-C-after-host-g', host_deadline_ms=15000,
                      control_deadline_ms=20000, core_watchdog_ms=30000)
    return policy


def retrieve_policy(target=True):
    return dict(create_policy(target, target),
                workload='retrieve-target-201-staged' if target else 'retrieve-four-probe',
                observer='etw+kd-target-retrieve')


def flow_policy(removal=False, retry=False):
    p = dict(create_policy(True, True), workload='flow-target-201-staged',
             debugger_points=[2, 3, 4], observer='etw+kd-target-flow',
             registration_confirmation='user-run-argument-no-independent-host-proof')
    if removal:
        p.update(workload='removal-target-201-staged', observer='etw+kd-target-removal',
                 debugger_points=[2, 3], inactive_debugger_points=[4])
    if retry:
        if removal:
            raise ValueError('TARGET_FLOW_MODES_EXCLUSIVE')
        p.update(workload='retry-target-201-staged', observer='etw+kd-target-retry',
                 debugger_points=[2, 3, 4, 5, 6])
    return p


def validate_positive_probe(capture, console, boot):
    # Replay the existing positive capture; never execute or refreeze it.
    from pb_target_create_report import evaluate
    capture, console = plain(Path(capture)), plain(Path(console))
    prior = read(capture / 'runtime-plan.json')
    if prior['policy'].get('endpoint_accept_pair') is True:
        from pb_accept_pair_report import evaluate as pair_evaluate
        if boot_identity(read(Path(prior['preparation'])/'boot-session.json'))!=boot_identity(boot):
            raise ValueError('TARGET_POSITIVE_PROBE_BOOT_DIFFERS')
        result=pair_evaluate(capture,console)
        if result['status']!='ACCEPT_PAIR_HEALTHY_OBSERVED' or result['errors']:
            raise ValueError('TARGET_POSITIVE_ACCEPT_PAIR_REQUIRED')
        return dict(capture=str(capture),console=str(console),plan_sha256=result['plan_sha256'],console_sha256=result['console_sha256'])
    if prior['policy'].get('endpoint_send_gate') is True:
        from pb_endpoint_send_gate import evaluate as send_evaluate
        if boot_identity(read(Path(prior['preparation'])/'boot-session.json'))!=boot_identity(boot):
            raise ValueError('TARGET_POSITIVE_PROBE_BOOT_DIFFERS')
        checked(prior['debugger_profile'],FLAG_SEND256_PROFILE_SHA if prior['policy'].get('endpoint_send_accept_limit')==256 else FLAG_SEND_PROFILE_SHA)
        result=send_evaluate(capture,console)
        if result['status']!='SEND_GATE_HEALTHY_CONTROL_OBSERVED' or result['errors']:
            raise ValueError('TARGET_POSITIVE_SEND_GATE_REQUIRED')
        return dict(capture=str(capture),console=str(console),plan_sha256=result['plan_sha256'],console_sha256=result['console_sha256'])
    if prior['policy'].get('endpoint_data_watch') is True:
        from pb_endpoint_watch_report import evaluate as watch_evaluate
        if boot_identity(read(Path(prior['preparation'])/'boot-session.json'))!=boot_identity(boot):
            raise ValueError('TARGET_POSITIVE_PROBE_BOOT_DIFFERS')
        checked(prior['debugger_profile'],FLAG_WATCH_PROFILE_SHA)
        result=watch_evaluate(capture,console)
        if result['status']!='ENDPOINT_WATCH_NATIVE_SUCCESS_OBSERVED' or result['errors']:
            raise ValueError('TARGET_POSITIVE_ENDPOINT_WATCH_REQUIRED')
        return dict(capture=str(capture),console=str(console),plan_sha256=result['plan_sha256'],console_sha256=result['console_sha256'])
    healthy_flag=prior['policy']==flag_policy(False,True,True,True)
    if prior['policy']==flag_policy(False) or healthy_flag:
        from pb_target_flag_report import evaluate as flag_evaluate
        if boot_identity(read(Path(prior['preparation'])/'boot-session.json'))!=boot_identity(boot):
            raise ValueError('TARGET_POSITIVE_PROBE_BOOT_DIFFERS')
        checked(prior['debugger_profile'],FLAG_HEALTHY_PROFILE_SHA if healthy_flag else FLAG_PROFILE_SHA)
        result=flag_evaluate(capture,console)
        if result['status']!=('FLAG_HEALTHY_PROBE_NATIVE_SUCCESS_OBSERVED' if healthy_flag else 'FLAG_PROBE_SUCCESS_OBSERVED') or result['errors']:
            raise ValueError('TARGET_POSITIVE_FLAG_PROBE_REQUIRED')
        return dict(capture=str(capture),console=str(console),plan_sha256=result['plan_sha256'],console_sha256=result['console_sha256'])
    retrieve = prior['policy'] == retrieve_policy(False)
    if not retrieve and prior['policy'] != create_policy():
        raise ValueError('TARGET_POSITIVE_FOUR_POLICY_REQUIRED')
    if boot_identity(read(Path(prior['preparation']) / 'boot-session.json')) != boot_identity(boot):
        raise ValueError('TARGET_POSITIVE_PROBE_BOOT_DIFFERS')
    checked(prior['debugger_profile'], RETRIEVE_PROFILE_SHA if retrieve else CREATE_PROFILE_SHA)
    if retrieve:
        from pb_target_retrieve_report import evaluate as retrieve_evaluate
        result = retrieve_evaluate(capture, console)
        if (result['status'] != 'RETRIEVE_SUCCESS_OBSERVED' or result['errors'] or
                len(result['retrieve_events']) != 1 or len(result['record_snapshots']) != 1):
            raise ValueError('TARGET_POSITIVE_RETRIEVE_REQUIRED')
        return dict(capture=str(capture), console=str(console),
                    plan_sha256=result['plan_sha256'], console_sha256=result['console_sha256'])
    result = evaluate(capture, console)
    if (result['status'] != 'CONTROL_CREATE_OBSERVED' or result['errors'] or
            result['unique_control_creation_observed'] is not True or
            len(result['create_events']) != 1):
        raise ValueError('TARGET_POSITIVE_CREATE_REQUIRED')
    return dict(capture=str(capture), console=str(console),
                plan_sha256=result['plan_sha256'], console_sha256=result['console_sha256'])


def validate_registration(profile_path, review_path, review_sha, boot):
    actual_sha = digest(Path(profile_path))
    if actual_sha in (FLAG_CHAIN_SHA,FLAG_PAIR_SHA,FLAG_EPOCHS_SHA,FLAG_NBL512_SHA,FLAG_NBL64_SHA,FLAG_NBL_SHA,FLAG_PROFILE_SHA,FLAG_ARMED_PROFILE_SHA,FLAG_ACCEPT64_PROFILE_SHA,FLAG_HEALTHY_PROFILE_SHA,FLAG_WATCH_PROFILE_SHA,FLAG_PACKET_PROFILE_SHA,FLAG_SEND_PROFILE_SHA,FLAG_SEND256_PROFILE_SHA,FLAG_SEND_NATIVE_SHA):
        return flag_registration(profile_path,review_path,review_sha,boot)
    if actual_sha in (FLOW_PROFILE_SHA, REMOVAL_PROFILE_SHA, REMOVAL_R2_PROFILE_SHA, RETRY_PROFILE_SHA):
        retry = actual_sha == RETRY_PROFILE_SHA
        removal = actual_sha in (REMOVAL_PROFILE_SHA, REMOVAL_R2_PROFILE_SHA)
        ids = [2, 3, 4, 5, 6] if retry else [2, 3, 4]
        kind = 'retry' if retry else ('removal' if removal else 'flow')
        version = 'v2' if actual_sha == REMOVAL_R2_PROFILE_SHA else 'v1'
        profile = read(checked(profile_path, actual_sha))
        receipt = read(checked(review_path, review_sha))
        if (profile['method'] != 'kd-target-'+kind+'-disabled-candidate-20261019-'+version or
                profile['registered_point_ids'] != ids or profile['active_point_ids'] != [] or
                profile['control_source_port'] != 42201 or profile['automatic_debugger_control']):
            raise ValueError('TARGET_FLOW_PROFILE_INVALID')
        # Prepared commands are not represented as an observed registration review.
        if (receipt['method'] != 'target-flow-prepared-commands-v1' or
                receipt['source'] != 'prepared-command-awaiting-user-attestation' or
                receipt['profile_sha256'] != actual_sha or
                receipt['expected_disabled_ids'] != ids or
                receipt['host_registration_observed'] is not False or
                boot_identity(receipt['boot']) != boot_identity(boot)):
            raise ValueError('TARGET_FLOW_PREPARED_COMMANDS_OR_BOOT_DIFFERS')
        return profile
    retrieve = actual_sha == RETRIEVE_PROFILE_SHA
    expected_sha = RETRIEVE_PROFILE_SHA if retrieve else CREATE_PROFILE_SHA
    kind = 'retrieve' if retrieve else 'create'
    profile = read(checked(profile_path, expected_sha))
    review = read(checked(review_path, review_sha))
    if (profile['method'] != 'kd-target-'+kind+'-disabled-candidate-20261019-v1' or
            profile['registered_point_ids'] != [2] or profile['active_point_ids'] != [] or
            profile['control_source_port'] != 42201 or profile['automatic_debugger_control']):
        raise ValueError('TARGET_CREATE_PROFILE_INVALID')
    if (review['method'] != 'target-'+kind+'-registration-review-v1' or
            review['profile_sha256'] != expected_sha or review['registered_ids'] != [2] or
            review['disabled_ids'] != [2] or review['action_matches_profile'] is not True or
            review['separate_g_shown'] is not True or review['source'] != 'user-chat-paste' or
            boot_identity(review['boot']) != boot_identity(boot)):
        raise ValueError('TARGET_CREATE_REGISTRATION_OR_BOOT_DIFFERS')
    return profile


def validate_command_parser_proof(path):
    path = plain(Path(path))
    r = read(path)
    if (r['method'] != 'cdb-safe-removal-command-fixture-v1' or r['passed'] is not True or
            r['kernel_connection'] is not False or r['product_started'] is not False or
            r['traffic_generated'] is not False or
            [c['name'] for c in r['cases']] != ['r1-readable', 'r2-readable', 'r2-unreadable']):
        raise ValueError('TARGET_COMMAND_PARSER_PROOF_INVALID')
    paths = [path]
    for index, case in enumerate(r['cases']):
        if case['passed'] is not True or case['profile_sha256'] != (REMOVAL_PROFILE_SHA if index == 0 else REMOVAL_R2_PROFILE_SHA):
            raise ValueError('TARGET_COMMAND_PARSER_PROFILE_DIFFERS')
        if index == 0:
            if not case['old_error_reproduced'] or case['action_end']:
                raise ValueError('TARGET_COMMAND_PARSER_REGRESSION_NOT_REPRODUCED')
        elif (case['old_error_reproduced'] or not all(case[k] for k in ('action_end', 'stack_begin', 'stack_end')) or case['exit_code'] != 0):
            raise ValueError('TARGET_COMMAND_PARSER_FIXED_BRANCH_FAILED')
        paths += [path.parent/(case['name']+suffix) for suffix in ('.wdbg', '.stdout.txt', '.stderr.txt')]
    return dict(path=str(path), sha256=digest(path), files=inventory(paths))


def verify_build(root, build):
    build = plain(build)
    if build.parent != root / 'artifacts/diagnostics':
        raise ValueError('TARGET_BUILD_DIRECTORY_INVALID')
    receipt = read(build / 'preparation.json')
    proof = read(build / 'verification/build-result.json')
    if (receipt['method'] != 'target-accept-barrier-v1' or
            receipt['status'] != 'DIAGNOSTIC_BUILD_PREPARED_NOT_RUNNABLE' or
            not receipt['inverse_patch_exact'] or not receipt['original_single_query_preserved'] or
            receipt['driver_installation'] or receipt['runtime_verified'] or
            proof['exports_match'] is not True or proof['export_count'] != 19 or proof['fake_api_tests'] != 10):
        raise ValueError('TARGET_BUILD_PROOF_INVALID')
    checked(build / 'kit/ProxyBridgeCore.dll', CORE)
    if receipt['core_sha256'].lower() != CORE or proof['core_sha256'].lower() != CORE:
        raise ValueError('TARGET_CORE_SHA_DIFFERS')
    for relative, sha in receipt['source_after_sha256'].items():
        path = plain(build / 'source' / relative)
        if not path.is_relative_to(build / 'source'):
            raise ValueError('TARGET_SOURCE_ESCAPE')
        checked(path, sha)
    return receipt


def validate(plan_path, sha, root):
    plan_path = checked(plan_path, sha)
    p = read(plan_path)
    flag=p.get('policy',{}).get('observer')=='etw+kd-target-flag'
    flag_four=flag and p['policy'].get('workload')=='flag-four-probe'
    flag_armed=flag and p['policy'].get('automatic_debugger_enable_after_create') in ([3],[3,4])
    flag_accept64=flag and (p['policy'].get('endpoint_send_native_query') is True or p['policy'].get('raw_hit_limits_per_point')==({'2':16,'3':64,'4':p['policy'].get('endpoint_send_accept_limit',64)} if p['policy'].get('endpoint_send_gate') is True else {'2':16,'3':16,'4':64}))
    flag_healthy=flag and p['policy'].get('healthy_setter_probe') is True
    flag_watch=flag and p['policy'].get('endpoint_data_watch') is True
    if flag_watch and p['policy'].get('endpoint_packet_header') is True:flag_watch='packet'
    if flag_watch and p['policy'].get('endpoint_send_gate') is True:flag_watch='sendnative' if p['policy'].get('endpoint_send_native_query') is True else 'send256' if p['policy'].get('endpoint_send_accept_limit')==256 else 'send'
    if flag_watch and p['policy'].get('endpoint_nbl_context') is True:flag_watch='nbl'
    if flag_watch and p['policy'].get('endpoint_nbl64_context') is True:flag_watch='nbl64'
    if flag_watch and p['policy'].get('endpoint_nbl512_context') is True:flag_watch='nbl512'
    if flag_watch and p['policy'].get('endpoint_retry_epochs') is True:flag_watch='epochs'
    if flag and p['policy'].get('endpoint_accept_pair') is True:flag_watch='pair'
    if flag and p['policy'].get('endpoint_retry_chain') is True:flag_watch='chain'
    removal = p.get('policy', {}).get('observer') == 'etw+kd-target-removal'
    retry = p.get('policy', {}).get('observer') == 'etw+kd-target-retry'
    flow = retry or removal or p.get('policy', {}).get('observer') == 'etw+kd-target-flow'
    kd = p.get('policy', {}).get('debugger_points') == (([2,3,4] if flag_watch in ('send','send256','epochs') else [2,3] if flag_watch and not flag_four else [2,4] if flag_four and not flag_armed else [2,3,4]) if flag else ([2,3,4,5,6] if retry else ([2, 3] if removal else ([2, 3, 4] if flow else [2]))))
    if flag_watch=='pair':kd=p['policy'].get('debugger_points')==[2,3]
    if flag_watch=='chain':kd=p['policy'].get('debugger_points')==[2,3,4]
    retrieve = p.get('policy', {}).get('observer') == 'etw+kd-target-retrieve'
    staged = p.get('policy', {}).get('workload') == 'create-target-201-staged'
    retrieve_four = p.get('policy', {}).get('workload') == 'retrieve-four-probe'
    target = (flag and not flag_four) or flow or (retrieve and not retrieve_four) or staged or p.get('policy', {}).get('workload') == 'create-target-201'
    if flag_watch=='chain':
        from pb_retry_chain_profile import policy as chain_policy
        expected_policy=chain_policy(not flag_four)
    elif flag_watch=='pair':
        from pb_accept_pair_profile import policy as pair_policy
        expected_policy=pair_policy(not flag_four)
    else:
        expected_policy = flag_policy(not flag_four,flag_armed,flag_accept64,flag_healthy,flag_watch) if flag else (flow_policy(removal, retry) if flow else (retrieve_policy(not retrieve_four) if retrieve else (create_policy(target, staged) if kd else POLICY)))
    if (p['method'] != 'target-accept-session-v1' or Path(p['root']) != root or
            Path(p['preparation']) != plan_path.parent or
            plan_path.parent.parent != root / 'artifacts/diagnostics' or p['policy'] != expected_policy):
        raise ValueError('TARGET_PLAN_CONTRACT_INVALID')
    check_files(p['files'])
    verify_build(root, Path(p['build']))
    assets = validate_assets(Path(p['assets']), ASSETS_SHA, root)
    if p['python'] != assets['python'] or p['core_sha256'] != CORE:
        raise ValueError('TARGET_RUNTIME_BINDING_DIFFERS')
    boot = read(plan_path.parent / 'boot-session.json')
    boot_identity(boot)
    if kd:
        profile = validate_registration(p['debugger_profile'], p['registration_review'], p['registration_review_sha256'], boot)
        if (digest(Path(p['debugger_profile'])) in (FLAG_CHAIN_SHA,FLAG_PAIR_SHA,FLAG_EPOCHS_SHA,FLAG_NBL512_SHA,FLAG_NBL64_SHA,FLAG_NBL_SHA,FLAG_PROFILE_SHA,FLAG_ARMED_PROFILE_SHA,FLAG_ACCEPT64_PROFILE_SHA,FLAG_HEALTHY_PROFILE_SHA,FLAG_WATCH_PROFILE_SHA,FLAG_PACKET_PROFILE_SHA,FLAG_SEND_PROFILE_SHA,FLAG_SEND256_PROFILE_SHA,FLAG_SEND_NATIVE_SHA))!=flag:
            raise ValueError('FLAG_OBSERVER_PROFILE_DIFFERS')
        if flag:
            if digest(Path(p['debugger_profile']))!=flag_profile_sha(flag_armed,flag_accept64,flag_healthy,flag_watch):raise ValueError('FLAG_PROFILE_DIFFERS')
        elif (('retrieve' in profile['method']) != retrieve or
                any(k in profile['method'] for k in ('flow','removal','retry')) != flow or
                ('removal' in profile['method']) != removal or ('retry' in profile['method']) != retry):
            raise ValueError('TARGET_OBSERVER_PROFILE_DIFFERS')
        parser_proof = p.get('command_parser_proof')
        if flag:
            if not parser_proof or flag_parser_proof(parser_proof['path'],flag_armed,flag_accept64,flag_healthy,flag_watch)!=parser_proof:
                raise ValueError('FLAG_PARSER_PROOF_BINDING_DIFFERS')
        elif retry:
            if not parser_proof or validate_retry_parser_proof(parser_proof['path']) != parser_proof:
                raise ValueError('TARGET_RETRY_PARSER_PROOF_BINDING_DIFFERS')
        elif digest(Path(p['debugger_profile'])) == REMOVAL_R2_PROFILE_SHA:
            if not parser_proof or validate_command_parser_proof(parser_proof['path']) != parser_proof:
                raise ValueError('TARGET_COMMAND_PARSER_PROOF_BINDING_DIFFERS')
        elif parser_proof:
            raise ValueError('TARGET_UNEXPECTED_COMMAND_PARSER_PROOF')
    elif any(p.get(k) for k in ('debugger_profile', 'registration_review', 'registration_review_sha256')):
        raise ValueError('TARGET_ETW_PLAN_HAS_DEBUGGER_BINDINGS')
    if target:
        proof = p.get('positive_probe')
        if not proof or validate_positive_probe(proof['capture'], proof['console'], boot) != proof:
            raise ValueError('TARGET_POSITIVE_PROBE_BINDING_DIFFERS')
    elif p.get('positive_probe'):
        raise ValueError('TARGET_UNEXPECTED_POSITIVE_PROBE_BINDING')
    return p


def prepare(root, build, output, debugger_profile=None, registration_review=None,
            create_target=False, positive_capture=None, positive_console=None, manual_host_window=False, retrieve_target=False, retrieve_probe=False, flow_target=False, removal_target=False, command_parser_proof=None, retry_target=False, flag_target=False, flag_probe=False, flag_create_armed=False,flag_accept64=False,flag_healthy_probe=False,endpoint_watch=False):
    # Preserve the profile and consumed captures for offline evaluation, but
    # prohibit new runs of the hot five-point observer after the VM stall.
    if retry_target:
        raise ValueError('TARGET_RETRY_PROFILE_RETIRED_HOT_TRACE_NO_RUNTIME')
    if endpoint_watch and not (flag_target or flag_healthy_probe):raise ValueError('ENDPOINT_WATCH_REQUIRES_FLAG_MODE')
    if flag_healthy_probe:
        if any((flag_target,flag_probe,flag_create_armed,flag_accept64,manual_host_window)):
            raise ValueError('FLAG_HEALTHY_REQUIRES_EXCLUSIVE_PROBE')
        flag_probe=flag_create_armed=flag_accept64=True
    if endpoint_watch and flag_target:flag_create_armed=flag_accept64=True
    if endpoint_watch and debugger_profile and digest(Path(debugger_profile))==FLAG_PACKET_PROFILE_SHA:endpoint_watch='packet'
    if endpoint_watch and debugger_profile and digest(Path(debugger_profile))in (FLAG_SEND_PROFILE_SHA,FLAG_SEND256_PROFILE_SHA,FLAG_SEND_NATIVE_SHA):endpoint_watch='sendnative' if digest(Path(debugger_profile))==FLAG_SEND_NATIVE_SHA else 'send256' if digest(Path(debugger_profile))==FLAG_SEND256_PROFILE_SHA else 'send'
    if endpoint_watch and debugger_profile and digest(Path(debugger_profile))==FLAG_NBL_SHA:endpoint_watch='nbl'
    if endpoint_watch and debugger_profile and digest(Path(debugger_profile))==FLAG_NBL64_SHA:endpoint_watch='nbl64'
    if endpoint_watch and debugger_profile and digest(Path(debugger_profile))==FLAG_NBL512_SHA:endpoint_watch='nbl512'
    if endpoint_watch and debugger_profile and digest(Path(debugger_profile))==FLAG_EPOCHS_SHA:endpoint_watch='epochs'
    if endpoint_watch and debugger_profile and digest(Path(debugger_profile))==FLAG_PAIR_SHA:endpoint_watch='pair'
    if endpoint_watch and debugger_profile and digest(Path(debugger_profile))==FLAG_CHAIN_SHA:endpoint_watch='chain'
    if flag_create_armed and not flag_healthy_probe and (not flag_target or flag_probe):
        raise ValueError('FLAG_CREATE_ARMED_REQUIRES_TARGET')
    if flag_accept64 and not flag_create_armed:
        raise ValueError('FLAG_ACCEPT64_REQUIRES_CREATE_ARMED')
    flag=flag_target or flag_probe
    if flag and (sum(map(bool,(flag_target,flag_probe)))!=1 or any((create_target,retrieve_target,retrieve_probe,flow_target,removal_target,retry_target)) or manual_host_window!=flag_target):
        raise ValueError('FLAG_REQUIRES_EXCLUSIVE_MODE')
    if flag and not (debugger_profile and registration_review and command_parser_proof):
        raise ValueError('FLAG_BINDINGS_REQUIRED')
    output = plain(output)
    if output.parent != root / 'artifacts/diagnostics' or set(output.iterdir()) != {output / 'boot-session.json'}:
        raise ValueError('TARGET_FRESH_PLAN_DIRECTORY_REQUIRED')
    verify_build(root, build)
    assets_path = root / 'artifacts/diagnostics/pb-kd-shared-assets' / ASSETS
    assets = validate_assets(assets_path, ASSETS_SHA, root)
    bindings = {}
    if sum(map(bool,(removal_target,flow_target,retry_target))) > 1:
        raise ValueError('TARGET_FLOW_MODES_EXCLUSIVE')
    flow_target = flow_target or removal_target or retry_target
    if flow_target and (create_target or retrieve_target or retrieve_probe or not manual_host_window):
        raise ValueError('TARGET_FLOW_REQUIRES_EXCLUSIVE_STAGED_TARGET')
    if retrieve_probe and (retrieve_target or create_target or manual_host_window):
        raise ValueError('TARGET_RETRIEVE_PROBE_EXCLUSIVE')
    if retrieve_probe and not (debugger_profile and registration_review):
        raise ValueError('TARGET_RETRIEVE_PROBE_REGISTRATION_REQUIRED')
    if retrieve_target and (create_target or not manual_host_window):
        raise ValueError('TARGET_RETRIEVE_REQUIRES_EXCLUSIVE_STAGED_TARGET')
    if manual_host_window and not (create_target or retrieve_target or flow_target or flag_target):
        raise ValueError('TARGET_STAGED_REQUIRES_201')
    if debugger_profile or registration_review:
        if not debugger_profile or not registration_review:
            raise ValueError('TARGET_PROFILE_AND_REGISTRATION_BOTH_REQUIRED')
        profile = validate_registration(debugger_profile, registration_review, digest(registration_review), read(output/'boot-session.json'))
        if (digest(Path(debugger_profile)) in (FLAG_CHAIN_SHA,FLAG_PAIR_SHA,FLAG_EPOCHS_SHA,FLAG_NBL512_SHA,FLAG_NBL64_SHA,FLAG_NBL_SHA,FLAG_PROFILE_SHA,FLAG_ARMED_PROFILE_SHA,FLAG_ACCEPT64_PROFILE_SHA,FLAG_HEALTHY_PROFILE_SHA,FLAG_WATCH_PROFILE_SHA,FLAG_PACKET_PROFILE_SHA,FLAG_SEND_PROFILE_SHA,FLAG_SEND256_PROFILE_SHA,FLAG_SEND_NATIVE_SHA))!=flag:
            raise ValueError('FLAG_OBSERVER_PROFILE_DIFFERS')
        if flag:
            if digest(Path(debugger_profile))!=flag_profile_sha(flag_create_armed,flag_accept64,flag_healthy_probe,endpoint_watch):raise ValueError('FLAG_PROFILE_DIFFERS')
        elif (('retrieve' in profile['method']) != (retrieve_target or retrieve_probe) or
                any(k in profile['method'] for k in ('flow','removal','retry')) != flow_target or
                ('removal' in profile['method']) != removal_target or ('retry' in profile['method']) != retry_target):
            raise ValueError('TARGET_OBSERVER_PROFILE_DIFFERS')
        bindings = dict(debugger_profile=str(plain(debugger_profile)), registration_review=str(plain(registration_review)),
                        registration_review_sha256=digest(registration_review))
    if flag:
        bindings['command_parser_proof']=flag_parser_proof(command_parser_proof,flag_create_armed,flag_accept64,flag_healthy_probe,endpoint_watch)
    elif retry_target:
        if not debugger_profile or digest(Path(debugger_profile)) != RETRY_PROFILE_SHA or not command_parser_proof:
            raise ValueError('TARGET_RETRY_AND_REAL_PARSER_PROOF_REQUIRED')
        bindings['command_parser_proof'] = validate_retry_parser_proof(command_parser_proof)
    elif removal_target:
        if not debugger_profile or digest(Path(debugger_profile)) != REMOVAL_R2_PROFILE_SHA or not command_parser_proof:
            raise ValueError('TARGET_REMOVAL_R2_AND_REAL_PARSER_PROOF_REQUIRED')
        bindings['command_parser_proof'] = validate_command_parser_proof(command_parser_proof)
    elif command_parser_proof:
        raise ValueError('TARGET_UNEXPECTED_COMMAND_PARSER_PROOF')
    if create_target or retrieve_target or flow_target or flag_target:
        if not bindings or not positive_capture or not positive_console:
            raise ValueError('TARGET_CREATE_TARGET_REQUIRES_PROFILE_AND_POSITIVE_PROBE')
        bindings['positive_probe'] = validate_positive_probe(positive_capture, positive_console, read(output/'boot-session.json'))
    elif positive_capture or positive_console:
        raise ValueError('TARGET_POSITIVE_PROBE_REQUIRES_EXPLICIT_CREATE_TARGET')
    paths = (list((root / 'modules').glob('*.psm1')) + list((root / 'src').glob('*.py')) +
             list((root / 'src').glob('*.cs')))
    paths += [root / 'scripts/Invoke-TargetAccept.ps1', output / 'boot-session.json',
              build / 'preparation.json', build / 'verification/build-result.json']
    paths += list((build / 'kit').glob('*'))
    paths += [root / 'bin/pb_console_host.exe', root / 'config/runtime.json']
    paths += [root / 'bin/tools/windivert-2.2.2/windivertctl.exe', root / 'bin/tools/windivert-2.2.2/WinDivert.dll']
    if bindings:
        paths += [Path(bindings['debugger_profile']), Path(bindings['registration_review'])]
    if flow_target:
        kind = 'retry' if retry_target else ('removal' if removal_target else 'flow')
        suffix = '-r2' if removal_target else ''
        paths += [root/('scripts/debugger/pb-kd-target-'+kind+'-disabled-20261019'+suffix+'.wdbg')]
    if flag:paths += [root/(FLAG_CHAIN_STAGE if endpoint_watch=='chain' else FLAG_PAIR_STAGE if endpoint_watch=='pair' else FLAG_EPOCHS_STAGE if endpoint_watch=='epochs' else FLAG_NBL_STAGE if endpoint_watch in ('nbl','nbl64','nbl512') else FLAG_SEND_NATIVE_STAGE if endpoint_watch=='sendnative' else FLAG_SEND256_STAGE if endpoint_watch=='send256' else FLAG_SEND_STAGE if endpoint_watch=='send' else FLAG_PACKET_STAGE if endpoint_watch=='packet' else FLAG_WATCH_STAGE if endpoint_watch else FLAG_HEALTHY_STAGE if flag_healthy_probe else FLAG_ACCEPT64_STAGE if flag_accept64 else FLAG_ARMED_STAGE if flag_create_armed else FLAG_STAGE)]
    if endpoint_watch=='nbl':paths += [root/FLAG_NBL_SCRIPT]
    if endpoint_watch=='nbl64':paths += [root/FLAG_NBL64_SCRIPT]
    if endpoint_watch=='nbl512':paths += [root/FLAG_NBL512_SCRIPT]
    if endpoint_watch=='epochs':paths += [root/FLAG_EPOCHS_SCRIPT]
    if endpoint_watch=='pair':paths += [root/FLAG_PAIR_SCRIPT]
    if endpoint_watch=='chain':paths += [root/FLAG_CHAIN_SCRIPT]
    plan = dict(method='target-accept-session-v1', root=str(root), preparation=str(output), build=str(build),
                assets=str(assets_path), python=assets['python'], core_sha256=CORE,
                policy=flag_policy(flag_target,flag_create_armed,flag_accept64,flag_healthy_probe,endpoint_watch) if flag else (flow_policy(removal_target, retry_target) if flow_target else (retrieve_policy(not retrieve_probe) if (retrieve_target or retrieve_probe) else (create_policy(create_target, manual_host_window) if bindings else POLICY))), files=inventory(paths), **bindings)
    boot_identity(read(output / 'boot-session.json'))
    save(output / 'runtime-plan.json', plan)
    validate(output / 'runtime-plan.json', digest(output / 'runtime-plan.json'), root)
    return output / 'runtime-plan.json'


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('phase', choices=['prepare', 'validate'])
    p.add_argument('--root', type=Path, required=True)
    p.add_argument('--build', type=Path)
    p.add_argument('--output', type=Path)
    p.add_argument('--plan', type=Path)
    p.add_argument('--sha')
    p.add_argument('--debugger-profile', type=Path)
    p.add_argument('--registration-review', type=Path)
    p.add_argument('--create-target', action='store_true')
    p.add_argument('--positive-capture', type=Path)
    p.add_argument('--positive-console', type=Path)
    p.add_argument('--manual-host-window', action='store_true')
    p.add_argument('--retrieve-target', action='store_true')
    p.add_argument('--retrieve-probe', action='store_true')
    p.add_argument('--flow-target', action='store_true')
    p.add_argument('--removal-target', action='store_true')
    p.add_argument('--command-parser-proof', type=Path)
    p.add_argument('--retry-target', action='store_true')
    p.add_argument('--flag-target', action='store_true')
    p.add_argument('--flag-probe', action='store_true')
    p.add_argument('--flag-create-armed', action='store_true')
    p.add_argument('--flag-accept64', action='store_true')
    p.add_argument('--flag-healthy-probe', action='store_true')
    p.add_argument('--endpoint-watch', action='store_true')
    a = p.parse_args()
    if a.phase == 'prepare':
        target = prepare(plain(a.root), plain(a.build), a.output, a.debugger_profile, a.registration_review,
                         a.create_target, a.positive_capture, a.positive_console, a.manual_host_window, a.retrieve_target, a.retrieve_probe, a.flow_target, a.removal_target, a.command_parser_proof, a.retry_target, a.flag_target, a.flag_probe, a.flag_create_armed,a.flag_accept64,a.flag_healthy_probe,a.endpoint_watch)
        print(str(target))
        print(digest(target))
    else:
        validate(a.plan, a.sha, plain(a.root))
        print('TARGET_PLAN_VALIDATED_NO_RUNTIME')
