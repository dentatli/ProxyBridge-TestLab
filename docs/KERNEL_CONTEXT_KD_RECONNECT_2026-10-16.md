# Точек нет; следующий шаг — обновить список модулей WinDbg

USER прислал вывод WinDbg 2026-10-16: pipe PB-Context-KD открыт, `Kernel Debugger connection established`, target 26100 x64 / ptr64 TRUE / MP6, время подключения 22:18:55 UTC+5. Uptime при остановке 12m06.695s. Сообщение 80000003 явно объясняет остановку ручным Break, а не crash Windows. В конце excerpt присутствует отдельная команда `g`. Это USER paste, не полученный оригинальный host log.

Следующий полный USER paste подтвердил: bl и bpcmds пусты, evaluator MASM, в конце отдельный g. В текущем сеансе нет зарегистрированных точек, в том числе прежних25. `lmvm nt` вывел PDB `B661C6FE72991D160FE37C48B8BC54701`, Brepro hash AFF6531F, checksum C8AD9C, size1450000. Эти headers/PDB key совпали с нынешним дисковым ntoskrnl.exe. Это не live whole-image SHA. `lmvm tcpip` и `lmvm fwpkclnt` дали только заголовки без строк модулей; причина пока неизвестна. Нельзя из пустого вывода объявить драйверы незагруженными или потерявшими redirect context.

Нормализованная локальная транскрипция USER paste имеет SHA256 `8609ebc2aca400760feffc854242c6b5e904c8cf60d18896aed7e4ba9cdebc53`; это не SHA исходного host console/log. Проверка и текущие disk PE/CodeView: `artifacts/diagnostics/pb-kd-reconnect-review-20261016/inventory-validation.json`.

Перед подключением USER read-only выводами подтвердил на физическом хосте Running / COM1 pipe `\\.\pipe\PB-Context-KD` / DebuggerMode On / COM2 empty Off; в гостевом BCD current debug Yes, dbgsettings Serial / port1 / 115200. Агент настройки не менял. Private запись наблюдений: `artifacts/diagnostics/pb-kd-reconnect-review-20261016/connection-observation.json`.

Это возобновление старого исследования C0000225/WSA10022. [Свежий TCP/UDP отказ 14 октября](TRAFFIC_FAILURE_OFFLINE_REVIEW_2026-10-14.md) остаётся отдельным случаем с обнаруженной несовместимостью формата Port; его runtime-причина и прежний context signature не доказаны. Подключение WinDbg не разрешает новый Run ни одной серии.

Новая загрузка и новый сеанс требуют проверки. Старые25 IDs отсутствуют; это не разрешает повторить старый stage. Live tcpip/fwpkclnt headers/PDB и прежние инструкции/смещения не проверены; совпадение только build26100 недостаточно. На диске ntoskrnl и fwpkclnt имеют version26100.9711, tcpip —26100.8875, но SHA и CodeView keys всех трёх отличаются от данных8 октября. Совпадение строки версии tcpip не означает прежний PE/PDB.

| Дисковый образ | Brepro hash / checksum / ImageSize | CodeView key |
| --- | --- | --- |
| ntoskrnl.exe | AFF6531F / C8AD9C / 1450000 | B661C6FE72991D160FE37C48B8BC54701 |
| tcpip.sys | D26770CA / 355D78 / 35A000 | 27C297493100FD36F8C7368E16FC36991 |
| fwpkclnt.sys | 5A1CC564 / 996F6 / 8B000 | 0E33083EA4502569DB2B3ECDC999F6571 |

Из151 прежних защищённых entries150 совпадают. Единственное выявленное отличие — внешний `codex-primary-runtime/dependencies/python/python.exe`: saved SHA10d845f5… против нынешнего b847bb9f…, при той же file version3.12.14. В старом kit163607 совпадают69/70 frozen entries; поэтому текущая проверка его freeze уже не проходит. Ни manifest, ни старые данные/kit-файлы не переписывались, refreeze/Resume не выполнялись. Причина/автор изменения runtime не установлены. Это ещё одна причина не запускать старый комплект.

## Подготовить на физическом хосте

Сохранить эту страницу и команды до Break. Убедиться, что на общей VM не идёт согласованный runtime другого чата; при активном прогоне Break отложить до его завершения. Агент в WinDbg не действует, нагрузку не запускает. USER предпочитает присылать полный console вывод в чат: logopen/logclose не требуются.

**Break останавливает всю PB-BUILD-W11-25H2, включая Codex и RDP.** Если WinDbg уже стоит на активном kd>, новый Break не нужен. Каждую команду вводить отдельно, Enter после каждой; весь список блоком не вставлять. Не добавлять `; g` к другой команде.

После одного USER Break выполнить следующий проверочный шаг. [Microsoft описывает .reload](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/-reload--reload-module-) как обновление module list и symbol metadata; без /f используется lazy loading. Устаревший/неполный список модулей — пока только гипотеза, обновление ещё не выполнялось и его успех не заявляется. Параметры /f, /i, /o, ручные base/size не добавлять. Здесь не вызываются DriverEntry/SCM и не устанавливаются драйверы на target.

1. `.reload /s`
2. `lm m *tcp*`
3. `lm m *fwpk*`
4. `lmvm tcpip`
5. `lmvm fwpkclnt`
6. `g`

Последний g всегда отдельный, даже при ошибке чтения/символов. При ошибке .reload не повторять/не пробовать другие flags, сохранить её и результаты последующих lm, затем g отдельно. Если неожиданная остановка повторится, сохранить её сообщение и g отдельно; не начинать workload. Полный вывод отправить в чат после g. Даже если строки снова пусты, не загружать модуль по guessed base из старого сеанса.

Ничего не регистрировать, не включать, не удалять и не подгружать stage/patch. В этом read-only шаге не выполнять bd по прежним IDs вслепую: состав и принадлежность нынешних точек ещё не проверены. При непустом bl сохранить весь список и тела; не трогать чужие точки. Команда [lm с verbose output](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/lm--list-loaded-modules-) показывает в том числе headers/версии и состояние symbols; если поля недоступны, это ограничение данных, не доказательство identity match.

После отдельного g проверить USER console, строки модулей и их соответствие disk PE/CodeView. Затем отдельно выбрать следующий read-only code/symbol gate. Семиточечный профиль сейчас отсутствует; не пытаться включить прежние IDs. Старый [план семи точек](KERNEL_CONTEXT_PACKET_MINIMAL_V1.md) сохраняется как неподтверждённый проект; для его установки/исполнения потребуются актуальная проверка и новый комплект, а не Run старого163607. Отсутствие module rows пока ограничивает проверку, а не доказывает новый дефект TCP.

Продукт, старые captures, frozen kits/manifest и исторические debugger scripts этим checkpoint не меняются. Причина исходного TCP отказа по-прежнему не установлена.
