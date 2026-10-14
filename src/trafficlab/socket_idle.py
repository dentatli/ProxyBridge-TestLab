"""Observe owned accepted TCP sockets, including TLS before application callbacks."""
from __future__ import annotations
import os
import re
from pathlib import Path

MAX_PROC_BYTES = 4 * 1024 * 1024


def tcp_inodes(text, ports):
    lines=text.splitlines()
    if not lines or 'local_address' not in lines[0] or 'inode' not in lines[0]:
        raise ValueError('TRAFFIC_SOCKET_TABLE_INVALID')
    result=set()
    for line in lines[1:]:
        fields=line.split()
        if len(fields)<10:
            raise ValueError('TRAFFIC_SOCKET_TABLE_INVALID')
        local=fields[1].split(':')
        if len(local)!=2 or not re.fullmatch(r'[0-9A-Fa-f]{8}|[0-9A-Fa-f]{32}',local[0]) or not re.fullmatch(r'[0-9A-Fa-f]{4}',local[1]):
            raise ValueError('TRAFFIC_SOCKET_TABLE_INVALID')
        port=int(local[1],16)
        state=int(fields[3],16)
        if not 1<=state<=12 or not fields[9].isdecimal():
            raise ValueError('TRAFFIC_SOCKET_TABLE_INVALID')
        # LISTEN and CLOSE have no live accepted connection; logical callbacks cover buffered cleanup.
        if port in ports and state not in (7,10) and fields[9]!='0':
            result.add(fields[9])
    return result


def owned_tcp_connections(ports, observer_fd, proc_root=Path('/proc/self')):
    if os.name == 'nt':
        return windows_owned_tcp_connections(ports, observer_fd)
    try:
        if not ports or type(observer_fd) is not int or observer_fd<0:
            return None
        descriptors=os.listdir(proc_root/'fd')
        if len(descriptors)>20000:
            return None
        owned=set()
        for descriptor in descriptors:
            try:
                target=os.readlink(proc_root/'fd'/descriptor)
            except FileNotFoundError:
                continue  # proc directory iteration itself may have held a transient descriptor
            match=re.fullmatch(r'socket:\[([0-9]+)\]',target)
            if match:
                owned.add(match[1])
        observer=re.fullmatch(r'socket:\[([0-9]+)\]',os.readlink(proc_root/'fd'/str(observer_fd)))
        if observer is None or observer[1] not in owned:
            return None
        connections=set()
        for table in ('tcp','tcp6'):
            with (proc_root/'net'/table).open('r',encoding='ascii') as stream:
                data=stream.read(MAX_PROC_BYTES+1)
            if len(data)>MAX_PROC_BYTES:
                return None
            connections.update(tcp_inodes(data,ports))
        if observer[1] not in connections:
            return None
        return len((connections & owned)-{observer[1]})
    except (OSError,ValueError,UnicodeError):
        return None  # Missing evidence must never become idle=0.


def windows_owned_tcp_connections(ports, observer_fd):
    import ctypes
    import socket
    from ctypes import wintypes
    try:
        if not ports or type(observer_fd) is not int or observer_fd < 0:
            return None
        observer = socket.socket(fileno=observer_fd)
        try:
            local_port, peer_port, family = observer.getsockname()[1], observer.getpeername()[1], observer.family
        finally:
            observer.detach()  # The asyncio transport owns this handle.
        query = ctypes.WinDLL('iphlpapi', use_last_error=True).GetExtendedTcpTable
        query.argtypes = [ctypes.c_void_p, ctypes.POINTER(wintypes.DWORD), wintypes.BOOL, wintypes.ULONG, ctypes.c_int, wintypes.ULONG]
        query.restype = wintypes.DWORD
        count = matched = 0
        for af, words, local_index, remote_index, state_index, pid_index in ((2,6,2,4,0,5),(23,14,5,11,12,13)):
            size = wintypes.DWORD(0)
            if query(None, ctypes.byref(size), False, af, 5, 0) not in (0,122) or not 4 <= size.value <= MAX_PROC_BYTES:
                return None
            data = ctypes.create_string_buffer(size.value)
            if query(data, ctypes.byref(size), False, af, 5, 0):
                return None
            total = ctypes.c_uint32.from_buffer(data).value
            if total > 20000 or 4+total*words*4 > size.value:
                return None
            for index in range(total):
                row = (ctypes.c_uint32*words).from_buffer(data,4+index*words*4)
                port = socket.ntohs(row[local_index] & 65535)
                if row[pid_index] != os.getpid() or port not in ports or row[state_index] in (1,2,12):
                    continue
                if af == family and port == local_port and socket.ntohs(row[remote_index]&65535) == peer_port:
                    matched += 1
                else:
                    count += 1
        return count if matched == 1 else None
    except (OSError, ValueError, AttributeError):
        return None
