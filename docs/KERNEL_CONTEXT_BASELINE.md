# Четыре соединения для проверки живого журнала WinDbg

USER Run 113826-0f33dffe: native baseline успешен (4 CTS GUID, 2 MiB, четыре исходных Core query; saved cleanup подтверждён). Host log проверен отдельно: четыре CREATE_POST/query/free allocator pairs, но только два CREATE_PRE, ноль TRANSFER_PRE/POST, 659 NULL TRANSFER_READ и повторяющиеся строки. Private endpoint ↔ exact Core query ownership не доказана; полный logger coverage остаётся неполным. Исходные USER files/status не переписаны. Повтор baseline или полную нагрузку пока не запускать. Следующий адресный шаг и найденная статическая packet-metadata ветка описаны в [KERNEL_CONTEXT_PACKET_ATTACHMENT_PLAN.md](KERNEL_CONTEXT_PACKET_ATTACHMENT_PLAN.md).

USER conditional patch подтверждён 2026-10-08 по attachment d71a00d5: заменены ровно существующие IDs 11–13 без ошибок; `.bpcmds` содержит 14 точных адресов/действий и 14 `bd`, отдельный `g` присутствует. Повторять patch или stage теперь не нужно. Audit `artifacts/diagnostics/pb-kd-conditional-patch-review-20261008/validation.json`; 62 frozen hashes свежего 111941 kit проверены повторно. Следующий шаг — открыть новый host log, включить известные 14 точек и отдельно `g`, затем USER baseline Run ниже. Проверено хранение команд, их живое исполнение ещё не проверено.

Обновление USER Run 102744-d827d20f: native workload не начался. SOCKS helper PID 16140 записал LISTENING, затем STDIN_STOP через 58.8 мс; естественный exit 0, forced=false. Контроллер сообщил CONNECTION_HELPER_NOT_READY_proxy. В физическом log 79 TRANSFER_READ с обоими record=NULL, ни одного CREATE_PRE/ALLOCATOR_FREE_CALL; затем остановка на WfpPoolFree+0x1a и ручное отключение 14 точек. Это свидетельство прерывания logger; причина и длительность паузы непосредственно не измерены. Сохранённые after snapshots: исходный service Stopped, известных WFP objects/loaded interception driver names/product processes не наблюдалось. Это сохранённое наблюдение, не полная текущая проверка системы и не доказательство причины исходных сбросов. Original USER files и использованный 101425 plan сохранены SHA; audit `artifacts/diagnostics/pb-kd-helper-review-20261008`.

Условные действия 11–13 теперь содержат `gc` в true **и** false ветках. Остальные 11 действий и адреса сохранены. Это явное продолжение по [документации Microsoft](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/gc--go-from-conditional-breakpoint-), а не доказательство ошибки старого CommandString. Для уже установленных точек предназначен отдельный [conditional patch](../scripts/debugger/pb-context-lifecycle-conditional-patch.wdbg): `bp11`/`bp12`/`bp13` заменяют ровно существующие ID, после чего отключают их. Candidate заново **не загружать**. Patch не проверяет идентичность точек автоматически: до него пользователь должен проверить `bl` на физическом хосте.

Baseline-only readiness wait сохраняет `proxy.jsonl.readiness.json` / `pc-samples.jsonl.readiness.json` с PID, elapsed, event count и причиной отказа. После возврата из ожидания он читает readiness до сравнения таймера: исправлена пропущенная финальная проверка. Таймаут остаётся 5000 мс; выход процесса, несколько LISTENING и повреждённый JSON не принимаются за готовность. Запись не утверждает наличие измеренной debugger pause. По шесть files-only случаев прошли PS5/PS7, включая готовность после фактического истечения таймера и отказ без неё. Shared controller/module не менялись.

**Текущий свежий комплект:** `artifacts/diagnostics/pb-kd-baseline-preparation-20261008-111941-ae56381c`. Реальные PS5 Prepare/Inspect и PS7 Inspect: 62 frozen files exact; files-only workload prefix PS5/PS7 подтверждён. Бинарники прежние; build/install/Run/traffic/debugger changes агент не выполнял. Использованные 095534 и 101425 комплекты больше не запускать и не refreeze/Resume. Живое продолжение новых действий и coverage четырёх соединений пока не проверены.

Перед следующим baseline скопировать patch на физический хост в `C:\PB-KD\pb-context-lifecycle-conditional-patch.wdbg`. **Break приостановит всю VM, Codex и RDP.** Заранее сохранить аварийные команды отключения 0..13 и отдельного `g`. После Break:

1. Отдельно `bl`: ровно наши известные 14 resolved points 0..13, все d, прежние symbol+offset. При несовпадении patch не выполнять.
2. Отдельно `.logopen /t C:\Users\Administrator\pb-context-kd-baseline-fixed.log` (предыдущий log закрыт; не перезаписывать его).
3. Отдельно `$<C:\PB-KD\pb-context-lifecycle-conditional-patch.wdbg`.
4. Отдельно `bl`, отдельно `.bpcmds`: все 14 d, IDs 11–13 теперь с `gc` в обеих ветках, 0–10 прежние. При ошибке не запускать workload; отдельно `g` обязателен даже при ошибке.
5. Только при совпадении включить известные 0..13 командой `be` из ручного порядка ниже, проверить `bl`, затем отдельно `g`.
6. В повышенном PowerShell внутри VM выполнить:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-KdContextBaseline.ps1" -Phase Run -PreparationDirectory "C:\src\ProxyBridge-TestLab\artifacts\diagnostics\pb-kd-baseline-preparation-20261008-111941-ae56381c" -DebuggerLoggerEnabled
```

После завершения/ошибки отключить наши точки и продолжить VM по ручному порядку ниже. При любой остановке WinDbg сначала сохранить сообщение и отключить наши точки, затем отдельно `g`, чтобы завершилась очистка. Полная нагрузка закрыта до офлайн проверки этого baseline. Передать console output и новый физический log.

Обновление USER Run 100731-2974e9ac: остановка до создания workload из-за отсутствующего components в receipt нового подготовщика. Это ошибка агентской подготовки, не ProxyBridge. Сохранены исходные три файла failed run и host log SHA e460582bfe7cf44016a612dd9a4abb9fdc57a79821b39215f04a426e02cdb5f5. В active части log есть 90 TRANSFER_READ с обоими record=NULL и без debugger errors; остальные действия на собственных соединениях не проверены. USER включил 14 e, затем отключил 14 d и закрыл log. Последующий g закрытый log не содержит; агент работает в продолжившейся VM. Audit: `artifacts/diagnostics/pb-kd-baseline-start-review-20261008/validation.json`.

Исправлен только receipt producer: components теперь содержит ровно три name/SHA256. Inspect дополнительно проверяет полноту, уникальность, разрешённые имена и SHA компонентов. Новый комплект `artifacts/diagnostics/pb-kd-baseline-preparation-20261008-101425-5dc367d1`; старый 095534 не переписан, не refreeze/Resume. Реальный PS5 Prepare/Inspect и PS7 Inspect: 61 frozen hashes exact, файлы валидированы. Полный files-only prefix workload-контроллера до создания evidence прошёл PS5/PS7 с v5 input, без процессов/SCM/трафика. Единственный CIM call prefix находится в v4 branch, false для проверенного v5; #RequiresAdmin исключён только из ad hoc read-only prefix check, production Run остаётся повышенным. Шесть повреждённых components случаев отклонены каждым PS. Нового Run не было.

Перед повтором открыть **новый** log на физическом WinDbg командой `.logopen /t C:\Users\Administrator\pb-context-kd-baseline.log` при остановленной VM. Старый log не перезаписывать; stage/probe файлы заново не загружать. Затем применять ручной порядок ниже с новым 101425 preparation и текущими 14 известными отключёнными точками. Полная нагрузка остаётся закрыта до проверки baseline.

2026-10-08. USER format probe выполнен без ошибок: 14 синтетических строк, три true conditions, false branch не выполнена, BEGIN/END присутствуют. Все точки 0..13 остались отключёнными, адреса и CommandString совпали с установленным файлом; отдельный g присутствует. Исходный attachment неизменён. Ignored audit: `artifacts/diagnostics/pb-kd-format-review-20261008/validation.json`. Это проверка formats/синтетических условий, не исполнение breakpoint действий на соединениях и не доказательство причины сбросов.

## Отдельный контроллер

[Invoke-KdContextBaseline.ps1](../scripts/Invoke-KdContextBaseline.ps1) поддерживает Prepare/Inspect/Run. Prepare и Inspect работают без администратора и только с файлами. Run выполняет пользователь в повышенном PowerShell внутри VM, после ручного включения журнала на физическом хосте. Агент Run не выполняет, к WinDbg не подключается и точек не включает.

Контроллер создаёт новый `pb-kd-baseline-preparation-*`, не меняет использованные комплекты. Он копирует:

- Исходные CLI ad83b3aa и driver 3cd79cfc из base kit.
- Проверенную Core 7dc8952e из прежнего 151313 kit. Она сохраняет единственный исходный query, содержит accept/query QPC и metadata трёх участков маршрута. Значение process-local selector фиксируется на original и восстанавливается в finally: исходный SOMAXCONN, без задержки accept. Новая сборка и подмена зарегистрированного пути драйвера не требуются.
- Новый manifest/receipt/env с методом redirect-kd-baseline-v5. Файлы бинарников и всех зависимостей заморожены SHA256. Ранее использованный runtime-plan не меняется и не запускается.

Отдельный [workload controller](../scripts/Invoke-KdContextBaselineWorkload.ps1) — копия существующего контроллера с узким v5 guard. Единственная фаза: 4 ConnectEx соединения, pending limit 32, 8 секунд по 64 KiB/с, 512 KiB проверяемых данных на соединение, rude TCP close. Нет уровней 64/256/640, recovery или OFF режима. Фаза вызывает существующий private Invoke-ConnectionCohort через module-bound script block. Shared ConnectionLoad и Invoke-LocalTcpConnections не изменены; их runtime guards и штатная очистка сохранены. Resource floor для четырёх соединений — 512 MiB свободной RAM, 256 MiB диска.

Сохранены проверки исходного драйвера, отсутствия чужого перехвата, точного пути процессов, mutex/lease, перезагрузки после старой 4.0.0/прерванного опыта, identity ACK receiver, close guard fixture, gracefulness CLI и остановки службы. Run не устанавливает драйвер, не меняет BCD, trust, proxy, Hyper-V или сеть. Запуск/остановка уже зарегистрированной исходной службы входят в пользовательский workload.

Синтетическая проверка PS5/PS7 подтвердила одну фазу 4 и отказ шести нарушенных условий без native execution. Reporter на отдельной копии прежних четырёх успешных соединений подтвердил GUID/data 2 MiB и отказ семи повреждённых вариантов. Исходные 67 файлов USER run не изменены. AST и files-only Prepare/Inspect проверяются отдельно. Эти проверки не являются новым Run или runtime готовностью logger.

Финальный свежий комплект `artifacts/diagnostics/pb-kd-baseline-preparation-20261008-095534-9e75f467`: фактический PS5 Prepare/Inspect и PS7 Inspect завершились KD_BASELINE_FILES_VALIDATED, все 61 SHA совпали. Get-ProductBuildIdentity files_verified=true, bundle a0e0cf314c7858bed6ee4382da1226b2023e23db3f61ccab2d7ceab0b1e6662f. AST подтверждён PS5/PS7; reporter повторно даёт точно тот же результат после записи своих выходных файлов. Shared controller и ConnectionLoad SHA неизменны. Run, SCM, native traffic и точки агент не исполнял. Подробная локальная проверка: `artifacts/diagnostics/pb-kd-format-review-20261008/baseline-validation.json`.

## Ручной порядок

Передавать Run только после проверенного source checkpoint/push, успешного Inspect свежего плана и наличия команд аварийного продолжения на физическом ПК. Не повторять старые Install/Run, не перезагружать VM ради этого опыта: после другого boot точки и символы нужно проверить заново.

1. На физическом хосте оставить открытым существующий log WinDbg. Заранее сохранить команды ниже. **Break останавливает всю VM, включая Codex и RDP. Активные точки тоже приостанавливают VM; ошибка действия может оставить её на kd>.** Даже если Run завис внутри гостя, управление возобновляется с физического WinDbg.
2. После Break ввести отдельно `bl`. Только если 0..13 — ровно наши ранее проверенные 14 resolved точки с прежними symbol+offset и полными CommandString, все d, включить их:

```text
be [0n0] [0n1] [0n2] [0n3] [0n4] [0n5] [0n6] [0n7] [0n8] [0n9] [0n10] [0n11] [0n12] [0n13]
```

3. Ввести отдельно `bl`, затем отдельно `g`. Все 14 должны быть e. Если адрес/команда не совпали, появились чужие точки или ошибка, не запускать workload: отключить только подтверждённые наши ID, затем g отдельно. Stage файл заново не загружать. Никаких bc*/bd*/be*.
4. В повышенном PowerShell **внутри VM** выполнить конкретную команду нового wrapper `-Phase Run -PreparationDirectory <fresh path> -DebuggerLoggerEnabled`. Этот switch — подтверждение пользователя о ручном включении и наличии host resume plan; он не доказывает coverage. Запуск содержит только четыре соединения. Номинально короткий опыт, но <5 минут с serial breakpoint logging не гарантируется; агент не исполняет его автоматически.
5. Дождаться окончания Run и штатной очистки; при остановке на ошибке WinDbg сохранить вывод, отключить наши точки и отдельно g, чтобы контроллер мог завершить cleanup. Даже если нет воспроизведения, не запускать полную нагрузку автоматически.
6. **Перед следующим Break снова предупредить об остановке всей VM/Codex/RDP.** На физическом хосте проверить bl и отключить только наши ID:

```text
bd [0n0] [0n1] [0n2] [0n3] [0n4] [0n5] [0n6] [0n7] [0n8] [0n9] [0n10] [0n11] [0n12] [0n13]
```

7. Отдельно `bl`. При необходимости закрыть текущий log командой `.logclose`, затем отдельно `g` даже при ошибке. Передать полный baseline console output и сохранённый log физического WinDbg. Старые логи не перезаписывать.

## Что должно быть доказано до нагрузки

Reporter требует ровно одну фазу baseline/4/8s, четыре успешных CTS GUID и соответствующие receiver bytes 2 MiB, четыре исходных query, QPC accept<=entry<=exit, исходную очередь, concurrent socket snapshot и штатную очистку. Успешный статус `KD_BASELINE_NATIVE_METADATA_CONFIRMED_DEBUGGER_PENDING` означает только эти наблюдения. Он никогда не подтверждает WinDbg coverage или root cause.

Затем offline связать raw sockaddr A/B из CREATE_PRE с четырьмя native tuple, не предполагая направление по порядку. Проверить реальные memory reads, quoted actions и auto-g; create/transfer/query/dereference/free и allocator pairs по явным объектам и срокам жизни. Не считать ETHREAD исполняющего контекста владельцем соединения, record/user-context одним выделением, указатели разных подсистем одним идентификатором или отсутствие free строки доказательством сохранности. Строки PBKD_PROBE исключены из живых событий.

Если logger меняет условия так, что цепочки не полны, результат INCOMPLETE; если ошибка не воспроизводится при последующей нагрузке, INCONCLUSIVE. Полная серия и точная причина сбросов пока не проверены этим baseline.
