"""Verified persistent TCP echo RTT while a separate ctsTraffic transfer is active."""
import argparse
import csv
from collections import Counter
import json
import math
from pathlib import Path
import re
import statistics

from pb_tcp_benchmark_report import read, jsonl, connection
from pb_tcp_rtt_report import evaluate_run


def status_rows(path):
    raw = path.read_bytes()
    text = raw.decode('utf-16' if raw.startswith(b'\xff\xfe') else 'utf-8-sig')
    return list(csv.DictReader(text.splitlines()))


def progress_tuple(row, native=False):
    keys = ('TimeSlice', 'SendBps', 'RecvBps', 'In-Flight', 'Completed', 'NetError', 'DataError') if native else (
        'time_slice', 'send_bps', 'recv_bps', 'in_flight', 'completed', 'net_errors', 'data_errors')
    return tuple(float(row[k]) for k in keys)


def evaluate_loaded_run(path):
    result = evaluate_run(path)
    errors = result['errors']
    cfg = result['config']; load = cfg['load']; mode = result['mode']
    if (not read(path/'run-receipt.json').get('load_receiver_identity_verified') or
            read(path/'load-receiver-process.json')['pid'] != load['receiver_pid']):
        errors.append('Concurrent receiver listener/PID identity not confirmed')
    client, receiver = [connection(path/('load-'+n+'.csv')) for n in ('client', 'receiver')]
    for name in ('load-client', 'load-receiver'):
        process = read(path/(name+'-process.json'))
        if not re.search(r'Level of verification:\s*Connections & Data', process['stdout']):
            errors.append(name+': data-verification setting not observed')
    if load['verify'] != 'data' or any(r['Result'] != 'Succeeded' for r in (client, receiver)):
        errors.append('Concurrent transfer data verification failed')
    if not re.fullmatch(r'[0-9a-fA-F-]{36}', client['ConnectionId']) or client['ConnectionId'] != receiver['ConnectionId']:
        errors.append('Concurrent transfer connection IDs differ')
    direction = load['direction']
    sent, received = ('SendBytes', 'RecvBytes') if direction == 'push' else ('RecvBytes', 'SendBytes')
    if (direction not in ('push', 'pull') or int(client[sent]) != load['transfer_bytes'] or
            int(receiver[received]) != load['transfer_bytes'] or int(client[received]) != 0 or int(receiver[sent]) != 0):
        errors.append('Concurrent verified payload volumes differ')
    destination = f"127.0.0.1:{load['receiver_port']}"
    if receiver['LocalAddress'] != destination or client['RemoteAddress'] != destination:
        errors.append('Concurrent controlled destination mismatch')
    proxy = jsonl(path/'proxy.jsonl')
    all_flows = [r for r in proxy if r['event'] == 'TCP_CONNECTED']
    flows = [r for r in all_flows if r['destination_port'] == load['receiver_port']]
    socket_observation = None
    if cfg.get('proxy_accepted_tcp_nodelay'):
        option_path = path/'proxy-socket-options.jsonl'
        options = jsonl(option_path) if option_path.exists() else []
        proxy_pid = read(path/'proxy-process.json')['pid']
        expected_peers = {(r['inbound_peer_ip'], r['inbound_peer_port']) for r in all_flows}
        matched = [r for r in options if tuple(r.get('peer', [])) in expected_peers]
        extras = [r for r in options if tuple(r.get('peer', [])) not in expected_peers]
        rejected_udp_peers = []
        for row in proxy:
            if row['event'] != 'LIBRARY_MESSAGE' or row.get('process_id') != proxy_pid:
                continue
            match = re.fullmatch(r'event=addon_error flow_id=\d+ proto=udp src=(127\.0\.0\.1):(\d+) '
                                 r'dst=0\.0\.0\.0:0 error_type=ValueError error=UDP_NOT_CONFIGURED',
                                 row.get('message', ''))
            if match:
                rejected_udp_peers.append((match[1], int(match[2])))
        socket_options_valid = not (mode != 'PROXY' or len(matched) != 2 or len(expected_peers) != 2 or
                {tuple(r['peer']) for r in matched} != expected_peers or
                Counter(tuple(r.get('peer', [])) for r in extras) != Counter(rejected_udp_peers) or any(
                    r.get('event') != 'ACCEPTED_TCP_SOCKET_OPTIONS' or r.get('process_id') != proxy_pid or
                    r.get('local') != ['127.0.0.1', cfg['proxy_port']] or
                    r.get('tcp_nodelay_after') != 1 or r.get('error') != '' for r in options))
        if mode == 'OFF':
            # The same fixture is started for both modes; direct traffic must not enter it.
            socket_options_valid = option_path.exists() and not options and not all_flows and not rejected_udp_peers
        if not socket_options_valid:
            errors.append('Diagnostic accepted-socket TCP_NODELAY not confirmed for both owned flows')
        socket_observation = dict(rule='owned_flows_and_explicitly_rejected_udp_v2',
                                  confirmed=socket_options_valid, accepted_sockets=len(options),
                                  matched_workload_sockets=len(matched), extra_accepted_sockets=len(extras),
                                  explicitly_rejected_udp_associates=len(rejected_udp_peers))
    flow_ids = {r['connection_id'] for r in flows}
    all_closes = [r for r in proxy if r['event'] == 'FLOW_CLOSED']
    closes = [r for r in all_closes if r['connection_id'] in flow_ids]
    if mode == 'OFF':
        if all_flows or all_closes or client['LocalAddress'] != receiver['RemoteAddress']:
            errors.append('Concurrent direct socket evidence mismatch')
    else:
        if (len(all_flows) != 2 or len(all_closes) != 2 or len(flows) != 1 or len(closes) != 1 or
                receiver['RemoteAddress'] != f"{flows[0]['outbound_local_ip']}:{flows[0]['outbound_local_port']}" or
                flows[0]['destination_ip'] != '127.0.0.1' or closes[0]['protocol'] != 'tcp' or
                closes[0]['bytes_up' if direction == 'push' else 'bytes_down'] < load['transfer_bytes']):
            errors.append('Concurrent owned proxy flow/socket/volume evidence mismatch')
        lifecycle = read(path/'cli-lifecycle.json')
        routes = read(path/'route-observations.json')
        if isinstance(routes, dict): routes = [routes]
        settings = re.search(r'\[1\]\s+SOCKS5\s+127\.0\.0\.1:54123\s+\(id=(\d+)\)', lifecycle['stdout'])
        pid = read(path/'load-client-process.json')['pid']
        if not settings or not any(r['event'] == 'RELAY_ACCEPTED_REDIRECT' and r['pid'] == pid and
                r['destination_ip'] == '127.0.0.1' and r['destination_port'] == load['receiver_port'] and
                r['action'] == 'PROXY' and r['proxy_config_id'] == int(settings.group(1)) for r in routes):
            errors.append('Concurrent product route observation missing')
    window = read(path/'load-window.json')
    pid = read(path/'load-client-process.json')['pid']
    start, end = result['measurement_start_qpc_ms'], result['measurement_end_qpc_ms']
    overlap = None
    snapshots = jsonl(path/'load-progress.jsonl')
    native_status = status_rows(path/'load-client-status.csv')
    native_rows = {progress_tuple(r, True) for r in native_status}
    if not snapshots or any(progress_tuple(s) not in native_rows or s['pid'] != pid or
            not all(math.isfinite(v) for v in progress_tuple(s)+(s['observed_qpc_ms'],)) for s in snapshots):
        errors.append('Observed concurrent progress does not match native status/PID')
    if any(b['time_slice'] <= a['time_slice'] or b['observed_qpc_ms'] <= a['observed_qpc_ms'] for a, b in zip(snapshots, snapshots[1:])):
        errors.append('Concurrent progress timestamps not strictly increasing')
    if not native_status or any(float(r['NetError']) or float(r['DataError']) for r in native_status):
        errors.append('Native concurrent transfer errors observed')
    if start is None or end is None or end <= start:
        errors.append('RTT measurement window missing')
    else:
        if (window['client_pid'] != pid or not window['load_running_at_rtt_exit'] or
                not window['start_qpc_ms'] <= window['ready_qpc_ms'] <= start < end <= window['end_qpc_ms']):
            errors.append('Load process did not enclose RTT measurement')
        inside = [s for s in snapshots if start <= s['observed_qpc_ms'] <= end]
        rate_key = 'send_bps' if direction == 'push' else 'recv_bps'
        points = [start]+[s['observed_qpc_ms'] for s in inside]+[end]
        max_gap = max(b-a for a, b in zip(points, points[1:]))
        if (len(inside) < 3 or max_gap > load['progress_max_gap_ms'] or
                any(s[rate_key] < load['rate_limit_bytes_per_s']*load['minimum_rate_fraction'] or
                    s['in_flight'] != 1 or s['completed'] != 0 or s['net_errors'] or s['data_errors'] for s in inside)):
            errors.append('Insufficient positive in-flight native load progress during RTT')
        overlap = dict(progress_samples=len(inside), max_observation_gap_ms=max_gap,
                       minimum_observed_bytes_per_s=min((s[rate_key] for s in inside), default=None),
                       rtt_window_ms=end-start, status_interval_ms=load['status_interval_ms'])
    transfer_ms = max(float(client['TimeMs']), float(receiver['TimeMs']))
    if transfer_ms <= 0: errors.append('Concurrent transfer duration missing')
    result.update(status='INCONCLUSIVE' if errors else 'MEASURED', correctness='INCONCLUSIVE' if errors else 'PASS',
                  direction=direction, load_overlap=overlap, load_connection_id=client['ConnectionId'],
                  load_verified_payload_bytes=int(client[sent]), load_transfer_ms=transfer_ms,
                  load_useful_mbit_per_s=load['transfer_bytes']*8/(transfer_ms*1000) if transfer_ms > 0 else None)
    if socket_observation is not None:
        result['diagnostic_socket_observation'] = socket_observation
    return result


def run_report(path):
    result = evaluate_loaded_run(path)
    (path/'tcp-loaded-rtt-report.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(dict(status=result['status'], errors=result['errors'])))
    return not result['errors']


def comparison(path):
    manifest = read(path/'comparison-manifest.json'); runs = []; conditions = []; errors = []; pairs = []
    if manifest.get('diagnostic_only'):
        errors.append('Isolated diagnostic is not a paired comparison')
    if manifest.get('proxy_accepted_tcp_nodelay') and manifest.get('tcp_fixture_revision') != 'accepted_nodelay_v1':
        errors.append('Unrecognised accepted TCP_NODELAY fixture revision')
    for entry in manifest['runs']:
        report = read(path/entry['directory']/'tcp-loaded-rtt-report.json')
        if (entry['status'] != 'COMPLETED' or report['status'] != 'MEASURED' or report['errors'] or
                report['mode'] != entry['mode'] or report['direction'] != entry['direction']):
            errors.append(entry['directory']+': loaded measurement not confirmed')
        cfg = {k:v for k,v in report['config'].items() if k not in ('run_id','receiver_pid','proxy_pid','sampler_pid','load')}
        load = {k:v for k,v in report['config']['load'].items() if k not in ('direction','receiver_pid')}
        if (bool(cfg.get('proxy_accepted_tcp_nodelay')) != bool(manifest.get('proxy_accepted_tcp_nodelay')) or
                cfg.get('tcp_fixture_revision') != manifest.get('tcp_fixture_revision')):
            errors.append(entry['directory']+': TCP fixture policy differs from manifest')
        for key in ('echo_count','warmup_count','message_bytes','pause_ms'):
            if cfg[key] != manifest[key]: errors.append(entry['directory']+': RTT traffic differs')
        for key in ('transfer_bytes','rate_limit_bytes_per_s'):
            if load[key] != manifest[key]: errors.append(entry['directory']+': load traffic differs')
        conditions.append((cfg, load, report['bundle_sha256'], report['other_driver_names_sha256']))
        runs.append(dict(**entry, report=report))
    if (manifest['status'] != 'COMPLETED' or len(runs) != manifest['pair_count']*4 or not conditions or
            any(c != conditions[0] for c in conditions[1:])):
        errors.append('Series incomplete or traffic/tool/product/driver conditions differ')
    for key, config in (('load_connection_id', False), ('run_id', True)):
        identities = [r['report']['config'][key] if config else r['report'][key] for r in runs]
        if len(set(identities)) != len(runs): errors.append('Run/transfer identities reused')
    for direction in ('push','pull'):
        for number in range(1,manifest['pair_count']+1):
            group = [r for r in runs if r['direction'] == direction and r['pair'] == number]
            if [r['mode'] for r in group] != (['OFF','PROXY'] if number % 2 else ['PROXY','OFF']):
                errors.append('Pair modes/order incomplete'); continue
            off, on = [next(r['report'] for r in group if r['mode'] == mode) for mode in ('OFF','PROXY')]
            if off['rtt'] and on['rtt']:
                pairs.append(dict(direction=direction, pair=number, **{k:on['rtt'][k]-off['rtt'][k] for k in ('p50_ms','p95_ms','p99_ms')}))
    result = dict(status='INCONCLUSIVE' if errors else 'LIMITED_COMPARISON', errors=errors, runs=runs,
                  pairs=pairs, version_switch_ready=False, failed_attempts=manifest.get('failed_attempts', []),
                  resumed_at_utc=manifest.get('resumed_at_utc'), retained_completed_runs=manifest.get('retained_completed_runs', 0))
    if manifest.get('tcp_fixture_revision'):
        result['tcp_fixture_revision'] = manifest['tcp_fixture_revision']
        result['proxy_accepted_tcp_nodelay'] = manifest.get('proxy_accepted_tcp_nodelay', False)
    lines = ['# Задержка TCP под нагрузкой / TCP latency under load', '', '**'+result['status']+'**', '',
             f"Передача / Transfer: {manifest['transfer_bytes']/1048576:.0f} MiB/run, RateLimit {manifest['rate_limit_bytes_per_s']/1048576:.0f} MiB/s; upload + download. RTT: {manifest['echo_count']} echoes + {manifest['warmup_count']} excluded warmup, {manifest['message_bytes']} bytes, {manifest['pause_ms']} ms pause after reply.", '',
             '| Нагрузка / Load | Mode | p50, ms | p95, ms | p99, ms | Max, ms | Transfer, Mbit/s | CLI CPU, % ПК | CLI RAM, MiB |',
             '|---|---|---:|---:|---:|---:|---:|---:|---:|']
    if not errors:
        for direction in ('push','pull'):
            for mode in ('OFF','PROXY'):
                group = [r['report'] for r in runs if r['direction'] == direction and r['mode'] == mode]
                quantiles = [statistics.median(r['rtt'][k] for r in group) for k in ('p50_ms','p95_ms','p99_ms')]
                maximum = max(r['rtt']['max_ms'] for r in group)
                rate = statistics.median(r['load_useful_mbit_per_s'] for r in group)
                cpu = f"{statistics.median(r['pc']['proxybridge_cli']['cpu_pct_machine_mean'] for r in group):.2f}" if mode == 'PROXY' else '—'
                ram = f"{statistics.median(r['pc']['proxybridge_cli']['private_mib_mean'] for r in group):.2f}" if mode == 'PROXY' else '—'
                lines.append(f"| {direction} | {mode} | {quantiles[0]:.3f} | {quantiles[1]:.3f} | {quantiles[2]:.3f} | {maximum:.3f} | {rate:.2f} | {cpu} | {ram} |")
        lines += ['', 'p50/p95/p99 и throughput — медианы показателей прогонов; Max — максимум. CPU/RAM — окно RTT после прогрева. / Median run quantiles/rate; resources within measured RTT window.', '',
                  '| Нагрузка / Load | Pair | Δ p50, ms | Δ p95, ms | Δ p99, ms |', '|---|---:|---:|---:|---:|']
        lines.extend(f"| {p['direction']} | {p['pair']} | {p['p50_ms']:+.3f} | {p['p95_ms']:+.3f} | {p['p99_ms']:+.3f} |" for p in pairs)
        for direction in ('push','pull'):
            selected = [p for p in pairs if p['direction'] == direction]
            values = [statistics.median(p[k] for p in selected) for k in ('p50_ms','p95_ms','p99_ms')]
            lines += ['', f"{direction}: медианная парная добавка / median paired delta PROXY−OFF: p50 {values[0]:+.3f}, p95 {values[1]:+.3f}, p99 {values[2]:+.3f} ms."]
        lines += ['', f"Ошибки echo / Echo failures: {sum(r['report']['failed_echoes'] for r in runs)}; verified incl. warmup: {sum(r['report']['verified_echoes'] for r in runs)}; verified load payload: {sum(r['report']['load_verified_payload_bytes'] for r in runs)/1048576:.0f} MiB."]
    lines += ['', 'Один постоянный TCP echo-сокет и одна отдельная ctsTraffic-сессия к другому контролируемому порту. Оба потока проходят выбранный маршрут; native verify:data/ConnectionId, echo run/sequence/SHA и owned proxy/product evidence обязательны. / Separate controlled ports, verified routes and payloads.', '',
              'Активность нагрузки проверяется по свежим native status samples с ненулевым темпом, In-Flight=1 и без ошибок внутри RTT-окна; шаг ctsTraffic 250ms, допустимый разрыв наблюдений ≤1000ms. Это интервальные наблюдения, не доказательство постоянного темпа в каждый момент. / Native progress observed during RTT; not an exact continuous offered-rate claim.', '',
              'RateLimit — настройка движка, не строгий потолок. Полный RTT включает ProxyBridge/SOCKS5/работу получателя; TCP_NODELAY, прогрев исключён. CPU/RAM всех участников и системы — в JSON. Driver-only/watts/ICMP/one-way/setup/capacity/game stability не измерены; SMOKE проверяет готовность. / Full-path RTT under capped transfer; bounded scope.', '',
              'Local IPv4 loopback, выбранный стендовый Driver CLI kit. HTTP отложен; UDP-дефекты этим сценарием не проверяются. Upstream HEAD/4.0.0 A-B/remote/global cleanup/version switching не подтверждены. Старые unloaded RTT отчёты не являются сопоставимой базой этого профиля. / Limited configuration and comparison only.', '']
    lines.extend('- '+e for e in errors)
    if manifest.get('tcp_fixture_revision'):
        lines += ['', 'SOCKS5-стенд: accepted TCP_NODELAY=1; рабочие сокеты проверены, в OFF прокси остаётся без соединений. Эта конфигурация отличается от прежнего стенда. / Accepted TCP_NODELAY=1 verified on workload sockets; direct mode leaves the proxy idle. Do not pool with legacy fixture results.']
    if result['resumed_at_utc']:
        lines += ['', f"Возобновлённая серия / Resumed series: retained {result['retained_completed_runs']} runs. Временной разрыв, не непрерывный нагрузочный прогон. / Includes a time gap, not uninterrupted stability evidence."]
    if result['failed_attempts']:
        lines += ['', 'Исключённые попытки сохранены / Excluded attempts retained:']
        for attempt in result['failed_attempts']:
            lines.append('- '+attempt['directory']+': '+('; '.join(attempt['errors']) or attempt['status']))
        lines += ['Не считать успешные повторы доказательством отсутствия пауз/сбоев первоначальной серии. / Successful retries do not erase original stalls or failures.']
    (path/'comparison-report.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    (path/'summary.md').write_text('\n'.join(lines), encoding='utf-8')
    print(json.dumps(dict(status=result['status'], errors=errors)))
    return not errors


def validate_resume(path):
    """Read-only gate for a stopped STANDARD series with a completed prefix."""
    manifest = read(path/'comparison-manifest.json')
    if manifest['profile'] != 'STANDARD' or manifest['status'] != 'FAILED':
        raise ValueError('Resume requires failed STANDARD series')
    if manifest.get('diagnostic_only'):
        raise ValueError('Isolated diagnostic cannot be resumed as comparison')
    if manifest.get('proxy_accepted_tcp_nodelay') and manifest.get('tcp_fixture_revision') != 'accepted_nodelay_v1':
        raise ValueError('Resume requires recognised TCP fixture revision')
    expected = [(direction, number, mode) for direction in ('push','pull') for number in range(1,4)
                for mode in (('OFF','PROXY') if number % 2 else ('PROXY','OFF'))]
    entries = manifest['runs']; retained = []; failed = []
    if not entries or len(entries) > len(expected): raise ValueError('Unexpected resume series length')
    for index, entry in enumerate(entries):
        if (entry['direction'], entry['pair'], entry['mode']) != expected[index]:
            raise ValueError('Resume order differs from requested comparison')
        folder = (path/entry['directory']).resolve()
        if folder.parent != path.resolve(): raise ValueError('Run directory must be directly inside evidence directory')
        if entry['status'] == 'COMPLETED':
            if failed: raise ValueError('Completed runs after failed attempt cannot be retained')
            result = evaluate_loaded_run(folder)
            saved = read(folder/'tcp-loaded-rtt-report.json')
            if result['status'] != 'MEASURED' or result != saved:
                raise ValueError('Retained run no longer matches verified evidence: '+entry['directory'])
            retained.append(entry)
        else:
            if index != len(entries)-1: raise ValueError('Only final interrupted attempt can be retried')
            receipt = read(folder/'run-receipt.json')
            if not receipt['workers_stopped'] or not receipt['driver_stop_observed']:
                raise ValueError('Interrupted run cleanup is unconfirmed')
            after = read(folder/'loaded-drivers-after.json'); state = read(folder/'interception-after.json')
            if not after['query_complete'] or not after['known_interception_driver_names_absent'] or not state['wfp_detachment_observed']:
                raise ValueError('Interrupted run stopped driver/WFP evidence missing')
            report_path = folder/'tcp-loaded-rtt-report.json'
            report = read(report_path) if report_path.exists() else None
            failed.append(dict(**entry, errors=report['errors'] if report else [receipt['error']],
                               evidence_status=report['status'] if report else receipt['status']))
    if not retained or len(retained) >= len(expected): raise ValueError('No unfinished work after verified prefix')
    reports = [read(path/e['directory']/'tcp-loaded-rtt-report.json') for e in retained]
    for report in reports:
        cfg = report['config']
        if (bool(cfg.get('proxy_accepted_tcp_nodelay')) != bool(manifest.get('proxy_accepted_tcp_nodelay')) or
                cfg.get('tcp_fixture_revision') != manifest.get('tcp_fixture_revision')):
            raise ValueError('Retained TCP fixture policy differs from manifest')
    def signature(r):
        cfg = {k:v for k,v in r['config'].items() if k not in ('run_id','receiver_pid','proxy_pid','sampler_pid','load')}
        load = {k:v for k,v in r['config']['load'].items() if k not in ('direction','receiver_pid')}
        return cfg, load, r['bundle_sha256'], r['other_driver_names_sha256']
    if any(signature(r) != signature(reports[0]) for r in reports[1:]):
        raise ValueError('Retained benchmark conditions differ')
    print(json.dumps(dict(status='RESUME_VALIDATED', retained=retained, failed=failed, remaining=len(expected)-len(retained))))
    return True


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--run-directory', type=Path)
    group.add_argument('--evidence-directory', type=Path)
    group.add_argument('--validate-resume', type=Path)
    args = parser.parse_args()
    operation = (validate_resume(args.validate_resume) if args.validate_resume else
                 run_report(args.run_directory) if args.run_directory else comparison(args.evidence_directory))
    raise SystemExit(0 if operation else 1)
