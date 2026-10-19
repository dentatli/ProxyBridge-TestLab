# Управляемый отказ одного контрольного соединения

Подтверждён целевой10022 при original query:200/200 заполнителей успешны,
затем именно заранее выбранное control соединение получило10022/bytes0.
Это пригодная основа для следующего наблюдения private Windows record,
не доказательство первопричины и не исправление продукта.

## Выполнение и наблюдения

Fresh plan043738-f794b092, SHA
`d35ac4303d027c6ccc7b5715d56f4d3ce3643207c4c5655aeac3e657fcb08b8d`,
consumed once. Boot115/event17081/start2026-10-19T04:20:13.5000000+00:00.
Run `pb-target-accept-run-20261019-043838-3106828f`.
Новый diagnostic Core SHAe04fc3e3.../loaded path+SHA подтверждены вCLI PID9744;
родительские/рабочие binaries, установка драйвера и frozen kits не изменялись.
WinDbg не управлялся, точки не устанавливались. Report sources после Run
исправлены отдельно; не заявляется conformance изменённого runner прежнему plan.

Native fillers PID14956, исходные127.0.0.1:42001..42200:200established snapshots
доcontrol,200native Succeeded,200original queries successful/context32,
ctx_pid соответствует PIDfillers, receiver GUID/512KiB проверены.
Control PID4720/127.0.0.1:42201→Core127.0.0.1:34010:
ровно одинquery seq201,api_return=-1/api_error10022/bytes0/required32;
native ErrorNotAllDataTransferred/send0/recv0. ДваPID/tuple роли не смешаны.
Gate ready/released1, native cohort COLLECTED, cleanup_errors[], process stopped.

Control ETW explicit fulltuple:

1.1553Succeeded1/Redirected0/CodePath2;
2.1214Reason30: Listener dropped SYN because SO_PAUSE_ACCEPT was set;
3.1186RexmitCount1, спустя приблизительно510ms;
4.1553Succeeded1/Redirected0/CodePath2 послеretry;
5.1214Reason10/ReceivedRST после отказаCore.

ETWfinal EventsLost/LogBuffersLost/RealTimeBuffersLost0,ControlStatus0,
181buffers, headerloss/decoding errors0. Только same-trace относительный порядок;
Core/ETW wallclock alignment не доказан, tracerpt offset+04:59 сохранёнкакесть.
Поля1553Redirected0/CodePath2 не интерпретируются как наличие/отсутствиеWFPcontext.
Kernel NTSTATUS/private allocation/free/transfer пока не измерены.

## Ограничение контроллера и очистка

Общий diagnostic-run.status осталсяFAILED: ПОСЛЕ успешного collect/CLI cleanup
контроллер ошибочно прочитал `$lifecycle.error`. Возвращаемый объект имеет
process_result, а error есть только в EvidenceSink. Начальный report также
перепутал эти схемы. Исправлены оба обработчика, добавлена regression check;
повторная нагрузка не выполнялась, исходные receipt/report не переписаны.

Исходный target-report INCOMPLETE сохранён. Новый offline review записан отдельно:
`pb-target-accept-review-20261019/capture-review-r1/target-report.json`,
SHA76f736337c46ec4a10b6680044b12c4108503086e022d42c5a65fe6e497fbac7.
Он сопоставил все201query/native и подтвердил target_trigger_observed=true,
control_original_api_failure=true; единственнаяошибка — общий Run status.
Это прямые наблюденияcapture, не переименование всегоRun вPASS.

Cleanup подтверждён: run.cleanup_errors[],resident_disabled_aftertrue,
synchronous DISABLEafter receipt,interception-after/loaded-driver snapshots,
CLI graceful/post_stop/outputcapture true/error empty, собственный ETW остановлен/
экспортирован. Resident service оставленRunning; независимогоgEnabledreadbackнет.

Первый Run вызов старого runtime plan043512-ca10ccb0 был остановлен доclaim
из-заTIME_WAITна57045/57062/57135/57179→127.0.0.1:24285. DynamicTCP range
49152..65535 подтверждён netsh; новый runtime выбрал42001..42201. Старый
build receipt с первоначальными портами не менялся, новыйpolicy явноотдельный.

## Следующий шаг

Разрабатывать наблюдение жизненного цикла одной записи Windows для controltuple
передпервымSYN/послеdrop/приretry/accept. Не повторять обычный328Run,
не увеличиватьнагрузку, не объявлятьWindowsbug/driverbug/tableoverflow.
Точки WinDbg пока не готовы; physicalhost actions остаются пользовательскими.
