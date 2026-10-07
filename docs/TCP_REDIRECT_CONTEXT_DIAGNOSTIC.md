# Диагностика отказов WFP-контекста у driver

Подготовлена отдельная копия Core из закреплённого `63be0ebf9bec92bfba95ef3d6729c375aa9af84e`. Исходные 138 файлов, baseline kit и результаты LOW/обоих HIGH сохранены без изменений. CLI и подписанный ProxyBridgeDrv.sys в диагностическом комплекте побайтно совпадают с baseline. Изменён только скопированный `Windows/src/driver/ProxyBridgeDrv_user.c`: добавлены наблюдения вокруг исходного запроса, без повторного запроса или изменения его аргументов, проверки длины и возвращаемого результата. Состояние WSA после запроса сохраняется через операции журналирования и восстанавливается перед возвратом.

Это отдельная диагностическая версия с другим SHA Core, не исходная сборка для сравнения производительности. Дополнительное журналирование может изменить тайминги и воспроизводимость; отсутствие отказа под журналированием не доказывает исправление original driver. Kernel driver не пересобирался, не подписывался и агентом не устанавливался/загружался.

## Что станет различимо

- API_FAILED: возврат WSAIoctl не равен0, немедленный код WSA зафиксирован отдельно от позднего сообщения relay.
- CONTEXT_SHORT: API вернул0, но число байт меньше32 (фактический sizeof контекста проверенной сборки).
- FAMILY_NOT_IPV4: полный контекст возвращён, family неAF_INET в этой IPv4-серии.
- IPV4_CONTEXT_AVAILABLE: полный IPv4-контекст; записаны PID/protocol и сопоставление с собственным генератором.

Microsoft требует считывать расширенный код после отказа вызова; `WSAGetLastError` относится к последней ошибке Winsock. Поэтому успешный API плюс короткий контекст или family mismatch нельзя объяснять одним поздним WSA10022. См. [SIO_QUERY_WFP_CONNECTION_REDIRECT_CONTEXT](https://learn.microsoft.com/en-us/windows/win32/winsock/sio-query-wfp-connection-redirect-context) и [WSAGetLastError](https://learn.microsoft.com/en-us/windows/win32/api/winsock2/nf-winsock2-wsagetlasterror).

Строки CTXDIAG содержат seq/socket/relay PID/thread/QPC, api_return/api_error/wsa_after, bytes/required/complete, family/protocol/ctx_pid и endpoints с ошибками их чтения. Поля ctx читаются только после успешного возврата и достаточного числа байт. Parser сопоставляет QPC-окно и peer endpoint с native client LocalAddress, независимо проверяет успешные GUID/объём у receiver. Отсутствующие, повторные или повреждённые строки не заменяются догадкой. Причины в ядре — например allocation failure или отсутствие назначения context — этим шагом ещё не различаются.

## Подготовленный комплект и проверка

`artifacts/diagnostics/tcp-redirect-context-preparation-20261005-143026-4b6b5e00/kit`

Core собран MSVC за несколько секунд, exit0, x64, те же19 экспортов. Одноразовый C harness исполнил изменённую функцию с подменёнными API: отказ10022, короткий ответ, IPv4 иIPv6; один запрос, исходный BOOL и состояние WSA сохранены, неуспешный/короткий ответ не читает неопределённый ctx. Это не вызовы WFP/сокетов продукта. Parser прочитал его реальные4 строки. Синтетическое сопоставление968 строк/86 failed native rows прошло; испорченный endpoint отвергнут. PS5.1+7.6.5 AST/BOM/PythonAST прошли. Старые3 оценки точно совпадают,103+101+101 sourceSHA прежние.

Wrapper Prepare/Inspect проверяют только файлы.29 зависимостей, helpers, native tools, kit, env и исходный файл зарегистрированного драйвера заморожены в runtime-plan.json. Пользовательский Run сохраняет общий mutex/execution.lock, проверки recorded4.0.0/new boot и interrupted history, затем существующие проверки OFF/interception/CLI/data/resource bounds/cleanup. Сам workload — только PROXY и те же4→64→256→640→4/8с/64KiB/с; исходные правила и rude/verify:data. Метод и manifest diagnostic-only/performance_comparable=false; обычный TCPconnections controller отказывает этому kit без специального opt-in. Diagnostic evidence сохраняется в artifacts/diagnostics, без обновления пользовательской сравнительной таблицы. Default benchmark paths и их evaluator не изменены.

## Исправление свежего каталога (2026-10-05)

Пользовательская попытка `tcp-redirect-context-run-20261005-144744-e769bff9` остановилась до запуска helpers/ProxyBridge: обёртка создала каталог для собственных receipts и передала его контроллеру, который требует отсутствующий каталог. Это ошибка лаборатории, не новое наблюдение отказа WFP. Три исходных файла попытки и её frozen plan сохранены без изменений.

Обёртка теперь хранит собственные receipts в корне результата, а контроллер сам создаёт новый дочерний `workload`. Исправлен только wrapper; новый frozen plan содержит те же28 файлов, изменился только его SHA. Прежний план сохранён в `verification/fresh-directory-fix/runtime-plan-before-fix.json`. Реальный извлечённый участок обёртки проверен с подставным контроллером в PowerShell5.1 и7.6.5: fresh child, сохранённые параметры, завершение и исключение/FAILED receipt. AST/BOM и files-only Inspect в обоих PowerShell прошли; продукт, трафик и driver queries не запускались. Receipt: `verification/fresh-directory-fix/validation.json`. Полный диагностический runtime пока не подтверждён.

## Исправление привязки службы (после попытки 15:03 UTC)

`tcp-redirect-context-run-20261005-150343-5e1a495b` остановился до helpers/CLI/phases на `CONNECTION_REQUIRES_CONFIRMED_PRODUCT_OFF`. Точный отказ проверки не был сохранён, поэтому наличие работающего продукта или конкретный блокер в этой попытке не доказаны. Подтверждена статическая несовместимость: диагностический env указывал на копию sys в kit, а последний сохранённый снимок службы13:31 UTC — на исходный baseline path. Проверка InterceptionState требует точного совпадения пути, одного совпадения SHA недостаточно.

Теперь только diagnostic opt-in проверяет pinned base_kit и одинаковый фиксированный SHA обоих sys, использует исходный `artifacts/product-builds/driver-63be0eb-testlab-cli/ProxyBridgeDrv.sys` для наблюдений и runtime preparation. CLI/Core остаются в отдельном diagnostic kit; проверка их файлов и side-by-side копии sys сохранена. Существующий runtime adapter запускает ту же ранее зарегистрированную службу с повторными path/hash checks; регистрация не меняется, никакая новая служба/драйвер не устанавливается. Перед запуском сохраняется `proxy/diagnostic-driver-binding.json`.

OFF gate сохраняет interception/loaded-driver/process observations перед отказом для before/after; сами условия запрета прежние. Проверен извлечённый код PS5.1+7.6.5: диагностическая привязка, неизменность ordinary path, отказ неверным base/hash и12 условий gate в каждом PowerShell на сохранённых/подставных наблюдениях без SCM/WFP/CIM. Files-onlyInspect/ASTBOM прошли. Reporter теперь различает `DIAGNOSTIC_NOT_STARTED` (FAILED/no phases/no CLI) и неполную запись после начала фаз; это не PASS и не подтверждение текущего OFF состояния. Новая read-only оценка прошлой попытки сохранена отдельно, исходные7 файлов прежние. 138 исходных sources и9 baseline files неизменны. Receipt `verification/registered-driver-binding/validation.json`; old29/intermediate и предыдущий28file plan сохранены там отдельно. Истинная причина исходных отказов redirect context и full diagnostic runtime ещё pending.

## Подтверждённый пользовательский результат (05.10.2026, 20:16–20:17 UTC+5)

`tcp-redirect-context-run-20261005-151606-472a07d3`: DIAGNOSTIC_METADATA_CORRELATED/errors[],968 сопоставленных query,96 native failures. До нагрузки4/4,64/64,224/256,576/640,восстановление4/4 втойжеCLI14496. Все96 — исходный API_FAILED,rc-1/immediateWSA10022/bytes0/required32; все872 успешных ответа — полный32byte IPv4/TCPконтекст. Ни stale error как единственная причина, ни успешныйshort context/family mismatch не объясняют эти96 отказов. Data matched receiver GUID/436MiB. Это не PASS или сравнение скорости; load256/640 snapshots неполны, поэтому224/576 не считать доказанным concurrent count.

CLI graceful/poststop/unforced, helper+sampler natural0/capture, STOPPED/STDIN_STOP, callbackERROR нет; savedafter scopedWFPdetached/Stopped baselinepath/knownnamesabsent/compatibleWinDivert0. Fixed directory/binding/newhelper shutdown fullruntime наблюдены. Read-only оценка exact,62originalfiles unchanged,29frozenfiles matches,138source+9baseline прежние. CLI projected lifecycle не хранит отдельныйexitcode, не изобретать его. Audit `artifacts/diagnostics/tcp-redirect-context-review-20261005-151606/{analysis.md,validation.json,readonly-evaluation.json}`.

Kernel root cause/table overflow ещё не доказаны. Следующий этап — отдельные metadata-only queries redirect RECORDS и bounded context size/buffer после исходного отказа с сохранением исходногоFALSE/ошибки/закрытия, без payloadlog/retry/fix/PASS. Он пока только спланирован, kit не подготовлен; та же серия повторно не нужна. Если этого недостаточно, потребуется прицельная kernel instrumentation, которая сейчас не собрана/установлена. Подробный план в audit/analysis.md.

Подготовлен следующий отдельный этап `redirect-context-followup-v2`; [описание и новая команда](TCP_REDIRECT_CONTEXT_FOLLOWUP.md). Прежний kit/data сохраняются, запускать следует новый directory153256-3e209b42. Ниже — история v1.

## Выполненная пользовательская команда

В административном PowerShell, при отсутствии других выполняющихся тестов:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-TcpRedirectContextDiagnostic.ps1" -DiagnosticDirectory "C:\src\ProxyBridge-TestLab\artifacts\diagnostics\tcp-redirect-context-preparation-20261005-143026-4b6b5e00" -Phase Run
```

Команда приведена для истории подтверждённого запуска, сейчас её повторять не требуется. Только локальные контролируемые соединения, без ETL и payload files. Runtime guard определяет необходимость перезагрузки из сохранённой истории; агент не выполняет перезагрузку и не обходит admin guard.

До пользовательского запуска агентский Run отказал LAB_RUN_REQUIRES_ADMINISTRATOR до mutex/lease/CIM/product. Теперь реальные запросы исходного API и завершение диагностического продукта подтверждены указанными пользовательскими saved artifacts. Основные выходы внутри напечатанного корня: `workload/redirect-context-report.json` и `workload/redirect-context-summary.md`; `diagnostic-run.json`, frozen plan и build receipt остаются в корне. DIAGNOSTIC_METADATA_CORRELATED означает наличие сопоставленных наблюдений, даже при отказах native; это не PASS продукта, не сравнение скорости и не доказательство переполнения таблицы.
