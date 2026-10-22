# Redirect context: отказ на одном соединении после блокировки пакетов

**Исправление разбора:** ниже сравнивались только terminal-RST события1184.
Последующий разбор1479/TcpRstSend и1601/TcpRx обнаружил ТРИ ранних RST+ACK
в SynSent на этом же TCB. Вывод о необязательности предварительного RST
отозван. [Различающий опыт с подавлением RST](TCP_CONTEXT_RST_DISCRIMINATION_2026-10-22.md)
сохранил context после трёх SYN retries без RST. Не использовать прежний
ограниченный список selected-etw.json как полный список RST.

## Установленный результат

Переполнение очереди приёма не является необходимым условием отказа.
На независимом Microsoft WFPSampler одно соединение после временного
блокирования входящих пакетов выбранного loopback tuple установилось, но
QUERY_RECORDS и QUERY_CONTEXT вернули10022/0. Следующее обычное соединение
на том же kit и boot успешно получило records970/context256 и передало
524288байт в каждую сторону. ProxyBridgeDrv остановлен; debugger не использован.

Это расширяет [результат с очередью](TCP_CONTEXT_QUEUE_MITIGATION_2026-10-22.md):
быстрый accept предотвращает проверенный queue-refusal сценарий, но не доказан
как универсальное исправление отказов после других потерь и повторных SYN.
Product branch37e64c6 не менялась, новые тесты в неё не добавлялись.

## Условия и наблюдения

PB-SUT build26200.9711, boot2026-10-22T05:12:09.5Z. Kit-r7, исправленный sampleSYS
SHA256 d09a6871038f1f5e4dfb6c6266262d582691ae843f4cbbd6cdbb53fdefe92b95.
Один server и один control, без200fillers; accept разрешён до запуска control.
Временный BASIC_ACTION_BLOCK ограничен входящим TCP loopback tuple
127.0.0.1:48801 -> 127.0.0.1:34010. Он удалён после наблюдения SynSent.
Удаление не мгновенное: ETW показывает три Reason7 drop и RexmitCount1/2/3.
Не описывать опыт как блокирование строго одного пакета.

| Наблюдение | Значение |
| --- | --- |
| Выбранный source port | 48801 |
| Accepted socket local port | 34010 |
| QUERY_RECORDS | -1, WSA10022, bytes0 |
| QUERY_CONTEXT | -1, WSA10022, bytes0 |
| ETW выбранных типов | decode_errors0, EventsLost0 |
| Следующий Healthy, source48802 | records970, context256, dataValidtrue |
| Финальная уборка | sample filters0, probe/listener0, servicesStopped |

HLKsvc осталась Running. Target остался включённым. Статусы дочерних процессов
exit=null в controller JSON не трактуются как подтверждённые exit0; готовые
server/control summaries сообщают cleanupCompletedtrue, errornull.

## Терминальный RST зарегистрирован после getter; ранние RST первоначально пропущены

UTC нельзя получать простым сложением BootTime и QPC: такое предположение
для этого ETL дало неверное смещение. Вместо этого существующий ETL прочитан
через OpenTrace/ProcessTrace дважды: с обычным преобразованием timestamp и
с PROCESS_TRACE_MODE_RAW_TIMESTAMP. Записи сопоставлены по индексу, eventID
и полному payload. ClockType1/QPC, frequency10000000, loss0.

| Событие | QPC |
| --- | --- |
| QUERY_CONTEXT begin | 63630434667 |
| QUERY_CONTEXT end, WSA10022 | 63630434788 |
| Единственный выбранный Tcp1184/RST | 63630455207 |

Терминальный RST зарегистрирован в06:58:12.2979301Z, на2.0419мс позже окончания getter.
PID2816/TID8320 совпадают с серверным query. Исходный probe после отказа
записывает результат и выходит из using(Socket), закрывая accepted socket.
Следовательно, этот зарегистрированный RST не мог быть причиной уже
завершившегося10022; его время и поток согласуются с закрытием после отказа.

Этот расчёт верен для события1184, но не охватывает все RST. В существующем
ETL есть1479/RST send и1601/Flags20 (=0x14), трижды на клиентском TCB в SynSent
до getter. Они не завершали соединение и поэтому не дали1184 в этот момент.
Именно ограничение типов событий привело к ошибочной интерпретации. Вывод
о произвольном silent packet loss без RST данным опытом не подтверждён.

## Статический разбор прежнего tcpip.sys

Отдельно исследован сохранённый образ VM26100 с совпадающим PDB:
binarySHA256 b0683bd7ed0f309e63b4e6e71675d8f04cfb0ea5533c3f5e8a13c6daca3b595a,
PDBSHA256 a2fac488927d63e45ec07b1c8cd95446e699f5075f7b9ef7eb1f99286ae9a0dc.
Границы функций получены из PDB и сверены с .pdata.

- WfpTlShimInspectFastLoopbackSendDatagram, RVA0xd7e80: проверка bit0x200000
  поля endpoint+0x30 ведёт прямо к эпилогу, обходя блок association key5.
- WfpTlShimInspectRecvTcpDatagram, RVA0x234e0: lock or endpoint+0x30,0x200000
  расположен перед последующей проверкой результата и вызовом
  TlShimInspectTcpTransportReceiveFast. Ранее runtime фиксировал установку
  этого бита на receive; статический код не доказывает назначение private flag.
- Три найденных immediate mask0xffdfffff относятся к другим полям (+0x34,
  +0x34,+0x78), поэтому они не подтверждают очистку этого поля. Это не полный
  поиск всех способов очистки/перезаписи.

Первоначально предположенный RVA0x534e0 для receive отвергнут; сохранён как
rejected, в выводах использован0x234e0. Позднейшее копирование tcpip.sys с
физического PB-SUT подтвердило побайтное совпадение с этим образом: версия
файла26100.8875 при OS26200.9711. Это подтверждает совпадение дискового кода,
но не факт исполнения каждой ветви в конкретном опыте. Загруженная память
целиком не хешировалась. Патчить private flag не предлагается.

Рабочая гипотеза: после раннего drop/inspection endpoint сохраняет состояние,
при котором SYN retry проходит без переноса redirect metadata на новый NBL.
Точная инструкция, нарушающая ожидаемый lifetime на физической ОС, ещё
не установлена; общую ошибку sample или влияние иных компонентов окончательно
не исключили. Повторять200fillers или просто повышать raw breakpoint limits
для проверки этой гипотезы не требуется.

## Свидетельства и продолжение

Игнорируемые локальные материалы:

- pb-independent-silent-retry-20261022-r1: controller result, ETL, selected-etw.json.
- pb-independent-silent-healthy-20261022-r1: свежий положительный контроль.
- pb-independent-silent-final-state-20261022-r1: QUIESCENT.
- pb-rst-gate-static-review-20261022-r1: static-report.json, disassembly,
  read-etl-clock.cpp, clock-events.csv, clock-report.json и анализ часов.

Далее имеет смысл различить association на первом SYN и на его retry в
минимальном single-flow случае. Нужна привязка к реальному образу26200 и
tuple/sequence, а не неограниченная точка на всех пакетах. Небезопасные прежние
KernelReadCapture/hidden kd не запускать. PktMon только проинвентаризирован,
capture/filters не запускались; на этой версии filter remove удаляет весь
набор, поэтому нельзя применять его к чужим фильтрам.

Контракт чтения часов: [Microsoft EVENT_TRACE_LOGFILEW](https://learn.microsoft.com/en-us/windows/win32/api/evntrace/ns-evntrace-event_trace_logfilew).
