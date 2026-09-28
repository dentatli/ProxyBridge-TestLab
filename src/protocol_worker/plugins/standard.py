from __future__ import annotations

import base64
import hashlib
import json
import socket
import ssl
import struct
import time
from pathlib import Path
from typing import Any, BinaryIO

from model import WorkerContractError, WorkerPlan
from plugins.common import base_record, expects_no_response, is_no_response_exception, no_response_reason, required_parameter, required_port


def _payload(plan: WorkerPlan, label: str) -> bytes:
    return f"{label}|{plan.raw['run_id']}|{plan.raw['scenario_id']}|{plan.raw['attempt_id']}|{plan.raw['flow_id']}".encode("utf-8")


def _metadata(plan: WorkerPlan, payload_hash: str) -> str:
    value = {field: str(plan.raw[field]) for field in ("run_id", "scenario_id", "attempt_id", "flow_id")}
    value["payload_sha256"] = payload_hash
    return base64.urlsafe_b64encode(json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")).decode("ascii")


def _tls_context(plan: WorkerPlan) -> ssl.SSLContext:
    ca_path = Path(required_parameter(plan, "ca_path", str)).resolve()
    if not ca_path.is_file():
        raise WorkerContractError("STANDARD_CA_FILE_MISSING")
    context = ssl.create_default_context(ssl.Purpose.SERVER_AUTH, cafile=str(ca_path))
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    return context


def _connect(plan: WorkerPlan, *, use_tls: bool = False) -> socket.socket:
    host = required_parameter(plan, "remote_host", str)
    port = required_port(plan)
    timeout = plan.raw["operation_timeout_ms"] / 1000.0
    raw = socket.create_connection((host, port), timeout=timeout)
    raw.settimeout(timeout)
    if not use_tls:
        return raw
    try:
        return _tls_context(plan).wrap_socket(raw, server_hostname=required_parameter(plan, "server_name", str))
    except Exception:
        raw.close()
        raise


def _readline(stream: BinaryIO, code: str) -> bytes:
    line = stream.readline(65537)
    if not line or len(line) > 65536 or not line.endswith(b"\n"):
        raise WorkerContractError(code)
    return line.rstrip(b"\r\n")


def _sendline(sock: socket.socket, value: str) -> None:
    if any(character in value for character in "\r\n"):
        raise WorkerContractError("STANDARD_LINE_INVALID")
    sock.sendall(value.encode("utf-8") + b"\r\n")


def _no_response(plan: WorkerPlan, started: float, payload_hash: str, byte_count: int, event: str, fields: dict[str, Any], exc: BaseException) -> list[dict[str, Any]]:
    record = base_record(plan, event=event, started=started, socket_id=0, local=None, remote=None, payload_sha256=payload_hash, byte_count=byte_count, result="PASS")
    fields.update({"no_response_observed": True, "no_response_reason": no_response_reason(exc)})
    record.update(fields)
    return [record]


def run_ftp(plan: WorkerPlan) -> list[dict[str, Any]]:
    started = time.monotonic()
    payload = _payload(plan, "ftp")
    payload_hash = hashlib.sha256(payload).hexdigest()
    secure = bool(plan.raw["parameters"].get("use_tls", False))
    sock: socket.socket | None = None
    try:
        sock = _connect(plan)
        stream = sock.makefile("rb")
        if not _readline(stream, "FTP_BANNER_INVALID").startswith(b"220 "):
            raise WorkerContractError("FTP_BANNER_INVALID")
        if secure:
            _sendline(sock, "AUTH TLS")
            if not _readline(stream, "FTPS_AUTH_INVALID").startswith(b"234 "):
                raise WorkerContractError("FTPS_AUTH_INVALID")
            stream.close()
            sock = _tls_context(plan).wrap_socket(sock, server_hostname=required_parameter(plan, "server_name", str))
            stream = sock.makefile("rb")
        for command, expected in (("USER anonymous", b"331 "), ("PASS testlab@invalid", b"230 "), (f"SITE TESTLAB {_metadata(plan, payload_hash)}", b"200 "), ("TYPE I", b"200 ")):
            _sendline(sock, command)
            if not _readline(stream, "FTP_CONTROL_STATUS_INVALID").startswith(expected):
                raise WorkerContractError("FTP_CONTROL_STATUS_INVALID")
        if secure:
            for command in ("PBSZ 0", "PROT P"):
                _sendline(sock, command)
                if not _readline(stream, "FTPS_PROTECTION_INVALID").startswith(b"200 "):
                    raise WorkerContractError("FTPS_PROTECTION_INVALID")
        _sendline(sock, "EPSV")
        epsv = _readline(stream, "FTP_EPSV_INVALID").decode("ascii")
        if not epsv.startswith("229 ") or "|||" not in epsv:
            raise WorkerContractError("FTP_EPSV_INVALID")
        try:
            data_port = int(epsv.split("|||", 1)[1].split("|", 1)[0])
        except (ValueError, IndexError) as exc:
            raise WorkerContractError("FTP_EPSV_INVALID") from exc
        data = socket.create_connection((required_parameter(plan, "remote_host", str), data_port), timeout=plan.raw["operation_timeout_ms"] / 1000.0)
        try:
            data.settimeout(plan.raw["operation_timeout_ms"] / 1000.0)
            _sendline(sock, "STOR probe.bin")
            if not _readline(stream, "FTP_TRANSFER_STATUS_INVALID").startswith(b"150 "):
                raise WorkerContractError("FTP_TRANSFER_STATUS_INVALID")
            if secure:
                data = _tls_context(plan).wrap_socket(data, server_hostname=required_parameter(plan, "server_name", str))
            data.sendall(payload)
            data.shutdown(socket.SHUT_WR)
        finally:
            data.close()
        if not _readline(stream, "FTP_TRANSFER_STATUS_INVALID").startswith(b"226 "):
            raise WorkerContractError("FTP_TRANSFER_STATUS_INVALID")
        _sendline(sock, "QUIT")
        control_status = _readline(stream, "FTP_QUIT_INVALID").decode("ascii")[:3]
        result = "PASS" if not expects_no_response(plan) and control_status == "221" else "FAIL"
        record = base_record(plan, event="FTP_TRANSFER_COMPLETED", started=started, socket_id=sock.fileno(), local=sock.getsockname(), remote=sock.getpeername(), payload_sha256=payload_hash, byte_count=len(payload), result=result)
        record.update({"file_protocol": "FTPS" if secure else "FTP", "operation": "UPLOAD", "content_sha256": payload_hash, "transferred_bytes": len(payload), "control_status": control_status, "data_channel_status": "TLS_PROTECTED" if secure else "CLEAR", "no_response_observed": False})
        return [record]
    except OSError as exc:
        if not expects_no_response(plan) or not is_no_response_exception(exc):
            raise
        return _no_response(plan, started, payload_hash, len(payload), "FTP_NO_RESPONSE_OBSERVED", {"file_protocol": "FTPS" if secure else "FTP", "operation": "UPLOAD", "content_sha256": payload_hash, "transferred_bytes": 0, "control_status": "NOT_OBSERVED", "data_channel_status": "NOT_OBSERVED"}, exc)
    finally:
        if sock is not None:
            sock.close()


def run_mail(plan: WorkerPlan) -> list[dict[str, Any]]:
    started = time.monotonic()
    protocol = required_parameter(plan, "mail_protocol", str).upper()
    if protocol not in {"SMTP", "SMTPS", "IMAP", "IMAPS", "POP3", "POP3S"}:
        raise WorkerContractError("MAIL_PROTOCOL_INVALID")
    payload = _payload(plan, protocol.lower())
    payload_hash = hashlib.sha256(payload).hexdigest()
    secure = protocol.endswith("S")
    sock: socket.socket | None = None
    status = "NOT_OBSERVED"
    operation = "SEND" if protocol.startswith("SMTP") else ("APPEND" if protocol.startswith("IMAP") else "RETRIEVE")
    try:
        sock = _connect(plan, use_tls=secure)
        stream = sock.makefile("rb")
        metadata = _metadata(plan, payload_hash)
        if protocol.startswith("SMTP"):
            if not _readline(stream, "SMTP_BANNER_INVALID").startswith(b"220 "):
                raise WorkerContractError("SMTP_BANNER_INVALID")
            for command, prefix in (("EHLO testlab.invalid", b"250 "), ("MAIL FROM:<sender@testlab.invalid>", b"250 "), ("RCPT TO:<receiver@testlab.invalid>", b"250 "), ("DATA", b"354 ")):
                _sendline(sock, command)
                if not _readline(stream, "SMTP_STATUS_INVALID").startswith(prefix):
                    raise WorkerContractError("SMTP_STATUS_INVALID")
            message = b"X-TestLab-Metadata: " + metadata.encode("ascii") + b"\r\nContent-Type: application/octet-stream\r\n\r\n" + base64.b64encode(payload) + b"\r\n.\r\n"
            sock.sendall(message)
            status = _readline(stream, "SMTP_DELIVERY_INVALID").decode("ascii")[:3]
            _sendline(sock, "QUIT")
            _readline(stream, "SMTP_QUIT_INVALID")
        elif protocol.startswith("IMAP"):
            if not _readline(stream, "IMAP_BANNER_INVALID").startswith(b"* PREAUTH"):
                raise WorkerContractError("IMAP_BANNER_INVALID")
            message = metadata.encode("ascii") + b"\n" + base64.b64encode(payload)
            _sendline(sock, f"A001 APPEND INBOX {{{len(message)}}}")
            if not _readline(stream, "IMAP_CONTINUATION_INVALID").startswith(b"+ "):
                raise WorkerContractError("IMAP_CONTINUATION_INVALID")
            sock.sendall(message + b"\r\n")
            line = _readline(stream, "IMAP_APPEND_INVALID")
            status = "OK" if line.startswith(b"A001 OK") else "FAIL"
            _sendline(sock, "A002 LOGOUT")
        else:
            if not _readline(stream, "POP3_BANNER_INVALID").startswith(b"+OK"):
                raise WorkerContractError("POP3_BANNER_INVALID")
            _sendline(sock, f"XTESTLAB {metadata}")
            if not _readline(stream, "POP3_METADATA_INVALID").startswith(b"+OK"):
                raise WorkerContractError("POP3_METADATA_INVALID")
            _sendline(sock, "RETR 1")
            if not _readline(stream, "POP3_RETR_INVALID").startswith(b"+OK"):
                raise WorkerContractError("POP3_RETR_INVALID")
            received = base64.b64decode(_readline(stream, "POP3_BODY_INVALID"), validate=True)
            if _readline(stream, "POP3_TERMINATOR_INVALID") != b".":
                raise WorkerContractError("POP3_TERMINATOR_INVALID")
            status = "OK" if received == payload else "FAIL"
            _sendline(sock, "QUIT")
        result = "PASS" if not expects_no_response(plan) and status in {"250", "OK"} else "FAIL"
        record = base_record(plan, event="MAIL_TRANSACTION_COMPLETED", started=started, socket_id=sock.fileno(), local=sock.getsockname(), remote=sock.getpeername(), payload_sha256=payload_hash, byte_count=len(payload), result=result)
        record.update({"mail_protocol": protocol, "session_id": str(plan.raw["flow_id"]), "operation": operation, "message_sha256": payload_hash, "protocol_status": status, "mailbox_state_digest": hashlib.sha256((str(plan.raw["flow_id"]) + "|stored").encode("ascii")).hexdigest(), "no_response_observed": False})
        return [record]
    except OSError as exc:
        if not expects_no_response(plan) or not is_no_response_exception(exc):
            raise
        return _no_response(plan, started, payload_hash, len(payload), "MAIL_NO_RESPONSE_OBSERVED", {"mail_protocol": protocol, "session_id": str(plan.raw["flow_id"]), "operation": operation, "message_sha256": payload_hash, "protocol_status": "NOT_OBSERVED", "mailbox_state_digest": hashlib.sha256(b"").hexdigest()}, exc)
    finally:
        if sock is not None:
            sock.close()


def _mqtt_remaining_length(value: int) -> bytes:
    encoded = bytearray()
    while True:
        digit = value % 128
        value //= 128
        if value:
            digit |= 0x80
        encoded.append(digit)
        if not value:
            return bytes(encoded)


def _mqtt_packet(stream: BinaryIO) -> tuple[int, bytes]:
    header = stream.read(1)
    if len(header) != 1:
        raise WorkerContractError("MQTT_PACKET_TRUNCATED")
    multiplier = 1
    length = 0
    for _ in range(4):
        digit = stream.read(1)
        if len(digit) != 1:
            raise WorkerContractError("MQTT_PACKET_TRUNCATED")
        length += (digit[0] & 127) * multiplier
        if not digit[0] & 128:
            break
        multiplier *= 128
    else:
        raise WorkerContractError("MQTT_REMAINING_LENGTH_INVALID")
    body = stream.read(length)
    if len(body) != length:
        raise WorkerContractError("MQTT_PACKET_TRUNCATED")
    return header[0], body


def _amqp_frame(frame_type: int, channel: int, payload: bytes) -> bytes:
    return struct.pack("!BHI", frame_type, channel, len(payload)) + payload + b"\xce"


def _amqp_method(class_id: int, method_id: int, arguments: bytes = b"") -> bytes:
    return _amqp_frame(1, 0 if class_id == 10 else 1, struct.pack("!HH", class_id, method_id) + arguments)


def _read_amqp_frame(stream: BinaryIO) -> tuple[int, int, bytes]:
    header = stream.read(7)
    if len(header) != 7:
        raise WorkerContractError("AMQP_FRAME_TRUNCATED")
    frame_type, channel, length = struct.unpack("!BHI", header)
    if length > 1024 * 1024:
        raise WorkerContractError("AMQP_FRAME_SIZE_INVALID")
    payload = stream.read(length)
    if len(payload) != length or stream.read(1) != b"\xce":
        raise WorkerContractError("AMQP_FRAME_TRUNCATED")
    return frame_type, channel, payload


def run_messaging(plan: WorkerPlan) -> list[dict[str, Any]]:
    started = time.monotonic()
    protocol = required_parameter(plan, "messaging_protocol", str).upper()
    if protocol not in {"MQTT", "MQTTS", "AMQP", "AMQPS"}:
        raise WorkerContractError("MESSAGING_PROTOCOL_INVALID")
    payload = _payload(plan, protocol.lower())
    payload_hash = hashlib.sha256(payload).hexdigest()
    secure = protocol.endswith("S")
    sock: socket.socket | None = None
    try:
        sock = _connect(plan, use_tls=secure)
        stream = sock.makefile("rb")
        metadata = _metadata(plan, payload_hash)
        if protocol.startswith("MQTT"):
            client_id = f"pb-{plan.raw['flow_id']}".encode("ascii")
            variable = b"\x00\x04MQTT\x04\x02\x00\x1e" + struct.pack("!H", len(client_id)) + client_id
            sock.sendall(b"\x10" + _mqtt_remaining_length(len(variable)) + variable)
            if _mqtt_packet(stream) != (0x20, b"\x00\x00"):
                raise WorkerContractError("MQTT_CONNACK_INVALID")
            topic = ("testlab/" + metadata).encode("ascii")
            packet_id = 1
            body = struct.pack("!H", len(topic)) + topic + struct.pack("!H", packet_id) + payload
            sock.sendall(b"\x32" + _mqtt_remaining_length(len(body)) + body)
            packet_type, ack = _mqtt_packet(stream)
            acknowledged = packet_type == 0x40 and ack == struct.pack("!H", packet_id)
            namespace = "testlab"
            delivery_mode = "QOS1"
        else:
            sock.sendall(b"AMQP\x00\x00\x09\x01")
            if _read_amqp_frame(stream)[2][:4] != struct.pack("!HH", 10, 10):
                raise WorkerContractError("AMQP_START_INVALID")
            start_ok_args = b"\x00\x00\x00\x00" + b"\x05PLAIN" + struct.pack("!I", 2) + b"\x00\x00" + b"\x05en_US"
            sock.sendall(_amqp_method(10, 11, start_ok_args))
            if _read_amqp_frame(stream)[2][:4] != struct.pack("!HH", 10, 30):
                raise WorkerContractError("AMQP_TUNE_INVALID")
            sock.sendall(_amqp_method(10, 31, struct.pack("!HIH", 0, 131072, 30)))
            sock.sendall(_amqp_method(10, 40, b"\x01/\x00\x00"))
            if _read_amqp_frame(stream)[2][:4] != struct.pack("!HH", 10, 41):
                raise WorkerContractError("AMQP_OPEN_INVALID")
            sock.sendall(_amqp_method(20, 10, b"\x00"))
            if _read_amqp_frame(stream)[2][:4] != struct.pack("!HH", 20, 11):
                raise WorkerContractError("AMQP_CHANNEL_INVALID")
            sock.sendall(_amqp_method(85, 10, b"\x00"))
            if _read_amqp_frame(stream)[2][:4] != struct.pack("!HH", 85, 11):
                raise WorkerContractError("AMQP_CONFIRM_INVALID")
            metadata_bytes = metadata.encode("ascii")
            routing_key = hashlib.sha256(metadata_bytes).hexdigest().encode("ascii")
            wire_body = metadata_bytes + b"\n" + payload
            publish_args = b"\x00\x00" + b"\x00" + bytes([len(routing_key)]) + routing_key + b"\x00"
            sock.sendall(_amqp_method(60, 40, publish_args))
            sock.sendall(_amqp_frame(2, 1, struct.pack("!HHQH", 60, 0, len(wire_body), 0)))
            sock.sendall(_amqp_frame(3, 1, wire_body))
            ack_payload = _read_amqp_frame(stream)[2]
            acknowledged = ack_payload[:4] == struct.pack("!HH", 60, 80)
            namespace = "/"
            delivery_mode = "CONFIRM"
        result = "PASS" if not expects_no_response(plan) and acknowledged else "FAIL"
        record = base_record(plan, event="MESSAGING_TRANSACTION_COMPLETED", started=started, socket_id=sock.fileno(), local=sock.getsockname(), remote=sock.getpeername(), payload_sha256=payload_hash, byte_count=len(payload), result=result)
        topic_source = metadata.encode("ascii") if protocol.startswith("MQTT") else routing_key
        record.update({"messaging_protocol": protocol, "namespace": namespace, "topic_digest": hashlib.sha256(topic_source).hexdigest(), "delivery_mode": delivery_mode, "message_sha256": payload_hash, "acknowledged": acknowledged, "no_response_observed": False})
        return [record]
    except OSError as exc:
        if not expects_no_response(plan) or not is_no_response_exception(exc):
            raise
        return _no_response(plan, started, payload_hash, len(payload), "MESSAGING_NO_RESPONSE_OBSERVED", {"messaging_protocol": protocol, "namespace": "", "topic_digest": hashlib.sha256(b"").hexdigest(), "delivery_mode": "NOT_OBSERVED", "message_sha256": payload_hash, "acknowledged": False}, exc)
    finally:
        if sock is not None:
            sock.close()


def run_ntp(plan: WorkerPlan) -> list[dict[str, Any]]:
    started = time.monotonic()
    payload = _payload(plan, "ntp")
    payload_hash = hashlib.sha256(payload).hexdigest()
    request_id = hashlib.sha256((payload_hash + "|request").encode("ascii")).hexdigest()[:16]
    metadata = _metadata(plan, payload_hash).encode("ascii")
    extension = struct.pack("!HH", 0xFEED, 4 + len(metadata)) + metadata
    extension += b"\x00" * ((4 - len(extension) % 4) % 4)
    request = bytearray(48)
    request[0] = 0x23
    request[40:48] = struct.pack("!Q", int(time.time() * (1 << 32)))
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(plan.raw["operation_timeout_ms"] / 1000.0)
    try:
        sock.connect((required_parameter(plan, "remote_host", str), required_port(plan)))
        sock.send(bytes(request) + extension)
        response = sock.recv(4096)
        if len(response) < 48 or response[0] >> 3 & 0x7 != 4 or response[24:32] != request[40:48]:
            raise WorkerContractError("NTP_RESPONSE_INVALID")
        stratum = response[1]
        result = "PASS" if not expects_no_response(plan) and stratum == 2 else "FAIL"
        record = base_record(plan, event="NTP_TRANSACTION_COMPLETED", started=started, socket_id=sock.fileno(), local=sock.getsockname(), remote=sock.getpeername(), payload_sha256=payload_hash, byte_count=len(request) + len(extension), result=result)
        record.update({"time_protocol": "NTPv4", "request_id": request_id, "stratum": stratum, "server_receive_utc": str(struct.unpack("!Q", response[32:40])[0]), "server_transmit_utc": str(struct.unpack("!Q", response[40:48])[0]), "round_trip_ms": int((time.monotonic() - started) * 1000), "no_response_observed": False})
        return [record]
    except OSError as exc:
        if not expects_no_response(plan) or not is_no_response_exception(exc):
            raise
        return _no_response(plan, started, payload_hash, len(request) + len(extension), "NTP_NO_RESPONSE_OBSERVED", {"time_protocol": "NTPv4", "request_id": request_id, "stratum": 0, "server_receive_utc": "", "server_transmit_utc": "", "round_trip_ms": int((time.monotonic() - started) * 1000)}, exc)
    finally:
        sock.close()


def run_irc(plan: WorkerPlan) -> list[dict[str, Any]]:
    started = time.monotonic()
    payload = _payload(plan, "irc")
    payload_hash = hashlib.sha256(payload).hexdigest()
    secure = bool(plan.raw["parameters"].get("use_tls", False))
    sock: socket.socket | None = None
    try:
        sock = _connect(plan, use_tls=secure)
        stream = sock.makefile("rb")
        nick = "pb" + hashlib.sha256(str(plan.raw["flow_id"]).encode("ascii")).hexdigest()[:8]
        _sendline(sock, f"NICK {nick}")
        _sendline(sock, f"USER {nick} 0 * :ProxyBridge TestLab")
        if b" 001 " not in _readline(stream, "IRC_WELCOME_INVALID"):
            raise WorkerContractError("IRC_WELCOME_INVALID")
        message = _metadata(plan, payload_hash) + "." + base64.urlsafe_b64encode(payload).decode("ascii")
        _sendline(sock, f"PRIVMSG #testlab :{message}")
        reply = _readline(stream, "IRC_ACK_INVALID").decode("utf-8")
        acknowledged = reply.endswith(payload_hash)
        _sendline(sock, "QUIT :done")
        result = "PASS" if not expects_no_response(plan) and acknowledged else "FAIL"
        record = base_record(plan, event="IRC_TRANSACTION_COMPLETED", started=started, socket_id=sock.fileno(), local=sock.getsockname(), remote=sock.getpeername(), payload_sha256=payload_hash, byte_count=len(payload), result=result)
        record.update({"messaging_protocol": "IRCS" if secure else "IRC", "namespace": "#testlab", "topic_digest": hashlib.sha256(b"#testlab").hexdigest(), "delivery_mode": "SERVER_NOTICE", "message_sha256": payload_hash, "acknowledged": acknowledged, "no_response_observed": False})
        return [record]
    except OSError as exc:
        if not expects_no_response(plan) or not is_no_response_exception(exc):
            raise
        return _no_response(plan, started, payload_hash, len(payload), "IRC_NO_RESPONSE_OBSERVED", {"messaging_protocol": "IRCS" if secure else "IRC", "namespace": "#testlab", "topic_digest": hashlib.sha256(b"#testlab").hexdigest(), "delivery_mode": "NOT_OBSERVED", "message_sha256": payload_hash, "acknowledged": False}, exc)
    finally:
        if sock is not None:
            sock.close()


def run_multipeer(plan: WorkerPlan) -> list[dict[str, Any]]:
    started = time.monotonic()
    payload = _payload(plan, "multipeer")
    payload_hash = hashlib.sha256(payload).hexdigest()
    sockets: list[socket.socket] = []
    streams: list[BinaryIO] = []
    try:
        for peer in ("peer-a", "peer-b"):
            sock = _connect(plan)
            sockets.append(sock)
            stream = sock.makefile("rb")
            streams.append(stream)
            _sendline(sock, f"REGISTER {_metadata(plan, payload_hash)} {peer}")
            if not _readline(stream, "MULTIPEER_REGISTER_INVALID").startswith(b"OK "):
                raise WorkerContractError("MULTIPEER_REGISTER_INVALID")
        _sendline(sockets[0], "SEND peer-b " + base64.urlsafe_b64encode(payload).decode("ascii"))
        if not _readline(streams[0], "MULTIPEER_SEND_INVALID").startswith(b"SENT "):
            raise WorkerContractError("MULTIPEER_SEND_INVALID")
        delivered = _readline(streams[1], "MULTIPEER_DELIVERY_INVALID").split(b" ", 2)
        received = base64.urlsafe_b64decode(delivered[2]) if len(delivered) == 3 and delivered[0] == b"MESSAGE" else b""
        result = "PASS" if not expects_no_response(plan) and received == payload else "FAIL"
        delivery_digest = hashlib.sha256(b"peer-a\npeer-b").hexdigest()
        record = base_record(plan, event="MULTIPEER_TRANSACTION_COMPLETED", started=started, socket_id=sockets[0].fileno(), local=sockets[0].getsockname(), remote=sockets[0].getpeername(), payload_sha256=payload_hash, byte_count=len(payload), result=result)
        record.update({"peer_id": "peer-a", "peer_count": 2, "channel_id": str(plan.raw["flow_id"]), "message_sha256": payload_hash, "delivery_set_digest": delivery_digest, "no_response_observed": False})
        return [record]
    except OSError as exc:
        if not expects_no_response(plan) or not is_no_response_exception(exc):
            raise
        return _no_response(plan, started, payload_hash, len(payload), "MULTIPEER_NO_RESPONSE_OBSERVED", {"peer_id": "peer-a", "peer_count": 2, "channel_id": str(plan.raw["flow_id"]), "message_sha256": payload_hash, "delivery_set_digest": hashlib.sha256(b"").hexdigest()}, exc)
    finally:
        for stream in streams:
            stream.close()
        for sock in sockets:
            sock.close()
