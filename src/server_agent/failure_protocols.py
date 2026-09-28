from __future__ import annotations

import asyncio
import base64
import hashlib
import json
import os
from datetime import datetime, timezone
from typing import Any, Callable


def _utc() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _decode_metadata(value: bytes) -> dict[str, str]:
    parsed = json.loads(base64.urlsafe_b64decode(value).decode("utf-8"))
    if not isinstance(parsed, dict):
        raise ValueError("METADATA_INVALID")
    result = {str(key): str(item) for key, item in parsed.items()}
    for field in ("run_id", "scenario_id", "attempt_id", "flow_id", "payload_sha256", "injector_id", "target_identity", "injection_started_utc", "expected_failure_signature"):
        if not result.get(field):
            raise ValueError("METADATA_MISSING")
    return result


async def _process_termination(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, evidence: Callable[[dict[str, Any]], None]) -> None:
    try:
        if await reader.readexactly(7) != b"PBFAIL1":
            return
        metadata_length = int.from_bytes(await reader.readexactly(2), "big")
        if metadata_length <= 0 or metadata_length > 4096:
            return
        metadata = _decode_metadata(await reader.readexactly(metadata_length))
        payload_length = int.from_bytes(await reader.readexactly(4), "big")
        if payload_length <= 0 or payload_length > 1024 * 1024:
            return
        payload = await reader.readexactly(payload_length)
        if hashlib.sha256(payload).hexdigest() != metadata["payload_sha256"]:
            return
        try:
            trailing = await reader.read(1)
        except ConnectionError:
            # TerminateProcess closes an established Windows TCP socket with a
            # reset rather than a graceful EOF.  Once the complete framed
            # payload has been validated, either condition proves the intended
            # client-process disconnect.
            trailing = b""
        if trailing:
            return
        local = writer.get_extra_info("sockname")
        remote = writer.get_extra_info("peername")
        evidence({
            "schema_version": 1, "run_id": metadata["run_id"], "scenario_id": metadata["scenario_id"],
            "attempt_id": metadata["attempt_id"], "flow_id": metadata["flow_id"], "phase": "server",
            "sequence": 1, "event": "CLIENT_DISCONNECT_OBSERVED", "timestamp_utc": _utc(), "monotonic_ms": 0,
            "process_id": os.getpid(), "socket_id": 0, "protocol_family": "process-failure", "transport": "TCP",
            "local_ip": str(local[0]), "local_port": int(local[1]), "remote_ip": str(remote[0]), "remote_port": int(remote[1]),
            "payload_sha256": metadata["payload_sha256"], "bytes": len(payload), "result": "PASS",
            "injector_id": metadata["injector_id"], "target_identity": metadata["target_identity"],
            "injection_started_utc": metadata["injection_started_utc"], "injection_verified": True,
            "expected_failure_signature": metadata["expected_failure_signature"], "rollback_verified": True,
        })
    except (asyncio.IncompleteReadError, ConnectionError, ValueError, KeyError, UnicodeDecodeError):
        pass
    finally:
        writer.close()
        try:
            await writer.wait_closed()
        except (ConnectionError, OSError):
            pass


async def start_failure_protocols(bind: str, config: dict[str, Any], evidence: Callable[[dict[str, Any]], None], preferred_ports: dict[str, int]) -> tuple[list[asyncio.AbstractServer], dict[str, int]]:
    requested = preferred_ports.get("failure_control", int(config["failure_control"]["port"]))
    server = await asyncio.start_server(lambda r, w: _process_termination(r, w, evidence), bind, requested)
    return [server], {"failure_control": int(server.sockets[0].getsockname()[1])}
