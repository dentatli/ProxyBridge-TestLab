# «На этом ПК» — checkpoint 26 октября 2026

Запрос адаптации нагрузки и полного сброса активной лаборатории выполнен. Установлена **preview.54**, source `bd32e3789a2506cca4c8cc7a4fd35dc7bba1961f`, 1685SHA matched. Admin **http://127.0.0.1:5178**, PID11224. Package `C:/src/ProxyBridge-TestLab/artifacts/releases/ProxyBridge-TestLab-0.3.0-local-preview.54-win-x64`. Browser оставлен на «Сборки»: комплект не выбран, сохранённых сборок нет.

## Новые профили

[Все51сценарий: конкретные LOW/HIGH и смысл результата](USER_LOAD_PROFILES_2026-10-26.md). Method `user-workload-v1`; одинаковые заранее заданные профили для WinDivert/WFP. LOW/HIGH: умеренно активная/интенсивная работа, синтетическая модель, не статистика реальных пользователей. Прикладные2соединения; SFTP15/25циклов/с на каждое, HTTP6/10, DNS3/5, прочее в таблице. TCPфон6/10МиБ/с в каждом направлении, probe15/25с; stability/soak поинтервально50/100/125/100%TCP, UDP постоянен. UDPмасштабирование25pps/flow, max128/192flows. Максимальная TCPскорость явно отдельная/неограниченная, может насыщатьстенд.

Byte/session targets включены вloadquality; единицы не смешиваются. 51ID/10групп, SHORT/NORMAL/LONG, saved-suiteimport/covers сохранены. Новые/старые численно не приравниваются. Remote306планов идентичны прежним. Strict exchange/route/capture/cleanup не ослаблены, WFPkernelmeasurement по-прежнему отложен; продуктовый код/драйверы/trust/BCD/systemproxy не менялись.

## Сброс и сохранённые свидетельства

По прямому запросу пользователя старый store целиком перенесён в **`C:/Users/LabAdmin/AppData/Local/ProxyBridge-TestLab-archive-20261026T050512Z`**; там прежние config/traffic-lab/evidence/jobs, включая оба последних fullattempt. Не публиковать архив/ключи. Новый `%LOCALAPPDATA%/ProxyBridge-TestLab` пуст в смысле истории/каталогов: API builds/suites/history/launches=[]; selection=null, unreadable=0. Browser только testlab-* этого origin сброшен по новой storeidentity; обычный upgrade без explicitreset сохраняет browserchoices. Активных проверок нет, busy=false, ProxyBridgeDrvStopped,0native/Coreprocesses иlisteners42501/2/3,stderrпуст. Frozenkits/captures и старые immutablepackages сохранены.

Предыдущие полные53теперьвarchive: WinDivert `20261025-160707-5e2eaa8c397e4115bb8715943f2873db`33PASS/11FAIL; WFP `20261025-164617-d189642ae3a143cd91f4e742b2fe0500`43PASS/1UNVERIFIED. [Разбор](FULL_RUN_COMPARABILITY_2026-10-26.md):44matchingpairs/26rankable,92rawSHA, UDP128 partial2716/383945, WFPbulkCPU≈100%, SFTPunderload. Корневаяпричина продукта не установлена.

## Проверки / evidence

306localplansвалидны и306remoteplansравныпрежним;102actualJSописанияLOW/HIGH/RU иseparateunits; browser-storeexplicitreset/changedstore/upgradepreservation/isolationPASS. C#build0warning/error, Pythoncompile,JSsyntax,diffcheckPASS. Existingcontrollergate14LOW/HIGHcases:tcp-rtt,udp-connected,loaded-rtt,flow-rate,app-sftp,app-smtps,mixed — всеexchange/route/windowsPASS/loadMET, фазовыеCPUсчётчики, signednativeorigin иprivateinputcleanupPASS. Sumraw165.96s (<5min); **ProductCoreне запускался**. `artifacts/engine-migration/controller-1792990915641/user-load-result.json`, `C:/src/ProxyBridge-TestLab/artifacts/user-load-component.log`. Новыхtrackedавтотестовнет. Browser54emptyhistory/builds/suites,2loadoptions,actualprofilelabels проверены. Full54/HIGHwholequeue/soak не запускались.

## Продолжение / ограничения

Пользователь заново добавляет комплекты и делает парные прогоны на54. Не запускать full автоматически и не сравнивать53/54 какодинаковыеусловия. Kernelattribution ипричиныWinDivertUDP/WFPpartial отдельно. Данные старых анализов искать вarchive, неактивномtraffic-lab. Успешныепроверки безновыхвходов не повторять.

Worktree `C:/Users/LabAdmin/.codex/worktrees/testlab-development/ProxyBridge-TestLab`, branch `codex/development-functional-completion`; базаd5b51f3 сохранена. Main `C:/src/ProxyBridge-TestLab`, branch `codex/checkpoint-20261007`: чужиеhandoffchange/KernelReadCapture.csне трогать/нечитать. Последниелимитыprimary23%used/weekly34%used; ≤5%remaining — checkpoint/стоп. Commit/pushбезforce/privateartifacts/PR. Relevant history: [методика53](COMPARISON_QUALITY_2026-10-25.md), [движокC#](CSHARP_TRANSPORT_ENGINE_2026-10-25.md).
