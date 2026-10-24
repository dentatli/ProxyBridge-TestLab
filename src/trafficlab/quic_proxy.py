"""Bounded QUIC-v1 datagram accounting within a shared SOCKS UDP association.

Only public wire connection IDs are read. Payload authentication remains at the
origin, which binds a connection's pending counters to its verified run/flow.
"""
from __future__ import annotations
import time
from typing import Any


class QuicRoutes:
    def __init__(self, limit: int) -> None:
        self.limit = limit
        self.routes: dict[tuple[int, int, bytes], dict[str, Any]] = {}
        self.outgoing: dict[tuple[int, int, bytes], dict[str, Any]] = {}
        self.incoming: dict[tuple[int, int, bytes], dict[str, Any]] = {}
        self.swept = 0.0

    def forget(self, association: dict[str, Any]) -> None:
        for key, route in list(self.routes.items()):
            if key[0] == id(association):
                self.remove(key, route)

    def remove(self, key: tuple[int, int, bytes], route: dict[str, Any]) -> None:
        self.routes.pop(key, None)
        for table, ids in ((self.outgoing, route['server_ids']), (self.incoming, route['client_ids'])):
            for cid in ids:
                table.pop((*key[:2], cid), None)

    @staticmethod
    def alias(table: dict, route: dict, cid: bytes, field: str) -> None:
        if not cid or len(cid) > 20:
            raise ValueError('SOCKS_QUIC_CID_INVALID')
        key = (*route['key'][:2], cid)
        if key in table and table[key] is not route:
            raise ValueError('SOCKS_QUIC_CID_COLLISION')
        if cid not in route[field] and len(route[field]) >= 32:
            raise ValueError('SOCKS_QUIC_CID_LIMIT')
        route[field].add(cid)
        table[key] = route

    def packet(self, association: dict, port: int, data: bytes, reply: bool = False) -> dict:
        # Both owned endpoints use the pinned aioquic configuration's 8-byte CID.
        from aioquic.buffer import Buffer
        from aioquic.quic.packet import pull_quic_header, QuicPacketType
        header = pull_quic_header(Buffer(data=data), host_cid_length=8)
        if header.version not in (None, 1):
            raise ValueError('SOCKS_QUIC_VERSION_UNSUPPORTED')
        now = time.monotonic()
        if now - self.swept >= 1:
            for key, value in list(self.routes.items()):
                if now - value['touched'] > 30:
                    self.remove(key, value)
            self.swept = now
        prefix = (id(association), port)
        table = self.incoming if reply else self.outgoing
        route = table.get((*prefix, header.destination_cid))
        if route is None and header.source_cid:
            other = self.outgoing if reply else self.incoming
            route = other.get((*prefix, header.source_cid))
        if route is None:
            if reply or header.packet_type != QuicPacketType.INITIAL or len(self.routes) >= self.limit:
                raise ValueError('SOCKS_QUIC_CONNECTION_UNKNOWN_OR_LIMIT')
            key = (*prefix, header.destination_cid)
            route = {'key': key, 'server_ids': set(), 'client_ids': set(),
                     'identity': None, 'sent': 0, 'received': 0, 'touched': now}
            # No routing entry is exposed until both initial IDs are valid.
            if not header.destination_cid or not header.source_cid:
                raise ValueError('SOCKS_QUIC_CID_INVALID')
            self.routes[key] = route
        self.alias(table, route, header.destination_cid, 'client_ids' if reply else 'server_ids')
        if header.source_cid:
            other = self.outgoing if reply else self.incoming
            self.alias(other, route, header.source_cid, 'server_ids' if reply else 'client_ids')
        route['touched'] = now
        route['received' if reply else 'sent'] += 1
        return route

    def connection(self, association: dict, port: int, original_cid: bytes) -> dict | None:
        return self.routes.get((id(association), port, original_cid))

    def server_cid(self, association: dict, port: int, original_cid: bytes, cid: bytes, retired: bool) -> None:
        route = self.connection(association, port, original_cid)
        if route is None:
            return  # Direct control, outside SOCKS.
        if retired:
            route['server_ids'].discard(cid)
            self.outgoing.pop((*route['key'][:2], cid), None)
        else:
            self.alias(self.outgoing, route, cid, 'server_ids')
