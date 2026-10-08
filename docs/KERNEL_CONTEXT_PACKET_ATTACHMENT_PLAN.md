# Проверка привязки redirect record через метаданные пакета

2026-10-08. USER baseline `113826-0f33dffe` проверен офлайн; новый запуск не выполнялся. Это план следующей адресной диагностики, не доказательство причины исходных сбросов и не готовый logger/Run.

## Что подтвердил baseline

- Reporter повторно вычислен только в памяти: полностью совпал с сохранённым результатом. Четыре CTS GUID, по 512 KiB, суммарно 2 MiB; четыре исходных Core query успешны, конфигурация исходной очереди сохранена, concurrent snapshot проверен.
- Helper readiness: proxy 4199 мс, sampler 125 мс. Сохранённые cleanup receipts подтверждают естественное завершение helper/client/receiver, graceful CLI, service Stopped и отсутствие известных interception driver names / product processes. Это ограниченные сохранённые наблюдения, не текущая полная проверка системы.
- Host log содержит четыре уникальные Windows record: для каждой CREATE_POST → QUERY_READ → QUERY_STATUS=0 → FREE_ENTER refs=0 → allocator call/return → FREE_POOL_RETURN. Адрес record совпадает на этих наблюдаемых границах; allocator return читает только slot, не освобождённую запись. True ветки двух allocator conditions исполнились и вывели корректные строки.
- CREATE_PRE есть только для двух записей. Четыре query endpoint отличаются от create endpoint. TRANSFER_PRE/POST отсутствуют; все 659 TRANSFER_READ показывают NULL у родителя и ребёнка. Есть одинаковые повторяющиеся строки, включая DEREF_POST. Причина пропусков/повторов не измерена; нельзя приписать её SMP, transport loss или конкретной ветке исполнения без дальнейших данных.
- Поля sockaddr A/B в двух CREATE_PRE декодируются в 127.0.0.1:54122 и 127.0.0.1:34010. Native source ports 50525–50528 там не представлены. Точное сопоставление четырёх private query endpoint с четырьмя Core query по tuple/PID/TID/rawQPC не доказано. Совпадение количества или порядок строк не заменяют эту связь.

Исходный log 131044 bytes и все USER run/used preparation files сохранены SHA (44 файла). Audit: `artifacts/diagnostics/pb-kd-baseline-review-20261008-113826/validation.json`. Исходный reporter/result не переписан; status остаётся DEBUGGER_PENDING.

## Найденная статическая ветка

Проверены текущий tcpip.sys SHA `4e6435db...` и его ранее связанный PDB. В `WfpAleAuthorizeAccept` есть ещё один store в endpoint+0x1c0, не охваченный установленным logger:

| Граница | Код / проверенное значение |
| --- | --- |
| entry +0x33 | RCX сохраняется в RDI; RDI не переприсваивается в рассмотренном теле функции |
| RVA 0x3b47a..0x3b48c | stack output slot rbp-0x28, NBL argument RBX/RCX, selector EDX=5 в success ветке, R8B=1 |
| RVA 0x3b48f | IAT call: fwpkclnt.sys!FwpsNetBufferListRetrieveContext0, импорт 0x24ce00 |
| RVA 0x3b49b | EAX проверяется на success; при error store пропускается |
| RVA 0x3b49f | RAX получает указатель из output slot |
| WfpAleAuthorizeAccept+0xcb7, RVA 0x3b4a3 | RAX записывается в [RDI+0x1c0] |

В другой cold ветке `WfpAleAuthorizeSend`, RVA 0x1cc45b, есть store record RCX в [RAX+0x1c0], затем increment refs+0x1f0. Это ещё одна потенциальная операция привязки. Совпадение displacement само по себе не определяет тип объекта; значения/владельцев требуется наблюдать.

Статический import table также связывает `FwppNetBufferListAssociateContext` и `FwppNetBufferListEventNotify` с **fwpkclnt.sys**, не NETIO. Проверены export RVAs 0x4a60/0x2b00/0x3130 и SHA дискового fwpkclnt.sys; загрузка/байты этого модуля на target ещё не проверены. Идентификатор контекста 5 и argument R8B=1 записываются как сырые значения: полная семантика private API не предполагается. Static audit: `accept-static-validation.json`, selected PE ranges и потенциальные displacement stores в том же ignored audit. Поиск не является полным доказательством всех операций записи.

## Что различит следующая диагностика

1. Запись переносится в принимающий endpoint через packet metadata и отсутствует у повторного SYN после отказа очереди.
2. Запись присутствует в packet metadata, но retrieval возвращает error или store в endpoint пропускается.
3. Retrieval/store успешны, затем запись очищается/заменяется до исходного query Core.

Для различения требуются явные NBL/record/endpoint lifetimes, исходный return status retrieval, фактический результат store, связь с собственным native tuple/первым и повторным SYN и query. Не считать отсутствие одного события доказательством удаления контекста. Не связывать packet/TCB/WFP/AFD pointers по равенству или ближайшему времени без проверенного перехода. Отдельно устранить шум NULL TRANSFER_READ и проверить полноту CREATE/DEREF, не маскируя пропуски.

## Ближайший ручной шаг: только чтение кода

Никаких новых точек или трафика до проверки следующих live boundaries. Использованный 111941 plan не менять/refreeze/Resume; полного load Run пока нет. Сначала нужны два коротких фрагмента инструкций с physical WinDbg, чтобы сверить импортные call rewrites и границы store с дисковыми байтами.

**Перед Break предупредить: остановится вся VM, Codex и RDP.** Подготовить команды на физическом ПК. Вводить каждую отдельно, Enter после каждой:

1. `bl` — ожидаются наши 14 известных точек 0..13, все d после последнего ручного bd. При несовпадении не включать/перезаписывать точки, сохранить вывод и отдельно g.
2. `u tcpip!WfpAleAuthorizeAccept+0xc7d L0n24`
3. `u tcpip+0x1cc442 L0n12`
4. Отдельно `g` даже при любой ошибке.

Прислать вывод. Этот шаг не исполняет целевые функции, не меняет память/регистры/точки и не запускает опыт. После проверки адресов можно подготовить конкретный новый logger с packet metadata веткой и проверкой ownership. Успешные четыре соединения не разрешают автоматически переходить к полной нагрузке.
