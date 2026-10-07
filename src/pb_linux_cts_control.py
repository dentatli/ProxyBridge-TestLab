#!/usr/bin/env python3
"""Fixed SSH-side lifecycle operations for the isolated CTS diagnostic receiver.

Reads one bounded JSON request from stdin. No shell interpolation, credentials,
arbitrary commands, global firewall changes or package installation.
"""
from __future__ import annotations

import base64
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time


ROOT = Path("/opt/proxybridge-testlab-diagnostics")
METHOD = "cts-2.0.3.9-push-receiver-v1"
SAFE_ID = re.compile(r"^[a-z0-9][a-z0-9-]{0,55}$")
SHA = re.compile(r"^[0-9a-f]{64}$")


def process(argv: list[str], timeout: int = 15) -> dict:
    result = subprocess.run(argv, stdin=subprocess.DEVNULL, capture_output=True,
                            text=True, timeout=timeout, check=False)
    if len(result.stdout) > 262144 or len(result.stderr) > 65536:
        raise ValueError("REMOTE_OPERATION_OUTPUT_BOUND")
    return {"exit_code": result.returncode, "stdout": result.stdout, "stderr": result.stderr}


def checked_directory(path: Path) -> None:
    for parent in (path, *path.parents):
        if parent.is_symlink():
            raise ValueError("REMOTE_INSTALL_SYMLINK")
        if parent.exists() and (not parent.is_dir() or parent.stat().st_uid != 0):
            raise ValueError("REMOTE_INSTALL_DIRECTORY_OWNER")
    path.mkdir(mode=0o755, parents=True, exist_ok=True)


def receiver_path(digest: str) -> Path:
    if not SHA.fullmatch(digest):
        raise ValueError("RECEIVER_HASH_INVALID")
    return ROOT / ("cts-push-" + digest[:16]) / "pb_cts_push_receiver.py"


def verified_receiver(request: dict) -> Path:
    path = receiver_path(request["receiver_sha256"])
    if path.is_symlink() or not path.is_file() or path.stat().st_uid != 0:
        raise ValueError("RECEIVER_INSTALL_INVALID")
    if hashlib.sha256(path.read_bytes()).hexdigest() != request["receiver_sha256"]:
        raise ValueError("RECEIVER_INSTALL_HASH_CHANGED")
    if path.stat().st_mode & 0o022:
        raise ValueError("RECEIVER_INSTALL_WRITABLE_BY_OTHERS")
    return path


def identity(request: dict) -> tuple[str, str, Path]:
    run_id = request.get("run_id", "")
    if not isinstance(run_id, str) or not SAFE_ID.fullmatch(run_id):
        raise ValueError("RUN_ID_INVALID")
    unit = "pb-testlab-cts-" + run_id + ".service"
    evidence = Path("/var/lib/pb-testlab-cts") / run_id / "receiver.jsonl"
    return run_id, unit, evidence


def status(unit: str) -> dict:
    result = process(["systemctl", "show", unit, "--no-pager",
                      "--property=LoadState,ActiveState,SubState,MainPID,Result,ExecMainStatus,ExecMainCode,Description,Transient"])
    fields = dict(line.split("=", 1) for line in result["stdout"].splitlines() if "=" in line)
    return {"systemctl_exit": result["exit_code"], "properties": fields}


def exit_receipt(evidence: Path, run_id: str, digest: str) -> dict | None:
    receipt_path = evidence.parent / "receiver-exit.json"
    if not receipt_path.exists():
        return None
    if receipt_path.stat().st_size > 4096:
        raise ValueError("REMOTE_EXIT_RECEIPT_BOUND")
    value = json.loads(receipt_path.read_text())
    if value.get("schema_version") != 1 or value.get("method") != METHOD or value.get("run_id") != run_id or value.get("receiver_sha256") != digest:
        raise ValueError("REMOTE_EXIT_RECEIPT_IDENTITY_DIFFERS")
    if value.get("service_result") not in ("success", "protocol", "timeout", "exit-code", "signal", "core-dump", "watchdog", "resources", "start-limit-hit", "oom-kill"):
        raise ValueError("REMOTE_EXIT_RECEIPT_RESULT_UNKNOWN")
    return value


def owned_unit(unit: str, digest: str, evidence: Path | None = None, run_id: str = "") -> dict:
    value = status(unit)
    fields = value["properties"]
    if fields.get("LoadState") == "not-found" and evidence:
        receipt = exit_receipt(evidence, run_id, digest)
        if receipt is not None:
            value["exit_receipt"] = receipt
            value["service_unloaded_after_exit"] = True
            return value
    if fields.get("Description") != METHOD + ":" + digest or fields.get("Transient") != "yes":
        raise ValueError("REMOTE_UNIT_OWNERSHIP_UNCONFIRMED")
    return value


def execute(request: dict) -> dict:
    if sys.platform != "linux" or os.geteuid() != 0 or request.get("schema_version") != 1:
        raise ValueError("REMOTE_CONTROL_PLATFORM_OR_SCHEMA_INVALID")
    phase = request.get("phase")
    digest = request.get("receiver_sha256", "")
    path = receiver_path(digest)
    if phase == "Deploy":
        payload = base64.b64decode(request.get("receiver_base64", ""), validate=True)
        if not 1024 <= len(payload) <= 131072 or hashlib.sha256(payload).hexdigest() != digest:
            raise ValueError("DEPLOY_PAYLOAD_INVALID")
        checked_directory(path.parent)
        if path.exists():
            verified_receiver(request)
        else:
            with path.open("xb") as stream:
                stream.write(payload)
            path.chmod(0o644)
        inspect = process(["/usr/bin/python3", "-B", str(path), "--inspect"])
        if inspect["exit_code"] != 0:
            raise ValueError("DEPLOY_RECEIVER_INSPECT_FAILED")
        observation = json.loads(inspect["stdout"])
        if observation.get("receiver_sha256") != digest or observation.get("method") != METHOD:
            raise ValueError("DEPLOY_RECEIVER_IDENTITY_DIFFERS")
        return {"status": "RECEIVER_DEPLOYED_FILES_VERIFIED", "path": str(path),
                "receiver": observation, "listener_started": False}
    verified_receiver(request)
    if phase == "Inspect":
        result = process(["/usr/bin/python3", "-B", str(path), "--inspect"])
        if result["exit_code"] != 0:
            raise ValueError("RECEIVER_INSPECT_FAILED")
        return {"status": "RECEIVER_DEPLOYMENT_OBSERVED", "receiver": json.loads(result["stdout"])}
    run_id, unit, evidence = identity(request)
    if phase == "Start":
        bind = str(ipaddress.IPv4Address(request["bind_ipv4"]))
        source = str(ipaddress.IPv4Address(request["allowed_source"]))
        if ipaddress.ip_address(bind).is_unspecified or ipaddress.ip_address(source).is_unspecified:
            raise ValueError("SPECIFIC_ADDRESS_REQUIRED")
        for name, lower, upper in (("port", 1024, 65535), ("transfer_bytes", 1, 8 * 1024 ** 3),
                ("max_connections", 1, 1024), ("max_total_connections", 1, 4096),
                ("max_duration_seconds", 1, 1800)):
            if type(request.get(name)) is not int or not lower <= request[name] <= upper:
                raise ValueError("REMOTE_START_BOUND_INVALID: " + name)
        if request["max_total_connections"] < request["max_connections"]:
            raise ValueError("REMOTE_TOTAL_LIMIT_INVALID")
        if evidence.parent.exists() or status(unit)["properties"].get("LoadState") != "not-found":
            raise ValueError("REMOTE_RUN_REQUIRES_FRESH_ID")
        started = process(["systemd-run", "--quiet", "--unit=" + unit,
            "--description=" + METHOD + ":" + digest,
            "--property=Type=exec", "--property=DynamicUser=yes", "--property=UMask=0077",
            "--property=StateDirectory=pb-testlab-cts/" + run_id,
            "--property=LimitNOFILE=2048", "--property=NoNewPrivileges=yes",
            "--property=ProtectSystem=strict", "--property=ProtectHome=yes", "--property=PrivateTmp=yes",
            "--property=IPAddressDeny=any", "--property=IPAddressAllow=" + source,
            "--property=IPAddressAllow=localhost", "--property=TimeoutStopSec=25",
            "--property=RuntimeMaxSec=" + str(request["max_duration_seconds"] + 25),
            "--property=ExecStopPost=/usr/bin/python3 -B " + str(path) + " --record-exit --run-id " + run_id + " --exit-receipt " + str(evidence.parent / "receiver-exit.json"),
            "/usr/bin/python3", "-B", str(path), "--serve", "--bind-ipv4", bind,
            "--allowed-source", source, "--port", str(request["port"]),
            "--transfer-bytes", str(request["transfer_bytes"]),
            "--max-connections", str(request["max_connections"]),
            "--max-total-connections", str(request["max_total_connections"]),
            "--max-duration-seconds", str(request["max_duration_seconds"]),
            "--run-id", run_id, "--jsonl-log", str(evidence)])
        if started["exit_code"] != 0:
            raise ValueError("REMOTE_RECEIVER_START_FAILED: " + started["stderr"][:1024])
        try:
            for _ in range(40):
                state = owned_unit(unit, digest)
                if evidence.exists():
                    with evidence.open(encoding="utf-8") as stream:
                        first = stream.readline(32769)
                    entry = json.loads(first) if first.strip() else {}
                    if entry.get("event") == "LISTENING" and entry.get("receiver_sha256") == digest:
                        if entry.get("bind_ipv4") != bind or entry.get("port") != request["port"]:
                            raise ValueError("REMOTE_LISTENER_IDENTITY_DIFFERS")
                        return {"status": "RECEIVER_LISTENING", "unit": unit, "evidence_path": str(evidence),
                                "listener": entry, "service": state, "native_client_compatibility_verified": False}
                if state["properties"].get("ActiveState") in ("failed", "inactive"):
                    break
                time.sleep(0.1)
            raise ValueError("REMOTE_RECEIVER_READINESS_NOT_CONFIRMED")
        except Exception as original:
            # Only a unit started by this request, with exact description and
            # transient ownership, can be stopped. Never stop an unrelated unit.
            try:
                owned_unit(unit, digest, evidence, run_id)
                cleanup = process(["systemctl", "stop", unit], timeout=30)
                if cleanup["exit_code"] != 0:
                    raise ValueError("REMOTE_READINESS_CLEANUP_FAILED")
            except Exception as cleanup_error:
                raise ValueError(str(original) + "; cleanup: " + str(cleanup_error)) from original
            raise
    state = owned_unit(unit, digest, evidence, run_id)
    if phase == "Status":
        return {"status": "RECEIVER_SERVICE_OBSERVED", "unit": unit, "service": state,
                "evidence_exists": evidence.is_file()}
    if phase == "Stop":
        stopped = {"exit_code": 0} if state.get("service_unloaded_after_exit") else process(["systemctl", "stop", unit], timeout=30)
        final = owned_unit(unit, digest, evidence, run_id)
        if stopped["exit_code"] != 0 or final["properties"].get("ActiveState") not in ("inactive", "failed"):
            raise ValueError("REMOTE_RECEIVER_STOP_UNCONFIRMED")
        return {"status": "RECEIVER_SERVICE_STOPPED", "unit": unit, "service": final}
    if phase == "Collect":
        if state["properties"].get("ActiveState") not in ("inactive", "failed"):
            raise ValueError("REMOTE_COLLECTION_REQUIRES_STOPPED_UNIT")
        if not evidence.is_file() or evidence.stat().st_size > 16 * 1024 * 1024:
            raise ValueError("REMOTE_EVIDENCE_MISSING_OR_BOUND")
        payload = evidence.read_bytes()
        return {"status": "RECEIVER_EVIDENCE_COLLECTED", "unit": unit, "service": state,
                "sha256": hashlib.sha256(payload).hexdigest(), "bytes": len(payload),
                "exit_receipt": exit_receipt(evidence, run_id, digest),
                "evidence_base64": base64.b64encode(payload).decode("ascii")}
    raise ValueError("REMOTE_CONTROL_PHASE_INVALID")


def main() -> int:
    try:
        raw = sys.stdin.buffer.read(262145)
        if len(raw) > 262144:
            raise ValueError("REMOTE_CONTROL_REQUEST_BOUND")
        request = json.loads(raw)
        result = execute(request)
        print(json.dumps({"schema_version": 1, **result}, separators=(",", ":")))
        return 0
    except Exception as exc:
        print(json.dumps({"schema_version": 1, "status": "REMOTE_OPERATION_FAILED",
                          "error": type(exc).__name__ + ": " + str(exc)}, separators=(",", ":")))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
