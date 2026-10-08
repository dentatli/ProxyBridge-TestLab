# Ручная установка отключённого журнала в WinDbg

Текущий результат USER2026-10-08:14точек0..13установлены по ожидаемым адресам, все d; .bpcmds совпадает с14source CommandString. Отдельный g присутствует. Агент сохранил неизменным USER attachment и сверил каждую строку; audit `artifacts/diagnostics/pb-kd-stage-review-20261008/validation.json`. Регистрация точек подтверждена, исполнение их действий на соединениях — нет. Инструкции установки ниже теперь исторические: **повторно файл установки не загружать**, иначе появятся дубли и новые точки вне отключаемого диапазона.

Две ошибки при чтении первоначального файла относятся к комментариям агента: semicolon завершил $$, оставшийся текст стал командой. Это ошибка подготовленного файла, комментарии исправлены без изменения14bp действий. Правило явно описано [Microsoft $$](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/-----comment-specifier-). Исходный ZIP/USER вывод сохранены, повторная установка ради исправления комментариев не нужна.

2026-10-08 USER bl пуст, WfpPoolFree разрешилась, затем отдельный g продолжил VM. Код WfpPoolFree: RBX сохраняет адрес ячейки; RCX получает record; при nonnull вызывается nt!ExFreePoolWithTag, затем ячейка заменяется BADBADFABADBADFA.14инструкций:12точно совпали с PE, одна пара import-call отличается структурно так же, как ранее. Исполнение free при отказанном SYN не наблюдалось. Audit только локально `artifacts/diagnostics/pb-kd-pool-free-review-20261008/validation.json`.

Подготовлен [файл установки](../scripts/debugger/pb-context-lifecycle-candidate.wdbg),14точек. Первые12границ побайтово совпадают с PE; новые две находятся на явно выведенных живых call/return границах WfpPoolFree+1a/+1f. Условие poi(RSP+28h)==AleRedirectRecordFree+76 связывает события allocator с конкретным вызовом освобождения Windows record: push RBX+sub RSP20h перемещают caller return address на RSP28h. Эти поля ещё необходимо проверить при runtime baseline. Событие ALLOCATOR_FREE_RETURN читает ячейку, а не содержимое освобождённого record. Непарные или неоднозначные события не считать доказанной жизнью объекта.

CREATE_PRE добавляет family/port/address двух sockaddr, скопированных в record+48/+c8 из второго/третьего аргументов. Это raw metadata в little-endian debugger display, не packet payload. Значение addr применяется как IPv4 только при family2; совпадение с owned native tuple проверить на baseline, не предполагать направление A/B по порядку. Размер контекста32сам по себе не доказывает принадлежность ProxyBridge.

## Что можно выполнить сейчас

Разрешена только ручная **установка отключённых точек**, не workload и не включение logger. У агента нет доступа к физическому WinDbg. Скрипт проверен офлайн по границам инструкций и framing; настоящий WinDbg parser/сохранение CommandString ещё не проверены. Система теста, product query и драйвер не меняются этим этапом; software breakpoint при активном состоянии меняют код target/timing. Источники checkpoint/push проверить перед передачей инструкций.

1. На физический ПК скопировать актуальный файл, не исторический12point кандидат. Положить его в C:\PB-KD\pb-context-lifecycle-candidate.wdbg. В переносимом ZIP есть этот файл, README и SHA manifest, без PDB/логов/ключей/сборок. Не закрывать текущий лог WinDbg.
2. **До Break предупредить: остановится вся VM/Codex/RDP.** Все команды приготовить на физическом ПК заранее.
3. Ввести bl отдельно, затем .expr отдельно. Только если список всё ещё пуст и выбран MASM evaluator, один раз выполнить `$<C:\PB-KD\pb-context-lifecycle-candidate.wdbg`. При непустом списке или другом evaluator не загружать файл: его заключительный bd рассчитан на0..13наших точек в пустом сеансе, а выражения — на MASM. Не менять evaluator вслепую и не запускать файл повторно.
4. Отдельно bl, затем отдельно .bpcmds. Должно быть ровно14resolved точек0..13, все d, с ожидаемыми symbol+offset и полными CommandString, завершающимися g. Пока нет этих наблюдений, установку не считать успешной. Никаких точек watchpoint и фильтра bp/p по executing PID нет.
5. **g отдельно даже при любой ошибке.** Если некоторые точки остались e, а bl подтверждает, что0..13относятся только к этому файлу, сначала отдельный bd по этим номерам, затем g. Не использовать bd*/bc*. При неизвестных точках сохранить вывод и не менять их.
6. После продолжения VM передать вывод чтения файла, bl и .bpcmds. Не выполнять be и не запускать старые Install/Run команды.

Команды внешнего уровня вводить по одной/Enter, не собирать цепочку через semicolon. `$<` читает строки файла отдельно; `$><`/`$$><` не применять. Внутренний semicolon в quoted bp CommandString предусмотрен [Microsoft bp](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/bp--bu--bm--set-breakpoint-). Команды [bd](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/bd--breakpoint-disable-) поддерживают bracket numeric expressions; [Run Script File](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/-----------------------a---run-script-file-) описывает построчный `$<`.

## После проверки установки

### Текущий следующий шаг без трафика

Подготовлен [read-only format probe](../scripts/debugger/pb-context-lifecycle-format-probe.wdbg). Он печатает14PBKD_PROBE строк с искусственными значениями, использует только constants/текущие @$thread и @rsp/два уже разрешённых символа. Не разыменовывает память соединения, не меняет регистры, точки, состояние службы и не запускает трафик. Все14format fields совпали с установленными CommandString, arg count совпадает с %p/%I64x/%x. Отдельно выполняются3trueусловия и1falseусловие. Форматы и грамматика .if соответствуют [Microsoft printf](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/-printf) и [Microsoft if](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/-if); реальное исполнение WinDbg ещё ожидается.

1. Перенести только новый probe на физический ПК в C:\PB-KD\pb-context-lifecycle-format-probe.wdbg. Не загружать заново stage файл, существующие14точек оставить d.
2. **До Break предупредить: VM/Codex/RDP остановятся.** Команды сохранить на физическом хосте заранее.
3. По одной/Enter: `$<C:\PB-KD\pb-context-lifecycle-format-probe.wdbg`, затем bl, затем **g отдельно даже при ошибке**. be не выполнять.
4. Передать вывод после продолжения. Ожидаются14строк PBKD_PROBE и PBKD_PROBE_END без ошибок и без PBKD_PROBE_UNEXPECTED_FALSE_BRANCH; bl должен сохранить14d.

Этот probe проверяет formats, базовые pseudo-register reads и synthetic condition parsing. Он не проверяет разворачивание quoted bp string во время trap, корректность памяти callee, caller-return condition на реальном вызове, стек, авто-g или принадлежность объектов. Синтетические строки имеют отдельный PBKD_PROBE префикс и не являются metadata живых соединений. Финальный pb-kd-format-probe-final.zip (1792 байта) содержит только probe/README/hash manifest; SHA/CRC roundtrip сохранены в ignored stage audit/probe-validation-final.json. Старый stage ZIP не заменён.

### Затем собственные соединения и нагрузка

Включение14точек и owned baseline требует отдельного согласованного шага с проверенным контроллером, QPC/tuple/endpoint жизнью и исходными ошибками. Ни baseline, ни полный workload пока не готовы к Run. Производительность исключена. Serial pipe и количество traps могут существенно удлинить опыт; прежние2–4мин не гарантируются. Если после включения встретится ошибка CommandString, VM может остаться остановленной; команды отключения и отдельный g должны быть заранее приготовлены на хосте.

Проверенный модуль ConnectionLoad сейчас всегда строит полную серию4→64/256/640→4дляHIGH. Нельзя выдавать существующий Run за одну baseline4или применять прежний использованный frozen kit. Для нового контролируемого baseline нужны freshfiles/manifest/binding исходных CLI/Core/driver/native engine, четыре GUID/data-verified соединения и штатная очистка; совпадениеrecord tupleA/B с native/query проверить явно до полной нагрузки. Existing benchmark verdicts не менять ради logger. В этом этапе модуль/контроллер/драйвер не изменялись и Run не выполнялся.

Аварийное отключение только после подтверждения назначения номеров0..13:

```text
bd [0n0] [0n1] [0n2] [0n3] [0n4] [0n5] [0n6] [0n7] [0n8] [0n9] [0n10] [0n11] [0n12] [0n13]
```

После отключения g вводить отдельно. Удаление после сохранения лога и проверки этих же номеров возможно отдельной командой bc с тем же списком bracket IDs; не очищать чужие точки. Включение/удаление агентом не выполнялись.

Отсутствие свободного record не равно доказанной причине; нужны парные create/transfer/free и выбранный endpoint исходного query при воспроизведении. Произвольные writes/endpoint lifecycle вне выбранных функций пока покрыты неполно. Отсутствие воспроизведения — INCONCLUSIVE. Дополнительные условия — [адресный план](KERNEL_CONTEXT_BREAKPOINT_PLAN.md).
