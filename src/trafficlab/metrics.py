"""All-sample latency and payload summaries, separate from product lifecycle."""
from __future__ import annotations
from typing import Any
from trafficlab.protocol import Histogram


def summary(report: dict[str, Any]) -> dict[str, Any]:
    if report.get("compact_stages"):
        resources = {role: {key:value for key,value in row.items() if key != "timeline"} for role,row in report.get("resources", {}).items()}
        return {"stages": report["stages"], "resources": resources, "overall": report["overall"],
                "skipped_stage_count": report.get("skipped_stage_count", 0), "schedule_errors": report.get("errors", []),
                "metric_scope": "identified-processes-separate-whole-OS-and-validated-payload",
                "cpu_scope": "percent-of-all-logical-CPUs; whole-OS-includes-background-work", "driver_resource_attribution": False,
                "stage_journal_sha256": report["stage_journal_sha256"], "stage_journal_records": len(report["stages"])}
    rows = []
    all_latency = Histogram()
    all_udp_latency = Histogram()
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
        def percentiles(histogram: Histogram) -> dict[str, Any]:
            return {key: value for key, value in histogram.view().items() if key not in ("bins", "sum_ms")}
        rows.append({"phase": stage["phase"], "complete": stage["complete"], "elapsed_seconds": stage["elapsed_seconds"],
            "tcp_tx_bytes_per_second": sum(row["tx_bytes"] for row in values) / stage["elapsed_seconds"],
            "tcp_rx_bytes_per_second": sum(row["rx_bytes"] for row in values) / stage["elapsed_seconds"],
            "probe_p99_ms": latency.view()["p99_ms"], "probe_latency": percentiles(latency),
            "udp_latency": percentiles(udp_latency), "connection_latency": percentiles(connection_latency),
            "tcp_active_peak": (stage.get("origin") or {}).get("tcp_active_peak"),
            "udp_observed_unique_flows": (stage.get("origin") or {}).get("udp_unique_flows"),
            "udp_sent": sent, "udp_received": received,
            "max_udp_flow_loss_fraction": max((flow["loss_fraction"] for row in values if row["task"] == "udp" for flow in row["flows"] if flow.get("loss_fraction") is not None),default=None),
            "udp_duplicates": sum(flow.get("duplicates", 0) for row in values for flow in row["flows"]),
            "udp_reordered": sum(flow.get("reordered", 0) for row in values for flow in row["flows"]),
            "udp_invalid": sum(flow.get("invalid", 0) for row in values for flow in row["flows"]),
            "udp_loss_fraction": (sent - received) / sent if sent else None,
            "tcp_offered": sum(flow.get("offered", 1) for row in values if row["task"] != "udp" for flow in row["flows"]),
            "tcp_completed": sum(row["successful_tcp_flows"] for row in values),
            "tcp_failed": sum(flow.get("failures", int(not flow["complete"])) for row in values if row["task"] != "udp" for flow in row["flows"]),
            "errors": sorted(set(error for row in values for flow in row["flows"] for error in flow.get("errors", [])))})
    resources = {role: {key:value for key,value in row.items() if key != "timeline"} for role,row in report.get("resources", {}).items()}
    elapsed = sum(row["elapsed_seconds"] for row in rows)
    sent = sum(row["udp_sent"] for row in rows)
    overall = {"stage_scope": "all-stages-including-baseline-and-recovery", "elapsed_seconds": elapsed,
        "tcp_tx_bytes_per_second": sum(row["tcp_tx_bytes_per_second"] * row["elapsed_seconds"] for row in rows) / elapsed if elapsed else None,
        "tcp_rx_bytes_per_second": sum(row["tcp_rx_bytes_per_second"] * row["elapsed_seconds"] for row in rows) / elapsed if elapsed else None,
        "probe_latency": {key: value for key, value in all_latency.view().items() if key not in ("bins", "sum_ms")},
        "udp_latency": {key: value for key, value in all_udp_latency.view().items() if key not in ("bins", "sum_ms")},
        "udp_loss_fraction": (sent - sum(row["udp_received"] for row in rows)) / sent if sent else None,
        "tcp_completed": sum(row["tcp_completed"] for row in rows), "tcp_offered": sum(row["tcp_offered"] for row in rows)}
    return {"stages": rows, "resources": resources, "skipped_stage_count": report.get("skipped_stage_count", 0),
            "schedule_errors": report.get("errors", []), "metric_scope": "identified-processes-separate-whole-OS-and-validated-payload",
            "overall": overall, "cpu_scope": "percent-of-all-logical-CPUs; whole-OS-includes-background-work", "driver_resource_attribution": False}


class SummaryWindow:
    """Streaming soak totals; raw exchanges are written once to the stage journal."""
    def __init__(self) -> None:
        self.echo = Histogram()
        self.udp = Histogram()
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
        for row in stage["results"]:
            if row["task"] in ("echo", "udp"):
                for flow in row["flows"]:
                    if flow.get("latency"):
                        (self.echo if row["task"] == "echo" else self.udp).merge(flow["latency"])
        return compact

    def view(self) -> dict[str, Any]:
        return {"stage_scope": "all-stages-including-baseline-and-recovery", "elapsed_seconds": self.seconds,
                "tcp_tx_bytes_per_second": self.tx / self.seconds if self.seconds else None,
                "tcp_rx_bytes_per_second": self.rx / self.seconds if self.seconds else None,
                "probe_latency": {key:value for key,value in self.echo.view().items() if key not in ("bins","sum_ms")},
                "udp_latency": {key:value for key,value in self.udp.view().items() if key not in ("bins","sum_ms")},
                "udp_loss_fraction": (self.sent - self.received) / self.sent if self.sent else None,
                "tcp_completed": self.completed, "tcp_offered": self.offered}
