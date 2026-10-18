# Диагностика с драйвером, оставленным в памяти

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
