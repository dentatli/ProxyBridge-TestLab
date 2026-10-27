# «На этом ПК» — checkpoint, 27 октября 2026

## Последний H2 WinDivert60

[Аудит 27октября](PB_SUT_WINDIVERT_H2_60_AUDIT_2026-10-27.md):7200свыполнены,cleanuptrue;DIRECT/BLOCK TCP/UDP464/464PASS,ruleIDs/PIDstable;TCPpersistent/bulk/churnуспех,UDP36000/36000безпотерь. HTTP/HTTPS/HTTP2/SFTP/DNS-TCPпо16окон/2880операцийсrouteproof. ЕдинственныйFAIL—третьеQUICокно:все60/60операцийимаршрутныесчётчикисогласованы,ноlocalclose_verifiedfalseпосле2с. Влабораториинайденфиксированный2сclosebudgetвместодинамического3PTOaioquic;конкретныйPTOневзаписи,такчтосвязьсэтимэпизодом—гипотеза,необвинениедрайвера. ПередследующимH2исправитьboundedожиданиеcloseтаймера/яснуюошибку,проверитькоротко. Коднеизменялся. SHA9файлов/raw/journal/captureиsummaryrecompute0diff;SUTidle,новыхнагрузокнебыло.
## Актуальная версия

**preview.60**, source `df1a002dd635ad6be339933ce7be1661825d5dd5`, установлена и запущена admin/idle на VM localhost5178 и физическом PB-SUT (его localhost5178). Все1704packageSHA на каждой копии совпали. По2сборки, историяVM10/SUT12элементов,unreadable0; stores разные. UIH2/эксклюзивныйвыборсохранены, первый H2 WinDivert после обновления проанализирован по ссылке выше.

VM `C:/src/ProxyBridge-TestLab/artifacts/releases/ProxyBridge-TestLab-0.3.0-local-preview.60-win-x64`; SUT `C:/PB-TestLab-20261026-r1/payload/lab60`. Comparison task обновлена, прежние пакеты и task-before60.clixml оставлены. История/сборки сохранены. ProductDLL/SYS,BCD/trust/установкаWFP не менялись; WinRMclientcleanup без ошибок. Evidence ignored: package60-verified.json/sut-upgrade60-r1, VM artifacts/endurance60-vm-ready.json.

## Последний запрос: расширить длительный тест

[PROXY/DIRECT/BLOCK60](ENDURANCE60_POLICIES_2026-10-27.md): четыре периодических канала DIRECT TCP/UDP (42541/42542),BLOCK TCP/UDP(42543/42544), в том числе в quiet, без переключения клиента. Точные nativeworker/host/port/protocol правила; под DIRECT стоит нижестоящий BLOCK, так что проверяется приоритет реального правила. BLOCK требует Coreevent,нулевуюдоставкуисправныйorigin. Originсампроверяетблокируемыепортыизнеохватываемогопроцесса. Тайм-аутсампосебенеPASS; неизвестныйworker/health/controlостанавливаетпопытку. Результаты4строк,полныедоказательствавpolicy-observationjournal. Метод endurance-fixed-cycle-v2-policies,профильнеэквивалентен59/58дляресурсногосравнения.

Проверки: настоящий официальныйWinDivert4.3.0CoreнаVM,70сprivateadmission,все6appPROXY+TCP/UDP/bulk/churnуспешны,4policyканалапо10PASS. Отрицательные: отключённыйDIRECTблокируетсяfallbackиFAIL;отключённыйBLOCKдоставляетTCP/UDPиFAIL. Отмена1.719с,обаnativehostjobs0/Corecleanuptrue/forcedstopfalse,ownedпроцессов/WinDivertслужбпослевыходанет. C#/UI0warnings/errors,MSVC/W4/WXуспех. 35nativecontractsPASS,3portscopePASS,2policy-evidenceguardtestsPASS;250старыхactualJSотчётов+4новыестрокиrenderPASS. UIустановленного60 загружаетсясH2/фиксированнымпрофилем. РеальныйWFPпослеэтогорасширениянепроверялся.

Evidence: artifacts/endurance-check/check60-guarded-product.log,probe-1793083989127074400;check60-cancel.log,probe-1793084214223596400;contracts60.log,engine-contract-1793084129640700200;ui60.log. КороткиеprivateoverrideнедоступнывHTTPAPI;необъявлятьуспешныйH2/24чпорезультатамadmission.

## Следующий шаг и границы покрытия

H2 WinDivert60 выполнен с одним QUIC close отказом; до нового H2 нужен коротко проверенный фикс close-критерия. WFP/24/48/72ч нового профиля не проверены. Параллельные DIRECT/BLOCK охватывают TCP/UDPдействияправилиприоритетDIRECT;это не все варианты доменныхправил/IPv6/многопоточности. Все6прикладныхпротоколовпроверяютсячерезPROXY. Фиксированный30минцикл,безloadselector,эксклюзивныйвыбор,H2default/H24/H48/H72,legacyдлительностисовместимы. ETWkernelвsoakотключён,полногоkernelCPU/RAMнеобещать.

[Порты59](ENDURANCE59_RULE_PORTS_FIX_2026-10-27.md) исправили6appмаршрутов; [H2WinDivert58](PB_SUT_WINDIVERT_H2_58_AUDIT_2026-10-27.md) отработал7200с/TCPиUDP36000/36000,ноappsобходилипродукт,поэтомуприкладнойохватнеподтверждён. [Heartbeat58](ENDURANCE58_HEARTBEAT_FIX_2026-10-27.md) исправил [controltimeout57](ENDURANCE57_EARLY_STOP_2026-10-27.md),вH2неповторился. Историческиеотчётынепереписывать.

UDPWinDivert—отдельныйчат `01a17935-ca69-7152-8f03-9c9bb8600e7c`,[VM-onlyhandoff](WINDIVERT_UDP_VM_HANDOFF_2026-10-26.md). Его запретPB-SUTсохраняется;здесьSUTобновлёнпоновомуразрешённомуdevelopmentscope. UDPownershipэтимнеисправлен;singleflowнесравниватьсколлизиейсокетовнаодномназначении. Послефинальныхпроверок—[итоговыйREADME](FINALIZATION_AND_NEXT_SCOPE_2026-10-26.md),безуниверсальногопобедителя/полногоkernelCPUрейтинга.

## Работа и ограничения

Worktree `C:/Users/LabAdmin/.codex/worktrees/testlab-development/ProxyBridge-TestLab`,branch codex/development-functional-completion;базаd5b51f3сохранена. MainC:/src/ProxyBridge-TestLab checkpoint-20261007:чужойhandoff/KernelReadCapture.csнетрогать/нечитать. Неавтозапускатьfull/HIGH/H2/24ч;trust/BCD/driverнеизменятькакroutineappstep,frozenkits/captures/archivesсохранить. No force/PR/privateartifacts,неделегировать. Последнийusageprimary52%used/weekly45%used;при<=5%remainingcheckpoint/стоп.

Историяпроверенныхданных: [SUTповторы56](PB_SUT_REPEAT56_AUDIT_2026-10-26.md),[SUTfull56](PB_SUT_NORMAL56_AUDIT_2026-10-26.md),[подготовкаSUT](PB_SUT_COMPARISON_PREPARATION_2026-10-26.md),[VMповторы](REPEAT_RUNS_VM56_2026-10-26.md),[kernel56](KERNEL_COLLECTION_PREVIEW56_2026-10-26.md). Не повторять весь аудит без новых входных данных.

