# Проба прошла; следующий шаг — регистрация семи отключённых точек

USER attachment9e0dddc2,6554bytes,SHA256 `e958235cb22fa2f9b4d9aa7795cae7bd3dcbc624e12c749fad860d492e448edc` проверен без изменения оригинала. Все команды совпали с probe из r2; MASM, два пустых bl, BEGIN/END, CID_RANGE_OK, NULL_GUARD_OK, IOCTL_TRUE_OK/IOCTL_FALSE_OK и7 полных синтетических форматов. Все7 guards вычислены:0/0/0/0/0/1/1. Нет исполненных UNEXPECTED/CID_RANGE_UNAVAILABLE и syntax/memory errors. Строки команд, содержащие названия ошибочных веток, не считались их исполнением. Отдельный g записан. Private audit `artifacts/diagnostics/pb-kd-reconnect-review-20261016/minimal-disabled-stage/probe-review.json`.

Это подтверждает синтаксис проверок доступности и форматов в текущем engine. Реальные endpoint/record reads, breakpoint action/gc, owned Core query binding и причина C0000225 ещё не проверены. Значения readable=0 при произвольных registers вне sites не являются отказом продукта. PID/TID0/0 относятся к текущему thread пробы, не к владельцу соединения.

## Подготовленные файлы

Новый [stage](../scripts/debugger/pb-kd-minimal-stage-20261016.wdbg) и [описание](../scripts/debugger/pb-kd-minimal-stage-profile-20261016.json) относятся только к новым IDs0..6. Старый proposed JSON и probe сохраняются без изменений. Stage содержит7 bp с немедленным bd после каждого, затем bl/.bpcmds. **bp первоначально регистрирует включённую точку**: target должен оставаться остановленным до отключения всех семи. Команды be/внешний g/Run отсутствуют. Синтаксис вложенных actions проверен только офлайн; disabled registration ещё не выполнена, успешная регистрация не доказывает работу actions.

Входное условие — свежий пустой bl и MASM в прежнем сеансе с проверенными PDB/code. Автоматического запрета загрузки при непустом bl нет: USER проверяет это до загрузки. Не загружать дважды, поверх любых точек или после переподключения/смены модулей без новой проверки. Не читать несуществующие bp pseudo-registers. При ошибке не повторять stage.

| ID | Событие | Символ | Проверенный RVA |
| --- | --- | --- | --- |
| 0 | CREATE_POST | tcpip!AlepCreateRedirectRecord+396 | 1088b6 |
| 1 | ACCEPT_RETRIEVE_RESULT | tcpip!WfpAleAuthorizeAccept+caf | 1567b |
| 2 | ACCEPT_JOIN | tcpip!WfpAleAuthorizeAccept+cbe | 1568a |
| 3 | QUERY_READ | tcpip!WfpAleProcessSocketOption+2c4 | 12157c |
| 4 | QUERY_STATUS | tcpip!WfpAleProcessSocketOption+47b | 121733 |
| 5 | FREE_ENTER | tcpip!AleRedirectRecordFree+d | 11d73d |
| 6 | FREE_CALL_RETURN | tcpip!AleRedirectRecordFree+76 | 11d7a6 |

Guards проверяют диапазоны до poi/dwo/wo. Нечитаемый диапазон должен дать PBKDM_UNREADABLE/capture=incomplete и gc; реальное поведение ещё не испытано. FREE_CALL_RETURN не читает освобождённый record. Query actions фильтруют r15d980000dd; executing PID не используется как owner filter. ACCEPT_JOIN имеет skip/error входы и сам по себе не доказывает store; raw_output_slot после ошибки retrieval не объявлять валидным record. Нет полного NBL/parent/allocator покрытия, общей QPC шкалы или защиты от всех ошибок debugger. Включённые точки всё равно могут существенно замедлить VM.

Офлайн проверены количество/ID/адреса, пары bp→bd, число аргументов форматов, roundtrip nested quotes, ASCII/CRLF, отсутствие content reads внутри guards и внешнего resume, ZIP CRC/byte roundtrip/Desktop copy.8 защищённых файлов совпали, включая старые logger/stage/minimal plan/kit runtime-plan, оба прежних proposed/probe и r2 archive. Это не проверка всех файлов старого freeze; известное отличие внешнего Python runtime остаётся. Private preparation audit `minimal-disabled-stage/validation.json`, generator `prepare-minimal-disabled-stage.py` в том же diagnostic audit directory. Агент не управлял debugger, не запускал трафик или продукт.

## 1. Перенос на физический ПК, без Break

Архив Desktop VM `PB-KD-Minimal-Stage-20261016.zip`,5113bytes,SHA256:

`9514e3cb1e411b92a75a89d56b409f02c1436813fcb202f0e86abb161723a9e8`

Stage SHA256 `bfda5c41a138c0351110caeddd9256f0238d66b37b0bbd0a15031632bbd53413`. Архив содержит stage, JSON-описание и README; это не baseline kit. USER physical transfer/hash/extract ещё не подтверждены.

Скопировать архив в D:\Загрузки. В физическом PowerShell по отдельности:

`Get-FileHash -LiteralPath 'D:\Загрузки\PB-KD-Minimal-Stage-20261016.zip' -Algorithm SHA256`

Только при полном совпадении SHA, распаковать в НОВУЮ папку, без -Force:

`Expand-Archive -LiteralPath 'D:\Загрузки\PB-KD-Minimal-Stage-20261016.zip' -DestinationPath 'C:\PB-KD-Minimal-Stage-20261016'`

При ошибке/другом SHA не перезаписывать папку и не переходить к WinDbg. Прислать результат; следующий USER шаг объяснить после проверки.

## 2. Только USER disabled registration после подтверждения переноса

Сохранить команды/восстановление на физическом ПК заранее. Если на общей VM идёт другой согласованный тест, дождаться его завершения. **Break останавливает всю PB-BUILD-W11-25H2, включая Codex и RDP.** Нажать один Break только если нет активного kd>. Каждая внешняя команда — отдельный Enter. Сначала:

`bl`

`.expr`

Если bl непустой или не MASM: stage не загружать, ничего не перезаписывать/отключать, отдельный g и прислать вывод. При пустом bl и MASM загрузить один раз:

`$<C:\PB-KD-Minimal-Stage-20261016\pb-kd-minimal-stage-20261016.wdbg`

Ожидаются ровно7 resolved IDs0..6, каждый d, соответствующие таблице; полные action strings в .bpcmds без потерь/ошибок. Stage сам не возобновляет VM. После завершения ИЛИ ОШИБКИ выполнить по отдельности:

`bd *`

`bl`

`g`

Здесь bd * допустим только благодаря проверенному пустому входному списку: все появившиеся точки принадлежат stage. Если исходно были чужие точки, этот путь не применять. При неожиданной повторной остановке сохранить сообщение и выполнить отдельный g; точки не включать, stage не повторять. Весь вывод прислать в чат, logopen не нужен. Успех/ошибка регистрации пока не известны.

## Следующая граница

Сначала проверить USER регистрацию и итоговые d состояния. После этого files-only подготовить НОВЫЙ four-only baseline kit с точным новым stage/profile, свидетельствами Core и привязкой конкретного query. До его подготовки и отдельного согласования USER enable/run нет. Нагрузка64/256/640/recovery остаётся запрещена; старый kit163607 и старые25/17/stage не использовать, не refreeze/Resume. Продукт/драйвер/build/install/BCD/гипервизор не менять. Диагностическая ветка codex/checkpoint-20261007; соседнюю разработку не трогать. Причина исходного отказа не установлена.
