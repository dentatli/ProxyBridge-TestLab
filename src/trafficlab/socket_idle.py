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
