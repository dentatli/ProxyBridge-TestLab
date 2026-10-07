"""Bounded manual diagnosis of the controlled SOCKS fixture, without ProxyBridge."""
import argparse
import asyncio
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

WHEEL_SHA = '5190d3ae00a29325ec9048306fcd8bd08f8e89ddd75c535cc01d1d646f105344'
BASE_SHA = 'bd3a487dca62556a83472d68ab24cad870d238b37a4e29be4eeaa06c7a65b2f1'


async def probe(args):
    root = Path(__file__).resolve().parent.parent
    wheel = root/'bin/tools/asyncio-socks-server-1.3.3/asyncio_socks_server-1.3.3-py3-none-any.whl'
    helper = root/'src/pb_controlled_tcp_proxy.py'
    for path, digest in ((wheel, WHEEL_SHA), (helper, BASE_SHA)):
        if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ValueError('Pinned fixture changed: '+str(path))
    sys.path.insert(0, str(wheel))
    launcher = root/'src/pb_tcp_halfclose_diagnostic.py' if args.half_close else helper
    from asyncio_socks_server.client.client import connect
    from asyncio_socks_server.core.types import Address
    args.directory.mkdir(parents=True, exist_ok=False)
    results = []
    current = None
    tasks = set()

    async def receive(reader, writer):
        task = asyncio.current_task()
        tasks.add(task)
        case = current
        record = dict(peer=writer.get_extra_info('peername'), local=writer.get_extra_info('sockname'),
                      payload_verified=False, eof_received=False, response_written=False, error='')
        try:
            data = await asyncio.wait_for(reader.readexactly(len(case['payload'])), 3)
            record['payload_verified'] = data == case['payload']
            if not record['payload_verified']:
                raise ValueError('Receiver payload mismatch')
            if case['scenario'] == 'REPLY_AFTER_EOF':
                if await asyncio.wait_for(reader.read(1), 3) != b'':
                    raise ValueError('Unexpected extra request bytes')
                record['eof_received'] = True
                await asyncio.sleep(.05)
            writer.write(case['response'])
            await writer.drain()
            record['response_written'] = True
            if case['scenario'] == 'REPLY_BEFORE_EOF':
                if await asyncio.wait_for(reader.read(1), 3) != b'':
                    raise ValueError('Unexpected extra request bytes')
                record['eof_received'] = True
        except Exception as error:
            record['error'] = type(error).__name__+': '+str(error)
        finally:
            writer.close()
            try:
                await asyncio.wait_for(writer.wait_closed(), 1)
            except (OSError, asyncio.TimeoutError):
                pass
            case['receiver'].set_result(record)
            tasks.discard(task)

    server = await asyncio.start_server(receive, '127.0.0.1', 0)
    receiver_port = server.sockets[0].getsockname()[1]
    reservation = await asyncio.start_server(lambda r,w: w.close(), '127.0.0.1', 0)
    proxy_port = reservation.sockets[0].getsockname()[1]
    reservation.close()
    await reservation.wait_closed()
    stdout = (args.directory/'helper-stdout.txt').open('x', encoding='utf-8')
    stderr = (args.directory/'helper-stderr.txt').open('x', encoding='utf-8')
    helper_log = args.directory/'proxy.jsonl'
    process = subprocess.Popen([sys.executable, '-u', str(launcher), '--wheel', str(wheel),
                                '--jsonl-log', str(helper_log), '--port', str(proxy_port),
                                '--receiver-port', str(receiver_port), '--max-duration-seconds', '60'],
                               stdin=subprocess.PIPE, stdout=stdout, stderr=stderr, text=True,
                               creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
    forced = False
    try:
        deadline = time.monotonic()+5
        while True:
            if process.poll() is not None:
                raise RuntimeError('Fixture exited before readiness')
            if helper_log.exists() and any(json.loads(line)['event'] == 'LISTENING'
                                           for line in helper_log.read_text(encoding='utf-8').splitlines() if line):
                break
            if time.monotonic() > deadline:
                raise TimeoutError('Fixture readiness timeout')
            await asyncio.sleep(.05)
        for repeat in range(1, 3):
            for scenario in ('REPLY_BEFORE_EOF', 'REPLY_AFTER_EOF'):
                for route in ('DIRECT', 'SOCKS_ONLY'):
                    payload = hashlib.sha256(f'{repeat}/{scenario}/{route}'.encode()).digest()*2048
                    response = b'DONE'+hashlib.sha256(payload).digest()*32
                    current = dict(scenario=scenario, payload=payload, response=response,
                                   receiver=asyncio.get_running_loop().create_future())
                    record = dict(repeat=repeat, scenario=scenario, route=route, pid=os.getpid(),
                                  payload_bytes=len(payload), response_bytes_expected=len(response),
                                  response_verified=False, orderly_eof=False, error='')
                    writer = None
                    try:
                        if route == 'DIRECT':
                            reader, writer = await asyncio.wait_for(asyncio.open_connection('127.0.0.1', receiver_port), 3)
                        else:
                            connection = await asyncio.wait_for(connect(Address('127.0.0.1', proxy_port),
                                                                        Address('127.0.0.1', receiver_port)), 3)
                            reader, writer = connection.reader, connection.writer
                        record['local'] = writer.get_extra_info('sockname')
                        record['peer'] = writer.get_extra_info('peername')
                        writer.write(payload)
                        await writer.drain()
                        if scenario == 'REPLY_AFTER_EOF':
                            writer.write_eof()
                            await writer.drain()
                        data = await asyncio.wait_for(reader.readexactly(len(response)), 3)
                        record['response_verified'] = data == response
                        if scenario == 'REPLY_BEFORE_EOF':
                            writer.write_eof()
                            await writer.drain()
                        record['orderly_eof'] = await asyncio.wait_for(reader.read(1), 3) == b''
                    except Exception as error:
                        record['error'] = type(error).__name__+': '+str(error)
                    finally:
                        if writer:
                            writer.close()
                            try:
                                await asyncio.wait_for(writer.wait_closed(), 1)
                            except (OSError, asyncio.TimeoutError):
                                pass
                    try:
                        record['receiver'] = await asyncio.wait_for(asyncio.shield(current['receiver']), 4)
                    except asyncio.TimeoutError:
                        raise RuntimeError('Receiver did not finish; cannot continue with another case')
                    record['status'] = 'PASS' if (record['response_verified'] and record['orderly_eof'] and
                                                  not record['error'] and record['receiver']['payload_verified'] and
                                                  record['receiver']['eof_received'] and not record['receiver']['error']) else 'FAIL'
                    results.append(record)
                    (args.directory/'cases.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
    finally:
        server.close()
        await server.wait_closed()
        if process.poll() is None:
            process.stdin.write('STOP\n')
            process.stdin.flush()
            try:
                await asyncio.to_thread(process.wait, 5)
            except subprocess.TimeoutExpired:
                process.kill()
                await asyncio.to_thread(process.wait, 2)
                forced = True
        process.stdin.close()
        stdout.close()
        stderr.close()
        if tasks:
            for task in list(tasks):
                task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)
        (args.directory/'probe-receipt.json').write_text(json.dumps(dict(
            diagnostic_only=True, product_started=False, benchmark=False, generator_pid=os.getpid(),
            helper_pid=process.pid, helper_exit_code=process.returncode, helper_forced_stop=forced,
            receiver_port=receiver_port, proxy_port=proxy_port, wheel_sha256=WHEEL_SHA, base_helper_sha256=BASE_SHA,
            fixture_revision='halfclose_diagnostic_v1' if args.half_close else 'original',
            launcher_sha256=hashlib.sha256(launcher.read_bytes()).hexdigest(),
            probe_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), completed_cases=len(results)), indent=2), encoding='utf-8')
    print(json.dumps(dict(directory=str(args.directory), helper_exit_code=process.returncode,
                          forced_stop=forced, cases=[{k:x[k] for k in ('scenario','route','repeat','status','error')}
                                                   for x in results])))
    return process.returncode == 0 and not forced and len(results) == 8


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--half-close', action='store_true')
    args = parser.parse_args()
    def create_loop():
        loop = asyncio.SelectorEventLoop() if sys.platform == 'win32' else asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        return loop
    raise SystemExit(0 if asyncio.run(probe(args), loop_factory=create_loop) else 1)


if __name__ == '__main__':
    main()
