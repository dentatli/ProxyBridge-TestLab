"use strict";
Object.assign(labText.ru,{reportKernelGroup:'Драйвер: наблюдения ядра',trafficKernelCpu:'CPU драйвера, с · оценка по выборкам',trafficKernelSamples:'Выборок в коде драйвера',trafficKernelPaged:'Paged pool по тегам, КиБ · максимум снимков',trafficKernelNonPaged:'Nonpaged pool по тегам, КиБ · максимум снимков',trafficKernelPoolAfter:'Пул по тегам в конце нагрузки, КиБ'});
Object.assign(labText.en,{reportKernelGroup:'Driver: kernel observations',trafficKernelCpu:'Driver CPU seconds · sampled estimate',trafficKernelSamples:'Samples in driver code',trafficKernelPaged:'Tagged paged pool, KiB · observed maximum',trafficKernelNonPaged:'Tagged nonpaged pool, KiB · observed maximum',trafficKernelPoolAfter:'Tagged pool at workload end, KiB'});

function trafficKernelRows(measured){
  const k=measured?.kernel_resources;
  return k?.available===true&&k.cleanup_verified===true?(k.phases||[]).filter(p=>!['baseline','recovery'].includes(p.phase)):[];
}
function trafficKernelMetric(measured,key){
  const k=measured?.kernel_resources,rows=trafficKernelRows(measured);
  if(!rows.length)return null;
  if(key==='trafficKernelCpu'||key==='trafficKernelSamples'){
    if(rows.some(p=>!['MEASURED','INSUFFICIENT_SAMPLES'].includes(p.cpu_state)))return null;
    const count=rows.reduce((s,p)=>s+p.sample_count,0);
    if(!Number.isSafeInteger(count))return null;
    return key==='trafficKernelSamples'?count:count>=30&&Number.isFinite(k.sampling_interval_100ns)?count*k.sampling_interval_100ns/1e7:null;
  }
  if(rows.some(p=>p.pool_state!=='TAGGED_GLOBAL'))return null;
  const peak=field=>rows.every(p=>Number.isFinite(p[field]))?Math.max(...rows.map(p=>p[field]))/1024:null;
  if(key==='trafficKernelPaged')return peak('paged_peak_observed');
  if(key==='trafficKernelNonPaged')return peak('nonpaged_peak_observed');
  if(key==='trafficKernelPoolAfter'){
    const last=rows[rows.length-1];return Number.isFinite(last.paged_last)&&Number.isFinite(last.nonpaged_last)?(last.paged_last+last.nonpaged_last)/1024:null;
  }
  return null;
}
function trafficKernelNote(measured){
  const k=measured?.kernel_resources,ru=labLanguage==='ru';
  if(!k)return ru?'Ядро не измерялось':'Kernel resources were not collected';
  if(!k.available)return (ru?'Сбор ядра недоступен: ':'Kernel collection unavailable: ')+(k.error||'UNKNOWN');
  const rows=trafficKernelRows(measured),parts=[ru?'CPU: только код драйвера; не складывать с CPU процесса. Пул: общесистемные теги, без общих буферов Windows.':'CPU: driver instructions only; do not add to process CPU. Pool: system-wide tags, shared Windows buffers excluded.'];
  if(rows.some(p=>p.cpu_state==='INSUFFICIENT_SAMPLES'))parts.push(ru?'Мало выборок CPU.':'Insufficient CPU samples.');
  if(!k.consumer_drained||k.events_lost!==0||k.error||!k.module_observed||k.module_ambiguous||k.interval_changed)parts.push(ru?'Полнота сбора не подтверждена.':'Collection completeness unverified.');
  return parts.join(' ');
}
function trafficKernelMarkup(measured){
  const k=measured?.kernel_resources,ru=labLanguage==='ru';
  let result=`<section class="result-metric-group"><h4>${html(t('reportKernelGroup'))}</h4><small>${html(trafficKernelNote(measured))}</small>`;
  if(k?.available){
    const keys=['trafficKernelCpu','trafficKernelSamples','trafficKernelPaged','trafficKernelNonPaged','trafficKernelPoolAfter'];
    result+=`<div class="result-quick-metrics">${keys.map(key=>{const v=trafficKernelMetric(measured,key);return `<span>${html(t(key))}<b>${Number.isFinite(v)?number(v,key==='trafficKernelSamples'?0:2):'—'}</b></span>`;}).join('')}</div><small>${html(k.driver_name||'')} · ${html((k.tags||[]).join(', '))} · ${ru?'Потеряно событий':'Lost events'}: ${Number.isSafeInteger(k.events_lost)?k.events_lost:'—'}</small>`;
  }
  return result+'</section>';
}
