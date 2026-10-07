"""Compare saved, explicitly bound STANDARD data transfers; generate no traffic."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import statistics

from pb_tcp_benchmark_report import evaluate_run
from pb_tcp_transfer_reference import digest, profile_constraints, read, require


RUN_FIELDS = {'direction', 'receiver_pid', 'proxy_pid', 'sampler_pid'}
VERSION_FIELDS = {'product_contract', 'product_label', 'route_profile_sha256',
                  'legacy_transfer_stage', 'version_transfer_stage', 'legacy_transfer_directory',
                  'driver_transfer_directory', 'driver_smoke_directory'}
WORKLOAD = (2147483648, 67108864, 1, 65536, 'data')


def snapshot(root):
    return {str(p.relative_to(root)): digest(p) for p in sorted(root.rglob('*')) if p.is_file()}


def load_series(root, contract):
    manifest, aggregate = [read(root / name) for name in ('comparison-manifest.json', 'comparison-report.json')]
    stage = 'data-transfer-repeat-legacy-v1' if contract == 'v4.0.0' else 'data-transfer-repeat-v1'
    require(manifest['status'] == 'COMPLETED' and not manifest['error'] and
            manifest['profile'] == 'STANDARD' and manifest['pair_count'] == 3 and
            manifest['product_contract'] == contract and len(manifest['runs']) == 12 and
            manifest['version_transfer_stage'] == stage and manifest['transfer_only'] is True and
            manifest['shutdown_mode'] == 'rude' and manifest['normal_tcp_close_verified'] is False and
            manifest['readiness_only'] is False and not manifest.get('resumed_at_utc') and
            not manifest.get('diagnostic_only') and not manifest.get('failed_attempts') and
            aggregate['status'] == 'LIMITED_COMPARISON' and not aggregate['errors'] and
            aggregate['version_reference_bound'] is True and len(aggregate['runs']) == 12,
            f'{contract}: complete fresh bound STANDARD data-only series required')
    require(tuple(manifest[k] for k in ('transfer_bytes', 'rate_limit_bytes_per_s', 'connections', 'buffer_bytes', 'verify')) == WORKLOAD,
            'Requested workload differs')
    reports, contexts, products, conditions, profiles, pairs = [], [], [], [], [], []
    for index, entry in enumerate(manifest['runs']):
        direction, pair = ('push' if index < 6 else 'pull'), (index % 6) // 2 + 1
        order = ('OFF', 'PROXY') if pair % 2 else ('PROXY', 'OFF')
        require(entry['direction'] == direction and entry['pair'] == pair and
                entry['mode'] == order[index % 2] and entry['status'] == 'COMPLETED',
                'Counterbalanced order or run status differs')
        path = (root / entry['directory']).resolve()
        require(path.parent == root, 'Run must be an immediate child of source series')
        report = evaluate_run(path)
        require(report == read(path / 'tcp-benchmark-report.json') and
                aggregate['runs'][index] == dict(**entry, report=report) and
                report['status'] == 'MEASURED' and not report['errors'] and
                report['version_reference_bound'] is True and report['readiness_only'] is False and
                report['normal_tcp_close_verified'] is False and
                report['mode'] == entry['mode'] and report['direction'] == direction and
                report['verified_payload_bytes'] == WORKLOAD[0],
                f'{contract}/{entry["directory"]}: saved verdict or evidence differs')
        cfg = report['config']
        require(tuple(cfg[k] for k in ('transfer_bytes', 'rate_limit_bytes_per_s', 'connections', 'buffer_bytes', 'verify')) == WORKLOAD and
                cfg['product_contract'] == contract and cfg['version_transfer_stage'] == stage and
                cfg['transfer_profile'] == 'STANDARD' and cfg['transfer_only'] is True and
                cfg['shutdown_mode'] == 'rude' and cfg['console_verbosity'] == 1 and
                cfg['tcp_shutdown_policy'] == 'data-transfer-only-v1', 'Measured workload differs')
        conditions.append({k: v for k, v in cfg.items() if k not in RUN_FIELDS})
        contexts.append(read(path / 'version-context.json'))
        product = read(path / 'product-build.json')
        require(product['files_verified'] and product['selected_contract'] == contract and
                product['declared_cli_variant'] == 'testlab-unbuffered-v1', 'Selected kit not verified')
        products.append(product)
        if entry['mode'] == 'PROXY':
            require(digest(path / 'route.pbprofile') == cfg['route_profile_sha256'].lower(), 'Route profile hash changed')
            profiles.append(profile_constraints(path / 'route.pbprofile'))
        reports.append(dict(**entry, report=report))
    require(all(c == conditions[0] for c in conditions) and all(c == contexts[0] for c in contexts),
            'Within-version configuration or context differs')
    require(all(all(p[k] == products[0][k] for k in ('bundle_sha256', 'declared_source_commit', 'components')) for p in products),
            'Within-version kit differs')
    require(len(profiles) == 6 and all(p == profiles[0] for p in profiles), 'Route constraints differ')
    metrics = {}
    for direction in ('push', 'pull'):
        group = [r['report'] for r in reports if r['direction'] == direction]
        direction_pairs = []
        for pair in range(1, 4):
            selected = [r['report'] for r in reports if r['direction'] == direction and r['pair'] == pair]
            off, on = [next(r for r in selected if r['mode'] == mode) for mode in ('OFF', 'PROXY')]
            change = 100 * (on['useful_mbit_per_s'] / off['useful_mbit_per_s'] - 1)
            p = dict(direction=direction, pair=pair, rate_change_pct=change)
            direction_pairs.append(p)
            pairs.append(p)
        metrics[direction] = dict(
            mode_medians={mode: statistics.median(r['useful_mbit_per_s'] for r in group if r['mode'] == mode) for mode in ('OFF', 'PROXY')},
            paired_change_pct_median=statistics.median(p['rate_change_pct'] for p in direction_pairs),
            paired_change_pct_range=[min(p['rate_change_pct'] for p in direction_pairs), max(p['rate_change_pct'] for p in direction_pairs)],
            cli={key: statistics.median(r['pc']['proxybridge_cli'][key] for r in group if r['mode'] == 'PROXY')
                 for key in ('cpu_pct_machine_mean', 'private_mib_mean')})
    require(pairs == aggregate['pairs'], 'Saved paired rate changes differ')
    return dict(directory=str(root), manifest=manifest, config=conditions[0], context=contexts[0],
                product=products[0], route_constraints=profiles[0], runs=reports, pairs=pairs, metrics=metrics,
                verified_payload_bytes=sum(r['report']['verified_payload_bytes'] for r in reports),
                minimum_pc_coverage_pct=min(100 * pc['coverage_ms'] / r['report']['process_window_ms']
                                            for r in reports for pc in r['report']['pc'].values()))


def compare(legacy_root, driver_root):
    sources_before = {str(root): snapshot(root) for root in (legacy_root, driver_root)}
    driver, legacy = load_series(driver_root, 'driver'), load_series(legacy_root, 'v4.0.0')
    require({k: v for k, v in driver['config'].items() if k not in VERSION_FIELDS} ==
            {k: v for k, v in legacy['config'].items() if k not in VERSION_FIELDS}, 'Cross-version tools/traffic/socket settings differ')
    require(driver['route_constraints'] == legacy['route_constraints'], 'Cross-version rule meanings differ')
    lc, dc = legacy['context'], driver['context']
    binding = read(legacy_root / 'driver-transfer-reference.json')
    require(Path(lc['driver_transfer_directory']).resolve() == driver_root and
            Path(binding['source_directory']).resolve() == driver_root and
            binding['source_sha256'] == sources_before[str(driver_root)] and
            lc['driver_boot_identity'] == binding['driver_boot_identity'] == dc['boot_identity'],
            '4.0.0 must reference this exact completed driver series')
    require(lc['reboot_between_versions_observed'] is True and
            all(lc['boot_identity'][key] == dc['boot_identity'][key] for key in ('computer_name', 'machine_guid', 'os_build')) and
            datetime.fromisoformat(lc['boot_identity']['boot_time_utc']) >
            datetime.fromisoformat(driver['manifest']['completed_at_utc']), 'New boot after driver on same VM/OS required')
    runs = driver['runs'] + legacy['runs']
    require(len({r['report']['connection_id'] for r in runs}) == 24, 'Connection GUIDs reused across versions')
    require(len({r['report']['other_driver_names_sha256'] for r in runs}) == 1, 'Other loaded driver names differ')
    preflight_path = Path(binding['preflight_directory']) / 'preflight.json'
    require(Path(lc['legacy_idle_directory']).resolve().parent == preflight_path.parent, 'Different preflight root')
    preflight = read(preflight_path)
    require(preflight['status'] == 'FILES_AND_PROFILES_PREPARED' and preflight['switch_policy'] == 'reboot_between_versions',
            'Preflight not confirmed')
    for series, contract in ((legacy, 'v4.0.0'), (driver, 'driver')):
        selected = [p for p in preflight['products'] if p['contract'] == contract]
        require(len(selected) == 1, 'Ambiguous prepared kit')
        selected = selected[0]
        require(selected['receipt_chain_verified'] and selected['base_components_unchanged'] and
                all(series['product'][k] == selected['identity'][k] for k in
                    ('bundle_sha256', 'declared_source_commit', 'declared_cli_variant', 'components')) and
                digest(Path(selected['env_path']).parent / 'build-receipt.json') == selected['build_receipt_sha256'],
                'Kit/receipt binding differs')
        profile = preflight_path.parent / (contract + '-transfer.pbprofile')
        require(digest(profile) == series['config']['route_profile_sha256'].lower() and
                profile_constraints(profile) == series['route_constraints'], 'Prepared profile differs')
    require(preflight['products'][0]['cli_changes'] == preflight['products'][1]['cli_changes'], 'CLI adaptations differ')
    changes = {}
    for direction in ('push', 'pull'):
        dm, lm = driver['metrics'][direction], legacy['metrics'][direction]
        changes[direction] = dict(
            proxy_rate_driver_vs_legacy_pct=100 * (dm['mode_medians']['PROXY'] / lm['mode_medians']['PROXY'] - 1),
            paired_change_driver_minus_legacy_percentage_points=dm['paired_change_pct_median'] - lm['paired_change_pct_median'],
            cli_cpu_driver_minus_legacy_percentage_points=dm['cli']['cpu_pct_machine_mean'] - lm['cli']['cpu_pct_machine_mean'])
    require(all(snapshot(Path(root)) == hashes for root, hashes in sources_before.items()), 'Source files changed while reading')
    return dict(schema_version=1, status='LIMITED_VERSION_COMPARISON', errors=[],
                created_at_utc=datetime.now(timezone.utc).isoformat(), legacy=legacy, driver=driver,
                driver_vs_legacy=changes, source_sha256=sources_before,
                analysis_sha256={p.name: digest(p) for p in (Path(__file__), Path(__file__).with_name('pb_tcp_benchmark_report.py'), Path(__file__).with_name('pb_tcp_transfer_reference.py'))},
                normal_tcp_close_verified=False, rtt_measured=False, version_switch_ready=False,
                global_cleanup_verified=False, paired_version_evidence_verified=True,
                known_problems=legacy['runs'][0]['report']['known_problems'],
                limitations=['Rate-capped local IPv4 TCP, one connection/run; not maximum throughput, RTT, remote or long-term stability.',
                             'Three counterbalanced pairs/direction/version; one driver then 4.0.0 boot order, no confidence interval.',
                             'Socket query and instrumentation included, no excluded warmup; whole SOCKS5 path, not isolated driver cost.',
                             'CLI CPU is sampled whole-machine percent; CLI private RAM excludes driver/kernel allocation and watts.',
                             '4.0.0 OFF retains idle WinDivert with zero compatible observed handles; driver OFF has no known loaded interceptors.',
                             'Data verified with identical stock rude shutdown; historical 4.0.0 normal-close failure remains unresolved.'])


def summary(result):
    lines = ['# Передача TCP: 4.0.0 и driver / TCP transfer: 4.0.0 vs driver', '',
             '**Ограниченно сопоставимо / LIMITED_VERSION_COMPARISON**', '',
             'По 12 успешных прогонов и 24 GiB проверенных данных на версию. Три пары с прямым трафиком на направление. / 12 confirmed runs and 24 GiB verified per version; three direct/proxy pairs per direction.', '',
             '| Показатель / Metric | 4.0.0 | driver |', '|---|---:|---:|']
    for direction, label in (('push', 'Отправка / Upload'), ('pull', 'Скачивание / Download')):
        lm, dm = [result[key]['metrics'][direction] for key in ('legacy', 'driver')]
        for mode, name in (('OFF', 'напрямую / direct'), ('PROXY', 'SOCKS5')):
            lines.append(f'| {label}, {name}, Mbit/s | {lm["mode_medians"][mode]:.2f} | {dm["mode_medians"][mode]:.2f} |')
        lines.append(f'| {label}, изменение к прямому / paired change, % | {lm["paired_change_pct_median"]:+.3f} | {dm["paired_change_pct_median"]:+.3f} |')
        lines.append(f'| {label}, CLI CPU, % ПК / machine | {lm["cli"]["cpu_pct_machine_mean"]:.3f} | {dm["cli"]["cpu_pct_machine_mean"]:.3f} |')
        lines.append(f'| {label}, CLI private RAM, MiB | {lm["cli"]["private_mib_mean"]:.2f} | {dm["cli"]["private_mib_mean"]:.2f} |')
    lines += ['', 'Показатели — медианы трёх прогонов; изменение к прямому — медиана изменений внутри пар, а не разность медиан. / Median run values and median within-pair rate changes.', '',
              'Темп отправки ограничен настройкой 64 MiB/s; по 2 GiB на соединение. Поэтому близкие скорости не доказывают одинаковую предельную производительность. / Capped sender rate, not a capacity benchmark.', '',
              'Разброс пар скачивания / Download paired change range: ' + '; '.join(
                  label + ' ' + '…'.join(f'{v:+.3f}%' for v in result[key]['metrics']['pull']['paired_change_pct_range'])
                  for key, label in (('legacy', '4.0.0'), ('driver', 'driver'))) + '.', '',
              '**4.0.0: ранее подтверждён сброс при штатном закрытии TCP. Здесь проверена передача данных с shutdown:rude; исправление закрытия не проверено. / Previously confirmed normal-close reset; data-only transfer does not verify a fix.**', '',
              'Версии последовательно запущены после разных загрузок одной VM. Фон мог меняться; OFF 4.0.0 сохраняет idle WinDivert. Запрос сокетов и инструментирование входят в измерение, прогрев не исключён. / Single cross-boot order, different idle interception baselines, instrumentation included.', '',
              'CPU/RAM относятся к CLI, не к драйверу или всему продукту. Ватты, RTT, игры, удалённый режим и длительная устойчивость этим профилем не измерены. / Sampled CLI resources only; no power, RTT, remote or long-soak claims.', '',
              'Исходные отчёты сохранены; технические свидетельства — comparison-report.json. / Original evidence preserved.', '']
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--legacy-directory', type=Path, required=True)
    parser.add_argument('--driver-directory', type=Path, required=True)
    parser.add_argument('--output-directory', type=Path, required=True)
    args = parser.parse_args()
    try:
        legacy, driver, output = [p.resolve() for p in (args.legacy_directory, args.driver_directory, args.output_directory)]
        require(legacy != driver and not output.exists() and
                all(not output.is_relative_to(source) and not source.is_relative_to(output) for source in (legacy, driver)),
                'Output must be a new directory outside source series')
        result = compare(legacy, driver)
        output.mkdir(parents=True, exist_ok=False)
        (output / 'comparison-report.json').write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding='utf-8')
        (output / 'summary.md').write_text(summary(result), encoding='utf-8')
        print(json.dumps(dict(status=result['status'], errors=[], directory=str(output))))
    except (ValueError, KeyError, IndexError, TypeError, OSError) as error:
        print(json.dumps(dict(status='INCONCLUSIVE', errors=[str(error)])))
        raise SystemExit(1)


if __name__ == '__main__':
    main()
