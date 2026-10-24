# Последний full50: ошибка завершения, 24 октября 2026

## Наблюдения

Пользовательский прогон `20261024-042424-ff58ebf4b5694516b91bb2b18bf43194`, установленная preview.32, WinDivert 4.3.0, NORMAL/LOW, 04:24:28–05:01:29 UTC. Все 50 сценариев запускались, skipped=0, все 50 case isolation verified. Это отдельный прогон от full50 от 23 октября.

- В сохранённых `measurements` **38 сценариев имеют все измерения complete=true**, 12 имеют собственные ошибки. После финализации у всех 50 записано `complete=false`, `cleanup_verified=false`.
- Queue: PID4596, Start1/Stop1, child_exit_code=0, exit_verified=true, forced_stop=false, lifecycle.cleanup_verified=true. Capture полный, retention=true. Это штатное завершение процесса, но ещё не подтверждение полного OFF системы.
- `local_origin_cleanup_verified=true`; общий error=`TRAFFIC_CLEANUP_OR_REBOOT_REQUIRED`, queue.cleanup_exception_type=`ValueError`, `off_after` отсутствует.
- `idle-failure-1792818089658463200.json`: PowerShell exit1, stdout пустой; `Get-CimInstance Win32_SystemDriver -OperationTimeoutSec 5` на строке46 `Assert-WinDivertTrafficIdle.ps1` завершился `CimException`, HRESULT **0x40004**. Это [WBEM_S_TIMEDOUT](https://learn.microsoft.com/en-us/windows/win32/wmisdk/wmi-non-error-constants). Причину задержки WMI эти данные не устанавливают.
- Read-only повтор системного запроса через административный Chat On Steroids успешен за258мс: ProxyBridgeDrv Stopped, WinDivert Running/Started=true, процессов ProxyBridge/ProxyBridge_CLI/ProxyBridgeSvc/pb_core_host нет. Службы не останавливали. Это текущее наблюдение, не ретроспективная аттестация OFF и не проверка отсутствия всех WinDivert handles.

## Почему все стали ошибками

1. `Assert-WinDivertTrafficIdle.ps1` вошёл в восстановление принадлежащего попытке WinDivert. По порядку исполнения перед строкой46 уже пройдены ownership/path/exit, settlement и zero-handles observation. Запрос SCM через CIM прервался до `Stop-Service`, поэтому остановка драйвера в этой ветке не была выполнена.
2. `runner.idle` сохранил диагностический файл и выбросил `TRAFFIC_PRODUCT_OFF_NOT_VERIFIED`. `session_runner` заменил это общей ошибкой `TRAFFIC_CLEANUP_OR_REBOOT_REQUIRED` и не сохранил исходный код непосредственно в queue evidence.
3. В финальном цикле `row.complete = row.complete and cleanup and graceful and capture_ok and immutable_ok`. При cleanup=false все 50 итоговых complete стали false. Первичные успешные measurements и пустые errors у38 сценариев сохранены.
4. `trafficReportStatus` трактует row.complete=false как FAIL. Получается50 ошибок вместо раздельных «38 успешных измерений /12 ошибок измерений» и «состояние системы после очереди не подтверждено».

Отказ подтвердить OFF обоснован. Представление этого отказа как50 отдельных ошибок трафика смешивает разные результаты. Автоматически делать PASS или предлагать обязательную перезагрузку по одному CIM timeout оснований нет.

## Собственные 12 ошибок

Набор полностью совпадает с [предыдущим разбором](FULL50_FAILURE_ANALYSIS_2026-10-24.md):

- 7 UDP-связанных: udp-connected, udp-unconnected, udp-sweep, udp-connections, app-dns-udp, mixed, stability. Transport/route/loss gates не пройдены. Например, udp-connected: origin и proxy получили10737 пакетов, proxy отправил10737 ответов, origin reply errors=0, четыре flow/одна association; большинство работников не получают свои подтверждённые ответы. Это согласуется с ранее установленным WinDivert4.3 reply ownership механизмом.
- 5 HTTP3/QUIC: app-http3, app-http3-multiplex, app-http3-payload-sweep, app-quic, app-quic-multiplex. Пример app-http3: origin UDP=0, workers отправляют QUIC Initial, получают0, handshake incomplete. Лабораторный proxy по-прежнему содержит ранее воспроизведённое ограничение общей UDP association.

SHA256 установленной32 и текущего source совпали для ключевых файлов: proxy.py `3ebfb0294ef4926b002ba45aaa983683dd20c8568e136c8d6ce5899393d874e5`, session_runner.py `f4099ddbbb5f8bc3a75fa5febb6317b3183f57a219ba11da7db79a9762f91fe5`, Assert-WinDivertTrafficIdle.ps1 `44c6d6efbadd6dfe77da5e771bba3648eee478d95d4aafb704a5bb0763c774ba`. Ранее найденные engine ограничения в preview.32 ещё не исправлялись; последние обновления были UI.

## Границы и следующий scope

Сохранённые попытка/reports/raw/console не изменены. Новых сетевых прогонов, установки/остановки драйверов, изменений продукта или лабораторного кода не было. Не запускать следующую очередь, полагаясь на старый OFF: текущее состояние требует штатной проверки/восстановления с сохранением ownership gates.

Рекомендуемое отдельное исправление лаборатории: ограниченный повтор наблюдения при CIM timeout без обхода проверок; сохранять первопричину cleanup; разделить исход измерений и финальную системную проверку, в том числе для старых reports. Успешные measurements при неподтверждённом OFF нельзя выдавать за полностью аттестованный PASS. Ошибку состояния системы показывать отдельно, не50 раз как ошибку трафика. Продуктовый UDP ownership и лабораторный QUIC association остаются отдельными задачами.
