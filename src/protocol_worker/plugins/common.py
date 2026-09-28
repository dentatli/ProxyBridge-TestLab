from __future__ import annotations

import os
import errno
import socket
import time
from datetime import datetime, timezone
from typing import Any

from model import WorkerContractError, WorkerPlan


NO_RESPONSE_ERRNOS = {
    errno.EACCES,
    errno.ECONNABORTED,
    errno.ECONNREFUSED,
    errno.ECONNRESET,
    errno.EHOSTUNREACH,
    errno.ENETUNREACH,
    errno.ETIMEDOUT,
}
NO_RESPONSE_WINERRORS = {10013, 10051, 10054, 10060, 10061, 10065}


def expects_no_response(plan: WorkerPlan) -> bool:
    return str(plan.raw["expected"].get("outcome", "response")).lower() == "no-response"


def is_no_response_exception(exc: BaseException) -> bool:
    if isinstance(exc, (socket.timeout, TimeoutError, ConnectionRefusedError, ConnectionResetError, ConnectionAbortedError)):
        return True
    if not isinstance(exc, OSError):
        return False
    return exc.errno in NO_RESPONSE_ERRNOS or getattr(exc, "winerror", None) in NO_RESPONSE_WINERRORS


def no_response_reason(exc: BaseException) -> str:
    if isinstance(exc, (socket.timeout, TimeoutError)):
        return "TIMEOUT"
    if isinstance(exc, PermissionError):
        return "ACCESS_DENIED"
    if isinstance(exc, ConnectionRefusedError):
        return "CONNECTION_REFUSED"
    if isinstance(exc, ConnectionResetError):
        return "CONNECTION_RESET"
    if isinstance(exc, ConnectionAbortedError):
        return "CONNECTION_ABORTED"
    return "NETWORK_UNREACHABLE"


def timestamp_utc() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def required_parameter(plan: WorkerPlan, name: str, expected_type: type) -> Any:
    value = plan.raw["parameters"].get(name)
    if not isinstance(value, expected_type) or (expected_type is str and not value):
        raise WorkerContractError(f"PLUGIN_PARAMETER_INVALID:{name}")
    return value


def required_port(plan: WorkerPlan) -> int:
    value = plan.raw["parameters"].get("remote_port")
    if isinstance(value, bool) or not isinstance(value, int) or value < 1 or value > 65535:
        raise WorkerContractError("PLUGIN_PARAMETER_INVALID:remote_port")
    return value


def base_record(
    plan: WorkerPlan,
    *,
    event: str,
    started: float,
    socket_id: int,
    local: Any,
    remote: Any,
    payload_sha256: str,
    byte_count: int,
    result: str,
) -> dict[str, Any]:
    return {
        "schema_version": 1,
        "run_id": plan.raw["run_id"],
        "scenario_id": plan.raw["scenario_id"],
        "attempt_id": plan.raw["attempt_id"],
        "flow_id": plan.raw["flow_id"],
        "phase": "client",
        "sequence": 1,
        "event": event,
        "timestamp_utc": timestamp_utc(),
        "monotonic_ms": int((time.monotonic() - started) * 1000),
        "process_id": os.getpid(),
        "socket_id": socket_id,
        "protocol_family": plan.protocol_family,
        "transport": plan.transport,
        "local_ip": str(local[0]) if local else "",
        "local_port": int(local[1]) if local else 0,
        "remote_ip": str(remote[0]) if remote else "",
        "remote_port": int(remote[1]) if remote else 0,
        "payload_sha256": payload_sha256,
        "bytes": byte_count,
        "result": result,
    }
