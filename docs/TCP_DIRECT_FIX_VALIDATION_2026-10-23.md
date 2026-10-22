# TCP DIRECT: минимальное исправление и проверка — 2026-10-23

Причина: `prepare_tcp_connection` определял DIRECT, но не передавал action
в `CONNECTION_CONFIG`. `connection_handler` всегда выбирал proxy; config0
означает первый доступный proxy. Это отдельный дефект Core, не исторический
отказ получения WFP redirect context и не ошибка UDP packet channel.

## Изменение

Ветка `codex/tcp-direct-route` создана непосредственно от fork `driver`
`b3596272a8dc8898790b016d1e4c488c2fdc917d`. UDP-ветка не включена.
Commit `340bdc839bed3c02d75dceb996cee68f39ecf045`: два файла, 51 добавленная
строка. Внутренний CONNECTION_CONFIG сохраняет RuleAction; DIRECT создаёт
IPv4/IPv6 socket и соединяется с исходным destination с 30-second timeout.
После подключения используется прежний byte pump. Ошибка DIRECT закрывает
соединение без proxy fallback. PROXY и BLOCK сохраняют прежнее поведение;
неизвестный action отклоняется. Legacy conntrack явно инициализируется PROXY.
Driver, proxy-config lookup, public API и UDP не изменены. Тестов в продукт
не добавлено. Это DIRECT через локальный Core relay, а не обход relay в kernel:
исходный source port приложения не сохраняется.

## Сборка и физический PB-SUT

Release Core собран без предупреждений/ошибок. SHA256:
`ad514e88f8b7eb2bf2f63f94f7ad724b963a6898de69033839cf36e3a86ee08c`.
Build receipt: `artifacts/diagnostics/tcp-direct-20261023-r1/build-receipt.json`.
Источник чистый, commit340bdc8. SYS не пересобирался/не переустанавливался;
использован исходный пакет на PB-SUT, SHA256
`3e5c3c709ee8c8800628f04b5550f3a82377deb264b045ab2f2ccbab3fd8fb4c`.

Для штатного Lab используется ранее проверенный native CLI из735b9fa как
harness, SHA256 `be95c16e2b837551e5d7a3382c0f04eff43d3fcb2d50f79d461e9fd67b227354`.
Это не сборка CLI текущей TCP-ветки: CLI здесь не менялся/не проверялся заново.
Версии/hashes зафиксированы в input.env и product-build evidence.

Штатные TCP SOCKS5 и HTTP probes: payload DIRECT/PROXY проверен; PROXY
`ROUTE_OBSERVED`, socket path подтверждён. DIRECT больше не вызывает proxy,
но штатный gate остаётся `INCONCLUSIVE`: требует совпадение client local port
с receiver peer port и не учитывает прямое соединение из Core relay.
Исходные receipts и критерий Lab не исправлялись/не ослаблялись.
Первый trial r1 остановился на этом результате; состояние восстановлено.
В r2 изолированный runner сохранил INCONCLUSIVE и выполнил дополнительный gate.
Это не означает «весь TestLab PASS»; общий статус
`PASS_WITH_LAB_DIRECT_INCONCLUSIVE`.

Дополнительная игнорируемая диагностическая fixture через public Core API:
**11/11 verified**, каждый успешный обмен с payload8192 bytes:

- IPv4 127.0.0.1 и IPv6 ::1: DIRECT достигает origin без SOCKS-соединений;
  PROXY выполняет SOCKS CONNECT и достигает origin; BLOCK не достигает
  ни proxy, ни origin (6 случаев).
- Отказ DIRECT destination при доступном proxy не вызывает proxy fallback (1).
- DIRECT IPv4/IPv6 работает после закрытия proxy listener (2).
- Отказ DIRECT destination IPv4/IPv6 при недоступном proxy закрывает клиента (2).

Direct rules fixture намеренно содержат валидный ненулевой config ID: действие
выбирается явно, не по номеру конфигурации. Для IPv4 accepted-redirect logs
подтверждают PID/action/destination. IPv6 проходит реальный driver relay path;
соединения origin и SOCKS события считает подконтрольная native fixture.
Stop=1, threads_alive=0, forced_cleanup=[], exit0.

## Восстановление и границы

Оба trial: baseline SYS hash совпадает; service Stopped/Disabled, devnode
problem32, restored=true. Remote wrapper COLLECTED, identity_confirmed=true,
cleanup_errors=[]; client WinRM/TrustedHosts восстановлены. Установка пакета,
trust, BCD, системный proxy и ProgramFiles файлы не менялись. WinDbg не запускался.

Evidence: `artifacts/diagnostics/tcp-direct-target-20261023-r1` и `...-r2`;
fixture/preparation: `tcp-direct-20261023-r1/r2`; ledger обоих captures:
`artifacts/diagnostics/tcp-direct-evidence-ledger-20261023-r1.json`.
Raw captures/fixtures остаются ignored и не входят в Git.

Проверены локальные TCP пути, не внешний сервер, длительная нагрузка,
link-local IPv6 scope, half-close semantics или 30-second blackhole deadline.
Скорость/ресурсы этого исправления не измерялись. UDP regression не повторялся:
в этой ветке нет UDP patch и его код не менялся. Исправление TestLab DIRECT
socket-owner gate остаётся отдельной работой; сохранение source port не заявляется.
В `driver` изменений нет, PR/merge не создавались.
