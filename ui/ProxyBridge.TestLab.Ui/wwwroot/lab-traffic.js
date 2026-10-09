"use strict";
Object.assign(labText.ru, {
  trafficHeading:"Трафик, скорость, нагрузка и стабильность", trafficScope:"Ubuntu 22.04. Проверка данных и маршрута, потери UDP, CPU/RAM всей ОС и CPU/RAM/handles/threads отдельных процессов. Число соединений и скорость не доказывают максимальную ёмкость или ресурсы драйвера.",
  trafficPrepare:"Проверить / подготовить runtime", trafficApply:"Установить по этому плану", trafficStart:"Запустить выбранные проверки", trafficStop:"Остановить и очистить", trafficDebugger:"WinDbg не запущен или все точки отключены; диагностический прогон не выполняется",
  trafficAdmin:"Для реальных проверок запустите scripts/Start-TestLabUi.ps1 -Administrator. При включённом UAC потребуется подтверждение.",
  trafficLongRun:"Разрешаю выбранный набор более 5 минут, включая 24/48/72 часа", trafficRunHelp:"Используется выбранная сборка. Перед каждым тестом проверяются файлы, получатель, OFF и UNRULED. SOCKS5 требует подписанных свидетельств. Неудачная очистка прекращает очередь.",
  trafficResults:"Удалённые проверки: история и измерения", trafficResultsHelp:"Ошибки и отмены сохраняются отдельно. CPU процесса нормирован на все логические CPU; RAM процесса не является памятью драйвера. Разные параметры и получатели сравнивайте отдельно.", trafficConditions:"Тест и условия", trafficAll:"Все попытки", trafficNone:"Удалённых попыток пока нет", trafficReady:"Состояние runtime", trafficEstimate:"Оценка с подготовкой", trafficPhase:"Этап", trafficSent:"Отправка, MiB/s", trafficReceived:"Получение, MiB/s", trafficP99:"RTT p99, мс", trafficLoss:"Потери UDP, %", trafficConnections:"TCP завершено / предложено", trafficCpu:"CLI CPU, % ПК", trafficRam:"CLI private commit, MiB", trafficEmpty:"Измерений нет",trafficMinutes:"мин",trafficRouteOk:"Маршрут подтверждён",trafficRouteBad:"Маршрут не подтверждён",trafficErrors:"Ошибки",trafficSkippedStages:"Пропущено этапов"
});
Object.assign(labText.en, {
  trafficHeading:"Traffic, speed, load and stability", trafficScope:"Ubuntu 22.04. Data and route validation, UDP loss, whole-OS CPU/RAM and CPU/RAM/handles/threads of identified processes. Connection count and speed do not establish absolute capacity or driver resource use.",
  trafficPrepare:"Check / prepare runtime", trafficApply:"Install this exact plan", trafficStart:"Start selected checks", trafficStop:"Stop and clean up", trafficDebugger:"WinDbg is closed or all breakpoints are disabled; no diagnostic run is active",
  trafficAdmin:"For real checks run scripts/Start-TestLabUi.ps1 -Administrator. With UAC enabled, Windows will request confirmation.",
  trafficLongRun:"I authorize this selection exceeding 5 minutes, including 24/48/72 hours", trafficRunHelp:"Uses the selected build. Files, origin, OFF and UNRULED are checked before each case. SOCKS5 requires signed evidence. Failed cleanup stops the queue.",
  trafficResults:"Remote checks: history and measurements", trafficResultsHelp:"Failures and cancellation are saved separately. Process CPU is normalized to all logical CPUs; process RAM is not driver memory. Compare different parameters and origins separately.", trafficConditions:"Case and conditions", trafficAll:"All attempts", trafficNone:"No remote attempts yet", trafficReady:"Runtime state", trafficEstimate:"Estimate including preparation", trafficPhase:"Stage", trafficSent:"Upload, MiB/s", trafficReceived:"Download, MiB/s", trafficP99:"RTT p99, ms", trafficLoss:"UDP loss, %", trafficConnections:"TCP completed / offered", trafficCpu:"CLI CPU, % of PC", trafficRam:"CLI private commit, MiB", trafficEmpty:"No measurements",trafficMinutes:"min",trafficRouteOk:"Route verified",trafficRouteBad:"Route unverified",trafficErrors:"Errors",trafficSkippedStages:"Skipped stages"
});
labText.ru.remoteTestGate='Для сетевых измерений используйте каталог ниже. Перед каждым тестом контроллер проверяет обмен и маршрут; неподтверждённый маршрут сохраняется как ошибка.';
labText.en.remoteTestGate='Use the traffic catalog below. The controller validates exchange and route before each case; an unverified route is saved as a failure.';
let trafficCatalog=null, trafficState=null, trafficHistory=[], trafficActionActive=false, trafficError="", trafficChoice={};
let trafficCardsKey="", trafficHistoryKey="", trafficLoading=false;
let trafficComparison=[],trafficComparisonKey="",trafficNextSkip=0,trafficHasMore=false,trafficCompareChoice={builds:{},metrics:{}};
Object.assign(labText.ru,{trafficMetrics:"Показатели",trafficCompare:"Последняя попытка каждой сборки при одинаковых условиях",trafficMore:"Ещё попытки",trafficSystemCpu:"Windows CPU, % ПК",trafficSystemRam:"Windows RAM, MiB",trafficOriginCpu:"Ubuntu CPU, % узла",trafficOriginRam:"Ubuntu RAM, MiB",trafficUdpP99:"UDP RTT p99, мс",trafficPeak:"Пик соединений TCP",trafficCleanup:"Очистка",trafficCliResident:"CLI working set, MiB",trafficWorkerCpu:"Работник CPU, % ПК",trafficWorkerRam:"Работник private commit, MiB",trafficOriginProcessCpu:"Origin/proxy CPU, % узла",trafficOriginProcessRam:"Origin/proxy RSS, MiB",trafficCliHandles:"CLI handles",trafficCliThreads:"CLI threads",trafficAllStages:"Сводные показатели включают все этапы: исходный, нагрузку и восстановление. CPU/RAM ОС включают фоновую работу. Пустое значение означает отсутствие подтверждённого измерения."});
Object.assign(labText.en,{trafficMetrics:"Metrics",trafficCompare:"Latest attempt for each build under matching conditions",trafficMore:"More attempts",trafficSystemCpu:"Windows CPU, % of PC",trafficSystemRam:"Windows RAM, MiB",trafficOriginCpu:"Ubuntu CPU, % of host",trafficOriginRam:"Ubuntu RAM, MiB",trafficUdpP99:"UDP RTT p99, ms",trafficPeak:"Peak TCP connections",trafficCleanup:"Cleanup",trafficCliResident:"CLI working set, MiB",trafficWorkerCpu:"Worker CPU, % of PC",trafficWorkerRam:"Worker private commit, MiB",trafficOriginProcessCpu:"Origin/proxy CPU, % of host",trafficOriginProcessRam:"Origin/proxy RSS, MiB",trafficCliHandles:"CLI handles",trafficCliThreads:"CLI threads",trafficAllStages:"Aggregates include every stage: baseline, load and recovery. Whole-OS CPU/RAM include background work. An empty value means no verified measurement is available."});
try{trafficCompareChoice=JSON.parse(localStorage.getItem("testlab-traffic-comparison")||"null")||trafficCompareChoice;}catch{}
try {trafficChoice=JSON.parse(localStorage.getItem("testlab-traffic-choice")||"{}");} catch {}
if(!trafficChoice||typeof trafficChoice!=='object'||Array.isArray(trafficChoice))trafficChoice={};
for(const [id,choice] of Object.entries(trafficChoice))if(!choice||!['SHORT','NORMAL','LONG'].includes(choice.duration)||!['LOW','HIGH'].includes(choice.load))delete trafficChoice[id];
if(!trafficCompareChoice||typeof trafficCompareChoice!=='object')trafficCompareChoice={};
trafficCompareChoice.builds=trafficCompareChoice.builds&&typeof trafficCompareChoice.builds==='object'?trafficCompareChoice.builds:{};
trafficCompareChoice.metrics=trafficCompareChoice.metrics&&typeof trafficCompareChoice.metrics==='object'?trafficCompareChoice.metrics:{};
const trafficCases=()=> (trafficCatalog?.cases||[]).filter(row=>trafficChoice[row.id]?.selected).map(row=>({id:row.id,duration:trafficChoice[row.id].duration,load:trafficChoice[row.id].load}));
const trafficCaseEstimate=row=>row.id==="soak"?({SHORT:24,NORMAL:48,LONG:72}[row.duration]*3600+300):({SHORT:6,NORMAL:30,LONG:120}[row.duration]*({"tcp-multistream":3,"loaded-rtt":3,"flow-rate":3,"mixed":3,"three-modes":3,"tcp-connections":5,"udp-connections":5,"udp-sweep":6,"stability":10}[row.id]||1)+20);
const trafficEstimate=()=>trafficCases().reduce((sum,row)=>sum+trafficCaseEstimate(row),0);
const trafficName=id=>trafficCatalog?.cases.find(row=>row.id===id)?.[labLanguage]||id;
function renderTraffic(){
  const remote=lab("lab-mode").value==="remote", active=!!trafficState?.execution?.active;
  lab("traffic-testing").hidden=!remote; lab("traffic-run").hidden=!remote;
  lab("lab-test-selection").hidden=remote; lab("lab-testing-time").hidden=remote;
  const busy=trafficActionActive||active||runActive()||remoteActionActive||labActionActive;
  lab("lab-local-launch").hidden=remote;
  lab("scenario-description").hidden=remote;
  lab("traffic-plan").disabled=busy||!labState.csrf;
  lab("traffic-apply").disabled=busy||!trafficState?.runtime?.plan;
  lab("traffic-start").disabled=busy||!trafficState?.runtime?.administrator||!labState.observation?.build_id||!trafficCases().length||!lab("traffic-debugger-inactive").checked||trafficEstimate()>300&&!lab("traffic-long-run").checked;
  lab("traffic-stop").disabled=!active||trafficActionActive;
  const plan=trafficState?.runtime?.plan;
  lab("traffic-runtime-status").textContent=`${t("trafficReady")}: ${trafficState?.runtime?.state||"VALIDATION_REQUIRED"}`;
  lab("traffic-runtime-plan").hidden=!plan;
  lab("traffic-runtime-plan").textContent=plan?JSON.stringify({ubuntu:plan.ubuntuVersion,bundle:plan.bundleSha256,files:plan.files,tcp:plan.tcpPorts,udp:plan.udpPorts,expires:plan.expiresUtc},null,2):"";
  lab("traffic-estimate").textContent=`${t("trafficEstimate")}: ${number(trafficEstimate()/60,1)} ${t("trafficMinutes")}`;
  const run=trafficState?.execution?.run, progress=trafficState?.execution?.progress;
  lab("traffic-run-status").textContent=[labState.builds.find(build=>build.id===labState.observation?.build_id)?.display_name,run?.state,progress?.stage,progress?.index!==undefined?`${progress.index+1}/${progress.total}`:"",run?.id].filter(Boolean).join(" · ");
  lab("traffic-error").textContent=trafficError||run?.error||(!trafficState?.runtime?.administrator?t("trafficAdmin"):"");
  const cardsKey=JSON.stringify([trafficCatalog,trafficChoice,labLanguage,busy]);
  if(trafficCatalog && cardsKey!==trafficCardsKey) {trafficCardsKey=cardsKey;lab("traffic-cases").innerHTML=trafficCatalog.cases.map(row=>{
    const choice=trafficChoice[row.id]||{selected:false,duration:"SHORT",load:"LOW"};
    return `<div class="lab-test-card"><label><input type="checkbox" data-traffic-case="${row.id}" ${choice.selected?"checked":""} ${busy?"disabled":""}><span>${html(row[labLanguage])}</span></label><div class="lab-test-settings"><label>${t("duration")}<select data-traffic-duration="${row.id}" ${busy?"disabled":""}>${["SHORT","NORMAL","LONG"].map(value=>`<option value="${value}" ${value===choice.duration?"selected":""}>${row.id==="soak"?{SHORT:24,NORMAL:48,LONG:72}[value]+" h":t(value)}</option>`).join("")}</select></label><label>${t("load")}<select data-traffic-load="${row.id}" ${busy?"disabled":""}>${["LOW","HIGH"].map(value=>`<option value="${value}" ${value===choice.load?"selected":""}>${t(value)}</option>`).join("")}</select></label></div><p>${t("trafficEstimate")}: ≈ ${number(trafficCaseEstimate({id:row.id,duration:choice.duration})/60,1)} ${t("trafficMinutes")}</p></div>`;
  }).join("");}
  renderTrafficHistory();
  renderTrafficComparison();
  if (typeof renderSavedSuites === "function") renderSavedSuites(busy);
}
function renderTrafficHistory(){
  const filter=lab("traffic-filter").value;
  const historyKey=JSON.stringify([trafficHistory,labLanguage,filter,labState.builds]);
  if(historyKey===trafficHistoryKey)return;trafficHistoryKey=historyKey;
  const keys=[...new Set(trafficHistory.flatMap(attempt=>(attempt.cases||[]).map(row=>`${row.Id||row.id}|${row.Duration||row.duration}|${row.Load||row.load}`)))];
  lab("traffic-filter").innerHTML=`<option value="all">${t("trafficAll")}</option>`+keys.map(key=>`<option value="${html(key)}">${html(key.split("|").map((part,index)=>index===0?trafficName(part):part).join(" · "))}</option>`).join("");
  if(keys.includes(filter)) lab("traffic-filter").value=filter;
  const selected=lab("traffic-filter").value;
  lab("traffic-history").innerHTML=trafficHistory.filter(attempt=>selected==="all"||(attempt.cases||[]).some(row=>`${row.Id||row.id}|${row.Duration||row.duration}|${row.Load||row.load}`===selected)).map(attempt=>{
    const name=labState.builds.find(build=>build.id===attempt.build_id)?.display_name||attempt.build_id;
    const rows=(attempt.results||[]).filter(row=>selected==="all"||`${row.case_id}|${row.duration}|${row.load}`===selected);
    return `<article class="lab-test-card"><h4>${html(name||"")} · ${html(attempt.state)} · ${html(attempt.id)}</h4><p>${html(attempt.error||"")}</p>${rows.map(row=>`<details><summary>${html(trafficName(row.case_id))} · ${html(row.duration)} / ${html(row.load)} · ${row.complete?"PASS":row.skipped?"SKIPPED":row.cancelled?"CANCELLED":"FAIL"}</summary><p>${t("trafficCleanup")}: ${row.cleanup_verified?"PASS":"UNVERIFIED"} · ${html((row.errors||[]).join(" · "))}</p>${(row.measurements||[]).map(measurement=>{
      const cpu=measurement.resources?.product_cli?.counters?.cpu_percent_of_pc?.mean,ram=measurement.resources?.product_cli?.counters?.private_bytes?.max;
      return `<h5>${html(measurement.mode)} · ${measurement.route_verified?t("trafficRouteOk"):t("trafficRouteBad")}</h5><p>${t("trafficSkippedStages")}: ${measurement.skipped_stage_count||0} · ${html((measurement.schedule_errors||[]).join(" · "))}</p><p>${t("trafficCpu")}: ${number(cpu)} · ${t("trafficRam")}: ${number(typeof ram==="number"?ram/1048576:null)}</p><p>${t("trafficSystemCpu")}: ${number(measurement.resources?.windows_system?.counters?.cpu_percent_of_pc?.mean)} · ${t("trafficOriginCpu")}: ${number(measurement.resources?.origin_system?.counters?.cpu_percent_of_pc?.mean)}</p><div class="lab-table-scroll"><table><thead><tr>${["trafficPhase","trafficSent","trafficReceived","trafficP99","trafficUdpP99","trafficLoss","trafficConnections","trafficPeak","trafficErrors"].map(key=>`<th>${t(key)}</th>`).join("")}</tr></thead><tbody>${measurement.stages.map(stage=>`<tr><td>${html(stage.phase)} · ${stage.complete?"PASS":"FAIL"}</td><td>${number(stage.tcp_tx_bytes_per_second/1048576)}</td><td>${number(stage.tcp_rx_bytes_per_second/1048576)}</td><td>${number(stage.probe_p99_ms)}</td><td>${number(stage.udp_latency?.p99_ms)}</td><td>${number(typeof stage.udp_loss_fraction==="number"?stage.udp_loss_fraction*100:null)}</td><td>${stage.tcp_completed}/${stage.tcp_offered}</td><td>${number(stage.tcp_active_peak)}</td><td>${html((stage.errors||[]).join(" · "))}</td></tr>`).join("")}</tbody></table></div>`;
    }).join("")||`<p>${t("trafficEmpty")}</p>`}</details>`).join("")}</article>`;
  }).join("")||`<p>${t("trafficNone")}</p>`;
}
const trafficMetrics=["trafficSent","trafficReceived","trafficP99","trafficUdpP99","trafficLoss","trafficCpu","trafficRam","trafficSystemCpu","trafficSystemRam","trafficOriginCpu","trafficOriginRam","trafficPeak","trafficCliResident","trafficWorkerCpu","trafficWorkerRam","trafficOriginProcessCpu","trafficOriginProcessRam","trafficCliHandles","trafficCliThreads"];
const trafficDefaultMetrics=new Set(["trafficSent","trafficReceived","trafficP99","trafficUdpP99","trafficLoss","trafficCpu","trafficCliResident","trafficSystemCpu","trafficOriginCpu"]);
const trafficMetricSelected=key=>trafficCompareChoice.metrics[key]??trafficDefaultMetrics.has(key);
function trafficMetric(row,key){
  if(!row.complete)return null;
  const measured=(row.result?.measurements||[]).find(value=>value.mode==="SOCKS5"&&value.complete&&value.route_verified);
  if(!measured)return null;
  const overall=measured.overall||{},resources=measured.resources||{};
  const counter=(role,name,stat)=>resources[role]?.counters?.[name]?.[stat];
  const values={trafficSent:overall.tcp_tx_bytes_per_second/1048576,trafficReceived:overall.tcp_rx_bytes_per_second/1048576,
    trafficP99:overall.probe_latency?.p99_ms,trafficUdpP99:overall.udp_latency?.p99_ms,
    trafficLoss:typeof overall.udp_loss_fraction==="number"?overall.udp_loss_fraction*100:null,
    trafficCpu:counter("product_cli","cpu_percent_of_pc","mean"),trafficRam:counter("product_cli","private_bytes","max")/1048576,
    trafficSystemCpu:counter("windows_system","cpu_percent_of_pc","mean"),trafficSystemRam:counter("windows_system","physical_used_bytes","max")/1048576,
    trafficOriginCpu:counter("origin_system","cpu_percent_of_pc","mean"),trafficOriginRam:counter("origin_system","physical_used_bytes","max")/1048576,
    trafficCliResident:counter("product_cli","working_set_bytes","max")/1048576,trafficWorkerCpu:counter("worker","cpu_percent_of_pc","mean"),trafficWorkerRam:counter("worker","private_bytes","max")/1048576,trafficOriginProcessCpu:counter("origin_and_proxy","cpu_percent_of_pc","mean"),trafficOriginProcessRam:counter("origin_and_proxy","working_set_bytes","max")/1048576,trafficCliHandles:counter("product_cli","handles","max"),trafficCliThreads:counter("product_cli","threads","max"),trafficPeak:measured.tcp_active_peak??((measured.stages||[]).some(stage=>typeof stage.tcp_active_peak==="number")?Math.max(...(measured.stages||[]).map(stage=>stage.tcp_active_peak||0)):null)};
  return Number.isFinite(values[key])?values[key]:null;
}
function renderTrafficComparison(){
  const select=lab("traffic-comparison-filter"),previous=select.value;
  const key=JSON.stringify([trafficComparison,labLanguage,previous,trafficCompareChoice,labState.builds]);
  if(key===trafficComparisonKey)return;trafficComparisonKey=key;
  const groups=new Map();for(const row of trafficComparison)groups.set(`${row.case_id}|${row.duration}|${row.load}|${row.condition_id}`,row);
  select.innerHTML=[...groups].map(([id,row])=>`<option value="${html(id)}">${html(`${trafficName(row.case_id)} · ${row.duration}/${row.load} · ${row.condition_id.slice(0,12)}`)}</option>`).join("");
  if(groups.has(previous))select.value=previous;
  const rows=trafficComparison.filter(row=>`${row.case_id}|${row.duration}|${row.load}|${row.condition_id}`===select.value);
  const name=row=>labState.builds.find(build=>build.id===row.build_id)?.display_name||row.build_id;
  lab("traffic-comparison-builds").innerHTML=rows.map(row=>`<label><input type="checkbox" data-traffic-build="${html(row.build_id)}" ${trafficCompareChoice.builds[row.build_id]!==false?"checked":""}>${html(name(row))}</label>`).join("");
  lab("traffic-comparison-metrics").innerHTML=trafficMetrics.map(metric=>`<label><input type="checkbox" data-traffic-metric="${metric}" ${trafficMetricSelected(metric)?"checked":""}>${html(t(metric))}</label>`).join("");
  const metrics=trafficMetrics.filter(metric=>trafficMetricSelected(metric));
  lab("traffic-comparison").innerHTML=rows.length?`<p>${html(t("trafficAllStages"))}</p><div class="lab-table-scroll"><table><thead><tr><th>${t("connection")}</th><th>Status</th>${metrics.map(metric=>`<th>${html(t(metric))}</th>`).join("")}</tr></thead><tbody>${rows.filter(row=>trafficCompareChoice.builds[row.build_id]!==false).map(row=>`<tr><td>${html(name(row))}<br><small>${html(row.attempt_id)}</small></td><td>${row.complete?"PASS":html(row.state)}<br>${html((row.result?.errors||[row.error]).filter(Boolean).join(" · "))}</td>${metrics.map(metric=>`<td>${number(trafficMetric(row,metric))}</td>`).join("")}</tr>`).join("")}</tbody></table></div><details><summary>${t("trafficConditions")}</summary><pre>${html(JSON.stringify(rows[0].conditions,null,2))}</pre></details>`:`<p>${t("trafficNone")}</p>`;
}
for(const id of ["traffic-comparison-builds","traffic-comparison-metrics"])lab(id).addEventListener("change",event=>{
  const build=event.target.dataset.trafficBuild,metric=event.target.dataset.trafficMetric;
  if(build)trafficCompareChoice.builds[build]=event.target.checked;if(metric)trafficCompareChoice.metrics[metric]=event.target.checked;
  localStorage.setItem("testlab-traffic-comparison",JSON.stringify(trafficCompareChoice));renderTrafficComparison();
});
lab("traffic-comparison-filter").addEventListener("change",renderTrafficComparison);
lab("traffic-history-more").addEventListener("click",async()=>{
  lab("traffic-history-more").disabled=true;
  try{
    const response=await fetch(`/api/v1/lab/traffic/history?skip=${trafficNextSkip}`,{cache:"no-store"});if(!response.ok)throw new Error("TRAFFIC_HISTORY_UNAVAILABLE");
    const data=await response.json(),loaded=new Map(trafficHistory.map(row=>[row.id,row]));for(const row of data.items)loaded.set(row.id,row);
    trafficHistory=[...loaded.values()].sort((a,b)=>b.id.localeCompare(a.id));trafficNextSkip=data.next_skip;trafficHasMore=data.has_more;renderTrafficHistory();
    lab("traffic-history-more").hidden=!trafficHasMore;
  }catch(error){trafficError=error.message;}finally{lab("traffic-history-more").disabled=false;}
});
async function loadTraffic(){
  if(trafficLoading)return;trafficLoading=true;
  try{
    const responses=await Promise.all([fetch("/api/v1/lab/traffic/catalog",{cache:"no-store"}),fetch("/api/v1/lab/traffic/state",{cache:"no-store"}),fetch("/api/v1/lab/traffic/history",{cache:"no-store"}),fetch("/api/v1/lab/traffic/comparison",{cache:"no-store"})]);
    if(responses.some(response=>!response.ok)) throw new Error("TRAFFIC_STATUS_UNAVAILABLE");
    const data=await Promise.all(responses.map(response=>response.json())); trafficCatalog=data[0]; trafficState=data[1];
    const loaded=new Map(trafficHistory.map(row=>[row.id,row])); for(const row of data[2].items)loaded.set(row.id,row);
    trafficHistory=[...loaded.values()].sort((a,b)=>b.id.localeCompare(a.id));trafficComparison=data[3].items;
    if(!trafficNextSkip){trafficNextSkip=data[2].next_skip;trafficHasMore=data[2].has_more;}
    lab("traffic-history-more").hidden=!trafficHasMore;
  }catch(error){trafficError=error.message;}finally{trafficLoading=false;}
  renderTraffic();
}
async function trafficAction(action){
  if(trafficActionActive)return;
  trafficActionActive=true;trafficError="";renderTraffic();
  try{
    const body=action==="apply"?{planId:trafficState.runtime.plan.planId}:action==="start"?{buildId:labState.observation.build_id,cases:trafficCases(),debuggerInactive:lab("traffic-debugger-inactive").checked,allowLongRun:lab("traffic-long-run").checked}:{};
    const response=await fetch(`/api/v1/lab/traffic/${action}`,{method:"POST",headers:{"Content-Type":"application/json","X-TestLab-CSRF":labState.csrf},body:JSON.stringify(body)});
    const data=await response.json();if(!response.ok)throw new Error(data.error||"TRAFFIC_REQUEST_FAILED");
  }catch(error){trafficError=error.message;}finally{trafficActionActive=false;await loadTraffic();}
}
lab("traffic-cases").addEventListener("change",event=>{
  const id=event.target.dataset.trafficCase||event.target.dataset.trafficDuration||event.target.dataset.trafficLoad;if(!id)return;
  trafficChoice[id]={selected:lab("traffic-cases").querySelector(`[data-traffic-case="${id}"]`).checked,duration:lab("traffic-cases").querySelector(`[data-traffic-duration="${id}"]`).value,load:lab("traffic-cases").querySelector(`[data-traffic-load="${id}"]`).value};
  localStorage.setItem("testlab-traffic-choice",JSON.stringify(trafficChoice));renderTraffic();
});
for(const action of ["plan","apply","start","stop"])lab(`traffic-${action}`).addEventListener("click",()=>trafficAction(action));
for(const id of ["traffic-debugger-inactive","traffic-long-run","lab-mode"])lab(id).addEventListener("change",renderTraffic);
lab("traffic-filter").addEventListener("change",renderTrafficHistory);
const renderLabBeforeTraffic=renderLab;
renderLab=function(){renderLabBeforeTraffic();renderTraffic();};
loadTraffic();setInterval(()=>{if(!trafficActionActive)loadTraffic();},3000);
