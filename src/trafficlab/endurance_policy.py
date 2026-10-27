"""Concurrent policy controls; a timeout alone is never evidence of BLOCK."""
from __future__ import annotations
import time
from trafficlab.native_engine import execute_worker
from trafficlab.schedule import origin_metrics
from trafficlab.worker import cancelled

POLICIES = (('direct.tcp',42541,'echo'), ('direct.udp',42542,'udp'),
            ('block.tcp',42543,'echo'), ('block.udp',42544,'udp'))


def check(job):
    session=job['_policy_session']
    def execute(name,port,task,health=False):
        probe={**job,'run_id':job['run_id']+'.'+name,'port':port,'task':task,'seconds':.2,
               'connections':1,'warmup_count':0,'message_bytes':64,'rate_exchanges_per_second':5,
               'rate_packets_per_second':5,'connect_timeout_seconds':1}
        probe.pop('test_proxy',None)
        if health:
            probe.update(native_worker_port=job['native_origin_port'],native_worker_pid=job['native_origin_pid'],
                         native_worker_executable=job['native_origin_executable'])
        result=execute_worker(probe)
        if result.get('worker_results_available') is False:
            raise ValueError('TRAFFIC_POLICY_WORKER_RESULT_UNKNOWN')
        return probe,result
    health=[]
    for name,port,task in POLICIES[2:]:
        if cancelled(job):return {'cancelled':True,'checks':[]}
        probe,result=execute('health.'+name,port,task,True)
        if not result['complete']:
            raise ValueError('TRAFFIC_POLICY_RECEIVER_HEALTH_UNVERIFIED')
        health.append(result)
    before_origin=origin_metrics(job)
    if set(before_origin.get('policy_receivers',{}))!={'42541','42542','42543','42544'}:
        raise ValueError('TRAFFIC_POLICY_RECEIVERS_UNAVAILABLE')
    before=session.command('POLICY_SNAP')
    probes=[]
    for name,port,task in POLICIES:
        if cancelled(job):return {'cancelled':True,'checks':[]}
        probe,result=execute(name,port,task)
        observed=origin_metrics(probe)
        if observed['active'] or observed.get('proxy',{}).get('tcp_active',0):
            raise ValueError('TRAFFIC_POLICY_PROBE_NOT_IDLE')
        probes.append((name,port,result,observed))
    # Observe after the owned blocked workers have returned and closed sockets.
    time.sleep(.2)
    after_origin=origin_metrics(job);after=session.command('POLICY_SNAP')
    checks=[]
    for name,port,result,observed in probes:
        key=str(port);delta={action:after['events'][key][action]-before['events'][key][action]
                             for action in ('DIRECT','PROXY','BLOCKED')}
        arrivals=after_origin['policy_receivers'][key]-before_origin['policy_receivers'][key]
        proxy=observed.get('proxy',{})
        no_proxy=proxy.get('tcp_flows',0)==0 and proxy.get('udp_sent',0)==0 and delta['PROXY']==0
        if name.startswith('direct'):
            ok=result['complete'] and arrivals>0 and no_proxy and delta['DIRECT']>0 and delta['BLOCKED']==0
            reason=None if ok else 'TRAFFIC_POLICY_DIRECT_UNVERIFIED'
        else:
            ok=not result['complete'] and arrivals==0 and no_proxy and delta['BLOCKED']>0 and delta['DIRECT']==0
            reason=None if ok else 'TRAFFIC_POLICY_BLOCK_UNVERIFIED'
        checks.append({'channel':name,'complete':ok,'error':reason,'receiver_arrivals':arrivals,
                       'events':delta,'result':result,'origin':observed})
    return {'cancelled':False,'checks':checks,'receiver_health':health,'before':before,'after':after,
            'origin_before':before_origin,'origin_after':after_origin,
            'scope':'owned-native-worker; exact host/port/protocol; explicit DIRECT/BLOCK; healthy unruled origin sentinel'}
