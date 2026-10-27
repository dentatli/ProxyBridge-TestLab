# Endurance58: исправление idle timeout, 27 октября 2026

Исправлен дефект [ранней остановки57](ENDURANCE57_EARLY_STOP_2026-10-27.md). Observer длительного режима каждые5с выполняет аутентифицированный origin metrics запрос через прежний preconnected сериализованный канал. Это не новый TCPconnect и не трафик через измеряемый продукт. Запрос действует и в затишье. Серверный idle30с, проверки данных/маршрута и запрет скрытого reconnect не изменены.

Ошибки observer сохраняются как первичная failure_detail; последующая ошибка isolation не перезаписывает причину. Summary получает тот же failure_context. При неизвестном состоянии проверка по-прежнему останавливается; канал не восстанавливается автоматически, PASS не подменяет отказ.

Проверено на VM без ProxyBridge/драйвера: настоящий Python Agent и OriginMetricsChannel, C#origin/relay/worker и HTTPadapter. 100.609с нагрузки, штатное окно60с, затем quietокно>30с;19 heartbeat, тот же объект/socket до конца, complete=true, nativejobs0. Искусственное закрытие controlchannel: complete=false, observercause CHANNEL_CLOSED сохранена, nativejobs0. Проекция успеха/ошибки в summary проверена отдельно; git diff --check пройден. Новых отслеживаемых автотестов не добавлено. Evidence ignored: artifacts/endurance-check/check58.log, probe-1793073656988624100, check58.py. Ограниченный private timescale доступен только прямому devвызову, не HTTPAPI.

Многочасовой прогон и реальный продукт в этой проверке не запускались. Изменение не исправляет и не скрывает самостоятельную проблему UDPownership в WinDivert. Пользователь сам запускает H2 после обновления приложения и проверки сохранности store. Продуктовые DLL/SYS, доверие, BCD и установки драйверов не меняются.

## Развёртывание

preview58 source cbc8e8460386400ad0693854c4d72f2e75f3048c установлена на VM и PB-SUT (payload/lab58). Все1702SHAнакаждомпроверены. НаSUT2сборки/11элементовистории,VM2/10,unreadable0,admintrue/activefalse/busyfalse. SUTстарыйstoreсохранён, задачаComparisonобновлена,clientcleanupбезошибок. Многочасовойтестнезапускался. Evidenceignored:sut-upgrade58-r1/package58-verified.json; VM artifacts/endurance58-vm-ready.json.
