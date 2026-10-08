const labText = {
  ru: {
    title: "Лаборатория ProxyBridge", language: "Язык", connection: "Подключение", testing: "Тестирование", launch: "Проверка и запуск", results: "Результаты", milliseconds: "мс", maximum: "Максимум",
    installationHelp: "Выберите файлы установленного ProxyBridge. Проверка читает файлы, не запускает программу и не меняет драйвер.",
    version: "Версия", folder: "Папка ProxyBridge", driverPath: "Файл драйвера, если находится в другой папке", inspect: "Проверить файлы", select: "Выбрать комплект", details: "Технические сведения",
    proxyMode: "Расположение SOCKS5-прокси", local: "На этом ПК", remote: "На удалённом узле", scenario: "Сценарий", transfer: "Отправка и скачивание TCP", rtt: "Задержка TCP-запроса и ответа", loadedRtt: "Задержка TCP под нагрузкой", udp: "Обмен UDP и задержка",
    controlled: "В каждом режиме используется контролируемый получатель. Прямой трафик служит базой для сравнения выбранного пути через SOCKS5.",
    launchHelp: "Подготовка повторно проверяет сохранённый комплект. Она не запускает ProxyBridge или трафик. Кнопка запуска доступна для локальных TCP RTT и отправки/скачивания; остальные сценарии запускаются подготовленной командой.",
    localTransferHistory: "Отправка и скачивание TCP из лаборатории", noLocalTransfers: "Проверок отправки и скачивания из этого экрана пока нет.", transferRate: "Темп передачи, Мбит/с", verifiedVolume: "Проверено данных, МиБ", transferChange: "Изменение к прямому трафику, %", transferLocalScope: "Короткая проверка: по одной паре на отправку и скачивание, 64 МиБ на прогон, заданный темп 8 МиБ/с. Это не максимальная скорость; RTT и штатное закрытие TCP не проверяются. CPU/RAM — выборки процесса CLI, не самого драйвера или энергопотребления.",
    prepareLaunch: "Подготовить запуск", adminCommand: "Команда для PowerShell от администратора", planPrepared: "План подготовлен. Готовность системы будет проверена перед запуском.", planMinutes: "Ориентировочно, минут", planFailed: "Не удалось подготовить план. Перепроверьте и сохраните комплект.",
    startRun: "Запустить проверку", stopRun: "Остановить после текущего прогона", runHelp: "Остановка дождётся завершения текущего прогона и очистки. Завершённые данные сохранятся; неполная серия не является сравнением.", adminHelp: "Чтобы запускать из интерфейса, откройте приложение через PowerShell от администратора.", manualHelp: "Для этого сценария пока используйте подготовленную команду в PowerShell от администратора.", progress: "Завершено прогонов", stoppingHelp: "Запрос остановки принят. Дождитесь завершения текущего прогона и очистки.", completedAfterStop: "Последний прогон завершён с очисткой после запроса остановки. Серия выполнена полностью.", pollFailed: "Не удалось получить состояние запуска. Проверка могла продолжить работу; обновите страницу для восстановления связи.", cancelledHistory: "Проверка остановлена. Итог сравнения не составлен.",
    STARTING: "Подготовка запуска", RUNNING: "Проверка выполняется", STOPPING: "Ожидаем завершения текущего прогона", COMPLETED: "Проверка завершена", CANCELLED: "Проверка остановлена", FAILED: "Проверка не подтверждена", INTERRUPTED: "Запуск прерван; очистка не подтверждена",
    ADMINISTRATOR_REQUIRED: "Запустите приложение от администратора.", REAL_RUN_ALREADY_ACTIVE: "Другой исполнитель уже запускает проверку. Дождитесь его завершения.", SELECTION_CHANGED_PREPARE_AGAIN: "Сохранённый комплект изменился. Подготовьте новый запуск.", PLAN_ALREADY_USED_PREPARE_AGAIN: "Этот план уже использован. Подготовьте новый запуск.", GUI_RUN_NOT_STARTED: "Запуск не подтверждён. Обновите состояние перед повторной попыткой.", GUI_STOP_NOT_QUEUED: "Запрос остановки не подтверждён. Обновите состояние и повторите остановку.", WRAPPER_PRECHECK_OR_START_FAILED: "Проверка условий запуска не пройдена. Подробности сохранены в журнале запуска.", WORKLOAD_OR_CLEANUP_FAILED: "Ошибка проверки или завершения процессов. Подробности сохранены в отчёте запуска.", EVIDENCE_NOT_CONFIRMED: "Достоверность результата не подтверждена.", WRAPPER_OR_EVIDENCE_NOT_CONFIRMED: "Завершение запуска не подтверждено. Подробности сохранены в журнале.", APP_RESTART_CLEANUP_NOT_CONFIRMED: "Приложение перезапущено во время проверки. Перед следующим запуском нужна перезагрузка Windows.", LAB_REBOOT_REQUIRED_AFTER_RECORDED_4_0_0: "После запуска 4.0.0 перезагрузите Windows перед проверкой driver.", LAB_REBOOT_REQUIRED_AFTER_INTERRUPTED_RUN: "После прерванного запуска перезагрузите Windows.", LAB_OTHER_REAL_RUN_ACTIVE_OR_LEASE_UNAVAILABLE: "Другой исполнитель занят либо блокировка запуска недоступна.",
    planTransferScope: "Короткая проверка отправки и скачивания, по одной паре напрямую/через SOCKS5. Данные проверяются полностью; штатное закрытие TCP этим запуском не проверяется.", planRttScope: "Короткая проверка задержки: одна пара напрямую/через SOCKS5, 128 измерений после прогрева. Не сравнение версий.", planLoadedScope: "Короткая проверка задержки при передаче данных, отправка и скачивание. SOCKS5-стенд использует TCP_NODELAY; результаты не смешивать с прежней конфигурацией.", planUdpScope: "Два потока к разным контролируемым портам, три пары напрямую/через SOCKS5. Известная ошибка источника ответа остаётся проверкой корректности; ошибка двух потоков к одному порту этим профилем не проверяется.",
    localHistory: "Проверки TCP-задержки из лаборатории", versionHistory: "Сохранённые сравнения версий", noLocalRuns: "Проверок из этого экрана пока нет.", localPass: "Данные и маршрут проверены", localNotConfirmed: "Запуск не подтверждён. Подробности сохранены в отчёте запуска.", verified: "Проверено обменов, включая прогрев", measured: "Измерено обменов", exchangeErrors: "Ошибки обмена", localRttScope: "Короткая проверка готовности: по 128 измерений в каждом режиме. Это сохранённый результат, не проверка текущего состояния системы и не доказательство игровой или длительной стабильности.",
    SELECTION_REQUIRED: "Сначала выберите и сохраните комплект.", SELECTED_FILES_CHANGED: "Выбранные файлы изменились или недоступны. Проверьте комплект заново.", COMPATIBILITY_PENDING: "Для этой сборки ещё не подтверждён путь запуска.", REMOTE_CONTROLLER_PENDING: "Удалённый сценарий пока не подключён к этому экрану.", LEGACY_REBOOT_PREFLIGHT_REQUIRED: "4.0.0 требует отдельной подготовки и проверки перезагрузки. Запуск из этого экрана пока недоступен.", RELOCATED_KIT_PENDING: "Запуск скопированного комплекта пока не подключён: существующие контроллеры используют исходную папку стенда.", INVALID_SCENARIO: "Выбранный сценарий не поддерживается.",
    selectionHelp: "Выбор сохранён для нового пути запуска. Он не меняет настройки старого интерфейса и не подтверждает совместимость произвольной сборки.",
    historyHelp: "История подтверждённых сравнений 4.0.0 и driver. Эти результаты относятся к комплектам предыдущих прогонов, а не автоматически к выбранной сейчас установке.",
    refresh: "Обновить", noSelection: "Комплект не выбран.", saved: "Выбор сохранён. Перед запуском потребуется новая проверка файлов и состояния системы.",
    savedObservation: "Сохранённая проверка файлов", checking: "Проверяем…", failed: "Проверка не завершена. Проверьте путь, состав файлов и доступ к папке.",
    known: "Файлы совпадают с проверенным стендовым комплектом. Состояние драйвера и готовность запуска ещё не проверены.",
    pending: "Файлы найдены. Версия и совместимость пока не подтверждены; это не пройденная проверка ProxyBridge.",
    unreadable: "Файлы найдены, но их не удалось прочитать. Проверка комплекта не пройдена.", incomplete: "Не хватает обязательных файлов CLI, Core или драйвера выбранной версии.", old: "Версии до 4.0.0 не поддерживаются.",
    manualLocal: "Локальный driver: подготовка запуска через проверенные контроллеры.", manualRemote: "Удалённый получатель ещё не подключён к этому пути запуска.",
    transferHelp: "Проверка целостности и темпа отправки/скачивания. Текущий профиль ограничивает темп и не измеряет максимальную скорость.",
    rttHelp: "Время запроса и полного ответа внутри TCP-соединения. Это прикладной RTT, не ICMP ping.",
    loadedHelp: "TCP RTT одновременно с контролируемой передачей данных; учитывается подтверждённое перекрытие нагрузки.",
    udpHelp: "Проверяются данные, источник ответа и UDP RTT. Известные ошибки отображаются отдельно от доступных измерений.",
    empty: "Сохранённых сравнений версий пока нет.", unavailable: "Историю не удалось прочитать.", limited: "Ограниченно сопоставимо", metric: "Показатель", upload: "Отправка", download: "Скачивание", direct: "напрямую", paired: "Изменение к прямому, %", cpu: "CPU CLI, % ПК", ram: "Private RAM CLI, MiB",
    rateLimit: "Темп ограничен 64 MiB/s; по три пары на направление. Это не максимальная производительность.", closeIssue: "4.0.0: ранее обнаружен сброс при штатном закрытии TCP. Этот профиль проверяет данные без ожидания FIN; исправление не проверено.",
    scope: "Разные загрузки одной VM; фон мог меняться. CPU/RAM относятся к CLI, не к драйверу. Исходные результаты сохранены.", addition: "Добавка к прямому RTT, мс", rttScope: "Три пары, 1000 измеренных обменов и 200 прогревочных на прогон. Разности квантилей не являются задержкой каждого отдельного пакета.", badReports: "Некоторые отчёты недоступны."
  },
  en: {
    title: "ProxyBridge laboratory", language: "Language", connection: "Connection", testing: "Testing", launch: "Check and run", results: "Results", milliseconds: "ms", maximum: "Max",
    installationHelp: "Choose your installed ProxyBridge files. Inspection reads files without starting the product or changing its driver.",
    version: "Version", folder: "ProxyBridge folder", driverPath: "Driver file if located elsewhere", inspect: "Inspect files", select: "Select kit", details: "Technical details",
    proxyMode: "SOCKS5 proxy location", local: "On this PC", remote: "On a remote host", scenario: "Scenario", transfer: "TCP upload and download", rtt: "TCP request/response latency", loadedRtt: "TCP latency under load", udp: "UDP exchange and latency",
    controlled: "Both modes use a controlled receiver. Direct traffic is the baseline for the selected SOCKS5 path.",
    launchHelp: "Preparation rechecks the saved kit without starting ProxyBridge or traffic. The run button supports local TCP RTT and upload/download checks; other scenarios use the prepared command.",
    localTransferHistory: "TCP upload/download checks from the lab", noLocalTransfers: "No upload/download checks from this screen yet.", transferRate: "Transfer rate, Mbit/s", verifiedVolume: "Verified data, MiB", transferChange: "Change vs direct traffic, %", transferLocalScope: "Short readiness check: one pair per upload/download direction, 64 MiB per run, sender rate cap 8 MiB/s. Not maximum throughput; RTT and normal TCP close are not tested. CPU/RAM are sampled CLI process metrics, not driver attribution or power consumption.",
    prepareLaunch: "Prepare launch", adminCommand: "Command for administrator PowerShell", planPrepared: "Plan prepared. Runtime readiness will be checked before launch.", planMinutes: "Estimated minutes", planFailed: "Could not prepare the plan. Recheck and save the selected kit.",
    startRun: "Run check", stopRun: "Stop after current run", runHelp: "Stopping waits for the current run and cleanup. Completed evidence is retained; an incomplete series is not a comparison.", adminHelp: "Open the application from an administrator PowerShell to run checks from the UI.", manualHelp: "Use the prepared command in an administrator PowerShell for this scenario.", progress: "Completed runs", stoppingHelp: "Stop requested. Wait for the current run and cleanup.", completedAfterStop: "The final run finished with cleanup after the stop request. The entire series completed.", pollFailed: "Could not read run state. The check may still be running; refresh the page to reconnect.", cancelledHistory: "Check stopped. No comparison produced.",
    STARTING: "Preparing launch", RUNNING: "Check running", STOPPING: "Waiting for current run to finish", COMPLETED: "Check completed", CANCELLED: "Check stopped", FAILED: "Check not confirmed", INTERRUPTED: "Run interrupted; cleanup unconfirmed",
    ADMINISTRATOR_REQUIRED: "Start the application as administrator.", REAL_RUN_ALREADY_ACTIVE: "Another executor is running a check. Wait for completion.", SELECTION_CHANGED_PREPARE_AGAIN: "Saved kit changed. Prepare a new launch.", PLAN_ALREADY_USED_PREPARE_AGAIN: "This plan was already used. Prepare a new launch.", GUI_RUN_NOT_STARTED: "Launch not confirmed. Refresh state before trying again.", GUI_STOP_NOT_QUEUED: "Stop request not confirmed. Refresh state and request stop again.", WRAPPER_PRECHECK_OR_START_FAILED: "Launch checks failed. Details are saved in the launch log.", WORKLOAD_OR_CLEANUP_FAILED: "Check or process cleanup failed. Details are saved in the run report.", EVIDENCE_NOT_CONFIRMED: "Result evidence not confirmed.", WRAPPER_OR_EVIDENCE_NOT_CONFIRMED: "Launch completion not confirmed. Details are saved in the log.", APP_RESTART_CLEANUP_NOT_CONFIRMED: "Application restarted during a check. Reboot Windows before the next launch.", LAB_REBOOT_REQUIRED_AFTER_RECORDED_4_0_0: "Reboot Windows after running 4.0.0 before checking driver.", LAB_REBOOT_REQUIRED_AFTER_INTERRUPTED_RUN: "Reboot Windows after an interrupted launch.", LAB_OTHER_REAL_RUN_ACTIVE_OR_LEASE_UNAVAILABLE: "Another executor is active or the launch lease is unavailable.",
    planTransferScope: "Short upload/download readiness check, one direct/SOCKS5 pair per direction. Data verification is retained; normal TCP close is not tested by this run.", planRttScope: "Short latency readiness check: one direct/SOCKS5 pair, 128 measured echoes after warmup. Not a version comparison.", planLoadedScope: "Short latency readiness check during upload/download. The SOCKS5 fixture uses TCP_NODELAY; do not pool results with the previous fixture.", planUdpScope: "Two streams to separate controlled ports, three direct/SOCKS5 pairs. The known source-endpoint defect remains a correctness check; the same-destination cross-stream defect is not exercised.",
    localHistory: "TCP latency checks from the lab", versionHistory: "Saved version comparisons", noLocalRuns: "No checks from this screen yet.", localPass: "Data and route verified", localNotConfirmed: "Run not confirmed. Details are preserved in the run report.", verified: "Verified echoes, including warmup", measured: "Measured echoes", exchangeErrors: "Echo failures", localRttScope: "Short readiness check: 128 measured echoes per mode. This is saved evidence, not a current runtime observation or proof of game or long-run stability.",
    SELECTION_REQUIRED: "Select and save a kit first.", SELECTED_FILES_CHANGED: "Selected files changed or cannot be read. Inspect the kit again.", COMPATIBILITY_PENDING: "The launch path for this build is not confirmed yet.", REMOTE_CONTROLLER_PENDING: "Remote scenarios are not connected to this screen yet.", LEGACY_REBOOT_PREFLIGHT_REQUIRED: "4.0.0 requires separate preparation and a reboot check. Launch preparation from this screen is not available yet.", RELOCATED_KIT_PENDING: "Copied kits are not connected yet: the existing controllers use the original lab folder.", INVALID_SCENARIO: "The selected scenario is unsupported.",
    selectionHelp: "Selection is saved for the new launch flow. It does not change the previous interface settings or establish compatibility of an arbitrary build.",
    historyHelp: "Saved confirmed comparisons of 4.0.0 and driver. Results belong to the kits used in those runs, not automatically to the installation selected now.",
    refresh: "Refresh", noSelection: "No kit selected.", saved: "Selection saved. Files and system state must be checked again before a run.",
    savedObservation: "Saved file inspection", checking: "Inspecting…", failed: "Inspection did not complete. Check the path, required files and folder access.",
    known: "Files match a verified benchmark kit. Driver state and launch readiness have not been checked.",
    pending: "Files found. Version and compatibility are unverified; this is not a passed ProxyBridge check.",
    unreadable: "Files were found but could not be read. File inspection did not pass.", incomplete: "Required CLI, Core or selected driver files are missing.", old: "Versions before 4.0.0 are unsupported.",
    manualLocal: "Local driver: prepare a launch through the validated controllers.", manualRemote: "Remote receiver is not connected to this launch flow yet.",
    transferHelp: "Data integrity and upload/download rate. The current profile is rate capped and does not measure maximum throughput.",
    rttHelp: "Request and complete reply within a TCP connection. Application RTT, not ICMP ping.",
    loadedHelp: "TCP RTT during verified concurrent data transfer, with confirmed load overlap.",
    udpHelp: "Checks data, reply source and UDP RTT. Known correctness defects are shown separately from available measurements.",
    empty: "No saved version comparisons yet.", unavailable: "Could not read saved comparisons.", limited: "Limited comparability", metric: "Metric", upload: "Upload", download: "Download", direct: "direct", paired: "Paired change vs direct, %", cpu: "CLI CPU, % machine", ram: "CLI private RAM, MiB",
    rateLimit: "Sender rate capped at 64 MiB/s; three pairs per direction. This is not maximum performance.", closeIssue: "4.0.0: normal TCP close reset previously observed. This profile verifies data without waiting for FIN; a fix is not verified.",
    scope: "Different boots of one VM; background activity may differ. CPU/RAM belong to the CLI, not the driver. Original results preserved.", addition: "Added RTT vs direct, ms", rttScope: "Three pairs, 1000 measured echoes and 200 warmup echoes per run. Quantile differences are not per-packet overhead measurements.", badReports: "Some reports could not be read."
  }
};
Object.assign(labText.ru, {
  connection: "Сборки", launch: "Запуск", navigation: "Разделы лаборатории",
  openRun: "Открыть запуск", toTesting: "К тестированию", toRun: "К запуску",
  toResults: "Посмотреть результаты", changeTesting: "Изменить тестирование",
  version: "Тип ProxyBridge", buildName: "Название сборки", savedBuilds: "Сохранённые сборки",
  buildCatalogHelp: "Выбор повторно проверит файлы. Собственное имя не подтверждает совместимость новой сборки.",
  noBuilds: "Сохранённых сборок пока нет.", selectedBuild: "Выбрана", chooseBuild: "Выбрать", renameBuild: "Переименовать",
  BUILD_SELECTION_FAILED: "Не удалось выбрать сборку. Файлы могли измениться или стать недоступными.",
  BUILD_RENAME_FAILED: "Не удалось сохранить имя. Допустимо до 64 символов без переводов строк."
});
Object.assign(labText.ru, {
  resultSections: "Разделы результатов", compareResults: "Сравнение", testHistory: "История",
  selectTests: "Выберите тесты", suiteHelp: "Выбранные тесты выполняются последовательно. При ошибке очередь останавливается. Остановка дожидается текущего прогона и очистки, остальные тесты не запускаются.",
  suiteProfileHelp: "Сейчас доступна короткая проверка готовности. Длительные профили, высокая нагрузка и остальные сценарии будут подключены отдельно.",
  suitePrepared: "Набор подготовлен. Перед каждым тестом будут проверены файлы и готовность системы.", suiteProgress: "Завершено тестов", currentTest: "Текущий тест", noTestsSelected: "Отметьте хотя бы один тест.",
  SUITE_SELECTION_INVALID: "Выберите один или оба доступных теста.", SUITE_LAUNCH_NOT_CONFIRMED: "Запуск набора не подтверждён. Подробности сохранены; оставшиеся тесты не запущены.", SUITE_TEST_NOT_STARTED: "Тест не запущен: очередь остановлена. Измерений нет.", PENDING: "Ожидает запуска",
  launchHelp: "Подготовка проверяет выбранный комплект и сохраняет набор. ProxyBridge и трафик запускаются только кнопкой запуска. Приложение должно быть открыто от администратора.",
  offGroup: "ProxyBridge выключен — трафик напрямую",
  unruledGroup: "ProxyBridge работает — тестовое приложение без правила, трафик напрямую",
  proxyGroup: "ProxyBridge работает — тестовое приложение через SOCKS5",
  differenceGroup: "Разница с выключенным ProxyBridge",
  latencyP50: "Типичная задержка (p50), мс", latencyP95: "Задержка для 95% обменов (p95), мс", latencyP99: "Задержка для 99% обменов (p99), мс",
  processCpu: "CPU процесса ProxyBridge, среднее, % ПК", processRam: "Память процесса ProxyBridge, среднее, MiB",
  proxyDifference: "Через SOCKS5 минус напрямую (p95), мс", unruledDifference: "Без правила минус выключен (p95), мс",
  latencyHelp: "Задержка — время запроса и полного ответа: меньше лучше. p50 — половина ответов пришла за это время или быстрее; p95 — 95% ответов; p99 — 99%. Это TCP-обмен, не ICMP-пинг.",
  resourceHelp: "CPU и память измерены для процесса ProxyBridge (CLI вместе с Core). Память — приватная память процесса. Расходы самого драйвера и энергопотребление отдельно не измерены. CPU 0,000% означает нулевое значение выборки, а не отсутствие нагрузки.",
  differenceHelp: "Разница = задержка выбранного режима минус задержка при выключенном ProxyBridge. Плюс означает больше задержку, минус — меньше в этом замере. Малую отрицательную разницу нельзя считать ускорением: короткий замер подвержен колебаниям.",
  measurementConditions: "Условия и ограничения измерения",
  threeModesRtt: "Задержка TCP: выключен / без правила / SOCKS5",
  offMode: "Напрямую, ProxyBridge выключен", unruledMode: "Напрямую, ProxyBridge работает",
  threeModesConditions: "Три режима: по 128 измерений после 200 прогревочных, 512 байт, пауза 20 мс; один короткий цикл OFF → UNRULED → SOCKS5.",
  threeModesScope: "Проверка готовности трёх путей в фиксированном порядке. Снимок сокетов исключён из измеряемого окна. Разницы относятся к этой короткой серии и не доказывают влияние продукта при длительной или высокой нагрузке.",
  unruledAddedP95: "Без правила: добавка к RTT при выключенном ProxyBridge p95, мс",
  unruledCpu: "Без правила: CPU CLI, среднее, % ПК", unruledRam: "Без правила: Private RAM CLI, среднее, MiB",
  allBuilds: "Все сборки", allTests: "Все тесты", allStatuses: "Все статусы", runStatus: "Статус",
  latestOnlyHelp: "Последний запуск каждой сборки. Ошибки и отмена не заменяются прежним успешным результатом.",
  comparisonScope: "Текущие локальные короткие проверки. CPU/RAM относятся к процессу CLI. Это просмотр сохранённых измерений; полная сопоставимость условий между сборками пока не подтверждена.",
  rttP50: "RTT SOCKS5 p50, мс", rttP95: "RTT SOCKS5 p95, мс", rttP99: "RTT SOCKS5 p99, мс",
  directP50: "ProxyBridge выключен: RTT напрямую p50, мс", directP95: "ProxyBridge выключен: RTT напрямую p95, мс", directP99: "ProxyBridge выключен: RTT напрямую p99, мс",
  unruledP50: "ProxyBridge работает, без правила: RTT напрямую p50, мс", unruledP95: "ProxyBridge работает, без правила: RTT напрямую p95, мс", unruledP99: "ProxyBridge работает, без правила: RTT напрямую p99, мс",
  addedP95: "Добавка SOCKS5 к RTT при выключенном ProxyBridge p95, мс",
  directModesHelp: "Три режима: ProxyBridge выключен → напрямую; ProxyBridge работает, приложение вне его правил → напрямую; приложение по правилу → SOCKS5. В этой TCP-серии измерены только первый и третий режимы. Второй пока не измерен и показан как «—», не как ноль.",
  cpuMean: "CPU CLI, среднее, % ПК", ramMean: "Private RAM CLI, среднее, MiB",
  uploadRate: "Отправка SOCKS5, Мбит/с", downloadRate: "Скачивание SOCKS5, Мбит/с",
  directUpload: "ProxyBridge выключен: отправка напрямую, Мбит/с", directDownload: "ProxyBridge выключен: скачивание напрямую, Мбит/с",
  unruledUpload: "ProxyBridge работает, без правила: отправка напрямую, Мбит/с", unruledDownload: "ProxyBridge работает, без правила: скачивание напрямую, Мбит/с",
  uploadCpu: "Отправка: CPU CLI, среднее, % ПК", downloadCpu: "Скачивание: CPU CLI, среднее, % ПК",
  uploadRam: "Отправка: Private RAM CLI, среднее, MiB", downloadRam: "Скачивание: Private RAM CLI, среднее, MiB",
  latestUnavailable: "Актуальность результатов не подтверждена: часть истории запусков недоступна. Обновите данные.",
  selectComparison: "Выберите сборки и показатели для таблицы.", noMeasurements: "Нет измерений",
  conditionsDiffer: "Параметры или инструменты измерения различаются либо не подтверждены. Значения можно просмотреть рядом; разница не доказывает улучшение сборки.",
  newMeasurementRunning: "Новый запуск выполняется. Актуальные значения появятся после его завершения и проверки.",
  shortRttConditions: "Короткая проверка задержки: 128 измерений после 16 прогревочных, 512 байт, пауза 20 мс; одна пара напрямую/SOCKS5.",
  shortTransferConditions: "Короткая передача: 64 MiB на прогон, заданный темп 8 MiB/с; одна пара напрямую/SOCKS5 на направление. Не максимальная скорость.",
  historyShown: "Показано запусков", historyIncomplete: "Часть свидетельств недоступна. Неподтверждённые попытки сохранены в истории.",
  noConfirmedDetails: "Подтверждённых показателей для этой попытки нет. Она не заменяется предыдущим успешным результатом.", noHistoryMatches: "Нет запусков по выбранным фильтрам.", moreHistory: "Загрузить более ранние запуски"
});
Object.assign(labText.en, {
  connection: "Builds", launch: "Run", navigation: "Laboratory navigation",
  openRun: "Open run", toTesting: "Continue to testing", toRun: "Continue to run",
  toResults: "View results", changeTesting: "Change testing",
  version: "ProxyBridge type", buildName: "Build name", savedBuilds: "Saved builds",
  buildCatalogHelp: "Selecting re-inspects the files. A custom name does not establish compatibility of a new build.",
  noBuilds: "No saved builds yet.", selectedBuild: "Selected", chooseBuild: "Select", renameBuild: "Rename",
  BUILD_SELECTION_FAILED: "Could not select the build. Its files may have changed or become unavailable.",
  BUILD_RENAME_FAILED: "Could not save the name. Use up to 64 characters without line breaks."
});
Object.assign(labText.en, {
  resultSections: "Result sections", compareResults: "Comparison", testHistory: "History",
  selectTests: "Select tests", suiteHelp: "Selected tests run sequentially. The queue stops on failure. Stopping waits for the current run and cleanup; remaining tests are not started.",
  suiteProfileHelp: "Short readiness checks are currently available. Long profiles, high load and other scenarios will be connected separately.",
  suitePrepared: "Suite prepared. Files and runtime readiness will be checked before each test.", suiteProgress: "Tests completed", currentTest: "Current test", noTestsSelected: "Select at least one test.",
  SUITE_SELECTION_INVALID: "Select one or both available tests.", SUITE_LAUNCH_NOT_CONFIRMED: "Suite launch not confirmed. Details are retained; remaining tests were not started.", SUITE_TEST_NOT_STARTED: "Test not started: the queue stopped. No measurements.", PENDING: "Waiting to start",
  launchHelp: "Preparation checks the selected kit and saves the suite. ProxyBridge and traffic start only through the run button. Open the application as administrator.",
  offGroup: "ProxyBridge off — direct traffic",
  unruledGroup: "ProxyBridge running — test application has no matching rule, direct traffic",
  proxyGroup: "ProxyBridge running — test application routed through SOCKS5",
  differenceGroup: "Difference vs ProxyBridge off",
  latencyP50: "Typical latency (p50), ms", latencyP95: "Latency for 95% of echoes (p95), ms", latencyP99: "Latency for 99% of echoes (p99), ms",
  processCpu: "ProxyBridge process CPU, mean, % machine", processRam: "ProxyBridge process memory, mean, MiB",
  proxyDifference: "SOCKS5 minus direct (p95), ms", unruledDifference: "Unruled minus off (p95), ms",
  latencyHelp: "Latency is the time for a request and its complete reply: lower is better. p50 means half the replies arrived within this time; p95 means 95% of replies; p99 means 99%. This is a TCP exchange, not ICMP ping.",
  resourceHelp: "CPU and memory belong to the ProxyBridge process (CLI with Core). Memory is process private memory. Driver costs and power consumption are not measured separately. CPU 0.000% is a zero sample value, not proof of no load.",
  differenceHelp: "Difference = latency in the selected mode minus latency with ProxyBridge off. Positive means higher latency, negative means lower latency in this run. A small negative difference does not establish a speedup: a short run is subject to variation.",
  measurementConditions: "Measurement conditions and limits",
  threeModesRtt: "TCP RTT: off / unruled / SOCKS5",
  offMode: "Direct, ProxyBridge off", unruledMode: "Direct, ProxyBridge running",
  threeModesConditions: "Three modes: 128 measurements after 200 warmup echoes each, 512 bytes, 20 ms pause; one short OFF → UNRULED → SOCKS5 cycle.",
  threeModesScope: "Fixed-order three-path readiness check. Socket observation finishes before measurement. Differences describe this short series and do not prove product impact under prolonged or high load.",
  unruledAddedP95: "Unruled: added RTT vs ProxyBridge off p95, ms",
  unruledCpu: "Unruled: CLI CPU, mean, % machine", unruledRam: "Unruled: CLI private RAM, mean, MiB",
  allBuilds: "All builds", allTests: "All tests", allStatuses: "All statuses", runStatus: "Status",
  latestOnlyHelp: "Latest attempt for each build. Failed or cancelled attempts are not replaced with an older success.",
  comparisonScope: "Current local short checks. CPU/RAM belong to the CLI process. These are saved measurements; full comparability across builds has not been established.",
  rttP50: "SOCKS5 RTT p50, ms", rttP95: "SOCKS5 RTT p95, ms", rttP99: "SOCKS5 RTT p99, ms",
  directP50: "ProxyBridge off: direct RTT p50, ms", directP95: "ProxyBridge off: direct RTT p95, ms", directP99: "ProxyBridge off: direct RTT p99, ms",
  unruledP50: "ProxyBridge running, no matching rule: direct RTT p50, ms", unruledP95: "ProxyBridge running, no matching rule: direct RTT p95, ms", unruledP99: "ProxyBridge running, no matching rule: direct RTT p99, ms",
  addedP95: "Added SOCKS5 RTT vs ProxyBridge off p95, ms",
  directModesHelp: "Three modes: ProxyBridge off → direct; ProxyBridge running, application outside its rules → direct; application routed by a rule → SOCKS5. This TCP series measured only the first and third modes. The second has not been measured and is shown as ‘—’, not zero.",
  cpuMean: "CLI CPU, mean, % machine", ramMean: "CLI private RAM, mean, MiB",
  uploadRate: "SOCKS5 upload, Mbit/s", downloadRate: "SOCKS5 download, Mbit/s",
  directUpload: "ProxyBridge off: direct upload, Mbit/s", directDownload: "ProxyBridge off: direct download, Mbit/s",
  unruledUpload: "ProxyBridge running, no matching rule: direct upload, Mbit/s", unruledDownload: "ProxyBridge running, no matching rule: direct download, Mbit/s",
  uploadCpu: "Upload: CLI CPU, mean, % machine", downloadCpu: "Download: CLI CPU, mean, % machine",
  uploadRam: "Upload: CLI private RAM, mean, MiB", downloadRam: "Download: CLI private RAM, mean, MiB",
  latestUnavailable: "Latest results cannot be established: part of launch history is unavailable. Refresh the data.",
  selectComparison: "Select builds and metrics for the table.", noMeasurements: "No measurements",
  conditionsDiffer: "Measurement parameters or tools differ or are unconfirmed. Values may be viewed side by side; a difference does not prove a build improvement.",
  newMeasurementRunning: "A new run is active. Current values will appear after completion and verification.",
  shortRttConditions: "Short RTT check: 128 measurements after 16 warmup echoes, 512 bytes, 20 ms pause; one direct/SOCKS5 pair.",
  shortTransferConditions: "Short transfer: 64 MiB per run, configured 8 MiB/s rate cap; one direct/SOCKS5 pair per direction. Not maximum throughput.",
  historyShown: "Runs shown", historyIncomplete: "Some evidence is unavailable. Unconfirmed attempts remain in history.",
  noConfirmedDetails: "No confirmed metrics for this attempt. It is not replaced with a previous successful result.", noHistoryMatches: "No runs match the selected filters.", moreHistory: "Load earlier runs"
});
let labLanguage = localStorage.getItem("testlab-language") === "en" ? "en" : "ru";
let labState = { csrf: "", builds: [], buildError: null, reports: [], localRuns: [], localTransfers: [], transferUnreadable: 0, localUnreadable: 0, observation: null, saved: false, unreadable: 0, plan: null, planFailed: false, runControl: { administrator: false, run: null }, runError: null };
labState.launches = [];
labState.launchUnreadable = 0;
labState.launchNextOffset = null;
labState.resultsUnavailable = false;
labState.localConnections = [];
labState.connectionUnreadable = 0;
let inspectedInput = null;
let labActionActive = false;
let runPollTimer = null;
let runPollActive = false;
const lab = (id) => document.getElementById(id);
const t = (key) => labText[labLanguage][key];
const html = (value) => String(value ?? "").replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;").replaceAll("'", "&#39;");
const number = (value, digits = 2) => typeof value === "number" && Number.isFinite(value) ? value.toLocaleString(labLanguage, { minimumFractionDigits: digits, maximumFractionDigits: digits }) : "—";
const runActive = () => !!labState.runControl.run && !labState.runControl.run.terminal || !!labState.runControl.suite && !labState.runControl.suite.terminal;
const testTitle = scenario => t({ tcp_rtt: "rtt", tcp_transfer: "transfer", tcp_rtt_three_modes: "threeModesRtt", tcp_connections: "connectionsTest", tcp_loaded_rtt: "loadedRtt", udp_echo: "udp" }[scenario]) || t("scenario");
Object.assign(labText.ru, {
  duration: "Длительность", load: "Нагрузка", SHORT: "Быстро", NORMAL: "Обычно", LONG: "Долго", LOW: "Низкая", HIGH: "Высокая",
  WORKLOAD: "Выбранный профиль", legacyWorkload: "Прежние короткие проверки",
  perConnectionMiB: "Объём на соединение, MiB", senderLimit: "Лимит отправителя, MiB/с", measurementsPerPath: "Измерений на путь", pauseAfterReply: "Пауза после ответа, мс",
  suiteProfileHelp: "Длительность и нагрузка задаются отдельно для каждого теста. В тесте «Три режима» все три пути получают одинаковые условия.",
  transferPresetHelp: "Данные проверяются полностью. Закрытие TCP не проверяется; это не максимальная скорость.",
  rttPresetHelp: "1000 прогревочных обменов исключены. Нагрузка — интенсивность запросов, без фоновой передачи.",
  approximateMinutes: "Примерно {range} мин", selectedTime: "Выбрано тестов: {count} · Общее время: примерно {range} мин",
  estimateHelp: "Оценка включает все прогоны и подготовку. Фактическое время зависит от задержки и планировщика Windows.",
  workloadScope: "Профиль задаёт объём обмена и интенсивность. Время зависит от задержки и планировщика Windows. CPU/RAM относятся к процессу ProxyBridge; память драйвера и ватты не измеряются.",
  LAB_WORKLOAD_INVALID: "Настройки профиля недопустимы. Подготовьте новый набор.",
  comparisonScope: "Сохранённые локальные измерения при выбранных условиях. CPU/RAM относятся к процессу CLI; полная сопоставимость машин и условий между сборками отдельно не подтверждена.",
  directModesHelp: "Сравнение напрямую при выключенном ProxyBridge и через SOCKS5. Влияние приложения вне правил проверяется отдельным тестом «Три режима».",
  SUITE_SELECTION_INVALID: "Выберите доступные тесты и настройки для каждого."
});
Object.assign(labText.ru, {
  connectionsTest: "Соединения TCP: нагрузка и восстановление", connectionLevels: "Уровни нагрузки", connectionHold: "Примерное время передачи на уровне, с",
  connectionPresetHelp: "Проверяемая передача по каждому соединению, лимит 64 KiB/с. До нагрузки и после неё — по 4 соединения. Восстановление без перезапуска ProxyBridge. RTT здесь не измеряется.",
  connectionScope: "Это поведение при подтверждённом числе соединений. Занятость внутренней таблицы не измеряется; достижение уровня не доказывает её переполнение или максимальную ёмкость.",
  connectionPhase: "Фаза", requestedConnections: "Запрошено соединений", confirmedConnections: "Подтверждено одновременно", successfulConnections: "Передачи без ошибок",
  baseline: "До нагрузки", connectionLoadPhase: "Нагрузка", recovery: "После нагрузки", recoveryConnections: "Соединений после нагрузки, SOCKS5", connectionDirect: "Одновременно напрямую", connectionProxy: "Одновременно через SOCKS5", connectionCpu: "CPU ProxyBridge на верхнем уровне, % ПК", connectionRam: "Память ProxyBridge на верхнем уровне, MiB"
});
Object.assign(labText.en, {
  duration: "Duration", load: "Load", SHORT: "Quick", NORMAL: "Normal", LONG: "Long", LOW: "Low", HIGH: "High",
  WORKLOAD: "Selected workload", legacyWorkload: "Earlier short checks",
  perConnectionMiB: "Volume per connection, MiB", senderLimit: "Sender cap, MiB/s", measurementsPerPath: "Measurements per path", pauseAfterReply: "Pause after reply, ms",
  suiteProfileHelp: "Duration and load are independent for each test. All three paths in the separate Three modes test use identical settings.",
  transferPresetHelp: "Data fully verified. TCP close is not tested; not maximum throughput.",
  rttPresetHelp: "1000 warmup echoes excluded. Load means request intensity, without background transfer.",
  approximateMinutes: "About {range} min", selectedTime: "Tests selected: {count} · Total time: about {range} min",
  estimateHelp: "Estimate includes all runs and setup. Actual time depends on latency and Windows scheduling.",
  workloadScope: "The profile defines exchange volume and intensity. Elapsed time depends on latency and Windows scheduling. CPU/RAM refer to the ProxyBridge process; driver memory and watts are not measured.",
  LAB_WORKLOAD_INVALID: "Invalid workload settings. Prepare a new suite.",
  comparisonScope: "Saved local measurements for selected conditions. CPU/RAM refer to the CLI process; full machine and condition comparability across builds is not separately established.",
  directModesHelp: "Direct traffic with ProxyBridge off versus SOCKS5. Unruled application overhead is measured in the separate Three modes test.",
  SUITE_SELECTION_INVALID: "Select supported tests and settings for each."
});
Object.assign(labText.en, {
  connectionsTest: "TCP connections: load and recovery", connectionLevels: "Load levels", connectionHold: "Approximate transfer time per level, seconds",
  connectionPresetHelp: "Verified data per connection, capped at 64 KiB/s. Four connections before and after load. Recovery without restarting ProxyBridge. RTT is not measured here.",
  connectionScope: "Behavior at a confirmed connection count. Internal table occupancy is not measured; reaching a level does not establish overflow or maximum capacity.",
  connectionPhase: "Phase", requestedConnections: "Requested connections", confirmedConnections: "Confirmed simultaneous", successfulConnections: "Error-free transfers",
  baseline: "Before load", connectionLoadPhase: "Load", recovery: "After load", recoveryConnections: "Connections after load, SOCKS5", connectionDirect: "Simultaneous direct connections", connectionProxy: "Simultaneous SOCKS5 connections", connectionCpu: "ProxyBridge CPU at highest level, % machine", connectionRam: "ProxyBridge memory at highest level, MiB"
});
function selectedWorkloads() {
  return selectedTests().map(scenario => ({ scenario,
    duration: document.querySelector(`[data-test-duration="${scenario}"]`).value,
    load: document.querySelector(`[data-test-load="${scenario}"]`).value }));
}
function workloadName(preset) { return preset ? `${t(preset.duration)} · ${t(preset.load)}` : t("legacyWorkload"); }
function workloadMinutes(scenario, preset) {
  if (scenario === "tcp_connections") return preset.duration === "LONG" ? [15,25] : preset.duration === "NORMAL" ? [5,10] : [3,6];
  const three = scenario === "tcp_rtt_three_modes";
  return preset.duration === "LONG" ? (three ? [8,15] : [6,12]) : preset.duration === "NORMAL" ? (three ? [4,7] : [3,6]) : (three ? [2,4] : [1,4]);
}
function workloadDescription(scenario, preset) {
  if (!preset) return "";
  if (scenario === "tcp_connections") return `${t("connectionLevels")}: ${preset.load === "HIGH" ? "64 → 256 → 640" : "8 → 32 → 64"}. ${t("connectionHold")}: ${{SHORT:8,NORMAL:32,LONG:120}[preset.duration]}. ${t("connectionPresetHelp")}`;
  const seconds = { SHORT: 8, NORMAL: 32, LONG: 120 }[preset.duration];
  const rate = preset.load === "HIGH" ? 64 : 8;
  const echoes = { SHORT: [128,256], NORMAL: [1500,3000], LONG: [6000,12000] }[preset.duration][preset.load === "HIGH" ? 1 : 0];
  return scenario === "tcp_transfer" ? `${t("perConnectionMiB")}: ${seconds * rate}; ${t("senderLimit")}: ${rate}. ${t("transferPresetHelp")}` : `${t("measurementsPerPath")}: ${echoes}; ${t("pauseAfterReply")}: ${preset.load === "HIGH" ? 10 : 20}. ${t("rttPresetHelp")}`;
}
function selectedTests() { return [...document.querySelectorAll("[data-lab-test]:checked")].map(node => node.dataset.labTest); }
function setSelectedTests(tests) { document.querySelectorAll("[data-lab-test]").forEach(node => { node.checked = tests.includes(node.dataset.labTest); }); }
function visibleSuite() {
  const { suite, run } = labState.runControl;
  return suite && (!run || suite.tests.some(test => test.planId === run.planId) || new Date(suite.startedAtUtc) >= new Date(run.startedAtUtc)) ? suite : null;
}
const labPages = { builds: "connection", testing: "testing", run: "launch", results: "results" };
const legacyLabPages = { connection: "builds", testing: "testing", launch: "run", results: "results" };
function pageFromUrl() {
  const url = new URL(location.href);
  const requested = url.searchParams.get("page");
  const legacy = url.hash.slice(1);
  return Object.hasOwn(labPages, requested) ? requested : Object.hasOwn(legacyLabPages, legacy) ? legacyLabPages[legacy] : "builds";
}
let labPage = pageFromUrl();
function renderLabPage() {
  document.querySelectorAll("[data-lab-view]").forEach(node => { node.hidden = node.dataset.labView !== labPage; });
  document.querySelectorAll("[data-lab-page]").forEach(node => {
    if (node.closest("nav") && node.dataset.labPage === labPage) node.setAttribute("aria-current", "page");
    else node.removeAttribute("aria-current");
  });
  document.querySelectorAll("[data-i18n-aria]").forEach(node => { node.setAttribute("aria-label", t(node.dataset.i18nAria)); });
  document.title = `${t(labPages[labPage])} · ProxyBridge TestLab`;
  renderResultViews();
}
function navigateLab(page, push = true, focus = true) {
  if (!Object.hasOwn(labPages, page)) return;
  const changed = labPage !== page;
  labPage = page;
  const url = new URL(location.href);
  url.searchParams.set("page", page);
  url.hash = "";
  if (push && changed) history.pushState(null, "", url);
  else if (!push) history.replaceState(null, "", url);
  renderLabPage();
  if (focus) {
    document.querySelector(`[data-lab-view="${page}"] h2`).focus({ preventScroll: true });
    window.scrollTo(0, 0);
  }
}
function restoreTestingChoice() {
  try {
    const choice = JSON.parse(sessionStorage.getItem("testlab-testing-choice") || "null");
    for (const [id, value] of [["lab-mode", choice?.mode]])
      if (Array.from(lab(id).options).some(option => option.value === value)) lab(id).value = value;
    if (Array.isArray(choice?.scenarios)) setSelectedTests(choice.scenarios);
    for (const setting of choice?.tests || []) {
      for (const [field, attribute, allowed] of [["duration", "data-test-duration", ["SHORT","NORMAL","LONG"]], ["load", "data-test-load", ["LOW","HIGH"]]]) {
        const node = [...document.querySelectorAll(`[${attribute}]`)].find(node => node.getAttribute(attribute) === setting.scenario);
        if (node && allowed.includes(setting[field])) node.value = setting[field];
      }
    }
    if (!Array.isArray(choice?.scenarios) && ["tcp_rtt", "tcp_transfer"].includes(choice?.scenario)) setSelectedTests([choice.scenario]);
  } catch { /* Storage is optional; keep the supported defaults. */ }
}
function saveTestingChoice() {
  try { sessionStorage.setItem("testlab-testing-choice", JSON.stringify({ mode: lab("lab-mode").value, scenarios: selectedTests(), tests: selectedWorkloads() })); }
  catch { /* Navigation still preserves the in-memory choice. */ }
}
function acceptRunControl(control) {
  const previousSuite = labState.runControl.suite, nextSuite = control.suite;
  if (Object.hasOwn(control, "suite") && (!previousSuite || !nextSuite ||
    (previousSuite.planId === nextSuite.planId ? new Date(nextSuite.updatedAtUtc) >= new Date(previousSuite.updatedAtUtc) && !(previousSuite.terminal && !nextSuite.terminal) : new Date(nextSuite.startedAtUtc) >= new Date(previousSuite.startedAtUtc)))) labState.runControl.suite = nextSuite;
  const current = labState.runControl.run, incoming = control.run;
  if (typeof control.administrator === "boolean") labState.runControl.administrator = control.administrator;
  if (current && incoming && (incoming.planId === current.planId
    ? new Date(incoming.updatedAtUtc) < new Date(current.updatedAtUtc) || current.terminal && !incoming.terminal
    : new Date(incoming.startedAtUtc) < new Date(current.startedAtUtc))) return;
  labState.runControl.run = incoming;
}

function selectionInput() {
  return { installationDirectory: lab("product-folder").value.trim(), contract: lab("product-contract").value,
    driverPath: lab("product-contract").value === "driver" ? lab("product-driver-path").value.trim() || null : null,
    displayName: lab("product-build-name").value.trim() || null };
}

function renderWorkloadCards(busy) {
  document.querySelectorAll("[data-lab-test], [data-test-duration], [data-test-load]").forEach(node => { node.disabled = busy; });
  document.querySelectorAll("[data-workload-description]").forEach(node => {
    const scenario = node.dataset.workloadDescription;
    const checkbox = document.querySelector(`[data-lab-test="${scenario}"]`);
    const duration = document.querySelector(`[data-test-duration="${scenario}"]`);
    const load = document.querySelector(`[data-test-load="${scenario}"]`);
    const preset = {duration: duration.value, load: load.value};
    const card = node.closest(".lab-test-card");
    card.classList.toggle("is-selected", checkbox.checked);
    card.querySelector(".lab-test-settings").hidden = !checkbox.checked;
    duration.disabled = load.disabled = busy || !checkbox.checked;
    node.hidden = !checkbox.checked;
    node.textContent = workloadDescription(scenario, preset);
    const time = card.querySelector("[data-workload-time]");
    time.textContent = t("approximateMinutes").replace("{range}", workloadMinutes(scenario, preset).join("–"));
    time.title = t("estimateHelp");
  });
  const choices = selectedWorkloads();
  const total = choices.reduce((sum, choice) => { const minutes = workloadMinutes(choice.scenario, choice); return [sum[0]+minutes[0], sum[1]+minutes[1]]; }, [0,0]);
  lab("lab-testing-time").textContent = choices.length ? t("selectedTime").replace("{count}", choices.length).replace("{range}", total.join("–")) : t("noTestsSelected");
  lab("lab-testing-time").title = t("estimateHelp");
}
function renderLab() {
  document.documentElement.lang = labLanguage;
  lab("lab-language").value = labLanguage;
  document.querySelectorAll("[data-i18n]").forEach((node) => { node.textContent = t(node.dataset.i18n); });
  renderLabPage();
  lab("driver-path-label").hidden = lab("product-contract").value !== "driver";
  const observation = labState.observation;
  const busy = labActionActive || runActive() || remoteActionActive || !!remoteState?.busy;
  renderRemote(busy);
  const message = { KNOWN_BENCHMARK_FILES: "known", FILES_OBSERVED_COMPATIBILITY_PENDING: "pending", FILES_INCOMPLETE: "incomplete", FILES_UNREADABLE: "unreadable", UNSUPPORTED_BEFORE_4_0_0: "old" }[observation?.status];
  lab("product-selection-status").textContent = observation ? `${observation.display_name || observation.product_label} (${observation.product_label}): ${t(message || "failed")} ${labState.saved ? t("saved") : ""}` : t("noSelection");
  lab("product-selection-details").hidden = !observation;
  lab("product-selection-json").textContent = observation ? JSON.stringify(observation, null, 2) : "";
  if (observation && labState.saved) lab("product-selection-json").textContent = `${t("savedObservation")}\n${lab("product-selection-json").textContent}`;
  lab("inspect-product").disabled = !labState.csrf || busy;
  lab("save-product-selection").disabled = busy || !inspectedInput || !observation?.files_observed || observation.status === "UNSUPPORTED_BEFORE_4_0_0";
  lab("refresh-lab").disabled = labActionActive;
  for (const id of ["product-folder", "product-contract", "product-driver-path", "product-build-name"]) lab(id).disabled = busy;
  lab("lab-builds").innerHTML = labState.builds.length ? labState.builds.map(build => `<div class="lab-build-row" data-build-id="${html(build.id)}">
    <div><strong>${html(build.display_name)}</strong> · ${html(build.contract)}${build.id === observation?.build_id && labState.saved ? ` · ${t("selectedBuild")}` : ""}<small>${html(new Date(build.observed_at_utc).toLocaleString(labLanguage))}</small></div>
    <div class="lab-build-actions"><button type="button" class="button secondary" data-build-action="select" ${busy || !labState.csrf ? "disabled" : ""}>${t("chooseBuild")}</button>
    <label><span class="lab-visually-hidden">${t("buildName")}</span><input type="text" maxlength="64" data-build-name value="${html(build.display_name)}" ${busy ? "disabled" : ""}></label>
    <button type="button" class="button secondary" data-build-action="rename" ${busy || !labState.csrf ? "disabled" : ""}>${t("renameBuild")}</button></div></div>`).join("") : `<p>${t("noBuilds")}</p>`;
  lab("lab-build-error").textContent = labState.buildError ? t(labState.buildError) : "";
  lab("lab-build-error").hidden = !labState.buildError;
  lab("lab-launch-status").textContent = t(lab("lab-mode").value === "local" ? "manualLocal" : "manualRemote");
  lab("prepare-lab-launch").disabled = busy || !labState.csrf || !labState.saved || !selectedTests().length;
  lab("lab-mode").disabled = busy;
  renderWorkloadCards(busy);
  renderSavedSuites(busy);
  const plan = labState.plan;
  const run = labState.runControl.run;
  const suite = visibleSuite();
  const guiPlan = plan?.status === "PLAN_PREPARED" && plan.gui_launch_supported;
  lab("start-lab-run").hidden = !guiPlan;
  lab("start-lab-run").disabled = busy || labState.runError === "pollFailed" || !labState.csrf || !labState.runControl.administrator || !guiPlan || run?.planId === plan?.plan_id || suite?.planId === plan?.plan_id;
  lab("stop-lab-run").hidden = !runActive();
  lab("stop-lab-run").disabled = labActionActive || !labState.csrf || !runActive() || (suite && !suite.terminal ? suite.cancellationRequested : run?.cancellationRequested);
  lab("lab-run-help").textContent = guiPlan || runActive() ? t(labState.runControl.administrator ? "runHelp" : "adminHelp") : plan?.status === "PLAN_PREPARED" ? t("manualHelp") : "";
  const stopNote = run?.cancellationRequested ? !run.terminal ? t("stoppingHelp") : run.status === "COMPLETED" ? t("completedAfterStop") : "" : "";
  lab("lab-run-status").textContent = run ? `${t(run.status) || t("FAILED")}. ${t("progress")}: ${number(run.completedRuns, 0)}/${number(run.totalRuns, 0)}${run.currentDirection ? ` · ${t(run.currentDirection === "push" ? "upload" : "download")}` : ""}${run.currentMode ? ` · ${run.currentMode === "OFF" ? t("direct") : "SOCKS5"}` : ""}. ${stopNote}${run.reason ? t(run.reason) || t("WRAPPER_OR_EVIDENCE_NOT_CONFIRMED") : ""}` : "";
  if (suite) {
    const childStatus = !suite.terminal && run && suite.tests[suite.currentTest - 1]?.planId === run.planId ? ` · ${t("progress")}: ${number(run.completedRuns, 0)}/${number(run.totalRuns, 0)}${run.currentDirection ? ` · ${t(run.currentDirection === "push" ? "upload" : "download")}` : ""}${run.currentMode ? ` · ${run.currentMode === "OFF" ? t("direct") : "SOCKS5"}` : ""}` : "";
    lab("lab-run-status").textContent = `${t(suite.status) || t("FAILED")}. ${t("suiteProgress")}: ${suite.completedTests}/${suite.tests.length}${!suite.terminal && suite.currentTest ? ` · ${t("currentTest")}: ${testTitle(suite.tests[suite.currentTest - 1].scenario)}` : ""}${childStatus}. ${suite.reason ? t(suite.reason) || t("SUITE_LAUNCH_NOT_CONFIRMED") : ""}${suite.cancellationRequested && !suite.terminal ? t("stoppingHelp") : ""}`;
  }
  lab("lab-run-error").textContent = labState.runError ? t(labState.runError) || t("GUI_RUN_NOT_STARTED") : "";
  lab("lab-global-run").hidden = !runActive() && labState.runError !== "pollFailed";
  lab("lab-global-run-status").textContent = labState.runError === "pollFailed" ? t("pollFailed") : lab("lab-run-status").textContent;
  lab("lab-selection-required").hidden = labState.saved;
  const summaryTests = runActive() && suite ? suite.tests.map(test => test.scenario) : runActive() && run?.scenario ? [run.scenario] : selectedTests();
  lab("lab-launch-summary").textContent = `${runActive() && (suite?.buildName || run?.buildName) || plan?.build_name || (labState.saved ? labState.observation.display_name || labState.observation.product_label : t("noSelection"))} · ${t(lab("lab-mode").value === "local" ? "local" : "remote")} · ${summaryTests.length ? summaryTests.map(scenario => {
    const choice = runActive() && suite ? suite.tests.find(test => test.scenario === scenario) : plan?.suite ? plan.tests.find(test => test.scenario === scenario) : selectedWorkloads().find(test => test.scenario === scenario);
    return testTitle(scenario) + (choice?.duration ? ` (${workloadName(choice)})` : "");
  }).join(" → ") : t("noTestsSelected")}`;
  lab("lab-plan-command-block").hidden = plan?.status !== "PLAN_PREPARED" || !plan.command;
  lab("lab-plan-command").textContent = plan?.status === "PLAN_PREPARED" ? plan.command || "" : "";
  lab("lab-plan-status").textContent = labState.planFailed ? t("planFailed") :
    plan?.status === "PLAN_PREPARED" ? `${t(plan.suite ? "suitePrepared" : "planPrepared")} ${t(plan.profile) || plan.profile}. ${t("planMinutes")}: ${plan.estimated_minutes}.` :
    plan?.status === "PLAN_BLOCKED" ? t(plan.reason) || t("planFailed") : "";
  lab("scenario-description").textContent = selectedTests().length ? selectedTests().map(scenario => t(scenario === "tcp_connections" ? "connectionScope" : scenario === "tcp_transfer" ? "transferHelp" : "rttHelp")).join(" ") : t("noTestsSelected");
  lab("lab-reports").innerHTML = labState.reports.length ? labState.reports.map(reportMarkup).join("") : `<p>${t("empty")}</p>`;
  if (labState.unreadable) lab("lab-reports").insertAdjacentHTML("beforeend", `<p>${t("badReports")}</p>`);
  renderSavedResults();
}

function reportBuildName(run) {
  const name = run.build?.name_at_run || labState.builds.find(build => build.id === run.build?.id)?.display_name;
  return name && name !== run.contract ? `${name} (${run.contract})` : run.contract;
}

function localRunMarkup(run) {
  const threeModes = run.scenario === "tcp_rtt_three_modes";
  const title = `<h3>${t(threeModes ? "threeModesRtt" : "rtt")} · ${html(reportBuildName(run))} · ${html(run.workload_preset ? workloadName(run.workload_preset) : run.profile)}</h3>`;
  const stamp = `<p>${html(new Date(run.created_at_utc).toLocaleString(labLanguage))}</p>`;
  if (run.correctness !== "PASS" || !run.mode_metrics)
    return `<article class="lab-report">${title}${stamp}<p>${run.status === "CANCELLED" ? t("cancelledHistory") : t("localNotConfirmed")}</p></article>`;
  const rows = ["p50_ms", "p95_ms", "p99_ms", "max_ms"].map(key =>
    `<tr><th>${key === "max_ms" ? t("maximum") : key.replace("_ms", "")}, ${t("milliseconds")}</th><td>${number(run.mode_metrics.off[key], 3)}</td>${threeModes ? `<td>${number(run.mode_metrics.unruled[key], 3)}</td>` : ""}<td>${number(run.mode_metrics.proxy[key], 3)}</td><td>${key === "max_ms" ? "—" : number(run.paired_addition_ms[key], 3)}</td></tr>`).join("");
  return `<article class="lab-report">${title}${stamp}<p>${t("localPass")} · ${t("limited")}</p>
    <div class="lab-table-scroll"><table><thead><tr><th>${t("metric")}</th><th>${threeModes ? t("offMode") : t("direct")}</th>${threeModes ? `<th>${t("unruledMode")}</th>` : ""}<th>SOCKS5</th><th>${t("addition")}</th></tr></thead><tbody>${rows}</tbody></table></div>
    <p>${t("verified")}: ${number(run.verified_echoes, 0)}; ${t("measured")}: ${number(run.measured_echoes, 0)}; ${t("exchangeErrors")}: ${number(run.failed_echoes, 0)}.</p><p>${run.workload_preset ? html(workloadDescription(run.scenario, run.workload_preset)) : t(threeModes ? "threeModesScope" : "localRttScope")}</p></article>`;
}

function localTransferMarkup(run) {
  const title = `<h3>${t("transfer")} · ${html(reportBuildName(run))} · ${html(run.workload_preset ? workloadName(run.workload_preset) : run.profile)}</h3>`;
  const stamp = `<p>${html(new Date(run.created_at_utc).toLocaleString(labLanguage))}</p>`;
  if (run.correctness !== "PASS" || !run.direction_metrics)
    return `<article class="lab-report">${title}${stamp}<p>${run.status === "CANCELLED" ? t("cancelledHistory") : t("localNotConfirmed")}</p></article>`;
  const directions = ["push", "pull"].map(direction => {
    const metrics = run.direction_metrics[direction];
    return `<h4>${t(direction === "push" ? "upload" : "download")}</h4>
      <div class="lab-table-scroll"><table><thead><tr><th>${t("metric")}</th><th>${t("direct")}</th><th>SOCKS5</th></tr></thead><tbody>
      <tr><th>${t("transferRate")}</th><td>${number(metrics.off_mbit_per_s)}</td><td>${number(metrics.proxy_mbit_per_s)}</td></tr>
      <tr><th>${t("transferChange")}</th><td>—</td><td>${number(metrics.change_pct, 3)}</td></tr>
      <tr><th>${t("cpu")}</th><td>—</td><td>${number(metrics.cli_cpu_pct_machine, 3)}</td></tr>
      <tr><th>${t("ram")}</th><td>—</td><td>${number(metrics.cli_private_mib)}</td></tr>
      </tbody></table></div>`;
  }).join("");
  return `<article class="lab-report">${title}${stamp}<p>${t("localPass")} · ${t("limited")}</p>${directions}<p>${t("verifiedVolume")}: ${number(run.verified_payload_bytes / 1048576, 0)}.</p><p>${run.workload_preset ? html(workloadDescription(run.scenario, run.workload_preset)) : t("transferLocalScope")}</p></article>`;
}

function localConnectionMarkup(run) {
  const title = `<h3>${t("connectionsTest")} · ${html(reportBuildName(run))} · ${html(workloadName(run.workload_preset))}</h3>`;
  const stamp = `<p>${html(new Date(run.created_at_utc).toLocaleString(labLanguage))}</p>`;
  if (run.correctness !== "PASS" || !run.modes?.length)
    return `<article class="lab-report">${title}${stamp}<p>${run.status === "CANCELLED" ? t("cancelledHistory") : t("localNotConfirmed")}</p></article>`;
  const tables = run.modes.map(mode => `<h4>${t(mode.mode === "OFF" ? "connectionDirect" : "connectionProxy")}</h4>
    <div class="lab-table-scroll"><table><thead><tr>${["connectionPhase","requestedConnections","confirmedConnections","successfulConnections","processCpu","processRam"].map(key => `<th>${t(key)}</th>`).join("")}</tr></thead><tbody>${mode.cohorts.map(cohort => `<tr><th>${t(cohort.phase === "load" ? "connectionLoadPhase" : cohort.phase)}</th><td>${number(cohort.requested_connections,0)}</td><td>${number(cohort.confirmed_connections,0)}</td><td>${number(cohort.successful_connections,0)}</td><td>${number(cohort.cpu_pct_machine_mean,3)}</td><td>${number(cohort.private_mib_mean,2)}</td></tr>`).join("")}</tbody></table></div>`).join("");
  return `<article class="lab-report">${title}${stamp}<p>${t("localPass")} · ${t("limited")}</p>${tables}<p>${html(workloadDescription(run.scenario,run.workload_preset))}</p><p>${t("connectionScope")}</p></article>`;
}

function reportMarkup(report) {
  let rows = "";
  const row = (label, left, right, digits = 2) => `<tr><td>${html(label)}</td><td>${number(left, digits)}</td><td>${number(right, digits)}</td></tr>`;
  if (report.kind === "tcp_transfer") {
    for (const direction of ["push", "pull"]) {
      const label = t(direction === "push" ? "upload" : "download");
      const left = report.legacy_metrics[direction], right = report.driver_metrics[direction];
      rows += row(`${label}, ${t("direct")}, Mbit/s`, left.mode_medians.off, right.mode_medians.off);
      rows += row(`${label}, SOCKS5, Mbit/s`, left.mode_medians.proxy, right.mode_medians.proxy);
      rows += row(`${label}, ${t("paired")}`, left.paired_change_pct_median, right.paired_change_pct_median, 3);
      rows += row(`${label}, ${t("cpu")}`, left.cli.cpu_pct_machine_mean, right.cli.cpu_pct_machine_mean, 3);
      rows += row(`${label}, ${t("ram")}`, left.cli.private_mib_mean, right.cli.private_mib_mean);
    }
  } else {
    for (const key of ["p50_ms", "p95_ms", "p99_ms"]) rows += row(`${t("addition")}, ${key.slice(0, 3)}`, report.legacy_metrics[key], report.driver_metrics[key], 3);
  }
  return `<article class="lab-report"><h3>${t(report.kind === "tcp_transfer" ? "transfer" : "rtt")}</h3><p>${t("limited")} · ${html(new Date(report.created_at_utc).toLocaleString(labLanguage))}</p>
    <div class="lab-table-scroll"><table><thead><tr><th>${t("metric")}</th><th>4.0.0</th><th>driver</th></tr></thead><tbody>${rows}</tbody></table></div>
    <p>${t(report.kind === "tcp_transfer" ? "rateLimit" : "rttScope")}</p>${report.kind === "tcp_transfer" ? `<p class="lab-warning">${t("closeIssue")}</p>` : ""}<p>${t("scope")}</p></article>`;
}

async function loadLab() {
  if (labActionActive) return;
  labActionActive = true;
  let loadFailed = false;
  renderLab();
  try {
    const response = await fetch("/api/v1/lab/state", { cache: "no-store", signal: AbortSignal.timeout(15000) });
    if (!response.ok) throw new Error("state");
    const data = await response.json();
    labState.csrf = data.csrf_token;
    await loadSavedSuites();
    await loadRemote();
    labState.builds = data.builds?.items || [];
    labState.launches = data.launch_history?.items || [];
    labState.launchNextOffset = data.launch_history?.next_offset ?? null;
    labState.launchUnreadable = data.launch_history?.unreadable || 0;
    labState.resultsUnavailable = false;
    resetResultCache();
    acceptRunControl(data.run_control || { administrator: false, run: null });
    labState.runError = null;
    const keepPlan = labState.saved && data.selection?.bundle_sha256 &&
      data.selection.bundle_sha256 === labState.observation?.bundle_sha256 &&
      data.selection.declared_contract === labState.observation?.declared_contract;
    labState.observation = data.selection;
    labState.saved = !!data.selection;
    labState.reports = data.reports.items;
    labState.localRuns = data.local_runs?.items || [];
    labState.localTransfers = data.local_transfers?.items || [];
    labState.localConnections = data.local_connections?.items || [];
    labState.connectionUnreadable = data.local_connections?.unreadable || 0;
    labState.transferUnreadable = data.local_transfers?.unreadable || 0;
    labState.localUnreadable = data.local_runs?.unreadable || 0;
    labState.unreadable = data.reports.unreadable;
    if (!keepPlan) { labState.plan = null; labState.planFailed = false; }
    inspectedInput = null;
    if (data.selection) {
      lab("product-contract").value = data.selection.declared_contract;
      lab("product-build-name").value = data.selection.display_name || "";
    }
    const activeSuite = visibleSuite(), activeScenario = labState.runControl.run?.scenario;
    if (runActive()) {
      lab("lab-mode").value = "local";
      setSelectedTests(activeSuite ? activeSuite.tests.map(test => test.scenario) : [activeScenario]);
      saveTestingChoice();
    }
    renderLab();
  } catch { loadFailed = true; labState.resultsUnavailable = true; }
  finally {
    labActionActive = false;
    renderLab();
    if (loadFailed) {
      labState.runError = "pollFailed";
      renderLab();
      lab("lab-reports").textContent = t("unavailable");
    }
    scheduleRunPoll();
  }
}

async function inspectSelection(save = false) {
  if (labActionActive || runActive()) return;
  let inspectionFailed = false;
  const button = lab(save ? "save-product-selection" : "inspect-product");
  const request = selectionInput();
  if (save && JSON.stringify(request) !== inspectedInput) return;
  labActionActive = true;
  labState.plan = null;
  labState.planFailed = false;
  renderLab();
  lab("refresh-lab").disabled = true;
  for (const id of ["product-folder", "product-contract", "product-driver-path"]) lab(id).disabled = true;
  lab("inspect-product").disabled = true;
  lab("save-product-selection").disabled = true;
  button.textContent = t("checking");
  try {
    const response = await fetch(`/api/v1/lab/${save ? "select" : "inspect"}`, { method: "POST",
      headers: { "Content-Type": "application/json", "X-TestLab-CSRF": labState.csrf }, body: JSON.stringify(request) });
    if (!response.ok) throw new Error("inspection");
    const observation = await response.json();
    if (JSON.stringify(selectionInput()) !== JSON.stringify(request)) return;
    labState.observation = observation;
    labState.saved = save;
    inspectedInput = save ? null : JSON.stringify(request);
    renderLab();
  } catch {
    inspectionFailed = true;
    inspectedInput = null;
    renderLab();
    lab("product-selection-status").textContent = t("failed");
  } finally {
    labActionActive = false;
    lab("inspect-product").disabled = !labState.csrf;
    lab("save-product-selection").disabled = !inspectedInput || !labState.observation?.files_observed || labState.observation.status === "UNSUPPORTED_BEFORE_4_0_0";
    lab("refresh-lab").disabled = false;
    for (const id of ["product-folder", "product-contract", "product-driver-path"]) lab(id).disabled = false;
    button.textContent = t(save ? "select" : "inspect");
    renderLab();
    if (inspectionFailed) lab("product-selection-status").textContent = t("failed");
    else if (save) await loadLab();
  }
}

async function changeBuild(action, id, name) {
  if (labActionActive || runActive() || !labState.csrf) return;
  labActionActive = true;
  labState.buildError = null;
  labState.plan = null;
  labState.planFailed = false;
  renderLab();
  try {
    const response = await fetch(`/api/v1/lab/build/${action}`, { method: "POST",
      headers: { "Content-Type": "application/json", "X-TestLab-CSRF": labState.csrf },
      body: JSON.stringify({ buildId: id, displayName: name }) });
    if (!response.ok) throw new Error("build");
    if (action === "select") {
      labState.observation = await response.json();
      labState.saved = true;
      inspectedInput = null;
      lab("product-folder").value = "";
      lab("product-driver-path").value = "";
    }
  } catch {
    labState.buildError = action === "select" ? "BUILD_SELECTION_FAILED" : "BUILD_RENAME_FAILED";
    if (action === "select") { labState.saved = false; labState.observation = null; inspectedInput = null; }
  }
  finally { labActionActive = false; renderLab(); }
  if (!labState.buildError) await loadLab();
}

async function prepareLabLaunch() {
  if (labActionActive || runActive() || !labState.saved || !selectedTests().length) return;
  labActionActive = true;
  labState.plan = null;
  labState.planFailed = false;
  renderLab();
  lab("prepare-lab-launch").textContent = t("checking");
  try {
    const response = await fetch("/api/v1/lab/suite/prepare", {
      method: "POST", headers: { "Content-Type": "application/json", "X-TestLab-CSRF": labState.csrf },
      body: JSON.stringify({ mode: lab("lab-mode").value, scenarios: selectedTests(), tests: selectedWorkloads() })
    });
    if (!response.ok) throw new Error("plan");
    labState.plan = await response.json();
  } catch { labState.planFailed = true; }
  finally { labActionActive = false; renderLab(); }
}

function scheduleRunPoll() {
  clearTimeout(runPollTimer);
  if (runActive()) runPollTimer = setTimeout(pollRun, 1500);
}

async function pollRun() {
  if (runPollActive || labActionActive) { scheduleRunPoll(); return; }
  runPollActive = true;
  let finished = false;
  try {
    const response = await fetch("/api/v1/lab/run", { cache: "no-store", signal: AbortSignal.timeout(10000) });
    if (!response.ok) throw new Error("run-state");
    acceptRunControl(await response.json());
    labState.runError = null;
    finished = !runActive() && !!(labState.runControl.run?.terminal || labState.runControl.suite?.terminal);
    renderLab();
  } catch { labState.runError = "pollFailed"; renderLab(); }
  finally { runPollActive = false; }
  if (finished) await loadLab();
  else scheduleRunPoll();
}

async function controlRun(stop = false) {
  if (labActionActive) return;
  const suite = visibleSuite();
  const suiteAction = stop ? suite && !suite.terminal : labState.plan?.suite;
  const id = stop ? suiteAction ? suite.planId : labState.runControl.run?.planId : labState.plan?.plan_id;
  if (!id || (stop ? !runActive() : runActive() || !labState.plan?.gui_launch_supported || !labState.runControl.administrator)) return;
  labActionActive = true;
  labState.runError = null;
  renderLab();
  try {
    const response = await fetch(`/api/v1/lab/${suiteAction ? "suite" : "run"}/${stop ? "stop" : "start"}`, {
      method: "POST", headers: { "Content-Type": "application/json", "X-TestLab-CSRF": labState.csrf },
      body: JSON.stringify({ planId: id })
    });
    const result = await response.json();
    if (!response.ok) labState.runError = result.error || (stop ? "GUI_STOP_NOT_QUEUED" : "GUI_RUN_NOT_STARTED");
    else acceptRunControl(suiteAction ? { suite: result, run: labState.runControl.run } : { run: result });
  } catch { labState.runError = "pollFailed"; }
  finally { labActionActive = false; renderLab(); scheduleRunPoll(); }
}

lab("product-selection-form").addEventListener("submit", (event) => { event.preventDefault(); inspectSelection(); });
lab("save-product-selection").addEventListener("click", () => inspectSelection(true));
for (const id of ["product-folder", "product-contract", "product-driver-path", "product-build-name"]) lab(id).addEventListener("input", () => { inspectedInput = null; labState.observation = null; labState.saved = false; labState.plan = null; labState.planFailed = false; renderLab(); });
lab("lab-builds").addEventListener("click", event => {
  const button = event.target.closest("[data-build-action]");
  if (!button || button.disabled) return;
  const row = button.closest("[data-build-id]");
  changeBuild(button.dataset.buildAction, row.dataset.buildId, row.querySelector("[data-build-name]").value);
});
for (const element of [lab("lab-mode"), ...document.querySelectorAll("[data-lab-test], [data-test-duration], [data-test-load]")]) element.addEventListener("change", () => { labState.plan = null; labState.planFailed = false; saveTestingChoice(); renderLab(); });
lab("prepare-lab-launch").addEventListener("click", prepareLabLaunch);
lab("start-lab-run").addEventListener("click", () => controlRun());
lab("stop-lab-run").addEventListener("click", () => controlRun(true));
lab("lab-language").addEventListener("change", () => { labLanguage = lab("lab-language").value; localStorage.setItem("testlab-language", labLanguage); renderLab(); });
lab("refresh-lab").addEventListener("click", loadLab);
document.querySelectorAll("[data-lab-page]").forEach(link => link.addEventListener("click", event => {
  if (event.button !== 0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
  event.preventDefault();
  navigateLab(link.dataset.labPage);
}));
window.addEventListener("popstate", () => { labPage = pageFromUrl(); renderLabPage(); document.querySelector(`[data-lab-view="${labPage}"] h2`).focus({ preventScroll: true }); });
window.addEventListener("hashchange", () => navigateLab(pageFromUrl(), false));
// The lab-suites module starts the page after registering the saved-suite controls.
