"""Essential native transport contract gate; no ProxyBridge, drivers or system changes.

Uses unchanged Python peers to detect a shared C# wire/validation mistake, then
checks the whole native pipeline and false-PASS guards. All sockets are loopback,
all children belong to this probe, and private temporary inputs are discarded.
"""
from __future__ import annotations
import base64
import concurrent.futures
import contextlib
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import socket
import subprocess
import sys
import tempfile
import threading
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'src'))
from trafficlab.native_engine import request
from trafficlab.native_engine import worker_state
from trafficlab.protocol import json_bytes, mac, pattern
from trafficlab.routes import stage_route
from trafficlab.worker import connect, execute, read_result

FLAGS = getattr(subprocess, 'CREATE_NO_WINDOW', 0)
PROJECT = ROOT / 'src/ProxyBridge.TestLab.TrafficEngine'
EXE = PROJECT / 'bin/Release/net10.0-windows/ProxyBridge.TestLab.TrafficEngine.exe'


def free_port():
    with socket.socket() as reservation:
        reservation.bind(('127.0.0.1', 0))
        return reservation.getsockname()[1]


@contextlib.contextmanager
def host(directory, secret, port, proxy=0, python=False, worker=False, ports=None):
    tag = uuid.uuid4().hex
    stop, configuration = directory / (tag + '.stop'), directory / (tag + '.json')
    control = free_port()
    config = {'bind':'127.0.0.1', 'secret':secret, 'port':port, 'proxy_port':proxy,
              'control_port':control, 'stop_path':str(stop), 'worker_only':worker,
              'origin_addresses':['127.0.0.1'], 'application_ports':ports or {}}
    configuration.write_bytes(json_bytes(config))
    command = ([sys.executable, '-B', '-u', '-m', 'trafficlab.agent'] if python else [str(EXE)]) + ['--config', str(configuration)]
    environment = dict(os.environ, PYTHONPATH=str(ROOT / 'src'), PYTHONDONTWRITEBYTECODE='1')
    child = subprocess.Popen(command, env=environment, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, text=True, creationflags=FLAGS)
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
            pending = pool.submit(child.stdout.readline)
            try:
                ready = pending.result(timeout=10).strip()
            except BaseException:
                child.kill(); child.wait(timeout=3)
                raise
        if python:
            assert ready.startswith('TRAFFIC_AGENT_READY '), ready
        else:
            assert ready.startswith('TRAFFIC_ENGINE_READY '), ready
            control = int(re.search(r'control=(\d+)', ready)[1])
        yield control
    finally:
        stop.write_text('stop', encoding='ascii')
        try:
            output, errors = child.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            child.kill(); child.communicate(timeout=3)
            raise AssertionError('Owned engine failed to stop')
        assert child.returncode == 0, (child.returncode, errors[-8192:])


def job(secret, port, task, proxy=0, connections=3, seconds=.2, connected=True):
    run = 'contract.' + uuid.uuid4().hex
    value = {'host':'127.0.0.1', 'port':port, 'secret':secret, 'run_id':run, 'task':task,
             'seconds':seconds, 'connections':connections, 'warmup_count':0, 'message_bytes':512,
             'rate_packets_per_second':100, 'udp_connected':connected}
    if proxy:
        value['test_proxy'] = {'host':'127.0.0.1', 'port':proxy, 'username':run}
    return value


def python_snapshot(control, value):
    observer = {**value, 'port':control}
    observer.pop('test_proxy', None)
    connection, stream, context, _ = connect(observer, 'metrics', str(uuid.uuid4()))
    try:
        return read_result(observer, stream, context)
    finally:
        stream.close(); connection.close()


def reconcile(value, result, snapshot, proxied):
    if not result['complete']:
        target = ROOT / 'artifacts/engine-migration' / ('failed-contract-' + str(time.time_ns()) + '.json')
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps({'result':result,'snapshot':snapshot},indent=2),encoding='utf-8')
        bad = [{key:row.get(key) for key in ('complete','errors','sent','received','cancelled','elapsed_seconds')} for row in result['flows'] if not row['complete']]
        raise AssertionError((value['task'], bad, snapshot.get('relay_diagnostics'), str(target)))
    assert stage_route({'complete':True, 'origin':snapshot, 'results':[result]}, proxied), 'Route reconciliation failed'
    if value['task'] == 'udp':
        assert all(row['invalid'] == row['send_errors'] == row['loss'] == 0 for row in result['flows']), result


def negative_worker(directory, worker, secret, checks):
    stopping = threading.Event()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as server, socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as stranger:
        server.bind(('127.0.0.1', 0)); stranger.bind(('127.0.0.1', 0)); server.settimeout(.05)
        fault = ['flow']
        def receive():
            while not stopping.is_set():
                try:
                    packet, peer = server.recvfrom(65535)
                except socket.timeout:
                    continue
                header, payload = packet.split(b'\n', 1)
                response = json.loads(header); response.pop('proof'); response['peer'] = list(peer)
                if fault[0] == 'flow': response['flow_id'] += '-wrong'
                if fault[0] == 'run': response['run_id'] += '-wrong'
                if fault[0] == 'payload': payload = b'x' + payload[1:]
                response['proof'] = mac(bytes.fromhex(secret), b'udp-server:', json_bytes(response) + payload) if fault[0] != 'mac' else '0' * 64
                reply = json_bytes(response) + b'\n' + payload if fault[0] != 'malformed' else b'bad\n'
                (stranger if fault[0] == 'source' else server).sendto(reply, peer)
        thread = threading.Thread(target=receive)
        thread.start()
        try:
            for name, reason in [('flow','TRAFFIC_DATAGRAM_FLOW_MISMATCH'), ('run','TRAFFIC_DATAGRAM_RUN_MISMATCH'),
                                 ('payload','TRAFFIC_DATAGRAM_PAYLOAD_MISMATCH'), ('mac','TRAFFIC_AUTHENTICATION_FAILED'),
                                 ('malformed','TRAFFIC_DATAGRAM_MALFORMED'), ('source','TRAFFIC_UDP_SOURCE_INVALID')]:
                fault[0] = name
                value = job(secret, server.getsockname()[1], 'udp', connections=1, seconds=.15, connected=False)
                result = request(worker, secret, {'operation':'worker', 'job':value}, timeout=6)
                row = result['flows'][0]
                assert result['complete'] is False and row['received'] == 0, (name, result)
                if name == 'source':
                    assert reason in row['errors'] and row['unexpected_source_packets'] > 0, row
                else:
                    assert row['invalid_reasons'].get(reason, 0) > 0 and row['invalid'] > 0, row
                checks.append({'negative':name, 'reason':reason, 'no_false_pass':True})
        finally:
            stopping.set(); thread.join(timeout=2)
            assert not thread.is_alive()


def main():
    if os.name != 'nt':
        raise RuntimeError('This gate targets the local Windows engine')
    evidence = ROOT / 'artifacts' / ('engine-contract-' + str(time.time_ns()))
    evidence.mkdir(parents=True)
    with (evidence / 'build.log').open('wb') as log:
        build = subprocess.run(['dotnet', 'build', str(PROJECT), '-c', 'Release', '--nologo', '-v', 'quiet'],
                               cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=90, creationflags=FLAGS)
    assert build.returncode == 0, str(evidence / 'build.log')
    sources = list(PROJECT.glob('*.cs')) + [PROJECT / 'ProxyBridge.TestLab.TrafficEngine.csproj', Path(__file__).resolve()] + list((ROOT / 'src/trafficlab').glob('*.py'))
    hashes = {str(path.relative_to(ROOT)):hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}
    binary = hashlib.sha256(EXE.with_suffix('.dll').read_bytes()).hexdigest()
    checks = []
    with tempfile.TemporaryDirectory(prefix='testlab-engine-contract-') as private:
        directory = Path(private); secret = secrets.token_hex(32)
        origin_port, proxy_port = free_port(), free_port()
        with host(directory, secret, origin_port, proxy_port) as native, host(directory, secret, origin_port, worker=True) as worker:
            native_pid = request(worker, secret, {'operation':'snapshot','run_id':'worker-control'})['native_pid']
            for task in ('duplex', 'udp'):
                value = job(secret, origin_port, task, proxy_port, 16 if task == 'udp' else 3)
                value.update(runtime_mode='local', native_worker_port=worker, native_worker_pid=native_pid,
                             native_worker_executable=str(EXE))
                result = execute(value)
                reconcile(value, result, request(native, secret, {'operation':'snapshot','run_id':value['run_id']}), True)
                assert result['engine_pid'] == native_pid and worker_state(value)['worker_jobs_active'] == 0
                checks.append({'python_dispatch':task, 'native_pid_verified':True, 'idle_verified':True})
            mismatch = job(secret, origin_port, 'echo')
            mismatch.update(runtime_mode='local', native_worker_port=worker, native_worker_pid=native_pid+1)
            rejected = execute(mismatch)
            untouched = request(native, secret, {'operation':'snapshot','run_id':mismatch['run_id']})
            assert not rejected['complete'] and not rejected['worker_results_available'] and untouched['accepted'] == 0
            checks.append({'wrong_worker_identity_rejected_before_traffic':True})
            # Each implementation is tested against the existing independent Python peer.
            for task in ('echo', 'hold', 'upload', 'download', 'duplex', 'flow_rate', 'udp'):
                for connected in ((False, True) if task == 'udp' else (True,)):
                    value = job(secret, origin_port, task, proxy_port, 32 if task == 'udp' else 3, connected=connected)
                    result = execute(value)
                    reconcile(value, result, request(native, secret, {'operation':'snapshot', 'run_id':value['run_id']}), True)
                    checks.append({'peer':'Python worker / C# origin+relay', 'task':task, 'connected':connected, 'complete':True})
            python_port, python_proxy = free_port(), free_port()
            with host(directory, secret, python_port, python_proxy, python=True) as python_control:
                for proxied in (False, True):
                    for task in ('echo', 'hold', 'upload', 'download', 'duplex', 'flow_rate', 'udp'):
                        value = job(secret, python_port, task, python_proxy if proxied else 0, 16 if task == 'udp' else 3)
                        result = request(worker, secret, {'operation':'worker', 'job':value}, timeout=20)
                        if task == 'flow_rate':
                            assert result['complete'], [(f.get('completed'),f.get('failures'),f.get('failure_samples',[])[:1]) for f in result['flows']]
                            for flow in result['flows']:
                                assert flow['verified_exchanges_per_flow'] == 1 and flow['payload_bytes_per_direction_per_flow'] == 64
                                assert flow['tx_bytes'] == flow['rx_bytes'] == flow['completed'] * 64
                                assert all(sample['exchange_count'] == 1 for sample in flow['route_samples'])

                        reconcile(value, result, python_snapshot(python_control, value), proxied)
                        checks.append({'peer':'C# worker / Python origin+relay', 'task':task, 'proxy':proxied, 'complete':True})
            for connected in (False, True):
                value = job(secret, origin_port, 'udp', proxy_port, 128, seconds=3., connected=connected)
                result = request(worker, secret, {'operation':'worker', 'job':value}, timeout=20)
                reconcile(value, result, request(native, secret, {'operation':'snapshot', 'run_id':value['run_id']}), True)
                totals = {key:sum(row[key] for row in result['flows']) for key in ('sent','received','invalid','loss','send_errors')}
                checks.append({'peer':'C# pipeline', 'flows':128, 'connected':connected, **totals})
            value = job(secret, origin_port, 'udp', proxy_port, 8, seconds=20.)
            cancellation = directory / 'cancel'; value['cancellation_path'] = str(cancellation)
            with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
                pending = pool.submit(request, worker, secret, {'operation':'worker', 'job':value}, 25)
                time.sleep(.3)
                assert request(worker, secret, {'operation':'snapshot','run_id':'worker-control'})['worker_jobs_active'] == 1
                cancellation.write_text('cancel', encoding='ascii'); result = pending.result(timeout=5)
            assert not result['complete'] and all(row['cancelled'] for row in result['flows'])
            snapshot = request(native, secret, {'operation':'snapshot', 'run_id':value['run_id']})
            assert snapshot['native_origin_connections'] == snapshot['proxy_connections'] == 0, snapshot
            assert request(worker, secret, {'operation':'snapshot','run_id':'worker-control'})['worker_jobs_active'] == 0
            checks.append({'cancelled':True, 'owned_cleanup':True})
            body = json_bytes({'operation':'snapshot', 'run_id':'auth'})
            nonce = secrets.token_hex(16)
            envelope = {'body':base64.b64encode(body).decode(), 'nonce':nonce, 'proof':'0'*64}
            def raw(value):
                with socket.create_connection(('127.0.0.1', native), timeout=2) as channel:
                    channel.sendall(json_bytes(value) + b'\n')
                    return channel.recv(65536)
            assert raw(envelope) == b''
            envelope['proof'] = mac(bytes.fromhex(secret), b'engine-control-request:', nonce.encode() + body)
            assert raw(envelope) and raw(envelope) == b''
            checks.append({'invalid_control_mac_rejected':True, 'recent_nonce_replay_rejected':True})
            negative_worker(directory, worker, secret, checks)
    assert hashes == {name:hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in hashes}, 'Sources changed during gate'
    (evidence / 'result.json').write_text(json.dumps({'complete':True, 'scope':'standalone-loopback-component-contract; no product',
        'source_hashes':hashes, 'engine_dll_sha256':binary, 'checks':checks}, indent=2), encoding='utf-8')
    print(f'PASS: {len(checks)} independent wire/route, capacity-profile, cancellation and false-PASS checks; {evidence}')


if __name__ == '__main__':
    main()
