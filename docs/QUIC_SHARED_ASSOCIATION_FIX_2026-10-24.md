# Исправление QUIC в общей UDP-ассоциации — preview.35

## Изменение

Source `eaf90ab`, ветка codex/development-functional-completion. Удалена привязка всей SOCKS UDP association к одному QUIC-порту/run/flow. Новый quic_proxy.py ведёт отдельные записи соединений по association, порту и QUIC Connection ID. Retry/handshake и выдача/отзыв серверных CID учитываются отдельно; обычный UDP/DNS может выполняться до и после QUIC. Payload не переписывается, TLS не терминируется прокси.

Origin по-прежнему проверяет подписанные application bytes и только затем закрепляет накопленные датаграммы за run/flow. Используется original_destination_connection_id pinned aioquic1.3.0, а не последний run всей association. Повторная/чужая identity, CID collision, malformed packet и превышение лимитов не принимаются. Fingerprint включает каждый аутентифицированный flow. Лимит записей равен max_connections, лимит активных aliases32 на направление/соединение; idle записи удаляются через30с, association close очищает все карты. Это выше QUIC idle_timeout5с; активные потоки обновляют timestamp. В endpoint contracts зафиксирована прежняя QUIC-v1/CID8 конфигурация. Миграция QUIC не добавлялась, остаётся NOT_TESTED. Нет заявления о покрытии любых существующих протоколов: сохраняется каталог51сценарий/10групп.

Клиент/драйвер не изменялись, очередь остаётся одной Core-сессией без per-case toggles. Gates подписей, сертификата, соответствия всех flows, route counters, ACK, idle и полного OFF не ослаблялись. Remote setup не расширялся. Старые saved suites, recipes и reports не переписаны.

## Проверка лабораторных компонентов

Ignored artifacts/quic-association-fix/component.py запускает только собственные loopback endpoints на ephemeral ports и отдельную аутентифицированную SOCKS association. Reference bridge объединяет четыре обычных worker socket в один SOCKS UDP endpoint и возвращает ответы по клиентским CID/flow/DNS id; это средство проверки лаборатории, не обход в продукте. Используются штатные worker/quic_client/application_client/origin, отдельный временный TLS certificate без установки доверия. Транспорт продукта не запускался в этой части.

**9 последовательных шагов ×4 потока PASS:** UDP → HTTP3 → HTTP3 multiplex → QUIC → QUIC multiplex → HTTP3 multiplex4096 → HTTP3 multiplex64 → DNS-UDP → UDP. HTTP3 multiplex512 покрыт третьим шагом. Все complete=true, штатный stage_route(stage,true)=true, proxy udp_sent точно равен сумме wire datagrams работников, все подписи/сертификат/содержимое/multiplex barrier проверены штатным кодом. SOCKS association ровно1 на всю последовательность; после закрытия maps пусты. Последний прогон~6с; result.json/component.log сохранены ignored.

Отдельные guards.py с настоящими QUIC Initial прошли: cap, malformed input, CID issue/retire, idle expiry, close cleanup. В существующий test_traffic_quic.py добавлен **один** необходимый regression test для нескольких аутентифицированных flows/ports в одной association, запрета чужой/повторной identity и отсутствия загрязнения прежнего UDP run. Все4целевых теста PASS. Синтаксис/diff проверены.

Общие protocol tests:69 выполнено,11skipped, без failures/errors. Общий discover test_traffic*.py:78tests,11skipped,6failures в прежних test_traffic_queue_guard. Отдельный запуск с queue_guard.py из неизменённого HEAD подтвердил те же6failures в9старых тестах; эта логика не менялась данным исправлением. Не выдавать общий suite за полностью зелёный. Логи tests.log/baseline.log/protocol-tests.log сохранены, эти не относящиеся к исправлению тесты не переписывались.

## Короткая проверка установленного ProxyBridge4.3

Пакет35 собран .NET publish, **1480SHA** matched, source eaf90ab. Controller34 штатно остановлен при idle;35 запущен admin/5178. Перед нагрузкой процессов WinDbg/kd/cdb нет. Через штатный local API запущена одна очередь: udp-connected,app-http3,app-quic-multiplex, всеSHORT/LOW. Выбранный пользователем полный набор не менялся. Оценка/фактическая длительность меньше5мин.

Attempt **20261024-062459-71e872599b264051b457da5efd3a697c**,06:25:02–06:25:36UTC (~34с), официальный WinDivert4.3.0. **3FAIL/0PASS**, без подмены успехом:

- UDP: proxy2259sent/2259received, работники0/0/5/563валидных ответов; у последнего1679invalid. Прежняя многопоточная проблема повторяется.
- HTTP3 после UDP: **один worker complete=true,600/600 verified transactions, TLS handshake/certificate=true**,633wire datagrams отправлены им/633учтены для этого authenticated flow в proxy. У других трёх timeout/termination. Origin подтверждает1application flow. До исправления лаборатории все4имели0ответов/0application flows.
- QUIC multiplex после смены порта: **один worker complete=true,600/600 transactions, TLS/certificate=true**,782wire datagrams/782proxy counter; остальные три handshake incomplete. Origin подтверждает1application flow. Старый лабораторный запрет порта устранён.

При продукте worker raw RX включает также посторонние QUIC datagrams от других соединений, тогда как proxy counters закреплены за authenticated CID. Такое отличие не маскируется. Картина1из4 соответствует установленному ранее WinDivert4.3 reply ownership механизму; данное исправление лаборатории не исправляет продукт. Успех каждого сценария требует всехflows, поэтому общий FAIL корректен. Граница: не проведён product A/B с исправленным relay; это не новая аттестация всех50/всего трафика ПК.

Start1/Stop1, cleanup_verified=true, local_origin_cleanup_verified=true, off_after.off_verified=true, known driver names absent=true, product processes0. Новых драйверных установок/BCD/signing/systemproxy/product PR нет. Приватные captures/bindings/секреты не коммитить; bounded product-summary.json ignored. Полный50/soak не повторялся. Следующий scope — запрос пользователя; оставшиеся отказы продукта отдельны от исправления лаборатории.
