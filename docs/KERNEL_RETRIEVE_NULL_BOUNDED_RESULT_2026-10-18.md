# Retrieve/NULL bounded: retrieval уже возвращает NOT_FOUND у24отказов

USER Run `pb-kd-retrieve-null-bounded-run-20261018-073047-8b2a010e`,07:30:47.680–07:33:05.080UTC. При попытке последующегоBreak USERне сразу получилостановку;позднееприслалbl2/3e→bd2/bd3→bl2/3d→отдельныйg. Отключениеподтвержденотекстомпоследующегосообщения,неавтоматическимуправлениемотладчиком. ПричиназадержкиBreakнеустановлена. ПоказаннойMemoryaccess/Syntax/Badregisterошибкилоггеранет;не смешиватьсстарымсбоемpoint17.

## Native иkernelнаблюдения

| Фаза | Попытки | Успех | СвязанныйCore10022 | Unidentifiedconnect10061 |
| --- | ---: | ---: | ---: | ---: |
| baseline | 4 | 4 | 0 | 0 |
| load-64 | 64 | 64 | 0 | 0 |
| load-256 | 256 | 214 | 24 | 18 |
| recovery | 4 | 4 | 0 | 0 |
| Всего | 328 | 286 | 24 | 18 |

Coremetadataсодержит310queries/одинPID16864/TID15928;всеCTXTIMINGинтервалыqueryнеперекрываются.24originalAPIreturn-1/error10022(seq283..306)связаныснеуспешнымиownednativeconnections.18unidentified10061не имеютидентифицируемыхendpoint/GUIDинеобъясняютсяэтимkernelreview. NativeCAPTURE_INCOMPLETEиwrapperFAILEDсохраняются;оригинальныйотчётнепереписан.

Consoleattachment8370650d,44945bytes,SHA256 `d3be8d87f72f9c5be01570ef4b532f6c31050de511d642bd6d2506315918ff18` содержит317RETRIEVE_RESULT:292EAX0 и25EAXC0000225,а также24QUERY_NULL. НетactualPBKDR_UNREADABLE/PBKDN_UNEXPECTED. Увсех24QUERY_NULLRDX=0/IOCTL980000dd.

## Связанныецепочки

Длякаждогоиз24failedCorequeries найденretrievalссоответствующимpeerportизnative/Coremetadata,endpointсовпадаетсоднимпоследующимQUERY_NULL. Порядок24NULLeventsсовпадаетспорядком24failedCorequeries. У23failedflowsодинretrievalкандидат,уseq283дваодинаковыхкандидата(EAXC0000225/output_raw0/тотжеep/NBL)доегоединственногоNULLevent. Поэтомунеутверждать24строгооднократныхвызова/неудалятьдублькакненужный. Однаизначальнаяпроверкаauditошибочнопредполагалаединственныйretrievalнапорт;онаотверглаseq283,послечегоreviewсохранёнсобоимикандидатамиипроверкойendpoint. Этоошибкадопущенияанализатора,неповторRun/несбойлоггера.

Во всех25связанныхretrievalстрокахEAX=C0000225/output_raw0,ипоследующийNULLдлякаждогосвязанногоendpoint. Output_rawприошибке—лишьсыроесостояниеслота,невалидныйрезультатполучения. Примерseq283/peer65341:retrievalendpointffff99875d3bec50→QUERY_NULLтогожеendpoint→Core10022/nativefail. Полные24цепочки/строки/NBL/ConnectionIdвprivateaudit,неспискомсырогологавGit.

В25строкахдля24failedflows6различныхNBLaddresses. Ихравенство/различиене доказываетpacketidentity/lifetime/reuse/одинTCPretry. Привязкаусловнанаполнотупредоставленногоконсоля:нетнезависимыхkernelPID/TID/socket/seq/sharedQPCвNULLсобытии. Endpoint/peerport/orderпроверены,нонеподменяютнепрерывныйlifetime. Успешныеquery-timepointersнеизмеряются,полноепокрытиевсехflowнеобъявляется.

## Чтосужено

Сохранённыйstaticreview19matchingtcpipinstructions/IAT24de00идентифицируетвызов `fwpkclnt!FwpsNetBufferListRetrieveContext0` сkey5перед+0xcaf. ТекущийfrozenimageSHAтотже,USERlivebytesreturn/test/storeизтойжезагрузкипроверялисьранее. EAXнаблюдалсянепосредственнопередtest. Штатныйкодприненулевомрезультатепропускаетstoreoutputв[rdi+1c0];позднееQUERY_NULLпоказываетNULL,загруженныйвRDXизэтогополя. Выполнениевсехпромежуточныхинструкцийнепротрассировано.

Дляэтих24flows **получениеконтекстауже неуспешновобработкеaccept**,доисходногоqueryCore. Версия«этотretrievalуспешновернулненулевойконтекст,азатемонпропалпередCore»неподдерживаетсяданнымизахваченныхвызовов. Этонеисключаетболееранниененаблюдавшиесясоздание/прикрепление/утратуилидругиепутижизниrecord.

NTSTATUSretrievalизмерен:EAXC0000225(NOT_FOUND). **ReturnNTSTATUSсамогоqueryвэтойсериипо-прежнемунеизмерен**:QUERY_NULLстоитпередегоstaticприсваиванием. Nativeфлагntstatus_observed=falseнепереписывается;отдельныйkernelreviewразличаетэтидвасобытия.

Неустановлено,почемуretrievalненашёлконтекст:оннебылсоздан/прикреплён,наNBLдругойlifetime,былснятранееилиестьинойпуть. Windowsbug/driverbug/tableoverflow/backlogcauseне доказаны. Причиннаярольdebuggerвразницесерийостаётсягипотезой,несмотрянаболееудачнуюловлюисходногоотказановымпрофилем.

## Сохранностьистоп

Все8329frozenSHAсовпали,63captureinputs(62runfiles+attachment)неизменнызаанализ. Workloadвсе4фазыCOMPLETED/workers_stopped/driver_stop_observedtrue,CLIgraceful/post_stop_verifiedtrue/forcedstopfalse/errorпуст. Privateaudit `artifacts/diagnostics/pb-kd-retrieve-null-bounded-result-review-20261018`:review.py/review.json/events.json/saved-console.txt. Логи/китывGitне добавлять.

Runизрасходован,2/3d/gподтверждены. Неповторять/не640/неbe. Следующийшаг—офлайнразобратьсамretrieval/lookupkey5иранниеcreate/associate/removeпути,чтобывыбратьминимальноедополнительноесвидетельство. Не возвращатьстаруюнеисправнуюpoint17/25pointstaging. Новыепрофиль/kit/Runпоканеподготовлены. Продуктне менятьдо установленияпричины;агентнеуправляетWinDbg/незапускаеттрафик. BeforeUSERBreak/enablewholeVM/Codex/RDPwarning,recoveryзаранее,gотдельноevenerror. Командытольковчате,безDesktopдубликатов.
