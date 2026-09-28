from __future__ import annotations

import os
import time
from datetime import datetime, timezone
from typing import Any

from model import WorkerPlan, deterministic_payload_hash


def _timestamp_utc() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def run_contract_selftest(plan: WorkerPlan) -> list[dict[str, Any]]:
    started = time.monotonic()
    marker = b"proxybridge-protocol-worker-selftest-v1"
    return [
        {
            "schema_version": 1,
            "run_id": plan.raw["run_id"],
            "scenario_id": plan.raw["scenario_id"],
            "attempt_id": plan.raw["attempt_id"],
            "flow_id": plan.raw["flow_id"],
            "phase": "selftest",
            "sequence": 1,
            "event": "SELF_TEST_COMPLETED",
            "timestamp_utc": _timestamp_utc(),
            "monotonic_ms": int((time.monotonic() - started) * 1000),
            "process_id": os.getpid(),
            "socket_id": 0,
            "protocol_family": plan.protocol_family,
            "transport": plan.transport,
            "local_ip": "",
            "local_port": 0,
            "remote_ip": "",
            "remote_port": 0,
            "payload_sha256": deterministic_payload_hash(marker),
            "bytes": 0,
            "result": "PASS",
            "expected_action": "SELF_TEST",
            "observed_action": "SELF_TEST",
            "send_count": 0,
            "receive_count": 0,
        }
    ]
