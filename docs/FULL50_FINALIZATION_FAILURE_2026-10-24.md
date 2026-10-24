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

## Минимальное исправление выполнено — preview.33

По следующему запросу пользователя внесён source `25b6fb2b2b9a362f762be90a42c2176b5a75a934`:

- Только CIM query в ветке owned WinDivert restoration повторяется один раз при HRESULT0x40004, после250мс; каждый запрос ограничен5с. Частичные строки не используются. Остальные ошибки/ownership gates не повторяются и не обходятся. Внешний timeout idle увеличен35→45с, чтобы вместить повтор вместе с существующими settlement/observers/stop bounds.
- Перед финальными gates сохраняется отдельное `workload_complete` в report и presentation queue. Общий complete/PASS по-прежнему требует OFF, graceful exit, полного capture и immutable files. В queue evidence сохраняется первичный cleanup_error без произвольного exception text.
- История и визуализация очереди отличают неуспешное измерение от неподтверждённого итога. Для старых queue-final-off reports исход восстанавливается только в UI из полного ожидаемого набора успешных measurements, при case isolation=true, без errors/cancel/skip. Исходные файлы не переписываются. Семейства без ошибок измерений показываются INCOMPLETE, этапы UNVERIFIED, причина «Измерения успешны; завершение не подтверждено»; полного PASS и ранжирования неподтверждённых результатов нет.

Проверено без сети/продуктовых запусков: ephemeral actual PowerShell retry AST (timeout→success, timeout×2, access denied, partial rows); actual Python finalization AST (cleanup=true/false); JS по двум реальным saved full50: старый38PASS/12FAIL сохранён, новый12FAIL/38UNVERIFIED, execution queue тот же12/38. Missing/ошибка capture/isolation/cancel/skip guards прошли. Временные проверки только ignored `artifacts/cleanup-fix`, tracked автотестов не добавлено.

Пакет33 собран .NET publish,1479 SHA matched. Установлен вместо32 только при active=false/busy=false штатным package Stop; новый controller5178 администратор, active=false/busy=false. Browser подтверждает12 ошибок/38не завершено, отдельную непроверенную очистку, статус и причину TCP; console errors/warnings пусты. Screenshot `artifacts/cleanup-fix/preview33.png`. Нагрузок/новой диагностики не запускали, оставшийся WinDivert не останавливали; готовность системы OFF этим не подтверждена. UDP/QUIC причины остаются отдельным scope. Source push/remote25b6fb2 подтверждены.

## Повторный запуск заблокирован; восстановление выполнено — preview.34

Пользовательская попытка `20261024-051900-b92c5d0a75194855b2178e66ce3cc619` остановлена до начала нагрузки: Start0/Stop0, preparation_failed=true,50skipped, error/cleanup_error=`TRAFFIC_PRODUCT_OFF_NOT_VERIFIED`. Оба новых idle-failure файла содержат exit2, без stderr: loaded query complete=true, known driver names absent=false, product processes0, no known WFP objects=true. Это не повторный CIM timeout: наблюдение исправно обнаружило оставшийся от предыдущей попытки WinDivert. Предыдущее исправление не восстанавливало уже загруженную службу, поэтому блокировка была обоснованной.

В рамках устранения этой блокировки выполнена отдельная owned cleanup без нагрузки. Исходный ownership claim предыдущего full50 содержит original off_before=true, readiness/path/exit/cleanup=true, SHA драйвера `8da085332782708d8767bcace5327a6ec7283c17cfb85e40b03cd2323a90ddc2`. SCM указывает на `C:/src/ProxyBridge-TestLab/artifacts/product-builds/v4.3.0-release/WinDivert64.sys`; файл соответствует этому SHA. В ignored artifacts/cleanup-fix/recovery создан новый минимальный recovery-only binding с копией существующего ownership и hashes наблюдателя пакета33. Он не содержит сетевых секретов, не восстанавливает удалённый runtime binding и не возобновляет старую подготовку/нагрузку. Штатный Assert-WinDivertTrafficIdle.ps1 -RestoreOwnedDriver проверил ownership, процессы, загруженные имена, отсутствие handles, уникальную SCM службу, путь и SHA перед остановкой. Итог exit0: **off_verified=true, known_driver_names_absent=true, loaded_query_complete=true, product_process_count=0, no_known_wfp_objects=true, ProxyBridgeDrv Stopped**. Перезагрузка/установка/удаление/перенастройка служб не выполнялись. Старые результаты остаются исторически cleanup=false; новая проверка этого не переписывает.

Source `93acd1c4650f93bd486b51207514f2e1ca775ef5` исправляет только отображение очереди: skip/cancel/unknown не увеличивают число выполненных тестов/этапов, preparation_failed показывает «Проверки не запущены», отдельно число пропусков и короткую причину OFF-блокировки. Actual saved-attempt JS model check:0/50,50skipped,0trafficFAIL,blocked=true; прежние two-full50 guards проходят. Новых tracked тестов нет.

Preview34 собрана,1479SHA verified, source push/remote подтверждены. Controller33 штатно остановлен только при idle,34 запущена admin/5178, active=false/busy=false. После перезапуска run state пуст; browser показывает выбранные50 и доступную кнопку запуска, ошибок console нет. Историческая неудачная попытка сохранена в отчётах. Screenshot artifacts/cleanup-fix/preview34-ready.png. Новый тестовый прогон агент не запускал; пользователь может повторить запуск, исходный OFF подтверждён отдельной очисткой.
