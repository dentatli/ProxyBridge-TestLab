"""Bounded binary/control framing and reassembly; RFC 6455 sections 5.2–5.5."""
from __future__ import annotations
import secrets
import struct
from typing import Any
from trafficlab.protocol import MAX_LINE
from trafficlab.socks_client import exact_socket

PROFILE = 'binary-single-and-fragmented-with-interleaved-control-v1'
MAX_FRAMES = 64


def validate_close(data: bytes) -> None:
    if not data:
        return
    if len(data) < 2:
        raise ValueError('APPLICATION_WEBSOCKET_CLOSE_INVALID')
    code = int.from_bytes(data[:2], 'big')
    if not (1000 <= code <= 1014 and code not in (1004,1005,1006) or 3000 <= code <= 4999):
        raise ValueError('APPLICATION_WEBSOCKET_CLOSE_INVALID')
    try:
        data[2:].decode('utf-8')
    except UnicodeError:
        raise ValueError('APPLICATION_WEBSOCKET_CLOSE_INVALID') from None


def frame(payload: bytes, masked: bool, opcode: int = 2, final: bool = True) -> bytes:
    if type(final) is not bool or opcode not in (0,2,8,9,10) or len(payload) > MAX_LINE:
        raise ValueError('APPLICATION_WEBSOCKET_FRAME_INVALID')
    if opcode >= 8 and (not final or len(payload) > 125):
        raise ValueError('APPLICATION_WEBSOCKET_FRAME_INVALID')
    if opcode == 8:
        validate_close(payload)
    length = len(payload)
    prefix = bytes([(0x80 if final else 0)|opcode, (0x80 if masked else 0)|(length if length<126 else 126)])
    if length >= 126:
        prefix += struct.pack('!H',length)
    if not masked:
        return prefix+payload
    key=secrets.token_bytes(4)
    return prefix+key+bytes(value^key[index%4] for index,value in enumerate(payload))


def prefix(first: int, second: int, masked: bool) -> tuple[bool,int,int]:
    final,opcode,size=bool(first&0x80),first&15,second&127
    if first&0x70 or bool(second&0x80)!=masked or opcode not in (0,2,8,9,10) or size==127:
        raise ValueError('APPLICATION_WEBSOCKET_FRAME_INVALID')
    if opcode>=8 and (not final or size>125):
        raise ValueError('APPLICATION_WEBSOCKET_FRAME_INVALID')
    return final,opcode,size


def length(marker: int, extended: bytes) -> int:
    size=int.from_bytes(extended,'big') if marker==126 else marker
    if size>MAX_LINE or marker==126 and (len(extended)!=2 or size<126):
        raise ValueError('APPLICATION_WEBSOCKET_FRAME_INVALID')
    return size


def unmask(data: bytes,key: bytes) -> bytes:
    return bytes(value^key[index%4] for index,value in enumerate(data)) if key else data


def read_frame(sock: Any, masked: bool=False) -> tuple[bool,int,bytes]:
    final,opcode,marker=prefix(*exact_socket(sock,2),masked)
    size=length(marker,exact_socket(sock,2) if marker==126 else b'')
    key=exact_socket(sock,4) if masked else b''
    return final,opcode,unmask(exact_socket(sock,size),key)


async def read_frame_async(reader: Any, masked: bool=True) -> tuple[bool,int,bytes]:
    final,opcode,marker=prefix(*await reader.readexactly(2),masked)
    size=length(marker,await reader.readexactly(2) if marker==126 else b'')
    key=await reader.readexactly(4) if masked else b''
    return final,opcode,unmask(await reader.readexactly(size),key)


class MessageAssembler:
    def __init__(self) -> None:
        self.active=False
        self.buffer=bytearray()
        self.frames=self.window_frames=self.last_fragments=0

    def feed(self, final: bool, opcode: int, data: bytes) -> tuple[int,bytes] | None:
        if type(final) is not bool or opcode not in (0,2,8,9,10):
            raise ValueError('APPLICATION_WEBSOCKET_FRAME_INVALID')
        self.window_frames+=1
        if self.window_frames>MAX_FRAMES:
            raise ValueError('APPLICATION_WEBSOCKET_FRAME_LIMIT')
        if opcode>=8:
            if not final or len(data)>125:
                raise ValueError('APPLICATION_WEBSOCKET_FRAME_INVALID')
            if opcode==8:
                validate_close(data)
                self.active=False
                self.buffer.clear()
            return opcode,data
        if opcode==2:
            if self.active:
                raise ValueError('APPLICATION_WEBSOCKET_INTERLEAVED_MESSAGE')
            self.active=True
            self.frames=0
        elif opcode!=0 or not self.active:
            raise ValueError('APPLICATION_WEBSOCKET_CONTINUATION_INVALID')
        self.frames+=1
        if len(self.buffer)+len(data)>MAX_LINE:
            raise ValueError('APPLICATION_WEBSOCKET_MESSAGE_LIMIT')
        self.buffer.extend(data)
        if not final:
            return None
        result=bytes(self.buffer)
        self.last_fragments=self.frames
        self.active=False
        self.buffer.clear()
        self.window_frames=0
        return 2,result


def fragmented_message(payload: bytes, masked: bool, ping: bytes) -> bytes:
    if not 3<=len(payload)<=MAX_LINE:
        raise ValueError('APPLICATION_WEBSOCKET_MESSAGE_LIMIT')
    first,second=len(payload)//3,2*len(payload)//3
    return (frame(payload[:first],masked,2,False)+frame(ping,masked,9)+
            frame(payload[first:second],masked,0,False)+frame(payload[second:],masked,0,True))


class WebSocketClient:
    def __init__(self,sock: Any) -> None:
        self.sock=sock
        self.assembler=MessageAssembler()
        self.stats={'websocket_profile':PROFILE,'ws_fragmented_requests':0,'ws_fragmented_responses':0,
                    'ws_client_pongs_verified':0,'ws_server_pings_answered':0}

    def receive(self,expected_pong: bytes | None=None) -> tuple[int,bytes]:
        pong=False
        while True:
            item=self.assembler.feed(*read_frame(self.sock))
            if item is None:
                continue
            opcode,data=item
            if opcode==9:
                self.sock.sendall(frame(data,True,10))
                self.stats['ws_server_pings_answered']+=1
            elif opcode==10:
                if expected_pong is not None:
                    if pong or data!=expected_pong:
                        raise ValueError('APPLICATION_WEBSOCKET_PONG_UNVERIFIED')
                    pong=True
                    self.stats['ws_client_pongs_verified']+=1
            else:
                if expected_pong is not None and not pong:
                    raise ValueError('APPLICATION_WEBSOCKET_PONG_UNVERIFIED')
                return opcode,data

    def exchange(self,message: bytes,fragmented: bool) -> bytes:
        ping=secrets.token_bytes(8) if fragmented else None
        self.sock.sendall(fragmented_message(message,True,ping) if fragmented else frame(message,True))
        opcode,data=self.receive(ping)
        if opcode!=2 or fragmented!=(self.assembler.last_fragments>1):
            raise ValueError('APPLICATION_WEBSOCKET_RESPONSE_PROFILE_INVALID')
        if fragmented:
            self.stats['ws_fragmented_requests']+=1
            self.stats['ws_fragmented_responses']+=1
        return data

    def close(self) -> None:
        close=struct.pack('!H',1000)
        self.sock.sendall(frame(close,True,8))
        if self.receive()!=(8,close):
            raise ValueError('APPLICATION_WEBSOCKET_CLOSE_UNVERIFIED')
