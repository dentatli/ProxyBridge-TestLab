# Потеря redirect context после отказа очереди: проверенные меры

На физическом PB-SUT подтверждено: предотвращение переполнения очереди
приёма устраняет наблюдаемый отказ в проверенном сценарии из 201 соединения.
Это проверенная мера предотвращения, а не восстановление утраченного context
или доказанное исправление внутренней ошибки Windows.

Позднейший [опыт на одном соединении](TCP_CONTEXT_SINGLE_FLOW_DROP_2026-10-22.md)
воспроизвёл отказ после временного inbound block без переполнения очереди.
Поэтому accept-first предотвращает проверенный queue trigger, но не доказан
как универсальное исправление metadata при потерях и повторной передаче.

## Различающий опыт

Windows 11 build26200.9711, boot2026-10-22T05:12:09.5Z. ProxyBridgeDrv
Stopped/Disabled; независимый Microsoft WFPSampler с исправленными inline flags,
SYS SHA d09a6871038f1f5e4dfb6c6266262d582691ae843f4cbbd6cdbb53fdefe92b95.
Debugger и точки не использовались. На каждом accepted socket ровно один
QUERY_RECORDS, затем один QUERY_CONTEXT, без fallback и повторного getter.

| Условие | Контекст и данные | ETW выбранного соединения |
| --- | --- | --- |
| SOMAXCONN; приём закрыт до заполнения 200 мест | 200 успешных; дополнительное соединение: оба getter10022/0 | Два1214Reason30, повторные SYN1186/Rexmit1/2 |
| SOMAXCONN; принимать до обработки данных | Все201: records/context и512KiB в каждую сторону успешны | Нет Reason30 и SYN retransmit |
| Единственный Listen(-512), то есть SOMAXCONN_HINT(512); приём закрыт до connect201 | Все201: records/context и512KiB в каждую сторону успешны | Нет Reason30 и SYN retransmit |

В каждом опыте проверено точное множество201 различных source ports,
соответствие tuple/context,256байт контекста sample, содержимое512KiB в обе
стороны и пустой cleanup. ETW EventsLost0, выбранные event types декодированы
без ошибок. В успешных трассах есть обычное событие Reason20 при завершении;
отсутствие всех TCP drop events не заявляется.

В Drain сервер действительно принял201 сокет до обработки данных. Это
ограниченный эксперимент, а не готовая промышленная реализация очереди.
В Capacity контроль успел подключиться, пока accept gate был ещё закрыт.
Таким образом, положительные результаты получены двумя разными изменениями,
сохраняющими WFP driver/context/API последовательность.

## Что установлено и что остаётся гипотезой

Воспроизводимый триггер — отказ заполненной очереди listener и последующий
SYN retry. Принимаемое после этого соединение может не иметь redirect record:
отказывают оба getter, хотя само TCP соединение установлено. Код ProxyBridge,
ошибка размера пользовательского буфера и активная отладка не являются
необходимыми условиями воспроизведения.

Старые kernel captures дополнительно показывали сохранённый record на source
endpoint, RST+ACK→установку bit0x200000 и обход send association для retry,
а также NULL record на query endpoint. Это согласуется с дефектом переноса
метаданных в Windows TCP/IP/WFP. Полная непрерывная история одного пакета и
назначение private bit не доказаны; данное сравнение не превращает гипотезу
о конкретной Windows инструкции в установленный факт.

## Как исправлять в приложении корректно

1. Освобождать очередь приёма независимо от обработки соединения. В исходном
   relay после accept на этом же потоке выполняются context query, поиск имени
   процесса, выбор правила, отчёт/логирование и создание worker. Медленные
   операции нужно вынести из потока приёма в ограниченную очередь работников.
   Это кандидат изменения продукта; на текущем этапе продукт не изменён.
2. Явно задавать запас backlog через SOMAXCONN_HINT(N) при первом listen для
   каждого IPv4/IPv6 listener, вместо предположения, что SOMAXCONN неограничен.
   Проверено N512 для201 соединения; это не универсально достаточное значение.
3. Ограничивать число принятых сокетов и работников, измерять задержку accept
   и отказы перегрузки. Просто увеличенная очередь не предотвращает отказ
   при любой нагрузке и не заменяет быстрый приём.
4. Если context/records уже отсутствуют, закрывать соединение с точной
   диагностикой. Не угадывать исходное назначение, не использовать чужой
   context и не выдавать повторный getter за восстановление. Исправление
   Windows, сохраняющее record при этом retry, требует отдельной работы
   поставщика ОС; поддерживаемого API для дописывания record принятому
   повреждённому сокету в рассмотренном контракте нет.

Практические меры выше доказаны на независимом IPv4 sample. Исправление
ProxyBridge, IPv6, длительная перегрузка и производительность продукта ещё
не проверены. Приписывать им успех этих опытов нельзя.

Контракты: [listen/SOMAXCONN_HINT](https://learn.microsoft.com/en-us/windows/win32/api/winsock2/nf-winsock2-listen),
[.NET Framework Socket.Listen](https://github.com/microsoft/referencesource/blob/main/System/net/System/Net/Sockets/Socket.cs).
В Framework Socket.Listen передаёт отрицательный backlog непосредственно в
Winsock и обновляет managed listening state; нативный обход не нужен.

## Неполные попытки и свидетельства

Capacity-r1: нативный listen не выставил managed listening state; Accept
отказал до queries. Capacity-r2: порт47001 зарезервирован WinRM, Bind10013.
Capacity-r3: двойной listen (SOMAXCONN, затем native hint) не обеспечил connect
контроля до deadline; это не тот single-listen профиль, который дал успех.
Все три INCOMPLETE, старые материалы сохранены. R4 использует простой первый
Socket.Listen(-512), отдельный kit-r7 и новый source port диапазон.

Private evidence:

- pb-independent-baseline-20261022-r1, source44000..44199/control44201, kit-r5.
- pb-independent-drain-20261022-r1, source46000..46199/control46201, kit-r5.
- pb-independent-capacity-20261022-r4, source48500..48699/control48701, kit-r7.
- pb-queue-comparison-review-20261022-r1/report.json:
  QUEUE_REFUSAL_PREVENTION_VERIFIED, все28 checks true.
- pb-independent-queue-final-state-20261022-r1: sample filters0,
  sample servicesStopped, productStopped, HLKRunning, probe/listenerнет.

ETL SHA256: baseline2854826eebc52a2228010bf57439140439fd35a560b6fcf43a2a3b5db5ca1cc5;
drain54c330f3df8c2b46a077aa2f68e1b39ff8f2d93a6a8369c83a2995c468f6b802;
capacity26def99a2450e3a7cfef9589aa48b519c636137b5c0591afeed438cd59297430.
Derived ETW selection читает ETL без создания многосотмегабайтного XML;
sockaddr из Get-WinEvent нормализованы из hex, loss получен tracerpt summary.
Киты, ETL, credentials и debugger keys в Git не включены. Никому не отправлялись.
