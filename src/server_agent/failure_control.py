"""Receipt-bound, adapter-injected control for the TestLab endpoint restart."""

from __future__ import annotations

import json
import re
from typing import Any, Protocol


_REQUEST_FIELDS = frozenset({"schema_version", "receipt_id", "request_id", "target", "action", "timeout_ms"})
_TARGET = "proxybridge-testlab-endpoint.service"
_ACTION = "restart"
_MIN_TIMEOUT_MS = 100
_MAX_TIMEOUT_MS = 30_000
_RECEIPT_ID = re.compile(r"^[0-9a-f]{64}$")
_REQUEST_ID = re.compile(r"^[0-9a-f]{32}$")


class FailureControlError(ValueError):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


class FailureControlAdapter(Protocol):
    """The privileged implementation is deliberately outside this offline core."""

    def await_barrier(self, receipt_id: str, request_id: str, timeout_ms: int) -> dict[str, Any]: ...
    def restart(self, target: str, timeout_ms: int) -> dict[str, Any]: ...
    def verify_health(self, target: str, invocation_id: str, timeout_ms: int) -> dict[str, Any]: ...
    def verify_rollback(self, receipt_id: str, request_id: str, timeout_ms: int) -> bool: ...


def _no_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise FailureControlError("FAILURE_CONTROL_REQUEST_JSON_INVALID")
        result[key] = value
    return result


def _parse_request(request_json: str | bytes) -> dict[str, Any]:
    if not isinstance(request_json, (str, bytes)):
        raise FailureControlError("FAILURE_CONTROL_REQUEST_JSON_INVALID")
    try:
        request = json.loads(request_json, object_pairs_hook=_no_duplicate_keys)
    except (json.JSONDecodeError, UnicodeDecodeError, FailureControlError) as error:
        if isinstance(error, FailureControlError):
            raise
        raise FailureControlError("FAILURE_CONTROL_REQUEST_JSON_INVALID") from error
    if not isinstance(request, dict) or set(request) != _REQUEST_FIELDS:
        raise FailureControlError("FAILURE_CONTROL_REQUEST_FIELDS_INVALID")
    if request["schema_version"] != 1:
        raise FailureControlError("FAILURE_CONTROL_SCHEMA_VERSION_INVALID")
    if not isinstance(request["receipt_id"], str) or not _RECEIPT_ID.fullmatch(request["receipt_id"]):
        raise FailureControlError("FAILURE_CONTROL_RECEIPT_INVALID")
    if not isinstance(request["request_id"], str) or not _REQUEST_ID.fullmatch(request["request_id"]):
        raise FailureControlError("FAILURE_CONTROL_REQUEST_ID_INVALID")
    if request["target"] != _TARGET:
        raise FailureControlError("FAILURE_CONTROL_TARGET_INVALID")
    if request["action"] != _ACTION:
        raise FailureControlError("FAILURE_CONTROL_ACTION_INVALID")
    if type(request["timeout_ms"]) is not int or not _MIN_TIMEOUT_MS <= request["timeout_ms"] <= _MAX_TIMEOUT_MS:
        raise FailureControlError("FAILURE_CONTROL_TIMEOUT_INVALID")
    return request


def _state(record: Any, expected_state: str, code: str) -> str:
    if not isinstance(record, dict) or set(record) != {"state", "invocation_id"}:
        raise FailureControlError(code)
    invocation_id = record["invocation_id"]
    if record["state"] != expected_state or not isinstance(invocation_id, str) or not invocation_id:
        raise FailureControlError(code)
    return invocation_id


def execute_failure_control_request(request_json: str | bytes, adapter: FailureControlAdapter) -> dict[str, Any]:
    """Validate and execute the sole permitted control operation through *adapter*.

    This module intentionally has no subprocess, socket, systemd, root, or
    network capability.  A provisioned caller supplies the narrowly scoped
    adapter; tests supply an in-memory adapter.
    """

    request = _parse_request(request_json)
    timeout_ms = request["timeout_ms"]
    receipt_id = request["receipt_id"]
    request_id = request["request_id"]
    target = request["target"]

    before = _state(adapter.await_barrier(receipt_id, request_id, timeout_ms), "ARMED", "FAILURE_CONTROL_BARRIER_INVALID")
    after = _state(adapter.restart(target, timeout_ms), "RESTARTED", "FAILURE_CONTROL_RESTART_INVALID")
    if after == before:
        raise FailureControlError("FAILURE_CONTROL_INVOCATION_NOT_CHANGED")
    healthy = _state(adapter.verify_health(target, after, timeout_ms), "HEALTHY", "FAILURE_CONTROL_HEALTH_INVALID")
    if healthy != after:
        raise FailureControlError("FAILURE_CONTROL_HEALTH_INVALID")
    if adapter.verify_rollback(receipt_id, request_id, timeout_ms) is not True:
        raise FailureControlError("FAILURE_CONTROL_ROLLBACK_UNVERIFIED")

    return {
        "schema_version": 1,
        "receipt_id": receipt_id,
        "request_id": request_id,
        "target": target,
        "action": _ACTION,
        "timeout_ms": timeout_ms,
        "invocation_id_before": before,
        "invocation_id_after": after,
        "barrier_states": ["ARMED", "RESTARTED", "HEALTHY", "ROLLBACK_VERIFIED"],
        "rollback_verified": True,
    }
