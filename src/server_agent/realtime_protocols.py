from __future__ import annotations

import asyncio
import base64
import hashlib
import hmac
import json
import os
import socket
import struct
from datetime import datetime, timezone
from typing import Any, Callable

from cryptography.hazmat.primitives.ciphers.aead import AESGCM


MAGIC_COOKIE = 0x2112A442
ATTR_USERNAME = 0x0006
ATTR_MESSAGE_INTEGRITY = 0x0008
ATTR_XOR_RELAYED_ADDRESS = 0x0016
ATTR_XOR_MAPPED_ADDRESS = 0x0020
INTEGRITY_KEY = hashlib.sha256(b"ProxyBridge-TestLab-STUN-v1").digest()


def _utc() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _sha(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _decode_metadata(value: bytes) -> dict[str, str]:
    parsed = json.loads(base64.urlsafe_b64decode(value).decode("utf-8"))
    if not isinstance(parsed, dict):
        raise ValueError("METADATA_INVALID")
    result = {str(key): str(item) for key, item in parsed.items()}
    for field in ("run_id", "scenario_id", "attempt_id", "flow_id", "payload_sha256"):
        if not result.get(field):
            raise ValueError("METADATA_MISSING")
    return result


def _record(metadata: dict[str, str], family: str, transport: str, local: Any, remote: Any, payload_hash: str, byte_count: int, fields: dict[str, Any]) -> dict[str, Any]:
    value: dict[str, Any] = {
        "schema_version": 1, "run_id": metadata["run_id"], "scenario_id": metadata["scenario_id"],
        "attempt_id": metadata["attempt_id"], "flow_id": metadata["flow_id"], "phase": "server",
        "sequence": 1, "event": "PROTOCOL_REQUEST_RECEIVED", "timestamp_utc": _utc(), "monotonic_ms": 0,
        "process_id": os.getpid(), "socket_id": 0, "protocol_family": family, "transport": transport,
        "local_ip": str(local[0]) if local else "", "local_port": int(local[1]) if local else 0,
        "remote_ip": str(remote[0]) if remote else "", "remote_port": int(remote[1]) if remote else 0,
        "payload_sha256": payload_hash, "bytes": byte_count, "result": "PASS",
    }
    value.update(fields)
    return value


def _attribute(kind: int, value: bytes) -> bytes:
    return struct.pack("!HH", kind, len(value)) + value + b"\x00" * ((4 - len(value) % 4) % 4)


def _xor_address(address: tuple[str, int]) -> bytes:
    port = address[1] ^ (MAGIC_COOKIE >> 16)
    mask = struct.pack("!I", MAGIC_COOKIE)
    encoded = bytes(left ^ right for left, right in zip(socket.inet_aton(address[0]), mask))
    return b"\x00\x01" + struct.pack("!H", port) + encoded


def _parse_stun(data: bytes) -> tuple[int, bytes, dict[int, bytes], int]:
    if len(data) < 20:
        raise ValueError("STUN_TRUNCATED")
    message_type, length, cookie, transaction = struct.unpack("!HHI12s", data[:20])
    if cookie != MAGIC_COOKIE or length != len(data) - 20 or length % 4:
        raise ValueError("STUN_INVALID")
    attributes: dict[int, bytes] = {}
    offset = 20
    integrity_offset = -1
    while offset < len(data):
        kind, size = struct.unpack("!HH", data[offset : offset + 4])
        end = offset + 4 + size
        if end > len(data):
            raise ValueError("STUN_ATTRIBUTE_INVALID")
        if kind == ATTR_MESSAGE_INTEGRITY:
            integrity_offset = offset
        attributes[kind] = data[offset + 4 : end]
        offset = end + ((4 - size % 4) % 4)
    integrity = attributes.get(ATTR_MESSAGE_INTEGRITY, b"")
    if integrity_offset < 0 or len(integrity) != 20 or not hmac.compare_digest(hmac.new(INTEGRITY_KEY, data[:integrity_offset], hashlib.sha1).digest(), integrity):
        raise ValueError("STUN_INTEGRITY_INVALID")
    return message_type, transaction, attributes, integrity_offset


def _stun_response(message_type: int, transaction: bytes, attributes: bytes) -> bytes:
    header = struct.pack("!HHI12s", message_type, len(attributes) + 24, MAGIC_COOKIE, transaction)
    integrity = hmac.new(INTEGRITY_KEY, header + attributes, hashlib.sha1).digest()
    return header + attributes + _attribute(ATTR_MESSAGE_INTEGRITY, integrity)


class StunTurnProtocol(asyncio.DatagramProtocol):
    def __init__(self, evidence: Callable[[dict[str, Any]], None], relay_port: int) -> None:
        self.evidence = evidence
        self.relay_port = relay_port
        self.transport: asyncio.DatagramTransport | None = None

    def connection_made(self, transport: asyncio.BaseTransport) -> None:
        self.transport = transport  # type: ignore[assignment]

    def datagram_received(self, data: bytes, address: Any) -> None:
        if self.transport is None:
            return
        try:
            message_type, transaction, attributes, _ = _parse_stun(data)
            metadata = _decode_metadata(attributes[ATTR_USERNAME])
            if message_type == 0x0001:
                mode, response_type, method = "STUN", 0x0101, "BINDING"
                response_attributes = _attribute(ATTR_XOR_MAPPED_ADDRESS, _xor_address(address))
                relay_digest = _sha(b"")
            elif message_type == 0x0003:
                mode, response_type, method = "TURN", 0x0103, "ALLOCATE"
                relay = (self.transport.get_extra_info("sockname")[0], self.relay_port)
                response_attributes = _attribute(ATTR_XOR_RELAYED_ADDRESS, _xor_address(relay)) + _attribute(ATTR_XOR_MAPPED_ADDRESS, _xor_address(address))
                relay_digest = _sha(f"{relay[0]}:{relay[1]}".encode("ascii"))
            else:
                return
            self.transport.sendto(_stun_response(response_type, transaction, response_attributes), address)
            local = self.transport.get_extra_info("sockname")
            self.evidence(_record(metadata, "stun-turn", "UDP", local, address, metadata["payload_sha256"], len(data), {
                "ice_protocol": mode, "transaction_id": transaction.hex(), "method": method,
                "mapped_address_digest": _sha(f"{address[0]}:{address[1]}".encode("ascii")),
                "relay_address_digest": relay_digest, "integrity_verified": True,
            }))
        except (KeyError, ValueError, UnicodeDecodeError, OSError):
            return


def _srtp_key(ssrc: int) -> bytes:
    return hashlib.sha256(b"ProxyBridge-TestLab-SRTP-key-v1|" + struct.pack("!I", ssrc)).digest()[:16]


def _srtp_nonce(ssrc: int, sequence: int) -> bytes:
    return b"\x00\x00" + struct.pack("!I", ssrc) + b"\x00\x00\x00\x00" + struct.pack("!H", sequence)


class MediaProtocol(asyncio.DatagramProtocol):
    def __init__(self, evidence: Callable[[dict[str, Any]], None]) -> None:
        self.evidence = evidence
        self.transport: asyncio.DatagramTransport | None = None
        self.sessions: dict[tuple[Any, int], dict[str, Any]] = {}

    def connection_made(self, transport: asyncio.BaseTransport) -> None:
        self.transport = transport  # type: ignore[assignment]

    def datagram_received(self, data: bytes, address: Any) -> None:
        if self.transport is None or len(data) < 12 + 16:
            return
        try:
            version, payload_type, sequence, _, ssrc = struct.unpack("!BBHII", data[:12])
            if version != 0x80 or payload_type != 111:
                return
            plaintext = AESGCM(_srtp_key(ssrc)).decrypt(_srtp_nonce(ssrc, sequence), data[12:], data[:12])
            metadata_length = struct.unpack("!H", plaintext[:2])[0]
            offset = 2
            metadata = _decode_metadata(plaintext[offset : offset + metadata_length]) if metadata_length else None
            offset += metadata_length
            frame = plaintext[offset:]
            key = (address, ssrc)
            state = self.sessions.setdefault(key, {"metadata": None, "frames": {}, "first": datetime.now(timezone.utc)})
            if metadata is not None:
                state["metadata"] = metadata
            state["frames"][sequence] = frame
            active = state["metadata"]
            if active is None:
                return
            expected_count = int(active["packet_count"])
            if len(state["frames"]) < expected_count:
                return
            sequences = sorted(state["frames"])
            gaps = sum(1 for expected, observed in enumerate(sequences) if expected != observed)
            media = b"".join(state["frames"][index] for index in range(expected_count) if index in state["frames"])
            digest = _sha(media)
            report_data = json.dumps({"media_digest": digest, "packet_count": len(sequences), "sequence_gap_count": gaps, "jitter_ms": 0}, separators=(",", ":")).encode("utf-8")
            report_data += b"\x00" * ((4 - len(report_data) % 4) % 4)
            length_words = (12 + len(report_data)) // 4 - 1
            report = struct.pack("!BBH", 0x80, 204, length_words) + struct.pack("!I", ssrc) + b"PBTS" + report_data
            self.transport.sendto(report, address)
            local = self.transport.get_extra_info("sockname")
            self.evidence(_record(active, "rtp-media", "UDP", local, address, digest, len(media), {
                "ssrc": ssrc, "payload_type": 111, "packet_count": len(sequences), "sequence_gap_count": gaps,
                "jitter_ms": 0, "rtcp_status": "RECEIVER_REPORT", "media_digest": digest,
            }))
            self.sessions.pop(key, None)
        except (KeyError, ValueError, UnicodeDecodeError, struct.error):
            return


class ReceiveOnlyProtocol(asyncio.DatagramProtocol):
    def __init__(self, evidence: Callable[[dict[str, Any]], None]) -> None:
        self.evidence = evidence
        self.transport: asyncio.DatagramTransport | None = None

    def connection_made(self, transport: asyncio.BaseTransport) -> None:
        self.transport = transport  # type: ignore[assignment]

    def datagram_received(self, data: bytes, address: Any) -> None:
        if self.transport is None or len(data) < 7 or not data.startswith(b"PBRO1"):
            return
        try:
            length = struct.unpack("!H", data[5:7])[0]
            if length <= 0 or 7 + length != len(data):
                return
            metadata = _decode_metadata(data[7:])
            registration_id = metadata.get("registration_id", "")
            payload = f"receive-only|{metadata['run_id']}|{metadata['scenario_id']}|{metadata['attempt_id']}|{metadata['flow_id']}".encode("utf-8")
            digest = _sha(payload)
            if not registration_id or digest != metadata["payload_sha256"]:
                return
            local = self.transport.get_extra_info("sockname")
            mapping_digest = _sha(f"{address[0]}:{address[1]}".encode("ascii"))
            self.evidence(_record(metadata, "udp-receive-only", "UDP", local, address, digest, len(payload), {
                "registration_id": registration_id, "registration_sent": True, "server_initiated": True,
                "message_sha256": digest, "nat_mapping_digest": mapping_digest,
            }))
            asyncio.get_running_loop().call_later(0.05, self.transport.sendto, b"PBRO2" + payload, address)
        except (KeyError, ValueError, UnicodeDecodeError, struct.error):
            return


async def start_realtime_protocols(bind: str, config: dict[str, Any], evidence: Callable[[dict[str, Any]], None], preferred_ports: dict[str, int]) -> tuple[list[asyncio.DatagramTransport], dict[str, int]]:
    loop = asyncio.get_running_loop()
    actual: dict[str, int] = {}
    transports: list[asyncio.DatagramTransport] = []
    stun_port = preferred_ports.get("stun_turn", int(config["stun_turn"]["port"]))
    media_port = preferred_ports.get("rtp_media", int(config["rtp_media"]["port"]))
    receive_only_port = preferred_ports.get("receive_only", int(config["receive_only"]["port"]))
    media_transport, _ = await loop.create_datagram_endpoint(lambda: MediaProtocol(evidence), local_addr=(bind, media_port))
    transports.append(media_transport)  # type: ignore[arg-type]
    actual["rtp_media"] = int(media_transport.get_extra_info("sockname")[1])
    stun_transport, _ = await loop.create_datagram_endpoint(lambda: StunTurnProtocol(evidence, actual["rtp_media"]), local_addr=(bind, stun_port))
    transports.append(stun_transport)  # type: ignore[arg-type]
    actual["stun_turn"] = int(stun_transport.get_extra_info("sockname")[1])
    receive_transport, _ = await loop.create_datagram_endpoint(lambda: ReceiveOnlyProtocol(evidence), local_addr=(bind, receive_only_port))
    transports.append(receive_transport)  # type: ignore[arg-type]
    actual["receive_only"] = int(receive_transport.get_extra_info("sockname")[1])
    return transports, actual
