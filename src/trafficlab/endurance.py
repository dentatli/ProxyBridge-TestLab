"""Exclusive fixed-profile endurance run: persistent channels and bounded evidence.

The private time-scale arguments are for short development admission checks only;
the HTTP request/binding cannot override the advertised wall-clock duration.
"""
from __future__ import annotations
import concurrent.futures
import collections
import hashlib
import json
import os
import threading
import time
from pathlib import Path

HOURS = {'H2':2, 'H24':24, 'H48':48, 'H72':72, 'SHORT':24, 'NORMAL':48, 'LONG':72}
METHOD = 'endurance-fixed-cycle-v2-policies'
APPLICATIONS = ('http','https','http2','sftp','dns-tcp','quic')


def summary_report(report):
    resources = {role:{k:v for k,v in row.items() if k!='timeline'} for role,row in report['resources'].items()}
    for row in resources.values():
        cpu=row.get('counters',{}).get('cpu_seconds')
        if cpu:cpu['measured_change']=cpu['last']-cpu['first']
    ok=report['complete']
    return {'stages':report['stages'], 'resources':resources, 'workload_resources':resources,
        'overall':report['overall'], 'endurance':report['endurance'],
        'kernel_resources':report.get('kernel_resources'), 'schedule_errors':report['errors'],
        'failure_context':report.get('failure_detail'),
        'comparison_quality':{'method':METHOD, 'exchange_state':'PASS' if ok else 'FAIL',
            'windows_complete':report['endurance']['planned_walltime_completed'],
            'route_accounting':'COMPLETE' if report['product_route_confirmed'] else 'UNVERIFIED',
            'load_state':'PROFILE', 'headroom':'CPU_SATURATED' if report['endurance']['cpu_saturated'] else 'CPU_NOT_SATURATED',
            'maximum_capacity_verified':False},
        'metric_scope':'endurance-run-and-drain-window; verified TCP work separate from UDP; live observations pending final proof',
        'cpu_scope':'identified-process-and-separate-whole-OS; never-sum', 'driver_resource_attribution':False,
        'stage_journal_sha256':report['stage_journal_sha256'], 'stage_journal_records':report['stage_journal_records'],
        'planned_stage_count':report['stage_count'], 'recorded_stage_count':report['endurance']['completed_jobs'],
        'workload_started_stage_count':report['workload_started_stage_count'], 'unstarted_stage_count':0,
        'skipped_stage_count':0, 'measurement_state':'COMPLETED' if ok else 'PARTIAL'}


def run(job, catalog, output, progress, *, _duration_seconds=None, _cycle_seconds=1800, _window_seconds=60):
    from trafficlab.schedule import atomic, origin_metrics
    from trafficlab.worker import execute, cancelled
    from trafficlab.bounded_worker import execute_bounded
    from trafficlab.native_engine import worker_state
    from trafficlab.metrics import SummaryWindow
    from trafficlab.resources import ResourceWindow, process_sample, system_sample
    from trafficlab.routes import stage_route
    from trafficlab.comparison_quality import stage_quality
    from trafficlab.protocol import json_bytes
    if job.get('runtime_mode')!='local' or not job.get('native_worker_port'):
        raise ValueError('TRAFFIC_ENDURANCE_LOCAL_NATIVE_REQUIRED')
    if job.get('_policy_session') is None or not job.get('native_origin_port'):
        raise ValueError('TRAFFIC_ENDURANCE_POLICY_SESSION_REQUIRED')
    seconds=HOURS[job['duration']]*3600 if _duration_seconds is None else float(_duration_seconds)
    if not 0.1<=seconds<=259200: raise ValueError('TRAFFIC_ENDURANCE_DURATION_INVALID')
    started=time.monotonic(); deadline=started+seconds; observer_stop=threading.Event()
    lock=threading.Lock(); resources=ResourceWindow(); totals=SummaryWindow(); tail=collections.deque(maxlen=8)
    digest=hashlib.sha256(); channels={}; sticky=set(); fatal=[]; pending={}; live={}; previous_live={}; previous_stamp=0.0; route_ok=True
    info={'method':METHOD,'planned_seconds':seconds,'cycle_seconds':_cycle_seconds,'fixed_load':True,
          'development_time_scale':_duration_seconds is not None,'planned_walltime_completed':False,
          'verified_tcp_tx_bytes':0,'verified_tcp_rx_bytes':0,'verified_application_transactions':0,'channels':channels,'completed_jobs':0,'minute_samples':0,'cpu_saturated':False,'maximum_reply_gap_seconds':{},
          'profile':{'normal_minutes':10,'burst_minutes':5,'churn_minutes':5,'quiet_minutes':5,'recovery_minutes':5,'tcp_mib_per_second_per_direction':[6,10,2,0,1],'tcp_probe_per_second':2,'udp_packets_per_second':5,'message_bytes':512,'churn_sessions_per_second':3,'application_transactions_per_second':3,'quic_transactions_per_second':1},
          'policy_checks':{'interval_seconds':60,'actions':['PROXY','DIRECT','BLOCK'],'protocols':['TCP','UDP'],
                           'direct_overrides_fallback_block':True,'block_requires':['core_event','zero_arrivals','healthy_receiver']},
          'persistent_connections':'one TCP echo connection and one UDP association throughout the run'}
    report={'schema_version':1,'method':'controlled-traffic-v1','case_id':'soak','run_id':job['run_id'],
        'duration':job['duration'],'load':'FIXED','complete':False,'cancelled':False,'compact_stages':True,
        'endurance':info,'stages':[],'resources':{},'overall':{},'product_route_confirmed':False,'errors':[],
        'expected_proxy':bool(job.get('expected_proxy')),'udp_expected':True,'stage_count':0,'workload_started_stage_count':0,'skipped_stage_count':0,
        'stage_journal_records':0,'stage_journal_sha256':digest.hexdigest(),
        'attempt_policy':'fresh-no-resume','kernel_resources':{'available':False,'error':'LONG_RUN_SCOPE_EXCLUDED','cleanup_verified':True}}
    def persist():
        report['resources']=resources.view();report['elapsed_seconds']=time.monotonic()-started
        report['stage_count']=report['workload_started_stage_count']
        report['overall']=totals.view()
        report['overall'].update(elapsed_seconds=report['elapsed_seconds'],tcp_tx_bytes_per_second=info['verified_tcp_tx_bytes']/max(report['elapsed_seconds'],.001),tcp_rx_bytes_per_second=info['verified_tcp_rx_bytes']/max(report['elapsed_seconds'],.001),application_transactions=info['verified_application_transactions'])
        report['stages']=report['stages'][:8]+list(tail)
        # Prefix and tail overlap only before 16 completed records.
        report['stages']=list({s['phase']:s for s in report['stages']}.values())
        atomic(output,report)
    def observe():
        nonlocal live
        previous_observation=time.monotonic()
        next_origin_poll=previous_observation
        while not observer_stop.is_set():
            try:
                current_observation=time.monotonic()
                gap=current_observation-previous_observation;previous_observation=current_observation
                if gap>10:raise ValueError('TRAFFIC_ENDURANCE_OBSERVATION_GAP')
                # The preconnected metrics socket expires after 30 idle seconds.
                # Keep using that authenticated, serialized channel during long
                # workload/quiet windows; never reconnect through the product.
                if job.get('_origin_metrics_channel') is not None and current_observation>=next_origin_poll:
                    origin_metrics(job)
                    info['origin_heartbeat_count']=info.get('origin_heartbeat_count',0)+1
                    next_origin_poll=time.monotonic()+5
                now=time.monotonic()-started
                samples={'windows_system':system_sample()}
                for role,p in job.get('resource_processes',{}).items():samples[role]=process_sample(int(p['pid']),p.get('path'))
                if any(not v.get('available') for v in samples.values()):raise ValueError('TRAFFIC_ENDURANCE_RESOURCE_UNAVAILABLE')
                state=worker_state(job)
                if state is None:raise ValueError('TRAFFIC_ENDURANCE_WORKER_IDENTITY_UNKNOWN')
                with lock:
                    for role,s in samples.items():
                        resources.add(role,now,s)
                        if resources.roles[role]['unavailable_samples']:raise ValueError('TRAFFIC_ENDURANCE_RESOURCE_IDENTITY_CHANGED')
                    live=state.get('endurance_jobs',{})
                    for rid,s in live.items():info['maximum_reply_gap_seconds'][rid]=max(info['maximum_reply_gap_seconds'].get(rid,0),s['reply_age_seconds'])
                atomic(progress,{'run_id':job['run_id'],'state':'RUNNING','stage':'endurance', 'operation':'RUNNING_WORKLOAD',
                    'elapsed_seconds':now,'remaining_seconds':max(0,deadline-time.monotonic()),'channels':{k:{a:v for a,v in s.items() if a!='latency'} for k,s in live.items()}})
            except Exception as e:
                report.setdefault('failure_detail',{'code':str(e)[:200],'source':'observer'})
                fatal.append(type(e).__name__+':ENDURANCE_OBSERVER_FAILED');return
            observer_stop.wait(min(1,_window_seconds/2))
    def make(name,task,span,**kw):
        j={**job,'run_id':job['run_id']+'.'+name,'task':task,'seconds':max(.05,span),
           '_endurance_async':True,'connections':1,'warmup_count':0,'message_bytes':512,**kw}
        if j.get('test_proxy'):j['test_proxy']={**j['test_proxy'],'username':j['run_id']}
        # Independent owned stop files permit quarantining one channel without
        # cancelling healthy channels. User cancellation is propagated below.
        j['cancellation_path']=str(Path(output).with_name(Path(output).name+'.'+name+'.stop'))
        if Path(j['cancellation_path']).exists():raise ValueError('TRAFFIC_ENDURANCE_ATTEMPT_NOT_FRESH')
        return j
    def stop(j):Path(j['cancellation_path']).touch(exist_ok=True)
    def isolated(j):
        until=time.monotonic()+5
        while True:
            o=origin_metrics(j)
            if o['active']==0 and o.get('proxy',{}).get('tcp_active',0)==0:return o
            if time.monotonic()>=until:raise ValueError('TRAFFIC_ENDURANCE_CHANNEL_NOT_IDLE')
            time.sleep(.05)
    def accept(name,j,result,journal):
        nonlocal route_ok
        if name=='policies':
            record=json_bytes({'kind':'policy-observation','elapsed_seconds':time.monotonic()-started,**result})+b'\n'
            journal.write(record);digest.update(record);report['stage_journal_records']+=1
            for check in result['checks']:
                key=check['channel'];state=channels.setdefault(key,{'runs':0,'failures':0,'state':'RUNNING'})
                state['runs']+=1
                if not check['complete']:state['failures']+=1;sticky.add(key);route_ok=False
                state['state']='FAILED' if key in sticky else 'SUCCESSFUL'
                state['last_error']=check['error']
            return
        if result.get('worker_results_available') is False:
            report.setdefault('failure_detail',{'code':'TRAFFIC_ENDURANCE_WORKER_RESULT_UNKNOWN','channel':name,
                                                'worker':result.get('failure_context'),
                                                'retained_control_result':result.get('retained_control_result')})
            raise ValueError('TRAFFIC_ENDURANCE_WORKER_RESULT_UNKNOWN:'+name+':'+','.join(result.get('errors',[])))
        if j.get('endurance') and result['complete'] and time.monotonic()<deadline-2:
            result={**result,'complete':False,'errors':result.get('errors',[])+['TRAFFIC_ENDURANCE_EARLY_CLOSE']}
        origin=isolated(j)
        stage={'phase':name+'-'+str(report['stage_journal_records']), 'elapsed_seconds':max(.001,result.get('elapsed_seconds',j['seconds'])),
            'complete':result['complete'],'results':[result],'origin':origin,'origin_evidence_error':None,
            'workload_profiles':[{'task':j['task'],'application':j.get('application'),'connections':j['connections'],'seconds':j['seconds'],'rate_bytes_per_second_per_flow':j.get('rate_bytes_per_second',0),'rate_flows_per_second_per_worker':j.get('rate_flows_per_second',0),'target_per_flow':j.get('rate_packets_per_second') if j['task']=='udp' or j.get('application') else j.get('rate_exchanges_per_second')}],
            'phase_resources':{}}
        route=stage_route(stage,bool(job.get('expected_proxy')));route_ok &= route
        stage['comparison_quality']=stage_quality(stage,bool(job.get('expected_proxy')),route)
        ok=result['complete'] and route
        if ok and j['task']!='udp':
            info['verified_tcp_tx_bytes']+=result['tx_bytes'];info['verified_tcp_rx_bytes']+=result['rx_bytes']
        if ok and j.get('application'):info['verified_application_transactions']+=sum(f.get('verified_transactions',0) for f in result['flows'])
        state=channels.setdefault(name,{'runs':0,'failures':0,'state':'RUNNING'})
        state['runs']+=1
        if not ok and not cancelled(job):state['failures']+=1;sticky.add(name)
        state['state']='CANCELLED' if cancelled(job) else 'FAILED' if name in sticky else 'SUCCESSFUL'
        record=json_bytes({'kind':'completed-work','stage':stage})+b'\n';journal.write(record);digest.update(record)
        compact=totals.add(stage);compact['route_verified']=route
        if j['task']=='udp':compact['tcp_tx_bytes_per_second']=compact['tcp_rx_bytes_per_second']=0
        if info['completed_jobs']<8:report['stages'].append(compact)
        else:tail.append(compact)
        report['stage_journal_records']+=1;info['completed_jobs']+=1
    def snapshot(journal,phase):
        nonlocal previous_live,previous_stamp
        from trafficlab.protocol import Histogram
        import math
        with lock:
            value={'kind':'minute-observation','elapsed_seconds':time.monotonic()-started,'cycle_phase':phase,
                   'scope':'live counters and latency histograms; final route/data proof pending',
                   'persistent':json.loads(json.dumps(live)), 'resources':{k:{a:v for a,v in r.items() if a!='timeline'} for k,r in resources.view().items()}}
        now=value['elapsed_seconds'];value['interval_seconds']=now-previous_stamp;value['intervals']={}
        for rid,current in value['persistent'].items():
            old=previous_live.get(rid,{});h=Histogram();raw=current['latency'];prior=old.get('latency',{})
            bins={str(k):v-prior.get('bins',{}).get(str(k),0) for k,v in raw['bins'].items() if v-prior.get('bins',{}).get(str(k),0)>0}
            count=sum(bins.values())
            if count:h.merge({'method':raw['method'],'bins':bins,'count':count,'sum_ms':raw['sum_ms']-prior.get('sum_ms',0),'max_ms':.001*math.expm1(max(map(int,bins))*math.log(1.01))})
            value['intervals'][rid]={'sent':current['sent']-old.get('sent',0),'received':current['received']-old.get('received',0),'latency':{k:v for k,v in h.view().items() if k not in ('bins','sum_ms')}}
        previous_live=value['persistent'];previous_stamp=now
        record=json_bytes(value)+b'\n';journal.write(record);digest.update(record);info['minute_samples']+=1;report['stage_journal_records']+=1
    pool=concurrent.futures.ThreadPoolExecutor(max_workers=6);observer=threading.Thread(target=observe,name='endurance-observer',daemon=True)
    journal=None;awake=None;previous_awake=0
    try:
        if os.name=='nt':
            import ctypes
            awake=ctypes.WinDLL('kernel32',use_last_error=True).SetThreadExecutionState
            awake.argtypes=[ctypes.c_uint32];awake.restype=ctypes.c_uint32
            previous_awake=awake(0x80000001)
            if not previous_awake:raise ValueError('TRAFFIC_ENDURANCE_AWAKE_REQUEST_FAILED')
            info['sleep_inhibition_verified']=True
        journal=open(output+'.stages.jsonl','xb')
        for name,task,kw in [('tcp','echo',{'rate_exchanges_per_second':2}),('udp','udp',{'rate_packets_per_second':5})]:
            j=make('persistent.'+name,task,seconds,endurance=True,**kw);origin_metrics(j)
            channels['persistent.'+name]={'runs':0,'failures':0,'state':'RUNNING'}
            pending[pool.submit(execute,j)]=('persistent.'+name,j)
            report['workload_started_stage_count']+=1
        observer.start();persist();index=0;app_index=0
        apps=APPLICATIONS
        while time.monotonic()<deadline and not cancelled(job) and not fatal:
            position=(time.monotonic()-started)%_cycle_seconds/_cycle_seconds
            phase='normal' if position<1/3 else 'burst' if position<.5 else 'churn' if position<2/3 else 'quiet' if position<5/6 else 'recovery'
            span=min(_window_seconds,deadline-time.monotonic())
            if span<.05:
                time.sleep(max(0,span));continue
            wave={}
            if span>=5:
                wave['policies']=make('window'+str(index)+'.policies','echo',span)
            if phase!='quiet':
                rate={'normal':6,'burst':10,'churn':2,'recovery':1}[phase]*1048576
                if 'bulk' not in sticky:wave['bulk']=make('window'+str(index)+'.bulk','duplex',span,rate_bytes_per_second=rate)
                if phase=='churn' and 'churn' not in sticky:wave['churn']=make('window'+str(index)+'.churn','flow_rate',span,rate_flows_per_second=3)
                app=apps[app_index%len(apps)];app_index+=1
                if 'app-'+app not in sticky:wave['app-'+app]=make('window'+str(index)+'.app', 'udp' if app=='quic' else 'echo',span,application=app,rate_packets_per_second=3 if app!='quic' else 1)
            for name,j in wave.items():
                if name=='policies':
                    from trafficlab.endurance_policy import check
                    pending[pool.submit(check,j)]=(name,j)
                    continue
                evidence=origin_metrics(j)
                if j.get('application'):j.update(_endurance_bounded=True,_worker_directory=str(Path(output).parent),_worker_process={},_isolated_origin_evidence=evidence)
                pending[pool.submit(execute_bounded if j.get('application') else execute,j)]=(name,j)
                report['workload_started_stage_count']+=1
            window_end=min(deadline,time.monotonic()+span)
            while time.monotonic()<window_end and not cancelled(job) and not fatal:
                for future,(name,j) in list(pending.items()):
                    if future.done():accept(name,j,future.result(),journal);del pending[future]
                with lock:
                    for rid,value in live.items():
                        if value['invalid'] or value['reply_age_seconds']>10:
                            for _,(name,j) in pending.items():
                                if j['run_id']==rid:sticky.add(name);stop(j)
                time.sleep(min(.2,max(.001,window_end-time.monotonic())))
            # Drain finite jobs before creating new ones; no unbounded queue.
            for future,(name,j) in list(pending.items()):
                if not j.get('endurance'):
                    if cancelled(job) or fatal:stop(j)
                    accept(name,j,future.result(timeout=25),journal);del pending[future]
            snapshot(journal,phase);journal.flush();os.fsync(journal.fileno());report['stage_journal_sha256']=digest.hexdigest()
            with lock:persist()
            index+=1
        info['planned_walltime_completed']=time.monotonic()>=deadline and not cancelled(job) and not fatal
        for future,(name,j) in list(pending.items()):
            if cancelled(job) or fatal:stop(j)
            accept(name,j,future.result(timeout=25),journal);del pending[future]
        if fatal:report['errors'].extend(fatal)
        if sticky:report['errors'].append('TRAFFIC_ENDURANCE_CHANNEL_FAILURE')
        report['cancelled']=cancelled(job)
        report['product_route_confirmed']=route_ok
        policy_covered=all(channels.get(key,{}).get('runs',0)>0 for key in ('direct.tcp','direct.udp','block.tcp','block.udp'))
        if not policy_covered and not report['cancelled']:report['errors'].append('TRAFFIC_ENDURANCE_POLICY_COVERAGE_INCOMPLETE')
        report['complete']=info['planned_walltime_completed'] and not sticky and not fatal and route_ok and policy_covered
    except Exception as error:
        report['errors'].extend(fatal)
        report['errors'].append(type(error).__name__+':TRAFFIC_ENDURANCE_FAILED')
        report.setdefault('failure_detail',{'code':str(error)[:200]})
    finally:
        report['cancelled']=cancelled(job)
        if report['cancelled']:report['complete']=False
        for value in channels.values():
            if value['state']=='RUNNING':value['state']='CANCELLED' if report['cancelled'] else 'UNVERIFIED'
        for future,(_,j) in pending.items():stop(j)
        observer_stop.set()
        if observer.is_alive():observer.join(timeout=12)
        # Cancellation never returns while an owned traffic task is unobserved.
        try:
            for future in pending:future.result(timeout=25)
        except Exception as error:report['errors'].append('TRAFFIC_ENDURANCE_CLEANUP_UNVERIFIED');report['complete']=False
        pool.shutdown(wait=True,cancel_futures=True)
        if awake is not None and previous_awake:
            info['sleep_inhibition_released']=bool(awake(previous_awake|0x80000000))
            if not info['sleep_inhibition_released']:report['errors'].append('TRAFFIC_ENDURANCE_AWAKE_RELEASE_UNVERIFIED');report['complete']=False
        if journal is not None:journal.flush();os.fsync(journal.fileno());journal.close()
        report['stage_journal_sha256']=digest.hexdigest()
        with lock:
            view=resources.view();cpu=view.get('windows_system',{}).get('counters',{}).get('cpu_percent_of_pc',{})
            info['cpu_saturated']=cpu.get('max',0)>=90
            persist()
        atomic(progress,{'run_id':job['run_id'],'state':'COMPLETE' if report['complete'] else 'CANCELLED' if report['cancelled'] else 'FAILED','operation':'COMPLETE','elapsed_seconds':report['elapsed_seconds']})
    return report
