# Локальная лаборатория — checkpoint, 28 октября 2026

## Очистка диска VM — 28 октября

По запросу пользователя очищена только VM, PB-SUT не подключали. Было29.39ГиБ свободно, стало60.76ГиБ; освобождено≈31.41ГиБ. Удалены66 старых локальных app-пакетов и31 папка временных файлов VisualStudioInstaller (≈18.79ГиБ). Сохранены preview56/62/63; все1698/1704/1704 packageSHA совпали. MANIFEST/SHA256SUMS удалённых пакетов сохранены отдельно. Старые61/60 и остальные previewпакеты удалены, не ссылаться на них как на доступный rollback. Baseline56 и rollback62 сохранены.

177 крупных неактивных ETL/XML/JSON/JSONL/log-файлов в artifacts/diagnostics иlocal-route сжаты штатной NTFScompression (≈12.63ГиБ). SHA256до/после каждого файла совпали; bytes/paths сохранены, evidence/frozenkits не удалялись/не refreeze. Private logs/results/captures, исходники/worktrees, установленныйSDK/драйверы, MSI/VS repaircache исистемные настройки не трогали. Приложение/тесты не запускали; UI перед очисткой не отвечал, активных UI/installerпроцессов/ссылокscheduledtasks настарые пакеты не обнаружено.

Ignored evidence: artifacts/disk-cleanup-20261028/{inventory.json,details.json,deletion-plan.json,deletion-result.json,retired-package-manifests,compression-plan.json,compression-result.json,compact-pilot-result.json,summary.json}. Последующие замеры учитывать: NTFScompressed logicalsize не равно занятому месту. Для полного отката сжатия есть NTFSdecompression; она потребует свободного места. Пакеты/программы за пределами подтверждённых старых app/tempдиректорий не удалялись.

## Перенос в main завершён — 28 октября

По запросу пользователя main продвинута fast-forward с a85a370 на20d25f5 (222коммита), удалённая SHA подтверждена. codex/development-functional-completion сохранена, история не переписывалась, продуктовый ProxyBridge не менялся. Предварительно: Gitclean,mainancestor,467изменённыхфайлов; нет найденных private capture/key/DPAPI/archive paths, private-key material/token patterns или conflict markers. Единственное замечание diff--check — старая пустая строка в EOF KernelResources.cs, не функциональный дефект. Повторные тесты/развёртывание не выполнялись: используются подтверждённые H2 WFP/WinDivert62 и VM63 UI/startup/SHA. Эта запись фиксируется в обеих ветках. GitHub Release/тег/бинарный архив не публиковались; установленные VM63 иSUT62 не менялись. Следующие действия — по запросу пользователя.

## Последний прогон принят — WinDivert H2

[Аудит28октября](PB_SUT_WINDIVERT_H2_62_AUDIT_2026-10-28.md):attempt20261027-160729-21277d8554704c44859131c503c176d4,WinDivert4.3.0,COMPLETE. Полные7200с,211/211работ обмен/маршрутPASS,TCP14400,UDP36000/36000безпотерь,QUIC16/16closePASS(max2.422с),DIRECT/BLOCK464/464независимо пересчитаны. Cleanup/off_aftertrue,driverStopped/namesabsent/productprocesses0,Start/Stop1/1. SHA9файлов/journal443записи/summary0diff. Оба подхода теперь прошли H2 наruntime62. Новые запуски/перезапуски/обновления/merge не выполнялись; WebAPI SUT не отвечал, прочитаны terminal files, приложение не запускали. EN/RU comparison results обновлены. Обычные UDP-проблемы и полный расход ядра остаются отдельными вопросами.

## Удалённый узел временно скрыт

По запросу пользователя из lab-mode удалён remote option. Старый browser choice остаётся на local; сохранённые/импортированные remote-наборы применяют доступный local без перезаписи исходной записи. Backend remote/history не удалены. Node syntax и одноразовая проверка настоящих restore/apply функций с local-only options PASS; новых постоянных автотестов, сетевых нагрузок и сборок не было. README EN/RU уточнены. Изменение установлено только на VM в preview.63; PB-SUT оставлен на preview.62.

## Документация к выпуску

Основной язык двух документов — английский; русские версии [README.ru.md](../README.ru.md) и [COMPARISON_RESULTS.ru.md](COMPARISON_RESULTS.ru.md) связаны переключателями языка. Русский текст сохранён, числовые таблицы сверены. По согласованию пользователя обновлён [README](../README.md): проект, требования, установка готового пакета и быстрый запуск. Результаты отдельно в [COMPARISON_RESULTS.md](COMPARISON_RESULTS.md): повторные обычные измерения preview.56 и длительные результаты с явными версиями/ограничениями. GitHub Releases пуст; отсутствующий архив не обещается. Source/app/пакеты не менялись, новых запусков не было. Документация включена в main. WFP и WinDivert H2 на preview.62 приняты; следующий шаг — по запросу пользователя.

## Сейчас

**PB-SUT:** после нового запроса «Посмотри последний прогон» выполнен только read-only аудит завершённого WinDivert H2. Прежний запрет вмешиваться во время проверки соблюдён. Последняя установка preview.62 сохранена, новые нагрузки/перезапуски не разрешать автоматически. WebAPI при аудите не ответил; runtime не запускали. Следующий шаг — по запросу пользователя.

**VM обновлена до preview.63**, source `ae312ecfa3840c18dfdf4144c7fec660941b7199`: `C:/src/ProxyBridge-TestLab/artifacts/releases/ProxyBridge-TestLab-0.3.0-local-preview.63-win-x64`, localhost5178. App admin/idle, обе сборки и14 отчётов сохранены/unreadable0. Все1704 SHA проверены до переключения; HTTP подтверждает новый root, отсутствие remote option и local fallback для наборов. После очистки диска старый preview.61 удалён; rollback — preview.62. Продукт/его драйвер/системные настройки не меняли, тесты не запускали. Evidence ignored: artifacts/endurance-check/publish63.log/.exit, update-vm63.ps1, vm63-ready.json, vm63-app.log/.err. Предыдущее отклонение подготовки VM62 не обходилось: новое обновление63 выполнено по отдельному прямому запросу пользователя.

## Исправление и проверка62

[Подробности](ENDURANCE62_POLICY_RPC_FIX_2026-10-27.md): POLICY_BEGIN очищает WFP callback cache перед DIRECT/BLOCK без изменения правил/соединений. Native FINISHED/FAILED остаётся до ACK, повтор чтения ограничен тремя попытками, workload не пересоздаётся. Первая RPC-ошибка/операция/status/errno сохраняются; неизвестный результат остаётся остановкой, не PASS.

C#/C build, Python compilation, 2 policy guards и 3 необходимых RPC regression-контракта PASS. Полный native gate на VM не объявлять PASS: первая попытка прошла прежние35, но новый harness ошибочно сравнивал mutable snapshot; после исправления повтор остановлен старым churn TCP_TRANSPORT_FAILED. Связь этого отказа с загруженным WinDivert не установлена, gate не ослаблялся.

**Реальная WFP приёмка PB-SUT PASS:** сокращённый70с цикл (72.313с с завершением), все6 apps, persistent TCP/UDP, bulk/churn, 9×4 policy checks; ещё3×4 свежих policy checks после цикла; отрицательный DIRECT/fallback BLOCK guard PASS. Отмена3.125с, cancelled=true/complete=false, оба native hosts idle. Core cleanup=true/forced_stop=false. Итог: ProxyBridgeDrv Stopped, устройство отключено/problem22, core_hosts0. SHA/41 записей журнала сверены. Продуктовые DLL/SYS, BCD/trust/установка не менялись. WinRM/TrustedHosts восстановлены. Evidence: ignored artifacts/endurance-check/sut-functional62-read-r1/target-files, package62-verified.json, ack62.log.

## Последний пользовательский H2 — принят

[WFP62 аудит](PB_SUT_WFP_H2_62_AUDIT_2026-10-27.md): attempt20261027-131017-401aef43458d48109dc0710697f2a05b, COMPLETE. 7200с нагрузки (7204.422с с завершением),212/212 работ обмен/маршрутPASS,464/464 DIRECT/BLOCK независимо пересчитаны. TCP14400 обменов,UDP36000/36000 без потерь;6 apps×16окон,QUIC close16/16. PID/ruleIDs стабильны,CoreStart/Stop1/1,все cleanup true/device disabled/службаStopped. Старые callback FAIL и часовая остановка не повторились. Control recovery не требовалось; причина исторического RPC отказа остаётся неизвестной. SHA9файлов/journal444записи/console prefix и summary0diff подтверждены. Полный console ограничен prefix4MiB, stage journal полный. Никаких новых запусков/перезапусков/изменений продукта не выполнялось. Следующий шаг — по запросу пользователя; автоматически H2/24ч не запускать. Ресурсы ядра WFP этим не измерены.

## Последние длительные результаты

- [WFP61 H2 аудит](PB_SUT_WFP_H2_61_AUDIT_2026-10-27.md):3596.985/7200с,103 завершённых PROXY операции PASS,7 QUIC close PASS. Policy поведение232/232 ожидаемое,224 callback unverified из-за дедупликации; это исправлено62. Остановка persistent TCP result UNKNOWN, исходная RPC-причина отсутствует. Последние live TCP7111/7111,UDP17776/17776; финальной сверки нет. Cleanup подтверждена.
- [WinDivert60 H2 аудит](PB_SUT_WINDIVERT_H2_60_AUDIT_2026-10-27.md):7200с,464/464 policy PASS; один QUIC close FAIL при полном обмене. [Таймер исправлен61](QUIC_CLOSE_TIMER_PREVIEW61_2026-10-27.md), подтверждён реальным Core и последующим WFP QUIC ожиданием4.203с.
- [Фиксированный профиль60](ENDURANCE60_POLICIES_2026-10-27.md): H2/H24/H48/H72, эксклюзивный выбор, без load selector; PROXY + периодические DIRECT/BLOCK TCP/UDP,6 apps, append-only journal/ограниченная сводка. Не обещать все IPv6/domain/UDP ownership варианты или полный CPU/RAM ядра; ETW в soak выключен.

## Ограничения и продолжение

Worktree `C:/Users/LabAdmin/.codex/worktrees/testlab-development/ProxyBridge-TestLab`, branch `codex/development-functional-completion`, базаd5b51f3 сохранена. Main `C:/src/ProxyBridge-TestLab`: чужие handoff/KernelReadCapture.cs не трогать/не читать. Не менять frozen kits/captures/archives. Не диагностировать продукт без отдельного запроса. Без subagents/PR/force-push/private artifacts. Usage: последние primary0%used/weekly54%used, проверять и останавливаться при<=5%remaining.

UDP WinDivert — отдельный чат `01a17935-ca69-7152-8f03-9c9bb8600e7c`, [VM-only handoff](WINDIVERT_UDP_VM_HANDOFF_2026-10-26.md). Его запрет PB-SUT относится к той диагностике; здесь SUT обновляется по запросам пользователя о длительном режиме. После приёмки — [итоговый README и границы сравнения](FINALIZATION_AND_NEXT_SCOPE_2026-10-26.md).
