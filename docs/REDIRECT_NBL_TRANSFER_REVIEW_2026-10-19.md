# Передача записи перенаправления между NBL

В прогоне `113318-fdff4bb4` наблюдался возврат `C0000225` с нулевой записью из
accept-side RetrieveContext; native API затем вернул10022/bytes0. Это локализует
отсутствующую привязку, но не доказывает освобождение самого контекста.

## Что показывает текущий код

Исследован сохранённый disassembly tcpip.sys с SHA256
`b0683bd7ed0f309e63b4e6e71675d8f04cfb0ea5533c3f5e8a13c6daca3b595a`.
Текущий файл на диске имеет этот же хеш. Адреса ниже — RVA, не live-адреса.

1. `WfpTlShimInspectFastLoopbackSendDatagram`, RVA d7e80: при установленном
   бите13 endpoint+34 берёт record из endpoint+1c0, увеличивает refs+1f0 и
   ассоциирует record с NBL под ключом5. Callback — `TlShimNblEventNotifyFn`.
   В теле этой функции бит не очищается; однако это не доказывает вызов функции
   для каждой повторной передачи.
2. Callback RVA108970 обрабатывает события1/2/3: клонирование NETIO, клонирование
   WFP API и дублирование NETIO. Для ключа5 ветвь108a5a..108a79 вызывает
   RetrieveContext на исходном NBL с removeContext=TRUE и нулевым output pointer,
   затем переходит к ассоциации с новым NBL в1089ef..108a3d. Передаваемый record
   берётся из аргумента callback, а не из output этого извлечения.
3. Статус извлечения сохраняется в EDI, но ветвь всё равно идёт на ассоциацию;
   затем EDI получает ненулевой результат ассоциации, если такой результат есть.
   Это само по себе не доказанная ошибка: внутренний контракт допускает передачу
   record в аргументе callback. Требуется runtime-наблюдение конкретной записи.
4. Событие5, CONTEXT_REMOVED, для ключа5 вызывает `AleRedirectRecordDereference`
   через108a4a. Это уменьшение ссылки, а не безусловное освобождение.
5. Dereference RVA11d700 уменьшает счётчик+1f0 атомарно; деструктор вызывается
   только при прежнем refs=1. В деструкторе читается context+1e0 и вызывается
   освобождение при ненулевом указателе. Поэтому одна строка CONTEXT_REMOVED
   также не докажет уничтожение context.

Названия функций извлечены из public records PDB. GUID и DBI age1 совпадают
с PE; info-stream age3 отличается. Две попытки DbgHelp SymFromAddr вернули126;
принудительная загрузка символов не применялась. Уже проверенные live CREATE,
RETRIEVE и ASSOC адреса не заменялись новыми предположениями.

## Проверенные контракты Microsoft

- [RetrieveContext](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/fwpsk/nf-fwpsk-fwpsnetbufferlistretrievecontext0): removeContext удаляет ассоциацию с NBL.
- [NotifyFn1](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/fwpsk/nc-fwpsk-fwps_net_buffer_list_notify_fn1): различает исходный и новый NBL, передаёт context и tag.
- [События NBL](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/fwpsk/ne-fwpsk-fwps_net_buffer_list_event_type0_): значения1/2/3 — clone/duplicate, значение5 — context removed.

## Следующее наблюдение и его границы

### Результат R2, Run123833-c0a05875

Получены два полных стека для отслеживаемой записи. Первый CONTEXT_REMOVED
при refs=3 пришёл из `FwppCheckAndRemoveDuplicatedContext` внутри ассоциации
контекста. Второй при refs=2 — из очистки NBL после `TcpTcbSendDatagramsComplete`.
Оба снимка содержат прежний ненулевой context и size32. Native:200фоновых
соединений успешны, контрольное42201 вернуло10022/bytes0; cleanup без ошибок.

Эти наблюдения не подтверждают преждевременное освобождение. Они объясняют
инициаторов двух снятий ссылок; post-decrement значения и полный lifetime не
измерены. Не объединять с NOT_FOUND другого Run в трассу одного объекта.

Дальнейший приоритет — путь повторного клиентского SYN и восстановление
ассоциации на его NBL. При offline разборе исключена ложная зацепка по имени:
`TcpRetransmitSynTcbSend` вызывает `TcpSynTcbSend` с TCP flags12h (SYN|ACK), а
`TcpCreateSynTcb` вызывается из `TcpListenerReceive`. Это не установленный путь
клиентского retry. Начало подходящего timeout-path: RVA51150
`TcpRetransmitTimeout` → RVA51650 `TcpRtoTimeout`; продолжить статический разбор
до подготовки runtime observer. Новая нагрузка ради повторения REMOVE не нужна.

Нужно различить отсутствие исходной ассоциации, неуспешный перенос между NBL и
более раннее снятие привязки. Повторение CREATE или QUERY отдельно этого не решит.
Приоритет — проследить одну контрольную record: исходный/новый NBL, событие,
результат ассоциации и снятие ссылки. Не считать разные NBL одним пакетом или
повторное использование адреса доказательством lifetime.

Перед регистрацией нового наблюдателя сверить live callback entry и участок
108a5a..108a79. Текущая точка2 RETRIEVE отключена, VM resumed. Новые точки,
нагрузка, установка или изменение продукта в ходе этого разбора не выполнялись.
Не повторять consumed планы. После live-чтения подготовить минимальный отдельный
профиль с явными границами покрытия; не возвращаться к широкому горячему logger.
