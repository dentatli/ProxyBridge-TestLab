"""Isolated EOF-only adaptation of the pinned SOCKS fixture; ordinary helper unchanged."""
import argparse
import ast
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import sys
import time
import zipfile

BASE_SHA = 'bd3a487dca62556a83472d68ab24cad870d238b37a4e29be4eeaa06c7a65b2f1'
WHEEL_SHA = '5190d3ae00a29325ec9048306fcd8bd08f8e89ddd75c535cc01d1d646f105344'


def main():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument('--wheel', type=Path, required=True)
    parser.add_argument('--jsonl-log', type=Path, required=True)
    args, _ = parser.parse_known_args()
    base = Path(__file__).with_name('pb_controlled_tcp_proxy.py')
    for path, sha in ((base, BASE_SHA), (args.wheel, WHEEL_SHA)):
        if hashlib.sha256(path.read_bytes()).hexdigest() != sha:
            raise ValueError('HALFCLOSE_DIAGNOSTIC_SOURCE_CHANGED')
    sys.path.insert(0, str(args.wheel.resolve()))
    import asyncio_socks_server.server.tcp_relay as relay
    import asyncio_socks_server.server.server as server_module
    import pb_controlled_tcp_proxy as helper
    with zipfile.ZipFile(args.wheel) as archive:
        source = archive.read('asyncio_socks_server/server/tcp_relay.py').decode('utf-8')
    original = source[source.index('async def _copy('):source.index('\n\nasync def handle_tcp_relay(')]
    # Reuse upstream copying, addon dispatch, 4096-byte buffers and counters verbatim.
    # Changes execute on EOF/teardown only; do not replace the transfer loop.
    close = '            writer.close()\n            await writer.wait_closed()'
    if original.count(close) != 1:
        raise ValueError('HALFCLOSE_DIAGNOSTIC_CLOSE_BLOCK_CHANGED')
    adapted = original.replace('    try:\n', '    eof = False\n    try:\n', 1)
    adapted = adapted.replace('            if not data:\n                break',
                              '            if not data:\n                eof = True\n                break', 1)
    adapted = adapted.replace(close, '''            if eof and writer.can_write_eof():
                writer.write_eof()
                await writer.drain()
                _halfclose_emit('WRITE_EOF', flow_id=flow.id, direction=direction.name,
                                local=writer.get_extra_info('sockname'), peer=writer.get_extra_info('peername'))
            else:
                writer.close()
                await writer.wait_closed()''', 1)
    original_loop = next(n for n in ast.walk(ast.parse(original)) if isinstance(n, ast.While))
    adapted_loop = next(n for n in ast.walk(ast.parse(adapted)) if isinstance(n, ast.While))
    original_non_eof = original_loop.body[2:]
    adapted_non_eof = adapted_loop.body[2:]
    if ast.dump(ast.Module(body=original_non_eof, type_ignores=[])) != ast.dump(ast.Module(body=adapted_non_eof, type_ignores=[])):
        raise ValueError('HALFCLOSE_DIAGNOSTIC_TRANSFER_LOOP_CHANGED')
    with args.jsonl_log.with_name('proxy-halfclose.jsonl').open('x', encoding='utf-8') as log:
        def emit(event, **fields):
            log.write(json.dumps(dict(event=event, process_id=os.getpid(), qpc_ms=time.perf_counter()*1000,
                                     timestamp_utc=dt.datetime.now(dt.timezone.utc).isoformat(), **fields))+'\n')
            log.flush()
        emit('ADAPTATION_READY', fixture_revision='halfclose_diagnostic_v1', base_sha256=BASE_SHA,
             wheel_sha256=WHEEL_SHA, original_copy_sha256=hashlib.sha256(original.encode()).hexdigest(),
             adapted_copy_sha256=hashlib.sha256(adapted.encode()).hexdigest(), transfer_loop_unchanged=True,
             launcher_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
        original_copy = relay._copy
        original_handle = server_module.handle_tcp_relay
        relay._halfclose_emit = emit
        exec(compile(adapted, str(Path(__file__).resolve()), 'exec'), relay.__dict__)
        async def handle(*arguments, **keywords):
            try:
                await original_handle(*arguments, **keywords)
            finally:
                writers = (arguments[1], arguments[3])
                for writer in writers:
                    writer.close()
                for writer in writers:
                    try:
                        await writer.wait_closed()
                    except (ConnectionError, OSError):
                        pass
                emit('BOTH_DIRECTIONS_FINISHED', flow_id=arguments[5].id)
        server_module.handle_tcp_relay = handle
        try:
            helper.main()
        finally:
            relay._copy = original_copy
            server_module.handle_tcp_relay = original_handle
            del relay._halfclose_emit


if __name__ == '__main__':
    main()
