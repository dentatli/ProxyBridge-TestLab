# Символы загружены; следующий шаг — выбранные live-инструкции

USER console подтвердил локальный symbol path C:\PB-KD-Symbols-20261016, Path validation OK, три .reload /f без показанных ошибок, tcpip/fwpkclnt с pdb symbols из новой папки. Их headers совпадают с проверенным disk PE. `dt nt!_ETHREAD Cid` показывает +0x508 Cid:_CLIENT_ID; в конце отдельный g. Это подтверждение загрузки символов и доступности типа, не чтения PID/TID конкретного соединения, не whole live image hash и не работы точек. Private запись — `artifacts/diagnostics/pb-kd-symbol-recovery-20261016/live-symbol-observation.json`.

На диске и matching PDB офлайн проверены четыре функции для сокращённого наблюдения. DBH использовался только с локальным PDB, dumpbin — только с PE-файлом, без target/PID/debugger connection, build/install/SCM или product traffic. Из .pdata получены границы функций, PDB public symbols сопоставлены с их началами; байты выбранной дисассемблированной выборки сверены с PE. Код и PDB закреплены SHA в `artifacts/diagnostics/pb-kd-reconnect-review-20261016/current-code/functions.json`.

| Событие проекта | Функция и относительный offset | Нынешний RVA |
| --- | --- | --- |
| CREATE_POST | AlepCreateRedirectRecord+0x396 | 0x1088b6 |
| FREE_ENTER | AleRedirectRecordFree+0xd | 0x11d73d |
| FREE_POOL_RETURN | AleRedirectRecordFree+0x76 | 0x11d7a6 |
| QUERY_READ | WfpAleProcessSocketOption+0x2c4 | 0x12157c |
| QUERY_STATUS | WfpAleProcessSocketOption+0x47b | 0x121733 |
| ACCEPT_RETRIEVE_RESULT | WfpAleAuthorizeAccept+0xcaf | 0x1567b |
| ACCEPT_AFTER_STORE | WfpAleAuthorizeAccept+0xcbe | 0x1568a |

Эти места **ещё не проверены по live-инструкциям и не установлены как точки**. Относительные offsets здесь совпали с прежними после отдельной проверки текущего PE/PDB; это не разрешает повторить старые stage/guard/body. Существующих25 IDs нет, семиточечный проект не зарегистрирован. Назначение IDs и новый отключённый stage будут отдельным решением после проверки кода/форматов.

Статически: call accept использует IAT RVA0x24de00 → fwpkclnt.sys!FwpsNetBufferListRetrieveContext0; key5, output [RBP-28], после success — запись в [RDI+1c0]. В query NULL [RDI+1c0] ведёт к status C0000225 через WfpReportAppErrorAsNtStatus (RVA0x25180), который возвращает переданный status; эта небольшая helper-функция также проверена на диске. Это возможность кода, а не наблюдение исходного отказа или доказательство момента утраты записи.

## Одна USER остановка для проверки

Сохранить команды на физическом ПК заранее. Если на общей VM идёт другой согласованный тест, дождаться завершения. **Break останавливает всю PB-BUILD-W11-25H2, включая Codex и RDP.** Если уже есть активное kd>, повторный Break не нужен. Вводить каждую команду отдельно, Enter после каждой; весь список блоком не вставлять. Вывод прислать в чат, logopen не требуется.

1. `u tcpip!AlepCreateRedirectRecord+0x36c L0n20`
2. `u tcpip!WfpAleAuthorizeAccept+0xc7d L0n24`
3. `uf tcpip!AleRedirectRecordFree`
4. `u tcpip!WfpAleProcessSocketOption+0x2c4 L0n18`
5. `u tcpip!WfpAleProcessSocketOption+0x47b L0n12`
6. `.printf "PBKD_IDCHECK thread=%p pid=%I64x tid=%I64x\n", @$thread, @@c++(@$thread->Cid.UniqueProcess), @@c++(@$thread->Cid.UniqueThread)`
7. `g`

Пять выбранных дисковых фрагментов содержат125 инструкций, включая padding, который uf может не вывести. Они охватывают все семь предполагаемых sites. [u/uf](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/uf--unassemble-function-) читают код; ничего не устанавливать и не включать. IDCHECK читает только Cid текущего ETHREAD через matching types, без угаданных offsets, изменения registers или memory. Значения0 допустимы для idle/current thread и не доказывают nonzero owned PID/TID. Эта проверка не использует payload, endpoint/record memory или QPC.

При ошибке любой команды не исправлять её новыми flags и не повторять stage: сохранить сообщение, пропустить оставшиеся probes и **ввести g отдельно**. При новой остановке сохранить сообщение и снова отдельный g. После возобновления VM прислать полный вывод. Символы уже подготовлены, повторять downloads/reload без новой причины не требуется.

Дальше — офлайн byte comparison live/PE на выбранных sites, отдельно учесть import-call rewrite и другие различия, проверить IDCHECK. Совпадение этих фрагментов не является проверкой всего image, выполнения lifecycle или причины сброса. До этого нет установки точек/нового baseline kit/Run/нагрузки; старые frozen kits не переписывать/refreeze/Resume. Продукт и runtime другого чата не менять.
