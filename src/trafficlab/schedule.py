"""Workload recipes, bounded checkpoints and resource observations for a single fresh attempt."""
from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import os
import re
import socket
import threading
import time
import uuid
from pathlib import Path
from typing import Any

from trafficlab.protocol import json_bytes, verify_mac
from trafficlab.metrics import SummaryWindow
from trafficlab.routes import stage_route
from trafficlab.resources import ResourceWindow, process_sample, system_sample
from trafficlab.worker import cancelled, connect, execute, read_result
from trafficlab.bounded_worker import execute_bounded


def atomic(path: str, value: Any) -> None:
    target = Path(path)
    temporary = target.with_name(target.name + '.' + uuid.uuid4().hex + '.tmp')
    try:
        temporary.write_bytes(json_bytes(value) + b"\n")
        for retry in range(6):
            try:
                temporary.replace(target)
                break
            except PermissionError:
                if retry == 5:
                    raise
                time.sleep(0.02 * (retry + 1))
    finally:
        temporary.unlink(missing_ok=True)


class OriginMetricsChannel:
    """One preconnected control socket, serialized between observer and final evidence.

    Every query still gets a fresh challenge, flow ID and signed response. A failed
    channel stays failed; it never reconnects through the product under measurement.
    """
    def __init__(self, job: dict[str, Any]) -> None:
        self.job = job
        self.lock = threading.Lock()
        self.socket: socket.socket | None = None

    def __enter__(self) -> OriginMetricsChannel:
        self.socket = socket.create_connection((self.job['host'], self.job.get('control_port', 42503)), timeout=10)
        try:
            origin_metrics({**self.job, '_origin_metrics_channel': self})
        except BaseException:
            self.__exit__(None, None, None)
            raise
        return self

    def __exit__(self, *_args: Any) -> None:
        with self.lock:
            if self.socket is not None:
                self.socket.close()
                self.socket = None


def origin_metrics(job: dict[str, Any]) -> dict[str, Any]:
    channel = job.get('_origin_metrics_channel')
    if channel is None:
        return _origin_metrics(job)
    with channel.lock:
        if channel.socket is None:
            raise ValueError('TRAFFIC_ORIGIN_CONTROL_CHANNEL_CLOSED')
        try:
            return _origin_metrics(job, channel.socket)
        except BaseException:
            channel.socket.close()
            channel.socket = None
            raise


def verified_origin_snapshot(job: dict[str, Any], snapshot: dict[str, Any]) -> dict[str, Any]:
    value = dict(snapshot)
    authentication = value.pop('authentication')
    context = bytes.fromhex(authentication['context_hex'])
    request = json.loads(context[64:])
    if request.get('run_id') != job['run_id'] or request.get('task') != 'metrics':
        raise ValueError('TRAFFIC_ORIGIN_SNAPSHOT_SCOPE_INVALID')
    verify_mac(bytes.fromhex(job['secret']), b'result:', context + json_bytes(value), authentication['proof'])
    validate_origin_identity(job, value)
    return value


def validate_origin_identity(job: dict[str, Any], result: dict[str, Any]) -> None:
    expected = job.get('remote_bundle_sha256')
    if expected and (not result.get('identity', {}).get('verified') or result['identity'].get('bundle_sha256') != expected):
        raise ValueError('TRAFFIC_REMOTE_ARTIFACT_IDENTITY_CHANGED')
    for field, name, error in (('application_tls_sha256', 'tls_certificate_sha256', 'APPLICATION_TLS_IDENTITY_CHANGED'),
                              ('application_ssh_sha256', 'ssh_host_key_sha256', 'APPLICATION_SSH_HOST_KEY_CHANGED')):
        if job.get(field) and result.get('identity', {}).get('application', {}).get(name) != job[field]:
            raise ValueError(error)


def _origin_metrics(job: dict[str, Any], connection: socket.socket | None = None) -> dict[str, Any]:
    binding = {**job, "seconds": 0.05, "port": job.get("control_port", 42503)}
    binding.pop("test_proxy", None)
    sock, stream, context, _ready = connect(binding, "metrics", str(uuid.uuid4()), connection=connection)
    try:
        result = read_result(job, stream, context)
        validate_origin_identity(job, result)
        return result
    finally:
        stream.close()
        if connection is None:
            sock.close()


def origin_evidence_error(error: Exception) -> dict[str, Any]:
    code = str(error) if isinstance(error, ValueError) and re.fullmatch(r'(?:TRAFFIC|APPLICATION)_[A-Z0-9_]+', str(error)) else 'TRAFFIC_ORIGIN_METRICS_UNAVAILABLE'
    return {'code': code, 'exception_type': type(error).__name__,
            'errno': getattr(error, 'errno', None), 'winerror': getattr(error, 'winerror', None)}


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
                **({'rate_exchanges_per_second':100} if task == 'echo' and job.get('native_worker_port') else {}),
                "message_bytes": 512, "rate_packets_per_second": pps, **extra}
    def phase(name: str, *workloads: dict[str, Any]) -> dict[str, Any]:
        return {"phase": name, "workloads": list(workloads)}
    baseline = phase("baseline", workload("echo"))
    recovery = phase("recovery", workload("echo"))
    recipe = case["recipe"]
    if recipe == "application":
        sizes = case.get('payload_sizes',[512])
        if not isinstance(sizes,list) or not 1<=len(sizes)<=4 or any(type(value) is not int or not 1<=value<=4096 for value in sizes) or len(set(sizes))!=len(sizes) or \
            ('payload_sizes' in case and case['application'] not in ('http','https','http2','websocket-tls','http3')):
            raise ValueError('TRAFFIC_CATALOG_PAYLOAD_PROFILE_INVALID')
        return [phase(f"{case['application']}-payload-{size}" if 'payload_sizes' in case else case['application'],
                      workload("udp" if case["application"] in ("dns-udp", "quic", "http3") else "echo", n,
                      application=case["application"], warmup_count=0,grpc_mode=case.get('grpc_mode','unary'),
                      quic_mode=case.get('quic_mode','single'),message_bytes=size)) for size in sizes]
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
        "origin_metrics_transport": "preconnected-authenticated-control-v1" if job.get('_origin_metrics_channel') else "per-query-authenticated-control-v1",
        "errors": [], "stage_count": len(stages), "skipped_stage_count": 0,
        "workload_started_stage_count": 0,
        "udp_expected": any(workload['task']=='udp' for stage in stages for workload in stage['workloads']),
        "ip_family": "IPv6" if ":" in job["host"] else "IPv4"}
    started = time.perf_counter()
    resources = ResourceWindow()
    monitor_stop = threading.Event()
    observations_lock = threading.Lock()
    current: dict[str, Any] = {"job": job, "origin": None, "phase_resources":None}
    isolated_worker = any(workload.get('application') in ('ssh', 'sftp') for stage in stages for workload in stage['workloads'])
    native_transport = bool(job.get('native_worker_port')) and not any(workload.get('application') for stage in stages for workload in stage['workloads'])
    progress_lock = threading.Lock()
    progress_state: dict[str, Any] = {'run_id':job['run_id'], 'state':'PREPARING', 'total':len(stages),
                                     'stage_run_id':None, 'live_origin':None}
    def publish_progress(observed_run_id: str | None=None, **changes: Any) -> None:
        # The monitor and coordinator share one atomic writer. An observation from
        # the previous stage may finish late; it must never be attributed to the next.
        with progress_lock:
            if observed_run_id is not None and (progress_state['state']!='RUNNING' or progress_state['stage_run_id']!=observed_run_id):
                return
            progress_state.update(changes)
            atomic(progress,{**progress_state,'elapsed_seconds':time.perf_counter()-started,
                             'emitted_at_unix_seconds':time.time()})
    def monitor() -> None:
        while not monitor_stop.is_set():
            with observations_lock:
                observed_job = current['job']
                phase_resources = current['phase_resources']
            stamp = time.perf_counter() - started
            samples = {"windows_system" if os.name == "nt" else "worker_system": system_sample()}
            if isolated_worker:
                with observations_lock:
                    child = dict(current['job'].get('_worker_process', {}))
                if child.get('pid') and not child.get('finished'):
                    samples['worker'] = process_sample(child['pid'], child['path'])
            elif native_transport:
                samples['worker'] = process_sample(job['native_worker_pid'], job['native_worker_executable'])
                samples['protocol_controller'] = process_sample(os.getpid())
            else:
                samples['worker'] = process_sample(os.getpid())
            for role, binding in job.get("resource_processes", {}).items():
                samples[role] = process_sample(int(binding["pid"]), binding.get("path"))
            live_origin: dict[str, Any] = {'available':False}
            try:
                remote = origin_metrics(observed_job)
                samples["origin_and_proxy"] = {**remote["resources"], "cpu_count": remote["cpu_count"]}
                samples["origin_system"] = remote["system_resources"]
                with observations_lock:
                    current["origin"] = remote
                def count(value: Any) -> int | None:
                    return value if type(value) is int and value>=0 else None
                transactions = [flow.get('transactions') for flow in remote.get('application_flows',{}).values()]
                live_origin = {'available':True, 'scope':'signed-origin-session-counters; not-final-client-verification',
                    'observed_at_elapsed_seconds':time.perf_counter()-started,
                    'observed_at_unix_seconds':time.time(),
                    **{key:count(remote.get(key)) for key in ('rx_bytes','tx_bytes','active','completed')},
                    'application_transactions':sum(transactions) if all(count(value) is not None for value in transactions) else None}
            except (OSError, ValueError, KeyError, EOFError) as error:
                live_origin['error'] = origin_evidence_error(error)
                samples["origin_and_proxy"] = {"available": False}
                samples["origin_system"] = {"available": False}
            with observations_lock:
                for role, sample in samples.items():
                    resources.add(role, stamp, sample)
                    if phase_resources is not None and phase_resources is current['phase_resources'] and observed_job is current['job']:
                        phase_resources.add(role, time.perf_counter() - started, sample)
            try:
                publish_progress(observed_job['run_id'],live_origin=live_origin)
            except OSError:
                pass  # Main coordinator writes still fail the attempt on storage failure.
            monitor_stop.wait(1)
    observer = threading.Thread(target=monitor, name="traffic-resource-observer", daemon=True)
    observer.start()
    journal = None
    journal_digest = hashlib.sha256()
    compact = job["case_id"] == "soak"
    totals = SummaryWindow()
    context = {"operation":"PREPARING_REPORT", "stage":None, "index":None}
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
            if isolated_worker:
                stage_job.update(_worker_directory=str(Path(output).parent), _worker_process={})
            context = {"operation":"REGISTERING_SESSION", "stage":stage['phase'], "index":index}
            publish_progress(state='RUNNING',stage=stage['phase'],index=index,stage_run_id=stage_job['run_id'],
                             operation=context['operation'],live_origin=None)
            if any(workload.get("application") for workload in stage["workloads"]):
                registration = origin_metrics(stage_job)  # Register before native DNS encodes its opaque run tag.
                if isolated_worker:
                    stage_job['_isolated_origin_evidence'] = registration
            with observations_lock:
                current["job"] = stage_job
                phase_resources = ResourceWindow()
                current['phase_resources'] = phase_resources
                def sample_phase_endpoints():
                    stamp = time.perf_counter() - started
                    phase_resources.add('windows_system' if os.name == 'nt' else 'worker_system', stamp, system_sample())
                    for role, process in job.get('resource_processes', {}).items():
                        phase_resources.add(role, stamp, process_sample(int(process['pid']), process.get('path')))
                sample_phase_endpoints()
            phase_started = time.perf_counter()
            with concurrent.futures.ThreadPoolExecutor(max_workers=len(stage["workloads"])) as pool:
                context['operation'] = 'RUNNING_WORKLOAD'
                publish_progress(operation=context['operation'])
                report['workload_started_stage_count'] += 1
                futures = [pool.submit(execute_bounded if workload.get('application') in ('ssh', 'sftp') else execute,
                                       {**stage_job, **workload}) for workload in stage["workloads"]]
                results = [future.result() for future in futures]
            with observations_lock:
                sample_phase_endpoints()
                current['phase_resources'] = None
                phase_samples = {role:{key:value for key,value in row.items() if key != 'timeline'} for role,row in phase_resources.view().items() if role in ('product_cli','windows_system','worker_system')}
            context['operation'] = 'COLLECTING_EVIDENCE'
            publish_progress(operation=context['operation'])
            evidence_error = None
            try:
                origin = origin_metrics(stage_job)
                release_deadline = time.perf_counter() + 2
                while (origin["active"] or origin.get("proxy", {}).get("tcp_active", 0)) and time.perf_counter() < release_deadline:
                    time.sleep(0.02)
                    origin = origin_metrics(stage_job)
            except (OSError, ValueError, KeyError, EOFError) as error:
                origin = None
                evidence_error = origin_evidence_error(error)
            stage_value = {"phase": stage["phase"], "elapsed_seconds": time.perf_counter() - phase_started,
                                      "phase_resources":phase_samples,
                                      "workload_profiles":[{'task':w['task'], 'application':w.get('application'), 'connections':w['connections'],
                                          'seconds':w['seconds'], 'target_per_flow':w.get('rate_packets_per_second') if w.get('application') or w['task']=='udp' else w.get('rate_exchanges_per_second')} for w in stage['workloads']],
                                      "results": results, "origin": origin, "origin_evidence_error": evidence_error,
                                      "complete": origin is not None and origin["active"] == 0 and origin.get("proxy", {}).get("tcp_active", 0) == 0 and all(row["complete"] for row in results)}
            route_verified = stage_route(stage_value, expected_proxy)
            from trafficlab.comparison_quality import stage_quality
            stage_value['comparison_quality'] = stage_quality(stage_value, expected_proxy, route_verified)
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
            context['operation'] = 'WRITING_REPORT'
            publish_progress(operation=context['operation'])
            atomic(output, report)
            # Preserve the failed stage, skip further load and still measure recovery when available.
        report["cancelled"] = cancelled(job)
        report["complete"] = not report["cancelled"] and not recovery_only and len(report["stages"]) == len(stages) and all(stage["complete"] for stage in report["stages"])
    except Exception as error:
        report['failure_context'] = dict(context)
        report['failure_detail'] = {'exception_type': type(error).__name__, 'errno': getattr(error, 'errno', None),
                                  'winerror': getattr(error, 'winerror', None), 'filename': str(getattr(error, 'filename', '') or '')}
        report["errors"].append(type(error).__name__ + ":TRAFFIC_SCHEDULE_FAILED")
    finally:
        if journal is not None:
            journal.close()
        monitor_stop.set()
        observer.join(timeout=12)
        with observations_lock:
            report["resources"] = resources.view()
        report["elapsed_seconds"] = time.perf_counter() - started
        report['unstarted_stage_count'] = len(stages)-report['workload_started_stage_count']
        atomic(output, report)
        publish_progress(state="COMPLETE" if report["complete"] else "CANCELLED" if report["cancelled"] else "FAILED",
                         completed_stages=len(report['stages']),live_origin=None)
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
