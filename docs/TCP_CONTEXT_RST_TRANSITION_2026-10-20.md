# Контекст перенаправления: запись флага при RST+ACK

## Обновление: SEND-пропуск и исходный query10022 связаны в Run150607

Сохранённый Run `pb-target-accept-run-20261020-150607-18e07be2` завершился
`SEND_SKIP_AND_NATIVE_QUERY_FAILURE_OBSERVED`, errors/native_errors пусты.
Глобальная ACCEPT-точка отключена; использованы CREATE и адресная read-watch
только выбранного source endpoint. В присланном выводе нет LIMIT, UNREADABLE
или незапланированной остановки. Это не независимая запись всей консоли.

Для source endpoint `ffffb888c55e8b30` создан record `ffffb888c4cca260`,
context32bytes. Перед каждым SEND подтверждена прежняя ссылка EP+1c0→record.
Первый и второй проходы: NBL `ffffb888c5839b00`, flags `0x01101641`.
Третий проход: NBL `ffffb888bef937d0`, flags `0x01301641`.
Все три TCP-заголовка — SYN, порты42201→34010, sequence4173869915.
Первые два снимка одного NBL не объявляются двумя передачами в сеть.

Снимок EAX снят непосредственно после `mov eax,[rcx+30]`, перед `bt eax,15h`.
На третьем проходе бит21 установлен, поэтому следующая ветка обходит вызов
ассоциации контекста в `WfpTlShimInspectFastLoopbackSendDatagram`. Это теперь
наблюдаемый выбор ветки конкретным последующим SYN, а не только статическая
гипотеза. Полный lifetime NBL и все другие пути ассоциации не покрыты.

В том же Run единственный control42201 принадлежит nativePID14796;
query201 в relayPID3956/socket6108 вернул APIreturn-1/WSA10022/bytes0,
при required32 и успешном чтении local/peer endpoints. Нулевой GUID не
используется как ключ. Session/cohort COLLECTED, cleanup_errors пусты,
native processes stopped; CLI graceful/unforced/poststopverified.
Сохранённый DisableIOCTL completed, независимого gEnabled readback нет.
ETW EventsLost/LogBuffersLost/RealTimeBuffersLost равны0; новые точные ETW
RST/retry joins здесь не выполнялись и debugger↔ETW clockalignment не заявлен.

Этот Run не измеряет kernel ACCEPT/RETRIEVE NTSTATUS. Он доказывает совместное
наблюдение SEND-пропуска и исходного query10022 одного контрольного соединения;
сам по себе не доказывает отсутствие всех альтернативных путей переноса record.
RST+ACK как источник установки bit21 наблюдался в прежнем Run084117 ниже,
не в этом же захвате. `root_cause_proven`/`trap_coverage_verified` остаютсяfalse.

Выборочная проверка исходников: driver записывает redirect handle, targetPID,
context/size до Apply; usermode вызывает IOCTL на принятом socket с буфером32.
Это соответствует проверенным базовым требованиям
[FWPS_CONNECT_REQUEST0](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/fwpsk/ns-fwpsk-_fwps_connect_request0)
и [SIO_QUERY_WFP_CONNECTION_REDIRECT_CONTEXT](https://learn.microsoft.com/en-us/windows/win32/winsock/sio-query-wfp-connection-redirect-context).
Это не полный аудит драйвера и не исключение всех нарушений контракта WFP.
Рабочий диагноз — нарушение переноса redirect context через loopback SYN retry
в пути tcpip.sys после установки bit21. Окончательная атрибуция Windows/driver
требует отдельного доказательства, а не ещё одного увеличения cap.

Private: `artifacts/diagnostics/pb-send-native-review-20261020-150607/`
с user-console.txt и send-report.json. Продукт и память ядра при разборе не менялись.

## Предшествующее наблюдение RST-перехода

Разобран сохранённый Run `pb-target-accept-run-20261020-084117-5cf406f7`.
Новых запусков, трафика и управления отладчиком при разборе не было.

## Что непосредственно наблюдалось

Адресная аппаратная точка записала изменение поля `source endpoint + 0x30`:
`0x01101641 → 0x01301641`, то есть установку `0x200000` (бит 21).
Инструкция — `lock or [rbx+0x30],0x200000` внутри
`tcpip!WfpTlShimInspectRecvTcpDatagram`. Аппаратная точка наблюдает состояние
после записи; стек подтверждает путь приёма TCP через loopback.

В том же срабатывании снят TCP-заголовок обрабатываемого пакета:

| Поле | Значение |
| --- | --- |
| Исходный порт | 34010, listener relay |
| Порт назначения | 42201, контрольный клиент |
| TCP flags | `0x14`: RST и ACK, SYN отсутствует |
| Длина заголовка | 20 байт |
| Sequence | 0 |
| Acknowledgment | 2356919607 |
| Window | 0 |

Сырые 20 байт: `84daa4d9000000008c7bbd3750140000fe1c0000`.
Декодирование flags согласуется с форматом TCP в
[RFC 9293, §3.1](https://www.rfc-editor.org/rfc/rfc9293.html#section-3.1).
Это прямое наблюдение установки флага при обработке RST+ACK, без сопоставления
двух часов по близости событий.

Пять WRITE относятся к одному выбранному endpoint и той же записи redirect
record. Обработчик перед каждым WRITE проверяет `endpoint+0x1c0 == record`.
Следовательно, запись не исчезла из исходного endpoint к моменту перехода.
Это не доказывает её сохранность после снятия watch-точки и не означает
сохранность контекста на последующем принимающем сокете.

## Независимые данные этого прогона

Нативный контроль: PID15052, единственный исходный query вернул
Winsock10022/bytes0. Отчёт `TARGET_FAILURE_REPRODUCED`, errors пусты.
ETW для точной пары `127.0.0.1:42201 ↔ 127.0.0.1:34010` содержит два
SYN-drop Reason30, два sent-RST Reason2, два client-discard Reason10,
повторные попытки RexmitCount1/2 и затем успешные TCP connect/accept.
Потери событий и буферов ETW равны нулю. Ненулевой client TCB рассмотрен
только в его интервале init..close; TCB0 не используется для соединения событий.

Session/cohort COLLECTED, cleanup_errors пусты, native processes stopped;
CLI завершён штатно без forced stop, post-stop проверен. Resident driver
disabled-after подтверждён сохранённым отчётом. Это факты завершённого Run,
а не заявление о текущем состоянии после выключения или перезагрузки VM.

## Механизм и оставшийся пробел

В проверенном коде `WfpTlShimInspectFastLoopbackSendDatagram` тест бита21
в `endpoint+0x30` расположен перед ассоциацией redirect record с NBL:
при установленном бите переход ведёт к завершению этого helper.
Это подтверждённая статическая ветка, не свидетельство исполнения этой ветки
конкретным повторным SYN в данном Run.

Наиболее вероятная цепочка: заполненная accept queue → пауза listener →
отклонение SYN/RST → обработчик receive устанавливает бит21 → повторный SYN
обходит ассоциацию redirect record → принимающий сокет не получает контекст →
10022. Последний захват закрыл именно звено «RST+ACK устанавливает бит21».

В том захвате не были связаны последующий повторный SYN/NBL того же endpoint
с исполнением обхода ассоциации и отсутствующим контекстом на accept.
Новое SEND-наблюдение описано выше. Часы WinDbg и ETW не привязаны; не присваивается
номер конкретному RST в ETW и не утверждается его точное положение относительно
retry/query. Здоровый Run080831 показал успешное получение record до установки
того же флага, но TCP-заголовок здорового перехода не снимался.

Данных для окончательного вывода «дефект ProxyBridgeDrv» или «дефект Windows»
пока недостаточно. Счётчик очереди AFD не является размером таблицы драйвера.
Поведение10061 отдельно не исследовалось. Продукт и память ядра не изменялись.

Приватные исходные данные и результаты разбора сохранены отдельно:
`artifacts/diagnostics/pb-endpoint-packet-watch-review-20261020-084117/`:
user-console-excerpt, provenance, watch-report, tcp-header-decoded,
control-etw-events и send-gate-disassembly. Граница Run подтверждена привязкой
пользователя; независимой автоматической записи всей консоли нет.
