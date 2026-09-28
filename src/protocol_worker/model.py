from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping


IDENTIFIER_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$")
ALLOWED_TRANSPORTS = {"NONE", "TCP", "UDP"}
PLAN_REQUIRED_KEYS = {
    "schema_version",
    "run_id",
    "scenario_id",
    "attempt_id",
    "flow_id",
    "plugin_id",
    "protocol_family",
    "transport",
    "operation_timeout_ms",
    "parameters",
    "expected",
}
PLAN_OPTIONAL_KEYS = {"capabilities"}
COMMON_EVIDENCE_FIELDS = {
    "schema_version",
    "run_id",
    "scenario_id",
    "attempt_id",
    "flow_id",
    "phase",
    "sequence",
    "event",
    "timestamp_utc",
    "monotonic_ms",
    "process_id",
    "socket_id",
    "protocol_family",
    "transport",
    "local_ip",
    "local_port",
    "remote_ip",
    "remote_port",
    "payload_sha256",
    "bytes",
    "result",
}
SENSITIVE_KEY_TOKENS = (
    "PASSWORD",
    "SECRET",
    "TOKEN",
    "CREDENTIAL",
    "PRIVATE_KEY",
    "SSH_KEY",
)
SENSITIVE_REFERENCE_SUFFIXES = ("_REF", "_ID", "_PRESENT")


class WorkerContractError(ValueError):
    """Stable, content-free protocol worker validation error."""


@dataclass(frozen=True)
class WorkerPlan:
    raw: Mapping[str, Any]

    @property
    def plugin_id(self) -> str:
        return str(self.raw["plugin_id"])

    @property
    def protocol_family(self) -> str:
        return str(self.raw["protocol_family"])

    @property
    def transport(self) -> str:
        return str(self.raw["transport"])


def _validate_identifier(value: Any, field: str) -> str:
    text = str(value)
    if not IDENTIFIER_RE.fullmatch(text):
        raise WorkerContractError(f"PLAN_IDENTIFIER_INVALID:{field}")
    return text


def _walk_plan(value: Any, *, depth: int = 0, nodes: list[int] | None = None) -> None:
    if nodes is None:
        nodes = [0]
    nodes[0] += 1
    if nodes[0] > 512:
        raise WorkerContractError("PLAN_NODE_LIMIT_EXCEEDED")
    if depth > 8:
        raise WorkerContractError("PLAN_DEPTH_LIMIT_EXCEEDED")
    if isinstance(value, Mapping):
        for key, child in value.items():
            key_text = str(key)
            upper_key = key_text.upper()
            if any(token in upper_key for token in SENSITIVE_KEY_TOKENS) and not upper_key.endswith(SENSITIVE_REFERENCE_SUFFIXES):
                raise WorkerContractError("PLAN_SECRET_VALUE_FORBIDDEN")
            _walk_plan(child, depth=depth + 1, nodes=nodes)
        return
    if isinstance(value, (list, tuple)):
        for child in value:
            _walk_plan(child, depth=depth + 1, nodes=nodes)
        return
    if value is None or isinstance(value, (bool, int, float)):
        return
    if isinstance(value, str):
        if len(value) > 4096:
            raise WorkerContractError("PLAN_SCALAR_LIMIT_EXCEEDED")
        if any(ord(character) < 0x20 and character not in "\t\r\n" for character in value):
            raise WorkerContractError("PLAN_CONTROL_CHARACTER_FORBIDDEN")
        return
    raise WorkerContractError("PLAN_VALUE_TYPE_INVALID")


def load_plan(path: Path) -> WorkerPlan:
    try:
        raw_bytes = path.read_bytes()
    except OSError as exc:
        raise WorkerContractError("PLAN_READ_FAILED") from exc
    if raw_bytes.startswith(b"\xef\xbb\xbf"):
        raise WorkerContractError("PLAN_UTF8_BOM_FORBIDDEN")
    try:
        raw = json.loads(raw_bytes.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise WorkerContractError("PLAN_JSON_INVALID") from exc
    if not isinstance(raw, dict):
        raise WorkerContractError("PLAN_ROOT_INVALID")
    unknown = set(raw) - PLAN_REQUIRED_KEYS - PLAN_OPTIONAL_KEYS
    missing = PLAN_REQUIRED_KEYS - set(raw)
    if missing:
        raise WorkerContractError("PLAN_REQUIRED_FIELD_MISSING")
    if unknown:
        raise WorkerContractError("PLAN_UNKNOWN_FIELD")
    if raw["schema_version"] != 1:
        raise WorkerContractError("PLAN_SCHEMA_UNSUPPORTED")
    for field in ("run_id", "scenario_id", "attempt_id", "flow_id", "plugin_id", "protocol_family"):
        _validate_identifier(raw[field], field)
    if str(raw["transport"]) not in ALLOWED_TRANSPORTS:
        raise WorkerContractError("PLAN_TRANSPORT_INVALID")
    timeout_ms = raw["operation_timeout_ms"]
    if isinstance(timeout_ms, bool) or not isinstance(timeout_ms, int) or timeout_ms <= 0 or timeout_ms > 86_400_000:
        raise WorkerContractError("PLAN_TIMEOUT_INVALID")
    if not isinstance(raw["parameters"], dict) or not isinstance(raw["expected"], dict):
        raise WorkerContractError("PLAN_OBJECT_FIELD_INVALID")
    capabilities = raw.get("capabilities", [])
    if not isinstance(capabilities, list) or any(not IDENTIFIER_RE.fullmatch(str(item)) for item in capabilities):
        raise WorkerContractError("PLAN_CAPABILITY_INVALID")
    _walk_plan(raw)
    return WorkerPlan(raw=raw)


def validate_evidence_record(record: Mapping[str, Any], plan: WorkerPlan, required_fields: set[str]) -> None:
    if not isinstance(record, Mapping):
        raise WorkerContractError("EVIDENCE_RECORD_INVALID")
    missing = (COMMON_EVIDENCE_FIELDS | required_fields) - set(record)
    if missing:
        raise WorkerContractError("EVIDENCE_REQUIRED_FIELD_MISSING")
    for field in ("run_id", "scenario_id", "attempt_id", "flow_id"):
        if str(record[field]) != str(plan.raw[field]):
            raise WorkerContractError("EVIDENCE_IDENTITY_MISMATCH")
    if str(record["protocol_family"]) != plan.protocol_family or str(record["transport"]) != plan.transport:
        raise WorkerContractError("EVIDENCE_PROTOCOL_MISMATCH")
    payload_hash = str(record["payload_sha256"])
    if not re.fullmatch(r"[0-9a-fA-F]{64}", payload_hash):
        raise WorkerContractError("EVIDENCE_PAYLOAD_HASH_INVALID")
    _walk_plan(record)


def deterministic_payload_hash(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()
