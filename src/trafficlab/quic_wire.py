"""Bounded QUIC stream and HTTP/3 POST framing; one request per bidirectional stream."""
from __future__ import annotations
from typing import Any
from trafficlab.protocol import MAX_LINE


def append_body(body: bytearray, data: bytes) -> None:
    if len(body) + len(data) > MAX_LINE:
        raise ValueError('APPLICATION_QUIC_BODY_TOO_LARGE')
    body.extend(data)


def h3_headers(headers: list[tuple[bytes, bytes]], response: bool = False) -> dict[bytes, bytes]:
    if len(headers) > 16 or sum(len(k) + len(v) for k, v in headers) > 2048:
        raise ValueError('APPLICATION_HTTP3_HEADERS_TOO_LARGE')
    values = dict(headers)
    if len(values) != len(headers):
        raise ValueError('APPLICATION_HTTP3_DUPLICATE_HEADER')
    expected = {b':status': b'200'} if response else {b':method': b'POST', b':path': b'/testlab', b':scheme': b'https'}
    if any(values.get(key) != value for key, value in expected.items()) or values.get(b'content-type') != b'application/json':
        raise ValueError('APPLICATION_HTTP3_STATUS_OR_REQUEST_INVALID')
    return values
