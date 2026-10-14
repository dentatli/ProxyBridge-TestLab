"use strict";
Object.assign(labText.ru, {
  trafficHeading:"Трафик, скорость, нагрузка и стабильность", trafficScope:"Ubuntu 22.04. Транспортные и прикладные протоколы: HTTP, QUIC, DNS, SSH, почта и обмен сообщениями. Проверка данных и маршрута, потери UDP, CPU/RAM всей ОС и CPU/RAM/handles/threads отдельных процессов. Число соединений и скорость не доказывают максимальную ёмкость или ресурсы драйвера.",
  trafficPrepare:"Проверить / подготовить runtime", trafficApply:"Установить по этому плану", trafficStart:"Запустить выбранные проверки", trafficStop:"Остановить и очистить", trafficDebugger:"WinDbg не запущен или все точки отключены; диагностический прогон не выполняется",
  trafficAdmin:"Для реальных проверок запустите scripts/Start-TestLabUi.ps1 -Administrator. При включённом UAC потребуется подтверждение.",
  trafficLongRun:"Разрешаю выбранный набор более 5 минут, включая 24/48/72 часа", trafficRunHelp:"Используется выбранная сборка. Перед каждым тестом проверяются файлы, получатель, OFF и UNRULED. SOCKS5 требует подписанных свидетельств. Неудачная очистка прекращает очередь.",
  trafficResults:"Удалённые проверки: история и измерения", trafficResultsHelp:"Ошибки и отмены сохраняются отдельно. CPU процесса нормирован на все логические CPU; RAM процесса не является памятью драйвера. Разные параметры и получатели сравнивайте отдельно.", trafficConditions:"Тест и условия", trafficAll:"Все попытки", trafficNone:"Удалённых попыток пока нет", trafficReady:"Состояние runtime", trafficEstimate:"Оценка с подготовкой", trafficPhase:"Этап", trafficSent:"Отправка, MiB/s", trafficReceived:"Получение, MiB/s", trafficP99:"RTT p99, мс", trafficLoss:"Потери UDP, %", trafficConnections:"TCP завершено / предложено", trafficCpu:"CLI CPU, % ПК", trafficRam:"CLI private commit, MiB", trafficEmpty:"Измерений нет",trafficMinutes:"мин",trafficRouteOk:"Маршрут подтверждён",trafficRouteBad:"Маршрут не подтверждён",trafficApplicationEvidence:"Прикладной обмен",trafficTransactions:"Проверенных обменов",trafficErrors:"Ошибки",trafficSkippedStages:"Пропущено этапов"
});
Object.assign(labText.en, {
  trafficHeading:"Traffic, speed, load and stability", trafficScope:"Ubuntu 22.04. Transport and application protocols: HTTP, QUIC, DNS, SSH, mail and messaging. Data and route validation, UDP loss, whole-OS CPU/RAM and CPU/RAM/handles/threads of identified processes. Connection count and speed do not establish absolute capacity or driver resource use.",
  trafficPrepare:"Check / prepare runtime", trafficApply:"Install this exact plan", trafficStart:"Start selected checks", trafficStop:"Stop and clean up", trafficDebugger:"WinDbg is closed or all breakpoints are disabled; no diagnostic run is active",
  trafficAdmin:"For real checks run scripts/Start-TestLabUi.ps1 -Administrator. With UAC enabled, Windows will request confirmation.",
  trafficLongRun:"I authorize this selection exceeding 5 minutes, including 24/48/72 hours", trafficRunHelp:"Uses the selected build. Files, origin, OFF and UNRULED are checked before each case. SOCKS5 requires signed evidence. Failed cleanup stops the queue.",
  trafficResults:"Remote checks: history and measurements", trafficResultsHelp:"Failures and cancellation are saved separately. Process CPU is normalized to all logical CPUs; process RAM is not driver memory. Compare different parameters and origins separately.", trafficConditions:"Case and conditions", trafficAll:"All attempts", trafficNone:"No remote attempts yet", trafficReady:"Runtime state", trafficEstimate:"Estimate including preparation", trafficPhase:"Stage", trafficSent:"Upload, MiB/s", trafficReceived:"Download, MiB/s", trafficP99:"RTT p99, ms", trafficLoss:"UDP loss, %", trafficConnections:"TCP completed / offered", trafficCpu:"CLI CPU, % of PC", trafficRam:"CLI private commit, MiB", trafficEmpty:"No measurements",trafficMinutes:"min",trafficRouteOk:"Route verified",trafficRouteBad:"Route unverified",trafficApplicationEvidence:"Application exchange",trafficTransactions:"Verified transactions",trafficErrors:"Errors",trafficSkippedStages:"Skipped stages"
});
labText.ru.remoteTestGate='Для сетевых измерений используйте каталог ниже. Перед каждым тестом контроллер проверяет обмен и маршрут; неподтверждённый маршрут сохраняется как ошибка.';
labText.en.remoteTestGate='Use the traffic catalog below. The controller validates exchange and route before each case; an unverified route is saved as a failure.';
labText.ru.trafficApplyUnknown='Результат настройки не подтверждён. Нажмите «Проверить / подготовить runtime» для повторной проверки того же сервера и создания нового плана.';
labText.en.trafficApplyUnknown='The setup result is unconfirmed. Check / prepare runtime again to inspect the same server and create a new plan.';
Object.assign(labText.ru,{trafficControls:'Контрольные режимы',trafficMeasurementState:'Нагрузка',trafficMeasurement_NOT_STARTED:'Не началась',trafficMeasurement_PARTIAL:'Неполный прогон',trafficMeasurement_COMPLETED:'Завершена',trafficMeasurement_UNKNOWN:'Нет сведений о начале нагрузки',trafficStageCounts:'Этапы: начаты / записаны / запланированы',trafficFailurePhase:'Остановка на этапе',trafficFailure_REGISTERING_SESSION:'Подготовка сеанса с получателем',trafficFailure_RUNNING_WORKLOAD:'Выполнение нагрузки',trafficFailure_COLLECTING_EVIDENCE:'Получение свидетельств и ожидание освобождения соединений',trafficFailure_WRITING_REPORT:'Сохранение отчёта',trafficFailure_PREPARING_REPORT:'Подготовка отчёта',trafficFailure_UNKNOWN:'Неизвестно',trafficLossEvidence:'Порог потерь ответов',trafficLoss_NOT_MEASURED:'Не измерено',trafficLoss_NOT_APPLICABLE:'Не применяется',trafficLoss_UNKNOWN:'Не подтверждено',trafficCliReady:'CLI вышел в READY',trafficCliCleanup:'Штатное завершение CLI'});
Object.assign(labText.en,{trafficControls:'Control modes',trafficMeasurementState:'Workload',trafficMeasurement_NOT_STARTED:'Not started',trafficMeasurement_PARTIAL:'Partial run',trafficMeasurement_COMPLETED:'Completed',trafficMeasurement_UNKNOWN:'Workload start unknown',trafficStageCounts:'Stages: started / recorded / planned',trafficFailurePhase:'Stopped during',trafficFailure_REGISTERING_SESSION:'Preparing the origin session',trafficFailure_RUNNING_WORKLOAD:'Running the workload',trafficFailure_COLLECTING_EVIDENCE:'Collecting evidence and waiting for connections to drain',trafficFailure_WRITING_REPORT:'Saving the report',trafficFailure_PREPARING_REPORT:'Preparing the report',trafficFailure_UNKNOWN:'Unknown',trafficLossEvidence:'Reply loss threshold',trafficLoss_NOT_MEASURED:'Not measured',trafficLoss_NOT_APPLICABLE:'Not applicable',trafficLoss_UNKNOWN:'Unconfirmed',trafficCliReady:'CLI reached READY',trafficCliCleanup:'Graceful CLI shutdown'});
Object.assign(labText.ru,{trafficContinue:"Продолжать после ошибки при подтверждённом восстановлении",trafficContinueHelp:"После ошибки теста контроллер проверяет штатное закрытие CLI, выключенный драйвер, подписанную идентичность и отсутствие соединений получателя. Отмена, смена файлов, потеря связи или непроверенная очистка останавливают очередь. Неудачные тесты сохраняют FAIL.",trafficQueuePolicy:"Продолжение после ошибки",trafficRecovery:"Проверка восстановления",trafficRecoveryOk:"Продолжение разрешено",trafficRecoveryBlocked:"Продолжение заблокировано"});
Object.assign(labText.en,{trafficContinue:"Continue after a failed case when recovery is verified",trafficContinueHelp:"After a case fails, the controller verifies graceful CLI shutdown, the driver being off, signed origin identity and no remaining connections. Cancellation, changed files, disconnection or unverified cleanup stop the queue. Failed cases retain FAIL.",trafficQueuePolicy:"Continue after failure",trafficRecovery:"Recovery check",trafficRecoveryOk:"Continuation allowed",trafficRecoveryBlocked:"Continuation blocked"});
let trafficCatalog=null, trafficState=null, trafficHistory=[], trafficActionActive=false, trafficError="", trafficChoice={};
let trafficCardsKey="", trafficHistoryKey="", trafficLoading=false;
let trafficCategoryKey="";
Object.assign(labText.ru,{trafficSearch:"Найти тест",trafficCategory:"Группа тестов",trafficSearchHelp:"Поиск и группа скрывают карточки, сохраняя выбранные тесты и их параметры.",trafficCategoriesAll:"Все группы",trafficSelectedOnly:"Выбранные тесты",trafficShown:"Показано",trafficSelected:"Выбрано",trafficHiddenSelected:"Скрыто фильтром",trafficNoMatches:"Подходящих тестов нет. Измените поиск или группу.",trafficGroup_transport:"Транспорт, скорость и стабильность",trafficGroup_web:"HTTP, WebSocket и gRPC",trafficGroup_security:"TLS и QUIC",trafficGroup_dns:"DNS",trafficGroup_ssh:"SSH и SFTP",trafficGroup_mail:"Почта: SMTP, IMAP и POP3",trafficGroup_messaging:"Сообщения: MQTT и AMQP",trafficGroup_other:"Прочие протоколы"});
Object.assign(labText.en,{trafficSearch:"Find a test",trafficCategory:"Test group",trafficSearchHelp:"Search and group filters hide cards while preserving selected tests and their settings.",trafficCategoriesAll:"All groups",trafficSelectedOnly:"Selected tests",trafficShown:"Shown",trafficSelected:"Selected",trafficHiddenSelected:"Hidden by filters",trafficNoMatches:"No matching tests. Change the search or group.",trafficGroup_transport:"Transport, speed and stability",trafficGroup_web:"HTTP, WebSocket and gRPC",trafficGroup_security:"TLS and QUIC",trafficGroup_dns:"DNS",trafficGroup_ssh:"SSH and SFTP",trafficGroup_mail:"Mail: SMTP, IMAP and POP3",trafficGroup_messaging:"Messaging: MQTT and AMQP",trafficGroup_other:"Other protocols"});
const trafficGroups=["transport","web","security","dns","ssh","mail","messaging","other"];
function trafficGroup(row){
  if(row.recipe!=="application")return "transport";
  if(["http","https","http2","http3","grpc","websocket","websocket-tls"].includes(row.application))return "web";
  if(["tls","quic"].includes(row.application))return "security";
  return {"dns-classic":"dns","dns-encrypted":"dns",ssh:"ssh",sftp:"ssh",mail:"mail",mqtt:"messaging",amqp:"messaging"}[row.family]||"other";
}
function filterTrafficCards(){
  const rows=trafficCatalog?.cases||[], category=lab("traffic-category").value;
  const words=lab("traffic-search").value.normalize("NFKC").trim().toLocaleLowerCase().split(/\s+/).filter(Boolean);
  let shown=0,hiddenSelected=0;
  for(const card of lab("traffic-cases").querySelectorAll("[data-traffic-card]")){
    const row=rows.find(item=>item.id===card.dataset.trafficCard), group=trafficGroup(row);
    const selected=!!trafficChoice[row.id]?.selected;
    const haystack=[row.id,row.ru,row.en,row.application,row.family].join(" ").normalize("NFKC").toLocaleLowerCase();
    card.hidden=!(category==="all"||category==="selected"&&selected||category===group)||!words.every(word=>haystack.includes(word));
    if(!card.hidden)shown++;else if(selected)hiddenSelected++;
  }
  for(const section of lab("traffic-cases").querySelectorAll("[data-traffic-group]")){
    section.hidden=![...section.querySelectorAll("[data-traffic-card]")].some(card=>!card.hidden);
  }
  lab("traffic-search-status").textContent=`${t("trafficShown")}: ${shown}/${rows.length} · ${t("trafficSelected")}: ${trafficCases().length} · ${t("trafficHiddenSelected")}: ${hiddenSelected}${shown?"":` · ${t("trafficNoMatches")}`}`;
}
let trafficComparison=[],trafficComparisonKey="",trafficNextSkip=0,trafficHasMore=false,trafficCompareChoice={builds:{},metrics:{}};
let trafficHistoryLoadedAt=null,trafficComparisonLoadedAt=null,trafficSnapshotUnavailable=true;
let trafficComparisonBlocked=false,trafficUnreadableHistory=false;
labText.ru.trafficPayloadBytes='Полезные данные запроса, байт';
labText.en.trafficPayloadBytes='Request payload, bytes';
Object.assign(labText.ru,{trafficConnectP50:'Соединение и аутентификация p50, мс',trafficConnectP95:'Соединение и аутентификация p95, мс',trafficConnectP99:'Соединение и аутентификация p99, мс',trafficConnectSamples:'Измерений соединения',trafficConnectHelp:'В сценарии частых подключений: до подтверждённой аутентификации получателя, только завершённые обмены. Сводка объединяет гистограммы всех этапов; процентили — верхние границы с шагом 1%. Это не TCP RTT и не время TLS/SSH handshake.'});
Object.assign(labText.en,{trafficConnectP50:'Connection and authentication p50, ms',trafficConnectP95:'Connection and authentication p95, ms',trafficConnectP99:'Connection and authentication p99, ms',trafficConnectSamples:'Connection samples',trafficConnectHelp:'Flow churn: time through verified origin authentication, completed exchanges only. Aggregates merge histograms across all stages; percentiles are upper bounds with 1% bins. This is not TCP RTT or TLS/SSH handshake timing.'});
Object.assign(labText.ru,{trafficMemoryDelta:'Изменение памяти, МиБ',trafficMemoryDeltaHelp:'Разница последнего и первого доступных наблюдений одной идентичности процесса за весь профиль; нужно минимум два образца. Показатель не определяет причину роста. Память ОС включает фоновую работу.',trafficCliRamDelta:'CLI private commit: изменение, МиБ',trafficCliResidentDelta:'CLI рабочий набор: изменение, МиБ',trafficOriginProcessRamDelta:'Origin/proxy RSS: изменение, МиБ'});
Object.assign(labText.en,{trafficMemoryDelta:'Memory change, MiB',trafficMemoryDeltaHelp:'Last minus first available observations of one process identity across the whole workload schedule; at least two samples are required. The counter does not identify the cause of growth. Whole-OS memory includes background work.',trafficCliRamDelta:'CLI private commit change, MiB',trafficCliResidentDelta:'CLI working set change, MiB',trafficOriginProcessRamDelta:'Origin/proxy RSS change, MiB'});
Object.assign(labText.ru,{trafficCoverage:'Полнота ресурсных наблюдений',trafficCoverageRole:'Источник',trafficCoverageAvailable:'Доступны / попытки опроса',trafficCoverageCpu:'Образцы CPU',trafficCoverageMemory:'Область памяти',trafficCoverageHelp:'Среднее CPU рассчитано по доступным интервалам. Пропуски и первое наблюдение без CPU-дельты не считаются нулями; эти данные не измеряют ресурсы драйвера.',trafficResource_product_cli:'CLI ProxyBridge',trafficResource_worker:'Исполнитель нагрузки',trafficResource_windows_system:'Windows целиком',trafficResource_worker_system:'ОС исполнителя целиком',trafficResource_origin_system:'Ubuntu целиком',trafficResource_origin_and_proxy:'Процесс получателя и SOCKS5'});
Object.assign(labText.en,{trafficCoverage:'Resource observation coverage',trafficCoverageRole:'Source',trafficCoverageAvailable:'Available / observation attempts',trafficCoverageCpu:'CPU samples',trafficCoverageMemory:'Memory scope',trafficCoverageHelp:'Mean CPU uses available intervals. Gaps and the initial observation without a CPU delta are not zeros; these counters do not measure driver resources.',trafficResource_product_cli:'ProxyBridge CLI',trafficResource_worker:'Load worker',trafficResource_windows_system:'Whole Windows OS',trafficResource_worker_system:'Whole worker OS',trafficResource_origin_system:'Whole Ubuntu OS',trafficResource_origin_and_proxy:'Origin and SOCKS5 process'});
Object.assign(labText.ru,{trafficHistoryUnreadable:'Один или несколько отчётов отсутствуют или не читаются. История неполная; сравнение заблокировано, старые успехи не подставляются.',trafficHistoryUnavailable:'История не обновлена: источник недоступен. Показаны ранее загруженные записи; сравнение и выгрузка недоступны.'});
Object.assign(labText.en,{trafficHistoryUnreadable:'One or more reports are missing or unreadable. History is incomplete; comparison is blocked without substituting older successes.',trafficHistoryUnavailable:'History could not refresh: the source is unavailable. Previously loaded entries are shown; comparison and export are unavailable.'});
Object.assign(labText.ru,{trafficLiveHelp:'Текущие счётчики получателя; итог обмена и маршрута ещё не подтверждён.',trafficLiveUnavailable:'Свежие счётчики получателя недоступны.',trafficLiveRx:'Принято, МиБ',trafficLiveTx:'Отправлено, МиБ',trafficLiveActive:'Активные сеансы',trafficLiveTransactions:'Прикладные запросы',trafficLiveElapsed:'Время текущего задания, с'});
Object.assign(labText.en,{trafficLiveHelp:'Current origin counters; final exchange and route are not yet verified.',trafficLiveUnavailable:'Fresh origin counters are unavailable.',trafficLiveRx:'Received, MiB',trafficLiveTx:'Sent, MiB',trafficLiveActive:'Active sessions',trafficLiveTransactions:'Application requests',trafficLiveElapsed:'Elapsed in the current workload schedule, s'});
Object.assign(labText.ru,{trafficExportComparison:'Скачать выбранное сравнение (CSV)',trafficExportHistory:'Скачать загруженную историю (JSON)',trafficExportHelp:'В CSV попадут выбранные сборки и показатели для текущих условий. JSON содержит только загруженные страницы с текущим фильтром; наличие следующих страниц указано в файле. Неподтверждённые показатели остаются пустыми.',trafficExportUnavailable:'Обновите результаты и выберите строки для выгрузки.',trafficExportTooLarge:'Выгрузка превышает 8 МиБ. Сузьте выбор результатов.',trafficExportStarted:'Выгрузка подготовлена. Файл передан браузеру.'});
Object.assign(labText.en,{trafficExportComparison:'Download selected comparison (CSV)',trafficExportHistory:'Download loaded history (JSON)',trafficExportHelp:'CSV includes selected builds and metrics for the current conditions. JSON includes only loaded pages with the current filter; the file indicates whether more pages exist. Unconfirmed metrics remain empty.',trafficExportUnavailable:'Refresh results and select rows to export.',trafficExportTooLarge:'Export exceeds 8 MiB. Narrow the result selection.',trafficExportStarted:'Export prepared. The file was handed to the browser.'});
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
const trafficCaseEstimate=row=>row.id==="soak"?({SHORT:24,NORMAL:48,LONG:72}[row.duration]*3600+300):({SHORT:6,NORMAL:30,LONG:120}[row.duration]*({"tcp-multistream":3,"loaded-rtt":3,"flow-rate":3,"mixed":3,"three-modes":3,"tcp-connections":5,"udp-connections":5,"udp-sweep":6,"stability":10}[row.id]||trafficCatalog?.cases.find(value=>value.id===row.id)?.payload_sizes?.length||1)+20);
const trafficSafeContinue=()=>trafficState?.runtime?.supports_safe_continuation===true&&lab("traffic-continue-after-failure").checked;
const trafficEstimate=()=>trafficCases().reduce((sum,row)=>sum+trafficCaseEstimate(row),0)+(trafficSafeContinue()?Math.max(0,trafficCases().length-1)*20:0);
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
  lab("traffic-start").disabled=busy||trafficState?.runtime?.state==="APPLY_UNKNOWN"||!trafficState?.runtime?.administrator||!labState.observation?.build_id||!trafficCases().length||!lab("traffic-debugger-inactive").checked||trafficEstimate()>300&&!lab("traffic-long-run").checked;
  lab("traffic-stop").disabled=!active||trafficActionActive;
  lab("traffic-recovery-option").hidden=trafficState?.runtime?.supports_safe_continuation!==true;
  lab("traffic-continue-after-failure").disabled=busy||trafficState?.runtime?.supports_safe_continuation!==true;
  const plan=trafficState?.runtime?.plan;
  lab("traffic-runtime-status").textContent=`${t("trafficReady")}: ${trafficState?.runtime?.state||"VALIDATION_REQUIRED"}`;
  lab("traffic-runtime-help").hidden=trafficState?.runtime?.state!=="APPLY_UNKNOWN";
  lab("traffic-runtime-help").textContent=t("trafficApplyUnknown");
  lab("traffic-runtime-plan").hidden=!plan;
  lab("traffic-runtime-plan").textContent=plan?JSON.stringify({ubuntu:plan.ubuntuVersion,bundle:plan.bundleSha256,files:plan.files,tcp:plan.tcpPorts,udp:plan.udpPorts,expires:plan.expiresUtc},null,2):"";
  lab("traffic-estimate").textContent=`${t("trafficEstimate")}: ${number(trafficEstimate()/60,1)} ${t("trafficMinutes")}`;
  const run=trafficState?.execution?.run, progress=trafficState?.execution?.progress;
  lab("traffic-run-status").textContent=[labState.builds.find(build=>build.id===labState.observation?.build_id)?.display_name,run?.state,progress?.stage,progress?.index!==undefined?`${progress.index+1}/${progress.total}`:"",run?.id].filter(Boolean).join(" · ");
  const live=progress?.live_origin,liveBox=lab('traffic-live-progress');
  liveBox.hidden=!active;
  const age=typeof live?.observed_at_unix_seconds==='number'?Date.now()/1000-live.observed_at_unix_seconds:null;
  const fresh=live?.available===true&&Number.isFinite(age)&&age>=-1&&age<=5;
  const operation=['REGISTERING_SESSION','RUNNING_WORKLOAD','COLLECTING_EVIDENCE','WRITING_REPORT','PREPARING_REPORT'].includes(progress?.operation)?t(`trafficFailure_${progress.operation}`):'';
  liveBox.textContent=[operation,`${t('trafficLiveElapsed')}: ${number(progress?.elapsed_seconds,1)}`,
    fresh?`${t('trafficLiveRx')}: ${number(trafficMiB(live.rx_bytes))} · ${t('trafficLiveTx')}: ${number(trafficMiB(live.tx_bytes))} · ${t('trafficLiveActive')}: ${number(live.active,0)} · ${t('trafficLiveTransactions')}: ${number(live.application_transactions,0)}`:t('trafficLiveUnavailable'),t('trafficLiveHelp')].filter(Boolean).join(' · ');
  lab("traffic-error").textContent=trafficError||(trafficState?.runtime?.state==="APPLY_UNKNOWN"?t("trafficApplyUnknown"):trafficState?.runtime?.error)||run?.error||(!trafficState?.runtime?.administrator?t("trafficAdmin"):"");
  const selectedView=lab("traffic-category").value==="selected";
  const cardsKey=JSON.stringify([trafficCatalog,trafficChoice,labLanguage,busy,selectedView]);
  let restoreFocus=null;
  if(cardsKey!==trafficCardsKey&&lab("traffic-cases").contains(document.activeElement)){
    for(const attribute of ["data-traffic-case","data-traffic-duration","data-traffic-load"]){
      const value=document.activeElement.getAttribute(attribute);
      if(value!==null){restoreFocus=`[${attribute}="${CSS.escape(value)}"]`;break;}
    }
  }
  const categoryKey=JSON.stringify([trafficCatalog,labLanguage]);
  if(trafficCatalog&&categoryKey!==trafficCategoryKey){
    trafficCategoryKey=categoryKey;
    const chosen=lab("traffic-category").value;
    lab("traffic-category").innerHTML=`<option value="all">${t("trafficCategoriesAll")}</option><option value="selected">${t("trafficSelectedOnly")}</option>`+trafficGroups.filter(group=>trafficCatalog.cases.some(row=>trafficGroup(row)===group)).map(group=>`<option value="${group}">${t(`trafficGroup_${group}`)} (${trafficCatalog.cases.filter(row=>trafficGroup(row)===group).length})</option>`).join("");
    if([...lab("traffic-category").options].some(option=>option.value===chosen))lab("traffic-category").value=chosen;
  }
  if(trafficCatalog && cardsKey!==trafficCardsKey) {trafficCardsKey=cardsKey;lab("traffic-cases").innerHTML=(selectedView?["selected"]:trafficGroups).map(group=>{
    // Selected view follows the catalog order used by the execution queue.
    const rows=group==="selected"?trafficCatalog.cases:trafficCatalog.cases.filter(row=>trafficGroup(row)===group);
    return rows.length?`<section class="traffic-group" data-traffic-group="${group}"><h4>${t(group==="selected"?"trafficSelectedOnly":`trafficGroup_${group}`)}</h4>`+rows.map(row=>{
    const choice=trafficChoice[row.id]||{selected:false,duration:"SHORT",load:"LOW"};
    return `<div data-traffic-card="${html(row.id)}" class="lab-test-card${choice.selected?" is-selected":""}"><label class="lab-test-toggle"><input type="checkbox" data-traffic-case="${row.id}" ${choice.selected?"checked":""} ${busy?"disabled":""}><span>${html(row[labLanguage])}</span></label><div class="lab-test-settings"><label>${t("duration")}<select data-traffic-duration="${row.id}" ${busy?"disabled":""}>${["SHORT","NORMAL","LONG"].map(value=>`<option value="${value}" ${value===choice.duration?"selected":""}>${row.id==="soak"?{SHORT:24,NORMAL:48,LONG:72}[value]+" h":t(value)}</option>`).join("")}</select></label><label>${t("load")}<select data-traffic-load="${row.id}" ${busy?"disabled":""}>${["LOW","HIGH"].map(value=>`<option value="${value}" ${value===choice.load?"selected":""}>${t(value)}</option>`).join("")}</select></label></div><p>${t("trafficEstimate")}: ≈ ${number(trafficCaseEstimate({id:row.id,duration:choice.duration})/60,1)} ${t("trafficMinutes")}</p></div>`;
  }).join("")+"</section>":"";}).join("");}
  filterTrafficCards();
  if(restoreFocus){
    const control=lab("traffic-cases").querySelector(restoreFocus);
    if(control&&!control.disabled&&!control.closest("[hidden]"))control.focus({preventScroll:true});
  }
  renderTrafficHistory();
  renderTrafficComparison();
  updateTrafficExportButtons();
  lab('traffic-history-warning').hidden=!trafficUnreadableHistory&&!trafficSnapshotUnavailable;
  lab('traffic-history-warning').textContent=trafficSnapshotUnavailable?t('trafficHistoryUnavailable'):t('trafficHistoryUnreadable');
  if (typeof renderSavedSuites === "function") renderSavedSuites(busy);
}
function trafficControlsMarkup(row){
  const controls=row.controls||[];
  if(!controls.length)return '';
  return `<p>${t('trafficControls')}: ${controls.map(control=>`${html(control.mode)} · ${control.complete===true&&control.route_verified===true?'PASS':control.complete===false?'FAIL':'UNVERIFIED'}`).join(' · ')}</p>`;
}
function trafficResourceCoverage(resources){
  const roles=['product_cli','worker','windows_system','worker_system','origin_system','origin_and_proxy'];
  const integer=value=>Number.isSafeInteger(value)&&value>=0?value:null;
  return roles.filter(role=>resources?.[role]).map(role=>{
    const row=resources[role],total=integer(row.samples),unavailable=integer(row.unavailable_samples);
    const memoryKey=['private_bytes','working_set_bytes','physical_used_bytes'].find(key=>row.counters?.[key]);
    const memory=row.counters?.[memoryKey];
    return {role,samples:total,available_samples:total!==null&&unavailable!==null&&unavailable<=total?total-unavailable:null,
      cpu_samples:integer(row.counters?.cpu_percent_of_pc?.count),memory_scope:row.memory_scope??null,
      memory_counter:memoryKey??null,memory_delta_mib:trafficMiB(trafficCounterChange(memory))};
  });
}
function trafficResourceCoverageMarkup(measurement){
  const rows=trafficResourceCoverage(measurement.resources);
  if(!rows.length)return '';
  return `<details><summary>${t('trafficCoverage')}</summary><p>${t('trafficCoverageHelp')}</p><p>${t('trafficMemoryDeltaHelp')}</p><div class="lab-table-scroll"><table><thead><tr>${['trafficCoverageRole','trafficCoverageAvailable','trafficCoverageCpu','trafficMemoryDelta','trafficCoverageMemory'].map(key=>`<th>${t(key)}</th>`).join('')}</tr></thead><tbody>${rows.map(row=>`<tr><td>${t(`trafficResource_${row.role}`)}</td><td>${number(row.available_samples,0)} / ${number(row.samples,0)}</td><td>${number(row.cpu_samples,0)}</td><td>${number(row.memory_delta_mib)}</td><td>${html([row.memory_counter,row.memory_scope].filter(Boolean).join(' · ')||'—')}</td></tr>`).join('')}</tbody></table></div></details>`;
}
function trafficMeasurementEvidence(measurement){
  const state=['NOT_STARTED','PARTIAL','COMPLETED'].includes(measurement.measurement_state)?measurement.measurement_state:'UNKNOWN';
  const context=measurement.failure_context;
  const operation=['REGISTERING_SESSION','RUNNING_WORKLOAD','COLLECTING_EVIDENCE','WRITING_REPORT','PREPARING_REPORT'].includes(context?.operation)?context.operation:'UNKNOWN';
  const lossState=['MEASURED','NOT_MEASURED','NOT_APPLICABLE'].includes(measurement.loss_evidence_state)?measurement.loss_evidence_state:'UNKNOWN';
  const loss=lossState==='MEASURED'&&typeof measurement.loss_threshold_met==='boolean'?`${measurement.loss_threshold_met?'PASS':'FAIL'} (${number(measurement.loss_threshold_fraction*100,1)}%)`:t(`trafficLoss_${lossState==='MEASURED'?'UNKNOWN':lossState}`);
  const recorded=measurement.recorded_stage_count??measurement.stages?.length;
  const readiness=measurement.lifecycle?.ready===true?'PASS':measurement.lifecycle?.ready===false?'FAIL':'UNVERIFIED';
  const cleanup=measurement.lifecycle?.cleanup_verified===true&&measurement.lifecycle?.forced_stop===false?'PASS':'UNVERIFIED';
  return `<p>${t('trafficMeasurementState')}: ${t(`trafficMeasurement_${state}`)} · ${t('trafficStageCounts')}: ${number(measurement.workload_started_stage_count,0)} / ${number(recorded,0)} / ${number(measurement.planned_stage_count,0)}</p>${context?`<p>${t('trafficFailurePhase')}: ${t(`trafficFailure_${operation}`)}${context.stage?` · ${html(context.stage)}`:''}</p>`:''}<p>${t('trafficLossEvidence')}: ${loss}</p>${measurement.mode==='OFF'?'':`<p>${t('trafficCliReady')}: ${readiness} · ${t('trafficCliCleanup')}: ${cleanup}</p>`}`;
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
    return `<article class="lab-test-card"><h4>${html(name||"")} · ${html(attempt.state)} · ${html(attempt.id)}</h4><p>${html(attempt.error||"")}</p>${attempt.continue_after_failure?`<p>${t("trafficQueuePolicy")}: ${t("trafficContinue")}</p>${(attempt.recovery_checks||[]).map(check=>`<p>${t("trafficRecovery")} · ${html(trafficName(check.case_id))}: ${check.safe_to_continue?t("trafficRecoveryOk"):t("trafficRecoveryBlocked")} · ${html(check.reason)}</p>`).join("")}`:""}${rows.map(row=>`<details><summary>${html(trafficName(row.case_id))} · ${html(row.duration)} / ${html(row.load)} · ${row.complete?"PASS":row.skipped?"SKIPPED":row.cancelled?"CANCELLED":"FAIL"}</summary><p>${t("trafficCleanup")}: ${row.cleanup_verified?"PASS":"UNVERIFIED"} · ${html((row.errors||[]).join(" · "))}</p>${trafficControlsMarkup(row)}${(row.measurements||[]).map(measurement=>{
      const cpu=measurement.resources?.product_cli?.counters?.cpu_percent_of_pc?.mean,ram=measurement.resources?.product_cli?.counters?.private_bytes?.max;
      return `<h5>${html(measurement.mode)} · ${measurement.route_verified?t("trafficRouteOk"):t("trafficRouteBad")}</h5>${trafficMeasurementEvidence(measurement)}${trafficResourceCoverageMarkup(measurement)}${measurement.overall?.connection_latency?.count>0?`<p>${t("trafficConnectP50")}: ${number(measurement.overall.connection_latency.p50_ms)} · ${t("trafficConnectP95")}: ${number(measurement.overall.connection_latency.p95_ms)} · ${t("trafficConnectP99")}: ${number(measurement.overall.connection_latency.p99_ms)} · ${t("trafficConnectSamples")}: ${number(measurement.overall.connection_latency.count,0)}</p><p>${html(t("trafficConnectHelp"))}</p>`:""}<p>${t("trafficSkippedStages")}: ${measurement.skipped_stage_count||0} · ${html((measurement.schedule_errors||[]).join(" · "))}</p><p>${t("trafficCpu")}: ${number(cpu)} · ${t("trafficRam")}: ${number(typeof ram==="number"?ram/1048576:null)}</p><p>${t("trafficSystemCpu")}: ${number(measurement.resources?.windows_system?.counters?.cpu_percent_of_pc?.mean)} · ${t("trafficOriginCpu")}: ${number(measurement.resources?.origin_system?.counters?.cpu_percent_of_pc?.mean)}</p><div class="lab-table-scroll"><table><thead><tr>${["trafficPhase","trafficSent","trafficReceived","trafficP99","trafficUdpP99","trafficLoss","trafficConnections","trafficPeak","trafficErrors"].map(key=>`<th>${t(key)}</th>`).join("")}</tr></thead><tbody>${measurement.stages.map(stage=>`<tr><td>${html(stage.phase)} · ${stage.complete?"PASS":"FAIL"}</td><td>${number(trafficMiB(stage.tcp_tx_bytes_per_second))}</td><td>${number(trafficMiB(stage.tcp_rx_bytes_per_second))}</td><td>${number(stage.probe_p99_ms)}</td><td>${number(stage.udp_latency?.p99_ms)}</td><td>${number(typeof stage.udp_loss_fraction==="number"?stage.udp_loss_fraction*100:null)}</td><td>${stage.tcp_completed}/${stage.tcp_offered}</td><td>${number(stage.tcp_active_peak)}</td><td>${html((stage.errors||[]).join(" · "))}</td></tr>`).join("")}</tbody></table></div>${measurement.stages.filter(stage=>stage.application).map(stage=>`<details><summary>${t("trafficApplicationEvidence")} · ${html(stage.application)}</summary><p>${t("trafficTransactions")}: ${stage.application_transactions||0} · ${t("trafficPayloadBytes")}: ${number(stage.application_payload_bytes,0)}</p><pre>${html(JSON.stringify({tls:stage.application_tls_sessions||[],protocol:stage.application_protocol_sessions||[],socket_errors:stage.application_socket_errors||[]},null,2))}</pre></details>`).join("")}`;
    }).join("")||`<p>${t("trafficEmpty")}</p>`}</details>`).join("")}</article>`;
  }).join("")||`<p>${t("trafficNone")}</p>`;
}
const trafficMetrics=["trafficSent","trafficReceived","trafficP99","trafficUdpP99","trafficLoss","trafficCpu","trafficRam","trafficSystemCpu","trafficSystemRam","trafficOriginCpu","trafficOriginRam","trafficPeak","trafficCliResident","trafficWorkerCpu","trafficWorkerRam","trafficOriginProcessCpu","trafficOriginProcessRam","trafficCliHandles","trafficCliThreads","trafficTransactions","trafficCliRamDelta","trafficCliResidentDelta","trafficOriginProcessRamDelta","trafficConnectP50","trafficConnectP95","trafficConnectP99","trafficConnectSamples"];
const trafficDefaultMetrics=new Set(["trafficSent","trafficReceived","trafficP99","trafficUdpP99","trafficLoss","trafficCpu","trafficCliResident","trafficSystemCpu","trafficOriginCpu"]);
const trafficMetricSelected=key=>trafficCompareChoice.metrics[key]??trafficDefaultMetrics.has(key);
const trafficMiB=value=>typeof value==='number'&&Number.isFinite(value)?value/1048576:null;
function trafficCounterChange(counter){
  return Number.isSafeInteger(counter?.count)&&counter.count>=2&&typeof counter.first==='number'&&Number.isFinite(counter.first)&&
    typeof counter.last==='number'&&Number.isFinite(counter.last)&&counter.first>=0&&counter.last>=0?counter.last-counter.first:null;
}
function trafficMetric(row,key){
  if(!row.complete)return null;
  const measured=(row.result?.measurements||[]).find(value=>value.mode==="SOCKS5"&&value.complete&&value.route_verified);
  if(!measured)return null;
  const overall=measured.overall||{},resources=measured.resources||{};
  const counter=(role,name,stat)=>resources[role]?.counters?.[name]?.[stat];
  const values={trafficTransactions:overall.application_transactions,trafficSent:trafficMiB(overall.tcp_tx_bytes_per_second),trafficReceived:trafficMiB(overall.tcp_rx_bytes_per_second),
    trafficP99:overall.probe_latency?.p99_ms,trafficUdpP99:overall.udp_latency?.p99_ms,
    trafficConnectP50:overall.connection_latency?.p50_ms,trafficConnectP95:overall.connection_latency?.p95_ms,
    trafficConnectP99:overall.connection_latency?.p99_ms,trafficConnectSamples:overall.connection_latency?.count,
    trafficLoss:typeof overall.udp_loss_fraction==="number"?overall.udp_loss_fraction*100:null,
    trafficCpu:counter("product_cli","cpu_percent_of_pc","mean"),trafficRam:trafficMiB(counter("product_cli","private_bytes","max")),
    trafficSystemCpu:counter("windows_system","cpu_percent_of_pc","mean"),trafficSystemRam:trafficMiB(counter("windows_system","physical_used_bytes","max")),
    trafficOriginCpu:counter("origin_system","cpu_percent_of_pc","mean"),trafficOriginRam:trafficMiB(counter("origin_system","physical_used_bytes","max")),
    trafficCliResident:trafficMiB(counter("product_cli","working_set_bytes","max")),
    trafficWorkerCpu:counter("worker","cpu_percent_of_pc","mean"),trafficWorkerRam:trafficMiB(counter("worker","private_bytes","max")),
    trafficOriginProcessCpu:counter("origin_and_proxy","cpu_percent_of_pc","mean"),trafficOriginProcessRam:trafficMiB(counter("origin_and_proxy","working_set_bytes","max")),
    trafficCliRamDelta:trafficMiB(trafficCounterChange(resources.product_cli?.counters?.private_bytes)),
    trafficCliResidentDelta:trafficMiB(trafficCounterChange(resources.product_cli?.counters?.working_set_bytes)),
    trafficOriginProcessRamDelta:trafficMiB(trafficCounterChange(resources.origin_and_proxy?.counters?.working_set_bytes)),
    trafficCliHandles:counter("product_cli","handles","max"),trafficCliThreads:counter("product_cli","threads","max"),
    trafficPeak:measured.tcp_active_peak??((measured.stages||[]).some(stage=>typeof stage.tcp_active_peak==="number")?Math.max(...(measured.stages||[]).map(stage=>stage.tcp_active_peak||0)):null)};
  return Number.isFinite(values[key])?values[key]:null;
}
function trafficComparisonRows(){
  const selected=lab('traffic-comparison-filter').value;
  return trafficComparison.filter(row=>`${row.case_id}|${row.duration}|${row.load}|${row.condition_id}`===selected&&trafficCompareChoice.builds[row.build_id]!==false);
}
function trafficHistoryRows(){
  const selected=lab('traffic-filter').value;
  const matches=row=>selected==='all'||`${row.Id||row.id||row.case_id}|${row.Duration||row.duration}|${row.Load||row.load}`===selected;
  return trafficHistory.filter(attempt=>selected==='all'||(attempt.cases||[]).some(matches)).map(attempt=>({...attempt,
    cases:(attempt.cases||[]).filter(matches),results:(attempt.results||[]).filter(matches),
    recovery_checks:(attempt.recovery_checks||[]).filter(check=>selected==='all'||check.case_id===selected.split('|')[0])}));
}
function updateTrafficExportButtons(){
  const blocked=trafficSnapshotUnavailable||trafficLoading;
  lab('traffic-export-comparison').disabled=blocked||trafficComparisonBlocked||!trafficComparisonRows().length;
  lab('traffic-export-history').disabled=blocked||!trafficHistoryRows().length;
}
function trafficCsvCell(value){
  if(value===null||value===undefined)return '""';
  let text=String(value);
  if(typeof value!=='number'&&/^[\s\u0000-\u001f]*[=+\-@]/.test(text))text="'"+text;
  return '"'+text.replaceAll('"','""')+'"';
}
function exportTraffic(kind){
  const status=lab('traffic-export-status');
  if(trafficSnapshotUnavailable||trafficLoading||kind==='comparison'&&trafficComparisonBlocked){status.textContent=t('trafficExportUnavailable');return;}
  const exportedAt=new Date().toISOString();
  let content,type,extension;
  if(kind==='comparison'){
    const rows=trafficComparisonRows(),metrics=trafficMetrics.filter(trafficMetricSelected);
    if(!rows.length){status.textContent=t('trafficExportUnavailable');return;}
    const header=['snapshot_loaded_at_utc','exported_at_utc','build_id','build_name','attempt_id','case_id','duration','load','condition_id','status','errors','conditions_json','resource_observation_summary_json',...metrics.map(metric=>`${metric} (${t(metric)})`)];
    const records=rows.map(row=>[trafficComparisonLoadedAt,exportedAt,row.build_id,
      labState.builds.find(build=>build.id===row.build_id)?.display_name||row.build_id,row.attempt_id,row.case_id,
      row.duration,row.load,row.condition_id,row.complete?'PASS':row.state||'UNVERIFIED',
      (row.result?.errors||[row.error]).filter(Boolean).join(' | '),JSON.stringify(row.conditions??null),JSON.stringify(trafficResourceCoverage((row.result?.measurements||[]).find(value=>value.mode==='SOCKS5')?.resources)),
      ...metrics.map(metric=>trafficMetric(row,metric))]);
    content='\ufeff'+[header,...records].map(record=>record.map(trafficCsvCell).join(',')).join('\r\n')+'\r\n';
    type='text/csv;charset=utf-8';extension='csv';
  }else{
    const items=trafficHistoryRows();
    if(!items.length){status.textContent=t('trafficExportUnavailable');return;}
    content=JSON.stringify({schema_version:1,scope:'loaded-history-pages-filtered-by-case',
      snapshot_loaded_at_utc:trafficHistoryLoadedAt,exported_at_utc:exportedAt,
      filter:lab('traffic-filter').value,has_more_pages:trafficHasMore,next_skip:trafficNextSkip,
      unreadable_reports_observed:trafficUnreadableHistory,
      attempt_state_scope:'whole-queue; results and choices use the selected case filter',history_pagination_scope:'loaded-pages-across-requests; not an atomic snapshot',items},null,2)+'\n';
    type='application/json;charset=utf-8';extension='json';
  }
  const blob=new Blob([content],{type});
  if(blob.size>8*1024*1024){status.textContent=t('trafficExportTooLarge');return;}
  const url=URL.createObjectURL(blob),anchor=document.createElement('a');
  anchor.href=url;anchor.download=`testlab-traffic-${kind}-${exportedAt.replace(/[:.]/g,'-')}.${extension}`;
  document.body.append(anchor);anchor.click();anchor.remove();
  setTimeout(()=>URL.revokeObjectURL(url),10000);
  status.textContent=t('trafficExportStarted');
}
lab('traffic-export-comparison').addEventListener('click',()=>exportTraffic('comparison'));
lab('traffic-export-history').addEventListener('click',()=>exportTraffic('history'));
function renderTrafficComparison(){
  if(trafficSnapshotUnavailable||trafficComparisonBlocked){
    trafficComparisonKey='';
    lab('traffic-comparison').innerHTML=`<p class="lab-warning">${t(trafficSnapshotUnavailable?'trafficHistoryUnavailable':'trafficHistoryUnreadable')}</p>`;
    lab('traffic-comparison-builds').innerHTML='';
    lab('traffic-comparison-metrics').innerHTML='';
    return;
  }
  const select=lab("traffic-comparison-filter"),previous=select.value;
  const key=JSON.stringify([trafficComparison,labLanguage,previous,trafficCompareChoice,labState.builds]);
  if(key===trafficComparisonKey)return;trafficComparisonKey=key;
  const groups=new Map();for(const row of trafficComparison)groups.set(`${row.case_id}|${row.duration}|${row.load}|${row.condition_id}`,row);
  select.innerHTML=[...groups].map(([id,row])=>`<option value="${html(id)}">${html(`${trafficName(row.case_id)} · ${row.duration}/${row.load} · ${row.condition_id.slice(0,12)}`)}</option>`).join("");
  if(groups.has(previous))select.value=previous;
  const rows=trafficComparison.filter(row=>`${row.case_id}|${row.duration}|${row.load}|${row.condition_id}`===select.value);
  const name=row=>labState.builds.find(build=>build.id===row.build_id)?.display_name||row.build_id;
  lab("traffic-comparison-builds").innerHTML=rows.map(row=>`<label class="lab-test-toggle"><input type="checkbox" data-traffic-build="${html(row.build_id)}" ${trafficCompareChoice.builds[row.build_id]!==false?"checked":""}>${html(name(row))}</label>`).join("");
  lab("traffic-comparison-metrics").innerHTML=trafficMetrics.map(metric=>`<label class="lab-test-toggle"><input type="checkbox" data-traffic-metric="${metric}" ${trafficMetricSelected(metric)?"checked":""}>${html(t(metric))}</label>`).join("");
  const metrics=trafficMetrics.filter(metric=>trafficMetricSelected(metric));
  lab("traffic-comparison").innerHTML=rows.length?`<p>${html(t("trafficAllStages"))}</p>${metrics.some(metric=>metric.startsWith("trafficConnect"))?`<p>${html(t("trafficConnectHelp"))}</p>`:""}<div class="lab-table-scroll"><table><thead><tr><th>${t("connection")}</th><th>Status</th>${metrics.map(metric=>`<th>${html(t(metric))}</th>`).join("")}</tr></thead><tbody>${rows.filter(row=>trafficCompareChoice.builds[row.build_id]!==false).map(row=>`<tr><td>${html(name(row))}<br><small>${html(row.attempt_id)}</small></td><td>${row.complete?"PASS":html(row.state)}<br>${html((row.result?.errors||[row.error]).filter(Boolean).join(" · "))}</td>${metrics.map(metric=>`<td>${number(trafficMetric(row,metric))}</td>`).join("")}</tr>`).join("")}</tbody></table></div><details><summary>${t("trafficConditions")}</summary><pre>${html(JSON.stringify(rows[0].conditions,null,2))}</pre></details>`:`<p>${t("trafficNone")}</p>`;
}
for(const id of ["traffic-comparison-builds","traffic-comparison-metrics"])lab(id).addEventListener("change",event=>{
  const build=event.target.dataset.trafficBuild,metric=event.target.dataset.trafficMetric;
  if(build)trafficCompareChoice.builds[build]=event.target.checked;if(metric)trafficCompareChoice.metrics[metric]=event.target.checked;
  localStorage.setItem("testlab-traffic-comparison",JSON.stringify(trafficCompareChoice));renderTrafficComparison();updateTrafficExportButtons();
});
lab("traffic-comparison-filter").addEventListener("change",()=>{renderTrafficComparison();updateTrafficExportButtons();});
lab("traffic-history-more").addEventListener("click",async()=>{
  lab("traffic-history-more").disabled=true;
  try{
    const response=await fetch(`/api/v1/lab/traffic/history?skip=${trafficNextSkip}`,{cache:"no-store"});if(!response.ok)throw new Error("TRAFFIC_HISTORY_UNAVAILABLE");
    const data=await response.json(),loaded=new Map(trafficHistory.map(row=>[row.id,row]));for(const row of data.items)loaded.set(row.id,row);
    trafficHistory=[...loaded.values()].sort((a,b)=>b.id.localeCompare(a.id));trafficNextSkip=data.next_skip;trafficHasMore=data.has_more;trafficUnreadableHistory=trafficUnreadableHistory||data.unreadable_count>0;if(data.unreadable_count>0){trafficComparisonBlocked=true;trafficComparison=[];}trafficHistoryLoadedAt=new Date().toISOString();renderTrafficHistory();updateTrafficExportButtons();
    lab("traffic-history-more").hidden=!trafficHasMore;
  }catch(error){trafficError=error.message;trafficSnapshotUnavailable=true;trafficComparison=[];trafficComparisonBlocked=true;}finally{lab("traffic-history-more").disabled=false;renderTraffic();}
});
async function loadTraffic(){
  if(trafficLoading)return;trafficLoading=true;
  try{
    const responses=await Promise.all([fetch("/api/v1/lab/traffic/catalog",{cache:"no-store"}),fetch("/api/v1/lab/traffic/state",{cache:"no-store"}),fetch("/api/v1/lab/traffic/history",{cache:"no-store"}),fetch("/api/v1/lab/traffic/comparison",{cache:"no-store"})]);
    if(responses.some(response=>!response.ok)) throw new Error("TRAFFIC_STATUS_UNAVAILABLE");
    const data=await Promise.all(responses.map(response=>response.json())); trafficCatalog=data[0]; trafficState=data[1];
    const loaded=new Map(trafficHistory.map(row=>[row.id,row])); for(const row of data[2].items)loaded.set(row.id,row);
    trafficHistory=[...loaded.values()].sort((a,b)=>b.id.localeCompare(a.id));trafficComparisonBlocked=data[3].available===false;trafficUnreadableHistory=data[2].unreadable_count>0||data[3].unreadable_count>0;trafficComparison=trafficComparisonBlocked?[]:data[3].items;trafficComparisonLoadedAt=trafficHistoryLoadedAt=new Date().toISOString();trafficSnapshotUnavailable=false;
    if(!trafficNextSkip){trafficNextSkip=data[2].next_skip;trafficHasMore=data[2].has_more;}
    lab("traffic-history-more").hidden=!trafficHasMore;
  }catch(error){trafficError=error.message;trafficSnapshotUnavailable=true;trafficComparison=[];trafficComparisonBlocked=true;}finally{trafficLoading=false;}
  renderTraffic();
}
async function trafficAction(action){
  if(trafficActionActive)return;
  trafficActionActive=true;trafficError="";renderTraffic();
  try{
    const body=action==="apply"?{planId:trafficState.runtime.plan.planId}:action==="start"?{buildId:labState.observation.build_id,cases:trafficCases(),debuggerInactive:lab("traffic-debugger-inactive").checked,allowLongRun:lab("traffic-long-run").checked,continueAfterFailure:trafficSafeContinue()}:{};
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
lab("traffic-continue-after-failure").addEventListener("change",renderTraffic);
for(const id of ["traffic-debugger-inactive","traffic-long-run","lab-mode"])lab(id).addEventListener("change",renderTraffic);
lab("traffic-filter").addEventListener("change",()=>{renderTrafficHistory();updateTrafficExportButtons();});
lab("traffic-search").addEventListener("input",filterTrafficCards);
lab("traffic-category").addEventListener("change",renderTraffic);
const renderLabBeforeTraffic=renderLab;
renderLab=function(){renderLabBeforeTraffic();renderTraffic();};
loadTraffic();setInterval(()=>{if(!trafficActionActive)loadTraffic();},3000);
