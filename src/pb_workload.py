"""Exact, versioned constraints for new workload presets; old profiles stay separate."""
METHOD = 'controlled-workload-v1'


def expected_workload(duration, load):
    seconds, low_echoes, high_echoes = {
        'SHORT': (8, 128, 256), 'NORMAL': (32, 1500, 3000),
        'LONG': (120, 6000, 12000)
    }[duration]
    rate, pause = {'LOW': (8388608, 20), 'HIGH': (67108864, 10)}[load]
    return dict(method=METHOD, duration=duration, load=load, transfer_bytes=seconds*rate,
                rate_limit_bytes_per_s=rate, nominal_transfer_seconds=seconds,
                echo_count=low_echoes if load == 'LOW' else high_echoes,
                warmup_count=1000, message_bytes=512, pause_ms=pause,
                connections=1, native_timeout_ms=600000)


def valid_workload(value):
    try:
        return isinstance(value, dict) and value == expected_workload(value['duration'], value['load'])
    except (KeyError, TypeError):
        return False


def check_rtt_workload(config, errors):
    value = config.get('workload_preset')
    if not valid_workload(value) or any(config.get(key) != value[key]
            for key in ('echo_count', 'warmup_count', 'message_bytes', 'pause_ms', 'connections')):
        errors.append('RTT workload preset or measured parameters differ')
    if config.get('live_socket_observation_policy') != 'owned-socket-snapshot-before-measurement-v1':
        errors.append('Preset requires owned socket observation before measurement')
