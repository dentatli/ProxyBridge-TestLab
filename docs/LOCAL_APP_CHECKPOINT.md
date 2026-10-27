# «На этом ПК» — checkpoint, 27 октября 2026

## Актуальная версия

**preview.59**, source `b379160804fd7447a2a90acd17313ea575fb663e`, установлена/запущена admin/idle на VM localhost5178 и физическом PB-SUT (его localhost5178). 1703 package SHA256 на каждой копии совпали. По2сборки; история VM10/SUT12 элементов, unreadable0. Stores отдельные, результаты разных машин не смешивать. DLL/SYS, установка WFP, BCD/trust не менялись.

VM: `C:/src/ProxyBridge-TestLab/artifacts/releases/ProxyBridge-TestLab-0.3.0-local-preview.59-win-x64`. SUT: `C:/PB-TestLab-20261026-r1/payload/lab59`; существующая задача Comparison обновлена, ярлык прежний. Пакеты58/57 оставлены для отката; task-before59.clixml наSUT. Evidence ignored: artifacts/endurance-check/package59-verified.json, sut-upgrade59-r1; VM artifacts/endurance59-vm-ready.json. WinRMclientcleanup без ошибок.

## Последнее исправление

[Порты endurance59](ENDURANCE59_RULE_PORTS_FIX_2026-10-27.md): общий выбор точного набора42501,42511,42513,42515,42517,42518,42520 для обоих worker-правил (API/CLI, WFP/WinDivert). Набор приложений общий с endurance. Control/proxy/посторонние порты исключены; process/ownedPID/route/payload scope не ослаблен. rule_change содержит target_ports. Обычные сценарии сохраняют один свой порт.

Проверки:3целевых regression PASS; **настоящий WinDivert4.3.0 Core наVM**, безexplicittest_proxy, короткий50сцикл: elapsed51.437с,15/15операций routeCOMPLETE,все6appканалов SUCCESSFUL,постоянныеTCP/UDP/bulk/churnуспешны. ACK обоих правил, nativePID/path подтверждены. Cleanuptrue/forcedstopfalse,nativejobs0,послевыходаownedпроцессов/WinDivertслужбнет. Временная загрузка официальногоWinDivert в ранее разрешённом scope, состояние восстановлено. Evidence artifacts/endurance-check/check59-product.log/.exit, probe-1793082505832651500. WFPпроверен на общем rulegeneration/serialization, нового реального WFPпрогона не было.

## Что показал предыдущий H2

[WinDivert H2preview58](PB_SUT_WINDIVERT_H2_58_AUDIT_2026-10-27.md): attempt20261027-041036-80501e557e9645ba8890e0f863afe413,7200свыполнены,cleanuptrue. UDP36000/36000,invalid0/loss0;TCPpersistent/bulk/churnсrouteproof. Но6appканалов выполняли обмены внеProxyBridge из-за правила42501; после первого окна карантин, итогFAILED, прикладной2чохватнеподтверждён. Это исправлено59; старый отчёт не переписывался. Журналы5.97МиБ,всяпапка7.33МиБ,ZIP772КиБ. 9fileSHA/raw/journal/captureSHA и summaryrecompute0diff.

[Heartbeat58](ENDURANCE58_HEARTBEAT_FIX_2026-10-27.md) исправил [раннюю остановку57](ENDURANCE57_EARLY_STOP_2026-10-27.md): originidle30с против окна60с. Подтверждено100снапрежнемsocket+quiet>30с+failurecleanup. В H2preview58 сработал1267раз, controltimeoutнеповторился. Не чинить это повторно.

## Следующий шаг

Пользователь самостоятельно запускает H2 на59; новый многочасовой запуск ни одной сборки после исправления портов не выполнялся. Для честного прикладного сравнения нужны результаты одной59; прежний58H2частичный. Неавтозапускатьfull/HIGH/H2/24ч. Длительный режим отдельный/эксклюзивный,фиксированныйцикл,H2default/H24/H48/H72,безloadselector,legacyдлительностисовместимы. [Устройство57](ENDURANCE_PREVIEW57_2026-10-26.md); ETWkernelвsoakотключён, полногоkernelCPU/RAM не обещать.

UDPWinDivert — отдельный чат `01a17935-ca69-7152-8f03-9c9bb8600e7c`, [VM-onlyhandoff](WINDIVERT_UDP_VM_HANDOFF_2026-10-26.md). Его запретPB-SUT сохраняется; здесь SUT читался/обновлялся по новым запросам пользователя о длительном режиме. UDPownership не исправлен этим портовым фиксом; singleUDPflow не проверяет коллизию нескольких сокетов с одним назначением. После финальных проверок — [итоговый README](FINALIZATION_AND_NEXT_SCOPE_2026-10-26.md), без универсального победителя и полного kernelCPU рейтинга.

## Ссылки и ограничения

История: [SUTповторы56](PB_SUT_REPEAT56_AUDIT_2026-10-26.md), [SUTfull56](PB_SUT_NORMAL56_AUDIT_2026-10-26.md), [подготовкаSUT](PB_SUT_COMPARISON_PREPARATION_2026-10-26.md), [VMповторы](REPEAT_RUNS_VM56_2026-10-26.md), [kernel56](KERNEL_COLLECTION_PREVIEW56_2026-10-26.md). Использовать подтверждённые результаты без повторного полного аудита.

Worktree `C:/Users/LabAdmin/.codex/worktrees/testlab-development/ProxyBridge-TestLab`, branch codex/development-functional-completion; база d5b51f3 сохранена. Main C:/src/ProxyBridge-TestLab checkpoint-20261007: чужой handoff/KernelReadCapture.cs не трогать/не читать. Trust/BCD/driver не менять как routineappstep, frozenkits/captures/archives сохранить. No force/PR/privateartifacts,не делегировать. При<=5%remaining checkpoint/стоп; последний usage primary23%used/weekly41%used.
