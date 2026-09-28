from __future__ import annotations

import base64
import hashlib
import json
import os
import queue
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import Any

PLUGIN_ROOT = Path(__file__).resolve().parents[1]
if str(PLUGIN_ROOT) not in sys.path:
    sys.path.insert(0, str(PLUGIN_ROOT))

from model import WorkerContractError, WorkerPlan
from plugins.common import base_record, required_parameter, required_port, timestamp_utc


def _payload(plan: WorkerPlan) -> bytes:
    return f"process-termination|{plan.raw['run_id']}|{plan.raw['scenario_id']}|{plan.raw['attempt_id']}|{plan.raw['flow_id']}".encode("utf-8")


def _query_process_path(pid: int) -> str:
    if os.name != "nt":
        try:
            return str(Path(f"/proc/{pid}/exe").resolve())
        except OSError:
            return ""
    import ctypes
    from ctypes import wintypes

    process = ctypes.windll.kernel32.OpenProcess(0x1000, False, pid)
    if not process:
        return ""
    try:
        size = wintypes.DWORD(32768)
        buffer = ctypes.create_unicode_buffer(size.value)
        if not ctypes.windll.kernel32.QueryFullProcessImageNameW(process, 0, buffer, ctypes.byref(size)):
            return ""
        return buffer.value
    finally:
        ctypes.windll.kernel32.CloseHandle(process)


def _verified_child_path(process: subprocess.Popen[str], expected: Path, timeout_ms: int = 2000) -> tuple[str, int, int]:
    started = time.monotonic()
    attempts = 0
    actual = ""
    while int((time.monotonic() - started) * 1000) < timeout_ms and process.poll() is None:
        attempts += 1
        actual = _query_process_path(process.pid)
        if actual:
            break
        time.sleep(0.025)
    elapsed = int((time.monotonic() - started) * 1000)
    if not actual:
        raise WorkerContractError("FAILURE_CHILD_PATH_UNAVAILABLE")
    if Path(actual).resolve() != expected.resolve():
        raise WorkerContractError("FAILURE_CHILD_PATH_MISMATCH")
    return actual, attempts, elapsed


def _read_child_line(stream: Any, target: queue.Queue[str]) -> None:
    try:
        target.put(stream.readline())
    except Exception:
        target.put("")


def run_process_termination(plan: WorkerPlan) -> list[dict[str, Any]]:
    started = time.monotonic()
    host = required_parameter(plan, "remote_host", str)
    port = required_port(plan)
    payload = _payload(plan)
    payload_hash = hashlib.sha256(payload).hexdigest()
    expected_path = Path(sys.executable).resolve()
    target_identity = hashlib.sha256(str(expected_path).lower().encode("utf-8")).hexdigest()
    injection_started = timestamp_utc()
    metadata = {
        field: str(plan.raw[field]) for field in ("run_id", "scenario_id", "attempt_id", "flow_id")
    }
    metadata.update({
        "payload_sha256": payload_hash,
        "injector_id": "client-process-controller",
        "target_identity": target_identity,
        "injection_started_utc": injection_started,
        "expected_failure_signature": "CLIENT_PROCESS_TERMINATED",
    })
    child_plan = base64.urlsafe_b64encode(json.dumps({
        "host": host,
        "port": port,
        "timeout_ms": int(plan.raw["operation_timeout_ms"]),
        "metadata": base64.urlsafe_b64encode(json.dumps(metadata, sort_keys=True, separators=(",", ":")).encode("utf-8")).decode("ascii"),
        "payload": base64.urlsafe_b64encode(payload).decode("ascii"),
    }, sort_keys=True, separators=(",", ":")).encode("utf-8")).decode("ascii")
    creation_flags = 0x08000000 if os.name == "nt" else 0
    process = subprocess.Popen(
        [str(expected_path), "-I", "-B", str(Path(__file__).resolve()), "--child", child_plan],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        creationflags=creation_flags,
    )
    try:
        actual_path, probe_attempts, probe_elapsed = _verified_child_path(process, expected_path)
        lines: queue.Queue[str] = queue.Queue(maxsize=1)
        reader = threading.Thread(target=_read_child_line, args=(process.stdout, lines), daemon=True)
        reader.start()
        try:
            line = lines.get(timeout=plan.raw["operation_timeout_ms"] / 1000.0)
        except queue.Empty as exc:
            raise WorkerContractError("FAILURE_CHILD_READY_TIMEOUT") from exc
        if not line.startswith("READY "):
            raise WorkerContractError("FAILURE_CHILD_READY_INVALID")
        try:
            child_state = json.loads(base64.urlsafe_b64decode(line[6:].strip()).decode("utf-8"))
        except (ValueError, UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise WorkerContractError("FAILURE_CHILD_READY_INVALID") from exc
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
        if process.returncode == 0:
            raise WorkerContractError("FAILURE_CHILD_TERMINATION_NOT_OBSERVED")
        record = base_record(
            plan, event="CLIENT_PROCESS_TERMINATED", started=started, socket_id=0,
            local=(str(child_state["local_ip"]), int(child_state["local_port"])),
            remote=(str(child_state["remote_ip"]), int(child_state["remote_port"])),
            payload_sha256=payload_hash, byte_count=len(payload), result="PASS",
        )
        record["process_id"] = process.pid
        record.update({
            "injector_id": "client-process-controller",
            "target_identity": target_identity,
            "injection_started_utc": injection_started,
            "injection_verified": True,
            "expected_failure_signature": "CLIENT_PROCESS_TERMINATED",
            "rollback_verified": True,
            "actual_path_probe_status": "PATH_OBTAINED",
            "actual_path_probe_attempts": probe_attempts,
            "actual_path_probe_elapsed_ms": probe_elapsed,
            "actual_path_identity": hashlib.sha256(actual_path.lower().encode("utf-8")).hexdigest(),
        })
        return [record]
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=5)
        if process.stdout is not None:
            process.stdout.close()
        if process.stderr is not None:
            process.stderr.close()


def _child_main(encoded: str) -> int:
    try:
        raw = json.loads(base64.urlsafe_b64decode(encoded).decode("utf-8"))
        host = str(raw["host"])
        port = int(raw["port"])
        timeout = int(raw["timeout_ms"]) / 1000.0
        metadata = str(raw["metadata"]).encode("ascii")
        payload = base64.urlsafe_b64decode(str(raw["payload"]).encode("ascii"))
        frame = b"PBFAIL1" + len(metadata).to_bytes(2, "big") + metadata + len(payload).to_bytes(4, "big") + payload
        with socket.create_connection((host, port), timeout=timeout) as sock:
            sock.settimeout(timeout)
            sock.sendall(frame)
            local = sock.getsockname()
            remote = sock.getpeername()
            state = base64.urlsafe_b64encode(json.dumps({"local_ip": local[0], "local_port": local[1], "remote_ip": remote[0], "remote_port": remote[1]}, separators=(",", ":")).encode("utf-8")).decode("ascii")
            print("READY " + state, flush=True)
            sock.recv(1)
        return 0
    except Exception:
        print("CHILD_ERROR", flush=True)
        return 2


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--child":
        raise SystemExit(_child_main(sys.argv[2]))
    raise SystemExit(2)
