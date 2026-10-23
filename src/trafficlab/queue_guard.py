"""Permit the next independent case only after fresh OFF and signed idle-origin evidence."""
from __future__ import annotations

import argparse
import datetime
import json
import subprocess
import time
from pathlib import Path
from typing import Any

from trafficlab.runner import idle
from trafficlab.schedule import origin_metrics
from trafficlab.worker import cancelled

CASE_FAILURES = {"TRAFFIC_TRANSPORT_INCOMPLETE", "TRAFFIC_ROUTE_UNVERIFIED",
                 "TRAFFIC_UDP_LOSS_THRESHOLD_EXCEEDED", "TRAFFIC_OFF_CONTROL_FAILED",
                 "TRAFFIC_UNRULED_CONTROL_FAILED", "TRAFFIC_UNRULED_CLEANUP_FAILED",
                 "TRAFFIC_CLI_CRASHED", "TRAFFIC_CLI_READINESS_FAILED",
                 "TRAFFIC_CLI_PROFILE_NOT_CONFIRMED", "TRAFFIC_CONTROLLED_SHUTDOWN_FAILED",
                 "TRAFFIC_CLI_CAPTURE_INCOMPLETE"}


def eligible(report: dict[str, Any], binding: dict[str, Any]) -> bool:
    errors = report.get("errors")
    controls = report.get("controls", [])
    measurements = report.get("measurements", [])
    conditions = report.get("conditions", {})
    if any(not isinstance(binding.get(key), str) or len(binding[key]) != 64
           for key in ("remote_bundle_sha256", "local_runtime_sha256")):
        return False
    if (report.get("complete") is not False or report.get("cancelled") is not False or
        report.get("cleanup_verified") is not True or report.get("off_after_attempt", {}).get("off_verified") is not True or
        not isinstance(errors, list) or not errors or any(not isinstance(code, str) for code in errors) or
        not set(errors).issubset(CASE_FAILURES) or
        conditions.get("remote_bundle_sha256") != binding.get("remote_bundle_sha256") or
        conditions.get("local_runtime_sha256") != binding.get("local_runtime_sha256") or
        not conditions.get("application_tls_sha256")):
        return False
    # A case may fail before measurements (including a CLI crash). Readiness
    # is not a recovery proof: require native process exit and retained identity.
    lifecycles = [row.get("lifecycle", {}) for row in measurements if row.get("mode") != "OFF"]
    lifecycles += [report[key] for key in ("unruled_lifecycle", "last_lifecycle") if report.get(key)]
    for lifecycle in lifecycles:
        if (lifecycle.get("exit_verified") is not True or lifecycle.get("path_verified") is not True or
            lifecycle.get("capture_complete") is not True or lifecycle.get("output_retention_ok") is not True or
            lifecycle.get("forced_stop") is not False):
            return False
    if any(code.startswith("TRAFFIC_CLI_") or code.endswith("SHUTDOWN_FAILED") or code == "TRAFFIC_UNRULED_CLEANUP_FAILED" for code in errors) and not lifecycles:
        return False
    return True


def recover(binding_path: str, binding: dict[str, Any], report: dict[str, Any]) -> dict[str, Any]:
    evidence: dict[str, Any] = {"case_id": report.get("case_id"), "safe_to_continue": False,
        "reason": "TRAFFIC_FAILURE_NOT_RECOVERABLE", "fresh_off_verified": None,
        "origin_identity_verified": False, "origin_idle_verified": False,
        "checked_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat()}
    if not eligible(report, binding):
        return evidence
    if cancelled(binding):
        evidence["reason"] = "TRAFFIC_RECOVERY_CANCELLED"
        return evidence
    try:
        off = idle(binding_path, binding)
        evidence["fresh_off_verified"] = off["off_verified"] is True
    except (OSError, ValueError, KeyError, subprocess.TimeoutExpired):
        evidence.update(reason="TRAFFIC_RECOVERY_OFF_NOT_VERIFIED", fresh_off_verified=False)
        return evidence
    job = {**binding, "run_id": binding["id"] + "." + report["case_id"],
           "application_tls_sha256": report["conditions"]["application_tls_sha256"]}
    if report['conditions'].get('application_ssh_sha256'):
        job['application_ssh_sha256'] = report['conditions']['application_ssh_sha256']
    deadline = time.monotonic() + 2
    try:
        while True:
            if cancelled(binding):
                evidence["reason"] = "TRAFFIC_RECOVERY_CANCELLED"
                return evidence
            origin = origin_metrics(job)
            if origin.get("identity", {}).get("verified") is not True:
                raise ValueError("TRAFFIC_REMOTE_ARTIFACT_IDENTITY_CHANGED")
            evidence["origin_identity_verified"] = True
            if all(type(origin.get(key)) is int and origin[key] == 0
                   for key in ("runtime_connections", "proxy_connections")):
                evidence.update(safe_to_continue=True, reason="TRAFFIC_RECOVERY_VERIFIED", origin_idle_verified=True)
                return evidence
            if time.monotonic() >= deadline:
                evidence["reason"] = "TRAFFIC_RECOVERY_ORIGIN_NOT_IDLE"
                return evidence
            time.sleep(0.1)
    except (OSError, ValueError, KeyError, EOFError):
        evidence.update(reason="TRAFFIC_RECOVERY_ORIGIN_NOT_VERIFIED", origin_identity_verified=False)
        return evidence


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binding", required=True)
    parser.add_argument("--report", required=True)
    args = parser.parse_args()
    report_path = Path(args.report)
    if report_path.is_symlink() or report_path.stat().st_size > 64 * 1024 * 1024:
        raise ValueError("TRAFFIC_RECOVERY_REPORT_INVALID")
    binding = json.loads(Path(args.binding).read_text(encoding="utf-8-sig"))
    report = json.loads(report_path.read_text(encoding="utf-8-sig"))
    evidence = recover(args.binding, binding, report)
    print(json.dumps(evidence, separators=(",", ":")))
    return 0 if evidence["safe_to_continue"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
