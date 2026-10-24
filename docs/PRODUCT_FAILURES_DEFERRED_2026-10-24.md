# Отложенные проблемы продукта WFP

По указанию пользователя от24октября: продуктовые проблемы зафиксировать и разбирать отдельно. В этом scope не менять драйвер/Core, не проводить новые product/WinDbg trials. Первичная доказательная база: [WFP full50](WFP_FULL50_ANALYSIS_2026-10-24.md), попытка `20261024-103903-840806ad7ea9436b9b94a19e533b0c72`, preview40,35PASS/15FAIL, обе очистки успешны.

Комплект: Core/CLI b3596272a8dc8898790b016d1e4c488c2fdc917d, baseline SYS SHA3e5c3c709ee8c8800628f04b5550f3a82377deb264b045ab2f2ccbab3fd8fb4c. SYS сохранён из прежней подготовки, не объявлять новой сборкой b359627. Raw evidence неизменны в `%LOCALAPPDATA%/ProxyBridge-TestLab/traffic-lab/<attempt>`, производные сводки ignored `artifacts/wfp-full50-review` development worktree.

| ID | Проблема | Подтверждение / граница вывода |
|---|---|---|
| P1 | Connected/wildcard UDP: lookup/назначение driver→relay |5 сценариев не доставляют UDP до origin; прежний driver-only опыт на том же SYS подтвердил wildcard mismatch/перезапись назначения. Текущий прогон не повторял IOCTL опыт.|
| P2 | UDP replies: ownership и прозрачность исходного endpoint в Core |11496 ответов отправлены proxy;3468 подтверждены,8028 invalid. Core выбирает most-recent client по одному remote ip:port. DNS также4 replies,3 timeout/1 wrong source. Нужен согласованный driver/Core контракт, не произвольная доставка winner.|
| P3 | SSH/SFTP: искажённый original TCP destination |Worker10916/14684, требуются42516/42517, capture показывает51192…/52120… и8 SOCKS reply2. Подтверждена граница driver/Core, точный виновный модуль ещё не установлен. Не расширять allowlist стенда.|
| P4 | QUIC/HTTP3: неожиданный UDP source |5 сценариев/20flows source-invalid до handshake. Продуктовая атрибуция предварительная: preview40 не сохранил actual sender. Повторить после исправления диагностических данных лаборатории; проверки source/TLS не отключать.|

Отдельно **не атрибутированный** отказ flow-rate:1 из747 соединений, failed sample не сохранён старой лабораторией. Не называть дефектом драйвера до появления evidence. Новая лаборатория должна сохранить отказ после sample cap.

Для отдельного чата начинать с этого регистра и первичного отчёта. Прежние driver-only результаты находятся в основном checkout `C:/src/ProxyBridge-TestLab/docs/UDP_FLOW_IDENTITY_ROOT_CAUSE_2026-10-22.md` и `UDP_LOCAL_MATRIX_CURRENT_DRIVER_2026-10-22.md`. Они не разрешают повторять старые trials автоматически. `driver` — пользовательская integration branch; PR/merge требуют отдельного указания. `codex/tcp-direct-route` и новая продуктовая реализация здесь не проверялись.
