# Восемь исходных query failures: NULL redirect record и C0000225

USER Run `pb-kd-query-bounded-run-20261017-072501-ff00bc02` состоялся 17 октября2026, 12:25:01.615–12:26:52.860 Asia/Yekaterinburg. Использован новый boot-bound kit072108-b356874d. Серия дошла до recovery; native workload/CLI завершились штатно, затем reporter и внешний wrapper вернули ошибку неполноты из-за 32 неидентифицированных connect failures. Это не timeout, не срабатывание boot guard и не сбой команды WinDbg.

## Результат

| Фаза | Запрошено | Успех | Native отказы | Исходных query Core | Query10022 | Неидентифицированных connect10061 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| baseline | 4 | 4 | 0 | 4 | 0 | 0 |
| load-64 | 64 | 64 | 0 | 64 | 0 | 0 |
| load-256 | 256 | 216 | 40 | 224 | 8 | 32 |
| recovery | 4 | 4 | 0 | 4 | 0 | 0 |
| Всего | 328 | 288 | 40 | 296 | 8 | 32 |

В user console найдено ровно592 actual PBKDM events, строго296 пар QUERY_READ→QUERY_STATUS. Для всех288 успешных исходных запросов record ненулевой/status0. У восьми запросов Core **seq285–292**, в конце load-256:

1. QUERY_READ: поле `[endpoint+0x1c0]` равно0 при ioctl980000dd.
2. QUERY_STATUS: то же endpoint/record/thread/PID/TID/scope, statusC0000225.
3. Соответствующий исходный Core query: api_return=-1/api_error10022.
4. Совпавшая по phase/QPC/owned native endpoint запись генератора: ErrorNotAllDataTransferred, SendBytes0/RecvBytes0. GUID этих отказов нулевой; он не использовался как ключ корреляции.

Все296 query Core имеют последовательные seq1..296, один PID12892/TID14900 (KD325c/3a34hex), их интервалы не перекрываются. PID/TID всех kernel pairs совпали; число, порядок и успешные/неуспешные статусы согласованы с Core/native. У каждого failed endpoint только один QUERY_READ в этом capture. Всего281 различных endpoint pointers на296 запросов: переиспользование указателей у успешных запросов наблюдается, равенство указателей не доказывает lifetime объекта. Stack scope повторяется во всех296 вызовах, не является flow ID.

**Граница доказательства привязки:** общий Core/KD QPC, независимый socket/seq/TCP tuple в KD actions отсутствуют. Сопоставление опирается на один PID/TID, последовательные неперекрывающиеся вызовы и полноту user paste. Это проверенная условная привязка, не независимая трассировка по TCP tuple. Kernel NULL/C0000225 сами по себе наблюдаются непосредственно в console, а не выводятся из Winsock10022.

На этих восьми запросах теперь наблюдалась ранее статически проверенная ветка Windows: QUERY_READ перед загрузкой указателя из endpoint+1c0 видит NULL, затем запрос завершается C0000225. Это локализует состояние при отказе. **Не установлено, почему поле нулевое:** запись могла не прикрепиться, retrieval мог быть пропущен/неуспешен, либо поле могло измениться раньше. Нет доказательства прежнего существования записи для этих соединений, преждевременного FREE, ошибки Windows/драйвера или переполнения таблицы. Содержимое context buffer при NULL record не измерялось.

## Почему сохранён CAPTURE_INCOMPLETE

Остальные32 native отказа load-256 имеют Result10061 с сообщением об отклонении подключения, пустыми LocalAddress/RemoteAddress/ConnectionId, нулевыми TimeMs/SendBytes/RecvBytes. Достаточной идентичности для привязки к query нет. Они не добавлены к восьми query10022 и не объявлены redirect-context failures. Место/механизм этих отказов не установлены; packets для них в этом опыте не собирались.

Pure evaluate reporter точно совпал с сохранённым `KD_QUERY_BOUNDED_CAPTURE_INCOMPLETE`, единственная ошибка `load-256: UNIDENTIFIED_NATIVE_CONNECT_FAILURE_10061: 32`. Оригинальный report не переписывался и не превращался в PASS. Его ntstatus_observed=false относится к native-only стадии до разбора console; новый kernel review хранится отдельно. Неполнота всей серии не уничтожает наблюдения по296 идентифицированным исходным запросам, но не разрешает переносить вывод на все328 попыток.

Под KD query elapsed244.682–304.422ms, медиана251.148ms; восемь failed query245.885–251.609ms. Accept-return→query-entry у них0.4–0.8µs. Эти интервалы включают debugger pauses/observer effects. Пробы с двумя активными точками и прежний968-контроль без активного логгера имеют разные расписания/контракты. Разницу8/40/96 нельзя выдавать за улучшение продукта или измерение вероятности исходного отказа.

## Logger, очистка и сохранность

Attachment `27bea4d9-8b7a-45b0-a3fa-ca9dd7307ee0/Вставленный текст.txt`:86574bytes,SHA256 `f52338138dc2d01cbc3c69010d5de41acf49e4e6722ece6458fb5f7fcc879cdf`. Два inventories показывают только3/4e с точными адресами/actions. Нет исполненных UNREADABLE/Memory access error/Syntax error. В конце manualBreak, `bl` ещё обеe, затем `bd 3`, `bd 4`, отдельный `g`, без показанных ошибок. **Контрольного bl после bd нет**, не выдавать его за имеющееся подтверждение состояний d. До любого нового enable/изменения профиля нужно сверить состояние. Наблюдались actions/continuation на успешном и failed paths; general gc safety и unreadable branch этим не проверены.

Workload manifest/run-receiptCOMPLETED,workers_stopped/driver_stop_observedtrue. CLI ready/graceful_stop/post_stop_verified/output_capture_complete, безforcedstop/error; proxy/samplerexit0. Все четыре cohorts без forced cleanup и записанных execution errors. After serviceStopped,knownWFPobjectsне наблюдаются, product-processes-after пуст. Общую видимость всех interception sources не объявлять полной. Свободная RAM перед фазами4.59–4.75GiB. Внешний diagnostic-runFAILED относится к отклонению неполного отчёта после выполнения серии.

Boot identity в run snapshot точно совпал с frozen evidence. Plan SHA `F68F550807FE2903B40A21CBEF49FE26C733C1E806C4B548C230A38E9FA846CD`, все8294 frozenfiles совпали, captured PythonSHA совпал с snapshot. Хешированы до/после анализа63 входа (62 runfiles+console), все неизменны. Агент не выполнял Run/debugger control/build/install/product/system changes.

Private audit `artifacts/diagnostics/pb-kd-query-bounded-result-review-20261017/`: input-sha256,frozen-input-review,recomputed-native-report,kernel-events,inventories,query-pairs,failed-query-pairs,pointer-reuse-review,validation.json и private review scripts. Raw captures/kit/console остаются вне Git.

## Следующий шаг — только офлайн локализация accept/retrieval

Повтор этой query-only серии не нужен: требуемые NULL/C0000225 у исходного query пойманы. Следующий причинный вопрос — какое состояние было у **того же принятого endpoint до query**.

Сохранённый matching disk disassembly WfpAleAuthorizeAccept показывает участок RVA15649: flags bit24 и esi управляют входом в retrieval; после retrieval RVA1567b проверяет eax, при успехе RVA15683 записывает rax в endpoint+1c0. RVA1568a/+cbe — общий join с входами в обход retrieval/store; прежний ACCEPT_JOIN сам по себе не доказывает прикрепление.19 инструкций этого участка заново сопоставлены побайтно с текущим disk image, SHA совпал с metadata прежнего разбора; private accept-static-flow-review.json. Это не новый live-site review или installable profile.

Офлайн разобрать этот gate/return/store/join и доступную идентификацию endpoint. Кандидат следующего capture должен различать: retrieval не вызывался; вызван с ошибкой; вернулNULL; вернул/прикрепилненулевой record, который отсутствует к query. Не читать output slot как validrecord после ошибки, не принимать executingPID за owner. Сначала обосновать фильтр/flow binding и минимальный набор точек; не включать старые7/25 или широкие CREATE/FREE/NBL точки автоматически. Указатели и stack scope недостаточны без границ lifetime/порядка.

Предварительный минимальный кандидат для review — пять событий: accept gate до ветвления (flags/esi/предыдущее поле), retrieval return (status; output только при success), общий accept join (состояние поля), прежние QUERY_READ/STATUS. Это позволит искать место расхождения до query, но не даёт CREATE/FREE покрытия. Число точек ещё не принято как пригодное к включению: нужно проверить частоту hits, фильтр с указанными ограничениями, guards и корреляцию конкретных вызовов. Не добавлять одновременно lifecycle точки без причины; стоимость пяти событий нельзя оценить по двум без новой четырёхсоединительной пробы.

Это ещё не готовый stage/kit и не разрешённый новый Run. Если новый capture обоснован, отдельный stage/kit и сначала новая четырёхсоединительная проверка его actions/вмешательства; затем отдельное решение о bounded нагрузке. Прежние snapshots/kit не refreeze/Resume. До этого точки оставить отключёнными, новых Break/enable/Run не выполнять. Перед будущим USER Break/enable предупредить о паузе всейVM/Codex/RDP, recovery заранее на физическом ПК, g отдельно даже после ошибки.
