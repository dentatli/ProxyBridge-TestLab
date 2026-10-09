"""Workload recipes, bounded checkpoints and resource observations for a single fresh attempt."""
from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import os
import threading
import time
import uuid
from pathlib import Path
from typing import Any

from trafficlab.protocol import json_bytes
from trafficlab.metrics import SummaryWindow
from trafficlab.routes import stage_route
from trafficlab.resources import ResourceWindow, process_sample, system_sample
from trafficlab.worker import cancelled, connect, execute, read_result


def atomic(path: str, value: Any) -> None:
    target = Path(path)
    temporary = target.with_suffix(target.suffix + ".tmp")
    temporary.write_bytes(json_bytes(value) + b"\n")
    temporary.replace(target)


def origin_metrics(job: dict[str, Any]) -> dict[str, Any]:
    binding = {**job, "seconds": 0.05, "port": job.get("control_port", 42503)}
    binding.pop("test_proxy", None)
    sock, stream, context, _ready = connect(binding, "metrics", str(uuid.uuid4()))
    try:
        result = read_result(job, stream, context)
        expected = job.get("remote_bundle_sha256")
        if expected and (not result.get("identity", {}).get("verified") or result["identity"].get("bundle_sha256") != expected):
            raise ValueError("TRAFFIC_REMOTE_ARTIFACT_IDENTITY_CHANGED")
        return result
    finally:
        stream.close()
        sock.close()


def recipes(job: dict[str, Any], catalog: dict[str, Any]) -> list[dict[str, Any]]:
    if catalog.get("schema_version") != 1 or catalog.get("method") != "controlled-traffic-v1":
        raise ValueError("TRAFFIC_CATALOG_INVALID")
    case = next((case for case in catalog["cases"] if case["id"] == job["case_id"]), None)
    if case is None:
        raise ValueError("TRAFFIC_CASE_UNKNOWN")
    duration = catalog["duration_seconds"][job["duration"]]
    load = catalog["loads"][job["load"]]
    n = load["connections"]
    pps = load["packets_per_second"]
    def workload(task: str, connections: int = 1, **extra: Any) -> dict[str, Any]:
        return {"task": task, "connections": connections, "seconds": duration, "warmup_count": job.get("warmup_count", 10),
                "message_bytes": 512, "rate_packets_per_second": pps, **extra}
    def phase(name: str, *workloads: dict[str, Any]) -> dict[str, Any]:
        return {"phase": name, "workloads": list(workloads)}
    baseline = phase("baseline", workload("echo"))
    recovery = phase("recovery", workload("echo"))
    recipe = case["recipe"]
    if recipe in ("echo", "upload", "download", "duplex"):
        return [phase(recipe, workload(recipe, (1 if job["load"] == "LOW" else 4) if recipe == "echo" else n))]
    if recipe == "multistream":
        return [phase(f"streams-{count}", workload("duplex", count)) for count in (1, max(2, n // 4), n)]
    if recipe == "loaded":
        return [baseline, phase("loaded", workload("duplex", n), workload("echo")), recovery]
    if recipe == "connections":
        return [baseline] + [phase(f"connections-{count}", workload("hold", count, warmup_count=0), workload("echo"))
                             for count in load["connection_steps"]] + [recovery]
    if recipe == "flow_rate":
        return [baseline, phase("churn", workload("flow_rate", load["flow_workers"])), recovery]
    if recipe in ("udp", "udp_unconnected"):
        return [phase(recipe, workload("udp", n, udp_connected=recipe == "udp"))]
    if recipe == "udp_sweep":
        return [phase(f"udp-{size}-{rate}", workload("udp", n, message_bytes=size, rate_packets_per_second=rate))
                for size in (64, 512, 1400) for rate in (pps, pps * 2)]
    if recipe == "udp_connections":
        return [phase("baseline", workload("udp"))] + [phase(f"udp-flows-{count}", workload("udp", count))
                for count in load["connection_steps"]] + [phase("recovery", workload("udp"))]
    if recipe == "mixed":
        return [baseline, phase("mixed", workload("duplex", n), workload("udp", n), workload("echo")), recovery]
    if recipe in ("stability", "soak"):
        count = 8 if recipe == "stability" else {"SHORT": 24, "NORMAL": 48, "LONG": 72}[job["duration"]] * 60
        segment = duration if recipe == "stability" else 60
        stages = [baseline]
        for index in range(count):
            # Each signed session has a bounded number of UDP flows; a fresh ID per interval avoids saturation.
            stages.append(phase(f"interval-{index + 1}", workload("duplex", n, seconds=segment),
                                workload("udp", n, seconds=segment), workload("echo", seconds=segment)))
        return stages + [recovery]
    raise ValueError("TRAFFIC_RECIPE_UNKNOWN")


def run(job: dict[str, Any], catalog: dict[str, Any], output: str, progress: str) -> dict[str, Any]:
    stages = recipes(job, catalog)
    report: dict[str, Any] = {"schema_version": 1, "method": "controlled-traffic-v1", "run_id": job["run_id"],
        "case_id": job["case_id"], "duration": job["duration"], "load": job["load"], "complete": False,
        "cancelled": False, "stages": [], "product_route_confirmed": False,
        "resource_scope": "identified-processes-and-separate-whole-OS-counters", "attempt_policy": "fresh-no-resume",
        "errors": [], "stage_count": len(stages), "skipped_stage_count": 0,
        "ip_family": "IPv6" if ":" in job["host"] else "IPv4"}
    started = time.perf_counter()
    resources = ResourceWindow()
    monitor_stop = threading.Event()
    observations_lock = threading.Lock()
    current: dict[str, Any] = {"job": job, "origin": None}
    def monitor() -> None:
        while not monitor_stop.is_set():
            stamp = time.perf_counter() - started
            samples = {"worker": process_sample(os.getpid()), "windows_system" if os.name == "nt" else "worker_system": system_sample()}
            for role, binding in job.get("resource_processes", {}).items():
                samples[role] = process_sample(int(binding["pid"]), binding.get("path"))
            try:
                remote = origin_metrics(current["job"])
                samples["origin_and_proxy"] = {**remote["resources"], "cpu_count": remote["cpu_count"]}
                samples["origin_system"] = remote["system_resources"]
                with observations_lock:
                    current["origin"] = remote
            except (OSError, ValueError, KeyError, EOFError):
                samples["origin_and_proxy"] = {"available": False}
                samples["origin_system"] = {"available": False}
            with observations_lock:
                for role, sample in samples.items():
                    resources.add(role, stamp, sample)
            monitor_stop.wait(1)
    observer = threading.Thread(target=monitor, name="traffic-resource-observer", daemon=True)
    observer.start()
    journal = None
    journal_digest = hashlib.sha256()
    compact = job["case_id"] == "soak"
    totals = SummaryWindow()
    if compact:
        report.update(compact_stages=True, expected_proxy=bool(job.get("expected_proxy", job.get("test_proxy"))),
                      stage_journal_sha256=journal_digest.hexdigest(), overall=totals.view())
    try:
        if compact:
            journal = open(output + ".stages.jsonl", "xb")  # Fresh attempt only; preserve previous journals.
        atomic(output, report)
        recovery_only = False
        expected_proxy = bool(job.get("expected_proxy", job.get("test_proxy")))
        for index, stage in enumerate(stages):
            if cancelled(job):
                break
            if recovery_only and stage["phase"] != "recovery":
                report["skipped_stage_count"] += 1
                continue
            stage_job = {**job, "run_id": f"{job['run_id']}.{index}"}
            current["job"] = stage_job
            atomic(progress, {"run_id": job["run_id"], "stage": stage["phase"], "index": index, "total": len(stages),
                              "elapsed_seconds": time.perf_counter() - started, "state": "RUNNING"})
            phase_started = time.perf_counter()
            with concurrent.futures.ThreadPoolExecutor(max_workers=len(stage["workloads"])) as pool:
                futures = [pool.submit(execute, {**stage_job, **workload}) for workload in stage["workloads"]]
                results = [future.result() for future in futures]
            try:
                origin = origin_metrics(stage_job)
                release_deadline = time.perf_counter() + 2
                while (origin["active"] or origin.get("proxy", {}).get("tcp_active", 0)) and time.perf_counter() < release_deadline:
                    time.sleep(0.02)
                    origin = origin_metrics(stage_job)
            except (OSError, ValueError, KeyError, EOFError):
                origin = None
            stage_value = {"phase": stage["phase"], "elapsed_seconds": time.perf_counter() - phase_started,
                                      "results": results, "origin": origin,
                                      "complete": origin is not None and origin["active"] == 0 and origin.get("proxy", {}).get("tcp_active", 0) == 0 and all(row["complete"] for row in results)}
            route_verified = stage_route(stage_value, expected_proxy)
            loss_ok = all(flow.get("loss_fraction") is None or flow["loss_fraction"] <= 0.01
                          for result in results if result["task"] == "udp" for flow in result["flows"])
            if not stage_value["complete"] or not route_verified or not loss_ok:
                recovery_only = True
                if "TRAFFIC_LOAD_HALTED_AFTER_STAGE_FAILURE" not in report["errors"]:
                    report["errors"].append("TRAFFIC_LOAD_HALTED_AFTER_STAGE_FAILURE")
            if compact:
                record = json_bytes(stage_value) + b"\n"
                journal.write(record)
                journal.flush()
                os.fsync(journal.fileno())
                journal_digest.update(record)
                row = totals.add(stage_value)
                row["route_verified"] = route_verified
                report["stages"].append(row)
                report["stage_journal_sha256"] = journal_digest.hexdigest()
                report["overall"] = totals.view()
            else:
                report["stages"].append(stage_value)
            with observations_lock:
                report["resources"] = resources.view()
            report["elapsed_seconds"] = time.perf_counter() - started
            atomic(output, report)
            # Preserve the failed stage, skip further load and still measure recovery when available.
        report["cancelled"] = cancelled(job)
        report["complete"] = not report["cancelled"] and not recovery_only and len(report["stages"]) == len(stages) and all(stage["complete"] for stage in report["stages"])
    except Exception as error:
        report["errors"].append(type(error).__name__ + ":TRAFFIC_SCHEDULE_FAILED")
    finally:
        if journal is not None:
            journal.close()
        monitor_stop.set()
        observer.join(timeout=12)
        with observations_lock:
            report["resources"] = resources.view()
        report["elapsed_seconds"] = time.perf_counter() - started
        atomic(output, report)
        atomic(progress, {"run_id": job["run_id"], "state": "COMPLETE" if report["complete"] else "CANCELLED" if report["cancelled"] else "FAILED",
                          "elapsed_seconds": report["elapsed_seconds"], "completed_stages": len(report["stages"]), "total": len(stages)})
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    for name in ("job", "catalog", "output", "progress"):
        parser.add_argument("--" + name, required=True)
    args = parser.parse_args()
    try:
        job = json.loads(Path(args.job).read_text(encoding="utf-8-sig"))
        catalog = json.loads(Path(args.catalog).read_text(encoding="utf-8-sig"))
        report = run(job, catalog, args.output, args.progress)
        print(json_bytes({"run_id": report["run_id"], "complete": report["complete"], "cancelled": report["cancelled"]}).decode())
        return 0 if report["complete"] else 1
    except (OSError, ValueError, KeyError):
        print("TRAFFIC_SCHEDULE_CONFIGURATION_INVALID")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
