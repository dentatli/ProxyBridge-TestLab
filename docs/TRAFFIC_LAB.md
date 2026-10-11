# Контролируемые проверки трафика

Срез разработки: 2026-10-11. Новый путь Testing → remote → «Трафик, скорость, нагрузка и стабильность» использует собственные `TrafficRuntimeService`, `Invoke-TrafficLabRun.ps1` и пакет `src/trafficlab`. Общие диагностические контроллеры и их подготовки не изменены. Старый remote launch API сохраняет свой `REMOTE_CONTROLLER_PENDING`; новый каталог запускается через `/api/v1/lab/traffic/*` с отдельным допуском.

## Каталог и условия

Все 34 пункта имеют отдельные галочки и SHORT/NORMAL/LONG, LOW/HIGH; доступны сохраняемые именованные наборы. Оценка показывается для каждого теста и всей очереди. Обычные этапы: 6/30/120 секунд нагрузки плюс подготовка, соединение и завершение. Это оценка, а не жёсткий срок всего задания.

SMTP/SMTPS, IMAP/IMAPS и MQTT/MQTTS — шесть независимых controlled profiles на TCP 42522–42527. Per-flow HMAC credentials, ordinary OS sockets и signed all-flow route/PID events обязательны. 4/16 connections LOW/HIGH, 512 bytes logical payload, 100/1000 предложенных transactions/sec/flow, одна транзакция одновременно на connection. TLS варианты проверяют CA/имя/leaf/ALPN и close_notify; cleartext варианты тоже проверяют signed proof. Сервер ограничивает connection до 150 секунд и command read до 5 секунд, message/literal/packet до 8 KiB; память не накапливает сообщения.

SMTP: EHLO/AUTH PLAIN/MAIL/RCPT/DATA/QUIT; фиксированный sender/recipient в `.invalid`, MIME base64, подписанный SHA-256 receipt в финальном 250. Приём происходит в памяти и не доставляет внешнюю почту; измеряется validated upload (RX logical payload=0). SMTP AUTH credentials — только TestLab token; STARTTLS, retry delivery, external mail servers не реализованы. IMAP4rev1: AUTHENTICATE PLAIN, virtual INBOX, APPEND, FETCH BODY.PEEK[], exact mail bytes, подписанный receipt в tagged OK, STORE Deleted/EXPUNGE/LOGOUT; максимум одна текущая запись per connection. Сторонние mailboxes/UID/search/persistence и скорость диска не заявлены. MQTT 3.1.1: clean session, bounded CONNECT, единственный result subscription QoS1, signed publish/request/result, проверка PUBACK в обе стороны, PINGREQ/PINGRESP перед DISCONNECT. Wildcards, retain, QoS0/2, persistent sessions, MQTT5 и arbitrary brokers не реализованы; DUP/replay в этом профиле приводит к FAIL вместо имитации retry.

Приёмка почты/MQTT 2026-10-11: 12 component cases direct/explicit SOCKS5 по 12 транзакций, 15 negative auth/pin/replay/cancel-after-exchange, стандартные Python SMTP/IMAP и Paho MQTT 2.1.0 interop. Первый MQTTS close дал SSLEOFError и остался FAIL; исправление protocol drain/TLS close прошло повторную приёмку. Native SMTP SDK выявил case-sensitive verbs, исправлено. .NET 0 errors/warnings, 21 unit tests, GUI RU/EN/selection и console errors=[]; signed remote idle 0/0. Product не запускался, component PASS не является ProxyBridge PASS.

QUIC и HTTP/3 — два пункта по UDP 42520/42521, QUIC v1, TLS 1.3 с проверкой CA/имени/leaf pin и ALPN. QUIC использует подписанный JSON echo на отдельном bidirectional stream; HTTP/3 — POST `/testlab` с QPACK и JSON echo. Один outstanding request на connection, 4/16 connections LOW/HIGH, 512 bytes payload, 100/1000 предложенных requests/sec на flow. Измеряются verified logical bytes/transactions/RTT, handshake и UDP datagram counts; retransmission не объявляется logical request loss. Старые имена `tcp_*_bytes_per_second` в общей summary содержат validated payload goodput всех workload transports. Миграция, 0-RTT, datagram application extension и внешние серверы не проверяются. `close_verified` для QUIC означает local close timer; удалённый idle отдельно подтверждается signed stage metrics. SOCKS5 all-flow proof включает authenticated origin peer/fingerprint и полный счётчик wire datagrams, включая handshake/retransmission/close.

Приёмка QUIC/H3 2026-10-11: 4 component cases Windows→Ubuntu direct/explicit SOCKS5, сначала по 12, затем по 20 транзакций; 8 negative checks wrong pin/missing CA/wrong proof/cancel after first exchange. Signed final runtime/proxy idle 0/0. Дополнительно 20 прежних application component cases и 5 прежних negative checks. 17 unit tests, .NET 0 warnings/errors. Component PASS не подтверждает ProxyBridge; продукт в этом срезе не запускался.

| Проверка | Измерения и этапы |
| --- | --- |
| Три режима | OFF / UNRULED / SOCKS5 с одинаковыми условиями RTT; отдельный пункт |
| TCP RTT | Все образцы после прогрева; p50/p95/p99/mean/max; HIGH использует четыре потока вместо одного |
| Upload / download | Два независимых пункта; проверенные байты и фактический goodput |
| Duplex | Одновременная отправка и получение |
| Multistream | LOW: 1/2/4; HIGH: 1/4/16 потоков |
| Loaded RTT | Исходный RTT, duplex вместе с RTT, восстановление |
| TCP connections | Исходный этап, LOW 8/32/128 или HIGH 64/256/640, восстановление; фактический пик на получателе и отказы |
| Flow rate | Новые соединения с проверкой короткого обмена; предложено/завершено/отказы, темп и задержка connect+authentication |
| UDP connected / unconnected | Два независимых пункта; потери, RTT, дубли, перестановка, неверные ответы, ошибки отправки |
| UDP sweep | Payload 64/512/1400 байт × заданный и удвоенный темп |
| UDP flows | Исходный этап, ступени потоков, восстановление; уникальные наблюдённые потоки не объявляются точным пиком одновременных соединений |
| Mixed | TCP duplex, UDP и RTT одновременно, с исходным этапом и восстановлением |
| Stability | Исходный этап, восемь смешанных интервалов, восстановление |
| Soak | SHORT/NORMAL/LONG означают 24/48/72 часа смешанной нагрузки плюс исходный этап, восстановление и накладные расходы |
| DNS TCP / UDP | Два отдельных пункта: контролируемый A-ответ, подписанное свидетельство в TXT, задержка; UDP — проверенные ответы и потери |
| TLS | Цепочка/имя сертификата, leaf SHA-256, SNI, ALPN, версия/cipher, обмен и close_notify |
| HTTP / HTTPS | Два отдельных пункта: HTTP/1.1 POST, keep-alive, полная проверка echo; HTTPS дополнительно проверяет TLS |
| WebSocket | HTTP upgrade, Sec-WebSocket-Accept, masked client binary messages, проверка echo и close 1000 |
| SSH | SSHv2, закреплённый Ed25519 host key, per-run password proof, exec-канал testlab-echo, данные и exit status 0 |
| SFTP | SSH host key/auth, SFTP v3: bounded write/close/stat/read, полная проверка данных и подписанного ответа |
| HTTP/2 | TLS chain/name/pin, ALPN h2, HPACK/SETTINGS/flow control, последовательные POST streams на одном соединении, GOAWAY и TLS close_notify |
| gRPC | TLS/ALPN h2, protobuf Envelope, unary Echo/Exchange, length-prefixed message и обязательный grpc-status=0 в trailers |

LOW/HIGH обычно дают 4/16 потоков, 100/1000 UDP datagrams/s на поток и 2/8 работников создания TCP-соединений. UDP tempo является предложенным темпом; отчёт содержит фактически достигнутый. Размер datagram включает дополнительные служебные данные сверх payload. Потери определяются отсутствием проверенного ответа в пределах двух секунд; порог успешности — не более 1% для каждого потока. Отказы сохраняются, а не превращаются в прежний успех.

Часы payload/RTT используют `perf_counter`/`perf_counter_ns`, включая Windows Python 3.11. Процентили объединяют гистограммы всех образцов, а не усредняют p99 разных потоков. Верхние границы логарифмических корзин имеют шаг 1%; прогрев исключён. Соединения и наблюдённый goodput не доказывают абсолютную ёмкость, переполнение внутренних таблиц или предел скорости канала. Flow rate включает короткий обмен, поэтому это не изолированный максимум установления TCP.

## Получатель и свидетельства

Проверенный целевой выпуск — Ubuntu 22.04, IPv4, systemd, Python 3.10. IPv6 и приёмка 24.04/26.04 отложены. Собственная служба `proxybridge-testlab-traffic.service` работает от `proxybridge-testlab`, из неизменяемого каталога `/opt/proxybridge-testlab-traffic/versions/<bundle>`. Старый сервер с 18 plugins не изменяется и не обязателен для этого runtime. Свежий wizard check должен доказать SSH, host trust и платформу (READY либо PLAN_READY); REPAIR_REQUIRED блокирует работу. PLAN_READY не означает готовность старого endpoint. Собственная служба отдельно требует проверенной установки и обмена.

TCP/UDP origin — 42501; SOCKS5 — TCP/UDP 42502 с отдельными UDP associations; подписанный metrics control — TCP 42503. Конфликты портов блокируют apply. В unit задана IP policy для localhost и SSH source IP; имеющийся активный ufw не расширяется автоматически. Чужая служба не заменяется. Apply проверяет платформу, файлы, конфигурацию, manifest, main process и listeners; предыдущая версия сохраняется для rollback. План одноразовый, привязан к узлу/ключу/файлам, действителен десять минут; перед запуском выполняется свежая проверка.

Прикладные origins: HTTP 42511/TCP, TLS 42512/TCP, HTTPS 42513/TCP, WebSocket 42514/TCP, DNS 42515/TCP+UDP. Продуктовое правило выбирает порт конкретного сценария; control 42503 исключён. На каждой версии создаётся отдельный CA/сертификат `traffic.testlab.invalid`; приватный CA-ключ после выпуска удаляется, leaf key остаётся только в защищённом каталоге службы. Системные trust stores не изменяются. Manifest включает PKI hashes; подписанный control публикует только CA/leaf fingerprint. После OFF control fingerprint фиксируется в условиях задания, смена сертификата отзывает допуск.

Новые TCP origins: SSH 42516, SFTP 42517, HTTP/2 42518, gRPC 42519. Отдельный Ed25519 host key создаётся внутри версии службы; public key/fingerprint опубликованы подписанным control, fingerprint фиксируется после OFF и повторно проверяется при восстановлении очереди. Административный SSH на порту 22 и его ключи/known_hosts не меняются. Ни CLI, ни библиотека не принимают неизвестный host key автоматически.

Библиотеки нового runtime поставляются отдельным `vendor/traffic-wheelhouse` и `traffic-dependencies.lock.json`, с точными размером/SHA-256 и лицензиями. Установка и тесты не обращаются к package index. Сервер использует versioned dependencies и manifest hashes; Windows — собственный cache по хэшу lock. Архивы проверяются перед использованием, извлечённые файлы повторно проверяются; локальная идентичность задания включает Windows lock/wheels. Старый protocol wheelhouse/lock сохранён: его exact-set gate нельзя расширять новыми файлами. Native DLL в Windows остаются в собственном cache, без глобальной pip-установки.

Private configuration передаётся через SSH stdin, а не argv; ключ обмена хранится на Windows под DPAPI в отдельной конфигурации remote wizard. Private jobs/profile имеют пользовательский ACL и удаляются после работы. SSH private key, пароли и private captures в Git не включаются.

TCP: nonce challenge, HMAC-SHA256 клиента/получателя, проверка offsets, всех байтов и SHA-256 двух направлений, сверка подписанных счётчиков. UDP: подписанные сообщения/ответы, sequence, payload и наблюдённый peer. Control port исключён из продуктового правила. Manifest и текущие hashes проверяются также при подписанном опросе metrics; подмена файлов отзывает допуск.

Реальные работники используют обычные OS sockets. Явный `test_proxy` существует только для проверок компонентов и не является свидетельством работы ProxyBridge. SOCKS5 route требует сверки всех TCP/UDP flow counts и aggregate fingerprints origin/proxy, включая потоки вне ограниченных samples, а также продуктового route event для PID работника. Совпадение агрегатов не подменяет продуктовый допуск.

## Прикладной профиль и пределы

Native DNS/ClientHello/HTTP/upgrade идут с первого байта; служебного TCP preface перед ними нет. HMAC внутри прикладного запроса/ответа связывает run, flow, sequence, payload digest и peer получателя. Повтор sequence либо смена peer/identity отвергается. Подписанные all-flow counters используются и для TLS: proxy связывает исходящий сокет с authenticated origin flow, не расшифровывает relay.

Базовые шесть сценариев проверяют собственные ограниченные endpoints, а не совместимость со всеми сторонними серверами или полное соответствие стандартам. DNS использует обычное wire framing, A `192.0.2.10` и дополнительный TXT proof в answer; это не рекурсивный resolver, DNSSEC, DoT или DoH. HTTP/1.1 использует Content-Length и POST; chunked/compression/redirects отсутствуют. TLS допускает 1.2+, проверяет цепочку/имя и leaf pin; ALPN — `testlab/1` либо `http/1.1`. WebSocket ограничен binary FIN frames и проверенным close; fragmentation/extensions/WSS пока отсутствуют. Форматы: [DNS RFC 1035](https://www.rfc-editor.org/rfc/rfc1035), [WebSocket RFC 6455](https://www.rfc-editor.org/rfc/rfc6455).

LOW/HIGH дают 4/16 потоков и предложенный темп 100/1000 транзакций в секунду на поток. У каждого потока один запрос ожидает ответ; фактический темп ограничен RTT. TCP echo payload — 512 байт, проверяется полностью. Goodput считает проверенные payload bytes, исключая JSON/base64/TLS/framing; DNS не получает выдуманную payload-скорость. TLS terminal echo/close_notify проверяется отдельно и исключается из количества измеренных транзакций, payload goodput и RTT. Серверные counters включают terminal echo. В истории доступны verified transaction count, TLS evidence и числовые errno/winerror; счётчик транзакций выбирается в сравнении. Отмена во время обмена сохраняет incomplete, даже если часть ответов успела пройти.

## Фактическая приёмка 2026-10-11

### SSH/SFTP, HTTP/2 и gRPC

SSH допускает только testlab-echo; OS shell/команды, PTY, forwarding и доступ к ssh-agent запрещены. SFTP обслуживает только /request и /response в памяти, с лимитами объектов/размера; произвольные пути и прежний ответ после неудачной записи отвергаются. Это проверка протокола и целостности controlled objects, а не производительности диска Ubuntu. SSH/SFTP latency включает полный обмен; connection/auth latency записана отдельно.

HTTP/2 проверяет повторные последовательные streams; multiplexing нескольких outstanding streams на одном TCP пока не испытывается. gRPC — один uncompressed protobuf Envelope на unary RPC, контракт [traffic-echo.proto](../config/traffic-echo.proto); streaming RPC, compression, retry/deadline metadata и произвольные сервисы не заявляются. Требуется статус в trailers, отсутствие/ненулевой статус, reset, обрезанный либо лишний frame не дают PASS. Основы реализации: [AsyncSSH API](https://asyncssh.readthedocs.io/en/latest/api.html), [hyper-h2 API](https://python-hyper.org/projects/hyper-h2/en/stable/api.html), [официальный gRPC HTTP/2 protocol](https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md).

Проверены 8 новых component cases Windows → установленная Ubuntu, direct/explicit SOCKS5, по 20 проверенных транзакций; signed all-flow route reconciliation успешна. Дополнительно 12 прежних application component cases и 5 прежних отрицательных проверок прошли. Новые 14 отрицательных проверок включают неверные SSH key/auth, TLS pin, frozen SSH identity, OS exec/forwarding, три запрещённых SFTP пути, replay/stale response и отмену SSH/gRPC во время обмена. Отдельный официальный grpcio 1.84.0 подтвердил совместимость unary endpoint; SDK установлен только в ignored testing directory. Это компонентная приёмка без продуктового PASS.

14 unit tests (9 queue guards + 5 protocol/dependency boundaries) прошли без продукта/сети. .NET build: 0 warnings/errors. GUI RU/EN показывает 26 пунктов, новая собственная временная suite сохраняет/восстанавливает четыре сценария и разные длительность/нагрузку после refresh/apply. Runtime bundle `4a264c7051d313c593a5c3986bc0551202cb2074cb4963fbf7d05f2f2844fad1` READY на Ubuntu .180; 12 TCP/3 UDP listeners и source/dependency/PKI hashes проверены.

Реальная SHORT/LOW очередь четырёх новых cases с безопасным продолжением: `20261011-142619-1d8874adccfb4536b6e16b11babf320c`, оценка 164 секунды, около 54 секунд с подготовкой. Четыре попытки, skipped=0, три recovery_checks VERIFIED. Каждый OFF/UNRULED control успешен, CLI READY, capture/cleanup=true, child exit=0, forced_stop=false; SSH fingerprint зафиксирован в условиях и передан в recovery. Все SOCKS5 measurements имеют stages=0: SSH/SFTP ConnectionAbortedError, HTTP/2/gRPC ConnectionResetError:TRAFFIC_SCHEDULE_FAILED на control exchange. Итог FAILED/TRANSPORT_INCOMPLETE/ROUTE_UNVERIFIED, успешных продуктовых прикладных измерений нет. Driver Stopped, product processes=0, execution inactive; отдельный подписанный post-health подтвердил тот же bundle/TLS/SSH key и origin/proxy connections=0. Продуктовый дефект не исследовался.

- Новый выделенный сервер пользователя `192.168.0.180`, root/22: Ubuntu 22.04.5/Python 3.10.12/OpenSSL 3.0.2. Собственные wizard settings/trust/runtime настроены; старый 18-plugin endpoint на нём не установлен и не объявляется READY. Прежние диагностические ключи/known_hosts/копия/комплекты не изменены.
- .NET: 0 warnings/errors; Python AST 16 файлов и `node --check` прошли. GUI RU/EN показывает 22 пункта; собственная временная suite восстанавливает шесть новых сценариев и разные параметры после refresh, затем удалена через API. Карточки и сравнение используют обычные компактные checkbox; выбранные карточки выделены. Сохранённые продуктовые FAIL/CANCELLED видны, browser console без ошибок.
- Ubuntu: 16 облегчённых component cases (шесть прикладных + TCP RTT/UDP connected, direct/explicit SOCKS5), полные ответы и route reconciliation проверены. Windows → установленный Ubuntu runtime: 12/12 новых component cases, по два потока и 20 проверенных транзакций. Это короткие профили 0.2/0.25 s, не HIGH/длительная приёмка и не продуктовый PASS.
- 12 отрицательных проверок: неверный leaf pin, отсутствующий CA, недоверенная CA chain, неправильное TLS-имя, неверные прикладная/DNS подписи, повтор HTTP transaction, JSON неправильного типа, обрезанный DNS name, unmasked/64-bit-length WebSocket client frame и cancel during HTTP exchange. Отказы подтверждены; свежий signed control остаётся доступен.
- Первичная проверка TLS выявила непроверенное завершение: EOF при unwrap. Исправлен authenticated terminal echo и close_notify; TLS/HTTPS теперь требуют завершения. После финальной правки повреждённых запросов, WebSocket bounds и HTTPS close повторены Windows 12/12 и все 12 отрицательных проверок.
- Финальный runtime bundle `0a86b630b75c488611b6e2dddb44a7bd528e984f3a4e0821e18a23cc55434b8c`: READY, hashes/active/enabled/main process/listeners проверены. Автотесты кода не добавлялись. Эта компонентная приёмка выполнялась без запуска ProxyBridge/драйвера; служба продукта оставалась Stopped, системный прокси/BCD/WinDbg не менялись. Компонентные отчёты остаются вне пользовательской продуктовой истории и Git.

## Реальная продуктовая попытка 2026-10-11, 17:06 +05:00

По отдельному запросу пользователя и после свежего подтверждения «WinDbg закрыт» запущен SHORT/LOW набор шести новых сценариев, оценка 156 секунд. Сборка «актуал»: bundle `a677580820ee370bef9aad59e3de6cf9eb7d5c672ccf9ec4c9b112753983ab2c`. Попытка `20261011-120624-387770ba5b664114b9ef5d2ee778d55a` сохранена в пользовательской истории.

OFF и UNRULED controls complete/route verified, ProxyBridge CLI достиг READY. В SOCKS5 подписанный control exchange дал `ConnectionAbortedError:TRAFFIC_SCHEDULE_FAILED` до первого прикладного этапа (stages=0); это не доказательство ошибки DNS payload. Первый case `app-dns-tcp` получил FAIL с TRANSPORT_INCOMPLETE/ROUTE_UNVERIFIED. Остальные пять SKIPPED_AFTER_FAILURE; TLS/HTTP/HTTPS/WebSocket и DNS UDP в этой очереди реально не измерены. Итог FAILED виден в GUI/сравнении, отсутствующие показатели показаны как недоступные.

CLI штатно завершён (child exit 0, forced stop=false, capture complete=true), own service restoration и OFF after verified: service Stopped, product processes=0, active=false, cleanup=true. Подписанный control после очистки снова доступен, bundle и сертификат прежние. Продуктовый отказ не расследовался; драйвер не переустанавливался, system proxy/BCD/signing/WinDbg/диагностическая копия/комплекты не менялись. Отчёты и GUI screenshot сохранены локально вне Git. Повторять тот же failing набор без нового основания не требуется.

## Жизненный цикл

Перед каждым тестом проверяются неизменяемые файлы продукта, Python, исполнители и загруженная сборка UI. OFF и UNRULED имеют собственные короткие проверки обмена; они не заменяют измерение выбранного режима. Console host идентифицирует свой CLI, проверяет путь/creation identity, ждёт фактический READY, закрывается штатным Ctrl+C и сохраняет bounded capture/hash/counts. Forced stop или неизвестная очистка блокируют очередь.

Пользователь отдельно разрешил восстановление `ProxyBridgeDrv` в Stopped после нашего запуска. Автоматическая остановка допустима только с private ownership witness: до запуска был доказан OFF, файлы/SCM path совпадают, собственный CLI был READY и штатно завершился, продуктовых процессов нет и отсутствуют другие известные interception drivers. Установка/файлы драйвера, BCD, trust/signing, system proxy и WinDbg не меняются. OFF gate проверяет SCM/file identity, известные WFP objects и loaded-driver names; **hash фактически загруженного kernel image не доказан**, это явно сохранено в scope.

По умолчанию ошибка прекращает очередь; оставшиеся пункты получают SKIPPED_AFTER_FAILURE. Дополнительная галочка разрешает продолжение после ошибки транспорта, маршрута или порога UDP loss только при успешных OFF/UNRULED controls, достигнутом CLI READY, полном capture, штатном закрытии без forced stop и подтверждённой очистке предыдущего теста. Перед следующим пунктом контроллер заново проверяет OFF, подписанные bundle/leaf identity и нулевые счётчики всех оставшихся origin/proxy соединений. Отсутствующие счётчики не считаются нулём. Файлы повторно сверяются до/после проверки восстановления и перед каждым следующим тестом; его controls выполняются заново.

Отмена, неизвестная ошибка, потеря связи, смена файлов/сертификата, занятый origin или неподтверждённая очистка блокируют продолжение. Автоматического retry/resume нет. Неудачный case остаётся FAIL, весь набор остаётся FAILED даже при успехе следующих пунктов. Политика и отдельные recovery_checks сохраняются в истории и показаны в RU/EN. Оценка добавляет по 20 секунд на возможный переход после ошибки; это накладная оценка, а не жёсткий timeout.

Stop создаёт cancel marker; shutdown также просит отмену, ожидает исполнителя и очистку. Набор ожидаемой длительности более пяти минут требует отдельного флажка пользователя; длительные проверки автоматически не выполнялись. После перезапуска незавершённая история не объявляется успешной.

## Приёмка безопасного продолжения — 2026-10-11

Unit tests защитных условий: 9/9, без продукта и сети. Отказ OFF, потеря связи/identity, занятый origin/proxy, отсутствующие счётчики, unsafe cleanup/capture/forced stop и отмена запрещают переход. Отдельная компонентная проверка Windows → Ubuntu подтвердила подписанные глобальные счётчики: удержанный direct flow дал runtime=1/proxy=0, explicit SOCKS5 flow — 1/1; после штатного завершения оба дали 0/0. Это не продуктовый PASS.

Реальная очередь `20261011-123248-3e85b9c917cb4aa4b3f1527177f8b6c7`: шесть application cases SHORT/LOW с continue_after_failure=true, оценка 256 секунд, фактически около 74 секунд с подготовкой. Шесть попыток выполнены, skipped=0; пять recovery_checks имеют fresh OFF, signed identity, idle=true и TRAFFIC_RECOVERY_VERIFIED. OFF/UNRULED controls каждого case успешны; каждый CLI READY, child exit=0, capture полный, forced_stop=false, cleanup=true. Итог FAILED/TRAFFIC_CASE_FAILED: DNS TCP получил ConnectionResetError, остальные пять — ConnectionAbortedError:TRAFFIC_SCHEDULE_FAILED на control exchange; все SOCKS5 measurements имеют stages=0. Успешных прикладных измерений продукта нет, его причина не исследовалась.

Runtime bundle `eaba1db569a54393021dbf4becf136b08faa3a5f2e91f117c3d3f0b518d87399` установлен и проверен на .180. После очереди driver Stopped, product processes=0, execution inactive. .NET build: 0 warnings/errors; Python/PowerShell AST и JS syntax прошли. GUI RU/EN показывает default-off галочку и пять разрешённых переходов в истории; refresh возвращает галочку в исходное состояние, console errors отсутствуют. Raw report и `artifacts/development-remote-wizard/queue-recovery-final.png` игнорируются Git. HIGH/long/cancel-during-product-load и реальные опасные отказы инфраструктуры не проверялись.

## Ресурсы и история

Отдельно измеряются worker, идентифицированный product CLI, процесс Ubuntu origin/proxy, вся Windows и вся Ubuntu. CPU процессов нормирован на все логические CPU соответствующей машины. Windows process memory включает working set и private committed bytes; Linux — RSS/anonymous RSS. Память ОС: Windows physical total/available/used; Linux MemTotal/MemAvailable. Whole-OS counters включают фон и не приписываются драйверу. PID reuse/смена image path и недоступные counters фиксируются, отсутствующие значения не заменяются нулём.

Агрегаты используют все наблюдения; timeline ограничен 4096 точками с decimation. Soak пишет полные этапы один раз в собственный append-only JSONL с flush/fsync и SHA-256, оставляя в основной истории компактные этапы и streaming totals. Route проверяется для каждого этапа до удаления его полного объекта из памяти; journal digest и число records привязаны к отчёту. Это не Resume. При отказе обмена, несовпадении маршрута либо потерях UDP выше 1% дальнейшие нагрузочные этапы пропускаются; предусмотренный recovery выполняется и сохраняется. Число пропущенных этапов и причина остановки нагрузки входят в отчёт.

История имеет paging. Сравнение выбирает последнюю попытку сборки/теста/условий, учитывает ошибки/отмены и позволяет выбрать сборки/показатели. Условия включают endpoint binding, remote bundle, локальный runtime (включая UI assembly/Python/helpers), версии ОС/Python, CPU model/count и RAM. Неизвестные условия новой попытки блокируют fallback к прежнему успеху. Одинаковые записанные условия не гарантируют одинаковый фон/канал; сводный goodput включает исходный этап, нагрузку и восстановление. Неподтверждённый route не публикуется как успешный benchmark.

## Фактическая приёмка 2026-10-09

- .NET build: 0 warnings/0 errors; Python AST, PowerShell AST и JS syntax проверены.
- 30 коротких проверок компонентов на Ubuntu: 15 рецептов напрямую и через явный SOCKS5. Это облегчённый профиль (0.15 s, небольшие connection steps), а не доказательство HIGH/24h или работы драйвера.
- Две короткие симуляции soak journal: direct/SOCKS5, по десять этапов; records/digest, compact summaries, all-sample totals и route reconciliation проверены. **24/48/72 часа не выполнялись.**
- Пять дополнительных коротких проверок остановки нагрузки: transport/route failure → 8 пропущенных интервалов + recovery; успешные direct/SOCKS5 → 10 этапов; compact journal digest/count проверены.
- Signed identity/exchange, отказ при подмене source, неверных origin/proxy keys, cancellation и disconnected origin проверены; временные агенты остановлены.
- Реальные Windows OFF/UNRULED TCP controls прошли. SOCKS5 TCP дал ConnectionResetError; SOCKS5 UDP — UDP_TRANSPORT_FAILED/потери/неподтверждённый route. Очередь сохранила FAIL и пропустила следующий тест. Причина продукта не исследовалась.
- После реальных попыток service Stopped, no known WFP objects/loaded driver names и отсутствие продуктовых процессов подтверждены в gates. Первый прогон обнаружил оставшийся Running service; с отдельного разрешения выполнена own restoration. Старые failed reports сохранены.
- Cancel во время PREPARING: CANCELLED, оба пункта skipped, cleanup verified, без запуска продукта. CSRF 403; invalid case/debugger/long-run gates 400.
- GUI RU/EN, полный каталог, разные параметры, save/apply/delete собственной временной suite, refresh и сохранённые реальные ошибки проверены. Private данные и диагностическая копия не изменены.

Остались: успешная приёмка реального SOCKS5 на работоспособной сборке продукта, HIGH/длинные наборы с отдельным разрешением, реальная отмена продуктового задания во время нагрузки, v4.0.0/reboot adapter, остальные прикладные семейства (HTTP/3/QUIC, mail/messaging и другие), расширение текущих controlled profiles и приёмка port-conflict/rollback/смены административного SSH host key. HTTP CONNECT отложен пользователем. Продуктовый TCP дефект ведётся отдельным чатом.
