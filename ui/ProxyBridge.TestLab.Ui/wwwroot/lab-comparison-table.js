"use strict";
Object.assign(labText.ru,{trafficOffP99:'OFF: RTT p99, мс',trafficUnruledP99:'UNRULED: RTT p99, мс',trafficSocksP99:'SOCKS5: RTT p99, мс',trafficCompleted:'Завершено TCP-соединений',trafficOffered:'Предложено TCP-соединений',trafficCps:'Коротких TCP-соединений завершено/с'});
Object.assign(labText.en,{trafficOffP99:'OFF: RTT p99, ms',trafficUnruledP99:'UNRULED: RTT p99, ms',trafficSocksP99:'SOCKS5: RTT p99, ms',trafficCompleted:'Completed TCP connections',trafficOffered:'Offered TCP connections',trafficCps:'Short TCP connections completed/s'});
Object.assign(labText.ru,{tableAdd:'Добавить столбец',tableRemove:'Убрать столбец',tableRun:'Прогон',tableMetric:'Проверка / показатель',tableAll:'Все проверки',tableFilter:'Показать',tableConditions:'Условия',tableBase:'База',tableBestObserved:'Лучшее показание',tableObservedNote:'Условия различаются: это лучшее число, а не подтверждённое преимущество сборки',tableBest:'Лучшее',tableEqual:'Одинаково',tableHint:'Зелёным выделено лучшее число. При разных условиях это справочное сравнение. Разница — к первому столбцу.',tableRegion:'Таблица сравнения, прокручивается',tableOlder:'Загрузите этот отчёт из истории',tableMore:'Ещё отчёты',tableNeutral:'Справочная разница',tableDelta:'Разница к первому столбцу',tableNoNumeric:'Нет числового измерения'});
Object.assign(labText.en,{tableAdd:'Add column',tableRemove:'Remove column',tableRun:'Run',tableMetric:'Check / metric',tableAll:'All checks',tableFilter:'Show',tableConditions:'Conditions',tableBase:'Baseline',tableBestObserved:'Best reading',tableObservedNote:'Conditions differ: this is the best reading, not a verified build advantage',tableBest:'Best',tableEqual:'Equal',tableHint:'Green highlights the best value. Different conditions make the comparison descriptive. Differences are relative to the first column.',tableRegion:'Scrollable comparison table',tableOlder:'Load this report from history',tableMore:'More reports',tableNeutral:'Descriptive difference',tableDelta:'Difference from first column',tableNoNumeric:'No numeric measurement'});

const trafficTableMetricGroups=[
  ['reportTrafficGroup',['trafficTargetTransactions','trafficRateTarget','trafficRateMin','trafficRateMax','trafficOffP99','trafficUnruledP99','trafficSocksP99','trafficCompleted','trafficOffered','trafficCps','trafficSent','trafficReceived','trafficP99','trafficConnectP50','trafficConnectP95','trafficConnectP99','trafficTransactions','trafficPeak']],
  ['reportUdpGroup',['trafficUdpP99','trafficLoss',...Object.keys(trafficUdpCounters)]],
  ['reportClientGroup',['trafficCpu','trafficCpuPerGiB','trafficCpuPerThousand','trafficRam','trafficCliResident','trafficCommitBefore','trafficCommitAfter','trafficCliRamDelta','trafficResidentBefore','trafficResidentAfter','trafficCliResidentDelta','trafficCliHandles','trafficCliThreads']],
  ['reportPcGroup',['trafficSystemCpu']],
  ['reportLoadGroup',['trafficLoadTx','trafficLoadRx','trafficLoadMinTx','trafficLoadMinRx','trafficLoadWorstP99','trafficRecoveryP99Change']]
];
const trafficTableHigher=new Set(['trafficSent','trafficReceived','trafficLoadTx','trafficLoadRx','trafficLoadMinTx','trafficLoadMinRx']);
const trafficTableLower=new Set(['trafficOffP99','trafficUnruledP99','trafficSocksP99','trafficP99','trafficConnectP50','trafficConnectP95','trafficConnectP99','trafficUdpP99','trafficLoss','trafficCpu','trafficRam','trafficCliResident','trafficCliHandles','trafficCliThreads','trafficSystemCpu','trafficLoadWorstP99']);
const trafficTableIntegers=new Set(['trafficCompleted','trafficOffered','trafficTransactions','trafficPeak','trafficCliHandles','trafficCliThreads',...Object.keys(trafficUdpCounters)]);
let trafficTableState={ids:[],family:'all'},trafficTableInitialized=false,trafficTableStamp='',trafficTableStructureKey='',trafficTableToolbarKey='';
try{
  const saved=JSON.parse(sessionStorage.getItem('testlab-comparison-table')||'null');
  if(Array.isArray(saved?.ids)&&saved.ids.length){trafficTableState={ids:trafficTableNormalize(saved.ids),family:typeof saved.family==='string'?saved.family:'all'};trafficTableInitialized=true;}
}catch{}
let trafficTableExpanded=new Set();
try{const saved=JSON.parse(localStorage.getItem('testlab-comparison-expanded')||'[]');if(Array.isArray(saved))trafficTableExpanded=new Set(saved.filter(key=>typeof key==='string'&&key.length<180).slice(0,512));}catch{}
function trafficTableGroup(key,label){return `<button type="button" class="comparison-group-toggle" data-table-group="${html(key)}" aria-expanded="${trafficTableExpanded.has(key)}">${trafficTableExpanded.has(key)?'▾':'▸'} ${html(label)}</button>`;}
function trafficTableNormalize(ids){
  const seen=new Set(),result=[];
  for(const value of ids.slice(0,4)){const id=typeof value==='string'&&value.length<128&&!seen.has(value)?value:'';result.push(id);if(id)seen.add(id);}
  while(result.length<2)result.push('');
  return result;
}
function trafficTableSave(){try{sessionStorage.setItem('testlab-comparison-table',JSON.stringify(trafficTableState));}catch{}}
function trafficTableValue(row,key){
  if(key==='trafficOffP99'||key==='trafficUnruledP99')return trafficMeasurementMetric(row?.measurements?.find(m=>m.mode===(key==='trafficOffP99'?'OFF':'UNRULED')),'trafficP99');
  const measured=row?.measurements?.find(m=>m.mode==='SOCKS5');
  if(key==='trafficSocksP99')return trafficMeasurementMetric(measured,'trafficP99');
  if(['trafficCompleted','trafficOffered','trafficCps'].includes(key)){
    const stages=(measured?.stages||[]).filter(stage=>stage.phase!=='baseline'&&stage.phase!=='recovery');
    if(!stages.length)return null;
    const field=key==='trafficOffered'?'tcp_offered':'tcp_completed';
    if(!stages.every(stage=>Number.isFinite(stage[field])))return null;
    const total=stages.reduce((sum,stage)=>sum+stage[field],0),elapsed=stages.reduce((sum,stage)=>sum+stage.elapsed_seconds,0);
    return key==='trafficCps'?(row.case_id==='flow-rate'&&elapsed>0?total/elapsed:null):total;
  }
  return trafficMeasurementMetric(measured,key);
}
function trafficTableBest(runs,rows,key){
  const values=rows.map(row=>trafficTableValue(row,key));
  if(runs.length<2||rows.some((row,i)=>!row||trafficReportStatus(row,runs[i])!=='PASS')||values.some(value=>!Number.isFinite(value)))return [];
  if(!trafficQualityRankable(runs,rows,key))return [];
  const lower=trafficTableLower.has(key);
  if(!lower&&!trafficTableHigher.has(key)||values.every(value=>value===values[0]))return [];
  const displayed=values.map(value=>Number(value.toFixed(trafficTableIntegers.has(key)?0:2)));
  if(displayed.every(value=>value===displayed[0]))return [];
  const best=(lower?Math.min:Math.max)(...displayed);
  return displayed.flatMap((value,i)=>value===best?[i]:[]);
}
function trafficTableDifference(value,base,comparable,key,allowPercent=true){
  if(!Number.isFinite(value)||!Number.isFinite(base))return '';
  const change=value-base,amount=Math.abs(change),digits=amount>0&&amount<0.01?4:2;
  const percent=allowPercent&&!['trafficCliRamDelta','trafficCliResidentDelta','trafficRecoveryP99Change'].includes(key)&&base>0?Math.abs(change)/base*100:null;
  const relative=change===0?t('tableEqual'):`${change>0?'+':'−'}${number(amount,digits)}${percent!==null?` (${change>0?'+':'−'}${percent>0&&percent<0.01?'&lt;'+number(0.01,2):number(percent,2)}%)`:''}`;
  return `<small class="comparison-cell-delta" title="${html(t(comparable?'tableDelta':'tableNeutral'))}">${relative}</small>`;
}
function trafficTableStage(run,id){return run?.results?.find(row=>row.case_id===id);}
function trafficTableBody(runs,slots,families){
  const span=slots.length+1,selected=runs.filter(Boolean);
  if(!selected.length)return `<tr><td colspan="${span}">${t('reportChoose')}</td></tr>`;
  let result='';
  for(const family of families){
    const stages=family.rows.filter(stage=>selected.some(run=>(run.cases||[]).some(row=>(row.id||row.Id)===stage.id)));
    if(!stages.length)continue;
    result+=`<tr class="comparison-family"><th colspan="${span}" scope="rowgroup">${trafficTableGroup(family.id,trafficFamilyName(family))}</th></tr>`;
    if(!trafficTableExpanded.has(family.id))continue;
    for(const stage of stages){
      const rows=runs.map(run=>trafficTableStage(run,stage.id)),base=rows[0],baseRun=runs[0];
      result+=`<tr class="comparison-stage"><th scope="row">${html(trafficName(stage.id))}</th>${runs.map((run,i)=>`<td>${run?trafficReportBadge(trafficReportStatus(rows[i],run)):'—'}${rows[i]?`<small>${html(t(rows[i].duration))} · ${html(t(rows[i].load))}</small>`:''}</td>`).join('')}</tr>`;
      result+=`<tr class="comparison-conditions"><th scope="row">${t('tableConditions')}</th>${runs.map((run,i)=>{
        if(!run||!rows[i])return '<td>—</td>';
        const reasons=base&&baseRun?trafficReportDifferences(baseRun,base,run,rows[i]):[];
        const label=i===0?t('tableBase'):!base?t('reportNoPair'):trafficReportComparable(baseRun,base,run,rows[i])?t('reportComparable'):reasons.map(t).join(', ')||t('reportUnknown');
        return `<td>${html(label)}<small>${html(trafficQualityNote(rows[i]))}</small></td>`;
      }).join('')}</tr>`;
      let metricCount=0;
      for(const [group,keys] of trafficTableMetricGroups){
        const relevant=trafficObjectiveMetricKeys(stage.id);
        const available=keys.filter(key=>(['reportClientGroup','reportPcGroup'].includes(group)||!relevant||relevant.includes(key))&&rows.some(row=>Number.isFinite(trafficTableValue(row,key)))&&!(key==='trafficTransactions'&&rows.every(row=>!trafficTableValue(row,key))));
        if(!available.length)continue;
        metricCount+=available.length;
        result+=`<tr class="comparison-metric-group"><th colspan="${span}">${trafficTableGroup(family.id+'/'+stage.id+'/'+group,t(group))}</th></tr>`;
        if(!trafficTableExpanded.has(family.id+'/'+stage.id+'/'+group))continue;
        for(const key of available){
          // Blank columns do not participate; a missing selected stage blocks ranking.
          const chosen=runs.flatMap((run,i)=>run?[i]:[]),best=slots.some((id,i)=>id&&!runs[i])?[]:trafficTableBest(chosen.map(i=>runs[i]),chosen.map(i=>rows[i]),key).map(i=>chosen[i]);
          const rankedComparable=chosen.length>=2&&chosen.every(i=>trafficReportComparable(runs[chosen[0]],rows[chosen[0]],runs[i],rows[i]));
          const labels={trafficCpu:'reportCpuMean',trafficRam:'reportPrivatePeak',trafficCliResident:'reportResidentPeak',trafficCliHandles:'reportHandlesPeak',trafficCliThreads:'reportThreadsPeak',trafficSystemCpu:'reportPcCpu'};
          result+=`<tr><th scope="row">${html(t(labels[key]||key))}</th>${runs.map((run,i)=>{
            const value=trafficTableValue(rows[i],key),valid=Number.isFinite(value),winner=best.includes(i),repeat=trafficTableRepeat(runs,rows,i,key),cpuNote=trafficCpuBudgetNote(rows[i],key),allowPercent=trafficCpuBudgetEnough(rows[i],key)&&trafficCpuBudgetEnough(base,key);
            const comparable=!!run&&!!baseRun&&trafficReportComparable(baseRun,base,run,rows[i]);
            return `<td class="${winner?(rankedComparable?'comparison-best':'comparison-best-observed'):''}"${winner?` aria-label="${html(t(rankedComparable?'tableBest':'tableBestObserved'))}: ${html(number(value,trafficTableIntegers.has(key)?0:2))}"`:''}>${valid?`<strong title="${html([repeat?.text,cpuNote].filter(Boolean).join(' · '))}">${number(value,trafficTableIntegers.has(key)?0:2)}</strong>${i>0?trafficTableDifference(value,trafficTableValue(base,key),comparable,key,allowPercent):''}`:'—'}</td>`;
          }).join('')}</tr>`;
        }
      }
      if(!metricCount)result+=`<tr><td colspan="${span}">${t('tableNoNumeric')}</td></tr>`;
    }
  }
  return result||`<tr><td colspan="${span}">${t('reportNoPair')}</td></tr>`;
}
function renderRunComparison(){
  if(typeof trafficReportChronological!=='function')return;
  const options=trafficReportChronological(trafficHistory).filter(run=>run.results?.length);
  if(!trafficTableInitialized&&options.length){trafficTableState.ids=trafficTableNormalize(options.slice(0,2).map(run=>run.id));trafficTableInitialized=true;}
  const families=trafficFamilies(trafficCatalog);
  if(trafficTableState.family!=='all'&&!families.some(f=>f.id===trafficTableState.family))trafficTableState.family='all';
  const stamp=JSON.stringify([trafficHistory,trafficCatalog,labState.builds,labLanguage,trafficTableState,[...trafficTableExpanded],trafficSnapshotUnavailable,trafficComparisonBlocked]);
  if(stamp===trafficTableStamp)return;trafficTableStamp=stamp;
  const selection=lab('traffic-pair-selection'),overview=lab('traffic-pair-overview');
  if(trafficSnapshotUnavailable||trafficComparisonBlocked){trafficTableStructureKey='';trafficTableToolbarKey='';selection.innerHTML='';overview.textContent=t('trafficHistoryUnavailable');return;}
  const previous=lab('traffic-comparison-scroll'),top=previous?.scrollTop||0,left=previous?.scrollLeft||0;
  const focus=document.activeElement?.dataset?.compareSlot,focusFamily=document.activeElement?.id==='traffic-table-family';
  const slots=trafficTableNormalize(trafficTableState.ids),runs=slots.map(id=>options.find(run=>run.id===id));
  const optionMetadata=options.map(run=>[run.id,trafficReportBuild(run),run.started_at_utc,run.cases?.length]);
  const controls=slots.map((id,i)=>`<div><label><span>${t('tableRun')} ${i+1}</span><select data-compare-slot="${i}" aria-label="${html(t('tableRun'))} ${i+1}"><option value="">${t('reportChoose')}</option>${id&&!runs[i]?`<option value="${html(id)}" selected>${t('tableOlder')}</option>`:''}${options.map(run=>`<option value="${html(run.id)}" ${id===run.id?'selected':''} ${slots.some((other,j)=>j!==i&&other===run.id)?'disabled':''}>${html(trafficReportBuild(run))} · ${html(trafficReportDate(run))} · ${run.cases?.length||0} ${t('reportSteps')}</option>`).join('')}</select></label><button type="button" class="comparison-remove" data-compare-remove="${i}" ${slots.length<=2?'disabled':''} aria-label="${html(t('tableRemove'))} ${i+1}">× ${t('tableRemove')}</button></div>`).join('');
  const toolbarKey=JSON.stringify([labLanguage,slots.length,trafficHasMore,families.map(f=>f.id),optionMetadata,slots.filter((id,i)=>id&&!runs[i])]);
  if(toolbarKey!==trafficTableToolbarKey){trafficTableToolbarKey=toolbarKey;selection.innerHTML=`<label><span>${t('tableFilter')}</span><select id="traffic-table-family"><option value="all">${t('tableAll')}</option>${families.map(f=>`<option value="${html(f.id)}" ${trafficTableState.family===f.id?'selected':''}>${html(trafficFamilyName(f))}</option>`).join('')}</select></label><button type="button" class="button secondary" data-compare-add ${slots.length>=4?'disabled':''}>＋ ${t('tableAdd')} (${slots.length}/4)</button>${trafficHasMore?`<button type="button" class="button secondary" data-compare-more>${t('tableMore')}</button>`:''}<div class="comparison-run-controls">${controls}</div>`;}
  lab('traffic-table-family').value=trafficTableState.family;
  const header=slots.map((id,i)=>`<th scope="col"><div data-compare-meta="${i}"></div></th>`).join('');
  const structureKey=JSON.stringify([labLanguage,slots.length,options.map(run=>[run.id,trafficReportBuild(run),run.started_at_utc,run.cases?.length]),slots.filter((id,i)=>id&&!runs[i])]);
  if(structureKey!==trafficTableStructureKey){trafficTableStructureKey=structureKey;overview.innerHTML=`<p class="result-hint">${t('tableHint')}</p><div id="traffic-comparison-scroll" class="comparison-table-scroll" role="region" aria-label="${html(t('tableRegion'))}" tabindex="0"><table class="comparison-matrix"><caption class="comparison-caption">${t('reportCompare')}</caption><colgroup><col class="comparison-label-column">${slots.map(()=>'<col>').join('')}</colgroup><thead><tr><th scope="col">${t('tableMetric')}</th>${header}</tr></thead><tbody></tbody></table></div>`;}
  selection.querySelectorAll('[data-compare-slot]').forEach(select=>{const i=Number(select.dataset.compareSlot);select.value=slots[i];for(const option of select.options)option.disabled=!!option.value&&slots.some((id,j)=>j!==i&&id===option.value);});
  overview.querySelectorAll('[data-compare-meta]').forEach(meta=>{const run=runs[Number(meta.dataset.compareMeta)];meta.innerHTML=run?`<strong>${html(trafficReportBuild(run))}</strong><small>${html(trafficReportDate(run))} · ${html(t(run.mode||'remote'))}</small>`:'';});
  overview.querySelector('tbody').innerHTML=trafficTableBody(runs,slots,trafficTableState.family==='all'?families:families.filter(f=>f.id===trafficTableState.family));
  const scroll=lab('traffic-comparison-scroll');scroll.scrollTop=top;scroll.scrollLeft=left;
  if(focusFamily)lab('traffic-table-family').focus({preventScroll:true});
  if(focus!==undefined)selection.querySelector(`[data-compare-slot="${CSS.escape(focus)}"]`)?.focus({preventScroll:true});
}
lab('traffic-pair-view').addEventListener('click',event=>{
  const group=event.target.closest('[data-table-group]');if(group){const key=group.dataset.tableGroup;if(trafficTableExpanded.has(key))trafficTableExpanded.delete(key);else trafficTableExpanded.add(key);try{localStorage.setItem('testlab-comparison-expanded',JSON.stringify([...trafficTableExpanded]));}catch{}renderRunComparison();lab('traffic-pair-overview').querySelector(`[data-table-group="${CSS.escape(key)}"]`)?.focus({preventScroll:true});return;}
  if(event.target.closest('[data-compare-add]')&&trafficTableState.ids.length<4){trafficTableState.ids.push('');trafficTableSave();renderRunComparison();}
  const remove=event.target.closest('[data-compare-remove]');
  if(remove&&trafficTableState.ids.length>2){trafficTableState.ids.splice(Number(remove.dataset.compareRemove),1);trafficTableSave();renderRunComparison();}
  if(event.target.closest('[data-compare-more]'))lab('traffic-history-more').click();
});
lab('traffic-pair-view').addEventListener('change',event=>{
  if(event.target.id==='traffic-table-family')trafficTableState.family=event.target.value;
  else if(event.target.dataset.compareSlot!==undefined){
    const index=Number(event.target.dataset.compareSlot),value=event.target.value;
    if(!Number.isInteger(index)||index<0||index>=trafficTableState.ids.length||value&&trafficTableState.ids.some((id,i)=>i!==index&&id===value))return;
    trafficTableState.ids[index]=value;
  }else return;
  trafficTableSave();renderRunComparison();
});

Object.assign(labText.ru,{trafficCompleted:'Успешных TCP-сеансов',trafficOffered:'Попыток TCP-сеанса',trafficTransactions:'Подтверждено обменов',trafficCliRamDelta:'Память commit: после − до, МиБ',trafficCliResidentDelta:'Память в RAM: после − до, МиБ',trafficCommitBefore:'Память commit: первый замер, МиБ',trafficCommitAfter:'Память commit: последний замер, МиБ',trafficResidentBefore:'RAM: первый замер, МиБ',trafficResidentAfter:'RAM: последний замер, МиБ',trafficCpuPerGiB:'CPU клиента, с / ГиБ данных',trafficCpuPerThousand:'CPU клиента, с / 1000 обменов',trafficConnectP50:'TCP + подготовка приёмника p50, мс',trafficConnectP95:'TCP + подготовка приёмника p95, мс',trafficConnectP99:'TCP + подготовка приёмника p99, мс',tableHint:'Подсветка только при подтверждённых сопоставимых измерениях. Разница — к первому столбцу. Один прогон не подтверждает устойчивое преимущество. Выберите повторы одной сборки: медиана и диапазон — в подсказке числа.'});
Object.assign(labText.en,{trafficCompleted:'Successful TCP sessions',trafficOffered:'TCP session attempts',trafficTransactions:'Verified transactions',trafficCliRamDelta:'Private memory: last − first, MiB',trafficCliResidentDelta:'Resident memory: last − first, MiB',trafficCommitBefore:'Private memory: first sample, MiB',trafficCommitAfter:'Private memory: last sample, MiB',trafficResidentBefore:'Resident memory: first sample, MiB',trafficResidentAfter:'Resident memory: last sample, MiB',trafficCpuPerGiB:'Client CPU seconds / GiB',trafficCpuPerThousand:'Client CPU seconds / 1000 transactions',trafficConnectP50:'TCP + receiver setup p50, ms',trafficConnectP95:'TCP + receiver setup p95, ms',trafficConnectP99:'TCP + receiver setup p99, ms',tableHint:'Highlighting requires verified comparable measurements. Differences use the first column. A single run does not establish a repeatable advantage. Select repeated runs of one build for median and range in value tooltips.'});

Object.assign(labText.ru,{trafficTargetTransactions:'Ориентир обменов по профилю, ≈',trafficRateTarget:'Целевой темп на поток, /с',trafficRateMin:'Фактический темп: минимум на поток, /с',trafficRateMax:'Фактический темп: максимум на поток, /с'});
Object.assign(labText.en,{trafficTargetTransactions:'Profile target transactions, approx.',trafficRateTarget:'Target rate per flow, /s',trafficRateMin:'Actual rate: minimum per flow, /s',trafficRateMax:'Actual rate: maximum per flow, /s'});
for(const key of ['trafficCpuPerGiB','trafficCpuPerThousand','trafficCommitBefore','trafficCommitAfter','trafficResidentBefore','trafficResidentAfter','trafficTargetTransactions','trafficRateTarget','trafficRateMin','trafficRateMax'])if(!trafficMetrics.includes(key))trafficMetrics.push(key);

function trafficTableRepeat(runs,rows,index,key){
  const base=runs[index],row=rows[index];
  if(!base?.build_id||!row)return null;
  const values=runs.flatMap((run,i)=>run?.build_id===base.build_id&&trafficReportComparable(base,row,run,rows[i])&&Number.isFinite(trafficTableValue(rows[i],key))?[trafficTableValue(rows[i],key)]:[]).sort((a,b)=>a-b);
  if(values.length<2)return null;
  const middle=Math.floor(values.length/2),median=values.length%2?values[middle]:(values[middle-1]+values[middle])/2;
  return {count:values.length,median,min:values[0],max:values.at(-1),text:labLanguage==='ru'?`${values.length} выбранных прогона этой сборки · медиана ${number(median,2)} · диапазон ${number(values[0],2)}…${number(values.at(-1),2)}`:`${values.length} selected runs of this build · median ${number(median,2)} · range ${number(values[0],2)}…${number(values.at(-1),2)}`};
}
