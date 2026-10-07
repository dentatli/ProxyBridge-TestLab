# Дополнительные наблюдения после отказа WFP-контекста

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

## Актуальный следующий этап

Первый matrix164945 разобран: ConnectEx32/1 —85/1APIотказов, второйcase остановлен из-за livePythoncallback10054; connect не проверен. Подготовлена matrix-v2 с узкой диагностической совместимостью закрытия стенда, без изменения продукта/передачи данных; полная проверка pendingUSERADMIN. Новый комплект `C:\src\ProxyBridge-TestLab\artifacts\diagnostics\tcp-redirect-context-preparation-20261005-170714-a2826a1f`, однакоманда8–16мин. [Разбор и запуск](TCP_REDIRECT_CONTEXT_MATRIX.md). Ниже — история, старые команды не повторять/не обновлять freeze.

## Несколько гипотез теперь в одном подготовленном запуске

По уточнению пользователя подготовлена [диагностическая матрица](TCP_REDIRECT_CONTEXT_MATRIX.md): ConnectEx/connect × pendingattempt1/32, четыре последовательных варианта и общий отчёт. Финальнаяпапка161454-c5595e9d, adminRun однойкомандой/8–16мин. Source/files-onlychecks прошли, fullruntimepending. Клиент/Core/driver побайтно прежние; kernelbuildinstall не выполнялись. Ниже сохранён разбор предыдущего single-run; его следующий PLAN-only уже заменён матрицей.

## Пользовательский запуск разобран: 96 отказов сохраняются

05.10.2026 20:44–20:45 UTC+5, tcp-redirect-context-run-20261005-154424-b81911e1 (driver): 4/4,64/64,224/256,576/640,recovery4/4. Все96 originalAPI failures и их3extra queries: -1/10022/0bytes. Буфер1024 не помог; requiredsize/recordsblob не получены. Это не доказывает отсутствия контекста в ядре; positiveRECORDScontrol наsuccess не наблюдался. SameCLI3932 recovery/scopedcleanup подтверждены, nativefailures retained. Pureevalexact62SHAunchanged/30frozenmatch/138sources9baseunchanged. Высокиеowned snapshots incomplete:224/576 неprovenconcurrent. Разбор: artifacts/diagnostics/tcp-redirect-context-followup-review-20261005-154424/analysis.md.

Повтор той же команды не требуется. Следующий source-only проект — distinct diagnostic pendingattempt limit1 вместо32, сохраняя уровни/данные/verdict/gates. Отказы идут группами32/24/8, естьsuccessbetween/after; это гипотеза о создании пачками, нетабличныйлимит. Профиль пока не реализован, команды запуска нет. При сохраненииотказов нужныcorrelated kernelclassify/allocation/contextassignment observations; сборка/подпись/установкаkerneldriver сейчаснеразрешены. Штатная методика и baseline не изменены.

Подготовлен отдельный комплект `artifacts/diagnostics/tcp-redirect-context-preparation-20261005-153256-3e209b42/kit`, method `redirect-context-followup-v2`. CLI и подписанный kernel driver побайтно прежние; меняется только copied Core. Исходный диагностический kit и результаты151606-472a07d3 сохранены. Kernel driver не собирался/не устанавливался, служба остаётся привязана к baseline path с прежними hash/path/SCM/WFP/loaded-driver/WinDivert gates.

На успешных исходных запросах новых IOCTL нет. Только после original SOCKET_ERROR, после сохранения rc/immediateWSA/bytes/QPC/endpoints, выполняются ровно три запроса:

1. `SIO_QUERY_WFP_CONNECTION_REDIRECT_RECORDS` с отдельным буфером1024байта.
2. `SIO_QUERY_WFP_CONNECTION_REDIRECT_CONTEXT` с NULL/0 output для наблюдения требуемой длины.
3. Тот же context query с отдельным буфером1024байта.

Лог `[CTXDIAG_EXTRA]` содержит sequence/socket/relayPID и только rc/immediateerror/bytes/capacity; у полного последнего ответа — family/protocol/ctxPID. Содержимое blob не записывается. Нет неограниченных allocation/retry/wait; supplied original ctx не изменяется дополнительными запросами. Возвращается исходный verdict, original WSA state восстанавливается после обоих журналов: даже если wide query успешен, relay по-прежнему закрывает исходно failed socket. Это наблюдение, не исправление продукта.

[Microsoft описывает RECORDS как blob переменной длины](https://learn.microsoft.com/en-us/windows/win32/winsock/sio-query-wfp-connection-redirect-records), а [CONTEXT query позволяет запросить требуемую длину нулевым буфером](https://learn.microsoft.com/en-us/windows/win32/winsock/sio-query-wfp-connection-redirect-context). Разные ошибки и required sizes сохраняются буквально; ошибка дополнительного запроса не доказывает отсутствия context в ядре. Успех позднего query не доказывает, что первоначальная ошибка вызвана малым буфером: дополнительное время/операции могли изменить наблюдаемое состояние. Буферный предел1024 явно указан, превышение не считается отсутствием записи.

## Проверено

Короткий standalone C harness `/W4 /WX` собран/исполнен,8 случаев fakeAPI: originalfail/shortsuccess/IPv4/IPv6, records/context failed, fullwide success, limit2048, shortwide31, fullwideIPv6. Только5 originalAPI failures получили дополнительные запросы; остальные по одному исходномуquery. Исходные BOOL/ctx/WSA сохранены. Harness не использует product/WFP/network API; Windows helpers QPC/ID/address formatting не являются probes.

Parser прочитал реальные harness logs. Синтетическое сопоставление96 follow-ups с прошлой пользовательской серией прошло; missing/duplicate/success-seq/wrong-socket записи дают INCOMPLETE, исходные96 failed native rows не становятся успешными. Old saved reevaluation exact,62originalsourceSHAunchanged; original138sources и9baselinefiles прежние. PS5.1+7.6.5 AST/BOM/PythonAST прошли. Build нового Core4,366с/exit0/x64/19экспортовbaseline; actual frozen30files+files-only Inspect PS5+7 прошли. При подготовке Core ещё не загружался. Теперь его пользовательский runtime разобран выше; агент трафик и driver queries не запускал. Receipts `verification/validation.json` (source-stage) и `verification/handoff.json` (после сборки).

## Выполненный пользовательский запуск (команда для истории)

Из PowerShell от администратора, при отсутствии других тестов:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-TcpRedirectContextDiagnostic.ps1" -DiagnosticDirectory "C:\src\ProxyBridge-TestLab\artifacts\diagnostics\tcp-redirect-context-preparation-20261005-153256-3e209b42" -Phase Run
```

ТолькоPROXY4→64→256→640→4, по8с nominal/64KiB/s/verify:data/rude, новый fresh workload, около2–4мин; ждать полного завершения/очистки и сообщить напечатанную root directory даже при ошибке. Shared admin/mutex/lease/crossboot/interrupted/frozen guards прежние; новая перезагрузка заранее ради Core не требуется. Старый v1 frozen plan теперь откажет из-за обновления runtime scripts; не менять его автоматически и не возобновлять старую попытку. Использовать именно новый v2 directory.

Выходы в `workload/redirect-context-report.json` и `workload/redirect-context-summary.md`. Metadata status CORRELATED не является PASS продукта, сравнением скорости или доказательством переполнения. Все successful/failed/count/resource ограничения прежние. True kernel allocation/context-assignment cause остаётся неизвестной до новых данных.
