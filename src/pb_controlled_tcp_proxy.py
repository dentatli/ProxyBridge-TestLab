"""Controlled TCP SOCKS5 host using unchanged asyncio-socks-server 1.3.3."""
import argparse
import asyncio
import datetime as dt
import hashlib
import importlib.metadata
import json
import ipaddress
import logging
import os
from pathlib import Path
import sys
import threading
import time


async def serve(args):
    if hashlib.sha256(args.wheel.read_bytes()).hexdigest() != '5190d3ae00a29325ec9048306fcd8bd08f8e89ddd75c535cc01d1d646f105344':
        raise ValueError('SOCKS_SERVER_WHEEL_DIGEST_MISMATCH')
    sys.path.insert(0, str(args.wheel.resolve()))
    from asyncio_socks_server import Addon, Server
    from asyncio_socks_server.core.types import Address
    from asyncio_socks_server.server.connection import Connection
    if importlib.metadata.version('asyncio-socks-server') != '1.3.3':
        raise ValueError('SOCKS_SERVER_VERSION_MISMATCH')
    with args.jsonl_log.open('x', encoding='utf-8') as log:
        def emit(event, **fields):
            log.write(json.dumps(dict(event=event, process_id=os.getpid(), qpc_ms=time.perf_counter()*1000,
                                     timestamp_utc=dt.datetime.now(dt.timezone.utc).isoformat(), **fields))+'\n')
            log.flush()

        restore_close_guard = None
        if args.guard_proactor_close_reset:
            from pb_proactor_close_guard import install
            restore_close_guard = install(args.port, emit)

        class Observe(Addon):
            async def on_connect(self, flow):
                if flow.dst.host != args.receiver_host or flow.dst.port not in {args.receiver_port, *args.additional_receiver_port}:
                    raise ValueError('DESTINATION_OUTSIDE_BENCHMARK')
                reader, writer = await asyncio.open_connection(flow.dst.host, flow.dst.port)
                local = writer.get_extra_info('sockname')
                emit('TCP_CONNECTED', connection_id=flow.id, inbound_peer_ip=flow.src.host,
                     inbound_peer_port=flow.src.port, destination_ip=flow.dst.host, destination_port=flow.dst.port,
                     outbound_local_ip=local[0], outbound_local_port=local[1])
                return Connection(reader, writer, Address(local[0], local[1]))

            async def on_udp_associate(self, flow):
                raise ValueError('UDP_NOT_CONFIGURED')

            async def on_flow_close(self, flow):
                emit('FLOW_CLOSED', connection_id=flow.id, protocol=flow.protocol,
                     bytes_up=flow.bytes_up, bytes_down=flow.bytes_down)

            async def on_error(self, error):
                emit('ERROR', reason=str(error))

        class Capture(logging.Handler):
            def emit(self, record):
                message = record.getMessage()
                emit('LIBRARY_MESSAGE', message=message)
                if message.startswith('event=server_started '):
                    emit('LISTENING', local_ip='127.0.0.1', local_port=args.port,
                         library='asyncio-socks-server', version='1.3.3',
                         receiver_ports=sorted({args.receiver_port, *args.additional_receiver_port}),
                         event_loop=type(asyncio.get_running_loop()).__name__,
                         requested_event_loop=args.event_loop)

        class WindowsServer(Server):
            def _install_signal_handlers(self):
                pass  # Windows stdin controller owns shutdown.

            def request_shutdown(self):
                super().request_shutdown()
                if args.bounded_shutdown:
                    # Python >=3.12 Server.wait_closed also waits for clients.
                    # Start the library's existing bounded task drain before its
                    # _run waits for the listener and its active clients to close.
                    async def drain():
                        await asyncio.sleep(0)
                        await super(WindowsServer, self)._wait_for_client_tasks()
                        # A reset in CPython's Proactor shutdown can occur after
                        # protocol.connection_lost but before socket.close and
                        # Server._detach. Complete only those recorded failures,
                        # after STOP. The original exception remains a test failure.
                        for transport in failed_closes:
                            sock = transport._sock
                            listener = transport._server
                            if (sock is None or listener is None or not transport._closing
                                    or transport._called_connection_lost):
                                continue
                            sock.close()
                            transport._sock = None
                            listener._detach()
                            transport._server = None
                            transport._called_connection_lost = True
                            emit('PROACTOR_CLOSE_FINALIZED', remaining_active_connections=listener._active_count)
                    self._stop_drain_task = asyncio.create_task(drain())

            async def _wait_for_client_tasks(self):
                if args.bounded_shutdown and hasattr(self, '_stop_drain_task'):
                    await self._stop_drain_task
                else:
                    await super()._wait_for_client_tasks()

        logger = logging.getLogger('asyncio_socks_server')
        handler = Capture()
        logger.addHandler(handler)
        server = WindowsServer(host='127.0.0.1', port=args.port, addons=[Observe()],
                               shutdown_timeout=1.0, log_format='json')
        loop = asyncio.get_running_loop()
        failed_closes = set()
        previous_exception_handler = loop.get_exception_handler()

        def capture_close_failure(event_loop, context):
            # Narrow compatibility cleanup for this fixture/runtime only. Do not
            # suppress asyncio errors or repair counters without closing a socket.
            from asyncio.proactor_events import _ProactorBasePipeTransport
            callback = getattr(context.get('handle'), '_callback', None)
            transport = getattr(callback, '__self__', None)
            error = context.get('exception')
            traceback = getattr(error, '__traceback__', None)
            while traceback is not None and traceback.tb_next is not None:
                traceback = traceback.tb_next
            if (isinstance(transport, _ProactorBasePipeTransport)
                    and getattr(callback, '__func__', None) is _ProactorBasePipeTransport._call_connection_lost
                    and isinstance(error, ConnectionResetError) and getattr(error, 'winerror', None) == 10054
                    and error.__context__ is None and traceback is not None
                    and traceback.tb_frame.f_code is _ProactorBasePipeTransport._call_connection_lost.__code__
                    and transport._server is not None and transport._sock is not None
                    and isinstance(transport._protocol, asyncio.StreamReaderProtocol)
                    and transport._protocol._closed.done()
                    and transport._closing and not transport._called_connection_lost):
                local = transport._sock.getsockname()
                if local[0] == '127.0.0.1' and local[1] == args.port:
                    failed_closes.add(transport)
                    emit('ERROR', reason='PROACTOR_SOCKET_CLOSE_FAILED', winerror=10054)
            if previous_exception_handler is None:
                event_loop.default_exception_handler(context)
            else:
                previous_exception_handler(event_loop, context)

        if args.bounded_shutdown and args.event_loop == 'proactor':
            loop.set_exception_handler(capture_close_failure)
        reason = None
        shutdown_requested = asyncio.Event()

        async def shutdown_diagnostics():
            # Metadata only, after STOP: no polling or socket changes during load.
            await shutdown_requested.wait()
            previous = 0
            for elapsed in (0, 1, 3):
                await asyncio.sleep(elapsed - previous)
                previous = elapsed
                tasks = []
                listeners = []
                current = asyncio.current_task()
                all_tasks = [task for task in asyncio.all_tasks() if task is not current]
                for task in all_tasks[:1024]:
                    chain = []
                    awaited = task.get_coro()
                    initial_frame = getattr(awaited, 'cr_frame', None)
                    writer = initial_frame.f_locals.get('writer') if initial_frame is not None else None
                    peer = writer.get_extra_info('peername') if isinstance(writer, asyncio.StreamWriter) else None
                    for _ in range(12):
                        frame = getattr(awaited, 'cr_frame', None) or getattr(awaited, 'gi_frame', None)
                        if frame is not None:
                            chain.append(dict(function=frame.f_code.co_name, file=Path(frame.f_code.co_filename).name,
                                              line=frame.f_lineno))
                            listener = frame.f_locals.get('srv')
                            if isinstance(listener, asyncio.Server):
                                listeners.append(dict(serving=listener.is_serving(),
                                                      active_connections=getattr(listener, '_active_count', None)))
                        next_await = getattr(awaited, 'cr_await', None) or getattr(awaited, 'gi_yieldfrom', None)
                        if next_await is None:
                            break
                        awaited = next_await
                    tasks.append(dict(done=task.done(), cancelling=task.cancelling(), await_chain=chain,
                                      inbound_peer=peer, writer_closing=writer.is_closing() if isinstance(writer, asyncio.StreamWriter) else None))
                emit('SHUTDOWN_TASKS', elapsed_seconds=elapsed, active_client_tasks=len(server._client_tasks),
                     total_tasks=len(all_tasks), truncated=len(all_tasks) > 1024, tasks=tasks, listeners=listeners)

        diagnostic_task = asyncio.create_task(shutdown_diagnostics()) if args.shutdown_diagnostics else None
        def stop(value):
            nonlocal reason
            if reason is None:
                reason = value
                emit('SHUTDOWN_REQUESTED', shutdown_reason=value)
                shutdown_requested.set()
                server.request_shutdown()
        def control():
            line = sys.stdin.readline()
            loop.call_soon_threadsafe(stop, 'STDIN_STOP' if line.strip() == 'STOP' else 'STDIN_EOF')
        threading.Thread(target=control, daemon=True).start()
        timer = loop.call_later(args.max_duration_seconds, stop, 'WATCHDOG_EXPIRED')
        try:
            await server._run()
            emit('STOPPED', shutdown_reason=reason or 'SERVER_RETURNED')
        finally:
            timer.cancel()
            if restore_close_guard is not None:
                restore_close_guard()
            if args.bounded_shutdown and args.event_loop == 'proactor':
                loop.set_exception_handler(previous_exception_handler)
            if diagnostic_task is not None:
                diagnostic_task.cancel()
                await asyncio.gather(diagnostic_task, return_exceptions=True)
            logger.removeHandler(handler)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--wheel', type=Path, required=True)
    parser.add_argument('--jsonl-log', type=Path, required=True)
    parser.add_argument('--port', type=int, required=True)
    parser.add_argument('--receiver-port', type=int, required=True)
    parser.add_argument('--receiver-host', default='127.0.0.1', help='Exact IPv4 controlled destination; local by default')
    parser.add_argument('--additional-receiver-port', type=int, action='append', default=[])
    parser.add_argument('--max-duration-seconds', type=int, default=180)
    parser.add_argument('--event-loop', choices=('selector', 'proactor'), default='selector')
    parser.add_argument('--shutdown-diagnostics', action='store_true', help='Record bounded task metadata after STOP; no payloads')
    parser.add_argument('--bounded-shutdown', action='store_true', help='Drain client tasks before waiting for server closure, only after STOP')
    parser.add_argument('--guard-proactor-close-reset', action='store_true', help='Diagnostic matrix only: pinned accepted-socket close compatibility')
    args = parser.parse_args()
    try:
        host = ipaddress.IPv4Address(args.receiver_host)
        if str(host) != args.receiver_host or host.is_unspecified or host.is_multicast or str(host)=='255.255.255.255':
            raise ValueError()
    except ValueError:
        parser.error('one canonical unicast IPv4 receiver host required')
    if not (1024 <= args.port <= 65535 and 1024 <= args.receiver_port <= 65535 and args.port != args.receiver_port):
        parser.error('distinct nonprivileged ports required')
    if len(args.additional_receiver_port)>1 or any(not 1024<=p<=65535 or p in (args.port,args.receiver_port) for p in args.additional_receiver_port):
        parser.error('at most one distinct additional controlled receiver port')
    # Workload controllers allow 600 seconds for the native client, plus
    # bounded setup/cleanup time before the helper watchdog stops the server.
    if not 10 <= args.max_duration_seconds <= 720:
        parser.error('watchdog must be 10..720 seconds')
    if sys.version_info < (3, 12):
        parser.error('Python 3.12 or newer required for explicit loop_factory')
    if args.event_loop == 'proactor' and sys.platform != 'win32':
        parser.error('Proactor fixture requires Windows')
    if args.guard_proactor_close_reset and (args.event_loop != 'proactor' or not args.bounded_shutdown):
        parser.error('close guard requires Proactor and bounded shutdown')
    def create_loop():
        # Avoid Proactor socket-shutdown failures retaining server transports on Windows.
        loop = (asyncio.ProactorEventLoop() if args.event_loop == 'proactor' else asyncio.SelectorEventLoop()) if sys.platform == 'win32' else asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        return loop
    asyncio.run(serve(args), loop_factory=create_loop)


if __name__ == '__main__':
    main()
