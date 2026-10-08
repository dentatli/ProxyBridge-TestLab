# План logger для packet metadata

2026-10-08. USER host log `pb-context-packet-code_03f8_2026-10-08_17-31-08-472.log` проверен офлайн. Причина исходных сбросов пока не доказана. Logger ниже — **неисполняемый draft**, не установленный набор точек и не готовый Run.

**Обновление:** USER v2 format log 19:09 прошёл, SHA физического probe совпал. Подготовлены отдельные команды регистрации **отключённых** 25 точек и новый files-only kit на четыре соединения. Следующий шаг — [проверка регистрации](KERNEL_CONTEXT_PACKET_LOGGER_STAGING.md), не повторная format probe и не Run. Ниже сохранён предыдущий этап с первой неудачной пробой.

## Последний результат: первая format probe не прошла

USER log `pb-context-packet-format_03f8_2026-10-08_18-49-33-692.log`: 13575 bytes, SHA256 `7347b514cffc83116c3990ddc097e3bb906dbd6720791de9c4b9d1341233e556`. WinDbg отверг `@$tpid` в полных printf командах; доступность `@$tid` отдельно не доказана. Две echoed команды имели усечённое начало (`f` и `rintf` вместо `.printf`). Причина усечения неизвестна: SHA физической копии не предоставлен, локальный исходник и прежний архив целы. Все 14 точек имеют прежние адреса/тела и состояние d. END/FALSE_PATH_OK/logclose достигнуты, но это **не успех probe**; отдельный g в закрытом log не записан.

Это ошибки подготовки отладчика, не наблюдение сброса или утраты контекста. До успешной проверки нового вывода нельзя готовить устанавливаемый patch, включать точки или запускать нагрузку. Старый probe и использованный 111941 frozen kit не изменяются.

В кэше найден `ntkrnlmp.pdb`: GUID `c29ebfb0-6b78-b3c0-20dc-a66d99713f9e`, PE/DBI age 1 (PDB save age 6). GUID/DBI age совпадают с дисковым `ntoskrnl.exe` SHA256 `d90c69cf…`, version 26100.9457, timestamp FDA9ED74/image size 1450000/checksum C817D5. Offline dbh видит типы `_ETHREAD` и `_CLIENT_ID`; это не проверка live module или конкретных expressions.

Новый `pb-context-packet-format-probe-v2.wdbg` использует поля `@@c++(@$thread->Cid.UniqueProcess)` и `UniqueThread`, **без числовых смещений CID**. [Документация Microsoft](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/c---numbers-and-operators) описывает typed `$thread` и вложенный C++ evaluator. В конкретном сеансе выражения ещё не проверены. Неисполняемый manifest остаётся DRAFT_NOT_INSTALLABLE; его зависимость от matching nt PDB и pending identity validation указана явно.

Архив на Desktop VM: `PB-KD-Packet-Identity-20261008.zip`, 2802237 bytes, SHA256 `8affa57b2863b8bc54ba7db15b19eb75d09dd1f32c032b5234df544a7d034c33`. Только PDB, v2 probe и инструкция; CRC и byte roundtrip проверены. Probe — ASCII/CRLF, 26 printf с проверенным числом аргументов. CRLF выбран для нового файла, но не заявлен как доказанное исправление причины усечения. Читаются только CID текущего thread и type information; connection memory, payload и target functions не читаются/вызываются.

Следующий шаг на **физическом хосте**, без тестирования продукта:

1. Скопировать новый архив и распаковать целиком в `C:\PB-KD-Packet-Identity-20261008`. Существующий `C:\PB-KD-Symbols` не заменять. В PowerShell до Break проверить физический файл: `Get-FileHash -LiteralPath 'C:\PB-KD-Packet-Identity-20261008\commands\pb-context-packet-format-probe-v2.wdbg' -Algorithm SHA256`. Ожидаемый SHA256 `8816e3ec025dc454f64c5f2913636a2ca6c34184855b7b96cd8c38e7dccdedcc`.
2. Подготовить команды на хосте. **Break приостанавливает всю VM, Codex и RDP.** Каждую внешнюю команду вводить отдельно, Enter после каждой:

   `.logopen /t C:\Users\Administrator\pb-context-packet-identity-v2.log`

   `.sympath+ C:\PB-KD-Packet-Identity-20261008\symbols`

   `.reload /f nt`

   `$<C:\PB-KD-Packet-Identity-20261008\commands\pb-context-packet-format-probe-v2.wdbg`

   `.logclose`

   `g`

3. Если загрузка nt завершилась ошибкой, probe пропустить; `.logclose` и `g` отдельно. Не использовать `/i` для игнорирования несовпадения. Даже при любой ошибке probe ввести `g` отдельно; при новой остановке сохранить сообщение и отдельно g ещё раз.
4. Прислать новый host log и SHA физической копии. Ожидаются matching nt PDB, readable Cid fields, 26 полных PBKDP2_PROBE строк без ошибок, FALSE_PATH_OK/END, прежние 14 d. Эти наблюдения не заменяют последующую проверку работы точек и ownership на четырёх соединениях.

Audit: `artifacts/diagnostics/pb-kd-packet-format-review-20261008/{validation,package-validation}.json`. Прежние 44 USER files, новый USER log, оба старых probe файла/архив и все 62 frozen SHA защищены. Новый frozen kit и команды установки не созданы.

## Проверка присланного кода

Исходный log: 98012 bytes, SHA256 `fdb0b777929f645b399804ce7e8f872085bd27daaa2c4eb168503506b9f37b9f`. Все 14 существующих точек 0..13 имеют прежние адреса/тела и состояние d. Все markers инспекции достигнуты, logclose записан; последующий отдельный g в уже закрытом log не фиксируется. Доступность VM не заменяет запись g в журнале.

1037 инструкций семи выбранных фрагментов сопоставлены с PE: 955 byte-exact, 78 инструкций образуют 39 пар import call rewrite (mov R10 из прежнего IAT + direct call вместо indirect call/NOP). Ещё четыре direct call target отличаются: один вызов в Associate и три dispatch вызова в Notify. Это **не полное совпадение байтов загруженных модулей** и не доказательство причины сброса. Сами direct targets и структурные различия сохранены в audit, семантика их подмены не заявлена.

Live fwpkclnt base fffff801`0fa10000, Timestamp 93E8A9FC, ImageSize 8B000, CheckSum 96DAE совпали с дисковым файлом SHA e846c63a…. Selected instruction boundaries предложенных точек подтверждены по текущим/предыдущим USER disassembly; их read sites описаны ниже.

Единственная ошибка команды инспекции — `Symbol nt!_ETHREAD not found` при dt Cid. Это отсутствие type information в текущем symbol set, не ошибка продукта и не наблюдение утраты контекста. Новое скачивание/загрузка nt PDB не выполнены. Для следующей проверки выбраны документированные [$tpid и $tid](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/pseudo-register-syntax); доступность этих значений именно в текущем live сеансе ещё должна быть проверена. Эти IDs не являются единственным owner filter на packet/DPC пути.

Audit локально: `artifacts/diagnostics/pb-kd-packet-code-review-20261008/validation.json`, `final-validation.json`. Исходный USER log и прежние 44 protected files не изменены; все 62 frozen SHA использованного 111941 plan совпали. План не refreeze/Resume.

## Предлагаемый набор

Неисполняемый manifest: `scripts/debugger/pb-context-packet-logger-draft.json`. Он содержит 25 предполагаемых точек 0..24, выражения полей и conditions. Он не содержит команды установки или включения.

| ID | Точка / назначение |
| --- | --- |
| 0, 5..9, 12..13 | Сохранить прежние create-pre, deref и free/allocator boundaries |
| 1 | Дополнить create-post context pointer/size/refs и raw sockaddr metadata, чтобы не зависеть от отдельной create-pre строки |
| 2 | Вместо шумного NULL-parent read наблюдать Accept непосредственно перед Retrieve call |
| 3, 4 | Сохранить явные parent store/clear boundaries — альтернативный путь переноса не исключён |
| 10, 11 | Query read/status с текущими PID/TID, только исходный IOCTL 980000DD |
| 14, 15 | Return status/output retrieval и состояние endpoint после возможного store; after-store boundary также достижима при обходе call, поэтому flags/ESI выводятся и наличие store не предполагается |
| 16, 17 | Association entry/return, key 5 и callback TlShimNblEventNotifyFn; явные NBL/record/caller arguments и исходный raw return |
| 18 | Callback raw event, source/peer NBL, record и key; не присваивать event номеру публичную семантику без доказательства |
| 19, 20 | Generic Retrieve: matched active tag, его record до внутренних операций и output pointer/value после них |
| 21, 24 | Оба return пути Retrieve с исходным status |
| 22, 23 | Результат сканирования и entry всех Retrieve key 5, включая другие callers |

Association prologue уменьшает RSP на 58h (три push + sub40h); входные key/callback в +28h/+48h соответствуют +80h/+A0h на return boundary до восстановления регистров. **R14 в generic пути переприсваивается**: return row не называет R14 исходным record. Для результата используются входные stack slots, NBL из сохранённого RBP и raw RAX; entry связывается с return по thread и исходному stack frame при подтверждённой полноте.

Retrieve prologue уменьшает RSP на 68h. Generic match проверяет active flag +B8h и key +10h, затем использует value +8. Output row не разыменовывает tag после внутренних removal/release вызовов — сохраняет только его адрес и читает pointer из output slot, который непосредственно перед этим записан кодом. Record после free не разыменовывается. Alternate return находится на +30Fh (RVA343F), не +310h внутри инструкции.

Нет PID-only фильтра на packet пути, чтения packet payload, изменения status/context/query или записи в target memory. Условия новых точек должны завершаться gc в обеих ветках при будущей установке. Никакой BP patch пока не сгенерирован/применён. Ограничения остаются: нет покрытия произвольных записей в поле, полного endpoint lifetime или доказанного native tuple/Core query bridge. Количество/порядок четырёх строк не заменяют ownership. Отсутствие одной строки не доказывает уничтожение записи. Полная нагрузка до подтверждения baseline coverage запрещена.

## Исторический шаг: первая format probe (завершилась ошибками)

Подготовлен `scripts/debugger/pb-context-packet-format-probe.wdbg`, архив на Desktop VM `PB-KD-Packet-Format-Probe-20261008.zip`. В архиве только probe, без draft/команд установки. Проверены CRC, byte roundtrip, 26 printf с совпадающим числом аргументов, markers, synthetic true/false paths. Это проверки файлов, **не проверка реального исполнения WinDbg**.

Probe выводит текущие thread/PID/TID/stack, затем synthetic значения форматов 25 событий. Он читает .expr и bl, не включает/изменяет точки, не читает память соединений, не запускает целевые функции, не меняет symbols и не содержит внешнего g. Внутренние .if используют constants; реальные conditions с memory reads и runtime gc этим probe не проверяются.

1. На физическом ПК распаковать `pb-context-packet-format-probe.wdbg` непосредственно в `C:\PB-KD`. Старые candidate/conditional patch не загружать.
2. Подготовить команды. **Break приостановит всю VM, Codex и RDP.**
3. После Break вводить каждую внешнюю команду по одной, Enter после каждой:

   `.logopen /t C:\Users\Administrator\pb-context-packet-format.log`

   `$<C:\PB-KD\pb-context-packet-format-probe.wdbg`

   `.logclose`

   `g`

4. Даже при ошибке сохранить вывод и ввести **g отдельно**. Если произошла повторная остановка, сохранить сообщение и отдельно g ещё раз. Прислать созданный host log.

Ожидаются MASM, CURRENT_IDS без ошибки, 25 synthetic event rows, FALSE_PATH_OK, END и прежние 14 d. Не запускать тест, не включать точки. После проверки probe можно подготовить конкретный guarded patch и **новый** frozen baseline kit; используемый 111941 kit не менять. Ни один из этих подготовительных шагов не устанавливает root cause автоматически.
