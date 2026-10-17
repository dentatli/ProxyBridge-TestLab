# Retrieve/query: сбой регистрации первого stage и исправление r2 — 2026-10-17

Первый USER stage не зарегистрировал новую точку2. После USERbc2 и неудачнойзагрузки итоговыйbl содержит только3/4d, .bpcmds тоже только3/4, отдельныйg показан. Новых RETRIEVE_RESULT events нет, Run не выполнялся. Это сбой логгера/staging, не наблюдение причины TCP.

USER console attachment `db8fa300-765f-4f64-9b74-95dbae597e3e/Вставленный текст.txt`,7978bytes,SHA25673b2258a38438e64b9467e02a60a6b80ad0cf87121f09e0a3ae21cb6625e162a. Копия/failed-registration-review сохранены в privateaudit `artifacts/diagnostics/pb-kd-retrieve-query-registration-repair-20261017/`. Исходныйconsole,первыйstage/profile/archive проверены неизменными.

## Наблюдаемые ошибки и предел объяснения

Две Syntax error относятся к комментариям `$$ ...; ...`. Ошибка в подготовленномstage доказана: точка с запятой завершает комментарий, остаток строки становится командой. Это документированное правило [Microsoft $$ Comment Specifier](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/-----comment-specifier-). Проверка только баланса скобок/quoting в первомкандидате не могла выявить все ошибки исполнения WinDbg.

В console также отдельно видны Bad register error для `Run` и pass-count parsing error для `p2 ...` вместо исходного `bp2 ...`. Причина появления отдельногоRun/исчезновенияb не установлена. Командаp2 отвергнута с ошибкой; её нельзя считать подтверждённымsingle-step. Первыйstage имелLF-only bytes. Вr2 выбранASCII/CRLF, но это мера совместимости, не доказательство механизма искажения. Документация [$< Run Script File](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/-----------------------a---run-script-file-) описывает передачу команд из файла, но не подтверждает конкретную причину этой потери символа.

## Что удалось проверить

USERu+cafL8 подтверждает восемь ожидаемыхliveinstructions поRVA1567b/1567d/1567f/15683/1568a/1568d/1568f/15697, без byte differences. Изначальноknown2/3/4d, послеbc2 только3/4d, и вконце3/4d. Тела query3/4 неизменны. Новаярегистрация/actions/stack reads не подтверждены, готовитьfreshfourkit доуспешногорегистрационногоreview нельзя.

## Отдельный r2

Новые файлы `scripts/debugger/pb-kd-retrieve-query-add-disabled-20261017-r2.wdbg` и `scripts/debugger/pb-kd-retrieve-query-candidate-20261017-r2.json`. Старые файлы не переписаны. Stage ровно четыреASCIIстроки, CRLF послекаждой, безBOM/комментариев:

1. bp2+0xcaf с прежнимguardedRETRIEVE_RESULT action.
2. bd2.
3. bl.
4. .bpcmds.

Нетbc/be/g/новых3/4. Body иquery3 byte-exact первомукандидату. Preconditionизменена нафактическое состояние: только3/4d,slot2absent. USERbc2 повторять не надо. Старый execution/action контракт(порты/EAX/output/guards/NULL/statuserror/gc) не менялся. ПровереныactualCRLFbytes,точные4команды,отсутствиекомментариев, ZIPCRC и unpackedbyteidentity; это не запускWinDbgparser/продукта/нагрузки.

StageSHA95fcc1ebd74e9d91bf50eb4ca6fa9c892010a12ba790e9a242a30493d4eb04c6.

ProfileSHAc915afa3d8b0188c3cde343de51d3b225ef33290605fc1d811bc1b0daeba9866.

Архив `C:\Users\LabAdmin\Desktop\PB-KD-Retrieve-Query-Candidate-20261017-r2.zip`,2848bytes,SHA2564C05D7D875C14C406B85C79E1FFA64FF2787EDAC19DF42BEA94BC136A83258C3. Толькоnewr2stage/profile/README. НовыйhostdirC:\PB-KD-Retrieve-Query-Candidate-20261017-r2, DownloadsD:\Загрузки; autoSHAcompare/throw, существующуюdestinationнеизменять. Старыйархив не использовать.

## Стоп-пункт

USER нужно повторить только disabledregistration новымr2. Это исправление уже согласованного следующего замера, не новыйпрофиль и не дополнительнаянагрузка. Не запрашивать общее разрешение заново. Заранее сохранитьrecoverybd2/bd3/bd4/bl/gпоодной;gвсегдаотдельноevenerror.

ПередBreak предупредить: останавливается всяVM/Codex/RDP. USERbl — только3/4d/slot2absent. Если2появилась илиестьдругиеточки, stageне загружать и ничего автоматическинеудалять. USERlive8instructionsуже совпали вприсланномлоге; безновогопризнакаreboot/codechange повторuнеобязателен.

Передstagewarn: новаяbp2начинаетenabled, всяVMдолжнаоставатьсяостановленнойдобd2. Одинраз `$<C:\PB-KD-Retrieve-Query-Candidate-20261017-r2\pb-kd-retrieve-query-add-disabled-20261017-r2.wdbg`. Вконцеожидаются2/3/4d,2+0xcafRETRIEVE_RESULT,3/4unchanged;затемgотдельноevenerror. Прислатьполныйconsole. НиbeниRun. Послеуспешногоreview — freshfourkit/newmanifest икороткаяпроба, старыеkitsнеизменять/неResume/неиспользоватьсэтимпрофилем.
