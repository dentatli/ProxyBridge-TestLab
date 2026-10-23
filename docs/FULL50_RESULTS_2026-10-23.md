# Полный локальный прогон WinDivert4.3.0

Attempt20261023-161135-c28a486a85e84ca5973c16cecbd2c088, preview18 из e57f15c. Все50NORMAL/LOW безсуточногоsoak выполнены, пропусков/отмен нет:38PASS/12FAIL. Общий статус FAILED корректен: полнота выполнения не означает работоспособность всех сценариев. Результаты не подменены прежними успехами. WFP не запускался и не сравнивался.

| Группа ошибок | Сценарии | Наблюдение |
| --- | --- | --- |
| UDP | udp-connected, udp-unconnected, udp-sweep, udp-connections | Неполный транспорт, превышение1% потерь, полный маршрут не подтверждён |
| HTTP3 | app-http3, app-http3-multiplex, app-http3-payload-sweep | Не завершён QUIC handshake, транспорт/маршрут не подтверждены |
| QUIC | app-quic, app-quic-multiplex | Не завершён QUIC handshake, транспорт/маршрут не подтверждены |
| DNS UDP | app-dns-udp | Timeout, нет ответа, маршрут не подтверждён |
| Смешанные | mixed, stability | Ошибки UDP внутри TCP/UDP профилей; сценарии FAIL |

Остальные38 сценариев PASS, включая TCP, прикладные протоколы по TCP и три режима OFF/UNRULED/SOCKS5. Это результаты данного комплекта/профиля, не универсальная приёмка всего трафика ПК. Причина UDP/QUIC отказов этим просмотром отчётов не установлена; продукт не менялся, дополнительное расследование не проводилось.

Оркестрация: один PID1220, Start1/Stop1, child0/host10, forced=false. Последний ACK253, одно правило/config, правило выключено. Capture полная, файл632228bytes без truncation. Final product cleanup=true, local-origin cleanup=true, fresh OFF:0productprocesses, известные драйверы и WFP objects отсутствуют. Обычные ошибки не оборвали очередь.

Private evidence: %LOCALAPPDATA%/ProxyBridge-TestLab/traffic-lab/20261023-161135-c28a486a85e84ca5973c16cecbd2c088. Снимок artifacts/session-development/preview18-full50-final.json в dev worktree. Не коммитить приватные raw/profile/секреты.

## Исправление текущих счётчиков

В preview18 TCP origin прибавлял rx_bytes/tx_bytes в общей сессии только в finally после завершения соединения. Поэтому активный сеанс показывал0 до его закрытия; это не доказывало отсутствия обмена. Теперь подписанный metrics snapshot суммирует завершённые данные и текущие validated transfers, исключая двойной учёт после закрытия. Итоговые transfer hashes/bytes и gates не меняются. Внутренние объекты transfers не попадают в wire JSON.

Также заполнены отсутствовавшие origin byte counters для UDP payload, DNS messages, SSH/SFTP и HTTP2/unary gRPC. Другие прикладные серверы уже обновляют их по транзакциям. Это объём данных получателя (DNS — длина DNS сообщения), не все bytes сетевой карты/шифрования. Малые значения UI показывает в Б/КиБ, затем МиБ; неизвестные значения остаются неизвестными. По запросу удалено время текущего задания в RU/EN.

Без продукта проверены подписанные snapshots во время upload/download/duplex/64-byte echo, по2одновременных flow: байты растут при active>0, финал точно равен клиентским counters, double counting отсутствует. Снимок artifacts/live-counters/stream-component-check.json. UDP payload counters проверены в памяти для валидного/невалидного пакета и ошибки отправки; непринятые/неотправленные байты не добавляются. Новых tracked autotests нет.

Пакет19 из a57e8c6:1470 SHA файлов, admin startup/preflight, AST/JS syntax и единицы Б/КиБ/МиБ/unknown PASS. Attempt20261023-170300-ad866a54057541f9850f3ed27829ba99: TCP-upload/DNS-TCP/SSH/HTTP2,4PASS, обе cleanup=true. Origin bytes ненулевые, подписанные маршруты подтверждены. Отдельный30s TCP upload20261023-170408-13f570cb6cbf4b40ad7e42f5e36663ae проверил видимое обновление UI во время обмена: Принято454,31МиБ при4активных сеансах; Отправлено0Б корректно для получателя upload. Время текущего задания отсутствует. Прогон завершился COMPLETE, обе cleanup=true. Снимки artifacts/live-counters/preview19-final.json, preview19-ui-progress.json, preview19-ui-final.json. Полный50 выше по-прежнему относится к18 и не повторялся из-за изменения счётчиков. Пакет19 оставлен запущенным, нагрузка завершена.
