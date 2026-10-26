"""All-sample latency and payload summaries, separate from product lifecycle."""
from __future__ import annotations
import math
from typing import Any
from trafficlab.protocol import Histogram


def execution_evidence(report: dict[str, Any]) -> dict[str, Any]:
    from trafficlab.comparison_quality import report_quality, workload_resources
    started = report.get('workload_started_stage_count')
    stages = report.get('stages',[])
    state = 'COMPLETED' if report.get('complete') is True else 'NOT_STARTED' if type(started) is int and started==0 else \
        'PARTIAL' if (type(started) is int and started>0) or stages else 'UNKNOWN'
    return {'measurement_state':state, 'planned_stage_count':report.get('stage_count'),
            'comparison_quality':report_quality(report),
            'kernel_resources':report.get('kernel_resources'),
            'workload_resources':workload_resources(report.get('stages', [])),
            'origin_metrics_transport':report.get('origin_metrics_transport'),
            'workload_started_stage_count':started, 'recorded_stage_count':len(stages),
            'unstarted_stage_count':report.get('unstarted_stage_count'),
            'failure_context':report.get('failure_context')}


UDP_COUNTERS = ("sent", "received", "duplicates", "reordered", "invalid", "expired", "send_errors")


def udp_observations(values: list[dict[str, Any]]) -> dict[str, Any]:
    """Native datagram replies only; application clients have different evidence."""
    flows = [flow for row in values if row['task'] == 'udp' and not row.get('application') for flow in row['flows']]
    def rates(key):
        return [flow[key] for flow in flows if type(flow.get(key)) in (int, float) and math.isfinite(flow[key])]
    achieved, requested = rates('achieved_send_packets_per_second'), rates('requested_send_packets_per_second')
    return {"flow_count": len(flows), "scope": "native-authenticated-UDP-replies; bounded-replay-window; 2s-deadline",
            "send_rate_scope": "packets/s-per-flow; requested-workload-window; excludes-setup-and-drain",
            "achieved_pps_per_flow_min": min(achieved) if achieved and len(achieved) == len(flows) else None,
            "achieved_pps_per_flow_max": max(achieved) if achieved and len(achieved) == len(flows) else None,
            "requested_pps_per_flow": requested[0] if requested and len(requested) == len(flows) and len(set(requested)) == 1 else None,
            **{key: sum(flow.get(key, 0) for flow in flows) if flows else None for key in UDP_COUNTERS}}


def phase_observations(stages: list[dict[str, Any]]) -> dict[str, Any]:
    """Describe recorded phase windows without averaging stage percentiles."""
    groups = {}
    def finite(value: Any) -> bool:
        return type(value) in (int, float) and math.isfinite(value) and value >= 0
    for name in ("baseline", "workload", "recovery"):
        rows = [row for row in stages if (row['phase'] if row['phase'] in ('baseline', 'recovery') else 'workload') == name]
        elapsed = sum(row['elapsed_seconds'] for row in rows)
        measured = [row['probe_p99_ms'] for row in rows if finite(row.get('probe_p99_ms'))]
        group = {"recorded_stages": len(rows), "completed_stages": sum(row.get('complete') is True for row in rows),
                 "elapsed_seconds": elapsed, "probe_stages_measured": len(measured),
                 "worst_stage_probe_p99_ms": max(measured) if measured else None}
        for direction in ('tx', 'rx'):
            field = f'tcp_{direction}_bytes_per_second'
            speeds = [row[field] for row in rows if finite(row.get(field))]
            group[field] = sum(row[field] * row['elapsed_seconds'] for row in rows) / elapsed if elapsed > 0 and len(speeds) == len(rows) else None
            group[f'min_stage_{field}'] = min(speeds) if speeds else None
            group[f'max_stage_{field}'] = max(speeds) if speeds else None
            group[f'{direction}_stages_measured'] = len(speeds)
        groups[name] = group
    baseline, recovery = groups['baseline'], groups['recovery']
    comparable = all(group['recorded_stages'] == group['completed_stages'] == group['probe_stages_measured'] == 1 for group in (baseline, recovery))
    return {"scope": "recorded-stages; baseline-and-recovery-excluded-from-workload; elapsed-weighted-payload-rates",
            "groups": groups, "recovery_probe_p99_change_ms": recovery['worst_stage_probe_p99_ms'] - baseline['worst_stage_probe_p99_ms'] if comparable else None}


def summary(report: dict[str, Any]) -> dict[str, Any]:
    if report.get("endurance"):
        from trafficlab.endurance import summary_report
        return summary_report(report)
    if report.get("compact_stages"):
        resources = {role: {key:value for key,value in row.items() if key != "timeline"} for role,row in report.get("resources", {}).items()}
        return {"stages": report["stages"], "resources": resources,
                "overall": {**report["overall"], "phase_observations": phase_observations(report["stages"])},
                "skipped_stage_count": report.get("skipped_stage_count", 0), "schedule_errors": report.get("errors", []),
                "metric_scope": "identified-processes-separate-whole-OS-and-validated-payload",
                "cpu_scope": "percent-of-all-logical-CPUs; whole-OS-includes-background-work", "driver_resource_attribution": False,
                "stage_journal_sha256": report["stage_journal_sha256"], "stage_journal_records": len(report["stages"]),
                **execution_evidence(report)}
    rows = []
    all_latency = Histogram()
    all_udp_latency = Histogram()
    all_connection_latency = Histogram()
    for stage in report.get("stages", []):
        values = stage["results"]
        sent = sum(flow.get("sent", 0) for row in values for flow in row["flows"])
        received = sum(flow.get("received", 0) for row in values for flow in row["flows"])
        latency = Histogram()
        udp_latency = Histogram()
        connection_latency = Histogram()
        for row in values:
            for flow in row["flows"]:
                if row["task"] in ("echo", "udp") and flow.get("latency"):
                    (latency if row["task"] == "echo" else udp_latency).merge(flow["latency"])
                    (all_latency if row["task"] == "echo" else all_udp_latency).merge(flow["latency"])
                if flow.get("connection_and_authentication_ms"):
                    connection_latency.merge(flow["connection_and_authentication_ms"])
                    all_connection_latency.merge(flow["connection_and_authentication_ms"])
        def percentiles(histogram: Histogram) -> dict[str, Any]:
            return {key: value for key, value in histogram.view().items() if key not in ("bins", "sum_ms")}
        rows.append({"phase": stage["phase"], "complete": stage["complete"], "elapsed_seconds": stage["elapsed_seconds"],
            'comparison_quality':stage.get('comparison_quality'), 'phase_resources':stage.get('phase_resources'), 'workload_profiles':stage.get('workload_profiles'),
            "origin_evidence_error": stage.get('origin_evidence_error'),
            "tcp_tx_bytes_per_second": sum(row["tx_bytes"] for row in values) / stage["elapsed_seconds"],
            "tcp_rx_bytes_per_second": sum(row["rx_bytes"] for row in values) / stage["elapsed_seconds"],
            "probe_p99_ms": latency.view()["p99_ms"], "probe_latency": percentiles(latency),
            "udp_latency": percentiles(udp_latency), "connection_latency": percentiles(connection_latency),
            "tcp_active_peak": (stage.get("origin") or {}).get("tcp_active_peak"),
            "udp_observed_unique_flows": (stage.get("origin") or {}).get("udp_unique_flows"),
            "udp_sent": sent, "udp_received": received,
            "udp_observations": udp_observations(values),
            "max_udp_flow_loss_fraction": max((flow["loss_fraction"] for row in values if row["task"] == "udp" for flow in row["flows"] if flow.get("loss_fraction") is not None),default=None),
            "udp_duplicates": sum(flow.get("duplicates", 0) for row in values for flow in row["flows"]),
            "udp_reordered": sum(flow.get("reordered", 0) for row in values for flow in row["flows"]),
            "udp_invalid": sum(flow.get("invalid", 0) for row in values for flow in row["flows"]),
            "udp_loss_fraction": (sent - received) / sent if sent else None,
            "tcp_offered": sum(flow.get("offered", 1) for row in values if row["task"] != "udp" for flow in row["flows"]),
            "tcp_completed": sum(row["successful_tcp_flows"] for row in values),
            "tcp_failed": sum(flow.get("failures", int(not flow["complete"])) for row in values if row["task"] != "udp" for flow in row["flows"]),
            "application": next((row["application"] for row in values if row.get("application")), None),
            "application_payload_bytes": next((row.get('application_payload_bytes') for row in values if row.get('application')),None),
            "application_transactions": sum(flow.get("verified_transactions", 0) for row in values for flow in row["flows"]),
            "application_tls_sessions": [{key: flow.get(key) for key in ("tls_version", "cipher", "certificate_sha256",
                "certificate_verified", "server_name", "alpn", "close_verified")} for row in values for flow in row["flows"] if flow.get("tls_version")],
            "application_socket_errors": [{"errno": flow.get("socket_errno"), "winerror": flow.get("socket_winerror")}
                for row in values for flow in row["flows"] if "socket_errno" in flow],
            "application_protocol_sessions": [{key: flow.get(key) for key in ('ssh_host_key_sha256', 'ssh_host_key_verified',
                'ssh_cipher', 'ssh_version', 'sftp_version', 'grpc_status_verified', 'quic_version', 'connection_id_sha256',
                'handshake_complete', 'quic_datagrams_sent', 'quic_datagrams_received', 'migration_status', 'messaging_protocol',
                'quic_profile','quic_peak_streams','quic_completed_streams',
                'websocket_profile','ws_fragmented_requests','ws_fragmented_responses','ws_client_pongs_verified',
                'ws_server_pings_answered','http_profile','http_chunked_requests','http_gzip_requests',
                'http_chunked_responses','http_gzip_responses','http_modes','dns_encrypted_protocol',
                'http2_profile','http2_peak_streams','http2_completed_streams',
                'grpc_streaming_mode','grpc_rpc_count','grpc_request_messages','grpc_response_messages','grpc_receipts','close_scope', 'close_verified')}
                for row in values for flow in row['flows'] if flow.get('ssh_host_key_verified') or flow.get('grpc_status_verified') or flow.get('quic_version') or flow.get('messaging_protocol') or flow.get('websocket_profile') or flow.get('http_profile') or flow.get('dns_encrypted_protocol') or flow.get('http2_profile')],
            "errors": sorted({error for row in values for flow in row["flows"] for error in flow.get("errors", [])} |
                             ({stage['origin_evidence_error']['code']} if stage.get('origin_evidence_error') else set()))})
    resources = {role: {key:value for key,value in row.items() if key != "timeline"} for role,row in report.get("resources", {}).items()}
    elapsed = sum(row["elapsed_seconds"] for row in rows)
    sent = sum(row["udp_sent"] for row in rows)
    udp_flows = sum(row['udp_observations']['flow_count'] for row in rows)
    overall = {"stage_scope": "all-stages-including-baseline-and-recovery", "elapsed_seconds": elapsed,
        "phase_observations": phase_observations(rows),
        "tcp_tx_bytes_per_second": sum(row["tcp_tx_bytes_per_second"] * row["elapsed_seconds"] for row in rows) / elapsed if elapsed else None,
        "tcp_rx_bytes_per_second": sum(row["tcp_rx_bytes_per_second"] * row["elapsed_seconds"] for row in rows) / elapsed if elapsed else None,
        "probe_latency": {key: value for key, value in all_latency.view().items() if key not in ("bins", "sum_ms")},
        "udp_latency": {key: value for key, value in all_udp_latency.view().items() if key not in ("bins", "sum_ms")},
        "connection_latency": {key: value for key, value in all_connection_latency.view().items() if key not in ("bins", "sum_ms")},
        "connection_latency_scope": "profile-defined-session-setup-boundary; all-recorded-samples",
        "udp_observations": {"flow_count": udp_flows,
            "scope": "native-authenticated-UDP-replies; bounded-replay-window; 2s-deadline",
            **{key: sum(row['udp_observations'][key] or 0 for row in rows) if udp_flows else None for key in UDP_COUNTERS}},
        "udp_loss_fraction": (sent - sum(row["udp_received"] for row in rows)) / sent if sent else None,
        "application_transactions": sum(row["application_transactions"] for row in rows) if any(row["application"] for row in rows) else None,
        "tcp_completed": sum(row["tcp_completed"] for row in rows), "tcp_offered": sum(row["tcp_offered"] for row in rows)}
    return {"stages": rows, "resources": resources, "skipped_stage_count": report.get("skipped_stage_count", 0),
            "schedule_errors": report.get("errors", []), "metric_scope": "identified-processes-separate-whole-OS-and-validated-payload",
            "overall": overall, "cpu_scope": "percent-of-all-logical-CPUs; whole-OS-includes-background-work", "driver_resource_attribution": False,
            **execution_evidence(report)}


class SummaryWindow:
    """Streaming soak totals; raw exchanges are written once to the stage journal."""
    def __init__(self) -> None:
        self.echo = Histogram()
        self.udp = Histogram()
        self.connection = Histogram()
        self.udp_flows = 0
        self.udp_counters = dict.fromkeys(UDP_COUNTERS, 0)
        self.seconds = 0.0
        self.tx = self.rx = self.sent = self.received = self.completed = self.offered = 0

    def add(self, stage: dict[str, Any]) -> dict[str, Any]:
        compact = summary({"stages": [stage]})["stages"][0]
        self.seconds += stage["elapsed_seconds"]
        self.tx += sum(row["tx_bytes"] for row in stage["results"])
        self.rx += sum(row["rx_bytes"] for row in stage["results"])
        self.sent += compact["udp_sent"]
        self.received += compact["udp_received"]
        self.completed += compact["tcp_completed"]
        self.offered += compact["tcp_offered"]
        self.udp_flows += compact['udp_observations']['flow_count']
        for key in UDP_COUNTERS:
            self.udp_counters[key] += compact['udp_observations'][key] or 0
        for row in stage["results"]:
            for flow in row["flows"]:
                if row["task"] in ("echo", "udp") and flow.get("latency"):
                    (self.echo if row["task"] == "echo" else self.udp).merge(flow["latency"])
                if flow.get("connection_and_authentication_ms"):
                    self.connection.merge(flow["connection_and_authentication_ms"])
        return compact

    def view(self) -> dict[str, Any]:
        return {"stage_scope": "all-stages-including-baseline-and-recovery", "elapsed_seconds": self.seconds,
                "tcp_tx_bytes_per_second": self.tx / self.seconds if self.seconds else None,
                "tcp_rx_bytes_per_second": self.rx / self.seconds if self.seconds else None,
                "probe_latency": {key:value for key,value in self.echo.view().items() if key not in ("bins","sum_ms")},
                "udp_latency": {key:value for key,value in self.udp.view().items() if key not in ("bins","sum_ms")},
                "connection_latency": {key:value for key,value in self.connection.view().items() if key not in ("bins","sum_ms")},
                "connection_latency_scope": "profile-defined-session-setup-boundary; all-recorded-samples",
                "udp_observations": {"flow_count": self.udp_flows,
                    "scope": "native-authenticated-UDP-replies; bounded-replay-window; 2s-deadline",
                    **{key: value if self.udp_flows else None for key, value in self.udp_counters.items()}},
                "udp_loss_fraction": (self.sent - self.received) / self.sent if self.sent else None,
                "tcp_completed": self.completed, "tcp_offered": self.offered}
