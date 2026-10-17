# Новая регистрация двух точек проверена; подготовка одной пробы4

17 октября2026, Asia/Yekaterinburg. USER прислал полный console: initialbl пуст; новыйstage зарегистрировал толькоIDs3/4, сразу отключил каждую; finalbl показывает обеd, адреса соответствуют matching live RVA; .bpcmds содержит точные actions иbd3/bd4; отдельныйg. Ошибок регистрации/комментариев не показано. Скрипт повторно не загружать.

## Подтверждение регистрации и границы

Private копия user chat paste сохранена UTF8/LF (не независимый host log) в `artifacts/diagnostics/pb-kd-query-session-preparation-review-20261017/registration-console.txt`, SHA `6adcf477712be3310673e923a7870c5da68c663bcfafb2cff1bcd2149b4052c5`. Машинная сверка двух echoedbp, двух inventory rows и .bpcmds exactprofile; registration-reviewSHA `8119dcd6f8bde9a00e0f3fd132e48b10021efe044146ccc5e2122956a1ae278e`. В review зафиксированы только регистрация/disabledstate/g, **не выполнение actions, gc, kernel query binding или rootcause**.

Новый метод `redirect-kd-query-session-four-v1` соответствует registeredIDs[3,4], а не прежней selection3/4 из7. Созданы отдельные `Invoke-KdQuerySession.ps1`, `Invoke-KdQuerySessionWorkload.ps1`, `pb_prepare_kd_query_session.py`, `pb_kd_query_session_report.py`; используется неизменённый four-only модуль `KdQueryProbeConnectionLoad.psm1`. Старые источники195830 и frozenkit не изменены. Старые kits/stage7/25 не Resume/refreeze/переиспользовать.

Fresh kit: `C:\src\ProxyBridge-TestLab\artifacts\diagnostics\pb-kd-query-session-preparation-20261017-063031-cfbfaa59`, локально11:30:31. PlanSHA `7e90ea90f7fd8f2cca02d9459a9c38f129369e6ed2b8bd40d759a413b073416a`. При Prepare копируется отдельный Python runtime, фиксируются новые источники/двухточечныйstage/profile и snapshot registration-review/console. Указанные в регистрации адреса не записываются в публичныйstage: он использует symbol+offset.

PS5 Prepare/встроенный Inspect завершился exit0 / KD_QUERY_SESSION_FILES_VALIDATED:8288 frozenfiles,8197 runtimefiles, connections4, product_started/traffic_generated/driver_installed/debugger_control/runtime_ready=false. Это готовность файлов, не доказательство runtime/action behavior. После проверки сохранность10 prior source/stage/plan и69 full-control capturefiles проверена отдельно. Private итогvalidation.json вpb-kd-query-session-preparation-review-20261017; данные/kit/fixtures вGitне добавляются.

Комплект допускает только одну baselineфазу4,512KiB/8s на соединение, один исходный query, original listener/delay0, ConnectEx/pending32. Нет load/recovery entry point. Минимум доступнойRAM2ГиБ;60s предел ожидания native клиента/180s бюджет фаз, startup/hash/cleanup вне бюджета. Pinned CLI/Core/stock driver прежние, product build/driver installation/debugger automation отсутствуют.

Проверки PS5/PS7 parser и pure reporter на адаптированной **копии старого** fourcapture пройдены: native evidence принято/debuggerpending, адаптированный full968capture отвергнут. Raw старых captures не менялись, нового Run эти проверки не создают. Точное сравнение двух CIM boot timestamps сначала отклонило различие319мкс у одной загрузки; guard сравнивает оценку boot UTC с допуском1с. Это ограниченный fail-closed guard для данного сеанса, не криптографическая bootidentity; большие сдвиги clock/CIM могут потребовать нового review. При несоответствии он прекращает Run, не перезагружает VM/не чинит manifests. Private boot-comparison-observation.json сохраняет проверку до первого Run.

## Предлагаемый порядок одной пробы после отдельного согласования

Сейчас enable/Run не выполнять: новый Run ещё не согласован. Инструкция конкретна, но требует свободной общейVM; USER сохраняет её в Блокноте до закрытия GPT/Codex. На рабочем столе будет `PB-KD-Query-Four-20261017.txt`. Достаточность RAM после закрытия нужно проверить, не считать гарантированной.

1. Сохранить **на физическом ПК** команды enable и recovery. **Break/enable останавливают или могут задержать всю VM, включая Codex/RDP.** Stage повторно не загружать. При activekd> повторныйBreak не нужен. Вводить каждую outer command отдельно. До начала вbl должны быть только3/4, обеd, с неизменными ранее сверенными targets/actions. При отличии отдельныйg, остановить опыт и прислать inventory.
2. После согласования закрыть ненужные приложения/GPT штатно, сохранить работу; никаких параллельных тестов/запусков разработки. Проверить свободнуюRAM в административном PowerShell VM:

```powershell
Get-CimInstance Win32_OperatingSystem | Select-Object @{Name='FreeGiB';Expression={[math]::Round($_.FreePhysicalMemory/1MB,2)}}
```

Нужен запас выше2ГиБ, желательно около3ГиБ до helperstartup. При≤2ГиБ не выполнять enable/Run. Порог не снижать. Если GPT закрыт, выполнять следующие пункты по сохранённой инструкции.

3. **На физическом ПК Break вновь остановит всю VM/Codex/RDP.** Затем отдельноbl, отдельноbe3, отдельноbe4, отдельноbl: только3/4обаe. При ошибке/несоответствии отдельноbd3, отдельноbd4, отдельноbl, затем отдельныйg даже после ошибки. При успехе отдельноg и только затем VM Run.
4. В административном PowerShell VM выполнить блок один раз. SHA сравнивается автоматически, при несовпадении Run не вызывается:

```powershell
$pbQueryPreparation='C:\src\ProxyBridge-TestLab\artifacts\diagnostics\pb-kd-query-session-preparation-20261017-063031-cfbfaa59'
$pbQueryPlanSha='7E90EA90F7FD8F2CCA02D9459A9C38F129369E6ED2B8BD40D759A413B073416A'
if ((Get-FileHash -LiteralPath (Join-Path $pbQueryPreparation 'runtime-plan.json') -Algorithm SHA256).Hash -ine $pbQueryPlanSha) {
    throw 'PLAN_SHA_MISMATCH: Run не выполнялся'
}
powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\src\ProxyBridge-TestLab\scripts\Invoke-KdQuerySession.ps1' -Phase Run -PreparationDirectory $pbQueryPreparation -QueryProfileReviewed -DebuggerLoggerEnabled
```

5. Дождаться возврата PowerShell и очистки. Проверка тысяч файлов в начале может быть молчаливой. При ошибке/timeout не повторять Run. Если VM неожиданно остановилась вWinDbg, сохранить сообщение на физическом ПК и вводить recovery по одной:bd3,bd4,bl,затемgотдельно даже после ошибки. После продолжения дать PowerShell закончить очистку.
6. После возврата PowerShell **ещё один Break снова остановит всю VM, включая Codex/RDP**. По одной:bd3,bd4,bl,затемотдельныйg. Только после отключения точек открыть чат. Сохранить весь consoleWinDbg от enableинвентаря до finaldisabled/g и полный PowerShell вывод/путь результатов. Logopen не требуется. Две точки остаются отключёнными.

## Что проверять после одной пробы

Сначала native/Core completeness/данные/очистку, затем actual QUERY_READ/QUERY_STATUS для конкретных Core запросов. Ожидаем по4 соответствующих события при полном захвате, но общее число строк с чужимиPID не доказательство. Сопоставлять kernelPID/TID/scope/endpoint и последовательность Coreseq/socket; при параллельных/пропущенных запросах не объявлять binding доказанным. Общей Core↔KD QPC и независимого socket/seq вKD нет.

Для successfulAPI ожидается kernelstatus0; если встретится API10022, статус/record должны проверяться для того же flow. Отсутствие failedflow на4 не опровергает96/968контроль. UNREADABLE/WinDbgerror/incompletecapture требуют остановки и разбора, не автоматической нагрузки. Две точки не показывают CREATE/attach/free и не устанавливают механизм потериrecord.64/256 остаются отдельным последующим решением после console-reviewчетырёх.

**Текущий стоп:** Prepare/Inspect проверен, комплект готов; отдельно согласовать один USER Run на4 при свободнойVM. Регистрация проверена, actuallogger/kernelbinding ещё нет. До согласования не be/Run. Агент не выполняет debugger/Run, не меняет продукт/поддерживаемыеtests/драйверную установку/BCD/гипервизор/питание/соседнийworktree. Privateaudit/kit/captures не в Git.
