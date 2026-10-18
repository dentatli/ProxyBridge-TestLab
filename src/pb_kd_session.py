"""Files-only diagnostic plans sharing verified assets; never starts product or debugger."""
import argparse
import json
from pathlib import Path
import re
import uuid
from datetime import datetime, timezone

from pb_prepare_kd_baseline import PINNED, digest, plain

METHOD = 'redirect-kd-session-v1'
SHAPES = {
    'four': dict(phase_connections=[4], load_levels=[], client_wait_limit_ms=60000,
                 cohort_budget_ms=180000, cohort_module='KdQueryProbeConnectionLoad'),
    'bounded256': dict(phase_connections=[4, 64, 256, 4], load_levels=[64, 256],
                       client_wait_limit_ms=120000, cohort_budget_ms=240000,
                       cohort_module='KdQueryBoundedConnectionLoad'),
}
SOURCE_FILES = (
    'scripts/Invoke-KdSession.ps1', 'scripts/Invoke-KdSessionWorkload.ps1',
    'src/pb_kd_session.py', 'src/pb_kd_session_report.py', 'src/pb_prepare_kd_baseline.py',
    'src/pb_tcp_redirect_context_report.py', 'src/pb_tcp_connections_report.py',
    'src/pb_tcp_kernel_timing_report.py', 'src/pb_controlled_tcp_proxy.py',
    'src/pb_pc_sampler.py', 'src/pb_proactor_close_guard.py', 'config/runtime.json',
    'src/pb_etw_redirect_report.py',
)
BOOT_FIELDS = ('computer', 'provider', 'event_id', 'event_record_id', 'event_time_utc',
               'start_time_utc', 'prefetch_boot_id')


def read(path):
    path = plain(Path(path))
    if path.stat().st_size > 16 * 1024 * 1024:
        raise ValueError('KD_SESSION_JSON_TOO_LARGE')
    return json.loads(path.read_text(encoding='utf-8-sig'))


def save(path, value):
    # Exclusive creation: a plan or shared manifest is never refrozen in place.
    with path.open('x', encoding='utf-8', newline='\n') as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')


def snapshot(source, target):
    """Keep the exact reviewed bytes, including JSON whitespace and BOM."""
    data = plain(Path(source)).read_bytes()
    with target.open('xb') as stream:
        stream.write(data)


def checked(path, expected):
    path = plain(Path(path))
    if not re.fullmatch('[a-fA-F0-9]{64}', expected) or digest(path) != expected.lower():
        raise ValueError('KD_SESSION_SHA_CHANGED: ' + str(path))
    return path


def check_files(files):
    seen = set()
    for item in files:
        path = checked(item['path'], item['sha256'])
        key = str(path).casefold()
        if key in seen:
            raise ValueError('KD_SESSION_DUPLICATE_FILE')
        seen.add(key)
    return seen


def inventory(paths):
    return [dict(path=str(p), sha256=digest(p)) for p in sorted(set(map(plain, paths))) ]


def boot_identity(evidence):
    identity = evidence['identity']
    if (evidence['method'] != 'kernel-general-12-and-prefetch-bootid-v1'
            or evidence['cryptographic_boot_identity']
            or identity['provider'] != 'Microsoft-Windows-Kernel-General'
            or identity['event_id'] != 12):
        raise ValueError('KD_SESSION_BOOT_EVIDENCE_INVALID')
    return {key: identity[key] for key in BOOT_FIELDS}


def policy(workload, profile):
    if workload not in SHAPES:
        raise ValueError('KD_SESSION_WORKLOAD_UNSUPPORTED')
    lifecycle = profile.get('driver_lifecycle', 'unload')
    if lifecycle not in ('unload', 'resident-disabled'):
        raise ValueError('KD_SESSION_DRIVER_LIFECYCLE_INVALID')
    ids = profile['active_point_ids']
    registered = profile['registered_point_ids']
    inactive = profile['inactive_point_ids']
    etw = profile['method'] == 'etw-tcpip-redirect-v1'
    if etw and (ids or lifecycle != 'resident-disabled' or profile.get('observer') != 'etw-tcpip'):
        raise ValueError('KD_SESSION_ETW_PROFILE_INVALID')
    if ((not ids and not etw) or len(set(ids)) != len(ids) or len(set(registered)) != len(registered)
            or sorted(ids + inactive) != sorted(registered)
            or set(ids) & set(inactive) or any(type(i) is not int or i < 0 for i in registered)
            or profile['point_count_active'] != len(ids)
            or {p['id'] for p in profile['points']} != set(registered)
            or len(profile['points']) != len(registered)
            or profile['automatic_debugger_control'] or profile['load_authorized']
            or profile['root_cause_proven']):
        raise ValueError('KD_SESSION_DEBUGGER_PROFILE_INVALID')
    result = dict(method=METHOD, workload=workload, **SHAPES[workload],
                total_connections=sum(SHAPES[workload]['phase_connections']), hold_seconds=8,
                final_four_same_session=workload != 'four', connect_method='ConnectEx', pending_limit=32,
                original_single_query=True, listener_case='original', listener_delay_ms=0,
                debugger_points=profile['method'], active_point_ids=ids,
                registered_point_ids=registered, inactive_point_ids=inactive,
                logger_verification_required_before_load=True, load_authorized=False,
                driver_installation=False, automatic_debugger_control=False,
                diagnostic_only=True, performance_comparable=False)
    if lifecycle == 'resident-disabled':
        result['driver_lifecycle'] = lifecycle
    if etw:
        result.update(observer='etw-tcpip', logger_verification_required_before_load=False,
                      etw_provider='2f07e2ee-15db-40f1-90ef-9d7ba282188a',
                      etw_keywords='0x2080', etw_level=5)
    return result


def register_assets(root, seed_plan, expected_sha):
    """Register references to an existing frozen runtime. No copy, link, or mutation."""
    seed_plan = checked(seed_plan, expected_sha)
    seed = read(seed_plan)
    if Path(seed['root']) != root or Path(seed['preparation']) != seed_plan.parent:
        raise ValueError('KD_SESSION_SEED_ROOT_DIFFERS')
    check_files(seed['files'])
    runtime_manifest = seed_plan.parent / 'runtime/manifest.json'
    checked(runtime_manifest, seed['runtime_manifest_sha256'])
    runtime = runtime_manifest.parent / 'python'
    source = read(runtime_manifest)
    if (not source['isolated_pth'] or source['import_site'] or source['source_runtime_reused_at_run']):
        raise ValueError('KD_SESSION_RUNTIME_NOT_ISOLATED')
    kit = seed_plan.parent / 'kit'
    for name, sha in PINNED.items():
        checked(kit / name, sha)
    bins = [Path(f['path']) for f in seed['files']
            if Path(f['path']).is_relative_to(root / 'bin')]
    assets = dict(schema_version=1, method='kd-shared-assets-v1', root=str(root),
                  seed_plan=dict(path=str(seed_plan), sha256=digest(seed_plan)),
                  runtime_manifest=dict(path=str(runtime_manifest), sha256=digest(runtime_manifest)),
                  python=str(runtime / 'python.exe'), kit=str(kit), files=inventory(
                      bins + [kit / n for n in (*PINNED, 'product.env', 'redirect-context-diagnostic.json')]))
    directory = root / 'artifacts/diagnostics/pb-kd-shared-assets'
    plain(directory).mkdir(exist_ok=True)
    key = digest(seed_plan)
    target = directory / (key + '.json')
    if target.exists():
        if read(target) != assets:
            raise ValueError('KD_SESSION_SHARED_MANIFEST_COLLISION')
    else:
        save(target, assets)
    validate_assets(target, digest(target), root)
    return target


def validate_assets(path, expected_sha, root):
    assets = read(checked(path, expected_sha))
    if assets['method'] != 'kd-shared-assets-v1' or Path(assets['root']) != root:
        raise ValueError('KD_SESSION_ASSET_ROOT_DIFFERS')
    manifest = assets['runtime_manifest']
    runtime_manifest = checked(manifest['path'], manifest['sha256'])
    runtime = runtime_manifest.parent / 'python'
    data = read(runtime_manifest)
    if (not data['isolated_pth'] or data['import_site'] or data['source_runtime_reused_at_run']
            or Path(assets['python']) != runtime / 'python.exe'):
        raise ValueError('KD_SESSION_RUNTIME_NOT_ISOLATED')
    files = data['files']
    actual = {p.relative_to(runtime).as_posix() for p in runtime.rglob('*') if p.is_file()}
    if actual != set(files) or len(files) != data['copied_files']:
        raise ValueError('KD_SESSION_RUNTIME_INVENTORY_CHANGED')
    for relative, sha in files.items():
        p = plain(runtime / relative)
        if not p.resolve().is_relative_to(runtime.resolve()):
            raise ValueError('KD_SESSION_RUNTIME_PATH_ESCAPE')
        checked(p, sha)
    check_files(assets['files'])
    for name, sha in PINNED.items():
        checked(Path(assets['kit']) / name, sha)
    return assets


def validate_review(review, profile, profile_sha, boot, workload):
    if (review['schema_version'] != 1 or not review['registration_reviewed']
            or review['profile_sha256'] != profile_sha or review['boot_identity'] != boot_identity(boot)
            or workload not in review['allowed_workloads'] or not review['evidence_files']
            or review['root_cause_proven'] or review['automatic_debugger_control']):
        raise ValueError('KD_SESSION_REVIEW_OR_WORKLOAD_NOT_APPROVED')
    policy(workload, profile)
    check_files(review['evidence_files'])
    # A bounded plan needs an explicit prior probe review, not just a new switch.
    if workload != 'four':
        prior = review['prior_four_review']
        if (not prior['native_probe_complete'] or prior['profile_sha256'] != profile_sha
                or prior['boot_identity'] != boot_identity(boot)):
            raise ValueError('KD_SESSION_PRIOR_FOUR_REQUIRED')
        checked(prior['path'], prior['sha256'])


def prepare(root, assets_path, assets_sha, profile_path, review_path, boot_path, workload):
    assets = validate_assets(assets_path, assets_sha, root)
    profile, review, boot = read(profile_path), read(review_path), read(boot_path)
    validate_review(review, profile, digest(profile_path), boot, workload)
    control = policy(workload, profile)
    stamp = datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')
    target = root / ('artifacts/diagnostics/pb-kd-session-plan-' + stamp + '-' + uuid.uuid4().hex[:8])
    plain(target).mkdir()
    snapshot(profile_path, target / 'debugger-profile.json')
    snapshot(review_path, target / 'registration-review.json')
    snapshot(boot_path, target / 'boot-session.json')
    kit = target / 'kit'
    kit.mkdir()
    receipt = read(Path(assets['kit']) / 'redirect-context-diagnostic.json')
    receipt.update(method=METHOD, control_policy=control)
    save(kit / 'redirect-context-diagnostic.json', receipt)
    # Only small metadata files are created. Product binaries stay in the shared kit.
    env = (Path(assets['kit']) / 'product.env').read_text(encoding='utf-8-sig')
    env = re.sub(r'(?m)^PB_TESTLAB_REDIRECT_CONTEXT_DIAGNOSTIC=.*$',
                 'PB_TESTLAB_REDIRECT_CONTEXT_DIAGNOSTIC=' + METHOD, env)
    (kit / 'product.env').write_text(env, encoding='utf-8', newline='\n')
    paths = [root / p for p in SOURCE_FILES] + list((root / 'modules').glob('*.psm1'))
    paths += [profile_path, review_path, assets_path, *target.glob('*.json'), *kit.iterdir()]
    paths += [Path(f['path']) for f in review['evidence_files']]
    paths += [Path(r'C:\Windows\System32') / p for p in ('ntoskrnl.exe', 'drivers/tcpip.sys', 'drivers/fwpkclnt.sys')]
    if workload != 'four':
        paths.append(Path(review['prior_four_review']['path']))
    plan = dict(schema_version=1, method=METHOD, root=str(root), preparation=str(target),
                diagnostic_only=True, performance_comparable=False, control_policy=control,
                assets=dict(path=str(assets_path), sha256=assets_sha.lower()), python=assets['python'],
                files=inventory(paths))
    save(target / 'runtime-plan.json', plan)
    validate(target / 'runtime-plan.json', digest(target / 'runtime-plan.json'), root)
    return target / 'runtime-plan.json'


def validate(plan_path, expected_sha, root):
    plan_path = checked(plan_path, expected_sha)
    plan = read(plan_path)
    if (plan['method'] != METHOD or plan['schema_version'] != 1 or Path(plan['root']) != root
            or Path(plan['preparation']) != plan_path.parent or not plan['diagnostic_only']
            or plan['performance_comparable'] or not re.fullmatch(
                r'pb-kd-session-plan-\d{8}-\d{6}-[a-f0-9]{8}', plan_path.parent.name)
            or plan_path.parent.parent != root / 'artifacts/diagnostics'):
        raise ValueError('KD_SESSION_PLAN_INVALID')
    frozen = check_files(plan['files'])
    required = [root / p for p in SOURCE_FILES] + list((root / 'modules').glob('*.psm1'))
    required += [plan_path.parent / p for p in ('debugger-profile.json', 'registration-review.json',
                 'boot-session.json', 'kit/product.env', 'kit/redirect-context-diagnostic.json')]
    required += [Path(plan['assets']['path'])]
    required += [Path(r'C:\Windows\System32') / p for p in
                 ('ntoskrnl.exe', 'drivers/tcpip.sys', 'drivers/fwpkclnt.sys')]
    if any(str(p).casefold() not in frozen for p in required):
        raise ValueError('KD_SESSION_CONTRACT_NOT_FROZEN')
    assets = validate_assets(plan['assets']['path'], plan['assets']['sha256'], root)
    if plan['python'] != assets['python']:
        raise ValueError('KD_SESSION_PYTHON_DIFFERS')
    base = plan_path.parent
    profile, review, boot = (read(base / p) for p in ('debugger-profile.json', 'registration-review.json', 'boot-session.json'))
    validate_review(review, profile, digest(base / 'debugger-profile.json'), boot, plan['control_policy']['workload'])
    if plan['control_policy'] != policy(plan['control_policy']['workload'], profile):
        raise ValueError('KD_SESSION_POLICY_DIFFERS')
    receipt = read(base / 'kit/redirect-context-diagnostic.json')
    if receipt['method'] != METHOD or receipt['control_policy'] != plan['control_policy']:
        raise ValueError('KD_SESSION_RECEIPT_DIFFERS')
    return plan


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    assets = sub.add_parser('register-assets')
    assets.add_argument('--seed-plan', type=Path, required=True)
    assets.add_argument('--expected-sha', required=True)
    prep = sub.add_parser('prepare')
    for name in ('assets', 'profile', 'review', 'boot'):
        prep.add_argument('--' + name, type=Path, required=True)
    prep.add_argument('--assets-sha', required=True)
    prep.add_argument('--workload', choices=SHAPES, default='four')
    check = sub.add_parser('validate')
    check.add_argument('--plan', type=Path, required=True)
    check.add_argument('--expected-sha', required=True)
    for p in (assets, prep, check):
        p.add_argument('--root', type=Path, required=True)
    args = parser.parse_args()
    root = plain(args.root)
    if args.action == 'register-assets':
        path = register_assets(root, args.seed_plan, args.expected_sha)
    elif args.action == 'prepare':
        path = prepare(root, args.assets, args.assets_sha, args.profile, args.review, args.boot, args.workload)
    else:
        print(json.dumps(validate(args.plan, args.expected_sha, root)))
        return
    print(json.dumps(dict(path=str(path), sha256=digest(path), product_started=False,
                          traffic_generated=False, debugger_control=False)))


if __name__ == '__main__':
    main()
