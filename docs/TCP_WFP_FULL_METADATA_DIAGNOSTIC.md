# Единый сбор WFP, AFD, TCP и контекста Core

Статус 2026-10-07 после пользовательского Run150744: четыре baseline соединения и передача2MiB успешны, сбор остановился на XML parsing в coverage gate до нагрузки. После исправления формата netsh saved baseline даёт COVERAGE_CONFIRMED: owned WFP Apply/classify, AFD accept и TCP setup сопоставлены для всех четырёх соединений. Приватная утрата context под нагрузкой не наблюдалась в этом запуске, точная причина исходных сбросов остаётся неизвестной. Source checkpoint сохраняется в `codex/checkpoint-20261007`; ignored captures, локальные бинарники и private settings не являются частью Git backup.

Текущий новый комплект: `artifacts/diagnostics/tcp-redirect-context-preparation-20261007-151313-480f38a3`. Контроллер: [Invoke-KernelTcpFullMetadataDiagnostic.ps1](../scripts/Invoke-KernelTcpFullMetadataDiagnostic.ps1). CLI/Core/sys и140 файлов копии источников совпадают с комплектом172202. На этом этапе не пересобирались ни продукт/драйвер, ни console host/ETL decoder; изменён только Python разбор WFP snapshot. Новый files-only kit не копирует installation receipt и не refreeze старые plans.

## Формат XML netsh и подтверждённый baseline

Снимок Run150744 содержит объявление XML, затем два соседних раздела `wfpstate` и `firewallState`. Обычный ET.parse отказывал с `junk after document element`; это ошибка нашего анализатора, не свидетельство сбоя ProxyBridge. Исправленный reader проверяет XML declaration, разбирает весь документ через общий контейнер и допускает только один wfpstate с необязательным последующим firewallState. Callout ownership берётся только из wfpstate. Не обрезается хвост; лишний текст/неизвестный или повторный root/malformed XML/DTD отвергаются.

Офлайн результат нового reader: все4 ports60060–60063 uniquely сопоставлены с Apply callout301, отдельными CorrelationId/TransportEndpointHandle и AFD accept pairs для CLI2916, native PID10476;2MiB data verified, native_failed0/kernel_records4. ETL SHA0870fccd8448e827c4a8a88756784127d02fbef9e24ca7524c3672f2794b8b24,1960 selected/lost0/buffers0/QPC10MHz/readclosewrite0. Не доказано равенство внутренних WFP/AFD объектов или private transfer/free. Нагрузочных уровней и recovery cohort в этой трассе нет.

Проверка actual frozen Python runtime также даёт COVERAGE_CONFIRMED;4 XML positive,10 corrupt XML rejects и13 coverage guards на actual saved events. Before/after snapshots корректно разбираются и не содержат owned IDs. CLI/CTS/collector/helper/sampler cleanup и saved Restore hash/path/Stopped/detached подтверждены; исходный FAILED/INCOMPLETE и все223 USER files сохранены. Не утверждается текущее глобальное состояние Windows. Fresh151313 проходит PS5Prepare/PS5PS7Inspect FILES_VALIDATED55+13 exact. Audit `artifacts/diagnostics/tcp-wfp-full-coverage-review-20261007-150744`.

Неиспользованный промежуточный125700-81e73d81 заменён до установки/сбора: по локальным NETIO metadata исправлена проверка CorrelationId, это UINT64, не GUID. Использованный130731-dbfa7b1c и его результаты сохраняются как история; исходная регистрация после его Run восстановлена и проверена в сохранённых receipts. Старые комплекты не refreeze/Resume; следующий Install/Run относится только к151313-480f38a3; использованный140958 также сохраняется как история.

## Отказ подтверждения PID получателя

В Run135055 получатель PID1972 успешно выполнил bind/listen127.0.0.1:54122, создал CSV с одним заголовком и оставил827 событий в интервале4794.3681мс. Затем наблюдаются отменённые AFD accept (C0000120). Startup receipt сохраняет принудительную очистку host job, а исключение получения process handle говорит об уже завершившемся процессе. Это согласуется с гонкой пятисекундного ожидания identity callback и очистки. Истинный порядок callback/таймаута/завершения не записан; отдельное падение CTS и его исходный exit code не доказаны. Пустой stdout сам по себе не доказывает отсутствие работы процесса.

Новый opt-in `receiver_identity_ack` действует только в едином сборе: host создаёт получателя suspended и публикует PID; адаптер удерживает process handle, проверяет путь и посылает READY; только затем host выполняет ResumeThread. EOF, неверная команда и таймаут завершают свою job, не дают запускать клиента. Сохраняются QPC начала/конца ожидания и callback, факт завершения ожидания, native child exit code, когда он доступен. Проверки пути, готовности listener и coverage gate остаются обязательными. Общий запуск без opt-in сохраняет прежний протокол.

Проверены настоящий CTS receiver без клиента/ProxyBridge в PS5/7, с ACK и без него: удержание PID/пути, штатный CTRL_BREAK, exit0, без forced stop. Отдельный host контроль проверил suspended child до READY, ранний exit37, неправильный ACK, EOF и таймаут. Адаптер в обеих версиях отвергает другой путь до Resume и отсутствие host. Не утверждается, что таймаут под полной нагрузкой воспроизведён или устранён во всех условиях.

В исходной трассе2786 выбранных событий:2236AFD,511TCPIP,39WFP ConnectRedirectClassify; QPC10MHz, events/buffers lost0, read/close/write errors0. WFP Apply для owned native cohort пока не проверен. Сохранённые CLI/helper/collector/sampler завершились штатно; host job получателя принудительно очищалась. Saved Restore подтверждает исходный hash/path, Stopped и отсутствие известных WFP объектов, а не текущее глобальное состояние Windows.

Audit: `artifacts/diagnostics/tcp-wfp-full-start-review-20261007-135055`;209 файлов пользовательского комплекта, запуска и трассы защищены hash snapshot. Историческая подготовка140958: PS5 Prepare и PS5/7 Inspect;14 capture/policy/cohort и8 frozen-plan checks в каждой версии. Следующие команды в `verification/HANDOFF.md`; агент не выполняет driver Install, повышение прав или перезагрузку.

## Что происходит в одной команде Run

1. Проверяются55 runtime hashes и13 внешних hashes, включая NETIO/AFD/TCPIP/mswsock, профиль и декодер. Новый policy допускает только `original`; внутреннее историческое обозначение `RouteMatrix` не означает три прогона.
2. Сохраняется read-only WFP state и запускается bounded ETW запись. Сохраняются четыре baseline соединения через исходную очередь, на локальный контролируемый receiver через локальный SOCKS5.
3. После штатного завершения baseline сохраняется активный WFP state и первый ETL. Декодируются rawQPC/headers/payload и TDH metadata. Проверяется конкретная принадлежность WFP Apply к callout ProxyBridge и native ports, связь CorrelationId с classify, AFD accept с CLI/remote native endpoint, наличие CurrentBacklog и TCP setup. Четыре нативные передачи должны быть успешными. Это проверка покрытия, не доказательство равенства WFP/AFD объектов или private transfer/free.
4. При недостающих/неоднозначных событиях нагрузка не начинается. Отчёт `baseline-coverage.json` перечисляет конкретные пробелы, исходные ошибки сохраняются, выполняется существующая очистка и guarded Restore.
5. При достаточном baseline начинается второй ETL; тот же CLI проходит64 →256 →640 →4 соединения. Snapshot `recovery-active` сохраняется до остановки CLI. В конце выполняется прежняя очистка/Restore, сохраняются второй ETL, snapshot после опыта и decoded events. Между baseline и нагрузкой имеется явно отмеченная пауза ETW; новый cohort в эту паузу не запускается. Это не непрерывная трасса всего времени жизни CLI.

WFP Callout provider описан [Microsoft](https://github.com/microsoft/ebpf-for-windows/blob/main/docs/Diagnostics.md); keyword4/level5 и нужные metadata проверены в локальном NETIO. AFD29 IDs дополняют прежние16TCPIP IDs и original Winsock WPP status. На каждый сегмент лимит64MiB; потери/достижение лимита/неподтверждённая остановка не считаются достаточным сбором. Успешный baseline не обязан содержать WPP error event: тот появляется при отказе. Эмиссия pause/unpause и события ошибки проверяются на нагрузке при последующем анализе.

## Запуск пользователем

В PowerShell **от администратора**:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-KernelTcpFullMetadataDiagnostic.ps1" -DiagnosticDirectory "C:\src\ProxyBridge-TestLab\artifacts\diagnostics\tcp-redirect-context-preparation-20261007-151313-480f38a3" -Phase Install
```

Только после успешного Install вручную перезагрузить Windows. Затем в административном PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-KernelTcpFullMetadataDiagnostic.ps1" -DiagnosticDirectory "C:\src\ProxyBridge-TestLab\artifacts\diagnostics\tcp-redirect-context-preparation-20261007-151313-480f38a3" -Phase Run
```

Около2–4 минут нагрузки плюс сохранение/разбор двух трасс и snapshots. Требуется прежний ресурсный запас>=2GiB свободной RAM. Если baseline источники не подтверждены, команда завершится раньше. Не дробить опыт ради лимита разрешённых коротких проверок. Дождаться завершения очистки, Restore и сохранения трасс; передать путь `tcp-wfp-full-trace-*` даже при ошибке. Snapshot может содержать пути и адреса других процессов, поэтому пакет остаётся локальным ignored evidence, не публикуется в Git.

Если guarded Restore не подтвердился, после штатной очистки используется этот же контроллер с `-Phase Restore`; автоматического обхода проверки нет. После восстановления исходного пути перед контрольными измерениями нужна ручная перезагрузка. BCD/доверие/UAC/настройки гипервизора/proxy/сети не меняются.

## Результат и предел вывода

`TRACE_SAVED_LOAD_CORRELATION_PENDING` означает: baseline coverage подтверждён, трассы сохранены и разобраны, loss/clock проверены; точная связь объектов нагрузочного участка ещё ожидает офлайн-анализа. Это не PASS продукта. `CAPTURE_INCOMPLETE` сохраняет ошибку workload, coverage или очистки и не подменяется прежним успешным прогоном.

В одном пакете можно проверять давление очереди, дополнительные callout/reauth/redirect действия, выбор/жизнь endpoint и исходный NTSTATUS. Нельзя заранее обещать увидеть приватный перенос/освобождение записи. Если переход отсутствует в событиях, остаётся [условный этап kernel debugging](TCP_CONTEXT_ENDPOINT_LIFECYCLE_PLAN.md); Windowsbug/driverbug/table overflow/capacity/fix/performance пока не доказаны.

Историческая проверка подготовки130731: PS5 Prepare и PS5/7 Inspect exit0, FILES_VALIDATED;13 capture/policy/cohort checks +8 frozen-plan checks в каждой версии PowerShell;17 synthetic coverage rejects;42477 raw headers/payloads прежней трассы совпали с предыдущим reader;322 USER files сохранены. Audit: `artifacts/diagnostics/tcp-wfp-full-development-20261007`, frozen handoff130731 сохранён; текущий handoff — в151313. Старые планы/отчёты не переписывались и не refreeze/Resume; изменённые общие контроллеры делают старые runtime source bindings устаревшими, использовать только новый комплект.
