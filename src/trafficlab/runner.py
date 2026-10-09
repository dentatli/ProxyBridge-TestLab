"""Real product attempt: OFF/UNRULED controls, authenticated route and owned cleanup."""
from __future__ import annotations

import argparse
import json
import os
import platform
import subprocess
import time
from pathlib import Path
from typing import Any

from trafficlab.product import Product
from trafficlab.protocol import mac
from trafficlab.metrics import summary
from trafficlab.routes import stage_route
from trafficlab.schedule import atomic, run
from trafficlab.worker import cancelled


def idle(binding_path: str, binding: dict[str, Any], restore_owned: bool = False) -> dict[str, Any]:
    script = Path(binding["root"]) / "scripts" / "Assert-TrafficLabIdle.ps1"
    arguments = ["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(script), "-BindingPath", binding_path]
    if restore_owned:
        arguments.append("-RestoreOwnedDriver")
    result = subprocess.run(arguments, capture_output=True, timeout=35, creationflags=subprocess.CREATE_NO_WINDOW)
    if result.returncode or len(result.stdout) > 16384:
        raise ValueError("TRAFFIC_PRODUCT_OFF_NOT_VERIFIED")
    value = json.loads(result.stdout.decode("utf-8-sig"))
    if value.get("off_verified") is not True:
        raise ValueError("TRAFFIC_PRODUCT_OFF_NOT_VERIFIED")
    return value


def ownership(binding_path: str, binding: dict[str, Any], product: Product) -> None:
    atomic(str(Path(binding_path).parent / "driver-ownership.json"), {"id": binding["id"], "off_before": True,
        "driver_sha256": binding["driver_sha256"], "cli_ready": product.evidence["ready"], "cli_cleanup_verified": product.evidence["cleanup_verified"]})


def validate_route(report: dict[str, Any], proxied: bool) -> bool:
    if not report["complete"]:
        return False
    if report.get("compact_stages"):
        return report["expected_proxy"] == proxied and all(stage["route_verified"] for stage in report["stages"])
    return all(stage_route(stage, proxied) for stage in report["stages"])


def profile(binding: dict[str, Any], run_id: str, mode: str) -> dict[str, Any]:
    return {"Version": "1.0", "LocalhostViaProxy": True, "IsTrafficLoggingEnabled": True,
        "ProxyConfigs": [{"Id": 1, "Name": "TestLab traffic", "Type": "SOCKS5", "Host": binding["host"], "Port": binding["proxy_port"],
            "Username": run_id, "Password": mac(bytes.fromhex(binding["secret"]), b"socks:", run_id.encode()), "SendDomainToProxy": False}],
        "ProxyRules": [{"Name": "Controlled traffic", "ProcessName": Path(binding["python"]).name if mode == "SOCKS5" else "pb-unruled-control-never.exe",
            "TargetHosts": binding["host"], "TargetPorts": str(binding["port"]), "TargetDomains": "", "Protocol": "BOTH", "Action": "PROXY", "ProxyConfigId": 1, "IsEnabled": True}]}


def attempt(binding_path: str, binding: dict[str, Any], case: dict[str, Any], output: str, progress: str) -> dict[str, Any]:
    directory = Path(output).parent
    catalog = json.loads((Path(binding["root"]) / "config" / "traffic-workloads.json").read_text(encoding="utf-8-sig"))
    run_id = binding["id"] + "." + case["case_id"]
    job = {**binding, **case, "run_id": run_id}
    job.pop("cases", None)
    result: dict[str, Any] = {"case_id": case["case_id"], "duration": case["duration"], "load": case["load"], "complete": False,
        "cancelled": False, "cleanup_verified": False, "product_route_confirmed": False, "errors": [], "measurements": [], "controls": [],
        "conditions": {"build_sha256": binding["build_sha256"], "remote_bundle_sha256": binding["remote_bundle_sha256"],
            "host_binding": __import__("hashlib").sha256(binding["host"].encode()).hexdigest(), "python_version": platform.python_version(),
            "windows_version": platform.version(), "logical_cpus": os.cpu_count(), "method": "controlled-traffic-v1"}}
    result["conditions"]["local_runtime_sha256"] = binding.get("local_runtime_sha256")
    result["conditions"]["windows_node_binding"] = __import__("hashlib").sha256(platform.node().encode()).hexdigest()
    result["conditions"]["cpu_model"] = os.environ.get("PROCESSOR_IDENTIFIER", "unknown")
    started = time.monotonic()
    product = None
    raw = directory / (case["case_id"] + ".raw.json")
    private_profile = directory / (case["case_id"] + ".profile-private.json")
    try:
        result["off_before"] = idle(binding_path, binding)
        short_catalog = {**catalog, "duration_seconds": {**catalog["duration_seconds"], "SHORT": 0.2}}
        control = {**job, "run_id": run_id + ".off", "case_id": "tcp-rtt", "duration": "SHORT", "load": "LOW", "warmup_count": 0, "expected_proxy": False}
        observed = run(control, short_catalog, str(directory / (case["case_id"] + ".OFF-control.raw.json")), progress)
        result["controls"].append({"mode":"OFF", "complete":observed["complete"], "route_verified":validate_route(observed,False), **summary(observed)})
        if not validate_route(observed, False):
            raise ValueError("TRAFFIC_DIRECT_CONTROL_FAILED")
        result["off_control_verified"] = True
        result["conditions"]["origin_logical_cpus"] = observed["stages"][0]["origin"]["cpu_count"]
        result["conditions"]["origin_physical_memory_bytes"] = observed["stages"][0]["origin"]["system_resources"].get("physical_total_bytes")
        from trafficlab.resources import system_sample
        result["conditions"]["windows_physical_memory_bytes"] = system_sample().get("physical_total_bytes")
        atomic(str(private_profile), profile(binding, run_id, "UNRULED"))
        product = Product(binding, str(private_profile))
        with product:
            control["run_id"] = run_id + ".unruled"
            control["resource_processes"] = {"product_cli": {"pid": product.pid, "path": binding["cli"]}}
            observed = run(control, short_catalog, str(directory / (case["case_id"] + ".UNRULED-control.raw.json")), progress)
            result["controls"].append({"mode":"UNRULED", "complete":observed["complete"], "route_verified":validate_route(observed,False), **summary(observed)})
            if not validate_route(observed, False):
                raise ValueError("TRAFFIC_UNRULED_CONTROL_FAILED")
        result["unruled_lifecycle"] = product.evidence
        if not product.evidence["cleanup_verified"]:
            raise ValueError("TRAFFIC_UNRULED_CLEANUP_FAILED")
        ownership(binding_path, binding, product)
        result["off_between"] = idle(binding_path, binding, True)
        if cancelled(job):
            return result
        modes = ("OFF", "UNRULED", "SOCKS5") if case["case_id"] == "three-modes" else ("SOCKS5",)
        for mode in modes:
            raw = directory / (case["case_id"] + "." + mode + ".raw.json")
            idle(binding_path, binding)
            measured_job = {**job, "run_id": run_id + "." + mode, "case_id": "tcp-rtt" if case["case_id"] == "three-modes" else case["case_id"], "expected_proxy": mode == "SOCKS5"}
            if mode == "OFF":
                measured = run(measured_job, catalog, str(raw), progress)
                lifecycle = {"product_started": False, "cleanup_verified": True, "route_events": {}}
            else:
                atomic(str(private_profile), profile(binding, run_id, mode))
                product = Product(binding, str(private_profile))
                with product:
                    measured_job["resource_processes"] = {"product_cli": {"pid": product.pid, "path": binding["cli"]}}
                    measured = run(measured_job, catalog, str(raw), progress)
                lifecycle = product.evidence
                ownership(binding_path, binding, product)
            gate = idle(binding_path, binding, mode != "OFF")
            route = validate_route(measured, mode == "SOCKS5") and (mode == "OFF" or lifecycle["route_events"].get("PROXY" if mode == "SOCKS5" else "DIRECT", 0) > 0)
            loss_ok = all(stage["max_udp_flow_loss_fraction"] is None or stage["max_udp_flow_loss_fraction"] <= 0.01 for stage in measured["stages"]) if measured.get("compact_stages") else all(
                flow.get("loss_fraction", 0) is None or flow.get("loss_fraction", 0) <= 0.01 for stage in measured["stages"] for row in stage["results"] for flow in row["flows"])
            capture_ok = mode == "OFF" or lifecycle.get("capture_complete") is True
            for failed, code in ((not measured["complete"], "TRAFFIC_TRANSPORT_INCOMPLETE"), (not route, "TRAFFIC_ROUTE_UNVERIFIED"),
                                 (not loss_ok, "TRAFFIC_UDP_LOSS_THRESHOLD_EXCEEDED"), (not capture_ok, "TRAFFIC_CLI_CAPTURE_INCOMPLETE")):
                if failed and code not in result["errors"]:
                    result["errors"].append(code)
            result["measurements"].append({"mode": mode, "complete": measured["complete"] and route and loss_ok and capture_ok and lifecycle["cleanup_verified"],
                "raw_evidence_sha256": __import__("hashlib").sha256(raw.read_bytes()).hexdigest(),
                "transport_complete": measured["complete"], "route_verified": route, "loss_threshold_fraction": 0.01,
                "loss_threshold_met": loss_ok, "lifecycle": lifecycle, "off_after": gate, **summary(measured)})
            if not lifecycle["cleanup_verified"]:
                raise ValueError("TRAFFIC_CONTROLLED_SHUTDOWN_FAILED")
            if cancelled(job):
                break
        result["complete"] = len(result["measurements"]) == len(modes) and all(row["complete"] for row in result["measurements"])
        result["product_route_confirmed"] = result["complete"] and any(row["mode"] == "SOCKS5" and row["route_verified"] for row in result["measurements"])
    except Exception as error:
        code = str(error) if isinstance(error, ValueError) and str(error).startswith("TRAFFIC_") else "TRAFFIC_ATTEMPT_FAILED"
        result["errors"].append(code)
        result["exception_type"] = type(error).__name__
        if product is not None:
            result["last_lifecycle"] = product.evidence
    finally:
        private_profile.unlink(missing_ok=True)
        try:
            if product is not None and product.evidence["ready"] and product.evidence["cleanup_verified"]:
                ownership(binding_path, binding, product)
            result["off_after_attempt"] = idle(binding_path, binding, product is not None and product.evidence["ready"] and product.evidence["cleanup_verified"])
            result["cleanup_verified"] = product is None or product.evidence["cleanup_verified"]
        except (OSError, ValueError, subprocess.TimeoutExpired):
            result["errors"].append("TRAFFIC_CLEANUP_OR_REBOOT_REQUIRED")
        result["cancelled"] = cancelled(job)
        result["complete"] = result["complete"] and result["cleanup_verified"] and not result["cancelled"]
        result["elapsed_seconds"] = time.monotonic() - started
        atomic(output, result)
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    for name in ("binding", "case", "output", "progress"):
        parser.add_argument("--" + name, required=True)
    args = parser.parse_args()
    binding = json.loads(Path(args.binding).read_text(encoding="utf-8-sig"))
    case = next(row for row in binding["cases"] if row["case_id"] == args.case)
    result = attempt(args.binding, binding, case, args.output, args.progress)
    return 0 if result["complete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
