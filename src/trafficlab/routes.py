"""Reconcile every authenticated flow, including those outside bounded route samples."""
from __future__ import annotations
from typing import Any


def stage_route(stage: dict[str, Any], proxied: bool) -> bool:
    if not stage["complete"]:
        return False
    proxy = stage["origin"].get("proxy", {})
    if not proxied:
        return proxy.get("tcp_flows", 0) == 0 and proxy.get("udp_sent", 0) == 0
    tcp_fingerprint = udp_fingerprint = tcp_flows = udp_flows = packets = 0
    for result in stage["results"]:
        tcp_flows += result["successful_tcp_flows"]
        tcp_fingerprint ^= int(result["tcp_origin_fingerprint"], 16)
        udp_fingerprint ^= int(result["udp_origin_fingerprint"], 16)
        if result["task"] == "udp":
            udp_flows += sum(flow.get("received", 0) > 0 for flow in result["flows"])
            packets += sum(flow.get("sent", 0) for flow in result["flows"])
    return (proxy.get("tcp_flows", 0) == tcp_flows and int(proxy.get("tcp_origin_fingerprint", "0"), 16) == tcp_fingerprint and
            proxy.get("udp_flows", 0) == udp_flows and int(proxy.get("udp_origin_fingerprint", "0"), 16) == udp_fingerprint and proxy.get("udp_sent", 0) == packets)
