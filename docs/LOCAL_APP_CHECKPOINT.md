# «На этом ПК» — checkpoint, 26 октября 2026

## Новое наблюдение, 27 октября

[Ранняя остановка endurance57](ENDURANCE57_EARLY_STOP_2026-10-27.md): пользовательский WinDivert/H2 на PB-SUT остановился после61.891с нагрузки. Ошибка лаборатории: keepalive origin channel закрывается сервером после30с простоя, endurance окно60с, native worker observer этот канал не опрашивает. Raw HEADER_INVALID, затем вторичный CHANNEL_CLOSED; очистка подтверждена. Это не доказательство UDP-дефекта продукта. В рамках запроса читались только сохранённые результаты; SUT не перезапускался/не изменялся, UDP-чат сохраняет VM-only scope. Код/пакет57 пока не исправлены. Перед новым многочасовым запуском нужен heartbeat на прежнем authenticated origin channel и проверка реального окна>60с. Не предлагать повтор H2 без исправления.
## Текущее приложение и scope

**preview.57**, source `592aa65f422f0691f2ccc0dda006b7d2b2f50c1d`, установлен на VM (localhost5178) и физическом PB-SUT (его localhost5178). У каждого отдельный пользовательский store; сборки и история сохранены. Проверены все 1702 SHA256 каждого пакета, admin=true/active=false/busy=false, по 2 сборки, 10 читаемых элементов первой страницы истории, unreadable=0. Реальные длительные тесты не запускались.

VM: `C:/src/ProxyBridge-TestLab/artifacts/releases/ProxyBridge-TestLab-0.3.0-local-preview.57-win-x64`. PB-SUT: `C:/PB-TestLab-20261026-r1/payload/lab57`; задача ProxyBridge-TestLab-Comparison обновлена, PB-USER InteractiveHighest/AtLogon и прежний ярлык сохранены. Пакет56 оставлен для отката; backup task-before57.clixml на SUT. Драйвер/HLK Stopped, trust/BCD/установка драйвера не менялись. Первое обновление остановилось на неподдерживаемом Set-ScheduledTask -Description; r2 без него успешно запустил/проверил 57. WinRM client cleanup без ошибок. Evidence ignored: artifacts/endurance-check/sut-upgrade57-r1,r2.

## Выполнено по последнему запросу

[Длительный режим57](ENDURANCE_PREVIEW57_2026-10-26.md): один эксклюзивный тест, без выбора нагрузки, 2ч по умолчанию/24/48/72ч. 30-минутный фиксированный цикл с постоянными TCP/UDP, прикладными операциями, всплеском, сменой соединений, затишьем/восстановлением. Ошибки каналов sticky, здоровые продолжают после подтверждённой изоляции; неизвестное состояние останавливает попытку. Нет Resume. Ограниченная сводка + append-only журнал; итоговые доказательства маршрута/данных обязательны. ETW ядра в долгом режиме отключён, полного kernelCPU/RAM не обещаем.

Проверки: C#/UI build без ошибок/предупреждений; 35 существующих native contracts PASS; 250 actualJS старых отчётов + новые длительности/совместимость/эксклюзивность PASS. API mixed/remote/H2-other gates PASS. Реальный короткий loopback цикл со всеми 6 прикладными адаптерами PASS; отмена ~0,99с PASS; UDP fault с продолжением TCP/сохранением ошибки и нулём оставшихся задач PASS. SHA журнала/полные счётчики/удержание постоянных сессий после 140 ID/освобождение запрета сна проверены. UI установленной57: нет load selector, остальные 9 карточек disabled при выборе, снятие выбора возвращает доступность, цикл раскрывается. Evidence: artifacts/endurance-check/final-admission.log, contracts.log, ui.cjs (ignored).

## Следующий шаг и порядок завершения

Пользователь запускает **2 часа каждой сборки на PB-SUT**; оценить каналы, итоговую очистку и журнал перед суточной приёмкой. 2/24/48/72ч с ProxyBridge ещё не проверены. Затем отдельно разобрать UDP WinDivert; после разработки — финальный README. [Решение о README/порядке](FINALIZATION_AND_NEXT_SCOPE_2026-10-26.md): измеренные преимущества по задержке/CPU процесса и privatecommit указать с версиями/стендом/диапазонами и ограничениями kernelCPU/RAM/throughput; универсального победителя не объявлять.

## Ранее подтверждённые результаты

- [Повторы56 наSUT](PB_SUT_REPEAT56_AUDIT_2026-10-26.md): WFP130126/131844, Win131033/132552; 16PASS, условия равны. Все rawSHA/recompute/cleanup подтверждены. WFP kernelCPU 0–2 выборки = unknown, не ноль. Не повторять аудит без новых данных.
- [Полные NORMAL56 наSUT](PB_SUT_NORMAL56_AUDIT_2026-10-26.md): WFP43PASS/1UNVERIFIEDUDP128, Win33PASS/11UDP-relatedFAIL. Root cause не установлен; текущий development scope его не разбирает.
- [ПодготовкаSUT](PB_SUT_COMPARISON_PREPARATION_2026-10-26.md), [случайныеVMповторы](REPEAT_RUNS_VM56_2026-10-26.md), [методядра56](KERNEL_COLLECTION_PREVIEW56_2026-10-26.md), [нагрузочныепрофили](USER_LOAD_PROFILES_2026-10-26.md).

## Границы работы

Worktree `C:/Users/LabAdmin/.codex/worktrees/testlab-development/ProxyBridge-TestLab`, branch `codex/development-functional-completion`; база d5b51f3 сохранена. Main C:/src/ProxyBridge-TestLab checkpoint-20261007: чужой handoff/KernelReadCapture.cs не трогать/не читать. Не автозапускать full/HIGH/многочасовой тест; не менять trust/BCD/driver как routineappstep. Frozenkits/captures/archives не удалять. Commit/push без force/PR/privateartifacts, не делегировать. Последние лимиты primary20%used/weekly26%used; при <=5%remaining checkpoint/стоп.

