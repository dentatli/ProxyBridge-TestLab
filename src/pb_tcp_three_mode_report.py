"""Saved-data checks and aggregation for a distinct three-mode TCP readiness series."""
import argparse
import hashlib
import json
from pathlib import Path
import re

from pb_tcp_benchmark_report import read

STAGE = 'three_modes_readiness_v1'
MODES = ('OFF', 'UNRULED', 'PROXY')


def validate_run(path, cfg, receipt, native, processes, lifecycle, measured_start):
    errors = []
    mode = receipt['mode']
    product = read(path/'product-build.json')
    preset = cfg.get('comparison_stage') == 'three_modes_workload_v1'
    if preset:
        from pb_workload import check_rtt_workload
        check_rtt_workload(cfg, errors)
    if (mode not in MODES or cfg.get('product_contract', 'driver') != 'driver' or
            product['selected_contract'] != 'driver' or not product['files_verified'] or
            cfg.get('load') or cfg.get('version_rtt_stage') or cfg.get('legacy_rtt_stage') or
            (not preset and (cfg['echo_count'], cfg['warmup_count'], cfg['message_bytes'], cfg['pause_ms'], cfg['connections']) != (128, 200, 512, 20, 1)) or
            cfg.get('live_socket_observation_policy') != 'owned-socket-snapshot-before-measurement-v1'):
        errors.append('Three-mode readiness configuration or selected kit differs')
    for phase in ('before', 'after', 'active') if mode != 'OFF' else ('before', 'after'):
        state = read(path/('interception-'+phase+'.json'))
        if (state['wfp']['status'] != 'SERVICE_FILE_VERIFIED' or
                state['wfp']['service_state'] != ('Running' if phase == 'active' else 'Stopped') or
                (phase != 'active' and (not state['wfp_detachment_observed'] or not state['wfp_objects']['query_complete']))):
            errors.append('Three-mode scoped driver state not confirmed: '+phase)
    observation = read(path/'live-socket-observation.json')
    owner = lifecycle['pid'] if mode == 'PROXY' else processes['client']['pid']
    target = cfg['proxy_port'] if mode == 'PROXY' else cfg['receiver_port']
    if (not measured_start or observation['owner_pid'] != owner or observation['target_port'] != target or
            not (0 < observation['start_qpc_ms'] <= observation['capture_completed_qpc_ms'] < measured_start)):
        errors.append('Owned socket observation not completed before measured RTT')
    connections = read(path/('product-proxy-connections.json' if mode == 'PROXY' else 'generator-direct-connections.json'))
    if isinstance(connections, dict):
        connections = [connections]
    if mode == 'PROXY':
        from pb_tcp_benchmark_report import jsonl
        flows = [row for row in jsonl(path/'proxy.jsonl') if row['event'] == 'TCP_CONNECTED']
        peer = (flows[0]['inbound_peer_ip'], flows[0]['inbound_peer_port']) if len(flows) == 1 else None
    else:
        peer = (native[0]['actual_local_ip'], native[0]['actual_local_port']) if native else None
    if peer is None or not any(row['OwningProcess'] == owner and
            (row['LocalAddress'], row['LocalPort']) == peer and row['RemoteAddress'] == '127.0.0.1' and row['RemotePort'] == target
            for row in connections):
        errors.append('Owned controlled TCP connection not confirmed')
    if mode != 'OFF':
        profile = read(path/'route.pbprofile')
        rules = profile['ProxyRules']
        proxies = profile['ProxyConfigs']
        image = 'pb_testlab_other_app.exe' if mode == 'UNRULED' else 'pb_tcp_rtt_client.exe'
        if (not profile['LocalhostViaProxy'] or not profile['IsTrafficLoggingEnabled'] or len(rules) != 1 or len(proxies) != 1 or
                rules[0]['ProcessName'] != image or rules[0]['Action'] != 'PROXY' or rules[0]['Protocol'] != 'TCP' or
                rules[0]['TargetHosts'] != '127.0.0.1' or str(rules[0]['TargetPorts']) != str(cfg['receiver_port']) or
                rules[0]['TargetDomains'] != '' or not rules[0]['IsEnabled'] or rules[0]['ProxyConfigId'] != 1 or
                proxies[0]['Id'] != 1 or proxies[0]['Type'] != 'SOCKS5' or proxies[0]['Host'] != '127.0.0.1' or
                str(proxies[0]['Port']) != str(cfg['proxy_port'])):
            errors.append('Exact single application rule/proxy profile differs')
        watches = re.findall(r'driver: pushed (\d+) watched image\(s\)', lifecycle['stdout'])
        added = re.findall(r"Added rule ID: \d+ for process '([^']+)'", lifecycle['stdout'])
        if (added != [image] or not watches or any(value != '1' for value in watches) or
                '1 added, 0 failed' not in lifecycle['stdout'] or 'driver: ProxyBridgeDrv active -' not in lifecycle['stdout']):
            errors.append('Applied profile/watchlist not confirmed by owned CLI')
        if mode == 'UNRULED':
            routes = read(path/'route-observations.json')
            if isinstance(routes, dict):
                routes = [routes]
            client = processes['client']['pid']
            owned = [row for row in routes if row.get('pid') == client]
            if (not any(row['event'] == 'ROUTE_DECISION' and row['process'].lower() == 'pb_tcp_rtt_client.exe' and
                    row['destination_ip'] == '127.0.0.1' and row['destination_port'] == cfg['receiver_port'] and row['action'] == 'DIRECT'
                    for row in owned) or any(row['event'] == 'RELAY_ACCEPTED_REDIRECT' or row.get('action') in ('PROXY', 'BLOCK') for row in owned)):
                errors.append('Unruled direct route or absence of owned redirect not confirmed')
    return errors


def comparison(path):
    from pb_tcp_rtt_report import evaluate_run
    manifest = read(path/'comparison-manifest.json')
    errors, runs, conditions = [], [], []
    preset = manifest.get('comparison_stage') == 'three_modes_workload_v1'
    if preset:
        from pb_workload import valid_workload
        if not valid_workload(manifest.get('workload_preset')):
            errors.append('Three-mode workload series preset differs')
    if (manifest.get('comparison_stage') not in (STAGE, 'three_modes_workload_v1') or manifest.get('product_contract') != 'driver' or
            manifest['profile'] != 'SMOKE' or manifest['pair_count'] != 1 or manifest['status'] != 'COMPLETED' or
            manifest['error'] or len(manifest['runs']) != 3 or manifest.get('readiness_only') != (not preset)):
        errors.append('Three-mode readiness series incomplete or method differs')
    for index, entry in enumerate(manifest['runs']):
        expected = MODES[index] if index < len(MODES) else None
        if entry['mode'] != expected or entry['pair'] != 1 or entry['directory'] != 'pair-01-'+str(expected).lower():
            errors.append('Three-mode readiness order or source directory invalid')
            continue
        directory = path/entry['directory']
        saved = read(directory/'tcp-rtt-report.json')
        actual = evaluate_run(directory)
        if entry['status'] != 'COMPLETED' or actual != saved or actual['status'] != 'MEASURED' or actual['correctness'] != 'PASS' or actual['errors']:
            errors.append(entry['directory']+': source measurement not confirmed')
        cfg = {key: value for key, value in saved['config'].items() if key not in ('run_id', 'receiver_pid', 'proxy_pid', 'sampler_pid')}
        if (cfg.get('comparison_stage') != manifest.get('comparison_stage') or
                (preset and cfg.get('workload_preset') != manifest.get('workload_preset')) or
                any(cfg[key] != manifest[key] for key in ('echo_count', 'warmup_count', 'message_bytes', 'pause_ms'))):
            errors.append(entry['directory']+': requested conditions differ')
        conditions.append((cfg, saved['bundle_sha256'], saved['other_driver_names_sha256']))
        runs.append(dict(**entry, report=saved))
    if not conditions or any(value != conditions[0] for value in conditions[1:]) or len({row['report']['config']['run_id'] for row in runs}) != 3:
        errors.append('Three-mode conditions/kit/driver inventory differ or identities reused')
    deltas = {}
    if not errors:
        by_mode = {row['mode']: row['report'] for row in runs}
        for name, left, right in (('unruled_vs_off', 'UNRULED', 'OFF'), ('proxy_vs_off', 'PROXY', 'OFF'), ('proxy_vs_unruled', 'PROXY', 'UNRULED')):
            deltas[name] = {key: by_mode[left]['rtt'][key]-by_mode[right]['rtt'][key] for key in ('p50_ms','p95_ms','p99_ms')}
    result = dict(schema_version=1, comparison_stage=manifest.get('comparison_stage'), status='INCONCLUSIVE' if errors else 'LIMITED_COMPARISON',
                  errors=errors, runs=runs, deltas_ms=deltas, readiness_only=not preset, version_switch_ready=False)
    if preset:
        result['workload_preset'] = manifest.get('workload_preset')
    lines = ['# Три режима: задержка TCP / Three-mode TCP RTT', '', '**'+result['status']+'**', '',
             '| Режим / Mode | p50, ms | p95, ms | p99, ms | CLI CPU, % ПК | CLI Private RAM, MiB |', '|---|---:|---:|---:|---:|---:|']
    labels = {'OFF':'Напрямую, ProxyBridge выключен / ProxyBridge off', 'UNRULED':'Напрямую, ProxyBridge работает, без правила / Running, unruled', 'PROXY':'Через SOCKS5 / SOCKS5'}
    if not errors:
        for row in runs:
            report = row['report']; rtt = report['rtt']; cli = report['pc'].get('proxybridge_cli')
            cpu = f"{cli['cpu_pct_machine_mean']:.3f}" if cli else '—'
            ram = f"{cli['private_mib_mean']:.2f}" if cli else '—'
            lines.append(f"| {labels[row['mode']]} | {rtt['p50_ms']:.3f} | {rtt['p95_ms']:.3f} | {rtt['p99_ms']:.3f} | {cpu} | {ram} |")
        lines += ['', '| Разница / Difference | Δ p50, ms | Δ p95, ms | Δ p99, ms |', '|---|---:|---:|---:|']
        for label, delta in deltas.items():
            lines.append(f"| {label} | {delta['p50_ms']:+.3f} | {delta['p95_ms']:+.3f} | {delta['p99_ms']:+.3f} |")
    lines += ['', f"{manifest['echo_count']} измерений + {manifest['warmup_count']} исключённых прогревочных обменов на режим; {manifest['message_bytes']} байт, пауза {manifest['pause_ms']} мс. / Measured echoes plus excluded warmup per mode.",
              'Один цикл в фиксированном порядке; не доказательство причинного улучшения сборки. Socket snapshot должен завершиться до измерения. / Fixed-order observations, no causal performance claim.',
              'UNRULED−OFF — наблюдаемая разница работающего продукта без правила. PROXY−OFF включает весь SOCKS5-путь и стенд. CPU/RAM CLI не равны ресурсам драйвера; ватты не измерены. / Observed path deltas, not driver-only cost or watts.',
              'Не ICMP ping, не максимальная скорость, не сравнение версий, не тест насыщения таблиц. / Not ICMP, capacity, version comparison or table saturation.',
              'Состояние драйверов проверяется в известной области; внешние незаписанные запуски не исключены глобально. / Scoped observations, no global interception proof.']
    lines.extend('- '+error for error in errors)
    (path/'comparison-report.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    (path/'summary.md').write_text('\n'.join(lines)+'\n', encoding='utf-8')
    print(json.dumps(dict(status=result['status'], errors=errors)))
    return not errors


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--evidence-directory', type=Path, required=True)
    raise SystemExit(0 if comparison(parser.parse_args().evidence_directory) else 1)
