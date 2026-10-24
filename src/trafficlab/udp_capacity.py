"""An explicit-SOCKS control only after clean UDP loss, never a product PASS."""
from __future__ import annotations
from trafficlab.routes import stage_route
from trafficlab.schedule import recipes, run
from trafficlab.worker import cancelled

CAPACITY_ERROR = 'TRAFFIC_LAB_UDP_CAPACITY_UNVERIFIED'


def clean_udp_loss(stage):
    workers = stage.get('results', [])
    if len(workers) != 1 or workers[0].get('task') != 'udp' or workers[0].get('application'):
        return False
    worker = workers[0]
    flows = worker.get('flows', [])
    return bool(flows and not worker.get('errors') and any((f.get('loss_fraction') or 0) > .01 for f in flows) and
        all(not f.get('errors') and not f.get('invalid', 0) and not f.get('unexpected_source_packets', 0) and
            not f.get('send_errors', 0) for f in flows))


def capacity_candidate(job, catalog, report):
    if job.get('runtime_mode') != 'local' or job.get('case_id') != 'udp-connections' or job.get('test_proxy'):
        return None
    for stage in report.get('stages', []):
        origin = stage.get('origin') or {}
        proxy = origin.get('proxy') or {}
        if clean_udp_loss(stage) and proxy.get('udp_sent', 0) > origin.get('udp_received', 0):
            for planned in recipes(job, catalog):
                if planned['phase'] == stage['phase']:
                    return {**planned['workloads'][0], 'source_phase': stage['phase']}
    return None


def run_capacity_control(job, catalog, candidate, output, progress):
    # Caller has disabled the owned Core rules and verified isolation first.
    # Same duration, connection count, packet size and per-flow offered rate.
    duration, load = job['duration'], job['load']
    control_catalog = {**catalog, 'cases':[{'id':job['case_id'], 'recipe':'udp'}],
        'duration_seconds':{**catalog['duration_seconds'], duration:candidate['seconds']},
        'loads':{**catalog['loads'], load:{**catalog['loads'][load], 'connections':candidate['connections'],
                                         'packets_per_second':candidate['rate_packets_per_second']}}}
    control_job = {**job, 'run_id':job['run_id'] + '.lab-capacity', 'expected_proxy':True,
        'test_proxy':{'host':job['host'], 'port':job['proxy_port'], 'username':job['id']}}
    report = run(control_job, control_catalog, output, progress)
    stages = report.get('stages', [])
    stage = stages[0] if len(stages) == 1 else None
    route = bool(stage and stage_route(stage, True))
    limited = bool(stage and not cancelled(job) and not report.get('cancelled') and route and clean_udp_loss(stage))
    return {'mode':'LAB-CAPACITY-control', 'scope':'explicit-SOCKS-with-product-rules-disabled',
        'source_phase':candidate['source_phase'], 'connections':candidate['connections'],
        'seconds':candidate['seconds'], 'message_bytes':candidate['message_bytes'],
        'packets_per_second_per_flow':candidate['rate_packets_per_second'],
        'route_verified':route, 'capacity_sufficient':bool(report.get('complete') and route),
        'laboratory_limited':limited, 'product_result_confirmed':False}
