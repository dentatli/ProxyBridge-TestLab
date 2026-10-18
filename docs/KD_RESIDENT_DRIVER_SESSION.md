# Диагностика с драйвером, оставленным в памяти

## Первый resident four: workload прошёл, аппаратный автологгер остановился

Run174017-c0dcbb02 имеет4 native/Core success, все query32bytes, errors[], resident before/after DISABLE success с одним session_id иRunning, run-receipt COMPLETED/workers_stopped=true/driver_stop_observed=false/resident_disable_observed=true. Controller17:40:17.1666918Z→17:41:46.1239689Z. Агент read-only SCM Running; original10022 не воспроизведён.

USER screenshot послеbe2/g показывает один снимок порт50158/PID7080, затем first chance Single step80000004 наClassifyCore+3de, processor5. Послеэтого USERbd2/TOTAL1/ddgEnabled1/отдельныйg. Порядок этого чтения относительно записанной17:41:45.8308471Z after-cleanupкоманды не установлен; нельзя объявитьниcleanupfailure,нидоказанное текущееgEnabled0. Автологгер не оставался подтверждённо активным на весьcohort, поэтому TOTAL1 не является доказательствомпропуска3Applycalls. Eventcauseне установлена; не делать вывод Windows/драйверbug. Screenshot справаобрезан; невидимые поляне достраивать. Privatecopy/review `pb-hardware-resident-four-result-review-20261018`.

Следующий шаг — USERread-only sx и текущийddgEnabled послезавершения Run; beforeBreakwholeVMwarning, затемотдельныйg evenerror. Не менятьфильтры/gc и не повторятьRunдоразбора. [Microsoft sx](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/sx--sxd--sxe--sxi--sxn--sxr--sx---set-exceptions-) разделяет настройки остановки и обработки исключений; чтение sx ихне меняет. [gc](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/gc--go-from-conditional-breakpoint-) документирован для loggerbreakpoints; факт остановки здесь сам по себе не доказывает ошибку gc.

## Hardware registration подтверждена USER console

Подготовлен только files-only four plan `pb-kd-session-plan-20261018-173830-08d08690/runtime-plan.json`, SHA256 `55AD385EDDC0B76F1738CAE72D7FADDBED6F34041158966235EF803D931A0B59`; Prepare exit0, runtime/product/traffic/debugger не запускались. Policy resident-disabled/four/active2 проверена. Результата Run пока нет.

После bc2 создана `ba2 e1 ProxyBridgeDrv!ClassifyCore+0x3de`, немедленно bd2; t0 обнулён. `.bpcmds` показывает именно аппаратную e1 поfffff8026c131696, прежнюю snapshot action иbd2; отдельноg. SCM read-only Running. Private review `pb-driver-hardware-resident-registration-review-20261018`, толькоfour/currentboot. Runtime action и полнота hardware захвата пока не проверены. Первый resident four должен после cleanup оставить Running и successful DISABLE receipts; после USER bd2 полезно независимо прочитать dd gEnabledL1 и TOTAL, затем отдельноg. Не выгружать/не reboot с сохранённой hardware точкой.

## Live load перед регистрацией hardware

USER подтвердил private PDB и live call ClassifyCore+3de на base fffff8026c130000 (RVA1696), bytes e8d3110000/488b4de8; PE метаданные совпали с reviewed SYS. gEnabled по6c1362cc равен0, отдельноg. Agent read-only SCM Running. Private `pb-resident-driver-review-20261018/live-load-observation.json`. Это чтение состояния до пробы; аппаратная регистрация и resident runtime пока не проверены. Следующий шаг только bc2/ba2 e1/bd2/rt0=0/.bpcmds/отдельныйg, с предупреждениями перед Break/созданием точки. Оставить драйвер Running, без нового Run до разбора регистрации.

USER предложил не перезагружать драйвер между пробами. В pinned source `pb_driver_stop()` отключает перехват IOCTL и закрывает handle; выгрузка службы была отдельным действием TestLab. Служба Running и включённый перехват — разные состояния. Продукт не менялся.

## Изменение запускателя

Профиль с `driver_lifecycle=resident-disabled` выбирает отдельный диагностический режим, пока только four. Без поля сохраняется прежняя политика unload. Перед Run пользователь должен один раз загрузить существующую службу и проверить live code/PDB/адрес аппаратной точки. Агент этого не делает. Существующий universal launcher и общие ресурсы переиспользуются; новые копии runtime не нужны.

Preflight требует Running, проверенный service file, только один известный interception driver, отсутствие Core/CLI и прежние проверки WFP/WinDivert. Затем открывается device handle, который удерживается на время пробы, и выполняется только `PBDRV_IOCTL_DISABLE` (0x22a00c, без буфера). Константа и синхронное `InterlockedExchange(gEnabled,0)` сверены с pinned исходниками. Включение перехвата остаётся штатной операцией Core. После завершения Core/работников повторяется Disable, проверяется Running и отсутствие продуктовых процессов. Handle закрывается; Stop-Service в этом режиме не вызывается, в том числе при ошибке. При неудачной очистке отчёт incomplete, автоматическая выгрузка под активной hardware точкой не выполняется.

Два receipts имеют один session_id, правильную операцию/device/IOCTL, completed=true, service_state=Running и driver_unloaded=false. Отчёт проверяет их и before/after observations; driver_stop_observed остаётся false. Это подтверждение успешного синхронного IOCTL по известному контракту, не независимое чтение gEnabled, не полная выгрузка WFP и не готовность переключать версии. Нового readback IOCTL в продукт не добавляли.

## Аппаратная точка

Кандидат `scripts/debugger/pb-kd-driver-apply-hardware-resident-candidate-20261018.json`: одна `ba2 e1 ProxyBridgeDrv!ClassifyCore+0x3de`, прежний snapshot action без изменений. Привязка действует только для проверенного текущего load. Перед выгрузкой/перезагрузкой надо отключить и удалить ba2 на хосте, затем отдельно g. Нельзя использовать адрес предыдущего load или старый план. До live review/disabled registration нового runtime plan нет.

Здесь меняются одновременно тип точки и жизненный цикл драйвера. Даже полный захват 4/4 не докажет, что прежние пропуски были вызваны исключительно software breakpoint. Критерий первой пробы: все четыре native/Core соединения и соответствующие портам снимки либо явный неполный захват; не объявлять исправление10022. Bounded пока запрещён этим режимом.

## Другие инструменты

В VM найдены wpr.exe, netsh.exe, PktMon.exe; они не запускались. [ETW/WPR](https://learn.microsoft.com/en-us/windows-hardware/test/wpt/event-tracing-for-windows) подходят для временной линии и нагрузки; [netsh wfp capture](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/netsh-wfp) — для WFP событий. Наличие нужных полей private redirect record в конкретных providers ещё не подтверждено. Захват пакетов помогает сопоставить retry/reset, но сам по себе не доказывает создание/прикрепление/освобождение контекста. Сначала не добавляем параллельную трассировку к проверке аппаратной точки. Смена транспорта KD может повлиять на скорость, но требует отдельного согласования изменения BCD/VM; сейчас не выполнялась.

## Офлайн-проверка

9 session tests и4 resident-receipt tests прошли. PowerShell5.1 parser и компиляция C# P/Invoke declarations прошли без открытия device/IOCTL. Служба до/после Stopped. Разбор старых captures four0fails и bounded32fails сохранил прежние результаты. Синтетический resident fixture принят только с корректными receipts; failed Disable отвергнут. Это проверки диагностического кода, не runtime доказательство нового режима. Private audit `pb-resident-driver-review-20261018`.

При подготовке команды проверки была ошибка quoting вложенного PowerShell: внешний shell подставил переменную. Вместо повторения использован отдельный private check.ps1, проверка exit0. Gate bypass не применялся. Приватные fixtures и captures в Git не добавлять.
