"""Authenticated, deadline-bounded loopback IPC with the owned compiled transport engine.

Application adapters and orchestration must not treat this channel as product-route evidence.
"""
from __future__ import annotations
import base64
import json
import secrets
import socket
import time
from typing import Any
from trafficlab.protocol import json_bytes, mac, verify_mac

MAX_REPLY = 24 * 1024 * 1024


def request(port: int, secret: str, value: dict[str, Any], timeout: float = 10) -> dict[str, Any]:
    if type(port) is not int or not 1024 <= port <= 65535 or not 0 < timeout <= 259230:
        raise ValueError('TRAFFIC_ENGINE_CHANNEL_INVALID')
    key = bytes.fromhex(secret)
    if len(key) != 32:
        raise ValueError('TRAFFIC_ENGINE_CHANNEL_INVALID')
    nonce = secrets.token_hex(16)
    body = json_bytes(value)
    if len(body) > 1024 * 1024:
        raise ValueError('TRAFFIC_ENGINE_REQUEST_LIMIT')
    envelope = {'nonce':nonce, 'body':base64.b64encode(body).decode('ascii'),
                'proof':mac(key, b'engine-control-request:', nonce.encode('ascii') + body)}
    deadline = time.monotonic() + timeout
    with socket.create_connection(('127.0.0.1', port), timeout=timeout) as channel:
        channel.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        channel.sendall(json_bytes(envelope) + b'\n')
        chunks = []
        size = 0
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError('TRAFFIC_ENGINE_DEADLINE_EXCEEDED')
            channel.settimeout(remaining)
            piece = channel.recv(min(65536, MAX_REPLY + 1 - size))
            if not piece:
                raise EOFError('TRAFFIC_ENGINE_RESPONSE_UNAVAILABLE')
            size += len(piece)
            if size > MAX_REPLY:
                raise ValueError('TRAFFIC_ENGINE_RESPONSE_LIMIT')
            chunks.append(piece)
            if b'\n' in piece:
                break
    raw = b''.join(chunks)
    if not raw.endswith(b'\n') or b'\n' in raw[:-1]:
        raise ValueError('TRAFFIC_ENGINE_RESPONSE_INVALID')
    response = json.loads(raw)
    if not isinstance(response, dict) or response.get('nonce') != nonce or not isinstance(response.get('body'), str):
        raise ValueError('TRAFFIC_ENGINE_RESPONSE_INVALID')
    payload = base64.b64decode(response['body'], validate=True)
    if len(payload) > 16 * 1024 * 1024:
        raise ValueError('TRAFFIC_ENGINE_RESPONSE_LIMIT')
    verify_mac(key, b'engine-control-response:', nonce.encode('ascii') + payload, response.get('proof'))
    result = json.loads(payload)
    if not isinstance(result, dict):
        raise ValueError('TRAFFIC_ENGINE_RESPONSE_INVALID')
    return result


def worker_state(job):
    if not job.get('native_worker_port'):
        return None
    result = request(job['native_worker_port'], job['secret'], {'operation':'snapshot', 'run_id':'worker-control'})
    if result.get('engine') != 'csharp-transport-v1' or type(result.get('native_pid')) is not int or result['native_pid'] != job.get('native_worker_pid') or \
            type(result.get('worker_jobs_active')) is not int or result['worker_jobs_active'] < 0:
        raise ValueError('TRAFFIC_ENGINE_IDENTITY_CHANGED')
    return result


def execute_worker(job):
    started = time.monotonic()
    allowed = ('host','port','secret','run_id','task','seconds','connections','message_bytes','warmup_count',
               'endurance','connect_timeout_seconds','rate_bytes_per_second','rate_packets_per_second','rate_flows_per_second','rate_exchanges_per_second','udp_connected','test_proxy','cancellation_path')
    try:
        if job.get('runtime_mode') != 'local' or type(job.get('native_worker_pid')) is not int:
            raise ValueError('TRAFFIC_NATIVE_ENGINE_LOCAL_ONLY')
        worker_state(job)  # Reject an unobserved replacement before submitting any traffic.
        payload={key:job[key] for key in allowed if key in job}
        if job.get('endurance') or job.get('_endurance_async'):
            accepted=request(job['native_worker_port'],job['secret'],{'operation':'worker-start','job':payload})
            if accepted.get('accepted') is not True:raise ValueError('TRAFFIC_ASYNC_JOB_REJECTED')
            deadline=time.monotonic()+float(job['seconds'])+25
            while True:
                if job.get('cancellation_path'):
                    from pathlib import Path
                    if Path(job['cancellation_path']).exists():deadline=min(deadline,time.monotonic()+10)
                value=request(job['native_worker_port'],job['secret'],{'operation':'worker-result','run_id':job['run_id']},timeout=5)
                if value.get('state')=='FINISHED':result=value['result'];break
                if time.monotonic()>=deadline:raise ValueError('TRAFFIC_ASYNC_JOB_DEADLINE')
                time.sleep(.2)
        else:
            result = request(job['native_worker_port'], job['secret'], {'operation':'worker', 'job':payload},timeout=float(job['seconds'])+25)
        flows = result.get('flows')
        if result.get('engine') != 'csharp-transport-v1' or result.get('engine_pid') != job['native_worker_pid'] or \
                result.get('run_id') != job['run_id'] or result.get('task') != job['task'] or type(result.get('complete')) is not bool or \
                not isinstance(flows, list) or len(flows) != job.get('connections', 1) or \
                any(not isinstance(flow, dict) or type(flow.get('complete')) is not bool for flow in flows) or \
                result['complete'] != all(flow['complete'] for flow in flows):
            raise ValueError('TRAFFIC_NATIVE_WORKER_RESULT_INVALID')
        return result
    except (OSError, ValueError, KeyError, EOFError):
        # Unavailable results cannot be turned into measured zeroes or inferred flow success.
        from trafficlab.worker import cancelled
        return {'schema_version':1, 'measurement_method':'controlled-traffic-v1', 'engine':'csharp-transport-v1',
                'run_id':job['run_id'], 'task':job['task'], 'complete':False, 'cancelled':cancelled(job), 'flows':[],
                'errors':['TRAFFIC_NATIVE_WORKER_RESULT_UNAVAILABLE'], 'worker_results_available':False,
                'successful_tcp_flows':0, 'tcp_origin_fingerprint':'0'*64, 'udp_origin_fingerprint':'0'*64,
                'tx_bytes':0, 'rx_bytes':0, 'elapsed_seconds':time.monotonic()-started, 'product_route_confirmed':False,
                'byte_scope':'confirmed-results-only; unavailable native reply'}


class OriginAdapter:
    """Protocol callbacks enter the same compiled relay that forwards their bytes."""
    def __init__(self, port: int, secret: str, executable: str, expected_pid: int | None = None):
        self.native_port, self.secret, self.executable = port, secret, executable
        self.pid = expected_pid

    def snapshot(self, run_id):
        result = request(self.native_port, self.secret, {'operation':'snapshot', 'run_id':run_id})
        pid = result.get('native_pid')
        if result.get('engine') != 'csharp-transport-v1' or type(pid) is not int or pid <= 0 or self.pid not in (None, pid):
            raise ValueError('TRAFFIC_ENGINE_IDENTITY_CHANGED')
        self.pid = pid
        return result

    def observe_application(self, run_id, flow_id, peer):
        self._observe({'operation':'application', 'run_id':run_id, 'flow_id':flow_id, 'peer':peer})

    def observe_quic(self, run_id, flow_id, peer, port, original_cid):
        self._observe({'operation':'quic', 'run_id':run_id, 'flow_id':flow_id, 'peer':peer,
                       'port':port, 'original_cid':original_cid.hex()})

    def observe_quic_cid(self, peer, port, original_cid, cid, retired):
        self._observe({'operation':'quic_cid', 'run_id':'cid-callback', 'peer':peer, 'port':port,
                       'original_cid':original_cid.hex(), 'cid':cid.hex(), 'retired':retired})

    def _observe(self, value):
        if request(self.native_port, self.secret, value).get('complete') is not True:
            raise ValueError('TRAFFIC_ENGINE_OBSERVATION_FAILED')

    def merge(self, result, run_id):
        from trafficlab.resources import process_sample
        if run_id.endswith((".persistent.tcp", ".persistent.udp")):
            self._observe({"operation":"session-retain", "run_id":run_id})
        native = self.snapshot(run_id)
        result['policy_receivers'] = native.get('policy_receivers', {})
        for key in ('accepted','completed','active','errors','rx_bytes','tx_bytes','udp_received','udp_reply_errors','udp_unique_flows'):
            if type(native.get(key)) is not int or native[key] < 0:
                raise ValueError('TRAFFIC_ENGINE_COUNTER_INVALID')
            result[key] = result.get(key, 0) + native[key]
        result['tcp_active_peak'] = max(result['tcp_active_peak'], native['tcp_active_peak'])
        result['route_samples'] = (result.get('route_samples', []) + native['route_samples'])[:256]
        for key in ('proxy','proxy_connections','proxy_udp_associations','proxy_tcp_connections','origin_udp_receive_buffer','relay_diagnostics'):
            result[key] = native[key]
        if type(native.get('native_origin_connections')) is not int or native['native_origin_connections'] < 0:
            raise ValueError('TRAFFIC_ENGINE_COUNTER_INVALID')
        # The compiled host decrements its count only after disposing all owned sockets.
        if type(result.get('runtime_connections')) is int:
            result['runtime_connections'] += native['native_origin_connections']
        result['runtime_connections_method'] = 'owned-protocol-sockets-and-QUIC-plus-compiled-socket-lifetimes'
        result['engine'] = 'csharp-transport-v1'
        result['native_origin_connections'] = native['native_origin_connections']
        native_resource = process_sample(native['native_pid'], self.executable)
        adapters = result['resources']
        result['resource_process_samples'] = {'protocol_adapters':adapters, 'native_origin_and_proxy':native_resource}
        if not native_resource.get('available') or not adapters.get('available'):
            result['resources'] = {'available':False, 'error':'TRAFFIC_ENGINE_PROCESS_RESOURCE_UNAVAILABLE'}
        else:
            result['resources'] = {'available':True,
                'identity_start':f"{adapters['pid']}:{adapters['identity_start']}|{native_resource['pid']}:{native_resource['identity_start']}",
                'memory_scope':'sum-of-owned-process-private-commit-and-working-sets; working-sets-not-unique-PC-memory',
                **{key:adapters[key]+native_resource[key] for key in ('cpu_seconds','working_set_bytes','private_bytes','handles','threads')}}

    async def close(self):
        # The controller owns both native process lifetimes, not this protocol adapter.
        pass
