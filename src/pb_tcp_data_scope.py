"""Verify live native options for the opt-in, data-only transfer readiness profile."""
from pathlib import Path
import re


def check_data_scope(path, config, client_process, read, errors):
    launch = read(path/'client-launch.json')
    window = read(path/'measurement-window.json')
    expected_label = '4.0.0' if config.get('product_contract') == 'v4.0.0' else 'driver'
    repeated = config.get('transfer_profile') == 'STANDARD'
    volume, rate = (2147483648, 67108864) if repeated else (67108864, 8388608)
    preset = config.get('workload_preset')
    if preset is not None:
        from pb_workload import valid_workload
        if (not valid_workload(preset) or config.get('product_contract', 'driver') != 'driver' or repeated or
                config.get('version_transfer_stage') or config.get('legacy_transfer_directory')):
            errors.append('Data-only workload preset differs')
        else:
            volume, rate = preset['transfer_bytes'], preset['rate_limit_bytes_per_s']
    if (config.get('transfer_only') is not True or config.get('tcp_shutdown_policy') != 'data-transfer-only-v1' or
        config.get('shutdown_mode') != 'rude' or config.get('console_verbosity') != 1 or
        config.get('product_label') != expected_label or config.get('diagnostic_only') or
        config.get('tcp_fixture_revision') or config.get('close_metadata_capture') or
        (config['transfer_bytes'], config['rate_limit_bytes_per_s'], config['connections'], config['buffer_bytes'], config['verify']) !=
        (volume, rate, 1, 65536, 'data') or
        (repeated and config.get('version_transfer_stage') !=
            ('data-transfer-repeat-legacy-v1' if expected_label == '4.0.0' else 'data-transfer-repeat-v1'))):
        errors.append('Data-only transfer policy/traffic scope differs')
    arguments = launch['expected_arguments']
    expected = {name: [a.split(':', 1)[1] for a in arguments if a.lower().startswith('-'+name+':')]
                for name in ('shutdown', 'consoleverbosity', 'transfer', 'ratelimit', 'verify')}
    observed = {name: re.findall(r'(?:^|\s)-'+name+r':([^\s"]+)', launch['observed_command_line'], re.I)
                for name in expected}
    values = dict(shutdown=['rude'], consoleverbosity=['1'], transfer=[str(volume)],
                  ratelimit=[str(rate)], verify=['data'])
    if (expected != values or observed != values or launch['pid'] != client_process['pid'] or
        not window['start_qpc_ms'] <= launch['capture_qpc_ms'] <= window['end_qpc_ms'] or
        any(str(Path(launch[k]).resolve()).casefold() != str(Path(client_process['actual_path']).resolve()).casefold()
            for k in ('expected_executable', 'observed_executable'))):
        errors.append('Data-only native live launch/options not confirmed')
    if config.get('product_contract') == 'v4.0.0':
        context = read(path/'version-context.json')
        if (not context.get('transfer_only') or context.get('tcp_shutdown_policy') != 'data-transfer-only-v1' or
            config.get('legacy_transfer_stage') != ('transfer_data_standard_v1' if repeated else 'transfer_data_smoke_v1')):
            errors.append('4.0.0 data-only stage/context differs')


def data_scope_details(label, repeated=False):
    result = dict(transfer_only=True, readiness_only=not repeated, product_label=label,
                  tcp_shutdown_policy='data-transfer-only-v1', normal_tcp_close_verified=False,
                  normal_tcp_close_observed_in_this_series=False)
    if label == '4.0.0':
        result['known_problems'] = [dict(code='LEGACY_TCP_GRACEFUL_CLOSE_RESET',
            observed_in_this_series=False, observation='PREVIOUS_CONTROLLED_RUN',
            title_ru='Сброс при штатном закрытии TCP — 4.0.0',
            title_en='Reset during normal TCP close — 4.0.0',
            message_ru='Ранее в 4.0.0 подтверждён сброс при штатном закрытии TCP. Этот профиль проверяет передачу данных и не подтверждает исправление закрытия.',
            message_en='A normal TCP close reset was previously confirmed in 4.0.0. This profile checks data transfer and does not verify a close fix.')]
    else:
        result['known_problems'] = []
    return result
