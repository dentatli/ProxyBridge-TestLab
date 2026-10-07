"""Summarize a real paced UDP series; never turn a source defect into correctness PASS."""
import argparse
import json
import math
from pathlib import Path
import statistics
from collections import Counter, defaultdict


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8-sig').splitlines() if line]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--evidence-directory', required=True)
    args = parser.parse_args()
    directory = Path(args.evidence_directory)
    config = read(directory / 'benchmark-config.json')
    receipt = read(directory / 'route-probe-receipt.json')
    test_id = config.get('test_id', 'local-udp-proxy')
    unruled = receipt.get('traffic_mode') == 'product-running-unruled'
    product_off = receipt.get('traffic_mode') == 'product-off-direct'
    process = read(directory / (test_id + '-process.json'))
    lifecycle = None if product_off else read(directory / 'cli-lifecycle.json')
    lifecycle_verified = receipt.get('product_off_verified') is True if product_off else (
        lifecycle['output_capture_complete'] and lifecycle['graceful_stop'] and not lifecycle['forced_stop'])
    native = sorted(rows(directory / (test_id + '.jsonl')), key=lambda r: r['sequence'])
    streams = config.get('parallelism', 1)
    per_stream = config.get('packets_per_stream', config['packet_count'] // streams)
    warmup_per_stream = config.get('warmup_packets_per_stream', config['warmup_packets'] // streams)
    stream_rows = [[r for r in native if r.get('benchmark_stream_index', 1) == index]
                   for index in range(1, streams + 1)]
    destination_mode = config.get('destination_mode', 'SHARED')
    destination_ports = config.get('destination_ports', [native[0]['requested_remote_port']] if native else [])
    destination_layout_verified = (
        (destination_mode == 'SHARED' and len(destination_ports) == 1 or
         destination_mode == 'DISTINCT' and streams == 2 and len(destination_ports) == 2 and len(set(destination_ports)) == 2) and
        all(all(r['requested_remote_ip'] == '127.0.0.1' and r['requested_remote_port'] ==
                destination_ports[index if destination_mode == 'DISTINCT' else 0] for r in group)
            for index, group in enumerate(stream_rows)))
    stream_layout_verified = (per_stream * streams == config['packet_count'] and
        warmup_per_stream * streams == config['warmup_packets'] and warmup_per_stream < per_stream and
        all([r['sequence'] for r in group] == list(range(index * per_stream + 1, (index + 1) * per_stream + 1))
            and len({(r['socket_id'], r['actual_local_port']) for r in group}) == 1
            for index, group in enumerate(stream_rows)) and
        len({group[0]['actual_local_port'] for group in stream_rows if group}) == streams)
    receiver_events = rows(directory / 'receiver.jsonl')
    receiver = [r for r in receiver_events if r.get('run_id') == receipt['run_id']
                and r.get('test_id') == test_id]
    proxy_events = rows(directory / 'proxy.jsonl')
    log_mode = config.get('helper_log_flush_mode', 'FLUSH_EACH')
    logging_policy_verified = (log_mode in ('FLUSH_EACH', 'BUFFERED') and
        any(r['event'] == 'LISTENING' for r in receiver_events) and
        any(r['event'] == 'LISTENING' for r in proxy_events) and
        all(r.get('log_flush_mode', 'FLUSH_EACH') == log_mode for r in receiver_events + proxy_events))
    samples = rows(directory / 'pc-samples.jsonl')
    sources = {name: sum(r['response_source_class'] == name for r in native)
               for name in ('ORIGINAL_ENDPOINT', 'OWNED_RELAY', 'UNEXPECTED', 'NOT_OBSERVED')}
    sent = [r for r in native if r['bytes_sent'] > 0]
    accepted = [r for r in native if r['accepted_for_performance']]
    failures = Counter(r['actual_result'] for r in native if r['actual_result'].startswith('fail:'))
    timeout_responses = sum(r['wsa_error'] == 10060 and r['bytes_received'] == 0 for r in sent)
    sent_by_hash = defaultdict(list)
    for record in sent:
        sent_by_hash[record['payload_sha256']].append(record)
    cross_stream_responses = []
    for record in native:
        candidates = sent_by_hash.get(record['response_sha256'], []) if record['bytes_received'] else []
        if (record['actual_result'] == 'fail:payload_mismatch' and len(candidates) == 1 and
            candidates[0].get('benchmark_stream_index', 1) != record.get('benchmark_stream_index', 1)):
            cross_stream_responses.append(dict(receiving_stream=record.get('benchmark_stream_index', 1),
                sent_sequence=record['sequence'], response_matches_sequence=candidates[0]['sequence'],
                response_matches_stream=candidates[0].get('benchmark_stream_index', 1)))
    delivery = []
    received_by_sequence = defaultdict(list)
    for event in receiver:
        if event['event'] == 'RECEIVED':
            received_by_sequence[event.get('sequence')].append(event)
    for r in sent:
        delivery.extend(e for e in received_by_sequence[r['sequence']]
                        if e['bytes'] == r['bytes_sent'] and e['sha256'] == r['payload_sha256'] and
                        e['local_port'] == r['requested_remote_port'])
    delivered_sequences = {r['sequence'] for r in delivery}
    complete = (stream_layout_verified and destination_layout_verified and logging_policy_verified and
                (not unruled or receipt.get('unruled_profile_verified') is True) and
                len(native) == config['packet_count'] and
                [r['sequence'] for r in native] == list(range(1, config['packet_count'] + 1)) and
                all(r['run_id'] == receipt['run_id'] and r['process_id'] == process['pid'] for r in native) and
                process['exit_code'] == 0 and not process['timed_out'] and process['output_capture_complete'] and
                lifecycle_verified and
                receipt['workers_stopped'] and receipt['driver_stop_observed'] and
                len(receipt['cases']) == config['packet_count'] and
                all(c['payload_verified'] and c['socket_path_verified'] and
                    (c.get('mode_state_verified') if product_off else c['product_route_observed']) and
                    c['status'] in ('ROUTE_OBSERVED', 'SOURCE_ENDPOINT_MISMATCH') for c in receipt['cases']) and
                len(accepted) == config['packet_count'] and not sources['UNEXPECTED'] and
                len(delivery) == config['packet_count'] and len(delivered_sequences) == config['packet_count'])
    result = dict(schema_version=1, name_ru='Напрямую, ProxyBridge выключен' if product_off else 'ProxyBridge включён, приложение вне правил' if unruled else 'UDP через SOCKS5: транспорт и нагрузка ПК',
                  name_en='Direct, ProxyBridge stopped' if product_off else 'ProxyBridge running, application outside rules' if unruled else 'UDP through SOCKS5: transport and PC resource measurement',
                  traffic_mode=receipt.get('traffic_mode', 'product-rules'), routed_udp_source_regression_covered=not (unruled or product_off),
                  run_id=receipt['run_id'], declared_source_commit=read(directory / 'product-build.json')['declared_source_commit'],
                  source_commit_verified=read(directory / 'product-build.json')['source_commit_verified'],
                  performance_status='MEASURED_WITH_SOURCE_DEFECT' if complete and sources['OWNED_RELAY'] else
                  'MEASURED' if complete else 'INCONCLUSIVE',
                  correctness_status='PAYLOAD_MISMATCH' if failures['fail:payload_mismatch'] else
                  'SOURCE_ENDPOINT_MISMATCH' if sources['OWNED_RELAY'] or sources['UNEXPECTED'] else
                  'PASS' if complete else 'INCONCLUSIVE',
                  source_defect_ru='Подмена источника ответа наблюдалась' if sources['OWNED_RELAY'] or sources['UNEXPECTED'] else
                  'Подмена источника ответа не обнаружена в этом прогоне' if complete else 'Недостаточно свидетельств',
                  source_defect_en='Response source substitution observed' if sources['OWNED_RELAY'] or sources['UNEXPECTED'] else
                  'Response source substitution not observed in this run' if complete else 'Insufficient evidence',
                  response_sources=sources, native_failure_counts=dict(failures),
                  cross_stream_responses=cross_stream_responses, response_timeouts=timeout_responses,
                  planned_packets=config['packet_count'], attempted_packets=len(sent),
                  unattempted_packets=config['packet_count'] - len(sent),
                  receiver_confirmed_packets=len(delivered_sequences), accepted_responses=len(accepted),
                  delivery_missing_packets=len(sent) - len(delivered_sequences),
                  response_missing_or_invalid_packets=len(sent) - len(accepted),
                  receiver_duplicate_packets=len(delivery) - len(delivered_sequences),
                  warmup_packets=config['warmup_packets'], parallelism=streams,
                  stream_layout_verified=stream_layout_verified, destination_layout_verified=destination_layout_verified,
                  destination_mode=destination_mode, destination_ports=destination_ports,
                  helper_log_flush_mode=log_mode, logging_policy_verified=logging_policy_verified,
                  cross_stream_regression_covered=not (unruled or product_off) and streams >= 2 and destination_mode == 'SHARED',
                  metrics=None, pc_metrics=None, rtt_windows=[],
                  limitations_ru=[f'Connected IPv4 UDP на loopback: {streams} поток(а), по одному запросу в полёте; LocalhostViaProxy=true.',
                                  'Заданный интервал — пауза после ответа: темп включает RTT, не фиксированная интенсивность поступления.',
                                  'Диагностический прогон с журналом каждого пакета; это не предельная скорость и не стабильность за пределами наблюдавшейся длительности.',
                                  'CPU/RAM относятся к наблюдаемым процессам; стоимость драйвера отдельно не выделена из системной нагрузки.',
                                  'Системная нагрузка включает другие приложения; вычитание фона не доказывает причинность.',
                                  'Пиковая память — максимум выборок 250 мс; энергопотребление в ваттах не измерено.',
                                  'CPU при малой нагрузке приблизителен: счётчики Windows имеют ограниченную дискретность.',
                                  'Совместимость игр, remote/IPv6/unconnected и A/B этим прогоном не подтверждены.'])
    result['cross_stream_status'] = ('OBSERVED' if cross_stream_responses else 'INCONCLUSIVE') if result['cross_stream_regression_covered'] else 'NOT_EXERCISED'
    if destination_mode == 'DISTINCT':
        result['limitations_ru'].insert(1, 'У каждого сокета свой контролируемый UDP-порт. Смешивание ответов при общем получателе не проверялось; успех не означает исправление этого дефекта.')
    if unruled:
        result['limitations_ru'].insert(0, 'Прямой путь при включённом ProxyBridge, одно правило для другого процесса. Этот PASS не означает исправление UDP-перенаправления; его дефект здесь не проверяется.')
        result['limitations_ru'].insert(1, 'Без сопоставимой серии с полностью остановленным ProxyBridge величина фоновых накладных расходов неизвестна.')
    if product_off:
        result['limitations_ru'].insert(0, 'Выбранный ProxyBridge не запущен; его служба/известные WFP-объекты/имя загруженного драйвера отсутствуют. Это не доказательство отсутствия всех сторонних сетевых фильтров.')
        result['limitations_ru'].insert(1, 'Трафик идёт напрямую; idle proxy оставлен как общий элемент инструментирования, пакеты через него не пересылаются.')
    if complete:
        measured = [r for group in stream_rows for r in group[warmup_per_stream:]]
        start = min(r['udp_send_qpc_ms'] for r in measured)
        end = max(r['udp_receive_qpc_ms'] for r in measured)
        warmup_end = max((r['udp_receive_qpc_ms'] for group in stream_rows
                          for r in group[:warmup_per_stream]), default=start)
        in_flight = peak_in_flight = 0
        for _, delta in sorted([(r['udp_send_qpc_ms'], 1) for r in measured] +
                               [(r['udp_receive_qpc_ms'], -1) for r in measured]):
            in_flight += delta
            peak_in_flight = max(peak_in_flight, in_flight)
        result['observed_concurrent_requests_max'] = peak_in_flight
        result['warmup_barrier_verified'] = warmup_end <= start
        variation = []
        for group in stream_rows:
            values = [r['udp_receive_qpc_ms'] - r['udp_send_qpc_ms'] for r in group[warmup_per_stream:]]
            variation.extend(abs(b-a) for a,b in zip(values, values[1:]))
        duration = (end - start) / 1000
        rtt_sequence = [r['udp_receive_qpc_ms'] - r['udp_send_qpc_ms'] for r in measured]
        rtts = sorted(rtt_sequence)
        valid_clock = (duration > 0 and peak_in_flight == streams and warmup_end <= start and
                       all(r['udp_receive_qpc_ms'] >= r['udp_send_qpc_ms'] > 0 for r in native))
        if not valid_clock:
            result['performance_status'] = 'INCONCLUSIVE'
        else:
            result['metrics'] = dict(measurement_packets=len(measured), duration_s=duration,
                                     receiver_confirmed_useful_bytes=sum(r['bytes_sent'] for r in measured),
                                     reply_useful_bytes=sum(r['bytes_received'] for r in measured),
                                     upload_useful_bits_per_s=8 * sum(r['bytes_sent'] for r in measured) / duration,
                                     download_useful_bits_per_s=8 * sum(r['bytes_received'] for r in measured) / duration,
                                     packets_per_s=len(measured) / duration, rtt_median_ms=statistics.median(rtts),
                                     rtt_p95_ms=rtts[math.ceil(.95 * len(rtts)) - 1],
                                     rtt_p99_ms=rtts[math.ceil(.99 * len(rtts)) - 1],
                                     rtt_max_ms=rtts[-1],
                                     late_response_threshold_ms=20,
                                     responses_above_threshold=sum(rtt > 20 for rtt in rtt_sequence),
                                     rtt_variation_mean_abs_ms=statistics.mean(variation) if variation else None,
                                     rtt_variation_definition='mean absolute difference of consecutive measured UDP RTTs within each stream; not one-way IP jitter',
                                     rate_window='first measured client send through last measured valid echo; receiver-confirmed bytes')
            if duration >= 30:
                windows = defaultdict(list)
                for record, rtt in zip(measured, rtt_sequence):
                    windows[int((record['udp_send_qpc_ms'] - start) // 30000)].append(rtt)
                for number, values in sorted(windows.items()):
                    ordered = sorted(values)
                    result['rtt_windows'].append(dict(start_s=number * 30, end_s=min((number + 1) * 30, duration),
                        packets=len(values), rtt_median_ms=statistics.median(values),
                        rtt_p95_ms=ordered[math.ceil(.95 * len(ordered)) - 1],
                        rtt_p99_ms=ordered[math.ceil(.99 * len(ordered)) - 1],
                        responses_above_20ms=sum(value > 20 for value in values)))
            first_send = min(r['udp_send_qpc_ms'] for r in native)
            phases = dict(background=(None, first_send),
                          warmup=(first_send, start), measurement=(start, end), recovery=(end, None))
            summaries = {}
            for phase, (lower, upper) in phases.items():
                selected = [s for s in samples if s['event'] == 'SAMPLE' and
                            (lower is None or s['interval_start_qpc_ms'] >= lower) and
                            (upper is None or s['qpc_ms'] <= upper)]
                elapsed = sum(s['qpc_ms'] - s['interval_start_qpc_ms'] for s in selected)
                summary = dict(samples=len(selected), covered_s=elapsed / 1000,
                               system_cpu_pct_mean=sum(s['system_cpu_pct'] * (s['qpc_ms'] - s['interval_start_qpc_ms'])
                                                        for s in selected) / elapsed if elapsed else None,
                               system_memory_used_max_bytes=max((s['system_memory_used_bytes'] for s in selected), default=None),
                               processes={})
                for role in ('proxybridge_cli', 'proxy', 'receiver', 'generator', 'sampler'):
                    observed = [(s, p) for s in selected for p in s['processes'] if p['role'] == role and
                                p['status'] == 'OBSERVED' and (lower is None or p['interval_start_qpc_ms'] >= lower)]
                    weights = [s['qpc_ms'] - p['interval_start_qpc_ms'] for s, p in observed]
                    total = sum(weights)
                    summary['processes'][role] = dict(samples=len(observed), covered_s=total / 1000,
                        cpu_pct_machine_mean=sum(p['cpu_pct_machine'] * w for (_, p), w in zip(observed, weights)) / total if total else None,
                        private_bytes_mean=sum(p['private_bytes'] * w for (_, p), w in zip(observed, weights)) / total if total else None,
                        private_bytes_sample_max=max((p['private_bytes'] for _, p in observed), default=None))
                    if phase == 'measurement' and duration >= 20:
                        early = [p['private_bytes'] for s, p in observed if s['qpc_ms'] <= lower + 10000]
                        late = [p['private_bytes'] for s, p in observed if p['interval_start_qpc_ms'] >= upper - 10000]
                        summary['processes'][role].update(
                            private_bytes_first10s_mean=statistics.mean(early) if early else None,
                            private_bytes_last10s_mean=statistics.mean(late) if late else None,
                            private_bytes_last_minus_first=statistics.mean(late) - statistics.mean(early) if early and late else None)
                summaries[phase] = summary
            result['pc_metrics'] = dict(cpu_normalization='delta process CPU seconds / elapsed seconds / logical CPUs * 100',
                                       phases=summaries, boundary_crossing_intervals_excluded=True)
            if product_off:
                for summary in summaries.values():
                    summary['processes']['proxybridge_cli']['status'] = 'NOT_RUNNING'
            required_roles = ('proxy', 'receiver', 'generator', 'sampler') if product_off else ('proxybridge_cli', 'proxy', 'receiver', 'generator', 'sampler')
            watched_receiver_pids = {s['pid'] for s in samples if s['event'] == 'WATCHED' and s['role'] == 'receiver'}
            receiver_identity_verified = (receipt.get('receiver_process_identity_verified') is True
                and len(watched_receiver_pids) == 1
                and {e.get('process_id') for e in receiver} == watched_receiver_pids)
            required_coverage = max(0, duration - 1)
            incomplete_roles = [role for role in required_roles
                    if not summaries['measurement']['processes'][role]['samples']
                    or summaries['measurement']['processes'][role]['covered_s'] < required_coverage]
            system_incomplete = not summaries['measurement']['samples'] or summaries['measurement']['covered_s'] < required_coverage
            if not receiver_identity_verified:
                incomplete_roles.append('receiver_identity')
            result['pc_metrics'].update(incomplete_roles=incomplete_roles,
                                       receiver_identity_verified=receiver_identity_verified,
                                       system_coverage_incomplete=system_incomplete,
                                       required_measurement_coverage_s=required_coverage)
            if incomplete_roles or system_incomplete:
                result['pc_metrics']['status'] = 'INCOMPLETE'
            else:
                result['pc_metrics']['status'] = 'OBSERVED'
    if result['cross_stream_regression_covered'] and result['metrics'] is not None:
        result['cross_stream_status'] = 'NOT_OBSERVED'
    result['limitations_ru'].append('Изменение private RAM между первыми/последними 10 с не доказывает утечку; необходимо учитывать рабочие буферы и последующие повторы.')
    (directory / 'udp-benchmark-report.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    summary = ['# ' + result['name_ru'], '', result['source_defect_ru'] + '.', '',
               f"Пакеты: доставлено {result['receiver_confirmed_packets']}/{result['planned_packets']}, "
               f"допустимых для замера ответов {result['accepted_responses']}. "
               f"Источники: исходный {sources['ORIGINAL_ENDPOINT']}, relay {sources['OWNED_RELAY']}, неожиданный {sources['UNEXPECTED']}.", '',
               f"Корректность: **{result['correctness_status']}**. Производительность: **{result['performance_status']}**.", '']
    summary.extend([f"UDP-потоков / UDP streams: {streams}; прогрев на поток / warmup per stream: {warmup_per_stream}. "
                    f"Максимум одновременных запросов / peak requests in flight: {result.get('observed_concurrent_requests_max', 'unconfirmed')}.", ''])
    cross_stream_labels = dict(OBSERVED='Смешивание ответов наблюдалось / Cross-stream response delivery observed',
        NOT_OBSERVED='Смешивание ответов не обнаружено в этом прогоне / Cross-stream response delivery not observed in this run',
        INCONCLUSIVE='Недостаточно данных для проверки смешивания ответов / Insufficient evidence for cross-stream delivery check',
        NOT_EXERCISED='Смешивание ответов при общем получателе не проверялось / Same-destination cross-stream delivery not exercised')
    summary.extend([f"Получатель / Destination: {destination_mode}, UDP ports {destination_ports}.", '',
                    cross_stream_labels[result['cross_stream_status']] + '.', ''])
    summary.extend([f"Запись журналов получателя/прокси / Receiver/proxy log flush mode: {log_mode}; "
                    f"проверено / verified: {logging_policy_verified}. Все записи пакетов сохраняются / All per-packet records retained.", ''])
    if failures['fail:payload_mismatch'] or timeout_responses:
        summary.extend([f"Несовпадение данных / Payload mismatches: {failures['fail:payload_mismatch']}; "
                        f"ответ совпал с пакетом другого потока / response matched another stream: {len(cross_stream_responses)}; "
                        f"тайм-ауты ответа / response timeouts: {timeout_responses}.", '',
                        'Измерение не завершено: ошибка данных не разрешена политикой продолжения для подмены порта. '
                        'Measurement incomplete: the source-port continuation policy does not permit payload errors.', ''])
    if result['metrics']:
        metrics = result['metrics']
        summary.extend([f"После прогрева: {metrics['measurement_packets']} пакетов за {metrics['duration_s']:.2f} с; "
                        f"{metrics['packets_per_s']:.2f} пакета/с. Полезная скорость: "
                        f"{metrics['upload_useful_bits_per_s']/1000:.2f} кбит/с в каждом направлении.", '',
                        f"RTT: медиана {metrics['rtt_median_ms']:.2f} мс, p95 {metrics['rtt_p95_ms']:.2f} мс; "
                        f"максимум {metrics['rtt_max_ms']:.2f} мс, ответов >20 мс: {metrics['responses_above_threshold']}.", ''])
    if result['pc_metrics']:
        phase = result['pc_metrics']['phases']['measurement']
        summary.extend([f"CPU/RAM: **{result['pc_metrics']['status']}**. / Resource coverage: **{result['pc_metrics']['status']}**.", ''])
        if result['pc_metrics']['status'] == 'INCOMPLETE':
            missing = ', '.join(result['pc_metrics']['incomplete_roles']) or 'system'
            summary.extend([f"Неполное покрытие / Incomplete coverage: {missing}. Сравнение не подтверждено / Comparison not confirmed.", ''])
        summary.extend(['| Процесс | Средний CPU, % всего ПК | Средняя / максимальная private RAM, МиБ |',
                        '|---|---:|---:|'])
        for role, values in phase['processes'].items():
            if values['samples']:
                summary.append(f"| {role} | {values['cpu_pct_machine_mean']:.3f} | "
                               f"{values['private_bytes_mean']/1048576:.2f} / {values['private_bytes_sample_max']/1048576:.2f} |")
        summary.extend(['', f"Системный CPU: {phase['system_cpu_pct_mean']:.2f}%; "
                        f"сбор: {phase['samples']} выборок, {phase['covered_s']:.2f} с покрытия.", ''])
    if unruled:
        summary.extend(['UDP-перенаправление здесь не проверяется: успешный прямой обмен вне правил не означает исправление relay-дефекта.', ''])
    if result['rtt_windows']:
        summary.extend(['| Интервал, с / Window, s | Пакеты / Packets | RTT median, ms | RTT p95, ms | RTT >20 ms |',
                        '|---|---:|---:|---:|---:|'])
        for window in result['rtt_windows']:
            summary.append(f"| {window['start_s']:.0f}–{window['end_s']:.1f} | {window['packets']} | {window['rtt_median_ms']:.3f} | {window['rtt_p95_ms']:.3f} | {window['responses_above_20ms']} |")
        summary.append('')
    if result['pc_metrics']:
        cli = result['pc_metrics']['phases']['measurement']['processes']['proxybridge_cli']
        if cli.get('private_bytes_last_minus_first') is not None:
            summary.extend([f"Private RAM CLI, первые/последние 10 с (first/last 10 s): "
                            f"{cli['private_bytes_first10s_mean']/1048576:.2f} / {cli['private_bytes_last10s_mean']/1048576:.2f} МиБ; "
                            f"delta {cli['private_bytes_last_minus_first']/1048576:+.2f} МиБ. Это не доказательство утечки / not proof of a leak.", ''])
    summary.extend(['Завершение собственных процессов и остановленное состояние выбранного драйвера подтверждены. '
                    'Готовность переключения версий не подтверждена.' if receipt['workers_stopped'] and receipt['driver_stop_observed']
                    else 'Остановка собственных процессов/службы не подтверждена.', '',
                    *['- ' + limitation for limitation in result['limitations_ru']], '',
                    '# ' + result['name_en'], '', result['source_defect_en'] + '.', '',
                    f"Delivered packets: {result['receiver_confirmed_packets']}/{result['planned_packets']}; "
                    f"accepted echoes: {result['accepted_responses']}. "
                    f"Original sources: {sources['ORIGINAL_ENDPOINT']}; owned relay: {sources['OWNED_RELAY']}; unexpected: {sources['UNEXPECTED']}.", '',
                    f'Connected UDP streams: {streams}; one request in flight per stream, {warmup_per_stream} warmup packets each. '
                    'This is a loopback measurement with per-packet instrumentation, not maximum throughput. '
                    'Process CPU includes user and kernel time attributed to that process; driver cost is not separately attributed. '
                    'Background applications affect system CPU. Watt consumption, stability beyond this duration, remote/IPv6 and version A/B are not measured.', ''])
    if unruled:
        summary.extend(['This run covers an application outside the rules. Routed UDP is not exercised, and its known source-port defect is not evaluated. Matched comparisons are reported separately.', ''])
    if result['metrics']:
        summary.extend([f"RTT median: {metrics['rtt_median_ms']:.2f} ms; p95: {metrics['rtt_p95_ms']:.2f} ms; "
                        f"maximum: {metrics['rtt_max_ms']:.2f} ms; responses >20 ms: {metrics['responses_above_threshold']}. "
                        f"Useful rate: {metrics['upload_useful_bits_per_s']/1000:.2f} kbit/s in each direction; "
                        f"{metrics['packets_per_s']:.2f} packets/s after {config['warmup_packets']} warmup packets.", ''])
    (directory / 'summary.md').write_text('\n'.join(summary), encoding='utf-8')
    print(json.dumps(dict(performance=result['performance_status'], correctness=result['correctness_status'],
                         accepted_responses=result['accepted_responses']), ensure_ascii=False))


if __name__ == '__main__':
    main()
