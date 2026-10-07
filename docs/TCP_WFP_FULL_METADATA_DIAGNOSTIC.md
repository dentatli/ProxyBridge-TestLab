# Единый сбор WFP, AFD, TCP и контекста Core

Статус 2026-10-07: новый комплект подготовлен и проверен на диске; реальная эмиссия дополнительных WFP/AFD событий, нагрузка и точная причина ещё не проверены. Install в текущем nonadmin процессе отказал с `FULL_METADATA_REQUIRES_ADMINISTRATOR` до изменения регистрации; installation receipt отсутствует. Source checkpoint сохраняется в `codex/checkpoint-20261007`; ignored captures, локальные бинарники и private settings не являются частью Git backup.

Новый комплект: `artifacts/diagnostics/tcp-redirect-context-preparation-20261007-130731-dbfa7b1c`. Контроллер: [Invoke-KernelTcpFullMetadataDiagnostic.ps1](../scripts/Invoke-KernelTcpFullMetadataDiagnostic.ps1). CLI/Core/sys и140 файлов копии источников совпадают с комплектом172202; продукт и драйвер не пересобирались. Собран только самостоятельный декодер сохранённых ETL, не подключающийся к процессам и не включающий провайдеры.

Неиспользованный промежуточный125700-81e73d81 заменён до установки/сбора: по локальным NETIO metadata исправлена проверка CorrelationId, это UINT64, не GUID. Его frozen файлы не переписывались; использовать только130731-dbfa7b1c.

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
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-KernelTcpFullMetadataDiagnostic.ps1" -DiagnosticDirectory "C:\src\ProxyBridge-TestLab\artifacts\diagnostics\tcp-redirect-context-preparation-20261007-130731-dbfa7b1c" -Phase Install
```

Только после успешного Install вручную перезагрузить Windows. Затем в административном PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-KernelTcpFullMetadataDiagnostic.ps1" -DiagnosticDirectory "C:\src\ProxyBridge-TestLab\artifacts\diagnostics\tcp-redirect-context-preparation-20261007-130731-dbfa7b1c" -Phase Run
```

Около2–4 минут нагрузки плюс сохранение/разбор двух трасс и snapshots. Требуется прежний ресурсный запас>=2GiB свободной RAM. Если baseline источники не подтверждены, команда завершится раньше. Не дробить опыт ради лимита разрешённых коротких проверок. Дождаться завершения очистки, Restore и сохранения трасс; передать путь `tcp-wfp-full-trace-*` даже при ошибке. Snapshot может содержать пути и адреса других процессов, поэтому пакет остаётся локальным ignored evidence, не публикуется в Git.

Если guarded Restore не подтвердился, после штатной очистки используется этот же контроллер с `-Phase Restore`; автоматического обхода проверки нет. После восстановления исходного пути перед контрольными измерениями нужна ручная перезагрузка. BCD/доверие/UAC/настройки гипервизора/proxy/сети не меняются.

## Результат и предел вывода

`TRACE_SAVED_LOAD_CORRELATION_PENDING` означает: baseline coverage подтверждён, трассы сохранены и разобраны, loss/clock проверены; точная связь объектов нагрузочного участка ещё ожидает офлайн-анализа. Это не PASS продукта. `CAPTURE_INCOMPLETE` сохраняет ошибку workload, coverage или очистки и не подменяется прежним успешным прогоном.

В одном пакете можно проверять давление очереди, дополнительные callout/reauth/redirect действия, выбор/жизнь endpoint и исходный NTSTATUS. Нельзя заранее обещать увидеть приватный перенос/освобождение записи. Если переход отсутствует в событиях, остаётся [условный этап kernel debugging](TCP_CONTEXT_ENDPOINT_LIFECYCLE_PLAN.md); Windowsbug/driverbug/table overflow/capacity/fix/performance пока не доказаны.

Проверка подготовки: PS5 Prepare и PS5/7 Inspect exit0, FILES_VALIDATED;13 capture/policy/cohort checks +8 frozen-plan checks в каждой версии PowerShell;17 synthetic coverage rejects;42477 raw headers/payloads прежней трассы совпали с предыдущим reader;322 USER files сохранены. Audit: `artifacts/diagnostics/tcp-wfp-full-development-20261007`, frozen handoff — `verification/HANDOFF.md` и `handoff.json` нового комплекта. Старые планы/отчёты не переписывались и не refreeze/Resume; изменённые общие контроллеры делают старые runtime source bindings устаревшими, использовать только новый комплект.
