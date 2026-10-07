"""Bounded SOCKS5 UDP probe using the pinned asyncio-socks-server relay.

No protocol engine is implemented here. Hooks record payload/socket evidence and
restrict destinations; stdin owns shutdown instead of Unix-only signal handlers.
"""
import argparse
import asyncio
import datetime as dt
import hashlib
import importlib.metadata
import json
import logging
import os
from pathlib import Path
import sys
import threading

WHEEL_SHA256 = "5190d3ae00a29325ec9048306fcd8bd08f8e89ddd75c535cc01d1d646f105344"


async def serve(args):
    if hashlib.sha256(args.wheel.read_bytes()).hexdigest() != WHEEL_SHA256:
        raise ValueError("SOCKS_SERVER_WHEEL_DIGEST_MISMATCH")
    sys.path.insert(0, str(args.wheel.resolve()))
    from asyncio_socks_server import Addon, Server
    from asyncio_socks_server.core.protocol import parse_udp_header
    from asyncio_socks_server.server.udp_relay import UdpRelay
    if importlib.metadata.version("asyncio-socks-server") != "1.3.3":
        raise ValueError("SOCKS_SERVER_VERSION_MISMATCH")

    with args.jsonl_log.open("x", encoding="utf-8", buffering=262144) as log:
        def emit(event, **fields):
            log.write(json.dumps(dict(timestamp_utc=dt.datetime.now(dt.timezone.utc).isoformat(),
                                      event=event, process_id=os.getpid(), log_flush_mode=args.log_flush_mode, **fields),
                                 separators=(",", ":")) + "\n")
            if args.log_flush_mode == "FLUSH_EACH" or event not in {"UDP_OUTBOUND_DATAGRAM", "UDP_RETURN_DATAGRAM"}:
                log.flush()

        class CaptureLog(logging.Handler):
            def emit(self, record):
                message = record.getMessage()
                emit("LIBRARY_MESSAGE", message=message)
                if message.startswith("event=server_started "):
                    emit("LISTENING", local_ip="127.0.0.1", local_port=args.port,
                         library="asyncio-socks-server", version="1.3.3")

        class ObservedRelay(UdpRelay):
            async def start(self):
                address = await super().start()
                emit("UDP_OUTBOUND_BOUND", connection_id=str(self._flow.id),
                     outbound_local_ip=address.host, outbound_local_port=address.port)
                return address

            def set_client_transport(self, transport):
                super().set_client_transport(transport)
                address = transport.get_extra_info("sockname")
                emit("UDP_ASSOCIATE_READY", connection_id=str(self._flow.id),
                     inbound_peer_ip=self._flow.src.host, inbound_peer_port=self._flow.src.port,
                     relay_bind_ip=address[0], relay_bind_port=address[1])

            def handle_client_datagram(self, data, client_addr):
                try:
                    destination, _, payload = parse_udp_header(data)
                except Exception as error:
                    emit("UDP_REJECTED", reason=str(error))
                    return
                if destination.host != "127.0.0.1" or destination.port not in args.receiver_port:
                    emit("UDP_REJECTED", reason="DESTINATION_OUTSIDE_PROBE")
                    return
                super().handle_client_datagram(data, client_addr)
                address = self._transport.get_extra_info("sockname")
                emit("UDP_OUTBOUND_DATAGRAM", connection_id=str(self._flow.id),
                     inbound_peer_ip=client_addr[0], inbound_peer_port=client_addr[1],
                     destination_ip=destination.host, destination_port=destination.port,
                     outbound_local_ip=address[0], outbound_local_port=address[1],
                     payload_sha256=hashlib.sha256(payload).hexdigest(), bytes=len(payload))

            def _on_remote_data(self, data, remote_addr):
                emit("UDP_RETURN_DATAGRAM", connection_id=str(self._flow.id),
                     remote_ip=remote_addr[0].removeprefix("::ffff:"), remote_port=remote_addr[1],
                     payload_sha256=hashlib.sha256(data).hexdigest(), bytes=len(data))
                super()._on_remote_data(data, remote_addr)

        class ObserveUdp(Addon):
            async def on_connect(self, flow):
                # This host is UDP-only; prevent unrelated TCP forwarding.
                raise ValueError("TCP_FORWARDING_NOT_CONFIGURED")

            async def on_udp_associate(self, flow):
                return ObservedRelay(client_addr=flow.src, flow=flow)

            async def on_flow_close(self, flow):
                emit("FLOW_CLOSED", connection_id=str(flow.id), protocol=flow.protocol,
                     bytes_up=flow.bytes_up, bytes_down=flow.bytes_down)

        class WindowsProbeServer(Server):
            def _install_signal_handlers(self):
                # Pinned upstream uses loop.add_signal_handler, unavailable on Windows.
                # The probe's bounded stdin controller calls request_shutdown instead.
                pass

        handler = CaptureLog()
        logger = logging.getLogger("asyncio_socks_server")
        logger.addHandler(handler)
        server = WindowsProbeServer(host="127.0.0.1", port=args.port,
                                    addons=[ObserveUdp()], shutdown_timeout=1.0,
                                    log_format="json")
        loop = asyncio.get_running_loop()
        shutdown_reason = None
        def request_shutdown(reason):
            nonlocal shutdown_reason
            if shutdown_reason is None:
                shutdown_reason = reason
                server.request_shutdown()
        def control():
            while True:
                command = sys.stdin.readline()
                if not command or command.strip() == "STOP":
                    loop.call_soon_threadsafe(request_shutdown, "STDIN_STOP" if command else "STDIN_EOF")
                    return
        threading.Thread(target=control, daemon=True).start()
        timeout = loop.call_later(args.max_duration_seconds, request_shutdown, "WATCHDOG_EXPIRED")
        try:
            await server._run()
            emit("STOPPED", shutdown_reason=shutdown_reason or "SERVER_RETURNED")
        finally:
            timeout.cancel()
            logger.removeHandler(handler)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wheel", type=Path, required=True)
    parser.add_argument("--jsonl-log", type=Path, required=True)
    parser.add_argument("--log-flush-mode", choices=("FLUSH_EACH", "BUFFERED"), default="FLUSH_EACH")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--receiver-port", type=int, action="append", required=True)
    parser.add_argument("--max-duration-seconds", type=int, default=60)
    args = parser.parse_args()
    if not (1024 <= args.port <= 65535 and all(1024 <= port <= 65535 for port in args.receiver_port)):
        parser.error("probe ports must be between 1024 and 65535")
    if not 10 <= args.max_duration_seconds <= 14400:
        parser.error("max duration must be between 10 and 14400 seconds")
    asyncio.run(serve(args))


if __name__ == "__main__":
    main()
