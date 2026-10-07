"""Strict scope checks for the opt-in 4.0.0 transfer readiness stage."""
import hashlib
import json
from pathlib import Path
import re


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def check_legacy_scope(path, config, receipt, client, flows, lifecycle, before, after, errors):
    product, context = read(path/'product-build.json'), read(path/'version-context.json')
    idle_path = Path(context['legacy_idle_directory'])
    idle = read(idle_path/'idle-receipt.json')
    idle_loaded = read(idle_path/'loaded-drivers-idle.json')
    preflight = read(idle_path.parent/'preflight.json')
    selected = [p for p in preflight['products'] if p['contract'] == 'v4.0.0']
    profiles = [p for p in preflight['profile_files'] if p['file_name'] == 'v4.0.0-transfer.pbprofile']
    diagnostic = config.get('legacy_transfer_stage') in ('transfer_rude_diagnostic_v1', 'transfer_graceful_diagnostic_v1', 'transfer_graceful_halfclose_diagnostic_v1')
    graceful_diagnostic = config.get('legacy_transfer_stage') in ('transfer_graceful_diagnostic_v1', 'transfer_graceful_halfclose_diagnostic_v1')
    repeated = config.get('legacy_transfer_stage') == 'transfer_data_standard_v1'
    stage = config['legacy_transfer_stage'] if diagnostic else 'transfer_data_standard_v1' if repeated else 'transfer_data_smoke_v1' if config.get('transfer_only') else 'transfer_smoke_v1'
    if diagnostic:
        shutdown = 'graceful' if graceful_diagnostic else 'rude'
        launch = read(path/'client-launch.json')
        window = read(path/'measurement-window.json')
        process = read(path/'client-process.json')
        options = re.findall(r'(?:^|\s)-shutdown:([^\s"]+)', launch['observed_command_line'], re.I)
        expected = [a.lower() for a in launch['expected_arguments'] if a.lower().startswith('-shutdown:')]
        if (not config.get('diagnostic_only') or config.get('shutdown_mode') != shutdown or
            not context.get('diagnostic_only') or context.get('shutdown_mode') != shutdown or context['readiness_only'] or
            receipt['mode'] != 'PROXY' or config['direction'] != 'push' or
            options != [shutdown] or expected != ['-shutdown:'+shutdown] or launch['pid'] != process['pid'] or
            not window['start_qpc_ms'] <= launch['capture_qpc_ms'] <= window['end_qpc_ms'] or
            any(str(Path(launch[k]).resolve()).casefold() != str(Path(process['actual_path']).resolve()).casefold()
                for k in ('expected_executable', 'observed_executable'))):
            errors.append('Diagnostic shutdown launch/scope not confirmed')
        if graceful_diagnostic:
            verbosity = re.findall(r'(?:^|\s)-consoleverbosity:([^\s"]+)', launch['observed_command_line'], re.I)
            expected_verbosity = [a.lower() for a in launch['expected_arguments'] if a.lower().startswith('-consoleverbosity:')]
            if (config.get('console_verbosity') != 6 or verbosity != ['6'] or expected_verbosity != ['-consoleverbosity:6'] or
                'completing a GracefulShutdown (statusCode 0)' not in process['stdout']):
                errors.append('Diagnostic graceful shutdown/debug observation not confirmed')
        if stage == 'transfer_graceful_halfclose_diagnostic_v1':
            events = [json.loads(line) for line in (path/'proxy-halfclose.jsonl').read_text(encoding='utf-8').splitlines() if line]
            ready = [e for e in events if e['event'] == 'ADAPTATION_READY']
            eof = [e for e in events if e['event'] == 'WRITE_EOF']
            finished = [e for e in events if e['event'] == 'BOTH_DIRECTIONS_FINISHED']
            if (config.get('tcp_fixture_revision') != 'halfclose_diagnostic_v1' or context.get('tcp_fixture_revision') != 'halfclose_diagnostic_v1' or
                any(e['process_id'] != config['proxy_pid'] for e in events) or len(ready) != 1 or
                (len(ready) == 1 and (not ready[0]['transfer_loop_unchanged'] or ready[0]['fixture_revision'] != config['tcp_fixture_revision'] or
                                    ready[0]['base_sha256'].lower() != config['proxy_helper_sha256'].lower() or
                                    ready[0]['wheel_sha256'].lower() != config['proxy_wheel_sha256'].lower() or
                                    ready[0]['launcher_sha256'].lower() != config['proxy_launcher_sha256'].lower())) or
                len(flows) != 1 or len(eof) != 2 or {e['direction'] for e in eof} != {'UPSTREAM', 'DOWNSTREAM'} or len(finished) != 1 or
                (len(flows) == 1 and any(e['flow_id'] != flows[0]['connection_id'] for e in eof+finished))):
                errors.append('Diagnostic half-close fixture adaptation/owned EOF not confirmed')
    elif config.get('diagnostic_only') or context.get('diagnostic_only') or context['readiness_only'] is not (not repeated):
        errors.append('Legacy readiness/diagnostic scope differs')
    if (config['product_contract'] != 'v4.0.0' or config.get('legacy_transfer_stage') != stage or
        config.get('live_socket_observation_policy') != 'owned-socket-snapshot-transfer-smoke-v1' or
        (config['transfer_bytes'], config['rate_limit_bytes_per_s'], config['connections'], config['buffer_bytes']) !=
            ((2147483648, 67108864, 1, 65536) if repeated else (67108864, 8388608, 1, 65536)) or
        context['product_contract'] != 'v4.0.0' or context['legacy_transfer_stage'] != stage or
        not context['reboot_required_before_other_version'] or context['version_switch_ready'] or
        not product['files_verified'] or product['selected_contract'] != 'v4.0.0' or
        product['declared_cli_variant'] != 'testlab-unbuffered-v1' or
        preflight['status'] != 'FILES_AND_PROFILES_PREPARED' or preflight['switch_policy'] != 'reboot_between_versions' or
        len(selected) != 1 or len(profiles) != 1 or
        (len(selected) == 1 and (product['bundle_sha256'] != selected[0]['identity']['bundle_sha256'] or
                               product['declared_source_commit'] != selected[0]['identity']['declared_source_commit']))):
        errors.append('Legacy transfer stage/kit/preflight not confirmed')
    if repeated:
        from pb_tcp_transfer_reference import check_legacy_repeat
        check_legacy_repeat(path, config, product, context, before, after, errors)
    if (idle['status'] != 'LEGACY_IDLE_SCOPED_OBSERVED' or idle['contract'] != 'v4.0.0' or idle['error'] or
        not all(idle[k] for k in ('same_version_idle_observed', 'no_compatible_windivert_handles_observed', 'known_wfp_detachment_observed')) or
        idle['boot_identity'] != context['boot_identity'] or not idle_loaded['query_complete'] or idle_loaded['selected_driver_loaded']):
        errors.append('Legacy idle/boot reference not confirmed')
    sha = config['route_profile_sha256'].lower()
    if context['route_profile_sha256'].lower() != sha or len(profiles) != 1 or (len(profiles) == 1 and profiles[0]['sha256'].lower() != sha):
        errors.append('Legacy transfer profile reference changed')
    if receipt['mode'] == 'PROXY':
        if hashlib.sha256((path/'route.pbprofile').read_bytes()).hexdigest() != sha:
            errors.append('Legacy transfer profile bytes changed')
        profile = read(path/'route.pbprofile')
        rules, proxies = profile['ProxyRules'], profile['ProxyConfigs']
        if (not profile['LocalhostViaProxy'] or len(rules) != 1 or len(proxies) != 1 or
            (len(rules) == 1 and any(rules[0].get(k) != v for k, v in
                dict(ProcessName='ctsTraffic.exe', TargetHosts='127.0.0.1', TargetPorts='54122', Protocol='TCP',
                     Action='PROXY', ProxyConfigId=1, IsEnabled=True).items())) or
            (len(proxies) == 1 and any(proxies[0].get(k) != v for k, v in
                dict(Id=1, Type='SOCKS5', Host='127.0.0.1', Port='54123', Username='', Password='').items())) or
            any(r.get('TargetDomains', '') for r in rules) or any(p.get('SendDomainToProxy', False) for p in proxies)):
            errors.append('Legacy transfer process/IP/port/proxy constraints differ')
    if (not all(r['query_complete'] and not r['selected_driver_loaded'] and
                all(n.lower() == 'windivert64.sys' for n in r['known_interception_drivers']) for r in (before, after)) or
        before['other_driver_names_sha256'] != after['other_driver_names_sha256'] or
        before['other_driver_names_sha256'] != idle_loaded['other_driver_names_sha256']):
        errors.append('Legacy stopped inventory differs or incomplete')
    phases = ('before', 'after', 'active') if receipt['mode'] == 'PROXY' else ('before', 'after')
    for phase in phases:
        state = read(path/('interception-'+phase+'.json'))
        observer = state['windivert']
        if (not state['wfp_detachment_observed'] or not state['wfp_objects']['query_complete'] or
            state['wfp']['status'] != 'SERVICE_FILE_VERIFIED' or state['wfp']['service_state'] != 'Stopped' or
            not observer['files_verified'] or not observer['capture_complete'] or
            observer['observer_sha256'] != 'f27980b00d97e3f6a590cf4fad04f30f4c61c72324d52af2442afdcf69f31765' or
            observer['observer_dll_sha256'] != 'c1e060ee19444a259b2162f8af0f3fe8c4428a1c6f694dce20de194ac8d7d9a2'):
            errors.append('Legacy '+phase+': scoped WFP/observer observation incomplete')
        handles = observer['handles']
        if phase == 'active':
            active = read(path/'loaded-drivers-active.json')
            if (not active['query_complete'] or active['selected_driver_loaded'] or
                [n.lower() for n in active['known_interception_drivers']] != ['windivert64.sys'] or
                active['other_driver_names_sha256'] != before['other_driver_names_sha256'] or
                observer['status'] != 'HANDLES_OBSERVED' or observer['observed_handle_count'] != 1 or len(handles) != 1 or
                (len(handles) == 1 and (handles[0]['pid'], handles[0]['layer'], handles[0]['flags']) != (lifecycle['pid'], 'NETWORK', '0'))):
                errors.append('Legacy owned active NETWORK handle not confirmed')
        elif (state['boot_identity'] != context['boot_identity'] or observer['status'] != 'NO_HANDLES_OBSERVED' or
              observer['observed_handle_count'] != 0 or handles):
            errors.append('Legacy '+phase+': boot/idle handles differ')
    observation = read(path/'live-socket-observation.json')
    owner = lifecycle['pid'] if receipt['mode'] == 'PROXY' else read(path/'client-process.json')['pid']
    target = config['proxy_port'] if receipt['mode'] == 'PROXY' else config['receiver_port']
    window = read(path/'measurement-window.json')
    if (observation['owner_pid'] != owner or observation['target_port'] != target or
        not window['start_qpc_ms'] <= observation['start_qpc_ms'] <= observation['capture_completed_qpc_ms'] <= window['end_qpc_ms']):
        errors.append('Legacy transfer socket observation scope/timing differs')
    connections = read(path/('product-proxy-connections.json' if receipt['mode'] == 'PROXY' else 'generator-direct-connections.json'))
    if isinstance(connections, dict):
        connections = [connections]
    peer = f"{flows[0]['inbound_peer_ip']}:{flows[0]['inbound_peer_port']}" if receipt['mode'] == 'PROXY' and len(flows) == 1 else client['LocalAddress'] if receipt['mode'] == 'OFF' else None
    if peer is None or not any(c['OwningProcess'] == owner and f"{c['LocalAddress']}:{c['LocalPort']}" == peer and
                              c['RemoteAddress'] == '127.0.0.1' and c['RemotePort'] == target for c in connections):
        errors.append('Legacy owned controlled TCP connection not confirmed')
    if lifecycle and len(selected) == 1:
        expected_cli = Path(selected[0]['env_path']).parent/'ProxyBridge_CLI.exe'
        if (lifecycle['actual_path_probe_status'] != 'PATH_OBTAINED' or
            str(Path(lifecycle['actual_path']).resolve()).casefold() != str(expected_cli.resolve()).casefold() or
            not lifecycle['output_capture_complete'] or lifecycle['error']):
            errors.append('Legacy CLI path/output/stop evidence incomplete')
