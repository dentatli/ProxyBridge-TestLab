"""Explicit SOCKS client for component checks only; product workers use normal sockets."""
import ipaddress
import socket
import struct

from trafficlab.protocol import mac


def exact_socket(sock, length):
    data = b""
    while len(data) < length:
        piece = sock.recv(length - len(data))
        if not piece:
            raise EOFError("SOCKS_TRUNCATED")
        data += piece
    return data


def address(host, port):
    parsed = ipaddress.ip_address(host)
    return bytes([1 if parsed.version == 4 else 4]) + parsed.packed + struct.pack("!H", port)


def negotiate(sock, job, udp=False):
    proxy = job["test_proxy"]
    sock.connect((proxy["host"], proxy["port"]))
    sock.sendall(b"\x05\x01\x02")
    if exact_socket(sock, 2) != b"\x05\x02":
        raise ValueError("SOCKS_AUTH_METHOD_REJECTED")
    username = proxy["username"].encode("ascii")
    password = mac(bytes.fromhex(job["secret"]), b"socks:", username).encode("ascii")
    sock.sendall(b"\x01" + bytes([len(username)]) + username + bytes([len(password)]) + password)
    if exact_socket(sock, 2) != b"\x01\x00":
        raise ValueError("SOCKS_AUTH_REJECTED")
    sock.sendall(b"\x05" + bytes([3 if udp else 1]) + b"\x00" + address("0.0.0.0" if udp else job["host"], 0 if udp else job["port"]))
    prefix = exact_socket(sock, 4)
    if prefix[:3] != b"\x05\x00\x00" or prefix[3] not in (1, 4):
        raise ValueError("SOCKS_REQUEST_REJECTED")
    host = str(ipaddress.ip_address(exact_socket(sock, 4 if prefix[3] == 1 else 16)))
    port = struct.unpack("!H", exact_socket(sock, 2))[0]
    return host, port


def unwrap(packet):
    if packet[:3] != b"\x00\x00\x00" or packet[3] not in (1, 4):
        raise ValueError("SOCKS_DATAGRAM_INVALID")
    return packet[10 if packet[3] == 1 else 22:]
