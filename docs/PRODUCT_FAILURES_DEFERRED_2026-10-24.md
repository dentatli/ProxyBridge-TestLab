# Отложенные проблемы продукта WFP

По указанию пользователя от24октября: продуктовые проблемы зафиксировать и разбирать отдельно. В этом scope не менять драйвер/Core, не проводить новые product/WinDbg trials. Первичная доказательная база: [WFP full50](WFP_FULL50_ANALYSIS_2026-10-24.md), попытка `20261024-103903-840806ad7ea9436b9b94a19e533b0c72`, preview40,35PASS/15FAIL, обе очистки успешны.

Комплект: Core/CLI b3596272a8dc8898790b016d1e4c488c2fdc917d, baseline SYS SHA3e5c3c709ee8c8800628f04b5550f3a82377deb264b045ab2f2ccbab3fd8fb4c. SYS сохранён из прежней подготовки, не объявлять новой сборкой b359627. Raw evidence неизменны в `%LOCALAPPDATA%/ProxyBridge-TestLab/traffic-lab/<attempt>`, производные сводки ignored `artifacts/wfp-full50-review` development worktree.

| ID | Проблема | Подтверждение / граница вывода |
|---|---|---|
| P1 | Connected/wildcard UDP: lookup/назначение driver→relay |5 сценариев не доставляют UDP до origin; прежний driver-only опыт на том же SYS подтвердил wildcard mismatch/перезапись назначения. Текущий прогон не повторял IOCTL опыт.|
| P2 | UDP replies: ownership и прозрачность исходного endpoint в Core |11496 ответов отправлены proxy;3468 подтверждены,8028 invalid. Core выбирает most-recent client по одному remote ip:port. DNS также4 replies,3 timeout/1 wrong source. Нужен согласованный driver/Core контракт, не произвольная доставка winner.|
| P3 | SSH/SFTP: искажённый original TCP destination |Worker10916/14684, требуются42516/42517, capture показывает51192…/52120… и8 SOCKS reply2. Подтверждена граница driver/Core, точный виновный модуль ещё не установлен. Не расширять allowlist стенда.|
| P4 | QUIC/HTTP3: неожиданный UDP source |В пользовательском41 full50 все20flows получили actual127.0.0.1:34011 вместо expected42521/42520; capture подтверждает product relay34011. DNS имеет тот же неверный source вместо42515. Endpoint mismatch подтверждён, внутренний kernel/Core механизм отдельно не исследован; source/TLS checks не отключать.|

Отдельно **не атрибутированный** отказ flow-rate:1 из747 соединений, failed sample не сохранён старой лабораторией. Не называть дефектом драйвера до появления evidence. Новая лаборатория должна сохранить отказ после sample cap.

Обновление: [пользовательский41 full50](PREVIEW41_FULL50_VALIDATION_2026-10-24.md), `20261024-124933-0f41ea6ddd64496f8206634cbdaf39e1`,36PASS/14FAIL/обеcleanuptrue. Flow-rate967/967, прежний одиночный отказ не повторился. P2:11298 UDP replies приняты с неправильного source34011,8226 имеют корректную HMAC, но чужой flow_id;3072 own-flow replies такжеwrong-source. P3: worker6204/11532, dest56118…/62474… вместо42516/17,8reply2. Эти новые сведения собраны без новых агентских runtime trials; продукт не исправлялся.

Для отдельного чата начинать с этого регистра и первичного отчёта. Прежние driver-only результаты находятся в основном checkout `C:/src/ProxyBridge-TestLab/docs/UDP_FLOW_IDENTITY_ROOT_CAUSE_2026-10-22.md` и `UDP_LOCAL_MATRIX_CURRENT_DRIVER_2026-10-22.md`. Они не разрешают повторять старые trials автоматически. `driver` — пользовательская integration branch; PR/merge требуют отдельного указания. `codex/tcp-direct-route` и новая продуктовая реализация здесь не проверялись.

## Проверка нового интегрированного комплекта4da324e

Пользовательский run `20261024-172320-3d3cb22ba46c4d29accb977fe0128a49`:13 из14 ранее проблемных сценариев PASS, обеcleanuptrue. Единственныйudp-connections FAILна32flows воспроизведён **без продукта** из-за receive buffer/служебныхизмерений лабораторногоorigin; увеличениетолькоприёмногобуферадо4MiBвкомпонентеконтролядало91793/91793. [Доказательства и ограничения](UDP32_LAB_RECEIVER_ANALYSIS_2026-10-24.md). Поэтому историческиеP1–P4 старогоb359 нельзя выдавать за текущие неподтверждённые дефекты4da324e. Полный50/128flows нового комплекта этим subset не аттестованы; product source исправлялся в отдельном чате, здесь только анализ лаборатории.

## Лаборатория44: дальнейшая атрибуция UDP stress

[Общийbuffer/контрольпригодностистенда](LOCAL_UDP_BUFFER_FIX_2026-10-24.md):WFP4da324e на32flows безпотерь,128 explicit-SOCKScontrol с отключённымиproductrules тоже теряетпакеты. Такойрезультатпродукта теперьUNVERIFIED,а неdriverFAIL/PASS. WinDivert4.3 продолжаетподтверждённоотдаватьчужиеflowна8клиентах;этотреальныйFAILне переклассифицируется. Обе проверкиимели одинаковыйsignedoriginbuffer4194304 и штатнуюочистку. Sourceпродукта/SYSне менялись. Это не новыйfull50/полнаяаттестацияHIGHпрофиля.
