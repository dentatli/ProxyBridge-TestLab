# Регистрация packet logger V3

USER журнал V2 21:18 (`pb-context-packet-stage-v2_03f8_2026-10-08_21-18-09-980.log`, 13317 bytes, SHA256 `93f0399225ea84a77eec03a0b46e456ab096c261975f60335c33ce35706b6894`) остановился на `Bad register error at '@$bp14 == 0)...'`. До code-gate/body выполнение не дошло. Те же 14 точек 0..13 до и после, все d, адреса/тела/.bpcmds совпадают. Logclose записан; последующий g вне закрытого журнала не наблюдается. Ошибка относится к моему ограничителю регистрации, не доказывает новую ошибку ProxyBridge.

[Документация Microsoft](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/pseudo-register-syntax) описывает ноль для `$bpNumber` при отсутствующем ID. Этот live log такого поведения для `@$bp14` не подтвердил. Причину отличия от документации не утверждаем; не пробуем угадывать альтернативный синтаксис отсутствующих псевдорегистров.

В V3 удалены обращения к отсутствующим 14..31. Остались проверки адресов **существующих** 0..13; полный состав точек теперь обязательная ручная проверка по bl. Это условие допуска к загрузке: ровно 14 известных разрешённых точек, все d, прежние тела, никаких дополнительных IDs. При отличии script не загружать: ручная проверка защищает от перезаписи чужих/уже добавленных точек.

Тела всех 15 заменяемых/добавляемых точек и ограниченный кодовый guard V2 сохранены без изменений. Изменены только entry inventory guard, комментарии и физические пути версии. Source ASCII/CRLF, 14 existing-address checks, ноль missing-ID reads, 15 code sites, exact point-body delta проверены офлайн. Архив CRC и byte roundtrip проверены. 253 защищённых hash entries, включая старые captures/plans и 69 SHA kit 144412, совпадают. Audit `artifacts/diagnostics/pb-kd-packet-stage-v2-runtime-review-20261008/validation.json`. Ни target debugger control, ни Run, build/install/SCM/traffic агент не выполнял.

## На физическом ПК, до Break

Перенести `PB-KD-Packet-Logger-V3-20261008.zip` с Desktop VM, распаковать **целиком** в `C:\PB-KD-Packet-Logger-V3-20261008`, сохранив `commands`. ZIP 6717 bytes, SHA256 `1db46ddf82e3812e6600d8fcfb2dc0306bf567e59320bc856653c1bf72416a51`. Старые архивы сохранять, internal body/code-gate напрямую не загружать.

В обычном PowerShell физического ПК:

`Get-FileHash -LiteralPath 'C:\PB-KD-Packet-Logger-V3-20261008\commands\pb-context-packet-stage-v3.wdbg' -Algorithm SHA256 | Select-Object -ExpandProperty Hash`

Ожидается `5A80B1317ECB4BA09E049F3E8D7E5599BE7F43BDFD1A862BF35DE10338FEF684`. Если файл отсутствует/hash другой, исправить распаковку до Break. Файлы не переименовывать: entry обращается к двум V3 internal files по полным путям.

## WinDbg на физическом ПК

**Break останавливает всю VM, Codex и RDP.** Заранее подготовить команды. Вводить каждую внешнюю команду отдельно, Enter после каждой, не блоком.

После Break:

1. `.logopen /t C:\Users\Administrator\pb-context-packet-stage-v3.log`
2. `bl`
3. `.expr`

Продолжать только при ровно 14 известных разрешённых точках 0..13, все d, прежних телах и MASM. Если иначе, script пропустить, `.logclose` и `g` отдельно, прислать журнал.

4. `$<C:\PB-KD-Packet-Logger-V3-20261008\commands\pb-context-packet-stage-v3.wdbg`
5. `bl`
6. `.bpcmds`
7. `.logclose`
8. `g`

Ожидаются BODY_END, ровно 25 разрешённых точек 0..24, все d, без ошибок/REFUSED. Не включать точки и не запускать тест; прислать журнал для проверки адресов и сохранённых тел.

При ошибке не повторять загрузку. Сохранить bl, отключить только присутствующие наши e точки по известным ID (`bd [0n14]` для присутствующей точки 14), повторить bl. Затем `.logclose` и **g отдельно даже при ошибке**. При новой остановке сохранить сообщение, g отдельно. Скрипт не включает точки/не возобновляет target/не запускает workload. Каждую зарегистрированную точку сразу отключает.

Не перезагружать symbols/candidate/patch и старые stage. Номера 14..31 больше не проверяются автоматически. Повторная загрузка ожидаемо отвергается изменённым bp2, но это не проверенный runtime механизм и не замена ручного условия ровно 14 точек. Code guard проверяет первые два bytes 15 sites, не полный live image hash.

## Ограничение следующего этапа

Регистрация V3, исполняемые условия, gc, owned PID/TID и связь NBL/record/query ещё не подтверждены. Причина исходного C0000225/WSA10022 не доказана. Новый four kit V3 пока не создавался: сначала проверить USER staging log, затем подготовить fresh kit с V3 sources/policy и дать enable → четыре соединения → disable handoff. Старый frozen kit 144412 сохранён, его Run пока не использовать, не refreeze/Resume. Полная нагрузка не запускается.
