"""Bounded line exchange inside the controlled SSH exec channel."""
from trafficlab.protocol import MAX_LINE


async def read_line(reader):
    data = bytearray()
    while len(data) <= MAX_LINE:
        piece = await reader.read(min(1024, MAX_LINE + 1 - len(data)))
        if not piece:
            if data:
                raise ValueError('APPLICATION_SSH_LINE_TRUNCATED')
            return b''
        data.extend(piece)
        if b'\n' in piece:
            if not data.endswith(b'\n') or data.count(b'\n') != 1 or len(data) > MAX_LINE:
                break
            return bytes(data)
    raise ValueError('APPLICATION_SSH_MESSAGE_TOO_LARGE')
