# «На этом ПК» — актуальный checkpoint, 26 октября 2026

## Приложения и scope

Лаборатория **preview.56**, source `6bce96b6f3a2a40d07c248a82e110ae8cd86326a`. VMadminlocalhost5178,1698packageSHAverified; физическийPB-SUT имеет отдельную копию56/свойstore/ярлык на рабочемстоле. Не смешивать их отчёты. 2сборки:WFPdriver4da324e иWinDivert4.3.0. Последний запрос — read-onlyпроверка двух новых выборочных повторов каждойсборки наPB-SUT; выполнен. Новые нагрузки/измененияпродукта/лаборатории не запускались.

## Последний результат PB-SUT

[Аудит повторов](PB_SUT_REPEAT56_AUDIT_2026-10-26.md):WFP130126/131844,Win131033/132552. Все4очереди COMPLETE,4одинаковыхэтапа loaded-rtt/tcp-connections/flow-rate/SFTP,NORMAL/LOW. Все16PASS/MET/fullroute,все6попарныхconditionsравны.61transferSHA/16rawSHA/recompute0diff;actualJS16renders,4CPUbudgeteligibleэтапауобоих,kernelwinner0. Start/Stop1/1,capturecomplete/cleanuptrue,forcedstopfalse.

Диапазоны2повторов:loadedRTTp99WFP1.058–1.146/Win5.361–6.102ms;TCP128RTT2.021–2.211/39.229–42.904ms;privatecommitпикTCPconnections45.227–45.234/8.484–8.527MiB;SFTPCPUпроцессана1000циклов1.443–1.476/7.517–7.674с. WFPSFTP888/900циклов,Win900/900,loadMET;нормализоватьCPUнафактическуюработу. Flow-rate180/180сеансоввкаждомпрогоне. Направлениеразличийповторилось;ещёfullдляэтогоненужен,но2повторанедаютдоверительногоинтервала.

Kernel16captures:модуль/ожидаемыйSHAverified,интервал1ms,lost0/drain/cleanuptrue,pollerrors0,QPC/formulaPASS. WFP0–2CPUвыборкипрофиля=>unknown,не0CPU;нетполногоkernelCPUсравнения. Taggedpoolчастичный,неfullRAM,сprocessCPUнескладывать. Полнаяатрибуция/overheadкалибровкаивнешнийoriginдляпиков—отдельнаябудущаяработа,неавторизованнаяэтимread-onlyаудитом.

PB-SUTприэкспорте:i3-10100/8логCPU,тотжеboot09:43:40Z,HighPerformance,IntelI219-V1Gbps,debugNo/testsigningYes,HLKStopped,driverStopped,active/busyfalse,своихETWнет. ЭкспортWinRMclientcleanupбезошибок. Evidenceartifacts/sut-repeat56иsut-comparison-prep/repeat-export-r2ignored,непубликоватьключи/DPAPI/privatecaptures.

## Предыдущие подтверждения

- [Полные NORMAL56 наSUT](PB_SUT_NORMAL56_AUDIT_2026-10-26.md):WFP43PASS/1UNVERIFIEDUDP128(70из96002пакетовнепокрытыrouteaccounting),Win33PASS/11UDP-relatedFAIL;29qualityeligibleпар,92rawSHA/recompute0diff. Rootcauseнеразбирался. PeakTCPнаSUTCPU~96%неподтверждаетмаксимумдрайвера.
- [Случайные VMповторы](REPEAT_RUNS_VM56_2026-10-26.md):новыераньшеоказалисьнаVMModel183/6CPU,неSUTModel165/8CPU;первыйWFPсдополнительнымUDPнеравен4caseочередям. Сохранятькакотдельныерезультаты.
- [ПодготовкаSUT](PB_SUT_COMPARISON_PREPARATION_2026-10-26.md):C:/PB-TestLab-20261026-r1/payload,1715SHA,driveroem25/1.1/SYS5a29f6b7…,backupдрайвера/BCD/настроексохранён. USERразрешилфизподготовку/reboot/disabledebug. TaskPB-USERInteractiveHighestAtLogon,контроллерloopbackonly. VMstoreнепереносилсянаSUT.
- [Методядра56](KERNEL_COLLECTION_PREVIEW56_2026-10-26.md),[fixed-session55](FIXED_SESSION_COMPACT_2026-10-26.md),[51LOW/HIGHпрофиль](USER_LOAD_PROFILES_2026-10-26.md). Soakотложен.

## Рабочие границы

Worktree `C:/Users/LabAdmin/.codex/worktrees/testlab-development/ProxyBridge-TestLab`, branch `codex/development-functional-completion`,базаd5b51f3сохранена. MainC:/src/ProxyBridge-TestLab branchcheckpoint-20261007:чужойhandoff/KernelReadCapture.csнетрогать/нечитать. Неавтозапускатьfull/HIGH/soak;неинвестигироватьпродуктовыйrootcauseвэтомdevelopmentscope. Неизменятьtrust/BCD/driverкакroutineappstep. Неудалятьfrozenkits/captures/archives. Commit/pushбезforce/PR/privateartifacts,неделегировать. Лимитывначалеаудитаprimary17%used/weekly17%used;проверятьпереддолгойработой,при<=5%remainingcheckpoint/стоп.
