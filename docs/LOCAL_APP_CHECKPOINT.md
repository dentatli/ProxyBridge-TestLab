# Локальная лаборатория — checkpoint, 27 октября 2026

## Последний WFP H2, 27 октября

[АудитWFP61](PB_SUT_WFP_H2_61_AUDIT_2026-10-27.md):attempt20261027-103040-7322e11562de4085ab3dda7583e8ec7d,нагрузка3596.985с/7200,FAILED. Все103завершённыеPROXYоперацииroutePASS,QUIC7/7closePASS(один4.203с—фикс61подтверждён). DIRECT/BLOCKповедение232/232ожидаемое,но224UNVERIFIEDпотерялисвежийcallbackиз-заWFPдедупликации(pid,ip,port,action);этоошибкаметодикилаборатории,неблокировки. НужнасвежаяCoreClearConnectionLogsэпохапередпробами,безослабленияevent/no-delivery/guardgates. Остановкаотдельная:результатpersistentTCPworkerсталUNKNOWN;исходноеRPCисключениепотеряно,причина/винадрайверанеустановлены. ПоследнийliveTCP7111/7111,UDP17776/17776,финальнойсверкинeт. Итоговаяcleanuptrue,устройствоdisabled/службаStopped. ПередновымH2исправитьcallbackметодикуисохранениеRPCпричин,проверитькоротко. Кодпоканеизменён. 9fileSHA/raw/journal/captureисummary0diffподтверждены.
## Текущая версия

**preview.61**, source `d1da6ff13daf50c803da96e0c2256e67f1cf1154`, установлена и запущена admin/idle на VM localhost5178 и PB-SUT (его localhost5178). Все1704packageSHA на каждой копии совпали. По2сборки, историяVM10/SUT13,unreadable0. Stores отдельные. ProductDLL/SYS,BCD/trust/установкаWFP не менялись. КлиентскийWinRM/TrustedHosts восстановлен без ошибок.

VM: `C:/src/ProxyBridge-TestLab/artifacts/releases/ProxyBridge-TestLab-0.3.0-local-preview.61-win-x64`. SUT: `C:/PB-TestLab-20261026-r1/payload/lab61`. Существующая Comparison task обновлена; предыдущие пакеты иtask-before61.clixml сохранены для отката. Evidence ignored: artifacts/endurance-check/package61-verified.json, sut-upgrade61-r1; VM artifacts/endurance61-vm-ready.json.

## Последний запрос — QUIC close

[Исправление61](QUIC_CLOSE_TIMER_PREVIEW61_2026-10-27.md): QUIC/HTTP3 ждут публичный таймер aioquic после первого CONNECTION_CLOSE, вместо фиксированных2с. Бюджет8с внутри прежнего15сworkergrace, отмена и ошибки не становятсяPASS. Записываются expectedtimer/budget/elapsed/close_verified; явные причины при неполномclose. Сертификат/данные/маршрут/remoteidle gates сохранены. Исходные отчёты не исправлялись.

Проверки:6QUICunitPASS (включая2новые regression-проверки с immediate/0.1/3.3с, cap/cancel/missingevent). Реальный WinDivert4.3.0Core наVM: QUIC иHTTP3 с настоящей aioquic и test-onlyувеличеннымPTOприclose прошли сtimer3.3с/wait3.375с,маршрутподтверждён. Timer12с ограничен8.015с иявнымCLOSE_BUDGET_EXCEEDED/complete=false. Corecleanuptrue/forcedstopfalse,ownedпроцессов/WinDivertслужбнет. ПервыйharnessимелошибочныйrunIDprefix,relayправильноотклонилобмен;послеисправлениятолькоharnessпрогонподтверждён. SourceкодQUICне менялсяпослеподтверждённогоactualCoreтеста.

Evidence: artifacts/endurance-check/check61-close-confirmed.log/.exit, probe-1793096052249287900. WFP H2 на61 выполнен частично и разобран выше. До нового многочасового прогона нужны callback/RPC исправления лаборатории; автоматически H2/24ч не запускать.

## Последний полный H2: WinDivert60

[Аудит](PB_SUT_WINDIVERT_H2_60_AUDIT_2026-10-27.md):attempt20261027-071015-84d71e37c35541b9bb1d914aaa063c32,7200свыполнены,cleanuptrue. DIRECT/BLOCK TCP/UDP464/464PASS,ruleIDs/PIDstable;TCPpersistent/bulk/churnуспех,UDP36000/36000безпотерь. HTTP/HTTPS/HTTP2/SFTP/DNS-TCPпо16окон/2880операцийсrouteproof. ЕдинственныйFAIL—3-еQUICокно:все60/60операцийимаршрутныесчётчикисогласованы,ноlocalclose_verifiedfalseпосле2с. КонкретныйPTOнеписался;связьисторическогоэпизодас3PTO>2с—гипотеза,необвинениедрайвера. Методическаяошибкафиксированных2сисправлена61. SHA9файлов/raw/journal/captureиsummaryrecompute0diff.

## Длительный профиль и границы

[Профиль60](ENDURANCE60_POLICIES_2026-10-27.md):PROXYTCP/UDP+6прикладныхпротоколов,параллельныепериодическиеDIRECTTCP/UDP42541/42542иBLOCK42543/42544,включаяquiet. ПодDIRECTстоитfallbackBLOCK,проверяетсяприоритет. BLOCKтребуетCoreevent,нулевуюдоставкуиздоровыйполучатель;тайм-аутсампосебенеPASS. Точныйnativeworker/host/port/protocolscope;клиентнеперезапускается. Незнакомыйworker/control/healthостанавливаетпопытку,ошибкиsticky,данныевappend-onlyjournal+ограниченнойсводке. H2default/H24/H48/H72,безloadselector,эксклюзивныйвыбор,legacyнаборысовместимы. Методendurance-fixed-cycle-v2-policies,неэквивалентен58/59дляресурсногорейтинга. Доменныeправила/IPv6/всеUDPownershipвариантыэтимнепокрыты;ETWkernelвsoakотключён.

Проверенныйadmission60:реальныйWinDivertCore70с,все6apps+4policyканалауспешны,отрицательныеDIRECT/BLOCKнедаютfalsePASS;отмена1.719собаnativehosts idle;35nativecontracts/3portscope/2policyguards/250actualJSотчётовPASS. Эти модули не менялисьв61,повторятьвесьаудитбезпричиныненужно. [Порты59](ENDURANCE59_RULE_PORTS_FIX_2026-10-27.md) и[heartbeat58](ENDURANCE58_HEARTBEAT_FIX_2026-10-27.md) сохранены.

## Организация работы

Worktree `C:/Users/LabAdmin/.codex/worktrees/testlab-development/ProxyBridge-TestLab`, branch codex/development-functional-completion; базаd5b51f3сохранена. MainC:/src/ProxyBridge-TestLab checkpoint-20261007:чужойhandoff/KernelReadCapture.csнетрогать/нечитать. Неавтозапускатьfull/HIGH/H2/24ч;trust/BCD/driverнеизменятькакroutineappstep;frozenkits/captures/archivesсохранить. Commit/pushбезforce/PR/privateartifacts,неделегировать. Usageпроверять,при<=5%remainingcheckpoint/стоп;началотекущегозапросаprimary8%used/weekly48%used.

UDPWinDivert—отдельныйчат `01a17935-ca69-7152-8f03-9c9bb8600e7c`,[VM-onlyhandoff](WINDIVERT_UDP_VM_HANDOFF_2026-10-26.md). ЕгозапретPB-SUTсохраняется;здесьSUTобновлёнпосвежимзапросамодлительномрежиме. ПродуктовыйUDPownershipэтимнеисправлен. Послефинальныхпроверок—[итоговыйREADME](FINALIZATION_AND_NEXT_SCOPE_2026-10-26.md),безуниверсальногопобедителя/полногоkernelCPUрейтинга.

