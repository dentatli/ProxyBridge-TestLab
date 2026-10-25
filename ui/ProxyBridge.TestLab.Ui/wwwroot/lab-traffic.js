"use strict";
Object.assign(labText.ru,{trafficCombined:'Совмещённые проверки — без повторного выполнения'});
Object.assign(labText.en,{trafficCombined:'Combined checks — without duplicate execution'});

Object.assign(labText.ru, {
  trafficHeading:"Трафик, скорость, нагрузка и стабильность", trafficScope:"Ubuntu 22.04. Транспортные и прикладные протоколы: HTTP, QUIC, DNS, SSH, почта и обмен сообщениями. Проверка данных и маршрута, потери UDP, CPU/RAM всей ОС и CPU/RAM/handles/threads отдельных процессов. Число соединений и скорость не доказывают максимальную ёмкость или ресурсы драйвера.",
  trafficPrepare:"Проверить / подготовить runtime", trafficApply:"Установить по этому плану", trafficStart:"Запустить выбранные проверки", trafficStop:"Остановить и очистить",
  trafficAdmin:"Для реальных проверок запустите scripts/Start-TestLabUi.ps1 -Administrator. При включённом UAC потребуется подтверждение.",
  trafficRunHelp:"Используется выбранная сборка. Перед каждым тестом проверяются файлы, получатель, OFF и UNRULED. SOCKS5 требует подписанных свидетельств. Неудачная очистка прекращает очередь.",
  trafficResults:"Проверки трафика: история и измерения", trafficResultsHelp:"Ошибки и отмены сохраняются отдельно. CPU процесса нормирован на все логические CPU; RAM процесса не является памятью драйвера. Разные параметры и получатели сравнивайте отдельно.", trafficConditions:"Тест и условия", trafficAll:"Все попытки", trafficNone:"Попыток пока нет", trafficReady:"Состояние runtime", trafficEstimate:"Оценка с подготовкой", trafficPhase:"Этап", trafficSent:"Отправка, MiB/s", trafficReceived:"Получение, MiB/s", trafficP99:"RTT p99, мс", trafficLoss:"Потери UDP, %", trafficConnections:"TCP завершено / предложено", trafficCpu:"CLI CPU, % ПК", trafficRam:"CLI private commit, MiB", trafficEmpty:"Измерений нет",trafficMinutes:"мин",trafficRouteOk:"Маршрут подтверждён",trafficRouteBad:"Маршрут не подтверждён",trafficApplicationEvidence:"Прикладной обмен",trafficTransactions:"Проверенных обменов",trafficErrors:"Ошибки",trafficSkippedStages:"Пропущено этапов"
});
Object.assign(labText.en, {
  trafficHeading:"Traffic, speed, load and stability", trafficScope:"Ubuntu 22.04. Transport and application protocols: HTTP, QUIC, DNS, SSH, mail and messaging. Data and route validation, UDP loss, whole-OS CPU/RAM and CPU/RAM/handles/threads of identified processes. Connection count and speed do not establish absolute capacity or driver resource use.",
  trafficPrepare:"Check / prepare runtime", trafficApply:"Install this exact plan", trafficStart:"Start selected checks", trafficStop:"Stop and clean up",
  trafficAdmin:"For real checks run scripts/Start-TestLabUi.ps1 -Administrator. With UAC enabled, Windows will request confirmation.",
  trafficRunHelp:"Uses the selected build. Files, origin, OFF and UNRULED are checked before each case. SOCKS5 requires signed evidence. Failed cleanup stops the queue.",
  trafficResults:"Traffic checks: history and measurements", trafficResultsHelp:"Failures and cancellation are saved separately. Process CPU is normalized to all logical CPUs; process RAM is not driver memory. Compare different parameters and origins separately.", trafficConditions:"Case and conditions", trafficAll:"All attempts", trafficNone:"No attempts yet", trafficReady:"Runtime state", trafficEstimate:"Estimate including preparation", trafficPhase:"Stage", trafficSent:"Upload, MiB/s", trafficReceived:"Download, MiB/s", trafficP99:"RTT p99, ms", trafficLoss:"UDP loss, %", trafficConnections:"TCP completed / offered", trafficCpu:"CLI CPU, % of PC", trafficRam:"CLI private commit, MiB", trafficEmpty:"No measurements",trafficMinutes:"min",trafficRouteOk:"Route verified",trafficRouteBad:"Route unverified",trafficApplicationEvidence:"Application exchange",trafficTransactions:"Verified transactions",trafficErrors:"Errors",trafficSkippedStages:"Skipped stages"
});
labText.ru.remoteTestGate='Для сетевых измерений используйте каталог ниже. Перед каждым тестом контроллер проверяет обмен и маршрут; неподтверждённый маршрут сохраняется как ошибка.';
labText.en.remoteTestGate='Use the traffic catalog below. The controller validates exchange and route before each case; an unverified route is saved as a failure.';
labText.ru.trafficApplyUnknown='Результат настройки не подтверждён. Нажмите «Проверить / подготовить runtime» для повторной проверки того же сервера и создания нового плана.';
labText.en.trafficApplyUnknown='The setup result is unconfirmed. Check / prepare runtime again to inspect the same server and create a new plan.';
Object.assign(labText.ru,{trafficControls:'Контрольные режимы',trafficMeasurementState:'Нагрузка',trafficMeasurement_NOT_STARTED:'Не началась',trafficMeasurement_PARTIAL:'Неполный прогон',trafficMeasurement_COMPLETED:'Завершена',trafficMeasurement_UNKNOWN:'Нет сведений о начале нагрузки',trafficStageCounts:'Этапы: начаты / записаны / запланированы',trafficFailurePhase:'Остановка на этапе',trafficFailure_REGISTERING_SESSION:'Подготовка сеанса с получателем',trafficFailure_RUNNING_WORKLOAD:'Выполнение нагрузки',trafficFailure_COLLECTING_EVIDENCE:'Получение свидетельств и ожидание освобождения соединений',trafficFailure_WRITING_REPORT:'Сохранение отчёта',trafficFailure_PREPARING_REPORT:'Подготовка отчёта',trafficFailure_UNKNOWN:'Неизвестно',trafficLossEvidence:'Порог потерь ответов',trafficLoss_NOT_MEASURED:'Не измерено',trafficLoss_NOT_APPLICABLE:'Не применяется',trafficLoss_UNKNOWN:'Не подтверждено',trafficCliReady:'CLI вышел в READY',trafficCliCleanup:'Штатное завершение CLI'});
Object.assign(labText.en,{trafficControls:'Control modes',trafficMeasurementState:'Workload',trafficMeasurement_NOT_STARTED:'Not started',trafficMeasurement_PARTIAL:'Partial run',trafficMeasurement_COMPLETED:'Completed',trafficMeasurement_UNKNOWN:'Workload start unknown',trafficStageCounts:'Stages: started / recorded / planned',trafficFailurePhase:'Stopped during',trafficFailure_REGISTERING_SESSION:'Preparing the origin session',trafficFailure_RUNNING_WORKLOAD:'Running the workload',trafficFailure_COLLECTING_EVIDENCE:'Collecting evidence and waiting for connections to drain',trafficFailure_WRITING_REPORT:'Saving the report',trafficFailure_PREPARING_REPORT:'Preparing the report',trafficFailure_UNKNOWN:'Unknown',trafficLossEvidence:'Reply loss threshold',trafficLoss_NOT_MEASURED:'Not measured',trafficLoss_NOT_APPLICABLE:'Not applicable',trafficLoss_UNKNOWN:'Unconfirmed',trafficCliReady:'CLI reached READY',trafficCliCleanup:'Graceful CLI shutdown'});
Object.assign(labText.ru,{trafficContinue:"Продолжать после ошибки при подтверждённом восстановлении",trafficContinueHelp:"После ошибки теста контроллер подтверждает выход процесса CLI (в том числе после аварии), выключенный драйвер, подписанную идентичность и отсутствие соединений получателя. Отмена, смена файлов, потеря связи или непроверенная очистка останавливают очередь. Неудачные тесты сохраняют FAIL.",trafficQueuePolicy:"Продолжение после ошибки",trafficRecovery:"Проверка восстановления",trafficRecoveryOk:"Продолжение разрешено",trafficRecoveryBlocked:"Продолжение заблокировано"});
Object.assign(labText.en,{trafficContinue:"Continue after a failed case when recovery is verified",trafficContinueHelp:"After a case fails, the controller verifies CLI process exit (including after a crash), the driver being off, signed origin identity and no remaining connections. Cancellation, changed files, disconnection or unverified cleanup stop the queue. Failed cases retain FAIL.",trafficQueuePolicy:"Continue after failure",trafficRecovery:"Recovery check",trafficRecoveryOk:"Continuation allowed",trafficRecoveryBlocked:"Continuation blocked"});
let trafficCatalog=null, trafficState=null, trafficHistory=[], trafficActionActive=false, trafficError="", trafficChoice={};
let trafficCardsKey="", trafficHistoryKey="", trafficLoading=false;
Object.assign(labText.ru,{trafficShown:"Показано",trafficHiddenSelected:"Скрыто фильтром",trafficNoMatches:"Подходящих проверок нет. Измените поиск или группу.",trafficSearch:"Найти протокол или этап",trafficCategory:"Проверки",trafficSearchHelp:"Выберите протокол и полноту проверки. Этапы выполняются последовательно; точный состав раскрывается в карточке. Фильтры сохраняют выбор.",trafficCategoriesAll:"Все проверки",trafficSelectedOnly:"Выбранные проверки",trafficSelected:"Выбрано проверок",trafficDepth:"Полнота",trafficDepth_BASIC:"Базовая",trafficDepth_STANDARD:"Стандартная",trafficDepth_FULL:"Полная",trafficDepth_CUSTOM:"Свой набор",trafficMixed:"Разные параметры",trafficFamilyStages:"Этапы и точный выбор",trafficStages:"Этапов",trafficFamilyHelp:"Общий результат относится только к выбранным этапам. Скорость, задержка и ошибки сохраняются отдельно для каждого этапа.",trafficSelectionReview:"Будут выполнены",trafficFamilyReport:"Итог выбранных этапов",trafficFamilyIncomplete:"Есть пропущенные, незавершённые или неподтверждённые этапы",trafficStageMissing:"Этап не записан",trafficPassed:"Прошло",trafficNoSelection:"Выберите хотя бы одну проверку."});
Object.assign(labText.en,{trafficShown:"Shown",trafficHiddenSelected:"Hidden by filters",trafficNoMatches:"No matching checks. Change the search or group.",trafficSearch:"Find a protocol or stage",trafficCategory:"Checks",trafficSearchHelp:"Choose a protocol and coverage. Stages run sequentially; expand a card for the exact selection. Filters preserve your choices.",trafficCategoriesAll:"All checks",trafficSelectedOnly:"Selected checks",trafficSelected:"Selected checks",trafficDepth:"Coverage",trafficDepth_BASIC:"Basic",trafficDepth_STANDARD:"Standard",trafficDepth_FULL:"Full",trafficDepth_CUSTOM:"Custom",trafficMixed:"Mixed settings",trafficFamilyStages:"Stages and exact selection",trafficStages:"Stages",trafficFamilyHelp:"The overall result covers only the selected stages. Rate, latency and errors are retained separately for each stage.",trafficSelectionReview:"Will run",trafficFamilyReport:"Selected stage outcome",trafficFamilyIncomplete:"Some stages were skipped, unfinished or unverified",trafficStageMissing:"Stage not recorded",trafficPassed:"Passed",trafficNoSelection:"Select at least one check."});
let trafficFamilyPreferences={};
try{trafficFamilyPreferences=JSON.parse(localStorage.getItem("testlab-traffic-families")||"{}");}catch{}
if(!trafficFamilyPreferences||typeof trafficFamilyPreferences!=="object"||Array.isArray(trafficFamilyPreferences))trafficFamilyPreferences={};
const trafficFamilyName=family=>family[labLanguage]||family.id;
const trafficFamilyChoice=family=>trafficFamilySelection(family,trafficChoice,trafficFamilyPreferences[family.id]||{});
let trafficComparison=[],trafficComparisonKey="",trafficNextSkip=0,trafficHasMore=false,trafficCompareChoice={builds:{},metrics:{}};
let trafficHistoryLoadedAt=null,trafficComparisonLoadedAt=null,trafficSnapshotUnavailable=true;
let trafficComparisonBlocked=false,trafficUnreadableHistory=false;
labText.ru.trafficPayloadBytes='Полезные данные запроса, байт';
labText.en.trafficPayloadBytes='Request payload, bytes';
Object.assign(labText.ru,{trafficControlTcpEcho:'TCP echo, не проверка UDP',trafficControlScopeUnknown:'Область контроля не записана',trafficCliProfile:'CLI подтвердил SOCKS5-конфигурацию',trafficCliOutput:'Вывод CLI сохранён в приватном каталоге',trafficCliOutputPrefix:'Сохранено начало вывода; достигнут лимит размера'});
Object.assign(labText.en,{trafficControlTcpEcho:'TCP echo, not a UDP check',trafficControlScopeUnknown:'Control scope not recorded',trafficCliProfile:'CLI confirmed the SOCKS5 configuration',trafficCliOutput:'CLI output retained in the private directory',trafficCliOutputPrefix:'Output prefix retained; size limit reached'});
Object.assign(labText.ru,{trafficActivityUnconfirmed:'Активность не подтверждена',trafficActivityHelp:'Сохранено PREPARING/RUNNING, но этот экземпляр UI не управляет прогоном. Он может выполняться в другом экземпляре или остаться после остановки. Прерывание и очистка не подтверждены; файл отчёта не изменён.'});
Object.assign(labText.en,{trafficActivityUnconfirmed:'Activity unconfirmed',trafficActivityHelp:'PREPARING/RUNNING is recorded, but this UI instance does not own the run. Another instance may still be running it, or the record may remain after shutdown. Interruption and cleanup are unconfirmed; the report file is unchanged.'});
Object.assign(labText.ru,{trafficStageMinTx:'Минимум отправки этапа, MiB/s',trafficStageMinRx:'Минимум получения этапа, MiB/s',trafficStageWorstP99:'Худший RTT p99 этапа, мс'});
Object.assign(labText.en,{trafficStageMinTx:'Minimum stage upload, MiB/s',trafficStageMinRx:'Minimum stage download, MiB/s',trafficStageWorstP99:'Worst stage RTT p99, ms'});
Object.assign(labText.ru,{trafficPhaseSummary:'Исходный этап, нагрузка и восстановление',trafficPhase_baseline:'Исходный этап',trafficPhase_workload:'Нагрузка',trafficPhase_recovery:'Восстановление',trafficPhaseStages:'Этапов завершено / записано',trafficPhaseProbeCoverage:'Этапов с RTT',trafficLoadTx:'Нагрузка: отправка, MiB/s',trafficLoadRx:'Нагрузка: получение, MiB/s',trafficLoadMinTx:'Нагрузка: минимум отправки этапа, MiB/s',trafficLoadMinRx:'Нагрузка: минимум получения этапа, MiB/s',trafficLoadWorstP99:'Нагрузка: худший RTT p99 этапа, мс',trafficRecoveryP99Change:'Восстановление минус исходный RTT p99, мс',trafficPhaseHelp:'Средние скорости взвешены по длительности записанных этапов; нагрузка исключает исходный этап и восстановление. Минимум относится к целому этапу, не краткому провалу. Худший p99 — максимум процентилей этапов, не общий процентиль. Изменение RTT доступно для одного завершённого исходного этапа и одного восстановления; это наблюдение, без порога PASS.'});
Object.assign(labText.en,{trafficPhaseSummary:'Baseline, workload and recovery',trafficPhase_baseline:'Baseline',trafficPhase_workload:'Workload',trafficPhase_recovery:'Recovery',trafficPhaseStages:'Completed / recorded stages',trafficPhaseProbeCoverage:'Stages with RTT',trafficLoadTx:'Workload upload, MiB/s',trafficLoadRx:'Workload download, MiB/s',trafficLoadMinTx:'Workload minimum stage upload, MiB/s',trafficLoadMinRx:'Workload minimum stage download, MiB/s',trafficLoadWorstP99:'Workload worst stage RTT p99, ms',trafficRecoveryP99Change:'Recovery minus baseline RTT p99, ms',trafficPhaseHelp:'Mean rates are weighted by recorded stage duration; workload excludes baseline and recovery. Minima describe whole stages, not short stalls. Worst p99 is the maximum stage percentile, not an aggregate percentile. RTT change requires exactly one completed baseline and recovery stage; it is an observation without a PASS threshold.'});
Object.assign(labText.ru,{trafficComparisonMode:'Измеренный режим',trafficComparisonModeHelp:'OFF и UNRULED измеряются в сценарии «Три режима». Короткие контрольные обмены сюда не подставляются. Пустые значения означают отсутствие полного подтверждённого измерения выбранного режима.',trafficModeNotMeasured:'Режим не измерен'});
Object.assign(labText.en,{trafficComparisonMode:'Measured mode',trafficComparisonModeHelp:'OFF and UNRULED measurements come from the Three modes case. Short control exchanges are never substituted. Empty values mean no complete verified measurement is available for the selected mode.',trafficModeNotMeasured:'Mode not measured'});
Object.assign(labText.ru,{trafficLoss:'Потери ответов, %',trafficUdpObservations:'Наблюдения нативного UDP',trafficUdpSent:'UDP отправлено',trafficUdpReceived:'UDP подтверждено',trafficUdpDuplicates:'Повторные ответы UDP',trafficUdpReordered:'Ответы UDP вне порядка',trafficUdpInvalid:'Некорректные ответы UDP',trafficUdpExpired:'Истечения и поздние ответы UDP',trafficUdpSendErrors:'Ошибки отправки UDP',trafficUdpHelp:'Счётчики нативного UDP; DNS/QUIC сюда не входят. Дедлайн ответа 2 с, окно распознавания повторов ограничено. Истечения и поздние ответы могут учитывать один запрос повторно; это не число потерянных пакетов. Наблюдения неполного прогона не подтверждают успешность маршрута или нагрузку.'});
Object.assign(labText.en,{trafficLoss:'Reply loss, %',trafficUdpObservations:'Native UDP observations',trafficUdpSent:'UDP sent',trafficUdpReceived:'UDP verified replies',trafficUdpDuplicates:'UDP duplicate replies',trafficUdpReordered:'UDP out-of-order replies',trafficUdpInvalid:'UDP invalid replies',trafficUdpExpired:'UDP expiry and late-reply events',trafficUdpSendErrors:'UDP send errors',trafficUdpHelp:'Native UDP counters; DNS/QUIC are excluded. Reply deadline is 2 seconds; duplicate detection has a bounded window. Expiry and late-reply events may count the same request twice and are not a lost-packet count. Partial-run observations do not confirm route or workload success.'});
Object.assign(labText.ru,{trafficConnectP50:'Подготовка сеанса p50, мс',trafficConnectP95:'Подготовка сеанса p95, мс',trafficConnectP99:'Подготовка сеанса p99, мс',trafficConnectSamples:'Измерений подготовки сеанса',trafficConnectHelp:'Граница зависит от профиля: flow churn — до аутентификации получателя завершённого обмена; QUIC/HTTP3 — handshake; SSH и messaging — аутентификация; остальные прикладные профили — первый подтверждённый обмен или batch. Все записанные samples, включая неполные сеансы; это не чистое TCP RTT. Процентили объединённой гистограммы — верхние границы с шагом 1%.'});
Object.assign(labText.en,{trafficConnectP50:'Session setup p50, ms',trafficConnectP95:'Session setup p95, ms',trafficConnectP99:'Session setup p99, ms',trafficConnectSamples:'Session setup samples',trafficConnectHelp:'Boundary depends on the profile: flow churn uses origin authentication for completed exchanges; QUIC/HTTP3 uses handshake; SSH and messaging use authentication; other application profiles use the first verified exchange or batch. All recorded samples, including incomplete sessions; this is not pure TCP RTT. Merged histogram percentiles are upper bounds with 1% bins.'});
Object.assign(labText.ru,{trafficMemoryDelta:'Изменение памяти, МиБ',trafficMemoryDeltaHelp:'Разница последнего и первого доступных наблюдений одной идентичности процесса за весь профиль; нужно минимум два образца. Показатель не определяет причину роста. Память ОС включает фоновую работу.',trafficCliRamDelta:'CLI private commit: изменение, МиБ',trafficCliResidentDelta:'CLI рабочий набор: изменение, МиБ',trafficOriginProcessRamDelta:'Origin/proxy RSS: изменение, МиБ'});
Object.assign(labText.en,{trafficMemoryDelta:'Memory change, MiB',trafficMemoryDeltaHelp:'Last minus first available observations of one process identity across the whole workload schedule; at least two samples are required. The counter does not identify the cause of growth. Whole-OS memory includes background work.',trafficCliRamDelta:'CLI private commit change, MiB',trafficCliResidentDelta:'CLI working set change, MiB',trafficOriginProcessRamDelta:'Origin/proxy RSS change, MiB'});
Object.assign(labText.ru,{trafficCoverage:'Полнота ресурсных наблюдений',trafficCoverageRole:'Источник',trafficCoverageAvailable:'Доступны / попытки опроса',trafficCoverageCpu:'Образцы CPU',trafficCoverageMemory:'Область памяти',trafficCoverageHelp:'Среднее CPU рассчитано по доступным интервалам. Пропуски и первое наблюдение без CPU-дельты не считаются нулями; эти данные не измеряют ресурсы драйвера.',trafficResource_product_cli:'CLI ProxyBridge',trafficResource_worker:'Исполнитель нагрузки',trafficResource_windows_system:'Windows целиком',trafficResource_worker_system:'ОС исполнителя целиком',trafficResource_origin_system:'Ubuntu целиком',trafficResource_origin_and_proxy:'Процесс получателя и SOCKS5'});
Object.assign(labText.en,{trafficCoverage:'Resource observation coverage',trafficCoverageRole:'Source',trafficCoverageAvailable:'Available / observation attempts',trafficCoverageCpu:'CPU samples',trafficCoverageMemory:'Memory scope',trafficCoverageHelp:'Mean CPU uses available intervals. Gaps and the initial observation without a CPU delta are not zeros; these counters do not measure driver resources.',trafficResource_product_cli:'ProxyBridge CLI',trafficResource_worker:'Load worker',trafficResource_windows_system:'Whole Windows OS',trafficResource_worker_system:'Whole worker OS',trafficResource_origin_system:'Whole Ubuntu OS',trafficResource_origin_and_proxy:'Origin and SOCKS5 process'});
Object.assign(labText.ru,{trafficHistoryUnreadable:'Один или несколько отчётов отсутствуют или не читаются. История неполная; сравнение заблокировано, старые успехи не подставляются.',trafficHistoryUnavailable:'История не обновлена: источник недоступен. Показаны ранее загруженные записи; сравнение и выгрузка недоступны.'});
Object.assign(labText.en,{trafficHistoryUnreadable:'One or more reports are missing or unreadable. History is incomplete; comparison is blocked without substituting older successes.',trafficHistoryUnavailable:'History could not refresh: the source is unavailable. Previously loaded entries are shown; comparison and export are unavailable.'});
Object.assign(labText.ru,{trafficLiveHelp:'Текущие счётчики получателя; итог обмена и маршрута ещё не подтверждён.',trafficLiveUnavailable:'Свежие счётчики получателя недоступны.',trafficLiveRx:'Принято',trafficLiveTx:'Отправлено',trafficLiveBytes:'Б',trafficLiveKiB:'КиБ',trafficLiveMiB:'МиБ',trafficLiveActive:'Активные сеансы',trafficLiveTransactions:'Прикладные запросы'});
Object.assign(labText.en,{trafficLiveHelp:'Current origin counters; final exchange and route are not yet verified.',trafficLiveUnavailable:'Fresh origin counters are unavailable.',trafficLiveRx:'Received',trafficLiveTx:'Sent',trafficLiveBytes:'B',trafficLiveKiB:'KiB',trafficLiveMiB:'MiB',trafficLiveActive:'Active sessions',trafficLiveTransactions:'Application requests'});
Object.assign(labText.ru,{trafficExportComparison:'Скачать выбранное сравнение (CSV)',trafficExportHistory:'Скачать загруженную историю (JSON)',trafficExportHelp:'В CSV попадут выбранные сборки и показатели для текущих условий. JSON содержит только загруженные страницы с текущим фильтром; наличие следующих страниц указано в файле. Неподтверждённые показатели остаются пустыми.',trafficExportUnavailable:'Обновите результаты и выберите строки для выгрузки.',trafficExportTooLarge:'Выгрузка превышает 8 МиБ. Сузьте выбор результатов.',trafficExportStarted:'Выгрузка подготовлена. Файл передан браузеру.'});
Object.assign(labText.en,{trafficExportComparison:'Download selected comparison (CSV)',trafficExportHistory:'Download loaded history (JSON)',trafficExportHelp:'CSV includes selected builds and metrics for the current conditions. JSON includes only loaded pages with the current filter; the file indicates whether more pages exist. Unconfirmed metrics remain empty.',trafficExportUnavailable:'Refresh results and select rows to export.',trafficExportTooLarge:'Export exceeds 8 MiB. Narrow the result selection.',trafficExportStarted:'Export prepared. The file was handed to the browser.'});
Object.assign(labText.ru,{trafficMetrics:"Показатели",trafficCompare:"Последняя попытка каждой сборки при одинаковых условиях",trafficMore:"Ещё попытки",trafficSystemCpu:"Windows CPU, % ПК",trafficSystemRam:"Windows RAM, MiB",trafficOriginCpu:"CPU получателя, % узла",trafficOriginRam:"RAM получателя, MiB",trafficUdpP99:"UDP RTT p99, мс",trafficPeak:"Пик соединений TCP",trafficCleanup:"Очистка",trafficCliResident:"CLI working set, MiB",trafficWorkerCpu:"Работник CPU, % ПК",trafficWorkerRam:"Работник private commit, MiB",trafficOriginProcessCpu:"Origin/proxy CPU, % узла",trafficOriginProcessRam:"Origin/proxy RSS, MiB",trafficCliHandles:"CLI handles",trafficCliThreads:"CLI threads",trafficAllStages:"Сводные показатели включают все этапы: исходный, нагрузку и восстановление. CPU/RAM ОС включают фоновую работу. Пустое значение означает отсутствие подтверждённого измерения."});
Object.assign(labText.en,{trafficMetrics:"Metrics",trafficCompare:"Latest attempt for each build under matching conditions",trafficMore:"More attempts",trafficSystemCpu:"Windows CPU, % of PC",trafficSystemRam:"Windows RAM, MiB",trafficOriginCpu:"Receiver CPU, % of host",trafficOriginRam:"Receiver RAM, MiB",trafficUdpP99:"UDP RTT p99, ms",trafficPeak:"Peak TCP connections",trafficCleanup:"Cleanup",trafficCliResident:"CLI working set, MiB",trafficWorkerCpu:"Worker CPU, % of PC",trafficWorkerRam:"Worker private commit, MiB",trafficOriginProcessCpu:"Origin/proxy CPU, % of host",trafficOriginProcessRam:"Origin/proxy RSS, MiB",trafficCliHandles:"CLI handles",trafficCliThreads:"CLI threads",trafficAllStages:"Aggregates include every stage: baseline, load and recovery. Whole-OS CPU/RAM include background work. An empty value means no verified measurement is available."});
try{trafficCompareChoice=JSON.parse(localStorage.getItem("testlab-traffic-comparison")||"null")||trafficCompareChoice;}catch{}
try {trafficChoice=JSON.parse(localStorage.getItem("testlab-traffic-choice")||"{}");} catch {}
if(!trafficChoice||typeof trafficChoice!=='object'||Array.isArray(trafficChoice))trafficChoice={};
for(const [id,choice] of Object.entries(trafficChoice))if(!choice||!['SHORT','NORMAL','LONG'].includes(choice.duration)||!['LOW','HIGH'].includes(choice.load))delete trafficChoice[id];
if(!trafficCompareChoice||typeof trafficCompareChoice!=='object')trafficCompareChoice={};
trafficCompareChoice.builds=trafficCompareChoice.builds&&typeof trafficCompareChoice.builds==='object'?trafficCompareChoice.builds:{};
trafficCompareChoice.metrics=trafficCompareChoice.metrics&&typeof trafficCompareChoice.metrics==='object'?trafficCompareChoice.metrics:{};
trafficCompareChoice.mode=['OFF','UNRULED','SOCKS5'].includes(trafficCompareChoice.mode)?trafficCompareChoice.mode:'SOCKS5';
lab('traffic-comparison-mode').value=trafficCompareChoice.mode;
const trafficCases=()=>trafficFamilies(trafficCatalog).flatMap(family=>family.rows.filter(row=>trafficChoice[row.id]?.selected).map(row=>({id:row.id,duration:trafficChoice[row.id].duration,load:trafficChoice[row.id].load})));
const trafficCaseEstimate=row=>row.id==="soak"?({SHORT:24,NORMAL:48,LONG:72}[row.duration]*3600+300):({SHORT:6,NORMAL:30,LONG:120}[row.duration]*({"tcp-multistream":3,"loaded-rtt":3,"flow-rate":3,"mixed":3,"three-modes":3,"tcp-connections":5,"udp-connections":5,"udp-sweep":6,"stability":10}[row.id]||trafficCatalog?.cases.find(value=>value.id===row.id)?.payload_sizes?.length||1)+20);
const trafficSafeContinue=()=>true;
const trafficEstimate=(cases=trafficCases(),continueAfterFailure=trafficSafeContinue())=>{const planned=trafficSelectionPlan(trafficCatalog,cases).cases;return planned.reduce((sum,row)=>sum+trafficCaseEstimate(row),0)+(continueAfterFailure?Math.max(0,planned.length-1)*20:0);};
function trafficLiveBytes(value){
  if(typeof value!=="number"||!Number.isFinite(value)||value<0)return "—";
  if(value<1024)return `${number(value,0)} ${t('trafficLiveBytes')}`;
  if(value<1048576)return `${number(value/1024,1)} ${t('trafficLiveKiB')}`;
  return `${number(value/1048576,2)} ${t('trafficLiveMiB')}`;
}
function trafficReviewChoices(run,active,choices){
  if(!active||!Array.isArray(run?.cases))return choices;
  return Object.fromEntries(run.cases.map(row=>[row.id||row.Id,{selected:true,duration:row.duration||row.Duration,load:row.load||row.Load}]));
}
Object.assign(labText.ru,{trafficActiveSelection:"Запущенный набор",trafficWindow:"Окно"});
Object.assign(labText.en,{trafficActiveSelection:"Running selection",trafficWindow:"Window"});
const trafficName=id=>trafficCatalog?.cases.find(row=>row.id===id)?.[labLanguage]||id;
function trafficFamilyCard(family,busy,expanded){
  const choice=trafficFamilyChoice(family),disabled=busy?"disabled":"";
  const options=(values,current,label)=>`${current==="MIXED"?`<option value="MIXED" disabled selected>${t("trafficMixed")}</option>`:""}${values.map(value=>`<option value="${value}" ${value===current?"selected":""}>${html(label(value))}</option>`).join("")}`;
  const effectiveIds=new Set(trafficSelectionPlan(trafficCatalog,trafficCases()).cases.map(row=>row.id));
  const estimate=family.rows.filter(row=>choice.ids.includes(row.id)&&(!choice.selected||effectiveIds.has(row.id))).reduce((sum,row)=>sum+trafficCaseEstimate({id:row.id,duration:choice.duration==="MIXED"?trafficChoice[row.id]?.duration||"SHORT":choice.duration}),0);
  return `<div data-traffic-card="${family.id}" class="lab-test-card${choice.selected?" is-selected":""}"><label class="lab-test-toggle"><input type="checkbox" data-traffic-family="${family.id}" ${choice.selected?"checked":""} ${disabled}><span>${html(trafficFamilyName(family))}</span></label>
    <div class="lab-test-settings ${Object.keys(family.profiles).length>1?"traffic-family-settings":""}">${Object.keys(family.profiles).length>1?`<label>${t("trafficDepth")}<select data-traffic-depth="${family.id}" ${disabled}>${choice.profile==="CUSTOM"?`<option value="CUSTOM" disabled selected>${t("trafficDepth_CUSTOM")}</option>`:""}${options(Object.keys(family.profiles),choice.profile,value=>t(`trafficDepth_${value}`))}</select></label>`:""}
    <label>${t("duration")}<select data-traffic-duration="${family.id}" ${disabled}>${options(["SHORT","NORMAL","LONG"],choice.duration,value=>family.id==="soak"?{SHORT:24,NORMAL:48,LONG:72}[value]+" h":t(value))}</select></label>
    <label>${t("load")}<select data-traffic-load="${family.id}" ${disabled}>${options(["LOW","HIGH"],choice.load,t)}</select></label></div>
    <p>${t("trafficStages")}: ${choice.ids.length} / ${family.rows.length} · ${t("trafficEstimate")}: ≈ ${number(estimate/60,1)} ${t("trafficMinutes")}</p>
    <details class="traffic-family-stages" data-family-stages="${family.id}" ${expanded?"open":""}><summary>${t("trafficFamilyStages")}</summary><p>${t("trafficFamilyHelp")}</p><ul>${family.rows.map(row=>`<li><label class="lab-test-toggle"><input type="checkbox" data-traffic-stage="${html(row.id)}" ${choice.selected&&choice.ids.includes(row.id)?"checked":""} ${disabled}>${html(row[labLanguage]||row.id)}${choice.selected&&choice.ids.includes(row.id)&&[choice.duration,choice.load].includes("MIXED")?` · ${html(trafficChoice[row.id].duration)} / ${html(trafficChoice[row.id].load)}`:""}</label></li>`).join("")}</ul></details>${family.id==="soak"?`<p class="traffic-soak-help">${t("reportSoak")}</p>`:""}</div>`;
}
Object.assign(labText.ru,{trafficCliExitCode:"Код завершения CLI"});
Object.assign(labText.en,{trafficCliExitCode:"CLI exit code"});
Object.assign(labText.ru,{trafficReadinessFailureHelp:"Клиент не подтвердил готовность в отведённое время.",trafficCrashFailureHelp:"Процесс клиента завершился аварийно. Проверка не считается пройденной; код завершения указан ниже."});
Object.assign(labText.en,{trafficReadinessFailureHelp:"The CLI did not confirm readiness within the deadline.",trafficCrashFailureHelp:"The CLI crashed. The check has not passed; its exit code is shown below."});
function trafficFailureHelp(row){
  const errors=row.errors||[],messages=[];
  if(errors.includes("TRAFFIC_CLI_READINESS_FAILED")) {
    messages.push(t("trafficReadinessFailureHelp"));
    if(row.conditions?.adapter_id==="windivert-4.0-cli-v1")messages.push(t("winDivertVersionSupport"));
  }
  if(errors.includes("TRAFFIC_CLI_CRASHED"))messages.push(t("trafficCrashFailureHelp"));
  return messages.length?`<p>${messages.map(html).join(" ")}</p>`:"";
}
Object.assign(labText.ru,{trafficForcedStop:"Процесс клиента не завершился вовремя и был принудительно закрыт. Тест сохраняет FAIL; продолжение возможно только после проверки полного восстановления."});
Object.assign(labText.en,{trafficForcedStop:"The CLI did not exit within the deadline and was forcibly closed. The case remains FAIL; continuation requires verified full recovery."});
function trafficCliExitMarkup(row){
  const code=row.last_lifecycle?.child_exit_code;
  const forced=row.last_lifecycle?.forced_stop===true||row.last_lifecycle?.host_exit_code===11?`<p>${html(t("trafficForcedStop"))}</p>`:"";
  return forced+(Number.isInteger(code)&&code>=0&&code<=0xffffffff?`<p>${t("trafficCliExitCode")}: 0x${code.toString(16).toUpperCase().padStart(8,"0")}</p>`:"");
}
function trafficHistoryFamilies(attempt,rows,selected,renderRow){
  const requested=(attempt.cases||[]).filter(row=>selected==="all"||`${row.Id||row.id}|${row.Duration||row.duration}|${row.Load||row.load}`===selected);
  return trafficFamilyReportGroups(trafficCatalog,requested,rows).map(group=>`<details class="traffic-family-result"><summary>${html(trafficFamilyName(group.family))} · ${t("trafficFamilyReport")}: ${group.status} · ${t("trafficPassed")}: ${group.passed}/${group.stages.length}</summary><p>${t("trafficFamilyHelp")}</p>${group.status==="INCOMPLETE"?`<p>${t("trafficFamilyIncomplete")}</p>`:""}${group.stages.map((stage,index)=>group.rows[index]?renderRow(group.rows[index]):`<p>${html(trafficName(stage.id))} · ${html(stage.duration)} / ${html(stage.load)} · ${t("trafficStageMissing")}</p>`).join("")}</details>`).join("");
}
function renderTraffic(){
  const remote=lab("lab-mode").value==="remote", active=!!trafficState?.execution?.active;
  lab("traffic-testing").hidden=false; lab("traffic-run").hidden=false;
  lab("lab-test-selection").hidden=true; lab("lab-testing-time").hidden=true;
  const busy=trafficActionActive||active||runActive()||remoteActionActive||labActionActive;
  lab("lab-mode").disabled=busy;
  lab("lab-local-launch").hidden=true;
  lab("scenario-description").hidden=true;
  lab("traffic-testing").querySelector('[data-i18n="trafficScope"]').textContent=(remote?"Ubuntu 22.04. ":t("trafficLocalScope"))+t("trafficScope").replace(/^Ubuntu 22\.04\. /, "");
  lab("traffic-plan").parentElement.hidden=!remote;
  lab("traffic-plan").disabled=busy||!labState.csrf;
  lab("traffic-apply").disabled=busy||!trafficState?.runtime?.plan;
  lab("traffic-start").disabled=busy||remote&&trafficState?.runtime?.state==="APPLY_UNKNOWN"||!trafficState?.runtime?.administrator||!remote&&trafficState?.runtime?.local_preflight?.ready!==true||!(labState.observation?.adapter_id||labState.observation?.declared_contract==="driver")||!labState.observation?.build_id||!trafficCases().length;
  const versionNotice=!active?productVersionNotice(labState.observation):"";
  lab("traffic-version-notice").textContent=versionNotice;
  lab("traffic-version-notice").hidden=!versionNotice;
  lab("traffic-stop").disabled=!active||trafficActionActive;
  const plan=trafficState?.runtime?.plan;
  lab("traffic-runtime-status").textContent=remote?`${t("trafficReady")}: ${trafficState?.runtime?.state||"VALIDATION_REQUIRED"}`:t("trafficLocalRuntime");
  const localIssues = remote ? [] : [...(trafficState?.runtime?.local_preflight?.errors||[]).map(t), ...(!trafficState?.runtime?.administrator?[t("trafficAdminHelp")]:[]), ...(labState.observation && !labState.observation.adapter_id && labState.observation.declared_contract!=="driver"?[t("trafficAdapterHelp")]:[])];
  lab("traffic-runtime-help").hidden=remote?trafficState?.runtime?.state!=="APPLY_UNKNOWN":!localIssues.length;
  lab("traffic-runtime-help").textContent=remote?t("trafficApplyUnknown"):localIssues.join(" ");
  lab("traffic-runtime-plan").hidden=!remote||!plan;
  lab("traffic-runtime-plan").textContent=plan?JSON.stringify({ubuntu:plan.ubuntuVersion,bundle:plan.bundleSha256,files:plan.files,tcp:plan.tcpPorts,udp:plan.udpPorts,expires:plan.expiresUtc},null,2):"";
  lab("traffic-estimate").textContent=`${t("trafficEstimate")}: ${number(trafficEstimate()/60,1)} ${t("trafficMinutes")}`;
  const run=trafficState?.execution?.run, progress=trafficState?.execution?.progress;
  const runningCases=run?.cases||[],caseIndex=runningCases.findIndex(row=>progress?.run_id?.startsWith(`${run.id}.${row.id||row.Id}.`));
  lab("traffic-run-status").textContent=[labState.builds.find(build=>build.id===(run?.build_id||labState.observation?.build_id))?.display_name,run?.state,
    caseIndex>=0?`${trafficName(runningCases[caseIndex].id||runningCases[caseIndex].Id)} · ${caseIndex+1}/${runningCases.length}`:"",progress?.stage,
    progress?.index!==undefined?`${t("trafficWindow")}: ${progress.index+1}/${progress.total}`:"",run?.id].filter(Boolean).join(" · ");
  renderTrafficExecution(trafficState?.execution);
  lab("traffic-error").textContent=trafficError||(remote&&trafficState?.runtime?.state==="APPLY_UNKNOWN"?t("trafficApplyUnknown"):trafficState?.runtime?.error)||(run?.error==="TRAFFIC_CASE_FAILED"?"":run?.error)||(!trafficState?.runtime?.administrator?t("trafficAdmin"):"");
  const families=trafficFamilies(trafficCatalog);
  const cardsKey=JSON.stringify([trafficCatalog,trafficChoice,trafficFamilyPreferences,labLanguage,busy]);
  let restoreFocus=null;
  if(cardsKey!==trafficCardsKey&&lab("traffic-cases").contains(document.activeElement)){
    for(const attribute of ["data-traffic-family","data-traffic-depth","data-traffic-duration","data-traffic-load","data-traffic-stage"]){
      const value=document.activeElement.getAttribute(attribute);
      if(value!==null){restoreFocus=`[${attribute}="${CSS.escape(value)}"]`;break;}
    }
  }
  if(trafficCatalog&&cardsKey!==trafficCardsKey){
    const expanded=[...lab("traffic-cases").querySelectorAll("details[open]")].map(detail=>detail.dataset.familyStages);
    trafficCardsKey=cardsKey;
    lab("traffic-cases").innerHTML=families.map(family=>trafficFamilyCard(family,busy,expanded.includes(family.id))).join("");
  }
  const selectionPlan=trafficSelectionPlan(trafficCatalog,trafficCases());
  const reviewChoices=trafficReviewChoices(run,active,Object.fromEntries(selectionPlan.cases.map(row=>[row.id,{...row,selected:true}])));
  const reviewChoice=family=>{const effective=trafficFamilySelection(family,reviewChoices);return active?effective:{...effective,profile:trafficFamilyChoice(family).profile};};
  const reviewCases=Object.entries(reviewChoices).map(([id,row])=>({id,...row}));
  const reviewEstimate=trafficEstimate(reviewCases,active?run?.continue_after_failure===true:trafficSafeContinue());
  const selectedFamilies=families.filter(family=>reviewChoice(family).selected);
  lab("traffic-selection-review").hidden=active;
  if(run&&lab("traffic-selection-review").dataset.queueRun!==run.id){lab("traffic-selection-review").open=false;lab("traffic-selection-review").dataset.queueRun=run.id;}
  lab("traffic-run").querySelector('[data-i18n="trafficRunHelp"]').hidden=!!run;
  lab("traffic-selection-summary").innerHTML=selectedFamilies.length?`<p>${t(active?"trafficActiveSelection":"trafficSelectionReview")}:</p><ul>${selectedFamilies.map(family=>{
    const choice=reviewChoice(family);
    return `<li>${html(trafficFamilyName(family))} · ${t(`trafficDepth_${choice.profile}`)} · ${t("trafficStages")}: ${choice.ids.length} · ${choice.duration==="MIXED"?t("trafficMixed"):family.id==="soak"?{SHORT:24,NORMAL:48,LONG:72}[choice.duration]+" h":t(choice.duration)} / ${choice.load==="MIXED"?t("trafficMixed"):t(choice.load)}</li>`;
  }).join("")}</ul><p>${t("trafficEstimate")}: ≈ ${number(reviewEstimate/60,1)} ${t("trafficMinutes")}</p>${!active?trafficSelectionNote(selectionPlan):''}`:`<p>${t("trafficNoSelection")}</p>`;
  if(restoreFocus){
    const control=lab("traffic-cases").querySelector(restoreFocus);
    if(control&&!control.disabled&&!control.closest("[hidden]"))control.focus({preventScroll:true});
  }
  renderTrafficHistory();
  renderTrafficComparison();
  if(typeof renderRunComparison==="function")renderRunComparison();
  updateTrafficExportButtons();
  lab('traffic-history-warning').hidden=!trafficUnreadableHistory&&!trafficSnapshotUnavailable;
  lab('traffic-history-warning').textContent=trafficSnapshotUnavailable?t('trafficHistoryUnavailable'):t('trafficHistoryUnreadable');
  if (typeof renderSavedSuites === "function") renderSavedSuites(busy);
}
function trafficControlsMarkup(row){
  const controls=row.controls||[];
  if(!controls.length)return '';
  return `<p>${t('trafficControls')}: ${controls.map(control=>`${html(control.mode)} · ${html(t(control.workload_scope==='tcp-echo'?'trafficControlTcpEcho':'trafficControlScopeUnknown'))} · ${control.complete===true&&control.route_verified===true?'PASS':control.complete===false?'FAIL':'UNVERIFIED'}`).join(' · ')}</p>`;
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
Object.assign(labText.ru,{trafficSession:'Одна сессия ProxyBridge на очередь; между проверками меняются правила',trafficSessionActive:'Без перезапуска',trafficQueueCleanup:'Очистка очереди',trafficSessionReady:'Готовность ProxyBridge',trafficSessionProfile:'Правила подтверждены',trafficSessionOutput:'Журнал сессии',trafficResource_origin_system:'ОС получателя',trafficResource_product_cli:'Процесс ProxyBridge',trafficCpu:'Процесс ProxyBridge CPU, % ПК',trafficRam:'Процесс ProxyBridge private commit, МиБ'});
Object.assign(labText.en,{trafficSession:'One ProxyBridge session per queue; rules change between checks',trafficSessionActive:'Session retained',trafficQueueCleanup:'Queue cleanup',trafficSessionReady:'ProxyBridge ready',trafficSessionProfile:'Rules confirmed',trafficSessionOutput:'Session log',trafficResource_origin_system:'Origin OS',trafficResource_product_cli:'ProxyBridge process',trafficCpu:'ProxyBridge process CPU, % of PC',trafficRam:'ProxyBridge process private commit, MiB'});
function trafficMeasurementEvidence(measurement){
  const state=['NOT_STARTED','PARTIAL','COMPLETED'].includes(measurement.measurement_state)?measurement.measurement_state:'UNKNOWN';
  const context=measurement.failure_context;
  const operation=['REGISTERING_SESSION','RUNNING_WORKLOAD','COLLECTING_EVIDENCE','WRITING_REPORT','PREPARING_REPORT'].includes(context?.operation)?context.operation:'UNKNOWN';
  const lossState=['MEASURED','NOT_MEASURED','NOT_APPLICABLE'].includes(measurement.loss_evidence_state)?measurement.loss_evidence_state:'UNKNOWN';
  const loss=lossState==='MEASURED'&&typeof measurement.loss_threshold_met==='boolean'?`${measurement.loss_threshold_met?'PASS':'FAIL'} (${number(measurement.loss_threshold_fraction*100,1)}%)`:t(`trafficLoss_${lossState==='MEASURED'?'UNKNOWN':lossState}`);
  const recorded=measurement.recorded_stage_count??measurement.stages?.length;
  const readiness=measurement.lifecycle?.ready===true?'PASS':measurement.lifecycle?.ready===false?'FAIL':'UNVERIFIED';
  const session=measurement.lifecycle?.scope==='selected-Core-in-TestLab-native-host; session-remains-running';
  const cleanup=measurement.lifecycle?.cleanup_verified===true&&measurement.lifecycle?.forced_stop===false?'PASS':'UNVERIFIED';
  const profile=measurement.lifecycle?.proxy_configuration_verified===true?'PASS':measurement.lifecycle?.proxy_configuration_verified===false?'FAIL':'UNVERIFIED';
  const retained=session?(measurement.lifecycle?.capture_live_verified?'PASS':'UNVERIFIED'):measurement.lifecycle?.output_retention_ok===true?(measurement.lifecycle?.output_capture_file?.truncated?t('trafficCliOutputPrefix'):'PASS'):measurement.lifecycle?.output_retention_ok===false?'FAIL':'UNVERIFIED';
  return `<p>${t('trafficMeasurementState')}: ${t(`trafficMeasurement_${state}`)} · ${t('trafficStageCounts')}: ${number(measurement.workload_started_stage_count,0)} / ${number(recorded,0)} / ${number(measurement.planned_stage_count,0)}</p>${context?`<p>${t('trafficFailurePhase')}: ${t(`trafficFailure_${operation}`)}${context.stage?` · ${html(context.stage)}`:''}</p>`:''}<p>${t('trafficLossEvidence')}: ${loss}</p>${measurement.mode==='OFF'?'':`<p>${t(session?'trafficSessionReady':'trafficCliReady')}: ${readiness} · ${session?t('trafficSessionActive'):t('trafficCliCleanup')}: ${session?(measurement.lifecycle?.ack_verified?'PASS':'UNVERIFIED'):cleanup}</p><p>${t(session?'trafficSessionProfile':'trafficCliProfile')}: ${profile} · ${t(session?'trafficSessionOutput':'trafficCliOutput')}: ${html(retained)}</p>`}`;
}
function trafficVerboseCase(row){return `${trafficFailureHelp(row)}${trafficCliExitMarkup(row)}<p>${t(row.cleanup_scope==="queue-final-off"?"trafficQueueCleanup":"trafficCleanup")}: ${row.cleanup_verified?"PASS":"UNVERIFIED"} · ${html((row.errors||[]).join(" · "))}</p>${trafficControlsMarkup(row)}${(row.measurements||[]).map(measurement=>{
      const cpu=measurement.resources?.product_cli?.counters?.cpu_percent_of_pc?.mean,ram=measurement.resources?.product_cli?.counters?.private_bytes?.max;
      return `<h5>${html(measurement.mode)} · ${measurement.route_verified?t("trafficRouteOk"):t("trafficRouteBad")}</h5>${trafficMeasurementEvidence(measurement)}${trafficResourceCoverageMarkup(measurement)}${trafficUdpObservationMarkup(measurement)}${trafficPhaseObservationMarkup(measurement)}${measurement.overall?.connection_latency?.count>0?`<p>${t("trafficConnectP50")}: ${number(measurement.overall.connection_latency.p50_ms)} · ${t("trafficConnectP95")}: ${number(measurement.overall.connection_latency.p95_ms)} · ${t("trafficConnectP99")}: ${number(measurement.overall.connection_latency.p99_ms)} · ${t("trafficConnectSamples")}: ${number(measurement.overall.connection_latency.count,0)}</p><p>${html(t("trafficConnectHelp"))}</p>`:""}<p>${t("trafficSkippedStages")}: ${measurement.skipped_stage_count||0} · ${html((measurement.schedule_errors||[]).join(" · "))}</p><p>${t("trafficCpu")}: ${number(cpu)} · ${t("trafficRam")}: ${number(typeof ram==="number"?ram/1048576:null)}</p><p>${t("trafficSystemCpu")}: ${number(measurement.resources?.windows_system?.counters?.cpu_percent_of_pc?.mean)} · ${t("trafficOriginCpu")}: ${number(measurement.resources?.origin_system?.counters?.cpu_percent_of_pc?.mean)}</p><div class="lab-table-scroll"><table><thead><tr>${["trafficPhase","trafficSent","trafficReceived","trafficP99","trafficUdpP99","trafficLoss","trafficConnections","trafficPeak","trafficErrors"].map(key=>`<th>${t(key)}</th>`).join("")}</tr></thead><tbody>${measurement.stages.map(stage=>`<tr><td>${html(stage.phase)} · ${stage.complete?"PASS":"FAIL"}</td><td>${number(trafficMiB(stage.tcp_tx_bytes_per_second))}</td><td>${number(trafficMiB(stage.tcp_rx_bytes_per_second))}</td><td>${number(stage.probe_p99_ms)}</td><td>${number(stage.udp_latency?.p99_ms)}</td><td>${number(typeof stage.udp_loss_fraction==="number"?stage.udp_loss_fraction*100:null)}</td><td>${stage.tcp_completed}/${stage.tcp_offered}</td><td>${number(stage.tcp_active_peak)}</td><td>${html((stage.errors||[]).join(" · "))}</td></tr>`).join("")}</tbody></table></div>${measurement.stages.filter(stage=>stage.application).map(stage=>`<details><summary>${t("trafficApplicationEvidence")} · ${html(stage.application)}</summary><p>${t("trafficTransactions")}: ${stage.application_transactions||0} · ${t("trafficPayloadBytes")}: ${number(stage.application_payload_bytes,0)}</p><pre>${html(JSON.stringify({tls:stage.application_tls_sessions||[],protocol:stage.application_protocol_sessions||[],socket_errors:stage.application_socket_errors||[]},null,2))}</pre></details>`).join("")}`;
    }).join("")||`<p>${t("trafficEmpty")}</p>`}`;}
function renderTrafficHistory(){if(typeof renderConciseTrafficHistory==="function")renderConciseTrafficHistory();}

const trafficMetrics=["trafficSent","trafficReceived","trafficP99","trafficUdpP99","trafficLoss","trafficCpu","trafficRam","trafficSystemCpu","trafficSystemRam","trafficOriginCpu","trafficOriginRam","trafficPeak","trafficCliResident","trafficWorkerCpu","trafficWorkerRam","trafficOriginProcessCpu","trafficOriginProcessRam","trafficCliHandles","trafficCliThreads","trafficTransactions","trafficCliRamDelta","trafficCliResidentDelta","trafficOriginProcessRamDelta","trafficConnectP50","trafficConnectP95","trafficConnectP99","trafficConnectSamples","trafficUdpSent","trafficUdpReceived","trafficUdpDuplicates","trafficUdpReordered","trafficUdpInvalid","trafficUdpExpired","trafficUdpSendErrors","trafficLoadTx","trafficLoadRx","trafficLoadMinTx","trafficLoadMinRx","trafficLoadWorstP99","trafficRecoveryP99Change"];
const trafficDefaultMetrics=new Set(["trafficSent","trafficReceived","trafficP99","trafficUdpP99","trafficLoss","trafficCpu","trafficCliResident","trafficSystemCpu","trafficOriginCpu"]);
const trafficMetricSelected=key=>trafficCompareChoice.metrics[key]??trafficDefaultMetrics.has(key);
const trafficMiB=value=>typeof value==='number'&&Number.isFinite(value)?value/1048576:null;
function trafficCounterChange(counter){
  return Number.isSafeInteger(counter?.count)&&counter.count>=2&&typeof counter.first==='number'&&Number.isFinite(counter.first)&&
    typeof counter.last==='number'&&Number.isFinite(counter.last)&&counter.first>=0&&counter.last>=0?counter.last-counter.first:null;
}
const trafficUdpCounters={trafficUdpSent:'sent',trafficUdpReceived:'received',trafficUdpDuplicates:'duplicates',trafficUdpReordered:'reordered',trafficUdpInvalid:'invalid',trafficUdpExpired:'expired',trafficUdpSendErrors:'send_errors'};
function trafficUdpObservationMarkup(measurement){
  const rows=[{phase:t('trafficUdpObservations'),observations:measurement.overall?.udp_observations},
    ...(measurement.stages||[]).map(stage=>({phase:stage.phase,observations:stage.udp_observations}))]
    .filter(row=>row.observations?.flow_count>0);
  if(!rows.length)return '';
  return `<details><summary>${t('trafficUdpObservations')}</summary><p>${html(t('trafficUdpHelp'))}</p><div class="lab-table-scroll"><table><thead><tr><th>${t('trafficPhase')}</th>${Object.keys(trafficUdpCounters).map(key=>`<th>${html(t(key))}</th>`).join('')}</tr></thead><tbody>${rows.map(row=>`<tr><td>${html(row.phase)}</td>${Object.values(trafficUdpCounters).map(key=>`<td>${number(row.observations[key],0)}</td>`).join('')}</tr>`).join('')}</tbody></table></div></details>`;
}
const trafficSelectedMeasurement=row=>(row.result?.measurements||[]).find(value=>value.mode===trafficCompareChoice.mode);
function trafficPhaseObservationMarkup(measurement){
  const observations=measurement.overall?.phase_observations;
  if(!observations?.groups)return '';
  return `<details><summary>${html(t('trafficPhaseSummary'))}</summary><p>${html(t('trafficPhaseHelp'))}</p><div class="lab-table-scroll"><table><thead><tr>${['trafficPhase','trafficPhaseStages','trafficSent','trafficReceived','trafficStageMinTx','trafficStageMinRx','trafficStageWorstP99','trafficPhaseProbeCoverage'].map(key=>`<th>${html(t(key))}</th>`).join('')}</tr></thead><tbody>${['baseline','workload','recovery'].map(name=>{
    const group=observations.groups[name];if(!group)return '';
    return `<tr><td>${html(t('trafficPhase_'+name))}</td><td>${number(group.completed_stages,0)} / ${number(group.recorded_stages,0)}</td><td>${number(trafficMiB(group.tcp_tx_bytes_per_second))}</td><td>${number(trafficMiB(group.tcp_rx_bytes_per_second))}</td><td>${number(trafficMiB(group.min_stage_tcp_tx_bytes_per_second))}</td><td>${number(trafficMiB(group.min_stage_tcp_rx_bytes_per_second))}</td><td>${number(group.worst_stage_probe_p99_ms)}</td><td>${number(group.probe_stages_measured,0)}</td></tr>`;
  }).join('')}</tbody></table></div><p>${html(t('trafficRecoveryP99Change'))}: ${number(observations.recovery_probe_p99_change_ms)}</p></details>`;
}
function trafficComparisonStatus(row){
  if(row.activity_observation==='UNCONFIRMED'&&['PREPARING','RUNNING'].includes(row.state))return 'ACTIVITY_UNCONFIRMED';
  if(!row.complete)return row.state||'UNVERIFIED';
  const measured=trafficSelectedMeasurement(row);
  return !measured?'NOT_MEASURED':measured.complete&&measured.route_verified?'PASS':'UNVERIFIED';
}
function trafficMetric(row,key){
  if(!row.complete)return null;
  const measured=trafficSelectedMeasurement(row);
  if(!measured?.complete||!measured.route_verified)return null;
  return trafficMeasurementMetric(measured,key);
}
function trafficMeasurementMetric(measured,key){
  if(!measured)return null;
  const overall=measured.overall||{},resources=measured.resources||{};
  const workload=overall.phase_observations?.groups?.workload;
  const counter=(role,name,stat)=>resources[role]?.counters?.[name]?.[stat];
  const values={trafficTransactions:overall.application_transactions,trafficSent:trafficMiB(overall.tcp_tx_bytes_per_second),trafficReceived:trafficMiB(overall.tcp_rx_bytes_per_second),
    trafficLoadTx:trafficMiB(workload?.tcp_tx_bytes_per_second),trafficLoadRx:trafficMiB(workload?.tcp_rx_bytes_per_second),
    trafficLoadMinTx:trafficMiB(workload?.min_stage_tcp_tx_bytes_per_second),trafficLoadMinRx:trafficMiB(workload?.min_stage_tcp_rx_bytes_per_second),
    trafficLoadWorstP99:workload?.worst_stage_probe_p99_ms,trafficRecoveryP99Change:overall.phase_observations?.recovery_probe_p99_change_ms,
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
  if(Object.hasOwn(trafficUdpCounters,key))return Number.isSafeInteger(overall.udp_observations?.[trafficUdpCounters[key]])?overall.udp_observations[trafficUdpCounters[key]]:null;
  return Number.isFinite(values[key])?values[key]:null;
}
function trafficComparisonRows(){
  const selected=lab('traffic-comparison-filter').value;
  return trafficComparison.filter(row=>`${row.runtime_mode||"remote"}|${row.case_id}|${row.duration}|${row.load}|${row.condition_id}`===selected&&trafficCompareChoice.builds[row.build_id]!==false);
}
function trafficHistoryRows(){
  const selected="all";
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
    const header=['snapshot_loaded_at_utc','exported_at_utc','build_id','build_name','attempt_id','case_id','duration','load','condition_id','runtime_mode','measurement_mode','status','errors','conditions_json','resource_observation_summary_json',...metrics.map(metric=>`${metric} (${t(metric)})`)];
    const records=rows.map(row=>[trafficComparisonLoadedAt,exportedAt,row.build_id,
      labState.builds.find(build=>build.id===row.build_id)?.display_name||row.build_id,row.attempt_id,row.case_id,
      row.duration,row.load,row.condition_id,row.runtime_mode||"remote",trafficCompareChoice.mode,trafficComparisonStatus(row),
      (row.result?.errors||[row.error]).filter(Boolean).join(' | '),JSON.stringify(row.conditions??null),JSON.stringify(trafficResourceCoverage(trafficSelectedMeasurement(row)?.resources)),
      ...metrics.map(metric=>trafficMetric(row,metric))]);
    content='\ufeff'+[header,...records].map(record=>record.map(trafficCsvCell).join(',')).join('\r\n')+'\r\n';
    type='text/csv;charset=utf-8';extension='csv';
  }else{
    const items=trafficHistoryRows();
    if(!items.length){status.textContent=t('trafficExportUnavailable');return;}
    content=JSON.stringify({schema_version:1,scope:'loaded-history-pages-filtered-by-case',
      snapshot_loaded_at_utc:trafficHistoryLoadedAt,exported_at_utc:exportedAt,
      filter:"all",has_more_pages:trafficHasMore,next_skip:trafficNextSkip,
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
  const groups=new Map();for(const row of trafficComparison)groups.set(`${row.runtime_mode||"remote"}|${row.case_id}|${row.duration}|${row.load}|${row.condition_id}`,row);
  select.innerHTML=[...groups].map(([id,row])=>`<option value="${html(id)}">${html(`${t(row.runtime_mode||"remote")} · ${trafficName(row.case_id)} · ${row.duration}/${row.load} · ${row.condition_id.slice(0,12)}`)}</option>`).join("");
  if(groups.has(previous))select.value=previous;
  const rows=trafficComparison.filter(row=>`${row.runtime_mode||"remote"}|${row.case_id}|${row.duration}|${row.load}|${row.condition_id}`===select.value);
  const name=row=>labState.builds.find(build=>build.id===row.build_id)?.display_name||row.build_id;
  lab("traffic-comparison-builds").innerHTML=rows.map(row=>`<label class="lab-test-toggle"><input type="checkbox" data-traffic-build="${html(row.build_id)}" ${trafficCompareChoice.builds[row.build_id]!==false?"checked":""}>${html(name(row))}</label>`).join("");
  lab("traffic-comparison-metrics").innerHTML=trafficMetrics.map(metric=>`<label class="lab-test-toggle"><input type="checkbox" data-traffic-metric="${metric}" ${trafficMetricSelected(metric)?"checked":""}>${html(t(metric))}</label>`).join("");
  const metrics=trafficMetrics.filter(metric=>trafficMetricSelected(metric));
  lab("traffic-comparison").innerHTML=rows.length?`<p>${html(t("trafficAllStages"))}</p>${metrics.some(metric=>metric.startsWith("trafficConnect"))?`<p>${html(t("trafficConnectHelp"))}</p>`:""}${metrics.some(metric=>Object.hasOwn(trafficUdpCounters,metric))?`<p>${html(t("trafficUdpHelp"))}</p>`:""}${metrics.some(metric=>metric.startsWith("trafficLoad")||metric==="trafficRecoveryP99Change")?`<p>${html(t("trafficPhaseHelp"))}</p>`:""}<div class="lab-table-scroll"><table><thead><tr><th>${t("connection")}</th><th>${html(trafficCompareChoice.mode)} · Status</th>${metrics.map(metric=>`<th>${html(t(metric))}</th>`).join("")}</tr></thead><tbody>${rows.filter(row=>trafficCompareChoice.builds[row.build_id]!==false).map(row=>`<tr><td>${html(name(row))}<br><small>${html(row.attempt_id)}</small></td><td>${trafficComparisonStatus(row)==="ACTIVITY_UNCONFIRMED"?html(t("trafficActivityUnconfirmed")):trafficComparisonStatus(row)==="NOT_MEASURED"?html(t("trafficModeNotMeasured")):html(trafficComparisonStatus(row))}<br>${html((row.result?.errors||[row.error]).filter(Boolean).join(" · "))}</td>${metrics.map(metric=>`<td>${number(trafficMetric(row,metric))}</td>`).join("")}</tr>`).join("")}</tbody></table></div><details><summary>${t("trafficConditions")}</summary><pre>${html(JSON.stringify(rows[0].conditions,null,2))}</pre></details>`:`<p>${t("trafficNone")}</p>`;
}
for(const id of ["traffic-comparison-builds","traffic-comparison-metrics"])lab(id).addEventListener("change",event=>{
  const build=event.target.dataset.trafficBuild,metric=event.target.dataset.trafficMetric;
  if(build)trafficCompareChoice.builds[build]=event.target.checked;if(metric)trafficCompareChoice.metrics[metric]=event.target.checked;
  localStorage.setItem("testlab-traffic-comparison",JSON.stringify(trafficCompareChoice));renderTrafficComparison();updateTrafficExportButtons();
});
lab("traffic-comparison-filter").addEventListener("change",()=>{renderTrafficComparison();updateTrafficExportButtons();});
lab('traffic-comparison-mode').addEventListener('change',()=>{
  trafficCompareChoice.mode=lab('traffic-comparison-mode').value;
  localStorage.setItem('testlab-traffic-comparison',JSON.stringify(trafficCompareChoice));
  renderTrafficComparison();
  if(typeof renderRunComparison==="function")renderRunComparison();updateTrafficExportButtons();
});
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
    const body=action==="apply"?{planId:trafficState.runtime.plan.planId}:action==="start"?{buildId:labState.observation.build_id,mode:lab("lab-mode").value,cases:trafficCases(),allowLongRun:true,continueAfterFailure:trafficSafeContinue()}:{};
    const response=await fetch(`/api/v1/lab/traffic/${action}`,{method:"POST",headers:{"Content-Type":"application/json","X-TestLab-CSRF":labState.csrf},body:JSON.stringify(body)});
    const data=await response.json();if(!response.ok)throw new Error(data.error||"TRAFFIC_REQUEST_FAILED");
    if(action==="start"){trafficState.execution={run:data,active:true};renderTrafficExecution(trafficState.execution);}
  }catch(error){trafficError=error.message;}finally{trafficActionActive=false;await loadTraffic();}
}
lab("traffic-cases").addEventListener("change",event=>{
  const target=event.target,card=target.closest("[data-traffic-card]");if(!card)return;
  const family=trafficFamilies(trafficCatalog).find(row=>row.id===card.dataset.trafficCard);if(!family)return;
  const choice=trafficFamilyChoice(family);
  let ids=[...choice.ids],selected=choice.selected;
  if(target.dataset.trafficFamily)selected=target.checked;
  else if(target.dataset.trafficDepth)ids=family.profiles[target.value]||ids;
  else if(target.dataset.trafficStage){
    const id=target.dataset.trafficStage;
    ids=selected?[...choice.ids]:[];
    ids=target.checked?[...new Set([...ids,id])]:ids.filter(value=>value!==id);
    selected=ids.length>0;
  }
  const duration=target.dataset.trafficDuration?target.value:choice.duration;
  const load=target.dataset.trafficLoad?target.value:choice.load;
  for(const row of family.rows){
    const previous=trafficChoice[row.id];
    trafficChoice[row.id]={selected:selected&&ids.includes(row.id),duration:duration==="MIXED"?previous?.duration||"SHORT":duration,load:load==="MIXED"?previous?.load||"LOW":load};
  }
  trafficFamilyPreferences[family.id]={ids,duration,load};
  localStorage.setItem("testlab-traffic-choice",JSON.stringify(trafficChoice));
  localStorage.setItem("testlab-traffic-families",JSON.stringify(trafficFamilyPreferences));
  renderTraffic();
});
for(const action of ["plan","apply","start","stop"])lab(`traffic-${action}`).addEventListener("click",()=>trafficAction(action));
lab("lab-mode").addEventListener("change",renderTraffic);
const renderLabBeforeTraffic=renderLab;
renderLab=function(){renderLabBeforeTraffic();renderTraffic();};
// User-facing resource names apply to both Core-host and historic CLI evidence.
Object.assign(labText.ru,{trafficCliResident:'Память процесса в RAM, МиБ',trafficCliRamDelta:'Изменение выделенной памяти процесса, МиБ',trafficCliResidentDelta:'Изменение памяти процесса в RAM, МиБ',trafficCliHandles:'Дескрипторы процесса',trafficCliThreads:'Потоки процесса',trafficResource_product_cli:'Процесс клиента ProxyBridge',trafficResource_origin_system:'ОС получателя',trafficWorkerCpu:'CPU исполнителя нагрузки, % ПК',trafficWorkerRam:'Выделенная память исполнителя, МиБ',trafficOriginProcessCpu:'CPU получателя и прокси, % узла',trafficOriginProcessRam:'Память получателя и прокси в RAM, МиБ',trafficOriginProcessRamDelta:'Изменение памяти получателя и прокси, МиБ',trafficCliExitCode:'Код завершения клиента',trafficCpu:'CPU процесса клиента, % ПК',trafficRam:'Выделенная память процесса, МиБ',trafficSent:'Отправка, МиБ/с',trafficReceived:'Получение, МиБ/с',trafficMore:'Ещё отчёты'});
Object.assign(labText.en,{trafficCliResident:'Process RAM working set, MiB',trafficCliRamDelta:'Process commit change, MiB',trafficCliResidentDelta:'Process RAM change, MiB',trafficCliHandles:'Process handles',trafficCliThreads:'Process threads',trafficResource_product_cli:'ProxyBridge client process',trafficResource_origin_system:'Receiver OS',trafficCliExitCode:'Client exit code',trafficCpu:'Client process CPU, % of PC',trafficRam:'Process committed memory, MiB'});
Object.assign(labText.ru,{trafficHeading:'Проверки сетевого трафика',trafficPrepare:'Проверить среду',trafficReady:'Готовность среды',trafficCliReady:'Готовность клиента подтверждена',trafficCliCleanup:'Клиент штатно завершён',trafficCliProfile:'Настройки SOCKS5 подтверждены',trafficCliOutput:'Журнал клиента сохранён',trafficContinueHelp:'После ошибки очередь продолжается только при подтверждённой изоляции и готовности к следующему этапу.'});
Object.assign(labText.en,{trafficHeading:'Network traffic checks',trafficPrepare:'Check environment',trafficReady:'Environment readiness',trafficCliReady:'Client readiness verified',trafficCliCleanup:'Client exited normally',trafficCliProfile:'SOCKS5 settings verified',trafficCliOutput:'Client log retained',trafficContinueHelp:'After a failure, the queue continues only after isolation and readiness for the next stage are verified.'});
loadTraffic();setInterval(()=>{if(!trafficActionActive)loadTraffic();},3000);

Object.assign(labText.ru,{trafficLocalScope:"Windows, получатель на этом же ПК. ",trafficLocalRuntime:"Локальный получатель подготавливается автоматически перед запуском. TLS/SSH-ключи изолированы; измерения используют ресурсы этого же ПК."});
Object.assign(labText.en,{trafficLocalScope:"Windows, origin on this PC. ",trafficLocalRuntime:"The local origin is prepared automatically before each run. TLS/SSH keys are isolated; measurements share this PC’s resources."});

function trafficSelectionNote(plan){
  if(!plan?.covered_cases?.length)return '';
  return `<details class="result-plan"><summary>${html(t('trafficCombined'))}: ${plan.requested_cases.length} → ${plan.cases.length}</summary><ul>${plan.covered_cases.map(row=>`<li>${html(trafficName(row.case_id))} → ${html(trafficName(row.covered_by))}</li>`).join('')}</ul></details>`;
}
