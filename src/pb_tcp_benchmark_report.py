"""Report verified ctsTraffic TCP transfers; TimeMs is transfer time, never RTT."""
import argparse
import csv
import json
from pathlib import Path
import re
import statistics


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def jsonl(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8-sig').splitlines() if line]


def connection(path):
    raw = path.read_bytes()
    text = raw.decode('utf-16' if raw.startswith(b'\xff\xfe') else 'utf-8-sig')
    rows = list(csv.DictReader(text.splitlines()))
    if len(rows) != 1:
        raise ValueError('Exactly one completed connection required: '+str(path))
    return rows[0]


def evaluate_run(path):
    errors = []
    receipt = read(path/'run-receipt.json')
    config = read(path/'benchmark-config.json')
    contract = config.get('product_contract', 'driver')
    if contract not in ('driver', 'v4.0.0'):
        errors.append('Unsupported product contract')
    lifecycle = None
    client, receiver = connection(path/'client.csv'), connection(path/'receiver.csv')
    if receipt['status'] != 'COMPLETED' or not all(receipt[k] for k in ('workers_stopped','driver_stop_observed','receiver_identity_verified')):
        errors.append('Run or owned-resource cleanup incomplete')
    for name in ('client','receiver','proxy','sampler'):
        process = read(path/(name+'-process.json'))
        if process['exit_code'] != 0 or process.get('forced_stop', False) or process.get('timed_out', False) or not process['output_capture_complete']:
            errors.append(name+': process completion not confirmed')
        if name in ('client','receiver') and not re.search(r'Level of verification:\s*Connections & Data', process['stdout']):
            errors.append(name+': engine data-verification setting not observed')
        if name == 'proxy' and 'Exception in callback' in process['stderr']:
            errors.append('Proxy Python event-loop callback failed')
    if config['verify'] != 'data' or any(r['Result'] != 'Succeeded' for r in (client, receiver)):
        errors.append('Data/connection verification did not pass')
    if not re.fullmatch(r'[0-9a-fA-F-]{36}', client['ConnectionId']) or client['ConnectionId'] != receiver['ConnectionId']:
        errors.append('Client/receiver connection identity differs')
    sent = 'SendBytes' if config['direction'] == 'push' else 'RecvBytes'
    received = 'RecvBytes' if config['direction'] == 'push' else 'SendBytes'
    unused_client = 'RecvBytes' if config['direction'] == 'push' else 'SendBytes'
    unused_receiver = 'SendBytes' if config['direction'] == 'push' else 'RecvBytes'
    if (int(client[sent]) != config['transfer_bytes'] or int(receiver[received]) != config['transfer_bytes'] or
        int(client[unused_client]) != 0 or int(receiver[unused_receiver]) != 0):
        errors.append('Verified payload volumes differ from requested transfer')
    proxy = jsonl(path/'proxy.jsonl')
    expected_loop = config.get('proxy_event_loop')
    if expected_loop and not any(r['event']=='LISTENING' and r.get('event_loop')==expected_loop for r in proxy):
        errors.append('Configured proxy event loop not observed')
    flows = [r for r in proxy if r['event'] == 'TCP_CONNECTED']
    closes = [r for r in proxy if r['event'] == 'FLOW_CLOSED']
    if any(r['event'] == 'ERROR' for r in proxy) or not any(r['event'] == 'STOPPED' and r['shutdown_reason'] == 'STDIN_STOP' for r in proxy):
        errors.append('Proxy error or unconfirmed orderly stop')
    if receiver['LocalAddress'] != '127.0.0.1:54122' or client['RemoteAddress'] != receiver['LocalAddress']:
        errors.append('Unexpected controlled destination')
    if receipt['mode'] == 'OFF':
        if flows or closes or client['LocalAddress'] != receiver['RemoteAddress']:
            errors.append('Direct path socket evidence mismatch')
    else:
        if (len(flows) != 1 or len(closes) != 1 or
            receiver['RemoteAddress'] != f"{flows[0]['outbound_local_ip']}:{flows[0]['outbound_local_port']}" or
            flows[0]['destination_ip'] != '127.0.0.1' or flows[0]['destination_port'] != 54122 or
            closes[0]['connection_id'] != flows[0]['connection_id'] or
            closes[0]['protocol'] != 'tcp' or closes[0]['bytes_up' if config['direction'] == 'push' else 'bytes_down'] < config['transfer_bytes']):
            errors.append('Owned proxy socket/flow/byte evidence mismatch')
        lifecycle = read(path/'cli-lifecycle.json')
        if not lifecycle['ready'] or not lifecycle['graceful_stop'] or lifecycle['forced_stop'] or not lifecycle['post_stop_verified']:
            errors.append('CLI lifecycle incomplete')
        routes = read(path/'route-observations.json')
        if isinstance(routes, dict):
            routes = [routes]
        settings = re.search(r'\[1\]\s+SOCKS5\s+127\.0\.0\.1:54123\s+\(id=(\d+)\)', lifecycle['stdout'])
        pid = read(path/'client-process.json')['pid']
        if contract == 'v4.0.0':
            route_found = any(r['event'] == 'ROUTE_DECISION' and r['pid'] == pid and r['process'].lower() == 'ctstraffic.exe' and
                              r['destination_ip'] == '127.0.0.1' and r['destination_port'] == 54122 and r['action'] == 'PROXY' and
                              r['route_detail'] == 'Proxy SOCKS5://127.0.0.1:54123' for r in routes)
        else:
            route_found = any(r['event'] == 'RELAY_ACCEPTED_REDIRECT' and r['pid'] == pid and
                                   r['destination_ip'] == '127.0.0.1' and r['destination_port'] == 54122 and
                                   r['action'] == 'PROXY' and settings and r['proxy_config_id'] == int(settings.group(1)) for r in routes)
        if not settings or not route_found:
            errors.append('Product route observation missing')
    before, after = [read(path/('loaded-drivers-'+stage+'.json')) for stage in ('before','after')]
    if contract == 'v4.0.0':
        from pb_tcp_transfer_scope import check_legacy_scope
        check_legacy_scope(path, config, receipt, client, flows, lifecycle, before, after, errors)
    elif (not all(r['query_complete'] and r['known_interception_driver_names_absent'] for r in (before, after)) or
        before['other_driver_names_sha256'] != after['other_driver_names_sha256']):
        errors.append('Stopped driver inventory differs or incomplete')
    if receipt['mode'] == 'PROXY' and contract != 'v4.0.0':
        active = read(path/'loaded-drivers-active.json')
        if not active['query_complete'] or not active['selected_driver_loaded'] or len(active['known_interception_drivers']) != 1 or active['other_driver_names_sha256'] != before['other_driver_names_sha256']:
            errors.append('Active selected driver not confirmed')
    window = read(path/'measurement-window.json')
    start, end = window['start_qpc_ms'], window['end_qpc_ms']
    samples = jsonl(path/'pc-samples.jsonl')
    full = [r for r in samples if r['event'] == 'SAMPLE' and r['interval_start_qpc_ms'] >= start and r['qpc_ms'] <= end]
    roles = ('receiver','proxy','generator') + (('proxybridge_cli',) if receipt['mode'] == 'PROXY' else ())
    expected_pids = dict(receiver=config['receiver_pid'],proxy=config['proxy_pid'],generator=window['client_pid'])
    if receipt['mode'] == 'PROXY':
        expected_pids['proxybridge_cli']=read(path/'cli-lifecycle.json')['pid']
    pc = {}
    for role in roles:
        if not any(r['event']=='WATCHED' and r['role']==role and r['pid']==expected_pids[role] for r in samples):
            errors.append(role+': actual process identity not observed')
        values = [(p, r['qpc_ms']) for r in full for p in r['processes'] if p['role'] == role and p['pid']==expected_pids[role] and p['status'] == 'OBSERVED' and p['interval_start_qpc_ms'] >= start]
        coverage = sum(t-p['interval_start_qpc_ms'] for p,t in values)
        if len(values) < 3 or coverage < .65*(end-start):
            errors.append(role+': insufficient process sampling coverage')
        pc[role] = dict(samples=len(values), coverage_ms=coverage,
                        cpu_pct_machine_mean=sum(p['cpu_pct_machine']*(t-p['interval_start_qpc_ms']) for p,t in values)/coverage if coverage else None,
                        private_mib_mean=statistics.mean(p['private_bytes'] for p,t in values)/1048576 if values else None)
    transfer_ms = max(float(client['TimeMs']), float(receiver['TimeMs']))
    if transfer_ms <= 0:
        errors.append('Transfer duration missing')
    result = dict(schema_version=1,status='INCONCLUSIVE' if errors else 'MEASURED',errors=errors,
                  mode=receipt['mode'],direction=config['direction'],connection_id=client['ConnectionId'],
                  verified_payload_bytes=int(client[sent]),transfer_ms=transfer_ms,
                  useful_mbit_per_s=config['transfer_bytes']*8/(transfer_ms*1000) if transfer_ms>0 else None,
                  process_window_ms=end-start,pc=pc,config=config,
                  bundle_sha256=read(path/'product-build.json')['bundle_sha256'],
                  other_driver_names_sha256=before['other_driver_names_sha256'],
                  rtt_measured=False,version_switch_ready=False)
    if contract == 'v4.0.0':
        result.update(readiness_only=True, live_socket_observation_during_transfer=True, product_contract=contract)
        if config.get('legacy_transfer_stage') in ('transfer_rude_diagnostic_v1', 'transfer_graceful_diagnostic_v1', 'transfer_graceful_halfclose_diagnostic_v1'):
            result.update(diagnostic_only=True, readiness_only=False,
                          graceful_shutdown_verified=config['shutdown_mode'] == 'graceful' and not errors,
                          comparison_eligible=False)
    if config.get('transfer_only') or config.get('tcp_shutdown_policy'):
        from pb_tcp_data_scope import check_data_scope, data_scope_details
        check_data_scope(path, config, read(path/'client-process.json'), read, errors)
        result.update(data_scope_details('4.0.0' if contract == 'v4.0.0' else 'driver', config.get('transfer_profile') == 'STANDARD'))
        if config.get('workload_preset') is not None:
            result.update(workload_preset=config['workload_preset'], readiness_only=False)
        result['status'] = 'INCONCLUSIVE' if errors else 'MEASURED'
    if config.get('version_transfer_stage') or config.get('legacy_transfer_directory'):
        if contract == 'v4.0.0' and config.get('version_transfer_stage') == 'data-transfer-repeat-legacy-v1':
            if config.get('legacy_transfer_stage') != 'transfer_data_standard_v1' or not config.get('transfer_only'):
                errors.append('Repeated 4.0.0 reference requires data-only STANDARD scope')
            # Full cross-version binding is checked by check_legacy_scope above.
        else:
            from pb_tcp_transfer_reference import check_bound_driver
            if contract != 'driver' or not config.get('transfer_only'):
                errors.append('Driver readiness reference requires data-only driver scope')
            check_bound_driver(path, config, receipt, client, flows, lifecycle, errors)
        result.update(version_reference_bound=not errors, live_socket_observation_during_transfer=True,
                      version_comparison_ready=False)
        result['status'] = 'INCONCLUSIVE' if errors else 'MEASURED'
    return result


def run_report(path):
    result = evaluate_run(path)
    (path/'tcp-benchmark-report.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    errors = result['errors']
    if result.get('diagnostic_only'):
        lines = ['# Диагностика закрытия TCP 4.0.0 / TCP close diagnostic', '', result['status'], '',
                 'Один upload через SOCKS5, 64 MiB, verify:data; штатный ctsTraffic -shutdown:'+result['config']['shutdown_mode']+'. / One upload using the stock shutdown option.', '',
                 'Успех подтверждает только этот способ завершения. Исходный graceful-сброс сохранён; точный виновник сброса не установлен. / Success applies only to this closing strategy; original graceful reset remains unresolved.', '',
                 'Нет прямой пары или сравнения версий; диагностический темп не объединять с обычными сериями. / No paired/version comparison; diagnostic timings remain separate.', '',
                 'Подтверждено graceful-завершение этого прогона / This run graceful shutdown verified: '+str(result['graceful_shutdown_verified'])]
        lines.extend('- '+error for error in errors)
        (path/'diagnostic-summary.md').write_text('\n'.join(lines),encoding='utf-8')
    print(json.dumps(dict(status=result['status'],errors=errors)))
    return not errors


def comparison(directory):
    manifest=read(directory/'comparison-manifest.json')
    if manifest.get('diagnostic_only'):
        raise ValueError('Isolated shutdown diagnostics cannot be used as paired comparisons')
    runs=[];errors=[];conditions=[]
    for entry in manifest['runs']:
        report=read(directory/entry['directory']/'tcp-benchmark-report.json')
        if report.get('diagnostic_only'):
            errors.append(entry['directory']+': isolated diagnostic excluded from comparisons')
        if entry['status']!='COMPLETED' or report['status']!='MEASURED' or report['mode']!=entry['mode'] or report['direction']!=entry['direction']:
            errors.append(entry['directory']+': incomplete or unconfirmed')
        config={k:v for k,v in report['config'].items() if k not in ('direction','receiver_pid','proxy_pid','sampler_pid')}
        if config['transfer_bytes']!=manifest['transfer_bytes'] or config['rate_limit_bytes_per_s']!=manifest['rate_limit_bytes_per_s']:
            errors.append(entry['directory']+': requested traffic differs')
        conditions.append((config,report['bundle_sha256'],report['other_driver_names_sha256']))
        runs.append(dict(**entry,report=report))
    if manifest['status']!='COMPLETED' or len(runs)!=manifest['pair_count']*4 or any(c!=conditions[0] for c in conditions[1:]):
        errors.append('Series incomplete or tool/traffic/product/driver conditions differ')
    if manifest.get('transfer_only') or any(r['report'].get('transfer_only') for r in runs):
        if manifest.get('workload_preset') is not None:
            from pb_workload import valid_workload
            preset = manifest['workload_preset']
            if (not valid_workload(preset) or manifest.get('readiness_only') is not False or
                    any(row['report']['config'].get('workload_preset') != preset or row['report'].get('readiness_only') is not False for row in runs)):
                errors.append('Workload transfer manifest/run preset differs')
        repeated = manifest.get('profile') == 'STANDARD'
        legacy_repeat = manifest.get('product_contract') == 'v4.0.0' and repeated
        repeated_stage = 'data-transfer-repeat-legacy-v1' if legacy_repeat else 'data-transfer-repeat-v1'
        source_key = 'driver_transfer_directory' if legacy_repeat else 'driver_smoke_directory'
        if (manifest.get('transfer_only') is not True or manifest.get('tcp_shutdown_policy') != 'data-transfer-only-v1' or
            manifest.get('shutdown_mode') != 'rude' or manifest.get('normal_tcp_close_verified') is not False or
            manifest.get('profile') not in ('SMOKE', 'STANDARD') or manifest['pair_count'] != (3 if repeated else 1) or
            (repeated and (manifest.get('product_contract') not in ('driver', 'v4.0.0') or
                manifest.get('version_transfer_stage') != repeated_stage or not manifest.get(source_key) or
                manifest.get('readiness_only') is not False or
                (manifest['transfer_bytes'], manifest['rate_limit_bytes_per_s'], manifest['connections'], manifest['buffer_bytes'], manifest['verify']) !=
                    (2147483648, 67108864, 1, 65536, 'data'))) or
            any(not r['report'].get('transfer_only') or r['report'].get('normal_tcp_close_verified') is not False or
                r['report'].get('product_label') != manifest.get('product_label') or
                (repeated and (r['report'].get('readiness_only') is not False or
                    r['report']['config'].get('transfer_profile') != 'STANDARD' or
                    r['report']['config'].get(source_key) != manifest[source_key])) for r in runs)):
            errors.append('Data-only readiness manifest/run scope differs')
    if len({r['report']['connection_id'] for r in runs})!=len(runs):
        errors.append('Connection IDs reused between runs')
    pairs=[]
    for direction in ('push','pull'):
        for number in range(1,manifest['pair_count']+1):
            group=[r for r in runs if r['direction']==direction and r['pair']==number]
            if [r['mode'] for r in group] != (['OFF','PROXY'] if number%2 else ['PROXY','OFF']):
                errors.append('Pair modes/order incomplete');continue
            off=next(r['report'] for r in group if r['mode']=='OFF');on=next(r['report'] for r in group if r['mode']=='PROXY')
            if off['useful_mbit_per_s'] and on['useful_mbit_per_s']:
                pairs.append(dict(direction=direction,pair=number,rate_change_pct=100*(on['useful_mbit_per_s']/off['useful_mbit_per_s']-1)))
    result=dict(status='INCONCLUSIVE' if errors else 'LIMITED_COMPARISON',errors=errors,runs=runs,pairs=pairs,rtt_measured=False,version_switch_ready=False,
                resumed_at_utc=manifest.get('resumed_at_utc'),retained_completed_runs=manifest.get('retained_completed_runs',0),
                failed_attempts=manifest.get('failed_attempts',[]),helper_stop_timeout_change=manifest.get('helper_stop_timeout_change'))
    if manifest.get('transfer_only'):
        from pb_tcp_data_scope import data_scope_details
        result.update(data_scope_details(manifest['product_label'], manifest.get('profile') == 'STANDARD'))
    if manifest.get('version_transfer_stage') or any(r['report'].get('version_reference_bound') for r in runs):
        legacy_repeat = manifest.get('version_transfer_stage') == 'data-transfer-repeat-legacy-v1'
        reference_key = 'driver_transfer_directory' if legacy_repeat else 'legacy_transfer_directory'
        if (manifest.get('version_transfer_stage') not in ('data-transfer-readiness-bound-v1', 'data-transfer-repeat-v1', 'data-transfer-repeat-legacy-v1') or
            manifest.get('product_contract') != ('v4.0.0' if legacy_repeat else 'driver') or not manifest.get(reference_key) or
            any(not r['report'].get('version_reference_bound') or
                r['report']['config'].get('version_transfer_stage') != manifest['version_transfer_stage'] or
                r['report']['config'].get(reference_key) != manifest[reference_key] for r in runs)):
            errors.append('Bound driver readiness manifest/run reference differs')
        result.update(version_reference_bound=not errors, version_comparison_ready=False)
        result['status'] = 'INCONCLUSIVE' if errors else 'LIMITED_COMPARISON'
    lines=['# TCP SOCKS5 и прямое соединение / TCP SOCKS5 vs direct','', '**'+result['status']+'**','',
           'Готовый движок ctsTraffic 2.0.3.9, verify:data; один TCP-поток на прогон, контролируемый получатель. / Existing engine, one TCP connection per run, controlled receiver.', '',
           f"Передача {manifest['transfer_bytes']/1048576:.0f} MiB; настройка RateLimit {manifest['rate_limit_bytes_per_s']/1048576:.0f} MiB/s в обоих режимах. / Identical configured sender rate limit. "
           'Измеренный средний темп короткой передачи может отличаться от настройки; это не проверка жёсткого лимита / A short-transfer observed average can differ from the setting; strict rate-limit enforcement is not evaluated.', '',
           '| Направление / Direction | Режим / Mode | Мбит/с / Mbit/s | CPU CLI, % ПК | Private RAM CLI, MiB |','|---|---|---:|---:|---:|']
    if not errors:
        for direction in ('push','pull'):
            for mode in ('OFF','PROXY'):
                group=[r['report'] for r in runs if r['direction']==direction and r['mode']==mode]
                cpu=statistics.median(r['pc']['proxybridge_cli']['cpu_pct_machine_mean'] for r in group) if mode=='PROXY' else None
                mem=statistics.median(r['pc']['proxybridge_cli']['private_mib_mean'] for r in group) if mode=='PROXY' else None
                cpu_text=f'{cpu:.2f}' if cpu is not None else '—'
                mem_text=f'{mem:.2f}' if mem is not None else '—'
                lines.append(f"| {'Загрузка на получатель / Upload' if direction=='push' else 'Скачивание / Download'} | {mode} | {statistics.median(r['useful_mbit_per_s'] for r in group):.2f} | {cpu_text} | {mem_text} |")
        lines.extend(['','| Направление / Direction | Пара / Pair | PROXY − OFF, % |','|---|---:|---:|'])
        lines.extend(f"| {p['direction']} | {p['pair']} | {p['rate_change_pct']:+.2f} |" for p in pairs)
    if result['resumed_at_utc']:
        change=result['helper_stop_timeout_change']
        lines.extend(['',f"Серия возобновлена: сохранено {result['retained_completed_runs']} завершённых прогонов; неудачных попыток вне сравнения: {len(result['failed_attempts'])}. / Resumed series; completed runs retained, failed attempts excluded.",
                      f"Ожидание остановки помощников после измерения: {change['previous_ms']} → {change['current_ms']} мс. Байты движка, proxy/sampler helpers и параметры трафика сохранены; между частями серии была пауза. / Post-measurement helper stop deadline changed; measurement tools/traffic unchanged, with a gap between series parts."])
        lines.extend(f"- Неудачная попытка / Failed attempt: `{attempt['directory']}` — {attempt['observed_failure']}; исходные свидетельства сохранены / original evidence retained." for attempt in result['failed_attempts'])
    if runs and runs[0]['report']['config'].get('proxy_event_loop'):
        lines.extend(['','TCP SOCKS5 helper использует Windows SelectorEventLoop; предел 512 сокетов. Текущий профиль — одно соединение; это не подтверждение высокой параллельной нагрузки. / Windows selector loop, 512-socket limit; current single-connection profile does not validate high concurrency.'])
    if runs and runs[0]['report']['config'].get('product_contract') == 'v4.0.0':
        if manifest.get('profile') == 'SMOKE':
            lines[4:4] = ['**Проверка готовности 4.0.0 / Legacy transfer readiness only.** Socket query выполняется во время передачи; темп диагностический. Это не A/B версий и не точные накладные расходы. / Socket observation overlaps transfer; diagnostic rates, no version comparison.', '']
        lines.extend(['', 'OFF допускает idle loaded WinDivert при нуле наблюдаемых совместимых handles. Перед driver нужна перезагрузка. / Legacy OFF can retain an idle loaded driver; reboot before driver.', ''])
    if manifest.get('transfer_only'):
        lines[2:2] = ['**Версия / Version: '+manifest['product_label']+'**', '',
                      '**Передача данных / Data transfer.** Обе стороны проверяют данные; ctsTraffic shutdown:rude. Штатное закрытие TCP не проверяется, его прежние ошибки сохраняются. / Data verification retained; normal TCP close is not tested.', '']
        for issue in result['known_problems']:
            lines[2:2] = ['**'+issue['title_ru']+' / '+issue['title_en']+'**', '', issue['message_ru']+' / '+issue['message_en'], '']
    if manifest.get('version_transfer_stage'):
        if manifest['version_transfer_stage'] == 'data-transfer-repeat-legacy-v1':
            lines.extend(['', 'Повторные измерения 4.0.0 связаны с завершённой серией driver: те же инструменты, правила, 3 пары на направление и 2 GiB @ 64 MiB/s; перезагрузка между версиями. Запрос сокетов выполняется во время передачи, прогрев не исключён. Итоги двух версий требуют отдельной агрегации; эта таблица сравнивает OFF/PROXY только для 4.0.0. / Equivalent rate-capped repeated 4.0.0 transfers, reboot and driver reference bound; instrumented timings, separate version aggregation pending.', ''])
        elif manifest['version_transfer_stage'] == 'data-transfer-repeat-v1':
            lines.extend(['', 'Повторные измерения driver: три чередующиеся пары на направление, 2 GiB и настройка 64 MiB/s на перенос. Условия связаны с подтверждённой проверкой готовности; эта серия имеет новые параметры, её темп не объединять с SMOKE. Запрос сокетов выполняется во время передачи, прогрев не исключён. Сопоставимая повторная серия 4.0.0 ещё не измерена; это не сравнение версий. / Repeated rate-capped driver transfers, readiness-bound conditions, instrumentation included; no excluded warmup or version comparison.', ''])
        else:
            lines.extend(['', 'Проверка готовности driver связана с завершённой серией 4.0.0: одинаковые инструменты и параметры, перезагрузка между версиями. Запрос сокетов выполняется во время передачи. Это ещё не повторное сравнение скорости версий. / Driver readiness bound to the completed 4.0.0 series; same tools/settings and reboot, with socket observation during transfer. This is not a repeated version speed comparison.', ''])
    lines.extend(['','RTT/ping не измерены; TimeMs — время TCP-передачи и её завершения, не задержка отдельного сообщения. / No RTT/ping measurement.','',
                  'Темп ограничен: это не максимальная ёмкость. Прогрев не исключён; один ограниченный перенос данных, не длительная стабильность. / Rate capped, no excluded warmup, bounded transfer, not sustained stability.','',
                  'Разница включает SOCKS5-сервер, проверку данных и инструменты; не отдельную стоимость только ProxyBridge/драйвера. CPU относится к окну процесса, driver-only/watts не измерены. / Whole instrumented path; process-window CPU, no driver-only or power attribution.','',
                  'CPU 0,00% означает ноль или малое значение в охваченных выборках с указанным округлением; это не доказательство отсутствия нагрузки. Короткие окна и исключённые граничные интервалы ограничивают оценку. / Zero displayed sampled CPU is not proof of zero CPU cost; short windows and excluded boundary intervals limit interpretation.','',
                  'Исходный commit не перепроверялся по сети; используется явно выбранный kit. Global cleanup/переключение версий не подтверждены. / Selected kit only; global/version gates remain false.',''])
    lines.extend('- '+error for error in errors)
    (directory/'comparison-report.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    (directory/'summary.md').write_text('\n'.join(lines),encoding='utf-8')
    print(json.dumps(dict(status=result['status'],errors=errors)))
    return not errors


def main():
    parser=argparse.ArgumentParser()
    group=parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--run-directory',type=Path)
    group.add_argument('--evidence-directory',type=Path)
    args=parser.parse_args()
    raise SystemExit(0 if (run_report(args.run_directory) if args.run_directory else comparison(args.evidence_directory)) else 1)


if __name__=='__main__':
    main()
