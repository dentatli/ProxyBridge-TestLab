"""Authenticated, resource-bounded TCP/UDP measurement origin. No product operations."""
from __future__ import annotations

import argparse
import asyncio
import collections
import hashlib
import hmac
import json
import os
import secrets
import signal
import socket
import time
from pathlib import Path
from typing import Any

from trafficlab.protocol import BLOCK, FRAME, MAX_CHUNK, MAX_LINE, json_bytes, mac, pattern, validate_request, verify_mac


class Agent:
    def __init__(self, secret: bytes, max_connections: int = 2048) -> None:
        if len(secret) != 32 or not 1 <= max_connections <= 4096:
            raise ValueError("TRAFFIC_AGENT_CONFIG_INVALID")
        self.secret = secret
        self.max_connections = max_connections
        self.active = 0
        self.origin_tcp_ports: set[int] = set()
        self.runs: collections.OrderedDict[str, dict[str, Any]] = collections.OrderedDict()
        self.tasks: set[asyncio.Task[Any]] = set()
        self.configuration_path: Path | None = None
        self.applications: Any = None
        self.identity_mode = 'remote'
        self.native = None
        self.origin_udp_receive_buffer: dict[str, int] | None = None

    def identity(self) -> dict[str, Any]:
        if self.configuration_path is None:
            return {"verified": False, "scope": "component-only"}
        try:
            if self.identity_mode == 'local-windows-v1':
                from trafficlab.local_runtime import identity
                return identity(self.configuration_path, self.applications)
            root = self.configuration_path.parent
            manifest = json.loads((root / "runtime-manifest.json").read_text())
            import re
            for name, expected in manifest["hashes"].items():
                if not re.fullmatch(r"(?:trafficlab/[a-z_]+\.py|traffic-workloads\.json|traffic-dependencies\.lock\.json|wheels/[A-Za-z0-9_.-]+\.whl)", name):
                    raise ValueError("TRAFFIC_MANIFEST_PATH_INVALID")
                path = root / name
                if path.is_symlink() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
                    raise ValueError("TRAFFIC_IDENTITY_MISMATCH")
            if hashlib.sha256(self.configuration_path.read_bytes()).hexdigest() != manifest["config_sha256"]:
                raise ValueError("TRAFFIC_CONFIG_MISMATCH")
            if self.applications and self.applications.ports:
                for name in ("ca.pem", "server.pem", "server.key", 'ssh_host.key'):
                    path = root / "pki" / name
                    if path.is_symlink() or hashlib.sha256(path.read_bytes()).hexdigest() != manifest.get("pki_hashes", {}).get(name):
                        raise ValueError("APPLICATION_PKI_IDENTITY_CHANGED")
            from trafficlab.dependencies import verify
            verify()
            return {"verified": True, "bundle_sha256": manifest["bundle_sha256"],
                    "application": self.applications.tls_identity() if self.applications else {},
                    "scope": "current-runtime-files-private-configuration-and-application-PKI"}
        except (OSError, ValueError, KeyError, TypeError):
            return {"verified": False, "scope": "current-runtime-files-and-private-configuration"}

    def metrics(self, run_id: str) -> dict[str, Any]:
        if run_id not in self.runs:
            if len(self.runs) >= 128:
                idle = next((key for key, row in self.runs.items() if row["active"] == 0), None)
                if idle is None:
                    raise ValueError("TRAFFIC_SESSION_LIMIT")
                del self.runs[idle]
            self.runs[run_id] = {"accepted": 0, "completed": 0, "active": 0, "errors": 0,
                                 "tcp_active_peak": 0,
                                 "rx_bytes": 0, "tx_bytes": 0, "udp_received": 0,
                                 "udp_reply_errors": 0, "route_samples": [], "udp_flows": {}}
        self.runs.move_to_end(run_id)
        return self.runs[run_id]

    async def header(self, reader: asyncio.StreamReader, timeout: float = 10) -> dict[str, Any]:
        line = await asyncio.wait_for(reader.readline(), timeout)
        if not line.endswith(b"\n") or len(line) > MAX_LINE:
            raise ValueError("TRAFFIC_HEADER_INVALID")
        request = json.loads(line)
        if not isinstance(request, dict):
            raise ValueError("TRAFFIC_HEADER_INVALID")
        validate_request(request)
        return request

    async def tcp(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter, metrics_only: bool = False) -> None:
        try:
            keepalive = False
            while True:
                keepalive = bool(await self.tcp_request(reader, writer, metrics_only, 30 if keepalive else 10))
                if not keepalive:
                    break
        finally:
            writer.close()
            try:
                await asyncio.wait_for(writer.wait_closed(), 2)
            except (OSError, asyncio.TimeoutError):
                pass

    async def tcp_request(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter, metrics_only: bool = False,
                          header_timeout: float = 10) -> bool | None:
        task = asyncio.current_task()
        if task is not None:
            self.tasks.add(task)
        admitted = False
        row: dict[str, Any] | None = None
        try:
            if self.active >= self.max_connections:
                raise ValueError("TRAFFIC_CONNECTION_LIMIT")
            self.active += 1
            admitted = True
            request = await self.header(reader, header_timeout)
            if (request["task"] == "metrics") != metrics_only:
                raise ValueError("TRAFFIC_CONTROL_PORT_REQUIRED")
            challenge = secrets.token_hex(32)
            raw = json_bytes(request)
            writer.write(json_bytes({"challenge": challenge}) + b"\n")
            await writer.drain()
            authentication = await self.header_auth(reader)
            verify_mac(self.secret, b"client:", challenge.encode() + raw, authentication)
            row = self.metrics(request["run_id"])
            peer = writer.get_extra_info("peername")
            ready = {"ready": True, "flow_id": request["flow_id"], "peer": list(peer[:2]),
                     "version": 1}
            ready["proof"] = mac(self.secret, b"server:", challenge.encode() + raw + json_bytes(ready))
            writer.write(json_bytes(ready) + b"\n")
            await writer.drain()
            if request["task"] == "metrics":
                result = {key: value for key, value in row.items() if key not in ("udp_flows", "_inflight_transfers")}
                if self.origin_udp_receive_buffer is not None:
                    result['origin_udp_receive_buffer'] = self.origin_udp_receive_buffer
                # Completed counters remain unchanged. Include validated payload in
                # live transfers exactly once, while their connections are open.
                inflight = row.get('_inflight_transfers', {}).values()
                for direction in ('rx_bytes', 'tx_bytes'):
                    result[direction] += sum(transfer[direction] for transfer in inflight)
                result["udp_unique_flows"] = len(row["udp_flows"])
                from trafficlab.resources import process_sample, system_sample
                result["resources"] = process_sample(os.getpid())
                result["system_resources"] = system_sample()
                result["cpu_count"] = os.cpu_count() or 1
                result["identity"] = self.identity()
                from trafficlab.socket_idle import owned_tcp_connections
                observer = writer.get_extra_info('socket')
                tcp_connections = owned_tcp_connections(self.origin_tcp_ports, observer.fileno() if observer else None)
                quic = self.applications.quic if self.applications is not None else None
                quic_connections = len(quic.protocols) if quic is not None else 0
                logical_tcp = self.active - 1 - quic_connections
                result['runtime_connections'] = (max(tcp_connections, logical_tcp) + quic_connections
                    if tcp_connections is not None and logical_tcp >= 0 else None)
                result['runtime_connections_method'] = 'owned-origin-TCP-sockets-and-QUIC-protocols'
                result['runtime_tcp_connections'] = tcp_connections
                result['runtime_quic_connections'] = quic_connections
                if self.native is not None:
                    self.native.merge(result, request['run_id'])
                else:
                    result["proxy_connections"] = len(self.proxy.pending) if hasattr(self, "proxy") else 0
                    result['proxy_udp_associations'] = len({id(value) for value in self.proxy.associations.values()}) if hasattr(self, 'proxy') else 0
                    result['proxy_tcp_connections'] = max(0, result['proxy_connections'] - result['proxy_udp_associations'])
                result["proof"] = mac(self.secret, b"result:", challenge.encode() + raw + json_bytes(result))
                writer.write(json_bytes(result) + b"\n")
                await writer.drain()
                return request.get('metrics_keepalive') is True
            row["accepted"] += 1
            row["active"] += 1
            row["tcp_active_peak"] = max(row["tcp_active_peak"], row["active"])
            if len(row["route_samples"]) < 256:
                row["route_samples"].append({"flow_id": request["flow_id"], "peer": list(peer[:2])})
            started = time.monotonic()
            transfer = {"rx_bytes": 0, "tx_bytes": 0, "rx_sha256": None, "tx_sha256": None}
            inflight = row.setdefault('_inflight_transfers', {})
            inflight[id(transfer)] = transfer
            try:
                await asyncio.wait_for(self.exchange(reader, writer, request, transfer), request["seconds"] + 20)
                row["completed"] += 1
            except (OSError, EOFError, ValueError, asyncio.TimeoutError, asyncio.IncompleteReadError):
                row["errors"] += 1
                raise
            finally:
                row["active"] -= 1
                row["rx_bytes"] += transfer["rx_bytes"]
                row["tx_bytes"] += transfer["tx_bytes"]
                del inflight[id(transfer)]
            result = {"complete": True, "flow_id": request["flow_id"],
                      "elapsed_seconds": time.monotonic() - started, **transfer}
            result["proof"] = mac(self.secret, b"result:", challenge.encode() + raw + json_bytes(result))
            writer.write(json_bytes(result) + b"\n")
            await writer.drain()
        except (OSError, ValueError, EOFError, asyncio.TimeoutError, asyncio.IncompleteReadError, json.JSONDecodeError):
            # Invalid credentials and network errors never disclose authentication material.
            pass
        finally:
            if admitted:
                self.active -= 1
            if task is not None:
                self.tasks.discard(task)

    async def header_auth(self, reader: asyncio.StreamReader) -> str:
        line = await asyncio.wait_for(reader.readline(), 10)
        if len(line) > 256 or not line.endswith(b"\n"):
            raise ValueError("TRAFFIC_AUTHENTICATION_FAILED")
        value = json.loads(line)
        if not isinstance(value, dict):
            raise ValueError("TRAFFIC_AUTHENTICATION_FAILED")
        return value.get("proof", "")

    async def exchange(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter,
                       request: dict[str, Any], result: dict[str, Any]) -> None:
        task = request["task"]
        deadline = time.monotonic() + request["seconds"]

        async def receive(echo: bool) -> None:
            digest = hashlib.sha256()
            offset = 0
            while True:
                position, size = FRAME.unpack(await reader.readexactly(FRAME.size))
                if position != offset or size > MAX_CHUNK:
                    raise ValueError("TRAFFIC_SEQUENCE_INVALID")
                if size == 0:
                    break
                data = await reader.readexactly(size)
                if data != pattern(offset, size):
                    raise ValueError("TRAFFIC_DATA_MISMATCH")
                digest.update(data)
                offset += size
                result["rx_bytes"] = offset
                if echo:
                    writer.write(FRAME.pack(position, size) + data)
                    await writer.drain()
                    result["tx_bytes"] += size
            result["rx_sha256"] = digest.hexdigest()
            if echo:
                writer.write(FRAME.pack(offset, 0))
                await writer.drain()
                result["tx_sha256"] = digest.hexdigest()

        async def send() -> None:
            digest = hashlib.sha256()
            offset = 0
            started = time.monotonic()
            rate = request.get("rate_bytes_per_second", 0)
            while time.monotonic() < deadline:
                writer.write(FRAME.pack(offset, MAX_CHUNK) + BLOCK)
                await writer.drain()
                digest.update(BLOCK)
                offset += MAX_CHUNK
                result["tx_bytes"] = offset
                if rate:
                    delay = started + offset / rate - time.monotonic()
                    if delay > 0:
                        await asyncio.sleep(min(delay, 0.2))
            writer.write(FRAME.pack(offset, 0))
            await writer.drain()
            result["tx_sha256"] = digest.hexdigest()

        if task in ("echo", "hold"):
            await receive(True)
        elif task == "upload":
            await receive(False)
        elif task == "download":
            await send()
        elif task == "duplex":
            children = [asyncio.create_task(receive(False)), asyncio.create_task(send())]
            try:
                await asyncio.gather(*children)
            finally:
                for child in children:
                    child.cancel()
                await asyncio.gather(*children, return_exceptions=True)


class DatagramAgent(asyncio.DatagramProtocol):
    def __init__(self, agent: Agent) -> None:
        self.agent = agent
        self.transport: asyncio.DatagramTransport | None = None

    def connection_made(self, transport: asyncio.BaseTransport) -> None:
        self.transport = transport  # type: ignore[assignment]

    def datagram_received(self, data: bytes, address: tuple[str, int]) -> None:
        try:
            header, payload = data.split(b"\n", 1)
            if len(header) > 2048 or len(payload) > 60000:
                raise ValueError("TRAFFIC_DATAGRAM_INVALID")
            request = json.loads(header)
            if not isinstance(request, dict):
                raise ValueError("TRAFFIC_DATAGRAM_INVALID")
            proof = request.pop("proof")
            if request.get("version") != 1 or type(request.get("sequence")) is not int or request["sequence"] < 0:
                raise ValueError("TRAFFIC_DATAGRAM_INVALID")
            from trafficlab.protocol import ID
            if any(not ID.fullmatch(str(request.get(key, ""))) for key in ("run_id", "flow_id")):
                raise ValueError("TRAFFIC_ID_INVALID")
            raw = json_bytes(request)
            verify_mac(self.agent.secret, b"udp-client:", raw + payload, proof)
            sequence = request["sequence"]
            if payload != pattern(sequence * len(payload), len(payload)):
                raise ValueError("TRAFFIC_DATA_MISMATCH")
            row = self.agent.metrics(request["run_id"])
            flows = row["udp_flows"]
            if request["flow_id"] not in flows and len(flows) >= 4096:
                raise ValueError("TRAFFIC_UDP_FLOW_LIMIT")
            flows[request["flow_id"]] = sequence
            row["udp_received"] += 1
            row['rx_bytes'] += len(payload)
            response = {**request, "peer": list(address[:2])}
            response["proof"] = mac(self.agent.secret, b"udp-server:", json_bytes(response) + payload)
            assert self.transport is not None
            try:
                self.transport.sendto(json_bytes(response) + b"\n" + payload, address)
                row['tx_bytes'] += len(payload)
            except OSError:
                row["udp_reply_errors"] += 1
        except (ValueError, KeyError, TypeError, AssertionError, OSError, json.JSONDecodeError):
            # A bad datagram cannot crash the shared origin or produce an amplified reply.
            pass

    def error_received(self, _exception: Exception) -> None:
        pass


LOCAL_ORIGIN_UDP_RECEIVE_BUFFER = 4 * 1024 * 1024


async def create_origin_datagram_endpoint(loop, agent: Agent, bind: str, port: int):
    # Local WFP and WinDivert use the same receiver and the same signed metrics.
    # Absorb input while identity/resource queries occupy the origin event loop.
    if agent.identity_mode != 'local-windows-v1':
        return await loop.create_datagram_endpoint(lambda: DatagramAgent(agent), local_addr=(bind, port))
    udp_socket = socket.socket(socket.AF_INET6 if ':' in bind else socket.AF_INET, socket.SOCK_DGRAM)
    try:
        udp_socket.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, LOCAL_ORIGIN_UDP_RECEIVE_BUFFER)
        effective = udp_socket.getsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF)
        if effective < LOCAL_ORIGIN_UDP_RECEIVE_BUFFER:
            raise ValueError('TRAFFIC_ORIGIN_UDP_RECEIVE_BUFFER_INSUFFICIENT')
        udp_socket.bind((bind, port))
        udp_socket.setblocking(False)
        endpoint = await loop.create_datagram_endpoint(lambda: DatagramAgent(agent), sock=udp_socket)
    except BaseException:
        udp_socket.close()
        raise
    agent.origin_udp_receive_buffer = {'requested_bytes': LOCAL_ORIGIN_UDP_RECEIVE_BUFFER, 'effective_bytes': effective}
    return endpoint


async def serve(config: dict[str, Any]) -> None:
    secret = bytes.fromhex(config["secret"])
    agent = Agent(secret, config.get("max_connections", 2048))
    agent.identity_mode = config.get('identity_mode', 'remote')
    if config.get("configuration_path"):
        agent.configuration_path = Path(config["configuration_path"])
    bind = config.get("bind", "127.0.0.1")
    port = config.get("port", 42501)
    if not isinstance(port, int) or not 1 <= port <= 65535:
        raise ValueError("TRAFFIC_AGENT_CONFIG_INVALID")
    loop = asyncio.get_running_loop()
    server = transport = None
    if config.get('native_engine'):
        from trafficlab.native_engine import OriginAdapter
        native = config['native_engine']
        if agent.identity_mode != 'local-windows-v1':
            raise ValueError('TRAFFIC_NATIVE_ENGINE_LOCAL_ONLY')
        agent.native = OriginAdapter(native['port'], config['secret'], native['executable'])
    else:
        server = await asyncio.start_server(agent.tcp, bind, port, limit=MAX_LINE + 1)
        transport, _ = await create_origin_datagram_endpoint(loop, agent, bind, port)
    control_port = config.get("control_port", 42503)
    control = await asyncio.start_server(lambda reader, writer: agent.tcp(reader, writer, True), bind, control_port, limit=MAX_LINE + 1)
    from trafficlab.proxy import SocksProxy, ProxyDatagram
    proxy = agent.native or SocksProxy(agent, port, config.get("origin_addresses", ["127.0.0.1"]))
    agent.proxy = proxy
    from trafficlab.application_origin import ApplicationOrigins
    agent.applications = ApplicationOrigins(agent, config)
    proxy.application_ports = set(agent.applications.ports.values())
    proxy.application_dns_port = agent.applications.ports.get("dns-udp")
    proxy.quic_ports = {agent.applications.ports[kind] for kind in ('quic', 'http3') if kind in agent.applications.ports}
    agent.origin_tcp_ports = ({port} if agent.native is None else set()) | {control_port} | (set(agent.applications.ports.values()) - proxy.quic_ports)
    await agent.applications.start(bind)
    proxy.port = config.get("proxy_port", 42502)
    proxy_server = None
    if agent.native is None:
        proxy_server = await asyncio.start_server(proxy.tcp, bind, proxy.port, limit=MAX_LINE + 1)
        await loop.create_datagram_endpoint(lambda: ProxyDatagram(proxy), local_addr=(bind, proxy.port))
    stopping = asyncio.Event()
    for signum in (signal.SIGTERM, signal.SIGINT):
        try:
            loop.add_signal_handler(signum, stopping.set)
        except NotImplementedError:
            signal.signal(signum, lambda *_: loop.call_soon_threadsafe(stopping.set))
    print(f"TRAFFIC_AGENT_READY origin={port} proxy={proxy.port} control={control_port}", flush=True)
    async def watch_stop() -> None:
        while not stopping.is_set():
            if config.get('stop_path') and Path(config['stop_path']).is_file():
                stopping.set()
                return
            await asyncio.sleep(0.25)
    watcher = asyncio.create_task(watch_stop())
    try:
        await stopping.wait()
    finally:
        watcher.cancel()
        await asyncio.gather(watcher, return_exceptions=True)
        if server is not None:
            server.close()
            await server.wait_closed()
        control.close()
        if proxy_server is not None:
            proxy_server.close()
        await control.wait_closed()
        if proxy_server is not None:
            await proxy_server.wait_closed()
        await proxy.close()
        await agent.applications.close()
        if transport is not None:
            transport.close()
        for task in list(agent.tasks):
            task.cancel()
        await asyncio.gather(*list(agent.tasks), return_exceptions=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    arguments = parser.parse_args()
    try:
        config = json.loads(Path(arguments.config).read_text(encoding="utf-8-sig"))
        config["configuration_path"] = str(Path(arguments.config).resolve())
        asyncio.run(serve(config))
        return 0
    except (OSError, ValueError, KeyError):
        print("TRAFFIC_AGENT_CONFIGURATION_OR_RUNTIME_ERROR", flush=True)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
