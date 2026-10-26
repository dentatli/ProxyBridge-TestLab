# «На этом ПК» — checkpoint 26 октября 2026

Запрос адаптации нагрузки и полного сброса активной лаборатории выполнен. Установлена **preview.54**, source `bd32e3789a2506cca4c8cc7a4fd35dc7bba1961f`, 1685SHA matched. Admin **http://127.0.0.1:5178**, PID11224. Package `C:/src/ProxyBridge-TestLab/artifacts/releases/ProxyBridge-TestLab-0.3.0-local-preview.54-win-x64`. Пользователь повторно добавил WinDivert4.3/WFP4da и выполнил триSHORT/LOWпрогона; active/busy=false.

## Последний анализ пользовательских54прогонов

[Сопоставимость, числа и оставшиеся ограничения](COMPARABILITY_PREVIEW54_2026-10-26.md). WinDivert `20261026-052749-776c4521c87442989338de33ff9db4a0` и `20261026-053731-768aa20821164c6b97ac76a2114db2ff`:оба33PASS/11FAIL. WFP `20261026-054809-a2dca698c1cb4cde89891160b9b8f736`:44PASS. ВсеSHORT/LOW,44matchingpairs,138rawSHA,quality/resourcesrecompute0diff,Core1/1/cleanup/capturetrue. 29pairs проходят текущиегейты; **flow-rateCPUнеравноценен**:36сессийeach, ноWFP630656 vsWin≈130000payloadbytes из-заunbounded50msвнутри, guardэтоещёнеучитывает. 6sCPUdeltasчасто0–0.0625CPU-с, percentages/rankingнеустойчивы; нужно достаточноевремя/повторы иlow-budgetdisplayguard. Кодне меняли, новуюнагрузку не запускали.

SFTP180цикловeach/targetMET; loadedRTTfixed6MiB/s/probe15sMET, CPUПК6.62–10.49%; WFPstability8/8METсCPU≈9.34%, UDP12819273/19273/fullroute. Прежняяперегрузкаустранена дляboundedprofiles; bulkWFPостаётся≈97%CPU, этоисключениеmaximumspeed. WinUDP11failповторяютсяпрималомCPU/заданномтемпе, корневаяпричинанеустановлена. WFPkernelattributionотложен. Следующийотдельныйфикслаборатории: fixedworkpernewsession иCPUconfidence; не объявлятьвсе29пар пригоднымидлялюбогорейтинга. ОдинWFPповтор,2Win,6sокна—не24hустойчивость.

## Новые профили

[Все51сценарий: конкретные LOW/HIGH и смысл результата](USER_LOAD_PROFILES_2026-10-26.md). Method `user-workload-v1`; одинаковые заранее заданные профили для WinDivert/WFP. LOW/HIGH: умеренно активная/интенсивная работа, синтетическая модель, не статистика реальных пользователей. Прикладные2соединения; SFTP15/25циклов/с на каждое, HTTP6/10, DNS3/5, прочее в таблице. TCPфон6/10МиБ/с в каждом направлении, probe15/25с; stability/soak поинтервально50/100/125/100%TCP, UDP постоянен. UDPмасштабирование25pps/flow, max128/192flows. Максимальная TCPскорость явно отдельная/неограниченная, может насыщатьстенд.

Byte/session targets включены вloadquality; единицы не смешиваются. 51ID/10групп, SHORT/NORMAL/LONG, saved-suiteimport/covers сохранены. Новые/старые численно не приравниваются. Remote306планов идентичны прежним. Strict exchange/route/capture/cleanup не ослаблены, WFPkernelmeasurement по-прежнему отложен; продуктовый код/драйверы/trust/BCD/systemproxy не менялись.

## Сброс и сохранённые свидетельства

По прямому запросу пользователя старый store целиком перенесён в **`C:/Users/LabAdmin/AppData/Local/ProxyBridge-TestLab-archive-20261026T050512Z`**; там прежние config/traffic-lab/evidence/jobs, включая оба последних fullattempt. Не публиковать архив/ключи. На момент сброса новый `%LOCALAPPDATA%/ProxyBridge-TestLab` был пуст в смысле истории/каталогов; теперь содержит2сборки и3пользовательскихпрогона54. Browser только testlab-* этого origin сброшен по новой storeidentity; обычный upgrade без explicitreset сохраняет browserchoices. Активных проверок нет, busy=false, ProxyBridgeDrvStopped,0native/Coreprocesses иlisteners42501/2/3,stderrпуст. Frozenkits/captures и старые immutablepackages сохранены.

Предыдущие полные53теперьвarchive: WinDivert `20261025-160707-5e2eaa8c397e4115bb8715943f2873db`33PASS/11FAIL; WFP `20261025-164617-d189642ae3a143cd91f4e742b2fe0500`43PASS/1UNVERIFIED. [Разбор](FULL_RUN_COMPARABILITY_2026-10-26.md):44matchingpairs/26rankable,92rawSHA, UDP128 partial2716/383945, WFPbulkCPU≈100%, SFTPunderload. Корневаяпричина продукта не установлена.

## Проверки / evidence

306localplansвалидны и306remoteplansравныпрежним;102actualJSописанияLOW/HIGH/RU иseparateunits; browser-storeexplicitreset/changedstore/upgradepreservation/isolationPASS. C#build0warning/error, Pythoncompile,JSsyntax,diffcheckPASS. Existingcontrollergate14LOW/HIGHcases:tcp-rtt,udp-connected,loaded-rtt,flow-rate,app-sftp,app-smtps,mixed — всеexchange/route/windowsPASS/loadMET, фазовыеCPUсчётчики, signednativeorigin иprivateinputcleanupPASS. Sumraw165.96s (<5min); **ProductCoreне запускался**. `artifacts/engine-migration/controller-1792990915641/user-load-result.json`, `C:/src/ProxyBridge-TestLab/artifacts/user-load-component.log`. Новыхtrackedавтотестовнет. Browser54emptyhistory/builds/suites,2loadoptions,actualprofilelabels проверены. Full54/HIGHwholequeue/soak не запускались.

## Продолжение / ограничения

Пользовательские парные54прогоны проанализированы выше. Не запускать full автоматически и не сравнивать53/54 какодинаковыеусловия. Kernelattribution ипричиныWinDivertUDP/WFPpartial отдельно. Данные старых анализов искать вarchive, неактивномtraffic-lab. Успешныепроверки безновыхвходов не повторять.

Worktree `C:/Users/LabAdmin/.codex/worktrees/testlab-development/ProxyBridge-TestLab`, branch `codex/development-functional-completion`; базаd5b51f3 сохранена. Main `C:/src/ProxyBridge-TestLab`, branch `codex/checkpoint-20261007`: чужиеhandoffchange/KernelReadCapture.csне трогать/нечитать. Последниелимитыprimary23%used/weekly34%used; ≤5%remaining — checkpoint/стоп. Commit/pushбезforce/privateartifacts/PR. Relevant history: [методика53](COMPARISON_QUALITY_2026-10-25.md), [движокC#](CSHARP_TRANSPORT_ENGINE_2026-10-25.md).
