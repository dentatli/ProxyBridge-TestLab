# Проверка привязки redirect record через метаданные пакета

2026-10-08. USER baseline `113826-0f33dffe` и следующий live code fragment проверены офлайн; новый запуск не выполнялся. Это план следующей адресной диагностики, не доказательство причины исходных сбросов и не готовый logger/Run.

**Текущий этап:** общий read-only код уже получен в USER host log 17:31 и проверен. Следующий шаг — [план 25 точек и format probe](KERNEL_CONTEXT_PACKET_LOGGER_PLAN.md). Инструкции инспекции ниже сохранены как история; повторять их не требуется.

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

## Проверка live boundaries выполнена

USER attachment `12f3f675` содержит 36 инструкций. 34 совпали с дисковыми байтами; оставшиеся две образуют импортный call rewrite: тот же IAT RVA 0x24ce00, live target `fwpkclnt!FwpsNetBufferListRetrieveContext0` по адресу fffff801`0fa13130. Это структурная проверка пары, не полное совпадение памяти модуля. Заголовок загруженного fwpkclnt ещё не получен. Обе операции store в endpoint+0x1c0 подтверждены на live boundaries. Все 14 известных точек 0..13 — d; адреса и тела команд совпали, отдельный g присутствует. Attachment сохранён без изменения, SHA `192d343e5631c1620eabea7cd8cba087539f4e19cf57cca04bfcd35eb1ebefe2`. Audit: `artifacts/diagnostics/pb-kd-attachment-path-review-20261008/validation.json`.

Ни одна из этих проверок не показывает фактическое исполнение ветки на собственном соединении.

## Остальная цепочка: статические находки

Проверен SHA дискового fwpkclnt и выбранные PE instruction ranges. Retrieve имеет несколько последовательных exception-directory ranges 0x3130..0x3470; первый диапазон заканчивается уже на 0x3157 и не представляет всё тело функции. Не обрезать анализ на первом pdata fragment.

- Generic retrieval сравнивает ключ `[RDI+0x10]` с RSI, проверяет `[RDI+0xb8]`, возвращает значение `[RDI+8]` через output pointer. При BPL!=0 выполняются дополнительные внутренние операции и запись в поле +0xb8; это наблюдаемое поведение кода, а не установленный публичный контракт private API. При отсутствии подходящей записи существует возврат C0000225. Не переносить branch для встроенных ключей 1..4 на ключ 5.
- `WfpTlShimInspectFastLoopbackSendDatagram`, RVA 0xd58e0: при выбранных flags увеличивает refs Windows record, затем вызывает Associate с record из endpoint+0x1c0, ключом 5 и callback `TlShimNblEventNotifyFn`. Название функции не доказывает её фактическое участие в этом TCP опыте.
- Cold fragments RVA 0x1c0448 и 0x1c06ac тоже вызывают Associate с ключом 5 и record с refs increment. Их ветки ещё не подтверждены на target.
- `TlShimNblEventNotifyFn`, RVA 0x10add0, имеет ветку вызова AleRedirectRecordDereference для ключа 5 и повторную association для других событий. Коды событий записывать как raw values до проверки contract/actual runtime; нельзя называть конкретную ветку потерей retry metadata только по её наличию.
- Associate/Notify содержат другие ключи и пути. Статический поиск 27 импортных call candidates не доказывает полного покрытия всех операций или принадлежности каждому собственному пакету.

Это обосновывает наблюдение association → callback/clone/free → retrieval status/output → endpoint store → query/free в одном сборе. По-прежнему требуется связь с собственными tuple и поколениями NBL/record/endpoint. Для привязки query к Core нужно проверить доступное поле ETHREAD.Cid; исполняющий PID на packet/DPC ветке не использовать как единственный owner filter.

## Следующий ручной шаг: одна инспекция всей выбранной цепочки

Никаких новых точек или трафика до проверки live boundaries оставшихся функций. Использованный 111941 plan не менять/refreeze/Resume; полного load Run пока нет. Подготовлен `scripts/debugger/pb-context-packet-code-inspect.wdbg`: только bl/lmvm/uf/u/dt и echo markers. Он не меняет точки, регистры, память, symbol path и не исполняет целевые функции. Actual WinDbg parsing и получение private type ещё не проверены. По ошибке не применять /i или менять symbols вслепую.

Перенести архив `PB-KD-Packet-Code-Inspect-20261008.zip` с Desktop VM на физический ПК. Распаковать файл **непосредственно** в `C:\PB-KD`, итоговый путь `C:\PB-KD\pb-context-packet-code-inspect.wdbg`. Архив содержит только этот файл. Не загружать lifecycle candidate или старый conditional patch.

**Перед Break: остановится вся VM, Codex и RDP.** Подготовить файл и команды на физическом ПК. Каждую внешнюю команду вводить отдельно, Enter после каждой:

1. Нажать Break.
2. `.logopen /t C:\Users\Administrator\pb-context-packet-code.log` — новый timestamped log. Если журнал уже открыт, сохранить его и закрыть отдельно, не перезаписывать.
3. `$<C:\PB-KD\pb-context-packet-code-inspect.wdbg` — дождаться возврата prompt. Сохранить ошибки вместе с выводом, не включать точки.
4. `.logclose` — сохранить вывод даже при любой ошибке файла.
5. Отдельно `g` **даже при ошибке**. Если VM снова остановится, ввести g отдельно ещё раз и сохранить сообщение остановки.

Прислать созданный host log. После проверки этих live инструкций будет подготовлен конкретный logger, охватывающий выбранные гипотезы и проверку ownership. Этот read-only файл не является logger и не разрешает автоматически полную нагрузку; тест в VM на этом шаге не запускать.
