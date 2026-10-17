# Двухточечная проба подготовлена; после перезагрузки сначала восстановить WinDbg

Актуальный стоп-пункт17 октября2026, Asia/Yekaterinburg. Последний полный контроль [подтвердил96 исходных API10022/native отказов из968](REDIRECT_CONTEXT_CONTROL_RESULT_2026-10-17.md). C0000225 в том опыте не измерялся, механизм потери контекста не установлен.

**Новое USER свидетельство после восстановления:** WinDbg достиг `nt!DbgBreakPointWithStatus`/`kd>`, `bl` вернул пустой список, затем введён отдельный `g`. Соединение пригодно для команд; точки отсутствуют. Полный Connection header/новые module headers и symbols/code ещё не присланы. Старый профиль выбора3/4 из7 к этому сеансу неприменим. Следующий USER шаг — только symbols/live-code inspection ниже; затем отдельная свежая регистрация двух query точек и соответствующий новый kit, не изменение195830.

Проверка на физическом хосте: заранее сохранить команды и recovery. **Break останавливает всю VM/Codex/RDP.** Вводить отдельно `.reload /s`, `.sympath C:\PB-KD-Symbols-20261016`, `.reload /f nt`, `.reload /f tcpip.sys`, `.expr`, `lmvm tcpip`, `dt nt!_ETHREAD Cid`, `u tcpip!WfpAleProcessSocketOption+0x2c4 L8`, `u tcpip!WfpAleProcessSocketOption+0x47b L8`, затем всегда отдельный `g`. При первой ошибке не продолжать последующие inspection команды: отдельныйg и передать весь вывод. Никаких bp/be/step/Run на этом шаге. Local symbol path — прежняя проверенная папка на физическом хосте, новые matching/live properties только предстоит подтвердить.

## Что сохранено после прерванной подготовки

Отдельные новые диагностические источники, без изменения прежних frozen controllers/product:

- `scripts/Invoke-KdQueryProbe.ps1` — Prepare/Inspect/Run, ручные flags QueryProfileReviewed/DebuggerLoggerEnabled, без debugger automation.
- `scripts/Invoke-KdQueryProbeWorkload.ps1` и `modules/KdQueryProbeConnectionLoad.psm1` — только одна фаза4,512KiB/8s, один исходный query, original listener/delay0, ConnectEx/pending32. Нет load/recovery entry point, минимальная RAM2ГиБ, прежние startup/cleanup gates сохранены.
- `src/pb_prepare_kd_query_probe.py` — новый изолированный Python snapshot, pinned CLI/Core/stock driver, frozen source/runtime/profile/historical evidence.
- `src/pb_kd_query_probe_report.py` — проверка native/Core metadata, kernel console остаётся pending. Не объявляет NTSTATUS/lifecycle coverage/product PASS.
- `scripts/debugger/pb-kd-query-profile-20261017.json` — **неисполняемый** выбор прежних IDs3/4 QUERY_READ/QUERY_STATUS из семи зарегистрированных точек. Тела actions не менялись. Это не stage, в нём нет команды загрузки/включения.

Отдельный новый комплект: `C:\src\ProxyBridge-TestLab\artifacts\diagnostics\pb-kd-query-probe-preparation-20261016-195830-aaf0be71`. Имя UTC16 октября19:58, локально17 октября. PlanSHA `367b313170201aa9650ef295da4ae7cc33e1e89de8c516b15e6311b5de2f5925`. PS5 Prepare завершился exit0 / KD_QUERY_PROBE_FILES_VALIDATED:8287 frozen files,8197 runtime files,4 connections, product_started/traffic_generated/driver_installed/debugger_control/runtime_ready=false. Старые kit/manifest/capture не перезаписывались и не Resume/refreeze.

PS5/PS7 разобрали новые PS scripts; служебный GetPreset не разрешает уровни нагрузки. Reporter проверен на **тестовой копии** старого four capture: только metadata адаптирована к новому контракту, native/Core raw оставлены. Native evidence принято, debugger pending. Тестовая копия full968 отклонена как неподходящий профиль. Это files-only проверки отчёта/границ, не новый Run. Private audit: `artifacts/diagnostics/pb-kd-query-probe-preparation-review-20261017/`, adapted fixtures/reports, protected-inputs, PS5/report verification. Приватные данные и комплекты не в Git.

После новой загрузки17 октября PS5 Inspect также завершился exit0 / KD_QUERY_PROBE_FILES_VALIDATED,8287 SHA/8197 runtime files, runtime_ready=false. Все78 защищённых inputs прежнего96-failure capture/controllers/stage совпали с before-инвентарём. Итог в private validation.json; готовность файлов не равна готовности нового live kernel сеанса.

В frozen debugger-evidence сохранены исторические console регистрации7 и successfulfour; их SHA сверены с известными оригиналами. Историческая ошибка комментария stage не скрывается, stage не перегружается. Реальные QUERY actions уже наблюдались в семиточечной пробе, но runtime сокращённого профиля **ещё не проверен**. Нет CREATE/attach/free покрытия, shared Core↔KD QPC, независимого socket/seq вKD; общий gc safety и UNREADABLE branch не доказаны.

## Восстановление после выключения

USER сообщил, что закрыл всё из-за лимита, и попросил восстановить работу. Read-only CIM в этом продолжении подтверждает новую загрузку VM17 октября11:04:48 +05:00, свободно около1.98ГиБ при открытом чате. Это не достаточный запас для опыта. Причина расхода памяти сейчас не расследовалась; процессы агент не закрывал.

Текущее состояние физического WinDbg неизвестно. **Не считать прежние IDs/адреса и подключённые PDB действующими после закрытия WinDbg/перезагрузки.** Подготовленный профиль применим только после проверки именно прежней регистрации7. Если bl пуст или points отличаются, сначала отдельная подготовка/проверка регистрации двух точек и новый соответствующий kit; не подменять profile/manifest внутри195830. Ни один Run нового query probe не выполнялся и сейчас не разрешён.

Порядок USER на физическом ПК, пока только восстановление соединения:

1. Открыть WinDbg от администратора: File → Start debugging → Attach to kernel → Paste connection string.
2. Указать прежний подтверждённый канал:

```text
com:pipe,port=\\.\pipe\PB-Context-KD,resets=0,reconnect
```

3. Подключиться и прислать полный новый вывод от Opened/Waiting/Connected. VM уже работает — команд запуска VM/смены BCD/COM/гипервизора здесь нет. Старый [setup](KERNEL_DEBUG_HYPERV_SETUP.md) содержит историческую настройку, не выполнять его целиком.
4. Подключение/Break могут остановить **всю VM, включая Codex и RDP**. Заранее сохранить на физическом ПК recovery: при активном kd> ввести **отдельной командой** `g`, даже после ошибки. Если система остаётся Running, пока не нажимать Break: сначала оценить вывод подключения. Самостоятельно stage/be/step/нагрузку не выполнять. Logopen не требуется.

После подтверждения подключения — USER inventory с предупреждением перед Break и отдельным g, проверка symbols/live code и актуальной регистрации, затем конкретный план пробной4. Включение только проверенных query точек и один Run согласовываются после этой проверки; сначала console четырёх, только затем решение о64/256. Нельзя объявить отказ не воспроизводящимся или запись не созданной по отсутствию событий сокращённого capture.

**Текущий стоп:** host kd отвечает, USER bl пустой/g отдельно; ждём matching symbols/live-code inspection. Исторический комплект195830 сохраняется, но его existing7 selection не соответствует новому пустому сеансу. Новый Run/регистрация/enable пока не разрешены. Агент только files-only анализ/подготовка/проверки/документация. Продукт, драйверную установку, BCD/гипервизор/питание и соседнюю рабочую копию разработки не меняет, debugger/Run не выполняет. Полный предыдущий Run и все frozen kits сохранить.
