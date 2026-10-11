"""Native protocol envelopes; authentication is carried inside each application message."""
from __future__ import annotations
import hashlib
import json
import secrets
import struct
from typing import Any
from trafficlab.protocol import ID, MAX_LINE, json_bytes, mac, verify_mac

APPLICATION_PORTS = {"http": 42511, "tls": 42512, "https": 42513, "websocket": 42514,
                     "dns-tcp": 42515, "dns-udp": 42515, "ssh": 42516, "sftp": 42517,
                     "http2": 42518, "grpc": 42519, "quic": 42520, "http3": 42521,
                     "smtp": 42522, "smtps": 42523, "imap": 42524, "imaps": 42525, "mqtt": 42526, "mqtts": 42527,
                     "pop3": 42528, "pop3s": 42529, "amqp": 42530, "amqps": 42531}
SERVER_NAME = "traffic.testlab.invalid"
WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


def request(secret: bytes, kind: str, run_id: str, flow_id: str, sequence: int, digest: str) -> dict[str, Any]:
    value = {"application": kind, "run_id": run_id, "flow_id": flow_id,
             "sequence": sequence, "payload_sha256": digest}
    value["proof"] = mac(secret, b"application-request:", json_bytes(value))
    return value


def validate(secret: bytes, value: dict[str, Any], kind: str) -> dict[str, Any]:
    value = dict(value)
    proof = value.pop("proof", "")
    if set(value) != {"application", "run_id", "flow_id", "sequence", "payload_sha256"} or value["application"] != kind:
        raise ValueError("APPLICATION_IDENTITY_INVALID")
    if not all(isinstance(value[key], str) and ID.fullmatch(value[key]) for key in ("run_id", "flow_id")):
        raise ValueError("APPLICATION_IDENTITY_INVALID")
    if type(value["sequence"]) is not int or not 0 <= value["sequence"] < 2 ** 48:
        raise ValueError("APPLICATION_SEQUENCE_INVALID")
    if not isinstance(value["payload_sha256"], str) or len(value["payload_sha256"]) != 64:
        raise ValueError("APPLICATION_PAYLOAD_INVALID")
    verify_mac(secret, b"application-request:", json_bytes(value), proof)
    return value


def response(secret: bytes, value: dict[str, Any], peer: list[Any], payload: str | None = None) -> dict[str, Any]:
    result = {"peer": peer, "payload_sha256": value["payload_sha256"]}
    if payload is not None:
        result["payload"] = payload
    result["proof"] = mac(secret, b"application-response:", json_bytes(value) + json_bytes(result))
    return result


def verify_response(secret: bytes, value: dict[str, Any], result: dict[str, Any]) -> list[Any]:
    result = dict(result)
    proof = result.pop("proof", "")
    if result.get("payload_sha256") != value["payload_sha256"] or not isinstance(result.get("peer"), list) or len(result["peer"]) != 2:
        raise ValueError("APPLICATION_RESPONSE_INVALID")
    verify_mac(secret, b"application-response:", json_bytes({key: item for key, item in value.items() if key != "proof"}) + json_bytes(result), proof)
    return result["peer"]


def run_tag(run_id: str) -> str:
    return hashlib.sha256(run_id.encode("ascii")).hexdigest()[:32]


def dns_request(secret: bytes, run_id: str, flow_id: str, sequence: int) -> tuple[bytes, dict[str, Any]]:
    tag = run_tag(run_id)
    name = f"{tag}.{flow_id}.{sequence:x}.pb.test"
    digest = hashlib.sha256(json_bytes({"query_name": name, "query_type": "A"})).hexdigest()
    value = request(secret, "dns", run_id, flow_id, sequence, digest)
    labels = [tag, flow_id, f"{sequence:x}", value["proof"][:32], value["proof"][32:], "pb", "test"]
    qname = b"".join(bytes([len(label)]) + label.encode("ascii") for label in labels) + b"\0"
    question = qname + struct.pack("!HH", 1, 1)
    return struct.pack("!6H", secrets.randbelow(65536), 0x0100, 1, 0, 0, 0) + question, value


def dns_decode(packet: bytes, runs: Any) -> tuple[dict[str, Any], bytes]:
    if len(packet) > 512 or len(packet) < 17:
        raise ValueError("APPLICATION_DNS_LENGTH_INVALID")
    _xid, flags, qd, an, ns, ar = struct.unpack("!6H", packet[:12])
    if flags not in (0, 0x0100) or (qd, an, ns, ar) != (1, 0, 0, 0):
        raise ValueError("APPLICATION_DNS_HEADER_INVALID")
    offset, labels = 12, []
    while True:
        size = packet[offset]
        offset += 1
        if not size:
            break
        if size > 63 or offset + size > len(packet) or len(labels) >= 7:
            raise ValueError("APPLICATION_DNS_NAME_INVALID")
        labels.append(packet[offset:offset + size].decode("ascii"))
        offset += size
    if len(labels) != 7 or labels[-2:] != ["pb", "test"] or packet[offset:] != b"\0\1\0\1":
        raise ValueError("APPLICATION_DNS_QUESTION_INVALID")
    run_id = next((key for key in runs if run_tag(key) == labels[0]), None)
    if run_id is None:
        raise ValueError("APPLICATION_DNS_SESSION_UNKNOWN")
    sequence = int(labels[2], 16)
    name = f"{labels[0]}.{labels[1]}.{sequence:x}.pb.test"
    value = {"application": "dns", "run_id": run_id, "flow_id": labels[1], "sequence": sequence,
             "payload_sha256": hashlib.sha256(json_bytes({"query_name": name, "query_type": "A"})).hexdigest(),
             "proof": labels[3] + labels[4]}
    return value, packet[12:]


def dns_response(packet: bytes, question: bytes, result: dict[str, Any]) -> bytes:
    txt = json_bytes(result)
    if len(txt) > 255:
        raise ValueError("APPLICATION_DNS_RESPONSE_TOO_LARGE")
    answers = b"\xc0\x0c" + struct.pack("!HHIH", 1, 1, 0, 4) + b"\xc0\x00\x02\x0a"
    answers += b"\xc0\x0c" + struct.pack("!HHIH", 16, 1, 0, len(txt) + 1) + bytes([len(txt)]) + txt
    reply = packet[:2] + struct.pack("!5H", 0x8500, 1, 2, 0, 0) + question + answers
    if len(reply) > 512:
        raise ValueError("APPLICATION_DNS_RESPONSE_TOO_LARGE")
    return reply


def dns_verify(packet: bytes, reply: bytes) -> dict[str, Any]:
    if len(reply) < len(packet) + 29 or reply[:2] != packet[:2] or reply[2:12] != struct.pack("!5H", 0x8500, 1, 2, 0, 0) or reply[12:len(packet)] != packet[12:]:
        raise ValueError("APPLICATION_DNS_RESPONSE_INVALID")
    offset = len(packet)
    if reply[offset:offset + 16] != b"\xc0\x0c" + struct.pack("!HHIH", 1, 1, 0, 4) + b"\xc0\x00\x02\x0a":
        raise ValueError("APPLICATION_DNS_ANSWER_INVALID")
    offset += 16
    if reply[offset:offset + 10] != b"\xc0\x0c" + struct.pack("!HHI", 16, 1, 0):
        raise ValueError("APPLICATION_DNS_PROOF_INVALID")
    size = struct.unpack("!H", reply[offset + 10:offset + 12])[0]
    body = reply[offset + 12:]
    if len(body) != size or not body or body[0] != len(body) - 1:
        raise ValueError("APPLICATION_DNS_PROOF_INVALID")
    return json.loads(body[1:])


def websocket_frame(payload: bytes, masked: bool, opcode: int = 2) -> bytes:
    if len(payload) > MAX_LINE or opcode not in (2, 8, 9, 10):
        raise ValueError("APPLICATION_WEBSOCKET_FRAME_INVALID")
    length = len(payload)
    header = bytes([0x80 | opcode, (0x80 if masked else 0) | (length if length < 126 else 126)])
    if length >= 126:
        header += struct.pack("!H", length)
    if not masked:
        return header + payload
    key = secrets.token_bytes(4)
    return header + key + bytes(byte ^ key[index % 4] for index, byte in enumerate(payload))
