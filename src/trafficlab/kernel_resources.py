"""Owned, per-case kernel observer. Collection failure is unknown, never measured zero."""
from __future__ import annotations
import threading
from trafficlab.native_engine import request, worker_state


class KernelCapture:
    def __init__(self, job):
        self.job = job
        self.lock = threading.Lock()
        self.active = False
        self.poll_errors = 0
        self.failure = None
        self.result = {'available':False, 'error':'NOT_REQUESTED', 'cleanup_verified':True}

    def call(self, operation, **values):
        value = request(self.job['native_worker_port'], self.job['secret'],
                        {'operation':'kernel-'+operation, 'run_id':self.job['run_id'], **values}, timeout=15)
        if not isinstance(value, dict):
            raise ValueError('TRAFFIC_KERNEL_RESPONSE_INVALID')
        return value

    def start(self):
        if not (self.job.get('runtime_mode') == 'local' and self.job.get('native_worker_port') and
                self.job.get('expected_proxy') and self.job.get('driver') and self.job.get('collect_kernel_resources', True)):
            return
        if self.job.get('case_id') == 'soak':
            self.result['error'] = 'LONG_RUN_SCOPE_EXCLUDED'
            return
        try:
            self.result = self.call('start', driver=self.job['driver'], driver_sha256=self.job['driver_sha256'])
            self.active = self.result.get('available') is True
        except (OSError, ValueError, EOFError) as error:
            self.result = {'available':False, 'error':'KERNEL_START_'+type(error).__name__}
            self.close()  # A lost reply may still have created our session.

    def begin(self, index, phase):
        if self.active:
            try:
                self.call('begin', phase_id=str(index), phase=phase)
            except (OSError,ValueError,EOFError):
                self.failure = 'KERNEL_PHASE_BOUNDARY_UNVERIFIED'
                self.close()

    def end(self):
        if self.active:
            try:
                self.call('end')
            except (OSError,ValueError,EOFError):
                self.failure = 'KERNEL_PHASE_BOUNDARY_UNVERIFIED'
                self.close()

    def poll(self):
        with self.lock:
            if self.active:
                try:
                    value = self.call('poll')
                    if value.get('available') is not True:
                        self.poll_errors += 1
                except (OSError, ValueError, EOFError):
                    self.poll_errors += 1

    def close(self):
        with self.lock:
            if self.active:
                try:
                    self.result = self.call('stop')
                except (OSError, ValueError, EOFError):
                    self.result = {'available':False, 'error':'KERNEL_STOP_UNVERIFIED', 'cleanup_verified':False}
                self.active = False
            if self.result.get('cleanup_verified') is not True:
                state = worker_state(self.job)
                if state and state.get('kernel_session_active') is True:
                    self.result = self.call('stop')
                elif state and state.get('kernel_session_active') is False:
                    self.result['cleanup_verified'] = True
                if self.result.get('cleanup_verified') is not True:
                    raise ValueError('TRAFFIC_KERNEL_COLLECTOR_CLEANUP_FAILED')
            if self.failure:
                self.result['error'] = self.failure
                for phase in self.result.get('phases',[]):
                    phase['cpu_state'] = phase['pool_state'] = 'UNVERIFIED'
            self.result['poll_errors'] = self.poll_errors
            if self.poll_errors:
                for phase in self.result.get('phases', []):
                    phase['pool_state'] = 'UNVERIFIED'
            return self.result
