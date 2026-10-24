"""Process deadline for asynchronous SSH/SFTP, including library cancellation/close.

Thread timeouts cannot stop a stuck coroutine and ThreadPoolExecutor waits on
exit. Only this workload's owned subprocess is terminated; Core stays running.
"""
from __future__ import annotations
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any
from trafficlab.worker import cancelled

DEADLINE_GRACE = 15.0


def execute_bounded(job: dict[str, Any]) -> dict[str, Any]:
    if job.get('application') not in ('ssh', 'sftp'):
        raise ValueError('TRAFFIC_BOUNDED_WORKER_APPLICATION_INVALID')
    started = time.monotonic()
    budget = float(job['seconds']) + DEADLINE_GRACE
    resource = job.get('_worker_process', {})
    process = None

    def failure(code: str, was_cancelled: bool = False) -> dict[str, Any]:
        result = {'schema_version': 1, 'measurement_method': 'controlled-traffic-v1', 'run_id': job['run_id'],
            'task': job['task'], 'application': job['application'], 'complete': False, 'cancelled': was_cancelled,
            'errors': [code], 'flows': [], 'successful_tcp_flows': 0, 'tcp_origin_fingerprint': '0' * 64,
            'udp_origin_fingerprint': '0' * 64, 'tx_bytes': 0, 'rx_bytes': 0,
            'worker_results_available': False, 'byte_scope': 'confirmed-results-only; unavailable after forced stop',
            'requested_flow_count': job['connections'], 'worker_deadline_seconds': budget,
            'worker_exit_code': process.returncode if process is not None else None,
            'worker_pid': process.pid if process is not None else None,
            'elapsed_seconds': time.monotonic() - started, 'product_route_confirmed': False}
        if process is not None and os.fstat(stderr.fileno()).st_size:
            stderr.seek(0)
            log = Path(job['_worker_directory']) / f'worker-{process.pid}-stderr.log'
            log.write_bytes(stderr.read())
            result['worker_stderr_file'] = log.name
        return result

    if cancelled(job):
        return failure('TRAFFIC_SSH_WORKER_CANCELLED', True)
    with tempfile.TemporaryDirectory(prefix='worker-private-', dir=job['_worker_directory']) as directory:
        root = Path(directory)
        request, output = root / 'job-private.json', root / 'result.json'
        request.write_text(json.dumps({k: v for k, v in job.items() if not k.startswith('_')}), encoding='utf-8')
        # No credentials in arguments. The temporary directory inherits attempt ACLs.
        with (root / 'stderr.log').open('w+b') as stderr:
            process = subprocess.Popen([sys.executable, '-B', '-m', 'trafficlab.worker', '--job', str(request),
                '--output', str(output)], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=stderr,
                creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
            resource.update(pid=process.pid, path=sys.executable, finished=False)
            try:
                while process.poll() is None:
                    diagnostic_limit = os.fstat(stderr.fileno()).st_size > 1024 * 1024
                    if cancelled(job) or time.monotonic() - started >= budget or diagnostic_limit:
                        was_cancelled = cancelled(job)
                        process.kill()
                        process.wait(timeout=3)
                        code = ('TRAFFIC_SSH_WORKER_CANCELLED' if was_cancelled else
                                'TRAFFIC_SSH_WORKER_DIAGNOSTIC_LIMIT' if diagnostic_limit else 'TRAFFIC_SSH_WORKER_DEADLINE_EXCEEDED')
                        return failure(code, was_cancelled)
                    time.sleep(.05)
                if process.returncode not in (0, 1) or not output.is_file() or output.stat().st_size > 16 * 1024 * 1024:
                    return failure('TRAFFIC_SSH_WORKER_RESULT_UNAVAILABLE')
                try:
                    result = json.loads(output.read_text(encoding='utf-8'))
                except (ValueError, UnicodeError):
                    return failure('TRAFFIC_SSH_WORKER_RESULT_INVALID')
                if (not isinstance(result, dict) or result.get('run_id') != job['run_id'] or result.get('task') != job['task'] or
                    result.get('application') != job['application'] or type(result.get('complete')) is not bool or
                    (process.returncode == 0) != result['complete']):
                    return failure('TRAFFIC_SSH_WORKER_RESULT_INVALID')
                result['worker_deadline_seconds'] = budget
                result['worker_exit_code'] = process.returncode
                result['worker_resource_scope'] = 'isolated-SSH/SFTP-process'
                return result
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait(timeout=3)
                resource['finished'] = True
