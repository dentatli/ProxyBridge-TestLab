#!/usr/bin/env python3
"""Loopback-only IPv4/IPv6 TCP and UDP echo endpoint for pb_net_client."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import ipaddress
import json
import signal
import socket
import threading
import time
from pathlib import Path
from typing import Any


ENDPOINT_A_PORT = 41001
ENDPOINT_B_PORT = 41002
MAX_PAYLOAD = 4096
POLL_SECONDS = 0.20


def endpoint_fields(endpoint: tuple[Any, ...] | None) -> tuple[str, int]:
    if endpoint is None:
        return "", 0
    return str(endpoint[0]), int(endpoint[1])


class JsonlLogger:
    def __init__(self, path: Path) -> None:
        self._file = path.open("a", encoding="utf-8", newline="\n")
        self._lock = threading.Lock()

    def write(
        self,
        *,
        event: str,
        family: str,
        protocol: str,
        local: tuple[Any, ...] | None = None,
        remote: tuple[Any, ...] | None = None,
        payload: bytes = b"",
        error: str = "",
    ) -> None:
        local_ip, local_port = endpoint_fields(local)
        remote_ip, remote_port = endpoint_fields(remote)
        record = {
            "timestamp_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
            "monotonic_ns": time.monotonic_ns(),
            "event": event,
            "family": family,
            "protocol": protocol,
            "local_ip": local_ip,
            "local_port": local_port,
            "remote_ip": remote_ip,
            "remote_port": remote_port,
            "bytes": len(payload),
            "sha256": hashlib.sha256(payload).hexdigest() if payload else "",
            "error": error,
        }
        line = json.dumps(record, ensure_ascii=True, separators=(",", ":"))
        with self._lock:
            self._file.write(line + "\n")
            self._file.flush()

    def close(self) -> None:
        with self._lock:
            self._file.close()


def family_name(family: int) -> str:
    return "IPv4" if family == socket.AF_INET else "IPv6"


def ip_value(version: int):
    def parse(text: str) -> str:
        try:
            address = ipaddress.ip_address(text)
        except ValueError as exc:
            raise argparse.ArgumentTypeError(f"invalid IPv{version} address") from exc
        if address.version != version:
            raise argparse.ArgumentTypeError(f"address must be IPv{version}")
        return str(address)
    return parse


def port_value(text: str) -> int:
    try:
        port = int(text, 10)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("port must be a decimal integer") from exc
    if port < 1 or port > 65535:
        raise argparse.ArgumentTypeError("port must be in 1..65535")
    return port


def configure_listener(sock: socket.socket, family: int) -> None:
    if family == socket.AF_INET6:
        sock.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
    sock.settimeout(POLL_SECONDS)


def udp_loop(
    sock: socket.socket,
    stop: threading.Event,
    logger: JsonlLogger,
) -> None:
    local = sock.getsockname()
    family = family_name(sock.family)
    while not stop.is_set():
        try:
            payload, remote = sock.recvfrom(MAX_PAYLOAD + 1)
        except socket.timeout:
            continue
        except OSError as exc:
            if not stop.is_set():
                logger.write(event="RECV_ERROR", family=family, protocol="UDP",
                             local=local, error=str(exc))
            return
        if len(payload) > MAX_PAYLOAD:
            logger.write(event="REJECTED", family=family, protocol="UDP",
                         local=local, remote=remote, payload=payload[:MAX_PAYLOAD],
                         error="payload_too_large")
            continue
        logger.write(event="RECEIVED", family=family, protocol="UDP",
                     local=local, remote=remote, payload=payload)
        try:
            sent = sock.sendto(payload, remote)
            if sent != len(payload):
                raise OSError(f"partial UDP echo {sent}/{len(payload)}")
            logger.write(event="ECHOED", family=family, protocol="UDP",
                         local=local, remote=remote, payload=payload)
        except OSError as exc:
            logger.write(event="SEND_ERROR", family=family, protocol="UDP",
                         local=local, remote=remote, payload=payload, error=str(exc))


def tcp_client_loop(
    client: socket.socket,
    remote: tuple[Any, ...],
    stop: threading.Event,
    logger: JsonlLogger,
) -> None:
    client.settimeout(POLL_SECONDS)
    local = client.getsockname()
    family = family_name(client.family)
    total = 0
    message_buffer = bytearray()
    logger.write(event="ACCEPTED", family=family, protocol="TCP",
                 local=local, remote=remote)
    try:
        while not stop.is_set():
            try:
                payload = client.recv(min(1024, MAX_PAYLOAD - total + 1))
            except socket.timeout:
                continue
            if not payload:
                logger.write(event="CLOSED", family=family, protocol="TCP",
                             local=local, remote=remote)
                return
            total += len(payload)
            if total > MAX_PAYLOAD:
                logger.write(event="REJECTED", family=family, protocol="TCP",
                             local=local, remote=remote, payload=payload,
                             error="connection_payload_too_large")
                return
            message_buffer.extend(payload)
            while b"\n" in message_buffer:
                boundary = message_buffer.index(b"\n") + 1
                message = bytes(message_buffer[:boundary])
                del message_buffer[:boundary]
                logger.write(event="MESSAGE_RECEIVED", family=family,
                             protocol="TCP", local=local, remote=remote,
                             payload=message)
            client.sendall(payload)
            logger.write(event="ECHOED", family=family, protocol="TCP",
                         local=local, remote=remote, payload=payload)
    except OSError as exc:
        logger.write(event="CLIENT_ERROR", family=family, protocol="TCP",
                     local=local, remote=remote, error=str(exc))
    finally:
        client.close()


def tcp_accept_loop(
    sock: socket.socket,
    stop: threading.Event,
    logger: JsonlLogger,
    clients: list[threading.Thread],
    clients_lock: threading.Lock,
) -> None:
    local = sock.getsockname()
    family = family_name(sock.family)
    while not stop.is_set():
        try:
            client, remote = sock.accept()
        except socket.timeout:
            continue
        except OSError as exc:
            if not stop.is_set():
                logger.write(event="ACCEPT_ERROR", family=family, protocol="TCP",
                             local=local, error=str(exc))
            return
        thread = threading.Thread(
            target=tcp_client_loop,
            args=(client, remote, stop, logger),
            name=f"tcp-{family}-{remote[0]}-{remote[1]}",
            daemon=True,
        )
        with clients_lock:
            clients.append(thread)
        thread.start()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jsonl-log", required=True, type=Path)
    parser.add_argument("--bind-ipv4", default="127.0.0.1", type=ip_value(4))
    parser.add_argument("--bind-ipv6", default="::1", type=ip_value(6))
    parser.add_argument("--endpoint-a-port", default=ENDPOINT_A_PORT, type=port_value)
    parser.add_argument("--endpoint-b-port", default=ENDPOINT_B_PORT, type=port_value)
    args = parser.parse_args()
    if args.endpoint_a_port == args.endpoint_b_port:
        parser.error("endpoint A and endpoint B ports must differ")
    return args


def main() -> int:
    args = parse_args()
    logger = JsonlLogger(args.jsonl_log)
    stop = threading.Event()
    listeners: list[socket.socket] = []
    services: list[threading.Thread] = []
    clients: list[threading.Thread] = []
    clients_lock = threading.Lock()
    exit_code = 0

    def request_stop(_signum: int, _frame: object) -> None:
        stop.set()

    signal.signal(signal.SIGINT, request_stop)
    signal.signal(signal.SIGTERM, request_stop)
    try:
        listener_specs = tuple(
            (family, kind, host, port, protocol)
            for family, host in (
                (socket.AF_INET, args.bind_ipv4),
                (socket.AF_INET6, args.bind_ipv6),
            )
            for port in (args.endpoint_a_port, args.endpoint_b_port)
            for kind, protocol in (
                (socket.SOCK_DGRAM, "UDP"),
                (socket.SOCK_STREAM, "TCP"),
            )
        )
        for family, kind, host, port, protocol in listener_specs:
            sock = socket.socket(family, kind)
            configure_listener(sock, family)
            sock.bind((host, port))
            if kind == socket.SOCK_STREAM:
                sock.listen(socket.SOMAXCONN)
            listeners.append(sock)
            logger.write(event="LISTENING", family=family_name(family),
                         protocol=protocol, local=sock.getsockname())

        for sock in listeners:
            if sock.type & socket.SOCK_DGRAM:
                target = udp_loop
                arguments = (sock, stop, logger)
            else:
                target = tcp_accept_loop
                arguments = (sock, stop, logger, clients, clients_lock)
            thread = threading.Thread(target=target, args=arguments,
                                      name=f"listener-{family_name(sock.family)}-{sock.type}",
                                      daemon=True)
            services.append(thread)
            thread.start()
        print(
            f"READY 8 listeners A={args.endpoint_a_port} B={args.endpoint_b_port}",
            flush=True,
        )
        while not stop.wait(POLL_SECONDS):
            pass
    except Exception as exc:
        exit_code = 1
        logger.write(event="SERVER_ERROR", family="", protocol="SERVER",
                     error=str(exc))
        print(f"SERVER_ERROR {exc}", flush=True)
    finally:
        stop.set()
        for sock in listeners:
            try:
                sock.close()
            except OSError:
                pass
        for thread in services:
            thread.join(timeout=1.0)
        with clients_lock:
            snapshot = list(clients)
        for thread in snapshot:
            thread.join(timeout=1.0)
        logger.write(event="STOPPED", family="", protocol="SERVER",
                     error="" if exit_code == 0 else "server_error")
        logger.close()
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
