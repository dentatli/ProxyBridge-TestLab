# Общий каталог «На этом ПК» и remote

2026-10-14 оба режима переведены на общий config/traffic-workloads.json: 51 сценарий, одинаковые schedule/worker/runner, controls, route/loss gates, stop и safe continuation. Текущий итоговый admin UI: http://127.0.0.1:5211/lab.html?page=testing, normal Debug output. Выбрать «На этом ПК». Ubuntu/SSH/remote plan/apply для local не нужны. Старые saved suites из четырёх TCP scenarios переводятся в новые IDs; исторические отчёты не переписываются.

## Локальный runtime

TrafficLocalRuntime создаёт собственный Windows origin на каждую попытку до включения продукта. Он слушает только 127.0.0.1: 25 TCP/5 UDP endpoints общего каталога. Занятый порт запрещает старт, чужой процесс не останавливается. Отдельное имя pb_testlab_origin.exe исключает исходящие соединения получателя из правила для python.exe нагрузочных workers. Интерпретатор и необходимые DLL копируются из проверенного Python3.11; PYTHONHOME указывает на исходный Python. Офлайн win-x64 wheels проверяются и извлекаются в private cache; глобальной установки пакетов нет.

На каждую попытку создаются изолированные CA/leaf/SSH/HMAC. CA private key не записывается; системные trust stores не меняются. Source/interpreter/DLL/config/PKI manifest и dependency files проверяются. Прежний предварительный control channel и отдельные подписи каждого запроса сохраняются. Windows IP Helper TCP tables учитывают owning PID и исключают текущий observer socket; неизвестная таблица не даёт idle=0.

Получатель завершается после product cleanup. Plaintext config, TLS key и SSH private key удаляются; публичные certs/manifest/SHA сохраняются. HMAC secret сохраняется только как local-origin-secret.dpapi для последующей проверки тем же пользователем, вне публичного JSON и Git. Private attempt directories не публиковать.

Mode и origin_scope записаны в conditions/attempt; history, CSV и comparison различают local/remote. Для local одноразовые bundle/TLS/SSH pins исключены только из condition grouping: исходные pins и их обязательная проверка остаются в полном evidence. Source/host/mode/CPU/RAM и прочие условия сравнения сохраняются. Loopback использует ресурсы того же ПК; его throughput нельзя сравнивать с отдельной Ubuntu как одинаковые условия.

## Фактическая проверка

Новых tests/* нет. Node/Python syntax и UI build0warnings/errors PASS. Браузер подтвердил одинаковые51 IDs/порядок local и remote, auto-runtime, прикладные группы, отсутствие JS errors.

- Component-only local-catalog-b0bc6ab115cc4c5bb3d9fcb017c2626e: 50 сценариев за55.89s,49 complete через явный SOCKS5 без ProxyBridge, .15s windows. Все35 прикладных сценариев прошли. UDP128-flow stage получил1091/1543 ответов, max per-flow loss70%; baseline/8/32/recovery без потерь. FAIL сохранён, порог1% не ослаблен. Это не штатная SHORT/HIGH/long приёмка; soak не запускался.
- Реальный local run20261014-155137-28a38b81ab784a29b1fb09463ae2af43, TCP/UDP/mixed/HTTPS SHORT/LOW,103.57s RUNNING: TCP PASS TX=RX9,802,240; HTTPS PASS TX=RX1,200,128. UDP2167/0 и mixed2219/0 — FAIL; mixed baseline/recovery TCP complete. Все6 final origin signed, raw+8untruncated CLI file/stream hashes сверены, все4 product cleanup=true, local_origin_cleanup_verified=true.
- Отмена20261014-155441-09a3691fb2444a959dc37b3d6293986a во время measured duplex: CANCELLED, product/origin cleanup=true. Это проверка отмены, не завершение сценария.
- Финальный TCP20261014-155619-a4ac6ef508bd41be97bb1078419c2040: COMPLETE, TX=RX9,765,888, route/product/origin cleanup=true. Final HMAC независимо проверен через DPAPI archive; bundle/raw SHA совпали, plaintext config удалён.

Последующая правка comparison metadata разделила barriers/selector по режимам; итоговый normal Debug UI5211 проверен через API comparison и браузер. Сетевой код после этих прогонов не менялся. Драйвер Stopped, product/origin processes отсутствовали, own listener ports закрыты.

HIGH и24/48/72h не приняты. UDP через ProxyBridge продолжает не доставлять ответы в проверенных local/remote случаях; точная причина здесь не исследуется. Смешанные stability/soak доступны, но их успешная приёмка не подтверждена. См. TRAFFIC_LOAD_ACCEPTANCE.md. Ubuntu runtime, диагностическая копия, frozen kits и продуктовые binaries не менялись. Новые общие Python sources требуют fresh remote plan/apply перед будущим remote run.
