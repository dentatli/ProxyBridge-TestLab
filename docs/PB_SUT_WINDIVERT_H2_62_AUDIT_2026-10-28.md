# PB-SUT: WinDivert H2 на preview.62 — аудит 28 октября 2026

Read-only разбор последнего пользовательского прогона. Новые нагрузки, обновления, перезапуски и изменения продукта не выполнялись. Web API PB-SUT при чтении не ответил; прочитаны уже завершённые файлы. Приложение не запускали.

## Результат

**COMPLETE, ошибок нет.** Attempt `20261027-160729-21277d8554704c44859131c503c176d4`, WinDivert 4.3.0, Core SHA256 `1996d5564a6c6f9b58a25e64781acbc07720cbac530e2706ce4a58f20ea18d14`. Прогон 27 октября16:07:46–18:08:06Z (21:07:46–23:08:06 Екатеринбург). Профиль H2: 7200 с нагрузки, 7204.609 с с завершением. Последняя установленная лаборатория на SUT — preview.62; runtime fingerprint `279c5c721680662800f9adb2f69bf4f9d9372d8e88f097fdd87fce11ccc2275d` совпадает с ранее принятым WFP62.

- 211/211 завершённых работ имеют подтверждённые обмен и маршрут,96 bulk-окон, 17 churn-окон, 6 apps × 16 окон, 2 persistent канала.
- Постоянный TCP: 14400 подтверждённых обменов,TX=RX 7372800 байт, полная конечная сверка.
- Постоянный UDP: 36000/36000, loss/invalid/expired 0.
- HTTP, HTTPS, HTTP/2, SFTP, DNS-TCP, QUIC: по 16 успешных окон. QUIC close 16/16, максимальное ожидание 2.422 с. Прежний QUIC FAIL из preview.60 не повторился. Исторический точный таймер не записывался; его причина задним числом не установлена.
- DIRECT/BLOCK: 116 × 4 = 464/464 PASS. Независимо пересчитаны callback after-before, receiver arrivals и health probes. DIRECT доставляет с событием, BLOCK имеет событие и нулевую доставку при здоровом получателе, PROXY на этих каналах отсутствует. PID 9772 / ruleIDs 3, 4, 5, 6 стабильны,Start/Stop 1/1.
- Worker failure_context отсутствует, записанных control_recovery 0. Не было UNKNOWN или часовой остановки.

211 работ против 212 у WFP не является рейтингом скорости: профиль ограничен временем, конечные окна и число заданий зависят от расписания и завершения предыдущих операций. Обычные UDP-related FAIL из preview.56 этот ограниченный длительный профиль не опровергает.

## Очистка и целостность

Product/localorigin/nativecleanup=true,forced_stop=false. off_after verified=true:serviceStopped,known driver names absent,no known WFP objects, product processes 0. Console полный, truncated=false, 1355422 байт.

9 экспортированных файлов SHA совпали. ZIP SHA256 `fc813eb37563197a4782e86c55cc122682cded15587e193fe03c82c09fa874a3`; raw/measurement SHA, journal SHA / 443 записи (116 policy + 211 completed + 116 minute), console SHA сверены. Пересчёт summary — 0 расхождений. Evidence только ignored: artifacts/endurance-check/sut-latest-20261028-r1, sut-windivert-h2-62-export-20261028-r1/target-files/evidence, audit-windivert-h2-62-20261028.py/.log. WinRM/TrustedHosts клиента восстановлены без ошибок.

6306 наблюдений ресурсов, unavailable 0. Core host CPU mean 1.501% ПК; handles 125→124, max 136; threads 14→10, max 14; private commit 2.88→3.75 MiB, max 4.14 MiB. Эти числа относятся к процессу, не полному расходу архитектуры. Небольшое изменение памяти в одном H2 не доказывает утечку или её отсутствие. ETW ядра в soak отключён.

## Статус приёмки

Теперь WFP и WinDivert прошли по одному H2 на одном runtime preview.62. Подтверждена функциональная приёмка описанного длительного профиля, не все возможные виды трафика/правил/сроков и не общий ресурсный рейтинг. Перенос в main / публикация/новые прогоны не выполнялись.
