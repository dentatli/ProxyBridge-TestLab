# Подключение WinDbg к исследуемой Hyper-V VM

2026-10-07: пользователь сообщил об установке WinDbg1.2610.1001.0 на физическом хосте Windows10Pro22H2/build19045.6811. Его Get-VM показывает PB-BUILD-W11-25H2/Generation2/Running и PB-HLK-CTRL/Generation2/Off. Read-only registry внутри текущей VM подтвердил VirtualMachineName=PB-BUILD-W11-25H2. WinDbg на хосте агент не запускал, debugger connection ещё не проверено.

Отладчик работает на физическом хосте, target — Windows VM PB-BUILD-W11-25H2 с ProxyBridge. PB-HLK-CTRL в этом опыте не используется. Цель — [наблюдать private context transfer/free](TCP_CONTEXT_ENDPOINT_LIFECYCLE_PLAN.md), не ещё один обычный ETW прогон и не измерение производительности.

Выбран COM1/named pipe `\\.\pipe\PB-Context-KD`. Microsoft документирует этот transport для VM, включая Generation2: COM добавляется через PowerShell, активация требует полного выключения и нового запуска VM. Secure Boot уже Off и не переключается. Настраивается kernel debugger, не boot debugger. [Microsoft KDCOM VM setup](https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/attaching-to-a-virtual-machine--kernel-mode-). Наличие WinDbg не означает, что target debug mode уже включён.

## Подтверждённые исходные настройки хоста

USER выполнил read-only команды ниже: SecureBoot=Off, SecureBootTemplate=MicrosoftWindows; COM1 Path пустой/DebuggerMode=On; COM2 Path пустой/DebuggerMode=Off. Secure Boot не требуется переключать; исходный COM1 debugger mode сохраняется. Никакой existing pipe не заменяется. Host settings agent сам не менял.

На **физическом ПК**, PowerShell от администратора:

```powershell
Get-VMFirmware -VMName 'PB-BUILD-W11-25H2' | Select-Object SecureBoot, SecureBootTemplate
Get-VMComPort -VMName 'PB-BUILD-W11-25H2' | Format-List Name, Path, DebuggerMode
```

Этот шаг уже выполнен пользователем. Он не менял firmware, UART, загрузку, сеть или power state. Перед будущей настройкой сохранить эти значения на физическом хосте для возврата.

## Подтверждённые исходные настройки гостя

В **VM PB-BUILD-W11-25H2**, PowerShell от администратора:

```powershell
manage-bde.exe -status C:
cmd.exe /c "bcdedit /enum {current}"
cmd.exe /c "bcdedit /enum {dbgsettings}"
```

Пользователь выполнил команды отдельно и прислал вывод: C: зашифрован XTS-AES128/100%, protection Off, unlocked, key protectors не обнаружены. Это не расшифрованный диск, но приостанавливать уже отключённую защиту не нужно. В `{current}` debug не указан, testsigning Yes; `{dbgsettings}` содержит только debugtype Local. Отсутствие debug в текущей записи не доказывает отсутствие inherited settings: полный BCD сохраняется перед изменением. Предыдущие склеенные команды завершились ошибкой синтаксиса и ничего не изменили.

Агентский token не административный; агент не повышает права и не меняет BCD. Все команды настройки ниже выполняются пользователем вручную. BCD физического хоста не меняется.

## 1. Сохранить BCD и настроить гостя

Внутри VM, PowerShell от администратора. Если указанные backup-файлы уже существуют, выбрать новые пути; сохранённые файлы не перезаписывать. На момент подготовки инструкции агент read-only проверил оба пути: файлов не было.

Это **одна команда**: сначала BCD export и полный enum для сверки inherited settings, затем Serial/debug и проверка результата. `&&` обрабатывает CMD, продолжая только при exit0 предыдущей операции. Передавать это как одну строку; не заменять разделители запятыми. Ручное действие пользователя, не выполненная агентом настройка:

```powershell
cmd.exe /c 'bcdedit /export "C:\Users\LabAdmin\pb-context-kd-before-20261007.bcd" && bcdedit /enum all > "C:\Users\LabAdmin\pb-context-kd-before-20261007.txt" && bcdedit /dbgsettings serial debugport:1 baudrate:115200 && bcdedit /debug {current} on && bcdedit /enum {current} && bcdedit /enum {dbgsettings}'
```

Ожидаются debug Yes у current, debugtype Serial/debugport1/baudrate115200 у dbgsettings. При ошибке не выключать VM и не продолжать настройку вслепую. Передать результат в чат. [BCDEdit /dbgsettings](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/bcdedit--dbgsettings) и [BCDEdit /debug](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/bcdedit--debug).

2026-10-08: пользователь выполнил эту команду и прислал три сообщения успешного завершения и итоговые enum: current debug Yes, testsigning Yes; dbgsettings Serial/debugport1/baudrate115200. Агент read-only подтвердил локальные backup-файлы: BCD24576байт с hive signature regf, полный enum4043байта; hashes записаны в ignored audit `artifacts/diagnostics/pb-kd-guest-setup-review-20261008/validation.json`. Сохранённый до изменения полный enum содержит debugtype Local и не содержит явного debug/debugport/baudrate. Экспорт не импортировался и восстановление не проверялось. Это подтверждение ручной guest configuration и сохранённых файлов, не подключение kernel debugger.

## 2. Подготовить физический хост и канал

Этот этап — после проверки результата шага1 и успешного source/docs checkpoint/push. VM содержит текущий Codex/workspace: заранее сохранить эту инструкцию на физическом ПК. Там в PowerShell от администратора сохранить исходные настройки в новый каталог:

```powershell
$pbKdBackup = Join-Path $env:USERPROFILE ('PB-KD-backup-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $pbKdBackup -ErrorAction Stop | Out-Null
Get-VMFirmware -VMName 'PB-BUILD-W11-25H2' | Select-Object SecureBoot, SecureBootTemplate | Export-Clixml -LiteralPath (Join-Path $pbKdBackup 'firmware.xml')
Get-VMComPort -VMName 'PB-BUILD-W11-25H2' | Select-Object Name, Path, DebuggerMode | Export-Clixml -LiteralPath (Join-Path $pbKdBackup 'com.xml')
$pbKdBackup
```

Штатно завершить работу Windows **внутри PB-BUILD-W11-25H2** через меню выключения. Не force power-off, не Save/Pause и не только Restart. На физическом хосте подтвердить Off:

```powershell
Get-VM -Name 'PB-BUILD-W11-25H2' | Select-Object Name, State
```

Только при Off, прежнем пустом COM1 и сохранённых исходных настройках назначить канал. DebuggerMode остаётся исходным On, COM2 и Secure Boot не меняются:

```powershell
Set-VMComPort -VMName 'PB-BUILD-W11-25H2' -Number 1 -Path '\\.\pipe\PB-Context-KD' -ErrorAction Stop
Get-VMComPort -VMName 'PB-BUILD-W11-25H2' | Format-List Name, Path, DebuggerMode
```

Ожидается COM1 Path `\\.\pipe\PB-Context-KD`, DebuggerMode On. При другом исходном пути остановиться, не заменять чужую настройку. [Set-VMComPort](https://learn.microsoft.com/en-us/powershell/module/hyper-v/set-vmcomport).

## 3. Подключить WinDbg и запустить VM

На физическом хосте открыть WinDbg от администратора → File → Start debugging → Attach to kernel. На вкладке COM: Pipe и Reconnect включены; Port `\\.\pipe\PB-Context-KD`, Baud115200, Resets0. Или вкладка Paste с connection string:

```text
com:pipe,port=\\.\pipe\PB-Context-KD,resets=0,reconnect
```

Нажать OK; ожидание канала до запуска VM допустимо. Затем на физическом хосте:

```powershell
Start-VM -Name 'PB-BUILD-W11-25H2' -ErrorAction Stop
```

WinDbg должен установить kernel connection. Если остановил гостя, `g` в WinDbg продолжает выполнение. Остановка ядра при Break/breakpoint останавливает всю VM, включая RDP/Codex; продолжение выполняется на физическом хосте. Не запускать нагрузку пока связь не проверена. [WinDbg Attach to kernel/Paste](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/windbg-kernel-mode-preview).

После подключения передать текст WinDbg с версией target и состоянием связи. На этом этапе ещё не установлены адресные breakpoint/watchpoint и не доказана доступность нужных private symbols. Сначала проверить target build/PE/PDB/инструкции именно загруженных tcpip/AFD/NETIO. Потом подготовить отдельный debugger command file для установки/переноса/очистки записи, жизни объектов и исходного query по [плану наблюдения](TCP_CONTEXT_ENDPOINT_LIFECYCLE_PLAN.md). Старый offset `+0x1c0` не применять автоматически. Отладка меняет timing; отсутствие воспроизведения — INCONCLUSIVE.

2026-10-08: пользователь прислал фактический WinDbg output: waiting pipe PB-Context-KD → Connected Windows10 26100 x64 → Kernel Debugger connection established, ptr64 TRUE, MP1, Free x64; engine10.0.29661.1004, символы srv*. Обозначение Windows10 в debugger не меняет ранее установленную Windows11 target. DriverEntry NetworkPrivacyPolicy C00000BB — отдельное boot сообщение; его связь с context failure не установлена. MCP Server Bridge указан enabled/not running/not connected; доступного инструмента управления WinDbg в текущем чате не найдено, сессией управляет пользователь на физическом хосте. Связь подтверждена USER output, но debugger ещё не проверил live symbols/инструкции/private context.

## 4. Сохранить лог и проверить загруженные символы

**Перед каждым Break/breakpoint/пошаговым выполнением предупреждать: остановится вся VM, включая находящийся в ней Codex и RDP.** Все команды и отдельный `g` для продолжения подготовить заранее на физическом ПК; нельзя рассчитывать на ответ агента из остановленного гостя.

2026-10-08 USER выполнил прежнюю составную строку. Она оказалась некорректной для этого сеанса: после .symfix появилось10 Whitespace at start of path element; tcpip/AFD no symbols, NETIO export symbols; uf получил аргумент `tcpip!InitializeEndpointContextFromParentContext; g`. Автоматический g не выполнен, USER продолжил VM отдельным g. Лог открыт в частном профиле Administrator с timestamp13-16-51. Записанная ошибка команды не является product failure и не доказывает проблему доступа к Microsoft symbol server. Эту составную строку больше не использовать. На данном этапе **одна команда на один Enter, никаких цепочек через `;` и никакого общего paste блока**; g всегда отдельный.

Чтобы не загружать PDB из сети при остановленной VM, подготовлен ignored архив `artifacts/diagnostics/pb-kd-symbol-recovery-20261008/windows-network-pdb.zip` (739303байта, только tcpip.pdb/afd.pdb/netio.pdb). Все3 PE CodeView GUID+age сопоставлены с PDB GUID+DBI age; PDB stream save age учитывается отдельно. Timestamp/ImageSize/CheckSum всех3 текущих файлов точно совпали с присланным lmvm. ZIP CRC/побайтовый roundtrip проверены. Audit `validation.json` хранит SHA и ограничения: loaded memory hash/PDB load ещё не проверены; это не symbols PASS на физическом хосте.

**До Break**, пока VM работает, перенести архив из VM на физический ПК и распаковать в `C:\PB-KD-Symbols`. Три PDB должны лежать непосредственно в этой папке, без дополнительного вложенного каталога. Прежний лог WinDbg оставлять открытым; не перезаписывать. При новом сеансе открывать новый лог отдельной командой `.logopen /t C:\Users\Administrator\pb-context-kd.log` (существующий частный каталог профиля физического хоста).

После предупреждения об остановке VM нажать Break на физическом хосте и дождаться `kd>`. В окне Command самого WinDbg выполнить **каждую строку отдельно**:

```text
.sympath C:\PB-KD-Symbols
.reload /f tcpip.sys
.reload /f afd.sys
.reload /f netio.sys
lmvm tcpip
lmvm afd
lmvm netio
x tcpip!*InitializeEndpointContextFromParentContext*
uf tcpip!InitializeEndpointContextFromParentContext
```

Это локальная symbol path вместо загрязнённого пути, без сети и без `/i`. Дождаться завершения каждого reload. Ниже **отдельная команда для продолжения VM**, даже если symbols/x/uf дали ошибку:

```text
g
```

Передать вывод в чат после продолжения VM. Пустой x, ошибка uf, no symbols или только export symbols означают неподтверждённую точку наблюдения, не отсутствие исполнения функции; при ошибке не задавать смещения или breakpoint вслепую.

Это только символы, сведения о модулях и disassembly; breakpoint/watchpoint и нагрузка не задаются. Target files на диске tcpip/AFD10.0.26100.8875, NETIO10.0.26100.9444; SHA также в ignored `pb-kd-connection-review-20261008`. Нужны live output/точные инструкции до назначения offset/регистров. Копирование PDB на физический хост и новая проверка пока не выполнены/не подтверждены.

2026-10-08 следующий USER output подтвердил Path validation OK, три pdb symbols и разрешение обеих ParentContext функций. Все117 выведенных opcode-инструкций InitializeEndpointContextFromParentContext совпали с дисковым PE. USER отдельно выполнил g. Символы и байты функции подтверждены; перенос при неисправном соединении ещё не наблюдался. Следующий этап — [общий адресный план и чтение шести соседних функций одной остановкой](KERNEL_CONTEXT_BREAKPOINT_PLAN.md), перед установкой точек или нагрузкой. Историческую ошибочную строку с semicolon не повторять.

2026-10-08 USER передал шесть UF и отдельный g. Выбранные12границ точек совпали с PE; создание/перенос/снятие ссылок/free/query объединены в [кандидат общего logger](KERNEL_CONTEXT_BREAKPOINT_PLAN.md#подготовленный-кандидат-общего-журнала).587/605инструкций совпали полностью,18call-related различий сохранены отдельно. Кандидат не установлен и не является готовым Run. Следующее USER чтение bl + uf tcpip!WfpPoolFree + отдельный g, с предупреждением о полной остановке VM перед Break; workload/установка драйвера не выполняются.

2026-10-08 USER bl пуст + WfpPoolFree14инструкций + g. Подготовлен14point файл с автоматическим отключением всех своих точек после установки в пустом сеансе. Две новые точки allocator call/return связаны с AleRedirectRecordFree по caller return address; новая raw sockaddr metadata нужна для проверки owned tuple на baseline. Сейчас разрешён только [ручной staging и вывод bl/.bpcmds](KERNEL_CONTEXT_LOGGER_STAGING.md), без be и трафика. Переносимый ZIP2378байт/CRC-roundtrip exact, source/portable SHA сохранены в ignored pb-kd-pool-free-review-20261008/stage-validation.json. Agent не устанавливал точки и не проверял WinDbg runtime parser; root cause всё ещё не доказана.

2026-10-08 USER staging завершился14resolved d/.bpcmds exact/g. Ошибка двух $$комментариев от semicolon исправлена в source без изменения breakpoint actions; повторный stage запрещён. Следующий [format probe](KERNEL_CONTEXT_LOGGER_STAGING.md#текущий-следующий-шаг-без-трафика) печатает14синтетических строк, не изменяет точки и не генерирует трафик. При Break предупредить о полной остановке VM, после чтения всегда отдельный g. Причина сбросов всё ещё требует наблюдения исполнения на owned соединениях.

[Microsoft .logopen](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/-logopen--open-log-file-) / [.symfix](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/-symfix--set-symbol-store-path-) / [.reload](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/-reload--reload-module-) / [x](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/x--examine-symbols-).

## Возврат исходных настроек после опыта

Резервный BCD и полный enum сохраняются только локально, вне Git. Не импортировать весь BCD автоматически: это аварийный backup, а обычный возврат ограничен нашими изменениями.

В VM от администратора восстановить Local и убрать добавленное явно указанное debug из current (до опыта элемент отсутствовал, включая сохранение наследования). После успешно включённого Serial проверить, остались ли debugport/baudrate; если остались, удалить только эти добавленные элементы. «Элемент не найден» при удалении уже отсутствующего элемента — не повод менять другие настройки.

```powershell
cmd.exe /c 'bcdedit /dbgsettings local'
cmd.exe /c 'bcdedit /deletevalue {current} debug'
cmd.exe /c 'bcdedit /enum {dbgsettings}'
```

При наличии оставшихся полей после возврата Local:

```powershell
cmd.exe /c 'bcdedit /deletevalue {dbgsettings} debugport'
cmd.exe /c 'bcdedit /deletevalue {dbgsettings} baudrate'
```

Сверить current/dbgsettings и inherited settings с сохранённым enum. Затем штатно выключить VM. На физическом хосте при Off вернуть только созданный нами COM1 path к исходному пустому; DebuggerMode On, COM2 empty/Off и SecureBoot Off сохраняются:

```powershell
Set-VMComPort -VMName 'PB-BUILD-W11-25H2' -Number 1 -Path '' -ErrorAction Stop
Get-VMComPort -VMName 'PB-BUILD-W11-25H2' | Format-List Name, Path, DebuggerMode
Start-VM -Name 'PB-BUILD-W11-25H2' -ErrorAction Stop
```

После старта проверить BCD и BitLocker read-only и сверить firmware/COM с backup. Driver installation/restore и перезагрузки отдельного диагностического комплекта остаются самостоятельными ручными этапами, не заменяются этой настройкой.

Гостевой Serial/debug включён и kernel connection через pipe подтверждён пользователем 2026-10-08. Host backup/полная сверка firmware/COM не представлены новым выводом; прежние исходные настройки сохранены как наблюдения USER. Откат не выполнен/не проверен. Изменения BCD/COM/firmware/trust/power/network агентом не выполнялись. Следующий ручной этап — лог и live symbols/disassembly → проверенный адресный план → диагностическая нагрузка. Нагрузку до проверки символов и адресного плана не запускать. Причина private context loss остаётся недоказанной.
