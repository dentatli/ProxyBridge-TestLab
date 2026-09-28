from __future__ import annotations

import hashlib
import json
import socket
import ssl
import time
from pathlib import Path
from typing import Any

from h2.config import H2Configuration
from h2.connection import H2Connection
from h2.events import DataReceived, ResponseReceived, StreamEnded, TrailersReceived
from h2.exceptions import H2Error

from model import WorkerContractError, WorkerPlan
from plugins.common import (
    base_record,
    expects_no_response,
    is_no_response_exception,
    no_response_reason,
    required_parameter,
    required_port,
)


def _request(
    plan: WorkerPlan,
    *,
    path: str,
    content_type: str,
    body: bytes,
) -> tuple[int, dict[str, str], dict[str, str], bytes, str, int, int, Any, Any]:
    host = required_parameter(plan, "remote_host", str)
    port = required_port(plan)
    authority = required_parameter(plan, "authority", str)
    server_name = required_parameter(plan, "server_name", str)
    ca_path = Path(required_parameter(plan, "ca_path", str)).resolve()
    if not ca_path.is_file():
        raise WorkerContractError("HTTP2_CA_FILE_MISSING")
    timeout = plan.raw["operation_timeout_ms"] / 1000.0
    context = ssl.create_default_context(ssl.Purpose.SERVER_AUTH, cafile=str(ca_path))
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.set_alpn_protocols(["h2"])
    raw = socket.create_connection((host, port), timeout=timeout)
    try:
        raw.settimeout(timeout)
        with context.wrap_socket(raw, server_hostname=server_name) as sock:
            if sock.selected_alpn_protocol() != "h2":
                raise WorkerContractError("HTTP2_ALPN_NEGOTIATION_FAILED")
            connection = H2Connection(config=H2Configuration(client_side=True, header_encoding="utf-8"))
            connection.initiate_connection()
            sock.sendall(connection.data_to_send())
            stream_id = connection.get_next_available_stream_id()
            headers = [
                (":method", "POST"),
                (":scheme", "https"),
                (":authority", authority),
                (":path", path),
                ("content-type", content_type),
                ("content-length", str(len(body))),
                ("x-testlab-run", str(plan.raw["run_id"])),
                ("x-testlab-scenario", str(plan.raw["scenario_id"])),
                ("x-testlab-attempt", str(plan.raw["attempt_id"])),
                ("x-testlab-flow", str(plan.raw["flow_id"])),
            ]
            connection.send_headers(stream_id, headers, end_stream=not body)
            if body:
                connection.send_data(stream_id, body, end_stream=True)
            sock.sendall(connection.data_to_send())
            response_headers: dict[str, str] = {}
            response_trailers: dict[str, str] = {}
            response_body = bytearray()
            ended = False
            while not ended:
                data = sock.recv(65535)
                if not data:
                    raise WorkerContractError("HTTP2_RESPONSE_TRUNCATED")
                for event in connection.receive_data(data):
                    if isinstance(event, ResponseReceived) and event.stream_id == stream_id:
                        response_headers.update((str(name), str(value)) for name, value in event.headers)
                    elif isinstance(event, TrailersReceived) and event.stream_id == stream_id:
                        response_trailers.update((str(name), str(value)) for name, value in event.headers)
                    elif isinstance(event, DataReceived) and event.stream_id == stream_id:
                        response_body.extend(event.data)
                        connection.acknowledge_received_data(event.flow_controlled_length, stream_id)
                    elif isinstance(event, StreamEnded) and event.stream_id == stream_id:
                        ended = True
                pending = connection.data_to_send()
                if pending:
                    sock.sendall(pending)
            status_text = response_headers.get(":status", "")
            if not status_text.isdigit():
                raise WorkerContractError("HTTP2_STATUS_INVALID")
            return (
                int(status_text),
                response_headers,
                response_trailers,
                bytes(response_body),
                sock.selected_alpn_protocol() or "",
                stream_id,
                sock.fileno(),
                sock.getsockname(),
                sock.getpeername(),
            )
    except H2Error as exc:
        raise WorkerContractError("HTTP2_PROTOCOL_ERROR") from exc
    finally:
        raw.close()


def run_http2(plan: WorkerPlan) -> list[dict[str, Any]]:
    started = time.monotonic()
    path = str(plan.raw["parameters"].get("path", "/probe"))
    authority = required_parameter(plan, "authority", str)
    if not path.startswith("/") or any(character in path for character in "\r\n"):
        raise WorkerContractError("HTTP2_PATH_INVALID")
    payload = f"http2|{plan.raw['run_id']}|{plan.raw['scenario_id']}|{plan.raw['attempt_id']}|{plan.raw['flow_id']}".encode("utf-8")
    payload_hash = hashlib.sha256(payload).hexdigest()
    try:
        status, _, _, response_body, alpn, stream_id, socket_id, local, remote = _request(
            plan, path=path, content_type="application/octet-stream", body=payload
        )
        try:
            value = json.loads(response_body.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise WorkerContractError("HTTP2_RESPONSE_BODY_INVALID") from exc
        expected_status = int(plan.raw["expected"].get("status_code", 200))
        result = "PASS" if (
            not expects_no_response(plan)
            and status == expected_status
            and value.get("flow_id") == plan.raw["flow_id"]
            and value.get("request_body_sha256") == payload_hash
            and value.get("result") == "PASS"
        ) else "FAIL"
        record = base_record(plan, event="HTTP2_TRANSACTION_COMPLETED", started=started, socket_id=socket_id, local=local, remote=remote, payload_sha256=payload_hash, byte_count=len(payload), result=result)
        record.update({"alpn": alpn, "stream_id": stream_id, "method": "POST", "authority": authority, "path_digest": hashlib.sha256(path.encode("utf-8")).hexdigest(), "status_code": status, "request_body_sha256": payload_hash, "response_body_sha256": hashlib.sha256(response_body).hexdigest(), "end_stream": True, "flow_control_complete": True, "no_response_observed": False})
        return [record]
    except OSError as exc:
        if not expects_no_response(plan) or not is_no_response_exception(exc):
            raise
        record = base_record(plan, event="HTTP2_NO_RESPONSE_OBSERVED", started=started, socket_id=0, local=None, remote=None, payload_sha256=payload_hash, byte_count=len(payload), result="PASS")
        record.update({"alpn": "", "stream_id": 0, "method": "POST", "authority": authority, "path_digest": hashlib.sha256(path.encode("utf-8")).hexdigest(), "status_code": 0, "request_body_sha256": payload_hash, "response_body_sha256": hashlib.sha256(b"").hexdigest(), "end_stream": False, "flow_control_complete": False, "no_response_observed": True, "no_response_reason": no_response_reason(exc)})
        return [record]


def run_grpc(plan: WorkerPlan) -> list[dict[str, Any]]:
    started = time.monotonic()
    service = required_parameter(plan, "service", str)
    method = required_parameter(plan, "method", str)
    payload = f"grpc|{plan.raw['run_id']}|{plan.raw['scenario_id']}|{plan.raw['attempt_id']}|{plan.raw['flow_id']}".encode("utf-8")
    framed = b"\x00" + len(payload).to_bytes(4, "big") + payload
    request_hash = hashlib.sha256(payload).hexdigest()
    try:
        status, _, trailers, response_body, _, _, socket_id, local, remote = _request(
            plan, path=f"/{service}/{method}", content_type="application/grpc", body=framed
        )
        if len(response_body) < 5 or response_body[0] != 0 or int.from_bytes(response_body[1:5], "big") != len(response_body) - 5:
            raise WorkerContractError("GRPC_RESPONSE_FRAME_INVALID")
        response_payload = response_body[5:]
        application_status = trailers.get("grpc-status", "")
        result = "PASS" if not expects_no_response(plan) and status == 200 and application_status == "0" and response_payload == payload else "FAIL"
        record = base_record(plan, event="GRPC_TRANSACTION_COMPLETED", started=started, socket_id=socket_id, local=local, remote=remote, payload_sha256=request_hash, byte_count=len(payload), result=result)
        record.update({"rpc_protocol": "grpc", "service": service, "method": method, "request_sha256": request_hash, "response_sha256": hashlib.sha256(response_payload).hexdigest(), "application_status": application_status, "no_response_observed": False})
        return [record]
    except OSError as exc:
        if not expects_no_response(plan) or not is_no_response_exception(exc):
            raise
        record = base_record(plan, event="GRPC_NO_RESPONSE_OBSERVED", started=started, socket_id=0, local=None, remote=None, payload_sha256=request_hash, byte_count=len(payload), result="PASS")
        record.update({"rpc_protocol": "grpc", "service": service, "method": method, "request_sha256": request_hash, "response_sha256": hashlib.sha256(b"").hexdigest(), "application_status": "NOT_OBSERVED", "no_response_observed": True, "no_response_reason": no_response_reason(exc)})
        return [record]
