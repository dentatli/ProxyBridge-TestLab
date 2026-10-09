# Функциональная инвентаризация TestLab

Проверка 2026-10-09 в `testlab-development/ProxyBridge-TestLab`, ветка `codex/development-functional-completion`. Статусы ниже относятся к исходникам текущей ветки. Старые пользовательские испытания продукта не подтверждают этот checkout. Диагностические исходники, рабочая копия, комплекты и журналы не менялись.

## Актуальный срез transport catalog — 2026-10-09

Полные методы/параметры/приёмка: [TRAFFIC_LAB.md](TRAFFIC_LAB.md). Новый transport путь не заменяет прежний общий protocol runner и его gates.

| Путь | Готово по реализации | Фактическая проверка / предел |
| --- | --- | --- |
| Каталог | 16 независимых пунктов, индивидуальные длительность/нагрузка, оценка каждого/набора, named suites | GUI RU/EN/save/apply/delete собственной записи/refresh; базовые throughput вместо заявления об абсолютном максимуме |
| Remote runtime | Отдельная Ubuntu 22.04 IPv4 служба, exact plan/hash/manifest/process/listeners, HMAC TCP/UDP/SOCKS5, runtime lease | Установка/повторная проверка; signed identity, tamper, wrong keys и disconnect; старый endpoint сохранён |
| Нагрузка / скорость / стабильность | RTT, upload/download/duplex/multistream/loaded RTT, connections/churn, UDP обоих типов/sweep/flows, mixed/stability/soak | 30 облегчённых component cases; HIGH и реальные 24–72 часа не выполнялись |
| Длительная история | Streaming JSONL полных этапов + SHA/count, compact stage history и all-sample totals | Две короткие десятиэтапные симуляции direct/SOCKS5; не являются сутками нагрузки |
| Реальный продукт / очередь | OFF/UNRULED controls, нормальные OS sockets, signed all-flow reconciliation + product PID route event, штатное закрытие/own service restoration, cancel/skipped | OFF/UNRULED успешны; реальные TCP/UDP SOCKS5 FAIL сохранены; service Stopped/cleanup gates; PREPARING cancel verified |
| Результаты | Paging истории, последняя попытка каждой сборки/теста/полных условий; failure/cancel без fallback; выбираемые сборки/метрики | Реальные сохранённые FAIL/CANCELLED просматриваются; нет успешного SOCKS5 benchmark |
| Ресурсы | Worker/CLI/origin process и обе ОС отдельно; CPU/RAM/handles/threads, unavailable/identity changes, bounded timeline | Windows/Linux counters проверены; ресурсам драйвера не приписываются |

Остались: прикладные семейства общего protocol catalog; v4.0.0/reboot и приёмка произвольных/перемещённых driver bundles; успешный реальный SOCKS5 на работоспособном продукте; отдельная приёмка HIGH/long/cancel-during-load; расширенные SSH host-key/port-conflict/rollback cases. Ubuntu 24.04/26.04 и IPv6 отложены. Продуктовый TCP дефект остаётся в диагностическом чате. Диагностические исходники/комплекты не изменены.

## Предыдущая инвентаризация до transport catalog

| Пользовательский путь | Реализация | Предел подтверждения |
| --- | --- | --- |
| Сборки → Тестирование → Запуск → Результаты | `lab.html`, `lab.js`, отдельные URL, RU/EN, browser history, серверное состояние запуска; новый экран открывается по `/` | Все четыре страницы и RU/EN просмотрены после удаления старого frontend; runtime не испытывался |
| Имена и идентичность сборок | `BenchmarkBuildCatalog`, DPAPI-пути, выбор с повторным files-only inspection, имя отдельно от bundle identity | Произвольная beta, перемещённые комплекты и 4.0.0 не допускаются к новому runtime |
| Галочки и условия каждого теста | RTT, TCP transfer, отдельные три режима, TCP connections; SHORT/NORMAL/LONG и LOW/HIGH; оценка каждого и всего набора | Transfer пока выбирается как upload+download вместе; пресеты присутствуют в коде, новые сетевые испытания не выполнялись |
| Подготовка и очередь | `BenchmarkLaunchPlanService`, `BenchmarkRunService`: immutable child plans, hashes, повторные проверки каждого теста, stop после текущего прогона/очистки, сохранение skipped/failed попыток | Реальный запуск очереди/отмены в этом worktree не проверялся; OS/driver не изолированы worktree |
| Соединения и восстановление | `ConnectionWorkload`, существующий TCP controller, baseline/load/recovery, фактические ошибки, отчёт | Число установленных соединений не доказывает переполнение таблицы или максимальную ёмкость; TCP-дефект остаётся отдельной диагностикой |
| Сравнение и история | `BenchmarkLabService`, `lab-results.js`: последняя попытка сборки/теста/условий, отдельные failure/cancel, чтение сохранённых свидетельств, paging/detail API, выбранные метрики RTT/темпа/CLI CPU/private RAM | Worktree не содержит прежние приватные результаты; история на реальных сохранённых данных здесь не проверялась; CPU CLI не CPU драйвера |
| **Именованные повторяемые наборы** | **Новый** `BenchmarkSuiteCatalog`, API list/save/update/delete, RU/EN, до 100 наборов в защищённой пользовательской config-папке | Хранят только выбор тестов/условий/топологию, без сборки, пути, ключей и runtime-допуска. Каждый запуск требует свежей подготовки |
| Ubuntu wizard | `RemoteUbuntuService`, RU/EN, protected identity/settings/trust, root LTS gate, exact plan/apply, состояние при refresh/restart | Реальная установка и NO_CHANGE_VERIFY на 22.04, 18 plugins/25 TCP/9 UDP listeners; TestReady=false, remote controller остаётся заблокирован |

## Исторический список до transport catalog

1. **Приёмка Ubuntu wizard:** UI/API ключа, host trust, root, IP/порт, check/setup/plan/apply и allowlist 22.04/24.04/26.04 реализованы. Установка/повторная настройка на Ubuntu 22.04 x64 Python 3.10 проверены. Нужны реальные 24.04/26.04/native vendor compatibility, changed-host-key/unsupported OS/port conflict/rollback и физическое отключение сети. Polling статуса читает локальное состояние/TTL, постоянная SSH-проверка сети ещё не реализована. Подробности — `REMOTE_UBUNTU_SETUP_PLAN.md`.
2. **Удалённые контроллеры и допуск:** контролируемый обмен напрямую/SOCKS5, проверка TCP/UDP, CPU/RAM, owned services/ports/cleanup, привязка readiness к настройкам и компонентам, отзыв при disconnect, backend recheck перед каждым тестом. Мастер повторно использует `ServerProvisioningService` с отдельным хранилищем; проверенные компоненты не подтверждают обмен или маршрут. `REMOTE_CONTROLLER_PENDING` сохранён.
3. **Раздельные направления TCP:** независимые галочки upload/download и параметры, соответствующие frozen plans/queue/history/conditions. Сейчас `tcp_transfer` всегда включает оба направления. Изменение общего контроллера согласовать с диагностикой до редактирования.
4. **Полный каталог в новом экране:** loaded RTT и UDP есть в files-only подготовке одиночных legacy профилей, но отсутствуют в GUI-очереди с индивидуальными пресетами и новой таблицей. Далее UDP connections/recovery, mixed/long/stability и прикладные семейства по реальной поддержке backend. Неподтверждённые сценарии сохраняют blocker; ошибки payload/source/route не маскировать.
5. **Runtime-адаптеры сборок:** произвольные driver-комплекты/beta/перемещённые комплекты, затем 4.0.0 с сохранением reboot/lifecycle/evidence gates. Новый worktree не содержит известный private kit; автоматически переносить диагностические комплекты или объявлять новый путь прежним frozen kit нельзя.
6. **Результаты полного каталога:** история remote/loaded RTT/UDP/новых направлений и параметров, условия/топология, область CPU/RAM всей системы и helpers отдельно от CLI при наличии подтверждённых измерений. Совпадение conditions key не является доказательством полной сопоставимости оборудования/фона.
7. **Практическая приёмка:** в отдельно согласованном окне проверить очередь, остановку, failure/cleanup, навигацию/refresh/restart, реальные saved reports и пользовательскую GitHub-сборку. Проверки, запускающие ProxyBridge или нагрузку, согласовать с диагностикой на общей VM. В этой инвентаризации нет утверждения об успешном новом benchmark.

## Предыдущие проверки wizard/frontend

Ubuntu wizard: .NET build 0 errors/0 warnings, JS syntax, ручные UI/API RU/EN, generation/reuse и invalid IP/port/path/plan, CSRF 403, wrong key/closed SSH port → ERROR, восстановление → READY. Первая установка выявила ошибку проверки всего резервного диапазона; исправлено различие reserved/listener ports. Active/enabled, hashes, 18 plugins и реальные слушатели проверены; повторная настройка NO_CHANGE_VERIFY без переустановки. После рестарта STALE, после конфигурации успешный статус отзывается до fresh check. Прямой remote launch API по-прежнему PLAN_BLOCKED/REMOTE_CONTROLLER_PENDING. Секреты вне Git; прежняя диагностическая конфигурация не изменялась. Реальный ProxyBridge benchmark не проводился.

Очистка frontend по запросу пользователя: старые `index.html`/`app.js`/`styles.css` удалены; только используемые общие CSS-правила перенесены в `base.css`. Лаборатория стала стартовой страницей, `/index.html` → 302 с сохранением query; удалённые ресурсы и неизвестные маршруты → 404. Убраны ссылка и тексты прежнего интерфейса, обновлены README и operator guide. Сборка и JS syntax прошли; HTTP-проверки и ручной просмотр Builds/Testing/Run/Results и RU/EN подтвердили работоспособность страниц без ошибок console. Общий backend, существующие probes и отдельный PowerShell runner сохранены из-за текущих зависимостей и дальнейшей интеграции; продукты/драйверы/диагностика/приватные данные не тронуты.

- Первичная `build --no-restore` остановилась с NETSDK1004: новый worktree не имел `project.assets.json`. Обычная .NET 10 сборка восстановила проект и прошла; после изменения каталога повторная сборка также прошла с 0 ошибок/0 предупреждений.
- `node --check` для `lab.js` и нового `lab-suites.js` прошёл.
- Ручной UI просмотр в отдельном `ConfigRoot` внутри игнорируемого `artifacts/development-ui-check`: RU/EN, сохранение/обновление набора, разные параметры RTT и transfer, восстановление после refresh, имя с `<beta>` отображается текстом. После остановки и нового старта сервера API подтвердил ту же запись и её параметры; оба временных UI-процесса остановлены.
- Ручные API проверки: без CSRF → 403; неизвестный сценарий, пресет, ID и повторное имя → 400; повреждённый JSON блокирует чтение/запись и не перезаписывается; удаление временного набора сохраняет соседнюю запись; remote preset не снимает `REMOTE_CONTROLLER_PENDING`.
- Автотесты кода не добавлялись и не запускались. ProxyBridge, драйвер и сетевые генераторы не запускались; system proxy/BCD/WinDbg не менялись. Снимок UI и данные проверки остаются локальными в `artifacts`, вне Git.
