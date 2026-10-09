"""Authenticated SOCKS5 restricted to this agent's origin; bounded, signed session counters."""
from __future__ import annotations

import asyncio
import hashlib
import ipaddress
import json
import struct
import time
from typing import Any

from trafficlab.protocol import ID, MAX_LINE, json_bytes, mac


def fingerprint(flow_id: str, peer: list[Any]) -> int:
    return int.from_bytes(hashlib.sha256(json_bytes([flow_id, peer])).digest(), "big")


class SocksProxy:
    def __init__(self, agent: Any, origin_port: int, origin_addresses: list[str]) -> None:
        self.agent = agent
        self.origin_port = origin_port
        self.addresses = {str(ipaddress.ip_address(value)) for value in origin_addresses}
        self.associations: dict[tuple[str, int], dict[str, Any]] = {}
        self.pending: set[asyncio.Task[Any]] = set()
        self.udp_transport: asyncio.DatagramTransport | None = None
        self.port = 0
        self.udp_seen: dict[str, set[str]] = {}

    def counters(self, run_id: str) -> dict[str, Any]:
        row = self.agent.metrics(run_id)
        return row.setdefault("proxy", {"tcp_flows": 0, "tcp_finished": 0, "tcp_active": 0, "tcp_errors": 0,
            "tcp_origin_fingerprint": "0" * 64, "udp_sent": 0, "udp_received": 0, "udp_flows": 0,
            "udp_origin_fingerprint": "0" * 64, "samples": []})

    async def address(self, reader: asyncio.StreamReader) -> tuple[str, int]:
        kind = (await reader.readexactly(1))[0]
        if kind not in (1, 4):
            raise ValueError("SOCKS_IP_ADDRESS_REQUIRED")
        host = str(ipaddress.ip_address(await reader.readexactly(4 if kind == 1 else 16)))
        port = struct.unpack("!H", await reader.readexactly(2))[0]
        return host, port

    @staticmethod
    def wire_address(host: str, port: int) -> bytes:
        address = ipaddress.ip_address(host)
        return bytes([1 if address.version == 4 else 4]) + address.packed + struct.pack("!H", port)

    async def tcp(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        task = asyncio.current_task()
        self.pending.add(task)
        upstream = None
        counters = None
        association = None
        children = []
        try:
            if len(self.pending) > self.agent.max_connections:
                raise ValueError("SOCKS_CONNECTION_LIMIT")
            async def handshake() -> tuple[str, int, tuple[str, int]]:
                version, count = await reader.readexactly(2)
                methods = await reader.readexactly(count)
                if version != 5 or 2 not in methods:
                    writer.write(b"\x05\xff")
                    await writer.drain()
                    raise ValueError("SOCKS_AUTH_REQUIRED")
                writer.write(b"\x05\x02")
                await writer.drain()
                version, length = await reader.readexactly(2)
                username = (await reader.readexactly(length)).decode("ascii")
                password = await reader.readexactly((await reader.readexactly(1))[0])
                if version != 1 or not ID.fullmatch(username) or password != mac(self.agent.secret, b"socks:", username.encode()).encode():
                    writer.write(b"\x01\x01")
                    await writer.drain()
                    raise ValueError("SOCKS_AUTH_FAILED")
                writer.write(b"\x01\x00")
                await writer.drain()
                version, command, reserved = await reader.readexactly(3)
                destination = await self.address(reader)
                if version != 5 or reserved != 0 or command not in (1, 3):
                    raise ValueError("SOCKS_REQUEST_INVALID")
                return username, command, destination
            username, command, destination = await asyncio.wait_for(handshake(), 10)
            if command == 3:
                peer = writer.get_extra_info("peername")
                key = (str(peer[0]), peer[1])
                if len(self.associations) >= self.agent.max_connections or key in self.associations:
                    raise ValueError("SOCKS_ASSOCIATION_LIMIT")
                # An ephemeral origin-side UDP socket per association correlates replies without parsing their contents.
                loop = asyncio.get_running_loop()
                transport, _ = await loop.create_datagram_endpoint(lambda: RelayDatagram(self, key), local_addr=("127.0.0.1", 0))
                local = writer.get_extra_info("sockname")
                ingress, _ = await loop.create_datagram_endpoint(lambda: AssociationDatagram(self, key), local_addr=(str(local[0]), 0))
                association = {"username": username, "transport": transport, "ingress": ingress, "client": None, "keys": {key}, "run_id": None,
                               "client_ip": str(peer[0]), "client_port": destination[1]}
                self.associations[key] = association
                relay = ingress.get_extra_info("sockname")
                writer.write(b"\x05\x00\x00" + self.wire_address(str(relay[0]), relay[1]))
                await writer.drain()
                await asyncio.wait_for(reader.read(1), 72 * 3600 + 60)
                return
            if destination[0] not in self.addresses or destination[1] != self.origin_port:
                writer.write(b"\x05\x02\x00\x01\x00\x00\x00\x00\x00\x00")
                await writer.drain()
                raise ValueError("SOCKS_DESTINATION_DENIED")
            upstream_reader, upstream = await asyncio.wait_for(asyncio.open_connection("127.0.0.1", self.origin_port), 10)
            local = upstream.get_extra_info("sockname")
            writer.write(b"\x05\x00\x00" + self.wire_address(str(local[0]), local[1]))
            await writer.drain()
            line = await asyncio.wait_for(reader.readline(), 10)
            request = json.loads(line)
            run_id, flow_id = request.get("run_id", ""), request.get("flow_id", "")
            if len(line) > MAX_LINE or not line.endswith(b"\n") or not ID.fullmatch(run_id) or not ID.fullmatch(flow_id) or not (run_id == username or run_id.startswith(username + ".")):
                raise ValueError("SOCKS_SESSION_ID_INVALID")
            counters = self.counters(run_id)
            counters["tcp_flows"] += 1
            counters["tcp_active"] += 1
            counters["tcp_origin_fingerprint"] = f"{int(counters['tcp_origin_fingerprint'], 16) ^ fingerprint(flow_id, list(local[:2])):064x}"
            if len(counters["samples"]) < 256:
                counters["samples"].append({"flow_id": flow_id, "origin_peer": list(local[:2])})
            upstream.write(line)
            await upstream.drain()
            async def pump(source: asyncio.StreamReader, sink: asyncio.StreamWriter) -> None:
                while True:
                    data = await source.read(65536)
                    if not data:
                        if sink.can_write_eof():
                            sink.write_eof()
                        return
                    sink.write(data)
                    await sink.drain()
            children = [asyncio.create_task(pump(reader, upstream)), asyncio.create_task(pump(upstream_reader, writer))]
            await asyncio.wait_for(asyncio.gather(*children), request.get("seconds", 0.05) + 30)
            counters["tcp_finished"] += 1
        except (OSError, ValueError, TypeError, UnicodeError, asyncio.TimeoutError, asyncio.IncompleteReadError):
            if counters is not None:
                counters["tcp_errors"] += 1
        finally:
            for child in children:
                child.cancel()
            await asyncio.gather(*children, return_exceptions=True)
            if counters is not None:
                counters["tcp_active"] -= 1
            if association is not None:
                for key in association["keys"]:
                    self.associations.pop(key, None)
                association["transport"].close()
                association["ingress"].close()
            for connection in (upstream, writer):
                if connection is not None:
                    connection.close()
                    try:
                        await asyncio.wait_for(connection.wait_closed(), 2)
                    except (OSError, asyncio.TimeoutError):
                        pass
            self.pending.discard(task)

    def datagram(self, packet: bytes, client: tuple[str, int], association_key: tuple[str, int] | None = None) -> None:
        try:
            if packet[:3] != b"\x00\x00\x00":
                return  # Fragmentation is explicitly unsupported.
            kind = packet[3]
            size = 4 if kind == 1 else 16 if kind == 4 else 0
            if not size:
                return
            host = str(ipaddress.ip_address(packet[4:4 + size]))
            port = struct.unpack("!H", packet[4 + size:6 + size])[0]
            if host not in self.addresses or port != self.origin_port:
                return
            association = self.associations.get(association_key)
            if association is None or client[0] != association["client_ip"] or association["client"] not in (None, client) or association["client_port"] not in (0, client[1]):
                return
            association["client"] = client
            data = packet[6 + size:]
            header = json.loads(data.split(b"\n", 1)[0])
            run_id = header["run_id"]
            username = association["username"]
            if not ID.fullmatch(run_id) or not (run_id == username or run_id.startswith(username + ".")):
                return
            # Authentication and payload validity are checked again by the origin before it responds.
            counters = self.counters(run_id)
            flow_id = header["flow_id"]
            if not ID.fullmatch(flow_id):
                return
            for expired in set(self.udp_seen) - set(self.agent.runs):
                del self.udp_seen[expired]
            seen = self.udp_seen.setdefault(run_id, set())
            if flow_id not in seen:
                if len(seen) >= 4096:
                    return
                seen.add(flow_id)
                peer = association["transport"].get_extra_info("sockname")
                counters["udp_flows"] += 1
                counters["udp_origin_fingerprint"] = f"{int(counters['udp_origin_fingerprint'], 16) ^ fingerprint(flow_id, list(peer[:2])):064x}"
            counters["udp_sent"] += 1
            association["run_id"] = run_id
            association["transport"].sendto(data, ("127.0.0.1", self.origin_port))
        except (ValueError, KeyError, TypeError, IndexError, OSError, struct.error):
            return

    async def close(self) -> None:
        if self.udp_transport is not None:
            self.udp_transport.close()
        for task in list(self.pending):
            task.cancel()
        await asyncio.gather(*list(self.pending), return_exceptions=True)


class ProxyDatagram(asyncio.DatagramProtocol):
    def __init__(self, proxy: SocksProxy) -> None:
        self.proxy = proxy

    def connection_made(self, transport: asyncio.BaseTransport) -> None:
        self.proxy.udp_transport = transport

    def datagram_received(self, packet: bytes, client: tuple[str, int]) -> None:
        self.proxy.datagram(packet, client)


class RelayDatagram(asyncio.DatagramProtocol):
    def __init__(self, proxy: SocksProxy, key: tuple[str, int]) -> None:
        self.proxy, self.key = proxy, key

    def datagram_received(self, packet: bytes, sender: tuple[str, int]) -> None:
        association = self.proxy.associations.get(self.key)
        if sender != ("127.0.0.1", self.proxy.origin_port) or association is None or association["client"] is None:
            return
        try:
            run_id = json.loads(packet.split(b"\n", 1)[0])["run_id"]
            self.proxy.counters(run_id)["udp_received"] += 1
            response = b"\x00\x00\x00" + self.proxy.wire_address(next(iter(sorted(self.proxy.addresses))), self.proxy.origin_port) + packet
            association["ingress"].sendto(response, association["client"])
        except (ValueError, KeyError, TypeError, OSError):
            pass


class AssociationDatagram(asyncio.DatagramProtocol):
    def __init__(self, proxy: SocksProxy, key: tuple[str, int]) -> None:
        self.proxy, self.key = proxy, key

    def datagram_received(self, packet: bytes, client: tuple[str, int]) -> None:
        self.proxy.datagram(packet, client, self.key)
