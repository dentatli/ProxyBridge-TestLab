# «На этом ПК» — checkpoint 26 октября 2026

Текущая версия **preview.55**, source `d2604ae14cfe178995823c36a51903abeb94a395`,1685SHA matched, admin **http://127.0.0.1:5178**. Package `C:/src/ProxyBridge-TestLab/artifacts/releases/ProxyBridge-TestLab-0.3.0-local-preview.55-win-x64`. Store54сохранён:2сборки/3fullreports плюс2новыхкороткихflowchecks; история не сбрасывалась.

## Компактная таблица и фиксированный TCPсеанс

[Исправления, полное evidence и ограничения](FIXED_SESSION_COMPACT_2026-10-26.md). Metricrow66→47.5px,group50→30,stickyheaders/expand/4columns сохраняются. Nativeflow-rateтеперь1verified64B echo насеанс вместоunbounded50ms; SHORTLOW36sessions/2304Bнаправление, HIGH60/3840. Existingcontract35PASSсновымиassertsC#→Pythondirect/proxy, cancellation/falsePASS. ActualJS CPUbudget/percent/memory/old-vs-fixed и132реальныхrenderingsPASS. Новыхотдельныхtrackedавтотестовнет.

Method `user-workload-v2-fixed-session`, fixedsession1/64 вphaseworkloadprofiles; старыйflow-rateне получает рейтингравнойработы. ПриclientCPUbudget<0.25CPU-с либоmissing не подсвечиватьCPU/CPUcostпобедителя и не выводитьrelative%; абсолютныепоказания/tooltipостаются. ЭтоUIpolicyнеstatisticaltest. «Быстро»6sчастонедостаточно; «Обычно»30s/«Долго»120sпомогают,ноне гарантируют информативныйbudget, нужныповторы. Длительностиавтоматическинеувеличивали; WFPkernelmeasurementотложен.

ФинальнаяmatchedflowSHORTLOW×2за79.58s:WFP `20261026-063834-feffe5256c434166941c656985586d31`,Win `20261026-063915-37ef3b4e8aaa42348adf2f617213aebe`:обаCOMPLETE/36sessions/2304tx=2304rx,loadMET/fullroute,Core1/1,capture/cleanuptrue. `artifacts/fixed-session55-proof.json`, `artifacts/engine-migration/fixed-session-smoke-1792996714631236300.json`. Финальноactive/busyfalse,ProxyBridgeDrvStopped,0native/Corelisteners42501/2/3,stderrпуст. Full/HIGH/soakне запускали. Сравниваемыеfull54столбцысохранены; screenshot `artifacts/compact-comparison55.png`.

## Последний анализ пользовательских54прогонов

[Сопоставимость, числа и оставшиеся ограничения](COMPARABILITY_PREVIEW54_2026-10-26.md). WinDivert `20261026-052749-776c4521c87442989338de33ff9db4a0` и `20261026-053731-768aa20821164c6b97ac76a2114db2ff`:оба33PASS/11FAIL. WFP `20261026-054809-a2dca698c1cb4cde89891160b9b8f736`:44PASS. ВсеSHORT/LOW,44matchingpairs,138rawSHA,quality/resourcesrecompute0diff,Core1/1/cleanup/capturetrue. 29pairs проходят текущиегейты; **flow-rateCPUнеравноценен**:36сессийeach, ноWFP630656 vsWin≈130000payloadbytes из-заunbounded50msвнутри, guardэтоещёнеучитывает. 6sCPUdeltasчасто0–0.0625CPU-с, percentages/rankingнеустойчивы; нужно достаточноевремя/повторы иlow-budgetdisplayguard. Кодне меняли, новуюнагрузку не запускали.

SFTP180цикловeach/targetMET; loadedRTTfixed6MiB/s/probe15sMET, CPUПК6.62–10.49%; WFPstability8/8METсCPU≈9.34%, UDP12819273/19273/fullroute. Прежняяперегрузкаустранена дляboundedprofiles; bulkWFPостаётся≈97%CPU, этоисключениеmaximumspeed. WinUDP11failповторяютсяпрималомCPU/заданномтемпе, корневаяпричинанеустановлена. WFPkernelattributionотложен. Эти два замечания исправлены в55выше; статистическаяуверенностьвсёещётребуетповторов; не объявлятьвсе29пар пригоднымидлялюбогорейтинга. ОдинWFPповтор,2Win,6sокна—не24hустойчивость.

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

Worktree `C:/Users/LabAdmin/.codex/worktrees/testlab-development/ProxyBridge-TestLab`, branch `codex/development-functional-completion`; базаd5b51f3 сохранена. Main `C:/src/ProxyBridge-TestLab`, branch `codex/checkpoint-20261007`: чужиеhandoffchange/KernelReadCapture.csне трогать/нечитать. Последниелимитыprimary1%used/weekly0%used; ≤5%remaining — checkpoint/стоп. Commit/pushбезforce/privateartifacts/PR. Relevant history: [методика53](COMPARISON_QUALITY_2026-10-25.md), [движокC#](CSHARP_TRANSPORT_ENGINE_2026-10-25.md).
