import asyncio
import hashlib
import json
import re
import sys
import tempfile
from pathlib import Path

root = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(root / "src" / "server_agent"))

from browser_origin import BrowserOriginError, build_browser_origin_response
import pb_protocol_server as protocol_server
from pb_protocol_server import EvidenceLog, _http, _ssl_context


PATH_ROOT = "/browser-origin/v1/runs/run-001/scenarios/canary-browser-download/attempts/attempt-001/flows/flow-001"


def expect_error(path, code):
    try:
        build_browser_origin_response(path)
    except BrowserOriginError as error:
        assert error.code == code, (error.code, code)
        return
    raise AssertionError(f"expected {code}")


class MemoryWriter:
    """A minimal in-memory HTTP boundary; it opens no listener or network socket."""

    def __init__(self):
        self.payload = bytearray()
        self.closed = False

    def write(self, value):
        self.payload.extend(value)

    async def drain(self):
        return None

    def close(self):
        self.closed = True

    async def wait_closed(self):
        return None

    def get_extra_info(self, name):
        if name == "sockname":
            return ("192.0.2.10", 443)
        if name == "peername":
            return ("198.51.100.20", 50000)
        if name == "ssl_object":
            return None
        return None


async def invoke_http(request):
    reader = asyncio.StreamReader()
    reader.feed_data(request)
    reader.feed_eof()
    writer = MemoryWriter()
    with tempfile.TemporaryDirectory() as directory:
        evidence_path = Path(directory) / "evidence.jsonl"
        await _http(reader, writer, EvidenceLog(str(evidence_path)), True)
        records = [json.loads(line) for line in evidence_path.read_text("utf-8").splitlines()] if evidence_path.exists() else []
    return bytes(writer.payload), records, writer.closed


def parse_response(value):
    head, body = value.split(b"\r\n\r\n", 1)
    lines = head.decode("iso-8859-1").split("\r\n")
    headers = {}
    for line in lines[1:]:
        name, item = line.split(":", 1)
        headers[name.lower()] = item.strip()
    return lines[0], headers, body


page = build_browser_origin_response(PATH_ROOT + "/page")
page_repeat = build_browser_origin_response(PATH_ROOT + "/page")
assert page.status_code == 200
assert page.content_type == "text/html; charset=utf-8"
assert page.body == page_repeat.body
assert b"ProxyBridge TestLab Browser Origin" in page.body
assert b"/download" in page.body
assert page.evidence == page_repeat.evidence
assert page.evidence == {
    "schema_version": 1,
    "run_id": "run-001",
    "scenario_id": "canary-browser-download",
    "attempt_id": "attempt-001",
    "flow_id": "flow-001",
    "phase": "server",
    "sequence": 1,
    "event": "BROWSER_ORIGIN_PAGE_SERVED",
    "resource": "page",
    "browser_session_id": page.evidence["browser_session_id"],
    "request_path": PATH_ROOT + "/page",
    "content_sha256": hashlib.sha256(page.body).hexdigest(),
    "content_length": len(page.body),
    "result": "PASS",
}

download = build_browser_origin_response(PATH_ROOT + "/download")
assert download.status_code == 200
assert download.content_type == "application/octet-stream"
assert download.body == build_browser_origin_response(PATH_ROOT + "/download").body
assert download.headers == {
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    "Content-Disposition": "attachment; filename=proxybridge-testlab-download.bin",
}
assert download.evidence["event"] == "BROWSER_ORIGIN_DOWNLOAD_SERVED"
assert download.evidence["browser_session_id"] == page.evidence["browser_session_id"]
assert download.evidence["content_sha256"] == hashlib.sha256(download.body).hexdigest()
assert download.evidence["content_length"] == len(download.body)

expect_error(PATH_ROOT + "/page?run_id=other", "BROWSER_ORIGIN_QUERY_FORBIDDEN")
expect_error(PATH_ROOT + "/runs/second/page", "BROWSER_ORIGIN_PATH_INVALID")
expect_error("/browser-origin/v1/runs/../scenarios/x/attempts/y/flows/z/page", "BROWSER_ORIGIN_TRAVERSAL_FORBIDDEN")
expect_error("/" + ("x" * 513), "BROWSER_ORIGIN_PATH_TOO_LONG")
expect_error("/browser-origin/v1/runs/run-001/scenarios/x/attempts/y/flows/z/unknown", "BROWSER_ORIGIN_RESOURCE_INVALID")

# Regression: a real browser cannot attach TestLab-only headers.  The versioned
# path must be handled before the generic header-bound HTTP route.
page_request = (
    b"GET " + (PATH_ROOT + "/page").encode("ascii") + b" HTTP/1.1\r\n"
    b"Host: origin.test\r\n"
    b"Connection: close\r\n\r\n"
)
page_wire, page_records, page_closed = asyncio.run(invoke_http(page_request))
page_status, page_headers, page_body = parse_response(page_wire)
assert page_status == "HTTP/1.1 200 OK"
assert page_headers["cache-control"] == "no-store"
assert page_headers["x-content-type-options"] == "nosniff"
assert page_closed
assert page_body.count(b'id="proxybridge-testlab-browser-result"') == 1
assert b"crypto.subtle.digest" in page_body
assert b"fetch(" in page_body
marker_start = page_body.index(b' id="proxybridge-testlab-browser-result"')
marker_start = page_body.index(b">", marker_start) + 1
marker_end = page_body.index(b"</script>", marker_start)
assert json.loads(page_body[marker_start:marker_end].decode("utf-8")) == {
    "dom_marker": "",
    "content_sha256": "",
    "response_status": 0,
    "negotiated_protocol": "",
}
completed_markers = re.findall(rb'emit\(\{dom_marker:"([^"]+)"', page_body)
assert completed_markers == [b"PB_TESTLAB_BROWSER_READY", b"PB_TESTLAB_BROWSER_READY"]
assert b"PROXYBRIDGE_TESTLAB_BROWSER_RESULT_V1" not in page_body
assert len(page_records) == 1
assert page_records[0]["resource"] == "page"
assert page_records[0]["sequence"] == 1
assert page_records[0]["transport"] == "TCP"
assert page_records[0]["negotiated_protocol"] == "http/1.1"

download_request = (
    b"GET " + (PATH_ROOT + "/download").encode("ascii") + b" HTTP/1.1\r\n"
    b"Host: origin.test\r\n"
    b"Connection: close\r\n\r\n"
)
download_wire, download_records, _ = asyncio.run(invoke_http(download_request))
download_status, download_headers, download_body = parse_response(download_wire)
assert download_status == "HTTP/1.1 200 OK"
assert download_headers["cache-control"] == "no-store"
assert download_headers["x-content-type-options"] == "nosniff"
assert hashlib.sha256(download_body).hexdigest() == download_records[0]["content_sha256"]
assert download_records[0]["resource"] == "download"
assert download_records[0]["sequence"] == 2

# Malformed browser-origin requests must not create a successful evidence item.
bad_wire, bad_records, _ = asyncio.run(invoke_http(b"GET " + (PATH_ROOT + "/page?bad=1").encode("ascii") + b" HTTP/1.1\r\nHost: origin.test\r\n\r\n"))
assert bad_wire == b""
assert bad_records == []

chunked_wire, chunked_records, _ = asyncio.run(invoke_http(
    b"GET " + (PATH_ROOT + "/page").encode("ascii") + b" HTTP/1.1\r\n"
    b"Host: origin.test\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n"
))
assert chunked_wire == b""
assert chunked_records == []

identity_headers = (
    b"Host: origin.test\r\nX-TestLab-Run: run-001\r\nX-TestLab-Scenario: generic\r\n"
    b"X-TestLab-Attempt: attempt-001\r\nX-TestLab-Flow: flow-001\r\n\r\n"
)
for reserved_path in (b"/browser-origin", b"/browser-origin?generic=1"):
    reserved_wire, reserved_records, _ = asyncio.run(invoke_http(
        b"GET " + reserved_path + b" HTTP/1.1\r\n" + identity_headers
    ))
    assert reserved_wire == b""
    assert reserved_records == []


class FakeTlsContext:
    def __init__(self, protocol):
        self.protocol = protocol
        self.minimum_version = None
        self.alpn_protocols = None

    def load_cert_chain(self, certificate, private_key):
        self.certificate = certificate
        self.private_key = private_key

    def set_alpn_protocols(self, protocols):
        self.alpn_protocols = tuple(protocols)


real_ssl_context = protocol_server.ssl.SSLContext
try:
    protocol_server.ssl.SSLContext = FakeTlsContext
    tls_config = {
        "_root": str(root),
        "tls": {"certificate": "server.pem", "private_key": "server.key"},
    }
    http1_context = _ssl_context(tls_config, ("http/1.1",))
    http2_context = _ssl_context(tls_config, ("h2",))
finally:
    protocol_server.ssl.SSLContext = real_ssl_context
assert http1_context.alpn_protocols == ("http/1.1",)
assert "h2" not in http1_context.alpn_protocols
assert http2_context.alpn_protocols == ("h2",)

# The generic HTTP contract remains header-bound and unchanged.
generic_wire, generic_records, _ = asyncio.run(invoke_http(
    b"POST /generic HTTP/1.1\r\nHost: origin.test\r\nX-TestLab-Run: run-001\r\n"
    b"X-TestLab-Scenario: generic\r\nX-TestLab-Attempt: attempt-001\r\nX-TestLab-Flow: flow-001\r\nContent-Length: 2\r\n\r\nok"
))
generic_status, _, _ = parse_response(generic_wire)
assert generic_status == "HTTP/1.1 200 OK"
assert generic_records[0]["protocol_family"] == "http1"

print("PASS: offline browser-origin contract")
