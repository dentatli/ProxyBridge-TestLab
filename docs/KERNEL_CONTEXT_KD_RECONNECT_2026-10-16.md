# Символы загружены; следующий шаг — live code gate

**Текущий стоп-пункт:** USER уже перенёс и загрузил новые PDB, tcpip/fwpkclnt показывают pdb symbols из локальной папки, Cid type доступен, отдельный g записан. Перенос и .reload ниже повторять не требуется. Далее — [выбранные live-инструкции и IDCHECK](KERNEL_CONTEXT_CURRENT_CODE_GATE_2026-10-16.md), без точек и workload. Остальные разделы сохраняют ход переподключения и предыдущие команды.

USER прислал вывод WinDbg 2026-10-16: pipe PB-Context-KD открыт, `Kernel Debugger connection established`, target 26100 x64 / ptr64 TRUE / MP6, время подключения 22:18:55 UTC+5. Uptime при остановке 12m06.695s. Сообщение 80000003 явно объясняет остановку ручным Break, а не crash Windows. В конце excerpt присутствует отдельная команда `g`. Это USER paste, не полученный оригинальный host log.

Первый полный USER paste подтвердил: bl и bpcmds пусты, evaluator MASM, в конце отдельный g. Прежние25 точек в новом сеансе отсутствуют. `lmvm nt` вывел PDB `B661C6FE72991D160FE37C48B8BC54701`, Brepro hash AFF6531F, checksum C8AD9C, size1450000. Эти headers/PDB key совпали с нынешним дисковым ntoskrnl.exe. Это не live whole-image SHA. До обновления списка `lmvm tcpip` и `lmvm fwpkclnt` дали только заголовки без строк модулей; причина исходного пустого списка не установлена. Нельзя из него объявить драйверы незагруженными или потерявшими redirect context.

USER выполнил .reload /s и прислал полный console: после уведомлений о связи22:36:23.508 и22:36:36.402 появились tcpip base5b1a0000/end5b4fa000, tcpipreg base5dce0000/end5dcf6000 и fwpkclnt base5b500000/end5b58b000. У tcpip/fwpkclnt тогда symbol state deferred, headers точно совпали с таблицей ниже. В конце отдельный g. Обновление module list подтверждено; deferred не означает ошибку загрузки драйвера. Два уведомления Connected не доказывают reboot. Private наблюдение: module-refresh-observation.json в том же audit. Следующий USER paste уже подтвердил локальные PDB и Cid type; live-инструкции/условия пока не проверены.

Нормализованная локальная транскрипция USER paste имеет SHA256 `8609ebc2aca400760feffc854242c6b5e904c8cf60d18896aed7e4ba9cdebc53`; это не SHA исходного host console/log. Проверка и текущие disk PE/CodeView: `artifacts/diagnostics/pb-kd-reconnect-review-20261016/inventory-validation.json`.

Перед подключением USER read-only выводами подтвердил на физическом хосте Running / COM1 pipe `\\.\pipe\PB-Context-KD` / DebuggerMode On / COM2 empty Off; в гостевом BCD current debug Yes, dbgsettings Serial / port1 / 115200. Агент настройки не менял. Private запись наблюдений: `artifacts/diagnostics/pb-kd-reconnect-review-20261016/connection-observation.json`.

Это возобновление старого исследования C0000225/WSA10022. [Свежий TCP/UDP отказ 14 октября](TRAFFIC_FAILURE_OFFLINE_REVIEW_2026-10-14.md) остаётся отдельным случаем с обнаруженной несовместимостью формата Port; его runtime-причина и прежний context signature не доказаны. Подключение WinDbg не разрешает новый Run ни одной серии.

Новая загрузка и новый сеанс требуют проверки. Старые25 IDs отсутствуют; это не разрешает повторить старый stage. Live tcpip/fwpkclnt headers теперь подтверждены, загрузка PDB и прежние инструкции/смещения — нет. На диске ntoskrnl и fwpkclnt имеют version26100.9711, tcpip —26100.8875, но SHA и CodeView keys всех трёх отличаются от данных8 октября. Совпадение строки версии tcpip не означает прежний PE/PDB.

| Дисковый образ | Brepro hash / checksum / ImageSize | CodeView key |
| --- | --- | --- |
| ntoskrnl.exe | AFF6531F / C8AD9C / 1450000 | B661C6FE72991D160FE37C48B8BC54701 |
| tcpip.sys | D26770CA / 355D78 / 35A000 | 27C297493100FD36F8C7368E16FC36991 |
| fwpkclnt.sys | 5A1CC564 / 996F6 / 8B000 | 0E33083EA4502569DB2B3ECDC999F6571 |

Из151 прежних защищённых entries150 совпадают. Единственное выявленное отличие — внешний `codex-primary-runtime/dependencies/python/python.exe`: saved SHA10d845f5… против нынешнего b847bb9f…, при той же file version3.12.14. В старом kit163607 совпадают69/70 frozen entries; поэтому текущая проверка его freeze уже не проходит. Ни manifest, ни старые данные/kit-файлы не переписывались, refreeze/Resume не выполнялись. Причина/автор изменения runtime не установлены. Это ещё одна причина не запускать старый комплект.

## Новые PDB подготовлены только файлами

В старом чате «Изучи проект ProxyBridge-TestLab» успешный путь8 октября подтверждён USER attachment887bb38e: локальные PDB в C:\PB-KD-Symbols → .sympath → отдельные .reload /f → lmvm с pdb symbols. Этот метод повторяется с новыми файлами/папкой; старый архив не подходит к новым CodeView keys.

Новый архив на Desktop VM: `PB-KD-Symbols-20261016.zip`, 3416856 bytes, SHA256 `6b1dd40d4551e1af10e876a621f26112bfe89a625f96a96e169f667f70c38f8a`. Внутри ntkrnlmp.pdb11522048bytes, tcpip.pdb2273280bytes, fwpkclnt.pdb446464bytes, manifest.json и README.txt. PDB получены с HTTPS Microsoft symbol server; GUID и **DBI age** всех3 совпали с PE CodeView, отдельно записан save age. ZIP CRC и распаковка byte-exact проверены, Desktop copy exact. Это не проверка загрузки символов в WinDbg или whole live image. Старые archive/manifest/стaging файлы не изменялись. Audit `artifacts/diagnostics/pb-kd-symbol-recovery-20261016/validation.json`.

## 1. Перенести на физический хост, без Break

**Выполнено USER:** загрузки на физическом ПК находятся в `D:\Загрузки`. SHA256 архива совпал полностью; Expand-Archive в новую C:\PB-KD-Symbols-20261016 завершился без показанной ошибки. USER listing подтвердил все3 PDB и ожидаемые размеры. Это проверка archive hash и наличия/размеров файлов, не отдельных physical PDB SHA и не загрузки в WinDbg. Private запись: `artifacts/diagnostics/pb-kd-symbol-recovery-20261016/physical-host-observation.json`. Следующий шаг — раздел2; копирование повторять не нужно.

Команды уже выполненного переноса сохранены для воспроизводимости. Скопировать архив с Desktop VM на физический ПК в `D:\Загрузки\PB-KD-Symbols-20261016.zip`. В PowerShell физического ПК проверить:

`Get-FileHash -LiteralPath 'D:\Загрузки\PB-KD-Symbols-20261016.zip' -Algorithm SHA256 | Select-Object -ExpandProperty Hash`

Ожидается SHA256 `6B1DD40D4551E1AF10E876A621F26112BFE89A625F96A96E169F667F70C38F8A`. При отличии или отсутствии файла Break не выполнять. Старую C:\PB-KD-Symbols не менять. Распаковать в новую папку, без -Force:

`Expand-Archive -LiteralPath 'D:\Загрузки\PB-KD-Symbols-20261016.zip' -DestinationPath 'C:\PB-KD-Symbols-20261016'`

Проверить, что три PDB лежат непосредственно в этой папке:

`Get-ChildItem -LiteralPath 'C:\PB-KD-Symbols-20261016' -Filter '*.pdb' | Select-Object Name,Length`

Следующий ручной этап — только после совпадения физического SHA и проверки распаковки. Если каталог уже содержит другие файлы или Expand-Archive отказал, не перезаписывать: прислать вывод. Проверка local archive агентом не заменяет physical file presence/hash.

## 2. Проверить локальную загрузку символов, без точек и workload

Сохранить эту страницу и команды до Break. Убедиться, что на общей VM не идёт согласованный runtime другого чата; при активном прогоне Break отложить до его завершения. Агент в WinDbg не действует, нагрузку не запускает. USER предпочитает присылать полный console вывод в чат: logopen/logclose не требуются.

**Break останавливает всю PB-BUILD-W11-25H2, включая Codex и RDP.** Если WinDbg уже стоит на активном kd>, новый Break не нужен. Каждую команду вводить отдельно, Enter после каждой; весь список блоком не вставлять. Не добавлять `; g` к другой команде.

После одного USER Break выполнить отдельные команды. Здесь /f запрашивает загрузку заранее проверенных PDB с локального диска физического хоста. /i, /o, guessed base/size не использовать. Путь целиком локальный, чтобы не рассчитывать на скачивание при остановленной VM. Windows драйверы/DriverEntry/SCM этими командами не запускаются.

1. `.sympath C:\PB-KD-Symbols-20261016`
2. `.reload /f nt`
3. `.reload /f tcpip.sys`
4. `.reload /f fwpkclnt.sys`
5. `lmvm tcpip`
6. `lmvm fwpkclnt`
7. `dt nt!_ETHREAD Cid`
8. `g`

Ожидаются локальные pdb symbols обоих сетевых модулей, matching identities и доступный Cid type; это не доказывает чтение nonzero owned PID/TID или исполнение точек. При ошибке загрузки не повторять/не пробовать другие flags: пропустить оставшиеся probes и ввести g отдельно. Последний g всегда отдельный, даже при ошибке. Полный вывод отправить в чат после g. Даже если строки снова пусты, не загружать модуль по guessed base из старого сеанса.

Ничего не регистрировать, не включать, не удалять и не подгружать stage/patch. В этом read-only шаге не выполнять bd по прежним IDs вслепую: состав и принадлежность нынешних точек ещё не проверены. При непустом bl сохранить весь список и тела; не трогать чужие точки. Команда [lm с verbose output](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/lm--list-loaded-modules-) показывает в том числе headers/версии и состояние symbols; если поля недоступны, это ограничение данных, не доказательство identity match.

После отдельного g проверить USER console, строки модулей и их соответствие disk PE/CodeView. Затем отдельно выбрать следующий read-only code/symbol gate. Семиточечный профиль сейчас отсутствует; не пытаться включить прежние IDs. Старый [план семи точек](KERNEL_CONTEXT_PACKET_MINIMAL_V1.md) сохраняется как неподтверждённый проект; для его установки/исполнения потребуются актуальная проверка и новый комплект, а не Run старого163607. Отсутствие module rows пока ограничивает проверку, а не доказывает новый дефект TCP.

Продукт, старые captures, frozen kits/manifest и исторические debugger scripts этим checkpoint не меняются. Причина исходного TCP отказа по-прежнему не установлена.
