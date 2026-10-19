# Захват установки флага с ограничением срабатываний

Статус: non-runnable candidate. Нового Prepare/Run/регистрации/активации нет.
Старый пяти-точечный профиль retired, его повтор запрещён. Точки2..6 по
последнему console пользователя отключены, отдельныйg выполнен.

Live-сверка завершена: USER показал entry и+15f, setter+190 неизменен;
вызов перед ним liveидёт через nt!KscpCfgDispatchUserCallTargetEsSmep. Сохранены
отдельные candidateJSON и disabledstage вscripts/debugger; stageпроверяет8bytes
setter иCREATE/ACCEPT доизмененияточек, отключает5/6, не включаетничего.
Два roundtrip/no-enable tests passed. Не является runnableпрофилемстарогоlauncher.

## Новые статические сведения

В сохранённом tcpip.sys (SHA b0683bd7ed0f309e63b4e6e71675d8f04cfb0ea5533c3f5e8a13c6daca3b595a)
установка endpoint+30 bit20 найдена в WfpAleAuthorizeConnect RVA5be77,
WfpAleConnectCompletionNotification RVAsa9d8a/a9e12, WfpAlepAuthorizeSend
RVA13b80d и WfpAlepAuthorizeConnectSecureCompletion RVA1647e5. Очисткаbit20
есть в WfpAleIpsecForceInboundReauth RVA15fa54. Это результаты поиска конкретных
форм instructions, не доказательство отсутствия других способов изменения.

В WfpTlShimInspectRecvTcpDatagram RVA23662 проверяется endpoint(RBX)!=0;
RVA23667 читает flags30, RVA2366a проверяетbit20, RVA23670 ставитbit21 через
lock or [rbx+30],200000h. RBX получает входнойRCX в23511/23530.
Перед этой ветвью вызывается косвенный обработчик2363f, его return сохраняется
вstack+64 и EDI. На ветвиreturn1 дополнительное AL/указатель изRBP-38 могут
раньше вывести функцию в23c08. EDI остаётся raw результатом, это не объявленный
NTSTATUS/action enum. Нельзя назватьbit20/21 по смыслу без дополнительных данных.

## Более богатые снимки, меньше горячих точек

Кандидат src/pb_target_flag_candidate.py задаёт три точки:

- CREATE+396: один controlport42201, record/context/size/refs, sourceendpoint.
  После выбранногоCREATE отключает себя. Нечитаемый неидентифицированный
  selector не печатает строк для постороннего трафика.
- RecvTcpDatagram+190: непосредственно перед lockorbit21, только RBX равному
  выбранному sourceendpoint. Один снимок flags30/34,record,thread,raw EDI и
  raw R12/R13/R15; один stack k8. До печати отключает себя. Это precall snapshot,
  а не отдельно измеренный post-write переход и не полное покрытие writers.
- Accept+caf: только прежняя контрольная парапортов; status/output_raw/NBL/ep.
  Выбранное событие отключает все три точки.

Все actions считают собственные rawhits ДО фильтра: при16-м попадании отключают
2/3/4 и печатают одну PBFG_LIMIT/capture=incomplete. Верхняя граница48попаданий
длянабора — счётная, не гарантия wallclocklatency. У selectedsnapshots максимум
поодному, стек максимумодин/8frames. Новый setter observer может исчерпатьлимит
на посторонних вызовах: тогда результат неполный, нагрузку не повторять.
Нет точек на общей отправке или entry каждой loopbackпроверки, нет targetwrites,
автоматического Break/enable/step. Automaticdisable — только debuggerbd.
IDs5/6 остаютсяdisabled. Старые frozenprofiles не менялись.

## Проверка и оставшиеся шаги

Реальный SDK CDB проверил selected/nonselected/selected-unreadable/limit длятрёх
actions, real k8 и actual bd. .bpcmds подтвердил отключённое состояние; при
nonselected point остаётсяenabled до лимита. Думмиbreakpoints локальногоcmd.exe
имеют разныеадреса, иначе CDB переопределяет прежний ID поодинаковомуадресу.
Private proof: pb-target-flag-candidate-parser-20261019-r4. Это commandproof,
не runtimeстоимость/корректностьновыхliveсмещений. Kernel/product/traffic не было.

Выполненное user-controlled liveчтение: RecvTcpDatagram entry L18 и +15f L18.
После чтения отдельноg. ПередBreak предупредить о паузе всейVM/Codex/RDP.
До новогоразрешённогоплана не регистрировать candidate. Recoveryбудущегонабора bd2/bd3/bd4
и отдельноg; 5/6не включать. Не использовать старый пяти-точечныйRun.

Дополнительный runtime blocker: прошлые diagnostic-run/cohort всё ещёRUNNING,
несмотря на сохранённые cleanupснимки. Их не переписывать вCOLLECTED; до нового
Run требуется отдельная проверка завершения/допустимости по существующему gate.
Новый candidate не реализует обход этого gate и не является разрешениемRun.
Проверка: предыдущиеrun/cohort всёещёRUNNING; процессыCLI/ctsTraffic/logman/
tracerpt не найдены, но это не снимает existinggate. Assert-TargetHistory,
Invoke-TargetAccept.ps1:107 требует TARGET_INTERRUPTED_DIAGNOSTIC_REQUIRES_REBOOT.
Нужно USERперезагрузитьVM передследующимruntime; старыеstate не переписывать.
