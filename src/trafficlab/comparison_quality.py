"""Separate verified exchange, route coverage and load quality; never relax admission gates."""
from __future__ import annotations
import math

METHOD = 'comparison-quality-v1'
RATE_TOLERANCE = .05  # Declared lab policy, not a protocol correctness threshold.


def finite(value):
    return type(value) in (int, float) and math.isfinite(value)


def stage_quality(stage, proxied, route):
    results = stage.get('results', [])
    flows = [flow for row in results for flow in row.get('flows', [])]
    loss_ok = all(not finite(f.get('loss_fraction')) or f['loss_fraction'] <= .01 for f in flows)
    exchange = 'PASS' if stage.get('complete') is True and flows and loss_ok else 'FAIL'
    coverage = 'COMPLETE' if route else 'UNVERIFIED'
    missing = None
    if proxied and not route and exchange == 'PASS' and results and all(row.get('task') == 'udp' and not row.get('application') for row in results):
        proxy = (stage.get('origin') or {}).get('proxy', {})
        packets = sum(f.get('sent', 0) for f in flows)
        fingerprint = 0
        for row in results:
            fingerprint ^= int(row.get('udp_origin_fingerprint', '0'), 16)
        if all(not f.get('errors') and not any(f.get(k, 0) for k in ('invalid', 'send_errors', 'unexpected_source_packets')) for f in flows) and \
                proxy.get('tcp_flows') == 0 and int(proxy.get('tcp_origin_fingerprint', '0'), 16) == 0 and \
                proxy.get('udp_flows') == sum(f.get('received', 0) > 0 for f in flows) and \
                int(proxy.get('udp_origin_fingerprint', '0'), 16) == fingerprint and \
                type(proxy.get('udp_sent')) is int and 0 < proxy['udp_sent'] < packets:
            coverage, missing = 'PARTIAL', packets - proxy['udp_sent']
    rates = []
    def record(plan, row, target, key, unit):
        count, seconds = plan['connections'], plan['seconds']
        if not finite(target) or target <= 0 or seconds <= 0:
            return
        values = [f.get(key) for f in row.get('flows', [])]
        known = len(values) == count and all(finite(v) and v >= 0 for v in values)
        actual = [v / seconds for v in values] if known else []
        rates.append({'unit':unit, 'target_per_flow':target,
                      'actual_per_flow_min':min(actual) if actual else None,
                      'actual_per_flow_max':max(actual) if actual else None, 'connections':count, 'window_seconds':seconds,
                      'state':'NOT_MEASURED' if not actual else 'MET' if all(abs(v / target - 1) <= RATE_TOLERANCE for v in actual) else 'OFF_TARGET' if any(v > target*(1+RATE_TOLERANCE) for v in actual) else 'BELOW_TARGET'})
    for plan, row in zip(stage.get('workload_profiles', []), results):
        key = 'verified_transactions' if plan.get('application') else 'sent' if plan['task'] == 'udp' else 'exchange_count'
        unit = 'verified-transactions' if plan.get('application') else 'sent-datagrams' if plan['task'] == 'udp' else 'verified-echoes'
        record(plan, row, plan.get('target_per_flow'), key, unit)
        if plan['task'] == 'flow_rate':
            record(plan, row, plan.get('rate_flows_per_second_per_worker'), 'completed', 'completed-sessions')
        if plan['task'] in ('upload','download','duplex'):
            for direction in (['tx','rx'] if plan['task'] == 'duplex' else ['tx' if plan['task'] == 'upload' else 'rx']):
                record(plan, row, plan.get('rate_bytes_per_second_per_flow'), direction+'_bytes', direction+'-bytes')
    pc = stage.get('phase_resources', {}).get('windows_system', {}).get('counters', {}).get('cpu_percent_of_pc', {})
    headroom = 'NOT_MEASURED' if not finite(pc.get('mean')) else 'CPU_SATURATED' if pc['mean'] >= 90 else 'CPU_NOT_SATURATED'
    return {'method':METHOD, 'exchange_state':exchange, 'route_accounting':coverage, 'unaccounted_sent_packets':missing,
            'load_profile_recorded':bool(stage.get('workload_profiles')),
            'received_flow_identity_confirmed':coverage in ('COMPLETE', 'PARTIAL'), 'rates':rates,
            'rate_tolerance_fraction':RATE_TOLERANCE, 'headroom':headroom, 'cpu_saturation_threshold_percent':90,
            'maximum_capacity_verified':False}


def report_quality(report):
    rows = [s.get('comparison_quality') for s in report.get('stages', [])]
    if not rows or any(not q or q.get('method') != METHOD for q in rows):
        return {'method':METHOD, 'exchange_state':'UNKNOWN', 'route_accounting':'UNKNOWN', 'load_state':'NOT_MEASURED',
                'maximum_capacity_verified':False, 'windows_complete':False}
    load_rows = [q for s, q in zip(report['stages'], rows) if s['phase'] not in ('baseline', 'recovery')]
    rates = [r for q in load_rows for r in q['rates']]
    complete = report.get('stage_count') == len(rows) and not report.get('skipped_stage_count', 0) and not report.get('unstarted_stage_count', 0)
    return {'method':METHOD, 'exchange_state':'PASS' if complete and all(q['exchange_state'] == 'PASS' for q in rows) else 'FAIL',
            'route_accounting':'COMPLETE' if all(q['route_accounting'] == 'COMPLETE' for q in rows) else
                'PARTIAL' if all(q['route_accounting'] in ('COMPLETE', 'PARTIAL') for q in rows) else 'UNVERIFIED',
            'windows_complete':complete, 'load_state':'PROFILE' if not rates and load_rows and all(q.get('load_profile_recorded') for q in load_rows) else 'NOT_MEASURED' if not rates or any(r['state'] == 'NOT_MEASURED' for r in rates) else
                'MET' if all(r['state'] == 'MET' for r in rates) else 'OFF_TARGET' if any(r['state'] == 'OFF_TARGET' for r in rates) else 'BELOW_TARGET',
            'headroom':'CPU_SATURATED' if any(q['headroom'] == 'CPU_SATURATED' for q in load_rows) else
                'CPU_NOT_SATURATED' if load_rows and all(q['headroom'] == 'CPU_NOT_SATURATED' for q in load_rows) else 'NOT_MEASURED',
            'rate_tolerance_fraction':RATE_TOLERANCE, 'maximum_capacity_verified':False}


def workload_resources(stages):
    """Only measured load windows; retain first/last, peak and duration-weighted means."""
    windows = [s for s in stages if s['phase'] not in ('baseline', 'recovery')]
    if not windows or any(not s.get('phase_resources') for s in windows):
        return None
    result = {}
    roles = set().union(*(s['phase_resources'] for s in windows))
    for role in roles:
        rows = [(s['phase_resources'].get(role), s['elapsed_seconds']) for s in windows]
        if any(not r or r.get('unavailable_samples') for r, _ in rows):
            continue
        counters = {}
        names = set.intersection(*(set(r['counters']) for r, _ in rows))
        for name in names:
            values = [(r['counters'][name], duration) for r, duration in rows]
            counters[name] = {'first':values[0][0]['first'], 'last':values[-1][0]['last'],
                              'max':max(c['max'] for c, _ in values), 'min':min(c['min'] for c, _ in values),
                              'mean':sum(c['mean'] * d for c, d in values) / sum(d for _, d in values)}
            if name == 'cpu_seconds':
                counters[name]['measured_change'] = sum(c['last'] - c['first'] for c, _ in values)
        result[role] = {'counters':counters, 'samples':sum(r['samples'] for r, _ in rows), 'scope':'load-windows-only',
                        'unavailable_samples':0}
    return result
