# Контекст WFP: три проверки за один запуск

## Опыт уже выполнен: повторять команду ниже не нужно

183525-74582558:10positiveRECORDS/112acceptedcontextfail/336latefail/448stabletype-endpoint; отдельно32initial10061безendpoint. ИсходныйFAILED/INCOMPLETEсохранён. Исправлена только reporterclassification пустыхCSVадресов,32неподтверждённыхattempts остаютсяINCOMPLETE; прежнийfrozenplanпосле3reporterchangesустарел. [Разбор](../artifacts/diagnostics/tcp-redirect-context-probes-review-20261005-183525/analysis.md). Следующий[проект kernelнаблюдения](TCP_REDIRECT_CONTEXT_KERNEL_OBSERVATION.md) покабезсборки/установки, требуетотдельногоразрешения. Нижекомандаисторическойподготовки.

Комплект подготовлен и проверен 2026-10-05. Новый метод `redirect-context-probes-v3`; runtime ещё не выполнен. Основание — завершённая матрица175848-a3cb97a9: ConnectEx32/1=96/1 отказ, connect32/1=15/1. Это связь с условиями подключения, не установленная причина в ядре.

## Что проверяем

1. **Положительный контроль RECORDS.** После успешного исходного IPv4 context query: sequence1–4 и далее кратный128, максимум16 наблюдений за процесс. Один RECORDS query с буфером1024; rc/immediateWSA/bytes/QPC/PID/socket/sequence. Blob и данные пакетов не сохраняются. Неудачный RECORDS на плохом сокете без положительного контроля не доказывает отсутствие records.
2. **Контекст спустя время.** После исходного API_FAILED и прежних трёх немедленных follow-ups: отдельные context1024 queries при номинальных5/25/100мс от окончания первого запроса. На том же принятом сокете, отдельные обнулённые буферы; фиксируются реальные QPC/elapsed/rc/error/bytes/семейство/protocol/PID/исходное назначение. Максимум3 поздние пробы на отказ и1000 отказавших сокетов за процесс. Исходный BOOL/context/WSA восстанавливаются; поздний успех не разрешает передачу и не отменяет исходную ошибку.
3. **Тип и адреса сокета.** До поздних запросов и после каждого из них: SO_TYPE/getsockname/getpeername и ошибки этих операций. SO_ERROR не читается, данные сокета не читаются и не отправляются. Совпадение типа и адресов — метаданные того же сокета; это не снимок TCP state и не доказательство доставки или отсутствия reset.

Один ConnectEx/pending32, прежние4→64→256→640→4, data/rate/GUID/recovery checks. Дополнительные вызовы и ожидания задерживают accept и могут изменить воспроизведение. Их числа и время нельзя сравнивать со старой матрицей как улучшение или исправление. Методика обычных бенчмарков сохранена.

## Проверено до запуска

Отдельный Core собран с MSVC, exit0, x64, те же19 экспортов. CLI и подписанный sys совпадают с baseline;138 исходных файлов и9 baseline файлов неизменны. В копии source изменён только `Windows/src/driver/ProxyBridgeDrv_user.c`.

16 fake-API/clock/socket cases, включая настоящий извлечённый upstream query: исходный BOOL, ctx и WSA сохранены; проверены late success/failure/short/family/PID/destination, oversleep, ограничения и failed positive control. Строгий parser связал синтетические96 поздних успехов с96 исходными ошибками, сохранив все ошибки;10 повреждённых вариантов отклонены.12 независимых старых reevaluations exact/543 saved files SHA unchanged. PS5+7 AST/BOM,12 извлечённых policy cases на оболочку, actual dispatch с подставным controller success/failure/freshchild. Продукт, SCM/WFP и трафик агентом не запускались.

Первичная сборка и harness: `artifacts/diagnostics/tcp-redirect-context-preparation-20261005-182422-8660d704`. После уточнения reporter/dependency checks создан новый комплект с побайтно тем же Core, исходный план не перезаписывался. Текущий frozen комплект содержит37 файлов; PS5 Prepare и PS7 Inspect — FILES_VALIDATED, runtimefalse. [Подтверждение](../artifacts/diagnostics/tcp-redirect-context-preparation-20261005-183038-7c035e66/verification/validation.json).

## Запуск

Закрыть пользовательский ProxyBridge и запустить в PowerShell администратора; одна команда, ориентировочно2–5минут:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-TcpRedirectContextDiagnostic.ps1" -DiagnosticDirectory "C:\src\ProxyBridge-TestLab\artifacts\diagnostics\tcp-redirect-context-preparation-20261005-183038-7c035e66" -Phase Run
```

Дождаться завершения и очистки; передать итоговую папку даже при ошибке. Новая попытка имеет свежую директорию; не Resume и не запуск прежней матрицы. Существующие admin/sharedlease/crossboot/resource/freshdirectory/cleanup guards сохранены. CLI/sys исходные, отдельная диагностическая копия Core. Узкий ранее проверенный Proactor close guard используется только в этом диагностическом варианте.

Отчёт: новая run-папка, `workload/redirect-context-report.json` и `workload/redirect-context-summary.md`. Native/API ошибки сохраняются; CORRELATED означает полноту метаданных, не PASS продукта. Capture/startup/cleanup errors остаются INCOMPLETE/FAILED.

## Граница вывода

Поздний контекст с правильными PID/protocol/исходным назначением показывает изменение доступности; точный kernel/Core дефект и пригодность retry не доказаны. Все поздние отказы не доказывают отсутствие контекста в ядре. Внутренняя занятость таблицы и максимальная ёмкость не измерены. Kernel classify/allocation/context-assignment telemetry остаётся возможным следующим шагом; сборка, подпись и установка kernel-кандидата сейчас не разрешены.
