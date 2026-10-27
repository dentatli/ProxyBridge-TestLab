# «На этом ПК» — checkpoint, 27 октября 2026

## Актуальная версия и последний запрос

**preview.58**, source `cbc8e8460386400ad0693854c4d72f2e75f3048c`, установлена и запущена admin/idle на VM localhost5178 и PB-SUT (его localhost5178). По1702packageSHA verified. VM2сборки/10элементовистории, PB-SUT2сборки/11элементов, unreadable0. Stores разные, не смешивать отчёты. НаSUT сохранены прежние сборки/история, задача Comparison переключена на58, WinRMclientcleanup без ошибок. Продуктовые DLL/SYS/driver/trust/BCD не менялись.

Пути: VM `C:/src/ProxyBridge-TestLab/artifacts/releases/ProxyBridge-TestLab-0.3.0-local-preview.58-win-x64`; SUT `C:/PB-TestLab-20261026-r1/payload/lab58`. Старые пакеты оставлены, task-before58.clixml наSUT. Evidence ignored: artifacts/endurance-check/package58-verified.json, sut-upgrade58-r1; VM artifacts/endurance58-vm-ready.json.

## Исправление длительного режима

[Причина57](ENDURANCE57_EARLY_STOP_2026-10-27.md): попытка WinDivert/H2 `20261026-170949-580b7f74b7204c918f288d5369fe1f1a` наSUT остановилась после61.891с нагрузки. Это дефект лаборатории: serveridle30с, окно60с, observer опрашивал только nativeworker. Raw HEADER_INVALID → вторичный CHANNEL_CLOSED, cleanuptrue; UDP-дефектом этот отказ не является.

[Исправление58/проверки](ENDURANCE58_HEARTBEAT_FIX_2026-10-27.md): каждые5с аутентифицированный originmetrics запрос по прежнему сериализованному preconnected socket, включая quiet; скрытого reconnect нет. Первая observerпричина не затирается последующим отказомизоляции, передаётсявsummary.failure_context. Серверные лимиты/маршрут/payloadgates не ослаблены.

Проверено безProxyBridge наVM: настоящий PythonAgent/OriginMetricsChannel +C#origin/relay/worker+HTTPadapter,100.609с, окно60с иquiet>30с,19heartbeats, исходныйsocketсохранён,complete=true,nativejobs0. Fault закрытияканала: complete=false,первичнаяпричинасохранена,nativejobs0. Summaryprojection/g diffcheck PASS. Пакет58собран, обеустановкипроверены. Evidence artifacts/endurance-check/check58.log, probe-1793073656988624100. Новых trackedавтотестов нет.

## Следующий шаг

Пользователь самостоятельно повторяет **2ч** длительной стабильности наPB-SUT. Послеисправления2/24/48/72ч сProxyBridge ещёнепроверены; неавтозапускать. Новый режим один/эксклюзивный, фиксированный30минцикл, безloadselector, H2default/H24/H48/H72, legacyдлительностисовместимы. Подробности [режим57](ENDURANCE_PREVIEW57_2026-10-26.md). ETWkernelвsoakвыключен, полногоkernelCPU/RAMнеобещаем.

UDPWinDivert — отдельныйчат `01a17935-ca69-7152-8f03-9c9bb8600e7c`, [VM-onlyпередача](WINDIVERT_UDP_VM_HANDOFF_2026-10-26.md). Его запретPB-SUTсохраняется; чтение/обновлениеSUTздесь выполнены только по новым пользовательским запросам о длительномрежиме. Отдельныйчат уже добавил93eeb6eofflineUDPвыводы; неотменять/неповторятьегоработу. Далее [финальныйREADME](FINALIZATION_AND_NEXT_SCOPE_2026-10-26.md), послефинальнойпроверки и UDP, безуниверсальногопобедителя.

## Подтверждённые исторические результаты

- [SUTповторы56](PB_SUT_REPEAT56_AUDIT_2026-10-26.md):16PASS,условияравны,rawSHA/recompute/cleanupподтверждены. WFPkernelCPU0–2samples=unknown,не0.
- [SUTfull56](PB_SUT_NORMAL56_AUDIT_2026-10-26.md):WFP43PASS/1UNVERIFIEDUDP128,Win33PASS/11UDP-relatedFAIL. Не смешивать с controltimeout57.
- [ПодготовкаSUT](PB_SUT_COMPARISON_PREPARATION_2026-10-26.md),[VMповторы](REPEAT_RUNS_VM56_2026-10-26.md),[kernel56](KERNEL_COLLECTION_PREVIEW56_2026-10-26.md),[профилинагрузки](USER_LOAD_PROFILES_2026-10-26.md).

## Рабочие границы

Worktree `C:/Users/LabAdmin/.codex/worktrees/testlab-development/ProxyBridge-TestLab`, branch codex/development-functional-completion; базаd5b51f3сохранена. Main C:/src/ProxyBridge-TestLab checkpoint-20261007:чужойhandoff/KernelReadCapture.csнетрогать/нечитать. Неавтозапускатьfull/HIGH/soak;trust/BCD/driverнеизменятькакroutineappstep;frozenkits/captures/archivesсохранить. No force/PR/privateartifacts,неделегировать. Проверятьлимиты,<=5%remainingcheckpoint/стоп. Последниелимитыprimary8%used/weekly39%used.
