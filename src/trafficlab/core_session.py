"""One isolated, owned Core API host for a local queue; rule acknowledgements are barriers."""
from __future__ import annotations

import ctypes
import hashlib
import io
import os
import queue
import subprocess
import threading
import time
from pathlib import Path
from typing import Any

from trafficlab.product import Product
from trafficlab.protocol import mac
from trafficlab.resources import process_sample
from trafficlab.rule_scope import port_filter


class CoreSession(Product):
    def __init__(self, binding: dict[str, Any], directory: Path) -> None:
        super().__init__(binding, str(directory / 'session-private'), directory / 'session.console.jsonl')
        self.responses: queue.Queue[list[str]] = queue.Queue()
        self.sequence = 0
        self.command_lock = threading.Lock()
        self.configuration: tuple[int, ...] | None = None
        self.last_state: dict[str, Any] = {}

    def finish_output(self) -> None:
        super().finish_output()
        self.evidence.pop('startup_profile', None)  # CLI text parsing does not apply to API acknowledgements.
        self.evidence['last_rule_state'] = dict(self.last_state)

    def capture(self, stream: Any, identity_stream: bool) -> None:
        try:
            while block := stream.readline(32769):
                if len(block) > 32768 or not block.endswith(b'\n'):
                    raise ValueError('TRAFFIC_SESSION_FRAME_INVALID')
                # Reuse full-stream hash and bounded durable capture; protocol has no credentials.
                super().capture(io.BytesIO(block), identity_stream)
                if not identity_stream and block.startswith(b'PB_ACK\t'):
                    self.responses.put(block.decode('ascii').strip().split('\t'))
        except (OSError, ValueError):
            self.read_errors += 1

    def command(self, operation: str, *fields: str) -> dict[str, Any]:
        with self.command_lock:
            if self.process is None or self.process.poll() is not None or self.read_errors:
                raise ValueError('TRAFFIC_SESSION_LOST')
            self.sequence += 1
            line = '\t'.join(('PB_CMD', str(self.sequence), operation, *fields)) + '\n'
            if len(line.encode('ascii')) > 8000:
                raise ValueError('TRAFFIC_SESSION_COMMAND_INVALID')
            self.process.stdin.write(line.encode('ascii'))
            self.process.stdin.flush()
            try:
                row = self.responses.get(timeout=20)
            except queue.Empty as error:
                raise ValueError('TRAFFIC_SESSION_ACK_TIMEOUT') from error
            native = bool(self.binding.get('native_worker_executable'))
            if len(row) != (10 if native else 9) or row[1] != str(self.sequence) or row[2] != '1':
                raise ValueError('TRAFFIC_SESSION_ACK_INVALID')
            config, rule, enabled, direct, proxy, blocked = map(int, row[3:9])
            native_rule = int(row[9]) if native else None
            if config < 1 or rule < 1 or enabled not in (0, 1):
                raise ValueError('TRAFFIC_SESSION_ACK_INVALID')
            identity = (config, rule, native_rule) if native else (config, rule)
            if native and (native_rule < 1 or native_rule == rule):
                raise ValueError('TRAFFIC_SESSION_ACK_INVALID')
            if self.configuration is not None and self.configuration != identity:
                raise ValueError('TRAFFIC_SESSION_IDENTITY_CHANGED')
            self.configuration = identity
            sample = process_sample(self.pid, self.binding['core_host'])
            if not sample['available'] or sample['identity_start'] != self.evidence['identity_start']:
                raise ValueError('TRAFFIC_SESSION_IDENTITY_CHANGED')
            self.route_events = {'DIRECT': direct, 'PROXY': proxy, 'BLOCKED': blocked}
            self.last_state = {'command_sequence': self.sequence, 'operation': operation, 'ack_verified': True,
                               'pid': self.pid, 'config_id': config, 'rule_id': rule, 'rule_enabled': bool(enabled),
                               'route_events': dict(self.route_events), 'path_verified': True}
            if native:
                self.last_state['native_rule_id'] = native_rule
            return dict(self.last_state)

    @staticmethod
    def hex(value: Any) -> str:
        return str(value).encode('utf-8').hex()

    def __enter__(self) -> CoreSession:
        binding = self.binding
        if binding.get('runtime_mode') != 'local' or binding.get('execution_model') != 'persistent-core-session-v1':
            raise ValueError('TRAFFIC_SESSION_LOCAL_ONLY')
        adapter = 'wfp' if binding.get('product_contract') == 'driver' else 'windivert43'
        if adapter == 'windivert43' and binding.get('product_version') != '4.3.0':
            raise ValueError('TRAFFIC_SESSION_VERSION_UNSUPPORTED')
        try:
            self.output_file = self.output_path.open('xb')
            self.process = subprocess.Popen([binding['console_host'], '--identity-ack', '--control-input', '5000',
                binding['core_host'], binding['core'], adapter], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, bufsize=0, creationflags=subprocess.CREATE_NO_WINDOW)
            for stream, identity in ((self.process.stdout, False), (self.process.stderr, True)):
                thread = threading.Thread(target=self.capture, args=(stream, identity), daemon=True)
                self.threads.append(thread)
                thread.start()
            if not self.identity.wait(5) or self.identity_error or self.pid is None:
                raise ValueError('TRAFFIC_SESSION_IDENTITY_FAILED')
            sample = process_sample(self.pid, binding['core_host'])
            if not sample['available']:
                raise ValueError('TRAFFIC_SESSION_PATH_MISMATCH')
            from ctypes import wintypes as w
            self.kernel = ctypes.WinDLL('kernel32', use_last_error=True)
            self.kernel.OpenProcess.argtypes = [w.DWORD, w.BOOL, w.DWORD]
            self.kernel.OpenProcess.restype = w.HANDLE
            self.kernel.GetExitCodeProcess.argtypes = [w.HANDLE, ctypes.POINTER(w.DWORD)]
            self.kernel.GetExitCodeProcess.restype = w.BOOL
            self.kernel.CloseHandle.argtypes = [w.HANDLE]
            self.kernel.CloseHandle.restype = w.BOOL
            self.handle = self.kernel.OpenProcess(0x1000 | 0x100000, False, self.pid)
            if not self.handle:
                raise ValueError('TRAFFIC_SESSION_HANDLE_FAILED')
            self.evidence.update(pid=self.pid, identity_start=sample['identity_start'], path_verified=True,
                                 execution_model='persistent-core-session-v1', core_sha256=hashlib.sha256(Path(binding['core']).read_bytes()).hexdigest())
            self.process.stdin.write(b'READY\n')
            self.process.stdin.flush()
            native = ()
            if binding.get('native_worker_executable'):
                from trafficlab.native_engine import worker_state
                worker_state(binding)
                if Path(binding['native_worker_executable']).name != 'pb_testlab_worker.exe':
                    raise ValueError('TRAFFIC_NATIVE_WORKER_RULE_INVALID')
                native = (self.hex('pb_testlab_worker.exe'), self.hex(binding['native_worker_executable']), str(binding['native_worker_pid']))
            self.command('INIT', self.hex(binding['host']), str(binding['proxy_port']), self.hex(binding['id']),
                self.hex(mac(bytes.fromhex(binding['secret']), b'socks:', binding['id'].encode())),
                self.hex(Path(binding['python']).name), self.hex(binding['port']), str(os.getpid()), *native)
            self.evidence['ready'] = True
            self.evidence['proxy_configuration_verified'] = True
            return self
        except BaseException:
            self.close()
            raise

    def disable(self) -> dict[str, Any]:
        state = self.command('DISABLE')
        if state['rule_enabled']:
            raise ValueError('TRAFFIC_SESSION_RULE_DISABLE_FAILED')
        return state

    def enable(self, port: int | tuple[int, ...]) -> dict[str, Any]:
        ports = port_filter(port)
        state = self.command('RULE', self.hex(ports), '1')
        if not state['rule_enabled']:
            raise ValueError('TRAFFIC_SESSION_RULE_ENABLE_FAILED')
        state['target_ports'] = ports
        return state

    def snapshot(self, before: dict[str, int]) -> dict[str, Any]:
        state = self.command('SNAP')
        return {**state, 'ready': True, 'forced_stop': False, 'proxy_configuration_verified': True,
                'capture_live_verified': self.read_errors == 0 and not self.output_write_failed,
                'route_events': {key: value - before[key] for key, value in self.route_events.items()},
                'scope': 'selected-Core-in-TestLab-native-host; session-remains-running'}
