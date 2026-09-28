from __future__ import annotations

import base64
import hashlib
import socket
import ssl
import struct
import time
from pathlib import Path
from typing import Any

from model import WorkerContractError, WorkerPlan
from plugins.common import base_record, expects_no_response, is_no_response_exception, no_response_reason, required_parameter, required_port


def _read_headers(stream: Any) -> tuple[int, dict[str, str]]:
    status_line = stream.readline(8193)
    if not status_line or len(status_line) > 8192:
        raise WorkerContractError("WEBSOCKET_HANDSHAKE_INVALID")
    parts = status_line.decode("iso-8859-1").rstrip("\r\n").split(" ", 2)
    if len(parts) < 2 or not parts[1].isdigit():
        raise WorkerContractError("WEBSOCKET_HANDSHAKE_INVALID")
    headers: dict[str, str] = {}
    total = len(status_line)
    while True:
        line = stream.readline(8193)
        total += len(line)
        if not line or total > 65536:
            raise WorkerContractError("WEBSOCKET_HANDSHAKE_INVALID")
        if line == b"\r\n":
            return int(parts[1]), headers
        text = line.decode("iso-8859-1").rstrip("\r\n")
        if ":" not in text:
            raise WorkerContractError("WEBSOCKET_HANDSHAKE_INVALID")
        name, value = text.split(":", 1)
        headers[name.strip().lower()] = value.strip()


def _send_masked_frame(sock: socket.socket, opcode: int, payload: bytes, mask: bytes) -> None:
    if len(mask) != 4 or len(payload) > 65535:
        raise WorkerContractError("WEBSOCKET_FRAME_SIZE_INVALID")
    if len(payload) <= 125:
        header = bytes([0x80 | opcode, 0x80 | len(payload)])
    else:
        header = bytes([0x80 | opcode, 0x80 | 126]) + struct.pack("!H", len(payload))
    masked = bytes(value ^ mask[index % 4] for index, value in enumerate(payload))
    sock.sendall(header + mask + masked)


def _receive_frame(sock: socket.socket) -> tuple[int, bytes]:
    header = sock.recv(2)
    if len(header) != 2 or not header[0] & 0x80:
        raise WorkerContractError("WEBSOCKET_FRAME_INVALID")
    opcode = header[0] & 0x0F
    masked = bool(header[1] & 0x80)
    length = header[1] & 0x7F
    if length == 126:
        encoded = sock.recv(2)
        if len(encoded) != 2:
            raise WorkerContractError("WEBSOCKET_FRAME_INVALID")
        length = struct.unpack("!H", encoded)[0]
    elif length == 127:
        raise WorkerContractError("WEBSOCKET_FRAME_SIZE_INVALID")
    if masked or length > 65535:
        raise WorkerContractError("WEBSOCKET_FRAME_INVALID")
    payload = bytearray()
    while len(payload) < length:
        chunk = sock.recv(length - len(payload))
        if not chunk:
            raise WorkerContractError("WEBSOCKET_FRAME_TRUNCATED")
        payload.extend(chunk)
    return opcode, bytes(payload)


def run_websocket(plan: WorkerPlan) -> list[dict[str, Any]]:
    started = time.monotonic()
    host = required_parameter(plan, "remote_host", str)
    port = required_port(plan)
    authority = required_parameter(plan, "authority", str)
    path = str(plan.raw["parameters"].get("path", "/socket"))
    subprotocol = str(plan.raw["parameters"].get("subprotocol", "pb-test.v1"))
    use_tls = bool(plan.raw["parameters"].get("use_tls", True))
    if not path.startswith("/") or any(character in path + subprotocol for character in "\r\n"):
        raise WorkerContractError("WEBSOCKET_PARAMETER_INVALID")
    payload = f"websocket|{plan.raw['run_id']}|{plan.raw['scenario_id']}|{plan.raw['attempt_id']}|{plan.raw['flow_id']}".encode("utf-8")
    payload_hash = hashlib.sha256(payload).hexdigest()
    key_bytes = hashlib.sha256((payload_hash + "|key").encode("ascii")).digest()[:16]
    key = base64.b64encode(key_bytes).decode("ascii")
    expected_accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode("ascii"), usedforsecurity=False).digest()).decode("ascii")
    request_lines = [
        f"GET {path} HTTP/1.1", f"Host: {authority}", "Upgrade: websocket", "Connection: Upgrade", "Sec-WebSocket-Version: 13",
        f"Sec-WebSocket-Key: {key}", f"Sec-WebSocket-Protocol: {subprotocol}", f"X-TestLab-Run: {plan.raw['run_id']}",
        f"X-TestLab-Scenario: {plan.raw['scenario_id']}", f"X-TestLab-Attempt: {plan.raw['attempt_id']}", f"X-TestLab-Flow: {plan.raw['flow_id']}", "", "",
    ]
    timeout = plan.raw["operation_timeout_ms"] / 1000.0
    raw: socket.socket | None = None
    socket_id = 0
    local: Any = None
    remote: Any = None
    try:
        raw = socket.create_connection((host, port), timeout=timeout)
        raw.settimeout(timeout)
        sock: socket.socket = raw
        if use_tls:
            ca_path = Path(required_parameter(plan, "ca_path", str)).resolve()
            context = ssl.create_default_context(ssl.Purpose.SERVER_AUTH, cafile=str(ca_path))
            context.set_alpn_protocols(["http/1.1"])
            sock = context.wrap_socket(raw, server_hostname=required_parameter(plan, "server_name", str))
        try:
            socket_id, local, remote = sock.fileno(), sock.getsockname(), sock.getpeername()
            sock.sendall("\r\n".join(request_lines).encode("ascii"))
            stream = sock.makefile("rb")
            status, response_headers = _read_headers(stream)
            accepted = status == 101 and response_headers.get("sec-websocket-accept") == expected_accept and response_headers.get("sec-websocket-protocol") == subprotocol
            mask = hashlib.sha256((payload_hash + "|mask").encode("ascii")).digest()[:4]
            _send_masked_frame(sock, 2, payload, mask)
            opcode, echo = _receive_frame(sock)
            _send_masked_frame(sock, 8, struct.pack("!H", 1000), mask)
            close_opcode, close_payload = _receive_frame(sock)
            close_code = struct.unpack("!H", close_payload[:2])[0] if close_opcode == 8 and len(close_payload) >= 2 else 0
            result = "PASS" if not expects_no_response(plan) and accepted and opcode == 2 and echo == payload and close_code == 1000 else "FAIL"
            record = base_record(plan, event="WEBSOCKET_TRANSACTION_COMPLETED", started=started, socket_id=socket_id, local=local, remote=remote, payload_sha256=payload_hash, byte_count=len(payload), result=result)
            record.update({"upgrade_status": status, "subprotocol": subprotocol, "message_type": "binary", "message_sha256": payload_hash, "echo_sha256": hashlib.sha256(echo).hexdigest(), "close_code": close_code, "no_response_observed": False})
            return [record]
        finally:
            if sock is not raw:
                sock.close()
    except OSError as exc:
        if not expects_no_response(plan) or not is_no_response_exception(exc):
            raise
        record = base_record(plan, event="WEBSOCKET_NO_RESPONSE_OBSERVED", started=started, socket_id=socket_id, local=local, remote=remote, payload_sha256=payload_hash, byte_count=len(payload), result="PASS")
        record.update({"upgrade_status": 0, "subprotocol": subprotocol, "message_type": "binary", "message_sha256": payload_hash, "echo_sha256": hashlib.sha256(b"").hexdigest(), "close_code": 0, "no_response_observed": True, "no_response_reason": no_response_reason(exc)})
        return [record]
    finally:
        if raw is not None:
            raw.close()
