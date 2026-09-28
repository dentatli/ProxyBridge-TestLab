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


def _read_headers(stream: Any) -> tuple[int, dict[str, str]]:
    status_line = stream.readline(8193)
    if not status_line or len(status_line) > 8192:
        raise WorkerContractError("HTTP_RESPONSE_STATUS_INVALID")
    parts = status_line.decode("iso-8859-1").rstrip("\r\n").split(" ", 2)
    if len(parts) < 2 or parts[0] != "HTTP/1.1":
        raise WorkerContractError("HTTP_RESPONSE_STATUS_INVALID")
    status = int(parts[1])
    headers: dict[str, str] = {}
    total = len(status_line)
    while True:
        line = stream.readline(8193)
        total += len(line)
        if total > 65536 or not line:
            raise WorkerContractError("HTTP_RESPONSE_HEADER_INVALID")
        if line == b"\r\n":
            break
        text = line.decode("iso-8859-1").rstrip("\r\n")
        if ":" not in text:
            raise WorkerContractError("HTTP_RESPONSE_HEADER_INVALID")
        name, value = text.split(":", 1)
        headers[name.strip().lower()] = value.strip()
    return status, headers


def run_http1(plan: WorkerPlan) -> list[dict[str, Any]]:
    started = time.monotonic()
    host = required_parameter(plan, "remote_host", str)
    port = required_port(plan)
    authority = required_parameter(plan, "authority", str)
    use_tls = bool(plan.raw["parameters"].get("use_tls", False))
    path = str(plan.raw["parameters"].get("path", "/probe"))
    if not path.startswith("/") or "\r" in path or "\n" in path:
        raise WorkerContractError("HTTP_PATH_INVALID")
    marker = f"http1|{plan.raw['run_id']}|{plan.raw['scenario_id']}|{plan.raw['attempt_id']}|{plan.raw['flow_id']}".encode("utf-8")
    request_hash = hashlib.sha256(marker).hexdigest()
    headers = [
        f"POST {path} HTTP/1.1", f"Host: {authority}", "Content-Type: application/octet-stream", f"Content-Length: {len(marker)}",
        f"X-TestLab-Run: {plan.raw['run_id']}", f"X-TestLab-Scenario: {plan.raw['scenario_id']}", f"X-TestLab-Attempt: {plan.raw['attempt_id']}",
        f"X-TestLab-Flow: {plan.raw['flow_id']}", "Connection: close", "", "",
    ]
    request = "\r\n".join(headers).encode("ascii") + marker
    timeout = plan.raw["operation_timeout_ms"] / 1000.0
    raw: socket.socket | None = None
    socket_id = 0
    local: Any = None
    remote: Any = None
    try:
        raw = socket.create_connection((host, port), timeout=timeout)
        raw.settimeout(timeout)
        socket_id = raw.fileno()
        local, remote = raw.getsockname(), raw.getpeername()
        sock: socket.socket
        if use_tls:
            ca_path = Path(required_parameter(plan, "ca_path", str)).resolve()
            server_name = required_parameter(plan, "server_name", str)
            context = ssl.create_default_context(ssl.Purpose.SERVER_AUTH, cafile=str(ca_path))
            context.set_alpn_protocols(["http/1.1"])
            sock = context.wrap_socket(raw, server_hostname=server_name)
        else:
            sock = raw
        try:
            socket_id = sock.fileno()
            local, remote = sock.getsockname(), sock.getpeername()
            sock.sendall(request)
            stream = sock.makefile("rb")
            status, response_headers = _read_headers(stream)
            content_length = int(response_headers.get("content-length", "-1"))
            if content_length < 0 or content_length > 1024 * 1024:
                raise WorkerContractError("HTTP_RESPONSE_LENGTH_INVALID")
            response_body = stream.read(content_length)
            if len(response_body) != content_length:
                raise WorkerContractError("HTTP_RESPONSE_BODY_TRUNCATED")
            try:
                value = json.loads(response_body.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                raise WorkerContractError("HTTP_RESPONSE_BODY_INVALID") from exc
            result = "PASS" if not expects_no_response(plan) and status == int(plan.raw["expected"].get("status_code", 200)) and value.get("flow_id") == plan.raw["flow_id"] and value.get("request_body_sha256") == request_hash and value.get("result") == "PASS" else "FAIL"
            record = base_record(plan, event="HTTP1_TRANSACTION_COMPLETED", started=started, socket_id=socket_id, local=local, remote=remote, payload_sha256=request_hash, byte_count=len(marker), result=result)
            record.update({"method": "POST", "authority": authority, "path_digest": hashlib.sha256(path.encode("utf-8")).hexdigest(), "request_body_sha256": request_hash, "status_code": status, "response_body_sha256": hashlib.sha256(response_body).hexdigest(), "connection_reused": False, "no_response_observed": False})
            return [record]
        finally:
            if sock is not raw:
                sock.close()
    except OSError as exc:
        if not expects_no_response(plan) or not is_no_response_exception(exc):
            raise
        record = base_record(plan, event="HTTP1_NO_RESPONSE_OBSERVED", started=started, socket_id=socket_id, local=local, remote=remote, payload_sha256=request_hash, byte_count=len(marker), result="PASS")
        record.update({"method": "POST", "authority": authority, "path_digest": hashlib.sha256(path.encode("utf-8")).hexdigest(), "request_body_sha256": request_hash, "status_code": 0, "response_body_sha256": hashlib.sha256(b"").hexdigest(), "connection_reused": False, "no_response_observed": True, "no_response_reason": no_response_reason(exc)})
        return [record]
    finally:
        if raw is not None:
            raw.close()
