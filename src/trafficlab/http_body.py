"""Bounded Content-Length/chunked HTTP bodies with optional gzip content encoding."""
from __future__ import annotations
import gzip
import re
import zlib
from typing import Any
from trafficlab.protocol import MAX_LINE

PROFILE='content-length-chunked-gzip-combinations-v1'
MODES=((False,False),(True,False),(False,True),(True,True))
MAX_CHUNKS=64


def framing(headers: dict[str,str]) -> tuple[bool,bool,int | None]:
    transfer=headers.get('transfer-encoding')
    compressed=headers.get('content-encoding','identity').lower()
    if compressed not in ('identity','gzip'):
        raise ValueError('APPLICATION_HTTP_CONTENT_ENCODING_UNSUPPORTED')
    if transfer is not None:
        if transfer.lower()!='chunked' or 'content-length' in headers:
            raise ValueError('APPLICATION_HTTP_FRAMING_AMBIGUOUS')
        return True,compressed=='gzip',None
    value=headers.get('content-length','')
    if not re.fullmatch(r'[0-9]{1,5}',value) or not 0<int(value)<=MAX_LINE:
        raise ValueError('APPLICATION_HTTP_LENGTH_INVALID')
    return False,compressed=='gzip',int(value)


def encode(data: bytes, chunked: bool=False, compressed: bool=False) -> tuple[bytes,bytes]:
    if not 0<len(data)<=MAX_LINE:
        raise ValueError('APPLICATION_HTTP_BODY_LIMIT')
    body=gzip.compress(data,mtime=0) if compressed else data
    if len(body)>MAX_LINE:
        raise ValueError('APPLICATION_HTTP_BODY_LIMIT')
    fields=b'Content-Encoding: gzip\r\n' if compressed else b''
    if chunked:
        fields+=b'Transfer-Encoding: chunked\r\n'
        size=max(1,len(body)//3)
        body=b''.join(f'{len(body[index:index+size]):X}\r\n'.encode()+body[index:index+size]+b'\r\n'
            for index in range(0,len(body),size))+b'0\r\n\r\n'
    else:
        fields+=f'Content-Length: {len(body)}\r\n'.encode()
    return fields,body


def decode(data: bytes, compressed: bool) -> bytes:
    if not 0<len(data)<=MAX_LINE:
        raise ValueError('APPLICATION_HTTP_BODY_LIMIT')
    if not compressed:
        return data
    try:
        decoder=zlib.decompressobj(31)
        result=decoder.decompress(data,MAX_LINE+1)
        if len(result)>MAX_LINE or not decoder.eof or decoder.unused_data or decoder.unconsumed_tail:
            raise ValueError('APPLICATION_HTTP_GZIP_INVALID_OR_TOO_LARGE')
        return result
    except zlib.error:
        raise ValueError('APPLICATION_HTTP_GZIP_INVALID_OR_TOO_LARGE') from None


def chunk_size(line: bytes, total: int, count: int) -> int:
    if not re.fullmatch(rb'[0-9A-Fa-f]{1,8}\r\n',line):
        raise ValueError('APPLICATION_HTTP_CHUNK_INVALID')
    size=int(line[:-2],16)
    if total+size>MAX_LINE or count>MAX_CHUNKS or count==MAX_CHUNKS and size!=0:
        raise ValueError('APPLICATION_HTTP_CHUNK_LIMIT')
    return size


def read(stream: Any, headers: dict[str,str]) -> tuple[bytes,bool,bool]:
    chunked,compressed,size=framing(headers)
    if not chunked:
        body=stream.read(size)
        if len(body)!=size:
            raise ValueError('APPLICATION_HTTP_BODY_TRUNCATED')
    else:
        body=bytearray()
        for count in range(MAX_CHUNKS+2):
            size=chunk_size(stream.readline(129),len(body),count)
            if size==0:
                if stream.readline(129)!=b'\r\n':
                    raise ValueError('APPLICATION_HTTP_TRAILERS_UNSUPPORTED')
                break
            value=stream.read(size)
            if len(value)!=size or stream.read(2)!=b'\r\n':
                raise ValueError('APPLICATION_HTTP_CHUNK_TRUNCATED')
            body.extend(value)
        else:
            raise ValueError('APPLICATION_HTTP_CHUNK_LIMIT')
    return decode(bytes(body),compressed),chunked,compressed


async def read_async(reader: Any, headers: dict[str,str]) -> tuple[bytes,bool,bool]:
    chunked,compressed,size=framing(headers)
    if not chunked:
        body=await reader.readexactly(size)
    else:
        body=bytearray()
        for count in range(MAX_CHUNKS+2):
            line=await reader.readuntil(b'\r\n')
            if len(line)>128:
                raise ValueError('APPLICATION_HTTP_CHUNK_INVALID')
            size=chunk_size(line,len(body),count)
            if size==0:
                if await reader.readuntil(b'\r\n')!=b'\r\n':
                    raise ValueError('APPLICATION_HTTP_TRAILERS_UNSUPPORTED')
                break
            body.extend(await reader.readexactly(size))
            if await reader.readexactly(2)!=b'\r\n':
                raise ValueError('APPLICATION_HTTP_CHUNK_TRUNCATED')
        else:
            raise ValueError('APPLICATION_HTTP_CHUNK_LIMIT')
    return decode(bytes(body),compressed),chunked,compressed
