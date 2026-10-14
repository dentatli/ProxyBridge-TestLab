# TCP/UDP 14 октября: несовместимый Port в профиле; прежний signature не подтверждён

Files-only разбор попытки `20261014-071814-69cfca6efb134488b6879301a17fe037`. Нового Run, трафика, управления WinDbg, build/install, изменений продукта/драйвера/поддерживаемых тестов не было. Диагностическая копия: `codex/checkpoint-20261007`; разработка прочитана без изменений в отдельном worktree, checkpoint `e6f49577992bc581ca0f8bebd4bb361f215152da`.

## Вывод и граница доказательства

В генераторе TestLab обнаружено конкретное расхождение с выбранным CLI: `ProxyConfigs[].Port` записывается числом, тогда как этот CLI читает только JSON string. При таком входе CLI пропускает proxy config. Правило PROXY при этом может быть добавлено с config ID 0, а CLI достигает READY. Это установленная несовместимость исходных форматов, объясняющая наблюдения без привлечения прежнего дефекта redirect context.

Однако использованный приватный профиль удалён штатным finally, текст CLI не сохранён в каталоге попытки. Поэтому точная причинная цепочка данного runtime ещё не наблюдалась. Нельзя объявить ни прежний C0000225, ни новый дефект продукта доказанными. Сначала устранить/проверить несовместимость стенда в чате разработки; не повторять старую WinDbg нагрузку.

## Что действительно сохранено

Каталог `%LOCALAPPDATA%\ProxyBridge-TestLab\traffic-lab\20261014-071814-69cfca6efb134488b6879301a17fe037` содержит ровно 11 файлов: attempt/progress/ownership и восемь report/raw JSON. Полного текстового CLI capture, kernel ETL/KD trace, исходных WSA/NTSTATUS и сохранённого профиля здесь нет. `capture_complete=true` означает завершённое чтение потоков без ошибок; это не наличие текста на диске. `product.py:38..68,134..138` хранит tail в памяти и сериализует только digest/объём/счётчики. `runner.py:161` удаляет профиль; `TrafficRunService.cs:311` удаляет binding.

Оба report семантически совпадают с соответствующими results в attempt.json. SHA256 measured raw совпали с полями report:

- TCP `fe8c90c8b08466152acb91a13b4f99c87d0af6f6d0b45ee194f0998e42916612`;
- UDP `8541109e7c1a702e37d7283b961e3563d9b8a3f16f61022b1120812a95e09ca0`.

У controls нет записанного raw hash: их SHA рассчитаны и сохранены новым аудитом; прежнюю криптографическую привязку к report для них не заявляем. Все 11 файлов побайтно сохранены. Private аудит: [validation.json](../artifacts/diagnostics/traffic-failure-review-20261014/validation.json), воспроизводимый files-only [review.py](../artifacts/diagnostics/traffic-failure-review-20261014/review.py).

| Наблюдение | TCP RTT | UDP connected |
| --- | --- | --- |
| Реально записанный measured stage | один echo, ~24.38 ms | один udp, ~6.31 ms |
| Payload/ответы | один flow, 0 TX/0 RX, ConnectionAbortedError:TRANSPORT_FAILED | четыре flows: по одной отправке, 0 ответов, UDP_TRANSPORT_FAILED |
| CLI route counts для worker PID | PROXY=1, DIRECT=1 | PROXY=0, DIRECT=2 |
| Origin после этапа | null | null |
| CLI lifecycle | READY; child exit0; host exit10; capture complete; no forced stop; cleanup verified | то же |

Worker TCP не сохраняет исходный OSError code/операцию, только класс исключения. UDP `worker.py:281..287` записывает общий OSError marker; receive/select error не раскрыт. Все четыре UDP flows оборвались примерно за 0.23–1.30 ms, expired=0, send_errors=0. Поэтому 100% здесь — отношение отсутствующих replies к четырём записанным отправкам после аварийного выхода, не доказательство четырёх истёкших двухсекундных таймаутов и не установленное место потери пакетов.

OFF/UNRULED controls complete и route_verified=true. **Для обоих cases это только TCP echo**, длительностью 0.2 s (`runner.py:77`, raw phases/tasks). Это не прямой UDP control, не явный SOCKS5 component control. Наличие remote READY и данных TCP controls не доказывает текущую исправность UDP relay/origin. Guard TCP→UDP действительно записал TRAFFIC_RECOVERY_VERIFIED; финальный attempt FAILED, cleanup=true, saved OFF показывает Stopped/нет продуктовых процессов. Глобальное текущее состояние ОС этим офлайн-разбором не измерялось.

13 октября app-quic-multiplex имеет len(stages)=0 и ConnectionAbortedError:TRAFFIC_SCHEDULE_FAILED; поле stage_count=1 является плановым. Новый отказ произошёл после старта workload, но до завершения первого verified exchange; stage1 не означает успешный transport handshake. Предварительную фазу старой попытки не переносим на новую.

## Проверка сборки и старого signature

Сборка с пользовательским именем «актуал» находится в `artifacts/product-builds/driver-63be0eb-testlab-cli`, а не является свидетельством новой версии по самому имени. Текущие файлы совпали с build receipt; bundle пересчитан по штатной canonical схеме и равен записанному `a677580820ee370bef9aad59e3de6cf9eb7d5c672ccf9ec4c9b112753983ab2c`, build ID `build-b0e6385eea7eb229177a477c9986084090593e4a75e41dc851e8eeb1a5a67e3a`. В receipt CLI version observation — 4.0.13-Beta, исходная ревизия63be0eb; нового запуска --version не выполнялось.

| Компонент | Свежий базовый комплект | Диагностический комплект серии7 октября |
| --- | --- | --- |
| CLI | ad83b3aa…bb40ca | тот же |
| Core | fb22ac11…032b9 | 7dc8952e…624ed, диагностическая instrumentation |
| Driver | 3cd79cfc…732c9e | 1e2acb49…b103, диагностическая instrumentation |

Полные hashes записаны в private validation. ZIP63be0eb имеет SHA256 `0381286929084199f68189f97b904731a602e21d158aed8b76dce69b755b746d`; семь использованных source files совпали побайтно с ZIP. Patched CLI main совпал с SHA исходника из receipt. Это files/receipt identity, не новая независимая аттестация source→PE.

Прежний подтверждённый signature — отказ первого SYN внутри SO_PAUSE_ACCEPT, retry, успешный accept, исходный context query C0000225/STATUS_NOT_FOUND→API-1/WSA10022/bytes0, закрытие Core **до SOCKS5**. Сохранённые [status-matches.json](../artifacts/diagnostics/tcp-wfp-full-load-review-20261007-153714/status-matches.json) содержат96 таких связей PID/TID/QPC; все271 файла old user-files-before.json сохранили SHA. [Прежний анализ](../artifacts/diagnostics/tcp-wfp-full-load-review-20261007-153714/analysis.md) и [статус](TCP_CONTEXT_STATUS_DIAGNOSTIC.md) отличают trigger от ещё не установленного механизма утраты записи. Backlog1024 был успешным контролем, не доказанным окончательным исправлением.

В свежих JSON нет исходного NTSTATUS, WSA10022, retry/queue или endpoint связи. PROXY count1 поддерживает гипотезу о состоявшемся rule decision, но без строк/tuple не является доказательством успешного context query конкретного flow: connection callback вызывается и relay, и monitor drain. UDP использует отдельный map/query/relay путь. Общая причина TCP и UDP по одному внешнему marker не устанавливается. Memory access error WinDbg logger относится к другой серии инструментария.

## Конкретное расхождение профиля и минимальный следующий шаг

В development `src/trafficlab/runner.py:50` Port = binding["proxy_port"], а `TrafficRunService.cs:279` задаёт proxy_port=42502 как число. Files-only вызов только чистой функции profile с синтетическими данными подтвердил тип int. Выбранный `main.testlab.c:182` требует первую кавычку для jstr; `:343..358` читает Port через jstr→strtol и добавляет config лишь при port>0. Число даёт пустую строку/port0/config skipped. Остальные поля host/process/TargetPorts/Protocol=BOTH согласуются с ожидаемым TCP/UDP профилем; отсутствия поддержки UDP вообще в исходниках нет.

При отсутствии configs CLI `:927..934` оставляет rule cfg0, `:961` может продолжить Start/READY. В закреплённом Core `Windows/src/relay/pb_relay_tcp.c:229..235` отсутствующий config вызывает drop; `Windows/src/core/ProxyBridge.c:157..159` не создаёт UDP relay без any_socks5_config, хотя `Windows/src/driver/pb_driver.c:239` включает redirectUdp. Core `ProxyBridge.c:215..216` пишет Warning: No proxy configs configured и продолжает успешный Start; CLI `main.testlab.c:863` печатает фактическое число configs. Это сильная статическая гипотеза TCP drop/UDP ошибки из-за профиля, согласующаяся с PROXY1/PROXY0 и мгновенным UDP отказом. Само runtime-сообщение No proxy config и наличие/отсутствие UDP listener в этом Run не сохранены.

Ближайшее files-only действие в **чате разработки**: согласовать JSON string Port (`str(binding["proxy_port"])`) с закреплённым CLI и сохранять безопасные сведения о реально загруженном config/правиле и CLI error text. Здесь development source и поддерживаемые tests не менялись. Результат files-only проверки не объявлять ProxyBridge PASS.

После отдельного допуска минимальный runtime discriminant — один bounded TCP flow с корректным string Port, новым сохранённым CLI выводом и проверкой «ровно один SOCKS5 config42502 реально добавлен», rule config ID, original context query/accepted redirect и SOCKS5 auth/connect. Не начинать с WinDbg/старого HIGH. Если context query успешен и SOCKS5 обмен проходит, старый механизм не объясняет этот flow; если он отказывает, WSA10022 само по себе ещё не равно C0000225 — нужен отдельный scoped оригинальный NTSTATUS сбор по диагностическому допуску. Для UDP затем отдельная проверка native direct + explicit SOCKS5 + продуктового relay/ASSOCIATE/listener/map и исходного OSError; TCP control её не заменяет. Это предложение, не новый Run-допуск/команда запуска. Старые frozen kits не refreeze/Resume; прежний logger стоп-пункт сохраняется для возобновления той серии.
