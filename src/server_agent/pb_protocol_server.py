from __future__ import annotations

import argparse
import asyncio
import hashlib
import json
import os
import ssl
import struct
import sys
import threading
import base64
from functools import partial
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

SERVER_ROOT = Path(__file__).resolve().parent
VENDOR_ROOT = SERVER_ROOT / "vendor"
if str(SERVER_ROOT) not in sys.path:
    sys.path.insert(0, str(SERVER_ROOT))
if VENDOR_ROOT.is_dir() and str(VENDOR_ROOT) not in sys.path:
    sys.path.insert(0, str(VENDOR_ROOT))

from browser_origin import BrowserOriginError, build_browser_origin_response


class ProtocolServerError(ValueError):
    pass


def _utc() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _load_config(path: Path) -> dict[str, Any]:
    try:
        data = path.read_bytes()
    except OSError as exc:
        raise ProtocolServerError("CONFIG_READ_FAILED") from exc
    if data.startswith(b"\xef\xbb\xbf"):
        raise ProtocolServerError("CONFIG_BOM_FORBIDDEN")
    try:
        value = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ProtocolServerError("CONFIG_JSON_INVALID") from exc
    if not isinstance(value, dict) or value.get("schema_version") != 1:
        raise ProtocolServerError("CONFIG_SCHEMA_UNSUPPORTED")
    required = {"bind_ipv4", "bind_ipv6", "jsonl_log", "dns", "http", "tls", "https", "http2", "quic_http3", "websocket", "grpc", "webtransport", "ftp", "ftp_data", "smtp", "smtps", "imap", "imaps", "pop3", "pop3s", "mqtt", "mqtts", "amqp", "amqps", "ntp", "irc", "ircs", "multipeer", "stun_turn", "rtp_media", "receive_only", "failure_control", "negative_proxy"}
    if not required.issubset(value):
        raise ProtocolServerError("CONFIG_REQUIRED_FIELD_MISSING")
    allow_ephemeral = value.get("allow_ephemeral_ports", False) is True
    if allow_ephemeral and (str(value.get("bind_ipv4", "")) != "127.0.0.1" or str(value.get("bind_ipv6", ""))):
        raise ProtocolServerError("CONFIG_EPHEMERAL_SCOPE_INVALID")
    ports: list[int] = []
    for section in ("dns", "http", "tls", "https", "http2", "quic_http3", "websocket", "grpc", "webtransport", "ftp", "ftp_data", "smtp", "smtps", "imap", "imaps", "pop3", "pop3s", "mqtt", "mqtts", "amqp", "amqps", "ntp", "irc", "ircs", "multipeer", "stun_turn", "rtp_media", "receive_only", "failure_control"):
        item = value[section]
        minimum_port = 0 if allow_ephemeral else 1
        if not isinstance(item, dict) or isinstance(item.get("port"), bool) or not isinstance(item.get("port"), int) or item["port"] < minimum_port or item["port"] > 65535:
            raise ProtocolServerError("CONFIG_PORT_INVALID")
        ports.append(item["port"])
    try:
        from negative_proxy import validate_negative_proxy_config
        validate_negative_proxy_config(value["negative_proxy"], set(ports))
    except ImportError as exc:
        raise ProtocolServerError("NEGATIVE_PROXY_MODULE_UNAVAILABLE") from exc
    except ValueError as exc:
        raise ProtocolServerError(str(exc)) from exc
    ports.extend([value["negative_proxy"]["auth_port"], value["negative_proxy"]["unavailable_port"]])
    nonzero_ports = [port for port in ports if port != 0]
    if len(set(nonzero_ports)) != len(nonzero_ports):
        raise ProtocolServerError("CONFIG_PORT_DUPLICATE")
    zone = str(value["dns"].get("zone", ""))
    if not zone.endswith(".") or len(zone) > 200:
        raise ProtocolServerError("CONFIG_DNS_ZONE_INVALID")
    root = path.resolve().parent
    for key in ("certificate", "private_key", "ca_certificate"):
        relative = str(value["tls"].get(key, ""))
        candidate = (root / relative).resolve()
        try:
            candidate.relative_to(root)
        except ValueError as exc:
            raise ProtocolServerError("CONFIG_TLS_PATH_ESCAPE") from exc
        if not candidate.is_file() or candidate.is_symlink():
            raise ProtocolServerError("CONFIG_TLS_FILE_MISSING")
    certificate_sha256 = str(value["tls"].get("certificate_sha256", ""))
    if len(certificate_sha256) != 64 or any(character not in "0123456789abcdef" for character in certificate_sha256):
        raise ProtocolServerError("CONFIG_TLS_CERTIFICATE_HASH_INVALID")
    log_path = Path(str(value["jsonl_log"]))
    if not log_path.is_absolute():
        value["jsonl_log"] = str((root / log_path).resolve())
    value["_root"] = str(root)
    return value


def _ssl_context(config: dict[str, Any], alpn_protocols: tuple[str, ...]) -> ssl.SSLContext:
    root = Path(config["_root"])
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(root / config["tls"]["certificate"], root / config["tls"]["private_key"])
    if alpn_protocols:
        context.set_alpn_protocols(list(alpn_protocols))
    return context


def _quic_configuration(config: dict[str, Any]) -> Any:
    try:
        from aioquic.h3.connection import H3_ALPN
        from aioquic.quic.configuration import QuicConfiguration
    except ImportError as exc:
        raise ProtocolServerError("QUIC_DEPENDENCY_UNAVAILABLE") from exc
    root = Path(config["_root"])
    configuration = QuicConfiguration(is_client=False, alpn_protocols=H3_ALPN, max_datagram_frame_size=65536)
    configuration.load_cert_chain(root / config["tls"]["certificate"], root / config["tls"]["private_key"])
    return configuration


class EvidenceLog:
    def __init__(self, path: str) -> None:
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.Lock()

    def append(self, value: dict[str, Any]) -> None:
        payload = (json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
        with self._lock:
            descriptor = os.open(self.path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o640)
            try:
                os.write(descriptor, payload)
                os.fsync(descriptor)
            finally:
                os.close(descriptor)


def _read_dns_name(message: bytes, offset: int) -> tuple[str, int]:
    labels: list[str] = []
    while True:
        if offset >= len(message):
            raise ProtocolServerError("DNS_NAME_TRUNCATED")
        length = message[offset]
        offset += 1
        if length == 0:
            break
        if length & 0xC0 or length > 63 or offset + length > len(message):
            raise ProtocolServerError("DNS_NAME_INVALID")
        try:
            labels.append(message[offset : offset + length].decode("ascii"))
        except UnicodeDecodeError as exc:
            raise ProtocolServerError("DNS_NAME_INVALID") from exc
        offset += length
    return ".".join(labels).lower() + ".", offset


def _encode_dns_name(name: str) -> bytes:
    labels = name.rstrip(".").split(".")
    return b"".join(bytes([len(label.encode("ascii"))]) + label.encode("ascii") for label in labels) + b"\x00"


def _parse_dns_query(message: bytes) -> tuple[dict[str, Any], bytes, int, str, int, int]:
    if len(message) < 12:
        raise ProtocolServerError("DNS_MESSAGE_TRUNCATED")
    query_id, flags, qd_count, answer_count, authority_count, additional_count = struct.unpack("!HHHHHH", message[:12])
    if qd_count != 1 or answer_count != 0 or authority_count != 0:
        raise ProtocolServerError("DNS_QUERY_SHAPE_INVALID")
    name, offset = _read_dns_name(message, 12)
    if offset + 4 > len(message):
        raise ProtocolServerError("DNS_QUESTION_TRUNCATED")
    query_type, query_class = struct.unpack("!HH", message[offset : offset + 4])
    question = message[12 : offset + 4]
    offset += 4
    metadata: dict[str, Any] = {}
    for _ in range(additional_count):
        _, offset = _read_dns_name(message, offset)
        if offset + 10 > len(message):
            raise ProtocolServerError("DNS_ADDITIONAL_TRUNCATED")
        record_type, _, _, data_length = struct.unpack("!HHIH", message[offset : offset + 10])
        offset += 10
        if offset + data_length > len(message):
            raise ProtocolServerError("DNS_ADDITIONAL_TRUNCATED")
        data = message[offset : offset + data_length]
        offset += data_length
        if record_type == 41:
            option_offset = 0
            while option_offset + 4 <= len(data):
                option_code, option_length = struct.unpack("!HH", data[option_offset : option_offset + 4])
                option_offset += 4
                option_data = data[option_offset : option_offset + option_length]
                option_offset += option_length
                if option_code == 65001:
                    try:
                        parsed = json.loads(option_data.decode("utf-8"))
                    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                        raise ProtocolServerError("DNS_METADATA_INVALID") from exc
                    if isinstance(parsed, dict):
                        metadata = parsed
    for field in ("run_id", "scenario_id", "attempt_id", "flow_id", "payload_sha256"):
        if not isinstance(metadata.get(field), str) or not metadata[field]:
            raise ProtocolServerError("DNS_METADATA_MISSING")
    return metadata, question, query_id, name, query_type, flags


def _dns_response(config: dict[str, Any], message: bytes) -> tuple[bytes, dict[str, Any]]:
    metadata, question, query_id, name, query_type, request_flags = _parse_dns_query(message)
    zone = str(config["dns"]["zone"]).lower()
    response_code = 0
    answer = b""
    answer_values: list[str] = []
    if name == "servfail." + zone:
        response_code = 2
    elif not name.endswith(zone):
        response_code = 3
    elif query_type == 1:
        import socket

        packed = socket.inet_pton(socket.AF_INET, str(config["dns"]["answer_ipv4"]))
        answer = b"\xc0\x0c" + struct.pack("!HHIH", 1, 1, 30, len(packed)) + packed
        answer_values.append(str(config["dns"]["answer_ipv4"]))
    elif query_type == 28:
        import socket

        packed = socket.inet_pton(socket.AF_INET6, str(config["dns"]["answer_ipv6"]))
        answer = b"\xc0\x0c" + struct.pack("!HHIH", 28, 1, 30, len(packed)) + packed
        answer_values.append(str(config["dns"]["answer_ipv6"]))
    else:
        response_code = 0
    response_flags = 0x8000 | 0x0400 | (request_flags & 0x0100) | response_code
    header = struct.pack("!HHHHHH", query_id, response_flags, 1, 1 if answer else 0, 0, 0)
    return header + question + answer, {
        **metadata,
        "query_id": query_id,
        "query_name": name,
        "query_type": query_type,
        "response_code": response_code,
        "answer_digest": _sha("\n".join(answer_values).encode("utf-8")),
    }


def _base_server_record(metadata: dict[str, Any], transport: str, local: Any, remote: Any, payload_hash: str, byte_count: int) -> dict[str, Any]:
    return {
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
        "protocol_family": metadata.get("protocol_family", ""),
        "transport": transport,
        "local_ip": str(local[0]) if local else "",
        "local_port": int(local[1]) if local else 0,
        "remote_ip": str(remote[0]) if remote else "",
        "remote_port": int(remote[1]) if remote else 0,
        "payload_sha256": payload_hash,
        "bytes": byte_count,
        "result": "PASS",
    }


class DnsDatagramProtocol(asyncio.DatagramProtocol):
    def __init__(self, config: dict[str, Any], evidence: EvidenceLog) -> None:
        self.config = config
        self.evidence = evidence
        self.transport: asyncio.DatagramTransport | None = None

    def connection_made(self, transport: asyncio.BaseTransport) -> None:
        self.transport = transport  # type: ignore[assignment]

    def datagram_received(self, data: bytes, address: Any) -> None:
        if self.transport is None:
            return
        try:
            response, details = _dns_response(self.config, data)
            self.transport.sendto(response, address)
            local = self.transport.get_extra_info("sockname")
            record = _base_server_record(details, "UDP", local, address, details["payload_sha256"], len(data))
            record.update({
                "dns_transport": "UDP",
                "query_id": details["query_id"],
                "query_name": details["query_name"],
                "query_type": details["query_type"],
                "response_code": details["response_code"],
                "answer_digest": details["answer_digest"],
                "truncated": False,
                "dnssec_status": "NOT_REQUESTED",
            })
            self.evidence.append(record)
        except ProtocolServerError:
            return


async def _dns_tcp(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, config: dict[str, Any], evidence: EvidenceLog) -> None:
    try:
        length = struct.unpack("!H", await reader.readexactly(2))[0]
        if length <= 0 or length > 65535:
            raise ProtocolServerError("DNS_TCP_LENGTH_INVALID")
        data = await reader.readexactly(length)
        response, details = _dns_response(config, data)
        writer.write(struct.pack("!H", len(response)) + response)
        await writer.drain()
        record = _base_server_record(details, "TCP", writer.get_extra_info("sockname"), writer.get_extra_info("peername"), details["payload_sha256"], len(data))
        record.update({"dns_transport": "TCP", "query_id": details["query_id"], "query_name": details["query_name"], "query_type": details["query_type"], "response_code": details["response_code"], "answer_digest": details["answer_digest"], "truncated": False, "dnssec_status": "NOT_REQUESTED"})
        evidence.append(record)
    except (asyncio.IncompleteReadError, ProtocolServerError):
        pass
    finally:
        writer.close()
        await writer.wait_closed()


async def _read_http_request(reader: asyncio.StreamReader) -> tuple[str, str, dict[str, str], bytes]:
    header = await reader.readuntil(b"\r\n\r\n")
    if len(header) > 65536:
        raise ProtocolServerError("HTTP_HEADER_TOO_LARGE")
    lines = header.decode("iso-8859-1").split("\r\n")
    request_line = lines[0].split(" ")
    if len(request_line) != 3 or request_line[2] != "HTTP/1.1":
        raise ProtocolServerError("HTTP_REQUEST_LINE_INVALID")
    headers: dict[str, str] = {}
    for line in lines[1:]:
        if not line:
            continue
        if ":" not in line:
            raise ProtocolServerError("HTTP_HEADER_INVALID")
        name, value = line.split(":", 1)
        headers[name.strip().lower()] = value.strip()
    if "transfer-encoding" in headers:
        raise ProtocolServerError("HTTP_TRANSFER_ENCODING_UNSUPPORTED")
    content_length = int(headers.get("content-length", "0"))
    if content_length < 0 or content_length > 1024 * 1024:
        raise ProtocolServerError("HTTP_BODY_TOO_LARGE")
    body = await reader.readexactly(content_length) if content_length else b""
    return request_line[0], request_line[1], headers, body


async def _http(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, evidence: EvidenceLog, secure: bool) -> None:
    try:
        method, path, headers, body = await _read_http_request(reader)
        if path == "/browser-origin" or path.startswith(("/browser-origin/", "/browser-origin?", "/browser-origin#", "/browser-origin%")):
            if method != "GET" or body:
                raise ProtocolServerError("BROWSER_ORIGIN_REQUEST_INVALID")
            try:
                origin = build_browser_origin_response(path)
            except BrowserOriginError as exc:
                raise ProtocolServerError(exc.code) from exc
            response_headers = [
                b"HTTP/1.1 200 OK",
                b"Content-Type: " + origin.content_type.encode("ascii"),
                b"Connection: close",
                b"Content-Length: " + str(len(origin.body)).encode("ascii"),
            ]
            for name, value in sorted(origin.headers.items()):
                response_headers.append(name.encode("ascii") + b": " + value.encode("ascii"))
            writer.write(b"\r\n".join(response_headers) + b"\r\n\r\n" + origin.body)
            await writer.drain()
            ssl_object = writer.get_extra_info("ssl_object")
            negotiated_protocol = ssl_object.selected_alpn_protocol() if ssl_object is not None else None
            record = dict(origin.evidence)
            record.update({
                "timestamp_utc": _utc(),
                "monotonic_ms": 0,
                "process_id": os.getpid(),
                "socket_id": 0,
                "protocol_family": "browser-origin",
                "transport": "TCP",
                "local_ip": str(writer.get_extra_info("sockname")[0]),
                "local_port": int(writer.get_extra_info("sockname")[1]),
                "remote_ip": str(writer.get_extra_info("peername")[0]),
                "remote_port": int(writer.get_extra_info("peername")[1]),
                "secure": secure,
                "negotiated_protocol": negotiated_protocol or "http/1.1",
                "status_code": origin.status_code,
            })
            evidence.append(record)
            return
        metadata = {
            "run_id": headers.get("x-testlab-run", ""),
            "scenario_id": headers.get("x-testlab-scenario", ""),
            "attempt_id": headers.get("x-testlab-attempt", ""),
            "flow_id": headers.get("x-testlab-flow", ""),
            "protocol_family": "http1",
        }
        if any(not metadata[key] for key in ("run_id", "scenario_id", "attempt_id", "flow_id")):
            raise ProtocolServerError("HTTP_METADATA_MISSING")
        request_hash = _sha(body)
        response_value = {"flow_id": metadata["flow_id"], "request_body_sha256": request_hash, "result": "PASS", "secure": secure}
        response_body = json.dumps(response_value, sort_keys=True, separators=(",", ":")).encode("utf-8")
        response = b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: " + str(len(response_body)).encode("ascii") + b"\r\n\r\n" + response_body
        writer.write(response)
        await writer.drain()
        record = _base_server_record(metadata, "TCP", writer.get_extra_info("sockname"), writer.get_extra_info("peername"), request_hash, len(body))
        record.update({"method": method, "authority": headers.get("host", ""), "path_digest": _sha(path.encode("utf-8")), "request_body_sha256": request_hash, "status_code": 200, "response_body_sha256": _sha(response_body), "connection_reused": False})
        evidence.append(record)
    except (asyncio.IncompleteReadError, asyncio.LimitOverrunError, ProtocolServerError, ValueError):
        pass
    finally:
        writer.close()
        try:
            await writer.wait_closed()
        except (ConnectionError, ssl.SSLError):
            pass


async def _tls_echo(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, evidence: EvidenceLog, certificate_sha256: str) -> None:
    try:
        line = await reader.readline()
        if not line or len(line) > 8192:
            raise ProtocolServerError("TLS_REQUEST_INVALID")
        value = json.loads(line.decode("utf-8"))
        if not isinstance(value, dict):
            raise ProtocolServerError("TLS_REQUEST_INVALID")
        for field in ("run_id", "scenario_id", "attempt_id", "flow_id", "payload_sha256"):
            if not isinstance(value.get(field), str) or not value[field]:
                raise ProtocolServerError("TLS_METADATA_MISSING")
        response = json.dumps({"flow_id": value["flow_id"], "payload_sha256": value["payload_sha256"], "result": "PASS"}, sort_keys=True, separators=(",", ":")).encode("utf-8") + b"\n"
        writer.write(response)
        await writer.drain()
        ssl_object = writer.get_extra_info("ssl_object")
        cipher = ssl_object.cipher() if ssl_object else None
        record = _base_server_record({**value, "protocol_family": "tls"}, "TCP", writer.get_extra_info("sockname"), writer.get_extra_info("peername"), value["payload_sha256"], len(line))
        record.update({"tls_version": ssl_object.version() if ssl_object else "", "cipher_suite": cipher[0] if cipher else "", "server_name": "proxybridge-testlab.test", "alpn": ssl_object.selected_alpn_protocol() if ssl_object else "", "peer_certificate_sha256": certificate_sha256, "resumed": bool(ssl_object.session_reused) if ssl_object else False, "shutdown_status": "GRACEFUL"})
        evidence.append(record)
    except (asyncio.IncompleteReadError, json.JSONDecodeError, ProtocolServerError):
        pass
    finally:
        writer.close()
        try:
            await writer.wait_closed()
        except (ConnectionError, ssl.SSLError):
            pass


async def _http2(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, evidence: EvidenceLog, grpc: bool) -> None:
    from h2.config import H2Configuration
    from h2.connection import H2Connection
    from h2.events import DataReceived, RequestReceived, StreamEnded

    connection = H2Connection(config=H2Configuration(client_side=False, header_encoding="utf-8"))
    streams: dict[int, dict[str, Any]] = {}
    try:
        ssl_object = writer.get_extra_info("ssl_object")
        if ssl_object is None or ssl_object.selected_alpn_protocol() != "h2":
            raise ProtocolServerError("HTTP2_ALPN_REQUIRED")
        connection.initiate_connection()
        writer.write(connection.data_to_send())
        await writer.drain()
        while True:
            data = await reader.read(65535)
            if not data:
                break
            for event in connection.receive_data(data):
                if isinstance(event, RequestReceived):
                    streams[event.stream_id] = {"headers": {str(name): str(value) for name, value in event.headers}, "body": bytearray()}
                elif isinstance(event, DataReceived):
                    state = streams.get(event.stream_id)
                    if state is None:
                        raise ProtocolServerError("HTTP2_STREAM_STATE_MISSING")
                    state["body"].extend(event.data)
                    connection.acknowledge_received_data(event.flow_controlled_length, event.stream_id)
                elif isinstance(event, StreamEnded):
                    state = streams.pop(event.stream_id, None)
                    if state is None:
                        raise ProtocolServerError("HTTP2_STREAM_STATE_MISSING")
                    headers = state["headers"]
                    body = bytes(state["body"])
                    metadata = {
                        "run_id": headers.get("x-testlab-run", ""),
                        "scenario_id": headers.get("x-testlab-scenario", ""),
                        "attempt_id": headers.get("x-testlab-attempt", ""),
                        "flow_id": headers.get("x-testlab-flow", ""),
                        "protocol_family": "grpc" if grpc else "http2",
                    }
                    if any(not metadata[field] for field in ("run_id", "scenario_id", "attempt_id", "flow_id")):
                        raise ProtocolServerError("HTTP2_METADATA_MISSING")
                    if grpc:
                        if len(body) < 5 or body[0] != 0 or int.from_bytes(body[1:5], "big") != len(body) - 5:
                            raise ProtocolServerError("GRPC_REQUEST_FRAME_INVALID")
                        payload = body[5:]
                        response_body = b"\x00" + len(payload).to_bytes(4, "big") + payload
                        connection.send_headers(event.stream_id, [(":status", "200"), ("content-type", "application/grpc")])
                        connection.send_data(event.stream_id, response_body)
                        connection.send_headers(event.stream_id, [("grpc-status", "0")], end_stream=True)
                        path_parts = headers.get(":path", "").strip("/").split("/", 1)
                        if len(path_parts) != 2:
                            raise ProtocolServerError("GRPC_METHOD_INVALID")
                        record = _base_server_record(metadata, "TCP", writer.get_extra_info("sockname"), writer.get_extra_info("peername"), _sha(payload), len(payload))
                        record.update({"rpc_protocol": "grpc", "service": path_parts[0], "method": path_parts[1], "request_sha256": _sha(payload), "response_sha256": _sha(payload), "application_status": "0"})
                    else:
                        request_hash = _sha(body)
                        response_value = {"flow_id": metadata["flow_id"], "request_body_sha256": request_hash, "result": "PASS"}
                        response_body = json.dumps(response_value, sort_keys=True, separators=(",", ":")).encode("utf-8")
                        connection.send_headers(event.stream_id, [(":status", "200"), ("content-type", "application/json"), ("content-length", str(len(response_body)))])
                        connection.send_data(event.stream_id, response_body, end_stream=True)
                        record = _base_server_record(metadata, "TCP", writer.get_extra_info("sockname"), writer.get_extra_info("peername"), request_hash, len(body))
                        record.update({"alpn": "h2", "stream_id": event.stream_id, "method": headers.get(":method", ""), "status_code": 200, "request_body_sha256": request_hash, "response_body_sha256": _sha(response_body), "end_stream": True, "flow_control_complete": True})
                    evidence.append(record)
            pending = connection.data_to_send()
            if pending:
                writer.write(pending)
                await writer.drain()
    except (asyncio.IncompleteReadError, ProtocolServerError, ValueError):
        pass
    finally:
        writer.close()
        try:
            await writer.wait_closed()
        except (ConnectionError, ssl.SSLError):
            pass


async def _read_websocket_frame(reader: asyncio.StreamReader) -> tuple[int, bytes]:
    first, second = await reader.readexactly(2)
    if not first & 0x80 or not second & 0x80:
        raise ProtocolServerError("WEBSOCKET_CLIENT_FRAME_INVALID")
    opcode = first & 0x0F
    length = second & 0x7F
    if length == 126:
        length = struct.unpack("!H", await reader.readexactly(2))[0]
    elif length == 127:
        raise ProtocolServerError("WEBSOCKET_FRAME_SIZE_INVALID")
    if length > 65535:
        raise ProtocolServerError("WEBSOCKET_FRAME_SIZE_INVALID")
    mask = await reader.readexactly(4)
    encoded = await reader.readexactly(length)
    return opcode, bytes(value ^ mask[index % 4] for index, value in enumerate(encoded))


def _websocket_frame(opcode: int, payload: bytes) -> bytes:
    if len(payload) <= 125:
        return bytes([0x80 | opcode, len(payload)]) + payload
    if len(payload) <= 65535:
        return bytes([0x80 | opcode, 126]) + struct.pack("!H", len(payload)) + payload
    raise ProtocolServerError("WEBSOCKET_FRAME_SIZE_INVALID")


async def _websocket(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, evidence: EvidenceLog) -> None:
    try:
        method, path, headers, body = await _read_http_request(reader)
        if method != "GET" or body or headers.get("upgrade", "").lower() != "websocket" or "upgrade" not in headers.get("connection", "").lower():
            raise ProtocolServerError("WEBSOCKET_UPGRADE_INVALID")
        key = headers.get("sec-websocket-key", "")
        subprotocol = headers.get("sec-websocket-protocol", "")
        try:
            if len(base64.b64decode(key, validate=True)) != 16:
                raise ValueError
        except ValueError as exc:
            raise ProtocolServerError("WEBSOCKET_KEY_INVALID") from exc
        metadata = {
            "run_id": headers.get("x-testlab-run", ""),
            "scenario_id": headers.get("x-testlab-scenario", ""),
            "attempt_id": headers.get("x-testlab-attempt", ""),
            "flow_id": headers.get("x-testlab-flow", ""),
            "protocol_family": "websocket",
        }
        if any(not metadata[field] for field in ("run_id", "scenario_id", "attempt_id", "flow_id")):
            raise ProtocolServerError("WEBSOCKET_METADATA_MISSING")
        accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode("ascii"), usedforsecurity=False).digest()).decode("ascii")
        response = "\r\n".join(["HTTP/1.1 101 Switching Protocols", "Upgrade: websocket", "Connection: Upgrade", f"Sec-WebSocket-Accept: {accept}", f"Sec-WebSocket-Protocol: {subprotocol}", "", ""])
        writer.write(response.encode("ascii"))
        await writer.drain()
        opcode, payload = await _read_websocket_frame(reader)
        if opcode != 2:
            raise ProtocolServerError("WEBSOCKET_MESSAGE_TYPE_INVALID")
        writer.write(_websocket_frame(2, payload))
        await writer.drain()
        close_opcode, close_payload = await _read_websocket_frame(reader)
        close_code = struct.unpack("!H", close_payload[:2])[0] if close_opcode == 8 and len(close_payload) >= 2 else 0
        writer.write(_websocket_frame(8, struct.pack("!H", 1000)))
        await writer.drain()
        payload_hash = _sha(payload)
        record = _base_server_record(metadata, "TCP", writer.get_extra_info("sockname"), writer.get_extra_info("peername"), payload_hash, len(payload))
        record.update({"upgrade_status": 101, "subprotocol": subprotocol, "message_type": "binary", "message_sha256": payload_hash, "echo_sha256": payload_hash, "close_code": close_code})
        evidence.append(record)
    except (asyncio.IncompleteReadError, asyncio.LimitOverrunError, ProtocolServerError, ValueError):
        pass
    finally:
        writer.close()
        try:
            await writer.wait_closed()
        except (ConnectionError, ssl.SSLError):
            pass


class _Http3ServerProtocolBase:
    """Marker used to keep aioquic imports outside the dependency-free self-test path."""


def _http3_protocol_factory(evidence: EvidenceLog, mode: str, local_address: tuple[str, int]) -> Any:
    try:
        from aioquic.asyncio.protocol import QuicConnectionProtocol
        from aioquic.h3.connection import H3Connection
        from aioquic.h3.events import DataReceived, DatagramReceived, HeadersReceived
    except ImportError as exc:
        raise ProtocolServerError("QUIC_DEPENDENCY_UNAVAILABLE") from exc

    class Http3ServerProtocol(QuicConnectionProtocol, _Http3ServerProtocolBase):
        def __init__(self, *args: Any, **kwargs: Any) -> None:
            super().__init__(*args, **kwargs)
            self._http = H3Connection(self._quic, enable_webtransport=mode == "webtransport")
            self._requests: dict[int, dict[str, Any]] = {}
            self._webtransport_sessions: dict[int, dict[str, Any]] = {}

        def quic_event_received(self, event: Any) -> None:
            try:
                for http_event in self._http.handle_event(event):
                    if isinstance(http_event, HeadersReceived):
                        state = {
                            "headers": {key.decode("ascii"): value.decode("utf-8") for key, value in http_event.headers},
                            "body": bytearray(),
                        }
                        self._requests[http_event.stream_id] = state
                        if mode == "webtransport" and state["headers"].get(":method") == "CONNECT":
                            self._accept_webtransport(http_event.stream_id, state)
                        elif http_event.stream_ended:
                            self._complete_http3(http_event.stream_id)
                    elif isinstance(http_event, DataReceived):
                        state = self._requests.get(http_event.stream_id)
                        if state is None:
                            raise ProtocolServerError("HTTP3_STREAM_STATE_MISSING")
                        state["body"].extend(http_event.data)
                        if http_event.stream_ended:
                            self._complete_http3(http_event.stream_id)
                    elif isinstance(http_event, DatagramReceived):
                        self._complete_webtransport(http_event.stream_id, http_event.data)
            except (ProtocolServerError, UnicodeDecodeError, ValueError):
                self.close(error_code=0x102, reason_phrase="PROTOCOL_CONTRACT_FAILED")
            finally:
                self.transmit()

        def _metadata(self, headers: dict[str, str], family: str) -> dict[str, Any]:
            metadata = {
                "run_id": headers.get("x-testlab-run", ""),
                "scenario_id": headers.get("x-testlab-scenario", ""),
                "attempt_id": headers.get("x-testlab-attempt", ""),
                "flow_id": headers.get("x-testlab-flow", ""),
                "protocol_family": family,
            }
            if any(not metadata[field] for field in ("run_id", "scenario_id", "attempt_id", "flow_id")):
                raise ProtocolServerError("HTTP3_METADATA_MISSING")
            return metadata

        def _remote_address(self) -> Any:
            paths = getattr(self._quic, "_network_paths", [])
            return paths[0].addr if paths else None

        def _local_address(self) -> Any:
            transport = getattr(self, "_transport", None)
            return transport.get_extra_info("sockname") if transport is not None else local_address

        def _quic_fields(self, stream_id: int, response_hash: str, status_code: int) -> dict[str, Any]:
            version = getattr(self._quic, "_version", 0)
            connection_id = bytes(getattr(self._quic, "host_cid", b""))
            return {
                "quic_version": f"0x{int(version):08x}",
                "alpn": "h3",
                "connection_id_digest": _sha(connection_id),
                "stream_id": stream_id,
                "handshake_complete": True,
                "status_code": status_code,
                "response_body_sha256": response_hash,
                "migration_status": "NOT_ATTEMPTED",
            }

        def _complete_http3(self, stream_id: int) -> None:
            state = self._requests.pop(stream_id, None)
            if state is None:
                raise ProtocolServerError("HTTP3_STREAM_STATE_MISSING")
            headers = state["headers"]
            body = bytes(state["body"])
            metadata = self._metadata(headers, "quic-http3")
            request_hash = _sha(body)
            response_body = json.dumps(
                {"flow_id": metadata["flow_id"], "request_body_sha256": request_hash, "result": "PASS"},
                sort_keys=True,
                separators=(",", ":"),
            ).encode("utf-8")
            self._http.send_headers(stream_id, [(b":status", b"200"), (b"content-type", b"application/json")])
            self._http.send_data(stream_id, response_body, end_stream=True)
            record = _base_server_record(metadata, "UDP", self._local_address(), self._remote_address(), request_hash, len(body))
            record.update(self._quic_fields(stream_id, _sha(response_body), 200))
            evidence.append(record)

        def _accept_webtransport(self, stream_id: int, state: dict[str, Any]) -> None:
            headers = state["headers"]
            if headers.get(":protocol") != "webtransport" or headers.get(":path") != "/webtransport":
                raise ProtocolServerError("WEBTRANSPORT_CONNECT_INVALID")
            metadata = self._metadata(headers, "webtransport")
            self._webtransport_sessions[stream_id] = metadata
            self._http.send_headers(stream_id, [(b":status", b"200"), (b"sec-webtransport-http3-draft", b"draft02")])

        def _complete_webtransport(self, stream_id: int, payload: bytes) -> None:
            metadata = self._webtransport_sessions.get(stream_id)
            if metadata is None or not payload or len(payload) > 65535:
                raise ProtocolServerError("WEBTRANSPORT_DATAGRAM_INVALID")
            self._http.send_datagram(stream_id, payload)
            payload_hash = _sha(payload)
            record = _base_server_record(metadata, "UDP", self._local_address(), self._remote_address(), payload_hash, len(payload))
            record.update(self._quic_fields(stream_id, payload_hash, 200))
            evidence.append(record)

    return Http3ServerProtocol


async def _serve(config: dict[str, Any]) -> None:
    evidence = EvidenceLog(str(config["jsonl_log"]))
    tls_echo_context = _ssl_context(config, ("pb-test/1",))
    http1_context = _ssl_context(config, ("http/1.1",))
    http2_context = _ssl_context(config, ("h2",))
    standard_tls_context = _ssl_context(config, ())
    loop = asyncio.get_running_loop()
    servers: list[asyncio.AbstractServer] = []
    transports: list[asyncio.DatagramTransport] = []
    quic_servers: list[Any] = []
    bind_addresses = [str(config["bind_ipv4"])]
    if str(config.get("bind_ipv6", "")):
        bind_addresses.append(str(config["bind_ipv6"]))
    bound_ports: dict[str, int] = {}
    for address_index, bind in enumerate(bind_addresses):
        dns_requested = bound_ports.get("dns", int(config["dns"]["port"]))
        transport, _ = await loop.create_datagram_endpoint(lambda: DnsDatagramProtocol(config, evidence), local_addr=(bind, dns_requested))
        transports.append(transport)  # type: ignore[arg-type]
        dns_actual = int(transport.get_extra_info("sockname")[1])
        if address_index == 0:
            bound_ports["dns"] = dns_actual
        servers.append(await asyncio.start_server(lambda r, w: _dns_tcp(r, w, config, evidence), bind, dns_actual))
        for name, handler, ssl_value in (
            ("http", lambda r, w: _http(r, w, evidence, False), None),
            ("tls", lambda r, w: _tls_echo(r, w, evidence, str(config["tls"]["certificate_sha256"])), tls_echo_context),
            ("https", lambda r, w: _http(r, w, evidence, True), http1_context),
            ("http2", lambda r, w: _http2(r, w, evidence, False), http2_context),
            ("websocket", lambda r, w: _websocket(r, w, evidence), http1_context),
            ("grpc", lambda r, w: _http2(r, w, evidence, True), http2_context),
        ):
            requested = bound_ports.get(name, int(config[name]["port"]))
            server = await asyncio.start_server(handler, bind, requested, ssl=ssl_value)
            servers.append(server)
            actual = int(server.sockets[0].getsockname()[1])
            if address_index == 0:
                bound_ports[name] = actual
        try:
            from aioquic.asyncio import serve as serve_quic
        except ImportError as exc:
            raise ProtocolServerError("QUIC_DEPENDENCY_UNAVAILABLE") from exc
        for name, mode in (("quic_http3", "http3"), ("webtransport", "webtransport")):
            requested = bound_ports.get(name, int(config[name]["port"]))
            local_address = (bind, requested)
            quic_server = await serve_quic(
                bind,
                requested,
                configuration=_quic_configuration(config),
                create_protocol=partial(_http3_protocol_factory(evidence, mode, local_address)),
            )
            quic_servers.append(quic_server)
            transport = getattr(quic_server, "_transport", None)
            actual = int(transport.get_extra_info("sockname")[1]) if transport is not None else requested
            if address_index == 0:
                bound_ports[name] = actual
        try:
            from standard_protocols import start_standard_protocols
        except ImportError as exc:
            raise ProtocolServerError("STANDARD_PROTOCOL_MODULE_UNAVAILABLE") from exc
        standard_servers, standard_transports, standard_ports = await start_standard_protocols(bind, config, evidence.append, standard_tls_context, bound_ports)
        servers.extend(standard_servers)
        transports.extend(standard_transports)
        if address_index == 0:
            bound_ports.update(standard_ports)
        try:
            from realtime_protocols import start_realtime_protocols
        except ImportError as exc:
            raise ProtocolServerError("REALTIME_PROTOCOL_MODULE_UNAVAILABLE") from exc
        realtime_transports, realtime_ports = await start_realtime_protocols(bind, config, evidence.append, bound_ports)
        transports.extend(realtime_transports)
        if address_index == 0:
            bound_ports.update(realtime_ports)
        try:
            from failure_protocols import start_failure_protocols
        except ImportError as exc:
            raise ProtocolServerError("FAILURE_PROTOCOL_MODULE_UNAVAILABLE") from exc
        failure_servers, failure_ports = await start_failure_protocols(bind, config, evidence.append, bound_ports)
        servers.extend(failure_servers)
        if address_index == 0:
            bound_ports.update(failure_ports)
    ready_order = ("dns", "http", "tls", "https", "http2", "quic_http3", "websocket", "grpc", "webtransport", "ftp", "ftp_data", "smtp", "smtps", "imap", "imaps", "pop3", "pop3s", "mqtt", "mqtts", "amqp", "amqps", "ntp", "irc", "ircs", "multipeer", "stun_turn", "rtp_media", "receive_only", "failure_control")
    print("PROTOCOL_SERVER_READY " + " ".join(f"{name}={bound_ports[name]}" for name in ready_order), flush=True)
    try:
        await asyncio.gather(*(server.serve_forever() for server in servers))
    finally:
        for transport in transports:
            transport.close()
        for quic_server in quic_servers:
            quic_server.close()
        for server in servers:
            server.close()
        await asyncio.gather(*(server.wait_closed() for server in servers), return_exceptions=True)


def main() -> int:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--config", required=True)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--serve", action="store_true")
    arguments = parser.parse_args()
    if arguments.self_test == arguments.serve:
        print("PROTOCOL_SERVER_ERROR MODE_INVALID", file=sys.stderr)
        return 40
    try:
        config = _load_config(Path(arguments.config))
        _ssl_context(config, ())
        _quic_configuration(config)
        try:
            from negative_proxy import self_test as negative_proxy_self_test
            negative_proxy_self_test(config["negative_proxy"])
        except ImportError as exc:
            raise ProtocolServerError("NEGATIVE_PROXY_MODULE_UNAVAILABLE") from exc
        if arguments.self_test:
            print("PROTOCOL_SERVER_SELF_TEST_OK services=29")
            return 0
        asyncio.run(_serve(config))
        return 0
    except ProtocolServerError as exc:
        print(f"PROTOCOL_SERVER_ERROR {exc}", file=sys.stderr)
        return 41
    except Exception:
        print("PROTOCOL_SERVER_ERROR UNEXPECTED_FAILURE", file=sys.stderr)
        return 42


if __name__ == "__main__":
    raise SystemExit(main())
