# WFP full50: разделение ошибок продукта и лаборатории

Прогон `20261024-103903-840806ad7ea9436b9b94a19e533b0c72`, 24 октября15:39–16:15 Екатеринбург, preview40/source6cde00e: **35 PASS /15 FAIL**. Все50 case reports записаны. Product cleanup и local-origin cleanup=true, каждый case cleanup=true, Core Start1/Stop1, child exit0. Это штатно завершившийся прогон с функциональными отказами, а не повтор прежней ошибки завершения. Комплект: Core/CLI b359627, сохранённый baseline SYS SHA3e5c3c709ee8c8800628f04b5550f3a82377deb264b045ab2f2ccbab3fd8fb4c; SYS не пересобирался из нового commit.

Разбор только сохранённых свидетельств и исходников. Новых сетевых/драйверных/WinDbg запусков, изменения продукта или лаборатории не было. SHA5 релевантных файлов immutable40 (proxy/quic_client/worker/ssh_client/Core host) соответствует manifest. Raw исходники отчётов не изменялись. Сводки и декодированный capture — ignored `artifacts/wfp-full50-review` в development worktree.

| Сценарии | Количество | Отнесение и уверенность |
|---|---:|---|
| UDP connected, размеры/темп, соединения UDP, mixed, stability |5|Продуктовый UDP-путь; наиболее вероятен уже подтверждённый wildcard/endpoint lookup драйвера. В новом прогоне отдельный IOCTL опыт не проводился.|
| UDP unconnected, DNS UDP |2|Продукт, Core UDP return/demultiplexing; сильные свидетельства неверной обратной доставки.|
| SSH, SFTP |2|Продуктовый путь получения исходного TCP destination, граница driver/Core. Неверные порты подтверждены capture; отдельно виновность конкретного SYS/Core не разделена.|
| HTTP3×3, QUIC×2 |5|Вероятен продуктовый UDP-путь: ответ приходит с неожиданного source endpoint. Точный sender не записан, причинная атрибуция предварительная.|
| Частота новых TCP-соединений |1|Недостаточно данных:1 отказ из747 попыток, конкретная ошибка потеряна из-за ограничения диагностических samples лаборатории.|

## UDP: наблюдения и механизм

`udp-connected`:11488 отправлено/0 подтверждено, origin0/proxy0. В sweep и single-flow baseline/recovery udp-connections также0 у origin. Mixed/stability сохраняют успешную TCP-часть (5 flows), но их UDP-часть не проходит. UNRULED контроль этих сценариев — TCP, он не является независимым UDP control; новый прогон сам по себе не доказывает точную kernel-функцию отказа.

Тот же SYS ранее проверен driver-only: wildcard/concrete mismatch и потеря назначения установлены отдельно. См. существующие документы основного checkout: [UDP cause](C:/src/ProxyBridge-TestLab/docs/UDP_FLOW_IDENTITY_ROOT_CAUSE_2026-10-22.md), [локальная матрица](C:/src/ProxyBridge-TestLab/docs/UDP_LOCAL_MATRIX_CURRENT_DRIVER_2026-10-22.md). Это подтверждённая прежняя причина на том же бинарнике, согласующаяся с текущими симптомами, а не новый воспроизведённый IOCTL trial.

`udp-unconnected`:11496 sent; origin11496/proxy received11496/sent11496; worker received3468, invalid8028. Per-flow accepted749/953/867/899 и invalid1788/2267/2000/1973. Все ответы физически вернулись, но не подтверждены нужными клиентами. В Core b359627 `Windows/src/relay/pb_relay_udp.c:314` reply выбирает наиболее активного клиента по одному исходному remote ip:port; затем sendto идёт от локального relay socket. Это сохраняющийся дефект ownership/endpoint transparency Core, не повод ослаблять проверку идентичности лаборатории. Raw invalid объединяет MAC/flow/payload ошибки: утверждать отдельный вид каждого invalid нельзя.

DNS UDP: origin обработал4 запроса, proxy получил/отправил4 ответа. У клиентов3 timeout и1 APPLICATION_DNS_SOURCE_INVALID. Какой именно sender был получен, raw не хранит. Потеря корректного обратного адреса/владельца в продукте согласуется с результатом; лабораторный DNS server не выглядит источником потери запросов.

## SSH/SFTP: неверное назначение до протокола

Каталог и worker задают SSH42516/SFTP42517 (`application_wire.py:11`). Worker PID10916/14684 подтверждены raw. В том же capture:

```
[RELAY] accepted redirect: pid=10916 dest=127.0.0.1:51192 action=1 cfg=0
SOCKS5: CONNECT failed (reply=2)
[RELAY] accepted redirect: pid=14684 dest=127.0.0.1:52123 action=1 cfg=0
SOCKS5: CONNECT failed (reply=2)
```

Всего8 таких отказов, по4 на worker. Дополнительные назначения51194/51195 и52121/52120 тоже не являются портами SSH/SFTP стенда. Core b359627 получает orig_dest через pb_driver_orig_dest и использует его в SOCKS CONNECT (`pb_relay_tcp.c:39,59,367`). Allowlist лаборатории закономерно отклоняет посторонний destination кодом2 (`proxy.py:149`). Расширять allowlist до ephemeral-портов нельзя: это скрывает искажённое назначение. Данный capture локализует дефект до SSH-протокола на границе driver/Core; точный kernel/API механизм без отдельного разбора не объявляется установленным.

Оба worker завершены deadline45сек (NORMAL30+15), очередь продолжилась, последующие сценарии прошли. Это исправно работающая защита40; тайм-аут не является самостоятельным доказательством SSH-ошибки драйвера, таким свидетельством здесь выступают неверные destination в capture.

## QUIC/HTTP3 и предел доказательств

Все20 flows пяти сценариев завершаются APPLICATION_QUIC_DATAGRAM_SOURCE_INVALID до подтверждённого QUIC handshake. Initial datagrams действительно отправлены (например HTTP3:2/4/3/2), получен неожиданный UDP sender; поэтому counters quic_datagrams_received остаются0 — счётчик увеличивается после source gate. Это не доказательство отсутствия вообще любых пришедших datagrams. Сравнение source с исходным destination (`quic_client.py:73`) необходимо для прозрачности; прежний лабораторный запрет UDP→QUIC в общей association в40 уже устранён. Нельзя автоматически перенести заключение о дефекте лаборатории из старой preview18.

Core отправляет ответы из relay UDP socket, что согласуется с endpoint mismatch и DNS отказом. Но unexpected sender не сохранён: нельзя доказать, что каждый QUIC отказ вызван именно этим портом, а не другим посторонним/запоздавшим пакетом.5 отказов остаются предварительно отнесёнными к продукту; TLS/HTTP3 после устранения UDP-препятствия ещё не аттестованы.

## Подтверждённые недостатки лаборатории

Доказанных ложных FAIL в этом прогоне не найдено. Найдены недостатки диагностических данных:

- Flow-rate:747 offered,746 complete,1 failure; baseline/recovery PASS, proxy746 finished/0 errors. У неуспешного churn-worker296 successes/1 failure, второй450/0. `worker.flow_churn` хранит только первые64 route_samples каждого worker; все128 samples успешны, сам failed sample не сохранён. Поэтому underlying отказ нельзя честно отнести ни к драйверу, ни к стенду. Нужно сохранять хотя бы первый failed result независимо от sample cap.
- QUIC/DNS source checks не сохраняют expected/actual endpoint и фазу при отказе. Нужна эта компактная ошибка, а не отключение проверки.
- UDP invalid не разделён по причине; общий счётчик не доказывает конкретный MAC/flow/payload mismatch каждого пакета.

Это предложения для следующего исправления лаборатории, не внесённые изменения. По запросу выполнен анализ.

## Ограничения охвата

После первых отказов внутренние нагрузки безопасно пропускались: sweep5, udp-connections3, HTTP3 payload2, stability7 — всего17 sub-stages не стартовали.50 итоговых сценариев не означают полного выполнения всех их внутренних сочетаний. Прогон локальный IPv4 loopback, без24h soak; он не аттестует весь внешний трафик ПК/IPv6. До установления работоспособности сравнение производительности отказавших сценариев некорректно. WinDivert на той же40 ещё не проверялся.
