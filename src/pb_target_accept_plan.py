"""Seal/validate an isolated target-accept plan; never execute a product."""
import argparse
from pathlib import Path
from pb_kd_session import read, save, checked, inventory, check_files, validate_assets, boot_identity
from pb_prepare_kd_baseline import plain, digest

ASSETS = '81fc33a6288b324dcb9880735728e0699729c5c804292fb07a2791c9db4f3a24.json'
ASSETS_SHA = 'f14a2fadc257c3167655264c7c11ab2d5ae2d1561c197164ad4abfddd945e52d'
CORE = 'e04fc3e39092328b8cb5a7edabf040dcf3f0906f39f88371b04eb3ea9111b720'
POLICY = dict(fillers=200, filler_ports=[42001, 42200], control_port=42201,
              control_connections=1, hold_ms=100, original_single_query=True,
              debugger_points=[], driver_installation=False, driver_lifecycle='resident-disabled')
CREATE_PROFILE_SHA = '42f1426e0a5c6ba0f98794692598e30ed22c30ae6416c194e66c5c12d2fa5aa5'
RETRIEVE_PROFILE_SHA = '19490d337a14b149c275d5d801f12ddb7c86290b5357b76b9639c369083be35c'


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


def retrieve_policy():
    return dict(create_policy(True, True), workload='retrieve-target-201-staged',
                observer='etw+kd-target-retrieve')


def validate_positive_probe(capture, console, boot):
    # Replay the existing positive capture; never execute or refreeze it.
    from pb_target_create_report import evaluate
    capture, console = plain(Path(capture)), plain(Path(console))
    prior = read(capture / 'runtime-plan.json')
    if prior['policy'] != create_policy():
        raise ValueError('TARGET_POSITIVE_FOUR_POLICY_REQUIRED')
    if boot_identity(read(Path(prior['preparation']) / 'boot-session.json')) != boot_identity(boot):
        raise ValueError('TARGET_POSITIVE_PROBE_BOOT_DIFFERS')
    checked(prior['debugger_profile'], CREATE_PROFILE_SHA)
    result = evaluate(capture, console)
    if (result['status'] != 'CONTROL_CREATE_OBSERVED' or result['errors'] or
            result['unique_control_creation_observed'] is not True or
            len(result['create_events']) != 1):
        raise ValueError('TARGET_POSITIVE_CREATE_REQUIRED')
    return dict(capture=str(capture), console=str(console),
                plan_sha256=result['plan_sha256'], console_sha256=result['console_sha256'])


def validate_registration(profile_path, review_path, review_sha, boot):
    actual_sha = digest(Path(profile_path))
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
    kd = p.get('policy', {}).get('debugger_points') == [2]
    retrieve = p.get('policy', {}).get('observer') == 'etw+kd-target-retrieve'
    staged = p.get('policy', {}).get('workload') == 'create-target-201-staged'
    target = retrieve or staged or p.get('policy', {}).get('workload') == 'create-target-201'
    expected_policy = retrieve_policy() if retrieve else (create_policy(target, staged) if kd else POLICY)
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
        if ('retrieve' in profile['method']) != retrieve:
            raise ValueError('TARGET_OBSERVER_PROFILE_DIFFERS')
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
            create_target=False, positive_capture=None, positive_console=None, manual_host_window=False, retrieve_target=False):
    output = plain(output)
    if output.parent != root / 'artifacts/diagnostics' or set(output.iterdir()) != {output / 'boot-session.json'}:
        raise ValueError('TARGET_FRESH_PLAN_DIRECTORY_REQUIRED')
    verify_build(root, build)
    assets_path = root / 'artifacts/diagnostics/pb-kd-shared-assets' / ASSETS
    assets = validate_assets(assets_path, ASSETS_SHA, root)
    bindings = {}
    if retrieve_target and (create_target or not manual_host_window):
        raise ValueError('TARGET_RETRIEVE_REQUIRES_EXCLUSIVE_STAGED_TARGET')
    if manual_host_window and not (create_target or retrieve_target):
        raise ValueError('TARGET_STAGED_REQUIRES_201')
    if debugger_profile or registration_review:
        if not debugger_profile or not registration_review:
            raise ValueError('TARGET_PROFILE_AND_REGISTRATION_BOTH_REQUIRED')
        profile = validate_registration(debugger_profile, registration_review, digest(registration_review), read(output/'boot-session.json'))
        if ('retrieve' in profile['method']) != retrieve_target:
            raise ValueError('TARGET_OBSERVER_PROFILE_DIFFERS')
        bindings = dict(debugger_profile=str(plain(debugger_profile)), registration_review=str(plain(registration_review)),
                        registration_review_sha256=digest(registration_review))
    if create_target or retrieve_target:
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
    plan = dict(method='target-accept-session-v1', root=str(root), preparation=str(output), build=str(build),
                assets=str(assets_path), python=assets['python'], core_sha256=CORE,
                policy=retrieve_policy() if retrieve_target else (create_policy(create_target, manual_host_window) if bindings else POLICY), files=inventory(paths), **bindings)
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
    a = p.parse_args()
    if a.phase == 'prepare':
        target = prepare(plain(a.root), plain(a.build), a.output, a.debugger_profile, a.registration_review,
                         a.create_target, a.positive_capture, a.positive_console, a.manual_host_window, a.retrieve_target)
        print(str(target))
        print(digest(target))
    else:
        validate(a.plan, a.sha, plain(a.root))
        print('TARGET_PLAN_VALIDATED_NO_RUNTIME')
