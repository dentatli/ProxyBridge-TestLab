# Кандидат retrieve/NULL: заменить только query-точку 3

Основание: [matched328контроль](REDIRECT_BOUNDED_CONTROL_RESULT_2026-10-18.md) воспроизвёл32CoreAPI10022 с отключёнными точками, а предшествующий capture с двумя активными точками не содержал таких отказов. USER согласовал подготовку следующего профиля. Цель — сократить срабатывания query-точки на успешных соединениях и попытаться наблюдать retrieval у failed flow. Причинный механизм отказа и единственная причина различия серий не доказаны.

## Новая точка и сохранённая

Профиль `scripts/debugger/pb-kd-retrieve-null-candidate-20261018.json`,SHA256 `b0fbb8dfc62a0fbd323aba7a721769ac438ace846a923cb61dd2210361c47f91`,methodkd-retrieve-null-pair-candidate-20261018-v1. Registered/active=[2,3],inactive=[],двеактивные. ID2 retrievalreturn+0xcaf полностью сохранён из предыдущего профиля; его не перерегистрировать. ID3 заменяет QUERY_READ+0x2c4 на QUERY_NULL+0x2d0/RVA121588,ожидаемыйадресfffff8026a861588 в текущейзагрузке.

В проверенномUSERliveconsole SHA277062ca5cfefddb0a283b0efd904b1fadb50f1602acd27560f059c78538bb73 последовательность:

1. RVA12157c:movrdx,[rdi+1c0].
2. RVA121583:testrdx,rdx.
3. RVA121586:jne+0x2db,минуяNULLветку.
4. RVA121588(+0x2d0):movr8d,0C0000225h.

Выбранные4instructionbytes и вычислениеRVA/offset сверены офлайн с сохранённымliveconsole. Read-onlybootcheck по-прежнемуEvent12record16566/BootId113/StartTime06:22:30.5Z; новойзагрузки не наблюдается. Это не свежийполныйmemorydump/побайтнаяпроверкавсегомодуля.

Actionфильтруетr15d=980000dd и проверяетrdx=0,затем пишетPBKDNQUERY_NULL сrdi/rdx/r15d/rsp(endpoint/record_reg/ioctl/scope). Ненулевойrdx даётPBKDN_UNEXPECTED/capture=incomplete. gc находитсяпослеусловий. Толькоprintfаргументыизрегистров,безpoi/wo/$vvalid/ETHREAD.Cid/содержимогоrecord. В этойточкеstatusassignment ещёнеисполнен,такчтоeventнеявляетсяизмереннымreturnNTSTATUSquery.

## Ограничения

Успешные query больше не дают события3 и ихquery-timepointer не проверяется. Retrieval2 по-прежнему останавливает систему при попадании в соответствующую системную инструкцию дофильтра и остаётся источником возмущения. Снижение общей задержки/воспроизведение не гарантированы.

УNULLсобытиянет независимогоPID/TID/socket/seq/QPC. Привязка кCore/native должна использоватьendpoint/peerportretrieval и проверенныйпорядок/полнотуconsole; припропуске/дубле/reuse неоднозначность сохраняется. Scope не уникальныйflowID. Отсутствиеretrieval не доказываетbypass. EAX≠0retrievaloutputrawнельзя считатьвалиднымрезультатом. ПозднийNULL приretrievalEAX0/nonnull сузитинтервал,но не докажетstore/free/lifetime.

Новый action пока не зарегистрирован и не исполнялся. Успешная регистрация не подтвердит runtime ветки. Four-only smoke безNULL подтвердит лишь ограниченный успешный путь; QUERY_NULLaction остаётсяpending донастоящегосрабатывания. Дляновогопрофиляпонадобитсяотдельныйkit/manifest; старыеRunнеповторять/неResume/refreeze.

## Защита от прежних ошибок

Старыеprofile/stage/liveevidence сохранены и сверены неизменными. Применены ограничения,известныеизDejavuкоррекции:никакихкомментариев/semicolonвисполняемомstage. Новый executable stage/ZIP не создаётся; USERвводиткомандыпоодной. Privateaudit `artifacts/diagnostics/pb-kd-retrieve-null-candidate-review-20261018`:generator/review/manual-bp3-command.txt. ПровереныASCII/escaping/сбалансированностьguard/4printfаргумента/финальныйgc/отсутствиемemorydereference. Это structuralchecks, не исполнениеWinDbgparser и не заявление обавтоматическомперехватеDejavu.

## Следующий USER шаг

Заранеесохранитьrecoverybd2/bd3/bl/gпоодной. ПередBreakпредупредить:останавливаетсявсяVM/Codex/RDP. blдолженпоказатьтолько2/3d с прежнимиactions,3+0x2c4. При другомinventoryне менятьточки,отдельныйgиreview. Приожидаемомсостоянии:bc3отдельно,blтолько2d. Предупредитьпередbp3:создаётсяenabledточка,VMдолжнаоставатьсяостановленнойдоbd3. Ввестиодинразновыйbp3+0x2d0 action,затемbd3/bl/.bpcmds/gкаждуюкомандуотдельно,gдажеприошибке. Finalожидается2/3d,3наfffff8026a861588,2неизменна.

Никакихbe/Runнагрузки. Сохранитьполныйconsoleдляregistrationreview;после негоотдельнаяподготовкасобственногокомплекта. Не повторятьbc3илиbp3поверхужеизменённойточки. АгентнеуправляетWinDbg/не запускаетпродукт/трафик/драйверы/системныеизменения.
