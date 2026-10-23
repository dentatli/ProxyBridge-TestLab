# Новый чат разработки: завершить режим «На этом ПК» — 2026-10-23

Текущая просьба пользователя: «Давай перейдем в новый чат и доделаем тестер
до конца. Пока сосредоточимся на режиме \"На этом ПК\"».
Это смена задачи с диагностики продукта на разработку TestLab.

## Цель и начало

Прочитать AGENTS.md и CHAT_HANDOFF_DEVELOPMENT.md. Затем сверить текущую
реализацию с INTERFACE_PLAN_2026-10-05.md и DEVELOPMENT_PLAN.md выборочно.
Провести фактический аудит режима «На этом ПК», кратко зафиксировать
готовое/незавершённое/непроверенное и самостоятельно довести локальные
пользовательские сценарии до рабочего состояния. Действовать, не останавливаться
на плане. Удалённый режим/Ubuntu/SSH сейчас вне приоритета; не расширять их.
Не превращать исторические NEXT диагностических документов в очередь работ.

Сохранить согласованный UI: сборки → выбор тестов → запуск → результаты/история;
RU/EN, реальные доступные тесты, отдельные duration/load, оценка времени,
пользовательские имена сборок с точной привязкой к файлам/revision/hash.
Проверить локальные prerequisites, реальные команды backend, прогресс,
ошибки, отмену/очистку, историю, таблицу сравнения последних результатов при
одинаковых условиях и корректные области измерения RTT/CPU/RAM/throughput.
Недоступные/неподтверждённые сценарии не выдавать за готовые. Не снимать
доказательные gates ради зелёного UI. «Три режима» — отдельный тест
OFF/UNRULED/SOCKS5, не замена остальных тестов. Поддержку новых proxy types
не добавлять без необходимости — текущие требования в development handoff.

## Workspace

C:\src\ProxyBridge-TestLab, branch codex/checkpoint-20261007.
Перед этой передачей remote/head40e62a97961abd850900a374bcc572d25bdf8d35.
Этот handoff будет отдельным следующим docs commit. Не переключать/reset
репозиторий ради названия ветки. Новый worktree пользователь не запрашивал.
В Git status только чужой untracked
src/independent_wfp/KernelReadCapture.cs: НЕ читать/запускать/удалять/коммитить.
Проверять status перед правками, сохранять работу других чатов.

## Известные долги тестера, которые нужно проверить по текущему коду

- Test-ProcessLifecycle.ps1 ранее падал из-за устаревшего ожидания пустого
  ReadyRegex: реализация подставляет обязательный ready regex. Выяснить контракт
  и исправить причину/проверку, не замаскировать ошибку.
- Штатный TCP DIRECT route gate требует совпадения исходного client port с
  receiver peer port. Для DIRECT через Core relay порт меняется. Нельзя просто
  принимать action/log DIRECT: нужны owner socket tuple, absence of SOCKS flow,
  receiver/payload evidence. В отдельной диагностике такое доказательство уже
  получено, но штатный gate остался INCONCLUSIVE. Сверить его применимость
  локальному UI/каталогу и исправить семантику с сохранением отрицательных gates.
- Исправленные ранее проблемы fixture FIN-vs-RST, LAN-source binding и report
  CPU=None описаны в UDP_TESTLAB_BEFORE_AFTER_RESULTS_2026-10-22.md. Это не новые
  задачи к повторному выполнению; не считать весь Lab suite проверенным.
- Benchmark DIRECT-only setup не воспроизводит Core bug: driver watchlist
  включает PROXY/BLOCK apps, а DIRECT-only app проходит напрямую в kernel.
  Для relay DIRECT нужен смешанный набор правил одного app. Эта подготовка
  была исправлена только в ignored fixture. Не смешивать kernel bypass и
  Core-relayed DIRECT, честно описывать условия измерения.

## Границы продуктовой диагностики

Этот чат НЕ продолжает WinDbg/WFP расследование и НЕ исправляет ProxyBridge.
Две продуктовые правки в отдельных ветках fork dentatli/ProxyBridge:
- codex/udp-map-source-key, headb9939135ba80c71ee9122727be84db0c56d7bc0b;
- codex/tcp-direct-route, head340bdc839bed3c02d75dceb996cee68f39ecf045.
Integration driver остаётсяb3596272a8dc8898790b016d1e4c488c2fdc917d.
Они не объединены, совместная TCP+UDP версия не проверена. Не создавать PR
или merge, не переносить/менять продуктовые ветки без явной просьбы пользователя.

Последний диагностический этап завершён:
TCP_DIRECT_BENCHMARK_RESULTS_2026-10-23.md —48 runs,43 008 replies+1.5GiB verified;
исправленная маршрутизация DIRECT подтверждена. Paced-p99 нестабилен; Core-host
upload cycles/MiB+32%, download−82%, нет обещания минимальных ресурсов/peak rate.
TCP_DIRECT_FIX_VALIDATION_2026-10-23.md — предыдущий native gate11/11.
UDP_TESTLAB_BEFORE_AFTER_RESULTS_2026-10-22.md — локальные UDP gates завершены.
Эти отчёты относятся к записанным binaries, не к будущей общей сборке.

Исторический redirect-context дефект воспроизведён без product driver,
с WFPSampler-derived callout; механизм в tcpip/WFP исследован, Microsoft
официально не подтвердил. MICROSOFT_WFP_REDIRECT_CONTEXT_BUG_REPORT_2026-10-22.md
подготовлен, не отправлен. Не открывать эту диагностику ради завершения UI.

Последнее подтверждённое состояние физического PB-SUT192.168.0.157:
baseline SYS3e5c3c709ee8c8800628f04b5550f3a82377deb264b045ab2f2ccbab3fd8fb4c,
Stopped/Disabled/problem32, forced_cleanup=[], client WinRM/TrustedHosts restored.
Это историческое наблюдение, не inventory локальной agent VM.
Fresh captures/kits/manifest сохранять; старые не Resume/refreeze/переписывать.

## Проверки и завершение

Соблюдать текущие AGENTS: обычные dev checks<5min разрешены, длинный suite
не дробить для обхода ограничения. Рутинная разработка не меняет BCD/trust,
proxy/hypervisor/power/product-driver install. Предыдущие разрешения на
диагностические установки не использовать как рутинную dev-процедуру.
Перед traffic/product checks сверить отсутствие параллельной диагностики;
worktree не изолирует OS/driver/services. Старт текущего чата после завершённых
выше trials; новые диагностические workloads в этой передаче не запущены.

Русский, конкретные результаты, не выдавать mock/synthetic proof за реальный
runtime. Надёжность > скорость > ресурсы > вес. Работать автономно до завершения;
остановка только при необходимом решении/вмешательстве пользователя или <=5%
reported Codex usage remaining. Проверять usage периодически/перед долгими
операциями; unavailable сообщать, не оценивать. Коммитить/пушить разрешённые
исходники/документы и проверять remote; captures/kits/keys/credentials вне Git.
Статус разработки вести в development handoff/тематическом документе.
