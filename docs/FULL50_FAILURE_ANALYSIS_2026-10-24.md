# Причины 12 FAIL в полном прогоне WinDivert 4.3.0

Разобран неизменённый attempt `20261023-161135-c28a486a85e84ca5973c16cecbd2c088`: preview.18, официальный WinDivert4.3.0, NORMAL/LOW,50 сценариев,38PASS/12FAIL. Это не WFP: прежние WFP map/injection findings сюда не переносились. Новых запусков продукта или сети нет; код продукта/лаборатории и старые отчёты не менялись.

## Вывод

- **7 UDP-связанных FAIL:** обнаружен дефект выбора получателя UDP-ответа в исходниках4.3.0. Сохранённые измерения показывают соответствующую ошибочную раздачу ответов между несколькими клиентскими сокетами одного назначения. Однопоточный UDP в этом же прогоне проходил.
- **5 HTTP/3/QUIC FAIL:** в лабораторном SOCKS5-получателе preview.18 есть воспроизведённая несовместимость с общей UDP-ассоциацией долгоживущей Core-сессии. Эти результаты не доказывают дефект QUIC/HTTP3 продукта. После исправления лаборатории фактический результат ещё предстоит измерить; PASS задним числом не выставлять.

## UDP: ответы возвращены, но попадают не тем потокам

| Сценарий | Прокси отправил к получателю | Прокси получил ответов | Работники подтвердили |
| --- | ---: | ---: | ---: |
| udp-connected |11285|11285|2824|
| udp-unconnected |11294|11294|2831|
| udp-sweep |11277|11277|2821|
| udp-connections |28250|28250|8507|
| app-dns-udp |4|4|0|
| mixed |11502|11502|2972|
| stability |11487|11487|2986|

Для udp-connected: четыре потока отправили2821/2821/2821/2822. Подтвердили2/0/2/2820; последний получил8451 чужих/некорректных ответов, invalid всего8461. Это не11285 исчезнувших в сети пакетов: получатель принял все, proxy reply counter тоже11285. Значение потерь~75% — отсутствие правильного подтверждения у нужного потока, а не доказанная физическая потеря в сети. invalid в этом формате не хранит отдельную причину (MAC/flow/payload), поэтому конкретный тип каждого invalid по raw установить нельзя.

В udp-connections baseline одного потока2835/2835 и recovery2830/2830 PASS. На нагрузке8 потоков:22585 отправлено,2842 подтверждено,19743 invalid. В mixed и stability TCP-часть нагрузки имеет5 успешных TCP flows; ломается UDP-часть. В DNS получатель и прокси вернули4 ответа; три клиента истекли по timeout, один отверг ответ как APPLICATION_DNS_RESPONSE_INVALID (проверка ID/вопроса запроса). Это соответствует попаданию ответа другого запроса в последний клиентский сокет.

### Механизм в официальном источнике

Тег `v4.3.0_Windows` разрешается в `8cb9dceeed582fcd7c2baed8d20eec34934732fc` (git ls-remote, совпадает с GitHub source). Считаны через GitHub plugin именно файлы тега, не текущая пользовательская WFP-ветка:

- [pb_relay.c, строки279–317](https://github.com/InterceptSuite/ProxyBridge/blob/8cb9dceeed582fcd7c2baed8d20eec34934732fc/Windows/src/pb_relay.c#L279): lookup только по orig_dest_ip/orig_dest_port, затем выбирается matching client с максимальным last_activity. Ответ отправляется на src_ip/src_port этого winner. Связи ответа с исходным клиентским сокетом здесь нет.
- [pb_relay.c, строки65–68 и183–206](https://github.com/InterceptSuite/ProxyBridge/blob/8cb9dceeed582fcd7c2baed8d20eec34934732fc/Windows/src/pb_relay.c#L65), [pb_socks5.c, establish_udp_associate_for_config](https://github.com/InterceptSuite/ProxyBridge/blob/8cb9dceeed582fcd7c2baed8d20eec34934732fc/Windows/src/pb_socks5.c#L394): SOCKS UDP-ассоциация/udp_send_sock принадлежат proxy config и разделяются клиентами. При одном удалённом endpoint возврат неоднозначен.

В capture одного прогона ровно1 UDP ASSOCIATE, PID1220; raw origin показывает1 association и один origin-side UDP peer у разных потоков. Source-механизм и наблюдаемая доставка практически всех ответов одному активному клиенту согласованы. Это анализ сохранённого runtime плюс официального исходника; бинарный патч/A-B исправления не выполнялся. Простая смена порядка выбора клиента/round-robin проблему владения ответом не решает.

## QUIC/HTTP3: блокирует лаборатория

Файл из immutable preview.18: `src/trafficlab/proxy.py`, SHA256 `3ebfb0294ef4926b002ba45aaa983683dd20c8568e136c8d6ce5899393d874e5`; совпадение с SHA256SUMS проверено. Там:

1. После обычного UDP в association сохраняется run_id текущего подэтапа.
2. Строки230–232 отбрасывают QUIC, если association уже имеет run_id, но ещё не имеет quic_identity. Следовательно, переход UDP→QUIC по общей ассоциации заблокирован до передачи Initial получателю.
3. Даже свежая QUIC association ограничена одним quic_port (менять HTTP3↔QUIC нельзя), а observe_quic55–66 отвергает вторую идентичность потока. Это также несовместимо с несколькими QUIC-клиентами в общей ассоциации.

Речь об ограничениях лабораторного учёта, не обязательном поведении SOCKS5: [RFC1928, UDP section](https://www.rfc-editor.org/rfc/rfc1928#section-7) задаёт адрес/порт в каждой дейтаграмме и связывает срок жизни UDP association с TCP control connection, а не с одним лабораторным case.

На **файле из пакета18**, с подставными transport (без сокетов/продукта/изменения пакета), воспроизведено:

| Состояние association | QUIC-пакетов передано дальше |
| --- | ---: |
| Новая association |1|
| После обычного UDP/run_id |0|
| Уже зарегистрированный QUIC, тот же порт |1|
| Уже зарегистрированный QUIC, другой порт |0|

Второй flow для той же association даёт SOCKS_QUIC_IDENTITY_INVALID. Порты в воспроизведении42520/42521 соответствуют frozen QUIC/HTTP3. Скрипт запускается с -B, frozen package не дополняется pycache.

Все5 affected cases: app-http3, app-http3-multiplex, app-http3-payload-sweep, app-quic, app-quic-multiplex. В raw каждый клиент отправлял4–5 QUIC datagrams и получил0; QUIC origin counters0. Правила получили verified ACK/path, lifecycle ready=true и4 PROXY events, DIRECT0. В capture одна association за всю очередь; до HTTP3 уже выполнялись UDP cases. Наличие run_id без quic_identity, блокирующее этот переход, следует из этой последовательности и кода. Итого generic handshake incomplete/connection terminated/route unverified — следствие, а не установленная ошибка QUIC продукта.

Исправлять следует совместимость лабораторного proxy/identity accounting с сохранённой ассоциацией и несколькими flows/протоколами, сохраняя authentication/ownership/route gates. Перезапускать клиент между case или отключать проверки идентичности — подмена согласованной методики. Даже после исправления лаборатории возможна реальная многопоточная UDP-проблема4.3; успешный QUIC заранее не обещать.

## Полнота, правила и очистка

Неправильно созданные правила не объясняют эти данные: verified rule ACK есть, UDP дошёл до proxy/origin, ответы вернулись; QUIC имел PROXY events, но не достиг origin. Ошибки ROUTE_UNVERIFIED/TRANSPORT_INCOMPLETE/LOSS_THRESHOLD — несколько последствий отказа, не три независимые причины.

Все50 atomic cases были запущены. Однако внутри failed recipes не стартовали16 подэтапов: udp-sweep5, udp-connections2, HTTP3 payload sweep2, stability7. Scheduler сохранял failed stage, пропускал дальнейшую нагрузку и выполнял recovery при наличии. Ноль пропущенных **cases** не равен полному выполнению всех внутренних вариантов. Исторические38PASS/12FAIL сохранены.

Product и local-origin cleanup=true, Start1/Stop1, force kill=false, capture complete. Новых driver installs/BCD/trust/system proxy/debugger/workloads/PR нет. Исправления сейчас не вносились.

## Свидетельства и следующий шаг

Ignored `artifacts/full50-review/`: evidence-summary.json (12cases, flow counts и SHA256 raw), frozen-proxy-gates.json, reproduce-frozen-proxy.py, udp-log-signatures.json, official-source.json (tag/commit/blob SHA), публичные reference C sources. Частные binding/secret/DPAPI/key/captures не коммитить. По3 исходным файлам frozen proxy/worker/DNS wire сверены manifest SHA, attempt и raw хеши сохранены. Подробные private original reports остаются в каталоге исходного attempt.

Следующий отдельный scope: исправление лабораторного proxy accounting и короткая проверка UDP→QUIC/смены QUIC-порта/нескольких соединений без перезапуска Core. Отдельно — решение о работе над продуктовым UDP ownership; WFP и старые kernel findings не подмешивать. Нельзя объявить исправленными7UDP или5QUIC без новых различающих проверок.
