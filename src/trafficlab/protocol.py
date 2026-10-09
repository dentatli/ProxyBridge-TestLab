"""Bounded wire format and streaming metrics shared by the controlled agent and worker."""
from __future__ import annotations

import hashlib
import hmac
import json
import math
import re
import struct
from typing import Any, BinaryIO

VERSION = 1
FRAME = struct.Struct("!QI")
BLOCK = bytes(range(256)) * 256
MAX_CHUNK = len(BLOCK)
MAX_LINE = 8192
MAX_SECONDS = 72 * 3600
ID = re.compile(r"^[a-zA-Z0-9_.-]{1,128}$")


def json_bytes(value: Any) -> bytes:
    return json.dumps(value, separators=(",", ":"), sort_keys=True, allow_nan=False).encode("ascii")


def read_json(stream: BinaryIO, limit: int = MAX_LINE) -> dict[str, Any]:
    line = stream.readline(limit + 1)
    if not line.endswith(b"\n") or len(line) > limit:
        raise ValueError("TRAFFIC_HEADER_INVALID")
    value = json.loads(line)
    if not isinstance(value, dict):
        raise ValueError("TRAFFIC_HEADER_INVALID")
    return value


def mac(secret: bytes, label: bytes, value: bytes) -> str:
    return hmac.new(secret, label + value, hashlib.sha256).hexdigest()


def verify_mac(secret: bytes, label: bytes, value: bytes, observed: str) -> None:
    if not isinstance(observed, str) or not hmac.compare_digest(mac(secret, label, value), observed):
        raise ValueError("TRAFFIC_AUTHENTICATION_FAILED")


def exact(stream: BinaryIO, size: int) -> bytes:
    parts = bytearray()
    while len(parts) < size:
        piece = stream.read(size - len(parts))
        if not piece:
            raise EOFError("TRAFFIC_TRUNCATED")
        parts.extend(piece)
    return bytes(parts)


def read_frame(stream: BinaryIO) -> tuple[int, bytes]:
    offset, size = FRAME.unpack(exact(stream, FRAME.size))
    if size > MAX_CHUNK:
        raise ValueError("TRAFFIC_FRAME_TOO_LARGE")
    return offset, exact(stream, size)


def pattern(offset: int, size: int) -> bytes:
    if not 0 <= size <= MAX_CHUNK:
        raise ValueError("TRAFFIC_FRAME_TOO_LARGE")
    start = offset % 256
    return (BLOCK + BLOCK[:256])[start:start + size]


def validate_request(request: dict[str, Any]) -> None:
    if request.get("version") != VERSION or request.get("task") not in ("echo", "upload", "download", "duplex", "hold", "metrics"):
        raise ValueError("TRAFFIC_REQUEST_INVALID")
    if any(not isinstance(request.get(field), str) or not ID.fullmatch(request[field]) for field in ("run_id", "flow_id")):
        raise ValueError("TRAFFIC_ID_INVALID")
    seconds = request.get("seconds")
    if isinstance(seconds, bool) or not isinstance(seconds, (float, int)) or not math.isfinite(seconds) or not 0.05 <= seconds <= MAX_SECONDS:
        raise ValueError("TRAFFIC_DURATION_INVALID")
    rate = request.get("rate_bytes_per_second", 0)
    if isinstance(rate, bool) or not isinstance(rate, (float, int)) or not math.isfinite(rate) or not 0 <= rate <= 10**10:
        raise ValueError("TRAFFIC_RATE_INVALID")


class Histogram:
    """Every observation is counted; percentiles are upper bounds with 1% relative bins."""
    def __init__(self) -> None:
        self.bins: dict[int, int] = {}
        self.count = 0
        self.total = 0.0
        self.maximum = 0.0

    def add(self, milliseconds: float) -> None:
        if not math.isfinite(milliseconds) or milliseconds < 0:
            raise ValueError("TRAFFIC_TIMING_INVALID")
        index = math.ceil(math.log1p(milliseconds / 0.001) / math.log1p(0.01))
        self.bins[index] = self.bins.get(index, 0) + 1
        self.count += 1
        self.total += milliseconds
        self.maximum = max(self.maximum, milliseconds)

    def view(self) -> dict[str, Any]:
        result: dict[str, Any] = {"count": self.count, "mean_ms": self.total / self.count if self.count else None,
                                  "max_ms": self.maximum if self.count else None, "method": "all-sample-log-histogram-upper-bound-1pct",
                                  "bins": dict(self.bins), "sum_ms": self.total}
        for percentile in (50, 95, 99):
            target = math.ceil(self.count * percentile / 100)
            cumulative = 0
            result[f"p{percentile}_ms"] = None
            if self.count:
                for index, count in sorted(self.bins.items()):
                    cumulative += count
                    if cumulative >= target:
                        result[f"p{percentile}_ms"] = 0.001 * (1.01 ** index - 1)
                        break
        return result

    def merge(self, value: dict[str, Any]) -> None:
        if value.get("method") != "all-sample-log-histogram-upper-bound-1pct":
            raise ValueError("TRAFFIC_HISTOGRAM_METHOD_MISMATCH")
        for index, count in value["bins"].items():
            key = int(index)
            self.bins[key] = self.bins.get(key, 0) + count
        self.count += value["count"]
        self.total += value["sum_ms"]
        self.maximum = max(self.maximum, value.get("max_ms") or 0)
