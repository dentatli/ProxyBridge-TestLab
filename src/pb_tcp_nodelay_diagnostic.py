"""Opt-in accepted-socket TCP_NODELAY observation over the unchanged TCP helper."""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import socket
import sys
import time

BASE_SHA256 = 'bd3a487dca62556a83472d68ab24cad870d238b37a4e29be4eeaa06c7a65b2f1'
WHEEL_SHA256 = '5190d3ae00a29325ec9048306fcd8bd08f8e89ddd75c535cc01d1d646f105344'


def main():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument('--wheel', type=Path, required=True)
    parser.add_argument('--jsonl-log', type=Path, required=True)
    args, _ = parser.parse_known_args()
    base = Path(__file__).with_name('pb_controlled_tcp_proxy.py')
    if hashlib.sha256(base.read_bytes()).hexdigest() != BASE_SHA256:
        raise ValueError('DIAGNOSTIC_BASE_HELPER_CHANGED')
    if hashlib.sha256(args.wheel.read_bytes()).hexdigest() != WHEEL_SHA256:
        raise ValueError('DIAGNOSTIC_WHEEL_CHANGED')
    sys.path.insert(0, str(args.wheel.resolve()))
    import asyncio_socks_server as package
    import pb_controlled_tcp_proxy as helper
    original_server = package.Server
    with args.jsonl_log.with_name('proxy-socket-options.jsonl').open('x', encoding='utf-8') as log:
        class NoDelayServer(original_server):
            async def _handle_client(self, reader, writer):
                sock = writer.get_extra_info('socket')
                before = after = None
                error = ''
                try:
                    before = sock.getsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY)
                    sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                    after = sock.getsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY)
                    if after != 1:
                        raise ValueError('ACCEPTED_TCP_NODELAY_NOT_CONFIRMED')
                except Exception as exc:
                    error = str(exc)
                record = dict(event='ACCEPTED_TCP_SOCKET_OPTIONS', process_id=os.getpid(),
                              qpc_ms=time.perf_counter()*1000,
                              timestamp_utc=dt.datetime.now(dt.timezone.utc).isoformat(),
                              local=writer.get_extra_info('sockname'), peer=writer.get_extra_info('peername'),
                              proto=sock.proto if sock else None, tcp_nodelay_before=before,
                              tcp_nodelay_after=after, error=error)
                try:
                    log.write(json.dumps(record)+'\n')
                    log.flush()
                    if error:
                        raise ValueError(error)
                except Exception:
                    writer.close()
                    await writer.wait_closed()
                    raise
                await super()._handle_client(reader, writer)

        package.Server = NoDelayServer
        try:
            helper.main()
        finally:
            package.Server = original_server


if __name__ == '__main__':
    main()
