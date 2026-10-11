"""Owned QUIC-v1 and HTTP/3 origins with authenticated, bounded exchanges."""
from __future__ import annotations
import asyncio
import base64
import json
from trafficlab.dependencies import enable
from trafficlab.application_wire import response
from trafficlab.protocol import json_bytes
from trafficlab.quic_wire import append_body, h3_headers

enable()
from aioquic.asyncio import serve
from aioquic.asyncio.protocol import QuicConnectionProtocol
from aioquic.quic.configuration import QuicConfiguration
from aioquic.quic.events import ConnectionTerminated, StreamDataReceived, StreamReset
from aioquic.h3.connection import H3Connection
from aioquic.h3.events import HeadersReceived, DataReceived


class QuicOrigin:
    def __init__(self, origins):
        self.origins, self.protocols = origins, set()

    async def start(self, bind, port, kind):
        configuration = QuicConfiguration(is_client=False, alpn_protocols=['h3' if kind == 'http3' else 'testlab-quic/1'],
            idle_timeout=5, max_data=262144, max_stream_data=16384, supported_versions=[1])
        configuration.load_cert_chain(self.origins.certificate, self.origins.key)
        return await serve(bind, port, configuration=configuration,
            create_protocol=lambda *args, **kwargs: OriginProtocol(*args, owner=self, kind=kind, **kwargs), retry=True)

    def close(self):
        for protocol in list(self.protocols):
            protocol.close()
            protocol.release()


class OriginProtocol(QuicConnectionProtocol):
    def __init__(self, *args, owner, kind, **kwargs):
        super().__init__(*args, **kwargs)
        self.owner, self.kind = owner, kind
        self.peer, self.identity, self.row = None, None, None
        self.bodies, self.headers = {}, {}
        self.http = H3Connection(self._quic) if kind == 'http3' else None
        self.admitted = owner.origins.agent.active < owner.origins.agent.max_connections
        if self.admitted:
            owner.origins.agent.active += 1
            owner.protocols.add(self)
        else:
            self.close(error_code=1, reason_phrase='connection limit')
        self.expiry = asyncio.get_running_loop().call_later(150, self.close)

    def release(self):
        self.expiry.cancel()
        if self.admitted:
            self.admitted = False
            self.owner.origins.agent.active -= 1
            self.owner.protocols.discard(self)
            if self.row is not None:
                self.row['active'] -= 1

    def datagram_received(self, data, addr):
        if self.peer is None:
            self.peer = list(addr[:2])
        elif self.peer != list(addr[:2]):
            self.close(error_code=1, reason_phrase='migration unsupported')
            return
        super().datagram_received(data, addr)

    def finish(self, stream):
        message = json.loads(self.bodies.pop(stream))
        if self.identity is not None and self.identity != (message['identity']['run_id'], message['identity']['flow_id']):
            raise ValueError('APPLICATION_QUIC_IDENTITY_CHANGED')
        if self.http:
            h3_headers(self.headers.pop(stream))
        identity, row, payload = self.owner.origins.authenticate(message, self.kind, self.peer, None)
        pair = (identity['run_id'], identity['flow_id'])
        if self.identity not in (None, pair):
            raise ValueError('APPLICATION_QUIC_IDENTITY_CHANGED')
        if self.identity is None:
            self.identity, self.row = pair, row
            row['active'] += 1
            self.owner.origins.agent.proxy.observe_quic(*pair, self.peer)
        row['rx_bytes'] += len(payload)
        row['tx_bytes'] += len(payload)
        returned = json_bytes(response(self.owner.origins.agent.secret, identity, self.peer, base64.b64encode(payload).decode()))
        if self.http:
            self.http.send_headers(stream, [(b':status', b'200'), (b'content-type', b'application/json')])
            self.http.send_data(stream, returned, end_stream=True)
        else:
            self._quic.send_stream_data(stream, returned, end_stream=True)
        self.transmit()

    def quic_event_received(self, event):
        if isinstance(event, ConnectionTerminated):
            self.release()
            return
        if not self.admitted:
            return
        try:
            if isinstance(event, StreamReset):
                raise ValueError('APPLICATION_QUIC_STREAM_RESET')
            if self.http:
                for value in self.http.handle_event(event):
                    if isinstance(value, HeadersReceived):
                        if value.stream_id in self.headers:
                            raise ValueError('APPLICATION_HTTP3_TRAILERS_UNSUPPORTED')
                        h3_headers(value.headers)
                        self.headers[value.stream_id] = value.headers
                        self.bodies[value.stream_id] = bytearray()
                    elif isinstance(value, DataReceived):
                        if value.stream_id not in self.bodies:
                            raise ValueError('APPLICATION_HTTP3_HEADERS_REQUIRED')
                        append_body(self.bodies[value.stream_id], value.data)
                    else:
                        continue
                    if len(self.bodies) > 8:
                        raise ValueError('APPLICATION_QUIC_STREAM_LIMIT')
                    if value.stream_ended:
                        self.finish(value.stream_id)
            elif isinstance(event, StreamDataReceived):
                if event.stream_id % 4 != 0:
                    raise ValueError('APPLICATION_QUIC_STREAM_DIRECTION_INVALID')
                body = self.bodies.setdefault(event.stream_id, bytearray())
                if len(self.bodies) > 8:
                    raise ValueError('APPLICATION_QUIC_STREAM_LIMIT')
                append_body(body, event.data)
                if event.end_stream:
                    self.finish(event.stream_id)
        except (ValueError, KeyError, TypeError):
            if self.row is not None:
                self.row['errors'] += 1
            self.close(error_code=1, reason_phrase='invalid application exchange')
