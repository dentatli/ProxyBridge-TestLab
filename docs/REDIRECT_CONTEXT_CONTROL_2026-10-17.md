# Контроль исходного отказа с отключёнными точками: комплект подготовлен

**Обновление после USER Run:** единственный согласованный запуск193023-40495829 остановлен ресурсной проверкой до native генератора:378.2МиБ доступно при пороге2ГиБ. Повтор не разрешён; текущий результат и следующий шаг — [разбор ресурсной остановки](REDIRECT_CONTEXT_CONTROL_RESOURCE_STOP_2026-10-17.md). Ниже сохранён исторический план, его Run-команду повторно не выполнять.

17 октября2026, Asia/Yekaterinburg. После подготовки отдельного контроля пользователь ответил «Продолжаем» на предложение провести сейчас один контроль968 на свободной VM. Согласован один USER Run указанного ниже комплекта с отключёнными точками; выполнение и результат ещё не получены. Агент не включал точки, не управлял debugger, не запускал продукт/трафик, не устанавливал драйвер и не менял Windows/BCD/гипервизор. Соседняя рабочая копия разработки не изменялась.

Цель следующего опыта — проверить, сохраняется ли наблюдаемый отказ **исходного запроса Core** на нынешних Windows binaries при отключённых точках. Последующая kernel-диагностика должна опираться на реально повторившийся отказ, а не только на двадцать NULL retrieval из успешной пробы четырёх соединений. Ошибка Windows/драйвера и механизм потери record по-прежнему не доказаны.

## Конкретный комплект

`C:\src\ProxyBridge-TestLab\artifacts\diagnostics\pb-redirect-control-preparation-20261016-190400-5cd405b0`

Имя каталога содержит UTC16 октября19:04; локальная дата подготовки —17 октября. Runtime plan SHA256: `68670ff7935c6d9c628322dba7a6bf52d9c22d7a95cba165a9cd742b5ba74097`.

Проверены8281 frozen SHA, включая8197 файлов отдельного Python runtime. Windows PowerShell5.1 Prepare/Inspect и PowerShell7 Inspect завершились с exit0 / REDIRECT_CONTROL_FILES_VALIDATED; product_started/traffic_generated/driver_installed/debugger_control/runtime_ready=false. Это проверка файлов, не результат нагрузочного опыта. Runtime gates при Run ещё могут остановить запуск.

Новые диагностические исходники:

- [Prepare/Inspect/Run wrapper](../scripts/Invoke-RedirectContextControl.ps1).
- [Изолированный workload](../scripts/Invoke-RedirectContextControlWorkload.ps1).
- [Модуль фаз с ограниченным ожиданием](../modules/RedirectControlConnectionLoad.psm1).
- [Подготовитель](../src/pb_prepare_redirect_control.py).
- [Отчёт](../src/pb_tcp_redirect_control_report.py).

Старые four-only/25-point/V3 контроллеры, shared ConnectionLoad и продукт не изменялись. Новый workload производен от отдельного KD workload, но принимает только control method и полный фиксированный профиль. Прежний four-only wrapper не ослаблен и не используется для968 соединений. Служба должна уже иметь ожидаемые путь/hash/type: используется прежний проверяющий ServiceController Start/Stop, без создания или перенастройки службы. При несовпадении — отказ preflight, не автоматическая установка.

## Рамки будущего одного Run

| Параметр | Значение |
| --- | --- |
| Последовательность | 4 →64 →256 →640 →4, всего968 |
| На соединение | 512KiB, rate65536bytes/s, hold8s |
| Клиент | ConnectEx, pending limit32 |
| Конечный receiver / SOCKS5 | Локальные,54122 /54123 |
| Listener Core | original, delay0; не backlog1024 |
| Запрос контекста | Один исходный; без дополнительных/отложенных query |
| WinDbg | Все точки отключены; автоматического управления нет |
| Завершающие4 | Та же сессия продукта, только если предыдущие этапы завершились без timeout/resource/forced-cleanup ошибки |
| Ожидание клиента | Не более60s за вызов ожидания, дополнительно ограничено остатком180s общего бюджета фаз |
| Ресурсы | Прежний HIGH gate: не менее2GiB доступной памяти |

180s — бюджет фаз, не обещание общего wall-clock времени: проверка тысяч хешей, startup/CIM/port checks и cleanup находятся вне него. Проверка файлов сама может быть заметной. При исчерпании бюджета, нехватке ресурсов, timeout или неполной очистке дальнейшие этапы прекращаются; результат неполный, raw evidence сохраняется. Штатные native TCP отказы не маскируются и сами по себе не запрещают сохранить заключительные4 в той же сессии. Это отдельный будущий контроль, не разрешение на recovery/повторные серии вообще.

CLI/Core/stock driver имеют те же pinned SHA, что успешная four-only проба: CLI `ad83b3aa…`, Core `7dc8952e…`, driver `3cd79cfc…`; полные SHA в receipt/плане и runtime checks. Никакой пересборки или исправления продукта. Новая Windows и отдельный Python являются явно зафиксированными условиями; байтовая эквивалентность всего окружения прежнему нагрузочному захвату не утверждается.

## Отдельный Python и офлайн-проверки

В комплект скопированы8196 исходных файлов runtime без `__pycache__`/pyc. Копирование проверяло SHA каждого файла и повторную неизменность источника; добавлен один `python312._pth`. Exe snapshot SHA — `b07b03b9ba866a341a3c13ee69710fbc8d43d4ce2523dee13f6df5c25378d15b`. Run не ссылается на общий `.cache/.../python.exe`; общий путь используется только Prepare. Manifest фиксирует полный состав копии, включая DLL/stdlib. Новые и пропавшие файлы также отклоняются Inspect.

Пути загрузки ограничены через [Windows Python _pth](https://docs.python.org/3.12/using/windows.html#finding-modules): snapshot root/DLLs/Lib и явно замороженные диагностические src, без import site. Проверка фактического interpreter metadata подтвердила isolated/no_site, prefix/base_prefix/executable/proactor из snapshot, отсутствие .cache в sys.path. Импорт psutil7.2.2 из frozen bin/packages и hash callback proactor guard также проверены. Все дочерние Python helpers и reporter получают -B; smoke не создал изменённых/новых bytecode files, SHA после него совпали. Это служебные импорты, не fixture launch и не трафик.

Новая копия защищает от обычного обновления исходного SDK runtime по его прежнему пути; файловая проверка всё равно обязательна. Причину прежней замены Python не расследовали. USER предположил связь с разработкой; это остаётся гипотезой, а не доказанным источником изменения или причиной TCP отказа. Старые manifests не переписывались, нет refreeze/Resume.

Новый reporter проверен на **тестовой копии старого захвата**153716-f140a1c9: изменены только metadata labels/policy/описание timeout для нового reporting contract, raw Core/CTS не менялись. Он распознал968 query и96 уникально связанных native/API10022 отказов. Это проверка отчёта на исторических данных, **не новый Run и не новое воспроизведение**. Отдельно реальные данные четырёх соединений отклонены как неполный full-control capture.192 защищённых входных файла/записи старых kit/capture/source после всей проверки совпали; старый внешний Python mismatch не превращался в valid old freeze.

Private audit: `artifacts/diagnostics/pb-redirect-control-preparation-review-20261016/verification-v1/validation.json`, engine stdout/stderr, snapshot-smoke.json, adapted-historical-report.json, four-only-rejected-by-full-control-report.json, protected-inputs.json. Адаптированная fixture лежит только в приватном audit. Исторические captures, новый kit, архивы и fixtures в Git не добавляются.

## Что будет означать результат

`REDIRECT_CONTROL_ORIGINAL_API_FAILURE_REOBSERVED` требует failed original Core query с api_return=-1/api_error10022, однозначно связанного с native отказом. Reporter сохраняет Core seq/socket/PID/TID/endpoints, native GUID и timing. NTSTATUS здесь не измеряется: C0000225 должен подтверждаться последующим связанным kernel capture, а не выводиться только из10022.

Другие outcomes: `REDIRECT_CONTROL_SIGNATURE_NOT_REOBSERVED`, `REDIRECT_CONTROL_OTHER_NATIVE_FAILURES`, `REDIRECT_CONTROL_CAPTURE_INCOMPLETE`. Отсутствие signature в одном контроле не доказывает исправление, наличие — не доказывает Windows/driver/table cause. В случае неполноты сохраняются raw сведения и ошибки; повтор Run не выполняется автоматически. Новый reporter не подменяет результаты product PASS.

## Согласование и порядок USER

**Текущий стоп-пункт — USER проверяет отключённые точки и выполняет один согласованный запуск профиля968 соединений, затем передаёт вывод.** Последнее «Продолжаем» относится к конкретному предложению одного полного контроля после подготовки нового комплекта. Предыдущее разрешение на четыре соединения уже использовано; оно не служит основанием этого запуска. Повторные серии и включение точек не разрешены. Агент Run не выполняет.

Сохранить порядок на физическом ПК. Перед Run USER проверяет состояние точек на хосте. **Break остановит всю PB-BUILD-W11-25H2, включая Codex и RDP.** При активном kd> повторный Break не нужен. Отдельные команды: `bl`, затем отдельный `g`, даже при ошибке. Продолжать только при всех точках d и известных неизменённых IDs0..6; при отличиях не включать/не перезагружать stage и не начинать Run, прислать вывод. Команды be/step и загрузка stage для этого контроля не нужны. Logopen не требуется.

Для согласованного одного запуска USER в административном PowerShell внутри VM:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-RedirectContextControl.ps1" -Phase Run -PreparationDirectory "C:\src\ProxyBridge-TestLab\artifacts\diagnostics\pb-redirect-control-preparation-20261016-190400-5cd405b0" -DebuggerPointsDisabled
```

Ключ — ручное подтверждение, не автоматическая проверка физического WinDbg. Дождаться возврата PowerShell и очистки, прислать весь вывод и путь Redirect control results. Точки всё время остаются отключёнными, дополнительный Break после штатного завершения не требуется. При ошибке не повторять Run/не переустанавливать драйвер/не менять систему. Если VM неожиданно остановилась в WinDbg, сохранить сообщение на хосте; g вводить отдельно, не объединять с другими командами. После возвращения VM дать PowerShell завершить очистку.

После одного Run сначала офлайн-разбор native/Core/очистки и полноты capture. Только затем отдельный план kernel-повтора. Агент не выполняет debugger/Run; разработка остаётся в своей рабочей копии.
