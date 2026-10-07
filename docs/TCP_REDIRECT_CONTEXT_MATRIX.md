# Несколько гипотез причины отказа за один запуск

## Полная матрица уже выполнена: актуальный результат175848-a3cb97a9

Все4варианта завершены с полными метаданными: ConnectEx32/1 —96/1отказ, connect32/1 —15/1. Recovery4/4all/no restart withincase, helpersclean/no callback;113API10022/zero-byteотказов сохраняются. Kernelcause/internalcapacity не доказаны. [Независимый разбор](../artifacts/diagnostics/tcp-redirect-context-matrix-review-20261005-175848/analysis.md), [проверки](../artifacts/diagnostics/tcp-redirect-context-matrix-review-20261005-175848/validation.json). Исторические команды ниже не повторять для того же вопроса.

Следующая отдельная диагностика [подготовлена и проверена](TCP_REDIRECT_CONTEXT_NEXT_PROBES.md): положительный RECORDSконтроль, context спустя5/25/100ms и тип/адреса отказавшего сокета. Одно выполнение ConnectEx32, original failures сохранены; runtime pending. Новая команда и frozen комплект указаны по ссылке. Методика обычных тестов/исходные CLI/sys сохранены; kernelbuildsigninstall не разрешены.

## Актуально после запуска174556-766e04c7

Baseline получателя не запустил клиент: console host не подтвердилPID; точныйфактор потерян старым startup catch. ПрежнийProactor guard обработал2reset и helper завершился0/noERROR/noCallback, но wholecase INCOMPLETE/триcaseSKIPPED. Новая правка сохраняет подробности запуска в receiver/client-start-failure.json и прекращает нагрузку при неполной baseline; PIDgate/таймаут5с не ослаблены/retryнет. Продукт и native data path прежние. PS5+7 actualbenignhost+fakecohort checks passed, старые305files неизменны/reevalexact.

Использовать только новый frozen комплект `C:\src\ProxyBridge-TestLab\artifacts\diagnostics\tcp-redirect-context-preparation-20261005-175531-06f4e1f5`; прежние команды ниже — история, планы не обновлять/не Resume. Запуск от администратора:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-TcpRedirectContextDiagnostic.ps1" -DiagnosticDirectory "C:\src\ProxyBridge-TestLab\artifacts\diagnostics\tcp-redirect-context-preparation-20261005-175531-06f4e1f5" -Phase Run
```

Все4варианта8–16мин; при ошибке запуска очередь остановится раньше и сохранит конкретные metadata. Fullnewruntime/PIDinitialcause/kernelcause pending. [Проверки](../artifacts/diagnostics/tcp-console-start-failure-check-20261005/validation.json), [разбор](../artifacts/diagnostics/tcp-redirect-context-matrix-review-20261005-174556/analysis.md). Ниже сохранена предыдущая подготовка/история.

Пользователь 2026-10-05 уточнил, что нужны несколько гипотез причины ошибки, а не несколько сборок. Подготовлен отдельный диагностический набор `redirect-context-matrix-v2` из четырёх последовательных вариантов:

| Вариант | Способ установления TCP | Максимум одновременно ожидающих подключения |
|---|---|---:|
| connectex-32 | Асинхронный ConnectEx | 32 |
| connectex-1 | Асинхронный ConnectEx | 1 |
| connect-32 | Обычный блокирующий connect | 32 |
| connect-1 | Обычный блокирующий connect | 1 |

Это два независимых фактора и их сочетание: пачки попыток соединения, способ подключения, зависимость от обоих. Лимит ожидающих подключения отдельно от числа установленных соединений. [Закреплённый исходный код Microsoft CTS](https://github.com/microsoft/ctsTraffic/blob/b0e2a48f30fb7caaaa9994ee2dea2a177a4639e2/ctsTraffic/ctsConfig.cpp#L529) описывает выбор API; в том же файле ParseForThrottleConnections задаёт лимит pending attempts. Фактические параметры каждого native-процесса проверяются по сохранённой CIM command line и launch receipt.

В каждом варианте — PROXY 4 → 64 → 256 → 640 → 4, прежние 524288 проверяемых байт на соединение при лимите 64 KiB/с, verify:data и shutdown:rude. Восстановление внутри варианта использует тот же CLI. Между вариантами предыдущий controller полностью останавливает продукт/помощники и сохраняет наблюдения покоя; следующий controller заново проверяет готовность. Порядок фиксирован, не рандомизирован: различия — диагностические признаки, не статистическое доказательство причины.

Сохраняется тот же подписанный driver, CLI и diagnostic follow-up Core из153256-3e209b42: побайтно скопированы в новый kit, без новой сборки/установки. Зарегистрированный driver path остаётся baseline. Методика штатных бенчмарков и их evaluator не менялись. Новый опциональный параметр контроллера недоступен обычному тесту/неподготовленному комплекту; data path библиотеки и Core не менялись.

## Запуск

Подготовка: `C:\src\ProxyBridge-TestLab\artifacts\diagnostics\tcp-redirect-context-preparation-20261005-170714-a2826a1f`. Замороженный план выбирает ConnectionMatrix; дополнительных переключателей в Run не требуется. От администратора при отсутствии других тестов:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-TcpRedirectContextDiagnostic.ps1" -DiagnosticDirectory "C:\src\ProxyBridge-TestLab\artifacts\diagnostics\tcp-redirect-context-preparation-20261005-170714-a2826a1f" -Phase Run
```

Ориентировочно 8–16 минут. Одна команда выполняет четыре варианта и печатает общую папку. Не перезагружать/закрывать процесс во время серии; ждать штатного завершения и сообщить папку даже при отказе. Сохраняются admin, общий mutex/FileShareNone lease на весь набор, recorded legacy/interrupted/crossboot guards, frozen hashes, свежие каталоги, проверки памяти/диска и прежняя очистка. Новая перезагрузка заранее только ради этой подготовки не требуется; фактические runtime guards остаются обязательными.

Исходные API/native-отказы при полном сборе и штатном завершении не мешают проверке следующего варианта: это диагностические данные. Ошибка контроллера/cleanup или неполные метаданные прекращают очередь; остальные варианты SKIPPED. Совместного запуска четырёх нагрузок нет.

## Отчёт и пределы вывода

В общей папке:

- `matrix-manifest.json` — порядок и статусы вариантов.
- `redirect-context-matrix-summary.md` — одна таблица результатов.
- `redirect-context-matrix-report.json` — полные метаданные и fingerprints.
- В каждом case-каталоге — controller evidence и `redirect-context-report.json` с сопоставлением native endpoint/PID/QPC и оригинальных/follow-up queries.

Варианты проверяет отдельный evaluator: закреплённые numeric preset/engine/wheel, planned+live conn/throttle/data options, полный набор фаз, native capture/unforced cleanup, sampler stop, активный выбранный драйвер/other-driver fingerprint и scoped before/after state. Исходные отказы не заменяются удачным поздним запросом, прошлым PASS или нулём. CORRELATED — полнота наблюдений, не PASS продукта.

Если ошибка зависит от pending limit или API, это поможет выбрать следующий точечный этап. Отсутствие отказов в других условиях не исправляет исходную сборку и не доказывает ошибку генератора. Большое число успешных передач не объявлять одновременностью при неполном owned snapshot. Здесь не измеряются максимальная ёмкость таблицы, kernel allocation/занятость, wire delivery или сравнительная скорость.

Follow-up Core по-прежнему выполняет дополнительные RECORDS/size/wide queries только после original API failure. Положительного runtime-контроля RECORDS на успешном сокете и kernel classify/context-assignment telemetry этот набор не добавляет. Не обещать проверку всех возможных причин. Диагностическая kernel-сборка/подпись/установка не выполнялись и сейчас не разрешены.

## Результат первой матрицы и новая подготовка

Первый пользовательский root164945-d24e6656 частичный: ConnectEx32 —85API/native отказов (21при256+64при640), ConnectEx1 —1при640. В обоих восстановление4/4 без перезапуска внутриcase. Все отказавшие original/followup queries: -1/immediateWSA10022/bytes0. Это сигнал зависимости от pending limit, не доказательство причины при фиксированном порядке и неполном второмcase. connect32/connect1 ещё не проверены.

Второйcase остановлен строго: callback принятого сокета в CPython3.12.14 при socket.shutdown(SHUT_RDWR) получил10054 доSTOP, после уведомления protocol.connection_lost, доsocket.close/Server._detach. ПослеSTOP существующая bounded cleanup завершила закрытие; helper natural0 не отменяет живую ошибку, evaluator остаётся INCOMPLETE.

Новая matrix-v2 включает только диагностический `--guard-proactor-close-reset`/`-DiagnosticFixtureCloseGuard`: закреплены Python3.12.14 и SHA исходного callback. AST меняет только shutdown expression, принимает только ConnectionResetError10054 с excNone у закрывающегося принятого loopback54123 StreamReaderProtocol после _closed.done. Оригинальные socket.close/detach/flag выполняются; событие PROACTOR_SHUTDOWN_RESET_HANDLED пишется только после их завершения. Неизвестные ошибки protocol/callback/close/detach по-прежнему дают INCOMPLETE; native/API/data отказы ProxyBridge сохраняются. Wheel и установленный PythonLib не изменены; guard действует только внутри диагностического helper процесса и восстанавливает callback при завершении. Обычные тесты его не включают.

Новый case/root method-v2 и close policy записаны в manifest/config/freeze. Reporter требует install event с pinned source/PID/port, hashes guard/helper/Python/runtime из freeze и полные handled events. Старыеcasev1/матрица переоцениваются точно; старые данные не исправлялись задним числом.

Одноразовые проверки без сети: actualCPython callback с fake sockets воспроизвёл original reset, новое закрытие/notify/detach ровноодинраз, normalpath прежний,8negative cases/source-runtime mismatch/install-restore. V2 reporter synthetic installed/handled metadata плюс8negative cases: все85 исходных отказов сохранены, произвольный ERROR/callback всё ещё INCOMPLETE. PS5.1/7.6.5 AST/BOM, actual extracted argument/dispatch boundaries passed (4variants/freshchildren/fail2skip2/defaultnative unchanged). Старыеv1/v2single+matrix exact/246filesSHAunchanged. Files-only PS5Prepare/PS7Inspect passed;33freeze совпали, компонентыkit byteidentical/noCorebuild/install.

Полный новый runtime pendingUSERADMIN; никакого product traffic/SCM-WFPquery/HTTP/buildinstall/signing/reboot/cleanup/commitpush/subagents/maintainedautotests агентом не выполнялось. Старые161454 и промежуточная170528 подготовки остаются историей; применять только новый170714-a2826a1f. Audits: matrix-review-20261005-164945/validation.json и analysis.md, matrix-close-guard-check-20261005/{validation,guard-validation,report-v2-validation}.json.
