"""Reconcile every authenticated flow, including those outside bounded route samples."""
from __future__ import annotations
from typing import Any
from trafficlab.websocket_wire import PROFILE
from trafficlab.http_body import PROFILE as HTTP_PROFILE


def stage_route(stage: dict[str, Any], proxied: bool) -> bool:
    if not stage["complete"]:
        return False
    proxy = stage["origin"].get("proxy", {})
    for result in stage['results']:
        for flow in result['flows']:
            if flow.get('dns_encrypted_protocol'):
                kind=flow['dns_encrypted_protocol']
                observed=stage['origin'].get('application_flows',{}).get(flow['flow_id'],{})
                if kind not in ('dns-tls','dns-https') or observed.get('dns_transport')!=kind or flow.get('certificate_verified') is not True or flow.get('close_verified') is not True:
                    return False
                count=observed.get('transactions')
                if type(count) is not int or count!=flow.get('verified_transactions',0)+1:
                    return False
            if flow.get('http_profile'):
                observed=stage['origin'].get('application_flows',{}).get(flow['flow_id'],{})
                fields=('http_chunked_requests','http_gzip_requests','http_chunked_responses','http_gzip_responses')
                if flow['http_profile']!=HTTP_PROFILE or any(type(flow.get(key)) is not int or type(observed.get(key)) is not int or
                    flow[key]!=observed[key] for key in fields):
                    return False
                transactions=flow.get('verified_transactions',0)
                chunked=transactions//4*2+int(transactions%4>1)
                gzip=transactions//4*2+int(transactions%4>2)
                if transactions<4 or flow['http_chunked_requests']!=chunked or flow['http_gzip_requests']!=gzip:
                    return False
            if flow.get('websocket_profile'):
                if flow['websocket_profile']!=PROFILE:
                    return False
                observed=stage['origin'].get('application_flows',{}).get(flow['flow_id'],{})
                pairs=(('ws_fragmented_requests','ws_fragmented_requests'),
                       ('ws_client_pongs_verified','ws_client_pings'),('ws_server_pings_answered','ws_server_pongs'))
                if any(type(flow.get(local)) is not int or type(observed.get(remote)) is not int or
                       flow[local]!=observed[remote] for local,remote in pairs):
                    return False
                fragments=flow['ws_fragmented_requests']
                if flow.get('ws_fragmented_responses')!=fragments or fragments!=flow.get('verified_transactions',0)//2:
                    return False
                if fragments<1 or flow['ws_client_pongs_verified']!=fragments or flow['ws_server_pings_answered']!=fragments:
                    return False
    if not proxied:
        return proxy.get("tcp_flows", 0) == 0 and proxy.get("udp_sent", 0) == 0
    tcp_fingerprint = udp_fingerprint = tcp_flows = udp_flows = packets = 0
    for result in stage["results"]:
        tcp_flows += result["successful_tcp_flows"]
        tcp_fingerprint ^= int(result["tcp_origin_fingerprint"], 16)
        udp_fingerprint ^= int(result["udp_origin_fingerprint"], 16)
        if result["task"] == "udp":
            udp_flows += sum(flow.get("received", 0) > 0 for flow in result["flows"])
            packets += sum(flow.get("quic_datagrams_sent", flow.get("sent", 0)) for flow in result["flows"])
    return (proxy.get("tcp_flows", 0) == tcp_flows and int(proxy.get("tcp_origin_fingerprint", "0"), 16) == tcp_fingerprint and
            proxy.get("udp_flows", 0) == udp_flows and int(proxy.get("udp_origin_fingerprint", "0"), 16) == udp_fingerprint and proxy.get("udp_sent", 0) == packets)
