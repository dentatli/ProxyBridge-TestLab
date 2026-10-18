# ETW bounded без WinDbg: подтверждение прежнего триггера

Run `pb-kd-session-run-20261018-191222-7a5aa77a`, пользовательская дата
2026-10-19: 4 →64→256→4,328попыток, оригинальный query один раз на принятый
сокет,512KiB, без зарегистрированных/активных WinDbg points. Драйвер resident,
профиль `pb-etw-tcpip-no-points-v1.json` SHA
`d7d05fd2d7a79c75e596b4f0d2b8b91096e4b1a370969d7544780e73bb4dbd3a`.
Boot114/event16953 прежний. Новый одноразовый plan191134-e981253b,
SHA `c9420fbd04736d007cbc4c03b5d1b34a32ba6446c0d206468b6d54e931525b45`;
priorfour190824-00e55c9d проверен и привязан к тем же boot/profile.

## Наблюдения

Native/Core evidence без ошибок:296успехов,32отказа, все32 уникально
сопоставлены с исходным query api_return=-1/WSA10022/bytes0. Отказы вload256;
recovery4успешен. Непривязанных10061 в этом Run не было.

| Наблюдение для того же local/peer tuple | 296 успешных | 32 с Core10022 |
| --- | ---: | ---: |
| TcpAcceptRedirect1553 на один tuple | 1 | 2 |
| TcpConnectRestransmit1186 | 0 | 1 |
| TcpipTransportPacketDrops1214 Reason30 | 0 | 1 |
| TcpRstSend1479 Reason2, local34010 | 0 | 1 |

Локальное декодирование Windows выводит Reason30 как
`Listener dropped SYN because SO_PAUSE_ACCEPT was set`, Reason2 как
`Listener was paused`. События связаны по полному local/remote sockaddr;
все328query tuples уникальны в capture. Для failed tuples между1553
511.760–512.134ms; есть1351v1 RTO/SynSentState/RexmitCount1 и1186 по тому же
clientTCB/tuple. Это относительное время внутри одной ETW трассы. Сопоставление
Core QPC с ETW timestamp не заявляется; XML имеет offset+04:59.

Все1553 для выбранных соединений имеют Succeeded1/Redirected0/CodePath2.
Эти значения не различают наличие WFPcontext: у296успешных он был получен.
1315 не наблюдался. Совпадение адресов TCB между событиями само по себе не
является идентичностью объекта за всю трассу: allocator повторно использует
адреса. Exploratory `lifecycle-examples.json` с глобальным TCB join не годится
для выводов о lifecycle; отдельный `lifecycle-owned-examples.json` предпочитает
явный sockaddr и ограничивает TCB-only события предшествующим адресным anchor.
Даже этот пример не доказывает приватный record transfer/free.

ETW final STOP counters EventsLost/LogBuffersLost/RealTimeBuffersLost=0,
header loss0,414buffers, TCPIP decoding errors0. Собственная сессия stopped/
exported. Native modeCOMPLETED/workers_stoppedtrue/resident DISABLE after
completed/SCMRunning/driver_unloadedfalse; независимый readback gEnabled не делался.
Исходные capture/ETL/XML/receipts и private review сохранены вне Git в
`artifacts/diagnostics/pb-etw-bounded-review-20261019` и каталоге Run.

## Что это устанавливает

Получено воспроизведение прежнего триггера без WinDbg points:
пауза listener → отклонённый SYN → повтор connect → принятый сокет →
исходный Core query10022. Аналогичная цепочка уже документирована в
[прежнем статусе](TCP_CONTEXT_STATUS_DIAGNOSTIC.md) и
[матрице](TCP_ROUTE_MATRIX_DIAGNOSTIC.md). Этот Run подтверждает работу новой
автономной оснастки, а не открывает новую первопричину. В этом capture
NTSTATUS исходного query не измерялся; исторический C0000225 не переносится
на него как новое прямое наблюдение.

Не доказаны: операция утраты/отсоединения privateWFP record, виновность Windows
или ProxyBridgeDrv, переполнение таблицы, исправление backlog. Продукт не менялся.
Повтор той же ETW нагрузки без нового наблюдаемого перехода не предлагается.
Далее нужен адресный разбор [record lifecycle](TCP_CONTEXT_ENDPOINT_LIFECYCLE_PLAN.md)
с учётом уже найденных silent misses/самостопов аппаратного логгера;
не возвращаться к большому набору точек и не трактовать пропуск снимка как
отсутствие Apply. Сначала офлайн определить, какой переход ещё не измерен и
какой способ может надёжно его наблюдать.
