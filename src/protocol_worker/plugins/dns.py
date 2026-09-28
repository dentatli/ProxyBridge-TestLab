from __future__ import annotations

import hashlib
import ipaddress
import json
import socket
import struct
import time
from typing import Any

from model import WorkerContractError, WorkerPlan
from plugins.common import base_record, expects_no_response, is_no_response_exception, no_response_reason, required_parameter, required_port


def _encode_name(name: str) -> bytes:
    try:
        labels = name.rstrip(".").split(".")
        encoded = b"".join(bytes([len(label.encode("ascii"))]) + label.encode("ascii") for label in labels) + b"\x00"
    except (UnicodeEncodeError, ValueError) as exc:
        raise WorkerContractError("DNS_QUERY_NAME_INVALID") from exc
    if any(not label or len(label.encode("ascii")) > 63 for label in labels) or len(encoded) > 255:
        raise WorkerContractError("DNS_QUERY_NAME_INVALID")
    return encoded


def _skip_name(message: bytes, offset: int) -> int:
    while True:
        if offset >= len(message):
            raise WorkerContractError("DNS_RESPONSE_TRUNCATED")
        length = message[offset]
        if length & 0xC0 == 0xC0:
            if offset + 2 > len(message):
                raise WorkerContractError("DNS_RESPONSE_TRUNCATED")
            return offset + 2
        offset += 1
        if length == 0:
            return offset
        if length > 63 or offset + length > len(message):
            raise WorkerContractError("DNS_RESPONSE_NAME_INVALID")
        offset += length


def _parse_response(message: bytes, expected_id: int) -> tuple[int, bool, list[str]]:
    if len(message) < 12:
        raise WorkerContractError("DNS_RESPONSE_TRUNCATED")
    query_id, flags, question_count, answer_count, _, _ = struct.unpack("!HHHHHH", message[:12])
    if query_id != expected_id or not flags & 0x8000 or question_count != 1:
        raise WorkerContractError("DNS_RESPONSE_IDENTITY_INVALID")
    offset = _skip_name(message, 12)
    if offset + 4 > len(message):
        raise WorkerContractError("DNS_RESPONSE_TRUNCATED")
    offset += 4
    answers: list[str] = []
    for _ in range(answer_count):
        offset = _skip_name(message, offset)
        if offset + 10 > len(message):
            raise WorkerContractError("DNS_RESPONSE_TRUNCATED")
        record_type, _, _, length = struct.unpack("!HHIH", message[offset : offset + 10])
        offset += 10
        data = message[offset : offset + length]
        offset += length
        if len(data) != length:
            raise WorkerContractError("DNS_RESPONSE_TRUNCATED")
        if record_type == 1 and length == 4:
            answers.append(str(ipaddress.IPv4Address(data)))
        elif record_type == 28 and length == 16:
            answers.append(str(ipaddress.IPv6Address(data)))
    return flags & 0xF, bool(flags & 0x0200), answers


def _read_exact(sock: socket.socket, length: int) -> bytes:
    value = bytearray()
    while len(value) < length:
        chunk = sock.recv(length - len(value))
        if not chunk:
            raise WorkerContractError("DNS_TCP_RESPONSE_EOF")
        value.extend(chunk)
    return bytes(value)


def run_dns(plan: WorkerPlan) -> list[dict[str, Any]]:
    started = time.monotonic()
    host = required_parameter(plan, "remote_host", str)
    port = required_port(plan)
    dns_transport = required_parameter(plan, "dns_transport", str).upper()
    query_name = required_parameter(plan, "query_name", str).lower()
    query_type_name = required_parameter(plan, "query_type", str).upper()
    if dns_transport not in {"UDP", "TCP"} or dns_transport != plan.transport:
        raise WorkerContractError("DNS_TRANSPORT_INVALID")
    query_type = {"A": 1, "AAAA": 28}.get(query_type_name)
    if query_type is None:
        raise WorkerContractError("DNS_QUERY_TYPE_INVALID")
    marker = f"{plan.raw['run_id']}|{plan.raw['scenario_id']}|{plan.raw['attempt_id']}|{plan.raw['flow_id']}".encode("utf-8")
    payload_hash = hashlib.sha256(marker).hexdigest()
    query_id = int.from_bytes(hashlib.sha256(marker).digest()[:2], "big")
    metadata = json.dumps({
        "run_id": plan.raw["run_id"], "scenario_id": plan.raw["scenario_id"], "attempt_id": plan.raw["attempt_id"],
        "flow_id": plan.raw["flow_id"], "protocol_family": plan.protocol_family, "payload_sha256": payload_hash,
    }, sort_keys=True, separators=(",", ":")).encode("utf-8")
    option = struct.pack("!HH", 65001, len(metadata)) + metadata
    query = struct.pack("!HHHHHH", query_id, 0x0100, 1, 0, 0, 1) + _encode_name(query_name) + struct.pack("!HH", query_type, 1) + b"\x00" + struct.pack("!HHIH", 41, 1232, 0, len(option)) + option
    timeout = plan.raw["operation_timeout_ms"] / 1000.0
    local: Any = None
    remote: Any = None
    socket_id = 0
    try:
        if dns_transport == "TCP":
            with socket.create_connection((host, port), timeout=timeout) as sock:
                sock.settimeout(timeout)
                socket_id = sock.fileno()
                local, remote = sock.getsockname(), sock.getpeername()
                sock.sendall(struct.pack("!H", len(query)) + query)
                response_length = struct.unpack("!H", _read_exact(sock, 2))[0]
                response = _read_exact(sock, response_length)
        else:
            address = socket.getaddrinfo(host, port, type=socket.SOCK_DGRAM)[0]
            with socket.socket(address[0], socket.SOCK_DGRAM) as sock:
                sock.settimeout(timeout)
                sock.connect(address[4])
                socket_id = sock.fileno()
                local, remote = sock.getsockname(), sock.getpeername()
                sock.send(query)
                response = sock.recv(65535)
    except OSError as exc:
        if not expects_no_response(plan) or not is_no_response_exception(exc):
            raise
        answer_digest = hashlib.sha256(b"").hexdigest()
        record = base_record(plan, event="DNS_NO_RESPONSE_OBSERVED", started=started, socket_id=socket_id, local=local, remote=remote, payload_sha256=payload_hash, byte_count=len(query), result="PASS")
        record.update({"dns_transport": dns_transport, "query_id": query_id, "query_name": query_name, "query_type": query_type, "response_code": -1, "answer_digest": answer_digest, "truncated": False, "dnssec_status": "NOT_OBSERVED", "no_response_observed": True, "no_response_reason": no_response_reason(exc)})
        return [record]
    response_code, truncated, answers = _parse_response(response, query_id)
    expected_code = int(plan.raw["expected"].get("response_code", 0))
    expected_answers = sorted(str(item) for item in plan.raw["expected"].get("answers", []))
    normalized_answers = sorted(answers)
    result = "PASS" if not expects_no_response(plan) and response_code == expected_code and normalized_answers == expected_answers and not truncated else "FAIL"
    answer_digest = hashlib.sha256("\n".join(normalized_answers).encode("utf-8")).hexdigest()
    record = base_record(plan, event="DNS_TRANSACTION_COMPLETED", started=started, socket_id=socket_id, local=local, remote=remote, payload_sha256=payload_hash, byte_count=len(query), result=result)
    record.update({"dns_transport": dns_transport, "query_id": query_id, "query_name": query_name, "query_type": query_type, "response_code": response_code, "answer_digest": answer_digest, "truncated": truncated, "dnssec_status": "NOT_REQUESTED", "no_response_observed": False})
    return [record]
