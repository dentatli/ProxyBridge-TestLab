# Причина отказов UDP: потеря назначения и идентичности клиента

## Вывод

На базе продукта `b3596272a8dc8898790b016d1e4c488c2fdc917d` причина установлена
в драйвере **и** Core. Текущая модель UDP хранит недостаточно данных для
однозначной маршрутизации пакетов. Исправить только wildcard lookup недостаточно.

| Участок | Причина | Проверенное проявление |
| --- | --- | --- |
| Driver → relay | Map индексируется исходным endpoint; один endpoint хранит только последнее назначение | Пакет A ещё в очереди relay, но IOCTL уже возвращает назначение B |
| Driver lookup | Wildcard адрес при регистрации не совпадает с конкретным recvfrom source | Connected implicit/wildcard не проходит; concrete bind проходит |
| Core → SOCKS → Core | Одна UDP-ассоциация на proxy config объединяет клиентов; ответ выбирает наиболее активного | Клиент B получил payload A, клиент A получил timeout |
| Core IPv6 | Получение назначения осталось на таблице старого пути, которую WFP backend не заполняет | Core IPv6 0/6 при успешных direct, explicit SOCKS и driver-only controls |

Предыдущие результаты и ограничения матрицы приведены в
[локальном отчёте](UDP_LOCAL_MATRIX_CURRENT_DRIVER_2026-10-22.md).
Ниже — новый опыт и проверка причин по исходникам; патч продукта не внесён.

## Новый driver-only опыт: один сокет, два назначения

Физический PB-SUT, локальный режим, установленный SYS SHA256
`3e5c3c709ee8c8800628f04b5550f3a82377deb264b045ab2f2ccbab3fd8fb4c`.
Core и SOCKS не загружались. Один controller владел штатным IOCTL handle.
Worker PID 8108 явно привязал один IPv4 UDP-сокет к `127.0.0.1:61578`,
послал два разных 33-byte nonce payload и оставался жив, удерживая сокет.
Controller начал читать relay только после завершения обеих отправок.

| Payload | Настоящее назначение при sendto | Source в recvfrom | Назначение из QUERY_UDP при dequeue |
| --- | --- | --- | --- |
| A | 127.0.0.1:61576 | 127.0.0.1:61578 | **127.0.0.1:61577** |
| B | 127.0.0.1:61577 | 127.0.0.1:61578 | 127.0.0.1:61577 |

Оба QUERY вернули found=1, 52 bytes и правильный PID 8108. На двух исходных
сокетах назначения пакетов не было; оба payload получены в relay. SHA256 A:
`b5ec42b6e914d1a34c173020d319fdc493f660d43703f3c71082bde1839b3b6f`, B:
`53e6d4a01a91ba3ba086fc5435bd632f89ee4977c0aa4f69af0eb1d192cf5f3e`.
Это потеря исходного назначения до Core, без wildcard и без закрытия клиента.
Задержка чтения контролируемая: опыт доказывает допустимое для очереди
расписание отказа, а не измеряет частоту ошибки в обычной нагрузке.

В сыром JSON вычисляемый marker `one_source=false` ошибочен: harness сравнил
tuple из recvfrom со list, полученным из JSON worker. Сами записанные адреса
и порты совпадают. Offline review нормализовал типы, подтвердил один source
и остальные gates; сырой capture сохранён без исправлений и повторного Run.

Evidence: private/ignored `artifacts/diagnostics/udp-two-dest-target-20261022-r1`;
новые исходники runner/probe и offline review:
`artifacts/diagnostics/udp-root-cause-20261022-r1`.
`review-result.json`: PASS. SHA256 нового `evidence-manifest.json`:
`64a970d1d48473cafcbae7dbe07d126cf46a795e6f60afeb288f641c952b3f6d`.

Runner подтвердил восстановление: driver Stopped/Disabled, PnP problem32,
restore exit0, test processes=[], probe disable/cleanup=true. Wrapper:
COLLECTED, target identity=true, cleanup_errors=[], client WinRM Stopped.
Драйвер не устанавливался; использован read-only Python runtime из r5,
старые workloads не возобновлялись. Debugger и KernelReadCapture не применялись.

## Проверка механизма в исходниках

Пути ниже относительно `C:/src/ProxyBridge-accept-first`, revision `b359627`.

1. `Windows/driver/src/ProxyBridgeDrv.c`, ClassifyCore, около строки 204:
   source берётся из localAddressAndPort до redirect и передаётся в UdpMapPut.
   `Windows/driver/src/pbdrv_state.c:89–129`: ключ family/source IP/source port;
   при совпадении UdpMapPut заменяет orig address/port и PID. UdpMapGet читает
   текущее значение, не значение для конкретного datagram. Именно это
   воспроизведено новым опытом. Нормализация wildcard устранит один lookup
   mismatch, но не восстановит перезаписанное назначение A.
2. `Windows/src/core/pb_internal.h:148–150`: udp_tcp_ctrl, udp_send_sock и
   udp_relay_addr принадлежат PROXY_CONFIG. `proxy/pb_socks5.c`,
   establish_udp_associate_for_config, создаёт эту общую ассоциацию;
   `relay/pb_relay_udp.c:231` отправляет через cfg->udp_send_sock.
   Ответы в строках 314–334 выбирают connection по remote address/port
   и максимальному last_activity. В предыдущем paired опыте оба запроса
   использовали один proxy_out peer `127.0.0.1:64269`, одно назначение
   `127.0.0.1:64220`; B получил точный hash payload A. Это ожидаемый результат
   данного алгоритма, а не неисправность origin.
3. SOCKS5 UDP-заголовок содержит адрес/порт назначения и payload, но не
   исходный локальный endpoint приложения. UDP association связана с TCP
   control connection; его закрытие завершает association.
   Следовательно, общий канал не даёт восстановить владельца произвольного
   ответа только из заголовка. Основание: [RFC 1928, sections 6–7](https://www.rfc-editor.org/rfc/rfc1928.html).
   last_activity, FIFO или порядок обхода hash table не заменяют идентификатор.
4. `relay/pb_relay_udp.c:176–185` получает IPv4 original/PID через драйвер и
   добавляет connection. IPv6-ветка `:391` только читает get_connection_full_v6.
   `relay/pb_conntrack.c:39–82`: единственная вставка создаёт is_ipv6=FALSE;
   lookup `:87–104` требует TRUE. В Windows/src нет присваивания
   is_ipv6=TRUE или другого заполнителя IPv6 connection table. WFP — единственный
   backend (`driver/pb_driver.c:10`). Поэтому IPv6 relay не может получить
   назначение этим путём. Одного нового IOCTL helper недостаточно без
   заполнения и использования полноценного IPv6 состояния.

Дополнительный риск по исходникам, **не отдельный runtime результат**:
add_connection сопоставляет source port/protocol/family, игнорируя source IP.
Два клиента с одинаковым портом на разных локальных адресах также могут
сливаться. Это нужно учесть при выборе нового ключа и lifecycle состояния.

Offline сравнение подтвердило: тела ClassifyCore, UdpMapPut, UdpMapGet
совпадают с upstream `63be0eb`; файлы pb_relay_udp.c и pb_conntrack.c целиком
имеют прежние Git blobs. Эти алгоритмы не внесены HLK и accept-before-setup PR.
Изменения жизненного цикла драйвера в HLK PR этим сравнением не отрицаются.

## Требования к исправлению и границы вывода

Нужен согласованный контракт driver ↔ relay: исходное назначение должно
однозначно относиться к конкретному принятому datagram/потоку и не исчезать
после следующего sendto того же сокета. Добавление destination в ключ QUERY
само по себе не помогает: relay ещё не знает этот destination. Конкретный
механизм передачи metadata или выделения relay endpoints ещё не выбран
и не проверен; это следующий этап реализации.

В Core нужно сохранить владельца upstream UDP-трафика отдельными полноценными
SOCKS associations на соответствующий endpoint/flow либо другим однозначным
механизмом. Нельзя предполагать, что несколько UDP sockets при общем TCP
UDP_ASSOCIATE совместимы с любым сервером. IPv4/IPv6 должны использовать
полноценный общий принцип получения original/rule/session и обратной доставки.
Ключи должны учитывать локальный адрес, семейство и lifecycle/повторное
использование endpoint; stale записи не являются доказательством владельца.

Вывод относится к проверенным UDP-сценариям. Внешний сервер, TCP failure,
полный TestLab Run и CLI lifecycle здесь не аттестованы. Product checkout
остался чистым на `codex/udp-map-source-key`; новых product commits/PR нет.
