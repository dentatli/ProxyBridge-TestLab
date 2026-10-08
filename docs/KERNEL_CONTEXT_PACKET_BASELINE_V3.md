# Четыре соединения с зарегистрированным packet logger V3

**Отменено как следующий шаг после сбоя 21:45:** точка 17 дважды остановила VM с Memory access error до нового Run. Все 25 в конце log отключены; USER сообщает отдельный g. Не выполнять прежние be25/Run ниже и не использовать kit 163607 для сокращённого профиля. Актуальные офлайн-результаты и следующий read-only шаг: [семь точек, план V1](KERNEL_CONTEXT_PACKET_MINIMAL_V1.md). Ниже сохранена прежняя инструкция как история.

USER stage log 21:30 `pb-context-packet-stage-v3_03f8_2026-10-08_21-30-24-322.log` (30291 bytes, SHA256 `f26054a9f937849104814437216932006c83a8b1fec8e0e292245147579e43d2`) проверен офлайн. Начальные 14 прежних точек d; оба guard прошли, BODY_END записан. Итоговые 25 точек 0..24 разрешены и d; адреса/сохранённые тела/.bpcmds точно соответствуют V3, четыре замены и 11 добавлений, десять сохранённых точек без изменений. Ограниченный code gate подтвердил первые два bytes 15 sites, не полный live image hash. Logclose записан; отдельный g после закрытия журнала не наблюдается. Ошибок регистрации нет. Runtime point actions, gc, owned PID/TID и NBL/record/query correlation пока не проверены; причина исходного сбоя не доказана.

Свежий комплект `pb-kd-packet-baseline-preparation-20261008-163607-3fe55948` создан только файлами: 70 frozen SHA exact, PS5 Prepare/Inspect и PS7 Inspect прошли. Версионные V3 wrapper/producer используют тот же неизменённый four workload, прежние pinned CLI/Core/driver (bundle a0e0cf31…). Добавлена замороженная saved-stage audit запись и её SHA/policy; она доказывает прежнюю регистрацию, не текущее состояние отладчика/исполнение точек. Policy prefix PS5/PS7: valid принят, по 11 повреждённых вариантов отклонены; workload prefix в обеих версиях подтвердил три компонента. Старые 255 protected hash entries без изменений. Ни build/install/SCM/traffic/Run, ни target debugger mutation агент не выполнял.

Это только четыре ConnectEx/32 соединения, hold 8s, 512 KiB на соединение, один исходный query; original queue/local SOCKS5. Нет уровней 64/256/640, recovery/OFF/kernel collector/установки драйвера. Reporter сохраняет DEBUGGER_PENDING, а не product PASS на основании native результата. С активными serial breakpoints VM может сильно замедляться; длительность менее пяти минут не обещается.

## Подготовить на физическом ПК до Break

Сохранить эту инструкцию на физический ПК, чтобы она была доступна при остановленной VM. Сначала подготовить отдельные команды включения и отключения ниже. Stage/candidate/patch заново не загружать. Использовать новый kit 163607, не старые kits и не full workload.

## 1. WinDbg на физическом ПК

**Break приостанавливает всю Windows VM, Codex и RDP.** Каждую внешнюю команду вводить отдельно, Enter после каждой.

После Break:

`.logopen /t C:\Users\Administrator\pb-context-packet-baseline-v3.log`

`bl`

`.expr`

Продолжать только если ровно 25 известных разрешённых точек 0..24, все d, тела после регистрации не менялись и evaluator MASM. При отличии ничего не включать, `.logclose` и `g` отдельно, прислать журнал.

`be [0n0] [0n1] [0n2] [0n3] [0n4] [0n5] [0n6] [0n7] [0n8] [0n9] [0n10] [0n11] [0n12] [0n13] [0n14] [0n15] [0n16] [0n17] [0n18] [0n19] [0n20] [0n21] [0n22] [0n23] [0n24]`

`bl`

Должны быть те же 25 точек, все e, без ошибок. Затем отдельно:

`g`

Не закрывать этот журнал до завершения проверки и отключения точек. Если включение ошиблось, выполнить строку bd из раздела 3, bl, .logclose и g отдельно; Run не выполнять.

## 2. PowerShell от администратора ВНУТРИ VM

После отдельного g и возобновления VM выполнить ОДНУ команду:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-KdPacketBaselineV3.ps1" -Phase Run -PreparationDirectory "C:\src\ProxyBridge-TestLab\artifacts\diagnostics\pb-kd-packet-baseline-preparation-20261008-163607-3fe55948" -PacketStageReviewed -DebuggerLoggerEnabled
```

Ключи подтверждают ручную подготовку, не доказывают debugger coverage. Дождаться возврата PowerShell/сообщения `KD baseline results` и завершения очистки. При ошибке не повторять Run: сохранить полный вывод, затем отключить точки по разделу 3. Не устанавливать драйвер/не перезагружать Windows для этой команды.

Если WinDbg неожиданно остановился с ошибкой и VM не отвечает, сохранить сообщение на физическом ПК, выполнить bd ниже, bl и g отдельно, чтобы workload мог завершить очистку. После возврата VM дождаться завершения PowerShell, затем закрыть журнал через порядок раздела 3. Не продолжать нагрузку при ошибках logger.

## 3. Отключение на физическом ПК после успеха ИЛИ ошибки

**Следующий Break снова приостанавливает всю VM, Codex и RDP.** После возврата PowerShell нажать Break на физическом ПК. По одной команде:

`bd [0n0] [0n1] [0n2] [0n3] [0n4] [0n5] [0n6] [0n7] [0n8] [0n9] [0n10] [0n11] [0n12] [0n13] [0n14] [0n15] [0n16] [0n17] [0n18] [0n19] [0n20] [0n21] [0n22] [0n23] [0n24]`

`bl`

Все 25 должны быть d. Затем:

`.logclose`

`g`

g отдельно даже при ошибке; при новой остановке сохранить сообщение и снова g отдельно. Не использовать bc*/bd* и не менять посторонние точки. Прислать полный вывод PowerShell и новый журнал `pb-context-packet-baseline-v3_...log` с физического ПК. Только после проверки этих данных можно переходить к диагностической нагрузке; текущая регистрация её не разрешает.

Audit: `artifacts/diagnostics/pb-kd-packet-stage-v3-review-20261008/validation.json`, files-only verification и final-validation в той же папке. Все использованные/frozen старые планы и USER captures сохранены без refreeze/Resume; archives/captures/kits не публикуются в Git.
