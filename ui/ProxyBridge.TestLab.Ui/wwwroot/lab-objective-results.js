"use strict";
// Present the experiment's observations, keeping validation and final status in the evidence layer.
const trafficObjectiveText={
  ru:{goal:'Что проверялось',modes:'Влияние клиента и перенаправления на один и тот же TCP-обмен',echo:'Задержка и целостность коротких TCP-обменов',upload:'Передача данных от клиента к получателю',download:'Передача данных от получателя к клиенту',duplex:'Одновременная передача в обе стороны',multistream:'Изменение скорости при разном числе TCP-потоков',loaded:'Задержка без нагрузки, под нагрузкой и после неё',connections:'Одновременные TCP-соединения и восстановление',flow_rate:'Создание и завершение коротких TCP-соединений',udp:'Доставка и целостность UDP-ответов',udp_unconnected:'Доставка UDP через сокеты без connect',udp_sweep:'Доставка UDP при разных размерах пакета и темпе отправки',udp_connections:'Разделение UDP-потоков, доставка и восстановление',mixed:'Совместная TCP/UDP-нагрузка: скорость, задержка и доставка',stability:'Устойчивость TCP/UDP в последовательных интервалах нагрузки',soak:'Длительная устойчивость TCP/UDP и восстановление',application:'Корректность прикладного обмена и его вариантов',stage:'Условие / интервал',status:'Обмен',ok:'Завершён',bad:'Не завершён',route:'Маршрут',yes:'Подтверждён',no:'Не подтверждён',rtt:'RTT p99, мс',tx:'Отправка, МиБ/с',rx:'Получение, МиБ/с',sent:'UDP отправлено',received:'UDP подтверждено',loss:'Потери UDP, %',udpRtt:'UDP RTT p99, мс',tcp:'TCP завершено / предложено',cps:'Завершено TCP/с',peak:'Пик TCP-соединений',transactions:'Проверенных обменов',payload:'Данные, байт',resources:'Ресурсы и дополнительные измерения',details:'Измерения по условиям',baseline:'Без нагрузки',recovery:'Восстановление',loadedPhase:'Под нагрузкой',mixedPhase:'TCP + UDP + задержка',interval:'Интервал',streams:'Потоков',connectionsLabel:'Соединений',udpFlows:'UDP-потоков',bytes:'байт',pps:'пакетов/с на поток',delta:'Изменение RTT к OFF, мс',missing:'Нет измерений для этой проверки',observed:'Незавершённые измерения — наблюдения, не подтверждённый результат.',limited:'Показаны первые и последние интервалы; полный журнал — в подробностях.',scope:'Скорость измерена в выбранной нагрузке; это не отдельное измерение предельной пропускной способности.',checks:'Подтверждения протокола',tls:'TLS / ALPN',cert:'Сертификат проверен',close:'Завершение проверено',host:'Ключ SSH проверен',grpc:'Статус gRPC проверен',handshake:'QUIC handshake',http2_peak_streams:'Пик HTTP/2 streams',http2_completed_streams:'Завершено HTTP/2 streams',quic_peak_streams:'Пик QUIC streams',quic_completed_streams:'Завершено QUIC streams',grpc_request_messages:'Сообщений gRPC отправлено',grpc_response_messages:'Сообщений gRPC получено',grpc_rpc_count:'RPC',ws_fragmented_requests:'Фрагментированных WS-запросов',ws_fragmented_responses:'Фрагментированных WS-ответов',ws_client_pongs_verified:'Проверенных Pong',ws_server_pings_answered:'Ответов на Ping',http_chunked_requests:'Chunked-запросов',http_chunked_responses:'Chunked-ответов',http_gzip_requests:'Gzip-запросов',http_gzip_responses:'Gzip-ответов',invalid:'Некорректных UDP-ответов',duplicates:'Повторных UDP-ответов',reordered:'UDP не по порядку',expired:'Просроченных UDP-ответов',send_errors:'Ошибок отправки UDP'},
  en:{goal:'Experiment',modes:'Client and redirection overhead for the same TCP exchange',echo:'Latency and integrity of short TCP exchanges',upload:'Client-to-origin transfer',download:'Origin-to-client transfer',duplex:'Simultaneous transfer in both directions',multistream:'Throughput across TCP stream counts',loaded:'Latency before, during and after load',connections:'Concurrent TCP connections and recovery',flow_rate:'Creation and completion of short TCP connections',udp:'UDP reply delivery and integrity',udp_unconnected:'UDP delivery through unconnected sockets',udp_sweep:'UDP delivery across packet sizes and send rates',udp_connections:'UDP flow isolation, delivery and recovery',mixed:'Concurrent TCP/UDP load: throughput, latency and delivery',stability:'TCP/UDP stability across successive load intervals',soak:'Long-running TCP/UDP stability and recovery',application:'Application exchange and profile correctness',stage:'Condition / interval',status:'Exchange',ok:'Completed',bad:'Incomplete',route:'Route',yes:'Verified',no:'Unverified',rtt:'RTT p99, ms',tx:'Upload, MiB/s',rx:'Download, MiB/s',sent:'UDP sent',received:'UDP verified',loss:'UDP loss, %',udpRtt:'UDP RTT p99, ms',tcp:'TCP completed / offered',cps:'TCP completed/s',peak:'Peak TCP connections',transactions:'Verified exchanges',payload:'Payload, bytes',resources:'Resources and additional measurements',details:'Measurements by condition',baseline:'Baseline',recovery:'Recovery',loadedPhase:'Under load',mixedPhase:'TCP + UDP + latency',interval:'Interval',streams:'Streams',connectionsLabel:'Connections',udpFlows:'UDP flows',bytes:'bytes',pps:'packets/s per flow',delta:'RTT change from OFF, ms',missing:'No measurements for this check',observed:'Incomplete measurements are observations, not a verified result.',limited:'First and last intervals shown; full journal is in details.',scope:'Throughput is observed under the selected load, not a separate maximum-throughput measurement.',checks:'Protocol evidence',tls:'TLS / ALPN',cert:'Certificate verified',close:'Closure verified',host:'SSH host key verified',grpc:'gRPC status verified',handshake:'QUIC handshake',http2_peak_streams:'Peak HTTP/2 streams',http2_completed_streams:'Completed HTTP/2 streams',quic_peak_streams:'Peak QUIC streams',quic_completed_streams:'Completed QUIC streams',grpc_request_messages:'gRPC request messages',grpc_response_messages:'gRPC response messages',grpc_rpc_count:'RPCs',ws_fragmented_requests:'Fragmented WS requests',ws_fragmented_responses:'Fragmented WS responses',ws_client_pongs_verified:'Verified Pongs',ws_server_pings_answered:'Answered Pings',http_chunked_requests:'Chunked requests',http_chunked_responses:'Chunked responses',http_gzip_requests:'Gzip requests',http_gzip_responses:'Gzip responses',invalid:'Invalid UDP replies',duplicates:'Duplicate UDP replies',reordered:'Reordered UDP replies',expired:'Expired UDP replies',send_errors:'UDP send errors'}
};
function trafficObjectiveLabel(key){return trafficObjectiveText[labLanguage]?.[key]||trafficObjectiveText.en[key]||key;}
function trafficObjectiveMetricKeys(caseId){
  const recipe=trafficCatalog?.cases?.find(item=>item.id===caseId)?.recipe;
  if(!recipe)return null;
  if(caseId==='three-modes')return ['trafficOffP99','trafficUnruledP99','trafficSocksP99'];
  if(recipe==='application')return ['trafficTransactions','trafficTargetTransactions','trafficRateTarget','trafficRateMin','trafficRateMax'];
  if(recipe==='echo')return ['trafficP99'];
  if(recipe==='upload')return ['trafficSent'];
  if(recipe==='download')return ['trafficReceived'];
  if(['duplex','multistream'].includes(recipe))return ['trafficSent','trafficReceived'];
  if(recipe==='connections')return ['trafficCompleted','trafficOffered','trafficPeak','trafficLoadWorstP99'];
  if(recipe==='flow_rate')return ['trafficCompleted','trafficOffered','trafficCps','trafficPeak','trafficConnectP50','trafficConnectP95','trafficConnectP99'];
  const udp=['trafficRateTarget','trafficRateMin','trafficRateMax','trafficUdpP99','trafficLoss',...Object.keys(trafficUdpCounters)];
  if(recipe.startsWith('udp'))return udp;
  return ['trafficLoadTx','trafficLoadRx','trafficLoadMinTx','trafficLoadMinRx','trafficLoadWorstP99','trafficRecoveryP99Change',...(['mixed','stability','soak'].includes(recipe)?udp:[])];
}
function trafficObjectiveNumber(value,digits=2){return typeof value==='number'&&Number.isFinite(value)?number(value,digits):'—';}
Object.assign(trafficObjectiveText.ru,{worstLoss:'Худшие потери одного UDP-потока, %',cpu:'CPU клиента, % ПК',ram:'Выделенная память клиента, МиБ · пик',churnScope:'Измеряется этот профиль коротких соединений с удержанием 50 мс, не предельная частота создания соединений.'});
Object.assign(trafficObjectiveText.ru,{requestedPps:'Задано, пак./с на поток',actualPps:'Подано, пак./с на поток',rateScope:'Фактическая подача указана за окно нагрузки, без подключения и ожидания ответов. Потери считаются от отправленных пакетов. Успешная доставка не подтверждает достижение заданного темпа.'});
Object.assign(trafficObjectiveText.en,{requestedPps:'Target packets/s per flow',actualPps:'Offered packets/s per flow',rateScope:'Offered rate uses the load window, excluding setup and reply drain. Loss uses sent packets. Successful delivery does not confirm reaching the target rate.'});
Object.assign(trafficObjectiveText.en,{worstLoss:'Worst single UDP flow loss, %',cpu:'Client CPU, % of PC',ram:'Client private memory, MiB · peak',churnScope:'This measures the selected short-connection profile with a 50 ms hold, not maximum connection creation rate.'});
function trafficObjectiveTable(columns,rows){
  return `<div class="objective-scroll"><table class="objective-table"><thead><tr>${columns.map(key=>`<th scope="col">${html(trafficObjectiveLabel(key))}</th>`).join('')}</tr></thead><tbody>${rows.map(row=>`<tr>${row.map((value,index)=>index===0?`<th scope="row">${html(value)}</th>`:`<td>${html(value)}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`;
}
function trafficObjectivePhase(phase){
  const labels={baseline:'baseline',recovery:'recovery',loaded:'loadedPhase',mixed:'mixedPhase',echo:'echo',upload:'upload',download:'download',duplex:'duplex',churn:'flow_rate',udp:'udp',udp_unconnected:'udp_unconnected'};
  if(labels[phase])return trafficObjectiveLabel(labels[phase]);
  for(const [pattern,key] of [[/^interval-(\d+)$/,'interval'],[/^streams-(\d+)$/,'streams'],[/^connections-(\d+)$/,'connectionsLabel'],[/^udp-flows-(\d+)$/,'udpFlows']]){const match=pattern.exec(phase||'');if(match)return `${trafficObjectiveLabel(key)}: ${match[1]}`;}
  const sweep=/^udp-(\d+)-(\d+)$/.exec(phase||'');
  if(sweep)return `${sweep[1]} ${trafficObjectiveLabel('bytes')} · ${sweep[2]} ${trafficObjectiveLabel('pps')}`;
  return String(phase||'—');
}
function trafficObjectiveProtocol(stages){
  const sessions=stages.flatMap(stage=>stage.application_protocol_sessions||[]),tls=stages.flatMap(stage=>stage.application_tls_sessions||[]);
  const facts=[];
  const item=(key,value)=>facts.push(`<span>${html(trafficObjectiveLabel(key))}<b>${html(value)}</b></span>`);
  const versions=[...new Set(tls.map(row=>[row.tls_version,row.alpn].filter(Boolean).join(' / ')).filter(Boolean))];
  if(versions.length)item('tls',versions.join(', '));
  for(const [key,field,rows] of [['cert','certificate_verified',tls],['close','close_verified',[...tls,...sessions]],['host','ssh_host_key_verified',sessions],['grpc','grpc_status_verified',sessions],['handshake','handshake_complete',sessions]]){
    const values=rows.filter(row=>typeof row[field]==='boolean');
    if(values.length)item(key,`${values.filter(row=>row[field]===true).length} / ${values.length}`);
  }
  for(const key of ['http2_peak_streams','http2_completed_streams','quic_peak_streams','quic_completed_streams','grpc_request_messages','grpc_response_messages','grpc_rpc_count','ws_fragmented_requests','ws_fragmented_responses','ws_client_pongs_verified','ws_server_pings_answered','http_chunked_requests','http_chunked_responses','http_gzip_requests','http_gzip_responses']){
    const values=sessions.map(row=>row[key]).filter(value=>typeof value==='number'&&Number.isFinite(value));
    if(values.length)item(key,trafficObjectiveNumber(key.includes('peak')?Math.max(...values):values.reduce((a,b)=>a+b,0),0));
  }
  return facts.length?`<section class="result-metric-group"><h5>${trafficObjectiveLabel('checks')}</h5><div class="result-quick-metrics">${facts.join('')}</div></section>`:'';
}
function trafficObjectiveMarkup(row,view={}){
  if(!row)return '';
  const spec=trafficCatalog?.cases?.find(item=>item.id===row.case_id),recipe=spec?.recipe;
  // Unknown historical recipes keep their original measurements available.
  if(!recipe)return trafficReportAdditionalMetricMarkup(row);
  const mode=row.measurements?.find(item=>item.mode==='SOCKS5'),stages=mode?.stages||[];
  let body=trafficQualityMarkup(row);
  if(row.case_id==='three-modes'){
    const off=row.measurements?.find(item=>item.mode==='OFF'),base=trafficMeasurementMetric(off,'trafficP99');
    body+=trafficObjectiveTable(['stage','status','route','rtt','delta','cpu','ram'],['OFF','UNRULED','SOCKS5'].map(name=>{
      const measured=row.measurements?.find(item=>item.mode===name),rtt=trafficMeasurementMetric(measured,'trafficP99');
      return [name,measured?trafficObjectiveLabel(measured.transport_complete===true?'ok':'bad'):'—',measured?trafficObjectiveLabel(measured.route_verified===true?'yes':'no'):'—',trafficObjectiveNumber(rtt),trafficObjectiveNumber(Number.isFinite(rtt)&&Number.isFinite(base)?rtt-base:null),trafficObjectiveNumber(trafficMeasurementMetric(measured,'trafficCpu')),trafficObjectiveNumber(trafficMeasurementMetric(measured,'trafficRam'))];
    }));
  }else if(!stages.length){body+=`<p>${trafficObjectiveLabel('missing')}</p>`;}
  else{
    const application=recipe==='application',udp=['udp','udp_unconnected','udp_sweep','udp_connections','mixed','stability','soak'].includes(recipe);
    const connections=['connections','flow_rate'].includes(recipe),latency=['echo','multistream','loaded','connections','mixed','stability','soak'].includes(recipe);
    const tx=['upload','duplex','multistream','loaded','mixed','stability','soak'].includes(recipe),rx=['download','duplex','multistream','loaded','mixed','stability','soak'].includes(recipe);
    const columns=['stage','status',...(application?['payload','transactions','targetRate','verifiedRate']:[]),...(connections?['tcp',...(recipe==='flow_rate'?['cps']:['peak'])]:[]),...(tx?['tx']:[]),...(rx?['rx']:[]),...(latency?['rtt']:[]),...(udp?['requestedPps','actualPps','sent','received','loss','worstLoss','udpRtt']:[])];
    const visible=stages.length>40?[...stages.slice(0,4),...stages.slice(-4)]:stages;
    body+=trafficObjectiveTable(columns,visible.map(stage=>{
      const u=stage.udp_observations,hasUdp=u?.flow_count>0;
      const values={stage:trafficObjectivePhase(stage.phase),status:trafficObjectiveLabel(stage.complete===true?'ok':'bad'),payload:trafficObjectiveNumber(stage.application_payload_bytes,0),transactions:trafficObjectiveNumber(stage.application_transactions,0),tcp:Number.isFinite(stage.tcp_completed)&&Number.isFinite(stage.tcp_offered)?`${stage.tcp_completed} / ${stage.tcp_offered}`:'—',cps:trafficObjectiveNumber(stage.elapsed_seconds>0?stage.tcp_completed/stage.elapsed_seconds:null),peak:trafficObjectiveNumber(stage.tcp_active_peak,0),tx:trafficObjectiveNumber(trafficMiB(stage.tcp_tx_bytes_per_second)),rx:trafficObjectiveNumber(trafficMiB(stage.tcp_rx_bytes_per_second)),rtt:trafficObjectiveNumber(stage.probe_latency?.count>0?stage.probe_p99_ms:null),sent:trafficObjectiveNumber(hasUdp?u.sent:null,0),received:trafficObjectiveNumber(hasUdp?u.received:null,0),loss:trafficObjectiveNumber(hasUdp&&u.sent>0&&Number.isFinite(u.received)?100*(u.sent-u.received)/u.sent:null),udpRtt:trafficObjectiveNumber(hasUdp&&stage.udp_latency?.count>0?stage.udp_latency.p99_ms:null)};
      const rate=stage.comparison_quality?.rates?.find(r=>r.unit==='verified-transactions');
      values.targetRate=trafficObjectiveNumber(rate?.target_per_flow);
      values.verifiedRate=Number.isFinite(rate?.actual_per_flow_min)?`${trafficObjectiveNumber(rate.actual_per_flow_min)}–${trafficObjectiveNumber(rate.actual_per_flow_max)}`:'—';
      values.requestedPps=trafficObjectiveNumber(u?.requested_pps_per_flow,0);
      values.actualPps=Number.isFinite(u?.achieved_pps_per_flow_min)&&Number.isFinite(u?.achieved_pps_per_flow_max)?`${trafficObjectiveNumber(u.achieved_pps_per_flow_min)}–${trafficObjectiveNumber(u.achieved_pps_per_flow_max)}`:'—';
      values.worstLoss=trafficObjectiveNumber(hasUdp&&Number.isFinite(stage.max_udp_flow_loss_fraction)?100*stage.max_udp_flow_loss_fraction:null);
      return columns.map(key=>values[key]);
    }));
    if(stages.length>40)body+=`<small>${trafficObjectiveLabel('limited')}</small>`;
    if(application)body+=trafficObjectiveProtocol(stages);
    if(udp){
      body+=`<small>${trafficObjectiveLabel('rateScope')}</small>`;
      const counters=mode?.overall?.udp_observations;
      if(counters?.flow_count>0)body+=`<section class="result-metric-group"><div class="result-quick-metrics">${['invalid','duplicates','reordered','expired','send_errors'].filter(key=>Number.isFinite(counters[key])).map(key=>`<span>${html(trafficObjectiveLabel(key))}<b>${trafficObjectiveNumber(counters[key],0)}</b></span>`).join('')}</div></section>`;
    }
    if(['mixed','stability','soak'].includes(recipe))body+=`<small>${trafficObjectiveLabel('scope')}</small>`;
    if(recipe==='flow_rate'){const workers=stages.find(s=>s.phase==='churn')?.workload_profiles?.find(w=>w.task==='flow_rate')?.connections;if(workers)body+=`<small>${workers} ${labLanguage==='ru'?'параллельных исполнителя':'parallel workers'} · 50 ${labLanguage==='ru'?'мс обмена на сеанс':'ms exchange per session'}</small>`;}
    if(recipe==='flow_rate')body+=`<small>${trafficObjectiveLabel('churnScope')}</small>`;
  }
  const goal=row.case_id==='three-modes'?'modes':recipe;
  const warning=mode&&(!mode.complete||!mode.route_verified)?`<p class="result-observed">${trafficObjectiveLabel('observed')}</p>`:'';
  const resourceKey=view.key?view.key+'.resources':null;
  return `<section class="objective-result"><p class="objective-purpose"><b>${trafficObjectiveLabel('goal')}:</b> ${html(trafficObjectiveLabel(goal))}</p>${warning}${body}<details class="objective-additional" ${resourceKey?`data-result-key="${html(resourceKey)}" ${view.expanded?.has(resourceKey)?'open':''}`:''}><summary>${trafficObjectiveLabel('resources')}</summary>${trafficPhaseResourceMarkup(mode)}${trafficReportAdditionalMetricMarkup(row)}</details></section>`;
}

Object.assign(trafficObjectiveText.ru,{targetRate:'Цель, обменов/с на поток',verifiedRate:'Подтверждено, обменов/с на поток',transactions:'Подтверждено обменов',tcp:'Успешных сеансов / попыток'});
Object.assign(trafficObjectiveText.en,{targetRate:'Target transactions/s per flow',verifiedRate:'Verified transactions/s per flow',transactions:'Verified transactions',tcp:'Successful sessions / attempts'});
function trafficQualityCpuCost(mode,transactions){
  const seconds=mode?.workload_resources?.product_cli?.counters?.cpu_seconds?.measured_change;
  const stages=(mode?.stages||[]).filter(s=>!['baseline','recovery'].includes(s.phase));
  if(!Number.isFinite(seconds)||seconds<0||!stages.length)return null;
  const work=transactions?stages.reduce((n,s)=>n+(s.application_transactions||0),0):stages.reduce((n,s)=>n+(s.tcp_tx_bytes_per_second+s.tcp_rx_bytes_per_second)*s.elapsed_seconds,0);
  return Number.isFinite(work)&&work>0?seconds/work*(transactions?1000:1073741824):null;
}
function trafficQualityNote(row){
  const q=row?.measurements?.find(m=>m.mode==='SOCKS5')?.comparison_quality,ru=labLanguage==='ru';
  if(!q||q.exchange_state==='UNKNOWN')return ru?'Архив: качество нагрузки не измерялось; ресурсы за весь этап':'Archive: load quality was not measured; resources cover the whole case';
  const notes=[ru?'Ресурсы: нагрузочные интервалы':'Resources: load windows'];
  if(!q.windows_complete){const m=row.measurements.find(m=>m.mode==='SOCKS5');notes.push(`${m.recorded_stage_count??'?'} / ${m.planned_stage_count??'?'} ${ru?'интервалов':'windows'}`);}
  if(q.route_accounting==='PARTIAL')notes.push(ru?'неполный учёт маршрута':'partial route accounting');
  if(['BELOW_TARGET','OFF_TARGET'].includes(q.load_state))notes.push(ru?'темп ниже цели':'rate below target');
  if(q.load_state==='PROFILE')notes.push(ru?'измерена работа этого профиля; предел клиента не установлен':'observed profile performance; client capacity ceiling unverified');
  if(q.load_state==='NOT_MEASURED')notes.push(ru?'фиксированный темп не подтверждён':'fixed rate not confirmed');
  if(q.headroom==='CPU_SATURATED')notes.push(ru?'стенд: CPU насыщен':'lab CPU saturated');
  return notes.join(' · ');
}
function trafficQualityRankable(runs,rows,key){
  if(rows.some((row,i)=>!trafficReportComparable(runs[0],rows[0],runs[i],row)))return false;
  const qs=rows.map(row=>row?.measurements?.find(m=>m.mode==='SOCKS5')?.comparison_quality);
  if(qs.some(q=>!q||q.exchange_state!=='PASS'||!q.windows_complete||q.route_accounting!=='COMPLETE'))return false;
  if(['trafficCliRamDelta','trafficCliResidentDelta','trafficRecoveryP99Change'].includes(key))return false;
  if(qs.some(q=>q.headroom!=='CPU_NOT_SATURATED'))return false;
  if(qs.some(q=>q.load_state!=='MET'))return false;
  return true;
}
function trafficQualityMarkup(row){
  const mode=row?.measurements?.find(m=>m.mode==='SOCKS5'),q=mode?.comparison_quality,ru=labLanguage==='ru';
  const labels=ru?{PASS:'подтверждён',FAIL:'ошибка',UNKNOWN:'не измерено',COMPLETE:'полный',PARTIAL:'неполный',UNVERIFIED:'не подтверждён',MET:'достигнут (допуск 5%)',PROFILE:'профиль без фиксированного темпа',BELOW_TARGET:'цель не достигнута',OFF_TARGET:'темп вне допуска',NOT_MEASURED:'не измерено'}:{PASS:'verified',FAIL:'failed',UNKNOWN:'not measured',COMPLETE:'complete',PARTIAL:'partial',UNVERIFIED:'unverified',MET:'met (5% tolerance)',PROFILE:'profile without a fixed rate',BELOW_TARGET:'target not reached',OFF_TARGET:'rate outside tolerance',NOT_MEASURED:'not measured'};
  if(!q||q.exchange_state==='UNKNOWN')return `<small>${html(trafficQualityNote(row))}</small>`;
  return `<p class="objective-purpose">${html(ru?'Обмен':'Exchange')}: ${html(labels[q.exchange_state]||q.exchange_state)} · ${html(ru?'Учёт маршрута':'Route accounting')}: ${html(labels[q.route_accounting]||q.route_accounting)} · ${html(ru?'Темп':'Rate')}: ${html(labels[q.load_state]||q.load_state)}</p><small>${html(trafficQualityNote(row))}</small>`;
}
function trafficPhaseResourceMarkup(mode){
  const ru=labLanguage==='ru',stages=(mode?.stages||[]).filter(s=>s.phase_resources?.product_cli?.counters);
  if(!stages.length)return '';
  const columns=ru?['Интервал','CPU клиента, % ПК','Commit: первый / пик / последний, МиБ','RAM: первый / пик / последний, МиБ','Потоки: пик']:['Window','Client CPU, % of PC','Private: first / peak / last, MiB','Resident: first / peak / last, MiB','Peak threads'];
  return trafficObjectiveTable(columns,stages.map(s=>{const c=s.phase_resources.product_cli.counters;const memory=k=>['first','max','last'].map(n=>trafficObjectiveNumber(trafficMiB(c[k]?.[n]))).join(' / ');return [trafficObjectivePhase(s.phase),trafficObjectiveNumber(c.cpu_percent_of_pc?.mean),memory('private_bytes'),memory('working_set_bytes'),trafficObjectiveNumber(c.threads?.max,0)];}));
}

function trafficQualityRateMetric(mode,key){
  const profiles=(mode?.stages||[]).filter(s=>!['baseline','recovery'].includes(s.phase)).flatMap(s=>s.comparison_quality?.rates||[]);
  if(!profiles.length)return null;
  if(key==='trafficTargetTransactions')return profiles.every(r=>r.unit==='verified-transactions')?profiles.reduce((sum,r)=>sum+r.target_per_flow*r.connections*r.window_seconds,0):null;
  const values=profiles.map(r=>key==='trafficRateTarget'?r.target_per_flow:key==='trafficRateMin'?r.actual_per_flow_min:r.actual_per_flow_max);
  if(!values.every(Number.isFinite))return null;
  return key==='trafficRateTarget'?(values.every(v=>v===values[0])?values[0]:null):key==='trafficRateMin'?Math.min(...values):Math.max(...values);
}
function trafficRouteAccountingUnverified(row){
  const q=row?.measurements?.find(m=>m.mode==='SOCKS5')?.comparison_quality;
  return !row?.cancelled&&(row?.measurements||[]).every(m=>m.mode==='SOCKS5'||m.complete)&&q?.exchange_state==='PASS'&&q.route_accounting==='PARTIAL'&&row.cleanup_verified===true&&(row.errors||[]).length>0&&(row.errors||[]).every(e=>['TRAFFIC_TRANSPORT_INCOMPLETE','TRAFFIC_ROUTE_UNVERIFIED'].includes(e));
}
