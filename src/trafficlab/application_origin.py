"""Bounded HTTP/1.1, TLS, HTTPS, WebSocket and authoritative DNS origins."""
from __future__ import annotations
import asyncio
import base64
import hashlib
import json
import ssl
import struct
from pathlib import Path
from typing import Any
from trafficlab.application_wire import (APPLICATION_PORTS, WS_GUID, dns_decode, dns_response,
                                         response, validate, websocket_frame)
from trafficlab.protocol import MAX_LINE, json_bytes


class ApplicationOrigins:
    def __init__(self, agent: Any, config: dict[str, Any]) -> None:
        self.agent = agent
        self.ports = dict(config.get("application_ports", {}))
        if self.ports and (set(self.ports) != set(APPLICATION_PORTS) or any(type(port) is not int or not 1 <= port <= 65535 for port in self.ports.values())):
            raise ValueError("APPLICATION_PORTS_INVALID")
        self.servers: list[Any] = []
        self.quic = None
        self.certificate = config.get("tls_certificate_file")
        self.key = config.get("tls_key_file")
        self.ca = config.get("tls_ca_file")
        self.ssh_key = config.get('ssh_host_key_file')
        self.ssh = None

    def tls_identity(self) -> dict[str, Any]:
        if not self.ports:
            return {}
        cert = Path(self.certificate).read_text(encoding="ascii")
        ca = Path(self.ca).read_text(encoding="ascii")
        if len(cert) > 8192 or len(ca) > 8192:
            raise ValueError("APPLICATION_CERTIFICATE_INVALID")
        identity = {"tls_ca_pem": ca, "tls_certificate_sha256": hashlib.sha256(ssl.PEM_cert_to_DER_cert(cert)).hexdigest()}
        if self.ssh_key:
            from trafficlab.dependencies import enable
            enable()
            import asyncssh
            key = asyncssh.read_private_key(self.ssh_key)
            identity.update(ssh_host_public_key=key.export_public_key('openssh').decode().strip(),
                            ssh_host_key_sha256=key.get_fingerprint('sha256'))
        return identity

    def authenticate(self, message: dict[str, Any], kind: str, peer: list[Any], session: dict[str, Any] | None) -> tuple[dict[str, Any], dict[str, Any], bytes | None]:
        if not isinstance(message, dict) or not isinstance(message.get("identity"), dict):
            raise ValueError("APPLICATION_MESSAGE_INVALID")
        identity = validate(self.agent.secret, message["identity"], kind)
        run_id, flow_id = identity["run_id"], identity["flow_id"]
        row = self.agent.metrics(run_id)
        flows = row.setdefault("application_flows", {})
        if len(flows) >= 64 and flow_id not in flows:
            raise ValueError("APPLICATION_FLOW_LIMIT")
        if session and session.get("identity") not in (None, (run_id, flow_id)):
            raise ValueError("APPLICATION_CONNECTION_IDENTITY_CHANGED")
        existing = flows.get(flow_id)
        if existing and (existing["peer"] != peer or identity["sequence"] <= existing["last_sequence"]):
            raise ValueError("APPLICATION_REPLAY_OR_PEER_CHANGED")
        payload = None
        if kind != "dns":
            payload = base64.b64decode(message["payload"], validate=True)
            if not payload or len(payload) > 4096 or hashlib.sha256(payload).hexdigest() != identity["payload_sha256"]:
                raise ValueError("APPLICATION_PAYLOAD_MISMATCH")
        if not existing:
            flows[flow_id] = {"peer": peer, "transactions": 0, "last_sequence": -1, "application": kind}
            if session is not None:
                row["accepted"] += 1
                row["active"] += 1
                row["tcp_active_peak"] = max(row["tcp_active_peak"], row["active"])
                session.update(identity=(run_id, flow_id), row=row)
                self.agent.proxy.observe_application(run_id, flow_id, peer)
            else:
                row["udp_flows"][flow_id] = True
        flows[flow_id]["transactions"] += 1
        flows[flow_id]["last_sequence"] = identity["sequence"]
        return identity, row, payload

    def dns(self, packet: bytes, peer: list[Any], session: dict[str, Any] | None = None) -> bytes:
        identity, question = dns_decode(packet, self.agent.runs)
        value, row, _ = self.authenticate({"identity": identity}, "dns", peer, session)
        if session is None:
            row["udp_received"] += 1
        return dns_response(packet, question, response(self.agent.secret, value, peer))

    async def headers(self, reader: asyncio.StreamReader) -> tuple[str, dict[str, str]]:
        raw = await reader.readuntil(b"\r\n\r\n")
        if len(raw) > MAX_LINE:
            raise ValueError("APPLICATION_HTTP_HEADERS_TOO_LARGE")
        lines = raw.decode("ascii").split("\r\n")
        headers = {}
        for line in lines[1:-2]:
            key, value = line.split(":", 1)
            key = key.lower()
            if key in headers:
                raise ValueError("APPLICATION_HTTP_DUPLICATE_HEADER")
            headers[key] = value.strip()
        if "transfer-encoding" in headers:
            raise ValueError("APPLICATION_HTTP_TRANSFER_ENCODING_UNSUPPORTED")
        return lines[0], headers

    async def ws_read(self, reader: asyncio.StreamReader) -> tuple[int, bytes]:
        first, second = await reader.readexactly(2)
        if not first & 0x80 or first & 0x70 or not second & 0x80 or second & 127 == 127 or first & 15 not in (2, 8, 9, 10):
            raise ValueError("APPLICATION_WEBSOCKET_FRAME_INVALID")
        size = second & 127
        if size == 126:
            size = struct.unpack("!H", await reader.readexactly(2))[0]
        if size > MAX_LINE or (first & 15 >= 8 and size > 125):
            raise ValueError("APPLICATION_WEBSOCKET_FRAME_INVALID")
        key = await reader.readexactly(4)
        data = await reader.readexactly(size)
        return first & 15, bytes(byte ^ key[index % 4] for index, byte in enumerate(data))

    async def connection(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter, kind: str) -> None:
        task = asyncio.current_task()
        self.agent.tasks.add(task)
        session: dict[str, Any] = {}
        admitted = False
        try:
            if self.agent.active >= self.agent.max_connections:
                raise ValueError("APPLICATION_CONNECTION_LIMIT")
            self.agent.active += 1
            admitted = True
            peer = list(writer.get_extra_info("peername")[:2])
            if kind in ('smtp', 'smtps', 'imap', 'imaps', 'mqtt', 'mqtts', 'pop3', 'pop3s'):
                from trafficlab.messaging_origin import serve
                await asyncio.wait_for(serve(self, reader, writer, kind, session, peer), 150)
                return
            if kind in ('http2', 'grpc'):
                from trafficlab.http_two import serve
                await asyncio.wait_for(serve(self, reader, writer, kind, session, peer), 150)
                return
            async def exchange() -> None:
                if kind == "websocket":
                    line, headers = await self.headers(reader)
                    key = headers.get("sec-websocket-key", "")
                    if line != "GET /testlab HTTP/1.1" or headers.get("upgrade", "").lower() != "websocket" or "upgrade" not in {token.strip() for token in headers.get("connection", "").lower().split(",")} or headers.get("sec-websocket-version") != "13" or len(base64.b64decode(key, validate=True)) != 16:
                        raise ValueError("APPLICATION_WEBSOCKET_UPGRADE_INVALID")
                    accept = base64.b64encode(hashlib.sha1((key + WS_GUID).encode()).digest()).decode()
                    writer.write(f"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {accept}\r\n\r\n".encode())
                    await writer.drain()
                while True:
                    if kind == "dns-tcp":
                        size = struct.unpack("!H", await reader.readexactly(2))[0]
                        if size > 512:
                            raise ValueError("APPLICATION_DNS_LENGTH_INVALID")
                        reply = self.dns(await reader.readexactly(size), peer, session)
                        writer.write(struct.pack("!H", len(reply)) + reply)
                    else:
                        if kind in ("http", "https"):
                            line, headers = await self.headers(reader)
                            size = int(headers.get("content-length", "-1"))
                            if line != "POST /testlab HTTP/1.1" or not 0 < size <= MAX_LINE or headers.get("content-type") != "application/json":
                                raise ValueError("APPLICATION_HTTP_REQUEST_INVALID")
                            data = await reader.readexactly(size)
                        elif kind == "websocket":
                            opcode, data = await self.ws_read(reader)
                            if opcode in (8, 9):
                                writer.write(websocket_frame(data, False, 8 if opcode == 8 else 10))
                                await writer.drain()
                                if opcode == 8:
                                    return
                                continue
                            if opcode != 2:
                                raise ValueError("APPLICATION_WEBSOCKET_OPCODE_INVALID")
                        else:
                            data = await reader.readline()
                            if not data.endswith(b"\n") or len(data) > MAX_LINE:
                                raise ValueError("APPLICATION_TLS_MESSAGE_INVALID")
                        message = json.loads(data)
                        value, row, payload = self.authenticate(message, kind, peer, session)
                        row["rx_bytes"] += len(payload)
                        reply = json_bytes(response(self.agent.secret, value, peer, message["payload"]))
                        row["tx_bytes"] += len(payload)
                        if kind in ("http", "https"):
                            connection = "close" if kind == "https" and message.get("close") is True else "keep-alive"
                            writer.write(f"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {len(reply)}\r\nConnection: {connection}\r\n\r\n".encode() + reply)
                        elif kind == "websocket":
                            writer.write(websocket_frame(reply, False))
                        else:
                            writer.write(reply + b"\n")
                    await writer.drain()
                    if kind in ("tls", "https") and message.get("close") is True:
                        return
            await asyncio.wait_for(exchange(), 150)
        except (OSError, ValueError, KeyError, IndexError, TypeError, UnicodeError, asyncio.TimeoutError, asyncio.LimitOverrunError, asyncio.IncompleteReadError):
            pass  # An incomplete client transaction remains FAIL; never manufacture a response.
        finally:
            if session.get("row") is not None:
                session["row"]["active"] -= 1
                session["row"]["completed"] += 1
            if admitted:
                self.agent.active -= 1
            self.agent.tasks.discard(task)
            writer.close()
            try:
                await writer.wait_closed()
            except OSError:
                pass

    async def start(self, bind: str) -> None:
        for kind, port in self.ports.items():
            if kind in ('quic', 'http3'):
                if self.quic is None:
                    from trafficlab.quic_origin import QuicOrigin
                    self.quic = QuicOrigin(self)
                self.servers.append(await self.quic.start(bind, port, kind))
                continue
            if kind in ('ssh', 'sftp'):
                if self.ssh is None:
                    from trafficlab.ssh_origin import SshOrigin
                    self.ssh = SshOrigin(self, self.ssh_key)
                self.servers.append(await self.ssh.start(bind, port))
                continue
            if kind == "dns-udp":
                transport, _ = await asyncio.get_running_loop().create_datagram_endpoint(lambda: DnsDatagrams(self), local_addr=(bind, port))
                self.servers.append(transport)
                continue
            context = None
            if kind in ("tls", "https", "http2", "grpc", "smtps", "imaps", "mqtts", "pop3s"):
                context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
                context.minimum_version = ssl.TLSVersion.TLSv1_2
                context.load_cert_chain(self.certificate, self.key)
                context.set_alpn_protocols(['h2' if kind in ('http2', 'grpc') else "http/1.1" if kind == "https" else
                    'mqtt' if kind == 'mqtts' else 'testlab-mail/1' if kind in ('smtps','imaps','pop3s') else "testlab/1"])
            self.servers.append(await asyncio.start_server(lambda reader, writer, kind=kind: self.connection(reader, writer, kind), bind, port, ssl=context, limit=MAX_LINE + 1))

    async def close(self) -> None:
        if self.quic is not None:
            self.quic.close()
        if self.ssh is not None:
            await self.ssh.close()
        for server in self.servers:
            server.close()
        for server in self.servers:
            if hasattr(server, "wait_closed"):
                await server.wait_closed()


class DnsDatagrams(asyncio.DatagramProtocol):
    def __init__(self, origins: ApplicationOrigins) -> None:
        self.origins = origins

    def connection_made(self, transport: Any) -> None:
        self.transport = transport

    def datagram_received(self, packet: bytes, peer: tuple[str, int]) -> None:
        try:
            self.transport.sendto(self.origins.dns(packet, list(peer[:2])), peer)
        except (OSError, ValueError, KeyError, IndexError, TypeError, UnicodeError):
            pass
