# Код выбранных мест подтверждён; следующий шаг — проба форматов и guards

**Обновление:** USER проба из attachment9e0dddc2 прошла; отдельный g записан. Текущий стоп-пункт — [новая регистрация семи отключённых точек](KERNEL_CONTEXT_MINIMAL_STAGE_2026-10-16.md). Пробу повторять не требуется; дальнейший текст сохраняет условия и состояние её подготовки.

USER attachment d5231444, 10131 bytes, SHA256 `1490f462856db2852ca7480516449419544e5c7ade80c2abf6ca5ebc083e046b` сохранён без изменений. Прочитано124 live-инструкции:116 byte-exact PE,8 составляют4 структурные пары import-call rewrite (mov R10 из того же IAT + direct call вместо indirect call/NOP). Неклассифицированных различий нет. Все7 выбранных sites byte-exact; один padding INT3 не выводился uf. Это ограниченная проверка кода, не whole-image hash и не наблюдение исполнения lifecycle. Audit `artifacts/diagnostics/pb-kd-reconnect-review-20261016/live-code-validation.json`.

UF выдал `Unable to load image ... NETIO.SYS, Win32 error 0n2`; нужные инструкции TCP/IP при этом выведены. Два NETIO call targets сохранены как адреса без подтверждения NETIO identity/символов. Это ограничение разрешения внешних вызовов, не доказательство отказа продукта. Для нового профиля точки NETIO не предлагаются. IDCHECK успешно прочитал текущий ETHREAD.Cid: PID/TID0/0, без syntax/memory ошибок; это не nonzero owned PID/TID или query Core binding. Отдельный g записан.

## Уточнения нового профиля

Предложены7 новых IDs0..6 в [неисполняемом проекте](../scripts/debugger/pb-kd-minimal-profile-20261016.json). Это не команда установки; installation_allowed=false. Прежний subset IDs1/7/9/10/11/14/15 относился к существовавшим25 точкам, которых в новом сеансе нет. Старые manifest/stage/kit остаются историей без изменений; их не загружать и не refreeze/Resume.

События: CREATE_POST, ACCEPT_RETRIEVE_RESULT, **ACCEPT_JOIN**, QUERY_READ, QUERY_STATUS, FREE_ENTER, FREE_CALL_RETURN. Сайт accept+cbe является общим join: к нему ведут также skip/error ветки без retrieval/store. Поэтому прежнее название AFTER_STORE не использовать как самостоятельное доказательство записи. Нужна связанная успешная retrieval-пара и совпадение endpoint/record в том же вызове. При ошибке retrieval поле raw_output_slot не объявлять действительным record. FREE_CALL_RETURN подтверждает возврат функции, не проверку всего allocator.

Добавлен **проект** guards через [MASM $vvalid](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/masm-numbers-and-operators): сначала проверить доступность диапазонов, затем читать poi/dwo в будущих actions. В guard нет poi/dwo и числовых CID offsets; адрес Cid получается через matching types. Нечитаемые данные должны приводить к маркеру неполного capture и gc, а не продолжению чтений. Реальное поведение действий/gc ещё не проверено, защиты от всех debugger failures не обещаем. Общесистемных fwpkclnt/NBL/allocator точек, включая неисправную17, в проекте нет.

Перед регистрацией нужно проверить **новый** синтаксис guards и7 форматов в текущем WinDbg. Именно это делает следующая проба. Она не устанавливает точки, не вызывает target functions, не меняет память/registers и не запускает нагрузку. Печатает реальные значения только текущего ETHREAD.Cid/thread; остальные поля — синтетические константы. $vvalid дополнительно проверяет доступность диапазонов, вычисленных из нынешних registers; содержимое этих диапазонов не печатается. Не называть такую пробу полностью memory-free.

## 1. Файлы на физическом ПК, без Break

Архив на Desktop VM: `PB-KD-Minimal-Probe-20261016-r2.zip`,3704 bytes, SHA256 `825540a4fd0c2cd3684ecdf3992fa4d2e9374d8bef4f215e612f103a1e741c9a`. CRC/byte roundtrip и Desktop copy проверены. Архив содержит ASCII/CRLF probe, неисполняемый JSON-проект и README; PDB/продуктовых binaries/bp-stage в нём нет. Внутренний probe SHA256 `19ba320bf6af55b9bf24b66cd724447785964ae13bdcea96c4fc6eeef7362073`. Runtime ещё не выполнен. Private audit `artifacts/diagnostics/pb-kd-reconnect-review-20261016/minimal-probe/validation-r2.json`. Первая неиспользованная упаковка сохранена, передавать только r2.

Скопировать архив на физический хост в `D:\Загрузки\PB-KD-Minimal-Probe-20261016-r2.zip`. В PowerShell физического хоста по отдельности:

`Get-FileHash -LiteralPath 'D:\Загрузки\PB-KD-Minimal-Probe-20261016-r2.zip' -Algorithm SHA256 | Select-Object -ExpandProperty Hash`

Продолжать только при указанном SHA. Затем в новую папку, без -Force:

`Expand-Archive -LiteralPath 'D:\Загрузки\PB-KD-Minimal-Probe-20261016-r2.zip' -DestinationPath 'C:\PB-KD-Minimal-Probe-20261016'`

При ошибке или несовпадении не выполнять Break, не перезаписывать старые папки/архивы, прислать вывод. JSON в WinDbg не загружать. PDB path C:\PB-KD-Symbols-20261016 сохраняется, повторный reload не нужен.

## 2. USER probe, без регистрации точек

Сохранить команды на физическом ПК. Если на общей VM идёт другой согласованный тест, дождаться завершения. **Break остановит всю PB-BUILD-W11-25H2, включая Codex и RDP.** Если уже есть активное kd>, повторный Break не нужен. После одного Break ввести одну команду:

`$<C:\PB-KD-Minimal-Probe-20261016\pb-kd-minimal-format-probe-20261016.wdbg`

После окончания или ошибки обязательно **отдельно**, с отдельным Enter:

`g`

Никаких stage/patch/bp/be/Run и повторного выполнения при ошибке. Проба не содержит внешнего g/gc и сама не возобновляет VM. При неожиданной повторной остановке сохранить сообщение и g отдельно. Полный console прислать в чат, logopen не требуется.

Ожидаются MASM, пустые bl до/после, BEGIN/END,7 полных PBKDM_PROBE event rows, CID_RANGE_OK, NULL_GUARD_OK, IOCTL_TRUE_OK/IOCTL_FALSE_OK и7 GUARD_EVALUATED rows. readable=0 в последних допустим при произвольных нынешних registers вне места события; это не ошибка продукта. Исполненные UNEXPECTED/CID_RANGE_UNAVAILABLE, syntax/memory errors или потерянные строки означают, что проба не прошла. Успешная проба не проверяет реальные endpoint/record reads или gc.

Сначала проверить USER результат этой пробы. После него отдельно подготовить новый отключённый stage7, проверить его регистрацию и только потом решать вопрос о свежем four-only baseline kit. Сейчас ни stage7, ни baseline kit не созданы. Полная нагрузка64/256/640/recovery, изменение продукта/драйвера и агентское управление debugger/Run остаются за границами.
