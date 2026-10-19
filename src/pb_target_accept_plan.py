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


def create_policy():
    # A new pointer-reading action first gets a four-connection positive probe.
    # This policy does not authorize the 201-connection experiment with KD active.
    return dict(POLICY, fillers=3, filler_ports=[42001, 42003], workload='create-four-probe',
                debugger_points=[2], observer='etw+kd-target-create',
                automatic_debugger_control=False, debugger_console_required=True)


def validate_registration(profile_path, review_path, review_sha, boot):
    profile = read(checked(profile_path, CREATE_PROFILE_SHA))
    review = read(checked(review_path, review_sha))
    if (profile['method'] != 'kd-target-create-disabled-candidate-20261019-v1' or
            profile['registered_point_ids'] != [2] or profile['active_point_ids'] != [] or
            profile['control_source_port'] != 42201 or profile['automatic_debugger_control']):
        raise ValueError('TARGET_CREATE_PROFILE_INVALID')
    if (review['method'] != 'target-create-registration-review-v1' or
            review['profile_sha256'] != CREATE_PROFILE_SHA or review['registered_ids'] != [2] or
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
    if (p['method'] != 'target-accept-session-v1' or Path(p['root']) != root or
            Path(p['preparation']) != plan_path.parent or
            plan_path.parent.parent != root / 'artifacts/diagnostics' or p['policy'] != (create_policy() if kd else POLICY)):
        raise ValueError('TARGET_PLAN_CONTRACT_INVALID')
    check_files(p['files'])
    verify_build(root, Path(p['build']))
    assets = validate_assets(Path(p['assets']), ASSETS_SHA, root)
    if p['python'] != assets['python'] or p['core_sha256'] != CORE:
        raise ValueError('TARGET_RUNTIME_BINDING_DIFFERS')
    boot = read(plan_path.parent / 'boot-session.json')
    boot_identity(boot)
    if kd:
        validate_registration(p['debugger_profile'], p['registration_review'], p['registration_review_sha256'], boot)
    elif any(p.get(k) for k in ('debugger_profile', 'registration_review', 'registration_review_sha256')):
        raise ValueError('TARGET_ETW_PLAN_HAS_DEBUGGER_BINDINGS')
    return p


def prepare(root, build, output, debugger_profile=None, registration_review=None):
    output = plain(output)
    if output.parent != root / 'artifacts/diagnostics' or set(output.iterdir()) != {output / 'boot-session.json'}:
        raise ValueError('TARGET_FRESH_PLAN_DIRECTORY_REQUIRED')
    verify_build(root, build)
    assets_path = root / 'artifacts/diagnostics/pb-kd-shared-assets' / ASSETS
    assets = validate_assets(assets_path, ASSETS_SHA, root)
    bindings = {}
    if debugger_profile or registration_review:
        if not debugger_profile or not registration_review:
            raise ValueError('TARGET_PROFILE_AND_REGISTRATION_BOTH_REQUIRED')
        validate_registration(debugger_profile, registration_review, digest(registration_review), read(output/'boot-session.json'))
        bindings = dict(debugger_profile=str(plain(debugger_profile)), registration_review=str(plain(registration_review)),
                        registration_review_sha256=digest(registration_review))
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
                policy=create_policy() if bindings else POLICY, files=inventory(paths), **bindings)
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
    a = p.parse_args()
    if a.phase == 'prepare':
        target = prepare(plain(a.root), plain(a.build), a.output, a.debugger_profile, a.registration_review)
        print(str(target))
        print(digest(target))
    else:
        validate(a.plan, a.sha, plain(a.root))
        print('TARGET_PLAN_VALIDATED_NO_RUNTIME')
