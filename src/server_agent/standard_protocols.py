from __future__ import annotations

import asyncio
import base64
import hashlib
import json
import os
import ssl
import struct
from datetime import datetime, timezone
from typing import Any, Callable


class StandardProtocolError(ValueError):
    pass


def _utc() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _sha(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _decode_metadata(value: str) -> dict[str, str]:
    try:
        raw = base64.urlsafe_b64decode(value.encode("ascii"))
        parsed = json.loads(raw.decode("utf-8"))
    except (ValueError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise StandardProtocolError("METADATA_INVALID") from exc
    if not isinstance(parsed, dict):
        raise StandardProtocolError("METADATA_INVALID")
    result = {str(key): str(item) for key, item in parsed.items()}
    for field in ("run_id", "scenario_id", "attempt_id", "flow_id", "payload_sha256"):
        if not result.get(field):
            raise StandardProtocolError("METADATA_MISSING")
    if len(result["payload_sha256"]) != 64:
        raise StandardProtocolError("METADATA_HASH_INVALID")
    return result


def _record(metadata: dict[str, str], family: str, transport: str, local: Any, remote: Any, payload_hash: str, byte_count: int, fields: dict[str, Any]) -> dict[str, Any]:
    value = {
        "schema_version": 1,
        "run_id": metadata["run_id"],
        "scenario_id": metadata["scenario_id"],
        "attempt_id": metadata["attempt_id"],
        "flow_id": metadata["flow_id"],
        "phase": "server",
        "sequence": 1,
        "event": "PROTOCOL_REQUEST_RECEIVED",
        "timestamp_utc": _utc(),
        "monotonic_ms": 0,
        "process_id": os.getpid(),
        "socket_id": 0,
        "protocol_family": family,
        "transport": transport,
        "local_ip": str(local[0]) if local else "",
        "local_port": int(local[1]) if local else 0,
        "remote_ip": str(remote[0]) if remote else "",
        "remote_port": int(remote[1]) if remote else 0,
        "payload_sha256": payload_hash,
        "bytes": byte_count,
        "result": "PASS",
    }
    value.update(fields)
    return value


async def _line(reader: asyncio.StreamReader, code: str) -> str:
    data = await reader.readline()
    if not data or len(data) > 65536 or not data.endswith(b"\n"):
        raise StandardProtocolError(code)
    try:
        return data.rstrip(b"\r\n").decode("utf-8")
    except UnicodeDecodeError as exc:
        raise StandardProtocolError(code) from exc


async def _reply(writer: asyncio.StreamWriter, value: str) -> None:
    writer.write(value.encode("utf-8") + b"\r\n")
    await writer.drain()


async def _close(writer: asyncio.StreamWriter) -> None:
    writer.close()
    try:
        await writer.wait_closed()
    except (ConnectionError, ssl.SSLError):
        pass


class FtpTransferState:
    def __init__(self) -> None:
        self.queue: asyncio.Queue[dict[str, Any]] = asyncio.Queue(maxsize=16)


async def _ftp_control(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, evidence: Callable[[dict[str, Any]], None], state: FtpTransferState, data_port: int, tls_context: ssl.SSLContext) -> None:
    metadata: dict[str, str] | None = None
    protected = False
    try:
        await _reply(writer, "220 ProxyBridge TestLab FTP ready")
        while True:
            line = await _line(reader, "FTP_COMMAND_INVALID")
            command, _, argument = line.partition(" ")
            command = command.upper()
            if command == "AUTH" and argument.upper() == "TLS":
                await _reply(writer, "234 Proceed with negotiation")
                await writer.start_tls(tls_context)
            elif command == "USER":
                await _reply(writer, "331 Anonymous identity accepted")
            elif command == "PASS":
                await _reply(writer, "230 Login successful")
            elif command == "SITE" and argument.startswith("TESTLAB "):
                metadata = _decode_metadata(argument.split(" ", 1)[1])
                await _reply(writer, "200 Metadata accepted")
            elif command == "TYPE" and argument.upper() == "I":
                await _reply(writer, "200 Type set to I")
            elif command == "PBSZ":
                await _reply(writer, "200 PBSZ=0")
            elif command == "PROT" and argument.upper() == "P":
                protected = True
                await _reply(writer, "200 Data protection enabled")
            elif command == "EPSV":
                await _reply(writer, f"229 Entering Extended Passive Mode (|||{data_port}|)")
            elif command == "STOR" and metadata is not None:
                completion: asyncio.Future[tuple[int, str]] = asyncio.get_running_loop().create_future()
                await state.queue.put({"metadata": metadata, "protected": protected, "completion": completion})
                await _reply(writer, "150 Opening data connection")
                transferred, digest = await asyncio.wait_for(completion, timeout=60.0)
                if digest != metadata["payload_sha256"]:
                    raise StandardProtocolError("FTP_PAYLOAD_MISMATCH")
                await _reply(writer, f"226 Transfer complete bytes={transferred}")
            elif command == "QUIT":
                await _reply(writer, "221 Goodbye")
                break
            else:
                await _reply(writer, "500 Unsupported command")
    except (asyncio.IncompleteReadError, asyncio.TimeoutError, StandardProtocolError, ConnectionError, ssl.SSLError):
        pass
    finally:
        await _close(writer)


async def _ftp_data(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, evidence: Callable[[dict[str, Any]], None], state: FtpTransferState, tls_context: ssl.SSLContext) -> None:
    transfer: dict[str, Any] | None = None
    try:
        transfer = await asyncio.wait_for(state.queue.get(), timeout=30.0)
        if transfer["protected"]:
            await writer.start_tls(tls_context)
        data = await asyncio.wait_for(reader.read(1024 * 1024 + 1), timeout=30.0)
        if len(data) > 1024 * 1024:
            raise StandardProtocolError("FTP_DATA_TOO_LARGE")
        digest = _sha(data)
        metadata = transfer["metadata"]
        record = _record(metadata, "ftp-ftps", "TCP", writer.get_extra_info("sockname"), writer.get_extra_info("peername"), digest, len(data), {
            "file_protocol": "FTPS" if transfer["protected"] else "FTP",
            "operation": "UPLOAD",
            "content_sha256": digest,
            "transferred_bytes": len(data),
            "control_status": "226",
            "data_channel_status": "TLS_PROTECTED" if transfer["protected"] else "CLEAR",
        })
        evidence(record)
        transfer["completion"].set_result((len(data), digest))
    except (asyncio.IncompleteReadError, asyncio.TimeoutError, StandardProtocolError, ConnectionError, ssl.SSLError) as exc:
        if transfer is not None and not transfer["completion"].done():
            transfer["completion"].set_exception(exc)
    finally:
        await _close(writer)


async def _smtp(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, evidence: Callable[[dict[str, Any]], None], protocol: str) -> None:
    try:
        await _reply(writer, "220 proxybridge-testlab ESMTP ready")
        while True:
            line = await _line(reader, "SMTP_COMMAND_INVALID")
            upper = line.upper()
            if upper.startswith("EHLO "):
                await _reply(writer, "250 proxybridge-testlab")
            elif upper.startswith("MAIL FROM:") or upper.startswith("RCPT TO:"):
                await _reply(writer, "250 OK")
            elif upper == "DATA":
                await _reply(writer, "354 End data with <CRLF>.<CRLF>")
                lines: list[bytes] = []
                size = 0
                while True:
                    data = await reader.readline()
                    if not data or len(data) > 65536:
                        raise StandardProtocolError("SMTP_DATA_INVALID")
                    if data == b".\r\n":
                        break
                    size += len(data)
                    if size > 1024 * 1024:
                        raise StandardProtocolError("SMTP_DATA_TOO_LARGE")
                    lines.append(data.rstrip(b"\r\n"))
                metadata_line = next((item for item in lines if item.lower().startswith(b"x-testlab-metadata: ")), None)
                separator = lines.index(b"") if b"" in lines else -1
                if metadata_line is None or separator < 0 or separator + 1 >= len(lines):
                    raise StandardProtocolError("SMTP_METADATA_MISSING")
                metadata = _decode_metadata(metadata_line.split(b": ", 1)[1].decode("ascii"))
                payload = base64.b64decode(lines[separator + 1], validate=True)
                digest = _sha(payload)
                evidence(_record(metadata, "smtp", "TCP", writer.get_extra_info("sockname"), writer.get_extra_info("peername"), digest, len(payload), {
                    "mail_protocol": protocol,
                    "session_id": metadata["flow_id"],
                    "operation": "SEND",
                    "message_sha256": digest,
                    "protocol_status": "250",
                    "mailbox_state_digest": _sha((metadata["flow_id"] + "|stored").encode("ascii")),
                }))
                await _reply(writer, "250 Message accepted")
            elif upper == "QUIT":
                await _reply(writer, "221 Bye")
                break
            else:
                await _reply(writer, "500 Unsupported")
    except (asyncio.IncompleteReadError, StandardProtocolError, ConnectionError, ValueError):
        pass
    finally:
        await _close(writer)


async def _imap(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, evidence: Callable[[dict[str, Any]], None], protocol: str) -> None:
    try:
        await _reply(writer, "* PREAUTH ProxyBridge TestLab ready")
        line = await _line(reader, "IMAP_COMMAND_INVALID")
        parts = line.split(" ")
        if len(parts) != 4 or parts[1].upper() != "APPEND" or not parts[3].startswith("{") or not parts[3].endswith("}"):
            raise StandardProtocolError("IMAP_APPEND_INVALID")
        length = int(parts[3][1:-1])
        if length <= 0 or length > 1024 * 1024:
            raise StandardProtocolError("IMAP_LITERAL_SIZE_INVALID")
        await _reply(writer, "+ Ready for literal")
        message = await reader.readexactly(length)
        if await reader.readexactly(2) != b"\r\n":
            raise StandardProtocolError("IMAP_LITERAL_INVALID")
        metadata_text, encoded = message.split(b"\n", 1)
        metadata = _decode_metadata(metadata_text.decode("ascii"))
        payload = base64.b64decode(encoded, validate=True)
        digest = _sha(payload)
        evidence(_record(metadata, "imap-pop3", "TCP", writer.get_extra_info("sockname"), writer.get_extra_info("peername"), digest, len(payload), {
            "mail_protocol": protocol,
            "session_id": metadata["flow_id"],
            "operation": "APPEND",
            "message_sha256": digest,
            "protocol_status": "OK",
            "mailbox_state_digest": _sha((metadata["flow_id"] + "|stored").encode("ascii")),
        }))
        await _reply(writer, f"{parts[0]} OK APPEND completed")
        await _line(reader, "IMAP_LOGOUT_INVALID")
        await _reply(writer, "* BYE")
    except (asyncio.IncompleteReadError, StandardProtocolError, ConnectionError, ValueError):
        pass
    finally:
        await _close(writer)


def _derived_payload(metadata: dict[str, str], label: str) -> bytes:
    return f"{label}|{metadata['run_id']}|{metadata['scenario_id']}|{metadata['attempt_id']}|{metadata['flow_id']}".encode("utf-8")


async def _pop3(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, evidence: Callable[[dict[str, Any]], None], protocol: str) -> None:
    metadata: dict[str, str] | None = None
    try:
        await _reply(writer, "+OK ProxyBridge TestLab ready")
        while True:
            line = await _line(reader, "POP3_COMMAND_INVALID")
            command, _, argument = line.partition(" ")
            if command.upper() == "XTESTLAB":
                metadata = _decode_metadata(argument)
                await _reply(writer, "+OK metadata accepted")
            elif command.upper() == "RETR" and metadata is not None:
                payload = _derived_payload(metadata, protocol.lower())
                digest = _sha(payload)
                await _reply(writer, f"+OK {len(payload)} octets")
                await _reply(writer, base64.b64encode(payload).decode("ascii"))
                await _reply(writer, ".")
                evidence(_record(metadata, "imap-pop3", "TCP", writer.get_extra_info("sockname"), writer.get_extra_info("peername"), digest, len(payload), {
                    "mail_protocol": protocol,
                    "session_id": metadata["flow_id"],
                    "operation": "RETRIEVE",
                    "message_sha256": digest,
                    "protocol_status": "OK",
                    "mailbox_state_digest": _sha((metadata["flow_id"] + "|stored").encode("ascii")),
                }))
            elif command.upper() == "QUIT":
                await _reply(writer, "+OK bye")
                break
            else:
                await _reply(writer, "-ERR unsupported")
    except (asyncio.IncompleteReadError, StandardProtocolError, ConnectionError):
        pass
    finally:
        await _close(writer)


async def _mqtt_read(reader: asyncio.StreamReader) -> tuple[int, bytes]:
    header = (await reader.readexactly(1))[0]
    length = 0
    multiplier = 1
    for _ in range(4):
        digit = (await reader.readexactly(1))[0]
        length += (digit & 127) * multiplier
        if not digit & 128:
            break
        multiplier *= 128
    else:
        raise StandardProtocolError("MQTT_LENGTH_INVALID")
    if length > 1024 * 1024:
        raise StandardProtocolError("MQTT_PACKET_TOO_LARGE")
    return header, await reader.readexactly(length)


async def _mqtt(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, evidence: Callable[[dict[str, Any]], None], protocol: str) -> None:
    try:
        header, _ = await _mqtt_read(reader)
        if header != 0x10:
            raise StandardProtocolError("MQTT_CONNECT_INVALID")
        writer.write(b"\x20\x02\x00\x00")
        await writer.drain()
        header, body = await _mqtt_read(reader)
        if header != 0x32 or len(body) < 6:
            raise StandardProtocolError("MQTT_PUBLISH_INVALID")
        topic_length = struct.unpack("!H", body[:2])[0]
        if topic_length <= 0 or 2 + topic_length + 2 > len(body):
            raise StandardProtocolError("MQTT_TOPIC_INVALID")
        topic = body[2 : 2 + topic_length].decode("ascii")
        packet_id = body[2 + topic_length : 4 + topic_length]
        payload = body[4 + topic_length :]
        if not topic.startswith("testlab/"):
            raise StandardProtocolError("MQTT_TOPIC_INVALID")
        metadata = _decode_metadata(topic.split("/", 1)[1])
        digest = _sha(payload)
        writer.write(b"\x40\x02" + packet_id)
        await writer.drain()
        evidence(_record(metadata, "mqtt", "TCP", writer.get_extra_info("sockname"), writer.get_extra_info("peername"), digest, len(payload), {
            "messaging_protocol": protocol,
            "namespace": "testlab",
            "topic_digest": _sha(topic.split("/", 1)[1].encode("ascii")),
            "delivery_mode": "QOS1",
            "message_sha256": digest,
            "acknowledged": True,
        }))
    except (asyncio.IncompleteReadError, StandardProtocolError, ConnectionError, UnicodeDecodeError):
        pass
    finally:
        await _close(writer)


def _amqp_frame(frame_type: int, channel: int, payload: bytes) -> bytes:
    return struct.pack("!BHI", frame_type, channel, len(payload)) + payload + b"\xce"


def _amqp_method(class_id: int, method_id: int, arguments: bytes = b"") -> bytes:
    return _amqp_frame(1, 0 if class_id == 10 else 1, struct.pack("!HH", class_id, method_id) + arguments)


async def _amqp_read(reader: asyncio.StreamReader) -> tuple[int, int, bytes]:
    frame_type, channel, length = struct.unpack("!BHI", await reader.readexactly(7))
    if length > 1024 * 1024:
        raise StandardProtocolError("AMQP_FRAME_TOO_LARGE")
    payload = await reader.readexactly(length)
    if await reader.readexactly(1) != b"\xce":
        raise StandardProtocolError("AMQP_FRAME_END_INVALID")
    return frame_type, channel, payload


async def _amqp(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, evidence: Callable[[dict[str, Any]], None], protocol: str) -> None:
    try:
        if await reader.readexactly(8) != b"AMQP\x00\x00\x09\x01":
            raise StandardProtocolError("AMQP_HEADER_INVALID")
        writer.write(_amqp_method(10, 10, b"\x00\x09\x01\x00\x00\x00\x00\x05PLAIN\x05en_US"))
        await writer.drain()
        if (await _amqp_read(reader))[2][:4] != struct.pack("!HH", 10, 11):
            raise StandardProtocolError("AMQP_START_OK_INVALID")
        writer.write(_amqp_method(10, 30, struct.pack("!HIH", 0, 131072, 30)))
        await writer.drain()
        if (await _amqp_read(reader))[2][:4] != struct.pack("!HH", 10, 31):
            raise StandardProtocolError("AMQP_TUNE_OK_INVALID")
        if (await _amqp_read(reader))[2][:4] != struct.pack("!HH", 10, 40):
            raise StandardProtocolError("AMQP_OPEN_INVALID")
        writer.write(_amqp_method(10, 41, b"\x00"))
        await writer.drain()
        if (await _amqp_read(reader))[2][:4] != struct.pack("!HH", 20, 10):
            raise StandardProtocolError("AMQP_CHANNEL_OPEN_INVALID")
        writer.write(_amqp_method(20, 11, b"\x00\x00\x00\x00"))
        await writer.drain()
        if (await _amqp_read(reader))[2][:4] != struct.pack("!HH", 85, 10):
            raise StandardProtocolError("AMQP_CONFIRM_SELECT_INVALID")
        writer.write(_amqp_method(85, 11))
        await writer.drain()
        _, _, publish = await _amqp_read(reader)
        if publish[:4] != struct.pack("!HH", 60, 40) or len(publish) < 8:
            raise StandardProtocolError("AMQP_PUBLISH_INVALID")
        offset = 4 + 2
        exchange_length = publish[offset]
        offset += 1 + exchange_length
        routing_length = publish[offset]
        offset += 1
        routing_key = publish[offset : offset + routing_length].decode("ascii")
        _, _, content_header = await _amqp_read(reader)
        body_size = struct.unpack("!Q", content_header[4:12])[0]
        _, _, wire_body = await _amqp_read(reader)
        if body_size != len(wire_body) or b"\n" not in wire_body:
            raise StandardProtocolError("AMQP_BODY_SIZE_INVALID")
        metadata_text, body = wire_body.split(b"\n", 1)
        metadata = _decode_metadata(metadata_text.decode("ascii"))
        if routing_key != _sha(metadata_text):
            raise StandardProtocolError("AMQP_ROUTING_KEY_INVALID")
        digest = _sha(body)
        writer.write(_amqp_method(60, 80, struct.pack("!Q", 1) + b"\x00"))
        await writer.drain()
        evidence(_record(metadata, "amqp", "TCP", writer.get_extra_info("sockname"), writer.get_extra_info("peername"), digest, len(body), {
            "messaging_protocol": protocol,
            "namespace": "/",
            "topic_digest": _sha(routing_key.encode("ascii")),
            "delivery_mode": "CONFIRM",
            "message_sha256": digest,
            "acknowledged": True,
        }))
    except (asyncio.IncompleteReadError, StandardProtocolError, ConnectionError, UnicodeDecodeError, IndexError):
        pass
    finally:
        await _close(writer)


class NtpProtocol(asyncio.DatagramProtocol):
    def __init__(self, evidence: Callable[[dict[str, Any]], None]) -> None:
        self.evidence = evidence
        self.transport: asyncio.DatagramTransport | None = None

    def connection_made(self, transport: asyncio.BaseTransport) -> None:
        self.transport = transport  # type: ignore[assignment]

    def datagram_received(self, data: bytes, address: Any) -> None:
        if self.transport is None or len(data) < 52 or data[0] >> 3 & 0x7 not in (3, 4):
            return
        try:
            extension_type, extension_length = struct.unpack("!HH", data[48:52])
            if extension_type != 0xFEED or extension_length < 5 or 48 + extension_length > len(data):
                raise StandardProtocolError("NTP_EXTENSION_INVALID")
            metadata = _decode_metadata(data[52 : 48 + extension_length].decode("ascii"))
            now = int(datetime.now(timezone.utc).timestamp() * (1 << 32))
            response = bytearray(48)
            response[0] = 0x24
            response[1] = 2
            response[2] = 6
            response[3] = 0xEC
            response[24:32] = data[40:48]
            response[32:40] = struct.pack("!Q", now)
            response[40:48] = struct.pack("!Q", now)
            self.transport.sendto(bytes(response) + data[48:], address)
            local = self.transport.get_extra_info("sockname")
            request_id = _sha((metadata["payload_sha256"] + "|request").encode("ascii"))[:16]
            self.evidence(_record(metadata, "ntp", "UDP", local, address, metadata["payload_sha256"], len(data), {
                "time_protocol": "NTPv4",
                "request_id": request_id,
                "stratum": 2,
                "server_receive_utc": str(now),
                "server_transmit_utc": str(now),
                "round_trip_ms": 0,
            }))
        except (StandardProtocolError, UnicodeDecodeError):
            return


async def _irc(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, evidence: Callable[[dict[str, Any]], None], protocol: str) -> None:
    nick = ""
    try:
        while True:
            line = await _line(reader, "IRC_COMMAND_INVALID")
            command, _, argument = line.partition(" ")
            if command.upper() == "NICK":
                nick = argument
            elif command.upper() == "USER" and nick:
                await _reply(writer, f":proxybridge-testlab 001 {nick} :Welcome")
            elif command.upper() == "PRIVMSG" and " :" in argument:
                _, message = argument.split(" :", 1)
                metadata_text, encoded = message.split(".", 1)
                metadata = _decode_metadata(metadata_text)
                payload = base64.urlsafe_b64decode(encoded.encode("ascii"))
                digest = _sha(payload)
                await _reply(writer, f":proxybridge-testlab NOTICE {nick} :ACK {digest}")
                evidence(_record(metadata, "irc", "TCP", writer.get_extra_info("sockname"), writer.get_extra_info("peername"), digest, len(payload), {
                    "messaging_protocol": protocol,
                    "namespace": "#testlab",
                    "topic_digest": _sha(b"#testlab"),
                    "delivery_mode": "SERVER_NOTICE",
                    "message_sha256": digest,
                    "acknowledged": True,
                }))
            elif command.upper() == "QUIT":
                break
    except (asyncio.IncompleteReadError, StandardProtocolError, ConnectionError, ValueError):
        pass
    finally:
        await _close(writer)


class MultiPeerState:
    def __init__(self) -> None:
        self.peers: dict[str, asyncio.StreamWriter] = {}
        self.metadata: dict[str, dict[str, str]] = {}
        self.lock = asyncio.Lock()


async def _multipeer(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, evidence: Callable[[dict[str, Any]], None], state: MultiPeerState) -> None:
    peer_id = ""
    try:
        register = (await _line(reader, "MULTIPEER_REGISTER_INVALID")).split(" ", 2)
        if len(register) != 3 or register[0] != "REGISTER" or register[2] not in {"peer-a", "peer-b"}:
            raise StandardProtocolError("MULTIPEER_REGISTER_INVALID")
        metadata = _decode_metadata(register[1])
        peer_id = register[2]
        async with state.lock:
            if peer_id in state.peers:
                raise StandardProtocolError("MULTIPEER_DUPLICATE_PEER")
            state.peers[peer_id] = writer
            state.metadata[peer_id] = metadata
        await _reply(writer, f"OK {peer_id}")
        while True:
            line = await _line(reader, "MULTIPEER_COMMAND_INVALID")
            parts = line.split(" ", 2)
            if len(parts) != 3 or parts[0] != "SEND":
                raise StandardProtocolError("MULTIPEER_COMMAND_INVALID")
            target = parts[1]
            payload = base64.urlsafe_b64decode(parts[2].encode("ascii"))
            async with state.lock:
                target_writer = state.peers.get(target)
                peer_count = len(state.peers)
            if target_writer is None:
                raise StandardProtocolError("MULTIPEER_TARGET_MISSING")
            await _reply(target_writer, f"MESSAGE {peer_id} {parts[2]}")
            await _reply(writer, f"SENT {target}")
            digest = _sha(payload)
            evidence(_record(metadata, "controlled-p2p", "TCP", writer.get_extra_info("sockname"), writer.get_extra_info("peername"), digest, len(payload), {
                "peer_id": peer_id,
                "peer_count": peer_count,
                "channel_id": metadata["flow_id"],
                "message_sha256": digest,
                "delivery_set_digest": _sha(b"peer-a\npeer-b"),
            }))
    except (asyncio.IncompleteReadError, StandardProtocolError, ConnectionError, ValueError):
        pass
    finally:
        if peer_id:
            async with state.lock:
                if state.peers.get(peer_id) is writer:
                    state.peers.pop(peer_id, None)
                    state.metadata.pop(peer_id, None)
        await _close(writer)


async def start_standard_protocols(bind: str, config: dict[str, Any], evidence: Callable[[dict[str, Any]], None], ssl_context: ssl.SSLContext, preferred_ports: dict[str, int]) -> tuple[list[asyncio.AbstractServer], list[asyncio.DatagramTransport], dict[str, int]]:
    loop = asyncio.get_running_loop()
    servers: list[asyncio.AbstractServer] = []
    transports: list[asyncio.DatagramTransport] = []
    actual: dict[str, int] = {}

    async def add(name: str, handler: Any, secure: bool = False) -> int:
        requested = preferred_ports.get(name, int(config[name]["port"]))
        server = await asyncio.start_server(handler, bind, requested, ssl=ssl_context if secure else None)
        servers.append(server)
        port = int(server.sockets[0].getsockname()[1])
        actual[name] = port
        return port

    ftp_state = FtpTransferState()
    data_port = await add("ftp_data", lambda r, w: _ftp_data(r, w, evidence, ftp_state, ssl_context))
    await add("ftp", lambda r, w: _ftp_control(r, w, evidence, ftp_state, data_port, ssl_context))
    await add("smtp", lambda r, w: _smtp(r, w, evidence, "SMTP"))
    await add("smtps", lambda r, w: _smtp(r, w, evidence, "SMTPS"), True)
    await add("imap", lambda r, w: _imap(r, w, evidence, "IMAP"))
    await add("imaps", lambda r, w: _imap(r, w, evidence, "IMAPS"), True)
    await add("pop3", lambda r, w: _pop3(r, w, evidence, "POP3"))
    await add("pop3s", lambda r, w: _pop3(r, w, evidence, "POP3S"), True)
    await add("mqtt", lambda r, w: _mqtt(r, w, evidence, "MQTT"))
    await add("mqtts", lambda r, w: _mqtt(r, w, evidence, "MQTTS"), True)
    await add("amqp", lambda r, w: _amqp(r, w, evidence, "AMQP"))
    await add("amqps", lambda r, w: _amqp(r, w, evidence, "AMQPS"), True)
    await add("irc", lambda r, w: _irc(r, w, evidence, "IRC"))
    await add("ircs", lambda r, w: _irc(r, w, evidence, "IRCS"), True)
    multipeer_state = MultiPeerState()
    await add("multipeer", lambda r, w: _multipeer(r, w, evidence, multipeer_state))
    requested_ntp = preferred_ports.get("ntp", int(config["ntp"]["port"]))
    transport, _ = await loop.create_datagram_endpoint(lambda: NtpProtocol(evidence), local_addr=(bind, requested_ntp))
    transports.append(transport)  # type: ignore[arg-type]
    actual["ntp"] = int(transport.get_extra_info("sockname")[1])
    return servers, transports, actual
