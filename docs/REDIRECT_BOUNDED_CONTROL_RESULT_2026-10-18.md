# Контроль без активных точек: исходный API-отказ снова наблюдается

USER выполнил единственный согласованный Run `pb-redirect-bounded-control-run-20261018-070522-24f1bd43`, 07:05:22.003–07:06:03.348 UTC. Независимый read-only пересчёт native report по сохранённым файлам подтвердил32связанных исходныхCorequery10022. Оригинальные отчёты сохранены без перезаписи. NTSTATUS ядра в этом контроле не измеряется.

## Измеренные результаты

| Фаза | Попытки | Успешно | Связанные native/Core10022 | Unidentified10061 |
| --- | ---: | ---: | ---: | ---: |
| baseline | 4 | 4 | 0 | 0 |
| load-64 | 64 | 64 | 0 | 0 |
| load-256 | 256 | 224 | 32 | 0 |
| recovery | 4 | 4 | 0 | 0 |
| Всего | 328 | 296 | 32 | 0 |

Все328Corequeries присутствуют в metadata.32failedqueries(seq283..314) имеют api_return=-1/api_error10022 и однозначно связанные неуспешные nativeconnections; прочие296успешны. Reporterrors[]/ORIGINAL_API_FAILURE_REOBSERVED означает воспроизведение измеренногоAPIотказа, не доказательство текущегоC0000225, Windowsbug, driverbug, tableoverflow или backlogмеханизма.

WorkloadCOMPLETED,все4фазыпройдены,workers_stopped/driver_stop_observedtrue;CLIgraceful_stop/post_stop_verifiedtrue,forced_stopfalse/errorпуст. WrapperREDIRECT_BOUNDED_CONTROL_CONTROLLER_RETURNED,errorпуст. Все8285frozenSHA совпадают,62runinputfiles неизменны за анализ. Приватныйaudit `artifacts/diagnostics/pb-redirect-bounded-control-result-review-20261018/review.py` и `review.json`,неGit.

## Сравнение с предшествующим retrieve/query capture

| Режим | Попытки | Успех | ИсходныйCore10022 | Unidentifiedconnect10061 |
| --- | ---: | ---: | ---: | ---: |
| Две активные точки, Run065211-af6e15fb | 328 | 307 | 0 | 21 |
| Точки отключены, Run070522-24f1bd43 | 328 | 296 | 32 | 0 |

Проверены exactсовпадения bootidentityEvent12 record16566/BootId113, всехпинованныхCLI/Core/driverSHA, engine/module/Python/proxyhelper/wheel/samplerSHA. Controlpolicy совпадает после исключенияmethod и полейdebuggerstate/reviewack:4→64→256→4/328/512KiB/8shold/ConnectEx32/originallistener/delay0/onesinglequery/120sclientwait/240scohort. Увеличениядо640 или измененияqueueнебыло.

Состояние отключённыхточек основано на последнем USERconsole2/3d/g и подтвержденииDebuggerPointsDisabled; автоматического inventory WinDbg во времяRun нет. Backgroundactivity и внутреннее состояние до каждого запуска не доказаны идентичными. Порядоксерий был с точками, затем без; это не рандомизированный повторный причинный эксперимент. Общую длительность иqueryelapsed не выдавать за performancecomparison.

Наблюдения поддерживают гипотезу влияния отладочныхостановок на тайминги и наблюдаемый характер отказов. Сам по себе этотконтроль не доказывает, что точки — единственная причина различия. Важно: исходныйAPIотказ актуален на прежнихbinaries даже при328; увеличиватьочередь или объявлять исправление основанийнет.21connect10061 предыдущейсерии не подменяют32query10022 этойсерии и не связываются с теми жеflows.

## Текущий стоп

Одинконтрольвыполнен,неповторять/не640/неbe. Точкиоставитьотключёнными. Следующий офлайн шаг — отдельныйreviewableпрофиль сretrievalreturn2 иредкойQUERY_NULLточкой3+0x2d0/RVA121588 вместообщегоQUERY_READ. Он сохранитпопыткуизмеритьretrievalуfailedflow,сокративсрабатыванияquerypointнауспешномпути; полноеcoverage/generalruntime/снижениеobservereffectнеобещаются. Новыйпрофиль/stage/kit ещё несозданы, существующий3непереставлен. Никаких productизменений/WinDbgcontrol/нагрузкиагентне выполнял. СтарыеkitsнеResume/refreeze. USER debugger/runtimeдействияпослеподготовкииревью; beforeBreak/enablewholeVM/Codex/RDPwarning, recoveryзаранее,gотдельноevenerror.
