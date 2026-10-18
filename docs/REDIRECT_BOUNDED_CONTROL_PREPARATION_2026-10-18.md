# Контроль воспроизведения с отключёнными точками, 328 соединений

USER запросил проверку воспроизведения без точек после [retrieve/query bounded](KERNEL_RETRIEVE_QUERY_BOUNDED_RESULT_2026-10-18.md), где было307успехов/21unidentified10061 и ни одного Core10022. Сначала повторяем ту же нагрузку4→64→256→4,328соединений. Исторический968контроль включал640 и не является таким же сравнением. Нулевая частота отказов на328не исключит их на640. Даже разница двух запусков не докажет причинного влияния отладчика без учёта вариативности.

## Контракт и состояние

Методredirect-context-bounded-control-v1. Те же512KiB/8shold/ConnectEx/pending32/originallistener/delay0/одинисходныйquery,120sclientwait/240scohort/2GiBgate. SharedKdQueryBoundedConnectionLoad и KdBootSessionEvidence не менялись; sourcee2cd66b содержит отдельныеwrapper/workload/preparer/reporter. Registered2/3 остаютсяd,active=[],inactive2/3; это контроль без срабатываний, не удаление сохранённой регистрации. ФлагDebuggerPointsDisabled — подтверждениеUSER, не автоматическая проверка WinDbg.

Последний USERconsole4a1c91c2 законченbl2/3d иотдельнымg. Не включатьточки,не загружатьstage и не Break при сохранённомсостоянии. Еслипослетого ихвключали/менялисессию — нужнапроверкаUSER. ПередлюбымнеобходимымBreakwarn:останавливаетсявсяVM/Codex/RDP; bd2/bd3/bl иgпоодной, gотдельноevenerror. Агент отладчиком не управляет.

Новый комплект привязан к bootEvent12 record16566/BootId113/StartTime2026-10-18T06:22:30.5Z. Stablebootguard/пинованныеCLI/Core/driver/изолированныйPython/всеfileSHA/mutex/lease/legacy-interruptedguards сохранены; ни driverinstallation, ни productbuild/patch, ни системныхизменений нет. После reboot неResume/refreeze. Тайминги подKD не считаются обычной API latency; этот контроль тоже не является тестом ёмкости/скорости.

Native report пишетredirect-bounded-control-report.json/summary.md. NTSTATUS не измеряется; WinDbg console для статусовнеожидается. При связанном исходномAPI10022 и полномnativeevidence статусORIGINAL_API_FAILURE_REOBSERVED; без негоNO_ORIGINAL_API_FAILURE_OBSERVED. Любая неполнота,включаяunidentified10061,остаётсяCAPTURE_INCOMPLETE,evenеслиестьчастичныесвязанные10022. Отдельное полеcorrelatedfailurecount сохраняетнаблюдения, kernelC0000225/причинаавтоматическиневыводятся.

## Проверки без продукта

PythonAST,PS5.1parse/purepresetpassed. Адаптированныйисторический968captureбезфазы640/еёquerymetadata и сновымpolicyreporterдал32связанныхAPI10022/32nativefailed,errors[],соответствующийконтрольныйstatus. Адаптированныйпоследний328сохранил21unidentified10061/0API10022/CAPTURE_INCOMPLETE. Activepointpolicyотвергнут. Это синтетическая адаптация сохранённых файлов для проверкикода, не новыйRun/не самостоятельное доказательство актуального воспроизведения.37старыхsource/moduleSHAнеизменны.

Приватныйaudit `artifacts/diagnostics/pb-redirect-bounded-control-review-20261018`:generators/purechecks/адаптированныеfixtures/reports/Prepareconsole/protectedhashes. НеGit. Прежниекиты/capturesнеизменять. Агентнипродуктнинагрузкуне запускал.

## Стоп-пункт

WindowsPS5Prepareexit0/FILES_VALIDATED8285/8197runtime. ПовторныйInspectне выполнялся. Новыйкомплект `artifacts/diagnostics/pb-redirect-bounded-control-preparation-20261018-070201-6df5d2de`, runtime-planSHA256 `534155E94FAD869C8994485B42DFF3A561A2A72CB3817C65CD66044CE34B46A7`.37oldsourceSHAпослеPrepareсовпали. Толькофайловаяподготовка,ниагентRunнипродукт/трафикне выполнялись.

ПолныйодинRunсautoSHAcompare/throw/DebuggerPointsDisabledсохранённаDesktop `PB-Redirect-Bounded-Control-20261018.txt`. Согласие на самконтроль уже даноUSER,повторнонепереспрашивать. ПоследнийUSERbl2/3d/g,припрежнемсостояниинеBreak/неbe/неstage. После одногоRunсохранитьвесьPS/каталогрезультатов;точкиоставитьd,безавтоматическогоповтора/640. GPTможнозакрытьдляосвобожденияпамяти. Следующимидействиямиуправляетразборрезультатов, нестарыеpendingNEXT.
