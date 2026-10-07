"""Compare actual paired direct/running UDP paths, retaining correctness defects."""
import argparse
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
    helper_log_mode = manifest.get('helper_log_flush_mode', 'FLUSH_EACH')
    routed = manifest.get('comparison_mode', 'UNRULED') == 'ROUTED'
    on_mode = 'PROXY' if routed else 'UNRULED'
    on_label = 'Через ProxyBridge и SOCKS5' if routed else 'ProxyBridge включён, приложение вне правил'
    expected_modes = {'OFF', on_mode}
    runs = []
    conditions = []
    errors = []
    if helper_log_mode not in ('FLUSH_EACH', 'BUFFERED'):
        errors.append('Unsupported helper log policy for direct/running comparison')
    for entry in manifest['runs']:
        path = directory / entry['directory']
        report = read(path / 'udp-benchmark-report.json')
        config = read(path / 'benchmark-config.json')
        dependencies = read(path / 'dependencies.json')
        receiver_identity = read(path / 'receiver-identity.json') if (path / 'receiver-identity.json').exists() else {}
        build = read(path / 'product-build.json')
        before = read(path / 'loaded-drivers-before.json')
        after = read(path / 'loaded-drivers-after.json')
        native = [json.loads(line) for line in (path / (config['test_id'] + '.jsonl')).read_text(encoding='utf-8-sig').splitlines() if line]
        native.sort(key=lambda r: r['sequence'])
        sampler = [json.loads(line) for line in (path / 'pc-samples.jsonl').read_text(encoding='utf-8-sig').splitlines() if line]
        listening = next(r for r in sampler if r['event'] == 'LISTENING')
        signature = dict(test_id=config['test_id'], packet_count=config['packet_count'], interval_ms=config['interval_ms'],
                         warmup_packets=config['warmup_packets'], parallelism=config['parallelism'], payload=config['payload'],
                         packets_per_stream=config.get('packets_per_stream', config['packet_count'] // config['parallelism']),
                         warmup_packets_per_stream=config.get('warmup_packets_per_stream', config['warmup_packets'] // config['parallelism']),
                         destination_mode=config.get('destination_mode', 'SHARED'),
                         destination_ports=config.get('destination_ports', sorted({r['requested_remote_port'] for r in native})),
                         message_size_bytes=config.get('message_size_bytes', 0),
                         helper_log_flush_mode=config.get('helper_log_flush_mode', 'FLUSH_EACH'),
                         helper_log_buffer_bytes=config.get('helper_log_buffer_bytes', 0),
                         proxy_helper_sha256=dependencies.get('proxy_helper_sha256'),
                         client_sha256=dependencies['client_sha256'], proxy_wheel_sha256=dependencies['proxy_wheel_sha256'],
                         proxy_max_duration_seconds=dependencies.get('proxy_max_duration_seconds', 60),
                         receiver_python_sha256=receiver_identity.get('python_sha256'),
                         receiver_helper_sha256=receiver_identity.get('helper_sha256'),
                         sampler_wheel_sha256=config['sampler_wheel_sha256'], bundle_sha256=build['bundle_sha256'],
                         logical_cpus=listening['logical_cpus'], sampler_interval_ms=listening['interval_ms'],
                         other_loaded_driver_names_sha256=before['other_driver_names_sha256'],
                         traffic=[(r['sequence'],r.get('benchmark_stream_index',1),r['bytes_sent'],r['family'],r['protocol'],r['udp_mode'],r['requested_remote_ip'],r['requested_remote_port']) for r in native])
        conditions.append(signature)
        if (signature['destination_mode'] != manifest.get('destination_mode', 'SHARED') or
            config['parallelism'] != manifest.get('stream_count', 1) or
            config['packet_count'] != manifest['packet_count'] or
            signature['warmup_packets_per_stream'] != manifest['warmup_packets'] or
            signature['helper_log_flush_mode'] != helper_log_mode):
            errors.append(entry['directory'] + ': requested stream/count/warmup configuration differs')
        if (report.get('helper_log_flush_mode', 'FLUSH_EACH') != helper_log_mode or
            report.get('logging_policy_verified', helper_log_mode == 'FLUSH_EACH') is not True):
            errors.append(entry['directory'] + ': helper log policy not confirmed')
        confirmed = report['correctness_status'] == 'PASS' and report['performance_status'] == 'MEASURED'
        if entry['mode'] == 'PROXY':
            confirmed = confirmed or (report['correctness_status'] == 'SOURCE_ENDPOINT_MISMATCH' and
                report['performance_status'] == 'MEASURED_WITH_SOURCE_DEFECT' and
                report['response_sources']['OWNED_RELAY'] > 0 and not report['response_sources']['UNEXPECTED'])
        expected_traffic_mode = {'OFF': 'product-off-direct', 'UNRULED': 'product-running-unruled', 'PROXY': 'product-rules'}
        if (entry['mode'] not in expected_modes or entry['status'] != 'COMPLETED' or not confirmed or
            report['traffic_mode'] != expected_traffic_mode.get(entry['mode']) or
            report['pc_metrics']['status'] != 'OBSERVED' or
            report['pc_metrics'].get('receiver_identity_verified') is not True or
            report['routed_udp_source_regression_covered'] != (entry['mode'] == 'PROXY')):
            errors.append(entry['directory'] + ': unconfirmed mode/traffic/resources')
        if (not before['query_complete'] or not after['query_complete'] or
            not before['known_interception_driver_names_absent'] or not after['known_interception_driver_names_absent'] or
            before['other_driver_names_sha256'] != after['other_driver_names_sha256']):
            errors.append(entry['directory'] + ': driver inventory changed or incomplete')
        if entry['mode'] != 'OFF':
            active = read(path / 'loaded-drivers-active.json')
            if (not active['query_complete'] or not active['selected_driver_loaded'] or
                len(active['known_interception_drivers']) != 1 or
                active['other_driver_names_sha256'] != before['other_driver_names_sha256']):
                errors.append(entry['directory'] + ': active driver state/inventory mismatch')
        runs.append(dict(pair=entry['pair'], mode=entry['mode'], directory=entry['directory'],
                         correctness_status=report['correctness_status'], performance_status=report['performance_status'],
                         cross_stream_regression_covered=report.get('cross_stream_regression_covered', False),
                         cross_stream_status=report.get('cross_stream_status', 'UNREPORTED'),
                         response_sources=report['response_sources'], metrics=report['metrics'],
                         pc=report['pc_metrics']['phases']['measurement']))
    if manifest['status'] != 'COMPLETED' or len(runs) != 2 * manifest['pair_count']:
        errors.append('Incomplete comparison series')
    if conditions and any(c != conditions[0] for c in conditions[1:]):
        errors.append('Traffic, tools, bundle, sampler or other-driver conditions differ')
    for number in range(1, manifest['pair_count'] + 1):
        members = [r for r in runs if r['pair'] == number]
        if len(members) != 2 or {r['mode'] for r in members} != expected_modes:
            errors.append(f'Pair {number}: missing or duplicate modes')
    pairs = []
    if not errors:
        for number in range(1, manifest['pair_count'] + 1):
            members = [r for r in runs if r['pair'] == number]
            off = next(r for r in members if r['mode'] == 'OFF')
            on = next(r for r in members if r['mode'] == on_mode)
            pairs.append(dict(pair=number, order=[r['mode'] for r in members],
                              median_rtt_delta_ms=on['metrics']['rtt_median_ms'] - off['metrics']['rtt_median_ms'],
                              p95_rtt_delta_ms=on['metrics']['rtt_p95_ms'] - off['metrics']['rtt_p95_ms'],
                              rate_delta_pps=on['metrics']['packets_per_s'] - off['metrics']['packets_per_s'],
                              rate_change_pct=100 * (on['metrics']['packets_per_s'] / off['metrics']['packets_per_s'] - 1),
                              system_cpu_delta_percentage_points=on['pc']['system_cpu_pct_mean'] - off['pc']['system_cpu_pct_mean']))
    result = dict(schema_version=1, status='NOT_COMPARABLE' if errors else 'LIMITED_COMPARISON', errors=errors,
                  name_ru='Прямой UDP и UDP через ProxyBridge/SOCKS5' if routed else 'Влияние включённого ProxyBridge на приложение вне правил',
                  name_en='Direct UDP vs UDP through ProxyBridge/SOCKS5' if routed else 'Effect of running ProxyBridge on an application outside its rules',
                  comparison_mode='ROUTED' if routed else 'UNRULED',
                  helper_log_flush_mode=helper_log_mode,
                  scope='same selected Driver kit, connected IPv4 UDP, loopback, paced pairs',
                  runs=runs, pairs=pairs, summary=None, version_switch_ready=False,
                  limitations_ru=[f"Пар: {manifest['pair_count']}; результат относится только к выбранным параметрам/длительности, не характеризует предельную нагрузку или все игровые сценарии.",
                                  'Delta — разница квантилей серий, не квантиль задержки, добавленной к отдельному пакету.',
                                  'Системный CPU включает фоновые приложения; его delta не является выделенной стоимостью драйвера.',
                                  'Остальные сетевые фильтры ПК не объявлены отсутствующими; global cleanup и переключение версий не подтверждены.',
                                  'Разница включает SOCKS5-прокси и его журналирование; это не выделенная стоимость только ProxyBridge. '
                                  'Подмена источника ответа сохраняется отдельным результатом корректности; совместимость приложений не подтверждена.'
                                  if routed else 'Известная подмена источника при перенаправлении UDP в этих режимах не проверяется.',
                                  'p99 и хвосты задержек относятся только к выбранным размеру выборки, нагрузке и длительности.',
                                  'Колебания/отрицательная delta не доказывают ускорения от ProxyBridge.'])
    if manifest.get('resumed_at_utc'):
        result['resumption'] = dict(resumed_at_utc=manifest['resumed_at_utc'],
            previous_error=manifest.get('resumed_from_error'),
            completed_runs_retained=len(runs) - 1, failed_attempts=manifest.get('failed_attempts', []))
        result['limitations_ru'].insert(0, 'Серия возобновлена после остановки: готовые прогоны сохранены, последний выполнен позднее. Между ними есть временной разрыв; это не непрерывная серия.')
    lines = ['# ' + result['name_ru'], '', 'Сопоставимость: **' + result['status'] + '**.', '']
    lines.extend([f'Политика журналов receiver/proxy в обеих сторонах / Receiver/proxy log policy on both sides: **{helper_log_mode}**. '
                  'BUFFERED использует буфер 256 KiB, журналы дописываются при штатной остановке; все записи/хеши/проверки сохраняются. '
                  'Журналы генератора/продукта неизменны. BUFFERED uses a 256 KiB buffer with full evidence flushed on orderly shutdown; '
                  'generator/product logs remain unchanged. Сравнивайте серии с одинаковой политикой / Compare series with the same policy.', ''])
    if result.get('resumption'):
        lines.extend([f"Возобновление: сохранено {len(runs) - 1} готовых прогонов; последний выполнен после {manifest['resumed_at_utc']}. История неудачной попытки сохранена; серия имеет временной разрыв.", ''])
    if not errors:
        deltas = [p['median_rtt_delta_ms'] for p in pairs]
        result['summary'] = dict(median_of_paired_median_rtt_deltas_ms=statistics.median(deltas),
                                  paired_median_rtt_delta_min_ms=min(deltas), paired_median_rtt_delta_max_ms=max(deltas),
                                  direction_consistent=all(d >= 0 for d in deltas) or all(d <= 0 for d in deltas),
                                  median_of_paired_rate_deltas_pps=statistics.median(p['rate_delta_pps'] for p in pairs),
                                  median_of_paired_rate_changes_pct=statistics.median(p['rate_change_pct'] for p in pairs),
                                  modes={})
        for mode in ('OFF',on_mode):
            subset = [r for r in runs if r['mode'] == mode]
            result['summary']['modes'][mode] = dict(median_run_rtt_median_ms=statistics.median(r['metrics']['rtt_median_ms'] for r in subset),
                                                   median_run_packets_per_s=statistics.median(r['metrics']['packets_per_s'] for r in subset),
                                                   median_run_rtt_p95_ms=statistics.median(r['metrics']['rtt_p95_ms'] for r in subset),
                                                   median_run_rtt_p99_ms=statistics.median(r['metrics']['rtt_p99_ms'] for r in subset),
                                                   rtt_max_ms=max(r['metrics']['rtt_max_ms'] for r in subset) if all('rtt_max_ms' in r['metrics'] for r in subset) else None,
                                                   responses_above_20ms=sum(r['metrics']['responses_above_threshold'] for r in subset),
                                                   measured_responses=sum(r['metrics']['measurement_packets'] for r in subset),
                                                   median_run_rtt_variation_ms=statistics.median(r['metrics']['rtt_variation_mean_abs_ms'] for r in subset),
                                                   median_run_system_cpu_pct=statistics.median(r['pc']['system_cpu_pct_mean'] for r in subset),
                                                   median_run_cli_private_bytes=None if mode == 'OFF' else statistics.median(r['pc']['processes']['proxybridge_cli']['private_bytes_mean'] for r in subset),
                                                   valid_packets=len(subset) * conditions[0]['packet_count'],
                                                   response_sources={source: sum(r['response_sources'][source] for r in subset)
                                                                     for source in ('ORIGINAL_ENDPOINT','OWNED_RELAY','UNEXPECTED','NOT_OBSERVED')})
        if conditions[0]['destination_mode'] == 'DISTINCT':
            lines.extend(['Два разных контролируемых UDP-порта: смешивание ответов двух сокетов к одному получателю не проверялось; успех не означает исправление. / Two distinct controlled UDP destination ports: same-destination cross-stream delivery is not exercised; success does not establish a fix.', ''])
        for mode in ('OFF', on_mode):
            values = result['summary']['modes'][mode]
            if values['rtt_max_ms'] is not None:
                lines.extend([f"{mode}: максимум RTT / maximum RTT **{values['rtt_max_ms']:.2f} мс/ms**; "
                              f"ответов >20 мс / responses >20 ms: **{values['responses_above_20ms']}/{values['measured_responses']}** после прогрева / after warmup.", ''])
        if conditions[0]['destination_mode'] == 'SHARED' and routed and all(r['cross_stream_status'] == 'NOT_OBSERVED' for r in runs if r['mode'] == on_mode):
            lines.extend(['Смешивание UDP-ответов при общем получателе не обнаружено во всех повторах PROXY этой серии. Результат относится к выбранной сборке и этим условиям. / Same-destination cross-stream response delivery was not observed in any PROXY repeat; result applies to the selected build and observed conditions.', ''])
        lines.extend([f"UDP-потоков / UDP streams: {conditions[0]['parallelism']}; "
                      f"по {conditions[0]['packets_per_stream']} обменов, прогрев {conditions[0]['warmup_packets_per_stream']} на поток / echoes and warmup per stream. "
                      'Один запрос в полёте на поток; CPU/RAM генератора суммарные / One request in flight per stream; combined generator CPU/RAM.', '',
                      '| Режим | Медиана RTT по повторам, мс | Медиана p95 по повторам, мс | Echo/s |', '|---|---:|---:|---:|'])
        for mode,label in (('OFF','ProxyBridge выключен'),(on_mode,on_label)):
            values = result['summary']['modes'][mode]
            lines.append(f"| {label} | {values['median_run_rtt_median_ms']:.3f} | {values['median_run_rtt_p95_ms']:.3f} | {values['median_run_packets_per_s']:.0f} |")
        delta_label = 'прокси-путь − напрямую' if routed else 'включён − выключен'
        lines.extend(['', f"Парная разница медиан RTT ({delta_label}): **{statistics.median(deltas):+.3f} мс**, "
                      f"диапазон {len(pairs)} пар **{min(deltas):+.3f}…{max(deltas):+.3f} мс**.", '',
                      '| Пара | Порядок | Разница медиан RTT, мс | Разница p95, мс | Echo/s delta | Rate change, % |', '|---|---|---:|---:|---:|---:|'])
        for pair in pairs:
            lines.append(f"| {pair['pair']} | {' → '.join(pair['order'])} | {pair['median_rtt_delta_ms']:+.3f} | {pair['p95_rtt_delta_ms']:+.3f} | {pair['rate_delta_pps']:+.0f} | {pair['rate_change_pct']:+.2f} |")
        lines.extend(['', f"Парная медиана изменения темпа ({delta_label}) / Median paired rate change: "
                      f"{result['summary']['median_of_paired_rate_deltas_pps']:+.0f} echo/s, "
                      f"{result['summary']['median_of_paired_rate_changes_pct']:+.2f}%. "
                      'Разность медиан режимов не заменяет медиану парных разностей / Difference of mode medians does not replace median paired change.', ''])
        lines.extend(['', 'Направление разницы менялось между парами: устойчивого увеличения задержки в этой серии не установлено.'
                      if not result['summary']['direction_consistent'] else
                      f"Направление разницы совпало в {len(pairs)} парах; этого недостаточно для общего вывода вне этих условий.", ''])
        lines.extend(['| Режим | Медиана p99, мс | Вариация RTT, мс | Общий CPU ПК, % | Private RAM CLI, МиБ |',
                      '|---|---:|---:|---:|---:|'])
        for mode,label in (('OFF','Выключен'),(on_mode,on_label)):
            v=result['summary']['modes'][mode]
            memory='процесс отсутствует' if v['median_run_cli_private_bytes'] is None else f"{v['median_run_cli_private_bytes']/1048576:.2f}"
            lines.append(f"| {label} | {v['median_run_rtt_p99_ms']:.3f} | {v['median_run_rtt_variation_ms']:.3f} | {v['median_run_system_cpu_pct']:.2f} | {memory} |")
        lines.extend(['', f"Вариация RTT — средний модуль разницы соседних RTT внутри каждого потока; значения в таблице — медианы по {manifest['pair_count']} повторам. "
                      f"CPU всей системы не атрибутирован ProxyBridge. Все {manifest['pair_count'] * manifest['packet_count']} обмена в каждом режиме подтверждены.", ''])
        lines.extend(['| Пара / режим | Корректность | Исходный источник | Подмена на собственный relay | Неожиданный источник |',
                      '|---|---|---:|---:|---:|'])
        for run in runs:
            s = run['response_sources']
            lines.append(f"| {run['pair']} / {run['mode']} | {run['correctness_status']} | {s['ORIGINAL_ENDPOINT']} | {s['OWNED_RELAY']} | {s['UNEXPECTED']} |")
        lines.append('')
    else:
        lines.extend(['- ' + error for error in errors])
    lines.extend(['- ' + limitation for limitation in result['limitations_ru']])
    lines.extend(['', '# ' + result['name_en'], '', 'Comparability: **' + result['status'] + '**.', '',
                  ('This compares direct UDP with the full local ProxyBridge/SOCKS5 path, including proxy instrumentation. '
                   if routed else 'This compares the selected product stopped vs running with the generator outside its rules. ')
                  +
                  f"{manifest['pair_count']} counterbalanced UDP pairs describe only the selected workload and duration, not maximum throughput, stability beyond that duration, driver-only CPU cost or game compatibility. "
                  'Other network filters are not declared absent. Version switching is not exercised.', ''])
    if result.get('resumption'):
        lines.extend([f"Resumed series: {len(runs) - 1} completed runs retained; the final run was performed later. Failed-attempt history is preserved; this is not an uninterrupted series.", ''])
    if result['summary']:
        lines.append(f"Median paired RTT difference (running minus stopped): {statistics.median(deltas):+.3f} ms; "
                     f"range: {min(deltas):+.3f} to {max(deltas):+.3f} ms. Negative/noisy differences are not proof of acceleration.")
        lines.extend(['', '| Mode | RTT median, ms | RTT p95, ms | Original source | Owned relay source |', '|---|---:|---:|---:|---:|'])
        for mode in ('OFF',on_mode):
            v = result['summary']['modes'][mode]
            s = v['response_sources']
            lines.append(f"| {mode} | {v['median_run_rtt_median_ms']:.3f} | {v['median_run_rtt_p95_ms']:.3f} | {s['ORIGINAL_ENDPOINT']} | {s['OWNED_RELAY']} |")
        lines.extend(['', 'Any owned-relay substitution retains SOURCE_ENDPOINT_MISMATCH; transport measurement is not a correctness pass.'
                      if routed else 'Routed UDP source substitution is not exercised by this comparison.'])
    (directory / 'comparison-report.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    (directory / 'summary.md').write_text('\n'.join(lines), encoding='utf-8')
    print(json.dumps(dict(status=result['status'], pairs=len(pairs), summary=result['summary']), ensure_ascii=False))


if __name__ == '__main__':
    main()
