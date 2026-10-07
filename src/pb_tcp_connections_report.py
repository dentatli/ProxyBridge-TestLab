"""Verified concurrent ctsTraffic cohorts, scoped cleanup and same-session recovery."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import re
import statistics

ENGINE='0548089e59c872306ce2c98e7163e2a717119756010cf64d3cb3da2854f632cf'
WHEEL='5190d3ae00a29325ec9048306fcd8bd08f8e89ddd75c535cc01d1d646f105344'

def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def jsonl(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8-sig').splitlines() if line]

def csv_rows(path):
    raw=path.read_bytes()
    return list(csv.DictReader(raw.decode('utf-16' if raw.startswith(b'\xff\xfe') else 'utf-8-sig').splitlines()))

def expected_preset(duration,load):
    seconds={'SHORT':8,'NORMAL':32,'LONG':120}[duration]
    if load not in ('LOW','HIGH'):raise ValueError('unsupported load')
    return dict(method='tcp-connection-load-v1',duration=duration,load=load,levels=[64,256,640] if load=='HIGH' else [8,32,64],hold_seconds=seconds,
        reference_connections=4,reference_seconds=8,rate_per_connection_bytes_per_s=65536,native_timeout_ms=600000,
        proxy_event_loop='ProactorEventLoop',minimum_available_bytes=2147483648 if load=='HIGH' else 536870912)

def phases(preset):
    return [('baseline','baseline',4,8)]+[('load-'+str(n),'load',n,preset['hold_seconds']) for n in preset['levels']]+[('recovery','recovery',4,8)]

def resources(samples,start,end,pids,errors):
    result={}
    for role,pid in pids.items():
        if not any(r['event']=='WATCHED' and r['role']==role and r['pid']==pid for r in samples):errors.append(role+': process not watched')
        values=[(p,r['qpc_ms']) for r in samples if r['event']=='SAMPLE' and r['interval_start_qpc_ms']>=start and r['qpc_ms']<=end
            for p in r['processes'] if p['role']==role and p['pid']==pid and p['status']=='OBSERVED' and p['interval_start_qpc_ms']>=start]
        coverage=sum(t-p['interval_start_qpc_ms'] for p,t in values)
        if len(values)<3 or coverage<.65*(end-start):errors.append(role+': sampling coverage incomplete')
        result[role]=dict(samples=len(values),coverage_ms=coverage,cpu_pct_machine_mean=sum(p['cpu_pct_machine']*(t-p['interval_start_qpc_ms']) for p,t in values)/coverage if coverage else None,
            private_mib_mean=statistics.mean(p['private_bytes'] for p,t in values)/1048576 if values else None)
    return result

def evaluate_mode(path,preset):
    errors=[];receipt=read(path/'run-receipt.json');cfg=read(path/'benchmark-config.json');mode=receipt['mode']
    if receipt['status']!='COMPLETED' or not receipt['workers_stopped'] or not receipt['driver_stop_observed']:errors.append('Mode or cleanup incomplete')
    if cfg['method']!='tcp-connection-load-v1' or cfg['workload_preset']!=preset or cfg['engine_sha256'].lower()!=ENGINE or cfg['proxy_wheel_sha256'].lower()!=WHEEL or cfg['shutdown_mode']!='rude' or cfg['verify']!='data' or cfg['proxy_event_loop']!='ProactorEventLoop':errors.append('Frozen native/fixture/method conditions differ')
    for name in ('proxy','sampler'):
        process=read(path/(name+'-process.json'))
        if process['exit_code']!=0 or process['forced_stop'] or not process['output_capture_complete'] or 'Exception in callback' in process['stderr']:errors.append(name+': completion unconfirmed')
    before,after=[read(path/('loaded-drivers-'+stage+'.json')) for stage in ('before','after')]
    for state in (before,after):
        if not state['query_complete'] or not state['known_interception_driver_names_absent']:errors.append('Idle known driver inventory not confirmed')
    if before['other_driver_names_sha256']!=after['other_driver_names_sha256']:errors.append('Other driver inventory differs')
    for stage in ('before','after'):
        state=read(path/('interception-'+stage+'.json'))
        if not state['current_driver_preparation_allowed'] or not state['wfp_detachment_observed'] or state['wfp']['service_state']!='Stopped':errors.append('Scoped WFP cleanup not confirmed')
        if not state['windivert']['configured'] or not state['windivert']['files_verified'] or not state['windivert']['capture_complete'] or state['windivert']['status']!='NO_HANDLES_OBSERVED' or state['windivert']['observed_handle_count']!=0:errors.append('Compatible WinDivert idle observation not confirmed')
    proxy=jsonl(path/'proxy.jsonl');flows=[r for r in proxy if r['event']=='TCP_CONNECTED'];closes={r['connection_id']:r for r in proxy if r['event']=='FLOW_CLOSED'}
    if not any(r['event']=='LISTENING' and r['event_loop']=='ProactorEventLoop' for r in proxy) or not any(r['event']=='STOPPED' and r['shutdown_reason']=='STDIN_STOP' for r in proxy) or any(r['event']=='ERROR' for r in proxy):errors.append('Proactor fixture lifecycle unconfirmed')
    cli=None;routes=[]
    if mode=='PROXY':
        cli=read(path/'cli-lifecycle.json');active=read(path/'loaded-drivers-active.json');routes=read(path/'route-observations.json')
        if isinstance(routes,dict):routes=[routes]
        if not all(cli[k] for k in ('ready','graceful_stop','post_stop_verified','output_capture_complete')) or cli['forced_stop'] or cli['error']:errors.append('Product lifecycle unconfirmed')
        if not active['query_complete'] or not active['selected_driver_loaded'] or len(active['known_interception_drivers'])!=1 or active['other_driver_names_sha256']!=before['other_driver_names_sha256']:errors.append('Active selected driver unconfirmed')
        state=read(path/'interception-active.json')
        if state['wfp']['status']!='SERVICE_FILE_VERIFIED' or state['wfp']['service_state']!='Running' or not state['windivert']['files_verified'] or not state['windivert']['capture_complete'] or state['windivert']['status']!='NO_HANDLES_OBSERVED' or state['windivert']['observed_handle_count']!=0:errors.append('Active owned interception state unconfirmed')
    elif mode!='OFF' or flows or closes:errors.append('OFF fixture unexpectedly carried traffic')
    samples=jsonl(path/'pc-samples.jsonl');cohorts=[]
    if not any(r['event']=='STOPPED' and r['requested'] for r in samples):errors.append('Sampler controlled stop not confirmed')
    if [r['id'] for r in receipt['phases']]!=[p[0] for p in phases(preset)]:errors.append('Cohort order or recovery incomplete')
    for id,kind,count,seconds in phases(preset):
        d=path/id;problems=[];summary=dict(id=id,phase=kind,requested_connections=count,status='INCONCLUSIVE',errors=problems)
        try:
            r=read(d/'phase-receipt.json');client=read(d/'client-process.json');server=read(d/'receiver-process.json')
            a,b=csv_rows(d/'client.csv'),csv_rows(d/'receiver.csv');snapshot=read(d/'owned-socket-snapshot.json');launch=read(d/'client-launch.json')
            if r['status']!='OBSERVED' or r['client_forced_stop'] or r['server_forced_stop'] or client['timed_out'] or server['timed_out'] or not client['output_capture_complete'] or not server['output_capture_complete']:problems.append('Cohort capture or natural cleanup incomplete')
            for p in (client,server):
                if p['exit_code']!=0 or not re.search(r'Level of verification:\s*Connections & Data',p['stdout']):problems.append('Native verification did not pass')
            successful=[row for row in a if row['Result']=='Succeeded']
            summary.update(completed_connections=len(a),successful_connections=len(successful),failed_connections=sum(row['Result']!='Succeeded' for row in a),confirmed_concurrent_connections=len(snapshot['sockets']))
            if len(a)!=count or len(b)!=count or len(successful)!=count or any(row['Result']!='Succeeded' for row in b):problems.append('Requested connection/data completion count differs')
            index={row['ConnectionId']:row for row in b}
            if len(index)!=count or len({row['ConnectionId'] for row in a})!=count or set(index)!={row['ConnectionId'] for row in a}:problems.append('Independent receiver connection identities differ')
            phase_flows=[f for f in flows if r['start_qpc_ms']<=f['qpc_ms']<=r['end_qpc_ms']]
            if mode=='PROXY' and len(phase_flows)!=count:problems.append('Owned SOCKS flow count differs')
            by_peer={f"{f['outbound_local_ip']}:{f['outbound_local_port']}":f for f in phase_flows}
            for row in a:
                other=index.get(row['ConnectionId'])
                if not other:continue
                if not re.fullmatch(r'[0-9a-fA-F-]{36}',row['ConnectionId']) or int(row['SendBytes'])!=seconds*65536 or int(other['RecvBytes'])!=seconds*65536 or int(row['RecvBytes'])!=0 or int(other['SendBytes'])!=0:problems.append('Per-connection verified payload differs');break
                if row['RemoteAddress']!='127.0.0.1:54122' or other['LocalAddress']!='127.0.0.1:54122':problems.append('Unexpected controlled destination');break
                if mode=='OFF' and row['LocalAddress']!=other['RemoteAddress']:problems.append('Direct reciprocal endpoints differ');break
                if mode=='PROXY':
                    flow=by_peer.get(other['RemoteAddress']);closed=closes.get(flow['connection_id']) if flow else None
                    if not flow or flow['destination_ip']!='127.0.0.1' or flow['destination_port']!=54122 or not closed or closed['protocol']!='tcp' or closed['bytes_up']<seconds*65536:problems.append('Per-flow controlled proxy evidence incomplete');break
            owner=cli['pid'] if cli else client['pid'];port=54123 if cli else 54122
            sockets=snapshot['sockets']
            expected_ports={f['inbound_peer_port'] for f in phase_flows} if cli else {int(row['LocalAddress'].rsplit(':',1)[1]) for row in a}
            if snapshot['owner_pid']!=owner or snapshot['target_port']!=port or len(sockets)!=count or {s['LocalPort'] for s in sockets}!=expected_ports or any(s['OwningProcess']!=owner or s['RemoteAddress']!='127.0.0.1' or s['RemotePort']!=port for s in sockets):problems.append('Simultaneously owned socket snapshot incomplete')
            if not r['start_qpc_ms']<=snapshot['start_qpc_ms']<=snapshot['end_qpc_ms']<=r['end_qpc_ms']:problems.append('Owned socket snapshot outside cohort')
            values=dict(connections=[str(count)],iterations=['1'],throttleconnections=['32'],shutdown=['rude'],verify=['data'],transfer=[str(seconds*65536)],ratelimit=['65536'],port=['54122'])
            for name,expected in values.items():
                observed=re.findall(r'(?:^|\s)-'+name+r':([^\s"]+)',launch['observed_command_line'],re.I)
                planned=[v.split(':',1)[1] for v in launch['expected_arguments'] if v.lower().startswith('-'+name+':')]
                if observed!=expected or planned!=expected:problems.append('Native live option differs: '+name)
            if launch['pid']!=client['pid'] or Path(launch['observed_executable']).resolve()!=Path(client['actual_path']).resolve():problems.append('Native launch process identity differs')
            if cli:
                owned=[v for v in routes if v['event']=='RELAY_ACCEPTED_REDIRECT' and v['pid']==client['pid'] and v['destination_ip']=='127.0.0.1' and v['destination_port']==54122 and v['action']=='PROXY' and v.get('proxy_config_id')==1]
                if len(owned)<count:problems.append('Product per-connection redirect log incomplete; log loss is not packet loss')
            durations=[max(float(row['TimeMs']),float(index[row['ConnectionId']]['TimeMs'])) for row in a if row['ConnectionId'] in index]
            if len(durations)!=count or min(durations)<seconds*600:problems.append('Insufficient sustained cohort duration')
            pids=dict(receiver=server['pid'],generator=client['pid'],proxy=cfg['proxy_pid'])
            if cli:pids['proxybridge_cli']=cli['pid']
            pc=resources(samples,r['start_qpc_ms'],r['end_qpc_ms'],pids,problems)
            summary.update(verified_payload_bytes=sum(int(row['SendBytes']) for row in successful),transfer_ms_max=max(durations) if durations else None,pc=pc)
            summary['status']='MEASURED' if not problems else 'INCONCLUSIVE'
        except (OSError,ValueError,KeyError,TypeError) as exc:problems.append('Incomplete cohort evidence: '+type(exc).__name__)
        errors.extend(id+': '+p for p in problems);cohorts.append(summary)
    return dict(schema_version=1,status='MEASURED' if not errors else 'INCONCLUSIVE',errors=errors,mode=mode,cohorts=cohorts,
                recovery_verified=not errors and cohorts[-1]['status']=='MEASURED',config=cfg,bundle_sha256=read(path/'product-build.json')['bundle_sha256'],
                table_occupancy_observed=False,maximum_capacity_verified=False,rtt_measured=False,driver_only_resources_measured=False,normal_tcp_close_verified=False)

def evaluate_comparison(path):
    manifest=read(path/'comparison-manifest.json');preset=manifest['workload_preset'];errors=[]
    if preset!=expected_preset(preset['duration'],preset['load']) or manifest['status']!='COMPLETED' or manifest['method']!='tcp-connection-load-v1' or manifest['product_contract']!='driver' or [(r['mode'],r['directory'],r['status']) for r in manifest['runs']]!=[('OFF','off','COMPLETED'),('PROXY','proxy','COMPLETED')]:errors.append('Series method/order/completion invalid')
    modes=[evaluate_mode(path/mode,preset) for mode in ('off','proxy')]
    errors.extend(mode['mode']+': '+error for mode in modes for error in mode['errors'])
    if modes[0]['bundle_sha256']!=modes[1]['bundle_sha256'] or modes[0]['config']!=modes[1]['config']:
        # Process IDs naturally differ; the remaining actual tool conditions must match.
        configs=[{k:v for k,v in m['config'].items() if k not in ('proxy_pid','sampler_pid')} for m in modes]
        if modes[0]['bundle_sha256']!=modes[1]['bundle_sha256'] or configs[0]!=configs[1]:errors.append('Kit or tool conditions differ between paths')
    return dict(schema_version=1,scenario='tcp_connections',method='tcp-connection-load-v1',status='INCONCLUSIVE' if errors else 'LIMITED_COMPARISON',errors=errors,
                workload_preset=preset,modes=modes,bundle_sha256=modes[0]['bundle_sha256'],table_occupancy_observed=False,maximum_capacity_verified=False,
                rtt_measured=False,normal_tcp_close_verified=False,version_comparison=False,global_interception_state_observed=False,
                source_sha256={str(file.relative_to(path)).replace('\\','/'):hashlib.sha256(file.read_bytes()).hexdigest() for mode in ('off','proxy') for file in (path/mode).rglob('*') if file.is_file()},
                limits=['Fixed OFF/PROXY order; bounded TCP cohorts, not a proven full table or maximum capacity.',
                        'Recovery uses the same CLI and fixture. Native data verified; normal TCP close and RTT not tested.',
                        'Owned socket snapshots and resource collection are part of this diagnostic workload. Process CPU/RAM are not driver-only costs.'])

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--evidence-directory',type=Path,required=True);args=parser.parse_args()
    result=evaluate_comparison(args.evidence_directory)
    (args.evidence_directory/'comparison-report.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    lines=['# Соединения TCP: нагрузка и восстановление / TCP connections: load and recovery','',result['status'],'',
        '| Путь / Path | Фаза / Phase | Запрошено / Requested | Подтверждено одновременно / Confirmed simultaneous | Проверено данных / Verified data | Статус / Status |',
        '|---|---|---:|---:|---:|---|']
    for mode in result['modes']:
        for cohort in mode['cohorts']:lines.append(f"| {mode['mode']} | {cohort['id']} | {cohort['requested_connections']} | {cohort.get('confirmed_concurrent_connections','—')} | {cohort.get('verified_payload_bytes','—')} | {cohort['status']} |")
    lines+=['','Занятость внутренней таблицы и её переполнение не наблюдались. / Internal table occupancy or overflow not observed.']+result['limits']+result['errors']
    (args.evidence_directory/'summary.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print(json.dumps(dict(status=result['status'],errors=result['errors']),ensure_ascii=False))
    return bool(result['errors'])

if __name__=='__main__':raise SystemExit(main())
