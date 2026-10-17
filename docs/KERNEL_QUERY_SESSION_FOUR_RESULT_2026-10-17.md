# Двухточечный логгер прошёл пробу четырёх соединений

USER выполнил предложенный один Run `pb-kd-query-session-run-20261017-063947-eb93855d`,17 октября2026 11:39:47.636–11:40:05.359 Asia/Yekaterinburg. PowerShell вернулся. Pure evaluate нового reporter точно совпал с saved native report:4/4 successful, native_failed0, исходных query4, API10022нет, errors[].2MiB переданных данных подтверждены native/receiver evidence. Это не воспроизведение исходного отказа и не исправление продукта.

## Console WinDbg и привязка

Attachment `c1c0fd3f-2665-4e98-a1f9-f80d709af392/Вставленный текст.txt`,6980bytes,SHA `96cc566e898ee80ea2f46632b3cfbb78505492e6e3a048750e13af20572a40be` содержит:

- Четыре inventories толькоIDs3/4:disabled→enabled→enabled после ручногоBreak→disabled. Адреса и тела actions во всех inventories точно совпадают с frozen stage/profile; два внешнихg введены отдельно.
- Ровно8 actualPBKDM events:4 QUERY_READ и4 QUERY_STATUS, строго чередуются под одним внешнимg. Во всех READ record ненулевой; в каждой паре совпадают kernelthread/PID/TID/scope/endpoint/record, STATUS0. Четыре различных endpoint иrecord pointers в пределах этой пробы.
- KernelPID39d8hex/TID2590hex = CorePID14808/TID9616decimal. Они совпали со всеми4 исходными Core queries seq1..4. Core query интервалы не перекрываются, порядок согласуется с console. Private query-pairs.json сохраняет сопоставление socket/peer/nativeidentity/seq с KDпарой.
- Нет исполненных UNREADABLE, Memory access error или syntaxerror. Финальная80000003 самим console описана как ручнойBreak, не crash. Послеbd3/bd4 inventory показывает обеd, затемg.

Привязка Core↔KD условна на полноту userpaste и последовательность вызовов одного PID/TID: нет общего Core/KD QPC, независимого socket/seq/peerport вKD. Scope — stack address — повторяется между четырьмя вызовами, не является уникальным flowID. Нельзя выдавать такое сопоставление за независимую привязку поTCPtuple или переносить его на параллельные/неполные captures.

Выполнение обеих actions и продолжение между наблюдёнными hits подтверждены на **успешном пути**. Общая gc safety, ветка UNREADABLE и чтения на failedflow не проверены. Две точки не покрывают CREATE/прикрепление/FREE и не доказывают историю record. В этом capture kernelstatus0 реально наблюдался; **C0000225 исходного failedquery всё ещё не пойман**.

## Очистка и frozen inputs

Run-receiptCOMPLETED,workers_stopped/driver_stop_observed=true; CLI ready/graceful_stop/post_stop_verified/output_capture_complete=true, forced_stopfalse,errorпуст. Proxy/sampler exit0 безforcedstop. AfterслужбаStopped,известныеWFPobjectsне наблюдаются,product-processes-afterпуст. Общая видимость всех источников перехвата остаётся неполной, all_interception_absent/interception_cleanup_verified не объявлятьtrue.

Saved runplan и freshkit063031-cfbfaa59planSHA совпали с `7e90ea90f7fd8f2cca02d9459a9c38f129369e6ed2b8bd40d759a413b073416a`. Все8288 frozenfiles сейчас совпали. Captured benchmark PythonSHA совпал с saved snapshotexe; frozen wrapper/workload используют snapshotpath, не общийSDK приRun. Это проверки наблюдённых границ, не непрерывное измерение всего окружения.

Private audit: `artifacts/diagnostics/pb-kd-query-session-four-review-20261017/` — review.py,validation.json,input-sha256.json,frozen-input-review.json,recomputed-native-report.json,inventories.json,kernel-events.json,query-pairs.json,python-capture-review.json.38 inputs (37runfiles иattachment) хешированы до анализа и повторно проверены неизменными. Original report/debuggerpending markers не перезаписывались: native-onlyreport сформирован до разбораKD, итогkernelreview хранится отдельно. Код/kit/manifest не refreeze/Resume. Агент ничего не запускал в продукте/debugger и не менял системные настройки.

Повреждённая кириллица в подписи `connections / ...` не сопровождалась ошибками JSON/CSV/metadata. Frozen module ради косметики не изменялся; это не признак исходного TCP отказа.

## Вмешательство логгера и следующий опыт

| Core query seq | Длительность под KD |
| --- | ---: |
| 1 | 316.6692мс |
| 2 | 250.9640мс |
| 3 | 264.6410мс |
| 4 | 249.7987мс |

Это elapsedинтервал, включающий остановки/работуKD, не обычная скорость query; длительности отдельных пауз и их доля не измерялись. В [полном контроле без активного логгера](REDIRECT_CONTEXT_CONTROL_RESULT_2026-10-17.md) query измерялись микросекундами. Под KD изменяется расписание, что может изменить приёмную очередь/исходный failure или убрать его воспроизведение; результат не годится для сравнения производительности.

Следующий предлагаемый отдельный kernel опыт —4→64→256→4 (328), те же две actions, original singlequery/порты/пинованные binaries/нагрузка на соединение.640 не нужен для первого поискаfailedquery: первый observedfailedэтап был256. Это отличается от968; требуется новый профиль/контроллер/freshkit, а не запуск четырёхсоединительного с другими аргументами.

При подготовке учесть примерно250–317мс на query в этой пробе. Простая иллюстрация256×этотинтервал даёт64–81с, это не прогноз времени нагрузки; она показывает риск прежнего60s ожидания. Предлагаемый reviewвариант:120s ожидание клиента,240s общий бюджет фаз, startup/hash/cleanup вне бюджета, ресурсныйgate2ГиБ сохранён. Такой новый timeoutcontract должен явно фиксироваться в новом kit и отчёте; не переписывать старый. Forced cleanup/ресурсныйgate/timeout прекращают серию, rawfailures сохраняются. Если получены толькоtimeout/изменённое поведение безисходногоsignature, механизм не объявлять установленным.

Критерий kernelpass: конкретный Core originalquery10022/nativefailure связан с QUERY_READ(состояниеrecord) иQUERY_STATUS(NTSTATUS) с проверенными PID/TID/порядком/полнотой. Даже NULL+C0000225 покажет состояние при запросе, но не где и почему запись потеряна; после этого нужен отдельный обоснованный lifecyclecapture создания/прикрепления/освобождения. ExecutingPID не принимать за owner, ACCEPT_JOIN не принимать за storeproof, отсутствие CREATE в сокращённом профиле не доказывает отсутствие создания.

**Текущий стоп:** одна USERfour-проба завершена, обе точки в концеconsole отключены/g. Следующий шаг только files-only подготовка bounded328 и отдельное согласованиеUSERRun после готовности конкретного kit. До этого не be/Run/новыеBreak. Не повторять063031/195830/старыеподготовки, не reloadstage. Перед каждым будущим USERBreak/enable предупредить о паузе всейVM/Codex/RDP, recoveryсохранитьнафизхосте, команды поодной/gвсегдаотдельно. Продукт/драйверную установку/BCD/гипервизор/питание/соседнийdevelopmentworktree не менять, поддерживаемыеtests не добавлять.
