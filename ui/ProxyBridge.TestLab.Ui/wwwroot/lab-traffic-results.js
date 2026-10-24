"use strict";
// Summary first. Original evidence and detailed measurements remain available on demand.
Object.assign(labText.ru,{
  reportAllMetrics:'Все показатели',reportDownload:'Скачать итоги (JSON)',reportObserved:'Наблюдения: корректность обмена или маршрута не подтверждена',reportRuns:'Отчёты',reportCompare:'Сравнить прогоны',reportAdvanced:'Экспорт и расширенное сравнение',reportArchive:'Архив прежних отчётов',reportClose:'Закрыть',
  reportPassed:'Пройдено',reportFailed:'Ошибки',reportOther:'Не завершено',reportSteps:'этапов',reportCleanup:'Очистка подтверждена',reportUnclean:'Очистка не подтверждена',
  reportDetails:'Подробности и логи',reportTechnical:'Измерения и условия',reportJson:'Данные отчёта',reportLogs:'Логи и исходные результаты',reportNoLogs:'Лог для этого этапа не сохранён.',reportLoading:'Загрузка…',reportLogError:'Не удалось открыть данные.',reportSharedLog:'Общий лог ProxyBridge',reportNext:'Следующая часть',
  reportLoss:'Потери ответов',reportTransport:'Обмен не завершён',reportRoute:'Маршрут не подтверждён',reportCancelled:'Выполнение отменено',reportSkipped:'Не запускалось',reportStartup:'ProxyBridge не подтвердил готовность',reportUnknown:'Результат не подтверждён',reportOk:'Обмен и маршрут подтверждены',
  reportA:'Исходный прогон',reportB:'С чем сравнить',reportChoose:'Выберите прогон',reportCompareHelp:'Сначала выберите два прогона. Затем откройте нужную проверку.',reportSameRun:'Выбран один и тот же прогон.',reportNoPair:'Нет парного этапа в другом прогоне',reportDifferent:'Условия различаются — числовое сравнение недоступно',reportComparable:'Одинаковые условия',reportChanged:'Изменился статус',reportSpeed:'Скорость',reportLatency:'Задержка',reportResources:'Ресурсы',reportDelta:'Разница B − A',reportComplex:'Комплексный прогон',reportRecent:'Последние запуски',reportScope:'CPU и память относятся к процессу ProxyBridge; это не ресурсы драйвера.',
  trafficRunHelp:'Проверки выполняются последовательно. После обычной ошибки очередь продолжается, если изоляция подтверждена. Потеря сессии или неподтверждённое восстановление останавливают очередь.',
  suiteHelp:'Этапы выполняются последовательно. Ошибка сохраняется в отчёте; следующие этапы продолжаются после проверки изоляции. Отмена завершает нагрузку и выполняет очистку.',
  reportSoak:'В течение выбранного времени повторяются минутные интервалы: передача TCP в обе стороны, UDP и измерение задержки. До нагрузки и после неё проверяется восстановление. Данные и ресурсы записываются по интервалам.'
});
Object.assign(labText.en,{
  reportAllMetrics:'All measurements',reportDownload:'Download results (JSON)',reportObserved:'Observations: exchange or route correctness is unverified',reportRuns:'Reports',reportCompare:'Compare runs',reportAdvanced:'Export and advanced comparison',reportArchive:'Earlier report archive',reportClose:'Close',
  reportPassed:'Passed',reportFailed:'Failed',reportOther:'Unfinished',reportSteps:'stages',reportCleanup:'Cleanup verified',reportUnclean:'Cleanup unverified',
  reportDetails:'Details and logs',reportTechnical:'Measurements and conditions',reportJson:'Report data',reportLogs:'Logs and raw results',reportNoLogs:'No log was retained for this stage.',reportLoading:'Loading…',reportLogError:'Could not open evidence.',reportSharedLog:'Shared ProxyBridge log',reportNext:'Next part',
  reportLoss:'Reply loss',reportTransport:'Exchange incomplete',reportRoute:'Route unverified',reportCancelled:'Cancelled',reportSkipped:'Not started',reportStartup:'ProxyBridge readiness unconfirmed',reportUnknown:'Unverified result',reportOk:'Exchange and route verified',
  reportA:'Baseline run',reportB:'Compare with',reportChoose:'Choose a run',reportCompareHelp:'Choose two runs, then open a check.',reportSameRun:'The same run is selected twice.',reportNoPair:'Stage missing from the other run',reportDifferent:'Conditions differ — numeric comparison unavailable',reportComparable:'Matching conditions',reportChanged:'Status changed',reportSpeed:'Speed',reportLatency:'Latency',reportResources:'Resources',reportDelta:'Difference B − A',reportComplex:'Comprehensive run',reportRecent:'Recent runs',reportScope:'CPU and memory describe the ProxyBridge process, not the driver.',
  trafficRunHelp:'Checks run sequentially. Ordinary failures continue after verified isolation. Lost sessions or unverified recovery stop the queue.',
  suiteHelp:'Stages run sequentially. Failures remain in the report; the queue continues after verified isolation. Cancellation ends the workload and performs cleanup.',
  reportSoak:'Repeats one-minute intervals for the selected duration: bidirectional TCP, UDP and latency probes. Baseline and recovery are checked around the load. Traffic and resources are recorded per interval.'
});
Object.assign(labText.ru,{reportTrafficGroup:'Трафик',reportUdpGroup:'UDP',reportClientGroup:'Ресурсы процесса клиента',reportPcGroup:'Нагрузка на весь ПК',reportLoadGroup:'Нагрузка и восстановление',reportCpuMean:'CPU, % ПК · среднее',reportPrivatePeak:'Выделенная память (commit), МиБ · пик',reportResidentPeak:'Память в RAM, МиБ · пик',reportHandlesPeak:'Дескрипторы · пик',reportThreadsPeak:'Потоки · пик',reportPcCpu:'Общий CPU, % · среднее',reportPcHint:'Включает Windows, лабораторию и фоновые приложения.',reportSideBySide:'Разница показаний справочная: условия различаются.',reportDiffReasons:'Различия',reportDiffDuration:'длительность',reportDiffLoad:'нагрузка',reportDiffMode:'расположение получателя',reportDiffQueue:'состав очереди',reportDiffPosition:'позиция в очереди',reportDiffRuntime:'версия лаборатории',reportDiffMethod:'метод проверки',reportDiffMachine:'машина или ОС',reportDiffProduct:'тип или версия клиента',reportDiffOrigin:'получатель',reportDiffEnvironment:'параметры среды',reportDiffEvidence:'есть неуспешный или неподтверждённый этап',reportDiffMissing:'не хватает сведений об условиях',reportMissingValue:'Нет измерения'});
Object.assign(labText.en,{reportTrafficGroup:'Traffic',reportUdpGroup:'UDP',reportClientGroup:'Client process resources',reportPcGroup:'Whole PC load',reportLoadGroup:'Load and recovery',reportCpuMean:'CPU, % of PC · mean',reportPrivatePeak:'Private commit, MiB · peak',reportResidentPeak:'RAM: working set, MiB · peak',reportHandlesPeak:'Handles · peak',reportThreadsPeak:'Threads · peak',reportPcCpu:'Total CPU, % · mean',reportPcHint:'Includes Windows, the lab and background applications.',reportSideBySide:'The value difference is descriptive: conditions differ.',reportDiffReasons:'Differences',reportDiffDuration:'duration',reportDiffLoad:'load',reportDiffMode:'receiver location',reportDiffQueue:'queue selection',reportDiffPosition:'queue position',reportDiffRuntime:'lab version',reportDiffMethod:'test method',reportDiffMachine:'machine or OS',reportDiffProduct:'client type or version',reportDiffOrigin:'receiver',reportDiffEnvironment:'environment settings',reportDiffEvidence:'a stage failed or is unverified',reportDiffMissing:'condition evidence is missing',reportMissingValue:'Not measured'});
Object.assign(labText.ru,{reportBaseline:'Исходный',reportCandidate:'Сравниваемый',reportHigher:'выше',reportLower:'ниже',reportEqual:'Значения совпадают',reportBetter:'лучше',reportWorse:'хуже',reportScale:'У каждой пары общая шкала от нуля.',reportNumericDifference:'B − A',reportObservedDelta:'Справочная разница'});
Object.assign(labText.en,{reportBaseline:'Baseline',reportCandidate:'Candidate',reportHigher:'higher',reportLower:'lower',reportEqual:'Equal values',reportBetter:'better',reportWorse:'worse',reportScale:'Each pair shares a scale starting at zero.',reportNumericDifference:'B − A',reportObservedDelta:'Descriptive difference'});
let resultView='reports',evidenceSelection=null,evidenceSequence=0,reportHasData=false;
const trafficReportBuild=run=>labState.builds.find(build=>build.id===run.build_id)?.display_name||'ProxyBridge';
function trafficReportDate(run){const date=new Date(run.started_at_utc);return Number.isNaN(date.valueOf())?'—':date.toLocaleString(labLanguage==='ru'?'ru-RU':'en-GB',{day:'2-digit',month:'short',hour:'2-digit',minute:'2-digit'});}
function trafficReportStatus(row,attempt){
  if(!row?.cancelled&&row?.cleanup_verified!==false&&(row?.environment_limited||row?.errors?.includes('TRAFFIC_LAB_UDP_CAPACITY_UNVERIFIED')))return 'UNVERIFIED';
  if(attempt?.activity_observation==='UNCONFIRMED')return 'UNVERIFIED';
  if(!row)return ['PREPARING','RUNNING'].includes(attempt?.state)?'RUNNING':'MISSING';
  return row.complete&&row.cleanup_verified?'PASS':row.skipped?'SKIPPED':row.cancelled?'CANCELLED':trafficWorkloadComplete(row)?'UNVERIFIED':'FAIL';
}
function trafficReportBadge(status){const names={ru:{PASS:'Успешно',FAIL:'Ошибка',FAILED:'С ошибками',COMPLETE:'Завершён',CANCELLED:'Отменён',RUNNING:'Выполняется',PREPARING:'Подготовка',SKIPPED:'Пропущен',MISSING:'Нет результата',INCOMPLETE:'Не завершён',UNVERIFIED:'Не подтверждено'}};return `<span class="result-badge status-${html(status.toLowerCase())}">${html(names[labLanguage]?.[status]||status)}</span>`;}
function trafficReportCounts(run){
  const rows=run.results||[],passed=rows.filter(row=>trafficReportStatus(row,run)==='PASS').length,failed=rows.filter(row=>trafficReportStatus(row,run)==='FAIL').length;
  return {passed,failed,other:Math.max(0,(run.cases?.length||0)-passed-failed)};
}
function trafficReportReason(row,attempt){
  if(trafficReportStatus(row,attempt)==='UNVERIFIED'&&(row?.environment_limited||row?.errors?.includes('TRAFFIC_LAB_UDP_CAPACITY_UNVERIFIED')))return labLanguage==='ru'?'Стенд не выдержал нагрузку; результат клиента не подтверждён':'Lab capacity exceeded; product result unverified';
  const status=trafficReportStatus(row,attempt),errors=row?.errors||[],measure=row?.measurements?.find(item=>item.mode==='SOCKS5');
  if(status==='PASS')return t('reportOk');
  if(status==='UNVERIFIED'&&trafficWorkloadComplete(row)&&attempt?.activity_observation!=='UNCONFIRMED')return labLanguage==='ru'?'Измерения успешны; завершение не подтверждено':'Measurements passed; finalization unverified';
  if(status==='CANCELLED')return t('reportCancelled');
  if(['SKIPPED','MISSING'].includes(status))return t('reportSkipped');
  if(errors.includes('TRAFFIC_UDP_LOSS_THRESHOLD_EXCEEDED'))return t('reportLoss')+(typeof measure?.overall?.udp_loss_fraction==='number'?`: ${number(measure.overall.udp_loss_fraction*100,1)}%`:'');
  if(errors.some(code=>/CLI_(READINESS|CRASHED)/.test(code)))return t('reportStartup');
  if(errors.includes('TRAFFIC_TRANSPORT_INCOMPLETE'))return t('reportTransport');
  if(errors.includes('TRAFFIC_ROUTE_UNVERIFIED'))return t('reportRoute');
  return t('reportUnknown');
}
function trafficReportMeasurements(row){
  const measured=row?.measurements?.find(item=>item.mode==='SOCKS5');
  return trafficMetrics.map(key=>[key,trafficMeasurementMetric(measured,key)])
    .filter(([,value])=>typeof value==='number'&&Number.isFinite(value));
}
function trafficReportMetricMarkup(row){
  const values=new Map(trafficReportMeasurements(row));
  const integer=new Set(['trafficPeak','trafficCliHandles','trafficCliThreads','trafficTransactions',...Object.keys(trafficUdpCounters)]);
  const labels={trafficCpu:'reportCpuMean',trafficRam:'reportPrivatePeak',trafficCliResident:'reportResidentPeak',trafficCliHandles:'reportHandlesPeak',trafficCliThreads:'reportThreadsPeak',trafficSystemCpu:'reportPcCpu'};
  const groups=[
    ['reportTrafficGroup',['trafficSent','trafficReceived','trafficP99','trafficConnectP50','trafficConnectP95','trafficConnectP99','trafficTransactions','trafficPeak']],
    ['reportUdpGroup',['trafficUdpP99','trafficLoss',...Object.keys(trafficUdpCounters)]],
    ['reportClientGroup',['trafficCpu','trafficRam','trafficCliResident','trafficCliRamDelta','trafficCliResidentDelta','trafficCliHandles','trafficCliThreads']],
    ['reportPcGroup',['trafficSystemCpu']],
    ['reportLoadGroup',['trafficLoadTx','trafficLoadRx','trafficLoadMinTx','trafficLoadMinRx','trafficLoadWorstP99','trafficRecoveryP99Change']]
  ];
  const duplicate={trafficLoadTx:'trafficSent',trafficLoadRx:'trafficReceived',trafficLoadMinTx:'trafficSent',trafficLoadMinRx:'trafficReceived',trafficLoadWorstP99:'trafficP99'};
  return groups.map(([group,keys])=>{
    const rows=keys.filter(key=>values.has(key)&&!(key==='trafficTransactions'&&values.get(key)===0)&&!(duplicate[key]&&values.get(key)===values.get(duplicate[key])));
    if(!rows.length)return '';
    return `<section class="result-metric-group"><h5>${t(group)}</h5>${group==='reportPcGroup'?`<small>${t('reportPcHint')}</small>`:''}<div class="result-quick-metrics">${rows.map(key=>`<span>${html(t(labels[key]||key))}<b>${number(values.get(key),integer.has(key)?0:2)}</b></span>`).join('')}</div></section>`;
  }).join('');
}
function trafficReportChronological(runs){
  const time=run=>{const value=Date.parse(run.started_at_utc);return Number.isFinite(value)?value:0;};
  return [...runs].sort((a,b)=>time(b)-time(a)||String(b.id).localeCompare(String(a.id)));
}
function downloadTrafficReport(runId){
  const run=trafficHistory.find(item=>item.id===runId);if(!run)return;
  const blob=new Blob([JSON.stringify({schema_version:1,scope:'single-attempt',exported_at_utc:new Date().toISOString(),items:[run]},null,2)+'\n'],{type:'application/json;charset=utf-8'});
  const status=lab('traffic-download-status');
  if(blob.size>8*1024*1024){status.textContent=t('trafficExportTooLarge');return;}
  const url=URL.createObjectURL(blob),anchor=document.createElement('a');
  anchor.href=url;anchor.download=`testlab-${String(run.id).replace(/[^a-zA-Z0-9_-]/g,'_')}.json`;
  document.body.append(anchor);anchor.click();anchor.remove();setTimeout(()=>URL.revokeObjectURL(url),10000);
  status.textContent=t('trafficExportStarted');
}
function renderConciseTrafficHistory(){
  const stamp=JSON.stringify([trafficHistory,trafficCatalog,labLanguage,labState.builds,trafficSnapshotUnavailable]);
  if(trafficHistoryKey===stamp)return;const firstRender=!reportHasData&&trafficHistory.length>0;trafficHistoryKey=stamp;
  if(trafficHistory.length)reportHasData=true;
  const expanded=new Set([...lab('traffic-history').querySelectorAll('details[open][data-result-key]')].map(node=>node.dataset.resultKey));
  const order=trafficReportChronological(trafficHistory);
  lab('traffic-history').innerHTML=order.map((run,index)=>{
    const counts=trafficReportCounts(run),groups=trafficFamilyReportGroups(trafficCatalog,run.cases||[],run.results||[]),key=run.id;
    const label=(run.cases?.length||0)>=20?t('reportComplex'):t('reportRecent');
    return `<article class="result-run"><details data-result-key="${html(key)}" ${expanded.has(key)||firstRender&&index===0?'open':''}><summary class="result-run-heading"><span><small>${html(label)} · ${html(trafficReportDate(run))} · ${html(t(run.mode||'remote'))}</small><strong>${html(trafficReportBuild(run))}</strong></span><span>${trafficReportBadge(run.activity_observation==='UNCONFIRMED'?'UNVERIFIED':run.state)}<span class="result-counts"><b class="result-pass">${t('reportPassed')}: ${counts.passed}</b><b class="result-fail">${t('reportFailed')}: ${counts.failed}</b>${counts.other?`<b>${t('reportOther')}: ${counts.other}</b>`:''}</span></span></summary>
      <p class="result-cleanup">${t(run.cleanup_verified&&run.local_origin_cleanup_verified!==false?'reportCleanup':'reportUnclean')} · ${run.cases?.length||0} ${t('reportSteps')}</p>
      <div class="result-report-actions"><button type="button" class="button secondary" data-report-download="${html(key)}">${t('reportDownload')}</button></div>
      <div class="result-families">${groups.map(group=>`<details class="result-family" data-result-key="${html(key+'.'+group.family.id)}" ${expanded.has(key+'.'+group.family.id)?'open':''}><summary><strong>${html(trafficFamilyName(group.family))}</strong><span>${trafficReportBadge(group.status)} ${group.passed}/${group.stages.length}</span></summary><div class="result-stage-list">${group.stages.map((stage,i)=>{
        const row=group.rows[i],stageKey=key+'.'+group.family.id+'.'+stage.id;
        return `<details class="result-stage" data-result-key="${html(stageKey)}" ${expanded.has(stageKey)?'open':''}><summary><strong>${html(trafficName(stage.id))}</strong>${trafficReportBadge(trafficReportStatus(row,run))}</summary><div class="result-stage-content"><p>${html(trafficReportReason(row,run))}</p><small>${html(t(stage.duration))} · ${html(t(stage.load))}</small>${row?.measurements?.some(m=>m.mode==='SOCKS5'&&(!m.complete||!m.route_verified))?`<p class="result-observed">${t('reportObserved')}</p>`:''}${trafficReportMetricMarkup(row)}${row?`<button type="button" class="button secondary" data-evidence-run="${html(key)}" data-evidence-case="${html(stage.id)}">${t('reportDetails')}</button>`:''}</div></details>`;
      }).join('')}</div></details>`).join('')}</div></details></article>`;
  }).join('')||`<p>${t('trafficNone')}</p>`;
  renderRunComparison();
}

// Follow the existing matching-conditions policy; never subtract unrelated measurements.
function trafficReportConditionKey(run,row){
  const c=row?.conditions;
  if(!c||typeof c.local_runtime_sha256!=='string'||typeof c.origin_physical_memory_bytes!=='number')return null;
  const skip=new Set(['build_sha256','adapter_id','product_contract','product_version',...(c.runtime_mode==='local'?['remote_bundle_sha256','application_tls_sha256','application_ssh_sha256']:[])]);
  return JSON.stringify(Object.fromEntries(Object.keys(c).filter(key=>!skip.has(key)).sort().map(key=>[key,c[key]])));
}
function trafficReportComparable(a,ra,b,rb){
  const key=trafficReportConditionKey(a,ra);
  return !!key&&key===trafficReportConditionKey(b,rb)&&ra.duration===rb.duration&&ra.load===rb.load&&a.mode===b.mode&&
    trafficReportStatus(ra,a)==='PASS'&&trafficReportStatus(rb,b)==='PASS';
}
function trafficReportDifferences(a,ra,b,rb){
  if(!ra||!rb)return [];
  const reasons=new Set();
  for(const [key,label] of [['duration','reportDiffDuration'],['load','reportDiffLoad']])if(ra?.[key]!==rb?.[key])reasons.add(label);
  if(a.mode!==b.mode)reasons.add('reportDiffMode');
  if(!trafficReportConditionKey(a,ra)||!trafficReportConditionKey(b,rb))reasons.add('reportDiffMissing');
  const ignored=new Set(['build_sha256','adapter_id','product_contract','product_version',...(a.mode==='local'&&b.mode==='local'?['remote_bundle_sha256','application_tls_sha256','application_ssh_sha256']:[])]);
  const labels={queue_profile_sha256:'reportDiffQueue',case_position_in_queue:'reportDiffPosition',local_runtime_sha256:'reportDiffRuntime',method:'reportDiffMethod',execution_model:'reportDiffMethod',resource_product_scope:'reportDiffMethod',session_state:'reportDiffMethod',off_control_scope:'reportDiffMethod',python_version:'reportDiffRuntime',windows_version:'reportDiffMachine',logical_cpus:'reportDiffMachine',windows_node_binding:'reportDiffMachine',cpu_model:'reportDiffMachine',windows_physical_memory_bytes:'reportDiffMachine',product_contract:'reportDiffProduct',adapter_id:'reportDiffProduct',product_version:'reportDiffProduct',host_binding:'reportDiffOrigin',origin_scope:'reportDiffOrigin',origin_logical_cpus:'reportDiffOrigin',origin_physical_memory_bytes:'reportDiffOrigin',remote_bundle_sha256:'reportDiffOrigin',runtime_mode:'reportDiffMode'};
  const ca=ra?.conditions||{},cb=rb?.conditions||{};
  for(const key of new Set([...Object.keys(ca),...Object.keys(cb)]))if(!ignored.has(key)&&JSON.stringify(ca[key])!==JSON.stringify(cb[key]))reasons.add(labels[key]||'reportDiffEnvironment');
  if(trafficReportStatus(ra,a)!=='PASS'||trafficReportStatus(rb,b)!=='PASS')reasons.add('reportDiffEvidence');
  return [...reasons];
}
function trafficReportMetric(row,key){
  const m=row?.measurements?.find(value=>value.mode==='SOCKS5');
  if(key==='latency')return trafficMeasurementMetric(m,'trafficP99')??trafficMeasurementMetric(m,'trafficConnectP99');
  return trafficMeasurementMetric(m,{tx:'trafficSent',rx:'trafficReceived',latency:'trafficP99',udpLatency:'trafficUdpP99',loss:'trafficLoss',udpSent:'trafficUdpSent',udpReceived:'trafficUdpReceived',ram:'trafficRam',cpu:'trafficCpu'}[key]);
}
async function openTrafficEvidence(runId,caseId){
  const sequence=++evidenceSequence;
  evidenceSelection={runId,caseId};
  lab('traffic-evidence-title').textContent=trafficName(caseId);
  lab('traffic-evidence-content').textContent=t('reportLoading');
  const dialog=lab('traffic-evidence-dialog');if(!dialog.open)dialog.showModal();
  try{
    const response=await fetch(`/api/v1/lab/traffic/attempts/${encodeURIComponent(runId)}/evidence?caseId=${encodeURIComponent(caseId)}`,{cache:'no-store'});
    if(!response.ok)throw Error('evidence');const data=await response.json();if(sequence!==evidenceSequence)return;
    lab('traffic-evidence-content').innerHTML=`<p>${html(trafficReportBuild(trafficHistory.find(run=>run.id===runId)||{}))} · ${html(runId)}</p><h4>${t('reportLogs')}</h4><div class="evidence-log-buttons">${data.logs.map((log,index)=>`<button class="button secondary" type="button" data-evidence-file="${html(log.name)}">${html(log.name==='session.console.jsonl'?t('reportSharedLog'):log.name)} <small>${trafficLiveBytes(log.bytes)}</small></button>`).join('')||html(t('reportNoLogs'))}</div><p id="traffic-log-meta" role="status"></p><pre id="traffic-log-text" tabindex="0" hidden></pre><button id="traffic-log-next" type="button" class="button secondary" hidden>${t('reportNext')}</button><details class="evidence-technical"><summary>${t('reportTechnical')}</summary>${trafficVerboseCase(data.report)}</details><details><summary>${t('reportJson')}</summary><pre>${html(JSON.stringify(data.report,null,2))}</pre></details>`;
  }catch{if(sequence===evidenceSequence)lab('traffic-evidence-content').textContent=t('reportLogError');}
}
async function loadTrafficLog(name,offset=0){
  const selection=evidenceSelection,sequence=++evidenceSequence;
  lab('traffic-log-text').hidden=false;lab('traffic-log-text').textContent=t('reportLoading');
  lab('traffic-log-next').hidden=true;
  try{
    const response=await fetch(`/api/v1/lab/traffic/attempts/${encodeURIComponent(selection.runId)}/log?caseId=${encodeURIComponent(selection.caseId)}&name=${encodeURIComponent(name)}&offset=${offset}`,{cache:'no-store'});
    if(!response.ok)throw Error('log');const log=await response.json();if(sequence!==evidenceSequence)return;
    lab('traffic-log-text').textContent=log.text||'—';
    lab('traffic-log-meta').textContent=`${name} · ${log.offset||0}–${(log.offset||0)+log.preview_bytes} / ${log.total_bytes} B`;
    const next=lab('traffic-log-next');next.hidden=!log.has_more;next.dataset.name=name;next.dataset.offset=log.next_offset;
  }catch{if(sequence===evidenceSequence)lab('traffic-log-text').textContent=t('reportLogError');}
}
lab('traffic-results').addEventListener('click',event=>{
  const download=event.target.closest('[data-report-download]');if(download){downloadTrafficReport(download.dataset.reportDownload);return;}
  const details=event.target.closest('[data-evidence-run]');if(details){openTrafficEvidence(details.dataset.evidenceRun,details.dataset.evidenceCase);return;}
  const view=event.target.closest('[data-result-view]');if(view){resultView=view.dataset.resultView;lab('traffic-report-view').hidden=resultView!=='reports';lab('traffic-pair-view').hidden=resultView!=='compare';for(const button of lab('traffic-results').querySelectorAll('[data-result-view]'))button.setAttribute('aria-pressed',String(button===view));renderRunComparison();}
});
lab('traffic-evidence-content').addEventListener('click',event=>{
  const button=event.target.closest('[data-evidence-file]');if(button)loadTrafficLog(button.dataset.evidenceFile);
  if(event.target.id==='traffic-log-next')loadTrafficLog(event.target.dataset.name,Number(event.target.dataset.offset));
});
lab('traffic-evidence-close').addEventListener('click',()=>lab('traffic-evidence-dialog').close());
lab('traffic-evidence-dialog').addEventListener('close',()=>{evidenceSequence++;});
if(trafficCatalog){renderConciseTrafficHistory();renderRunComparison();}
