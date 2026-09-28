from __future__ import annotations

import asyncio
import hashlib
import json
import time
from pathlib import Path
from typing import Any

from aioquic.asyncio import connect
from aioquic.asyncio.protocol import QuicConnectionProtocol
from aioquic.h3.connection import H3_ALPN, H3Connection
from aioquic.h3.events import DataReceived, DatagramReceived, HeadersReceived
from aioquic.quic.configuration import QuicConfiguration

from model import WorkerContractError, WorkerPlan
from plugins.common import base_record, expects_no_response, is_no_response_exception, no_response_reason, required_parameter, required_port


class _Http3ClientProtocol(QuicConnectionProtocol):
    def __init__(self, *args: Any, webtransport: bool = False, **kwargs: Any) -> None:
        super().__init__(*args, **kwargs)
        self._http = H3Connection(self._quic, enable_webtransport=webtransport)
        self._headers: dict[int, list[tuple[bytes, bytes]]] = {}
        self._bodies: dict[int, bytearray] = {}
        self._completed: dict[int, asyncio.Future[tuple[list[tuple[bytes, bytes]], bytes]]] = {}
        self._datagrams: dict[int, asyncio.Future[bytes]] = {}
        self._header_only: set[int] = set()

    def quic_event_received(self, event: Any) -> None:
        for http_event in self._http.handle_event(event):
            if isinstance(http_event, HeadersReceived):
                self._headers.setdefault(http_event.stream_id, []).extend(http_event.headers)
                if http_event.stream_id in self._header_only and not self._completed[http_event.stream_id].done():
                    self._completed[http_event.stream_id].set_result((self._headers[http_event.stream_id], bytes(self._bodies.get(http_event.stream_id, b""))))
                if http_event.stream_ended:
                    self._finish_stream(http_event.stream_id)
            elif isinstance(http_event, DataReceived):
                self._bodies.setdefault(http_event.stream_id, bytearray()).extend(http_event.data)
                if http_event.stream_ended:
                    self._finish_stream(http_event.stream_id)
            elif isinstance(http_event, DatagramReceived):
                waiter = self._datagrams.get(http_event.stream_id)
                if waiter is not None and not waiter.done():
                    waiter.set_result(http_event.data)

    def _finish_stream(self, stream_id: int) -> None:
        waiter = self._completed.get(stream_id)
        if waiter is not None and not waiter.done():
            waiter.set_result((self._headers.get(stream_id, []), bytes(self._bodies.get(stream_id, b""))))

    async def request(self, headers: list[tuple[bytes, bytes]], body: bytes, timeout: float) -> tuple[int, list[tuple[bytes, bytes]], bytes]:
        stream_id = self._quic.get_next_available_stream_id()
        self._completed[stream_id] = asyncio.get_running_loop().create_future()
        self._http.send_headers(stream_id, headers, end_stream=not body)
        if body:
            self._http.send_data(stream_id, body, end_stream=True)
        self.transmit()
        response_headers, response_body = await asyncio.wait_for(self._completed[stream_id], timeout)
        return stream_id, response_headers, response_body

    async def open_webtransport(self, headers: list[tuple[bytes, bytes]], payload: bytes, timeout: float) -> tuple[int, list[tuple[bytes, bytes]], bytes]:
        stream_id = self._quic.get_next_available_stream_id()
        self._completed[stream_id] = asyncio.get_running_loop().create_future()
        self._header_only.add(stream_id)
        self._http.send_headers(stream_id, headers, end_stream=False)
        self.transmit()
        response_headers, _ = await asyncio.wait_for(self._completed[stream_id], timeout)
        if dict(response_headers).get(b":status") != b"200":
            raise WorkerContractError("WEBTRANSPORT_CONNECT_FAILED")
        self._datagrams[stream_id] = asyncio.get_running_loop().create_future()
        self._http.send_datagram(stream_id, payload)
        self.transmit()
        response = await asyncio.wait_for(self._datagrams[stream_id], timeout)
        return stream_id, response_headers, response


def _configuration(plan: WorkerPlan) -> QuicConfiguration:
    ca_path = Path(required_parameter(plan, "ca_path", str)).resolve()
    if not ca_path.is_file():
        raise WorkerContractError("QUIC_CA_FILE_MISSING")
    configuration = QuicConfiguration(
        is_client=True,
        alpn_protocols=H3_ALPN,
        server_name=required_parameter(plan, "server_name", str),
        max_datagram_frame_size=65536,
    )
    configuration.load_verify_locations(cafile=str(ca_path))
    return configuration


def _addresses(protocol: _Http3ClientProtocol) -> tuple[int, Any, Any]:
    transport = getattr(protocol, "_transport", None)
    if transport is None:
        return 0, None, None
    socket_value = transport.get_extra_info("socket")
    return (
        int(socket_value.fileno()) if socket_value is not None else 0,
        transport.get_extra_info("sockname"),
        transport.get_extra_info("peername"),
    )


def _quic_fields(protocol: _Http3ClientProtocol, stream_id: int, response_hash: str, status_code: int) -> dict[str, Any]:
    version = getattr(protocol._quic, "_version", 0)
    connection_id = bytes(getattr(protocol._quic, "host_cid", b""))
    return {
        "quic_version": f"0x{int(version):08x}",
        "alpn": "h3",
        "connection_id_digest": hashlib.sha256(connection_id).hexdigest(),
        "stream_id": stream_id,
        "handshake_complete": True,
        "status_code": status_code,
        "response_body_sha256": response_hash,
        "migration_status": "NOT_ATTEMPTED",
    }


async def _run_http3_async(plan: WorkerPlan, payload: bytes) -> tuple[_Http3ClientProtocol, int, int, bytes]:
    host = required_parameter(plan, "remote_host", str)
    port = required_port(plan)
    authority = required_parameter(plan, "authority", str)
    path = str(plan.raw["parameters"].get("path", "/probe"))
    if not path.startswith("/") or any(character in path for character in "\r\n"):
        raise WorkerContractError("HTTP3_PATH_INVALID")
    timeout = plan.raw["operation_timeout_ms"] / 1000.0
    create_protocol = lambda *args, **kwargs: _Http3ClientProtocol(*args, webtransport=False, **kwargs)
    async with connect(host, port, configuration=_configuration(plan), create_protocol=create_protocol) as raw_protocol:
        protocol = raw_protocol
        if not isinstance(protocol, _Http3ClientProtocol):
            raise WorkerContractError("HTTP3_PROTOCOL_INVALID")
        headers = [
            (b":method", b"POST"), (b":scheme", b"https"), (b":authority", authority.encode("utf-8")), (b":path", path.encode("utf-8")),
            (b"content-type", b"application/octet-stream"), (b"x-testlab-run", str(plan.raw["run_id"]).encode("ascii")),
            (b"x-testlab-scenario", str(plan.raw["scenario_id"]).encode("ascii")), (b"x-testlab-attempt", str(plan.raw["attempt_id"]).encode("ascii")),
            (b"x-testlab-flow", str(plan.raw["flow_id"]).encode("ascii")),
        ]
        stream_id, response_headers, response_body = await protocol.request(headers, payload, timeout)
        status_value = dict(response_headers).get(b":status", b"")
        if not status_value.isdigit():
            raise WorkerContractError("HTTP3_STATUS_INVALID")
        snapshot = protocol
        return snapshot, stream_id, int(status_value), response_body


async def _run_webtransport_async(plan: WorkerPlan, payload: bytes) -> tuple[_Http3ClientProtocol, int, bytes]:
    host = required_parameter(plan, "remote_host", str)
    port = required_port(plan)
    authority = required_parameter(plan, "authority", str)
    timeout = plan.raw["operation_timeout_ms"] / 1000.0
    create_protocol = lambda *args, **kwargs: _Http3ClientProtocol(*args, webtransport=True, **kwargs)
    async with connect(host, port, configuration=_configuration(plan), create_protocol=create_protocol) as raw_protocol:
        protocol = raw_protocol
        if not isinstance(protocol, _Http3ClientProtocol):
            raise WorkerContractError("WEBTRANSPORT_PROTOCOL_INVALID")
        headers = [
            (b":method", b"CONNECT"), (b":scheme", b"https"), (b":protocol", b"webtransport"),
            (b":authority", authority.encode("utf-8")), (b":path", b"/webtransport"),
            (b"sec-webtransport-http3-draft", b"draft02"), (b"x-testlab-run", str(plan.raw["run_id"]).encode("ascii")),
            (b"x-testlab-scenario", str(plan.raw["scenario_id"]).encode("ascii")), (b"x-testlab-attempt", str(plan.raw["attempt_id"]).encode("ascii")),
            (b"x-testlab-flow", str(plan.raw["flow_id"]).encode("ascii")),
        ]
        stream_id, _, response = await protocol.open_webtransport(headers, payload, timeout)
        snapshot = protocol
        return snapshot, stream_id, response


def run_quic_http3(plan: WorkerPlan) -> list[dict[str, Any]]:
    started = time.monotonic()
    payload = f"http3|{plan.raw['run_id']}|{plan.raw['scenario_id']}|{plan.raw['attempt_id']}|{plan.raw['flow_id']}".encode("utf-8")
    payload_hash = hashlib.sha256(payload).hexdigest()
    try:
        protocol, stream_id, status, response_body = asyncio.run(_run_http3_async(plan, payload))
        try:
            value = json.loads(response_body.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise WorkerContractError("HTTP3_RESPONSE_BODY_INVALID") from exc
        expected_status = int(plan.raw["expected"].get("status_code", 200))
        result = "PASS" if not expects_no_response(plan) and status == expected_status and value.get("flow_id") == plan.raw["flow_id"] and value.get("request_body_sha256") == payload_hash and value.get("result") == "PASS" else "FAIL"
        socket_id, local, remote = _addresses(protocol)
        record = base_record(plan, event="HTTP3_TRANSACTION_COMPLETED", started=started, socket_id=socket_id, local=local, remote=remote, payload_sha256=payload_hash, byte_count=len(payload), result=result)
        record.update(_quic_fields(protocol, stream_id, hashlib.sha256(response_body).hexdigest(), status))
        record["no_response_observed"] = False
        return [record]
    except (OSError, asyncio.TimeoutError) as exc:
        if not expects_no_response(plan) or not is_no_response_exception(exc):
            raise
        record = base_record(plan, event="HTTP3_NO_RESPONSE_OBSERVED", started=started, socket_id=0, local=None, remote=None, payload_sha256=payload_hash, byte_count=len(payload), result="PASS")
        record.update({"quic_version": "", "alpn": "", "connection_id_digest": hashlib.sha256(b"").hexdigest(), "stream_id": 0, "handshake_complete": False, "status_code": 0, "response_body_sha256": hashlib.sha256(b"").hexdigest(), "migration_status": "NOT_OBSERVED", "no_response_observed": True, "no_response_reason": no_response_reason(exc)})
        return [record]


def run_webtransport(plan: WorkerPlan) -> list[dict[str, Any]]:
    started = time.monotonic()
    payload = f"webtransport|{plan.raw['run_id']}|{plan.raw['scenario_id']}|{plan.raw['attempt_id']}|{plan.raw['flow_id']}".encode("utf-8")
    payload_hash = hashlib.sha256(payload).hexdigest()
    try:
        protocol, stream_id, response = asyncio.run(_run_webtransport_async(plan, payload))
        result = "PASS" if not expects_no_response(plan) and response == payload else "FAIL"
        socket_id, local, remote = _addresses(protocol)
        record = base_record(plan, event="WEBTRANSPORT_TRANSACTION_COMPLETED", started=started, socket_id=socket_id, local=local, remote=remote, payload_sha256=payload_hash, byte_count=len(payload), result=result)
        record.update(_quic_fields(protocol, stream_id, hashlib.sha256(response).hexdigest(), 200))
        record["no_response_observed"] = False
        return [record]
    except (OSError, asyncio.TimeoutError) as exc:
        if not expects_no_response(plan) or not is_no_response_exception(exc):
            raise
        record = base_record(plan, event="WEBTRANSPORT_NO_RESPONSE_OBSERVED", started=started, socket_id=0, local=None, remote=None, payload_sha256=payload_hash, byte_count=len(payload), result="PASS")
        record.update({"quic_version": "", "alpn": "", "connection_id_digest": hashlib.sha256(b"").hexdigest(), "stream_id": 0, "handshake_complete": False, "status_code": 0, "response_body_sha256": hashlib.sha256(b"").hexdigest(), "migration_status": "NOT_OBSERVED", "no_response_observed": True, "no_response_reason": no_response_reason(exc)})
        return [record]
