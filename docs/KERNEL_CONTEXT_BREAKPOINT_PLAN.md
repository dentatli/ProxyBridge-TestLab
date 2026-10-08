# Адресный план наблюдения redirect context

2026-10-08. Kernel connection с target VM подтверждён USER; tcpip/AFD/NETIO загрузили PDB с физического хоста. Это подготовка адресного опыта, не результат исполнения переноса/освобождения и не готовая команда Run. Новый обычный ETW опыт не требуется.

## Проверенные точки переноса

USER прислал `uf tcpip!InitializeEndpointContextFromParentContext`. Агент сравнил все117 выведенных инструкций с текущим tcpip.sys: байты совпали. Заголовки трёх загруженных модулей (Timestamp/ImageSize/CheckSum) совпали с дисковыми файлами; этот ограниченный контроль не является SHA всей загруженной памяти. PDB GUID/DBI age пакета ранее проверены по CodeView. Audit только локально: `artifacts/diagnostics/pb-kd-parent-transfer-review-20261008/validation.json`; исходное USER attachment не изменено.

| Точка в tcpip!InitializeEndpointContextFromParentContext | Подтверждённая инструкция / назначение |
| --- | --- |
| +0x70 | RDI получает родительский endpoint из `[RBX+0x220]`; RBX — текущий дочерний endpoint в этой функции |
| +0x174 | RAX получает указатель записи из `[RDI+0x1c0]` |
| +0x1d7 | Ненулевой указатель записывается в `[RBX+0x1c0]` |
| +0x1de | `[RDI+0x1c0]` обнуляется |

RVA функции0x1aad4; WfpAle wrapper0x19ebc. Для будущих точек использовать проверенный symbol+offset, не переносить абсолютные адреса этого boot в другой сеанс. Эти инструкции ещё не наблюдались во время отказанного SYN. Поле `+0x1c0` — указатель Windows record; не считать его автоматически указателем32-байтного пользовательского контекста драйвера.

## Проверка соседних функций одной остановкой

Эта проверка выполнена USER отдельными командами с последующим g. Все шесть функций разрешились. Из605 выведенных инструкций587 побайтово совпали с PE. Остальные18 — восемь пар изменённых import-call инструкций (исходный косвенный call+NOP, загруженный mov R10+прямой call) и два изменённых вызова memset. Эти различия сохранены отдельно; механизм их изменения не объявляется доказанным. Все выбранные ниже границы точек и инструкции доступа к record совпали с PE. Audit: `artifacts/diagnostics/pb-kd-record-lifecycle-review-20261008/validation.json`. Исходный attachment сохранён неизменным. Наблюдение исполнения при неисправном соединении ещё предстоит.

Аргументы установлены по явным перемещениям в выведенном коде, а не по предположенной структуре private PDB:

| Функция | Что установить для общего опыта |
| --- | --- |
| WfpAleInitializeEndpointContextFromParentContext | Wrapper непосредственно вызывает InitializeEndpointContextFromParentContext, аргументы не переставляет |
| AlepCreateRedirectRecord | RCX сохраняется в RDI endpoint; TCP branch+38f присваивает новый RAX record в endpoint+1c0 |
| AleRedirectRecordDereference | RCX record; atomic decrement+1f0; прежнее число1 вызывает Free через адрес сохранённого указателя |
| AleRedirectRecordFree | RCX адрес ячейки, RBX=poi(RCX); освобождает context и вспомогательные ссылки, затем вызывает WfpPoolFree для record |
| WfpAleReleaseEndpointContext | Прибавляет80h к RCX и снимает WaitRef; сам Release не доказывает Free record |
| WfpAleProcessSocketOption | RCX сохраняется в RDI endpoint, EDX в R15D IOCTL;0x980000DD читает record+1c0, null ведёт к C0000225 |

**Перед Break обязательно предупредить: остановится вся VM/Codex/RDP.** Заранее сохранить команды на физическом хосте. В WinDbg после Break/`kd>` каждую команду вводить отдельным Enter, не вставлять весь блок и не объединять `;`:

```text
uf tcpip!WfpAleInitializeEndpointContextFromParentContext
uf tcpip!AlepCreateRedirectRecord
uf tcpip!AleRedirectRecordDereference
uf tcpip!AleRedirectRecordFree
uf tcpip!WfpAleReleaseEndpointContext
uf tcpip!WfpAleProcessSocketOption
```

После чтения или любой ошибки отдельно продолжить VM:

```text
g
```

Это чтение кода; workload и breakpoint не устанавливаются. Лог WinDbg оставить открытым. Передать вывод после продолжения VM. Для неразрешённого имени сохранить ошибку, не подменять соседней функцией/nearest-address.

## Что собрать в одном диагностическом опыте после адресной проверки

Один общий сбор должен различить: (1) перенос в первого ребёнка и освобождение после отказанного SYN; (2) живая запись остаётся у другого владельца при повторе; (3) указатель очищен/заменён иной операцией или дополнительной classify. Наблюдать создание/привязку, состояния до и после переноса, очистку/освобождение, retry/второго ребёнка и endpoint исходного запроса Core, плюс успешный контроль той же серии.

Требования до запуска:

- Точки на границах подтверждённых инструкций; заранее сохранить debugger command file и команду продолжения/удаления только наших точек на физическом хосте. Проверить bl, не заменять чужие точки и не использовать bc* как универсальную очистку.
- Подтвердить аргументы/значения полей в baseline до нагрузки. Текущий executing PID при DPC не является владельцем соединения; фильтр bp/p только по процессу может пропустить важную операцию. Не переносить прежний APPID blind spot в новый logger.
- Связать PID/tuple и endpoint/record по явным переходам и срокам жизни. WFP handle, AFD endpoint и TCP указатель — разные виды идентификаторов. Повторное использование адреса ограничивать create/free; порядок строки/ближайший timestamp не заменяет связь объектов.
- Наблюдать writes/free со стеком, включая операции вне исходного callout; не считать отсутствие выбранного function breakpoint доказательством отсутствия иных записей. Hardware write slots ограничены — не обещать наблюдение всех968объектов одновременно.
- Измерение производительности исключено. Каждое kernel breakpoint событие кратковременно приостанавливает VM даже при автоматическом продолжении; logger меняет timing. Если отказ не воспроизвёлся или identity/coverage неполны, вывод INCONCLUSIVE/INCOMPLETE.
- Контроллер/комплект для согласованной нагрузки определить после готовности адресного logger. Не refreeze/resume прежний использованный план и не запускать старый FullMetadata Run автоматически. Agent не устанавливает драйвер и не генерирует трафик.

## Подготовленный кандидат общего журнала

[pb-context-lifecycle-candidate.wdbg](../scripts/debugger/pb-context-lifecycle-candidate.wdbg) содержит12 автоматически нумеруемых software breakpoint. Это кандидат: агент не подключал его к WinDbg, не проверял исполнение CommandString и не запускал workload. Сейчас его **не загружать**. Следующее ручное чтение — bl и uf tcpip!WfpPoolFree, затем отдельный g; по выводу проверить свободную ёмкость и фактическую обёртку allocator Free. Вызов/возврат WfpPoolFree сам по себе пока не объявляется наблюдением deallocation. bp без явного номера не заменяет ранее существующие точки; kernel limit32. Все точки из кандидата необходимо отдельно сверить в bl после установки, а их номера записать для удаления только этих точек. Нельзя использовать bc*.

| Группа | symbol+offset | Проверенные значения |
| --- | --- | --- |
| Привязка новой записи | AlepCreateRedirectRecord+38f / +396 | Перед store: RDI endpoint, RAX new record, старый endpoint+1c0; после store: фактически присвоенный record |
| Перенос | InitializeEndpointContextFromParentContext+174 / +1d7 / +1e6 | До read; перед store ребёнку; после очистки родителя. RBX child, RDI parent, RAX record перед store |
| Снятие ссылки | AleRedirectRecordDereference+c / +14 | RCX сам record; +1f0 refs перед atomic xadd, EAX прежнее число после него. Между двумя trap возможна конкурирующая операция; не выводить отсутствующий decrement только из этих снимков |
| Освобождение | AleRedirectRecordFree+d / +71 / +76 | Вход: RBX=poi(RCX), RCX адрес ячейки, а не record. Перед вызовом WfpPoolFree RCX ячейка/RBX record и stack. После возврата только прежний адрес RBX, без dereference освобождённой памяти |
| Запрос | WfpAleProcessSocketOption+2c4 / +47b | RDI endpoint, +1c0 record, R15D IOCTL. На +47b EBX уже содержит итоговый NTSTATUS, EAX ещё не присвоен; logger читает EBX и выбирает только 980000DD |

WfpAleReleaseEndpointContext прибавляет к RCX80h и вызывает DecrementWaitRef. Его вызов сам по себе не доказывает освобождение record, поэтому не выбран как заменитель Free. Wrapper ParentContext прямо вызывает проверенную внутреннюю функцию. AlepCreateRedirectRecord выделяет228h байт для Windows record; его +1e0/+1e8 — pointer/size пользовательского контекста. Это разные выделения,32байт собственный контекст не считать размером Windows record.

Кандидат не фильтрует по executing PID, не меняет NTSTATUS/память объектов/пользовательский query, не ставит watchpoint и не читает packet payload или произвольные32байт data. ETHREAD+stack и явные parent/child/record переходы сохраняются. После Free адрес не разыменовывается. Logger не даёт автоматически точной связи endpoint с native tuple/owned query; эту связь и create/free поколения нужно проверить на baseline вместе с действующими Core/kernel/CTS метаданными. Полная история жизни endpoint и произвольные записи вне выбранных функций ещё не покрыты. Отсутствие FREE строки не доказывает сохранность записи.

Внутри **quoted breakpoint CommandString** semicolon разделяет команды printf/stack/g по документированной грамматике [Microsoft bp](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/bp--bu--bm--set-breakpoint-). Это отличается от прежней ошибочной цепочки symfix/uf/g. Пользователь по-прежнему вводит внешние команды по одной; заключительный g всегда отдельный. Для будущего чтения файла выбирать построчный `$<`, а не `$><`/`$$><`, которые объединяют строки в один блок: [Microsoft Run Script File](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/-----------------------a---run-script-file-). Файл не содержит самостоятельного g в конце и не открывает/перезаписывает журнал.

**Перед следующими Break/установкой обязательно предупредить:** VM/Codex/RDP останавливаются; каждая активная точка тоже кратко приостанавливает всю VM. Готовность runtime logger, ownership/coverage, нагрузка и её длительность ещё не подтверждены. Не считать старую оценку2–4мин применимой к12kernel точкам через serial pipe. Не запускать старый использованный kit автоматически; не дробить длинный опыт ради разрешения на <5мин.

Наблюдение конкретного free/неправильного владельца должно предшествовать выводу Windows bug/driver bug и любому product fix. Подробная причинная цепочка и ограничения — [план жизненного цикла](TCP_CONTEXT_ENDPOINT_LIFECYCLE_PLAN.md).
