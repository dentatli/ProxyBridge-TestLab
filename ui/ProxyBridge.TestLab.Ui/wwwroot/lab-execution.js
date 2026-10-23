"use strict";
// Presentation uses confirmed runner milestones; it never supplies execution evidence.
const trafficQueueText={
  ru:{preparation:"Подготовка",environment:"Подготовка машины",baseline:"Исходное состояние",client:"Работоспособность клиента",cleanup:"Завершение",product:"Клиент остановлен",origin:"Получатель освобождён",WAIT:"В очереди",RUNNING:"Выполняется",PASS:"Успешно",PROVISIONAL:"Этап пройден",FAIL:"Ошибка",MIXED:"Частично успешно",CANCELLED:"Отменено",SKIP:"Пропущено",UNKNOWN:"Не подтверждено",FINISHED:"Проверка завершена",STOPPING:"Завершение и очистка",completed:"Завершено",logs:"Результаты и логи",provisional:"Итог подтвердится после очистки"},
  en:{preparation:"Preparation",environment:"Machine preparation",baseline:"Initial state",client:"Client readiness",cleanup:"Finishing",product:"Client stopped",origin:"Receiver released",WAIT:"Queued",RUNNING:"Running",PASS:"Passed",PROVISIONAL:"Stage passed",FAIL:"Failed",MIXED:"Partially passed",CANCELLED:"Cancelled",SKIP:"Skipped",UNKNOWN:"Unverified",FINISHED:"Run finished",STOPPING:"Finishing and cleanup",completed:"Completed",logs:"Results and logs",provisional:"Final result follows cleanup"}
};
const trafficQueueLabel=key=>trafficQueueText[labLanguage]?.[key]||trafficQueueText.en[key]||key;
const trafficQueueIcons={WAIT:"○",RUNNING:"●",PASS:"✓",PROVISIONAL:"✓",FAIL:"×",MIXED:"◐",CANCELLED:"—",SKIP:"—",UNKNOWN:"?"};
let trafficQueueDomKey="",trafficQueuePreferences={},trafficQueueRunId=null;

function trafficQueueAggregate(rows){
  const statuses=rows.map(row=>row.status),pass=statuses.some(value=>["PASS","PROVISIONAL"].includes(value)),fail=statuses.includes("FAIL");
  if(pass&&fail)return "MIXED";
  if(statuses.includes("RUNNING"))return "RUNNING";
  if(fail)return "FAIL";
  if(statuses.every(value=>value==="PASS"))return "PASS";
  if(statuses.every(value=>["PASS","PROVISIONAL"].includes(value)))return "PROVISIONAL";
  if(statuses.includes("WAIT"))return "WAIT";
  if(statuses.includes("UNKNOWN"))return "UNKNOWN";
  return statuses.includes("CANCELLED")?"CANCELLED":"SKIP";
}

function trafficQueueModel(execution,catalog){
  const run=execution?.run;if(!run?.id)return null;
  const active=execution.active===true,queue=execution.queue?.run_id===run.id?execution.queue:null;
  const requested=run.cases||[],results=active?(queue?.results||[]):(run.results||[]);
  const progress=execution.progress;
  const current=active?(queue?queue.current_case_id:requested.find(row=>progress?.run_id?.startsWith(`${run.id}.${row.id||row.Id}.`))?.id):null;
  const terminal=run.state==="CANCELLED"?"CANCELLED":"UNKNOWN";
  const phase=queue?.phase;
  const prepared=queue?.client_ready===true;
  const milestone=(ready,running)=>ready?"PASS":active?(running?"RUNNING":"WAIT"):terminal;
  const preparing=active&&(!queue||["PREPARING","BASELINE","CLIENT_STARTING"].includes(phase)||phase==="TESTING"&&!prepared);
  const prepRows=[
    {id:"environment",name:trafficQueueLabel("environment"),status:milestone(queue?.environment_ready,preparing&&(!queue||phase==="PREPARING"))},
    {id:"baseline",name:trafficQueueLabel("baseline"),status:milestone(queue?.baseline_ready,phase==="BASELINE")},
    {id:"client",name:trafficQueueLabel("client"),status:milestone(prepared,phase==="CLIENT_STARTING"||phase==="TESTING"&&!prepared)}
  ];
  if(queue?.preparation_failed){
    const failed=prepRows.find(row=>row.status!=="PASS");if(failed)failed.status="FAIL";
  }else if(queue?.cancelled){prepRows.filter(row=>row.status!=="PASS").forEach(row=>row.status="CANCELLED");}
  if(!queue&&!active&&run.state==="FAILED"&&!results.length){prepRows[0].status="FAIL";}
  // Historic/remote runs without a milestone file use actual completed evidence only.
  if(!queue&&(run.results||[]).some(row=>row.complete&&row.cleanup_verified))prepRows.forEach(row=>row.status="PASS");
  const groups=[{id:"preparation",name:trafficQueueLabel("preparation"),rows:prepRows,current:preparing&&!!queue}];
  for(const group of trafficFamilyReportGroups(catalog,requested,results)){
    const rows=group.stages.map((stage,index)=>{
      const result=group.rows[index];
      let status=active?"WAIT":terminal;
      if(result){
        status=result.skipped?"SKIP":result.cancelled?"CANCELLED":result.complete===true?(active?"PROVISIONAL":result.cleanup_verified===true?"PASS":"UNKNOWN"):"FAIL";
      }else if(current===stage.id)status="RUNNING";
      return {id:stage.id,name:trafficName(stage.id),status};
    });
    groups.push({id:group.family.id,name:trafficFamilyName(group.family),rows,current:rows.some(row=>row.id===current)&&!preparing});
  }
  const finishing=active&&(phase==="CLEANUP"||phase==="FINISHED");
  const productDone=queue?.product_cleanup_verified===true||!active&&run.cleanup_verified===true;
  const originDone=!active&&(run.mode!=="local"||run.local_origin_cleanup_verified===true);
  groups.push({id:"cleanup",name:trafficQueueLabel("cleanup"),current:finishing,rows:[
    {id:"product",name:trafficQueueLabel("product"),status:productDone?"PASS":active?(finishing?"RUNNING":"WAIT"):"UNKNOWN"},
    {id:"origin",name:trafficQueueLabel("origin"),status:originDone?"PASS":active?(phase==="FINISHED"?"RUNNING":"WAIT"):"UNKNOWN"}
  ]});
  for(const group of groups)group.status=trafficQueueAggregate(group.rows);
  const measured=groups.slice(1,-1).flatMap(group=>group.rows);
  return {id:run.id,active,groups,completed:measured.filter(row=>!["WAIT","RUNNING","UNKNOWN"].includes(row.status)).length,total:requested.length,finishing,passed:measured.filter(row=>row.status==="PASS").length,failed:measured.filter(row=>row.status==="FAIL").length};
}

function renderTrafficExecution(execution){
  const container=lab("traffic-execution"),model=trafficQueueModel(execution,trafficCatalog);
  container.hidden=!model;if(!model)return;
  if(trafficQueueRunId!==model.id){
    trafficQueueRunId=model.id;
    try{const saved=JSON.parse(sessionStorage.getItem("testlab-queue-expansion")||"null");trafficQueuePreferences=saved?.id===model.id?saved.preferences||{}:{};}catch{trafficQueuePreferences={};}
  }
  const key=JSON.stringify([model.id,labLanguage,model.groups.map(group=>[group.id,group.rows.map(row=>row.id)])]);
  if(key!==trafficQueueDomKey){
    trafficQueueDomKey=key;
    container.innerHTML=`<div class="traffic-queue-overview"><strong data-queue-overview role="status" aria-live="polite"></strong><a href="/lab.html?page=results" data-lab-page="results">${html(trafficQueueLabel("logs"))}</a></div><ol class="traffic-queue-list">${model.groups.map((group,index)=>`<li><details data-queue-card="${html(group.id)}"><summary><span class="traffic-queue-number">${index+1}</span><span class="traffic-queue-title">${html(group.name)}</span><span class="traffic-queue-status"></span><span class="traffic-queue-count"></span></summary><ol class="traffic-queue-stages">${group.rows.map(row=>`<li data-queue-stage="${html(row.id)}"><span class="traffic-queue-stage-icon" aria-hidden="true"></span><span>${html(row.name)}</span><span class="traffic-queue-stage-status"></span></li>`).join("")}</ol></details></li>`).join("")}</ol>`;
    container.querySelectorAll("details").forEach(card=>{
      card.querySelector("summary").addEventListener("click",event=>{
        event.preventDefault();card.open=!card.open;
        trafficQueuePreferences[card.dataset.queueCard]=card.open;
        try{sessionStorage.setItem("testlab-queue-expansion",JSON.stringify({id:model.id,preferences:trafficQueuePreferences}));}catch{}
      });
    });
    // Links added after initial page binding participate in normal lab navigation.
    container.querySelector("a").addEventListener("click",event=>{event.preventDefault();navigateLab("results");});
  }
  container.querySelector("[data-queue-overview]").textContent=`${model.active?(model.finishing?trafficQueueLabel("STOPPING"):trafficQueueLabel("RUNNING")):trafficQueueLabel("FINISHED")} · ${model.completed}/${model.total}${!model.active?` · ${trafficQueueLabel("PASS")}: ${model.passed} · ${trafficQueueLabel("FAIL")}: ${model.failed}`:""}`;
  for(const group of model.groups){
    const card=container.querySelector(`[data-queue-card="${CSS.escape(group.id)}"]`);
    card.dataset.status=group.status;card.classList.toggle("is-current",group.current);
    card.open=Object.hasOwn(trafficQueuePreferences,group.id)?trafficQueuePreferences[group.id]:group.current;
    card.querySelector(".traffic-queue-status").textContent=`${trafficQueueIcons[group.status]} ${trafficQueueLabel(group.current?"RUNNING":group.status)}`;
    card.querySelector(".traffic-queue-count").textContent=`${group.rows.filter(row=>!["WAIT","RUNNING","UNKNOWN"].includes(row.status)).length}/${group.rows.length}`;
    for(const row of group.rows){
      const element=card.querySelector(`[data-queue-stage="${CSS.escape(row.id)}"]`);
      element.dataset.status=row.status;
      element.querySelector(".traffic-queue-stage-icon").textContent=trafficQueueIcons[row.status];
      element.querySelector(".traffic-queue-stage-status").textContent=trafficQueueLabel(row.status);
    }
  }
  lab("traffic-run-status").hidden=true;
}
