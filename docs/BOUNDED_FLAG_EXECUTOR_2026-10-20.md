# Исполнитель ограниченного захвата флага

## После Run071515: cap ACCEPT64

TRACK+SET_PRE впервые пойманы наодномEP/record; flags30before01101641,
bit20установлен/bit21сброшен; stackвreceiveTCPloopback. Это prewrite,
а не наблюдённыйрезультатзаписи. Nativecontrol10022 повторён, cleanupCOLLECTED/OK.
ACCEPT4 исчерпалrawcap16: финальногоRETRIEVEнет, reportINCOMPLETE с сохранением
двухположительныхснимков. Private review071515.
Новыйпрофильaccept64оставляет2/3cap16,4cap64,max96,one-shot иk8.
FlagAccept64требуетFlagCreateArmed+FlagTarget; отдельныеSHA/profile/proof/stage,
старыепрофилисохранены. Updateтолько4; наREADYhostbe2/be4/g какпрежде.
119targettests/PSparser иCDBbounds16/63/64passed,31proof filesbound.
Лимитбольше не доказывает runtimecost/достаточностьокна; повторногоRunещёнет.

## Обновление после cap Run070133

Контроль снова API10022/bytes0, nativeCOLLECTED/cleanupOK, но только
PBFG_LIMITpoint3 безTRACK/SET_PRE/RETRIEVE: kernelcaptureINCOMPLETE.
USER явно разрешилbe3 изselectedCREATE. Новый FlagCreateArmed вместесFlagTarget
использует отдельныйпрофиль create-armed-20261020, первоначальныеhostenable2/4,
autoenable3 послеTRACK/resetcounter. Update-stage меняеттолько2;3/4 прежние.
Старыепрофили/планы сохранены. Одинhostcodeblockсgпоследнейотдельнойстрокой.
Ресурсы,нагрузка,cap16/max48,one-shot,k8 иcleanupgates прежние. ПослеCREATE
глобальныеhits3 всё ещё могут исчерпатьcap; отсутствиеснимка не опровергаетwriter.
НовыйCDBproof r2 проверил реальныйenabledstate3 во всех4ветках ивсе12actions;
binding замораживает28files иотклоняетсмешениестарогоreceipt/profile/policy.
НовогоkernelRun/проверкиruntimecost пока нет. НикакойagentBreak/step.

Boot117 подтверждён Kernel-General12 record17422, start2026-10-20T06:17:50.5Z.
Старый прерванныйRun оставлен без изменений, его rebootgate теперь относится
к предыдущемуboot. USER подключилWinDbg, blпуст, код CREATE/SETTER/ACCEPT сверён,
MASM, отдельныйg. Текущийtcpipbase fffff806`1bdd0000, setter fffff806`1bdf3670.
USER разрешил выдавать команды одним блоком сg последней отдельнойстрокой.
Не требовать дополнительногоbl при неизменномсостоянии.

## Точный профиль и два режима

Новый runtimeprofile pb-kd-target-flag-disabled-profile-20261020.json SHA
c1fb07110f92188237fa3a32436e30cd31fa2fd7ba8590d442241d1fca1da75a,
method kd-target-flag-disabled-candidate-20261020-v1. Actions идентичны проверенному
ограниченному candidate; старыеcandidate/retiredretryprofile не изменялись.
Новаяfreshregistration stage создаёт только2/3/4, отключаеткаждую, reset t1..5,
не содержитbe илиouterg; предназначена только для подтверждённого пустогоbl.
Подготовленныйreceipt не выдаётся за independentlyobservedregistration.

- FlagProbe: только4соединения (3фоновых+контроль42201), active2CREATE/4ACCEPT,
  setter3inactive, no stack. Bound16rawhitsнаpoint, максимум32, auto-disable
  после выбранногоснимка илиlimit; acceptотключаетвсё. Один исходныйAPIquery.
- FlagTarget: прежние200+1, prefillбезточек, hostwindow15s, control20s/Core30s;
  active2/3/4, максимум48rawhits, одинsetterstackk8, auto-disable. Требуется
  samebootpositiveprobe исвязанныйconsole; ещёнеподготовлен и не запускался.

Оба режима используют существующий Invoke-TargetAccept.ps1 и boot/files/driver/
resources/port/history/cleanup gates. Общаярегистрационнаяuserattestation
FlowProfileRegisteredDisabled обязательна; automaticenable/Break/step нет.
FlagProbe требует DebuggerLoggerEnabled после USERbe2/be4; FlagTarget —
DebuggerPointsDisabled иBoundedLoadReviewed, аактивациятольконаREADY.
НовыйPrepareпяти-точечногоRetryTarget по-прежнему запрещён.

## Проверки

114Python tests passed, PSparser, HostWindow5faults/Cleanup прошли безтрафика.
Новый CDBproof pb-target-flag-candidate-parser-20261020-r1:4cases×3actions,
syntax и actualdisabledstate подтверждены. Binding замораживает14files,
проверяетcandidateSHA9c04426b... и точноеравенство actionsruntimeprofile.
Дополнительныеtests проверяют samebootpositivegate, ложныйhostreceipt,
отсутствующийreturnedrecord, cap/incomplete, stack и отсутствиеpostwriteclaim.

Драйвер послеboot былStopped. ПередStart-Service проверены pinnedSYS SHA
3cd79cfc2a9ec6e45a11b2c225d11cb18c504fec3535e3ef1cb730e0e7732c9e иservicepath.
Start-Service выполнен одинраз, Running подтверждён; synchronousdisableIOCTL
успешен, independentenabledflagreadbackfalse. Private receipt
pb-flag-boot117-review-20261020/resident-disable.json. Продукт не переустановлен,
нагрузки/traffic/новогоRun не было. BeforeBreak/be wholeVM/Codex/RDP warning.
Recoveryдляprobe bd2/bd3/bd4/g отдельнымистроками в одномблоке дажеошибка.

FlagProbe Prepare065042-61585189 завершён exit0/PREPARED_NOT_RUN,
SHA9d78a5905f19630de411a451f5df5406e3707c5e4808603a8eeb8a3b4890008e.
ПередактивациейUSER зарегистрирует2/3/4disabled иresettrackers. Послеbe2/be4/g
запускаетVMRunсDebuggerLoggerEnabled/FlowProfileRegisteredDisabled;3неактивна.
НовыйRun самимагентом не запускался, native/debuggercoverage покаотсутствует.

## Результат контрольного прогона и следующий план

Run065643-4f819598: все4соединенияуспешны, run/cohortCOLLECTED, cleanuperrors[],
CLIgraceful/poststoptrue, residentdisabledaftertrue. USER TRACK+RETRIEVEstatus0
совпалипоrecord; Flagreport FLAG_PROBE_SUCCESS_OBSERVED/errors[]. Setter3была
неактивна — положительныйконтрольнеявляетсяcoverageэтойточки. Privateevidence
pb-flag-four-review-20261020-065643; пользовательсвязалстрокисlatestRun,
independentconsoleboundaryнеподтверждалась. Повторконтроляне нужен.

FlagTargetPrepare065820-5f641b23 exit0/PREPARED_NOT_RUN,
SHAb69f99466387aa31f864161c25f5b956f9b645f3ade0a38c3bc12bf78d6b5e1a.
Тежеactions/драйвер/нагрузка200+1; связаныbaselineboot117/proof14files.
Новаярегистрацияне нужна: передRun USERbd2/3/4, reset t1..5 иg; наREADY
включает2/3/4 иg, затемCвVM. Нельзя включатьдоREADY илиоставлятьстарыеcounters.
ПослеRunилиошибкиbd2/3/4/g; Runнеповторять. Автоматическаяактивацияотсутствует.
