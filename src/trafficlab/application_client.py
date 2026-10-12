"""Normal OS sockets with native protocol framing and authenticated application evidence."""
from __future__ import annotations
import base64
import concurrent.futures
import hashlib
import json
import secrets
import socket
import ssl
import struct
import time
import uuid
from typing import Any
from trafficlab.application_wire import (APPLICATION_PORTS, SERVER_NAME, WS_GUID, dns_request, dns_verify,
                                         request, verify_response)
from trafficlab.protocol import Histogram, MAX_LINE, json_bytes, read_json
from trafficlab.proxy import fingerprint
from trafficlab.socks_client import exact_socket


def headers(stream: Any) -> tuple[str, dict[str, str]]:
    line = stream.readline(MAX_LINE + 1)
    size, result = len(line), {}
    if not line.endswith(b"\r\n"):
        raise ValueError("APPLICATION_HTTP_RESPONSE_INVALID")
    while True:
        item = stream.readline(MAX_LINE + 1)
        size += len(item)
        if size > MAX_LINE or not item.endswith(b"\r\n"):
            raise ValueError("APPLICATION_HTTP_HEADERS_INVALID")
        if item == b"\r\n":
            break
        key, value = item.decode("ascii").rstrip("\r\n").split(":", 1)
        if key.lower() in result:
            raise ValueError("APPLICATION_HTTP_DUPLICATE_HEADER")
        result[key.lower()] = value.strip()
    return line.decode("ascii").rstrip("\r\n"), result


def ws_read(sock: Any) -> tuple[int, bytes]:
    from trafficlab.websocket_wire import WebSocketClient
    return WebSocketClient(sock).receive()


def application_flow(job: dict[str, Any], flow_id: str) -> dict[str, Any]:
    from trafficlab.worker import cancelled
    kind = job["application"]
    if kind in ('smtp', 'smtps', 'imap', 'imaps', 'mqtt', 'mqtts', 'pop3', 'pop3s', 'amqp', 'amqps'):
        from trafficlab.messaging_client import messaging_flow
        return messaging_flow(job, flow_id)
    if kind in ('quic', 'http3'):
        from trafficlab.quic_client import quic_flow
        return quic_flow(job, flow_id)
    if kind in ('ssh', 'sftp'):
        from trafficlab.ssh_client import ssh_flow
        return ssh_flow(job, flow_id)
    udp = kind == "dns-udp"
    secret = bytes.fromhex(job["secret"])
    sock = stream = control = None
    histogram, connection_latency = Histogram(), Histogram()
    http_modes=[Histogram() for _ in range(4)] if kind in ('http','https') else None
    result: dict[str, Any] = {"flow_id": flow_id, "complete": False, "errors": [], "application": kind,
        "tx_bytes": 0, "rx_bytes": 0, "verified_transactions": 0, "peer_observed_by_origin": None}
    if udp:
        result.update(sent=0, received=0, duplicates=0, reordered=0, invalid=0)
    started = time.perf_counter()
    try:
        target = {**job, "port": job.get("application_ports", APPLICATION_PORTS)[kind]}
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM if udp else socket.SOCK_STREAM)
        sock.settimeout(2)
        destination = (job["host"], target["port"])
        if job.get("test_proxy"):
            from trafficlab.socks_client import negotiate
            if udp:
                control = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                control.settimeout(5)
                destination = negotiate(control, target, True)
            else:
                negotiate(sock, target)
        elif not udp:
            sock.connect(destination)
        if kind in ("tls", "https", "http2", "grpc", "websocket-tls", "dns-tls", "dns-https"):
            identity = job["application_identity"]
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
            context.minimum_version = ssl.TLSVersion.TLSv1_2
            context.load_verify_locations(cadata=identity["tls_ca_pem"])
            alpn = 'h2' if kind in ('http2', 'grpc') else "dot" if kind=='dns-tls' else "http/1.1" if kind in ("https", "websocket-tls", "dns-https") else "testlab/1"
            context.set_alpn_protocols([alpn])
            sock = context.wrap_socket(sock, server_hostname=SERVER_NAME)
            observed = hashlib.sha256(sock.getpeercert(binary_form=True)).hexdigest()
            if observed != identity["tls_certificate_sha256"] or sock.selected_alpn_protocol() != alpn:
                raise ValueError("APPLICATION_TLS_IDENTITY_OR_ALPN_CHANGED")
            result.update(tls_version=sock.version(), cipher=sock.cipher()[0], certificate_sha256=observed,
                          certificate_verified=True, server_name=SERVER_NAME, alpn=sock.selected_alpn_protocol())
        if kind in ('http2', 'grpc'):
            from trafficlab.http_two import H2Client
            h2_client = H2Client(sock, kind == 'grpc')
        if kind in ("http", "https", "tls", "dns-https"):
            stream = sock.makefile("rb")
        if kind in ("websocket", "websocket-tls"):
            key = base64.b64encode(secrets.token_bytes(16)).decode()
            sock.sendall(f"GET /testlab HTTP/1.1\r\nHost: {SERVER_NAME}:{target['port']}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n".encode())
            stream = sock.makefile("rb", buffering=0)
            status, values = headers(stream)
            if status != "HTTP/1.1 101 Switching Protocols" or values.get("upgrade", "").lower() != "websocket" or values.get("connection", "").lower() != "upgrade" or values.get("sec-websocket-accept") != base64.b64encode(hashlib.sha1((key + WS_GUID).encode()).digest()).decode():
                raise ValueError("APPLICATION_WEBSOCKET_UPGRADE_REJECTED")
            stream.close()
            stream = None
            from trafficlab.websocket_wire import WebSocketClient
            ws_client = WebSocketClient(sock)
        deadline = time.perf_counter() + job["seconds"]
        next_send, sequence = time.perf_counter(), 0
        while time.perf_counter() < deadline and not cancelled(job):
            stamp = time.perf_counter()
            if kind=='http2':
                from trafficlab.http_two import MULTIPLEX_PROFILE,MULTIPLEX_WIDTH
                batch=[]
                for offset in range(MULTIPLEX_WIDTH):
                    payload=bytes((index+sequence+offset)%256 for index in range(job.get('message_bytes',512)))
                    value=request(secret,kind,job['run_id'],flow_id,sequence+offset,hashlib.sha256(payload).hexdigest())
                    batch.append((value,payload,json_bytes({'identity':value,'payload':base64.b64encode(payload).decode()})))
                replies,rtts=h2_client.exchange_many([item[2] for item in batch])
                for (value,payload,_),response,rtt in zip(batch,replies,rtts):
                    if base64.b64decode(response.get('payload',''),validate=True)!=payload:
                        raise ValueError('APPLICATION_ECHO_PAYLOAD_MISMATCH')
                    peer=verify_response(secret,value,response)
                    if result['peer_observed_by_origin'] not in (None,peer):
                        raise ValueError('APPLICATION_ORIGIN_PEER_CHANGED')
                    result['peer_observed_by_origin']=peer
                    result['tx_bytes']+=len(payload);result['rx_bytes']+=len(payload)
                    histogram.add(rtt);result['verified_transactions']+=1
                if sequence==0:connection_latency.add((time.perf_counter()-started)*1000)
                result.update(http2_profile=MULTIPLEX_PROFILE,http2_peak_streams=MULTIPLEX_WIDTH,
                              http2_completed_streams=result['verified_transactions'])
                sequence+=MULTIPLEX_WIDTH
                next_send+=MULTIPLEX_WIDTH/job.get('rate_packets_per_second',100)
                while time.perf_counter()<min(deadline,next_send) and not cancelled(job):
                    time.sleep(max(0,min(.05,min(deadline,next_send)-time.perf_counter())))
                continue
            if kind.startswith("dns-"):
                packet, value = dns_request(secret, job["run_id"], flow_id, sequence)
                if udp:
                    sent_packet = packet
                    if job.get("test_proxy"):
                        from trafficlab.socks_client import address, unwrap
                        sent_packet = b"\0\0\0" + address(job["host"], target["port"]) + packet
                    sock.sendto(sent_packet, destination)
                    result["sent"] += 1
                    reply, source = sock.recvfrom(2048)
                    if source != destination:
                        raise ValueError("APPLICATION_DNS_SOURCE_INVALID")
                    if job.get("test_proxy"):
                        reply = unwrap(reply)
                elif kind=='dns-https':
                    from trafficlab.dns_http import post
                    reply=post(sock,stream,packet,SERVER_NAME,target['port'],headers)
                else:
                    sock.sendall(struct.pack("!H", len(packet)) + packet)
                    length = struct.unpack("!H", exact_socket(sock, 2))[0]
                    if length > 512:
                        raise ValueError("APPLICATION_DNS_RESPONSE_TOO_LARGE")
                    reply = exact_socket(sock, length)
                response = dns_verify(packet, reply)
            else:
                payload = bytes((index + sequence) % 256 for index in range(job.get("message_bytes", 512)))
                value = request(secret, kind, job["run_id"], flow_id, sequence, hashlib.sha256(payload).hexdigest())
                message = json_bytes({"identity": value, "payload": base64.b64encode(payload).decode()})
                if kind in ("http", "https"):
                    from trafficlab.http_body import PROFILE,MODES,encode,read
                    chunked,compressed=MODES[sequence%len(MODES)]
                    fields,body=encode(message,chunked,compressed)
                    sock.sendall(f"POST /testlab HTTP/1.1\r\nHost: {SERVER_NAME}:{target['port']}\r\nContent-Type: application/json\r\nAccept-Encoding: gzip\r\nConnection: keep-alive\r\n".encode()+fields+b'\r\n'+body)
                    status, values = headers(stream)
                    if status != "HTTP/1.1 200 OK" or values.get('content-type')!='application/json':
                        raise ValueError('APPLICATION_HTTP_RESPONSE_INVALID')
                    raw,returned_chunked,returned_compressed=read(stream,values)
                    if (returned_chunked,returned_compressed)!=(chunked,compressed):
                        raise ValueError('APPLICATION_HTTP_RESPONSE_PROFILE_INVALID')
                    response = json.loads(raw)
                    result['http_profile']=PROFILE
                    for key,flag in (('http_chunked_requests',chunked),('http_gzip_requests',compressed),
                                      ('http_chunked_responses',returned_chunked),('http_gzip_responses',returned_compressed)):
                        result[key]=result.get(key,0)+int(flag)
                elif kind in ('http2', 'grpc'):
                    response = h2_client.exchange(message)
                elif kind in ("websocket", "websocket-tls"):
                    raw = ws_client.exchange(message, sequence % 2 == 1)
                    response = json.loads(raw)
                    result.update(ws_client.stats)
                else:
                    sock.sendall(message + b"\n")
                    response = read_json(stream)
                if base64.b64decode(response.get("payload", ""), validate=True) != payload:
                    raise ValueError("APPLICATION_ECHO_PAYLOAD_MISMATCH")
                result["tx_bytes"] += len(payload)
                result["rx_bytes"] += len(payload)
            peer = verify_response(secret, value, response)
            if result["peer_observed_by_origin"] is not None and result["peer_observed_by_origin"] != peer:
                raise ValueError("APPLICATION_ORIGIN_PEER_CHANGED")
            result["peer_observed_by_origin"] = peer
            if udp:
                result["received"] += 1
            histogram.add((time.perf_counter() - stamp) * 1000)
            if http_modes is not None:
                http_modes[sequence%4].add((time.perf_counter()-stamp)*1000)
            result["verified_transactions"] += 1
            if sequence == 0:
                connection_latency.add((time.perf_counter() - started) * 1000)
            sequence += 1
            next_send += 1 / job.get("rate_packets_per_second", 100)
            while time.perf_counter() < min(deadline, next_send) and not cancelled(job):
                time.sleep(max(0, min(0.05, min(deadline, next_send) - time.perf_counter())))
        if kind in ("websocket", "websocket-tls"):
            ws_client.close()
            if kind == "websocket-tls":
                sock = sock.unwrap()
            result["close_verified"] = True
        if kind in ('http2', 'grpc'):
            h2_client.close()
            sock = sock.unwrap()
            result['close_verified'] = True
            if kind == 'grpc':
                result['grpc_status_verified'] = True
            from trafficlab.dependencies import verify
            verify()
        if kind in ('dns-tls','dns-https'):
            packet,value=dns_request(secret,job['run_id'],flow_id,sequence,close=kind=='dns-tls')
            if kind=='dns-https':
                reply=post(sock,stream,packet,SERVER_NAME,target['port'],headers,close=True)
                stream.close();stream=None
            else:
                sock.sendall(struct.pack('!H',len(packet))+packet)
                length=struct.unpack('!H',exact_socket(sock,2))[0]
                if not 17<=length<=512:
                    raise ValueError('APPLICATION_DNS_RESPONSE_TOO_LARGE')
                reply=exact_socket(sock,length)
            if verify_response(secret,value,dns_verify(packet,reply))!=result['peer_observed_by_origin']:
                raise ValueError('APPLICATION_DNS_CLOSE_RESPONSE_INVALID')
            if sock.recv(1)!=b'':
                raise ValueError('APPLICATION_DNS_TLS_CLOSE_UNVERIFIED')
            sock=sock.unwrap()
            result.update(dns_encrypted_protocol=kind,close_verified=True)
        if kind in ("tls", "https"):
            terminal = b"close"
            value = request(secret, kind, job["run_id"], flow_id, sequence, hashlib.sha256(terminal).hexdigest())
            message = json_bytes({"identity": value, "payload": base64.b64encode(terminal).decode(), "close": True})
            if kind == "https":
                sock.sendall(f"POST /testlab HTTP/1.1\r\nHost: {SERVER_NAME}:{target['port']}\r\nContent-Type: application/json\r\nContent-Length: {len(message)}\r\nConnection: close\r\n\r\n".encode() + message)
                status, values = headers(stream)
                length = int(values.get("content-length", "-1"))
                if status != "HTTP/1.1 200 OK" or not 0 < length <= MAX_LINE:
                    raise ValueError("APPLICATION_TLS_CLOSE_RESPONSE_INVALID")
                returned = json.loads(stream.read(length))
            else:
                sock.sendall(message + b"\n")
                returned = read_json(stream)
            if verify_response(secret, value, returned) != result["peer_observed_by_origin"] or base64.b64decode(returned.get("payload", ""), validate=True) != terminal:
                raise ValueError("APPLICATION_TLS_CLOSE_RESPONSE_INVALID")
            stream.close()
            stream = None
            sock = sock.unwrap()
            result["close_verified"] = True
        if kind in ('websocket','websocket-tls') and result.get('ws_fragmented_requests',0)<1 and not cancelled(job):
            raise ValueError('APPLICATION_WEBSOCKET_PROFILE_NOT_EXERCISED')
        if kind in ('http','https') and result['verified_transactions']<4 and not cancelled(job):
            raise ValueError('APPLICATION_HTTP_PROFILE_NOT_EXERCISED')
        result["complete"] = result["verified_transactions"] > 0 and not cancelled(job)
    except Exception as error:
        code = str(error) if isinstance(error, ValueError) and str(error).startswith("APPLICATION_") else "APPLICATION_TRANSPORT_FAILED"
        result["errors"].append(type(error).__name__ + ":" + code)
        if isinstance(error, OSError):
            result["socket_errno"] = error.errno
            result["socket_winerror"] = getattr(error, "winerror", None)
    finally:
        if stream is not None:
            stream.close()
        if sock is not None:
            sock.close()
        if control is not None:
            control.close()
    result["elapsed_seconds"] = time.perf_counter() - started
    result["latency"] = histogram.view()
    if http_modes is not None:
        result['http_modes']=[{'mode':name,'latency':observed.view()} for name,observed in zip(
            ('content-length','chunked','gzip','chunked-gzip'),http_modes)]
    result["connection_and_authentication_ms"] = connection_latency.view()
    if udp:
        result["loss_fraction"] = (result["sent"] - result["received"]) / result["sent"] if result["sent"] else None
        result["peer_observed_by_origin"] = [result["peer_observed_by_origin"]] if result["peer_observed_by_origin"] else []
    return result


def execute_application(job: dict[str, Any]) -> dict[str, Any]:
    from trafficlab.schedule import origin_metrics
    origin = origin_metrics(job)
    job = {**job, "application_identity": origin.get("identity", {}).get("application", {})}
    started = time.perf_counter()
    with concurrent.futures.ThreadPoolExecutor(max_workers=job["connections"]) as pool:
        futures = [pool.submit(application_flow, job, str(uuid.uuid4())) for _ in range(job["connections"])]
        flows = [future.result() for future in futures]
    tcp = udp = count = 0
    for flow in flows:
        if job["task"] == "udp" and flow.get("received"):
            udp ^= fingerprint(flow["flow_id"], flow["peer_observed_by_origin"][0])
        elif job["task"] != "udp" and flow["complete"]:
            tcp ^= fingerprint(flow["flow_id"], flow["peer_observed_by_origin"])
            count += 1
    return {"schema_version": 1, "measurement_method": "controlled-traffic-v1", "run_id": job["run_id"],
        "task": job["task"], "application": job["application"], "flows": flows, "complete": all(flow["complete"] for flow in flows),
        "elapsed_seconds": time.perf_counter() - started, "tx_bytes": sum(flow["tx_bytes"] for flow in flows),
        "rx_bytes": sum(flow["rx_bytes"] for flow in flows), "successful_tcp_flows": count,
        "tcp_origin_fingerprint": f"{tcp:064x}", "udp_origin_fingerprint": f"{udp:064x}", "product_route_confirmed": False}
