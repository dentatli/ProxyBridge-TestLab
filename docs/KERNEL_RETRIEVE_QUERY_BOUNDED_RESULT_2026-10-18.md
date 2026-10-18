# Retrieve/query bounded: исходный отказ не воспроизведён

USER выполнил один Run `pb-kd-retrieve-query-bounded-run-20261018-065211-af6e15fb`, 06:52:11.418–06:55:09.278 UTC, фазы4→64→256→4. Оба breakpoint отключены в конце сохранённого console, затем отдельныйg. Повторного запуска агент не выполнял; результат не является PASS продукта или доказательством причины.

## Наблюдения

| Фаза | Попытки | Успех | Отказы native |
| --- | ---: | ---: | ---: |
| baseline | 4 | 4 | 0 |
| load-64 | 64 | 64 | 0 |
| load-256 | 256 | 235 | 21 |
| recovery | 4 | 4 | 0 |
| Всего | 328 | 307 | 21 |

Все21отказа — UNIDENTIFIED_NATIVE_CONNECT_FAILURE_10061 вload-256. У этих CTSстрок нет идентифицируемых endpoint/ConnectionId, поэтому нет достоверной связи с конкретным kernel endpoint/redirectrecord. Не считать их Corequery10022 или доказанным переполнением очереди. Все307исходныхCorequeries имеют APIreturn/error0/0 и IPV4 context. QuerykernelNTSTATUS не измерялся.

Console attachment4a1c91c2,89180bytes,SHA256 `bf6cbe7a24e7b941e7576ba1eb0a3baeaac0f6c3feb64f8433874a3440d03a63`:305RETRIEVE_RESULT и307QUERY_READ. У всех305retrieval EAX0/outputnonnull; у всех307queries recordnonnull. Не показано UNREADABLE/Memory access/Syntax/Bad register errors. Начальныйbl2/3d → be2/be3 → bl2/3e → g → события → manualBreak/bl2/3e → bd2/bd3/bl2/3d → отдельныйg. Других точек не показано.

## Привязка и границы покрытия

CorePID/TID12188/13948 совпадают с kernel2f9c/367c.307неперекрывающихсяCTXTIMINGинтервалов и307native/Coremetadata задают порядокquery. Кандидатыretrieval проверены поendpoint, nativepeerport изrawnetworkword и положению доquery. Это условная привязка по полноте сохранённого console, без независимогоkernel socket/seq/sharedQPC или непрерывногоlifetime.

- 289query имеют ровноодного предшествующего кандидатаretrieval, указателиoutput/query совпадают во всех289.
- 8query(seq6/12/89/91/164/173/230/300) имеют по2предшествующих кандидата с тем жеendpoint/peerport. Обаoutput равныqueryrecord; выбрать единственное событие нельзя.
- 10query(seq9/26/29/33/55/185/208/232/276/297) не имеют подходящегоretrievalevent. Все10Corequeries успешны. Отсутствиестроки не доказывает bypass/потерюконтекста; механизм пропусков/повторений не установлен.

Итого305=289+16retrievalevents,307=289+8+10queries. Не сводить неполноту к «не хватает двух событий» и не заявлять полного покрытия. Queryelapsed122.2462–299.9019ms включает влияниеKD; не сравнивать как обычную API latency.

WrapperFAILED сCONNECTION_REDIRECT_DIAGNOSTIC_CAPTURE_INCOMPLETE вызван отчётом с21unidentified10061. Все4фазыCOMPLETED,workers_stopped/driver_stop_observedtrue,CLIgraceful/post_stopverifiedtrue,forcedstopfalse/errorпуст. After:serviceStopped/knownWFPobjectsне наблюдались/visibility_completefalse. Полную системную очистку не утверждаем. Ни признаков ошибки debugger logger, ни исходной NULL-query ветки в этом capture не показано.

## Сохранность доказательств

Все8330frozenSHA runtimeplan совпали;63captureinputs(62runfiles+console) неизменны за времяанализа. Исходные отчёты не переписаны. Приватный воспроизводимый audit `artifacts/diagnostics/pb-kd-retrieve-query-bounded-result-review-20261018/`:review.py/review.json/pairs.json/events.json/saved-console.txt. Не добавлять вGit. NativeCAPTURE_INCOMPLETE остаётся актуальным даже при успешном разборе наблюдавшихся kernelсобытий.

## Вывод и следующий офлайн шаг

Серия не содержит исходного отказа: она не различает retrievalfailure и потерю после retrieval для отказавшегоCoreflow, поскольку такогоflowздесьнет. Успешные307connections не доказывают исправление или отсутствиеWindows/driverbug. Queue/retry по-прежнему гипотеза. Изменение расписанияиз-заKD правдоподобно, но причинная роль отладчика не доказана этим запуском.

Следующий кандидат: оставить2наretrievalreturn, перенести3сQUERY_READ+0x2c4 наNULLветку+0x2d0 (RVA121588, текущийадресfffff8026a861588). В уже проверенномliveкоде сначалаmovrdx,[rdi+1c0],testrdx,rdx,jne+0x2db; приNULL исполнение приходит к+0x2d0 `mov r8d,0C0000225h`. Там можно логироватьendpoint/RDX/IOCTL изрегистров, не читаяCID/recordmemory. Это наблюдение выбораNULLветки, не измеренный returnNTSTATUS всегоquery. Существующий3непереставлен.

При таком изменении успешныеqueryeventsнебудутлогироваться: теряем их pointerсопоставление, зато исключаем срабатыванияquerypoint науспешномпути. Предполагаемое снижениевозмущения требует проверки; retrievalpoint остаётся системным trap дофильтра, числоактивныхточек остаётся2. Сохранить native/Coremetadata для всехflow. Не обещать полное покрытие, причину10061 или воспроизведение.

**Стоп:** одинсогласованныйRunизрасходован. Не повторять/не640/неbe автоматически, старыеstage/kitsнеизменять/неResume/refreeze. Продолжать толькоофлайн подготовку собственного изменённогопрофиля/плана; доегоreview и нового согласованного USER debugger/runtimeшага ничего не переставлять. ПередкаждымBreak/enable/step предупреждать о паузе всейVM/Codex/RDP, recoveryзаранее, gотдельноevenerror. Продукт не менять до установления причины.
