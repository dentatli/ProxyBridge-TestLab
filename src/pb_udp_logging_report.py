"""Compare helper file-flush policies on the same verified SOCKS5 UDP path."""
import argparse
import hashlib
import json
from pathlib import Path
import statistics


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--evidence-directory', required=True)
    directory = Path(parser.parse_args().evidence_directory)
    manifest = read(directory / 'comparison-manifest.json')
    errors, runs, conditions = [], [], []
    if manifest['status'] != 'COMPLETED' or manifest['comparison_mode'] != 'LOGGING':
        errors.append('Logging series is not completed')
    for entry in manifest['runs']:
        path = directory / entry['directory']
        report = read(path / 'udp-benchmark-report.json')
        config = read(path / 'benchmark-config.json')
        deps = read(path / 'dependencies.json')
        build = read(path / 'product-build.json')
        receiver = read(path / 'receiver-identity.json')
        before, active, after = [read(path / ('loaded-drivers-' + stage + '.json'))
                                 for stage in ('before', 'active', 'after')]
        sampler = [json.loads(line) for line in (path / 'pc-samples.jsonl').read_text(encoding='utf-8-sig').splitlines() if line]
        listening = next(r for r in sampler if r['event'] == 'LISTENING')
        native = sorted([json.loads(line) for line in (path / (config['test_id'] + '.jsonl')).read_text(encoding='utf-8-sig').splitlines() if line], key=lambda r: r['sequence'])
        traffic = [(r['sequence'], r['benchmark_stream_index'], r['bytes_sent'], r['family'],
                    r['protocol'], r['udp_mode'], r['requested_remote_ip'], r['requested_remote_port']) for r in native]
        signature = dict(config={k: v for k, v in config.items() if k != 'helper_log_flush_mode'},
                         dependencies=deps, bundle_sha256=build['bundle_sha256'],
                         receiver_python_sha256=receiver['python_sha256'], receiver_helper_sha256=receiver['helper_sha256'],
                         logical_cpus=listening['logical_cpus'], sampler_interval_ms=listening['interval_ms'],
                         other_drivers=before['other_driver_names_sha256'],
                         traffic_sha256=hashlib.sha256(json.dumps(traffic, separators=(',', ':')).encode()).hexdigest())
        conditions.append(signature)
        confirmed = report['correctness_status'] == 'PASS' and report['performance_status'] == 'MEASURED'
        confirmed |= (report['correctness_status'] == 'SOURCE_ENDPOINT_MISMATCH' and
                      report['performance_status'] == 'MEASURED_WITH_SOURCE_DEFECT' and
                      report['response_sources']['OWNED_RELAY'] > 0 and not report['response_sources']['UNEXPECTED'])
        if (entry['status'] != 'COMPLETED' or entry['mode'] not in ('FLUSH_EACH', 'BUFFERED') or
            config['helper_log_flush_mode'] != entry['mode'] or not report['logging_policy_verified'] or
            report['helper_log_flush_mode'] != entry['mode'] or not confirmed or
            report['traffic_mode'] != 'product-rules' or not report['routed_udp_source_regression_covered'] or
            report['cross_stream_regression_covered'] or report['cross_stream_status'] != 'NOT_EXERCISED' or
            config['destination_mode'] != 'DISTINCT' or config['parallelism'] != 2 or
            config['packet_count'] != manifest['packet_count'] or config['interval_ms'] != manifest['interval_ms'] or
            config['warmup_packets_per_stream'] != manifest['warmup_packets'] or
            config['message_size_bytes'] != manifest['message_size_bytes'] or
            report['pc_metrics']['status'] != 'OBSERVED' or not report['pc_metrics']['receiver_identity_verified']):
            errors.append(entry['directory'] + ': workload/logging/resources not confirmed')
        if (not all(x['query_complete'] for x in (before, active, after)) or
            not before['known_interception_driver_names_absent'] or not after['known_interception_driver_names_absent'] or
            not active['selected_driver_loaded'] or len(active['known_interception_drivers']) != 1 or
            len({x['other_driver_names_sha256'] for x in (before, active, after)}) != 1):
            errors.append(entry['directory'] + ': driver state/inventory differs')
        runs.append(dict(pair=entry['pair'], mode=entry['mode'], directory=entry['directory'],
                         correctness_status=report['correctness_status'], response_sources=report['response_sources'],
                         metrics=report['metrics'], pc=report['pc_metrics']['phases']['measurement']))
    if not conditions or any(x != conditions[0] for x in conditions):
        errors.append('Conditions differ beyond the declared helper flush policy')
    pairs = []
    for number in range(1, manifest['pair_count'] + 1):
        group = [r for r in runs if r['pair'] == number]
        expected = ['FLUSH_EACH', 'BUFFERED'] if number % 2 else ['BUFFERED', 'FLUSH_EACH']
        if [r['mode'] for r in group] != expected:
            errors.append(f'Pair {number}: order/modes differ')
        elif all(r['metrics'] is not None for r in group):
            base = next(r for r in group if r['mode'] == 'FLUSH_EACH')
            buffered = next(r for r in group if r['mode'] == 'BUFFERED')
            pairs.append(dict(pair=number, rtt_delta_ms=buffered['metrics']['rtt_median_ms']-base['metrics']['rtt_median_ms'],
                              rate_delta_pps=buffered['metrics']['packets_per_s']-base['metrics']['packets_per_s'],
                              rate_change_pct=100 * (buffered['metrics']['packets_per_s'] / base['metrics']['packets_per_s'] - 1)))
    result = dict(schema_version=1, status='INCONCLUSIVE' if errors else 'LIMITED_COMPARISON',
                  comparison_mode='LOGGING', errors=errors, runs=runs, pairs=pairs, summary=None,
                  version_switch_ready=False,
                  scope='Receiver and proxy per-event file flush vs 256 KiB buffering; same routed UDP workload')
    lines = ['# Журналирование получателя и SOCKS5-прокси / Receiver and SOCKS5 proxy logging', '',
             '**' + result['status'] + '**', '',
             'Обе стороны используют ProxyBridge/SOCKS5 и два разных контролируемых UDP-порта. '
             'Все записи/хеши и проверки сохранены; меняется только сброс файлов двух helpers. '
             'Both modes use the same routed two-destination traffic and retain all evidence.', '',
             'Журналы генератора/продукта, SHA вычисления и CPU sampler неизменны: это часть стоимости инструментирования, '
             'не полная цена журналирования или только драйвера. Generator/product logs, hashing and sampler are unchanged; '
             'this is a partial instrumentation-cost comparison.', '']
    if not errors:
        summary = {}
        lines.extend(['| Режим / Mode | RTT median, ms | RTT p99, ms | Echo/s | Receiver CPU, % ПК | Proxy CPU, % ПК | CLI CPU, % ПК |',
                      '|---|---:|---:|---:|---:|---:|---:|'])
        for mode in ('FLUSH_EACH', 'BUFFERED'):
            group = [r for r in runs if r['mode'] == mode]
            values = dict(rtt_median_ms=statistics.median(r['metrics']['rtt_median_ms'] for r in group),
                          rtt_p99_ms=statistics.median(r['metrics']['rtt_p99_ms'] for r in group),
                          packets_per_s=statistics.median(r['metrics']['packets_per_s'] for r in group),
                          cpu_pct={role: statistics.median(r['pc']['processes'][role]['cpu_pct_machine_mean'] for r in group)
                                   for role in ('receiver', 'proxy', 'proxybridge_cli')},
                          helpers_private_mib=statistics.median(sum(r['pc']['processes'][role]['private_bytes_mean']
                              for role in ('receiver', 'proxy')) / 1048576 for r in group),
                          source_counts={key: sum(r['response_sources'][key] for r in group) for key in group[0]['response_sources']},
                          rtt_max_ms=max(r['metrics']['rtt_max_ms'] for r in group),
                          responses_above_20ms=sum(r['metrics']['responses_above_threshold'] for r in group))
            summary[mode] = values
            lines.append(f"| {mode} | {values['rtt_median_ms']:.3f} | {values['rtt_p99_ms']:.3f} | {values['packets_per_s']:.0f} | "
                         f"{values['cpu_pct']['receiver']:.2f} | {values['cpu_pct']['proxy']:.2f} | {values['cpu_pct']['proxybridge_cli']:.2f} |")
        result['summary'] = summary
        lines.extend(['', f"Парная разница / paired difference BUFFERED − FLUSH_EACH: median RTT "
                      f"{statistics.median(p['rtt_delta_ms'] for p in pairs):+.3f} ms; "
                      f"echo/s {statistics.median(p['rate_delta_pps'] for p in pairs):+.0f}; "
                      f"median paired rate change {statistics.median(p['rate_change_pct'] for p in pairs):+.2f}%.", '',
                      '| Пара / Pair | RTT delta, ms | Echo/s delta | Rate change, % |',
                      '|---|---:|---:|---:|'])
        for pair in pairs:
            lines.append(f"| {pair['pair']} | {pair['rtt_delta_ms']:+.3f} | {pair['rate_delta_pps']:+.0f} | {pair['rate_change_pct']:+.2f} |")
        lines.extend(['', 'Таблица режимов содержит медианы отдельных прогонов; разность этих медиан не равна медиане парных разностей. '
                      'Для оценки изменения используйте пары выше; величина эффекта различается между парами. '
                      'Mode medians are descriptive; their difference is not the median paired difference. '
                      'Use the paired changes above; effect size varies between pairs.', ''])
        for mode, values in summary.items():
            lines.extend([f"{mode}: maximum RTT {values['rtt_max_ms']:.2f} ms; >20 ms: {values['responses_above_20ms']}; "
                          f"receiver+proxy private RAM {values['helpers_private_mib']:.2f} MiB; "
                          f"sources {values['source_counts']}.", ''])
    lines.extend(['Корректность источника остаётся отдельной проверкой; смешивание при одном получателе не проверяется. '
                  'Source correctness remains separate; same-destination cross-stream mixing is not exercised.', '',
                  'Короткие bursts с разным достигнутым темпом; CPU не нормирован на одинаковую интенсивность. '
                  'Это не максимальная ёмкость/длительная стабильность и не сравнение версий. '
                  'Short bursts at different achieved rates; CPU is not normalized to fixed offered load. '
                  'Not maximum capacity, sustained stability or version A/B.', ''])
    lines.extend('- ' + error for error in errors)
    (directory / 'comparison-report.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    (directory / 'summary.md').write_text('\n'.join(lines), encoding='utf-8')
    print(json.dumps(dict(status=result['status'], errors=errors), ensure_ascii=False))


if __name__ == '__main__':
    main()
