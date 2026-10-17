# Подготовка пробы accept/query на четырёх соединениях

USER регистрация новой точки2 проверена по attachment `a4c5e1bf-5c5c-4cbd-8439-293e5df22642/Вставленный текст.txt`,6243bytes,SHA256 `edb949cf7e157d572e1221b35614ddcbd5562448bbccbaf44dae327a27f63c6b`. Первоначальный bl только3/4d; загружен ровно один новый add-disabled stage, выполнен только bp2→bd2. Итоговый bl — только2/3/4d, точные addresses/actions; .bpcmds точен, затем отдельныйg, без показанных ошибок. Это регистрация, **не выполнение actions/port reads/проверка фильтра**.

Private raw console сохранён отдельно, SHA копии совпал. Registration-reviewSHA `3e36b6463ab8685230f458dfb98c492a967a970b1bc371248490dd7dab6396f4`,statusACCEPT_QUERY_THREE_DISABLED_POINTS_REGISTERED_ACTIONS_PENDING. Его flagsactualactions/gc/portfilter/flowbinding/rootcause остаютсяfalse.

## Новый ограниченный контракт

Метод `redirect-kd-accept-query-four-v1`: только4 соединения,512KiB каждое,8s hold,ConnectEx/pending32,original listener/delay0,один исходный query. Levels пусты, recovery и нагрузки64/256/640 в этом контроллере нет. Прежние пинованные CLI/Core/driver копируются без сборки/установки; существующий four-only module не меняется.

Registered IDs2/3/4, active2/3, inactive4. ACCEPT_STATE2 отбирает rawlocal0xda84 (ожидаемый Core34010), сохраняет peerport/endpoint/record; QUERY_READ3 остаётся прежним. QUERY_STATUS4 не включается. Native reporter по файлам не измеряет NTSTATUS, filter coverage или kernel pair binding и не объявляет их подтверждёнными автоматически.

Новые отдельные файлы: `scripts/Invoke-KdAcceptQuery.ps1`, `scripts/Invoke-KdAcceptQueryWorkload.ps1`, `src/pb_prepare_kd_accept_query.py`, `src/pb_kd_accept_query_report.py`. Старые Session/Bounded/Boot source/kit не изменены. Wrapper требует ручные AcceptQueryProfileReviewed/DebuggerLoggerEnabled, сохраняет mutex/lease/legacy/interrupted gates; boot binding — frozen Event12/registryBootId, не плавающая CIM-оценка. Preparer ограничен рассмотренным boot16348/112 и точной registration/static/live metadata. Никакого debugger control.

Ресурсный gate2GiB RAM; client wait60s, бюджет phase180s. Хеширование/startup/cleanup имеют отдельные интервалы, это не жёсткий wall-time предел при остановке VM. При ошибке/timeout/resource bound не повторять автоматически. Snapshot Python используется с isolated pth и -B вместо изменяемого общего SDK при Run.

## Проверка файлов

PS5.1/7 parse двух новых PS scripts и four-only preset прошли; cohort/продукт/сеть не вызывались. PythonAST проверен. Pure reporter на адаптированной копии старой four пробе получил4 исходных query/0nativefail и kernelpending; адаптированную328серию отверг по contractphases. Это синтетическая проверка кода, не новый Run.8358 защищённых старых frozen/capture inputs проверены неизменными до подготовки.

Private audit `artifacts/diagnostics/pb-kd-accept-query-preparation-review-20261017/`: raw registrationconsole/review,protectedinputs,sourcegenerator,PS5/7verification,adaptedfixtures/reports,Prepareconsole,validation.json. В Git не добавлять. Новый kit создан fresh, без refreeze/Resume старых комплектов.8358 старых inputs повторно проверены неизменными после подготовки.

Fresh kit `artifacts/diagnostics/pb-kd-accept-query-preparation-20261017-081124-5b6ae9b8`: Windows PowerShell5.1 Prepare exit0, встроенная общая проверка FILES_VALIDATED,8294 frozen files/8197 snapshot files. Отдельный повтор Inspect без новых изменений не выполнялся. PlanSHA256 `40F9DB349FF8DD13FC74A43AE10D3E16252956882F6D42787C684C45702FD766`. Product_started/traffic_generated/driver_installed/debugger_control/runtime_readyfalse; готовность файлов не подтверждает готовность/результат runtime.

Desktop VM `C:\Users\LabAdmin\Desktop\PB-KD-Accept-Query-Four-20261017.txt` содержит полную инструкцию для сохранения на физический ПК: warnings/recovery, USERbl→be2→be3→bl→g по одной, ожидаемые2e/3e/4d, один Run с проверкой SHA в общем scriptblock и throw до вызова при несовпадении, финальныеbd2/bd3/bl/gотдельно. Выполнять только после отдельного согласования одного Run. GPT можно закрыть перед пробой; stage больше не загружать.

## Что должна проверить будущая USER проба

После полного kernel console review проверить actual ACCEPT_STATE и QUERY_READ для четырёх исходных запросов: rawlocal соответствует34010; swappedpeerport совпадает с Core peer_port и ownednativeendpoint; каждый отобранный accept/query относится к одной проверенной паре, учтены порядок/повторное использование адресов endpoint/границы lifetime. Отсутствие ACCEPT_STATE или лишние/неоднозначные кандидаты — ограничение покрытия, не доказательство отсутствия record.

Сравнить recordA на общем join и recordB перед query. Join не доказывает выполненный store. `status_esi` — сохранённое сырое ESI, **не eax результата retrieval**; не выдавать его за NTSTATUS получения metadata. NULL в A/B допустим для диагностики и фильтром не исключается. Полного TCPtuple/общегоQPC/CREATE/FREEcoverage эти две точки не дают.

Проверить продолжение/actions/guards на реально наблюдённом пути. Отсутствие UNREADABLE не проверяет саму ветку UNREADABLE и не доказывает общую gc safety. Измерить наблюдённые query/phase elapsed и отметить субъективные лаги отдельно; отбор вывода не устраняет гарантированно стоимость всех software breakpoint hits. Даже удачная four проба не разрешает автоматически нагрузку или расширение профиля.

## Стоп-пункт

Комплект/autoSHA инструкция готовы, файлы проверены. Следующий шаг — отдельно согласовать один USER Run4. Существующие2/3/4 в конце user console всеd/g. До согласования не Break/be/Run. После согласования USER включает только2/3,4остаётсяd; по возвратеPS/ошибке USER отключает2/3,bl,gотдельно. Перед каждым Break/enable предупредить о паузе всейVM/Codex/RDP, recovery заранее на физическом ПК, команды по одной/g даже после ошибки. Stage повторно не загружать. Агент runtime/debugger/system/product не выполняет/не меняет.
