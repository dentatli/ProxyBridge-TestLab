# Регистрация отключённого packet logger

2026-10-08. Проба USER `pb-context-packet-identity-v2_03f8_2026-10-08_19-09-11-184.log` прошла. 16964 bytes, SHA256 `8934f1ceb496b281059c9b70b2c8d6cdd628335a6a4f1bdd887f70fdb8651634`: все 26 полных printf rows, MASM, FALSE_PATH_OK/END, без ошибок/усечённых команд. Физическая копия probe имеет подтверждённый USER SHA256 `8816e3ec…`, равный исходнику.

nt PDB загрузился без override, live header FDA9ED74/C817D5/1450000 совпал с дисковым ядром; типы показали Cid +508h, UniqueProcess +0 и UniqueThread +8. Для выражений используются имена полей, не эти числовые смещения. Текущий thread fffff8017c9d25c0 вернул PID/TID 0/0. Это успешный разбор/чтение выражения, **не подтверждение PID/TID процесса ProxyBridge или owned query**. Все прежние 14 точек остались d, адреса/тела прежние. Logclose записан; последующий g вне закрытого журнала не наблюдается.

Причина исходной ошибки C0000225/WSA10022 пока не доказана. Проба использовала synthetic packet fields, не исполняла breakpoint actions, настоящие memory conditions или gc. Не переходить к полной нагрузке по этому результату.

## Что подготовлено

Архив на Desktop VM: `PB-KD-Packet-Logger-20261008.zip`, 6676 bytes, SHA256 `2fb0661b3558f4db9fb314cb6f1f75e33124e37b4b9ef68d6ed53639eee79901`. Внутри три ASCII/CRLF command files, READ-ME, ожидаемые тела всех точек и SHA файлов. CRC/byte roundtrip проверены, binary/capture/keys отсутствуют.

Entry `scripts/debugger/pb-context-packet-stage.wdbg` заменяет только существующие 1/2/10/11 и добавляет 14..24. Остальные 10 точек сохраняются. Каждая зарегистрированная точка немедленно отключается, target остаётся остановленным. Ни be, ни внешнего g, ни workload нет. Внутренние `$$<` вызовы отделены semicolon согласно [документации Microsoft](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/-----------------------a---run-script-file-); внешний `$<` вводится отдельной командой.

Guard проверяет адреса прежних 14 точек, отсутствие номеров 14..31 и первые два байта в 15 новых/заменяемых boundaries. Это ограниченная проверка кода, **не полный hash live images**. `$bpNumber` — документированный адрес точки, но runtime исполнения guard ещё не проверен. Состояние d, MASM, отсутствие дополнительных IDs вне диапазона и тела проверяются вручную по bl/.bpcmds. Без этого entry не загружать. Internal body/code-gate напрямую не загружать. Повторная загрузка должна быть отвергнута occupied-ID guard; это требование пока проверено только офлайн.

Новые действия используют проверенные форматы и typed Cid, key 5/callback selector; оба пути условных действий заканчиваются gc. Старые сохранённые действия остаются без изменений. Они читают raw context/NBL/endpoint metadata, не packet payload. После allocator free record не разыменовывается. Инструкция BODY_END означает завершение регистрации, **не actual memory/ownership coverage**. Таблица 25 точек и ограничений — в [плане](KERNEL_CONTEXT_PACKET_LOGGER_PLAN.md).

## Следующий USER шаг — только регистрация

1. На физическом ПК распаковать весь архив в `C:\PB-KD-Packet-Logger-20261008`. Сохранить структуру: три .wdbg внутри `commands`. Прежние candidate/conditional patch не загружать; текущие symbols не перезагружать без новой причины.
2. Подготовить команды на физическом хосте. **Break приостанавливает всю VM, Codex и RDP.** Каждую внешнюю команду вводить отдельно, Enter после каждой:

   `.logopen /t C:\Users\Administrator\pb-context-packet-stage.log`

   `bl`

   `.expr`

3. Продолжать только если bl содержит ровно прежние 14 разрешённых точек 0..13, все d, а evaluator MASM. Если условие не выполнено, пропустить script, `.logclose` и `g` отдельно, отправить журнал.

   `$<C:\PB-KD-Packet-Logger-20261008\commands\pb-context-packet-stage.wdbg`

   `bl`

   `.bpcmds`

   `.logclose`

   `g`

4. Ожидаются ровно 25 разрешённых точек 0..24, все d, BODY_END и отсутствие ошибок/REFUSED. Если script ошибся, ничего не включать. Сохранить bl; любую присутствующую нашу точку e отключить по её известному ID (`bd [0n14]` для существующей точки 14), снова bl. Затем logclose и **g отдельно даже при ошибке**; при новой остановке сохранить сообщение и снова g отдельно. Прислать журнал регистрации **до включения точек и Run**.

## Новый комплект для последующей проверки четырёх соединений

Подготовлен отдельный files-only `pb-kd-packet-baseline-preparation-20261008-142037-5bdac43e`: 69 frozen SHA, Prepare/Inspect PS5 и Inspect PS7 успешны. Новый `Invoke-KdPacketBaseline.ps1`/`pb_prepare_kd_packet_baseline.py` сохраняет старые источники и used plans; исходный four-connection workload и shared controllers/modules не изменены. Прежние CLI/Core/driver копируются byte-identical (bundle a0e0cf31…), без сборки/подписи/установки. Четыре ConnectEx/32 соединения, hold 8s, по 512 KiB, один исходный query, local SOCKS5/original queue; no load/recovery/OFF/kernel collector. Reporter сохраняет status DEBUGGER_PENDING, не выдаёт product PASS по одному native успеху.

Новый wrapper замораживает stage source/manifest/v2 probe и packet policy IDs 0..24. Требует USER `PacketStageReviewed` и `DebuggerLoggerEnabled` перед Run, имеет прежние admin/mutex/boot/cleanup gates; acknowledgement не доказывает регистрацию или coverage. Cleanup message указывает новые 0..24. Его files-only policy prefix проверен PS5/PS7: valid принят, семь неверных policy вариантов отклонены. Files-only workload prefix PS5/PS7 подтвердил три pinned components/identity, нагрузка/SCM/target control не исполнялись. Actual Run, PID/TID owned query, association/consumption/free/query bridge пока pending. Длительность с serial traps не обещана менее пяти минут.

После проверки USER stage log можно дать конкретный enable/four-connection Run/disable handoff. До этого не давать старый 111941 Run, не включать точки и не запускать full workload. 44 прежних USER files, два новых USER logs и 62 hashes старого used kit сохранены; старые планы не refreeze/Resume. Audit: `artifacts/diagnostics/pb-kd-packet-stage-review-20261008/`.
