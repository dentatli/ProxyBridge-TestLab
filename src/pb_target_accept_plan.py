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
    if (p['method'] != 'target-accept-session-v1' or Path(p['root']) != root or
            Path(p['preparation']) != plan_path.parent or
            plan_path.parent.parent != root / 'artifacts/diagnostics' or p['policy'] != POLICY):
        raise ValueError('TARGET_PLAN_CONTRACT_INVALID')
    check_files(p['files'])
    verify_build(root, Path(p['build']))
    assets = validate_assets(Path(p['assets']), ASSETS_SHA, root)
    if p['python'] != assets['python'] or p['core_sha256'] != CORE:
        raise ValueError('TARGET_RUNTIME_BINDING_DIFFERS')
    boot_identity(read(plan_path.parent / 'boot-session.json'))
    return p


def prepare(root, build, output):
    output = plain(output)
    if output.parent != root / 'artifacts/diagnostics' or set(output.iterdir()) != {output / 'boot-session.json'}:
        raise ValueError('TARGET_FRESH_PLAN_DIRECTORY_REQUIRED')
    verify_build(root, build)
    assets_path = root / 'artifacts/diagnostics/pb-kd-shared-assets' / ASSETS
    assets = validate_assets(assets_path, ASSETS_SHA, root)
    paths = (list((root / 'modules').glob('*.psm1')) + list((root / 'src').glob('*.py')) +
             list((root / 'src').glob('*.cs')))
    paths += [root / 'scripts/Invoke-TargetAccept.ps1', output / 'boot-session.json',
              build / 'preparation.json', build / 'verification/build-result.json']
    paths += list((build / 'kit').glob('*'))
    paths += [root / 'bin/pb_console_host.exe', root / 'config/runtime.json']
    paths += [root / 'bin/tools/windivert-2.2.2/windivertctl.exe', root / 'bin/tools/windivert-2.2.2/WinDivert.dll']
    plan = dict(method='target-accept-session-v1', root=str(root), preparation=str(output), build=str(build),
                assets=str(assets_path), python=assets['python'], core_sha256=CORE, policy=POLICY, files=inventory(paths))
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
    a = p.parse_args()
    if a.phase == 'prepare':
        target = prepare(plain(a.root), plain(a.build), a.output)
        print(str(target))
        print(digest(target))
    else:
        validate(a.plan, a.sha, plain(a.root))
        print('TARGET_PLAN_VALIDATED_NO_RUNTIME')
