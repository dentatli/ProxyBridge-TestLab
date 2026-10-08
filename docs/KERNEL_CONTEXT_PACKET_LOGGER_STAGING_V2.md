# Повторная регистрация packet logger: V2

**Текущий этап:** V2 журнал 21:18 остановился до изменения точек на отсутствующем `@$bp14`. V2 source/archive/frozen kit сохранены неизменными. Не выполнять дальнейшую загрузку/Run по этой странице; текущая инструкция — [регистрация V3](KERNEL_CONTEXT_PACKET_LOGGER_STAGING_V3.md).

**Последний USER журнал 21:13:** снова выполнен старый путь `C:\PB-KD-Packet-Logger-20261008\commands\pb-context-packet-stage.wdbg`, без `V2` в папке и без `-v2` в имени файла. Echo guard побайтно соответствует прежнему исходнику с `&&`; эта попытка не проверяла V2. Те же 14 точек до/после, все d, адреса/тела и .bpcmds без изменений. SHA журнала `db5eb51a13a5f3876f7e6549c28873dde53bf993fbeb96efc62a371122c5e038`. Ни body, ни workload не выполнялись. Архив V2, все его commands и 69 SHA свежего kit повторно сверены без изменений. Audit: `artifacts/diagnostics/pb-kd-packet-stage-path-review-20261008/validation.json`.

2026-10-08. USER stage log `pb-context-packet-stage_03f8_2026-10-08_19-33-38-725.log` (13939 bytes, SHA256 `a5230b98ded524b1a5269bd40102bdc786e409ecb4061d40662038cb0032ed3f`) показал ошибку моего скрипта: `Numeric expression missing from '& (@$bp1 ...'`. MASM отверг `&&` в первом guard. До body выполнение не дошло. Начальный и конечный bl содержат те же 14 разрешённых точек 0..13, все d; адреса и тела совпали, .bpcmds подтвердил каждое тело. Logclose записан; отдельный последующий g за пределами закрытого журнала не наблюдается. Это ошибка регистрации диагностического logger, не новое свидетельство ошибки драйвера.

## Исправление и проверка

Новые stage/кодовый guard/body с суффиксом `-v2` используют `and` между заключёнными в скобки сравнениями. Исправлены обе проверки до регистрации и условия точек 16/17/20, а не только первая строка. [Microsoft документирует `and`/`&` для MASM и результат сравнения 0/1](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/masm-numbers-and-operators). Поэтому побитовое И даёт 1 только при истинности всех сравнений. Short circuit не предполагается: прежние stack-slot reads в условиях остаются теми же; вложенное чтение output record у точки 20 остаётся внутри true body. Все адреса, поля и остальные команды сохранены.

Подготовлены отдельные `Invoke-KdPacketBaselineV2.ps1`, `pb_prepare_kd_packet_baseline_v2.py` и versioned manifest. Старые источники включены в frozen plans, поэтому они не переписаны. 180 защищённых записей hash (44 прежних USER files, 62 hashes used kit, 69 hashes предыдущего packet kit, планы и новые USER captures/archive) проверены без изменений.

Новый files-only комплект `pb-kd-packet-baseline-preparation-20261008-144412-f4ffe1ac`: 69 frozen SHA exact, PS5 Prepare/Inspect и PS7 Inspect прошли. Policy prefix PS5/PS7 принял valid и отклонил по семь повреждённых вариантов. Неизменённый workload prefix в обеих версиях подтвердил три pinned binaries и bundle `a0e0cf31…`. Python syntax и PowerShell AST проверены. Не выполнялись Run, traffic, SCM, сборка/подпись/установка драйвера или управление target debugger.

Отдельная попытка Evaluate констант через локальный SDK DbgEng без target вернула E_UNEXPECTED (`0x8000ffff`). Она не подключалась к VM, не исполняла debugger commands, не читала target memory и не регистрировала точки. Поэтому runtime grammar/условия новой версии пока не считаются проверенными. Следующий ручной шаг проверяет регистрацию; исполняемые memory conditions, gc, owned PID/TID и lifecycle coverage останутся pending до отдельного baseline. Корень исходной ошибки C0000225/WSA10022 ещё не доказан.

## Только следующий шаг на физическом ПК

Архив на Desktop VM: `PB-KD-Packet-Logger-V2-20261008.zip`, 6783 bytes, SHA256 `97f871686e259800f94d1d88795d951011670720378a52c4095942f62d0c8d77`. Содержит три command files, READ-ME, expected-points и file-hashes; CRC и byte roundtrip проверены. Старый архив не заменять. Распаковать весь новый архив на физическом ПК в `C:\PB-KD-Packet-Logger-V2-20261008`, сохранив подпапку `commands`.

До Break, в обычном PowerShell на **физическом ПК**, проверить именно распакованный V2 entry:

`Get-FileHash -LiteralPath 'C:\PB-KD-Packet-Logger-V2-20261008\commands\pb-context-packet-stage-v2.wdbg' -Algorithm SHA256 | Select-Object -ExpandProperty Hash`

Ожидаемый SHA256: `88363D6838AE4698BA422AD9598128904FA508CC8FE21EC9A37D6BA612159A90`. Если файл не найден или hash отличается, не нажимать Break и не загружать script: сначала исправить копирование/распаковку, сверить файл повторно. Не переименовывать V2 файлы в старые имена: entry обращается к двум другим V2 files по полным путям. Это проверка файла на физическом хосте, не запуск диагностики.

**Break останавливает всю Windows VM, Codex и RDP.** Заранее подготовить команды на физическом ПК. Внешние команды вводить по одной, Enter после каждой, не одним блоком.

1. В WinDbg на физическом ПК нажать Break, затем отдельно:

   `.logopen /t C:\Users\Administrator\pb-context-packet-stage-v2.log`

   `bl`

   `.expr`

2. Продолжать только при ровно 14 прежних разрешённых точках 0..13, все d, тела прежние и MASM. Если иначе, пропустить script, `.logclose` и `g` отдельно, отправить журнал.

   `$<C:\PB-KD-Packet-Logger-V2-20261008\commands\pb-context-packet-stage-v2.wdbg`

   `bl`

   `.bpcmds`

   `.logclose`

   `g`

3. Ожидаются BODY_END, ровно 25 разрешённых точек 0..24, все d, без ошибок/REFUSED. Скрипт заменяет только 1/2/10/11, добавляет 14..24; остальные 10 сохраняются. После каждой регистрации точка немедленно отключается; target автоматически не возобновляется. Script не включает точки и не запускает workload.

4. При ошибке не повторять загрузку и ничего не включать. Сохранить bl; любую присутствующую нашу точку e отключить по известному ID (например `bd [0n14]` для присутствующей точки 14), повторить bl. Затем `.logclose` и **g отдельно даже при ошибке**. При новой остановке сохранить сообщение и снова g отдельно. Прислать журнал регистрации до enable/Run.

Не загружать internal body/code-gate напрямую, прежние stage/candidate/patch или новый entry повторно. Symbols не перезагружать без новой причины. Guard проверяет адреса/свободные IDs 14..31 и первые два байта 15 instruction boundaries, а не полный live image hash. Состояние d/все тела/дополнительные номера проверяются вручную. Вложенные `$$<` отделены semicolon внутри .if; внешние `$<` и g всегда отдельные.

Новый комплект для четырёх соединений подготовлен только файлами. Его Run пока не давать: сначала проверить USER stage log. Старый kit 142037 и used kit 111941 не refreeze/Resume. Позднее нужны enable → четыре соединения → disable и разбор совместного журнала; полная нагрузка не разрешена на основании одной регистрации. Audit: `artifacts/diagnostics/pb-kd-packet-stage-masm-review-20261008/`.
