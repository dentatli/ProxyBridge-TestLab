"""QUIC-v1 / HTTP/3 over ordinary UDP sockets, with no synthetic datagram envelope."""
from __future__ import annotations
import base64
import hashlib
import json
import select
import socket
import time
from trafficlab.dependencies import enable, verify
from trafficlab.application_wire import APPLICATION_PORTS, SERVER_NAME, request, verify_response
from trafficlab.protocol import Histogram, json_bytes
from trafficlab.quic_wire import append_body, h3_headers, MULTIPLEX_PROFILE, MULTIPLEX_WIDTH
from trafficlab.diagnostics import require_datagram_source


def quic_flow(job, flow_id):
    enable()
    from aioquic.quic.configuration import QuicConfiguration
    from aioquic.quic.connection import QuicConnection
    from aioquic.quic.events import HandshakeCompleted, ConnectionTerminated, StreamDataReceived, StreamReset, StopSendingReceived
    from aioquic.h3.connection import H3Connection
    from aioquic.h3.events import HeadersReceived, DataReceived
    from cryptography.hazmat.primitives.serialization import Encoding
    from trafficlab.worker import cancelled
    kind, secret = job['application'], bytes.fromhex(job['secret'])
    result = {'flow_id':flow_id, 'application':kind, 'complete':False, 'errors':[], 'tx_bytes':0, 'rx_bytes':0,
        'verified_transactions':0, 'peer_observed_by_origin':[], 'sent':0, 'received':0,
        'quic_datagrams_sent':0, 'quic_datagrams_received':0, 'migration_status':'NOT_TESTED'}
    started = time.perf_counter()
    histogram, connection_latency = Histogram(), Histogram()
    sock, control, conn = None, None, None
    prefix = b''
    closed = handshake = False
    pending = {}
    multiplex = job.get('quic_mode','single') == 'multiplex'
    width = MULTIPLEX_WIDTH if multiplex else 1
    http = None
    try:
        if job.get('quic_mode','single') not in ('single','multiplex'):
            raise ValueError('APPLICATION_QUIC_PROFILE_INVALID')
        if multiplex:
            result.update(quic_profile=MULTIPLEX_PROFILE, quic_peak_streams=0, quic_completed_streams=0)
        target = {**job, 'port':job.get('application_ports', APPLICATION_PORTS)[kind]}
        destination = (job['host'], target['port'])
        if job.get('test_proxy'):
            from trafficlab.socks_client import negotiate, address
            control = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            control.settimeout(5)
            destination = negotiate(control, target, True)
            prefix = b'\0\0\0' + address(job['host'], target['port'])
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.bind(('0.0.0.0', 0))
        sock.setblocking(False)
        configuration = QuicConfiguration(is_client=True, alpn_protocols=['h3' if kind == 'http3' else 'testlab-quic/1'],
            server_name=SERVER_NAME, idle_timeout=5, max_data=262144, max_stream_data=16384, supported_versions=[1])
        configuration.load_verify_locations(cadata=job['application_identity']['tls_ca_pem'].encode())
        conn = QuicConnection(configuration=configuration)
        conn.connect((job['host'], target['port']), now=time.monotonic())
        http = H3Connection(conn) if kind == 'http3' else None

        def pump(timeout=.05):
            nonlocal handshake, closed
            now = time.monotonic()
            timer = conn.get_timer()
            if timer is not None and timer <= now:
                conn.handle_timer(now=now)
            for packet, _address in conn.datagrams_to_send(now=now):
                sock.sendto(prefix + packet, destination)
                result['quic_datagrams_sent'] += 1
            timer = conn.get_timer()
            delay = min(timeout, max(0, timer - time.monotonic())) if timer is not None else timeout
            if select.select([sock], [], [], delay)[0]:
                packet, sender = sock.recvfrom(65535)
                require_datagram_source(result, sender, destination, 'APPLICATION_QUIC_DATAGRAM_SOURCE_INVALID',
                                        phase='workload' if handshake else 'handshake')
                if prefix:
                    from trafficlab.socks_client import unwrap
                    if packet[:len(prefix)] != prefix:
                        raise ValueError('APPLICATION_QUIC_SOCKS_SOURCE_INVALID')
                    packet = unwrap(packet)
                result['quic_datagrams_received'] += 1
                conn.receive_datagram(packet, (job['host'], target['port']), now=time.monotonic())
            while (event := conn.next_event()) is not None:
                if isinstance(event, HandshakeCompleted):
                    cert = conn.tls._peer_certificate  # pinned aioquic 1.3 internal leaf representation
                    observed = hashlib.sha256(cert.public_bytes(Encoding.DER)).hexdigest()
                    if observed != job['application_identity']['tls_certificate_sha256'] or event.alpn_protocol != configuration.alpn_protocols[0]:
                        raise ValueError('APPLICATION_TLS_IDENTITY_OR_ALPN_CHANGED')
                    handshake = True
                    result.update(certificate_sha256=observed, certificate_verified=True, tls_version='TLSv1.3',
                        alpn=event.alpn_protocol, server_name=SERVER_NAME, quic_version='0x00000001', handshake_complete=True,
                        connection_id_sha256=hashlib.sha256(conn.host_cid).hexdigest())
                elif isinstance(event, ConnectionTerminated):
                    closed = True
                    if event.error_code != 0 or not result.get('closing'):
                        raise ValueError('APPLICATION_QUIC_CONNECTION_TERMINATED')
                elif isinstance(event, (StreamReset, StopSendingReceived)):
                    raise ValueError('APPLICATION_QUIC_STREAM_RESET')
                if http:
                    for value in http.handle_event(event):
                        if not isinstance(value, (HeadersReceived, DataReceived)):
                            continue
                        context = pending.get(value.stream_id)
                        if context is None or context['ended']:
                            raise ValueError('APPLICATION_QUIC_STREAM_CHANGED')
                        if isinstance(value, HeadersReceived):
                            if context['headers'] is not None:
                                raise ValueError('APPLICATION_HTTP3_TRAILERS_UNSUPPORTED')
                            context['headers'] = h3_headers(value.headers, response=True)
                        else:
                            if context['headers'] is None:
                                raise ValueError('APPLICATION_HTTP3_HEADERS_REQUIRED')
                            append_body(context['body'], value.data)
                        if value.stream_ended:
                            complete(context)
                elif isinstance(event, StreamDataReceived):
                    context = pending.get(event.stream_id)
                    if context is None or context['ended']:
                        raise ValueError('APPLICATION_QUIC_STREAM_CHANGED')
                    append_body(context['body'], event.data)
                    if event.end_stream:
                        complete(context)

        def complete(context):
            if http and context['headers'] is None:
                raise ValueError('APPLICATION_HTTP3_HEADERS_REQUIRED')
            returned = json.loads(context['body'])
            if base64.b64decode(returned.get('payload',''),validate=True) != context['payload']:
                raise ValueError('APPLICATION_ECHO_PAYLOAD_MISMATCH')
            peer = verify_response(secret, context['identity'], returned)
            if multiplex and (returned.get('quic_profile') != MULTIPLEX_PROFILE or
                type(returned.get('quic_peak_streams')) is not int or returned['quic_peak_streams'] != width or
                type(returned.get('quic_batch_index')) is not int or returned['quic_batch_index'] != context['identity']['sequence']//width):
                raise ValueError('APPLICATION_QUIC_MULTIPLEX_PROOF_INVALID')
            if result['peer_observed_by_origin'] not in ([], [peer]):
                raise ValueError('APPLICATION_ORIGIN_PEER_CHANGED')
            result['peer_observed_by_origin'] = [peer]
            result['verified_transactions'] += 1
            result['received'] += 1
            result['tx_bytes'] += len(context['payload']); result['rx_bytes'] += len(context['payload'])
            histogram.add((time.perf_counter() - context['stamp']) * 1000)
            context['ended'] = True
            if multiplex:
                result['quic_completed_streams'] += 1

        deadline = time.perf_counter() + 5
        while not handshake:
            if cancelled(job) or time.perf_counter() >= deadline:
                raise ValueError('APPLICATION_QUIC_HANDSHAKE_INCOMPLETE')
            pump()
        connection_latency.add((time.perf_counter() - started) * 1000)
        deadline, next_send, sequence = time.perf_counter() + job['seconds'], time.perf_counter(), 0
        while time.perf_counter() < deadline and not cancelled(job):
            pending.clear()
            stamp = time.perf_counter()
            for offset in range(width):
                current = sequence + offset
                payload = bytes((i + current) % 256 for i in range(job.get('message_bytes',512)))
                value = request(secret, kind, job['run_id'], flow_id, current, hashlib.sha256(payload).hexdigest())
                envelope = {'identity':value,'payload':base64.b64encode(payload).decode()}
                if multiplex:
                    envelope['quic_profile'] = MULTIPLEX_PROFILE
                message = json_bytes(envelope)
                if len(message) > 8192:
                    raise ValueError('APPLICATION_QUIC_BODY_TOO_LARGE')
                stream = conn.get_next_available_stream_id()
                pending[stream] = {'body':bytearray(), 'headers':None, 'ended':False,
                                   'identity':value, 'payload':payload, 'stamp':stamp}
                if http:
                    http.send_headers(stream, [(b':method',b'POST'),(b':scheme',b'https'),(b':authority',SERVER_NAME.encode()),
                        (b':path',b'/testlab'),(b'content-type',b'application/json')])
                    http.send_data(stream, message, end_stream=True)
                else:
                    conn.send_stream_data(stream, message, end_stream=True)
                result['sent'] += 1
            if multiplex:
                result['quic_peak_streams'] = max(result['quic_peak_streams'],len(pending))
            exchange_deadline = time.perf_counter() + 2
            while not all(context['ended'] for context in pending.values()):
                if cancelled(job) or time.perf_counter() >= exchange_deadline:
                    raise ValueError('APPLICATION_QUIC_EXCHANGE_INCOMPLETE')
                pump()
            sequence += width
            next_send += width/job.get('rate_packets_per_second',100)
            while time.perf_counter() < min(deadline,next_send) and not cancelled(job):
                pump(min(.05, max(0,min(deadline,next_send)-time.perf_counter())))
        result['closing'] = True
        conn.close()
        close_deadline = time.perf_counter() + 2
        while not closed and time.perf_counter() < close_deadline:
            pump()
        result['close_verified'] = closed
        result['close_scope'] = 'local-QUIC-close-timer; remote-idle-verified-by-signed-stage-metrics'
        verify()
        result['complete'] = closed and result['received'] > 0 and not cancelled(job)
    except Exception as error:
        code = str(error) if isinstance(error,ValueError) and str(error).startswith(('APPLICATION_','TRAFFIC_DEPENDENCY_')) else 'APPLICATION_QUIC_TRANSPORT_FAILED'
        result['errors'].append(type(error).__name__ + ':' + code)
        if isinstance(error,OSError):
            result.update(socket_errno=error.errno,socket_winerror=getattr(error,'winerror',None))
    finally:
        if conn is not None and sock is not None and not result.get('closing'):
            try:
                conn.close()
                for packet, _address in conn.datagrams_to_send(now=time.monotonic()):
                    sock.sendto(prefix + packet, destination)
                    result['quic_datagrams_sent'] += 1
            except (OSError, ValueError):
                pass
        if sock is not None:
            sock.close()
        if control is not None:
            control.close()
    result.update(elapsed_seconds=time.perf_counter()-started,latency=histogram.view(),connection_and_authentication_ms=connection_latency.view(),
        loss_fraction=(result['sent']-result['received'])/result['sent'] if result['sent'] else None)
    return result
