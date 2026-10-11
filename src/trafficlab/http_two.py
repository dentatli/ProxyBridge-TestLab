"""Bounded HTTP/2 POST and protobuf unary gRPC with required status trailers."""
from __future__ import annotations
import asyncio
import json
import struct
from typing import Any
from trafficlab.dependencies import enable
from trafficlab.application_wire import SERVER_NAME, response
from trafficlab.protocol import MAX_LINE, json_bytes

enable()
from h2.config import H2Configuration
from h2.connection import H2Connection
from h2.events import (ConnectionTerminated, DataReceived, RequestReceived, ResponseReceived,
                       StreamEnded, StreamReset, TrailersReceived)
from h2.settings import SettingCodes

GRPC_PATH = '/testlab.Echo/Exchange'


def grpc_encode(data: bytes) -> bytes:
    length, integer = bytearray(), len(data)
    while integer >= 128:
        length.append((integer & 127) | 128); integer >>= 7
    length.append(integer)
    message = b'\x0a' + bytes(length) + data  # Envelope { bytes json = 1; }
    return b'\0' + struct.pack('!I', len(message)) + message


def grpc_decode(data: bytes) -> bytes:
    if len(data) < 7 or data[0] != 0 or struct.unpack('!I', data[1:5])[0] != len(data) - 5 or data[5] != 10:
        raise ValueError('APPLICATION_GRPC_FRAME_INVALID')
    offset, length, shift = 6, 0, 0
    while offset < len(data) and shift <= 28:
        value = data[offset]; offset += 1
        length |= (value & 127) << shift
        if value < 128:
            if length != len(data) - offset or not 0 < length <= MAX_LINE:
                break
            return data[offset:]
        shift += 7
    raise ValueError('APPLICATION_GRPC_PROTOBUF_INVALID')


class H2Client:
    def __init__(self, sock: Any, grpc: bool):
        self.sock, self.grpc = sock, grpc
        self.conn = H2Connection(config=H2Configuration(client_side=True, header_encoding='ascii'))
        self.conn.initiate_connection()
        sock.sendall(self.conn.data_to_send())

    def exchange(self, message: bytes) -> dict[str, Any]:
        stream = self.conn.get_next_available_stream_id()
        content_type = 'application/grpc+proto' if self.grpc else 'application/json'
        headers = [(':method', 'POST'), (':scheme', 'https'), (':authority', SERVER_NAME),
                   (':path', GRPC_PATH if self.grpc else '/testlab'), ('content-type', content_type)]
        if self.grpc:
            headers.append(('te', 'trailers'))
        self.conn.send_headers(stream, headers)
        self.conn.send_data(stream, grpc_encode(message) if self.grpc else message, end_stream=True)
        self.sock.sendall(self.conn.data_to_send())
        body, received, trailers = bytearray(), {}, {}
        while True:
            raw = self.sock.recv(16384)
            if not raw:
                raise EOFError('APPLICATION_HTTP2_TRUNCATED')
            ended = False
            for event in self.conn.receive_data(raw):
                if isinstance(event, (StreamReset, ConnectionTerminated)):
                    raise ValueError('APPLICATION_HTTP2_RESET')
                if getattr(event, 'stream_id', stream) != stream:
                    raise ValueError('APPLICATION_HTTP2_STREAM_CHANGED')
                if isinstance(event, ResponseReceived):
                    received = dict(event.headers)
                elif isinstance(event, TrailersReceived):
                    trailers = dict(event.headers)
                elif isinstance(event, DataReceived):
                    body.extend(event.data)
                    self.conn.acknowledge_received_data(event.flow_controlled_length, stream)
                    if len(body) > MAX_LINE + 16:
                        raise ValueError('APPLICATION_HTTP2_RESPONSE_TOO_LARGE')
                elif isinstance(event, StreamEnded):
                    ended = True
            outgoing = self.conn.data_to_send()
            if outgoing:
                self.sock.sendall(outgoing)
            if ended:
                if received.get(':status') != '200' or received.get('content-type') != content_type:
                    raise ValueError('APPLICATION_HTTP2_STATUS_INVALID')
                if self.grpc and trailers.get('grpc-status') != '0':
                    raise ValueError('APPLICATION_GRPC_STATUS_UNVERIFIED')
                return json.loads(grpc_decode(bytes(body)) if self.grpc else body)

    def close(self):
        self.conn.close_connection()
        self.sock.sendall(self.conn.data_to_send())


async def serve(origins: Any, reader: asyncio.StreamReader, writer: asyncio.StreamWriter,
                kind: str, session: dict[str, Any], peer: list[Any]) -> None:
    if writer.get_extra_info('ssl_object').selected_alpn_protocol() != 'h2':
        raise ValueError('APPLICATION_HTTP2_ALPN_INVALID')
    conn = H2Connection(config=H2Configuration(client_side=False, header_encoding='ascii'))
    conn.initiate_connection()
    conn.update_settings({SettingCodes.MAX_CONCURRENT_STREAMS: 16, SettingCodes.MAX_HEADER_LIST_SIZE: MAX_LINE})
    writer.write(conn.data_to_send()); await writer.drain()
    requests: dict[int, Any] = {}
    while True:
        raw = await reader.read(16384)
        if not raw:
            return
        for event in conn.receive_data(raw):
            if isinstance(event, ConnectionTerminated):
                return
            if isinstance(event, StreamReset):
                raise ValueError('APPLICATION_HTTP2_RESET')
            if isinstance(event, RequestReceived):
                if len(requests) >= 16 or sum(len(k) + len(v) for k,v in event.headers) > MAX_LINE:
                    raise ValueError('APPLICATION_HTTP2_REQUEST_LIMIT')
                headers = dict(event.headers)
                if headers.get(':method') != 'POST' or headers.get(':path') != (GRPC_PATH if kind == 'grpc' else '/testlab') or headers.get('content-type') not in (('application/grpc', 'application/grpc+proto') if kind == 'grpc' else ('application/json',)):
                    raise ValueError('APPLICATION_HTTP2_REQUEST_INVALID')
                if kind == 'grpc' and headers.get('te') != 'trailers':
                    raise ValueError('APPLICATION_GRPC_TRAILERS_REQUIRED')
                requests[event.stream_id] = bytearray()
            elif isinstance(event, DataReceived):
                requests[event.stream_id].extend(event.data)
                conn.acknowledge_received_data(event.flow_controlled_length, event.stream_id)
                if len(requests[event.stream_id]) > MAX_LINE + 16:
                    raise ValueError('APPLICATION_HTTP2_REQUEST_TOO_LARGE')
            elif isinstance(event, StreamEnded):
                data = bytes(requests.pop(event.stream_id))
                message = json.loads(grpc_decode(data) if kind == 'grpc' else data)
                identity, _, _ = origins.authenticate(message, kind, peer, session)
                reply = json_bytes(response(origins.agent.secret, identity, peer, message['payload']))
                if kind == 'grpc':
                    reply = grpc_encode(reply)
                conn.send_headers(event.stream_id, [(':status', '200'), ('content-type', 'application/grpc+proto' if kind == 'grpc' else 'application/json')])
                conn.send_data(event.stream_id, reply, end_stream=kind != 'grpc')
                if kind == 'grpc':
                    conn.send_headers(event.stream_id, [('grpc-status', '0')], end_stream=True)
        writer.write(conn.data_to_send()); await writer.drain()
