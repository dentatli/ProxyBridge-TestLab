# План logger для packet metadata

2026-10-08. USER host log `pb-context-packet-code_03f8_2026-10-08_17-31-08-472.log` проверен офлайн. Причина исходных сбросов пока не доказана. Logger ниже — **неисполняемый draft**, не установленный набор точек и не готовый Run.

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

## Сейчас: только format probe

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
