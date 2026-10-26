# Передача: UDP WinDivert 4.3.0 — только agent VM, 26 октября 2026

Актуальный результат: [локализация user-mode UDP reply selection и изолированное воспроизведение на VM](WINDIVERT_UDP_VM_FINDINGS_2026-10-26.md). Продуктовый runtime/исправление не выполнялись; запрет PB-SUT остаётся.

## Запрос и границы

Пользователь явно выбрал новый чат: разобраться в UDP WinDivert, работать в VM, **PB-SUT не трогать** (в сообщении написано PT-SUT, имеется в виду физический PB-SUT). Запрещены любые обращения к 192.168.0.157/PB-SUT: WinRM/RDP/инвентаризация/перезапуск/копирование/дебаг/нагрузки, даже read-only. Там пользователь самостоятельно запускает 2-часовой тест. Использовать только уже сохранённые на VM экспорты; новая работа не должна влиять на физический ПК. Не ждать его результатов и не мониторить его.

Цель нового чата: локализовать UDP-отказы WinDivert 4.3.0; доказательно разделить ошибку TestLab/несовместимость SOCKS5 relay/ошибку продукта. Не считать виновным WinDivert.sys по одному FAIL и не переносить выводы из WFP UDP автоматически. Пользователь отмечал, что Discord у него работает; это не доказывает корректность всех UDP сценариев, но требует проверить специфичность стенда, правила и формат datagram. Исторические HIGH/full/driver-install разрешения не являются новой диагностической авторизацией.

Начать автономно с offline данных и чтения кода. Перед любым runtime проверить локальную занятость VM, применимые diagnostic gates и отсутствие debugger/workload; обычный допуск development <5мин не разрешает diagnostic Run. Не менять system proxy/BCD/trust/signing/hypervisor/power/установку product driver без отдельного разрешения. Не запускать full/HIGH/многочасовой прогон. Новые runtime-опыты — только в пределах актуальной авторизации, минимальный различающий опыт с сохранением исходных ошибок и подтверждением очистки. Не исправлять продукт вслепую.

## Правила — прочитать до работы

1. `C:/Users/LabAdmin/.codex/AGENTS.md` (полные глобальные предпочтения) и `C:/src/ProxyBridge-TestLab/AGENTS.md` (актуальные проектные правила); этот checkpoint уточняет scope и ужесточает запрет PB-SUT.
2. `C:/src/ProxyBridge-TestLab/docs/NEXT_DIAGNOSTIC_CHAT_2026-10-22.md` — требуемая AGENTS точка входа, но его WFP/SUT trials и исторические разрешения не являются задачей этого чата. Читать только актуальный верх/релевантные ссылки, не весь растущий журнал.
3. `C:/src/ProxyBridge-TestLab/docs/PRODUCT_BRANCH_WORKFLOW.md`: новая продуктовая работа от dentatli/ProxyBridge driver в отдельной ветке; PR и merge каждый требуют явного запроса. Только Squash and merge при разрешённом merge, no force-push. Старые rewrite разрешения исчерпаны.

Ключевые обязательства: русский, кратко/конкретно; различать наблюдения/гипотезы/предложения; проверять успех; Git status перед изменениями, сохранять чужие изменения; адресные чтения/вывод1–3к токенов, большие evidence в ignored artifacts, не повторять доказанное; минимум необходимых проверок, без лишних автотестов/тестов в продуктовую ветку. Приоритеты: надёжность → скорость/задержка → ресурсы → размер. Не делегировать без запроса. Проверять Codex usage; при <=5%remaining — recoverable state, короткий checkpoint и стоп; unavailable не оценивать. Для grilling ровно один вопрос и ожидание. Commit/push разрешённых source/docs с remote verify, без секретов/захватов/kit/credentials. WinDbg agent VM как target запрещён, старый pipe не использовать; физический target сейчас тоже исключён текущим запретом. KernelReadCapture и hidden kd с redirect запрещены.

## Рабочие копии и актуальное приложение

- Диагностический проект/checkout `C:/src/ProxyBridge-TestLab`, branch codex/checkpoint-20261007. На момент передачи: modified docs/CHAT_HANDOFF_DEVELOPMENT.md, untracked src/independent_wfp/KernelReadCapture.cs — **не читать/запускать/коммитить/удалять/перезаписывать этот .cs**, чужой handoff сохранить. Не переключать/сбрасывать checkout.
- Разработка завершена в `C:/Users/LabAdmin/.codex/worktrees/testlab-development/ProxyBridge-TestLab`, branch codex/development-functional-completion, HEAD0423cedec1d9458a82f44eac1f226797ce053956 (до добавления этого документа), remote проверен, status clean. База UI d5b51f3 сохранена. Сюда относятся современные src/trafficlab и C# engine — не диагностировать устаревший runtime из main как будто он текущий.
- VM приложение: `C:/src/ProxyBridge-TestLab/artifacts/releases/ProxyBridge-TestLab-0.3.0-local-preview.57-win-x64`, localhost5178. Пакет source592aa65f422f0691f2ccc0dda006b7d2b2f50c1d, 1702SHA verified. Отдельный VM store `%LOCALAPPDATA%/ProxyBridge-TestLab`. 2 сборки: WFP4da324e и WinDivert4.3.0. При последней проверке VM idle/admin; новое состояние проверить локально перед runtime, не переносить статус на будущее.
- VM product folders: `C:/src/ProxyBridge-TestLab/artifacts/product-builds/v4.3.0-release` и `.../driver-4da324e-combined-20261024-r1/release`. Подтверждать конкретные файлы/ревизии до выводов. SYS WinDivert SHA2568da085332782708d8767bcace5327a6ec7283c17cfb85e40b03cd2323a90ddc2; WFP5a29f6b7af37ec2a266520187e5fda304cf1526520e074c0fadeb8dc79f11cce.

## Подтверждённые данные (читать локально)

Современные docs лежат в development worktree выше:
- docs/PB_SUT_NORMAL56_AUDIT_2026-10-26.md — сохранённые экспорты, не повод подключаться к SUT.
- WinDivert attempt20261026-095445-98e2c2dc226540488f96d12d6b822c20: 33PASS/11UDP-relatedFAIL (UDPconnected/unconnected/sweep/connections, HTTP3single/sweep, QUICsingle/multiplex, DNSUDP, mixed, stability).
- UDPconnected:6750sent/2250received/4500invalid, reason DATAGRAM_FLOW_MISMATCH, wholePC CPU7.95%. ФизическийПК безKDNET, умереннаяNORMAL/LOW нагрузка. Это не простой довод о CPU перегрузке; пакетные причины ещё не локализованы.
- WFP full43PASS/1UNVERIFIEDUDP128 из-за70 непокрытыхrouteaccounting пакетов из96002; это отдельное наблюдение, не тот же root cause.
- 275exportSHA/92rawSHA и пересчёт92summary:0diff, capture/cleanup подтверждены. Корректное сохранение/арифметика не доказывает корректность wire-протокола и семантики flow-id.
- Локальная evidence: `<development-worktree>/artifacts/sut-normal56/20261026-095445-98e2c2dc226540488f96d12d6b822c20`, `artifacts/sut-normal56-analysis/analysis.json`, metric-audit.json. Исходные captures private/ignored, не коммитить/публиковать.
- docs/REPEAT_RUNS_VM56_2026-10-26.md — VM и SUT разные машины, не смешивать результаты. docs/PB_SUT_REPEAT56_AUDIT_2026-10-26.md — TCP/SFTP повторы, не доказательство UDPисправности.
- preview57 добавила отдельный фиксированный endurance2/24/48/72ч, сохранила ordinary checks; многочасовые результаты ещё не проверены. docs/LOCAL_APP_CHECKPOINT.md и docs/ENDURANCE_PREVIEW57_2026-10-26.md — текущие состояние/ограничения. Не начинать повторный аудит всей лаборатории.

## Первые различающие вопросы

Адресно найти origin/worker/relay evidence первого DATAGRAM_FLOW_MISMATCH; сравнить sent/received/invalid и фактический source/destination/flow-id/payload. Проверить UDP controls отдельно от TCP, правила CLI/их реальное применение, SOCKS5 UDP ASSOCIATE endpoint и формат datagram. Прямой UDP, явный SOCKS5 и продуктовый путь — разные controls. Исключить коллизию идентификаторов/ошибку receiver/маршрут/loopback до обвинения драйвера. Старый числовой ProxyConfigs.Port уже исправляли — не чинить повторно без проверки текущего кода. Не отключать проверки payload/route ради PASS.

## Инструменты и плагины

Использовать доступные подходящие плагины; discover через ALL_TOOLS по задаче, не весь каталог. Chat On Steroids Core — файлы/терминал/админ на VM (workdir /src, абсолютные пути); повышение прав уже разрешено для авторизованного scope, но не отменяет запреты. Core может возвращать Unattributed notice: он сам по себе не запрещает exec/edit; фактический отказ операции соблюдать, не обходить. Core write_stdin ранее отказывал по ownership: читать сохранённые logs/status, не переигрывать успешную мутацию. Обычные exec/write_stdin доступны. Background Start-Process Hidden.

GitHub plugin — первичный источник для ревизий/source/issues; Context7 — релевантная документация библиотек; Serena предпочитать если подключена; Desktop/CUA — UI при необходимости после чтения computer-use skill. Dejavu skill читать при REMINDER/BLOCKED, не обходить gate. Не менять plugin connections/permissions и не обещать недоступный инструмент: проверить availability в новом чате. Список skills наследуется из окружения, релевантный SKILL.md читать при первом применении. Credentials/DPAPI не печатать/не передавать; remotecredential SUT вообще не использовать. PowerShell rg: directory + -g, не literal wildcard paths. PythonUTF8, secrets не интерполировать в shell. Проверенные ограничения CPU: processCPU не включает полный WFP kernelcost; exclusiveSYSsampling не весьCPU; unknown не0, максимум/победителя не объявлять без измерений.

Следующий результат нового чата: начать offline анализ и дать доказанную локализацию либо конкретную недостающую границу наблюдения; затем минимальный разрешённый VM-опыт/исправление и подтверждение. Короткий диагностический checkpoint вести отдельно. Последовательность после UDP — финальный README с ограничениями сравнения, не расширять scope сейчас.
