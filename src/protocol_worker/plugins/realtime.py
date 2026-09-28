from __future__ import annotations

import base64
import hashlib
import hmac
import json
import socket
import struct
import time
from typing import Any

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from model import WorkerContractError, WorkerPlan
from plugins.common import base_record, expects_no_response, is_no_response_exception, no_response_reason, required_parameter, required_port


MAGIC_COOKIE = 0x2112A442
STUN_BINDING_REQUEST = 0x0001
STUN_BINDING_SUCCESS = 0x0101
TURN_ALLOCATE_REQUEST = 0x0003
TURN_ALLOCATE_SUCCESS = 0x0103
ATTR_USERNAME = 0x0006
ATTR_MESSAGE_INTEGRITY = 0x0008
ATTR_XOR_RELAYED_ADDRESS = 0x0016
ATTR_XOR_MAPPED_ADDRESS = 0x0020
INTEGRITY_KEY = hashlib.sha256(b"ProxyBridge-TestLab-STUN-v1").digest()


def _payload(plan: WorkerPlan, label: str) -> bytes:
    return f"{label}|{plan.raw['run_id']}|{plan.raw['scenario_id']}|{plan.raw['attempt_id']}|{plan.raw['flow_id']}".encode("utf-8")


def _metadata(plan: WorkerPlan, payload_hash: str, **extra: Any) -> bytes:
    value: dict[str, Any] = {field: str(plan.raw[field]) for field in ("run_id", "scenario_id", "attempt_id", "flow_id")}
    value["payload_sha256"] = payload_hash
    value.update(extra)
    return base64.urlsafe_b64encode(json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8"))


def _attribute(kind: int, value: bytes) -> bytes:
    padding = b"\x00" * ((4 - len(value) % 4) % 4)
    return struct.pack("!HH", kind, len(value)) + value + padding


def _stun_message(message_type: int, transaction_id: bytes, attributes: bytes, *, integrity: bool) -> bytes:
    if len(transaction_id) != 12:
        raise WorkerContractError("STUN_TRANSACTION_ID_INVALID")
    integrity_size = 24 if integrity else 0
    header = struct.pack("!HHI12s", message_type, len(attributes) + integrity_size, MAGIC_COOKIE, transaction_id)
    if not integrity:
        return header + attributes
    digest = hmac.new(INTEGRITY_KEY, header + attributes, hashlib.sha1).digest()
    return header + attributes + _attribute(ATTR_MESSAGE_INTEGRITY, digest)


def _parse_stun(data: bytes, expected_type: int, transaction_id: bytes) -> dict[int, bytes]:
    if len(data) < 20:
        raise WorkerContractError("STUN_RESPONSE_TRUNCATED")
    message_type, length, cookie, observed_transaction = struct.unpack("!HHI12s", data[:20])
    if message_type != expected_type or cookie != MAGIC_COOKIE or observed_transaction != transaction_id or length != len(data) - 20 or length % 4:
        raise WorkerContractError("STUN_RESPONSE_INVALID")
    result: dict[int, bytes] = {}
    offset = 20
    integrity_offset = -1
    while offset < len(data):
        if offset + 4 > len(data):
            raise WorkerContractError("STUN_ATTRIBUTE_TRUNCATED")
        kind, size = struct.unpack("!HH", data[offset : offset + 4])
        end = offset + 4 + size
        if end > len(data):
            raise WorkerContractError("STUN_ATTRIBUTE_TRUNCATED")
        if kind == ATTR_MESSAGE_INTEGRITY:
            integrity_offset = offset
        result[kind] = data[offset + 4 : end]
        offset = end + ((4 - size % 4) % 4)
    integrity_value = result.get(ATTR_MESSAGE_INTEGRITY)
    if integrity_offset < 0 or integrity_value is None or len(integrity_value) != 20:
        raise WorkerContractError("STUN_INTEGRITY_MISSING")
    expected = hmac.new(INTEGRITY_KEY, data[:integrity_offset], hashlib.sha1).digest()
    if not hmac.compare_digest(expected, integrity_value):
        raise WorkerContractError("STUN_INTEGRITY_INVALID")
    return result


def _xor_address(value: bytes, transaction_id: bytes) -> tuple[str, int]:
    if len(value) != 8 or value[1] != 1:
        raise WorkerContractError("STUN_XOR_ADDRESS_INVALID")
    port = struct.unpack("!H", value[2:4])[0] ^ (MAGIC_COOKIE >> 16)
    mask = struct.pack("!I", MAGIC_COOKIE)
    address = socket.inet_ntoa(bytes(left ^ right for left, right in zip(value[4:8], mask)))
    return address, port


def run_realtime(plan: WorkerPlan) -> list[dict[str, Any]]:
    started = time.monotonic()
    mode = required_parameter(plan, "ice_protocol", str).upper()
    if mode not in {"STUN", "TURN"}:
        raise WorkerContractError("REALTIME_PROTOCOL_INVALID")
    payload = _payload(plan, mode.lower())
    payload_hash = hashlib.sha256(payload).hexdigest()
    transaction_id = hashlib.sha256(payload + b"|transaction").digest()[:12]
    request_type = STUN_BINDING_REQUEST if mode == "STUN" else TURN_ALLOCATE_REQUEST
    response_type = STUN_BINDING_SUCCESS if mode == "STUN" else TURN_ALLOCATE_SUCCESS
    method = "BINDING" if mode == "STUN" else "ALLOCATE"
    metadata = _metadata(plan, payload_hash)
    request = _stun_message(request_type, transaction_id, _attribute(ATTR_USERNAME, metadata), integrity=True)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(plan.raw["operation_timeout_ms"] / 1000.0)
    try:
        sock.connect((required_parameter(plan, "remote_host", str), required_port(plan)))
        sock.send(request)
        response = sock.recv(4096)
        attributes = _parse_stun(response, response_type, transaction_id)
        mapped = _xor_address(attributes.get(ATTR_XOR_MAPPED_ADDRESS, b""), transaction_id)
        relayed = _xor_address(attributes[ATTR_XOR_RELAYED_ADDRESS], transaction_id) if mode == "TURN" and ATTR_XOR_RELAYED_ADDRESS in attributes else None
        result = "PASS" if not expects_no_response(plan) and (mode == "STUN" or relayed is not None) else "FAIL"
        record = base_record(plan, event=f"{mode}_TRANSACTION_COMPLETED", started=started, socket_id=sock.fileno(), local=sock.getsockname(), remote=sock.getpeername(), payload_sha256=payload_hash, byte_count=len(request), result=result)
        record.update({
            "ice_protocol": mode,
            "transaction_id": transaction_id.hex(),
            "method": method,
            "mapped_address_digest": hashlib.sha256(f"{mapped[0]}:{mapped[1]}".encode("ascii")).hexdigest(),
            "relay_address_digest": hashlib.sha256(f"{relayed[0]}:{relayed[1]}".encode("ascii")).hexdigest() if relayed else hashlib.sha256(b"").hexdigest(),
            "integrity_verified": True,
            "no_response_observed": False,
        })
        return [record]
    except OSError as exc:
        if not expects_no_response(plan) or not is_no_response_exception(exc):
            raise
        record = base_record(plan, event=f"{mode}_NO_RESPONSE_OBSERVED", started=started, socket_id=sock.fileno(), local=sock.getsockname() if sock.fileno() >= 0 else None, remote=None, payload_sha256=payload_hash, byte_count=len(request), result="PASS")
        record.update({"ice_protocol": mode, "transaction_id": transaction_id.hex(), "method": method, "mapped_address_digest": hashlib.sha256(b"").hexdigest(), "relay_address_digest": hashlib.sha256(b"").hexdigest(), "integrity_verified": False, "no_response_observed": True, "no_response_reason": no_response_reason(exc)})
        return [record]
    finally:
        sock.close()


def _srtp_key(ssrc: int) -> bytes:
    return hashlib.sha256(b"ProxyBridge-TestLab-SRTP-key-v1|" + struct.pack("!I", ssrc)).digest()[:16]


def _srtp_nonce(ssrc: int, sequence: int) -> bytes:
    return b"\x00\x00" + struct.pack("!I", ssrc) + b"\x00\x00\x00\x00" + struct.pack("!H", sequence)


def run_media(plan: WorkerPlan) -> list[dict[str, Any]]:
    started = time.monotonic()
    payload = _payload(plan, "srtp-media")
    packet_count = plan.raw["parameters"].get("packet_count", 12)
    if isinstance(packet_count, bool) or not isinstance(packet_count, int) or packet_count < 2 or packet_count > 200:
        raise WorkerContractError("MEDIA_PACKET_COUNT_INVALID")
    ssrc = struct.unpack("!I", hashlib.sha256(str(plan.raw["flow_id"]).encode("ascii")).digest()[:4])[0] or 1
    frames = [hashlib.sha256(payload + struct.pack("!H", sequence)).digest() * 5 for sequence in range(packet_count)]
    media = b"".join(frames)
    media_digest = hashlib.sha256(media).hexdigest()
    metadata = _metadata(plan, media_digest, packet_count=packet_count)
    aes = AESGCM(_srtp_key(ssrc))
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(plan.raw["operation_timeout_ms"] / 1000.0)
    try:
        sock.connect((required_parameter(plan, "remote_host", str), required_port(plan)))
        for sequence, frame in enumerate(frames):
            header = struct.pack("!BBHII", 0x80, 111, sequence, sequence * 960, ssrc)
            plaintext = struct.pack("!H", len(metadata) if sequence == 0 else 0) + (metadata if sequence == 0 else b"") + frame
            sock.send(header + aes.encrypt(_srtp_nonce(ssrc, sequence), plaintext, header))
        report = sock.recv(4096)
        if len(report) < 16 or report[1] != 204 or report[8:12] != b"PBTS" or struct.unpack("!I", report[4:8])[0] != ssrc:
            raise WorkerContractError("RTCP_REPORT_INVALID")
        report_data = json.loads(report[12:].rstrip(b"\x00").decode("utf-8"))
        complete = report_data.get("media_digest") == media_digest and report_data.get("packet_count") == packet_count and report_data.get("sequence_gap_count") == 0
        result = "PASS" if not expects_no_response(plan) and complete else "FAIL"
        record = base_record(plan, event="SRTP_MEDIA_COMPLETED", started=started, socket_id=sock.fileno(), local=sock.getsockname(), remote=sock.getpeername(), payload_sha256=media_digest, byte_count=len(media), result=result)
        record.update({"ssrc": ssrc, "payload_type": 111, "packet_count": packet_count, "sequence_gap_count": int(report_data.get("sequence_gap_count", -1)), "jitter_ms": int(report_data.get("jitter_ms", 0)), "rtcp_status": "RECEIVER_REPORT", "media_digest": media_digest, "no_response_observed": False})
        return [record]
    except OSError as exc:
        if not expects_no_response(plan) or not is_no_response_exception(exc):
            raise
        record = base_record(plan, event="SRTP_NO_RESPONSE_OBSERVED", started=started, socket_id=sock.fileno(), local=sock.getsockname() if sock.fileno() >= 0 else None, remote=None, payload_sha256=media_digest, byte_count=len(media), result="PASS")
        record.update({"ssrc": ssrc, "payload_type": 111, "packet_count": packet_count, "sequence_gap_count": packet_count, "jitter_ms": 0, "rtcp_status": "NOT_OBSERVED", "media_digest": media_digest, "no_response_observed": True, "no_response_reason": no_response_reason(exc)})
        return [record]
    finally:
        sock.close()


def run_receive_only(plan: WorkerPlan) -> list[dict[str, Any]]:
    started = time.monotonic()
    payload = _payload(plan, "receive-only")
    payload_hash = hashlib.sha256(payload).hexdigest()
    registration_id = hashlib.sha256(payload + b"|registration").hexdigest()[:24]
    metadata = _metadata(plan, payload_hash, registration_id=registration_id)
    registration = b"PBRO1" + struct.pack("!H", len(metadata)) + metadata
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(plan.raw["operation_timeout_ms"] / 1000.0)
    try:
        sock.connect((required_parameter(plan, "remote_host", str), required_port(plan)))
        sock.send(registration)
        received = sock.recv(4096)
        valid = received == b"PBRO2" + payload
        result = "PASS" if not expects_no_response(plan) and valid else "FAIL"
        local = sock.getsockname()
        record = base_record(plan, event="UDP_SERVER_INITIATED_RECEIVED", started=started, socket_id=sock.fileno(), local=local, remote=sock.getpeername(), payload_sha256=payload_hash, byte_count=len(payload), result=result)
        record.update({
            "registration_id": registration_id,
            "registration_sent": True,
            "server_initiated": True,
            "message_sha256": payload_hash,
            "nat_mapping_digest": hashlib.sha256(f"{local[0]}:{local[1]}".encode("ascii")).hexdigest(),
            "no_response_observed": False,
        })
        return [record]
    except OSError as exc:
        if not expects_no_response(plan) or not is_no_response_exception(exc):
            raise
        local = sock.getsockname() if sock.fileno() >= 0 else None
        record = base_record(plan, event="UDP_SERVER_INITIATED_NOT_OBSERVED", started=started, socket_id=sock.fileno(), local=local, remote=None, payload_sha256=payload_hash, byte_count=len(payload), result="PASS")
        record.update({"registration_id": registration_id, "registration_sent": True, "server_initiated": False, "message_sha256": payload_hash, "nat_mapping_digest": hashlib.sha256(b"").hexdigest(), "no_response_observed": True, "no_response_reason": no_response_reason(exc)})
        return [record]
    finally:
        sock.close()
