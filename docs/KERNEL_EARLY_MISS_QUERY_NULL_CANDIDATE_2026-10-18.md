# Две точки на путях отказа: ранний miss и query NULL

Продолжение [lookup four result](KERNEL_LOOKUP_FOUR_RESULT_2026-10-18.md) после унификации [запускателя](KD_DIAGNOSTIC_SESSION.md). Агент не выполнял WinDbg/Run. Продукт и старые профили/комплекты не менялись.

## Почему нельзя просто перенести общий lookup trap

Текущий disk fwpkclnt снова совпал с SHAfae91d16768b1e0827eeaae71287ef12ef65dfcfd8e9209b4daf7b6a81001066; tcpip — b0683bd7ed0f309e63b4e6e71675d8f04cfb0ea5533c3f5e8a13c6daca3b595a. Read-only boot: Event12record16566/PrefetchBootId113, та же проверенная загрузка. В сохранённом live-листинге подтверждены восемь выбранных инструкций вокруг getter/общего статуса/раннего miss.

В просмотренном текущем disk-коде getter NULL после RVA330c попадает на330e. Туда же возвращаются успешная обработка найденной записи (jmp3408→330e, R14B уже1) и исчерпание списка (jmp3425→330e). Проверены байты и оба относительных адреса переходов. Далее статус выбирается на335e/3368 с conditional move. Поэтому перенос точки с335e на330e не убирает успешный путь, а точка только на3425 не покрывает начальный пустой список. В этих просмотренных местах не найден один failure-only адрес, охватывающий оба общих промаха. Это не доказательство отсутствия любых иных средств трассировки.

## Новый узкий профиль

`scripts/debugger/pb-kd-early-miss-query-null-candidate-20261018.json`, method `kd-early-miss-query-null-candidate-20261018-v1`, SHA2561b182afd166ece0d7b37df415c6c9997fdf7a327765537eccd489926bc6a2858.

| ID | Действие |
| --- | --- |
| 2 | Сохранить точный существующий EARLY_MISS: fwpk retrieve+f3, fffff8026aaa3223 |
| 3 | Заменить общий SEARCH_MISS на QUERY_NULL: tcpip WfpAleProcessSocketOption+2d0, fffff8026a861588 |

ID2 action/target/registration_command побайтно сохранены. ID3 берётся из ранее проверенного retrieve/NULL профиля: только RDI/RDX/R15D/RSP, без poi/wo/Cid; final gc. Его действие уже наблюдалось в прошлой bounded-пробе на этой загрузке. Новый current-live запрос этого адреса в этом шаге не выполнялся; используется ранее проверенный код при совпавших boot/disk identity, а не выдуманный новый live capture. Исполнение stack reads ID2 по-прежнему pending.

Обе выбранные ветки находятся на путях отказа, общий lookup success-site из профиля убран. Фактическая частота ловушек и уменьшение тормозов ещё не измерены. QUERY_NULL не ограничен PID Core, поэтому нужна привязка к его исходному запросу, а не подсчёт всех строк как ProxyBridge failures.

Положительная цепочка EARLY_MISS→QUERY_NULL→Core10022 для связанного endpoint/порта/порядка подтверждает раннюю группу отказа: getter NULL/sentinel до общего поиска. Это ещё не причина предшествующего отсутствия данных. QUERY_NULL без EARLY_MISS не доказывает общий search miss: полнота capture, фильтр, stack guards и lifetime/reuse остаются ограничениями. Успешные kernel query records и общий search miss напрямую больше не измеряются. Нельзя выдавать два редких места за полное покрытие истории контекста.

## Следующий USER шаг

Только замена отключённого ID3. Before Break предупредить: вся VM/Codex/RDP останавливается. Заранее recovery bd2/bd3/bl/g по одной; g отдельно даже после ошибки. Initial bl должен показать2d наfwpk+f3 и3d наfwpk+22e; иначе не менять inventory, g отдельно и прислать вывод. При ожидаемом inventory bc3, затем новый bp3 с предупреждением, что он создаётся включённым и VM нельзя возобновлять до bd3; bd3/bl/.bpcmds, отдельно g. ID2 не перерегистрировать, старые stage не загружать. Никаких be/Run сейчас.

После console review используется общий запускатель: только небольшой новый plan с новым review, без копирования runtime/скриптов. Нового plan пока нет. Первую пользовательскую пробу общего runtime пути и нового сочетания точек ещё надо рассмотреть; старую four-пробу не называть проверкой этого профиля. Bounded автоматически не разрешён, старые kits/демонстрационный migration plan не запускать.10061 вне активного разбора. Private audit `artifacts/diagnostics/pb-kd-early-null-candidate-review-20261018` содержит структурную проверку, CFG-переходы и сохранённые SHA старых профилей; не WinDbg parser/runtime verification. Stage/ZIP не создавались, инструкции только в чате.

## Регистрация подтверждена; готов маленький four plan

USER прислал console текстом в чат: исходные2/3d, bc3, новый queryNULL bp3/bd3, finalbl и .bpcmds показывают2d наfffff8026aaa3223/3d наfffff8026a861588 с ожидаемыми actions, затем отдельныйg. Ошибок регистрации в показанном выводе нет. Это ручной разбор chat paste, не raw attachment с выдуманным SHA. Private attestation явно сохраняет source_kind=USER_CHAT_PASTE_REVIEW_NOT_RAW_ATTACHMENT/raw_console_file=null. Ни события, ни работа stack reads этим не подтверждены.

Boot16566/113 сверён read-only; общий запускатель Prepare завершился WindowsPS5 exit0. Новый `artifacts/diagnostics/pb-kd-session-plan-20261018-091337-a586a7f5/runtime-plan.json`, SHA256 `0107734BDF095669183788C9DA970FB88DA20D416DDFCC62FF1C9714F6B1128C`. Только6файлов/22985байт/61frozen references; общий runtime повторно не копировался, старые102source/module/profile SHA совпали. Private audit `pb-kd-early-null-four-preparation-review-20261018`. Продукт/трафик/WinDbg агентом не запускались, новый Inspect не повторялся.

Следующий шаг — один USER Run four через Invoke-KdSession.ps1 с PlanPath/PlanSha/ProfileReviewed/DebuggerLoggerEnabled. Перед Break/каждым be2/be3 предупредить об остановке всей VM/Codex/RDP; recovery bd2/bd3/bl/g отдельно. Проверить existing2/3d, не повторять регистрацию; включить только2/3, bl, отдельноg. Можно закрытьGPT для экономииRAM. ПослеRun илиошибки bd2/bd3/bl/g отдельно, полный console+PS. Это первая runtime-проверка общего исполнителя и нового сочетания; успешный four безmiss не подтвердит тело failure-action2. Не повторятьRun и неувеличивать нагрузку до разбора; bounded этим review заблокирован.

## Four отработал; подготовлен отдельный bounded plan

USER Run `pb-kd-session-run-20261018-091910-2ed07351`:4native success/4исходныхCorequery api0, bytes32, peer54574..54577; errors[]. Workload COMPLETED, workers_stopped/driver_stop_observed=true, CLI graceful/post_stop_verified=true, forced=false, error пустой. Общий исполнитель вернулся `KD_SESSION_CONTROLLER_RETURNED_DEBUGGER_PENDING`; исходный10022 не воспроизведён.

Raw console USERc85331a7, SHA256649fd9cf4dc23e7292d60805cd696d60351166fd79b719bed51e8f8f0b3e522f: проверены точные actions/адреса во всех4inventory состояниях d/e/e/d, финальныеbd2/bd3/bl2/3d и отдельныйg. Событий EARLY_MISS/QUERY_NULL/UNREADABLE и Memory/Syntax/Bad register/Image load ошибок нет. Stack reads2 и положительное прохождение фильтра этим не подтверждены. Controller111.605197s; сокращение overhead не доказано, это не speed test. Проверены61frozen references, общий runtime inventory/SHA и неизменность38run/consoleinputs. Исходные отчёты не переписаны. Privateaudit `pb-kd-early-null-four-result-review-20261018`.

Следующий USER bounded256 ранее запрошен; после разбора four подготовлен новый малый план общим запускателем, без изменений исполнителя/бинарников/runtime. Review связан с фактическим результатом four, теми же profile SHA и boot16566/113, включает прежние frozen references и все four inputs. Полнота miss-actions остаётся false. WindowsPS5 Prepare exit0: `artifacts/diagnostics/pb-kd-session-plan-20261018-092346-4adad3d3/runtime-plan.json`, SHA256 `F98CE5E661F53139EDD09912D280CA6A0F2198198FDD2F4090854A2760E6F50B`.6files/55750bytes/106frozenrefs/102oldSHA unchanged, новых runtime/product copies нет. Privateaudit `pb-kd-early-null-bounded-preparation-review-20261018`.

Policy4→64→256→4/328,512KiB,8shold,ConnectEx32,originalsinglequery,clientwait120s/cohortbudget240s/RAMgate2GiB. Active только2/3, никаких bp/staging. Один USER Run с PlanPath/PlanSha/ProfileReviewed/DebuggerLoggerEnabled/BoundedLoadReviewed. Before Break/каждыйbe warningwholeVM/Codex/RDP, заранееrecoverybd2/bd3/bl/g отдельно. Сначалаinventory2/3d, be2/be3/bl/g по одной; послеRun/error bd2/bd3/bl/g отдельно. Можно закрытьGPT радиRAM. Неrepeat/не640/неавтоматическипродолжатьпослеошибки. Связанные положительные EARLY_MISS/QUERY_NULL/Core10022 могут подтвердить раннюю группу; отсутствиеEARLY_MISS неproof общегоsearchmiss.10061 отдельно не разбирать. AgentRun/debuggercontrol/productchanges не было.
