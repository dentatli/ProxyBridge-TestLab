"""Pure, deterministic browser-origin response construction for TestLab."""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import re
from typing import Any


_MAX_PATH_LENGTH = 512
_IDENTIFIER = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$")
_PATH_LABELS = ("browser-origin", "v1", "runs", "scenarios", "attempts", "flows")
_RESOURCES = {"page": ("text/html; charset=utf-8", "BROWSER_ORIGIN_PAGE_SERVED"), "download": ("application/octet-stream", "BROWSER_ORIGIN_DOWNLOAD_SERVED")}
_MARKER_ID = "proxybridge-testlab-browser-result"
_MARKER_VALUE = "PB_TESTLAB_BROWSER_READY"


class BrowserOriginError(ValueError):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


@dataclass(frozen=True)
class BrowserOriginResponse:
    status_code: int
    content_type: str
    headers: dict[str, str]
    body: bytes
    evidence: dict[str, Any]


def _parse_path(path: str) -> tuple[str, str, str, str, str]:
    if not isinstance(path, str):
        raise BrowserOriginError("BROWSER_ORIGIN_PATH_INVALID")
    if len(path) > _MAX_PATH_LENGTH:
        raise BrowserOriginError("BROWSER_ORIGIN_PATH_TOO_LONG")
    if "?" in path or "#" in path:
        raise BrowserOriginError("BROWSER_ORIGIN_QUERY_FORBIDDEN")
    if "\\" in path or "%" in path:
        raise BrowserOriginError("BROWSER_ORIGIN_PATH_INVALID")
    parts = path.split("/")
    if ".." in parts or "." in parts:
        raise BrowserOriginError("BROWSER_ORIGIN_TRAVERSAL_FORBIDDEN")
    if len(parts) != 12 or parts[0] != "":
        raise BrowserOriginError("BROWSER_ORIGIN_PATH_INVALID")
    if (parts[1], parts[2], parts[3], parts[5], parts[7], parts[9]) != _PATH_LABELS:
        raise BrowserOriginError("BROWSER_ORIGIN_PATH_INVALID")
    run_id, scenario_id, attempt_id, flow_id, resource = parts[4], parts[6], parts[8], parts[10], parts[11]
    for identifier in (run_id, scenario_id, attempt_id, flow_id):
        if not _IDENTIFIER.fullmatch(identifier):
            raise BrowserOriginError("BROWSER_ORIGIN_IDENTIFIER_INVALID")
    if resource not in _RESOURCES:
        raise BrowserOriginError("BROWSER_ORIGIN_RESOURCE_INVALID")
    return run_id, scenario_id, attempt_id, flow_id, resource


def _session_id(run_id: str, scenario_id: str, attempt_id: str, flow_id: str) -> str:
    value = "\x1f".join((run_id, scenario_id, attempt_id, flow_id)).encode("utf-8")
    return hashlib.sha256(value).hexdigest()


def _body(resource: str, path: str, session_id: str, identities: dict[str, str]) -> bytes:
    if resource == "page":
        download_path = path.rsplit("/", 1)[0] + "/download"
        return (
            "<!doctype html><html><head><meta charset=\"utf-8\"><title>ProxyBridge TestLab Browser Origin</title>"
            "</head><body data-browser-session=\"" + session_id + "\"><h1>ProxyBridge TestLab Browser Origin</h1>"
            "<a id=\"download\" href=\"" + download_path + "\">Download</a>"
            "<script id=\"" + _MARKER_ID + "\" type=\"application/json\">{\"dom_marker\":\"\",\"content_sha256\":\"\",\"response_status\":0,\"negotiated_protocol\":\"\"}</script>"
            "<script>(()=>{const target=\"" + download_path + "\";const marker=document.getElementById(\"" + _MARKER_ID + "\");"
            "const emit=value=>{marker.textContent=JSON.stringify(value)};fetch(target,{cache:\"no-store\"}).then(async response=>{"
            "const bytes=await response.arrayBuffer();const digest=await crypto.subtle.digest(\"SHA-256\",bytes);"
            "const hash=Array.from(new Uint8Array(digest),item=>item.toString(16).padStart(2,\"0\")).join(\"\");"
            "const entry=performance.getEntriesByName(new URL(target,location.href).href).slice(-1)[0];"
            "emit({dom_marker:\"" + _MARKER_VALUE + "\",content_sha256:hash,response_status:response.status,"
            "negotiated_protocol:entry&&typeof entry.nextHopProtocol===\"string\"?entry.nextHopProtocol:\"\"})"
            "}).catch(()=>emit({dom_marker:\"" + _MARKER_VALUE + "\",content_sha256:\"\",response_status:0,negotiated_protocol:\"\"}))})()</script>"
            "</body></html>"
        ).encode("utf-8")
    return (
        b"proxybridge-testlab-browser-download-v1\n"
        + json.dumps(identities, sort_keys=True, separators=(",", ":")).encode("utf-8")
        + b"\n"
    )


def build_browser_origin_response(path: str) -> BrowserOriginResponse:
    """Build one path-bound response; this function opens no socket or process."""

    run_id, scenario_id, attempt_id, flow_id, resource = _parse_path(path)
    identities = {"run_id": run_id, "scenario_id": scenario_id, "attempt_id": attempt_id, "flow_id": flow_id}
    session_id = _session_id(run_id, scenario_id, attempt_id, flow_id)
    content_type, event = _RESOURCES[resource]
    body = _body(resource, path, session_id, identities)
    evidence = {
        "schema_version": 1,
        **identities,
        "phase": "server",
        "sequence": 1 if resource == "page" else 2,
        "event": event,
        "resource": resource,
        "browser_session_id": session_id,
        "request_path": path,
        "content_sha256": hashlib.sha256(body).hexdigest(),
        "content_length": len(body),
        "result": "PASS",
    }
    headers = {
        "Cache-Control": "no-store",
        "X-Content-Type-Options": "nosniff",
    }
    if resource == "download":
        headers["Content-Disposition"] = "attachment; filename=proxybridge-testlab-download.bin"
    return BrowserOriginResponse(200, content_type, headers, body, evidence)
