# Подтверждённая цепочка RST → SYN retry → отсутствие redirect context

## Результат

На физическом PB-SUT получена непрерывная цепочка одного соединения от
создания redirect record до отказа запроса на принятом сокете. Причина
наблюдаемого отказа локализована в tcpip.sys: ранний RST+ACK устанавливает
bit 0x200000 в source endpoint+0x30; последующий loopback SYN retry с этим
битом обходит привязку redirect metadata к новому NBL. Accepted endpoint
остаётся без record, поэтому запросы RECORDS и CONTEXT возвращают 10022/0.
Сам source record и его context в этот момент сохранены.

Это подтверждение механизма на исследованной сборке, а не утверждение о всех
версиях Windows или готовый патч её закрытого исходного кода. Именованная
семантика private bit неизвестна. Изменений private flags/памяти ядра не было.

## Условия и связь свидетельств

Один flow 127.0.0.1:48807 → listener34010, context256, corrected Microsoft
WFPSampler kit-r7. Product ProxyBridgeDrv остановлен; fillers и переполнения
очереди нет. Boot PB-SUT: 2026-10-22T05:12:09.5Z, OS26200.9711.
tcpip.sys26100.8875, SHA256
`b0683bd7ed0f309e63b4e6e71675d8f04cfb0ea5533c3f5e8a13c6daca3b595a`.
Перед регистрацией проверены live instructions выбранных точек.

WinDbg GUI работает в agent VM и подключён только к физическому PB-SUT.
Старый named pipe к VM, KernelReadCapture и hidden kd не использовались.
Профиль отслеживает source endpoint hardware watch; software return/accept/query
точки включаются по этапам. Новый профиль не объявлен соответствующим старым
frozen kits. Адреса ниже относятся только к этому boot.

| Этап | Наблюдение |
| --- | --- |
| CREATE | sourceEP `ffffa18fbae2a010`, record `ffffa18fb6c60660`, context `ffffa18fbcc6fb40`, size0x100 |
| Первый SYN | flags0x1101641; NBL `ffffa18fb6ded8e0` меняет info_raw с1 на `ffffa18fc38cd2b1` между SEND_GATE и SEND_RETURN |
| Ранний RST+ACK | flags TCP0x14, seq0, ack_raw0x3457b0e9; writer `WfpTlShimInspectRecvTcpDatagram+0x198` после OR: endpoint flags0x1101641 → 0x1301641 |
| Повторные SYN | тот же sourceEP/record/seq_raw0x3357b0e9; info_raw1 до и после send helper, return status0 |
| Последний SYN | NBL `ffffa18fc2aa9c30`, info_raw1, flags0x1301641 |
| ACCEPT | ровно этот NBL; acceptedEP `ffffa18fbe682050`, retrieve status0xc0000225, output_record0, info_raw1 |
| QUERY | тот же acceptedEP, IOCTL0x980000dd, record0; sourceEP всё ещё содержит исходный record |
| Исходный API | serverPID5684/TID4940 = kernelPID0x1634/TID0x134c; source port48807; RECORDS10022/0 и CONTEXT10022/0 |

ACK RST равен SYN sequence+1 после перевода из network byte order.
В журнале шесть SEND_GATE/RETURN событий: это проходы helper, а не шесть
доказанных отправок пакета. ETW отдельно показывает SYN retries1/2 и три
RST send/receive всего; терминальный RST нельзя смешивать с ранними.
ETW events lost0. Контроллер собрал одну query, ошибки cleanup отсутствуют.
Child ExitCode в его JSON null; это не выдаётся за подтверждённый exit0.

## Почему это объясняет отказ

Проверенный код `WfpTlShimInspectFastLoopbackSendDatagram+0x30` тестирует
bit21; переход +0x34 при установленном бите идёт прямо к эпилогу+0x14f,
обходя association key5. В этом опыте зафиксированы flags с этим битом,
SYN header и отсутствие metadata до и после helper. Затем тот же NBL
дошёл до accept и дал NOT_FOUND. Это закрывает прежний пробел, когда
skip и accept были получены для разных NBL без надёжного join.

Здесь info_raw1 означает отсутствие структуры WFP info в проверенном
представлении; private списки key5 заново не обходились. Вывод о пропущенной
привязке опирается на live gate/return, дисковый код и retrieve NOT_FOUND
вместе, а не на единственное поле info_raw.

Предыдущие [различающие опыты](TCP_CONTEXT_RST_DISCRIMINATION_2026-10-22.md)
без отладчика дополняют цепочку: при подавлении ранних RST три SYN retries
сохраняют context и передают данные; при возврате RST ошибка возвращается.
Поэтому один лишь retry или задержка debugger не объясняют совокупность результатов.

## Корректное исправление

В ProxyBridge — уже подготовленный accept до setup: быстро освобождать
accept queue, выполнять context/process/rules и дальнейший setup вне accept
loop. Это предотвращает подтверждённый queue-refusal trigger. Ветка
`codex/accept-before-setup`, commit `37e64c6e835a64833f1d3ae385052bb2125b93e6`.
Этот захват не является runtime-проверкой новой продуктовой сборки; код
продукта, драйвер и тесты здесь не менялись.

Такой accept не устраняет все возможные источники раннего RST: независимый
опыт воспроизвёл отказ одним соединением с временным transport block.
При отсутствующем context нельзя угадывать original destination или
многократно повторять getter в надежде восстановить отсутствующую привязку.

Для Windows требуется сохранить необходимую redirect association на SYN
retry после нефатального раннего receive, соблюдая lifetime/refcount.
Точное изменение закрытого кода должен подтвердить его владелец. Патчить
private bit или подавлять все RST в продукте не предлагается.

## Сохранение и завершение

Private captures, не в Git:

- `artifacts/diagnostics/pb-independent-single-flow-kernel-20261022-r2` — API, ETL, flow-history, capture files.
- `artifacts/diagnostics/pb-gui-single-flow-20261022-r2` — профиль, debugger-final.log, анализ связи.
- `artifacts/diagnostics/pb-single-flow-final-state-20261022-r2` — QUIESCENT.

После опыта sample filters0, probe0, listener0; WFPSampler/Callouts и
ProxyBridgeDrv Stopped, HLKsvc Running. Hardware watch3 удалён; IDs2/4/5/6
проверены disabled, выполнен отдельный g, PB-SUT работает.

Предыдущий fresh run-r1 неполон: ошибка разделителя внутри hardware callback
остановила target. Точки сняты и g выполнен; WinRM восстановлен, свидетельства
собраны отдельно. Контроллер сообщил ошибку загрузки NetTCPIP. Для run-r2
разделители исправлены и модуль загружен до запуска flow. Старый run не
повторялся и не использовался как доказательство сетевого механизма.
