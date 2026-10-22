# UDP: фактическое сравнение до/после на физическом PB-SUT

## Результат и границы

Новый UDP packet channel исправил проверенные ошибки адреса и владельца ответа.
Штатный TestLab подтвердил **13 536/13 536** корректных ответов через новый Core:
3×512 одним потоком, 3×2000 двумя потоками к одному origin, 3×2000 двумя потоками
к двум origin. Ещё 13 536 пакетов прошли соответствующие OFF controls.
Во всех этих сериях CPU/RAM coverage=OBSERVED, route/payload/source gates
подтверждены, helpers/CLI завершились штатно, driver выгружен. Короткие gate
на 64 пакета в это число не включены.

Это локальные IPv4 SOCKS5 echo-проверки с паузой 20 ms после ответа, 512-byte
payload и одним запросом в полёте на поток. Это не максимум throughput и не
подтверждение многочасовой стабильности, всех приложений, remote path или HLK.
Дополнительная диагностическая матрица и повторная проверка окончательного
пакета 1.1.0.0 также прошли (ниже). Локальные UDP gates пройдены; глобальная
готовность продукта не заявляется из-за отдельного TCP дефекта и границ проверок.

Затем финальный штатный CLI прошёл ещё 3×512 UDP-ответов и OFF controls:
**всего TestLab15 072/15 072 корректных PROXY-ответа**, плюс столько же OFF.
Последние 1536 относятся к final SYS1.1.0.0 и настоящему upstream CLI, без
лабораторной модификации executable. Подробнее — отдельный gate ниже.

## Комплекты и одинаковые инструменты

- До: product source `b3596272a8dc8898790b016d1e4c488c2fdc917d`, Core SHA256
  `37c1575ee688d5de0227b89b9c26257f1364828f4f6a44235ae6676ae8466b83`,
  SYS `3e5c3c709ee8c8800628f04b5550f3a82377deb264b045ab2f2ccbab3fd8fb4c`.
- После: source `959ec92a06dd9361a7ce050cc82e2a303a9c4006`, Core
  `7a02e79b4cbb5bae55c3323fe1984c8468622d0f6bbfdcdf766dac992c070104`,
  SYS `482940c023d2e4f763d298abc8ffb032f8fb9819a9ebb541b6d82d54525310c3`.
- Финальный package source `4bba75848908ebfbe7a9c2d23ddb8241533811da`, версия
  **1.1.0.0**, signed SYS
  `c1ab41935cc96afea18cdd6aec7916038d1683d1e45fce6dfefe8b1902607a6b`.
  Core тот же. Изменены INF/PE version и description; executable sections
  `.text`, `fothk`, `INIT` побайтно идентичны benchmark SYS. Поведение пакета
  заново проверено, длинные серии относятся к указанному benchmark hash.
- Один и тот же instrumented TestLab CLI
  `ad83b3aad22252be0ab20a6c26470f7c364930af35089e9904f1dd0d29bb40ca` и
  native client `d6973b8976418faf5633b457deacbdb1e340f43be3317be40b68d8da6d123d8c`.
  Отличия CLI и проверенные receipts описаны в [журнале](UDP_LOOPBACK_AND_TESTLAB_2026-10-22.md).
- Lab commit `74aab347585240d8208d1e9ef99d4a47c0596495`. Профили, helpers,
  logging, streams, размеры, warmup и OFF/PROXY порядок чередуются одинаково.
  Хеши файлов/driver service identity проверены; поле автоматического отчёта
  source_commit_verified остаётся false: сам runner не доказывает build provenance.

## Надёжность важнее сравнения скорости с дефектной версией

| Штатный сценарий | До | После |
|---|---|---|
| Один поток, 3×512 пакетов | Payload доставлен, **1536 ответов с неверного source endpoint** | **1536/1536 PASS**, исходный source |
| Два клиента, общий origin | Ответ stream2 доставлен stream1; второй клиент timeout, workload остановлен | **6000/6000 PASS**, смешивания/потерь нет |
| Два клиента, два origin | В этой серии не повторялось | **6000/6000 PASS** |
| TCP PROXY smoke | PASS | PASS |
| TCP DIRECT smoke | **ROUTE_MISMATCH: реально через SOCKS5** | **Тот же ROUTE_MISMATCH** |

TCP DIRECT — существующий отдельный дефект, не регрессия UDP patch. В обоих
комплектах Core сообщает Direct, но receiver tuple и controlled-proxy log
подтверждают SOCKS5. `prepare_tcp_connection` оставляет cfg=0 для DIRECT, а
`connection_handler` не переносит action и запрашивает proxy config; lookup(0)
возвращает первый proxy. Этот код не менялся между b359627 и 959ec92.
Исправление TCP DIRECT в этой UDP работе пока не выполнено. Не писать «всё PASS».

## Измеренные задержки и ресурсы

Для одиночного потока ниже — медиана показателей трёх PROXY runs, после 16
warmup packets/run. Старая версия имеет SOURCE_ENDPOINT_MISMATCH, поэтому её
значения — только справка о стоимости некорректного пути, не победитель ranking.

| Показатель | До, с дефектом source | После, корректный source |
|---|---:|---:|
| Медианный RTT, ms | 2.697 | 2.866 |
| p99 RTT, ms | 2.928 | 3.154 |
| CPU CLI/Core, % всего ПК | 0.320 | 0.676 |
| Средняя private RAM CLI/Core, MiB | 2.664 | 2.472 |

При двух потоках новая версия: медианный RTT около 2.724–2.725 ms, p99 около
3.202–3.241 ms, максимум 3.890 ms; ответов >20 ms нет. OFF control: медиана
около 0.753–0.755 ms. Наблюдаемая скорость около 82 packets/s при заданной паузе
20 ms не является предельной пропускной способностью.

CPU включает время ядра, отнесённое к процессу, но не выделяет всю стоимость
драйвера из System. Нет отдельного измерения kernel pool/handles и энергии.
RAM — выборки 250 ms; небольшую разницу нельзя считать универсальной экономией
или доказательством отсутствия утечки. Фоновая нагрузка системы учитывается
как ограничение. По этим данным нельзя утверждать, что архитектура быстрее
или легче прежней; её преимущество здесь — корректность и изоляция трафика.

## Размер компонентов

Core DLL: 216 064 → 221 184 bytes; подписанный SYS: 29 592 → 39 832 bytes.
Итого прибавка этих двух файлов **15 360 bytes (15 KiB)**. GUI/installer не
пересобирались; это не сравнение полного дистрибутива.

Штатный CLI с исправленным lifecycle: 204 800 → 205 312 bytes (+512 bytes).
Итого CLI+Core+SYS прибавили 15 872 bytes (15.5 KiB).

## Дополнительные correctness/fault gates

### Финальный штатный CLI

Product source `735b9fa7a8f07782d783710730b7e6605e967e12`: обработчик Ctrl+C
теперь только просит завершение; main владеет Stop и сохраняет DLL до выхода
процесса, исключая прежнюю гонку Stop/FreeLibrary. Строка readiness явно
flush-ится в stdout, ошибка Stop приводит к ненулевому exit code.
CLI SHA256 `be95c16e2b837551e5d7a3382c0f04eff43d3fcb2d50f79d461e9fd67b227354`.
Core7a02e79b/SYSc1ab4193 не изменены.

TestLab с variant=upstream/ConPTY подтвердил 3×512 PROXY и 3×512 OFF, two streams,
512 bytes,20ms,16 warmup/stream. Все route/payload/source/resource gates прошли.
В каждом PROXY run: ready=true, graceful_stop=true, forced_stop=false,
output_capture_complete=true, driver detached. Никакого изменения readiness
regex или fallback на Core API для этого gate не было.

### Native UDP/SOCKS diagnostic cases

На финальном пакете 1.1.0.0: **42/42 Direct controls**, **42/42 explicit SOCKS5
controls**, **39/39 Core cases**. Это отдельная диагностическая native UDP/SOCKS
fixture с public Core API, а не замена штатного TestLab benchmark выше.

Проверены 0/1/1200/8192/65000-byte payloads, IPv4/IPv6, 127.0.0.1/127.0.0.2 и
собственный 192.168.0.157. Один сокет отправляет двум назначениям до возврата
первого ответа; оба payload/source tuples верны. Повторное использование того
же порта новым endpoint с задержанным старым ответом не смешало владельцев;
поступление старого запроса к origin отдельно подтверждено. UDP DIRECT сохранил
исходный source port и обошёл controlled proxy; UDP BLOCK не дал пакета ни
proxy, ни origin. Это не проверка TCP DIRECT и не external-network validation.

Fault gate: один socket направляет пакет в конфигурацию с зависшим handshake,
затем в исправную конфигурацию. Исправный маршрут ответил за **2.0205 ms** и
сохранил обмен после 5-second deadline другой association. Проблемный пакет
не попал к origin; timeout закрыл TCP через reset. `drops=1` — ожидаемо
отброшенный pending packet; malformed=0, io_errors=0. В обоих этапах Stop=1,
helper threads_alive=0, forced_cleanup=[]; независимость association подтверждена.

Первоначальная fault fixture принимала за закрытие только FIN, поэтому пометила
сценарий FAILED, несмотря на исправный маршрут. Повторный gate корректно записал
ConnectionResetError как закрытие и прошёл. Первый LAN control ошибочно привязал
source127 к LAN destination; это отказ controls до Core, а не дефект продукта.
Он сохранён; исправленная fixture привязала LAN client к собственному LAN IP.

Owner crash/постоянный fail-closed режим здесь не проверялись и не менялись:
существующий cleanup отключает filtering после выхода Core. Длительный стресс,
несколько local IP одного endpoint и power/HLK остаются отдельными проверками.

## Evidence и восстановление

Private/ignored roots `artifacts/diagnostics/`:

- `udp-testlab-series-target-20261022-before-r1`: matched-one-stream,
  tcp-smoke, parallel-negative. Последний workload подтвердил PAYLOAD_MISMATCH,
  cross-stream response (sequence33 → stream1 sequence1), response_timeout=1.
- `udp-testlab-series-target-20261022-after-r1`: matched-one-stream PASS;
  TCP smoke ROUTE_MISMATCH, поэтому общий runner status FAILED и следующая
  parallel серия в этом trial не запускалась.
- `udp-testlab-series-target-20261022-after-r2`: обе parallel серии,
  12 runs, все functional/resource gates подтверждены; status MEASURED.
- `udp-final-1100-target-20261022-r1`: PnP oem24.inf, file/PnP version1.1.0.0,
  точный SYS hash перед трафиком; normal+fault PASS, exit0; baseline restored.
- `udp-extended-target-20261022-r2`: предыдущий package прошёл normal38 Core
  cases; r1 control failure и r3 FIN-only fixture failure сохранены отдельно.
- `udp-native-cli-target-20261022-r1`: штатный CLI, final package; 3 OFF/PROXY
  пары, 1536/1536 PROXY и1536/1536 OFF; wrapper/rollback подтверждены.

Для ручной проверки подготовлен private/ignored headless kit
`artifacts/diagnostics/udp-review-kit-1100-20261022-r1`: штатный CLI, Core, matching
signed INF/CAT/SYS, LICENSE и manifest. GUI/installer в него не входят. На PB-SUT
после проверки сохранён исходный установленный пакет, Stopped/Disabled.

Архив `udp-review-kit-1100-20261022-r1.zip` — 256942 bytes, SHA256
`7c1129a3e6737f059cbb4c6bed44e0f9e5e85a9c810cd731dbd3538f766909ce`;
manifest SHA256 `ae507dfaa552ec84bb1c79eac01367826caf1538b353b20a49f2469fc879e51a`.
Product branch head `b9939135ba80c71ee9122727be84db0c56d7bc0b` (последний code
commit735b9fa); remote подтверждён. Integration driver по-прежнему b359627,
PR/merge не создавались. Кодовые изменения и локальная проверка завершены;
следующий PR — только по отдельному запросу USER после его проверки.

Каждая серия — новые directories, без Resume/reseal. После каждого trial
проверены исходный SYS hash, Stopped/Disabled/problem32 и restored=true;
wrapper COLLECTED, cleanup_errors=[], клиентский WinRM/TrustedHosts восстановлен.
Trust/BCD/system proxy/power не менялись. UDP branch опубликована отдельно,
integration driver не менялась, PR не создан.
