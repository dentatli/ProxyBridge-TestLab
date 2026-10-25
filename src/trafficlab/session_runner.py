"""Local queue: one native Core host, acknowledged rule changes, final OFF once."""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import platform
import time
from pathlib import Path
from typing import Any

from trafficlab.core_session import CoreSession
from trafficlab.metrics import summary
from trafficlab.runner import idle, ownership, validate_route
from trafficlab.schedule import OriginMetricsChannel, atomic, origin_metrics, run
from trafficlab.worker import cancelled
from trafficlab.wfp_device import device
from trafficlab.udp_capacity import CAPACITY_ERROR, capacity_candidate, run_capacity_control

MODEL = 'persistent-core-session-v1'


def immutable(binding: dict[str, Any]) -> None:
    for name, expected in binding['source_hashes'].items():
        path = Path(name)
        if path.is_symlink() or hashlib.sha256(path.read_bytes()).hexdigest().lower() != expected.lower():
            raise ValueError('TRAFFIC_IMMUTABLE_FILE_CHANGED')


def isolation(binding: dict[str, Any], session: CoreSession, job: dict[str, Any]) -> dict[str, Any]:
    state = session.disable()
    immutable(binding)
    deadline = time.monotonic() + 3
    while True:
        origin = origin_metrics(job)
        if origin.get('identity', {}).get('verified') is not True:
            raise ValueError('TRAFFIC_REMOTE_ARTIFACT_IDENTITY_CHANGED')
        from trafficlab.native_engine import worker_state
        native_worker = worker_state(job)
        # An idle SOCKS UDP association may live for the queue. It is not a workload.
        # All TCP sessions and origin workloads must nevertheless be absent.
        if (type(origin.get('runtime_connections')) is int and origin['runtime_connections'] == 0 and
                type(origin.get('proxy_tcp_connections')) is int and origin['proxy_tcp_connections'] == 0 and
                (native_worker is None or native_worker['worker_jobs_active'] == 0)):
            return {**state, 'verified': True, 'origin_identity_verified': True, 'origin_idle_verified': True,
                    'native_worker_idle_verified': native_worker is not None,
                    'proxy_udp_associations': origin.get('proxy_udp_associations'), 'scope': 'rules-disabled-and-signed-idle; Core-remains-running'}
        if time.monotonic() >= deadline:
            raise ValueError('TRAFFIC_SESSION_ORIGIN_NOT_IDLE')
        time.sleep(0.1)


def job_for(binding: dict[str, Any], case: dict[str, Any]) -> dict[str, Any]:
    job = {**binding, **case, 'run_id': binding['id'] + '.' + case['case_id']}
    job.pop('cases', None)
    return job


def measurement(report: dict[str, Any], raw: Path, mode: str, lifecycle: dict[str, Any], specification: dict[str, Any]) -> dict[str, Any]:
    route = validate_route(report, mode == 'SOCKS5') and (mode == 'OFF' or lifecycle['route_events'].get('PROXY' if mode == 'SOCKS5' else 'DIRECT', 0) > 0)
    losses = ([stage.get('max_udp_flow_loss_fraction') for stage in report['stages']] if report.get('compact_stages') else
              [flow.get('loss_fraction') for stage in report['stages'] for row in stage['results'] if row['task'] == 'udp' for flow in row['flows']])
    losses = [value for value in losses if type(value) in (int, float)]
    loss_ok = all(value <= 0.01 for value in losses)
    loss_state = 'MEASURED' if losses else 'NOT_MEASURED' if report.get('udp_expected') else 'NOT_APPLICABLE'
    capture_ok = mode == 'OFF' or lifecycle.get('capture_live_verified') is True
    errors = [code for failed, code in ((not report['complete'], 'TRAFFIC_TRANSPORT_INCOMPLETE'),
        (not route, 'TRAFFIC_ROUTE_UNVERIFIED'), (not loss_ok, 'TRAFFIC_UDP_LOSS_THRESHOLD_EXCEEDED'),
        (not capture_ok, 'TRAFFIC_CLI_CAPTURE_INCOMPLETE')) if failed]
    return {'mode': mode, 'complete': not errors, 'raw_evidence_sha256': hashlib.sha256(raw.read_bytes()).hexdigest(),
            'transport_complete': report['complete'], 'route_verified': route, 'lifecycle': lifecycle,
            'loss_threshold_fraction': 0.01 if loss_state != 'NOT_APPLICABLE' else None,
            'loss_threshold_met': loss_ok if losses else None, 'loss_evidence_state': loss_state,
            'loss_scope': ('application-replies' if specification['recipe'] == 'application' else 'udp-responses') if report.get('udp_expected') else None,
            'errors': errors, **summary(report)}


def execute(binding_path: str, directory: Path) -> int:
    binding = json.loads(Path(binding_path).read_text(encoding='utf-8-sig'))
    attempt_path = directory / 'attempt.json'
    original = json.loads(attempt_path.read_text(encoding='utf-8-sig'))
    results: list[dict[str, Any]] = []
    recovery: list[dict[str, Any]] = []
    session = None
    channel = None
    cleanup = False
    error = ''
    off_before = None
    baseline: dict[str, dict[str, Any]] = {}
    queue_evidence: dict[str, Any] = {'execution_model': MODEL, 'start_count': 0, 'stop_count': 0}
    base_conditions = {'build_sha256': binding['build_sha256'], 'remote_bundle_sha256': binding['remote_bundle_sha256'],
        'local_runtime_sha256': binding['local_runtime_sha256'], 'method': 'controlled-traffic-core-session-v1',
        'transport_engine': binding.get('transport_engine', 'python-transport-v1'),
        'execution_model': MODEL, 'resource_product_scope': 'selected-Core-in-TestLab-native-host; excludes-official-CLI',
        'queue_profile_sha256': hashlib.sha256(json.dumps(binding['cases'], sort_keys=True, separators=(',', ':')).encode()).hexdigest(),
        'session_state': 'retained-between-cases', 'off_control_scope': 'queue-before-Core-Start',
        'host_binding': hashlib.sha256(binding['host'].encode()).hexdigest(), 'python_version': platform.python_version(),
        'windows_version': platform.version(), 'logical_cpus': os.cpu_count(), 'windows_node_binding': hashlib.sha256(platform.node().encode()).hexdigest(),
        'cpu_model': os.environ.get('PROCESSOR_IDENTIFIER', 'unknown'), 'runtime_mode': 'local', 'origin_scope': 'same-Windows-host-loopback',
        'product_contract': binding['product_contract'], 'adapter_id': binding['adapter_id'], 'product_version': binding['product_version']}
    progress = str(directory / 'progress.json')
    queue_view: dict[str, Any] = {'run_id': binding['id'], 'phase': 'PREPARING',
        'environment_ready': False, 'baseline_ready': False, 'client_ready': False, 'current_case_id': None}

    def publish_queue(phase: str, **updates: Any) -> None:
        # Presentation only. A UI snapshot must never change execution or evidence gates.
        queue_view.update(phase=phase, **updates)
        queue_view['results'] = [{key: row.get(key) for key in
            ('case_id', 'duration', 'load', 'complete', 'workload_complete', 'cancelled', 'skipped', 'case_isolation_verified')} for row in results
            if row.get('elapsed_seconds') is not None or row.get('skipped')]
        try:
            atomic(str(directory / 'queue-state.json'), queue_view)
        except OSError:
            pass

    publish_queue('PREPARING')
    try:
        if binding.get('runtime_mode') != 'local' or binding.get('execution_model') != MODEL:
            raise ValueError('TRAFFIC_SESSION_LOCAL_ONLY')
        immutable(binding)
        off_before = idle(binding_path, binding)
        publish_queue('BASELINE', environment_ready=True)
        catalog = json.loads((Path(binding['root']) / 'config/traffic-workloads.json').read_text(encoding='utf-8-sig'))
        short_catalog = {**catalog, 'duration_seconds': {**catalog['duration_seconds'], 'SHORT': 0.2}}
        if cancelled(binding):
            return 1
        # True OFF is measured before Start, once. Rules-disabled is always UNRULED.
        control_job = {**binding, 'run_id': binding['id'] + '.baseline', 'case_id': 'tcp-rtt', 'duration': 'SHORT',
                       'load': 'LOW', 'warmup_count': 0, 'expected_proxy': False}
        raw = directory / 'queue.OFF-control.raw.json'
        observed = run(control_job, short_catalog, str(raw), progress)
        control_row = {'mode': 'OFF', 'workload_scope': 'tcp-echo', 'complete': observed['complete'],
                       'route_verified': validate_route(observed, False), 'scope': 'queue-before-Core-Start',
                       'raw_evidence_sha256': hashlib.sha256(raw.read_bytes()).hexdigest(), **summary(observed)}
        queue_evidence['off_control'] = control_row
        if not control_row['route_verified']:
            raise ValueError('TRAFFIC_OFF_CONTROL_FAILED')
        identity = observed['stages'][0]['origin']['identity']['application']
        base_conditions.update(application_tls_sha256=identity['tls_certificate_sha256'])
        if identity.get('ssh_host_key_sha256'):
            base_conditions['application_ssh_sha256'] = identity['ssh_host_key_sha256']
        base_conditions['origin_logical_cpus'] = observed['stages'][0]['origin']['cpu_count']
        base_conditions['origin_physical_memory_bytes'] = observed['stages'][0]['origin']['system_resources'].get('physical_total_bytes')
        from trafficlab.resources import system_sample
        base_conditions['windows_physical_memory_bytes'] = system_sample().get('physical_total_bytes')
        # OFF part of three-modes uses its own selected duration/load before Start.
        for case in binding['cases']:
            if case['case_id'] == 'three-modes':
                job = {**job_for(binding, case), 'case_id': 'tcp-rtt', 'expected_proxy': False}
                job.update({key: base_conditions[key] for key in ('application_tls_sha256', 'application_ssh_sha256') if key in base_conditions})
                raw = directory / 'three-modes.OFF.raw.json'
                measured = run(job, catalog, str(raw), progress)
                baseline['three-modes'] = measurement(measured, raw, 'OFF', {'product_started': False, 'cleanup_verified': True}, {'recipe': 'echo'})
        if cancelled(binding):
            return 1
        publish_queue('CLIENT_STARTING', baseline_ready=True)
        channel_job = {**binding, 'run_id': binding['id'] + '.queue', **{key: base_conditions[key] for key in ('application_tls_sha256', 'application_ssh_sha256') if key in base_conditions}}
        channel = OriginMetricsChannel(channel_job)
        channel.__enter__()
        channel_job['_origin_metrics_channel'] = channel
        immutable(binding)
        queue_evidence['device_start'] = device(binding_path, binding, 'Enable')
        session = CoreSession(binding, directory)
        session.__enter__()
        queue_evidence['start_count'] = 1
        queue_evidence['pid'] = session.pid
        publish_queue('TESTING')
        for case in binding['cases']:
            if cancelled(binding):
                break
            publish_queue('TESTING', current_case_id=case['case_id'])
            started = time.monotonic()
            row: dict[str, Any] = {'case_id': case['case_id'], 'duration': case['duration'], 'load': case['load'],
                'complete': False, 'cancelled': False, 'cleanup_verified': False, 'cleanup_scope': 'queue-final-off',
                'product_route_confirmed': False, 'measurements': [], 'controls': [control_row], 'errors': [], 'conditions': dict(base_conditions)}
            results.append(row)
            row['conditions']['case_position_in_queue'] = len(results)
            job = {**job_for(binding, case), **{key: base_conditions[key] for key in ('application_tls_sha256', 'application_ssh_sha256') if key in base_conditions},
                   '_origin_metrics_channel': channel, 'resource_processes': {'product_cli': {'pid': session.pid, 'path': binding['core_host']}}}
            specification = next(value for value in catalog['cases'] if value['id'] == case['case_id'])
            try:
                row['isolation_before'] = isolation(binding, session, {**channel_job, 'run_id': job['run_id']})
                before = dict(session.route_events)
                control = {**job, 'case_id': 'tcp-rtt', 'duration': 'SHORT', 'load': 'LOW', 'warmup_count': 0,
                           'run_id': job['run_id'] + '.unruled', 'expected_proxy': False}
                raw = directory / (case['case_id'] + '.UNRULED-control.raw.json')
                observed = run(control, short_catalog, str(raw), progress)
                life = session.snapshot(before)
                row['unruled_lifecycle'] = life
                row['controls'].append({'mode': 'UNRULED', 'workload_scope': 'tcp-echo', 'complete': observed['complete'],
                    'route_verified': validate_route(observed, False) and life['route_events']['DIRECT'] > 0,
                    'lifecycle': life, **summary(observed)})
                if not row['controls'][-1]['route_verified']:
                    row['errors'].append('TRAFFIC_UNRULED_CONTROL_FAILED')
                else:
                    publish_queue('TESTING', client_ready=True)
                    if case['case_id'] == 'three-modes':
                        row['measurements'].append(baseline['three-modes'])
                    from trafficlab.application_wire import APPLICATION_PORTS
                    port = APPLICATION_PORTS[specification['application']] if specification.get('application') else binding['port']
                    modes = ('UNRULED', 'SOCKS5') if case['case_id'] == 'three-modes' else ('SOCKS5',)
                    for mode in modes:
                        if cancelled(binding):
                            break
                        if mode == 'SOCKS5':
                            state = session.enable(port)
                        else:
                            state = session.disable()
                        before = dict(session.route_events)
                        raw = directory / (case['case_id'] + '.' + mode + '.raw.json')
                        measured_job = {**job, 'run_id': job['run_id'] + '.' + mode, 'expected_proxy': mode == 'SOCKS5',
                                        'case_id': 'tcp-rtt' if case['case_id'] == 'three-modes' else case['case_id']}
                        measured = run(measured_job, catalog, str(raw), progress)
                        life = session.snapshot(before)
                        item = measurement(measured, raw, mode, life, specification)
                        item['rule_change'] = state
                        row['measurements'].append(item)
                        row['errors'].extend(code for code in item['errors'] if code not in row['errors'])
                        candidate = capacity_candidate(measured_job, catalog, measured) if mode == 'SOCKS5' else None
                        if candidate is not None and not cancelled(binding):
                            safe = isolation(binding, session, {**channel_job, 'run_id':job['run_id']})
                            control = run_capacity_control(measured_job, catalog, candidate,
                                str(directory / (case['case_id'] + '.LAB-CAPACITY-control.raw.json')), progress)
                            control['isolation_before'] = safe
                            row['controls'].append(control)
                            if control['laboratory_limited']:
                                row['environment_limited'] = True
                                row['errors'].append(CAPACITY_ERROR)
                                item['errors'].append(CAPACITY_ERROR)
                                item['measurement_state'] = 'LABORATORY_LIMITED'
                                item['product_result_confirmed'] = False
                row['case_isolation'] = isolation(binding, session, {**channel_job, 'run_id': job['run_id']})
                row['case_isolation_verified'] = True
                expected = 3 if case['case_id'] == 'three-modes' else 1
                row['complete'] = not row['errors'] and len(row['measurements']) == expected and all(item['complete'] for item in row['measurements'])
                row['product_route_confirmed'] = any(item['mode'] == 'SOCKS5' and item['route_verified'] for item in row['measurements'])
                if not row['complete'] and not cancelled(binding) and len(results) < len(binding['cases']):
                    recovery.append({'case_id': case['case_id'], 'safe_to_continue': True, 'reason': 'TRAFFIC_SESSION_ISOLATION_VERIFIED',
                                     'isolation': row['case_isolation'], 'fresh_off_verified': None})
            except Exception as exception:
                row['errors'].append(str(exception) if isinstance(exception, ValueError) and str(exception).startswith('TRAFFIC_') else 'TRAFFIC_SESSION_CASE_FAILED')
                row['exception_type'] = type(exception).__name__
                raise
            finally:
                row['cancelled'] = cancelled(binding)
                row['complete'] = row['complete'] and not row['cancelled']
                row['elapsed_seconds'] = time.monotonic() - started
                atomic(str(directory / (case['case_id'] + '.report.json')), row)
                publish_queue('TESTING', current_case_id=None)
            if not row['complete'] and not binding.get('continue_after_failure', True):
                break
    except Exception as exception:
        error = str(exception) if isinstance(exception, ValueError) and str(exception).startswith('TRAFFIC_') else 'TRAFFIC_SESSION_CONTROLLER_FAILED'
        queue_evidence['exception_type'] = type(exception).__name__
        queue_evidence['exception_detail'] = str(exception)[:400]
    finally:
        publish_queue('CLEANUP', current_case_id=None, interrupted=bool(error) or cancelled(binding),
                      preparation_failed=bool(error) and not queue_view['client_ready'], cancelled=cancelled(binding))
        if session is not None:
            session.close()
            queue_evidence['stop_count'] = int(queue_evidence['start_count'] > 0)
            queue_evidence['lifecycle'] = session.evidence
            ownership(binding_path, binding, session)
        if channel is not None:
            channel.__exit__(None, None, None)
        try:
            exited = session is None or session.evidence.get('exit_verified') is True
            if exited:
                queue_evidence['device_restore'] = device(binding_path, binding, 'Disable')
            final_off = idle(binding_path, binding, session is not None and exited)
            cleanup = exited and final_off['off_verified'] is True
            queue_evidence['off_after'] = final_off
        except Exception as exception:
            error = error or 'TRAFFIC_CLEANUP_OR_REBOOT_REQUIRED'
            queue_evidence['cleanup_exception_type'] = type(exception).__name__
            queue_evidence['cleanup_error'] = (str(exception) if isinstance(exception, ValueError)
                                               and str(exception).startswith('TRAFFIC_') else 'TRAFFIC_CLEANUP_CHECK_FAILED')
        graceful = session is None or session.evidence.get('cleanup_verified') is True
        capture_ok = session is None or (session.evidence.get('capture_complete') is True and session.evidence.get('output_retention_ok') is True)
        if not graceful:
            error = error or 'TRAFFIC_CONTROLLED_SHUTDOWN_FAILED'
        if not capture_ok:
            error = error or 'TRAFFIC_CLI_CAPTURE_INCOMPLETE'
        immutable_ok = True
        try:
            immutable(binding)
        except (OSError, ValueError):
            immutable_ok = False
            error = error or 'TRAFFIC_IMMUTABLE_FILE_CHANGED'
        stopped = cancelled(binding)
        for case in binding['cases']:
            if not any(row['case_id'] == case['case_id'] for row in results):
                results.append({**case, 'complete': False, 'cancelled': stopped, 'skipped': True,
                    'errors': ['SKIPPED_AFTER_CANCEL' if stopped else 'SKIPPED_AFTER_FAILURE'], 'measurements': []})
        for row in results:
            # Preserve the case outcome; final OFF remains a separate mandatory gate.
            row['workload_complete'] = row['complete']
            row['cleanup_verified'] = cleanup
            row['cleanup_scope'] = 'queue-final-off'
            row['complete'] = row['complete'] and cleanup and graceful and capture_ok and immutable_ok
            if not graceful and not row.get('skipped'):
                row['errors'].append('TRAFFIC_CONTROLLED_SHUTDOWN_FAILED')
            if not capture_ok and not row.get('skipped'):
                row['errors'].append('TRAFFIC_CLI_CAPTURE_INCOMPLETE')
            if not immutable_ok and not row.get('skipped'):
                row['errors'].append('TRAFFIC_IMMUTABLE_FILE_CHANGED')
            atomic(str(directory / (row['case_id'] + '.report.json')), row)
        complete = not stopped and not error and all(row['complete'] for row in results) and cleanup
        final = {**original, 'state': 'CANCELLED' if stopped else 'COMPLETE' if complete else 'FAILED', 'complete': complete,
                 'cleanup_verified': cleanup, 'completed_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                 'error': error or ('TRAFFIC_CASE_FAILED' if not complete and not stopped else ''), 'results': results,
                 'execution_model': MODEL, 'queue_session': queue_evidence, 'off_before': off_before,
                 'continue_after_failure': binding.get('continue_after_failure', True), 'recovery_checks': recovery}
        atomic(str(attempt_path), final)
        publish_queue('FINISHED', product_cleanup_verified=cleanup, error=error, cancelled=stopped)
    return 0 if complete else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--binding', required=True)
    parser.add_argument('--output-root', required=True)
    args = parser.parse_args()
    return execute(args.binding, Path(args.output_root))


if __name__ == '__main__':
    raise SystemExit(main())
