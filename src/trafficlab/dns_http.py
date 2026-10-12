"""Controlled DNS-over-HTTPS POST profile: HTTP/1.1, binary MIME, bounded DNS body."""
from __future__ import annotations
import re
from typing import Any

PATH='/dns-query'
MIME='application/dns-message'


def body_length(headers: dict[str,str]) -> int:
    if headers.get('content-type','').lower()!=MIME or 'transfer-encoding' in headers or headers.get('content-encoding','identity').lower()!='identity':
        raise ValueError('APPLICATION_DOH_MEDIA_OR_FRAMING_INVALID')
    value=headers.get('content-length','')
    if not re.fullmatch(r'[0-9]{1,3}',value) or not 17<=int(value)<=512:
        raise ValueError('APPLICATION_DOH_LENGTH_INVALID')
    return int(value)


def post(sock: Any,stream: Any,packet: bytes,server_name: str,port: int,parse_headers: Any,close: bool=False) -> bytes:
    if not 17<=len(packet)<=512:
        raise ValueError('APPLICATION_DOH_LENGTH_INVALID')
    connection='close' if close else 'keep-alive'
    sock.sendall(f'POST {PATH} HTTP/1.1\r\nHost: {server_name}:{port}\r\nContent-Type: {MIME}\r\nAccept: {MIME}\r\nContent-Length: {len(packet)}\r\nConnection: {connection}\r\n\r\n'.encode()+packet)
    status,headers=parse_headers(stream)
    if status!='HTTP/1.1 200 OK' or headers.get('cache-control')!='no-store':
        raise ValueError('APPLICATION_DOH_RESPONSE_INVALID')
    length=body_length(headers)
    reply=stream.read(length)
    if len(reply)!=length:
        raise ValueError('APPLICATION_DOH_BODY_TRUNCATED')
    return reply
