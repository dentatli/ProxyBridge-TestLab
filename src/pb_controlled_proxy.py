"""Loopback TCP proxy probe host; protocol and relay are provided by pinned pproxy.

This is a bounded route diagnostic, not the selected throughput benchmark engine.
"""
import argparse
import asyncio
import contextvars
import datetime as dt
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import sys
import threading
import uuid

WHEEL_SHA256 = "a073d02616a47c43e1d20a547918c307dbda598c6d53869b165025f3cfe58e80"
connection_context = contextvars.ContextVar("connection", default={})


async def serve(args):
    if hashlib.sha256(args.wheel.read_bytes()).hexdigest() != WHEEL_SHA256:
        raise ValueError("PPROXY_WHEEL_DIGEST_MISMATCH")
    sys.path.insert(0, str(args.wheel.resolve()))
    import pproxy
    from pproxy.server import ProxyDirect, stream_handler

    if importlib.metadata.version("pproxy") != "2.7.9":
        raise ValueError("PPROXY_VERSION_MISMATCH")
    with args.jsonl_log.open("x", encoding="utf-8") as log:
        def emit(event, **fields):
            record = dict(timestamp_utc=dt.datetime.now(dt.timezone.utc).isoformat(),
                          event=event, process_id=os.getpid(),
                          **connection_context.get(), **fields)
            log.write(json.dumps(record, separators=(",", ":")) + "\n")
            log.flush()

        class ObservedDirect(ProxyDirect):
            @property
            def direct(self):
                return True

            async def open_connection(self, host, port, *positional, **keywords):
                if host != "127.0.0.1" or port not in args.receiver_port:
                    raise ValueError("DESTINATION_OUTSIDE_PROBE")
                reader, writer = await super().open_connection(host, port, *positional, **keywords)
                local = writer.get_extra_info("sockname")
                peer = writer.get_extra_info("peername")
                emit("OUTBOUND_CONNECTED", destination_ip=host, destination_port=port,
                     outbound_local_ip=local[0], outbound_local_port=local[1],
                     outbound_peer_ip=peer[0], outbound_peer_port=peer[1])
                return reader, writer

        async def observed_handler(reader, writer, **kwargs):
            peer = writer.get_extra_info("peername")
            token = connection_context.set(dict(connection_id=uuid.uuid4().hex,
                                                 inbound_peer_ip=peer[0], inbound_peer_port=peer[1]))
            try:
                emit("INBOUND_ACCEPTED")
                await stream_handler(reader, writer, **kwargs)
            finally:
                connection_context.reset(token)

        proxy = pproxy.Server(f"{args.proxy_type}://127.0.0.1:{args.port}")
        server = await proxy.start_server(dict(
            rserver=[ObservedDirect()],
            verbose=lambda message: emit("LIBRARY_MESSAGE", message=message),
            block=lambda host: host != "127.0.0.1",
        ), stream_handler=observed_handler)
        emit("LISTENING", local_ip="127.0.0.1", local_port=args.port,
             library="pproxy", version="2.7.9", proxy_type=args.proxy_type)
        stop = asyncio.Event()
        loop = asyncio.get_running_loop()

        def control():
            while True:
                command = sys.stdin.readline()
                if not command or command.strip() == "STOP":
                    loop.call_soon_threadsafe(stop.set)
                    return

        threading.Thread(target=control, daemon=True).start()
        try:
            await asyncio.wait_for(stop.wait(), timeout=60)
        finally:
            server.close()
            await server.wait_closed()
            emit("STOPPED")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wheel", type=Path, required=True)
    parser.add_argument("--jsonl-log", type=Path, required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--receiver-port", type=int, action="append", required=True)
    parser.add_argument("--proxy-type", choices=("socks5", "http"), default="socks5")
    args = parser.parse_args()
    if not (1024 <= args.port <= 65535 and all(1024 <= port <= 65535 for port in args.receiver_port)):
        parser.error("probe ports must be between 1024 and 65535")
    asyncio.run(serve(args))


if __name__ == "__main__":
    main()
