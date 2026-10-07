#!/usr/bin/env python3
"""Bounded IPv4 push receiver for the pinned ctsTraffic 2.0.3.9 client.

Wire contract: server sends a 36-character UUID plus NUL; client sends
the configured deterministic byte count; server acknowledges with DONE.
Only push/data-only is supported. This is not a replacement for the
Windows kernel/Core probes or a claim of ctsTraffic performance parity.

Protocol references (Microsoft, Apache-2.0), commit
b0e2a48f30fb7caaaa9994ee2dea2a177a4639e2: ctsIOPattern.cpp,
ctsIOPatternState.hpp and ctsStatistics.hpp. Independently implemented.
"""

from __future__ import annotations

import argparse
import asyncio
import datetime as dt
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import signal
import struct
import sys
import time
import uuid


METHOD = "cts-2.0.3.9-push-receiver-v1"
CTS_COMMIT = "b0e2a48f30fb7caaaa9994ee2dea2a177a4639e2"
CTS_CLIENT_SHA256 = "0548089e59c872306ce2c98e7163e2a717119756010cf64d3cb3da2854f632cf"
# ctsTraffic constructs uint16 LE values, but copies/wraps at 65536 BYTES.
PATTERN = struct.pack("<32768H", *range(32768))
PERIOD = len(PATTERN)
CHUNK = 65536


def expected_bytes(offset: int, size: int) -> bytes:
    if offset < 0 or not 0 <= size <= CHUNK:
        raise ValueError("PATTERN_WINDOW_INVALID")
    start = offset % PERIOD
    return (PATTERN + PATTERN)[start:start + size]


class VerifyPush:
    def __init__(self, total: int):
        if type(total) is not int or not 1 <= total <= 8 * 1024 ** 3:
            raise ValueError("TRANSFER_SIZE_INVALID")
        self.total = total
        self.received = 0
        self.digest = hashlib.sha256()

    def consume(self, block: bytes) -> None:
        if not block:
            raise ValueError("PREMATURE_EOF")
        if self.received + len(block) > self.total:
            raise ValueError("EXCESS_DATA")
        expected = expected_bytes(self.received, len(block))
        if block != expected:
            first = next(i for i, (actual, wanted) in enumerate(zip(block, expected)) if actual != wanted)
            raise ValueError("CORRUPT_DATA_AT_" + str(self.received + first))
        self.digest.update(block)
        self.received += len(block)

    def complete(self) -> bool:
        return self.received == self.total


class Journal:
    def __init__(self, path: Path, run_id: str):
        self.file = path.open("x", encoding="utf-8", newline="\n")
        self.run_id = run_id
        self.sequence = 0

    def emit(self, event: str, **fields) -> None:
        self.sequence += 1
        self.file.write(json.dumps({"schema_version": 1, "method": METHOD,
            "run_id": self.run_id, "event": event, "sequence": self.sequence,
            "process_id": os.getpid(), "monotonic_ns": time.monotonic_ns(),
            "timestamp_utc": dt.datetime.now(dt.timezone.utc).isoformat(), **fields},
            separators=(",", ":")) + "\n")
        self.file.flush()


async def serve(args) -> int:
    stopped = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, stopped.set)
    if sys.platform == "linux":
        import resource
        soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
        needed = args.max_connections + 128
        if soft < needed:
            if hard != resource.RLIM_INFINITY and hard < needed:
                raise ValueError("RECEIVER_FILE_LIMIT_TOO_LOW")
            resource.setrlimit(resource.RLIMIT_NOFILE, (needed, hard))
    journal = Journal(args.jsonl_log, args.run_id)
    active: set[asyncio.Task] = set()
    handlers: set[asyncio.Task] = set()
    accepted = completed = failed = rejected = peak = 0
    unexpected_errors = 0
    server = None

    async def flow(reader, writer):
        nonlocal accepted, completed, failed, rejected, peak
        task = asyncio.current_task()
        peer = writer.get_extra_info("peername")
        local = writer.get_extra_info("sockname")
        allowed = peer and peer[0] in args.allowed_source
        if not allowed or len(active) >= args.max_connections or accepted >= args.max_total_connections or stopped.is_set():
            rejected += 1
            journal.emit("REJECTED", peer=list(peer) if peer else None,
                         reason="SOURCE_NOT_ALLOWED" if not allowed else "RECEIVER_BOUND")
            writer.close()
            try:
                await asyncio.wait_for(writer.wait_closed(), 2)
            except (OSError, asyncio.TimeoutError):
                pass
            return
        active.add(task)
        accepted += 1
        peak = max(peak, len(active))
        connection_id = str(uuid.uuid4())
        verified = VerifyPush(args.transfer_bytes)
        deadline = loop.time() + args.connection_timeout_seconds
        original_error = ""
        data_confirmed = completion_sent = False
        journal.emit("ACCEPTED", connection_id=connection_id, local=list(local), peer=list(peer),
                     active_connections=len(active), requested_bytes=args.transfer_bytes)
        try:
            writer.write(connection_id.encode("ascii") + b"\0")
            await asyncio.wait_for(writer.drain(), max(0.001, deadline - loop.time()))
            while not verified.complete():
                block = await asyncio.wait_for(reader.read(min(CHUNK, verified.total - verified.received)),
                                               max(0.001, deadline - loop.time()))
                verified.consume(block)
            data_confirmed = True
            writer.write(b"DONE")
            await asyncio.wait_for(writer.drain(), max(0.001, deadline - loop.time()))
            completion_sent = True
            # A rude CTS client may reset after receiving DONE. Preserve close
            # evidence separately; reset before DONE is always an error.
            try:
                tail = await asyncio.wait_for(reader.read(1), args.close_timeout_seconds)
                if tail:
                    raise ValueError("EXCESS_DATA_AFTER_COMPLETION")
                close_status = "EOF"
            except ConnectionResetError:
                close_status = "RESET_AFTER_COMPLETION"
            completed += 1
            journal.emit("TRANSFER_VERIFIED", connection_id=connection_id, local=list(local), peer=list(peer),
                         bytes_received=verified.received, payload_sha256=verified.digest.hexdigest(),
                         completion_sent=True, close_status=close_status)
        except asyncio.CancelledError:
            failed += 1
            original_error = "CANCELLED_DURING_TRANSFER_OR_CLOSE"
            journal.emit("TRANSFER_FAILED", connection_id=connection_id, local=list(local), peer=list(peer),
                         bytes_received=verified.received, data_confirmed=data_confirmed,
                         completion_sent=completion_sent, error=original_error)
            raise
        except (OSError, ValueError, asyncio.TimeoutError) as exc:
            failed += 1
            original_error = type(exc).__name__ + ": " + str(exc)
            journal.emit("TRANSFER_FAILED", connection_id=connection_id, local=list(local), peer=list(peer),
                         bytes_received=verified.received, data_confirmed=data_confirmed,
                         completion_sent=completion_sent, error=original_error)
        finally:
            writer.close()
            try:
                await asyncio.wait_for(writer.wait_closed(), 2)
            except (OSError, asyncio.TimeoutError) as exc:
                journal.emit("CLOSE_OBSERVATION", connection_id=connection_id,
                             error=type(exc).__name__, original_error=original_error)
            active.discard(task)
            journal.emit("FLOW_ENDED", connection_id=connection_id, active_connections=len(active))

    async def handle(reader, writer):
        nonlocal unexpected_errors
        task = asyncio.current_task()
        handlers.add(task)
        try:
            await flow(reader, writer)
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            unexpected_errors += 1
            journal.emit("FIXTURE_ERROR", error=type(exc).__name__ + ": " + str(exc))
            writer.close()
        finally:
            handlers.discard(task)

    try:
        server = await asyncio.start_server(handle, args.bind_ipv4, args.port,
                                           backlog=1024, limit=CHUNK)
        journal.emit("LISTENING", bind_ipv4=args.bind_ipv4, port=args.port,
                     allowed_sources=args.allowed_source, transfer_bytes=args.transfer_bytes,
                     max_connections=args.max_connections, max_total_connections=args.max_total_connections,
                     max_duration_seconds=args.max_duration_seconds, cts_commit=CTS_COMMIT,
                     cts_client_sha256=CTS_CLIENT_SHA256, python=sys.version.split()[0],
                     receiver_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
        try:
            await asyncio.wait_for(stopped.wait(), args.max_duration_seconds)
            stop_reason = "SIGNAL"
        except asyncio.TimeoutError:
            stop_reason = "DURATION_LIMIT"
        stopped.set()
        server.close()
        await server.wait_closed()
        initial = set(handlers)
        pending = set()
        if initial:
            _, pending = await asyncio.wait(initial, timeout=args.stop_timeout_seconds)
        for task in pending:
            task.cancel()
        if pending:
            await asyncio.gather(*pending, return_exceptions=True)
        status = "CAPTURE_COMPLETE" if not active and not handlers and not pending and not rejected and not unexpected_errors else "CAPTURE_INCOMPLETE"
        journal.emit("STOPPED", status=status, stop_reason=stop_reason, accepted=accepted,
                     completed=completed, failed=failed, rejected=rejected,
                     peak_active_connections=peak, forced_flow_count=len(pending), active_connections=len(active),
                     remaining_handlers=len(handlers), unexpected_errors=unexpected_errors,
                     native_client_compatibility_verified=False, product_route_verified=False)
        return 0 if status == "CAPTURE_COMPLETE" else 2
    finally:
        if server:
            server.close()
            await server.wait_closed()
        journal.file.close()


def ipv4(text: str) -> str:
    address = ipaddress.IPv4Address(text)
    if address.is_unspecified or address.is_multicast or str(address) == "255.255.255.255":
        raise argparse.ArgumentTypeError("specific unicast IPv4 required")
    return str(address)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--inspect", action="store_true")
    mode.add_argument("--serve", action="store_true")
    mode.add_argument("--record-exit", action="store_true")
    parser.add_argument("--exit-receipt", type=Path)
    parser.add_argument("--bind-ipv4", type=ipv4)
    parser.add_argument("--allowed-source", action="append", type=ipv4, default=[])
    parser.add_argument("--port", type=int, default=54122)
    parser.add_argument("--transfer-bytes", type=int, default=524288)
    parser.add_argument("--max-connections", type=int, default=1024)
    parser.add_argument("--max-total-connections", type=int, default=1200)
    parser.add_argument("--max-duration-seconds", type=int, default=720)
    parser.add_argument("--connection-timeout-seconds", type=int, default=60)
    parser.add_argument("--close-timeout-seconds", type=int, default=10)
    parser.add_argument("--stop-timeout-seconds", type=int, default=15)
    parser.add_argument("--run-id")
    parser.add_argument("--jsonl-log", type=Path)
    args = parser.parse_args()
    if args.record_exit and not args.inspect and not args.serve and sys.platform == "linux":
        if not args.run_id or not args.exit_receipt or len(args.run_id) > 96 or not all(c in "abcdefghijklmnopqrstuvwxyz0123456789-" for c in args.run_id):
            parser.error("exit receipt requires a safe run ID and path")
        with args.exit_receipt.open("x", encoding="utf-8") as stream:
            json.dump({"schema_version": 1, "method": METHOD, "run_id": args.run_id,
                "receiver_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                "service_result": os.environ.get("SERVICE_RESULT", ""),
                "exit_code": os.environ.get("EXIT_CODE", ""),
                "exit_status": os.environ.get("EXIT_STATUS", ""),
                "timestamp_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
                "monotonic_ns": time.monotonic_ns()}, stream)
            stream.write("\n")
        return 0
    if args.inspect and not args.serve:
        print(json.dumps({"status": "RECEIVER_FILES_READ", "method": METHOD,
            "cts_commit": CTS_COMMIT, "cts_client_sha256": CTS_CLIENT_SHA256,
            "receiver_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            "pattern_period_bytes": PERIOD, "pattern_sha256": hashlib.sha256(PATTERN).hexdigest(),
            "connection_id_bytes": 37, "completion_bytes": 4,
            "python": sys.version.split()[0], "network_used": False,
            "native_client_compatibility_verified": False, "product_route_verified": False}))
        return 0
    if not args.serve or args.inspect or args.record_exit or sys.platform != "linux":
        parser.error("select --inspect or explicit Linux --serve")
    if not args.bind_ipv4 or not args.allowed_source or not args.jsonl_log or not args.run_id:
        parser.error("bind/source/run-id/jsonl-log are required")
    if not 1024 <= args.port <= 65535 or not 1 <= args.max_connections <= 1024:
        parser.error("invalid port or concurrent connection bound")
    if not args.max_connections <= args.max_total_connections <= 4096:
        parser.error("invalid total connection bound")
    if not 1 <= args.max_duration_seconds <= 1800 or not 1 <= args.connection_timeout_seconds <= 120:
        parser.error("invalid duration bound")
    if not 1 <= args.close_timeout_seconds <= 30 or not 1 <= args.stop_timeout_seconds <= 30:
        parser.error("invalid shutdown bound")
    if len(args.run_id) > 96 or not all(c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-" for c in args.run_id):
        parser.error("invalid run ID")
    VerifyPush(args.transfer_bytes)
    return asyncio.run(serve(args))


if __name__ == "__main__":
    raise SystemExit(main())
