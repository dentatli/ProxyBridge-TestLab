"""Compare two saved, explicitly bound STANDARD TCP RTT series; generate no traffic."""
import argparse
from copy import deepcopy
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import statistics

from pb_tcp_rtt_report import evaluate_run, read


QUANTILES = ('p50_ms', 'p95_ms', 'p99_ms')
RUN_FIELDS = {'run_id', 'receiver_pid', 'proxy_pid', 'sampler_pid'}
VERSION_FIELDS = {'product_contract', 'route_profile_sha256', 'legacy_rtt_stage', 'version_rtt_stage'}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def common_profile(profile):
    """Only absent legacy domain fields equal the explicitly disabled Driver fields."""
    result = deepcopy(profile)
    for proxy in result['ProxyConfigs']:
        require(proxy.get('SendDomainToProxy', False) is False, 'Domain forwarding enabled')
        proxy.pop('SendDomainToProxy', None)
    for rule in result['ProxyRules']:
        require(rule.get('TargetDomains', '') == '', 'Domain rule present')
        rule.pop('TargetDomains', None)
    return result


def load_series(root, contract):
    manifest = read(root/'comparison-manifest.json')
    aggregate = read(root/'comparison-report.json')
    require(manifest['status'] == 'COMPLETED' and not manifest['error'] and
            manifest['profile'] == 'STANDARD' and manifest['pair_count'] == 3 and
            manifest['product_contract'] == contract and len(manifest['runs']) == 6 and
            aggregate['status'] == 'LIMITED_COMPARISON' and not aggregate['errors'] and len(aggregate['runs']) == 6,
            f'{contract}: incomplete source series')
    runs, contexts, products, fingerprints, pairs = [], [], [], [], []
    for index, entry in enumerate(manifest['runs']):
        pair = index//2 + 1
        modes = ('OFF', 'PROXY') if pair % 2 else ('PROXY', 'OFF')
        require(entry['pair'] == pair and entry['mode'] == modes[index % 2] and
                entry['status'] == 'COMPLETED', f'{contract}: unexpected pair order/status')
        path = (root/entry['directory']).resolve()
        require(path.parent == root, 'Run directory must be an immediate child of source series')
        report = evaluate_run(path)
        require(report == read(path/'tcp-rtt-report.json') and
                aggregate['runs'][index] == dict(**entry, report=report),
                f'{contract}/{entry["directory"]}: saved evaluation changed')
        require(report['status'] == 'MEASURED' and report['correctness'] == 'PASS' and
                not report['errors'] and report['mode'] == entry['mode'],
                f'{contract}: evidence not confirmed')
        cfg = report['config']
        require(cfg['product_contract'] == contract and not cfg.get('load') and
                cfg.get('legacy_rtt_stage' if contract == 'v4.0.0' else 'version_rtt_stage') == 'repeat_rtt_v1',
                'Only explicitly bound repeated RTT stages can be compared')
        require((cfg['scenario_id'], cfg['echo_count'], cfg['warmup_count'], cfg['message_bytes'],
                 cfg['pause_ms'], cfg['connections']) == ('tcp_echo_rtt_v1', 1000, 200, 512, 20, 1),
                'Unexpected RTT workload')
        for key in ('echo_count', 'warmup_count', 'message_bytes', 'pause_ms'):
            require(cfg[key] == manifest[key], 'Requested and measured workload differs')
        context, product = read(path/'version-context.json'), read(path/'product-build.json')
        require(product['files_verified'] and product['selected_contract'] == contract and
                product['declared_cli_variant'] == 'testlab-unbuffered-v1', 'Selected kit not confirmed')
        if report['mode'] == 'PROXY':
            profile = path/'route.pbprofile'
            require(digest(profile) == cfg['route_profile_sha256'].lower(), 'Profile hash changed')
            fingerprints.append(common_profile(read(profile)))
        hashes = {f.name: digest(f) for f in sorted(path.iterdir()) if f.is_file()}
        runs.append(dict(pair=pair, directory=str(path), report=report, evidence_sha256=hashes))
        contexts.append(context)
        products.append(product)
    conditions = [{k: v for k, v in r['report']['config'].items() if k not in RUN_FIELDS} for r in runs]
    require(all(c == conditions[0] for c in conditions), 'Within-version configuration differs')
    require(all(c == contexts[0] for c in contexts), 'Within-version context differs')
    require(all(p['bundle_sha256'] == products[0]['bundle_sha256'] and
                p['declared_source_commit'] == products[0]['declared_source_commit'] and
                p['components'] == products[0]['components'] for p in products), 'Within-version kit differs')
    require(len(fingerprints) == 3 and all(p == fingerprints[0] for p in fingerprints), 'Route rules differ')
    for pair in range(1, 4):
        group = [r['report'] for r in runs if r['pair'] == pair]
        off, on = [next(r['rtt'] for r in group if r['mode'] == mode) for mode in ('OFF', 'PROXY')]
        pairs.append(dict(pair=pair, **{k: on[k]-off[k] for k in QUANTILES}))
    require(pairs == aggregate['pairs'], 'Saved paired deltas changed')
    values = [r['report'] for r in runs]
    modes = {}
    for mode in ('OFF', 'PROXY'):
        group = [r for r in values if r['mode'] == mode]
        modes[mode] = {k: statistics.median(r['rtt'][k] for r in group) for k in QUANTILES}
        modes[mode]['max_ms'] = max(r['rtt']['max_ms'] for r in group)
        modes[mode]['system_cpu_pct_mean_median'] = statistics.median(r['system']['cpu_pct_mean'] for r in group)
    cli = {k: statistics.median(r['pc']['proxybridge_cli'][k] for r in values if r['mode'] == 'PROXY')
           for k in ('cpu_pct_machine_mean', 'private_mib_mean')}
    observation_gaps = [r['report']['measurement_start_qpc_ms'] -
                        read(Path(r['directory'])/'live-socket-observation.json')['capture_completed_qpc_ms'] for r in runs]
    return dict(directory=str(root), config=conditions[0], context=contexts[0], product=products[0],
                route_profile=fingerprints[0], runs=runs, modes=modes, pairs=pairs, cli=cli,
                paired_addition_ms={k: statistics.median(p[k] for p in pairs) for k in QUANTILES},
                verified_echoes=sum(r['verified_echoes'] for r in values),
                measured_echoes=sum(r['measured_echoes'] for r in values),
                failed_echoes=sum(r['failed_echoes'] for r in values),
                responses_above_20ms=sum(r['rtt']['responses_above_20ms'] for r in values),
                minimum_capture_gap_ms=min(observation_gaps),
                minimum_pc_coverage_pct=min(100*r['system']['coverage_ms']/
                    (r['measurement_end_qpc_ms']-r['measurement_start_qpc_ms']) for r in values),
                source_sha256={f: digest(root/f) for f in ('comparison-manifest.json', 'comparison-report.json')})


def compare(legacy_root, driver_root):
    legacy, driver = load_series(legacy_root, 'v4.0.0'), load_series(driver_root, 'driver')
    require({k: v for k, v in legacy['config'].items() if k not in VERSION_FIELDS} ==
            {k: v for k, v in driver['config'].items() if k not in VERSION_FIELDS},
            'Cross-version traffic/tool/socket conditions differ')
    require(legacy['route_profile'] == driver['route_profile'], 'Cross-version profile constraints differ')
    dc, lc = driver['context'], legacy['context']
    require(Path(dc['legacy_rtt_directory']).resolve() == legacy_root and
            dc['legacy_boot_identity'] == lc['boot_identity'], 'Driver references a different legacy series/boot')
    require(dc['reboot_between_versions_observed'] and
            all(dc['boot_identity'][k] == lc['boot_identity'][k] for k in ('machine_guid', 'os_build', 'computer_name')) and
            datetime.fromisoformat(dc['boot_identity']['boot_time_utc']) >
            datetime.fromisoformat(lc['boot_identity']['boot_time_utc']), 'Same VM/OS and new boot not confirmed')
    require(datetime.fromisoformat(read(legacy_root/'comparison-manifest.json')['completed_at_utc']) <
            datetime.fromisoformat(dc['boot_identity']['boot_time_utc']), 'Driver boot must follow completed legacy series')
    all_runs = legacy['runs'] + driver['runs']
    require(len({r['report']['config']['run_id'] for r in all_runs}) == 12, 'Run identities reused')
    require(len({r['report']['other_driver_names_sha256'] for r in all_runs}) == 1, 'Other loaded driver names changed')
    preflight_path = Path(lc['legacy_idle_directory']).resolve().parent/'preflight.json'
    preflight = read(preflight_path)
    require(preflight['status'] == 'FILES_AND_PROFILES_PREPARED' and
            preflight['switch_policy'] == 'reboot_between_versions', 'Version preflight not confirmed')
    for series, contract in ((legacy, 'v4.0.0'), (driver, 'driver')):
        selected = [p for p in preflight['products'] if p['contract'] == contract]
        require(len(selected) == 1, 'Preflight product selection ambiguous')
        p = selected[0]
        require(p['receipt_chain_verified'] and p['base_components_unchanged'] and
                all(series['product'][k] == p['identity'][k] for k in
                    ('bundle_sha256', 'declared_source_commit', 'declared_cli_variant', 'components')) and
                digest(Path(p['env_path']).parent/'build-receipt.json') == p['build_receipt_sha256'],
                'Kit/source receipt binding changed')
        profile_name = contract+'-tcp.pbprofile'
        profiles = [r for r in preflight['profile_files'] if r['file_name'] == profile_name]
        require(len(profiles) == 1 and profiles[0]['sha256'] == series['config']['route_profile_sha256'].lower() and
                digest(preflight_path.parent/profile_name) == profiles[0]['sha256'], 'Preflight profile binding changed')
    require(preflight['products'][0]['cli_changes'] == preflight['products'][1]['cli_changes'], 'CLI adaptations differ')
    difference = {k: driver['paired_addition_ms'][k]-legacy['paired_addition_ms'][k] for k in QUANTILES}
    return dict(schema_version=1, status='LIMITED_VERSION_COMPARISON', errors=[],
                created_at_utc=datetime.now(timezone.utc).isoformat(), legacy=legacy, driver=driver,
                driver_minus_legacy_addition_ms=difference,
                preflight=dict(path=str(preflight_path), sha256=digest(preflight_path)),
                analysis_sha256={p.name: digest(p) for p in
                    (Path(__file__), Path(__file__).with_name('pb_tcp_rtt_report.py'),
                     Path(__file__).with_name('pb_tcp_benchmark_report.py'))},
                version_switch_ready=False, global_cleanup_verified=False, latest_driver_head_verified=False,
                limitations=['Three within-version counterbalanced pairs; one version order across two boots, no confidence interval.',
                             'Local IPv4 persistent sequential TCP echo, one request in flight; not ICMP/game/capacity/remote/long-soak evidence.',
                             'Full SOCKS5 path including helper and controlled receiver; quantile differences are not quantiles of per-packet overhead.',
                             'Legacy OFF retains idle loaded WinDivert with zero observed compatible handles; Driver OFF has no known loaded interceptors.',
                             'CLI CPU is sampled whole-machine percent; private RAM is not whole-product/driver usage or watts.',
                             'Pinned declared kit revisions and existing build receipts; not latest HEAD or independently reproduced source-release binaries.'])


def summary(result):
    rows = ['# Сравнение задержек ProxyBridge / ProxyBridge latency comparison', '',
            '**'+result['status']+'**', '',
            'Локальный TCP через SOCKS5, три пары с прямым трафиком на версию. / Local TCP via SOCKS5, three direct/proxy pairs per version.', '',
            '| Метрика / Metric | 4.0.0 | Driver '+result['driver']['product']['declared_source_commit'][:7]+' |',
            '|---|---:|---:|']
    for mode, label in (('OFF', 'Напрямую / Direct'), ('PROXY', 'Через SOCKS5 / Via SOCKS5')):
        for key in QUANTILES:
            rows.append(f"| {label}, {key[:-3]}, ms | {result['legacy']['modes'][mode][key]:.3f} | {result['driver']['modes'][mode][key]:.3f} |")
    for key in QUANTILES:
        rows.append(f"| Добавка / Paired addition, {key[:-3]}, ms | {result['legacy']['paired_addition_ms'][key]:+.3f} | {result['driver']['paired_addition_ms'][key]:+.3f} |")
    for key, label, precision in (('cpu_pct_machine_mean', 'CLI CPU, % ПК / machine', 3),
                                  ('private_mib_mean', 'CLI private RAM, MiB', 2)):
        rows.append(f"| {label} | {result['legacy']['cli'][key]:.{precision}f} | {result['driver']['cli'][key]:.{precision}f} |")
    rows += ['', 'Показатели — медианы трёх прогонов; добавка — медиана трёх разностей PROXY−OFF внутри пар. / Median run quantiles and median within-pair differences.', '',
             'Изменение добавки Driver−4.0.0 / Change in paired addition: '+
             ', '.join(f"{k[:-3]} {result['driver_minus_legacy_addition_ms'][k]:+.3f} ms" for k in QUANTILES)+'.', '',
             'Прогрев 200 обменов, 512 байт, пауза 20 ms после ответа; один постоянный сокет. Socket snapshot завершён до измерений. / Warmup and socket observation excluded.', '',
             'Вывод относится к этому локальному сценарию и конкретным комплектам. Версии запущены после разных загрузок Windows в одном порядке; фон VM мог меняться. OFF 4.0.0 сохраняет загруженный WinDivert без наблюдаемых дескрипторов. / Single cross-boot version order; background VM activity and idle driver baselines differ.', '',
             'Это полный RTT прикладного запроса через SOCKS5 и получателя. ICMP ping, игры, предельная скорость, длительная стабильность, remote, driver-only CPU и ватты этим сравнением не подтверждены. / Limited application RTT and sampled CLI resources.', '',
             'Стендовые CLI обеих версий имеют одинаковые минимальные изменения вывода/остановки; Core и драйверы сохранены из выбранных комплектов. Driver закреплён, актуальность HEAD и независимая воспроизводимость сборок не проверены. / Same CLI adaptation, pinned kits; latest HEAD and independent build reproduction unverified.', '',
             'Исходные отчёты сохранены. Технические свидетельства и ограничения — comparison-report.json. / Original evidence preserved; details in comparison-report.json.', '']
    counts = ['']
    for name, series in (('4.0.0', result['legacy']), ('Driver', result['driver'])):
        counts.append(f"{name}: измеренных / measured {series['measured_echoes']}; подтверждено с прогревом / verified incl. warmup {series['verified_echoes']}; ошибок / failures {series['failed_echoes']}; ответы / responses >20 ms {series['responses_above_20ms']}.")
    rows[4:4] = counts + ['']
    return '\n'.join(rows)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--legacy-directory', type=Path, required=True)
    parser.add_argument('--driver-directory', type=Path, required=True)
    parser.add_argument('--output-directory', type=Path, required=True)
    args = parser.parse_args()
    try:
        output = args.output_directory.resolve()
        legacy, driver = args.legacy_directory.resolve(), args.driver_directory.resolve()
        require(not output.exists() and not output.is_relative_to(legacy) and not output.is_relative_to(driver) and
                not legacy.is_relative_to(output) and not driver.is_relative_to(output), 'Output must be a new directory outside source series')
        result = compare(legacy, driver)
        output.mkdir(parents=True, exist_ok=False)
        (output/'comparison-report.json').write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding='utf-8')
        (output/'summary.md').write_text(summary(result), encoding='utf-8')
        print(json.dumps(dict(status=result['status'], errors=[], directory=str(output))))
    except (ValueError, KeyError, IndexError, TypeError, OSError) as exc:
        print(json.dumps(dict(status='INCONCLUSIVE', errors=[str(exc)])))
        raise SystemExit(1)
