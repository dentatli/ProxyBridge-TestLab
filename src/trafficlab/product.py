"""Owned console-host lifecycle with bounded capture and retained child identity."""
from __future__ import annotations

import ctypes
import hashlib
import os
import re
import subprocess
import threading
import time
from typing import Any

from trafficlab.resources import process_sample

ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b[@-_]")
CONNECTION = re.compile(r"(?P<process>\S+).*?\((?:PID:)?\s*(?P<pid>\d+)\).*?->.*?via\s+(?P<route>Direct|Proxy|Blocked)", re.I)


class Product:
    def __init__(self, binding: dict[str, Any], profile: str) -> None:
        self.binding = binding
        self.profile = profile
        self.process: subprocess.Popen[bytes] | None = None
        self.pid: int | None = None
        self.handle = None
        self.ready = threading.Event()
        self.identity = threading.Event()
        self.lock = threading.Lock()
        self.tail = ""
        self.digest = hashlib.sha256()
        self.output_bytes = 0
        self.route_events = {"DIRECT": 0, "PROXY": 0, "BLOCKED": 0}
        self.read_errors = 0
        self.identity_error = False
        self.threads: list[threading.Thread] = []
        self.evidence: dict[str, Any] = {"ready": False, "cleanup_verified": False, "forced_stop": False}

    def capture(self, stream: Any, identity_stream: bool) -> None:
        pending = ""
        try:
            while True:
                block = stream.read(4096)
                if not block:
                    break
                text = block.decode("utf-8", errors="replace")
                with self.lock:
                    self.digest.update(block)
                    self.output_bytes += len(block)
                    self.tail = (self.tail + text)[-1048576:]
                    clean = ANSI.sub("", self.tail[-65536:])
                    if "ProxyBridge is running. Press Ctrl+C to stop." in clean:
                        self.ready.set()
                pending = (pending + text)[-65536:]
                lines = pending.split("\n")
                pending = lines.pop()
                for line in lines:
                    line = ANSI.sub("", line).strip()
                    if identity_stream and not self.identity.is_set():
                        match = re.fullmatch(r"PB_CONSOLE_HOST_PID=(\d+)", line)
                        if match:
                            self.pid = int(match[1])
                            self.identity.set()
                        else:
                            self.identity_error = True
                            self.identity.set()
                    event = CONNECTION.search(line)
                    if event and int(event["pid"]) == os.getpid():
                        with self.lock:
                            self.route_events[event["route"].upper()] += 1
        except (OSError, ValueError):
            self.read_errors += 1

    def __enter__(self) -> "Product":
        if os.name != "nt":
            raise ValueError("TRAFFIC_PRODUCT_REQUIRES_WINDOWS")
        try:
            self.process = subprocess.Popen([self.binding["console_host"], "--identity-ack", "--terminal", "5000",
                self.binding["cli"], "--profile", self.profile, "--verbose", "3"], stdin=subprocess.PIPE,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0, creationflags=subprocess.CREATE_NO_WINDOW)
            for stream, identity_stream in ((self.process.stdout, False), (self.process.stderr, True)):
                thread = threading.Thread(target=self.capture, args=(stream, identity_stream), daemon=True)
                self.threads.append(thread)
                thread.start()
            if not self.identity.wait(5) or self.identity_error or self.pid is None:
                raise ValueError("TRAFFIC_CLI_IDENTITY_FAILED")
            sample = process_sample(self.pid, self.binding["cli"])
            if not sample["available"]:
                raise ValueError("TRAFFIC_CLI_PATH_MISMATCH")
            from ctypes import wintypes as w
            self.kernel = ctypes.WinDLL("kernel32", use_last_error=True)
            self.kernel.OpenProcess.argtypes = [w.DWORD, w.BOOL, w.DWORD]
            self.kernel.OpenProcess.restype = w.HANDLE
            self.kernel.GetExitCodeProcess.argtypes = [w.HANDLE, ctypes.POINTER(w.DWORD)]
            self.kernel.GetExitCodeProcess.restype = w.BOOL
            self.kernel.CloseHandle.argtypes = [w.HANDLE]
            self.kernel.CloseHandle.restype = w.BOOL
            self.handle = self.kernel.OpenProcess(0x1000 | 0x100000, False, self.pid)
            if not self.handle:
                raise ValueError("TRAFFIC_CLI_HANDLE_FAILED")
            self.evidence.update(pid=self.pid, identity_start=sample["identity_start"], path_verified=True)
            self.process.stdin.write(b"READY\n")
            self.process.stdin.flush()
            if not self.ready.wait(15) or self.process.poll() is not None:
                raise ValueError("TRAFFIC_CLI_READINESS_FAILED")
            self.evidence["ready"] = True
            return self
        except BaseException:
            self.close()
            raise

    def close(self) -> None:
        if self.process is None:
            return
        if self.process.poll() is None:
            try:
                self.process.stdin.write(b"STOP\n")
                self.process.stdin.flush()
                self.process.wait(timeout=11)
            except (OSError, subprocess.TimeoutExpired):
                self.evidence["forced_stop"] = True
                self.process.kill()  # Closing this owned console host terminates only its job children.
                self.process.wait(timeout=5)
        for thread in self.threads:
            thread.join(timeout=2)
        exit_code = None
        if self.handle:
            from ctypes import wintypes as w
            result = w.DWORD()
            if self.kernel.GetExitCodeProcess(self.handle, ctypes.byref(result)):
                exit_code = result.value
            self.kernel.CloseHandle(self.handle)
            self.handle = None
        with self.lock:
            self.evidence.update(host_exit_code=self.process.returncode, child_exit_code=exit_code,
                cleanup_verified=self.process.returncode == 10 and exit_code == 0 and not self.evidence["forced_stop"],
                output_bytes=self.output_bytes, output_capture_sha256=self.digest.hexdigest(),
                capture_scope="bounded-tail-and-streaming-route-event-counts", route_events=dict(self.route_events),
                capture_complete=self.read_errors == 0 and all(not thread.is_alive() for thread in self.threads))
        for stream in (self.process.stdin, self.process.stdout, self.process.stderr):
            stream.close()
        self.process = None

    def __exit__(self, *_args: Any) -> None:
        self.close()
