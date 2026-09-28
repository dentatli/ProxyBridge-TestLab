from __future__ import annotations

import hashlib
import json
import socket
import ssl
import time
from pathlib import Path
from typing import Any

from model import WorkerContractError, WorkerPlan
from plugins.common import base_record, expects_no_response, is_no_response_exception, no_response_reason, required_parameter, required_port


def run_tls(plan: WorkerPlan) -> list[dict[str, Any]]:
    started = time.monotonic()
    host = required_parameter(plan, "remote_host", str)
    port = required_port(plan)
    server_name = required_parameter(plan, "server_name", str)
    ca_path = Path(required_parameter(plan, "ca_path", str)).resolve()
    if not ca_path.is_file():
        raise WorkerContractError("TLS_CA_FILE_MISSING")
    marker = f"tls|{plan.raw['run_id']}|{plan.raw['scenario_id']}|{plan.raw['attempt_id']}|{plan.raw['flow_id']}".encode("utf-8")
    payload_hash = hashlib.sha256(marker).hexdigest()
    request = json.dumps({"run_id": plan.raw["run_id"], "scenario_id": plan.raw["scenario_id"], "attempt_id": plan.raw["attempt_id"], "flow_id": plan.raw["flow_id"], "payload_sha256": payload_hash}, sort_keys=True, separators=(",", ":")).encode("utf-8") + b"\n"
    timeout = plan.raw["operation_timeout_ms"] / 1000.0
    context = ssl.create_default_context(ssl.Purpose.SERVER_AUTH, cafile=str(ca_path))
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.set_alpn_protocols(["pb-test/1"])
    socket_id = 0
    local: Any = None
    remote: Any = None
    try:
        with socket.create_connection((host, port), timeout=timeout) as raw:
            raw.settimeout(timeout)
            socket_id = raw.fileno()
            local, remote = raw.getsockname(), raw.getpeername()
            with context.wrap_socket(raw, server_hostname=server_name) as sock:
                socket_id = sock.fileno()
                local, remote = sock.getsockname(), sock.getpeername()
                peer_certificate = sock.getpeercert(binary_form=True) or b""
                sock.sendall(request)
                response = sock.makefile("rb").readline(8193)
                if not response or len(response) > 8192:
                    raise WorkerContractError("TLS_RESPONSE_INVALID")
                try:
                    value = json.loads(response.decode("utf-8"))
                except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                    raise WorkerContractError("TLS_RESPONSE_INVALID") from exc
                cipher = sock.cipher()
                result = "PASS" if not expects_no_response(plan) and value.get("flow_id") == plan.raw["flow_id"] and value.get("payload_sha256") == payload_hash and value.get("result") == "PASS" else "FAIL"
                record = base_record(plan, event="TLS_TRANSACTION_COMPLETED", started=started, socket_id=socket_id, local=local, remote=remote, payload_sha256=payload_hash, byte_count=len(request), result=result)
                record.update({"tls_version": sock.version() or "", "cipher_suite": cipher[0] if cipher else "", "server_name": server_name, "alpn": sock.selected_alpn_protocol() or "", "peer_certificate_sha256": hashlib.sha256(peer_certificate).hexdigest(), "resumed": bool(sock.session_reused), "shutdown_status": "GRACEFUL", "no_response_observed": False})
                return [record]
    except OSError as exc:
        if not expects_no_response(plan) or not is_no_response_exception(exc):
            raise
        record = base_record(plan, event="TLS_NO_RESPONSE_OBSERVED", started=started, socket_id=socket_id, local=local, remote=remote, payload_sha256=payload_hash, byte_count=len(request), result="PASS")
        record.update({"tls_version": "", "cipher_suite": "", "server_name": server_name, "alpn": "", "peer_certificate_sha256": hashlib.sha256(b"").hexdigest(), "resumed": False, "shutdown_status": "NOT_OBSERVED", "no_response_observed": True, "no_response_reason": no_response_reason(exc)})
        return [record]
