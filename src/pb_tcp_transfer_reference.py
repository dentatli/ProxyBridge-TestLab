"""Bind a driver readiness run to actual 4.0.0 data-only evidence; no traffic."""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def profile_constraints(path):
    profile = read(path)
    require(profile['LocalhostViaProxy'] and profile['IsTrafficLoggingEnabled'] is True and
            len(profile['ProxyRules']) == len(profile['ProxyConfigs']) == 1,
            'One localhost proxy rule required')
    rule, proxy = profile['ProxyRules'][0], profile['ProxyConfigs'][0]
    fields = dict(ProcessName='ctsTraffic.exe', TargetHosts='127.0.0.1', TargetPorts='54122',
                  Protocol='TCP', Action='PROXY', ProxyConfigId=1, IsEnabled=True)
    endpoint = dict(Id=1, Type='SOCKS5', Host='127.0.0.1', Port='54123', Username='', Password='')
    require(all(rule.get(k) == v for k, v in fields.items()) and not rule.get('TargetDomains') and
            all(proxy.get(k) == v for k, v in endpoint.items()) and not proxy.get('SendDomainToProxy'),
            'Controlled TCP process/IP/port/SOCKS5 constraints differ')
    return dict(rule=fields, proxy=endpoint)


def prepare_reference(source):
    # Import here to avoid a cycle when the evaluator checks a bound driver run.
    from pb_tcp_benchmark_report import evaluate_run
    source = source.resolve()
    before = {str(p.relative_to(source)): digest(p) for p in sorted(source.rglob('*')) if p.is_file()}
    manifest, aggregate = [read(source/name) for name in ('comparison-manifest.json', 'comparison-report.json')]
    require(manifest['status'] == 'COMPLETED' and not manifest['error'] and manifest['profile'] == 'SMOKE' and
            manifest['pair_count'] == 1 and manifest.get('product_contract') == 'v4.0.0' and
            manifest.get('transfer_only') is True and manifest.get('tcp_shutdown_policy') == 'data-transfer-only-v1' and
            manifest.get('normal_tcp_close_verified') is False and manifest.get('shutdown_mode') == 'rude' and
            len(manifest['runs']) == 4 and aggregate['status'] == 'LIMITED_COMPARISON' and not aggregate['errors'] and
            len(aggregate['runs']) == 4, 'Complete 4.0.0 data-only SMOKE required')
    context, common, bundle, other = None, None, None, None
    reports = []
    for index, entry in enumerate(manifest['runs']):
        direction, mode = ('push' if index < 2 else 'pull'), ('OFF' if index % 2 == 0 else 'PROXY')
        name = direction+'-pair-01-'+mode.lower()
        require(entry['directory'] == name and entry['mode'] == mode and entry['direction'] == direction and
                entry['pair'] == 1 and entry['status'] == 'COMPLETED', 'Source order/status differs')
        path = source/name
        report = evaluate_run(path)
        require(report == read(path/'tcp-benchmark-report.json') and report['status'] == 'MEASURED' and
                not report['errors'] and aggregate['runs'][index] == dict(**entry, report=report),
                'Source saved verdict/evidence changed')
        cfg, ctx = report['config'], read(path/'version-context.json')
        tools = {k: cfg[k] for k in ('engine_sha256', 'proxy_wheel_sha256', 'proxy_helper_sha256',
                                    'sampler_helper_sha256', 'python_sha256', 'proxy_event_loop')}
        if context is None:
            context, common, bundle, other = ctx, tools, report['bundle_sha256'], report['other_driver_names_sha256']
        require(ctx == context and tools == common and report['bundle_sha256'] == bundle and
                report['other_driver_names_sha256'] == other, 'Source conditions mixed')
        reports.append(report)
    preflight_dir = Path(context['legacy_idle_directory']).parent
    preflight_path = preflight_dir/'preflight.json'
    preflight = read(preflight_path)
    require(preflight['status'] == 'FILES_AND_PROFILES_PREPARED' and
            preflight['switch_policy'] == 'reboot_between_versions', 'Common preflight not confirmed')
    profiles, products = {}, {}
    external = {str(p.resolve()): digest(p) for p in (preflight_path,
                Path(context['legacy_idle_directory'])/'idle-receipt.json',
                Path(context['legacy_idle_directory'])/'loaded-drivers-idle.json')}
    for contract in ('v4.0.0', 'driver'):
        selected = [p for p in preflight['products'] if p['contract'] == contract]
        require(len(selected) == 1, 'Preflight product missing')
        selected = selected[0]
        kit = Path(selected['env_path']).parent
        receipt = kit/'build-receipt.json'
        require(digest(receipt) == selected['build_receipt_sha256'].lower(), 'Build receipt changed')
        external[str(receipt.resolve())] = digest(receipt)
        for component in selected['identity']['components']:
            require(digest(kit/component['file_name']) == component['sha256'].lower(), 'Selected product bytes changed')
        products[contract] = selected
        profile = preflight_dir/(contract+'-transfer.pbprofile')
        expected = [p for p in preflight['profile_files'] if p['file_name'] == profile.name]
        require(len(expected) == 1 and digest(profile) == expected[0]['sha256'].lower(), 'Prepared profile changed')
        external[str(profile.resolve())] = digest(profile)
        profiles[contract] = dict(path=str(profile.resolve()), sha256=digest(profile), constraints=profile_constraints(profile))
    require(products['v4.0.0']['identity']['bundle_sha256'] == bundle and
            profiles['v4.0.0']['sha256'] == context['route_profile_sha256'].lower() and
            profiles['driver']['constraints'] == profiles['v4.0.0']['constraints'], 'Profile/kit source binding differs')
    require(before == {str(p.relative_to(source)): digest(p) for p in sorted(source.rglob('*')) if p.is_file()},
            'Source files changed while reading')
    return dict(schema_version=1, stage='data-transfer-readiness-bound-v1', source_directory=str(source),
                source_sha256=before, external_sha256=external, legacy_boot_identity=context['boot_identity'],
                legacy_completed_at_utc=manifest['completed_at_utc'], common_tools=common, profiles=profiles,
                driver_product=products['driver'], other_driver_names_sha256=other,
                readonly_source_runs_verified=4, readiness_only=True, version_comparison_ready=False,
                normal_tcp_close_verified=False)


def prepare_driver_smoke(source):
    from pb_tcp_benchmark_report import evaluate_run
    source = source.resolve()
    before = {str(p.relative_to(source)): digest(p) for p in sorted(source.rglob('*')) if p.is_file()}
    manifest, aggregate = [read(source/name) for name in ('comparison-manifest.json', 'comparison-report.json')]
    require(manifest['status'] == 'COMPLETED' and not manifest['error'] and manifest['profile'] == 'SMOKE' and
            manifest['pair_count'] == 1 and manifest.get('product_contract') == 'driver' and
            manifest.get('transfer_only') is True and manifest.get('normal_tcp_close_verified') is False and
            manifest.get('version_transfer_stage') == 'data-transfer-readiness-bound-v1' and
            len(manifest['runs']) == 4 and aggregate['status'] == 'LIMITED_COMPARISON' and not aggregate['errors'] and
            aggregate.get('version_reference_bound') is True and len(aggregate['runs']) == 4,
            'Complete bound driver data-only SMOKE required')
    binding = read(source/'legacy-transfer-reference.json')
    require(binding == prepare_reference(Path(manifest['legacy_transfer_directory'])), 'Driver SMOKE legacy binding changed')
    context = None
    for index, entry in enumerate(manifest['runs']):
        direction, mode = ('push' if index < 2 else 'pull'), ('OFF' if index % 2 == 0 else 'PROXY')
        name = direction+'-pair-01-'+mode.lower()
        require(entry['directory'] == name and entry['mode'] == mode and entry['direction'] == direction and
                entry['pair'] == 1 and entry['status'] == 'COMPLETED', 'Driver SMOKE order/status differs')
        path = source/name
        report = evaluate_run(path)
        require(report == read(path/'tcp-benchmark-report.json') and report['status'] == 'MEASURED' and
                not report['errors'] and report.get('version_reference_bound') is True and
                aggregate['runs'][index] == dict(**entry, report=report), 'Driver SMOKE verdict/evidence changed')
        ctx = read(path/'version-context.json')
        if context is None:
            context = ctx
        require(ctx == context, 'Driver SMOKE boot/context mixed')
    require(before == {str(p.relative_to(source)): digest(p) for p in sorted(source.rglob('*')) if p.is_file()},
            'Driver SMOKE source changed while reading')
    return dict(legacy_reference=binding, driver_smoke_reference=dict(schema_version=1,
                source_directory=str(source), source_sha256=before, boot_identity=context['boot_identity'],
                completed_at_utc=manifest['completed_at_utc'], readonly_source_runs_verified=4,
                repeat_profile=dict(transfer_bytes=2147483648, rate_limit_bytes_per_s=67108864,
                                    pair_count=3, connections=1, buffer_bytes=65536, verify='data')))


def prepare_driver_repeat(source):
    from pb_tcp_benchmark_report import evaluate_run
    source = source.resolve()
    before = {str(p.relative_to(source)): digest(p) for p in sorted(source.rglob('*')) if p.is_file()}
    manifest, aggregate = [read(source/name) for name in ('comparison-manifest.json', 'comparison-report.json')]
    require(manifest['status'] == 'COMPLETED' and not manifest['error'] and manifest['profile'] == 'STANDARD' and
            manifest['pair_count'] == 3 and manifest.get('product_contract') == 'driver' and
            manifest.get('transfer_only') is True and manifest.get('normal_tcp_close_verified') is False and
            manifest.get('version_transfer_stage') == 'data-transfer-repeat-v1' and manifest.get('readiness_only') is False and
            len(manifest['runs']) == 12 and aggregate['status'] == 'LIMITED_COMPARISON' and not aggregate['errors'] and
            aggregate.get('version_reference_bound') is True and len(aggregate['runs']) == 12,
            'Complete repeated driver data-only series required')
    seed = prepare_driver_smoke(Path(manifest['driver_smoke_directory']))
    binding = seed['legacy_reference']
    require(read(source/'legacy-transfer-reference.json') == binding and
            read(source/'driver-smoke-reference.json') == seed['driver_smoke_reference'], 'Repeated driver source binding changed')
    context, conditions, other, ids = None, None, None, set()
    for index, entry in enumerate(manifest['runs']):
        direction, pair = ('push' if index < 6 else 'pull'), ((index % 6)//2+1)
        modes = ('OFF', 'PROXY') if pair % 2 else ('PROXY', 'OFF')
        mode = modes[index % 2]
        name = f'{direction}-pair-{pair:02d}-{mode.lower()}'
        require(entry['directory'] == name and entry['mode'] == mode and entry['direction'] == direction and
                entry['pair'] == pair and entry['status'] == 'COMPLETED', 'Repeated driver order/status differs')
        path = source/name
        report = evaluate_run(path)
        require(report == read(path/'tcp-benchmark-report.json') and report['status'] == 'MEASURED' and
                not report['errors'] and report.get('version_reference_bound') is True and
                report.get('readiness_only') is False and aggregate['runs'][index] == dict(**entry, report=report),
                'Repeated driver saved verdict/evidence changed')
        cfg = {k:v for k,v in report['config'].items() if k not in ('direction', 'receiver_pid', 'proxy_pid', 'sampler_pid')}
        ctx = read(path/'version-context.json')
        if context is None:
            context, conditions, other = ctx, cfg, report['other_driver_names_sha256']
        require(ctx == context and cfg == conditions and report['other_driver_names_sha256'] == other and
                report['bundle_sha256'] == binding['driver_product']['identity']['bundle_sha256'], 'Repeated driver conditions mixed')
        require(report['connection_id'] not in ids, 'Repeated driver connection IDs reused')
        ids.add(report['connection_id'])
    preflight = read(Path(binding['profiles']['v4.0.0']['path']).parent/'preflight.json')
    legacy = [p for p in preflight['products'] if p['contract'] == 'v4.0.0']
    require(len(legacy) == 1, 'Prepared 4.0.0 product missing')
    require(before == {str(p.relative_to(source)): digest(p) for p in sorted(source.rglob('*')) if p.is_file()},
            'Repeated driver files changed while reading')
    return dict(schema_version=1, stage='data-transfer-repeat-legacy-v1', source_directory=str(source),
                source_sha256=before, driver_boot_identity=context['boot_identity'],
                driver_completed_at_utc=manifest['completed_at_utc'], readonly_source_runs_verified=12,
                common_tools=binding['common_tools'], profiles=binding['profiles'], legacy_product=legacy[0],
                preflight_directory=str(Path(binding['profiles']['v4.0.0']['path']).parent),
                other_driver_names_sha256=other, normal_tcp_close_verified=False, version_comparison_ready=False)


def check_legacy_repeat(path, config, product, context, before, after, errors):
    try:
        binding = read(path.parent/'driver-transfer-reference.json')
        require(binding == prepare_driver_repeat(Path(config['driver_transfer_directory'])), 'Repeated driver reference changed')
        require(config.get('transfer_profile') == 'STANDARD' and config.get('transfer_only') is True and
                context.get('driver_transfer_directory') == binding['source_directory'] and
                context.get('driver_boot_identity') == binding['driver_boot_identity'] and
                config.get('version_transfer_stage') == context.get('version_transfer_stage') == binding['stage'] and
                context.get('readiness_only') is False and context.get('reboot_between_versions_observed') is True and
                str(Path(context['legacy_idle_directory']).parent.resolve()) == binding['preflight_directory'],
                'Repeated 4.0.0 reference/profile context differs')
        boot = context['boot_identity']
        require(all(boot[k] == binding['driver_boot_identity'][k] for k in ('computer_name', 'machine_guid', 'os_build')) and
                datetime.fromisoformat(boot['boot_time_utc']) > datetime.fromisoformat(binding['driver_completed_at_utc']),
                'New boot after the complete driver series required')
        require(product['files_verified'] and product['selected_contract'] == 'v4.0.0' and
                product['declared_cli_variant'] == 'testlab-unbuffered-v1' and
                all(product[k] == binding['legacy_product']['identity'][k] for k in ('bundle_sha256', 'declared_source_commit')),
                'Repeated 4.0.0 selected kit differs')
        require(all(config[k].lower() == v.lower() for k,v in binding['common_tools'].items()) and
                config['route_profile_sha256'].lower() == binding['profiles']['v4.0.0']['sha256'] and
                all(r['other_driver_names_sha256'] == binding['other_driver_names_sha256'] for r in (before, after)),
                'Repeated 4.0.0 tools/profile/other loaded driver names differ')
    except (ValueError, KeyError, OSError, TypeError, IndexError) as error:
        errors.append('Repeated 4.0.0 binding: '+str(error))


def check_bound_driver(path, config, receipt, client, flows, lifecycle, errors):
    try:
        binding = read(path.parent/'legacy-transfer-reference.json')
        require(binding == prepare_reference(Path(config['legacy_transfer_directory'])), 'Bound source fingerprint changed')
        repeated = config.get('version_transfer_stage') == 'data-transfer-repeat-v1'
        stage = 'data-transfer-repeat-v1' if repeated else binding['stage']
        if repeated:
            seed = read(path.parent/'driver-smoke-reference.json')
            require(seed == prepare_driver_smoke(Path(config['driver_smoke_directory']))['driver_smoke_reference'],
                    'Driver repeated transfer readiness source changed')
            require(config.get('transfer_profile') == 'STANDARD' and config.get('transfer_only') is True and
                    tuple(config[k] for k in ('transfer_bytes', 'rate_limit_bytes_per_s', 'connections', 'buffer_bytes', 'verify')) ==
                    (2147483648, 67108864, 1, 65536, 'data'), 'Driver repeated transfer workload differs')
        context = read(path/'version-context.json')
        require(context['legacy_transfer_directory'] == binding['source_directory'] and
                context['legacy_boot_identity'] == binding['legacy_boot_identity'] and
                context['version_transfer_stage'] == config['version_transfer_stage'] == stage and
                context['reboot_between_versions_observed'] and context['readiness_only'] is (not repeated) and
                not context['version_switch_ready'], 'Driver readiness reference context differs')
        boot = context['boot_identity']
        if repeated:
            require(boot == seed['boot_identity'] and context['driver_smoke_directory'] == seed['source_directory'],
                    'Repeated driver transfer must use the successful readiness boot')
        require(all(boot[k] == binding['legacy_boot_identity'][k] for k in ('computer_name', 'machine_guid', 'os_build')) and
                datetime.fromisoformat(boot['boot_time_utc']) > datetime.fromisoformat(binding['legacy_completed_at_utc']),
                'A new boot after the complete 4.0.0 series required')
        product = read(path/'product-build.json')
        expected = binding['driver_product']['identity']
        require(product['files_verified'] and product['selected_contract'] == 'driver' and
                product['declared_cli_variant'] == 'testlab-unbuffered-v1' and
                all(product[k] == expected[k] for k in ('bundle_sha256', 'declared_source_commit')),
                'Bound driver kit differs')
        require(all(config[k].lower() == v.lower() for k, v in binding['common_tools'].items()) and
                config['live_socket_observation_policy'] == 'owned-socket-snapshot-transfer-smoke-v1' and
                config['route_profile_sha256'].lower() == context['route_profile_sha256'].lower() == binding['profiles']['driver']['sha256'],
                'Bound driver tools/profile/socket policy differs')
        for phase in ('before', 'after'):
            state, loaded = read(path/('interception-'+phase+'.json')), read(path/('loaded-drivers-'+phase+'.json'))
            observer = state['windivert']
            require(state['boot_identity'] == boot and state['wfp_detachment_observed'] and
                    state['wfp_objects']['query_complete'] and state['wfp']['service_state'] == 'Stopped' and
                    loaded['query_complete'] and loaded['known_interception_driver_names_absent'] and
                    loaded['other_driver_names_sha256'] == binding['other_driver_names_sha256'] and
                    observer['files_verified'] and observer['capture_complete'] and
                    observer['observer_sha256'] == 'f27980b00d97e3f6a590cf4fad04f30f4c61c72324d52af2442afdcf69f31765' and
                    observer['observer_dll_sha256'] == 'c1e060ee19444a259b2162f8af0f3fe8c4428a1c6f694dce20de194ac8d7d9a2' and
                    observer['status'] == 'NO_HANDLES_OBSERVED' and observer['observed_handle_count'] == 0 and not observer['handles'],
                    'Bound driver idle/boot/interception evidence differs')
        if receipt['mode'] == 'PROXY':
            state = read(path/'interception-active.json')
            observer = state['windivert']
            require(state['wfp']['service_state'] == 'Running' and state['wfp']['status'] == 'SERVICE_FILE_VERIFIED' and
                    observer['files_verified'] and observer['capture_complete'] and
                    observer['observer_sha256'] == 'f27980b00d97e3f6a590cf4fad04f30f4c61c72324d52af2442afdcf69f31765' and
                    observer['observer_dll_sha256'] == 'c1e060ee19444a259b2162f8af0f3fe8c4428a1c6f694dce20de194ac8d7d9a2' and
                    observer['status'] == 'NO_HANDLES_OBSERVED' and observer['observed_handle_count'] == 0 and not observer['handles'],
                    'Bound driver active WFP/WinDivert evidence incomplete')
            require(digest(path/'route.pbprofile') == binding['profiles']['driver']['sha256'] and
                    profile_constraints(path/'route.pbprofile') == binding['profiles']['v4.0.0']['constraints'],
                    'Bound driver owned profile differs')
            require(Path(lifecycle['actual_path']).resolve() == Path(binding['driver_product']['env_path']).parent/'ProxyBridge_CLI.exe' and
                    lifecycle['output_capture_complete'] and not lifecycle['error'], 'Bound driver CLI path/output differs')
        owner = lifecycle['pid'] if receipt['mode'] == 'PROXY' else read(path/'client-process.json')['pid']
        target = 54123 if receipt['mode'] == 'PROXY' else 54122
        observation, window = read(path/'live-socket-observation.json'), read(path/'measurement-window.json')
        require(observation['owner_pid'] == owner and observation['target_port'] == target and
                window['start_qpc_ms'] <= observation['start_qpc_ms'] <= observation['capture_completed_qpc_ms'] <= window['end_qpc_ms'],
                'Bound driver live socket timing/ownership differs')
        connections = read(path/('product-proxy-connections.json' if receipt['mode'] == 'PROXY' else 'generator-direct-connections.json'))
        if isinstance(connections, dict):
            connections = [connections]
        peer = f"{flows[0]['inbound_peer_ip']}:{flows[0]['inbound_peer_port']}" if receipt['mode'] == 'PROXY' and len(flows) == 1 else client['LocalAddress'] if receipt['mode'] == 'OFF' else None
        require(peer is not None and any(c['OwningProcess'] == owner and
                f"{c['LocalAddress']}:{c['LocalPort']}" == peer and c['RemoteAddress'] == '127.0.0.1' and c['RemotePort'] == target
                for c in connections), 'Bound driver owned controlled socket missing')
    except (ValueError, KeyError, OSError, TypeError, IndexError) as error:
        errors.append('Bound driver readiness: '+str(error))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--source', type=Path)
    group.add_argument('--driver-smoke', type=Path)
    group.add_argument('--driver-repeat', type=Path)
    args = parser.parse_args()
    result = prepare_reference(args.source) if args.source else prepare_driver_smoke(args.driver_smoke) if args.driver_smoke else prepare_driver_repeat(args.driver_repeat)
    print(json.dumps(result, ensure_ascii=True))
