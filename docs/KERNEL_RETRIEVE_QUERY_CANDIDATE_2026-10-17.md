# Кандидат retrieve/query: замена отключённой точки2 — 2026-10-17

USER «давай попробуем следующий замер» продолжил исследование после восьми NULL уже на accept join. Подготовлен новый отдельный кандидат: ID2 переносится с `tcpip!WfpAleAuthorizeAccept+0xcbe` на `+0xcaf` (RVA1567b), непосредственно после возврата `FwpsNetBufferListRetrieveContext0` и до проверкиEAX/store. ID3QUERY_READ сохраняется, ID4QUERY_STATUS остаётсяd. Активных точек после будущего согласованного включения будет две.

## Новый event

`PBKDR RETRIEVE_RESULT ep=... nbl=... local_raw=... peer_raw=... status=... output_raw=...`

Шесть аргументов: RDI/RBX, порты `[rbp-7c]`/`[rbp-7a]`, EAX, сырой output-slot `[rbp-28]`. ФильтрCore34010/rawda84. Нет фильтра по status илиNULL, нет фильтра по currentPID. NBL иendpoint печатаются как адреса без чтения их содержимого. Ненулевойstatus не гарантирует валидности output_raw; не выдавать сырой слот за действительный context при ошибке.

Все чтения портов после `$vvalid(rbp-7c,4)`, output после `$vvalid(rbp-28,8)`. Ветки PBKDR_UNREADABLE помечают capture=incomplete; gc расположен после ветвлений. Это структурная проверка, не исполнение parser/actions/веток ошибки в WinDbg и не общая гарантияgc safety.

EAX здесь является непосредственным результатом вызова: на успешном store-путиjoin он уже заменялся указателем и потому прежний ESI/EAXjoin не давали нужного статуса. Новыйreturn event не доказывает фактическогоstore/весьlifetime; ID3 покажет последующее состояние endpoint для сопоставленногоquery. Если returnevent отсутствует или неоднозначен — неполное покрытие, не доказательство bypass. Независимого kernel socket/seq/sharedQPC нет.

## Проверки файлов

Проверены10 byte ranges текущего `tcpip.sys` SHA b0683bd7ed0f309e63b4e6e71675d8f04cfb0ea5533c3f5e8a13c6daca3b595a: сохранение портов, output-slot setup, возврат/test/ветка/store. `[rbp-28]` соответствует текущемуRSP+138 при рассматриваемомframe; это не чтение произвольногоRSP+offset. Прежний USERlive selected bytes подтверждал85c0 поRVA1567b. Перед новой регистрацией USER повторно просматривает8инструкцийreturn/store/join; при отличиине менятьточки.

Старый QUERY_READ action и его quoting сохранены byte-exact. Проверены6printfargs/quote roundtrip/сбалансированныеветки/порядокguards. Stage содержит только одинbp2→bd2→bl→.bpcmds, ниbc/be/g, ни изменения3/4.68 старых inputs (включаяпоследнийcapture/console и прежниеstage/profile/staticproof) проверены неизменными. Продукт/трафик/драйвер/debugger агентом не запускались и не менялись.

Stage: `scripts/debugger/pb-kd-retrieve-query-add-disabled-20261017.wdbg`,SHA d83ba15c44f70dc3a912677dcf7a8c4ed05afe39b3b284c2ae98e7f7a03a52aa.

Profile: `scripts/debugger/pb-kd-retrieve-query-candidate-20261017.json`,SHA e37e14426196eaedc69fedd4a4b46bd84038de6968efac29094608afe69ed5e0.

Desktop archive `C:\Users\LabAdmin\Desktop\PB-KD-Retrieve-Query-Candidate-20261017.zip`,3084bytes,SHA256 E490D8C8599E9B8E662478889611797DCEBB2CB8F26DE08C4984A2C2DF638E48. ZIP содержит толькоnewstage/profile/README; распакованные bytes сопоставлены с исходными. HostDownloadsD:\Загрузки; новая destinationC:\PB-KD-Retrieve-Query-Candidate-20261017. Автоматически сравнить archiveSHA и отклонить существующуюdestination, безoverwrite. Архив/privateaudit вGit не добавлять.

Private audit `artifacts/diagnostics/pb-kd-retrieve-query-candidate-review-20261017/`: генератор/проверки/protectedinputs/validation/hostREADME. Первое формирование README остановилось наASCII encoding длинного тире; исправлено UTF8 и упаковка завершена без запускапродукта. Старые файлы не переписывались.

## USER порядок замены в отключённом состоянии

Сначала сохранить на физическомhost recovery: bd2,bd3,bd4,bl,g — по одной/g отдельно даже после ошибки. ПередBreak предупредить: останавливается всяPB-BUILD-W11-25H2VM/Codex/RDP. Если ужеkd>, Breakповторно не нужен.

1. USERbl: только2/3/4d;2 должнабыть прежнейточнойACCEPT_STATE+0xcbe,3/4прежниеquerypoints. При несоответствии не удалять/не загружатьstage.
2. USERu tcpip!WfpAleAuthorizeAccept+0xcaf L8: ожидаются testEAX/jne+cbe/movRAX,[rbp-28]/store[rdi+1c0]/testRBX/je+ccb/btr[rbx+88],17/cmp[rbp-60],r12. При отличииg отдельно,беззамены.
3. USERbc2 отдельнойкомандой; затемbl: только3/4d,slot2нет. Это управляемая замена известногоID2; stage сам не очищаетточки.
4. Передзагрузкойwarn: bp2 сначала создаётся включённой; всяVMдолжнаоставатьсяостановленной доbd2. Одинраз$<C:\PB-KD-Retrieve-Query-Candidate-20261017\pb-kd-retrieve-query-add-disabled-20261017.wdbg. Не повторять поверх2. Файлсоздаётnew2+bd2 и выводитbl/.bpcmds. Ожидатьтолько2/3/4d,new2RETRIEVE_RESULT+0xcaf,3/4unchanged.
5. Отдельныйg даже при ошибке; приошибке передg recoveryпоодной,безbe/Run. Прислатьвесьconsole.

## Стоп-пункт

Готовы файлы кандидата, регистрациянаhost ещё не проверена. Следующий USERшаг — только описанная disabled replacement/review, безвключенияточек/Run. Не просить повторного общего разрешения на уже предложенный следующий замер; последующие runtimeшаги сделать конкретными и согласовать в пределах нового профиля послеготовности.

Послеconsole review подготовитьfreshfour-onlykit с новымпрофилем и собственнымmanifest, затем USERпроба4 передрешением оbounded. Прежниеfour/328kits/замороженныеmanifest не менять/неResume/не использовать дляновогопрофиля. Причинапотериrecord/ошибкаWindows/драйвера/таблица/окончательныйfix пока не доказаны.
