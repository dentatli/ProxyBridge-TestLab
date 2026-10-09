"""Timed, bounded transport workload. It never creates product or routing evidence."""
from __future__ import annotations

import argparse
import collections
import concurrent.futures
import hashlib
import ipaddress
import json
import math
import select
import socket
import threading
import time
import uuid
from pathlib import Path
from typing import Any

from trafficlab.protocol import BLOCK, FRAME, Histogram, ID, MAX_SECONDS, json_bytes, mac, pattern, read_frame, read_json, verify_mac


def connect(job: dict[str, Any], task: str, flow_id: str) -> tuple[socket.socket, Any, bytes, dict[str, Any]]:
    stream = None
    address = ipaddress.ip_address(job["host"])
    sock = socket.socket(socket.AF_INET6 if address.version == 6 else socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(10)
    sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    try:
        if job.get("test_proxy"):
            from trafficlab.socks_client import negotiate
            negotiate(sock, job)
        else:
            sock.connect((str(address), job["port"]))
        request = {"version": 1, "task": task, "run_id": job["run_id"], "flow_id": flow_id, "seconds": job["seconds"],
                   "rate_bytes_per_second": job.get("rate_bytes_per_second", 0)}
        raw = json_bytes(request)
        sock.sendall(raw + b"\n")
        stream = sock.makefile("rb")
        secret = bytes.fromhex(job["secret"])
        challenge = read_json(stream).get("challenge", "")
        if not isinstance(challenge, str) or len(challenge) != 64:
            raise ValueError("TRAFFIC_CHALLENGE_INVALID")
        context = challenge.encode() + raw
        sock.sendall(json_bytes({"proof": mac(secret, b"client:", context)}) + b"\n")
        ready = read_json(stream)
        proof = ready.pop("proof", "")
        verify_mac(secret, b"server:", context + json_bytes(ready), proof)
        if ready.get("ready") is not True or ready.get("flow_id") != flow_id:
            raise ValueError("TRAFFIC_ORIGIN_IDENTITY_MISMATCH")
    except BaseException:
        if stream is not None:
            stream.close()
        sock.close()
        raise
    return sock, stream, context, ready


def read_result(job: dict[str, Any], stream: Any, context: bytes) -> dict[str, Any]:
    value = read_json(stream, 131072)
    proof = value.pop("proof", "")
    verify_mac(bytes.fromhex(job["secret"]), b"result:", context + json_bytes(value), proof)
    value["authentication"] = {"method": "HMAC-SHA256", "proof": proof, "context_hex": context.hex()}
    return value


def cancelled(job: dict[str, Any]) -> bool:
    path = job.get("cancellation_path")
    return bool(path and Path(path).is_file())


def pace(started: float, units: int, rate: float, job: dict[str, Any]) -> None:
    if rate:
        target = min(started + units / rate, started + job["seconds"])
        while not cancelled(job):
            delay = target - time.perf_counter()
            if delay <= 0:
                break
            time.sleep(min(delay, 0.1))


def tcp_flow(job: dict[str, Any], task: str, flow_id: str) -> dict[str, Any]:
    sock: socket.socket | None = None
    stream = None
    result: dict[str, Any] = {"flow_id": flow_id, "task": task, "complete": False,
                              "tx_bytes": 0, "rx_bytes": 0, "errors": [], "latency": None}
    histogram = Histogram()
    try:
        connection_started = time.perf_counter()
        sock, stream, context, ready = connect(job, task, flow_id)
        result["connect_ms"] = (time.perf_counter() - connection_started) * 1000
        result["local"] = list(sock.getsockname()[:2])
        result["peer_observed_by_origin"] = ready["peer"]
        started = time.perf_counter()
        deadline = started + job["seconds"]
        tx_hash = hashlib.sha256()
        rx_hash = hashlib.sha256()

        def send() -> None:
            offset = 0
            while time.perf_counter() < deadline and not cancelled(job):
                sock.sendall(FRAME.pack(offset, len(BLOCK)) + BLOCK)
                tx_hash.update(BLOCK)
                offset += len(BLOCK)
                result["tx_bytes"] = offset
                pace(started, offset, job.get("rate_bytes_per_second", 0), job)
            sock.sendall(FRAME.pack(offset, 0))

        def receive() -> None:
            offset = 0
            while True:
                if cancelled(job):
                    raise ValueError("TRAFFIC_CANCELLED")
                position, data = read_frame(stream)
                if position != offset or (data and data != pattern(offset, len(data))):
                    raise ValueError("TRAFFIC_DATA_OR_SEQUENCE_MISMATCH")
                if not data:
                    break
                rx_hash.update(data)
                offset += len(data)
                result["rx_bytes"] = offset

        if task in ("echo", "hold"):
            offset = 0
            iterations = 0
            while time.perf_counter() < deadline and not cancelled(job):
                data = pattern(offset, job.get("message_bytes", 512))
                sample = time.perf_counter_ns()
                sock.sendall(FRAME.pack(offset, len(data)) + data)
                position, echoed = read_frame(stream)
                elapsed_ms = (time.perf_counter_ns() - sample) / 1_000_000
                if position != offset or echoed != data:
                    raise ValueError("TRAFFIC_DATA_OR_SEQUENCE_MISMATCH")
                tx_hash.update(data)
                rx_hash.update(data)
                offset += len(data)
                result["tx_bytes"] = result["rx_bytes"] = offset
                if iterations >= job.get("warmup_count", 100):
                    histogram.add(elapsed_ms)
                iterations += 1
                if task == "hold":
                    time.sleep(0.2)
            sock.sendall(FRAME.pack(offset, 0))
            position, final = read_frame(stream)
            if final or position != offset:
                raise ValueError("TRAFFIC_TERMINATION_INVALID")
        elif task == "duplex":
            # One reader and one writer per connection; both exceptions are observed.
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                sender = pool.submit(send)
                receiver = pool.submit(receive)
                sender.result()
                receiver.result()
        elif task == "upload":
            send()
        elif task == "download":
            receive()
        else:
            raise ValueError("TRAFFIC_TASK_INVALID")
        observed = read_result(job, stream, context)
        result["origin_result"] = observed
        if observed.get("complete") is not True or observed.get("flow_id") != flow_id:
            raise ValueError("TRAFFIC_ORIGIN_INCOMPLETE")
        if observed["rx_bytes"] != result["tx_bytes"] or observed["tx_bytes"] != result["rx_bytes"]:
            raise ValueError("TRAFFIC_ORIGIN_BYTE_COUNTER_MISMATCH")
        if result["tx_bytes"] and observed["rx_sha256"] != tx_hash.hexdigest():
            raise ValueError("TRAFFIC_ORIGIN_HASH_MISMATCH")
        if result["rx_bytes"] and observed["tx_sha256"] != rx_hash.hexdigest():
            raise ValueError("TRAFFIC_ORIGIN_HASH_MISMATCH")
        if task == "echo" and not histogram.count:
            raise ValueError("TRAFFIC_NO_LATENCY_SAMPLES_AFTER_WARMUP")
        result["elapsed_seconds"] = time.perf_counter() - started
        result["tx_bytes_per_second"] = result["tx_bytes"] / result["elapsed_seconds"]
        result["rx_bytes_per_second"] = result["rx_bytes"] / result["elapsed_seconds"]
        result["complete"] = not cancelled(job)
        result["cancelled"] = cancelled(job)
    except (OSError, EOFError, ValueError, KeyError) as exception:
        result["errors"].append(type(exception).__name__ + ":" + (str(exception) if isinstance(exception, ValueError) else "TRANSPORT_FAILED"))
    finally:
        result["cancelled"] = cancelled(job)
        result["latency"] = histogram.view()
        if stream is not None:
            stream.close()
        if sock is not None:
            sock.close()
    return result


def udp_flow(job: dict[str, Any], flow_id: str) -> dict[str, Any]:
    address = ipaddress.ip_address(job["host"])
    secret = bytes.fromhex(job["secret"])
    connected = job.get("udp_connected", True)
    histogram = Histogram()
    result: dict[str, Any] = {"flow_id": flow_id, "sent": 0, "received": 0, "duplicates": 0,
                              "reordered": 0, "invalid": 0, "expired": 0, "send_errors": 0, "errors": []}
    destination = (str(address), job["port"])
    control = None
    socks_prefix = b""
    if job.get("test_proxy"):
        from trafficlab.socks_client import negotiate, address as socks_address
        control = socket.socket(socket.AF_INET6 if ":" in job["test_proxy"]["host"] else socket.AF_INET, socket.SOCK_STREAM)
        control.settimeout(10)
        try:
            destination = negotiate(control, job, True)
            socks_prefix = b"\x00\x00\x00" + socks_address(job["host"], job["port"])
        except (OSError, ValueError, EOFError):
            control.close()
            return {**result, "complete": False, "cancelled": cancelled(job), "errors": ["SOCKS_UDP_ASSOCIATION_FAILED"]}
    pending: collections.OrderedDict[int, int] = collections.OrderedDict()
    seen: collections.OrderedDict[int, None] = collections.OrderedDict()
    last_sequence = -1
    with socket.socket(socket.AF_INET6 if address.version == 6 else socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 * 1024 * 1024)
        if connected:
            sock.connect(destination)
        else:
            sock.bind(("::" if address.version == 6 else "0.0.0.0", 0))
        sock.setblocking(False)
        started = time.perf_counter()
        deadline = started + job["seconds"]
        drain_deadline = deadline + 2
        next_send = started
        rate = job.get("rate_packets_per_second", 1000)
        sequence = 0
        peer_samples = []
        try:
            while time.perf_counter() < drain_deadline and not cancelled(job):
                now = time.perf_counter()
                if now < deadline and now >= next_send and len(pending) < 8192:
                    payload = pattern(sequence * job.get("message_bytes", 512), job.get("message_bytes", 512))
                    request = {"version": 1, "run_id": job["run_id"], "flow_id": flow_id, "sequence": sequence}
                    request["proof"] = mac(secret, b"udp-client:", json_bytes(request) + payload)
                    packet = socks_prefix + json_bytes(request) + b"\n" + payload
                    try:
                        if connected:
                            sock.send(packet)
                        else:
                            sock.sendto(packet, destination)
                        pending[sequence] = time.perf_counter_ns()
                        result["sent"] += 1
                    except OSError:
                        result["send_errors"] += 1
                    sequence += 1
                    next_send = max(next_send + (1 / rate if rate else 0), now)
                timeout = min(0.01, max(0.0, next_send - time.perf_counter())) if now < deadline and len(pending) < 8192 else 0.01
                if select.select([sock], [], [], timeout)[0]:
                    packet, _sender = sock.recvfrom(65535)
                    try:
                        if socks_prefix:
                            from trafficlab.socks_client import unwrap
                            packet = unwrap(packet)
                        header, payload = packet.split(b"\n", 1)
                        response = json.loads(header)
                        proof = response.pop("proof")
                        verify_mac(secret, b"udp-server:", json_bytes(response) + payload, proof)
                        reply_sequence = response["sequence"]
                        if response["run_id"] != job["run_id"] or response["flow_id"] != flow_id or payload != pattern(reply_sequence * job.get("message_bytes", 512), job.get("message_bytes", 512)):
                            raise ValueError("TRAFFIC_DATAGRAM_IDENTITY_MISMATCH")
                        if reply_sequence in seen:
                            result["duplicates"] += 1
                        elif reply_sequence in pending:
                            stamp = pending.pop(reply_sequence)
                            histogram.add((time.perf_counter_ns() - stamp) / 1_000_000)
                            result["received"] += 1
                            if reply_sequence < last_sequence:
                                result["reordered"] += 1
                            last_sequence = max(reply_sequence, last_sequence)
                            seen[reply_sequence] = None
                            if len(seen) > 16384:
                                seen.popitem(last=False)
                            if len(peer_samples) < 16:
                                peer_samples.append(response["peer"])
                        else:
                            result["expired"] += 1
                    except (ValueError, KeyError, TypeError, json.JSONDecodeError):
                        result["invalid"] += 1
                while pending and (time.perf_counter_ns() - next(iter(pending.values()))) > 2_000_000_000:
                    pending.popitem(last=False)
                    result["expired"] += 1
                if now >= deadline and not pending:
                    break
        except OSError:
            result["errors"].append("UDP_TRANSPORT_FAILED")
        result["elapsed_seconds"] = time.perf_counter() - started
        result["loss"] = result["sent"] - result["received"]
        result["loss_fraction"] = result["loss"] / result["sent"] if result["sent"] else None
        result["loss_definition"] = "authenticated-replies-not-received-within-2s-deadline"
        result["achieved_send_packets_per_second"] = result["sent"] / job["seconds"]
        result["received_packets_per_second"] = result["received"] / result["elapsed_seconds"]
        result["peer_observed_by_origin"] = peer_samples
        result["latency"] = histogram.view()
        result["complete"] = not cancelled(job) and not result["errors"] and result["invalid"] == 0 and result["received"] > 0
        result["cancelled"] = cancelled(job)
    if control is not None:
        control.close()
    return result


def validate_job(job: dict[str, Any]) -> None:
    ipaddress.ip_address(job["host"])
    if len(bytes.fromhex(job["secret"])) != 32 or not isinstance(job["run_id"], str) or not ID.fullmatch(job["run_id"]):
        raise ValueError("TRAFFIC_JOB_INVALID")
    for key, minimum, maximum in (("port", 1, 65535), ("connections", 1, 1024),
                                 ("message_bytes", 1, 60000), ("warmup_count", 0, 100000)):
        value = job.get(key, {"connections": 1, "message_bytes": 512, "warmup_count": 100}.get(key))
        if isinstance(value, bool) or not isinstance(value, int) or not minimum <= value <= maximum:
            raise ValueError("TRAFFIC_JOB_INVALID")
    for key, maximum in (("seconds", MAX_SECONDS), ("rate_bytes_per_second", 10**10), ("rate_packets_per_second", 10**7), ("rate_flows_per_second", 10**5)):
        value = job.get(key, 0)
        if isinstance(value, bool) or not isinstance(value, (float, int)) or not math.isfinite(value) or not 0 <= value <= maximum:
            raise ValueError("TRAFFIC_JOB_INVALID")
    if job["seconds"] < 0.05 or job.get("task") not in ("echo", "upload", "download", "duplex", "hold", "udp", "flow_rate"):
        raise ValueError("TRAFFIC_JOB_INVALID")


def execute(job: dict[str, Any]) -> dict[str, Any]:
    validate_job(job)
    started = time.perf_counter()
    with concurrent.futures.ThreadPoolExecutor(max_workers=job.get("connections", 1)) as pool:
        futures = []
        for index in range(job.get("connections", 1)):
            flow_id = str(uuid.uuid4())
            if job["task"] == "udp":
                futures.append(pool.submit(udp_flow, job, flow_id))
            elif job["task"] == "flow_rate":
                futures.append(pool.submit(flow_churn, job, index))
            else:
                futures.append(pool.submit(tcp_flow, job, job["task"], flow_id))
        flows = [future.result() for future in futures]
    elapsed = time.perf_counter() - started
    from trafficlab.proxy import fingerprint
    tcp_fingerprint = 0
    tcp_flows = 0
    udp_fingerprint = 0
    for flow in flows:
        if job["task"] == "flow_rate":
            tcp_fingerprint ^= int(flow["tcp_origin_fingerprint"], 16)
            tcp_flows += flow["completed"]
        elif job["task"] != "udp" and flow["complete"]:
            tcp_fingerprint ^= fingerprint(flow["flow_id"], flow["peer_observed_by_origin"])
            tcp_flows += 1
        elif job["task"] == "udp" and flow.get("received", 0):
            udp_fingerprint ^= fingerprint(flow["flow_id"], flow["peer_observed_by_origin"][0])
    return {"schema_version": 1, "measurement_method": "controlled-traffic-v1", "run_id": job["run_id"],
            "task": job["task"], "complete": all(flow["complete"] for flow in flows), "flows": flows,
            "elapsed_seconds": elapsed, "tx_bytes": sum(flow.get("tx_bytes", 0) for flow in flows),
            "rx_bytes": sum(flow.get("rx_bytes", 0) for flow in flows),
            "product_route_confirmed": False, "metric_scope": "controlled-worker-and-origin",
            "tcp_origin_fingerprint": f"{tcp_fingerprint:064x}", "successful_tcp_flows": tcp_flows,
            "udp_origin_fingerprint": f"{udp_fingerprint:064x}",
            "rate_limit_bytes_per_second_per_flow": job.get("rate_bytes_per_second", 0),
            "rate_limit_packets_per_second_per_flow": job.get("rate_packets_per_second", 1000)}


def flow_churn(job: dict[str, Any], worker_index: int) -> dict[str, Any]:
    started = time.perf_counter()
    deadline = started + job["seconds"]
    offered = completed = failures = 0
    histogram = Histogram()
    samples = []
    fingerprint_value = 0
    tx_bytes = rx_bytes = 0
    while time.perf_counter() < deadline and not cancelled(job):
        short = {**job, "seconds": 0.05, "warmup_count": 0, "message_bytes": 64}
        result = tcp_flow(short, "echo", f"{job['run_id']}.{worker_index}.{offered}")
        offered += 1
        if result["complete"]:
            completed += 1
            histogram.add(result["connect_ms"])
            from trafficlab.proxy import fingerprint
            fingerprint_value ^= fingerprint(result["flow_id"], result["peer_observed_by_origin"])
        else:
            failures += 1
        tx_bytes += result["tx_bytes"]
        rx_bytes += result["rx_bytes"]
        if len(samples) < 64:
            samples.append(result)
        pace(started, offered, job.get("rate_flows_per_second", 0), job)
    elapsed = time.perf_counter() - started
    return {"complete": failures == 0 and completed > 0 and not cancelled(job), "cancelled": cancelled(job),
            "offered": offered, "completed": completed, "failures": failures, "elapsed_seconds": elapsed,
            "completed_flows_per_second": completed / elapsed, "connection_and_authentication_ms": histogram.view(),
            "tx_bytes": tx_bytes, "rx_bytes": rx_bytes, "tcp_origin_fingerprint": f"{fingerprint_value:064x}",
            "route_samples": samples, "hold_seconds_per_flow": 0.05, "errors": [] if failures == 0 else ["CONNECTION_FAILURES_OBSERVED"]}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--job", required=True)
    parser.add_argument("--output", required=True)
    arguments = parser.parse_args()
    try:
        job = json.loads(Path(arguments.job).read_text(encoding="utf-8-sig"))
        report = execute(job)
        temporary = Path(arguments.output + ".tmp")
        temporary.write_bytes(json_bytes(report) + b"\n")
        temporary.replace(arguments.output)
        print(json_bytes({"complete": report["complete"], "task": report["task"], "elapsed_seconds": report["elapsed_seconds"]}).decode(), flush=True)
        return 0 if report["complete"] else 1
    except (OSError, ValueError, KeyError):
        print("TRAFFIC_WORKER_CONFIGURATION_OR_RUNTIME_ERROR", flush=True)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
