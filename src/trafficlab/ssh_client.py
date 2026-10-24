"""SSH/SFTP over ordinary sockets, fixed signed host key and per-run authentication."""
from __future__ import annotations
import asyncio
import base64
import hashlib
import json
import socket
import time
from typing import Any
from trafficlab.dependencies import enable, verify
from trafficlab.protocol import Histogram, MAX_LINE, json_bytes, mac
from trafficlab.application_wire import APPLICATION_PORTS, request, verify_response
from trafficlab.worker import cancelled
from trafficlab.ssh_wire import read_line


def ssh_flow(job: dict[str, Any], flow_id: str) -> dict[str, Any]:
    enable()
    import asyncssh
    kind = job['application']
    result = {'flow_id': flow_id, 'application': kind, 'complete': False, 'errors': [],
        'tx_bytes': 0, 'rx_bytes': 0, 'verified_transactions': 0, 'peer_observed_by_origin': None}
    histogram, connection_latency = Histogram(), Histogram()
    started = time.perf_counter()
    secret = bytes.fromhex(job['secret'])
    async def execute():
        target = {**job, 'port': job.get('application_ports', APPLICATION_PORTS)[kind]}
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(2)
        conn = None
        try:
            if job.get('test_proxy'):
                from trafficlab.socks_client import negotiate
                negotiate(sock, target)
            else:
                sock.connect((job['host'], target['port']))
            identity = job['application_identity']
            public_key = identity['ssh_host_public_key']
            trusted = f"[{job['host']}]:{target['port']} {public_key}\n".encode('ascii')
            conn = await asyncssh.connect(job['host'], target['port'], sock=sock, known_hosts=trusted,
                username=job['run_id'], password=mac(secret, b'ssh-auth:', job['run_id'].encode('ascii')),
                client_keys=[], agent_path=None, config=None, preferred_auth=['password'],
                server_host_key_algs=['ssh-ed25519'], kex_algs=['curve25519-sha256'],
                encryption_algs=['aes128-gcm@openssh.com', 'chacha20-poly1305@openssh.com'],
                connect_timeout=5, login_timeout=5)
            host_key = conn.get_server_host_key()
            if host_key.get_fingerprint('sha256') != identity['ssh_host_key_sha256']:
                raise ValueError('APPLICATION_SSH_HOST_KEY_CHANGED')
            result.update(ssh_host_key_sha256=host_key.get_fingerprint('sha256'), ssh_host_key_verified=True,
                          ssh_cipher=conn.get_extra_info('send_cipher'), ssh_version=conn.get_extra_info('server_version'))
            connection_latency.add((time.perf_counter() - started) * 1000)
            if kind == 'ssh':
                process = await asyncio.wait_for(conn.create_process('testlab-echo', encoding=None), 2)
            else:
                sftp = await asyncio.wait_for(conn.start_sftp_client(sftp_version=3), 2)
                result['sftp_version'] = sftp.version
            deadline, next_send, sequence = time.perf_counter() + job['seconds'], time.perf_counter(), 0
            while time.perf_counter() < deadline and not cancelled(job):
                payload = bytes((index + sequence) % 256 for index in range(job.get('message_bytes', 512)))
                value = request(secret, kind, job['run_id'], flow_id, sequence, hashlib.sha256(payload).hexdigest())
                message = json_bytes({'identity': value, 'payload': base64.b64encode(payload).decode()})
                stamp = time.perf_counter()
                async def exchange():
                    if kind == 'ssh':
                        process.stdin.write(message + b'\n')
                        await process.stdin.drain()
                        return await read_line(process.stdout)
                    async with sftp.open('/request', 'wb', encoding=None) as file:
                        await file.write(message)
                    async with sftp.open('/response', 'rb', encoding=None) as file:
                        if (await file.stat()).size > MAX_LINE:
                            raise ValueError('APPLICATION_SSH_RESPONSE_TOO_LARGE')
                        return await file.read(MAX_LINE)
                raw = await asyncio.wait_for(exchange(), 2)
                if len(raw) > MAX_LINE:
                    raise ValueError('APPLICATION_SSH_RESPONSE_TOO_LARGE')
                returned = json.loads(raw)
                if base64.b64decode(returned.get('payload', ''), validate=True) != payload:
                    raise ValueError('APPLICATION_ECHO_PAYLOAD_MISMATCH')
                peer = verify_response(secret, value, returned)
                if result['peer_observed_by_origin'] not in (None, peer):
                    raise ValueError('APPLICATION_ORIGIN_PEER_CHANGED')
                result['peer_observed_by_origin'] = peer
                result['tx_bytes'] += len(payload); result['rx_bytes'] += len(payload)
                result['verified_transactions'] += 1
                histogram.add((time.perf_counter() - stamp) * 1000)
                sequence += 1
                next_send += 1 / job.get('rate_packets_per_second', 100)
                while time.perf_counter() < min(deadline, next_send) and not cancelled(job):
                    await asyncio.sleep(min(.05, max(0, min(deadline, next_send) - time.perf_counter())))
            if kind == 'ssh':
                process.stdin.write_eof()
                await asyncio.wait_for(process.wait_closed(), 2)
                if process.exit_status != 0:
                    raise ValueError('APPLICATION_SSH_EXIT_UNVERIFIED')
            else:
                sftp.exit()
                await asyncio.wait_for(sftp.wait_closed(), 2)
            result['close_verified'] = True
            verify()
            result['complete'] = result['verified_transactions'] > 0 and not cancelled(job)
        finally:
            if conn is not None:
                conn.close()
                try:
                    await asyncio.wait_for(conn.wait_closed(), 2)
                except asyncio.TimeoutError:
                    conn.abort()
                    result['complete'] = result['close_verified'] = False
                    result['errors'].append('TimeoutError:APPLICATION_SSH_CLOSE_TIMEOUT')
            sock.close()
    try:
        asyncio.run(execute())
    except Exception as error:
        code = str(error) if isinstance(error, ValueError) and str(error).startswith(('APPLICATION_', 'TRAFFIC_DEPENDENCY_')) else 'APPLICATION_SSH_TRANSPORT_FAILED'
        result['errors'].append(type(error).__name__ + ':' + code)
        if isinstance(error, OSError):
            result.update(socket_errno=error.errno, socket_winerror=getattr(error, 'winerror', None))
    result.update(elapsed_seconds=time.perf_counter() - started, latency=histogram.view(),
                  connection_and_authentication_ms=connection_latency.view())
    return result
