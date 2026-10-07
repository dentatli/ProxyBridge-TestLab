"""Four controlled diagnostic cases; original failures remain failures."""
import argparse
import hashlib
import json
from pathlib import Path
import re
from pb_tcp_redirect_context_extended_report import evaluate as evaluate_extended
from pb_tcp_redirect_context_report import evaluate as evaluate_base
from pb_tcp_connections_report import read, jsonl, expected_preset, ENGINE, WHEEL

CASES=(('connectex-32','ConnectEx',32),('connectex-1','ConnectEx',1),
       ('connect-32','connect',32),('connect-1','connect',1))
CASE_METHOD='tcp-redirect-context-matrix-case-v1'
CLOSE_POLICY='pinned-proactor-shutdown-reset-close-v1'
CLOSE_SOURCE='3777dc92992769764dafcb4d7049bb4eb3fd3dd5c64cee67862b1283d439064e'

def options(launch,name):
    planned=[v.split(':',1)[1].lower() for v in launch['expected_arguments'] if v.lower().startswith('-'+name+':')]
    observed=[v.lower() for v in re.findall(r'(?:^|\s)-'+name+r':([^\s"]+)',launch['observed_command_line'],re.I)]
    return planned,observed

def evaluate_case(path, *, diagnostic_method=None, target_ip='127.0.0.1', receiver_evaluator=None):
    case_method=diagnostic_method or CASE_METHOD
    try:
        if diagnostic_method is None and read(path/'comparison-manifest.json')['method']=='tcp-redirect-context-matrix-case-v2':
            case_method='tcp-redirect-context-matrix-case-v2'
    except (OSError,KeyError,ValueError,TypeError):pass
    evaluator=evaluate_base if case_method=='tcp-redirect-kernel-context-v4' else evaluate_extended
    result=evaluator(path,diagnostic_method=case_method,report_method=case_method.removeprefix('tcp-'),
        distinguish_unidentified_connect_failures=(case_method in ('tcp-redirect-context-probes-v3','tcp-redirect-kernel-context-v4')),
        **(dict(target_ip=target_ip,receiver_evaluator=receiver_evaluator) if evaluator is evaluate_base else {}))
    try:
        failures=[p['process_start_failure'] for p in read(path/'proxy/run-receipt.json')['phases'] if 'process_start_failure' in p]
        if failures:
            result['process_start_failures']=failures
            result['errors'].insert(0,'NATIVE_PROCESS_START_FAILED: '+failures[0]['worker']+': '+failures[0]['error'])
    except (OSError,KeyError,ValueError,TypeError):pass
    try:
        manifest=read(path/'comparison-manifest.json')
        case=manifest['diagnostic_connection_case']
        expected=next(dict(id=id,connect_method=method,pending_limit=limit) for id,method,limit in CASES if id==case['id'])
        if case!=expected:raise ValueError('CASE_SETTINGS_INVALID')
        if manifest['workload_preset']!=expected_preset('SHORT','HIGH'):raise ValueError('CASE_PRESET_DIFFERS')
        result['diagnostic_connection_case']=case
        if result['status']=='DIAGNOSTIC_NOT_STARTED':return result
        mode=read(path/'proxy/run-receipt.json')
        config=read(path/'proxy/benchmark-config.json')
        if config['diagnostic_connection_case']!=case or config['method']!=case_method:raise ValueError('CASE_CONFIG_DIFFERS')
        if case_method.endswith('-v2') or case_method in ('tcp-redirect-context-probes-v3','tcp-redirect-kernel-context-v4'):
            if manifest['fixture_close_guard']!=CLOSE_POLICY or config['fixture_close_guard']!=CLOSE_POLICY:raise ValueError('CASE_CLOSE_POLICY_DIFFERS')
            freeze=read(path.parent/'runtime-plan.json')
            hashes={Path(f['path']).name.lower():f['sha256'].lower() for f in freeze['files']}
            if freeze['fixture_close_guard']!=CLOSE_POLICY or config['fixture_close_guard_sha256'].lower()!=hashes['pb_proactor_close_guard.py'] or config['proactor_runtime_sha256'].lower()!=hashes['proactor_events.py']:
                raise ValueError('CASE_CLOSE_GUARD_FREEZE_DIFFERS')
            if config['proxy_helper_sha256'].lower()!=hashes['pb_controlled_tcp_proxy.py'] or config['python_sha256'].lower()!=hashes['python.exe']:
                raise ValueError('CASE_CLOSE_GUARD_HELPER_RUNTIME_DIFFERS')
            events=jsonl(path/'proxy/proxy.jsonl')
            installed=[e for e in events if e['event']=='PROACTOR_CLOSE_GUARD_INSTALLED']
            if len(installed)!=1 or installed[0]['policy']!=CLOSE_POLICY or installed[0]['callback_source_sha256']!=CLOSE_SOURCE or installed[0]['local_port']!=54123 or installed[0]['process_id']!=config['proxy_pid']:
                raise ValueError('CASE_CLOSE_GUARD_INSTALL_UNCONFIRMED')
            handled=[e for e in events if e['event']=='PROACTOR_SHUTDOWN_RESET_HANDLED']
            for event in handled:
                if event['policy']!=CLOSE_POLICY or event['winerror']!=10054 or event['local_ip']!='127.0.0.1' or event['local_port']!=54123 or event['process_id']!=config['proxy_pid'] or event['socket_closed'] is not True or event['listener_detached'] is not True:
                    raise ValueError('CASE_CLOSE_GUARD_EVENT_INVALID')
            result['fixture_close_guard']=dict(policy=CLOSE_POLICY,handled_shutdown_resets=len(handled),product_errors_preserved=True)
        if config['engine_sha256'].lower()!=ENGINE or config['proxy_wheel_sha256'].lower()!=WHEEL or config['shutdown_mode']!='rude' or config['verify']!='data':raise ValueError('CASE_NATIVE_OR_FIXTURE_DIFFERS')
        sampler=read(path/'proxy/sampler-process.json')
        if sampler['exit_code']!=0 or sampler['forced_stop'] or not sampler['output_capture_complete']:raise ValueError('CASE_SAMPLER_CLEANUP_INCOMPLETE')
        if not any(r['event']=='STOPPED' and r['requested'] for r in jsonl(path/'proxy/pc-samples.jsonl')):raise ValueError('CASE_SAMPLER_STOP_UNCONFIRMED')
        idle=[]
        for stage in ('before','after'):
            state=read(path/'proxy'/('interception-'+stage+'.json'))
            loaded=read(path/'proxy'/('loaded-drivers-'+stage+'.json'));idle.append(loaded)
            if not state['current_driver_preparation_allowed'] or not state['wfp_detachment_observed'] or state['wfp']['service_state']!='Stopped':raise ValueError('CASE_SCOPED_DETACHMENT_UNCONFIRMED')
            if not state['windivert']['configured'] or not state['windivert']['files_verified'] or not state['windivert']['capture_complete'] or state['windivert']['status']!='NO_HANDLES_OBSERVED' or state['windivert']['observed_handle_count']!=0:
                raise ValueError('CASE_COMPATIBLE_WINDIVERT_IDLE_UNCONFIRMED')
            if not loaded['query_complete'] or not loaded['known_interception_driver_names_absent']:raise ValueError('CASE_IDLE_INVENTORY_UNCONFIRMED')
        active=read(path/'proxy/loaded-drivers-active.json')
        if not active['query_complete'] or not active['selected_driver_loaded'] or len(active['known_interception_drivers'])!=1 or active['other_driver_names_sha256']!=idle[0]['other_driver_names_sha256'] or idle[1]['other_driver_names_sha256']!=idle[0]['other_driver_names_sha256']:
            raise ValueError('CASE_ACTIVE_OR_OTHER_DRIVER_INVENTORY_DIFFERS')
        if [(p['id'],p['requested_connections'],p['hold_seconds']) for p in mode['phases']]!=[
            ('baseline',4,8),('load-64',64,8),('load-256',256,8),('load-640',640,8),('recovery',4,8)]:raise ValueError('CASE_PHASES_DIFFERS')
        for phase in mode['phases']:
            folder=path/'proxy'/phase['id']
            launch=read(folder/'client-launch.json')
            client=read(folder/'client-process.json')
            server=read(folder/'receiver-process.json') if not receiver_evaluator else dict(timed_out=False,output_capture_complete=True)
            if phase['client_forced_stop'] or phase['server_forced_stop'] or client['timed_out'] or server['timed_out'] or not all(p['output_capture_complete'] for p in (client,server)):
                raise ValueError('CASE_NATIVE_CAPTURE_OR_CLEANUP_INCOMPLETE')
            if launch['pid']!=client['pid'] or Path(launch['observed_executable']).resolve()!=Path(client['actual_path']).resolve():raise ValueError('CASE_CLIENT_IDENTITY_DIFFERS')
            values=dict(conn=[case['connect_method'].lower()],throttleconnections=[str(case['pending_limit'])],
                connections=[str(phase['requested_connections'])],iterations=['1'],shutdown=['rude'],verify=['data'],
                transfer=['524288'],ratelimit=['65536'],port=['54122'],target=[target_ip])
            for name,expected_value in values.items():
                if options(launch,name)!=(expected_value,expected_value):raise ValueError('CASE_LIVE_ARGUMENT_DIFFERS: '+name)
    except (OSError,KeyError,ValueError,TypeError,StopIteration) as error:
        result['errors'].append('INCOMPLETE_MATRIX_CASE_EVIDENCE: '+str(error))
    if result['errors']:result['status']='DIAGNOSTIC_CAPTURE_INCOMPLETE'
    return result

def evaluate_matrix(path):
    result=dict(schema_version=1,method='redirect-context-matrix-v1',diagnostic_only=True,performance_comparable=False,
        product_correctness_pass=False,kernel_root_cause_proven=False,table_overflow_proven=False,errors=[],cases=[])
    try:
        manifest=read(path/'matrix-manifest.json')
        if manifest['method']=='redirect-context-matrix-v2':
            result['method']=manifest['method']
            if manifest['fixture_close_guard']!=CLOSE_POLICY:raise ValueError('MATRIX_CLOSE_POLICY_DIFFERS')
            result['fixture_close_guard']=CLOSE_POLICY
        if manifest['method']!=result['method'] or manifest['diagnostic_only'] is not True or manifest['performance_comparable'] is not False:
            raise ValueError('MATRIX_MANIFEST_INVALID')
        if [c['id'] for c in manifest['cases']]!=[c[0] for c in CASES]:raise ValueError('MATRIX_CASE_ORDER_DIFFERS')
        if manifest['status']!='COMPLETED':result['errors'].append('MATRIX_NOT_COMPLETED: '+manifest.get('error',''))
        for saved,(id,method,limit) in zip(manifest['cases'],CASES):
            if saved['directory']!=id:raise ValueError('MATRIX_CASE_PATH_INVALID')
            item=dict(id=id,connect_method=method,pending_limit=limit,run_status=saved['status'],metadata_status='NOT_CAPTURED')
            if saved['status']!='CONTROLLER_RETURNED':result['errors'].append(id+': '+saved['status'])
            child=path/id
            if child.exists():
                case=evaluate_case(child)
                if result['method'].endswith('-v2') and case['method']!='redirect-context-matrix-case-v2':
                    result['errors'].append(id+': CASE_METHOD_DIFFERS')
                item.update(metadata_status=case['status'],native_failed=case.get('native_failed'),query_count=case.get('query_count'),
                    followup_count=case.get('followup_count'),phases=[{k:p[k] for k in ('id','requested','successful','failed')} for p in case['phases']],
                    errors=case['errors'],records_observations=case.get('records_observations',{}),context_observations=case.get('context_observations',{}))
                result['errors'].extend(id+': '+e for e in case['errors'])
                if 'fixture_close_guard' in case:item['fixture_close_guard']=case['fixture_close_guard']
                if 'process_start_failures' in case:item['process_start_failures']=case['process_start_failures']
            result['cases'].append(item)
        result['source_sha256']={str(p.relative_to(path)):hashlib.sha256(p.read_bytes()).hexdigest() for p in path.rglob('*')
            if p.is_file() and p.name not in ('redirect-context-matrix-report.json','redirect-context-matrix-summary.md','diagnostic-run.json')}
    except (OSError,KeyError,ValueError,TypeError) as error:result['errors'].append('INCOMPLETE_MATRIX_EVIDENCE: '+str(error))
    result['status']='DIAGNOSTIC_MATRIX_INCOMPLETE' if result['errors'] else 'DIAGNOSTIC_MATRIX_METADATA_CORRELATED'
    result['interpretation']='Sequential cases vary connection API and pending-attempt limit. Differences suggest hypotheses; no kernel cause, capacity, performance comparison or product fix is proven.'
    return result

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence-directory',type=Path,required=True)
    parser.add_argument('--case',action='store_true')
    args=parser.parse_args();result=(evaluate_case if args.case else evaluate_matrix)(args.evidence_directory)
    name='redirect-context-report.json' if args.case else 'redirect-context-matrix-report.json'
    (args.evidence_directory/name).write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    if not args.case:
        lines=['# Несколько гипотез в одном диагностическом запуске','',result['status'],'',
            '| Подключение | Одновременно ожидают подключения, максимум | Успешные передачи при 256 | При 640 | Восстановление | API-отказы |',
            '|---|---:|---:|---:|---:|---:|']
        for case in result['cases']:
            phases={p['id']:p for p in case.get('phases',[])}
            def cell(id):
                p=phases.get(id);return str(p['successful'])+'/'+str(p['requested']) if p else '—'
            lines.append(f"| {case['connect_method']} | {case['pending_limit']} | {cell('load-256')} | {cell('load-640')} | {cell('recovery')} | {case.get('native_failed','—')} |")
        lines+=['','Исходные CLI/driver и тот же диагностический Core. Между вариантами — проверенное завершение и новый запуск продукта; восстановление внутри варианта без перезапуска.',
            'Метаданные не являются PASS продукта или сравнением скорости. Неполные и пропущенные варианты остаются видимыми; отсутствие ошибок при иных условиях не исправляет исходный дефект.']
        lines+=result['errors']
        (args.evidence_directory/'redirect-context-matrix-summary.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print(json.dumps(dict(status=result['status'],diagnostic_only=True,errors=result['errors'])))
    return bool(result['errors'])

if __name__=='__main__':raise SystemExit(main())
