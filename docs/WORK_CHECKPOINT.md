# Work checkpoint

## 2026-10-07: полная WFP/AFD нагрузочная трасса разобрана

USER151313 Run153716-f140a1c9/fullTrace153714-1811d8fe: OFFLINE_FULL_WFP_AFD_LOAD_CORRELATION_COMPLETE_PRIVATE_CAUSE_UNPROVEN.968 exact owned WFP/AFD/TCP/kernel/Core/query chains,96 original C0000225→WSA10022;32@256+64@640,872 success/data436MiB/recovery4sameCLI1856. All native owned Apply301/target1856/relay34010 +unique CorrelationId/Classify/Auth NTSTATUS0 before first SYN;2763 selected classify unique TransportEndpointHandle/IsReauth0. No visible second classify on native handles; private write/free still unobserved.

Actual AFD listener bind/life observed; original Core passes SOMAXCONN, provider/AFD listen200.4019 Pause TLBacklogCount200/201→Unpause160,51,3511/95,7253/62,5418ms;32 native drops30/retry/context fails in each paused interval. All96 exact STATUS_NOT_FOUND within PID/TID/rawQPCquery; accepted AFD child close follows query failure, reuse bounded by create..close.872 successes no native SYNdrop30/retry. This is accept queue pressure, not driver table overflow/capacity or a proven Windows/driver bug. No equality assumed between WFP/AFD/TCP object types.

ETL baseline1MiB/1875selected/load18,375MiB/102667selected,loss0buffers0/QPC10MHz/readclosewrite0/declaredgap no newcohort. Independent xperf102667 headers+available numeric/text/IPv4/bool fields exact,8header collisions resolved by payload; Get-WinEvent96WPP payloads exact. Other binary/zero-length fields explicitly limited. Kernel968/NULL0/overwritten0/unconfirmed0/reportreevalexact.55runtime13outer hashes verified,271newUSERfiles+223previous unchanged. Saved CLI graceful/unforced/receiver0/helpercollector sampler0; native load256exit32/load640exit64 retained;resource5AVAILABLE. SavedRestore baselinehash/pathStopped/detached checked/currentglobalfalse.

Audit [analysis.md](../artifacts/diagnostics/tcp-wfp-full-load-review-20261007-153714/analysis.md)+validation.json. No binary/controller/query change, build/sign/install/livecapture/traffic/refreeze/Resume/report rewrite. NEXT direct observation of private endpoint context transfer/free/retry/query; physical host OS/access asked before choosing transport. No new ordinary ETW Run needed. BCD/trust/hypervisor/proxy/network/UAC/password/autoreboot/subagents/productfix remain untouched; source/docs checkpoint/push authorized, ignored evidence excluded.

## 2026-10-07: единый WFP/AFD контроллер подготовлен

FINAL новый комплект130731-dbfa7b1c: PS5 Prepare и PS5/7 Inspect FILES_VALIDATED/0;55 runtime +13 outer hashes verified. CLI/Core/sys побайтово совпадают172202, bundleacece5c3;140 файлов source copy exact. Продукт/драйвер не пересобирались; собран только offline ETL decoder. Original очередь, одна local/SOCKS5 серия, ConnectEx32,4→baseline coverage gate→64/256/640→4, sameCLI. Дополнительные WFP/AFD журналы собираются вместе с TCP/WPP/kernel/Core; snapshots read-only. После baseline сохраняется и проверяется первый ETL; при пробеле нагрузка не начинается. Во время проверки ETW приостановлен, интервал записан; новые cohorts не запускаются. Второй ETL covers load/recovery,64MiB каждый; native errors не становятся PASS.

Actual saved ETL decode42477raw headers/payload exact;17synthetic coverage rejects;PS5/7 по13capture/policy/cohort +8frozenplan checks,AST6.322USER files unchanged; прежние plans не refreeze/Resume, общие source bindings четырёх контроллеров изменились дополнительно к прежним отличиям parent172202. Новый runtime source map фиксируется отдельно. Actual nonadmin Install отказал FULL_METADATA_REQUIRES_ADMINISTRATOR до mutation; receipt отсутствует, trace/product/traffic не запускались. Реальная эмиссия WFP/AFD и exact load object matching/private transfer/free/rootcause ещё pending. Audit tcp-wfp-full-development-20261007/validation.json и новый verification/HANDOFF.md/handoff.json.

NEXT USERADMIN [новый wrapper](TCP_WFP_FULL_METADATA_DIAGNOSTIC.md) Install→толькоsuccess ручная reboot→Run2–4min+two trace saves/decode; дождаться очистки/guarded Restore и передать tcp-wfp-full-trace root даже при ошибке. TRACE_SAVED_LOAD_CORRELATION_PENDING означает готовность к офлайн-анализу, не PASS продукта. Новый handoff заменяет прежний черновой NEXT; не повторять local/Linux matrix. Нет BCD/trust/hypervisor/proxy/network/UAC/password/autoreboot/subagents/productfix. Source commit/push разрешён, ignoredkits/captures/private settings не являются Git backup.

## 2026-10-07: найдены источники для единого расширенного сбора

Запрос USER: перестать проверять гипотезы по одной. Статически подтверждены Windows WFP Callout provider (GUID00e7ee66-5b24-5c41-22cb-af98f63e2f90, шесть redirect metadata variants, keyword4/level<=5) и AFD29 templates, совпадающие с прежним локальным каталогом. Новые поля: WFP CorrelationId/TransportEndpointHandle/CalloutId/IsReauth и redirect actions; AFD Endpoint/AcceptEndpoint/CurrentBacklog/Backlog/PauseUnPause/TLBacklogCount. GUID также документирован Microsoft. Реальная регистрация Callout не наблюдалась; эмиссия, семантика счётчиков и точная связь объектов пока не проверены.

Новый [черновой WPR профиль](../config/tcp-wfp-full-metadata-draft.wprp) объединяет эти источники с прежними16TCPIP IDs и original Winsock status; лимит64MiB. Actual `wpr -profiles` exit0 подтверждает разбор файла, не запись событий. Профиль не подключён к контроллеру и не является готовой командой Run. Capture/traffic/build/install/registry/BCD/hypervisor changes отсутствуют;322 USER files последнего парного опыта сохранили hashes. Audit: `artifacts/diagnostics/tcp-endpoint-expansion-review-20261007/validation.json`, status STATIC_EXPANSION_FEASIBILITY_VERIFIED_RUNTIME_PENDING.

NEXT: [единый сбор](TCP_CONTEXT_ENDPOINT_LIFECYCLE_PLAN.md) с отдельным новым sealed controller/handoff; одна команда, проверка owned baseline emission до полной нагрузки, WFP/AFD/TCP/WPP+kernel/Core/CTS одновременно, exact rawQPC/identity/lifecycle correlation и явные coverage gaps. Парную local/Linux матрицу и использованные frozen plans не повторять/не refreeze. Прямое наблюдение памяти внешним kernel debugger потребуется только если нужный private transfer/free переход не представлен дополнительной трассой; hostOS/access/transport пока неизвестны. Это уточняет прежний слишком категоричный NEXT про обязательный WinDbg. Корневая причина/Windowsbug/driverbug/capacity/fix/PERF остаются недоказанными. Source commit/push разрешён, секреты и ignored captures исключаются.

## 2026-10-07: парный local/Linux контроль разобран

USER093635 candidate Run094224-62cd5574 / statusTrace094223-d0d110cc: OFFLINE_EXTERNAL_PAIR_TRACE_ANALYSIS_COMPLETE. Local96/968fail(32@256+64@640),Linux95/968(32+63); все191originalSTATUS_NOT_FOUND C0000225→WSA10022 строгоPID/TID/rawQPCentry..exit,0unassigned. ВсеfailureSYNdrop30/SO_PAUSE_ACCEPT→retry→query; Linuxодинsocket дваretry/3inspection,по192nativeSYNdrop/retry.1745successno-native-retry,872,5MiB/fullroutes/GUID/LinuxSHA. Endpoint destinationexternal неустраняетfault; native→Core loopbackвобоих,поэтомуloopbackrelayprivatecontextmechanismнеисключён.1936scopedalloc32/Apply/APPIDblindspot retained; privateWindowsrecordmove/free/Windowsbug/driverbug/tableoverflow/capacity/fix/PERFнепроверены.

ETL13,25MiB/106,0231402s/SHA619f6237/lost0buffers0,42286TCPIPfullpayloadmultisets2decoderexact/191statusRAW+WinEvent+xperfexact/UserData4/QPC10MHz,UTCdrift5,1853msнеиспользован.8successfulfixture→Linuxoutboundretry/dataOK/causeunknown;8otherloopback5985retry/notserviceidentityclaim.4923otherdrops4752ownedpairphase/171unassigned. Reports3reevalsexact;322newUSERfiles+oldsnaps+57runtime7trace+PE/PDBunchanged. SameCLIrecovery4both/gracefulworkers0/unforced/resource10passed(min5209952256bytes)/5Linuxunitscleanexit0. SavedRestorebaselinehashStopped/detachedverified/currentglobalfalse. Audit [analysis.md](../artifacts/diagnostics/tcp-external-receiver-review-20261007-094223/analysis.md)+validation.json; ignoredcapturesnotGitbackup.

NEXT [endpoint-lifecycle plan](TCP_CONTEXT_ENDPOINT_LIFECYCLE_PLAN.md): outside-VMkerneldebugger/identity+transfer+free+retry+query+unscopedwrites. HostOS/access/transport not confirmed; noBCD/trust/hypervisor/UAC/rebootchanges/newRun/productfix. Completed093635handoffnotnewcommand/nooldrefreezeResume. Source commit/pushauthorized; secrets/capturesexcluded. RemoteUIcontrollerpending.


## Парный local/Linux контроль подготовлен; новый Run ожидается (2026-10-07)

FINAL tcp-redirect-context-preparation-20261007-093635-91ea36ae: PS5 Prepare, PS5/7 Inspect FILES_VALIDATED; 57 runtime + 7 trace hashes, WPP traceGUID UserData4. CLI/Core/sys byte-identical172202, bundle acece5c33a9fd03f41e16b2e4b55f331633dda857c806a3cbe11724101bc9302; сборки/подписи/установки/трафика не было. Opt-in local → linux, исходная очередь/локальный SOCKS5/ConnectEx32/4→64→256→640→4. Linux контролируется отдельно по фазам, strict GUID/data/hash/lifecycle; Windows QPC не смешивается с Linux clocks. Новые отчёты остаются TRACE_PENDING; ошибки не становятся PASS.

Три старых kernel-отчёта повторно exact; синтетическая пара сохраняет96отказов,8corrupt rejected. PS5/7: cohort6+dispatch3+policy13 каждый, AST; реальный on_connect с fake network —8destinationcases. Два сохранённых новых case-report reeval exact после исключения собственных generatedoutputs из source hashes. Исторические USER data сохранены. SSH Inspect подтвердил deployment; receiver не запускали. Текущий token неadmin: actualInstall отказал до регистрации/no receipt. Свободная Windows RAM наблюдалась2.27GiB, нужно>=2GiB с запасом; RESOURCE_BOUND не причина продукта.

NEXT USERADMIN Invoke-KernelTcpExternalReceiverDiagnostic.ps1 NEW093635 -Phase Install → только success ручная reboot → Run4–8min+traceSave; дождаться очистки/guarded Restore/save, передать tcp-context-status-trace root даже при ошибке. Команды в TCP_CONTEXT_EXTERNAL_RECEIVER_CONTROL.md и FINAL verification/HANDOFF.md. Новый verification/handoff.json фиксирует бинарники/freeze; промежуточный неустановленный092520 заменён, не refreeze/Resume. Точная Windows private-context lifecycle причина ещё не доказана; remote UI не включён. Изменения исходников/doc отправляются в текущую checkpoint ветку; секреты/артефакты вне Git.

## Согласован штатный SSH-сценарий Ubuntu (2026-10-07)

USER задал новый remote workflow: generated SSH key/public copy для root authorized_keys, IP/optional port, автоматическая настройка или проверка готового узла, запрет тестов без соединения. Только последние Ubuntu; точный allowlist/LTS policy пока не определён. План REMOTE_UBUNTU_SETUP_PLAN.md описывает backend fail-closed/fresh per-test route checks, idempotent setup, full catalogue goal и текущие пробелы. Код remote wizard/controllers не реализовывался и REMOTE_CONTROLLER_PENDING не снимался. Следующий диагностический шаг остаётся парный local/Linux receiver с local SOCKS; Windows internal-context lifecycle ещё неизвестен.

Предыдущий source checkpoint c3c5f93dc0c015ed0a5627e9cf0720db43df4499 отправлен в origin/codex/checkpoint-20261007 и remote SHA проверен. Секреты/ignored runtime evidence не включались. Новый согласованный план сохраняется в той же ветке.

## USER разрешил Git checkpoint и изменения диагностической VM (2026-10-07)

Пользователь разрешил необходимые изменения расходуемой Windows VM для текущей диагностики и потребовал push, чтобы не потерять исходники. Общий прежний запрет commit/push отменён; необходимо сначала сохранить текущие накопленные исходники/документацию отдельным checkpoint и подтвердить remote commit. Private keys/settings и ignored artifacts/bin/captures в Git не включать; это source checkpoint, не backup runtime evidence и не утверждение полной функциональной проверки всей WIP-работы. Рабочий proxy для Codex сохраняется; разрешение не повышает current process token автоматически. Потенциально разрушительных VM действий до сохранения не выполняли. До push установлен baseline origin/main=a85a370a47f58604e5e588c4c027a95103c29a7c.

## USER топология: две VM на одном ПК, системный proxy для Codex (2026-10-07)

Пользователь подтвердил общий физический хост Windows/Linux VM и системный HTTP proxy Windows для Codex. Readonly HKCU наблюдение/USER screenshot сохранены в linux-cts-compat-review-20261007-080842/topology-user-confirmation.json, секреты/proxy-env значения не выводились. Настройки proxy, hypervisor network, NAT/TUN, registry не менялись. Локальный pinnedctsConfigSHAda00... проверен (WSASocket/ConnectEx selector), официальный pinned MicrosoftctsConnectEx.cpp передаёт target sockaddr в ctConnectEx/Winsock без HTTP proxy API. Вывод только о checked client code, не global absence of transparent interception/TUN. Предположение NAT согласуется с native/receiver address changes, механизм не доказан. Общийхост означает external относительно loopback VM, не независимый физический receiver/ресурсы. NEXT отдельныйoptinpairedkernelcontrol, same localSOCKS; UIremote/fullkitpending, trueprivate-record cause stillunproven. Пользовательского уточнения physicalhost больше не ждать/не спрашивать снова. Нет traffic/driver install/reboot/login/subagents/refreezeResume/productfix/commitpush.

## USER Windows CTS → Linux: совместимость и смена адресов (2026-10-07)

USER linux-cts-compat-20261007-080842-cd3262eb:4/4nativeGUID/2MiB/NetworkErrors0/ProtocolErrors0/naturalexit0; Linux4exactGUID/payloadSHA164092.../DONE/reset-after-completion/accepted4completed4failed0peak4/forced0handlers0/serviceexit0. Known OFF before/after/other-driver inventory unchanged; scoped, not global proof. Initial strictv1 INCOMPLETE DIRECT_RECIPROCAL_ENDPOINTS_DIFFERS: native172.30.238.75:57597–57600→receiverPeer192.168.0.136:64121/64123/64158/64162. Readonly currentWindowsCIM confirmsMicrosoftVirtualMachine/HypervisorPresent/defaultgateway172.30.224.1. NAT compatible with observations, mechanism unobserved; physical Linux VM host/topology USER reply pending.

Only2lab runtime files changed: reporter optin guid-correlated/v2 + wrapper sealedmethod/endpoint_policy. Original strictoutput exact/USER19+oldplan unchanged, no overwrite/refreeze/Resume. Newwirecompatibilitytrue/directedendpointreciprocityfalse/translationmechanismfalse/productroutefalse/PERFfalse/capacityfalse, fullGUID/data/hash/lifecycle/source/offgates maintained. New separate report review/reevaluated-final NATIVE_CTS_LINUX_COMPATIBILITY_VERIFIED_TOPOLOGY_UNCONFIRMED/errors[]. Savedpositive+newv2positive+oldstrictpositive/USERfailureexact+23negativecases passed; first temporary fixture assumedUTF8CSV and failed, correctedUTF16-aware verification passed with no source guard relaxation. PS5PS7AST/PythonAST/actualPS5PreparePS5PS7Inspect FILES_VALIDATED0 new081522-8d38f129; oldplanInspect deliberate PLAN_BINDING_DIFFERS. No new native/receiver/product traffic/build/install/reboot/login/subagents/maintainedtests.

Audit artifacts/diagnostics/linux-cts-compat-review-20261007-080842/{analysis.md,validation.json,original-evidence-sha256.json,negative-validation.json,strict-reevaluation.json,reevaluated-final/summary.md}. Previous NEXT075455 USER Run completed; no repeat needed. NEXT distinct optin paired originalqueue local/external kernel experiment with GUID-aware boundary and actualdrop/retry; fullcontroller/kit/UIremote stillpending. ExactWindowsprivate-record lifecycle/rootcause unproven. Shortchecks<5min allowed/no UAC-password-reboot-driverinstall bypass.

## Linux CTS receiver foundation и короткий контроль (2026-10-07)

Пользователь поручил проверить имеющееся SSH-соединение самостоятельно, затем повторно разрешил проверки менее 5 минут и попросил это зафиксировать. Новые приоритетные записи в AGENTS.md: короткий Run/необходимые наблюдения допускаются; обход UAC, парольный вход, автоматическая перезагрузка/driver install и дробление долгих опытов не разрешены. Наблюдённый ED25519 host key закреплён в приватном отдельном known_hosts по пользовательскому поручению; independent_console_verification=false, trust_method=user-authorized-observed-ssh-key. SSH root/IPv4/дистрибутив/ресурсы проверены, private connection profile/ключи только LocalAppData.

Ubuntu 22.04.5/Python 3.10.12/systemd. Новый изолированный src/pb_cts_push_receiver.py установлен в versioned /opt/proxybridge-testlab-diagnostics; sourceSHA 9df9708a718ab91b08d54d28676b2e96c1201e2f0bd5c81a9e40712801841011, actual повторный SSH Inspect совпал. CTS2.0.3.9 push/data-only contract UUID37/uint16LE byte-period65536/DONE4; no maintained receiver replacement/performance claim. src/pb_linux_cts_control.py + scripts/Invoke-LinuxCtsReceiver.ps1: strict pinned SSH, dynamic transient unit, source/time/FD/connection bounds, controlled owned stop, ExecStopPost receipt, SHA collection. Readiness-error owned-stop дополнительно проверен offline stub (первая stub попытка неверно моделировала fresh-directory gate и отказала; corrected stub3passed, source guard не ослаблен).

Actual Linux-only lifecycle accepted0/failed0/forced0/exit0; wire fixture 4 parallel valid512KiB +4 adverse: corrupt/earlyEOF/excess/reset-before-DONE all retained, completed4/failed4/forced0/handlers0/exit0. Saved journals hashes/exit receipts exact, receiver stopped. Real Windows native и ProxyBridge traffic не запускались; Linux fixture не доказательство внешнего product route. Audit artifacts/diagnostics/linux-cts-foundation-review-20261007/{linux-fixture-validation.json,linux-deployment-inspect.json,synthetic-validation.json,control-stub-validation.json,nonadmin-run-refusal.json,HANDOFF.md,validation.json}.

Новый scripts/Invoke-LinuxCtsCompatibility.ps1 + src/pb_linux_cts_compatibility_report.py подготовлены: direct OFF4x512KiB@64KiB/s/ConnectEx32/rude/verifydata, shared lease/mutex, restore/legacy/interrupted crossboot gates, before/after interception observations, native GUID/path/SHA/CSV ↔ Linux GUID/tuple/data/hash/exit exact, errors stay INCOMPLETE. PS5Prepare/PS5PS7InspectFILES_VALIDATED0, PythonAST3/PS5PS7AST2/onefullsynthetic+16corruptreject. Fresh plan linux-cts-compatibility-preparation-20261007-075455-ab612ebd, planSHA47eb615a2218ec914fe0ac824e132daef1d2e6e77b8d3a3671d75ad1c8e2a017. Actual current-token Run exited1 LIN​UX_COMPAT_REQUIRES_USER_ADMINISTRATOR BEFORE Windows state query/receiver/traffic, no UAC/login bypass. NEXT run this exact short plan from already-elevated USER PowerShell (command in HANDOFF); if elevated agent token available, USER permission already covers <5min. Then build distinct paired local/external original-queue kernel control; full topology controller/GUI REMOTE_CONTROLLER_PENDING. Windows-private-record lifecycle exact cause still not proven; no product fix/kernel build/install/old refreeze/Resume/subagents/commit/push/maintained tests.

## Linux VM и SSH-ключ для внешнего получателя (2026-10-06)

Пользователь предложил вместо выключенной HLK-машины развернуть Linux VM и дать полный SSH-доступ, пользователь root; затем явно попросил самостоятельно сгенерировать ключ, добавить публичную часть обещал вручную и сообщить IP. Существующий Server Setup поддерживает Debian/Ubuntu/systemd, SSH private-key-only и fingerprint trust; новые benchmark plans всё ещё возвращают REMOTE_CONTROLLER_PENDING. В текущем UI mode=remote означает расположение SOCKS5, а receiver — отдельная роль. Для root-cause контроля согласованное предложение сохраняет SOCKS5 на Windows и меняет только исходное назначение на Linux; удалённый SOCKS5 в том же опыте смешал бы факторы. CTS2.0.3.9 Windows engine/receiver и новый lab receiver-протокол несовместимы автоматически с существующим pb_net_endpoint echo: нужна отдельная совместимость при сохранении исходного native генератора.

Создан отдельный Ed25519 keypair в private LocalAppData вне репозитория. После стандартных ACL ssh-keygen локальный ACL сужен через icacls до текущего SID+LocalSystem, protected=true/две записи; ssh-keygen -y подтвердил совпадение публичной части, fingerprint SHA256:oFO3nciXYz+io4P4c61SWc/kTR+yacczp8x4QzhAEOo. Приватные данные/пути не внесены в репозиторий; публичный ключ передаётся пользователю для authorized_keys. Никакого SSH подключения/пароля/Windows admin/SCMWFP/трафика/install/reboot/build не было. NEXT получить IP/порт/host fingerprint/root key authentication/дистрибутив и sudo-доступность; Linux SSH подготовка теперь явно разрешена пользователем, Windows runtime/install границы не сняты. Новый Linux receiver/controller/UI путь пока не реализован и не объявлен READY.

## Предложена HLK-машина для внешнего получателя (2026-10-06)

Пользователь предложил соседнюю HLK-машину, сейчас выключенную; обычно подключается по RDP. IPv4/доступность/администратор ещё не подтверждены. Проверены исходники: текущие controller/module/proxy/evaluator привязаны к loopback, готовой внешней команды нет. Сохранён конкретный отдельный план [TCP_CONTEXT_EXTERNAL_RECEIVER_CONTROL.md](TCP_CONTEXT_EXTERNAL_RECEIVER_CONTROL.md): новая парная original-backlog серия local/external, 4/64/256/640/4, ConnectEx32, 8 с, 64 KiB/с; оба варианта должны воспроизвести drop30/retry перед выводом. Receiver/GUID evidence с второй машины; remote QPC не смешивать с local; loopback-to-remote kernel rewritten address наблюдать, не предполагать. Машину включает пользователь, затем передаёт её IPv4. Никаких исходников runtime/бинарников/frozen-планов не изменено; никаких install/run/login/reboot/SCMWFP/traffic/build/subagents. Нового комплекта и команд запуска пока нет.

## Интернет-поиск гипотез по запросу пользователя (2026-10-06)

Пользователь явно разрешил интернет-поиск; прежнее ограничение HTTP для этой работы снято, остальные границы сохранены. Первичные источники: Microsoft Windows-driver-samples #979 (сообщение о loopback Connect/Redirect, поведение отличается от нашего) и Npcap #363 (автор воспроизводил ошибку CONTEXT IOCTL при loopback capture). Точного публичного совпадения SO_PAUSE_ACCEPT → retry → C0000225 в выполненном поиске не найдено. Это гипотезы, не атрибуция нашего сбоя. Все 968 сохранённых original kernel records имеют remote_v4=new_v4=16777343, то есть 127.0.0.1 в представлении этих записей. Проверенный участок pinned драйвера заполняет handle/PID/context/size и не освобождает context после Apply; остальные ветви и unscoped classify этим не исключены.

Исследование и план различающих проверок: [web-research-20261006.md](../artifacts/diagnostics/tcp-context-status-review-20261006-174008/web-research-20261006.md). Ближайший предлагаемый контроль — внешнее исходное назначение при том же локальном прокси, исходной очереди и подтверждённом drop/retry. Без воспроизведения триггера отсутствие ошибки не является опровержением. План не реализован/не собран/не подготовлен/не запущен; никаких Install/Run/admin/login/reboot/SCMWFP/traffic/subagents/refreeze/cleanup/commitpush/fix.

## Исходный NTSTATUS подтверждён; полный маршрут проверен (2026-10-06)

USER174009-c99d8b28 / contextstatus174008-1007a7a4 OFFLINE COMPLETE:96original WSA10022 exactlySTATUS_NOT_FOUND C0000225 via rawQPC/PID/TID inside originalentry..exit,0unassigned/2808successnoevent. Original32@256+64@640fail,controls1024/delay6500/968 each;all96 inspection1553→drop30SO_PAUSE_ACCEPT→retry1→second1553→connect501.273–515.507ms→queryNotFound→CorecloseBEFOREupstream. Both1553retained/headerPID0DPCnotlogicalownership; primaryTCP1033/1017payloadPIDtuplephaseTCBlife exact. ActualWPPformat CORRECTS prior20payload assumption: traceGUID97dcf1eb-61bd-3c9f-e009-df6b3349ea30 in EVENT_HEADER.ProviderId,UserDataLength4/littleendianNTSTATUS; enableGUIDac7ff34d different. ONLYnewaudit matcher-v2/30synthetic/RawProcessTrace-GetWinEvent-xperf96exact; oldmatcher/plans/receipts unchanged. TCPIP71659fullpayloadmultisets/rawQPCexact;ETL22.5MiB/169.726s/SHAf85702b0/lost0buffers0/QPC10MHz/UTCdrift8.2752msNOTused. Full2808routes/data1404MiB; actualSleep659.277ms/baselinecontext659.591–662.929ms/3SYNbeforeSleep1during/noRetry; wait-alone500msTTLunsupported. Other8941drops5806ownedpair-phase/3135unassigned;8retry5985outsideownedroute/notserviceidentityclaim. All2904scopedalloc32/Apply;APPIDscope retained. Savedreports3+aggregateexact/cleanupnatural0unforced/resource15/RestorebaselineStoppedhashdetached/currentglobalfalse. New215+old371USERhash/pinned138/base3/frozenold48+4+8/new48+7+8/20localPEbytegates+PEPDB unchanged.

Audit [analysis.md](../artifacts/diagnostics/tcp-context-status-review-20261006-174008/analysis.md) +validation.json; earlierNEXT172202InstallRun completed USER/no blindrepeat/no newkit. ImmediateCoreclose mechanism and queue-refusedSYN retry trigger confirmed; privateendpointrecord transfer/free execution/Windowsbug/driverbug/tableoverflow/capacity/fix/PERF NOTproven. NEXT onlyunresolvedWindowsprivate-record lifecycle, publictrace insufficient. NoagentInstallRun/adminloginpasswordreboot/SCMWFPtraffic/HTTP/subagents/refreezeResume/cleanup/commitpush/maintainedautotests/maintainedproductfix. Broaderlabpending.

## Исходный статус Windows: следующий целевой сбор подготовлен

- 2026-10-06 USER continue exact-cause analysis: offline local PE/PDB path verified (19 byte gates + BUFFER_TOO_SMALL map), tcpip CONTEXT reads endpoint+1c0; null->STATUS_NOT_FOUND C0000225->mswsock10022; INVALID_PARAMETER also10022; BUFFER_TOO_SMALL->10014. Static parent-to-child move of +1c0 clears parent, NOT observed live/not proven refused-SYN loss. Kernel all2904 scoped records reason13/redirectmetadata0/alloc32/Apply; no scoped reclassify, APPID scope limitation retained. TCPIP1488 bypassed by query return path; not added. Built-in mswsock FastWpp provider ac7ff34d-58da-490c-843e-57baeb1bafef event11/level4/keyword2 writes original NTSTATUS before same10022, traceGUID97dcf1eb-61bd-3c9f-e009-df6b3349ea30+4status=20bytes. NewONLY lab wrappers Invoke-KernelTcpContextStatus{Trace,Diagnostic}.ps1 + config/tcp-context-status-diagnostic.wprp; same TCP16 IDs + selected WPP event, bounded32MiB; no hooks/Core/kernel/native-query changes. FINAL fresh candidate tcp-redirect-context-preparation-20261006-172202-6d951b52 source/sys/Core/CLI byte-identical114601; no build/sign/install/traffic. First unrun171215 superseded because validation metadata was changed after freeze; no refreeze/no install/Resume. Final validation sealed BEFORE Prepare; freeze48+7+8 exact. ActualWPR profiles parse0/PS5PreparePS5PS7InspectFILES_VALIDATED0; PS5PS7 fakecapture11/statuspolicy-pathhash14/outerplan7/controllerbinding10 each; matcher21synthetic rejects missing/duplicates/wrongscope/overlap/knownstatus-Wsa contradiction. Old371userSHA/pinned138/base3/old48+4+8 frozen unchanged. Audit tcp-context-retention-review-20261006-121256/{analysis.md,validation.json}; FINAL verification/HANDOFF.md+handoff.json. NEXT USERADMIN new ContextStatusDiagnostic Install -> only success manual reboot -> Run6-12min+traceSave -> wait cleanup/guardedRestore/save/send tcp-context-status-trace root evenerror. Require loss0/rawQPC/providerGUID/traceGUID20bytes/exactPIDTID unique inside original query; no event INCOMPLETE/no reproduction INCONCLUSIVE. No liveNTSTATUS/private-endpoint-lifecycle/rootcause/fix/capacity/PERF proof. NoagentInstallRun/adminloginpasswordreboot/SCMWFPtraffic/HTTP/subagents/oldrefreezeResume/cleanup/commitpush/maintainedautotests. Broaderlab pending.

## RouteMatrix завершена: локализован отказ первого SYN

2026-10-06: пользователь завершил комплект114601-c11a4ded; результаты121256-c8ce657a, трасса121255-9881c0bd. Исходная очередь —96/968ошибок(32при256,64при640); очередь1024 и очередь1024 с паузой до accept —0/968 каждая. Все96отказов: SYNdrop30/SO_PAUSE_ACCEPT→retry1→успешный connect→query10022 до исходящего подключения Core. Проверены2 808полныхмаршрутов и1 404MiB; все2 904kernelвыделения ненулевые/Apply boundary. Внутреннее удержание контекста Windows не видно.

Контроль ожидания действителен: Sleep663.541ms, все4baselineSYNдо паузы, query через663.801–668.577ms после kernel finish без SYNdrop/retry, контекст и данные доступны. В backlog1024 ожидание accept достигает696.963ms без ошибки. Локализован пусковой механизм приёмной очереди/отклонённого SYN; объяснение только500msTTL ожидания противоречит контролям. Переполнение таблицы драйвера, приватная Windows-функция утраты контекста, максимальная ёмкость не доказаны. Исправление обычного продукта не применено.

ETL9.5MiB/166.437s/lostEvents0/lostBuffers0, два полных payload multiset71465TCPIP совпадают, rawQPC10MHz; UTCdrift1.712ms не использован. Остальные8878drops отдельно классифицированы(5933ownedpair-phase/2945непривязаны), не объявлены все фоновыми. Все96retry общей TCP-трассы принадлежат исходным native fail. Saved cleanup/resource/Restore baseline hashStopped-detached проверены; текущая система не опрашивалась. Новые215+прежние156файлов пользователя, pinned138, base3, frozen48+4+8 сохранены SHA.

Аудит: `artifacts/diagnostics/tcp-handshake-review-20261006-121255/analysis.md` и `validation.json`. Предыдущий NEXT Install/Run114601 и tracepending завершены; повтор для различения этих гипотез не нужен. Обычный Core fix/verification — отдельная работа, этим аудитом не выполнялись. Никаких runtime/install/admin/login/reboot/traffic/SCMWFP/HTTP/subagents/refreeze/projectcleanup/commitpush/maintainedautotests. Broaderlab остаётся незавершённой.

- 2026-10-06 USER requested one multi-hypothesis/full-route inspection. New isolated RouteMatrix candidate tcp-redirect-context-preparation-20261006-114601-c11a4ded: one Core/sys/CLI kit, three sealed env cases original / backlog1024 / backlog1024-delay650, each PROXY4/64/256/640/4 ConnectEx32/sameCLIrecovery. One ADMIN Install/manual reboot/Run6–12min+traceSave; kernel wrapper restores only after all cases. Same signed sys1e2acb49/CLI ad83b3aa reused, no kernel build/sign/install/query/traffic. Core actualbuild0/same19exports; only copied relay source changed/inverse exact: listen selector, once650ms BEFOREfirstaccept, ROUTELEG acceptedSocket/nativepeer→upstream tuple/connect/SOCKSstatus/QPC; WSA restored/original singlequery/verdict/pump preserved/no payload. Raw WSA field on successful API may be stale; not an error. Shared inner dispatcher +connections controller changed ONLYoptin RouteMatrix, new helper/module/reporter/wrapper; ordinary defaults unchanged. ActualfakeAPI7selectors/16delaysteps/2leg-Wsa cases; PS5PS7 policy12/dispatch4+childinherit/ASTBOMCRLF/planpathhash7/controllerbinding10 each; synthetic1936legs/7corruptreject +selection8/aggregate8; two saved kernel reevaluations exact (92 vs0 nativefails), 156userSHA/pinned138/baseline3 preserved. ActualPS5Prepare/PS5PS7Inspect FILES_VALIDATED0/RouteMatrix; frozen plans verification/handoff.json. No installation receipt; live selectors/delay owned-no-retry/leg chain/ETW loss-QPC-TCB correlation/cleanup/Restore pending. Full Windows private context retention/internaltablecapacity not observed/proven; control no-repro yields inconclusive, no PASS/error masking. NEXT USERADMIN Invoke-KernelTcpRouteDiagnostic.ps1 NEW114601 -Phase Install -> onlysuccessmanualreboot -> NEWRun6–12min -> wait cleanup/guardedRestore/traceSave/send tcp-handshake-trace root evenerror. New docs/TCP_ROUTE_MATRIX_DIAGNOSTIC.md +verification/HANDOFF/handoff supersede 111807 single delay and intermediate113449; neither refrozen/resumed (old shared frozen hashes now expected refusal). Noagentadminbypass/login/password/reboot/trustBCD/SCMWFPquery/traffic/HTTP/subagents/projectcleanup/commitpush/maintainedautotests. Broaderlab/exactinternalcause pending.

## Backlog1024: нулевые ошибки; готов контроль ожидания до accept

2026-10-06 USER110918-bf24906c / handshake110917-1f81c172 backlog1024: offline exact report/kernel/Core/native968, nativefail0/data484MiB/recovery4sameCLI10212; ETL3.75MiB/SHAabe851ad/50.618s/lost0buffers0/twofullpayloadmultisets exact. RawQPC10MHz/UTCdrift1.2912ms NOTused. Ownednative→relay34010 all968 SYN/connect/accept unique, drop/retry0, SYN→connect0.0188–0.0808ms, Windowsaccept→Coreacceptmax331.1385ms; observed pendingmax567 notactualAFDcounter/capacity. Remaining84wholePCdrop30/retry EXACT CLI10212→ownedSOCKSfixture8748:54123, allconnect/accept/TCP_CONNECTED+nativeverified; notbackground/notWFPleg. Originalvscontrol92→0supportsCorelistenbacklog role, notinternaldriver-tableoverflow/maintainedproductfix/performance/internalWFPretentioncauseproof. Savedcleanupworkers0/unforced/CLIgraceful/resource5(min4778557440)/baselineRestoreStoppedhashdetached verified/currentglobalfalse.78new+78old/pinned138/baselinecomponents unchanged; originalreports untouched.

New isolated first650msIPv4acceptdelay candidate tcp-redirect-context-preparation-20261006-111807-1b0b134f, backlog1024 preserved; one source declaration+once block afterreadability BEFOREaccept (neverpostacceptbeforequery), WSApreserved/originalquery/verdict/pump unchanged. ActualCorebuild0/19exports, sysCLI identical073447/no kernelbuildsigninstall. NewONLYlabwrapper Invoke-KernelTcpAcceptDelayDiagnostic.ps1; fakeSleepWSA8iterations/PS5PS7policydispatch11+plangates7each/ASTBOMCRLF; actualPS5PreparePS5PS7InspectFILES_VALIDATED0,45runtime+4trace+6delayfreezeSHAverification/handoff.json. NEXT USERADMIN newDelaywrapperInstall→onlysuccessmanualreboot→Run2–4min+cleanup/guardedRestore/save/sendtcp-handshake-trace root evenerror. Offline requirebaselinefirstflow rawQPCwait>=600ms AND noSYNdrop/retry beforeinterpretation; zeroerrorsalone insufficient. Separatehypotheses refusedSYN/retryloss vs~500mscontextexpirybeforeaccept; exactWindowsinternalcause stillpending. Noagentadminbypass/login/password/reboot/trustBCD/SCMWFPquery/traffic/HTTP/subagents/oldrefreezeResume/projectcleanup/commitpush/maintainedautotests. NewverificationHANDOFF/handoff+audit tcp-handshake-review-20261006-110917 analysis/validation supersedeolderNEXT; broaderlabpending.


## SYNdrop/SO_PAUSE_ACCEPT: готов контрольный backlog опыт

2026-10-06: USER071743-70b51502 / handshake071742-922c0824: офлайн проверены 968 уникальных цепочек, 92 API10022 (28@256+64@640), 876 успешных/438MiB. Все 92: SYN → INET drop30 (PktMon1229/VMAP→message0xd0000121, SO_PAUSE_ACCEPT) → retry1 → connect за501–507ms → Core accept/query10022; успешные без drop/retry. ETL3.5MiB/lost0buffers0, два декодера payload multiset exact; rawQPC10MHz, UTC drift6.795ms не использован. Сопоставление PID/tuple/phase/TCB-life без nearest/orderfallback. Локальные PE/PDB GUID+DBIage, VMAP/message и AFD pause/unpause статически проверены; наблюдение199–202 ожидающих приёма согласуется с очередью200, фактические счётчики AFD не прочитаны. Место утраты WFPctx/переполнение внутренней таблицы/rootcause не доказаны. Saved cleanup/resource/Restore baseline hashStopped-detached проверены; не currentglobal.

Новый изолированный backlog Core tcp-redirect-context-preparation-20261006-073447-5ad2210d: один source/two listen args SOMAXCONN_HINT(1024), inverse patch exact, actual short Core build0/19exports; CLI/sys identical070917, kernel не build/sign/install. CoreSHA b352040ceebf21a9a9601654d93ee0c89bc8db8bfa6631e7508494d81bef894e; bundle30ecd620f2e353867e812d4c33b4f47707297d7274db92fb9130390a671b965a. Новый ONLY lab wrapper Invoke-KernelTcpBacklogDiagnostic.ps1; существующие controllers/helpers/Corequery/kernel/source baseline unchanged. FakeSDK4calls, PS5PS7 policy/dispatch11+plan/path/hash7each; actualPS5Prepare/PS5PS7InspectFILES_VALIDATED0; frozen runtime/trace/backlog hashes в verification/handoff.json. Original78/pinned138/baselinecomponents unchanged. NEXT USERADMIN new Backlog wrapper Install → onlysuccessmanualreboot → Run2–4min+waitcleanup/guardedRestore/traceSave/sendtcp-handshake-trace root evenerror. Noagentadminbypass/login/password/reboot/trustBCD/SCMWFPquery/traffic/HTTP/subagents/oldrefreezeResume/projectcleanup/commitpush/maintainedautotests. Exact analysis artifacts/diagnostics/tcp-handshake-review-20261006-071742/analysis.md +validation.json; new verification/HANDOFF supersedes olderNEXT. Runtime/rootcause/broaderlab pending.


##500мс доaccept; готов целевой TCPsetup ETW опыт (2026-10-06)

Current2026-10-06 USER063333-1ddf373d CORRELATED968kernel/Core/timing96API10022fail32@25664@640/872verified436MiB/recovery4sameCLIclean. Actualreadonlyevalexact70SHA unchanged; allocNULL0/overwritten0/queryentryafterfinishall. Delay500.229–547.508ms BEFOREaccept-return; accept→querymax0.0012ms/APImax0.0112ms. Rootcausepending: handshake/retry/acceptredirect vsestablishedacceptqueue, nottablecapacity/driverfixproof. Savedresources5pass/CLIgraceful/helpercollector sampler0/unforced/baselineRestoreStoppedhashdetached verified, no currentglobalclaim. New ONLY2labfiles optionalInvoke-KernelTcpSetupDiagnostic.ps1+config/tcp-setup-diagnostic.wprp;12exactTCPIPeventIDs/raw32MiB/no packetpayloadprovider; localmanifestmetadata read/no traces/SCMWFPqueries/traffic. ActualWPRprofilesparse0/PS5PS7fakecapture11+frozengates7each/ASTBOMCRLF. Freshsamebinarykit tcp-redirect-context-preparation-20261006-064810-ab610cd3 no buildsigninstall; PS5PreparePS5PS7InspectFILE_VALIDATED0/inner45SHA cbe8b0f74efc534791dc4627f5717fb98f72fcd52028bff0f1ffa3a292f690ce/outer4SHA 77979186ea4dbdf71997d35cd0905f1b1e0601c0a4eecd497e9dd988d6a2ebf0;noinstallationreceipt/ETWemissionlostclockownedmatchingpending. NEXTUSERADMIN NEWwrapperInstall→onlysuccessmanualreboot→NEWwrapperRun2–4min+save/waitguardedRestore+owntraceStop/sendtcp-setup-trace root evenerror. Noagentadminbypass/login/auto reboot/trustBCD/refreezeold/HTTP/subagents/projectcleanup/commitpush/maintainedautotests; user70 preserved/rootcausebroaderlabpending. Exactnewverification/HANDOFF+handoff.json and audit tcp-kernel-timing-review-20261006-063333 supersede priorNEXT.

Подробности: C:\src\ProxyBridge-TestLab\artifacts\diagnostics\tcp-redirect-context-preparation-20261006-064810-ab610cd3\verification\HANDOFF.md.

## Timing запуск не начался: RAM ниже2GiB (2026-10-06)

Current2026-10-06 USER062252-ff2c356c timing RUN FAILED baselineRESOURCE_BOUND BEFOREnativeclient/receiver; exactCIMfree1321500672<2147483648/disk56009334784passes; preinstallfree3303346176/causeofdroppending/notproductcause. Kernelrecords0/querytiming0; CLIgracefulpoststop/helpercollector sampler0/unforced/capture/scopedsavedRestorebaselinehashStopped-detached verified. OriginalFAILED/INCOMPLETE31SHA unchanged, no10022timing/rootcauseevidence. Fresh identicalbinaryreuse tcp-redirect-context-preparation-20261006-062504-d4ca8a79: sysCoreCLISHA identical055507/no buildsigninstallqueriestraffic; copiedbuildreceipt+validation byteidentical/historypathsretained/newenvpaths/noinstallationcopy. PS5PreparePS5PS7Inspect FILES_VALIDATED0/45freeze/runtimePlan da469001f3a1b85a4102a071c95a7bbc3b6a8f17d4d9cfcada5e063e1c84dbff. NEXT USERfreeRAM>=2GiBAFTERreboot/3–4GiBheadroom→newADMINInstall→onlysuccessUSERreboot→newRun2–4min/waitguardedRestore/sendroot evenerror. Old055507installationRESTORED/noDelete-refreeze-Resume. NoagentSCMWFPqueries/traffic/install/login/subagents/HTTP/reboot/projectcleanup/commitpush/maintainedautotests; exactcause/broaderlabpending. Newverification/HANDOFF.md+handoff.json/audit tcp-kernel-timing-resource-review-20261006-062252 supersedes olderNEXT.

Подробности: C:\src\ProxyBridge-TestLab\artifacts\diagnostics\tcp-redirect-context-preparation-20261006-062504-d4ca8a79\verification\HANDOFF.md.

## Timing Core готов; требуется новый runtime опыт (2026-10-06)

Current2026-10-06 USERcontinue exactcause: fresh timing candidate tcp-redirect-context-preparation-20261006-055507-015f5510 PREPARED_STATIC_CHECKS_PASSED_RUNTIME_PENDING. NewCore actualbuild0/4.1s/x64/19sameexports; signedkernel1e2acb49 byteidentical185952/signatureValid/norebuildsigninstall. accept-return TLS/APIentry/APIexit QPC/originalsinglequery/WSA preserved/log onlyafterquery. ActualfakeAPI8/PS5PS7policyconfigASTBOMCRLF36each;3syntheticdelaystages968/88failsretained19corruptreject/oldv4projectionexact. Original138/base9/user70SHA unchanged. PS5PreparePS5PS7Inspect FILES_VALIDATED/0/45freeze/runtimePlan 2b5b755512669496c9b3c3834c9c8307f121d10da7b93541424b0238733af72d;noinstallationreceipt/runtimepending. Earlier USER053859 strictly968matches/88API10022 notNULLalloc, delay505–542ms atPOSTAPI; truecausepending. NEXT USERADMIN newInstall→onlysuccess USERreboot→Run2–4min/waitguardedRestore/sendroot evenerror. Agentnonadmin/noSCMWFPquery/traffic/install/login; nonewpermission/bypass/trustBCD/auto reboot/refreezeold/productfix/PERFclaim/subagents/HTTP/projectcleanup/commitpush/maintainedautotests. Exactnew verification/HANDOFF.md+handoff.json supersedes timingPLANONLY; broaderlabpending.

Подробности: C:\src\ProxyBridge-TestLab\artifacts\diagnostics\tcp-redirect-context-preparation-20261006-055507-015f5510\verification\HANDOFF.md.

## Kernel metadata сопоставлены;88отказов сохранены (2026-10-06)

Current2026-10-06 USER053859-26ab0cd4: v4 completed5cohorts/968queries968kernel/88nativefails24@256+64@640/880data440MiB/sameCLI12684 recovery4clean. OriginalFAILED/INCOMPLETE preserved70SHA. Labv4 matching assumedkernelboundIP; actualall968localV4=0/nonzeroports; strictoptin ownednativeCSV wildcardbinding/PIDphaseoriginal+rewrittentupleQPC/noorderfallback now968unique. Allocationallpresent32/AcquireWritable0/Applyboundaryall/noNULL/drop, doesnotproveWindowscommit/retention/rootcause. Onlyv4reporterchanged/PythonAST/16matchingchecks+25fullsyntheticnegative/96failsretained/58oldSHA/original138base9unchanged; noCorekernel/helper/controller/build/install/traffic. SavedRestorebaselineStoppedhashdetached/collectorhelper sampler0/unforced/resourcefloorpassed min5372026880bytes; no currentglobalclaim. Querycompletion-kernelend failed505.575–542.328ms/success0.157–69.147ms; timestampPOSTAPI, entry/acceptnotobserved/noSYNretryAPIwaitclaim. NEXT source-only timingprobe plan docs/TCP_REDIRECT_CONTEXT_TIMING_PROBES.md (acceptreturn/APIentry/APIexit afterqueryonlylog/originalverdict) notimplementedbuilt/prepared/nocommand; nooldrepeat/refreeze/Resume053310 (reportSHAchanged). Audit tcp-kernel-context-review-20261006-053859/{analysis,validation,readonly-evaluation,apply-query-timing}. No subagents/HTTP/SCMWFPqueries/reboot/cleanup/commitpush/maintainedautotests.

Подробный анализ: C:\src\ProxyBridge-TestLab\artifacts\diagnostics\tcp-kernel-context-review-20261006-053859\analysis.md.

## Первый kernel опыт остановлен по ресурсам; новый комплект готов (2026-10-06)

Current2026-10-06 USER052735-313c10ce: kernel v4 FAILED baselineRESOURCE_BOUND before nativeclient/receiver; sampleravail1128402944–1268772864<2GiB/exactCIMdiskmissing. Collector0STOPtrue0records/CLIgracefulpoststop/helper sampler0/unforced; savedRestorebaselinefilehash Stopped/detached verified; no currentglobalclaim/rootcause. Only2labsourcesmodified: ConnectionLoad resource-observation beforeexistingfloorrefusal +Installer resourcepreflight beforeSCMmutation/same2GiB256MiB thresholds. ActualPS5PS7 11fakechecks each/norealqueries, ASTBOMpassed. New signedbinaryreusekit tcp-redirect-context-preparation-20261006-053310-e548deac: sysCoreCLIsameSHA/no rebuildsigninstall; actualPS5PreparePS5PS7InspectFILES_VALIDATED/0/42freezeSHA/runtimePlan8282fc884ee6cf06a564694c0a4350e486987e734ff38261c6f8f4f6ae486fbe;old30userSHA+oldplanunchanged/old2sourceSHA mismatch expected/noResume-refreezeold. NEXT USERfreeRAM>=2GiBwithheadroom→ADMINnewInstall→onlysuccessUSERreboot→Run2–4min/guardedRestore/sendnewroot evenerror. NewverificationHANDOFF+handoff/binaryreuse, audit tcp-kernel-resource-review-20261006-052735/validation.json. Userpassword notsaved/noauthattempt; lockoutcauseunknown. NoagenttrafficSCMWFPquery/install/subagents/HTTP/reboot/cleanup/commitpush/maintainedautotests; fullkernelcorrelationstillpending.

Подробности: C:\src\ProxyBridge-TestLab\artifacts\diagnostics\tcp-redirect-context-preparation-20261006-053310-e548deac\verification\HANDOFF.md. Предыдущие pending/completion entries исторические; kernelrootcause/capacity/performance не установлены.

## Интеграция завершена: новый kernel опыт ожидает администратора (2026-10-06)

После USER «Можешь продолжить?» закончены проверки kernel/Core диагностики v4. Кандидат tcp-redirect-context-preparation-20261005-185952-9c036895 уже собран/подписан существующим сертификатом; теперь callback/collectorSTOP-beforeCLIstop, installer/restore/refusals, sourcebinding/report и PS5/PS7 UTCboot gates проверены. Validation PREPARED_STATIC_CHECKS_PASSED_RUNTIME_PENDING. Actualfiles-only PreparePS5 + InspectPS5/7 FILES_VALIDATED/exit0;42frozenfileSHA verified/runtime-planSHA 02f7a82cb161c382e696771a6e7f0505473ce7ee8bc65b29459b69ee055a3a4c. PS5+7 each: callback3, registration32, candidate11, UTC4, dispatch2. Actualcollectorloop fakeWinDLL5, fullsynthetic968matches/96originalfailures retained/25corruptnegatives. No realdevice/SCM/WFP probes. ActualInstall in nonadmin terminal refused at administratorguard before runtimeimports/queries;installationreceipt absent. Original138/base9/latest62 unchanged, old12default reports/543SHA preserved. Kernelrootcause pending; noproductfix/capacity/PERFclaim.

NEXT USERADMIN Invoke-KernelContextDiagnostic.ps1 with thisroot -Phase Install → USERreboot → same -Phase Run (~2–4min), oneConnectEx32/4→64→256→640→4/recovery sameCLI, kernel metadata uniquely matched toCore/native. Run finally attempts guardedbaselineRestore aftercleanup; guardrefusal remainsrefusal, sendresultroot evenerror. No newpermission needed, noautomaticreboot/trustBCD/guardbypass/oldplanrefreeze/repeat. Details candidate/verification/HANDOFF.md +handoff.json; previousHANDOFF saved asHANDOFF-before-integration.md. Thisentry supersedes integrationpending/permissionpending below. Broader laboratory/customGitHubbuild support stillpending. Noagents/HTTP/cleanup/commitpush/maintainedautotests.

## Диагностический kernel кандидат собран; интеграция сохранена перед лимитом (2026-10-06)

USER разрешил kernel этап «Хорошо, приступай» после обсуждения отдельной сборки/подписи/временной установки; прежнее permission-pending ниже историческое. Затем USER «Лимит заканчивается»: сохранена текущая точка, не запускать непроверенную установку. Candidate artifacts/diagnostics/tcp-redirect-context-preparation-20261005-185952-9c036895: isolated Core/sys build7.8s, same existing cert4544323109A45FC4761819E079BBDBD5E0BFE8D6, signtool verify0/AuthenticodeValid/no trust-BCD-timestamp changes/no install/load/traffic/SCM-WFP query. Sys1e2acb496aa4caf703408f0b96ceae04b416a56616fa165270c619f4b404b103. Original138+baseline9 unchanged, copied138 verified/two original files patched(Core query logger+kernel Classify/readonly IOCTL)/2headers. Actual extracted Classify fake256 functional/API/action/req/context cases equal/PAGE_NOACCESS afterApply; ring6checks/152record56header/8192 resident nonpaged1,245,184bytes; Core19sameexports/x64. ABI8negative/correlation8checks/old12reports exact543SHA/latest62unchanged; PS5+7 ASTBOM4/PythonAST4. New collector/start-before-cohorts/drain-before-CLIstop/report/sourcefreeze/install-reboot-run-restore draft; **integration not verified, validation status CANDIDATE_BUILT_SIGNED_INTEGRATION_PENDING intentionally blocks Install**. NEXT agent actual closure scope/STOP ordering fakePS5+7 + installer/restore negative stub paths + full syntheticreport/freezebinding then files-onlyPrepareInspect/freeze; only after checks pass adminuser Install→reboot→Run(~2–4min) guardedrestore. No new permission for already authorized stage; no auto reboot/trust/BCD/bypass. Do not rerun oldmatrix/v3/refreezeold evidence. Rootcause pending/no productfix/no performanceclaim. Detailed exacthandoff verification/HANDOFF.md, validation.json, check-candidate.py/check-ast.ps1; no subagents/commitpush/cleanup/HTTP/maintainedautotests.
## Разобраны112contextfail и32connectfail; kernelэтап требуетразрешения (2026-10-05)

USER183525-74582558v3: originalwrapperFAILED/CAPTURE_INCOMPLETE, workloadCOMPLETED/recovery4sameCLIclean.936acceptedqueries/824GUIDdataverified412MiB/112originalcontext10022zero, immediate3followups10022zero;336late10022zero(actual5→7.88–16.50ms/25→28.63–39.77/100→102.60–111.42),448type+endpointsallstreamunchanged/10positiveRECORDS780bytes. Native968attempts/144fail=112context+32initialCSV10061blanklocal/remote/GUID zeroBytes/TimeMs0. Источник10061неустановлен; acceptdelaypressurehypothesisnotproven. Originalreportmistook32blankrowsforduplicates. Opt-in v3 reportclassificationonly nowexplicitUNIDENTIFIED_NATIVE_CONNECT_FAILURE_10061:32/INCOMPLETE retained; old12defaultreevalsexact543SHAunchanged,62newUSERfiles unchanged/138sources9baselineunchanged/6negativeCSVvariantsreject/PythonASTpassed. No original reportrewrite/falsePASS/no Core/kernel/helper/controller modifications/build/runtimequeries. 8nativeexit0/clients20,124/allcaptureunforced/notimeout;helper+sampler0/CLIgracefulpoststop/noerror;2diagnosticguardhandledreset; scopedcleanup savedonly/currentglobalfalse.

NEXT no repeat oldmatrix/v3. Prepared concrete source-only kernelobservation plan docs/TCP_REDIRECT_CONTEXT_KERNEL_OBSERVATION.md: allocationNULL vs contextattachment/classify/redirectstate and separate10061, boundedring/drops/PIDtupleQPC/Applyvoid/noactionorownershipchanges; no candidate sourcepatch/build/sign/install yet. Kernelbuild/sign/install remainsnotauthorized, requiresexplicitUSERpermission forrealnextstep. v3 frozenplan nowexpectedSHArefusal due3reporters changed; do NOT rebase/refreeze/Resume or blindrepeat. Audit artifacts/diagnostics/tcp-redirect-context-probes-review-20261005-183525/{analysis.md,validation.json,revised-readonly-report.json,review.py}. Noagenttraffic/SCM-WFPquery/install/HTTPUI/subagents/reboot/cleanup/commitpush/maintainedautotests. Rootcause/internaltable/capacity/productfix/broaderreadinesspending. GPT6.1Sol/high.

## Подготовлены три наблюдения в одном опыте; runtime pending (2026-10-05)

USER разрешил несколько гипотез. Отдельный Core `redirect-context-probes-v3`: positive RECORDS successful IPv4 seq1–4/stride128/cap16; original API failures сохраняют immediate3followups, затем context1024 при5/25/100ms от original end/cap1000sockets; SO_TYPE+local/peer до/после, без SO_ERROR/данных. Original BOOL/ctx/WSA/native failure сохранены. Одно ConnectEx32,4/64/256/640/4; delays change accept timing, no speed/fix/capacity claim. Ordinary paths/Core/CLI/sys baseline unchanged. Diagnostic-only existing Proactor guard reused, strict case/policy/receipt/freeze/report gates; old case evaluator defaults exact.

16 fake API/clock/socket cases compared actual extracted upstream query; synthetic96late-owned successes retain96nativefailed,10bad variants rejected;12saved reevaluations exact/543 files SHAunchanged/138sources9baseline unchanged. Short Core buildexit0/x64/same19exports; PS5+7 ASTBOM,12policy cases each, extracted actual wrapper dispatch success/failure/freshworkload passed. Initialsource/build182422-8660d704 plan kept; currentfreshkit tcp-redirect-context-preparation-20261005-183038-7c035e66 contains copiedbyteidentical Core andnew37filefreeze, PS5Prepare+PS7InspectFILES_VALIDATED/runtimefalse. Receipt verification/validation.json. One-off audit harness correction: synthetic rows sorted byseq insteadCSVorder; unusedPSmatrix_cases null treatedempty; no productfailure fromtheseauditasserts. No agent producttraffic/SCM-WFPquery/kernelbuildsigninstall/HTTPUI/subagent/reboot/cleanup/commitpush/maintainedautotests.

NEXTUSER ADMIN `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-TcpRedirectContextDiagnostic.ps1" -DiagnosticDirectory "C:\src\ProxyBridge-TestLab\artifacts\diagnostics\tcp-redirect-context-preparation-20261005-183038-7c035e66" -Phase Run` (~2–5min), waitcleanup/sendroot evenerror. No new runtime/rootcause proof yet. Sources frozen; do not edit/refreeze this plan, blind-repeat oldmatrix or selectdiagnostic kit inGUI. See docs/TCP_REDIRECT_CONTEXT_NEXT_PROBES.md. Kernel telemetry permission remains absent; broaderlab readiness pending.

## Полная матрица подтверждена, ошибки driver сохраняются (2026-10-05)

USER root175848-a3cb97a9 все4cases CORRELATED/errors[] иparentCOMPLETED/METADATA_CORRELATED. ConnectEx32:224/256,576/640,96fail; ConnectEx1:256/256,639/640,1fail; connect32:255/256,626/640,15fail; connect1:256/256,639/640,1fail. Всеbaseline4/load64/recovery4 полные, recovery sameCLI внутриcase. Total3872originalqueries/3759data-GUIDverifiedsuccess1879.5MiB/113nativefail beforedata. Все113 originalcontext+RECORDS1024/NULL0size/context1024 followups rc-1/immediate10022/bytes0; всеsuccess full32IPv4TCP/PIDmatched. Pending32 association stronger, butfixedorder1matrixnotcausalproof; notConnectEx-only andserialnotfix, nointernaloccupancy/kernelallocation/capacity proof. IncompleteHIGHowned snapshots не превращать в concurrentcount.

Независимые5pureevaluations exact/238USERfilesSHAunchanged/33freeze matched/138originalsources9baselineunchanged.40native captured/unforced/no timeout:34exit0 +32/64/1/14/1/1.4CLIready/graceful/poststop/unforced/capture/noerror (проекциябезexitcode),4helpers+samplersnatural0/capture/STDINSTOP+STOPPED/noERROR/nocallback. DiagnosticProactorguard runtimefullmatrix подтверждён; handledresets0/2/0/1, обычныйdefaultHIGHнепроверенсэтимguard. StartupPIDошибка здесьнеповторилась, первоначальнаяточнаяпричинанеустановлена/no rootfixclaim. Сохранённыйscopedidle/driverfingerprintpassed, не current/global state.

NEXT не повторять эту же матрицу. Source-only конкретныйплан docs/TCP_REDIRECT_CONTEXT_NEXT_PROBES.md: boundedpositiveRECORDScontrols successfulsockets +5/25/100ms delayedcontext probes failedsockets, originalverdict/WSActx preserved/no retry-PASS/newsourcekit; оба в одномdiagnosticcase, observereffect/holdaccept acknowledged/noPERF pooling. ПокаPLAN ONLY/notimplemented/built/runtime/no newcommand. СначалаfakeAPI-clockharness/sourceoldreeval checks, отдельнаяCorebuild<5min разрешенаUSER, kernelbuild/sign/install НЕ разрешены. Kernelclassify/ctxallocation-assignmenttelemetry еслиuser-modeнедостаточно остаётсяfuture. Истиннаяпричинаиbroaderlab readiness pending, не объявлятьprojectготовым. HTTPUI/producttraffic/SCM-WFPqueries/buildinstall/reboot/cleanup/commitpush/subagents/maintainedautotests агентом не выполнялись; провереныMicrosoftprimarydocs ambiguity10022/records(controlnotyetpositive). Runtime/Core/driver/GUI не менялись в этомturn. Audit artifacts/diagnostics/tcp-redirect-context-matrix-review-20261005-175848/{analysis.md,validation.json,readonly-evaluation.json,review.py};GPT6.1Sol/high.

## Срыв базовой фазы из-за подтверждения PID получателя (2026-10-05)

USER root174556-766e04c7/caseconnectex32: baseline receiver Start CONSOLE_HOST_IDENTITY_FAILED, client не запускался; старый adapter потерялfirststderr/handleerror/hostexit. Точный runtimeфактор неизвестен, это не доказательство kernelcause. Controller продолжил64/256/640/recovery вопреки baselineINCONCLUSIVE:64/64,224/256,576/640,4/4;964queries/96API10022fail/96followups, overallINCOMPLETE/other3SKIPPED. Agent exactreadonlyreeval/rootcase/59SHAunchanged; freeze33matchbeforechanges. Proactor guard USERruntime observed:2handled resets/noERROR/noCallback/helper6980natural0capture/CLI11412same4recoveryclean; полнаяcase/matrix не подтверждены.

Исправлена потеря startup evidence: ProcessAdapter C# retains originalexception+PB_START_Data identityline/error/hostPID-exit/forcedcleanup-error/capped8KiBstreams/capture; identity5s/noRetry/noWeakening unchanged. ConnectionLoad saves receiver/client-start-failure.json+phase structuredmetadata, infrastructureerror aborts nextcohort; native/data/API failedCSV still retained/recovery path. Reporter newoptionalstartfailure firstreason/aggregatemetadata; oldoutputs exact. UTF8BOMmodule normalized (initialauditassertcaughtmissingexistingBOM, byte-bodyunchangedencodingonly). ActualcompiledPS5+7 benignownprocess invalidline/invalidPID/timeout+boundedcleanup/normalrealhost passed; fakeOSnetworkactualcohort2stage receipts+failfast1cohort passed; reportsyntheticstartmetadata checked/noPASS. ASTBOM/argdefault4variants/dispatchsuccessfailfast/oldv1v2matrixreeval exact305SHAunchanged/newkit byteidentical/files-onlyPS5PreparePS7Inspect/33freeze match. No producttraffic/SCM-WFPprobe/buildinstall/signing/HTTP/reboot/projectcleanup/commitpush/subagents/maintainedautotests byagent.

NEXTUSER ADMIN samewrapper newDiagnosticDirectory `C:\src\ProxyBridge-TestLab\artifacts\diagnostics\tcp-redirect-context-preparation-20261005-175531-06f4e1f5` -Phase Run (~8–16мин all4cases; ifstartfails abortimmediatelywithdetails), waitcleanup/sendroot. Newproductruntime/PIDinitialcause/kernelctxcause pending; no claimPIDfailurefixed or fullmatrixreadiness. Old170714 preparation immutable/frozenmismatch expected/noResume/refreeze. Evidence matrix-review-20261005-174556/{analysis.md,validation.json} and tcp-console-start-failure-check-20261005/{validation,session-cohort-validation}.json. GPT6.1Sol/high.

## Матрица остановилась на ошибке стенда; подготовлена узкая совместимость закрытия (2026-10-05)

USER run164945-d24e6656: ConnectEx32 имеет85отказов (235/256,576/640), ConnectEx1 —1 (256/256,639/640); baseline64/recovery4 полные. Все отказавшие original/followup API-1/immediate10022/bytes0. Первыйcase CORRELATED, второй CAPTURE_INCOMPLETE из-за живого Python Proactor socket.shutdown10054 до STOP; helper всё же natural0, предыдущий afterSTOP cleanup завершил close/detach. Строгая очередь правильно SKIPPED connect32/connect1. SameCLI recovery/cleanCLI/scoped saved detachment, не current/global/capacity/cause/performance proof. Независимая переоценка exact/122USERfilesSHAunchanged. Гипотеза зависимости от burst усилена85→1, но fixedorder+incomplete не доказывают причину.

Matrix-v2 только opt-in DiagnosticFixtureCloseGuard: pinned CPython3.12.14 callback source SHA/AST заменяет только shutdown expression, принимает только reset10054 в closing accepted127.0.0.1:54123 StreamReaderProtocol после connection_lost/_closed.done с excNone; оригинальные socket.close/Server._detach/calledflag остаются. Event PROACTOR_SHUTDOWN_RESET_HANDLED только после завершения; неизвестные callback/protocol/close/detach errors остаются INCOMPLETE. Обычные тесты/defaulthelper без guard, native/data/API-отказы не скрываются, CLI/Core/sys byteidentical, PythonLib/wheel не изменены. Новыйreportcase/rootv2/guardmetadata+frozenSHA, старыеv1/v2 outputs exact. Прежние планы не перезаписывать/не Resume.

Одноразовый actualCPython fake-socket harness воспроизвёл oldreset и подтвердил close/detach/notify ровноодинраз/normalclose/8negative/source-runtime rejects/installrestore; без сети. PS5+7 ASTBOM/actualextracteddefault+4args/non-diagreject/dispatch4success+fail2skip2, savedcase+badlive/forcedsampler, v2syntheticguard8negative/old85fails retained. Oldsingle+matrix pureeval exact/246sourceSHAunchanged. Files-only PS5Prepare/PS7Inspect прошли;33frozenfiles, freshkit C:\src\ProxyBridge-TestLab\artifacts\diagnostics\tcp-redirect-context-preparation-20261005-170714-a2826a1f. Полный fixedproduct runtime PENDING USERADMIN: однакоманда wrapper -DiagnosticDirectory "C:\src\ProxyBridge-TestLab\artifacts\diagnostics\tcp-redirect-context-preparation-20261005-170714-a2826a1f" -Phase Run (~8–16мин), дождаться cleanup/сообщитьroot. Нет agent PBtraffic/SCM-WFPquery/buildinstall/signing/HTTP/subagents/reboot/cleanup/commitpush/autotests. Истинная kernelctx причина и broaderlab pending. Audits matrix-review-20261005-164945 и matrix-close-guard-check-20261005; GPT6.1Sol/high.

## Один запуск для нескольких гипотез подготовлен (2026-10-05)

USER уточнил: несколько гипотез причины, не сборок. Новый matrix-v1 автоматическипоследовательно ConnectEx32/ConnectEx1/connect32/connect1 pendingattempts; каждыйPROXY4/64/256/640/4 с прежнимиdata/rate/verify/rude, sameCLIrecovery внутриcase/newCLIafterconfirmedcleanupмеждуcase. Одинwrapper общийadmin/mutex/filelease/crossboot/frozen guard на4cases, controller gates+resourcebounds unchanged. NativeAPI/data failures withcompletecapture retained/continue; controllercleanup/capture failure abortsnext/SKIPPED. Новаяordinaryopt-in защита, normaldefaultargs32/no-conn/evaluator unchanged; extendedreport keyworddefaults preserveoldv2; strictmatrixcase live/plannedargs/enginewheel/nativesampler/scopedinventory/phase checks; aggregate noPASS/capacity/kernelcause/PERF claim.

Freshkit161454-c5595e9d копирует byteidentical CLI/Core/sys+receipt из153256 (безbuild/install/registrationchange), env paths rebound,31files freezeConnectionMatrix. PS5+7ASTBOM+PythonAST; actualextractedargumentboundarydefault+4cases/non-diagreject, actualdispatchstubsuccess/fail2skip2freshchildren/originalerror;4saveddata-casechecks+4badlive+4forcedsamplerreject; failedparentINCOMPLETE. Oldv1+v2pureeval exact124userfilesSHAunchanged/oldkitunchanged/138sources9baselineverified; realfiles-onlyPS5Prepare+PS7Inspect passed. Fullnewruntime pendingUSERADMIN, noagentPBtraffic/SCM-WFPquery/buildinstall/signing/HTTP/subagents/reboot/cleanup/commitpush/autotests. Failuregroups onlyhypothesis; positiveRECORDScontrol/kernelalloc-assignment notadded. Kernelbuildinstall stillnotauthorized/broaderlabpending.

NEXTUSER однаadminкоманда Invoke-TcpRedirectContextDiagnostic.ps1 -DiagnosticDirectory C:\src\ProxyBridge-TestLab\artifacts\diagnostics\tcp-redirect-context-preparation-20261005-161454-c5595e9d -Phase Run, примерно8–16min/waitcleanup/sendrootevenerror. Неoldsingle/newfirstfreeze161112afterreportgateupdate. Новаяперезагрузкаsolelyforpreparationне нужна unlessruntimeguard. FinalplanSHA 6b5d018b80ad32c2f1be0e833f26988661822121423ed8ff86bacd5574d4c74f. Docs TCP_REDIRECT_CONTEXT_MATRIX.md; audit matrix-preparation-check-20261005/validation.json+boundary/inspect/synthetic logs. GPT6.1Sol/high.

## Пользовательский follow-up разобран (2026-10-05, 20:44–20:45 UTC+5)

Run tcp-redirect-context-run-20261005-154424-b81911e1/workload, версия driver: 4/4,64/64,224/256,576/640,recovery4/4. Из968 original queries —872successful/436MiB и96 nativefail32+64 безpayload. Все96 original API failures и их3followup queries RECORDS1024/contextNULL0/context1024 вернули -1/immediate10022/bytes0. Большойбуфер не помог вэтойсерии; recordsblob/requiredlength не получены. Decodedzeros означают no decode, неreturnedнулевойконтекст. RecordsIOCTL наsuccess отдельно ненаблюдался. Это неctxabsence/kernelallocation/tableoverflow proof, metadataCORRELATED неproductPASS/неperformance.

SameCLI3932 восстановил4/4, ready/graceful/poststop/capture/unforced/primarycleanupempty; separateCLIexitcode не записан. Helper+sampler natural0/STOPPEDSTDINSTOP/no callbackERROR. Native10unforced/fullcapture/8exit0+client32+64; неполныеreceiver2controlledstop. SavedbeforeafterWFPStopped/baselinepathfileverified/scoped-detached/compatibleWinD0/knownloadedabsent, неglobal/current. Load256/640 owned snapshots incomplete:224/576 —successful transfers, неprovenconcurrent. Independentpurev2evalexact62sourceSHAunchanged/30freeze/currenthashmatch/138sources9baselineunchanged.

Failureseq: load256293–324(32); load640555–586(32),771–794(24),862–869(8), естьsuccessbetween/after. Это relay queryorder, неkernelclassifyorder/occupancy. Сохранённыйnative launch содержит throttle32 pendingattempts, отдельно отconncount; назначение сверено сpinnedMicrosoftCTS source. Causality пачек покаhypothesis. NEXT source-only проектdistinctdiagnostic pendingattempt1 вместо32 припрежнихlevel/data/verdict/gates; PLAN ONLY/notimplemented/nocommand. Успехвновыхусловиях неfix/capacity/PERFclaim. Приотказах нужныcorrelated kernelclassify/allocation/contextassignment observations; kernelbuild/install/signing сейчаснеразрешены. Не повторятьтужеHIGHкоманду безновыхнаблюдений.

Audit artifacts/diagnostics/tcp-redirect-context-followup-review-20261005-154424/{analysis.md,validation.json,readonly-evaluation.json,review.py}. Agent saveddata/source/primarydocs only/noPBtraffic/SCM-WFPquery/buildinstall/HTTP/subagents/reboot/cleanup/commitpush/autotests. Source/runtimeproduct unchanged. Fullrootcause/broaderlab/customGitHub pending; GPT6.1Sol/high. Нижние nextsteps — история, этотcheckpoint актуальнее.

## Подготовлен и собран отдельный follow-up Core (2026-10-05)

USERcontinue: fresh tcp-redirect-context-preparation-20261005-153256-3e209b42/kit methodredirect-context-followup-v2. OriginalAPI success: onlyoriginalquery. After originalSOCKET_ERROR: records1024, contextNULL0size, context1024 metadataonly/3queries; suppliedoriginalctx untouched/originalFALSE+WSA restored evenwide success, no retryfix/PASS/bloblog/unboundedallocation. New preparer reusespinned archive/baseline, onlycopyProxyBridgeDrv_user.c; Build optionalExtendedQueries+Prepare/Build sourcespendinghash validation, v2 auto freezeswrapper afterbuild. Wrapper+controller method/marker/capacity/queries/originalverdict contract gates; v1default savedreport outputs equal. New extendedreport seq/socket/PID match exactoriginalfailedset, missingduplicate/success-seq/wrongsocketINCOMPLETE, buffer-limit distinct from absentctx, latequerysuccessnotprooforiginalbufferissue.

Actualoneoff fakeAPI C harness W4WX compile+run8cases/originalreturnctxWSApreserved/only5failedgetextra; actuallogparser8primary5extra; synthetic96followups/4corruptcases rejected/oldv1evalexact62SHAunchanged. PS5+7ASTBOM/PythonAST passed. ShortCorebuild permittedUSER<5min completed4.366s0/x64/19baselineexports; freeze30files/currenthash+files-onlyInspect PS5+7 passed. Original138sources9baselinefiles+oldv1kitcomponents+62userfiles unchanged. Agent noPBtraffic/SCM-WFPqueries/kernelbuildinstall/signing/HTTP/subagents/reboot/cleanup/commitpush/maintainedautotests. Truekernelcause/fullnewruntime pending. Observereffect /diagnostic-only/no performance.

NEXTUSER ADMIN Invoke-TcpRedirectContextDiagnostic.ps1 -DiagnosticDirectory C:\src\ProxyBridge-TestLab\artifacts\diagnostics\tcp-redirect-context-preparation-20261005-153256-3e209b42 -Phase Run (~2–4min), PROXY4/64/256/640/4, waitcleanup/sendroot evenerror. Newdirectory only, oldv1plan now frozen-file mismatch dueupdated scripts; don't silentlyrebase/reuse/Resume. No upfrontrebootsolelyforCore; existingrecorded4/interrupted/crossboot/admin/sharedlease checks remain. Docs TCP_REDIRECT_CONTEXT_FOLLOWUP.md. Evidence newprep/verification/{validation.json(source-stage),handoff.json(postbuild),query-harness.stdout.log,synthetic-extended-report.json}; GPT6.1Sol/high. Broaderlab tasks pending/customGitHubafterready.

## Подтверждены реальные API_FAILED у diagnostic driver (2026-10-05, 20:16–20:17 UTC+5)

USER tcp-redirect-context-run-20261005-151606-472a07d3/workload metadata CORRELATED/errors[]/968query; baseline4/4,64/64,224/256,576/640,recovery4/4 sameCLI14496.32+64=96 nativefails/sendrecv0: alloriginal WSAIoctl rc-1/immediateWSA10022/bytes0/required32/complete0, не stale-only/short-success/family mismatch.872successfulfull32byteIPv4TCPctx/PIDmatch/receiverGUIDdata436MiB. Load256/640 snapshots incomplete, неclaim224/576concurrent/tableoverflow/capacity/pool exhaustion. LoggingCore diagnostic-only/notperformance/notproductPASS.

Wrapper/directories/registered-baseline-binding+helpernewshutdown full userruntime observed: wrapperCONTROLLER_RETURNED/error'', manifestCOMPLETED, CLIready/graceful/poststop/unforced/primarycleanupempty/ctrlbreak, projectedreceipt no separateCLIexitcode. Helper+sampler natural0capture/STOPPEDSTDINSTOP/no callbackERROR;10nativeprocessescaptured/unforced,8exit0/client256exit32/client640exit64. SavedscopedafterWFPStopped-fileverified-detached/baselinepath/compatibleWinDivert0/knownloadednamesabsent, noglobalcurrentclaim. Independentpureeval exact62sourceSHA unchanged/29frozenfilesmatch/138sources+9baselineunchanged. Agent onlysaveddata+source+MSprimarydocs, no newtraffic/probe/build/install/signing/HTTP/subagents/reboot/cleanup/commitpush/autotests.

NEXT source-only prepare separate diagnostic extension for refusedsockets: metadata redirect RECORDS+bounded context size/buffer; retain originalFALSE/immediateerror/closure/no retry-PASS/payloadlogs, fakeAPI harness before separatekit/freeze/useradminrun. Still PLAN ONLY/notimplemented/built/run; don't issue sameoldcommand/newbenchmark blindly. Kernelctxallocation/assignment cause stillpending, kernelbuildinstallnotauthorized. Originalbaseline/currentdiagnostickit anddata remain intact. Broader GUIfailedpartial/UDPchurn/loaded/custom4remote/packaging remain, labnotfullyready/customGitHubafterready. Receipt artifacts/diagnostics/tcp-redirect-context-review-20261005-151606/{analysis.md,validation.json,readonly-evaluation.json,review.py}; docsTCP_REDIRECT_CONTEXT_DIAGNOSTIC+CONNECTION_STRESS_PLAN. GPT6.1Sol/high.

## Диагностика: привязка к исходному зарегистрированному драйверу (2026-10-05, после 15:03 UTC)

USER tcp-redirect-context-run-20261005-150343-5e1a495b FAILED before helpers/CLI/phases, OFF guard дважды CONNECTION_REQUIRES_CONFIRMED_PRODUCT_OFF. Точный blocker не сохранён; прошлый SCM path наблюдён только13:31 UTC. Статически diagnostic env ожидал скопированныйsys/newpath, служба последним saved snapshot указываетbaselinepath. Исправлен diagnostic-only binding: pinnedreceiptbasekit+sysSHA, observation/runtimeplan driver path baseline; отдельныеCLI/Core остаютсяdiagnostickit/ordinarypaths неизменны. Не менятьSCM/устанавливатьdriver/ослаблятьgates. Controller сохраняетbefore/after observations даже приотказе +diagnostic-driver-binding.json доproductpreparation. Metadatareport DIAGNOSTIC_NOT_STARTED отделяетFAILED безphases/CLI; послеphases/missingCLI остаётсяINCOMPLETE. PS5.1+7.6.5 extractedbinding+12gatecases каждое/negativebase-hash/ordinarypath, ASTBOM/files-onlyInspect прошли. Original7failedfiles+138sources+9baselinefiles unchanged; new29filefreeze changeswrapper/controller/diagnosticreport +addcanonicalbaseline.sys; old/intermediateplans сохраненыverification/registered-driver-binding/. NoagentPBtraffic/SCM-WFPquery/install/build/HTTP/subagents/reboot/cleanup/commitpush. Fullruntime/kernelcause pending. NEXTUSER ADMIN та же Invoke-TcpRedirectContextDiagnostic.ps1 -DiagnosticDirectory C:\src\ProxyBridge-TestLab\artifacts\diagnostics\tcp-redirect-context-preparation-20261005-143026-4b6b5e00 -Phase Run (~2–4мин), freshattempt automatic/waitcleanup/sendroot; приguardfail будутконкретныеснимки. Existingadmin/sharedlease/crossboot/frozen guards сохранить. Receipt verification/registered-driver-binding/validation.json supersedesprevioushandoff/planSHA. GPT6.1Sol/high.

## Исправлен каталог диагностической обёртки (2026-10-05, после 14:47 UTC)

USER `tcp-redirect-context-run-20261005-144744-e769bff9` FAILED `CONNECTION_EVIDENCE_REQUIRES_FRESH_DIRECTORY` до helpers/product: wrapper создал root и передал его контроллеру. Исправлен только wrapper: receipts в parent, fresh workload child создаёт controller; receipt workload_directory=workload. Исходные3 файла failed attempt неизменны. Новый frozen28files план меняет только wrapperSHA, oldplan сохранён verification/fresh-directory-fix/runtime-plan-before-fix.json. PS5.1+7.6.5 extracted-boundary/stubcontroller success+failure (freshchild/parameters/exception+FAILED preserved), ASTBOM и actual files-onlyInspect прошли,10 checks. Controller/Core/CLI/driver/helpers/evaluators прежние; no PBtraffic/probes/build/install/HTTP/subagents/reboot/cleanup/commitpush. Fullruntime pending; прошлый failure не новая причинаWFP/не новая необходимостьreboot. NEXTUSER ADMIN повторить ту же команду `Invoke-TcpRedirectContextDiagnostic.ps1 -DiagnosticDirectory C:\src\ProxyBridge-TestLab\artifacts\diagnostics\tcp-redirect-context-preparation-20261005-143026-4b6b5e00 -Phase Run` (~2–4мин), freshattempt automatic, ждатьcleanup. Metadata outputs вworkload/, wrapperreceipts вparent. Evidence verification/fresh-directory-fix/validation.json. Existingadmin/sharedlease/frozen/crossboot guards не обходить.

## Подготовлен диагностический Core для WFP-контекста (2026-10-05)

По продолжению пользователя подготовлена отдельная копия из закреплённого63be0eb: `artifacts/diagnostics/tcp-redirect-context-preparation-20261005-143026-4b6b5e00/kit`. Только скопированныйProxyBridgeDrv_user.c с querymetadata; аргументы/API/BOOL/length прежние, immediateWSA восстанавливается послеlogging. CLI/driver exactbaseline,138originalsources+9basefiles прежние. BuildCore5.7s/0/x64/19exports;4fakeAPIharness cases доказывают локальное сохранение решения/WSA, не fullruntime equivalence. Actualparser4cases+synthetic968query/86fail/corruptendpoint rejection; PS5+7ASTBOM/PythonSyntax;3oldreevalsexact305sourceSHA unchanged.

Новый wrapper defaultInspect(files-only), frozen28files, runtimeadmin/sharedmutexlease/recorded4crossboot/interruptedguards, затем opt-in existingconnectionscontroller толькоPROXY4→64→256→640→4 SHORT/HIGH. Diagnostic-only manifest и отдельныйmetadatareport; normalbenchmark не принимает этотkit/defaultbenchmarkdata/strict evaluatorunchanged. Полная ядровая причина ещё pending; дополнительноеlogging может изменитьвоспроизводимость/тайминги, измерениянеиспользоватьдляspeed/tablecapacity/PASS. Originalbaselineнеpatched. AgentactualRun refused LAB_RUN_REQUIRES_ADMINISTRATOR доCIM/lease/product; no WFPquery/install/signing/HTTP/subagents/reboot/cleanup/commitpush/maintainedautotests. Shortbuild разрешёнuser<5min.

NEXTUSER ADMIN `Invoke-TcpRedirectContextDiagnostic.ps1 -DiagnosticDirectory C:\src\ProxyBridge-TestLab\artifacts\diagnostics\tcp-redirect-context-preparation-20261005-143026-4b6b5e00 -Phase Run` (~2–4мин), ждатьcleanup/прислатьпапкуevenerror. Не выбиратьdiagnostickit вGUI/неповторятьoriginalHIGHвслепую/неперезагружатьзаранеерадиCore. ОстальноеUI/UDPchurn/loaded/custom4remote/packaging остаётся. [Описание и команда](TCP_REDIRECT_CONTEXT_DIAGNOSTIC.md), receipts verification/validation.json +handoff.json. GPT6.1Sol/high.

## Повтор HIGH: установлена причина зависания стенда (2026-10-05, 13:29 UTC)

Проверен новый USER run `lab-tcp_connections-smoke-20261005-132957-d5b7dc88`: OFF все4/64/256/640/4; PROXY4/64/234/576/4.22+64 ошибок до данных,86 сообщений Core/WFP contextFAIL10022. SameCLI recovery4 прошёл, затем штатная остановка и saved scoped detachment/knownnamesabsent/compatibleWinDivert0. Точная причина запроса WFP остаётся не определена, переполнение внутренней таблицы не доказано.

Полное зависание fixture теперь локализовано по фактическому stderr: CPython3.12.14 Proactor `_call_connection_lost` получает10054 вsocket.shutdown и пропускаетsocket.close/Server._detach. ПослеSTOP в0/1/3с clienttasks0/listeneractive1; существующий boundeddrain не может это исправить. Подготовлена opt-in очистка только этого собственного зарегистрированного транспорта послеSTOP, policyv2. Private CPythonfields, исходный exception handler+stderr+новый ERROR сохраняются: строгий evaluator неизменён, попытка со сбоем не становитсяPASS. Product/Core/driver/pinnedwheel не изменены.

Изолированная реальнаяtransport проверка с явно помеченной инъекцией10054: defaulthang, opt-in natural0/STOPPED/active0/errorretained.640concurrent+4recovery/1932echo/natural0 иpendinghandshake1.063с прошли.200 естественных UDP-reset попыток исключение не воспроизвели. PS5+7ASTBOM/PythonSyntax+новый actualPS5 frozen Inspect(files-only) прошли. LOW и обаHIGH оценки точны,103+101+101SHA неизменны. Fullproduct новогоcleanuppending; без нового PB/WFP probe, установки/HTTP/build/subagents/reboot/cleanup/commitpush.

Следующий шаг — точная диагностика WSAIoctl return/immediateWSA/bytes/family/PID+endpoints и назначенияctx драйвером, а не ещё один слепой HIGH. Отдельная инструментированная версия потребует явного отделения от baseline и измерений; здесь не создавалась. Failed partial GUI projection/UDPchurn/loadedUI/custom4remote/packaging остаются. Подробнее [разбор](../artifacts/diagnostics/tcp-connections-high-failure-20261005-132957/analysis.md), [проверки](../artifacts/diagnostics/tcp-connections-high-failure-20261005-132957/preparation.json). GPT6.1Sol/high.

## Исправлена остановка SOCKS-стенда, добавлена диагностика (2026-10-05)

Изолированная fixture-only проверка воспроизвела слабое место pinned asyncio-socks-server1.3.3 на Python>=3.12: библиотечный _run сначала ожидает srv.wait_closed(), затем применяет shutdown_timeout к client tasks. Одна незавершённая SOCKS handshake задерживает STOP сверх1с; после закрытия нашего клиента helper естественно выходит0. Это доказанный сценарий стенда, а не доказательство точной причины зависания в исходном полном HIGH. [Документация Python](https://docs.python.org/3/library/asyncio-eventloop.html#asyncio.Server.wait_closed) подтверждает ожидание активных соединений.

Добавлены opt-in --bounded-shutdown и --shutdown-diagnostics в pb_controlled_tcp_proxy.py. Только TCPconnections controller включает их и записывает условия proxy_shutdown_policy=bounded-task-drain-after-stop-v1 / proxy_shutdown_diagnostics=task-metadata-after-stop-v1 в config; обе стороны OFF/PROXY одинаковы. Существующий library bounded drain запускается после STOP до ожидания listener close; копирование данных в pinned wheel не меняется. Другие сценарии не включают новые флаги. Снимки после STOP (0/1/3с, до1024tasks×12awaitframes) записывают ожидаемые функции, peer endpoint/closing и listener active_count, без payload/locals dump. Неполные/forced попытки и native data/route/resource/cleanup gates остаются строгими;80 исходных отказов не «исправлены» и не становятся PASS.

Фактические отдельные проверки: unfinished owned client остаётся открыт, но новый helper завершает его и выходит0/STDIN_STOP естественно за1,032с; task+listener metadata подтверждены. С bounded shutdown отдельно640 одновременно/1920verified echo плюс4recovery/12echo,1932total,helper0,1,172с. Это SOCKS fixture, не новый запуск ProxyBridge и не доказательство его ёмкости. PS5.1+7.6.5 AST/UTF8BOM, Python syntax, реальный fresh planned Inspect(files-only) прошли. Старые LOW+HIGH чисто переоценены точно,103+101 исходныхSHA не изменились; старыйFAILEDсохранён. Сохранённые system memory samples HIGH показали минимум2099,445MiB available, memory exhaustion не доказан; kernelpool не измерен.

**Следующий USER шаг:** тот же idle adminUI, толькоTCPconnections «Быстро / Высокая», новаяПодготовка→Run (~3–6мин), дождаться очистки и прислать результат даже если снова NOT_CONFIRMED. Это проверка исправления завершения/новой диагностики; WFP отказы могут повториться. UI restart/rebuild/reboot не нужны для этой sourceправки; старыйплан не использовать. Tool terminal не elevated, агент product run/driver query не выполняет и не обходитguard. На основании нового run отдельно подтвердить либо уточнить fullfixture cleanup; затем направленно исследовать исходныйCore/WFP context failure без правки/пересборки продукта. Static installed provider metadata просмотрены: Winsock/AFD events не дают доказанной точной пары WSAIoctl return/bytes/family, поэтому произвольная ETL трасса и затраты диска ради неё сейчас не добавлены. ПолныйGUI runtime и исправление конкретного fullHIGH hang pending; failedhistorypartialprojection/UDP-churn/loadedUI/custom4remote/packaging остаются.

Receipt: artifacts/diagnostics/tcp-connections-high-failure-20261005-124851/shutdown-preparation.json. Следующая модель GPT6.1Sol/high.

## Высокая нагрузка обнаружила неуспешные соединения (2026-10-05)

USER SHORT/HIGH TCPconnections lab-tcp_connections-smoke-20261005-124851-1085fd04 FAILED: OFF4/64/256/640/4 allverified+owned snapshots; PROXY4/64/240/576/4 successful,16+64 ErrorNotAllDataTransferred beforepayload,receiverGUID/volume matchedsuccessful888flows. CLI80redirect-context queryFAILED/loggedWSA10022 (16/64 byphase), localizedCore/WFPbeforeSOCKSnotexactkernelrootcause/tablelimit. Pinned63be0ebsource query/family/bytechecksverified; recordedWSAcanbestale forfamily/shortbytebranches. SameCLI13960recovery4passed/gracefulpoststop/unforced, savedafterWFPdetached-knownnamesabsent-compatibleWinD0 scopedonly. Separatefixture9384STDINSTOPbutnoSTOPPED forcedexit-1 after15s; sampler0;47UDP_ASSOCIATErejections do notaloneexplainhang: isolated47UDPfixturetest0/STOPPED noPB. Purefailedreeval+101SHAunchanged/originalFAILEDretained. Minimalcontrollererrorappend worker/exit/forced replacesemptyreason, PS5+7AST/BOMpassed; method/Core/driver/helper/evaluator unchanged/newproductruntimepending. NoUIrebuild/HTTP/product/driverprobe/install/subagents/reboot/cleanup/commitpush. NEXT targetedCore/WFP/socket contextandfixturemixedshutdown diagnostics, no blindHIGHrerun/noPASS/no640capacityclaim; failedGUIpartialprojectionstillpending. Receipt artifacts/diagnostics/tcp-connections-high-failure-20261005-124851/{analysis.md,validation.json,readonly-evaluation.json}; GPT6.1Sol/high; WORK_CHECKPOINT.

## Подтверждён TCP-тест «Быстро / Низкая» (2026-10-05, 11:33:10 UTC)

Пользовательский запуск suite-0850c85245184cb9b3516a31d04a1c1d / plan-3d66d949b81544fc82d3cc129ad2b58a / lab-tcp_connections-smoke-20261005-113310-3d66d949 завершился: 2/2 пути, десять фаз, errors=[] / LIMITED_COMPARISON. Для OFF и SOCKS5 подтверждены одновременно 4 → 8 → 32 → 64 → 4 соединения и все передачи: суммарно 224, 112 MiB проверенных данных. Восстановление SOCKS5 прошло с тем же PID CLI без перезапуска продукта.

Повторная чистая оценка сохранённых данных точно совпала с отчётом, 103 исходных SHA не изменились. Wrapper/controller завершились с exit0 и полным capture; workers — natural0, CLI — graceful/poststop/unforced. Сохранённые проверки до/после подтвердили WFP detached, отсутствие известных загруженных interception names и настроенный compatible WinDivert observer с нулём handles. Это наблюдение выбранных ресурсов, не глобальная очистка. Минимальное покрытие CLI samples — 93,752775%. Private RAM CLI: 23,294471 MiB при 64 соединениях, 4,164063 MiB после снижения до четырёх. Одного короткого восстановления недостаточно для исключения утечки; kernel pool и занятость внутренних таблиц не измерялись.

Исправление настройки наблюдателя теперь подтверждено фактическим GUI/product runtime. Старый FAILED сохранён. Только lab.js уточняет RU/EN: время передачи на уровне примерное; снято обещание непрерывности передачи. Числа, методика, controller/evaluator/Core/driver/native не менялись. Node syntax и одноразовая проверка 48 вариантов/57 IDs/RUEN/latestFAILED без fallback прошли. Новая формулировка в браузере доступна после CtrlF5; сборка и перезапуск UI не нужны.

**Следующий шаг:** в том же admin UI выбрать только «Соединения TCP: нагрузка и восстановление», «Быстро / Высокая», новая «Подготовить запуск» → «Запустить проверку» (64 → 256 → 640, примерно 3–6 минут). LOW не повторять; перезагрузка для этой правки не нужна, системные guards остаются обязательными. HIGH product runtime ещё не подтверждён. После него — следующие этапы UDP/churn, loaded RTT GUI, произвольные сборки/4.0.0/remote и упаковка; лаборатория целиком ещё не готова. Агент новых product runs/driver probes/build/install/reboot/cleanup/commit/push не выполнял.

Receipt: artifacts/diagnostics/tcp-connections-low-confirmation-20261005-113310/validation.json. Следующая модель: GPT-6.1 Sol/high.

## Исправлена настройка наблюдателя нового теста (2026-10-05, после запуска11:20:42UTC)

USER suite-47b1fdd8521d497d8b93cb3cb02888a3 / plan-b5489ef971c0426ab43952b029a6504c / lab-tcp_connections-smoke-20261005-112042-b5489ef9 завершилсяFAILED перед первым PROXY cohort: CONNECTION_ACTIVE_INTERCEPTION_NOT_CONFIRMED. WFP serviceRunning/fileverified, selecteddriver1 и CLIready подтверждены в сохранённых данных. Причина TestLab: controller требовал files/capture/zerohandles WinDivert observer, но не добавлял его конфигурацию. Snapshot NOT_CONFIGURED; это не переполнение/отказ продукта под нагрузкой. Proxycohorts отсутствуют, controlled SOCKS flows0.

OFF data/cohorts4/8/32/64/4 прошли data/reciprocalGUID/snapshot/PCcoverage:112успешных соединений/56MiB. Весь OFF не получаетPASS: fixed evaluator обнаруживает2 отсутствующих idleWinDivert observations. CLIgraceful/unforced/poststop, всеworkers exit0/capture; savedWFPStopped/detached/knownloadedabsent; scopedonly, не глобальная проверка.65исходных файлов SHA unchanged.

Исправлены только новый controller и его evaluator: отдельный observationEnvironment с теми же pinned list-only observerkeys, что у трёхрежимного теста; before/active/after используют его, callback явно захватывает его после выхода из scope. OFFfailfast требует observerfiles/capture/zerohandles; проверки не ослаблены. Reporter также требует idle compatibleWinDivert snapshots. Currentfailedrun entry теперьFAILED вместо оставшегосяRUNNING. Core/driver/native/helper/UI unchanged; product.env не изменялся.

PS5.1/7 AST/BOM и actualcallbacksource проверены с явно синтетическими metadata без запуска observer/product; оба файла observer SHA совпали. Fresh реальный frozen-plan Inspect прошёл, runtime/traffic/driver flagsfalse. Receipt artifacts/diagnostics/tcp-connection-observer-fix-20261005-112042/validation.json. Новый fullproductruntime PENDING_USERADMIN. Agent не запускал PB/observer/driverprobe/build/HTTP/install/reboot/cleanup/subagents/commitpush.

Актуальный следующий USER шаг заменяет прежнее требование restartUI ниже: в том же idle приложении от администратора нажать «Подготовить запуск» заново, затем «Запустить проверку» для одного connectionSHORTLOW. Около3–6мин; ждать2/2 иcleanup, прислать результат. ПерезапускUI/CtrlF5/перезагрузка для этой source-only правки не нужны; если existingcrossbootguard потребуетreboot по другой причине, соблюдать его. Failed evidence сохранён/noResume. HIGH только после разбораLOW. GPT6.1Sol/high.

## Текущий шаг: TCP-соединения, нагрузка и восстановление (2026-10-05)

Пользователь подтвердил компактный выбор тестов и историю. SHORT/HIGH «Три режима» suite-3fed8a7de46144b1add40db4e0460838 / plan-cfadc687ddd145babaa6f80074f57176 завершён3/3:3768 проверенных обменов,768 измеренных,0ошибок. Три readonly reevaluations совпали с отчётами;77 файлов не изменились в ходе проверки. Receipt: artifacts/diagnostics/lab-workload-confirmation-20261005-101640/validation.json. Успешную серию не повторять. Aggregate reporter был ошибочно вызван до snapshot; receipt не заявляет readonly aggregate проверку.

Подготовлен четвёртый отдельный тест «Соединения TCP: нагрузка и восстановление». method=tcp-connection-load-v1: OFF затем SOCKS5; baseline4 → три растущих уровня → recovery4. LOW8/32/64, HIGH64/256/640; номинальная передача на уровень8/32/120с при64KiB/с на соединение. Исходный ctsTraffic verify:data/rude, Core/driver исходные. CLI и SOCKS helper не перезапускаются между уровнями и восстановлением. Новый модуль/контроллер/evaluator/frozen plans/очередь/история/актуальная таблица подключены. Отмена между уровнями, текущий уровень и cleanup заканчиваются. Ресурсы проверяются перед уровнем; forced cleanup прекращает нагрузку и не считается успехом. RTT/graceful close/kernel CPU/pool/занятость таблицы/максимальная ёмкость не измеряются.

Для нового теста helper получает opt-in ProactorEventLoop; default Selector прежних тестов сохранён. Реальная проверка только стенда:640 одновременно/1920echo +4recovery/12echo,644 закрытия,exit0/STDIN_STOP. Новый модуль без продукта:8 одновременных native соединений/4MiB verified, matching GUID, receiver/client/sampler exit0 и PC samples. Первые сбои одноразовых проверок сохранены: недренируемая PIPE в масштабном checker, ошибочное требование пустого INFO stderr, пустой массив JSON sampler. Исправлены checker и запись JSON нового модуля через ConvertTo-Json -InputObject; повторы прошли. Это готовность инструментария, не тест ёмкости ProxyBridge.

Проверки: PS5.1/7 AST+BOM/callback после выхода из scope;6 одинаковых preset Python/PS5/PS7;6 реальных Invoke-PlannedBenchmark Inspect без runtime; Node/RUEN/57 IDs/48настроек/latestFAILED без подстановки старогоPASS; UI build2.41с/0errors0warnings. Семь прежних RTT/transfer reevaluations exact,174 SHA originals unchanged. Receipts artifacts/diagnostics/tcp-connection-fixture-preparation-20261005/{saved-review,ui-validation,old-evidence-review}.json. Новый product GUI/HTTP/runtime НЕ подтверждён. Терминал агента nonadmin, guard не обходить. Нет subagents/install/reboot/cleanup/commit/push/maintained autotests.

Следующий обязательный USER шаг: остановить idle UI Ctrl+C, запустить от администратора прежней dotnet run командой, Ctrl+F5. Выбрать только «Соединения TCP: нагрузка и восстановление» → Быстро/Низкая → Подготовить → Запустить. Оценка3–6мин, данные в памяти. Дождаться2/2 путей и очистки; прислать результат/ошибку. Нужен новый план, hashes wrapper/host изменились. Перезагрузка ради этого UI/теста не нужна; требование прежнего crossboot guard обязательно. Другую ProxyBridge рядом вручную не запускать.

Команда: dotnet run --project "C:\src\ProxyBridge-TestLab\ui\ProxyBridge.TestLab.Ui\ProxyBridge.TestLab.Ui.csproj" -- --RepositoryRoot "C:\src\ProxyBridge-TestLab"

После LOW runtime разобрать данные, затем HIGH. До готовности остаются UDP/churn saturation; UDP/loaded RTT в новом UI; произвольные именованные сборки/4.0.0 через проверяемые adapters/lifecycle/reboot; remote controlled receiver; упаковка. Проверка пользовательской GitHub beta — после готовности лаборатории. Весь проект готовым не объявлен. Следующий GPT-6.1 Sol/high. Старые разделы ниже — история этапов.

## Исправлен отказ нового профиля и уплотнён выбор тестов (2026-10-05)

USER suite-7e8c1dadaffb4262bda1b989d2addf7a / plan-a9878221a6e44d6ba32fdd0600027a48 / lab-tcp_rtt_three_modes-smoke-20261005-085627-a9878221 FAILED при первом OFF до генератора/ProxyBridge, traffic_generated=false. Proxy helper exit2: watchdog must be10..600seconds, хотя контроллер передал720. Receiver exit0/unforced; остановка признана неуспешной из-за exit2 helper, критерии не ослаблялись. Исправлена только верхняя граница аргумента helper до720; default180 и serve AST прежние. Новый источник отслеживается SHA; старые результаты не переписывались.

Files-only вызов реального main() с сетевым выполнением отключённым:10/180/600/720 приняты,9/721 отклонены.3readonly saved reevaluations exact,88saved+failed SHA unchanged; receipt artifacts/diagnostics/lab-workload-watchdog-20261005/validation.json.

По новой просьбе UI Testing:18px галочка рядом с читаемым названием, выделение выбранного теста, настройки раскрыты только у выбранных; ориентировочное время всех прогонов каждого теста и суммарное время набора, без повторов единиц в описаниях. RU/EN36 комбинаций проверены безHTTP,56uniqueIDs/Node syntax; suite backend суммирует диапазоны дочерних планов. Реальная короткая UI build2.90s/0errors0warnings; визуальный браузер и полный новый сетевой запуск ещё не подтверждены.

NEXT USER idle admin UI restart→CtrlF5→only separate «Три режима»/Быстро/Высокая→newPrepare→Run→wait3/3. Старый failedplan не переиспользовать, Resume/перезагрузка не нужны для исправления аргумента. Агентский терминал nonadmin, guard не обходить. Длинные профили после короткого подтверждения. Следующая разработка — насыщение/восстановление по CONNECTION_STRESS_PLAN, сейчас NOTimplemented. ModelGPT-6.1Sol/high.


Короткий агентский запуск нового SHORT/HIGH трёхрежимного плана остановился BEFORE product/runtimequeries/claim: LAB_RUN_REQUIRES_ADMINISTRATOR. Терминал инструментов не elevated; controller не запускался, traffic/driverstate false. Не обходить guard. NEXT USER admin UI restart/newPrepare→Run; это не неудачный сетевой результат и не повод перезагружать Windows.

## Профили длительности/нагрузки и отдельный тест «Три режима» — source/build готовы (2026-10-05)

Добавлены реальные независимые настройки для каждой из трёх галочек: TCP RTT, transfer и tcp_rtt_three_modes. Каталог config/benchmark-workloads.json, Get-BenchmarkWorkload и C#/Python allowlists фиксируют шесть сочетаний. RTT128/256,1500/3000,6000/12000 измерений,1000 исключённых warmup, пауза20/10мс; transfer8/64MiB/с ×8/32/120 номинальных секунд,4verify:data/rude переноса. Новый preset не равен прежнему SMOKE: он сохраняется workload_preset/method controlled-workload-v1, отображается WORKLOAD; compatibility container SMOKE/одна пара сохранён. Разные нагрузки относятся к интенсивности запросов либо лимиту передачи, не к гарантированной загрузке ПК. Deadline600sec/watchdog720sec; прежние socket/data/PC/cleanup/cancel/filelease/crossboot gates сохранены.

Separate3mode GUI/queue (3tests max,3runs) uses three_modes_workload_v1. Остальные тесты OFF/PROXY. Frozen module/catalog SHA + numeric consistency before product; latest/history conditionfilter6combos+legacy, failed/cancel/unstarted no oldPASS, preserved safe labels and same-source metrics. Core/driver/native/networkhelpers unchanged; evaluators only opt-in new workload branches. Сборка UI3.62sec0errors0warnings; PS5.1 files-only Inspect3plans and6presets, PS5+7 AST/BOM, Python/Node syntax and JS presentation checks;9savedreevals exact/220SHA unchanged. Receipt artifacts/diagnostics/lab-workload-preparation-20261005; docs/WORKLOAD_PROFILES.md. NewGUI/API/product runtime not executed yet.

NEXT USER admin restart idle dotnetUI/CtrlF5, only «Три режима» / Быстро / Высокая, newPrepare→Run→wait3/3/sendresult. No oldA-B repeat/reboot unlessguard; oldfrozenplans invalidated by changed wrapper/host/controller hashes, no reuse. Длинные профили после короткой проверки. Тест насыщения/восстановления NOTimplemented, next bounded controller must distinguish fixture512socket ceiling/OS limits from PB behavior. User shortchecks<5min authorization remains, otherboundaries unchanged. Next GPT-6.1 Sol/high.


## Последнее уточнение: отдельный тест «Три режима» (2026-10-05)

Пользователь подтвердил: OFF / UNRULED / SOCKS5 нужны отдельным тестом с выбором длительности и нагрузки. Не добавлять эти три пути внутрь остальных тестов. Обычные тесты, включая насыщение соединениями, сохраняют напрямую / SOCKS5. Условия принадлежат каждому выбранному тесту; все три пути отдельного теста выполняются в одинаковых условиях.

Приоритет исправлен: реальные независимые профили длительности/нагрузки и тест насыщения с восстановлением. Подключение лишь прежней короткой трёхрежимной проверки не завершает задачу. INTERFACE_PLAN_2026-10-05, CONNECTION_STRESS_PLAN и TEST_SUITES согласованы; реализация новых профилей и насыщения ещё отсутствует. Подтверждённые короткие серии сохраняются; повторять их ради уточнения не нужно. Этот шаг — документы, без изменений контроллеров/методики/UI и новых запусков. Следующий шаг GPT-6.1 Sol / high; необходимые проверки менее5мин разрешены пользователем, остальные границы сохраняются.

## Реальная очередь из двух тестов подтверждена (2026-10-05)

USER screenshot «Проверка завершена,2/2» соответствует suite-547cf98312dd4476a92871cb05810eeb COMPLETED/terminaltrue/noCancel. Оба children той же сборки актуал/b0e6385e: RTT lab-tcp_rtt-smoke-20261005-071216-3e1d2ba2 COMPLETED2/2; transfer lab-tcp_transfer-smoke-20261005-071235-46866598 COMPLETED4/4. Parent от07:12:15.7064342Z до07:13:24.6827347Z,68.9763с (местное UTC+5). Transfer hoststarted07:12:35.2549128Z после RTT hostcompleted07:12:34.4078948Z; последовательность подтверждена receipts.

Все6evaluate_run в read-only совпали с savedreports и embeddedreports;142sourceSHAunchanged, обаLIMITED_COMPARISON/errors[]. RTT288verified256measured0failed;transfer4x64MiB=256MiBverifydata/rude.24worker receipts naturalexit0/capturetrue,3CLIready/graceful/poststop/unforced/capture/noerrors. CLI cleanup scope owned-process, interception_cleanup_verifiedfalse в CLIreceipt не глобальная очистка; отдельные scoped controllergates подтверждены evaluators. Никаких текущих driverprobes, нового traffic/build агентом не выполнялось.

Prepare/start/sequential-completion GUI/API/runtime подтверждены пользовательским запуском. Остановка/failure/restart очереди ещё НЕ наблюдались на actual runtime; не выдавать source/NodeVM checks за полную runtime-проверку. Успешный набор повторять не надо. Это короткая готовность, неcapacity/versionAB/3modevalidation. Receipt artifacts/diagnostics/lab-test-suite-confirmation-20261005-071215/validation.json.

NEXT development: adapter трёхрежимного RTT в GUI/очередь с прежними строгими guards/markers/results, затем другие сценарии/профили по плану; saturationcontroller не реализован. GPT-6.1 Sol/high. USER разрешил необходимые короткие проверки сборки<5мин; другие прежние явные boundaries остаются.


## Выбор тестов галочками и очередь — source/build готовы (2026-10-05)

Пользователь подтвердил понятное отображение grouped3mode таблицы. Затем разрешил агенту короткие проверки сборки менее5мин. Реальная UI dotnet build в отдельный output artifacts/development-checks/ui-suite-build прошла1.57с/0errors0warnings; это только сборка, не запуск продукта. Установки/перезагрузки/долгие серии не выполнялись.

Новый выбор TCPRTT и TCPtransfer галочками (один или оба), session миграция старого выбора, подготовка suite через существующие files-only childplans, freeze childSHA/bundle/build. Backend sequential wrappers ждёт каждого result/cleanup, busy между тестами; parentstop сохраняется и останавливает текущий прогон штатным marker, skipremaining. Failure stopsqueue. Durable parent job/no resume; INTERRUPTEDparent guard для следующего штатного wrapper. Не достигнутые tests получают CANCELLED0runs/SUITE_TEST_NOT_STARTED historyjob без метрик, не oldPASSfallback. Каждая успешная операция — прежний отдельный результат. Scope local known driverSMOKE, RTT ещё2mode;3mode/UDP/loaded/long/high/custom4remote очередь pending. Lease штатная pertest, не глобальная на весь набор; UI queuebusy/oldrealendpoint guard дополнительно исключают UI interleaving.

Проверены2Node syntax/PS5.1+7AST+BOM/RUEN216keys/54ids/одноразовая NodeVM presentation-state selection/gapbusy/stalestate/parentstop/no-start explanation.78savedthree-modeSHA unchanged. Core/driver/native/helpers/методикаконтроллеров не менялись. Receipt artifacts/diagnostics/lab-test-suite-preparation-20261005/validation.json; docs/TEST_SUITES.md. GUI/API/runtime последовательного набора и остановки PENDING_USER.

NEXT USER ADMIN idleUI Ctrl+C → dotnet run --project C:\src\ProxyBridge-TestLab\ui\ProxyBridge.TestLab.Ui\ProxyBridge.TestLab.Ui.csproj -- --RepositoryRoot C:\src\ProxyBridge-TestLab;CtrlF5. Отметить оба теста, Запуск→Подготовить→явно запустить, около3–7мин. Ожидать2/2tests,2RTT+4transfer runs,отдельныеhistoryresults. Это новая queueintegration, не очередной performanceA-B; успешную3mode/oldA-B не повторять. Reboot не нужен, если existingguard не требует. Model GPT-6.1 Sol/high. Агент теперь может необходимые короткие проверки<5мин, комбинированная очередь оценена>5мин и оставлена пользователю. Maintained autotests/subagents/commitpush не добавлены.


## Понятное отображение трёх режимов (2026-10-05)

Пользовательский screenshot подтвердил новую серию: p95 OFF .384 / UNRULED .372 / SOCKS5 .699 мс, разницы +.315 / -.012 мс, CPU/RAM совпадают с saved data. Прежний статус UI projection pending этой серии снят по наблюдению пользователя; агент не собирал приложение и не вызывал HTTP.

После «Не особо понятно» изменены только lab.js, lab-results.js, lab.css: выбор показателей и таблица RTT сгруппированы по режимам, разницы отдельно; короткие названия p50/p95/p99 с объяснением времени ответа, знака разницы и области CPU/private memory. Условия раскрываются отдельно. IDs выбора, сборки, latest-attempt/no-fallback и числа сохранены. Малая отрицательная разница не объявляется ускорением, CPU0 — не доказательство отсутствия затрат драйвера.

2 Node syntax, RU/EN205keys, полнота групп12/10/15metrics, одноразовая проверка разметки на saved data passed: 4groups/15metrics RU/EN, .699 и -.012 сохранены, failed15dash, имя сборки экранируется. Node VM — не browser/HTTP/build/benchmark, новых автотестов в проекте нет. Receipt artifacts/diagnostics/lab-results-clarity-20261005/validation.json. Новая визуальная версия pendingUSER CtrlF5 только; повтор измерения, перезапуск приложения, перезагрузка не нужны. Методика/контроллеры/backend/Core/driver/native/helpers не менялись. Следующий development шаг GPT-6.1 Sol/high: наборы тестов/очередь и повторяемые профили по плану; насыщение соединениями не реализовано.


## Первый реальный трёхрежимный TCP RTT подтверждён (2026-10-05)

USER Run tcp-rtt-three-modes-smoke-20261005-062214-57566d COMPLETED OFF/UNRULED/PROXY3/3, comparison LIMITED_COMPARISON/errors[]. Read-only3evaluate_run точно совпали с3saved и embedded;78sourcefilesSHA unchanged,984verified/384measured/failed0 (>20ms0).12workers naturalexit0/capturetrue/unforced,2CLIready/graceful/poststop/clean; saved afterknownWFPStopped/detached/knownloadedabsent. Проверка только saveddata, не текущий probe/globalcleanup.

RTTp50/p95/p99ms OFF.22790/.38370/.49470;UNRULED.23215/.37170/.50840;PROXY.51025/.69880/.75270. UNRULED−OFF +.00425/−.01200/+.01370;PROXY−OFF +.28235/+.31510/+.25800. CLI UNRULED CPU0%wholePC/private3.17578125MiB,PROXY.0681625%/3.234375MiB; sampler zero не доказывает отсутствие kernelCPU/productcost. В window3.83–3.86s coverage, socket snapshot finishes>=4347.3523msbeforemeasurement. Один128echo fixedorderreadinesscycle, не causaloverhead/capacity/gaming/longstability/versionproof. Значения CPUCLI не ресурсы самого драйвера.

NewUNRULED actualsingleotherrule/watch1/activeDriver+Runningservice/directroutePID/noownedRELAY/directsocketreceiver flow подтверждены прежними strict evaluators; originalProduct/native/helpers unchanged. Artifact artifacts/diagnostics/lab-three-mode-rtt-confirmation-20261005-062214/validation.json. No new agent producttraffic/build/HTTP/probes/install/autotestsubagentcommitpushrebootcleanup; successfulnewseries no rerun.

NEXT USER restartidle UI Ctrl+C→ADMIN dotnet run --project C:\src\ProxyBridge-TestLab\ui\ProxyBridge.TestLab.Ui\ProxyBridge.TestLab.Ui.csproj -- --RepositoryRoot C:\src\ProxyBridge-TestLab;CtrlF5 Results→«Задержка TCP: выключен / без правила / SOCKS5»,актуал,choose3p95+UNRULED/PROXYCLIcpuRAM andHistory. ActualnewUIcompile/APIprojectionpending; no benchmark/reboot. AfterUIconfirmation→testcheckboxes/queue+repeat3modeprofiles perplan, saturationstillNOTimplemented. GPT-6.1 Sol/high.

## Три режима TCP RTT: новая ветка подготовлена (2026-10-05)

Existing Invoke-LocalTcpRtt optional ThreeModes onlydriverSMOKE/nolegacy/versionrefs:128measured+200warmup512bytes20ms, OFF/UNRULED/PROXY fresh distinctstage three_modes_readiness_v1. Reuse native/receiver/SOCKS/PC lifecycle+cleanup; UNRULED profile single dummyprocess instead generator, actualCLI oneadded/watch1/activedriver-service, PID DIRECT/noRELAY and owned reciprocal direct endpoints/nohelperflow. All3 ownedTCPsnapshot completesbeforemeasured elseINCONCLUSIVE. New pb_tcp_three_mode_report extends base evaluator onlystage, validatesexactprofiles/states/PC/data and readonlysource reevaluation; onefixedorderreadiness, notoverhead/capacity/versionproof. Default old2mode/legacy source evaluations unchanged. Core/driver/native/helpers untouched.

New Invoke-LocalTcpThreeModes Phase Inspect default files-only pinnedknownkit+sourceSHA, PS5 actual FILES_PREPARED/bundlea6775808/producttrafficdriverfalse. Phase Run USERADMIN sharedGlobalmutex+FileShareNone checkoutlease throughcleanup; clonedexisting wrapper recorded4/GUI interrupted crossboot guard +priorRUNNINGthree-mode guard, noauto reboot/globalproof. CurrentoldpreparedGUIplans controllerSHA changed→reprepareifused. Newmanualruntime notexecuted.

Saved Results/History newscenario tcp_rtt_three_modes separatefromold2, exact3source/profile/receipt/bundle/method gates,counts984verified384measured, UNRULEDRTT+CLIcpuprivateRAM+addition. Manualsource root tcp-rtt-three-modes-smoke-* strictbasename GET; oldreports/historyunchanged, no oldmetricpool. ActualC#compile/HTTP/UIprojection pendingUSER afterrun, manualcommandonly/noGUIstartfornewscenario yet. Failedunknownbundle canblocklatest conservatively.

PS5.1+7.6.5AST/BOM/2PythonAST/2NodeSyntax/2C#Roslynsyntax(notbuild)/54HTMLids/RUENmetricids passed;16savedRTT reevaluations exact (2GUI+6legacySTD+6driverSTD),387originalfilesSHA unchanged. Receipt artifacts/diagnostics/lab-three-mode-rtt-preparation-20261005/validation.json+files-only-inspection.json. No agent buildHTTPPBtrafficdriverprobesinstallautotestsubagentcommitpushrebootcleanup.

NEXT USER ADMIN powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\src\ProxyBridge-TestLab\scripts\Invoke-LocalTcpThreeModes.ps1 -Phase Run (~3–5min;3newreadinessruns), sendoutput/dir. No oldsuccessfulrerun/rebootunlessguardrequires. Afteractualresult review→USER restartdotnetUI CtrlF5 Results newthree-mode dropdown. docs/THREE_MODE_TCP_READINESS.md. Then repeatedcounterbalancedmodes/testsuite; stress separatelynotimplemented. GPT-6.1 Sol/high.

## Три траектории и сценарий большого числа соединений (2026-10-05)

USER screenshot подтвердил работающую latest таблицу с RTT/CPU/RAM; запросил OFF / running-unruled / SOCKS5 и тест насыщения соединений. lab-results.js/js только: добавлены direct OFF p50/p95/p99 + upload/download из тех же подтверждённых TCP данных; чёткие RU/EN labels. UNRULED selectors пока возвращают null («—») + пояснение, текущие TCP серии OFF/PROXY; не подставлять старые UDP/другие профили. Нужен новый трёхрежимный TCP контроллер с собственными current conditions/route/state gates, этого runtime пока нет. DIRECT правило для перехваченного процесса не равно процессу вне watchlist.

Проверены закреплённые upstream исходники driver63be0eb по GitHub; локальный checkout137d1286 не использован как provenance. Event ring2048/2047 usable drops oldest logs; UDP2048 buckets linked dynamically allocated nonpaged nodes/no per-flow expiry in state file, clear only observed at driver unload; TCP WFP redirect context+relay allocations/threads, failures close new socket. Анализ кода/гипотезы, не эксперимент и не вывод о4.0.0. Новый docs/CONNECTION_STRESS_PLAN.md: independent retained TCP/UDP flows +churn/recovery, separate logs/data loss, resource ceiling attribution, bounded controlled receiver runs; исходный продукт не менять. Stress controller NOT_IMPLEMENTED.

Node2JS syntax/RUEN unique metric labels passed;4backend/markup/style SHA unchanged vs prior receipt;2saved TCP reports modes OFF/PROXY readonly. Receipt artifacts/diagnostics/lab-three-modes-20261005/validation.json. Agent no build/HTTP/product/driver probe/benchmark/reboot/cleanup/autotests/subagents/commit/push. NEXT USER CtrlF5 only, no UI rebuild/restart/newtraffic. Next implementation preparation three-mode controlled comparison and test suite per plan; heavier new runtime USER manual after prepared command/time estimate. GPT-6.1 Sol/high.

## Актуальная таблица и история подготовлены (2026-10-05)

USER подтвердил каталог «Работает»; это сообщение принято как подтверждение пользовательской UI проверки, не отдельная agent build/HTTP/DPAPI проверка. Новый Results: вкладки Сравнение/История с URL tab=compare|history и Back/Forward. Сборки/метрики галочками и выбор TCP RTT/TCPtransfer (только текущие короткие локальные SMOKE). Выбор сравнения хранится session без paths/secrets. Один последний attempt на build identity+scenario+фиксированный profile; статус/дата показаны, numeric только confirmed terminal PASS. Failure/cancel/inconclusive/active не заменяется oldPASS. Полной beta/high/long/remote поддержки пока нет.

Backend saved local projection сохраняет strict data/route/receipt/kit gates, добавляет RTT CLI средние CPU/privateRAM и conditions_key по canonical sorted config (исключены ephemeralports/PIDs/runid/direction/productlabel), отказывается подтверждать смешанные configs внутри серии. Это не новое измерение/оценка энергии или driver-only CPU и не полное доказательство A/B сопоставимости; UI явно пишет ограничения. Старые source JSON/metrics не переписаны.

Новая launch_history из frozen plans+saved jobs (profile/contract/id/bundle validation) включает pre-workload failure/cancel/no-report. Source/job dedup по plan id; active current state overlay. Unreadable source остаётся INCONCLUSIVE, неизвестная поздняя попытка/нечитаемая job history блокирует latest table. История фильтруется build/test/status, раскрывает исходные подтверждённые показатели; paired4/driver archive отдельно. Первоначально50local/scenario +1000jobs; GETlab/history?offset и кнопка older, GETlab/history/{strictlabid} source-only details для older. Cache reset on refresh/epoch guard, не запуск продукта; старый результат никогда не выбирается вручную для актуальной таблицы. Переименование label не меняет binding файлов.

Проверено: оба JS Node syntax,2C#Roslyn syntax НЕ build,54uniqueHTMLIDs/JS+aria targets/RUEN+metric keys/defer order lab-results.js→lab.js;3savedseries одинаковые condition поля,2RTT CLI finite CPU/RAM,187originalsavedfilesSHA unchanged;4savedUIjobs including2failed/cancelled;3PScontroller-host-wrapper SHA unchanged. Никаких agent build/HTTP/PBtraffic/probes/install/autotests/subagents/commit/push/reboot/cleanup. Receipt artifacts/diagnostics/lab-results-history-20261005/validation.json. Новый full compile/HTTP/tabs/latest/filter/pagination/detail runtime PENDING_USER; source-only проверки не считать runtime proof.

NEXT USER: Ctrl+C idle UI, ADMIN dotnet run --project C:\src\ProxyBridge-TestLab\ui\ProxyBridge.TestLab.Ui\ProxyBridge.TestLab.Ui.csproj -- --RepositoryRoot C:\src\ProxyBridge-TestLab; CtrlF5 /lab.html?page=results. Сравнение: «актуал», TCPзадержка→p95/CPU/RAM, затем TCPtransfer и выбор метрик. История: filters/открытие прошлых+failed/cancelled, pairedarchive retained. Без нового benchmark/reboot. После подтверждения — тесты галочками/последовательный набор, затем duration/load presets и runtime custom/4/remote по плану. GPT-6.1 Sol / Высокое.

## Каталог именованных сборок подготовлен (2026-10-05)

USER «Вроде всё работает» + screenshot подтверждают навигацию отдельных views/активную вкладку Results/прежние67.85/67.92 transfer metrics. Детали Back/Forward/refresh активного задания отдельно не наблюдались; нет повода повторять benchmark.

Новый BenchmarkBuildCatalog (DPAPI benchmark-builds.dpapi, bounded1MiB/256entries/no reparse/atomic temp move/semaphore) хранит request paths приватно, публично только ID/name/type/дату files observation/runtimefalse. ID = SHA256(contract + normalized binary bundle), одно содержимое не становится двумя версиями из-за имени. ProductSelectionRequest.optional DisplayName64/control validated; old saved selection мигрирует из исходного observation при GetState без новых probes. Select re-inspects files и сохраняет/обновляет запись; rename не пишет measurement evidence. POST lab/build/select|rename используют existing origin/CSRF; select отказывается при наблюдаемом активном UI job. UI поле «Название сборки», тип отдельно; catalog choose/rename, safe HTML escaping, failed select требует обновления выбора. Не обещать arbitrary beta readiness: known/original/local gates unchanged.

Frozen plans build_id/build_name_at_run + optional backward-compatible persisted job BuildId/BuildName; launch verifies binding against frozen bundle. Старые планы без этих полей поддержаны. Saved local projections сохранили прежние evidence gates/численные поля; добавлена build metadata из source verified bundle либо связанного frozen plan+controller receipt для неполной попытки. Для RTT проверяется единый bundle у обоих modes; mismatch не PASS. Старые результаты не переписаны; отсутствующее старое пользовательское имя не выдумывать. New name snapshot runtime ещё не проверен. Saved name_at_run при наличии имеет приоритет над новым именем каталога.

Проверено: Node syntax/5C#Roslyn syntax НЕ build,44uniqueHTML IDs/JS+aria refs/RUEN translations;3existing controller-host-wrapper SHA unchanged.3confirmed saved series имеют единый64hex bundle/187savedfiles SHA unchanged. Receipt artifacts/diagnostics/lab-build-catalog-20261005/validation.json. Build/HTTP/DPAPI migration/select/rename/plan metadata runtime PENDING_USER. Изменены только UI/services/launch metadata; PScontrollers/Core/driver/native/helpers/evaluators не менялись. Agent no build/HTTP/product/traffic/probe/install/autotests/subagents/commit/push/reboot/cleanup.

NEXT USER: остановить idleUI Ctrl+C, ADMIN dotnet run --project C:\src\ProxyBridge-TestLab\ui\ProxyBridge.TestLab.Ui\ProxyBridge.TestLab.Ui.csproj -- --RepositoryRoot C:\src\ProxyBridge-TestLab; CtrlF5 /lab.html?page=builds. Сохранённый driver должен появиться автоматически; переименовать его «актуал», выбрать запись, обновить страницу, посмотреть её подпись в старых Results. Только каталог/files inspection, не новый benchmark/reboot. Сообщить результат/build error. Затем latest-only comparison+отдельная история, test suite/presets/custom adapters по плану. GPT-6.1 Sol / Высокое.

## Отдельные страницы лаборатории подготовлены (2026-10-05)

Первый шаг нового плана реализован в lab.html/js/css: отдельные URL /lab.html?page=builds|testing|run|results, один видимый раздел и активная навигация; переходы через History API без уничтожения состояния/плана или остановки серверного задания. Back/Forward и старые bookmarks #connection/#testing/#launch/#results, корректный title/RUEN/aria-current/focus. Общая полоса активного задания/потери связи ведёт на Запуск; сводка выбора, кнопки переходов, команда в details. Не создавались дубли четырёх HTML файлов или новые backend зависимости.

sessionStorage содержит только валидированные mode/scenario, не пути/секреты/планы. Перезагрузка восстанавливает saved kit и active job через прежний API; неподготовленная/изменённая сборка остаётся blocked. Неиспользованный план сохраняется при переходах и refresh результатов при прежнем сохранённом bundle/contract; полный reload требует новой подготовки. Active scenario восстановлен из серверного job. Навигация не запускает ничего, старые strict gates/cancel/CSRF/lease/boot policy остаются в прежнем backend. Браузерная работоспособность новых переходов пока НЕ наблюдалась.

Проверено: Node syntax, static HTML inventory41uniqueIDs/11validlinks/4views/JS+aria targets, RUEN key equality/HTML translations;7controller/backend SHA совпадают с прежним receipt. Проверки только исходников, без UI/build/HTTP/traffic/probe/install/autotests/subagents/commit/push/reboot/cleanup. Receipt artifacts/diagnostics/lab-pages-20261005/validation.json. Измерительные файлы/старые результаты не изменялись.

NEXT USER: CtrlF5 http://127.0.0.1:5178/lab.html?page=builds; пройти страницы, выбрать сценарий, проверить Назад/Вперёд и обновление страницы «Тестирование», RU/EN и прежние Results. Не запускать новый benchmark ради навигации. Для статических изменений restart/build/reboot не нужны. После visual/navigation feedback следующий этап — named build catalog и единый latest-only comparison с отдельной историей, затем test suite/presets и arbitrary kit adapters по плану. GPT-6.1 Sol / Высокое.

## Уточнение истории и актуальных результатов (2026-10-05)

Пользователь добавил историю всех запусков и потребовал только актуальные данные в выборочной таблице. INTERFACE_PLAN обновлён: отдельные «Сравнение»/«История», последний результат по фактической ревизии сборки/тесту/точным условиям, сохранённые ID/дата. Последний FAILED/CANCELLED/INCONCLUSIVE не заменять старым успехом; метрики одного теста из одного результата. При новом активном запуске прежние данные явно предыдущие; после изменения бинарников не наследовать результаты старой ревизии. История сохраняет все исходные отчёты/ошибки/отмены. Это docs-only уточнение, без изменения UI/runtime/свидетельств и без выполнения тестов; следующий шаг остаётся реализация отдельных страниц. GPT-6.1 Sol / Высокое.

## Новый план интерфейса (2026-10-05)

Пользователь предложил разнести длинный экран по страницам, выбирать тесты галочками, длительность и нагрузку независимо, именовать сборки «актуал»/«бета» и строить таблицу по выбранным результатам/характеристикам. Требования и порядок реализации записаны в INTERFACE_PLAN_2026-10-05.md; DEVELOPMENT_PLAN и указатель в прежнем INTERFACE_FLOW обновлены. Сейчас менялся только план, не UI или runtime.

Следующий шаг: отдельные страницы Сборки → Тестирование → Запуск → Результаты на существующем рабочем backend, сохранение выбора/языка/серверного активного задания при переходах. Затем каталог сборок с отдельными display name и стабильными ID/ревизией файлов; единый каталог saved runs/метрик и таблица; очередь выбранных тестов и проверенные пресеты. Полная проверка произвольной GitHub beta требует адаптера совместимости/готовности; имя не заменяет доказательства происхождения. Не смешивать разные окна, нагрузку, инструменты или старые методики; не назначать старым SMOKE/STANDARD новые названия low/high задним числом. Новые страницы/наборы/профили/custom support пока НЕ реализованы.

USER screenshots подтверждают GUI transfer завершён4/4 и показывает upload OFF67.85/PROXY67.92 Mbit/s, download67.95/67.88, CLI CPU/RAM. Read-only проверка lab-tcp_transfer-smoke-20261005-043156-536c66fa: manifest COMPLETED/error empty/четыре completed OFF-PROXY push-pull; comparison LIMITED_COMPARISON/errors[]; summary совпадает с screenshot. Это наблюдение GUI runtime/проекции, не полный повторный source аудит и не доказательство transfer cancellation/maximum capacity. Новую успешную серию не повторять ради оформления.

В этом ходе только чтение исходников/сохранённых JSON/документация; агент не запускал build, HTTP, продукты, генераторы, probes, installs, автотесты, subagents, commit/push, reboot или cleanup. Измерительные контроллеры и исходные свидетельства не менялись. Для следующего этапа GPT-6.1 Sol / Высокое.

## GUI TCP-передача подготовлена (2026-10-04)

Разрешён второй GUI сценарий tcp_transfer для исходного known driver/local/SMOKE. Existing frozenplan/DPAPI повторная проверка/admin/origin-CSRF/sharedlease/crossboot gates сохранены. BenchmarkRunService запускает тот же wrapper/host/controller,4 runs вместо2, добавлены optional Scenario/CurrentDirection в persisted view с совместимыми defaults для старых RTT jobs. Прогресс показывает отправку/скачивание и direct/SOCKS5. Host/wrapper передают фиксированный CancellationPath также TCP transfer; one-useplans/UTF8capture/outcome checks/не убивать controller unchanged. Остальные сценарии и4/remote/relocated/custom по-прежнему не запускаются через кнопку.

Только opt-in cancellation изменяет Invoke-LocalTcpBenchmark.ps1: fresh driver data-only SMOKE без Resume/diagnostics, marker перед следующим прогоном, текущий Invoke-TcpRun завершается с исходными проверками/cleanup. CANCELLED сохраняет partial runs без comparisonPASS; поздний stop допускает полныйCOMPLETED. Профиль прежний64MiB8MiB/s x4, stock ctsTraffic rude verifydata, CLI/Core/driver/native/helpers/evaluators/обычный default/предыдущие серии не менялись. Предыдущий closure fix контроллера TCP transfer уже используется.

GetLocalTransferReports +GETlab/state local_transfers и новый RU/EN Results раздел: отправка/скачивание OFF/SOCKS5 Mbit/s/change%, CPUwholemachine/privateRAM CLI и256MiBverifiedtotal. Только saved lab-tcp_transfer-smoke-* с4complete manifests/source reports exactembedded/config/profile/receipt/data/kit/matchingbundle gates получают PASS; failed/cancelled не скрываются. Scope явно readiness/ratecapped/normal-close-not-tested/notdriverCPU/notwatts/notcurrent-state. Технические paths/logs в API не отдавать. RTT history и saved version comparisons сохранены.

Проверено PS5.1+7AST/BOM, Node syntax, C#Roslyn syntax (НЕ fullcompile/build),32HTMLids/JSrefs/RUENkeys, files-only transfer frozenplan Inspect PLAN_FILES_VALIDATED/runtimefalse/productfalse/trafficfalse/probefalse. Четыре readonly evaluations existing driver dataSMOKE равныoriginals;112 saved sourceSHAunchanged. Ошибка вспомогательной HTML-проверки Where-Object -gt1 исправлена на block и проверка повторена; не ошибка приложения. Новые GUIcompile/HTTP/transfer-start-stop/report projection ещё PENDING_USER. No agent build/HTTP/producttraffic/driverprobe/install/autotests/subagents/commit/push/reboot/cleanup. Receipts artifacts/diagnostics/lab-gui-transfer-preparation-20261004/{validation.json,saved-evidence-observation.json,files-only-plan-observation.json}.

NEXT USER: Ctrl+C в консоли старого idleUI, ADMIN dotnet run --project C:\src\ProxyBridge-TestLab\ui\ProxyBridge.TestLab.Ui\ProxyBridge.TestLab.Ui.csproj -- --RepositoryRoot C:\src\ProxyBridge-TestLab; CtrlF5 /lab.html. Known driver/local/«Отправка и скачивание TCP»→Подготовить→Запустить, дождаться4/4 и показать Results/ошибку. Около2–4мин/256MiBmemorypayload, никаких payload files; не повторять прежние A/B/RTT. Это первая проверка новой GUItransfer связки, не capacity series. После успеха остальные localGUI scenarios/remote/4 по плану. GPT-6.1 Sol / Высокое.

## GUI RTT: полный запуск и запросы остановки подтверждены (2026-10-04)

USER показал два новых результата. lab-tcp_rtt-smoke-20261004-172900-af4fbe60: CANCELLED,0 entries, cancel.request записан17:29:01.3089206Z ДО manifest/start17:29:01.3743698Z; ни одного Invoke-TcpRun, сравнение отсутствует, wrapper exit0/capturetrue. Это отмена до первого прогона, не проверка очистки работающего прогона.

lab-tcp_rtt-smoke-20261004-172929-f7ba8a62: COMPLETED/2из2, оба PASS/MEASURED/errors[], LIMITED_COMPARISON/errors[]. Два readonly reevaluations равны originals;46 файлов обеих серий SHAunchanged.288verified/256measured/0failed;8 worker results exit0/unforced/no timeout/capturetrue;CLI6308 ready/graceful/unforced/poststop/capturetrue. Saved receipts workers_stopped/driver_stop true; WFPStopped/detached/known loaded names absent после обоих modes. Saved scoped observations only; no global/current driver state claim.

OFFp50.225000/p95.303800/p99.327300/max.331500ms; PROXY.515650/.797000/.893600/1.041300ms; paired adds+.290650/+.493200/+.566300ms. Одна SMOKE пара, не максимальная/игровая/длительная производительность и не A/B версий. UI start/progress/terminal auto-results/UTF8 host и исправленный nested callback теперь actual runtime подтверждены. Stopmarker17:29:39.8181699Z поступил после завершённого OFFreceipt17:29:37.8422404Z, когда PROXY уже стартовал; последний прогон завершён с cleanup и полная серия остаётся COMPLETED. Отдельный случай остановки активного первого прогона с последующим пропуском второго НЕ наблюдался; не объявлять все cancel branches проверенными и не повторять успешную серию ради отчёта.

Уточнён ТОЛЬКО JS RU/EN: CANCELLED history теперь нейтральное «Проверка остановлена. Итог сравнения не составлен», без ложного сообщения про выполненные прогоны при0. COMPLETED+cancellationRequested объясняет завершение последнего прогона и полной серии. Node syntax/RUEN keys проверены; для отображения CtrlF5, без C# rebuild/restart/benchmark/reboot. Agent не выполнял build/HTTP/traffic/probe/install/autotests/subagents/commit/push/reboot/cleanup. Следующий development — other local scenario result projections и GUI controllers с теми же strict/lease/crossboot/cancel gates;4/remote/custom по backlog. GPT-6.1 Sol / Высокое. Receipt artifacts/diagnostics/lab-gui-rtt-confirmation-20261004-172929/validation.json.

## Вложенный RTT callback: ошибка лаборатории исправлена (2026-10-04)

USER GUI запуск plan-d25a43e6255e423db600ca72aa6c59d2 дошёл до нового host/controller, но lab-tcp_rtt-smoke-20261004-171856-d25a43e6 завершился FAILED/0из2 на первом OFF: Qpc-Ms не найден внутри GetNewClosure dynamic module при вызове контроллера из parent script. Native client ещё не стартовал: traffic_generated=false, нет client.jsonl/client-process/measurement-window; продукт в OFF не запускался. Три helpers receiver8132/proxy7924/sampler8988 naturalexit0/unforced/capturetrue. Saved workers_stopped/driver_stop_observed/receiver_identity=true; WFPStopped/detached и known loaded names absent в saved postrun. Это scoped сохранённое наблюдение, не текущая/глобальная проверка. UI compile/HTTP prepare/explicit start/failed projection и UTF8 wrapper output capture теперь подтверждены через USER runtime. Cancellation_requested=false: остановка ещё не проверена.

Исправлен только Invoke-LocalTcpRtt.ps1 по уже применённому TCP transfer решению: четыре script inputs client/ProductContract/pairedDriver/observationEnvironment материализованы как function locals; FunctionInfo Qpc/WriteJson/2Interception commands явно captured и вызываются через &, sink использует captured writer. Пустой callback executable отсекается до nativeStart. Протокол/генератор/параметры/таймерная формула/контроль data-route-PC/cleanup/cancel между прогонами неизменны; Core/driver/native/helper/evaluator/UI/C# не менялись. Не маскировать исходный FAILED.

Проверка: AST/BOM PS5.1+7; actual callback AST metadata после завершения child script scope вызвал настоящий timer/writer/sink и сохранил executable в PS5.1 и PS7.6.5. NativeStart заменён безопасной границей до любого запуска; interception commands только captured, не выполнены. Files-only fresh plan Inspect PLAN_FILES_VALIDATED/runtimefalse/productfalse/trafficfalse/probefalse. Два старых saved RTT reevaluations точно равны originals;60 файлов успешного и нового failed runs SHA unchanged. Первые попытки создать metadata observer shell here-string и вызвать несуществующий стандартный PS7 path не дали product/runtime; observer записан через patch, PS7 найден через PSHOME. Полный исправленный GUI run/cancellation PENDING_USER; агент build/HTTP/traffic/probe/install/autotests/subagents/commit/push/reboot/cleanup не выполнял.

NEXT USER: приложение НЕ перезапускать, новая сборка UI не требуется. В том же экране «Подготовить запуск» создаёт новый frozen plan с исправленным controller hash → «Запустить проверку» → во время первого OFF0/2 «Остановить после текущего прогона» → ждать итог/сообщить screenshot. Старый failed plan не переиспользовать/не Resume, failed artifacts сохранить. Эта ошибка не требует перезагрузки; текущие runtime gates остаются обязательными при новой попытке. GPT-6.1 Sol / Высокое. Receipts: artifacts/diagnostics/lab-rtt-callback-scope-20261004-171856/{failure-analysis.json,validation.json,files-only-plan-observation.json,metadata-5/observation.json,metadata-7/observation.json}.

## Запуск TCP RTT и остановка из UI подготовлены (2026-10-04)

Добавлены BenchmarkRunService, POST lab/run/start|stop и GET lab/run; существующие loopback/origin/CSRF проверки сохранены. Только явный запуск по созданному сервером plan-id, только исходный known driver/local/tcp_rtt/SMOKE, приложение должно работать от администратора. Перед запуском повторно проверяются DPAPI selection/исходный путь/bundle; frozen controller/entry/host/env hashes и все runtime/route/data/PC/cleanup gates остаются в PowerShell. Новые RU/EN кнопки Run/Stop, completed-count из manifest (0/2–2/2), direct/SOCKS mode, polling только активного запуска, автоматическое обновление результатов. Нет выдуманного процента или claim о готовности всей лаборатории. Остальные сценарии пока по подготовленной команде; unknown/relocated/4.0.0/remote/custom не включены.

Единственное изменение измерительного контроллера Invoke-LocalTcpRtt.ps1: необязательный CancellationPath и проверка маркера перед каждым следующим прогоном. Текущий Invoke-TcpRun завершает исходные проверки и cleanup; CANCELLED сохраняет completed runs, не составляет paired comparison и не становится PASS. При позднем запросе последняя проверка может завершиться COMPLETED. Core/driver/native/helper/evaluator не менялись, default без маркера прежний. Wrapper/host передают фиксированный путь cancel.request, не убивают процесс; stdout/stderr/exit receipts сохраняются. При отсутствии summary больше не выводится ссылка на несуществующий отчёт.

Shared RuntimeExecutionLease (FileShare.None) согласован с Invoke-PlannedBenchmark и старым real RunExecutor для того же checkout. Старый fixture-путь не затронут. Это не блокировка внешних вручную запущенных продуктов/прямых контроллеров. UI job.json сохраняется атомарно; app restart не возобновляет job, ставит marker и INTERRUPTED с прежним updated time. Wrapper требует новую загрузку Windows после такого времени/зарегистрированной 4.0.0 activity, кроме собственного текущего job. Проверка истории scoped; глобальная очистка не доказана. При штатном закрытии приложения stop кооперативный, HostShutdownTimeout 3 минуты; force-kill не добавлен.

Проверено: PS5.1+PS7 AST/BOM, Node syntax, C# Roslyn syntax (НЕ build),31 HTML ids без дублей/потерянных JS targets, RU/EN keys одинаковые. Настоящий безопасный child PS5 не смог открыть занятую метаданную file lease, после release файл открылся. Новая frozen files-only Inspect PLAN_FILES_VALIDATED/runtimefalse/productfalse/trafficfalse/driver_statefalse. Два readonly evaluate_run прежнего успешного SMOKE совпали с originals,45 source SHA неизменны. Receipts: artifacts/diagnostics/lab-gui-run-control-20261004/{validation.json,files-only-plan-observation.json,saved-evidence-observation.json}. Новые GUI API/полная сборка/host/кнопки/cancellation/product runtime ещё НЕ проверены. Agent не выполнял build/HTTP/PB/traffic/driverprobe/install/autotests/subagents/commit/push/reboot/cleanup.

NEXT USER: остановить старую UI console Ctrl+C (если нет активной проверки), открыть PowerShell от администратора и запустить dotnet run --project C:\src\ProxyBridge-TestLab\ui\ProxyBridge.TestLab.Ui\ProxyBridge.TestLab.Ui.csproj -- --RepositoryRoot C:\src\ProxyBridge-TestLab. Ctrl+F5 на /lab.html; выбранный known driver → local TCP RTT → Подготовить запуск → Запустить проверку. Во время первого прямого прогона (0/2) нажать «Остановить после текущего прогона», дождаться статуса и сообщить результат/скриншот или build error. Это проверка новой UI/cancel связки, не повтор успешной серии производительности; agent runtime не запускает. Если остановка запрошена поздно, возможен COMPLETED вместо CANCELLED. Без автоматической перезагрузки. Затем остальные local report projections/GUI paths; 4/remote/custom по плану. Следующая модель GPT-6.1 Sol / Высокое.

## Отображение local RTT в UI подтверждено (2026-10-04)

USER screenshot confirms local SMOKE RTT Results renders actual saved metrics correctly (OFF/PROXY, deltas,288verified256measured0errors); app compile and HTTP projection observed through user. Fixed duplicate units in header and translated ms/maximum row label in JS only; Node syntax passed. Only CtrlF5 needed, no restart or new benchmark. Receipt: artifacts/diagnostics/lab-first-rtt-review-20261004/ui-result-observation.json. Next development: automatic GUI execution/progress/cancel and other local scenario report projection, with existing strict/runtime/exclusivity/crossboot gates; unknown/relocated/4/remote remain gated. NewUTF8host fullproductruntime still pending, no redundant output-only benchmark rerun. No agent product/HTTP/build/probe/install/autotests/cleanup/subagents/commit/push. GPT-6.1 Sol/high.


## Первый запуск по плану UI подтверждён (2026-10-04)

USER выполнил plan-fff18fedae1a40fd828b1b6482180f9a -Phase Run. Фактическая папка artifacts/local-route/lab-tcp_rtt-smoke-20261004-155706-fff18fed: manifest COMPLETED, OFF/PROXY MEASURED+PASS/errors[], comparison LIMITED_COMPARISON. Два readonly evaluate_run точно равны исходным;45 исходных файлов SHA до/после одинаковые. Проверено288 обменов (256 measured+32 warmup), ошибок0. Paired additions p50+.267700/p95+.454200/p99+.458700ms; mode p50 OFF.2269/PROXY.4946, p99 OFF.4394/PROXY.8981ms. Это одна SMOKE пара, не A/B версий, игровая/длительная стабильность или максимальная нагрузка.8 workers exit0/timed_outfalse/capturetrue; CLI ready/graceful/unforced/poststop/capture true; saved WFPStopped/detached + querycomplete known loaded names absent. Только сохранённое scoped cleanup; не глобальная/текущая проверка.

В консоль дошли только строки обёртки: CreateNoWindow без redirect/forward дочерних streams. Это не провал workload; old wrapper exit code отдельно не сохранён. Исправлена обёртка: живое чтение stdout/stderr одновременно, UTF8 stdout host, отдельные logs+controller-process receipt,15s bounded drain после exit и сохранение exitcode, one-use plan directory. При ошибке записи лога продолжать ждать cleanup контроллера/не выдавать complete capture. Новый минимальный Invoke-BenchmarkControllerHost.ps1 задаёт ConsoleUTF8/ProgressSilentlyContinue и передаёт те же параметры исходным контроллерам в отдельном PS5; fingerprint host также frozen. Controller/Core/driver/native/helpers/evaluators не менялись; старый успешный план не повторять. Новая host/stream full product integration ещё не выполнялась; console pump проверен на безвредном child stdout2+stderr1 RU/exit7. Первый metadata observer scope failure исправлен dot-sourcing; cold module CLIXML suppressed, это не ошибки продукта.

UI GET lab/state теперь проецирует saved local RTT SMOKE из lab-tcp_rtt-smoke-* в новый простой RU/EN раздел Results: OFF/SOCKS p50/p95/p99/max+pairedaddition, counts, readiness/saved-only caveats. Для PASS требует complete manifests/embedded reports==source reports/strict source verdicts/config/kit/cleanup receipts; failed/unconfirmed не скрывать. Не читает raw logs/paths в API, не запускает продукты/состояние системы. Other local scenario results/automatic UI launch/progress/cancel/4/remote/custom остаются pending. C# Roslynsyntax(notbuild), Node, PS5AST+newfiles-only plan Inspect,26HTMLids/refs passed. Полная обновлённая C# компиляция/HTTP проекция pending user.

NEXT USER: Ctrl+C в UIconsole, dotnet run --project C:\src\ProxyBridge-TestLab\ui\ProxyBridge.TestLab.Ui\ProxyBridge.TestLab.Ui.csproj -- --RepositoryRoot C:\src\ProxyBridge-TestLab, Ctrl+F5 /lab.html, Results/Обновить. Проверить отображение уже готового результата и сообщить screenshot/build errors. Новые benchmarks/reboot сейчас не нужны; runtime не запускать агентом. GPT-6.1 Sol/high. Receipts: artifacts/diagnostics/lab-first-rtt-review-20261004/validation.json +saved-evidence-review.json +console-pump-observation.json.


## Подготовка через UI подтверждена пользователем (2026-10-04)

Скриншот показывает готовый tcp_rtt SMOKE план. Файл plan-fff18fedae1a40fd828b1b6482180f9a.json прочитан и соответствует driver/local/Invoke-LocalTcpRtt.ps1. Работа обновлённого приложения и HTTP prepare наблюдаются через действия пользователя; агент не выполнял build/HTTP/runtime. Следующий шаг USER ADMIN: powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\src\ProxyBridge-TestLab\scripts\Invoke-PlannedBenchmark.ps1 -PlanId plan-fff18fedae1a40fd828b1b6482180f9a -Phase Run (1–3min). Это первая проверка связки UI plan→контроллер, не новая серия сравнения версий. Runtime/boot/cleanup новых данных пока не подтверждены; автоматическую перезагрузку/запуск не выполнять. Receipt ui-observation.json в artifacts/diagnostics/lab-launch-preparation-20261004. GPT-6.1 Sol/high.


## Подготовка запуска из лаборатории (2026-10-04)

Пользователь показал сохранённый выбор driver после обновления страницы: files recognition/save/load наблюдаются через UI. Добавлена «Подготовить запуск» RU/EN и POST /api/v1/lab/prepare с existing CSRF/origin. BenchmarkLaunchPlanService читает DPAPI-сохранённый request, повторяет files-only inspect, разрешает только исходный известный driver kit; unknown/relocated/4.0.0/remote возвращают явный BLOCKED, без fallback на oldsettings. Замороженный plan-<guid>.json содержит controller/entry/env/bundle SHA, scenario/profile, runtime_ready=false. Перед показом команды выполняется только Invoke-PlannedBenchmark.ps1 -Phase Inspect.

Explicit USER admin -Phase Run (agent НЕ запускал): повторно проверяет план/комплект/контроллер/env, требует boot позже сохранённой активности4.0.0 (включая FAILED lifecycle/transfers), scoped mutex для этого entrypoint; затем отдельный PS5 process с собственным ModulePath и неизменённым контроллером/EnvPath/новой evidence-папкой. Это не global lease/switch proof; внешний запуск продуктов не покрывается историей. TCP transfer/RTT/loadedRTT =SMOKE, TransferOnly для данных, ProxyNoDelay для loaded; UDP MULTI_TARGET+BUFFERED, известные correctness ограничения явно описаны. Original controllers/Core/driver/helpers/evaluators не менялись. Нет автоматического фонового запуска, отмены/прогресса через новый экран; результаты новых local runs пока не подключены к UI истории A/B. Полный automatic UI runner/4-preflight/remote/custom candidates остаются следующим этапом.

Actual four frozen validation-metadata plans через PS5 child с inherited PS7 modules: PLAN_FILES_VALIDATED, product_started/traffic/driver_observed=false. Это проверка entrypoint Inspect, не HTTP вызов C# service. PS5 parsing/execution, Node syntax, C# Roslyn syntax (не build),25 HTML ids/JSrefs passed; receipt artifacts/diagnostics/lab-launch-preparation-20261004/validation.json. Unit autotests/build/HTTP/product/driver probes/install/cleanup/reboot/subagents/commit/push не выполнялись.

NEXT USER: остановить текущий UI Ctrl+C, dotnet run --project C:\src\ProxyBridge-TestLab\ui\ProxyBridge.TestLab.Ui\ProxyBridge.TestLab.Ui.csproj -- --RepositoryRoot C:\src\ProxyBridge-TestLab, Ctrl+F5 /lab.html. Сохранённый driver → local → TCP RTT → Подготовить запуск. Сообщить outcome/build errors; пока не выполнять полученную benchmark command и не повторять успешные A/B. HTTP preparation/runtime bridge pending until actual user result. GPT-6.1 Sol/high.


## Исправление проверки файлов из UI (2026-10-04)

UI показал все три компонента UNREADABLE с корректными размерами. Воспроизведено через .NET ProcessStartInfo с унаследованным PS7 PSModulePath: WindowsPS5.1 не находит Get-FileHash. Inspect-ProductSelection.ps1 теперь явно загружает Utility из собственного PSHOME, не меняя общий ProductBuild или окружение приложения. Добавлен FILES_UNREADABLE и отдельное сообщение RU/EN. Оба комплекта через тот же дочерний запуск теперь KNOWN_BENCHMARK_FILES/files_observed=true/runtime_ready=false, exit0; PS AST и Node syntax passed. Только чтение файлов, без сборки/ProxyBridge/трафика/проб драйвера. Receipt: artifacts/diagnostics/lab-inspector-module-path-20261004/validation.json. Следующий шаг пользователя: Ctrl+F5 в /lab.html, Проверить файлы → Выбрать комплект → Обновить. HTTP/DPAPI roundtrip остаётся неподтверждённым до результата пользователя. GPT-6.1 Sol/high.


## Текущая точка: первый экран лаборатории RU/EN и выбор файлов комплекта подготовлены (2026-10-02)

Новый /lab.html в существующем .NET UI: Подключение → Тестирование → Проверка и запуск → Результаты; RU/EN с сохранением языка в браузере. Папка ProxyBridge/driver или4.0.0/необязательный отдельныйdriverpath; meaningful TCP transfer/RTT/loadedRTT/UDP scenarios, local/remote SOCKS5 choice/onlycontrolledreceiver. Старый технический интерфейс/index.html остаётся; ссылка на новый экран добавлена в navigation. Переведён новый экран, старый advanced UI пока English. История показывает actual saved version transfer+RTT metric tables, без хешей/сырыхлогов/путей в общем итоге; исторический4normalcloseFAIL остаётся предупреждением. Старые отчёты не относятся автоматически к выбранной теперь установке.

New scripts/Inspect-ProductSelection.ps1 реиспользует ProductBuild.psm1+Env.psm1: только чтение файлов; no CLI/product/bootstrap/service/boot/traffic probes. Localabsolute paths/no reparse/64MiB componentlimit. Expectedhashes не выдумываются: filesobserved/fingerprint отдельно от provenance/compatibility/runtime. MatchCLI/Core/driver(orWinDivertDLL+SYS)knownselectedbaseline fingerprints→KNOWN_BENCHMARK_FILES; unknowncandidate→FILES_OBSERVED_COMPATIBILITY_PENDING. Неполные/observedpre4 metadata не сохранять. ActualPS5.1 оба existingkits matched; runtime_ready=false/product_started=false/traffic_generated=false/driver_state_observed=false.

New BenchmarkLabService +GET/api/v1/lab/state/POSTinspect-select использует existing loopback/origin/CSRF; запускает только files-only helper через ProcessStartInfo.ArgumentList/no shell с30sdeadline. Выбор сохраняется отдельно benchmark-selection.dpapi под текущим Windowsuser, pathvalues не возвращаются в API, исходные/oldsettings-runner inputs не меняются. Сохранённая observation не считается свежей readiness; перед будущим запуском нужно перепроверять. ActualDPAPI APIroundtrip ещё не выполнен. Read-only savedreport projection ограничен knownTCP comparison roots, completeLIMITED/errors[]/boundedJSON/numericfields, одинаковыеsourcepairsdeduplicated; no source reevaluation/traffic when displaying history.

Запуск новых benchmarks из экрана пока НЕ подключён (automatic_benchmark_available=false). Это первый source integration slice, не готовыйвыпуск и не совместимость произвольного installedkit. Перед подключением сохранять existing preflight/route-PID/nativeoptions/data/PC/cleanup/rebootbetweenversions gates; unknowncandidate не обходить. Бенчмарки и method/controllers/Core/drivers/native/helpers не изменялись,651 sourceSHA предыдущегоA-B unchanged. Старые успешные серии не повторять.

Проверено: actualPS5.1 files-only2kits; PS5.1+7Parser/BOM; NodeJSsyntax; C#RoslynParseText syntax (НЕ build/semanticcompile);21uniqueHTMLids/literalJSreferences. SDK10.0.401 directory observed. Сборку/запуск UI/HTTP/visual/DPAPI save-roundtrip агент не выполнял. Validation artifacts/diagnostics/lab-ui-selection-20261002/validation.json; actualobservations artifacts/product-selection-driver-observation.json +product-selection-legacy-observation.json. No agentbuild/install/autotests/subagents/commit/push/reboot/cleanup/PBtraffic/driverprobes.

Следующий USER ручной запуск .NET UI (команда собирает изменённый UI), без перезагрузки; продукт/бенчмарки не запускать:

```powershell
& "C:\Program Files\dotnet\dotnet.exe" run --project "C:\src\ProxyBridge-TestLab\ui\ProxyBridge.TestLab.Ui\ProxyBridge.TestLab.Ui.csproj" -- --RepositoryRoot "C:\src\ProxyBridge-TestLab"
```

Открыть http://127.0.0.1:5178/lab.html. Проверить переключение RU/EN и историю; для firstcheck выбрать driver+папку C:\src\ProxyBridge-TestLab\artifacts\product-builds\driver-63be0eb-testlab-cli или4.0.0+папку C:\src\ProxyBridge-TestLab\artifacts\product-builds\v4.0.0-release-testlab-cli, Проверить файлы→Выбрать комплект→Обновить (DPAPI сохранение). Сообщить результат/ошибки сборки. Дальше — исправитьactualUIissues иподключить запускexistingcontrollers/selectedkit с прежними gates. Remote/highmixedlongloads/пакетдлядругихWindowsusers остаются; customGitHubvalidation AFTERlabready. GPT-6.1 Sol/high.

## Предыдущая точка: сравнение передачи 4.0.0 / driver подтверждено (2026-10-02)

Пользовательская 4.0.0 серия tcp-socks5-4.0.0-data-standard-20261002-165457-053fdb COMPLETED/12MEASURED/errors[],24GiB/12GUID, LIMITED_COMPARISON/errors[]. Создан saved-data-only src/pb_tcp_version_transfer_report.py; итог artifacts/version-comparison/tcp-transfer-4.0.0-driver-20261002-165457-053fdb LIMITED_VERSION_COMPARISON/errors[]. Все24 actual readonly evaluations обеих серий совпали с originals/aggregate;322legacy+329driverfiles SHA unchanged,24uniqueGUID/48GiB.96ownedworkers naturalexit0/unforced/outputcapture;12CLIready/graceful/poststop/capture/noerrors. Сохранённые scoped interception/routePID/nativeoptions/ownedTCPsocket/PC/cleanup gates passed; нет свежих agentprobes/globalcleanup/automaticversion-switch proof.

Проверены одинаковая VM/OS, новая загрузка4.0.0 boot16:37:42.4713860Z строго после завершенияdriver16:21:56.2013114Z, точная rootreference на исходнуюdriverSTANDARD, sourcefingerprints/kitreceipts/Core+drivers unchanged/commonCLIadaptation/profileconstraints/tools/trafficsettings/3counterbalancedpairsdirection. PCcoverage>=98.655897%legacy/98.603973%driver. Исходные контроллеры/оценщики/Core/драйверы/native/helper в этом шаге не изменялись; новый агрегатор отдельно сохраняет готовый отчёт, не переписывает оригиналы. Python syntax + фактический CLI агрегатора + сохранение sourceSHA проверены. Нагрузку агент не запускал.

| Метрика | 4.0.0 | driver |
|---|---:|---:|
| Upload OFF / PROXY, Mbit/s | 538.318 / 537.593 | 538.368 / 538.132 |
| Download OFF / PROXY, Mbit/s | 538.486 / 538.014 | 538.385 / 529.998 |
| Paired change upload / download, % | -0.134581 / -0.087686 | -0.046988 / -1.573346 |
| CLI CPU upload / download, % wholePC | 7.151887 / 3.744270 | 0.197088 / 2.271764 |
| CLI private RAM upload / download, MiB | 2.446297 / 2.411300 | 2.722125 / 2.749968 |

driver PROXY относительно4.0.0 PROXY: upload+0.100235%,download-1.490051%. Это отношение медиан скоростей, отдельно от медианы изменений внутриOFF/PROXYпар. Разбросdownloadpaired: driver-3.358672…+0.003133%;4.0.0-0.103335…-0.059511%. Не приписывать разницу или разброс исключительно драйверу. Темп ограничен64MiB/s/2GiB/одно соединение, socketqueryoverlap/noexcludedwarmup; максимум производительности не измерен. Один порядокdriver→4.0.0 между загрузками VM, фон мог меняться, baselineOFFlegacy сохраняет idleWinDivert. CLI CPU/RAM не включают стоимость kerneldriver/всего продукта/ватты. RTT/длительная устойчивость/remote/highconcurrency не следуют из этой серии.

Обычное закрытие TCP здесь не проверяется (stock rude, verify:data): прежние4.0.0 closeFAIL сохранены, исправление не объявлять. Ранее failed163846 firstOFF до nativeStart из-за callbackscope остаётся отдельным FAILED; исправленный standalonecontroller фактически успешно завершил новую серию. Старые RTT и другие условия не повторять/не объединять.

Следующий приоритет: выбор установленной версии4.0.0+ и связка проверенных контроллеров/отчётов с простым UI RU/EN. Удалённый controlledreceiver, много потоков/смешанная/длительная нагрузка и упаковка остаются. Лаборатория ещё не готовый выпуск; пользовательская GitHubсборка AFTERlabready. Для этой завершённой серии новая команда/перезагрузка не нужна; перед следующим driver продуктовым запуском нужна перезагрузка после4.0.0. GPT-6.1 Sol/high. No agenttraffic/bootprobe/build/install/autotests/subagents/commit/push/reboot/cleanup.

## Предыдущая точка: исправлен запуск генератора при вложенном вызове; повторить только 4.0.0 STANDARD (2026-10-02)

Подготовка пользователя успешна: lifecycle legacy-lifecycle-20261002-163838-a2e57b и idle legacy-idle-20261002-163841-20aeb9, boot16:37:42.4713860Z. Первый OFF tcp-socks5-4.0.0-data-standard-20261002-163846-e71bb3 остановился до nativeStart: GetNewClosure не сохранил переменные скрипта при вызове контроллера из preflight, путь генератора оказался пуст. Это ошибка TestLab, не результат ProxyBridge. Генератор не запустился, клиентские файлы отсутствуют; receiver13512 принудительно остановлен после15s ожидания соединения, proxy11116/sampler9824 естественно завершились0. Исходный FAILED сохранён. Сохранённые scoped наблюдения: WFPdetached/compatibleWinDivert0/idleWinDivert64 остаётся; глобальная очистка не доказана, свежих probes агент не делал.

Исправлен только controller:14 входных переменных явно перенесены в локальную область до GetNewClosure; пустой executable теперь вызывает понятную ошибку. На фактическом AST плана метаданными воспроизведена потеря пути и подтверждено исправление в PS5.1+7: путь, stock rude/verify:data/2GiB64MiB/s/timeout и owned-socket gate сохранены. Parser/BOM проверены. Полный исправленный runtime ещё не выполнен; Core/driver/native/helper/evaluators/preflight/методика unchanged. 329 source driver SHA подтверждены,18 исходных файлов failed серии сохранены;38 успешных оценок прошлого шага повторять не требовалось. Анализ и validation: artifacts/diagnostics/tcp-callback-input-scope-20261002-163846.

Следующий шаг USER ADMIN на текущей загрузке Windows, около10–15мин. Не перезагружать, не повторять wrapper/lifecycle, не Resume исходный FAILED. Новая папка серии создаётся автоматически:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-LocalTcpBenchmark.ps1" -Profile STANDARD -ProductContract v4.0.0 -TransferOnly -LegacyIdleDirectory "C:\src\ProxyBridge-TestLab\artifacts\version-comparison\preflight-20261002-114842-637268\legacy-idle-20261002-163841-20aeb9" -DriverTransferDirectory "C:\src\ProxyBridge-TestLab\artifacts\local-route\tcp-socks5-driver-data-standard-20261002-161431-bebe37"
```

12×2GiB передаются в памяти, без payloadfiles/ETL. После результата — проверка фактической4.0.0 серии и агрегация версий; не повтор RTT. Перед возвращением к driver нужна новая перезагрузка. GPT-6.1 Sol/high. No agent producttraffic/bootprobe/build/install/autotests/subagents/commit/push/reboot/cleanup; originals preserved, historical4normal-closeFAIL отдельно.

## Предыдущая точка: 12 driver STANDARD подтверждены; подготовлена эквивалентная 4.0.0 серия (2026-10-02)

Actual driver tcp-socks5-driver-data-standard-20261002-161431-bebe37 COMPLETED/12MEASURED/errors[], LIMITED_COMPARISON/errors[].24GiB/12uniqueGUID, all actual readonly evaluations exactsaved+aggregate,329originalfiles unchanged. Same successfuldriverSMOKEboot16:01:18.1485980Z/kitpreflight/tools/profiles/legacy+driverSMOKE sourcebinding confirmed. Fourworkers/run naturalexit0/unforced/outputcapture;6CLIready/graceful/poststop/clean. Saved idle knownnamesabsent/compatibleWinDivert0/WFPdetached/active selecteddriverRunning/WinDivert0/othernamesstable, scopedonly/globalfalse/noagentcurrentprobes. PCcoverage>=98.60397275%. UploadOFF/PROXYmedian538.368249/538.132159Mbit/s;pairedmedianchange−0.046988% (range−0.072024…+0.025059). Download538.385120/529.997507;pairedmedian−1.573346% (range−3.358672…+0.003133). CLIcpu median0.197088/2.271764%wholePC/private2.722125/2.749968MiB. Distinguishpairedmedianchange frommode-mediandifference. Capped64MiB/s/2GiB oneconnection/3pairs; socketqueryoverlap/noexcludedwarmup, no ceiling/pureProxyBridgecost/driver-only/watts/RTT/leakproof/longstability. NormalTCPcloseNOTchecked;4historicalcloseFAILretained; no attribution of download spread to onlydriver.

Existing controller now explicit legacy STANDARD -TransferOnly -DriverTransferDirectory <driverSTANDARD> +freshLegacyIdleDirectory, noResume/diagnostics. Equivalent12×2GiB64MiB/s/stockctsTraffic rude verifydata/buffer65536/baseSOCKSSelector/oneconnection/3counterbalancedpairs. Newstage transfer_data_standard_v1 + version_transfer_stage data-transfer-repeat-legacy-v1/transfer_profileSTANDARD/readinessfalse. Saved-data-only prepare_driver_repeat validates12actualorigverdicts+aggregate/order/GUID/conditions/boot/driverSMOKE+legacySMOKE chains/tools/kit/profile/currentbytes/fingerprints; rootdriver-transfer-reference.json exported. New4requires sameVM+OS andboot strictlyAFTERdrivercompleted16:21:56.2013114Z, successfulcurrentboot lifecycle/idle/knownWFPdetached/compatibleWinDivert0/sourceothernames stable. Usespinnedexistingpreflightv4-transferprofile/SHA/equivalentconstraints/currentlegacykit. NativeCIMactualoptions+QPCwindow/ownedTCPsnapshot/routePID/GUID/data/PC/worker+CLI gates retained, active exactownedNETWORKWinDivert1/idle0; legacy neverDriverbootstrap/SCMstop/GUI. Basehelper/Core/driver/native unchanged. Evaluators optinvalidate2GiB64cap/3pairs/12complete/data-only/rude/profile/context/source+reboot binding; version_reference_bound but version_comparison_readyfalse. Olddefaults/SMOKE/Resume/diagnostics/source schemas unchanged, no originalrewrite or pooling. SummaryRUENstatesinstrumentedcappedOFF-PROXY4only/versionaggregationpending/historicalcloseFAIL.

New existingpreflight phase LegacyTransferComparison -DriverTransferDirectory <driverSTANDARD>, USERADMINsinglecommand afterreboot. Files/sourcebind/rebootguardBEFOREproductaction, samefrozenpreflight directory automatic. Calls existing LegacyLifecycle→LegacyIdleObservation once thennewSTANDARDcontroller/createduniqueidle. No LegacyTransferReadiness/defaultgraceful/extraSMOKE; no automaticreboot. Kit/source/safeidle failstops, no cleanup workaround. Runtimepending: new4STANDARD/phasechain/notexecutedbyagent; actualversionaggregationprepare aftersaved4result. About10–15min/24GiBmemory/nopayloadfiles/noETL.

Checks: PS5.1+7AST/BOM/PythonAST passed;38actualsavedevals exact (12driverSTANDARD+4driverSMOKE+4legacySMOKE+18old),329driverfiles andoldhistories unchanged. NormalPS5.1 -File files-only sourceJSON→legacykit/profile/preflightbindingpassed. Finaltinyreboot-marker additions ASTchecked; no redundant fullrecheck. Analysis/reference/validation at artifacts/diagnostics/tcp-driver-data-standard-review-20261002-161431. No agent producttraffic/bootprobe/build/install/autotests/subagents/commit/push/reboot/cleanup. Selectedbaseline63be0eb (upstreamHEADconfirmed11:36UTC), customGitHubvalidation AFTERlabready.

Next USER rebootWindows, thenADMIN firstProxyBridgeaction:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-VersionComparisonPreflight.ps1" -Phase LegacyTransferComparison -DriverTransferDirectory "C:\src\ProxyBridge-TestLab\artifacts\local-route\tcp-socks5-driver-data-standard-20261002-161431-bebe37"
```

Send consoleoutput/resultsaftercompletion. Next GPT-6.1 Sol/high. Before switching back todriver another reboot mandatory.

## Предыдущая точка: driver data-only SMOKE подтверждена; подготовлены повторные переносы (2026-10-02)

Пользовательская tcp-socks5-driver-data-smoke-20261002-160209-ca7a6a COMPLETED/4MEASURED/errors[], LIMITED_COMPARISON/errors[]. Четыре source evaluations совпали с originals/aggregate,112 исходных файлов unchanged; legacy source4 reevaluations/fingerprints109 также verified.256MiB/4uniqueGUID/upload+download OFF/PROXY/nativeSucceeded/data verification/owned route+socket PID-path-liveoptions/PC/cleanup passed. Boot16:01:18.1485980Z sameVM+OS строго после legacy completed15:39:04.7629978Z, prepared kit/profiles/receipt/tools matching. Fourworkers/run naturalexit0,2CLIclean; idle known loaded absent/WFPdetached/compatibleWinDivert0, active selecteddriver/SCMRunning/WinDivert0, othernamesstable. Saved scoped observations only, no fresh agent probes/global/version_switch_readyfalse. PCcoverage>=95.444100%. UploadOFF/PROXY67.864/67.907Mbit/s;download67.872/67.855. CLIcpu0.068329/0.373780%wholePC/private2.753906/2.730469MiB. Capped64MiB8MiB/s/socketquery454–2463ms overlaps/1pair, no ceiling/exact cost/version speed A-B/RTT/stability/watts/driver-only. NormalTCPclose notchecked; historical4closeFAIL notfixed/nodriverfailureinferred.

Prepared existingTCPcontroller new explicit driver STANDARD -TransferOnly -DriverSmokeDirectory <completeddriverSMOKE>, fresh/noResume/no diagnostics. Three counterbalancedpairs per direction/12runs/2GiB each/64MiB/s/oneTCPconn/65536buffer/verify:data/stock shutdown:rude.24GiB transferred in memory, no payload files/ETL. About8–12min; native120s/helper180s unchanged. Same successful driverSMOKE boot required (no reboot now), current selectedkit/preflight/legacyreference/driverSMOKE sourcefingerprints/alltools/profileconstraints verified, pinned driver-transfer.pbprofile. Allbefore-active-after/interception/owned route+liveTCPsocket/CIMoptions/dataGUID/PC/worker+CLI cleanup gates retained. Longer whole-transfer rates remain rate-capped/instrumented/socketqueryoverlap/no excludedwarmup, notmaxcapacity/pureoverhead orversioncomparison. New config transfer_profileSTANDARD/version_transfer_stage data-transfer-repeat-v1; root driver-smoke-reference.json +legacy-transfer-reference.json/currentcontext bound. Evaluators distinguish repeated/readiness_onlyfalse vs unchanged SMOKE; exact2GiB64cap/3pairs/12complete/rude/normalclosefalse/nodiagnostics/sameconditions mandatory. New stage driver-only until actualseriesreview; 4.0.0 STANDARD/paired aggregation notimplementedyet. Olddefaultgraceful/Resume/legacydiagnostics/Core/driver/native/basehelper untouched; no pooling oldSMOKE timings. No auto reboot/productpatch.

Verification: PS5.1+7AST/BOM/PythonAST passed;26 actual saved evaluations unchanged (4driver+4legacy+18otherprior), bothkitbytes/receipts/profileconstraint/tool hashes checked. WindowsPS5.1 normal-File files-only JSONreference→kit/profile/repeatparameters passed; boot/interception gates awaitmanualruntime. No producttraffic/bootprobe/build/install/autotests/subagents/commit/push/reboot/cleanup byagent. Analysis/reference/validation at artifacts/diagnostics/tcp-driver-data-smoke-review-20261002-160209.

Next USER ADMIN WITHOUT reboot on same driver boot, approximately8–12min:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-LocalTcpBenchmark.ps1" -Profile STANDARD -ProductContract driver -TransferOnly -DriverSmokeDirectory "C:\src\ProxyBridge-TestLab\artifacts\local-route\tcp-socks5-driver-data-smoke-20261002-160209-ca7a6a"
```

After actual driver STANDARD review prepare equivalent4.0.0 STANDARD +newboot/explicitLegacyLifecycle→LegacyIdleObservation/driverrepeat sourcebinding, then saved-data aggregation. Do not blindly invoke old LegacyTransferReadiness (default graceful close remains failed), repeat oldsuccessfulSMOKE/RTT, pool olddifferentfixtures, or issue an unprepared4STANDARDcommand. CustomGitHub driver validation remains AFTERlabready. Next model GPT-6.1 Sol/high.

## Предыдущая точка: 4.0.0 передала данные; подготовлен связанный запуск driver (2026-10-02)

Пользовательская серия tcp-socks5-4.0.0-data-smoke-20261002-153812-13ecce COMPLETED: четыре MEASURED/errors[], 256 MiB полезных данных, четыре уникальных GUID, upload/download OFF/PROXY. Все четыре readonly оценки совпали с originals; 109 исходных файлов неизменны. Сохранённые owned route/socket/native PID-path-options/data verification подтверждены; четыре workers/run natural exit0, два CLI ready/graceful/poststop/output capture/без cleanup errors. WinDivert handles до/после0, WFPdetached, idle WinDivert64 retained; scoped saved observation, не global cleanup/current probe. PC coverage ≥96.404889%. Upload OFF/PROXY67.915/67.812 Mbit/s, download67.855/67.864; CLI CPU1.313665/0.674966% всегоПК, private RAM2.449219/2.480469MiB. Это64MiB8MiB/s короткий rate-capped перенос, не capacity/точная стоимость ProxyBridge/driver-only/watts/RTT/длительная стабильность. Socketquery overlaps transfer507–2206ms, нельзя делать точный speed A/B по этой серии. Normal TCPclose НЕ проверено; исторический FAIL4.0.0 остаётся предупреждением, исправление не заявлено.

Existing Invoke-LocalTcpBenchmark.ps1 новый opt-in driver -TransferOnly -LegacyTransferDirectory <эта серия>, freshSMOKE/noResume. Новый saved-data-only pb_tcp_transfer_reference.py повторно проверяет4actual verdicts+aggregate/order/conditions/source fingerprints, preflight+idle/receipt chains/product bytes, эквивалентные prepared profiles/включённое logging/SOCKS constraints. Скрипт требует same VM/OS + boot строго ПОСЛЕ completed_at legacy; driver kit bundle/commit/build receipt и все tools hashes match source. Перед/после no known interceptors/совместимых WinDivert handles0/WFPdetached/othernames stable; active selected driver/SCM Running/WinDivert0. Driver копирует pinned preflight driver-transfer.pbprofile; liveCIM/native options + owned socket query как у4.0.0, dataGUID/route/PC/clean workers/CLI исходные gates. Reference/context/config/manifest binding rechecked в evaluator, version_reference_bound, readiness_only/version_comparison_readyfalse. SummaryRU/EN говорит о readiness с запросом сокетов во время передачи; никаких version speed claims/нормальногоFINpass.

PS5.1+7AST/BOM/PythonAST passed;22actual saved evaluations exact originals (4new+18old). Actual normal WindowsPS5.1 -File files-only reference JSON→kit/profile validation passed. Дополнительная Python-spawned encoded PS probe не разрешила Get-FileHash; её не считать file identity evidence, successful normal -File проверка сохранена отдельно. Core/driver/native/basehelper unchanged, default graceful/DriverResume/legacy/diagnostic schemas retained. New driver runtime pending, агент продукт/трафик/boot probes не запускает. No builds/installs/autotests/subagents/commit/push/reboot/cleanup. Analysis/reference/validation: artifacts/diagnostics/tcp-data-smoke-review-20261002-153812.

Следующий USER: перезагрузить Windows, затем ADMIN команда ниже (~2–4 минуты), первым запуском ProxyBridge после reboot. Перед этим не запускать другую версию. New tcp-socks5-driver-data-smoke-*; после результата подготовить повторное сравнение скорости, не объединять old graceful/rude diagnostics/readiness timings. Перезагрузку агент не выполняет.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-LocalTcpBenchmark.ps1" -Profile SMOKE -ProductContract driver -TransferOnly -LegacyTransferDirectory "C:\src\ProxyBridge-TestLab\artifacts\local-route\tcp-socks5-4.0.0-data-smoke-20261002-153812-13ecce"
```

Следующая модель: GPT-6.1 Sol / high.

## Предыдущая точка: подготовлена проверка передачи данных 4.0.0 и driver (2026-10-02)

Пользовательские названия версий: **4.0.0** и **driver**. Git ref upstream Driver/исторические файлы/внутренний contractv4.0.0 сохраняют технические имена. Пользователь выбрал исходную4.0.0 не исправлять и сообщил «Продолжай» после предложения общих условий передачи/отдельной корректности закрытия. Обычное закрытие4.0.0 остаётся известным FAIL в прежней серии; не переносить вывод наdriver и не продолжать patch/FINдиагностикуlegacy.

Existing Invoke-LocalTcpBenchmark.ps1 новый opt-in **-TransferOnly** для обеих версий: толькоfreshSMOKE/noResume/no diagnosticflags, 4runs upload+download/OFF+PROXY/1pairdirection/64MiB8MiB/s/oneTCPconnection/verify:data/originalbaseSOCKSfixture. ШтатныйctsTraffic shutdown:rude; данные/GUID/nativeSucceeded/routePID/PC/cleanup прежние. Реальный liveCIMsnapshot собственного nativePID/path подтверждает ровноshutdown:rude/consoleverbosity1/transfer64MiB/rate8MiB/verifydata доcompletewindow. Безфлага прежнийgraceful/default/DriverResume/diagnostics неизменны. НикакихизмененийCore/driver/native/helper. Новая4.0.0stage transfer_data_smoke_v1 сохраняет kit/preflight/idle/sameboot/profile/WinDivertactiveowned1/idle0/WFPdetached/socketobservation gates. Новый driver opt-in имеетsame64MiB8cap, обычныеexistingDrivergates; crossversionbinding/aggregation ещёНЕготовы, не выдаватьdrivercommandпреждевременнопереданализом4readiness.

New pb_tcp_data_scope.py/evaluator opt-in требуетpolicy data-transfer-only-v1/actualoptions. New results readiness_only/product_label4.0.0-driver/normal_tcp_close_verifiedfalse. SummaryRUEN сообщаетпроверкуданныхбезпроверкиnormalFIN; для4.0.0 показываетРАНЕЕнаблюдённыйcloseFAIL, observed_in_this_series=false/неисправленностьнепроверялась; driverfalseissueнеполучает. Manifest/per-run scope guard исключает смешение oldgraceful/rudediagnostic/data-only илинеполнуюсерию. Rates диагностические:shortcapped1pair/socketqueryoverlap4, notcapacity/versionA-B/ping/stability. Oldresults неpool. Existing failure notices canonical label4.0.0; implementations вJSONdetails допустимы.

PS5.1+7AST/BOM/PythonAST passed;18прошлыхactualsavedreadonlyevaluations exactoriginals/sourcefilesunchanged. Both preparedtransferprofiles identicalprocess/IP/port/SOCKSconstraints/SHA match; bothbuildreceipts+Corebytesselectedverified/4DLL-SYS match, basehelperBD3 unchanged. No new traffic/build/install/autotests/subagents/commit/push/reboot/cleanup byagent. Files-only validation artifacts/diagnostics/tcp-data-readiness-preparation-20261002/validation.json. New4fullupload+downloadruntime PENDINGUSER; actualnew policy unproven untilreceipt review.

Следующий USER ADMIN, БЕЗ reboot, та же4idleboot, около2–4мин:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-LocalTcpBenchmark.ps1" -Profile SMOKE -ProductContract v4.0.0 -LegacyIdleDirectory "C:\src\ProxyBridge-TestLab\artifacts\version-comparison\preflight-20261002-114842-637268\legacy-idle-20261002-115842-0db06f" -TransferOnly
```

Новаяпапка tcp-socks5-4.0.0-data-smoke-*, четыре прогона. Прислатьполныйвывод/ошибку. Это4.0.0vsdirectreadiness, НЕversioncomparison; success uploadalone неdownloadproof. Послеactual4 readiness подготовить повторяемуюtransfer/versionseries скоммонусловиями/новымboot driver/profilebinding; reboot междуверсиями, oldDriverseriesнеpool. СледующаямодельGPT-6.1 Sol/high.

## Предыдущая точка: 4.0.0 с WinDivert не исправляем; добавлено пояснение в итоги (2026-10-02)

Пользователь уточнил, что дефект относится к 4.0.0 с WinDivert, и выбрал сохранить продукт без изменений и уведомлять пользователя в итогах. Это дефект логики закрытия ProxyBridge4, не доказанный дефект WinDivert; вывод не переносить на Driver. Дальнейшую диагностику/patch/build legacy ради этого отказа не делать. Неподтверждённые планы автора не включать как факт в UI.

Добавлен pb_tcp_close_notice.py, вызываемый существующим TCP controller только после сохранения failed legacy receipt и cleanup, перед прежним throw. Формирует known-problems.json/md на RU/EN; исходный FAILED/10054 сохраняется, data delivery отделена от close correctness, speed comparison false. Условие:4.0.0/PROXY/graceful/verifiedproduct/dataGUID/fullreceiverSucceeded/receiver0/client1-10054. Если native verbose подтверждает GracefulShutdown→RequestFIN/10054, close correctness FAILED. Без этапного журнала показывает сброс после данных и историческое известное ограничение4.0.0; exact close phase NOT_CONFIRMED, не выдумывает атрибуцию. Successful/rude/Driver не получают ложную текущую ошибку. Ошибка создания пояснения не подменяет исходный отказ. Обычные настройки передачи/закрытия, verdict gates, Core/driver/native/fixture/evaluators не изменены.

Текущий сохранённый вывод: artifacts/diagnostics/tcp-close-metadata-20261002-145446/user-results/known-problems.md +json; оригинальный run каталог31файл SHA unchanged. Проверка пяти реальных saved runs: три verbose graceful FAILED notice, обычный короткий журнал NOT_CONFIRMED, rude-success no notice. PS5.1+7AST/BOM/PythonAST passed, notice-validation.json. Нового продуктового запуска/автотестов/build/install/subagents/commit/push/reboot/cleanup нет. Fresh failure output integration с печатью пути ещё не проверялась новым runtime, без причины не повторять только ради сообщения.

Следующий рабочий этап — продолжить лабораторию на исходных4.0.0/Driver и реализовать сопоставимую методику скорости с отдельной проверкой обычного закрытия; конкретная ordinary rude методика в коде пока не реализована и в этом изменении не переключена. Нового runnable comparison command сейчас нет; сначала подготовить изменения. Driver branch remains63be0eb; перед сменой версии reboot. Фактическая цепочка неправильного порта ACK/FIN/RST сохранена в предыдущем checkpoint и analysis. GPT-6.1 Sol/high.

## Предыдущая точка: подтверждены неверный порт ACK/FIN и цепочка сброса 4.0.0 (2026-10-02)

Пользовательский metadata run tcp-socks5-v4.0.0-graceful-diagnostic-smoke-20261002-145446-fbf36e FAILED/TCP_CLIENT_FAILED, client2284 RequestFIN/10054; receiver7368 проверил64MiB/GUID127401b5-6506-4691-adb7-6b23c25ab26c. Native61591→54122, relay34010. Положительные парные записи priority124→122 (IPID/seq/ack/flags/IP/length совпали): первый FIN1423 перенаправлен54122→34010; возврат ACK1424/FIN1425 остался34010→61591, порт54122 НЕ восстановлен. Два RST1427/1428 от61591 к34010 имеют seq358188826=ACK неверных сегментов. Повтор FIN1436 с той жеseq/ack снова перенаправлен; RST1437 уже переписан34010→54122 и seq3964601425 соответствует ожидаемойsequence клиента. ACK инициировал первый RST ещё до доставки неверногоFIN. Это observed port-restoration defect на закрытии, не только гипотезаEOFfixture.

PinnedCore4 source975–976 восстанавливаетпорт толькоget_connection;997–1001 удаляетmap+portstateприFIRSTFIN/RST;1108 сноваadd_connectionдляPROXYpacket. Это объясняет запись неправильных ответов и восстановлениепоследнегоRSTпослеретрансляцииFIN. Нет memory/instructiontrace/patchedproductfixproof/independentbuildproof. Core/WinDivertSYSselectedreleasebytes SHA match; unchangedhelper/evaluator/controller/collector SHA verified. SD_BOTH relay — отдельныйhalfclose risk, ещёнепроверенныеальтернативныесценарии. Предлагаемыйproductfix: сохранитьmappingчерезFIN/ACK/retransmits до terminalcleanup, boundedexpiry/reuse/SYN, неоставлятьбессрочныеentries. ProductНЕпатчитьвэтойзадаче.

Helper8088 flow10 UPSTREAM61561→54122/DOWNSTREAM54123→61560 2write_eof+finished; егоspecificfixнеснялCoreошибку. Collector12920 2ownedflags21priority124/122/CLI14364ownedflags0priority123 confirmed; each16209received/2094saved/68critical/ACKtailoverwrite14161.2159089bytes≈2.06MiB, noerrors/filelimit/critical-limit, queue-lossunknown/ACKpartial/no absenceproof.4workers naturalexit0/unforced/collectorSTDIN_STOP+handlesclosed; CLIready-graceful-poststop-capture/cleanupempty/exitNOTstoredfailure-schema. Savedbefore-afterhandles0/WFPdetached/idleWinDivert64only/globalfalse;31sourcefilesunchanged/routeexportabsentnotfabricated. Analysis+ownedheaders+sourcefragments+validation: artifacts/diagnostics/tcp-close-metadata-20261002-145446.

ВлияниеEOF/Corefixнаspeedнеизмерено, metadata timings неbenchmark. ЧтобысравнитьОРИГИНАЛ4.0.0сDriver, предложенаОДИНАКОВАЯnativectsTraffic shutdown:rude/dataGUID/route/PC/cleanup методика OFF/4/Driver сsamefixture/freshseries, а «Штатное завершение TCP» — separate strictcorrectness; nativefailure остаётсяFAIL, productpassневыдумывать. Это не измерение normalFIN/capacity, closed/openedconnectionoverheadотдельныйscenario. НовыйисправленныйCoreбылбыновойсборкой, baseline4сохранить. Ordinaryrude метод по-прежнему НЕ принят/НЕ реализован.

Пользователю задан один вопрос выбора: исходные версии со скоростью и закрытием отдельно (рекомендуется) либо сначала проверить отдельную исправленную сборку4.0.0. Зависимая реализация benchmark/fix и новый runtime command ждут выбора; диагностическийанализ завершён. Не повторять metadata/ETL/успешныеRTT/весьSMOKE/Lifecycle без новой причины. Нет команды запуска сейчас. Перед Driver reboot. No new producttraffic/build/install/autotests/subagents/commit/push/reboot/cleanup byagent; толькоsaveddata/docanalysis. GPT-6.1 Sol/high.

## Предыдущая точка: native сброс сохраняется после исправления EOF; подготовлена запись заголовков (2026-10-02)

Пользовательский tcp-socks5-v4.0.0-graceful-diagnostic-smoke-20261002-143244-0ff023 FAILED/TCP_CLIENT_FAILED. Client7160:64MiB/DONE/shutdown(SD_SEND)0 → RequestFIN/WSARecv10054; receiver8644 sameGUID/64MiB/Succeeded/exit0. Исправленный helper14468 flow5 действительно передал write_eof UPSTREAM59979→54122 и DOWNSTREAM54123→59977, BOTH_DIRECTIONS_FINISHED. Pinned SHA base/wheel/adaptation соответствуют. Этот fixture fix не устранил конкретный native сброс. Источник RST ещё НЕ доказан; early FIN/RST mapping removal и relay SD_BOTH в Core4 остаются кандидатами.

Readonly анализ artifacts/diagnostics/tcp-legacy-halfclose-result-20261002-143244/analysis.json+md:28исходныхфайлов unchanged. Receiver/proxy/sampler natural0/unforced; CLI10216 ready/graceful/poststop/outputcapture/cleanup_error empty. Failed lifecycle schema НЕ хранит CLI exit_code, не утверждатьexit0. Saved handles1ownedpriority123 active/0before-after/knownWFPdetached; не global/current cleanup. Route-observations отсутствует из-за failed lifecycle, не выдумывать full evaluator pass.

Новый opt-in -DiagnosticCloseMetadata только с -DiagnosticGracefulShutdown -DiagnosticHalfCloseFixture/explicit4/freshSMOKE/noResume. Отдельный pb_tcp_close_metadata.py использует уже выбранный DLLSHA/WinDivert2.2 ABI; пассивные SNIFF|RECV_ONLY|NO_INSTALL(21) NETWORK handles priorities124/122 вокруг product123. Не устанавливает/не инъецирует; filter IPv4loopback127.0.0.1/ports54122,54123,34010/SYN-FIN-RST-or-emptyACK. Содержимое пакетов не сохраняется. По512criticalSYN-FIN-RST и circular2048tail/priority, output ≤3MiB; overwriteACK явно указан, queue loss НЕ наблюдаем и отсутствие события не доказательство. Наблюдение имеет стоимость, НЕ benchmark.

Открытие только после неизменного active gate с одним CLI handle; новый отдельный interception-close-capture.json требует ровно3owned handles:CLIflags0priority123+monitorflags21priorities124/122. Snapshot до native Start, collector PID/SHA pinned config, watchdog150s/STDIN_STOP/drain/Close/natural worker cleanup до Assert-Off handles0. Ошибка native сохраняет FAILED; collector не делает graceful pass. Config/context/manifest marker passive_control_headers_v1; обычные default/Driver/Resume/evaluators/base helper/Core/driver/native неизменны. Ordinary rude метод по-прежнему НЕ выбран пользователем.

Проверено: PS5.1+7AST/BOM/PythonAST; DLL API layout80/filter compile offline (WinDivertOpen не выполнялся/handles0/driver runtime false). 18 прежних saved reevaluations ранее успешны; evaluator/fixture SHA неизменны, повтор без причины не запускался. Full passive capture integration PENDING пользовательского ADMIN запуска, agent не запускает PB/traffic/build/install/autotests/subagents/commit/push/reboot/cleanup. Влияние EOF fix на скорость ещё НЕ измерено; исправление стенда сопоставимо при одинаковой новой fixture для обеих версий, old results не pool.

Следующий USER ADMIN, БЕЗ reboot, same4idleboot, примерно1–2мин:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-LocalTcpBenchmark.ps1" -Profile SMOKE -ProductContract v4.0.0 -LegacyIdleDirectory "C:\src\ProxyBridge-TestLab\artifacts\version-comparison\preflight-20261002-114842-637268\legacy-idle-20261002-115842-0db06f" -DiagnosticGracefulShutdown -DiagnosticHalfCloseFixture -DiagnosticCloseMetadata
```

Прислать весь вывод даже TCP_CLIENT_FAILED: failure вероятен и нужен для анализа. Перед Driver reboot. Не повторять Lifecycle/весь SMOKE/ETL/успешные старые серии. GPT-6.1 Sol/high.

## Предыдущая точка: ограничение EOF в SOCKS fixture изолировано; проверить влияние на сброс 4.0.0 (2026-10-02)

Пользователь выбрал сначалаcause+влияниенасравнение, обычныйrude benchmark НЕвыбран. Bounded standalone networkcontrol БЕЗProxyBridge/CTS: pinnedwheel готовый SOCKSclient+unchangedhelper/selector/64KiBrequest+1028reply/2repeats/DIRECT-SOCKS/ответдо-послеEOF. KnownPB/CTSprocessesabsent+serviceStopped checked, nonglobal. Original6PASS/2FAIL, обаSOCKSreplyafterEOF0of1028; receivepayload+EOF подтверждены, directPASS. ReplybeforeEOF (=порядокCTS, неactualnative)2SOCKSPASS; найденноеfixtureограничение не является автоматическимобъяснением4.0.0CTSreset. Flowsownports correlated/4TCP/STDINSTOP/helpernatural0. Baseline artifacts/diagnostics/socks-halfclose-baseline-20261002-01.

Separate pb_tcp_halfclose_diagnostic.py reuses pinnedwheel `_copy` body/4096buffers/addon/counters unchanged; EOF-onlyadaptation write_eof/drain вместоwholeclose, обаsocketcleanup послеобоихdirections. Basehelper/wheel/SOCKSoptions/Core/driver/native unchanged. Fixtureadapted8/8PASS/8WRITE_EOF/4BOTH_FINISHED/ownPIDflow/cleanhelper0, artifacts/diagnostics/socks-halfclose-adapted-20261002-01. No code-autotest suite; actual boundedmanualnetworkdiagnosis alloweduser. CopyloopAST/sourceSHA/pinnedbase/wheel/launchers logged. No throughput/game/longloadproof.

Existingcontroller новыйflag DiagnosticHalfCloseFixture толькоcombinedDiagnosticGracefulShutdown/explicit4/freshSMOKE/noResume; isolatedstage transfer_graceful_halfclose_diagnostic_v1/configcontextmanifestfixtureRevision+launcherSHA/proxy-halfclose.jsonl. ТолькоодинPROXYupload64MiB8cap/verbosity6. ExistingdataGUID/nativeSucceeded/route/ownedTCP/kitboot/PC/cleanup gates плюсsameownhelperPID/sourceSHA/revision/2WRITE_EOF(up-down)+terminalsameflow. Diagnosticexcludedfromcomparisons/ordinarygracefuldefault/DriverResumeunchanged. PS5.1+7AST/BOM/PythonAST/18oldactualtransferreadonlyreevals exactoriginals. Nativeproductintegration pending, noProxyBridgeagentlaunch.

Сравниватьверсии послеfixturefix можноприодинаковомfixture обеим, separateordinaryclosecorrectness, старыеусловиянеpool. EOFизменение внеобычногоcopyloop, но effectonduration/CPU NOTMEASURED/zeroeffectнеутверждать. Сейчастолькоdiagnosticfix, ordinarydeployment/methodchangeнеприняты. Analysis/validation artifacts/diagnostics/socks-halfclose-investigation-20261002.

Следующий USER ADMIN **безreboot**, same4idleboot,1–2мин:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-LocalTcpBenchmark.ps1" -Profile SMOKE -ProductContract v4.0.0 -LegacyIdleDirectory "C:\src\ProxyBridge-TestLab\artifacts\version-comparison\preflight-20261002-114842-637268\legacy-idle-20261002-115842-0db06f" -DiagnosticGracefulShutdown -DiagnosticHalfCloseFixture
```

Sendfulloutputevenfailure. IfRequestFIN10054remains, thisspecificfixturefix неустраняетobserved4reset и Coreатрибуцияещёнужна. Ifpass, changehelpedbutonepassnotsolecause/stability/throughputproof. Do notfullSMOKE/Lifecycle/ETL/repeatoldsuccessfulseries. ПередDriver reboot. No newproducttraffic/build/install/autotests/subagents/commit/push/reboot/cleanup byagent; onlyprivatehelpernetworkdiagnosis/nohistoricaloverwrite. GPT-6.1 Sol/high.

## Предыдущая точка: подтверждён отказ в ожидании FIN; выбор методики ожидает пользователя (2026-10-02)

Уточнение после вопроса пользователя «Это дефект лаборатории?»: виновник не установлен. Readonly извлечён pinnedwheel server/tcp_relay.py: EOF→writer.close()/wait_closed, no write_eof; это ограничение half-close вSOCKS fixture, не доказанныйисточникRST. Core4 такжеSD_BOTH/earlyFINmapping candidate. Source copy+hash receipt втекущейdiagnosticпапке. Рекомендованный следующий путь — контрольSOCKShalf-close безProxyBridge до атрибуции/сменыметода; новыйruntime/скрипт/patch неготовились. Пользователь НЕсогласилсясrudemethod, задаётвопрос; pendingchoiceсохранён. No newtraffic/code/build/install/autotests/subagents/cleanup. GPT-6.1 Sol/high.

`tcp-socks5-v4.0.0-graceful-diagnostic-smoke-20261002-140504-a42ee8` FAILED/TCP_CLIENT_FAILED. Native CTS7712 журнал подтверждает порядок:64MiB → ClientRecvCompletion → GracefulShutdown → shutdown(SD_SEND) successful0 → RequestFIN → WSARecv10054. По pinned Microsoft state source переход ClientRecvCompletion означает проверку4-byteDONE. Этап ошибки теперь установлен: ожидание ответного закрытия после данных/DONE. Источник RST, wire rewriting/единственныйвиновник остаются неизвестны; Core earlyFINmap removal/relaySD_BOTH/helperclosure — кандидаты, не установленные причины.

Receiver6240 sameGUID/64MiB/Succeeded/exit0/RequestFIN→CompletedTransfer. Его успех не означает gracefulpass клиента (stockserver допускает некоторые terminal ошибки). SOCKS4976 owned64879→64880/receiver54122/up67108864down41; ownCLI9804→SOCKS socket matches flow/callbackCTS7712. Live launch PID/path/graceful/verbosity6 подтверждены. CLI9804 ready/graceful/poststop/capture/errorTCP_CLIENT_FAILED,3helpers naturalexit0; saved knownWFPdetached/compatiblehandles0/onlyidleWinDivert64 loaded. Не currentglobalcleanup proof. OriginalFAILED/28sourcefileSHAunchanged; missingroute-observations не выдумывали/fullsuccessful evaluator не запускали. Analysis artifacts/diagnostics/tcp-legacy-graceful-20261002-140504/analysis.md,json+validation.

Итого два graceful resets (обычный122627, verbose140504) и один успешный rude134918; режимы/времяразные, не статистическая доказанная solecause/fix. Повтор такой же диагностики/ETL не требуется для определения фазы.

Подготовлено конкретное предложение docs/TCP_TRANSFER_METHOD_PROPOSAL.md: correctness ordinarygraceful отдельно, сохранять FAIL текущегоclose дефекта и проверять исправление на новойверсии; ограниченный datatransfer benchmark отдельно в одинаковом stockrude режиме OFF/4.0.0/Driver со всеми прежними dataGUID/nativeSucceeded/ownedroute/PC/cleanup gates. Benchmark не включает ожидание ordinaryclose/не объявляет correctness PASS/не capacity. Первым после выбора подготовить fresh4.0.0 upload+download4×64MiB8cap readiness; затем эквивалентную repeated/versionmethod с учётом intrusive socketquery. Existing isolatedsuccess — НЕготовность download/A-B. Ordinarybenchmark/newSTANDARD/Drivertransfer НЕреализованы, прежний defaultgraceful сохранён.

Пользователю задан один вопрос через request_user_input_async: выбрать отдельный benchmark+closecorrectness (рекомендуется) либо сначала установить RSTorigin. **Ждать ответа на выбор методики; зависимую реализацию и новую runtimeкоманду пока не выдавать.** Анализ/документация завершены; никаких новых code/producttraffic/probes/build/install/autotests/subagents/commit/push/reboot/cleanup byagent. ПередDriver reboot, не повторятьLifecycle/fullSMOKE на этойidleboot. Histories/RTTA-B/cleanup сохранены. Следующая модель GPT-6.1 Sol/high.

## Предыдущая точка: rude-close upload прошёл; готов graceful с журналом этапов (2026-10-02)

Пользовательский `tcp-socks5-v4.0.0-rude-diagnostic-smoke-20261002-134918-1e6152` COMPLETED/одинPROXYpush/MEASURED/errors[]. Readonly оценка точно совпадает. CTS15220 и receiver2648 Succeeded/exit0/sameGUID/64MiB Connections&Data. Live CIM commandline/path/PID подтверждает ровно один shutdown:rude. SOCKS12712 up67108864/down41/ownedflow. CLI10196 ready/graceful/poststop/capture/noerror; receiver/proxy/sampler natural0/unforced. PCcoverage>=96.640563%; короткий capped темп не является A/B/capacity/RTT/driver-only cost. Saved WFPdetached/compatiblehandles0/known idleWinDivert only; не currentglobalstate proof.

Old graceful FAILED122627 сохранён. Config traffic/tools/product/route совпадают кромеstage/shutdown/diagnosticmarker/PIDs; запуски в разное время, новая диагностика содержит дополнительный liveCIMsnapshot. Успех rude поддерживает гипотезу завершающегоTCP handshake, но один run не доказывает повторяемость/единственную причину. Возможны original4.0.0 relaySD_BOTH/earlyFINmapping deletion либо взаимодействие с закрытием SOCKS helper. Native RequestFin в lowverbosity старомлоге не подтверждён, RSToriginunknown. Исправления Core/driver нет.

Added opt-in -DiagnosticGracefulShutdown: mutually exclusive with rude, explicit4.0.0/freshSMOKE/noResume/onePROXYpush64MiB8MiBcap, штатное graceful +ConsoleVerbosity6 наclient/receiver. Existing controller/stockCTS reused, никакихETL/нового генератора. Live ownCTS launchsnapshot подтверждает shutdown иverbosity; config/context/manifest отдельный transfer_graceful_diagnostic_v1/diagnostic_only/readinessfalse. StrictdataGUID/nativeSucceeded/ownedroute/kitboot/PC/cleanup прежние; успешный derivedreport требует debug completingGracefulShutdown(statusCode0), gracefulverified только при noerrors. Если ошибка повторится, FAILED/исходные stdout в client-process.json/receiver-process.json сохраняются, evaluator не выдумывает недостающие evidence. Diagnostic timings не агрегировать/не делать versionA-B; обычныйgraceful default/Driver/Resume/legacySMOKE/Core/driver/helpers/native unchanged.

Pinned Microsoft ctsConfig.h macro включает debug приConsoleVerbosity6, ctsIOPattern.cpp печатает завершения GracefulShutdown/Recv errors; actualverboseoutput ещё не получен. PS5.1+7AST/UTF8BOM/PythonAST passed; rude+newOFF+16oldDriver readonly evaluations exactoriginals (18total), sourcefingerprintsunchanged. Analysis/validation artifacts/diagnostics/tcp-legacy-rude-20261002-134918. Нового producttraffic агент не запускал.

Следующий USER ADMIN **без перезагрузки**, та же4.0.0boot/idle reference, около1–2мин:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-LocalTcpBenchmark.ps1" -Profile SMOKE -ProductContract v4.0.0 -LegacyIdleDirectory "C:\src\ProxyBridge-TestLab\artifacts\version-comparison\preflight-20261002-114842-637268\legacy-idle-20261002-115842-0db06f" -DiagnosticGracefulShutdown
```

Отправить полный вывод, включая вероятныйTCP_CLIENT_FAILED. Не повторять весьSMOKE/Lifecycle/неResumefailedroots. Если reboot уже была, oldidle должен быть отвергнут. После actualverboseanalysis определить следующий путь graceful correctness/ограниченногоbenchmark; ordinary rude method/standard4/versiontransfer пока не реализованы/не согласованы. Перед Driver требуется reboot. No agenttraffic/build/install/autotests/subagents/commit/push/reboot/cleanup, originals preserved/RTTA-Bpreserved/cleanupdone-norepeat. Следующая модель GPT-6.1 Sol/high.

## Предыдущая точка: legacy upload завершился сбросом; готова отдельная диагностика закрытия (2026-10-02)

Standalone SMOKE `tcp-socks5-v4.0.0-smoke-20261002-122627-74f35f`: OFF COMPLETED/MEASURED, PROXY FAILED/TCP_CLIENT_FAILED. Исправленный Qpc callback реально отработал. CTS client4556 отправил64MiB, exit1/WSAECONNRESET10054; receiver9556 проверил64MiB/sameGUID/Succeeded/exit0. Owned SOCKS flow14352: up67108864/down41, ERROR событий нет. Это наблюдение конца соединения, не успешная проверка клиентского протокола. Helpers receiver/proxy/sampler natural0/unforced, CLI7488 ready/graceful/poststop/outputcapturetrue/errorTCP_CLIENT_FAILED; saved WFPdetached/Stopped/compatiblehandles0/onlyidleWinDivert64/othernamesstable. Нового current-state/globalcleanup probe нет. Route-observations отсутствует из-за failure до штатного экспорта; callback есть в сохранённом CLI stdout, отсутствующий файл не выдуман. Failed manifest/CSV/logs сохранены.

Hypotheses: FIN/half-close relay/loopback map removal в4.0.0 либо взаимодействие с закрытием SOCKS helper. В original Core one_way_relay вызывает SD_BOTH в обоих направлениях после EOF одной стороны; map удаляется наFIN/RST. Это кандидат причины, не packet-level доказательство источника RST. Закреплённый Microsoft ctsTraffic source проверяет DONE после данных, затем graceful ждётEOF, rude закрывается без этого ожидания. Core/driver/native/helper не менялись.

Добавлен opt-in -DiagnosticRudeShutdown к existing TCP controller: только explicit4.0.0/freshSMOKE/noResume/тот жеsuccessful idle boot; один PROXY push64MiB@8MiB/s/verify:data. Live CIM snapshot own CTS PID/path/commandline подтверждает ровно один -shutdown:rude, хранится client-launch.json. Config/context/manifest отдельный transfer_rude_diagnostic_v1/diagnostic_only/readinessfalse/versionfalse; source profile/kit/boot/route/owned sockets/nativeSucceeded/dataGUID/PC/cleanstop gates сохранены. Отдельный diagnostic-summary.md, обычная paired aggregation отвергает diagnostics. Успех НЕ исправляет graceful сброс/не определяет единственную причину/не является readiness graceful или версионным сравнением. Ordinary graceful default/Driver/Resume неизменны.

PS5.1+7 AST/UTF8BOM/PythonAST прошли; readonly новыйOFF и16 прежних Driver transfer evaluations exact originals. Source fingerprints всех исходных runfiles совпали после анализа. Analysis+validation: artifacts/diagnostics/tcp-legacy-reset-20261002-122627. Runtime нового diagnostic НЕ выполнялся агентом.

Следующий USER ADMIN, **без новой перезагрузки**, на той же4.0.0 boot, около1–2мин; не повторятьLifecycle/весьSMOKE/непродолжатьfailedroot:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-LocalTcpBenchmark.ps1" -Profile SMOKE -ProductContract v4.0.0 -LegacyIdleDirectory "C:\src\ProxyBridge-TestLab\artifacts\version-comparison\preflight-20261002-114842-637268\legacy-idle-20261002-115842-0db06f" -DiagnosticRudeShutdown
```

Пользователь сообщает полный вывод. Если уже была reboot, старыйidle reference должен быть отвергнут. После этого определить следующий путь graceful диагностики/корректной методики, не готовить STANDARD4 или versiontransfer до подтверждённой готовности. Перед Driver всё ещё нужна reboot. Старые данные/RTT A-B/cleanup сохранены; no new producttraffic/build/install/autotests/subagents/commit/push/reboot/cleanup byagent. Следующая модель GPT-6.1 Sol/high.

## Предыдущая точка: исправлена область видимости callback передачи; повторить только legacy SMOKE (2026-10-02)

Пользователь выполнил LegacyTransferReadiness после reboot11:54:50.3984110Z. Lifecycle `legacy-lifecycle-20261002-115839-db5a40` и idle `legacy-idle-20261002-115842-0db06f` successful в preflight-20261002-114842-637268. Transfer `tcp-socks5-v4.0.0-smoke-20261002-115842-ac1bb6` FAILED на первом OFF до StartProcess клиента: Qpc-Ms не найден в GetNewClosure при вложенном запуске controller из preflight. Client-process/CSV отсутствуют, receipt traffic_generated=false; это ошибка TestLab scope, не дефект ProxyBridge/данных/скорости. Receiver15272 ожидал соединение, после15s принудительно закрыт/exit−1, proxy7480+sampler2156 natural0/outputcapturetrue. Saved post-run WFPStopped/detached/observercomplete/handles0/onlyidleWinDivert64/othernamesstable; workers_stopped=false/originalFAILED остаются, globalcleanup не заявлять. Это прошлое наблюдение, не новый current-state probe.

Invoke-LocalTcpBenchmark.ps1 теперь захватывает actual FunctionInfo Qpc-Ms/Write-Json и module-owned Get-LoadedInterceptionDriverObservation/Get-InterceptionStateSnapshot перед GetNewClosure; callback/sink вызывают их через&capturedCommand. Это устраняет зависимость от того, какой parent script видит функции. Другие контроллеры/профили/traffic settings/helpers/Core/driver/native/evaluators/cleanup policy не менялись. PS5.1+7AST/UTF8BOM прошли. Bounded actual PS5 helper observation через callback ПОСЛЕ завершения defining child scope: real extracted timer даёт2positive nondecreasingQPC, actual writer сохраняет/читает validation JSON; module command references captured/InterceptionState identity confirmed, interception functions NOTexecuted. Receipt `artifacts/diagnostics/tcp-transfer-closure-20261002-122317/validation.json`, failure-analysis.json/sourceSHA matches. Это адресная ручная проверка реальной причины, без новых product/runtime/traffic и без code-autotest suite. Full fixed transfer integration pending пользовательскому запуску.

Следующая команда USER ADMIN, **без новой перезагрузки**, на той же4.0.0 boot, около2–4мин; использовать confirmed idle reference, не повторять LegacyTransferReadiness/Lifecycle и не продолжать failedroot:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-LocalTcpBenchmark.ps1" -Profile SMOKE -ProductContract v4.0.0 -LegacyIdleDirectory "C:\src\ProxyBridge-TestLab\artifacts\version-comparison\preflight-20261002-114842-637268\legacy-idle-20261002-115842-0db06f"
```

Fresh `tcp-socks5-v4.0.0-smoke-*`,4×64MiB@8MiB/s/verify:data/owned socket observation DURING transfer; readiness only/no version speedA-B. Current fresh gates проверяются самим controller до трафика; если пользователь уже перезагрузился, oldboot reference не подходит, gate должен отказать. После анализа четырёх результатов готовить STANDARD/Driver-speed method, не раньше successful readiness. Перед Driver всё ещё нужна reboot. Histories/failed evidence/готовое RTT A-B сохранены, no build/install/autotests/subagents/commit/push/reboot/cleanup/newproducttraffic byagent. GitHub-fork validation после labready, upstreamDriver63be0eb подтверждён ранее11:36UTC. Следующая модель GPT-6.1 Sol/high.

## Предыдущая точка: подготовлена передача TCP для 4.0.0, runtime pending (2026-10-02)

После подтверждённого A/B RTT выбран следующий срез — скорость/целостность TCP upload/download для4.0.0. Продолжен existing ctsTraffic2.0.3.9/verify:data путь, без собственного генератора. Existing Invoke-LocalTcpBenchmark.ps1 получил явные ProductContract v4.0.0 и LegacyIdleDirectory, только freshSMOKE/noResume; defaultDriver/старыйResume прежние. Legacy4×64MiB при8MiB/s cap/одна connection/одна OFF-PROXY пара на direction. Более длинный8s перенос даёт время owned socket query, которая выполняется ВО ВРЕМЯ переноса: темп диагностический readiness only, не точные overhead/versionA-B/maxthroughput. Не смешивать с прежним defaultSMOKE16MiB или STANDARD512MiB. BaseSOCKS helper/егоNODELAY/defaultSelector/cts binary/Core/driver/native/sampler/строгая load-progress policy неизменны.

Подготовка Legacy привязана к successful idle/preflight/profileSHA/selectedkit+receipt/sourcevariant и той же VM/OS/boot. Before/after совместимых WinDivert handles0/knownWFPdetached/serviceStopped, допускается idle loadedWinDivert64.sys; прочие имена стабильны. Active exact1 ownCLI NETWORK flags0/WinDivert64 only/WFPdetached. Legacy не запускает GUI/Driver bootstrap и не вызывает SCMstop. Owned live TCP snapshot подтверждает generator→receiver дляOFF и CLI→SOCKS peer controlledflow дляPROXY; callbackROUTE_DECISION проверяет ctsTraffic PID/process/destination/SOCKS endpoint. Existing data/GUID/bytes/receiver flow/CPU-RAM coverage/natural workers/CLI stop gates сохранены. Новая pb_tcp_transfer_scope.py держит legacy-only scope, reporter refactored evaluate_run read-only + samewritingwrapper; старые Driver results неизменны. Legacy result отмечает readiness_only/live_socket_observation_during_transfer, global/version_switch_readyfalse. STANDARD4/Driver-transfer-A-B пока НЕ реализованы.

Preflight Prepare добавляет отдельные одинаковые transfer rules CTS→127.0.0.1:54122 черезSOCKS54123, прежние RTT/lifecycle profiles не меняет. Новая LegacyTransferReadiness фаза последовательно вызывает existingLegacyLifecycle→LegacyIdleObservation→transferSMOKE и останавливается при ошибке; без automaticreboot/автоматического повтора. Новая WindowsPS5.1 files-only Prepare реально завершена: `artifacts/version-comparison/preflight-20261002-114842-637268`, FILES_AND_PROFILES_PREPARED/обаkitsfilesverified/baseCoreDriverunchanged/5profilehashesmatch/constraints-equivalent/runtimefalse. Validation receipt в той же папке. PS5.1+7 AST/UTF8BOM/PythonAST прошли;16настоящих сохранённых transfer reevaluations exact originals/no rewrites. Full new runtime не выполнялся агентом.

**Следующее действие пользователя: перезагрузить Windows**, затем первым ProxyBridge запуском в административном PowerShell, около2–4мин:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-VersionComparisonPreflight.ps1" -Phase LegacyTransferReadiness -EvidenceDirectory "C:\src\ProxyBridge-TestLab\artifacts\version-comparison\preflight-20261002-114842-637268"
```

Результаты получают новый `artifacts/local-route/tcp-socks5-v4.0.0-smoke-*`; вывод содержит lifecycle/idle/SMOKE папки. После выполнения пользователь отправляет полный вывод, включая возможную ошибку. Не повторять failed run вслепую/не стирать evidence. После успешного анализа подготовить repeated transfer методику без query confound и Driver сравнение; пока не выдавать readiness за version speed benchmark. Reboot нужен потому, что текущая сессия использовала Driver; новая4.0.0 стартует на свежей boot послеPrepare. Поддержку своей GitHub-сборки пользователь хочет проверять ПОСЛЕ готовности лаборатории; currentupstreamDriver63be0eb HEAD подтверждён отдельнымremote-ref receipt11:36UTC, новаясборка радиактуализации не нужна.

Этот шаг: preparation files + code + saved-data verification; no new productruntime/traffic/build/install/autotests/subagents/commit/push/reboot/cleanup byagent. Старые96GiB series/failedattempts/RTT A-B reports сохранены; cleanupdone-norepeat. Следующая модель GPT-6.1 Sol/high.

## Уточнение: baseline совпадает с HEAD; пользовательскую версию проверить после готовности (2026-10-02)

Уточнение пользователя и проверка 2026-10-02T11:36:26.017339+00:00: git ls-remote https://github.com/InterceptSuite/ProxyBridge.git refs/heads/Driver вернул63be0ebf9bec92bfba95ef3d6729c375aa9af84e. Выбранный baseline действительно является текущим HEAD upstream Driver на момент проверки; новая сборка ради актуализации не нужна. Прежние флаги latestHEAD_verified=false в benchmark artifacts отражают отсутствие этой проверки при агрегации, originals не менять. Remote-ref receipt: artifacts/version-comparison/driver-head-observation-20261002-113626.json. Fork dentatli/ProxyBridge/driver — отдельная ветка, не смешивать с upstream Driver. Пользователь хочет ПОСЛЕ готовности лаборатории проверить свою GitHub версию драйвера как практическую проверку самого TestLab. Зафиксировано для этапа выбор версии/выпуск: явные repository/ref/commit и выбранные binaries, та же controlled-receiver методика, отдельная серия корректности/производительности, исходный baseline сохранить; runtime/новаясборка/custom-branch support сейчас не выполнять. Дальнейшая работа — завершение лаборатории по DEVELOPMENT_PLAN, не повтор успешного RTT и не поиск новой upstream сборки. GPT-6.1 Sol/high.

## Предыдущая точка: первое локальное сравнение RTT Driver и 4.0.0 подтверждено (2026-10-02)

Пользователь завершил `tcp-rtt-driver-version-standard-20261002-100723-30f0b4`: COMPLETED/6 MEASURED-PASS/LIMITED_COMPARISON/errors[]. Повторная read-only оценка всех6 Driver и6 legacy STANDARD точно совпала с сохранёнными результатами. На версию7200 проверенных обменов, включая1200 прогревочных,6000 measured/failed0/>20ms0. Driver socket capture заканчивается за2216.511–5956.856ms до measuredstart, PCcoverage>=98.979681%. Все4workers/run naturalexit0/unforced;3CLI ready/graceful/poststop/capture/noerrors. Прежние scoped gates Driver before/after WFPdetached/selectedserviceStopped/knownloadednamesabsent/compatibleWinDivert0, active selecteddriver+serviceRunning/WinDivert0 подтверждены сохранёнными свидетельствами. Это не новый current-state probe и не global cleanup.

Добавлен `src/pb_tcp_version_rtt_report.py`: только saved-data aggregation, без трафика. Переиспользует evaluate_run; проверяет complete6+6/order/PASS/exact reevaluation/общие параметры и7tool SHA/уникальные IDs/эквивалентные правила и pinnedprofileSHA/source binding/sameVM+OS/newboot после завершённой legacy серии/other-driver-name hash/preflightkit+receiptchain/одинаковые CLI adaptations. Различаться могут только явно разрешённые per-run IDs/PIDs и поля версии; отсутствующие legacy domain fields равны только пустым/disabled Driver fields. Ошибки дают INCONCLUSIVE, output только в новую папку вне source roots. JSON сохраняет fingerprints всех файлов run directories, исходных manifests/aggregates и analysis modules; originals не переписываются.

Итоговый отчёт: `artifacts/version-comparison/tcp-rtt-4.0.0-driver-20261002-100723-30f0b4/summary.md` и `comparison-report.json`, LIMITED_VERSION_COMPARISON/errors[]. Две версии в одной VM/OS26200, boot legacy07:30:38.6933510Z → Driver09:26:39.6886160Z. Общий RTT512bytes/20ms/1000measured+200warmup/один socket/3чередующиеся пары, observation строго вне measuredwindow. 4.0.0 paired median additions p50+.818900/p95+1.054800/p99+1.404400ms; Driver63be0eb +.314400/+.413200/+.479300ms. Изменение Driver−legacy −.504500/−.641600/−.925100ms. Mode p50 OFF/PROXY legacy.225/1.043ms, Driver.218/.537ms; maxPROXY Driver1.452ms. CLI medianCPU legacy.074125%/Driver.041267% всегоПК, privateRAM2.411681/2.746787MiB; не весь продукт/driver-only/watts. PC фон OFF medianCPU.828% vs1.225%, только один порядок версий через reboot; это описательное сравнение конкретных комплектов без confidence interval, не доказательство игр/remote/throughput/long-soak. Legacy OFF сохраняет idle loaded WinDivert с handle0, Driver OFF без известных loaded interceptors. Показатели добавки — медиана разностей внутри пар, не difference of mode medians и не quantile of packetwise overhead.

Python AST и реальная saved-data агрегация прошли; analysis SHA и все291 source-file fingerprints совпали после записи. Промежуточная производная папка tcp-rtt-4.0.0-driver-20261002-verified оставлена историей разработки, canonical итог — папка выше. Ошибка console cp1251 при выводе Unicode касалась только просмотра; UTF8 отчёт проверен повторным чтением. Никакого product traffic/build/install/autotests/subagents/commit/push/reboot/cleanup агентом; controllers/base evaluators/Core/driver/native/helpers/progress не менялись. Global/version_switch_ready/latestHEAD_verified=false.

Предыдущее предложение об актуализации baseline отменено после проверки remote-ref выше:63be0eb — текущий HEAD upstream Driver. Currentcheckout137d1286 относится к другому fork/ref и не является происхождением выбранного binary. Продолжить завершение лаборатории; свою версию пользователь проверит после готовности. Следующие version throughput/loadedRTT/UDP и удобный UI/remote/release остаются в плане. Успешные серии не повторять, старые Driver серии не объединять. Долгие прогоны продолжает запускать пользователь, reboot только вручную. Следующая модель GPT-6.1 Sol, усиление высокое (high).

## Предыдущая точка: RTT STANDARD 4.0.0 подтверждена; подготовлен Driver после reboot (2026-10-02)

`tcp-rtt-v4.0.0-standard-20261002-083024-173c48`: COMPLETED/6MEASURED/PASS/LIMITED_COMPARISON/errors[]. Все6 read-only reevaluations равны originals, configs одинаковы;7200verified/6000measured/failed0/>20ms0. Медианы paired PROXY−OFF quantile deltas: p50+.818900,p95+1.054800,p99+1.404400ms. Это не разница медиан режимов (таблица p50OFF.225/PROXY1.043ms), не индивидуальная added-latency quantile/driver-only/game evidence. MaxPROXY2.553ms. Capture заканчивался за4411–5914ms до measuredstart во всех6 случаях, PCcoverage>=98.754689%; CLI medianCPU .074125% всегоПК/privateRAM2.411681MiB, без watts/driver-only attribution.

Все4workers/run naturalexit0/unforced,3CLI ready/graceful/poststop/capture/unforced/noerrors; activeowned NETWORKhandle1, idle0, knownWFPdetached, WinDivert64.sys retained/other-driver-name hash stable. Оригинальные reports/logs/manifest сохранены, новых current runtime probes не делалось.

В существующий RTT controller добавлен явный opt-in Driver STANDARD `-LegacyRttDirectory`. Он связывает подготовку с six successful repeated4reports, порядком пар, прежними toolkit SHA/preflight/Driver kit63be0eb/common2ruleprofile. Требуются sameVM/OS и boot строго позже legacy; перед/после — knownloadednamesabsent/knownWFPdetached/compatibleWinDivert0, active — selectedWFPdriver/serviceRunning/WinDivert0. Только existing Driver service bootstrap/ownedCLI, старая cleanup без ослабления.200warmup/1000measured/512bytes/20ms/3pairs, owned socket snapshots в обоих modes, strictly before measuredstart; copied pinned driver-tcp.pbprofile и config/version-context сохраняются. Reporter добавляет opt-in boot/profile/socket/observer gates, прежний defaultDriver и legacy evaluation не меняются. Global/version_switch_ready остаютсяfalse, loaded identity/все семейства/история между boots не сертифицированы.

Проверены PS5.1/7AST/UTF8BOM/PythonAST;6legacy и12предыдущих loadedNODELAY reevaluations равны originalJSON. Реальная files-only metadata сверка: Driveridentity filesverified/samepreflightbundle, pinnedDriverprofileSHA,7currenttoolhashes совпадают во всех6sourceconfigs, process/IP/port/proto/action/Id/enabledconstraints двух профилей эквивалентны. Kit63be0eb — проверенный выбранный baseline, актуальный upstreamHEAD не проверен; currentcheckout137d1286 не доказательство происхождения этого binary. Новый Driver runtime integration пока pending. Core/driver/native/helpers/progress policy не менялись; никаких новых traffic/build/install/autotests/subagents/commit/push/reboot/cleanup агентом.

**Следующее действие пользователя: перезагрузить Windows**, затем первым ProxyBridge-действием в административном PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-LocalTcpRtt.ps1" -Profile STANDARD -ProductContract driver -LegacyRttDirectory "C:\src\ProxyBridge-TestLab\artifacts\local-route\tcp-rtt-v4.0.0-standard-20261002-083024-173c48"
```

Около5–10мин, fresh artifacts/local-route/tcp-rtt-driver-version-standard-*/summary.md. Самостоятельно не запускать GUI/другую версию/старый Driver-only STANDARD до команды. Ошибка до bootguard не означает product runtime; при runtimeошибке сохраняются evidence, не повторять вслепую. После результатов проверить реальные две серии и подготовить итоговое version A/B; итоговая агрегация ещё не реализована/не подтверждена, старые Driver данные сюда не добавлять. Последующее обновление baseline до актуальной выбранной Driver ревизии остаётся отдельным provenance/build шагом.

GPT-6.1 Sol/high для следующего Driver результата/сравнения.

## Предыдущая точка: TCP SMOKE 4.0.0 подтверждён; подготовлена повторная RTT-серия (2026-10-02)

`artifacts/local-route/tcp-rtt-v4.0.0-smoke-20261002-081534-6fb514`: COMPLETED/2×MEASURED/PASS/LIMITED_COMPARISON/errors=[], обе read-only reevaluation точно совпали с оригиналами.288verified/256measured, failed0/>20ms0. OFF/PROXY p50 .247050/1.154550ms, p95 .331900/1.452800, p99 .402500/2.457000; paired deltas +.907500/+1.120900/+2.054500ms, maxPROXY3.627300ms. Один короткий локальный pair, старые Driver цифры сюда не подмешивать.

CLI1740 exactselectedpath/ready/graceful/poststop/capture=true/unforced/errorsempty. Active1owned NETWORK/flags0/priority123 handle; before/after0compatiblehandles/knownWFP detached, WinDivert64.sys остаётся загружен/otherdriverhashstable/globalversionfalse. Generator11560 callback process/PID/destination/ProxySOCKS endpoint совпал с фактическим owned CLI→SOCKS source57934 и controlled flow→receiver source57935;144frames/74304bytesup/73728down совпали. Четыре workers/run naturalexit0/unforced, PCcoverage>=90.621%,14samples/role; CLI .143075% всегоПК/private2.429129MiB, не driver-only/watts.

Наблюдение сокетов заняло2097/2335ms и закончилось через1594.959/1750.450ms после начала measuredwindow. Это ожидаемое ограничение SMOKE с16warmup; оригинальный readinessPASS не меняется, точные overhead/версии по нему не заявлять.

Добавлена legacy STANDARD `repeat_rtt_v1`:3чередующиеся пары OFF/PROXY/PROXY/OFF/OFF/PROXY,1000measured+200warmup/run,512bytes/20ms;7200verified inclwarmup при успехе. Требуются явные successful LegacySmokeDirectory/LegacyIdleDirectory, прежняя boot/VM/OS/kit/profile/tool chain. New policy `owned-socket-snapshot-before-measurement-v1`: capture_completed_qpc_ms строго раньше первого measured send; overlap оставляет INCONCLUSIVE, не исключает неудобные samples. Все старые payload/socket/route/PC/lifecycle/scopedhandle gates сохранены; oldSMOKE stage/defaultDriver не меняются. Новая серия получает отдельную папку и не смешивается с SMOKE. Helpers/native/Core/driver/progress policy не изменены. STANDARD пока runtime pending.

Следующая команда пользователя в административном PowerShell, **без перезагрузки**, около5–10мин; не запускать другую версию ProxyBridge:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-LocalTcpRtt.ps1" -Profile STANDARD -ProductContract v4.0.0 -LegacyIdleDirectory "C:\src\ProxyBridge-TestLab\artifacts\version-comparison\preflight-20261002-072108-51203a\legacy-idle-20261002-075231-195015" -LegacySmokeDirectory "C:\src\ProxyBridge-TestLab\artifacts\local-route\tcp-rtt-v4.0.0-smoke-20261002-081534-6fb514"
```

Fresh artifacts/local-route/tcp-rtt-v4.0.0-standard-*/summary.md. При ошибке сохранить вывод/папку, не выбирать лучшие повторы. После анализа нужен подготовленный новый Driver-прогон с теми же200warmup/capturepolicy/общими2rules и новой перезагрузкой; прежние Driver STANDARD не являются этим A/B. Driver command для новой методики пока не готова; latestDriverHEAD ещё не верифицирован.

Проверены PS5.1/7 AST/UTF8BOM/PythonAST; после изменения2savedSMOKE reevaluations по-прежнему exact originals. Это saved-data analysis и подготовка продукта, не developer автотесты. Агент новый трафик/CLI не запускал, builds/installs/subagents/commit/push/reboot/cleanup не выполнял. Все истории/96GiB STANDARD сохранены. Следующий шаг GPT-6.1 Sol/high.

## Предыдущая точка: покой 4.0.0 подтверждён в известном scope; подготовлена короткая TCP-проверка (2026-10-02)

Пользователь выполнил LegacyIdleObservation: `legacy-idle-20261002-075231-195015` в прежнем preflight root, LEGACY_IDLE_SCOPED_OBSERVED/error пустой. Saved observer files_verified/capture_complete=true, NO_HANDLES_OBSERVED/count0; known WFP querycomplete+absent/serviceStopped, loaded-name querycomplete/onlyWinDivert64.sys/no selectedWFP/unchanged other-driver-name hash. Boot07:30:38.6933510Z тот же; источник/loaded identity/global cleanup/version_switch_ready остаются неполными/false. Это подтверждённое наблюдение покоя, не маршрут/скорость и не разрешение перейти к Driver без reboot.

Переиспользован существующий `Invoke-LocalTcpRtt.ps1`, добавлены явные ProductContract/LegacyIdleDirectory; по умолчанию прежний Driver. 4.0.0 пока допускается только SMOKE с successful idle receipt и тем же текущим boot/VM/OS. Реальные файлы selected legacy kit/receipt/source declaration/variant и SHA общего preflight TCP-профиля должны совпасть. Legacy запускает только свой стендовый CLI: без GUI, service bootstrap и остановки Driver SCM. Профиль копируется из закреплённого v4.0.0-tcp.pbprofile: общий process/IP/port/SOCKS contract, второе ctsTraffic правило не используется в echo.

На каждый OFF/PROXY: новый run-ID/144×512byte echo,16warmup исключены/128measured,20ms после ответа, TCP_NODELAY клиента/получателя, неизменённый base SOCKS helper/BUFFERED receiver/psutil. Перед/после — actual boot + fresh handle0/knownWFP detached/inventory/no active ProxyBridge; во время PROXY — exact1 NETWORK/flags0 handle owned CLI и только WinDivert64.sys в известных names, actualCLIpath/штатная остановка. В обоих режимах снимается owned TCP socket snapshot (`owned-socket-snapshot-smoke-v1`, query time/QPC сохраняются); PROXY snapshot связывается с inboundpeer единственного controlled TCP flow, OFF — с native socket и peer получателя. Original4.0.0 callback сообщает ROUTE_DECISION с process/PID/destination и Proxy SOCKS5 endpoint вместо Driver RELAY_ACCEPTED_REDIRECT; existing parser переиспользован, PID/process/destination/endpoint проверяются вместе с точными flow/bytes/hash/receiver свидетельствами. Полнота продуктового eventstream не заявляется.

`pb_tcp_rtt_report.py` сохраняет строгие Driver-проверки, добавляет отдельную legacy branch с handle/WFP/owned socket/профилем/boot scope. Количества/порядок/данные/PC coverage/clean worker exits и CLI lifecycle остаются обязательными. OFF может оставлять загруженный WinDivert без дескрипторов; это не driver-unloaded baseline. Один короткий pair с live socket observation — только readiness/диагностические RTT deltas, не строгий benchmark overhead, стабильность игр/нагрузка/A-B версий. Globalcleanup/version_switch_ready всегда false. Fresh result tcp-rtt-v4.0.0-smoke-*; прежние серии и отчёты не переписываются.

Проверено PS5.1/7 AST + UTF8BOM, Python AST; адресно прочитана pinned upstream CLI/Core callback форма. Реальная read-only files/metadata проверка подтвердила files_verified/тот же bundle/buildreceipt/profileSHA/VM/OS/boot. Read-only saved reevaluation12NODELAY loaded STANDARD полностью равна originalJSON; все6старых RTT STANDARD совпали по существующим полям/вердиктам/метрикам. В старой RTT-схеме отсутствуют два timestamp поля measurement_start/end_qpc_ms, уже добавленных evaluator до этого шага: первоначальное предположение полного equality исправлено, originals не изменены. Это анализ настоящих benchmark данных, не автотесты TestLab кода. Новая legacy runtime/active observer/socket correlation integration пока НЕ исполнена агентом.

Следующее действие пользователя, **без перезагрузки**, административный PowerShell; не запускать другой ProxyBridge:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-LocalTcpRtt.ps1" -Profile SMOKE -ProductContract v4.0.0 -LegacyIdleDirectory "C:\src\ProxyBridge-TestLab\artifacts\version-comparison\preflight-20261002-072108-51203a\legacy-idle-20261002-075231-195015"
```

Около1–3мин:2run OFF/PROXY, fresh artifacts/local-route/tcp-rtt-v4.0.0-smoke-*, summary.md при успешном завершении. При ошибке сообщить вывод и папку, не стирать failed evidence/не повторять вслепую. Перед Driver — новая перезагрузка; сейчас продолжение той же4.0.0. После SMOKE рассмотреть единые условия/fixture для реального сравнения версий, не объединять новые readiness результаты с прежним Driver STANDARD.

Этот шаг:2узких расширения controller/reporter + saved-data/metadata/docs; no product traffic/CLI runtime/build/install/autotests/subagents/commit/push/reboot. Core/driver/native/basehelpers/strict native progress unchanged, successful96GiB и старые INCONCLUSIVE сохранены/не повторены, cleanupdone/norepeat. Selected Driver63be0eb не verifiedlatestHEAD, currentcheckout137d1286 не provenance. GPT-6.1 Sol/high для следующего результата.

## Предыдущая точка: 4.0.0 штатно остановлена; перед маршрутом проверить оставшийся WinDivert (2026-10-02)

Пользователь выполнил LegacyLifecycle после reboot. Сохранённый `legacy-lifecycle-20261002-073624-2c372d` внутри `artifacts/version-comparison/preflight-20261002-072108-51203a`: START_STOP_OBSERVED_REBOOT_REQUIRED, ready/graceful_stop/post_stop_verified/output_capture_complete=true, forced_stop=false, actual CLI path совпал с выбранной 4.0.0, errors пусты. Boot07:30:38.6933510Z; генератор не запускался. Flat cli-lifecycle evidence содержит output_capture_complete непосредственно, не вложенный process_result; exit0 проверен контроллером при формировании startup_shutdown_verified, отдельно в flat JSON не записан.

После остановки WinDivert64.sys остался в complete loaded-name snapshot, selected WFP driver отсутствует, serviceStopped/knownWFP querycomplete+absent; other-driver-names SHA совпал before/after. Оригинальный WinDivert observer NOT_CONFIGURED, поэтому отсутствие открытых дескрипторов ещё не доказано. Загруженное имя само по себе не доказывает активный перехват. Строка stop «Failed to receive packet (232)» при штатном завершении не является доказательством сетевого дефекта. Исходные receipts/snapshots/logs сохранены.

Добавлен только read-only этап LegacyIdleObservation в существующий preflight controller. Он требует admin, той же загрузки/VM/OS, ровно одного successful legacy lifecycle на этой загрузке, прежних kit/profile hashes, сохранённого CLI path/штатной остановки, отсутствия active ProxyBridge до/после наблюдения. Existing InterceptionState observer запускает официальный windivertctl2.2.2 только с `list`, pinned EXE/DLL и timeout10s; сохраняются WFP/loaded-name/handle observations и idle-receipt. Допустимо только сохранённое имя WinDivert64.sys при отсутствии handles совместимого семейства, knownWFP detached, unchanged other-driver-name hash; новый selected Driver не допускается. Это snapshot известного scope, не история всех процессов/драйверов и не глобальная очистка. version_switch_ready/route_verified/benchmark_ready остаются false; перед Driver обязательна перезагрузка.

Официальный архив 405137bytes SHA63cb41763bb4b20f600b6de04e991a9c2be73279e317d4d82f237b150c5f3f15 сохранён в bin/tools/windivert-2.2.2. Извлечены только x64 windivertctl.exe/WinDivert.dll, LICENSE/README/VERSION; driver не извлекался/не устанавливался. EXE SHAf27980b00d97e3f6a590cf4fad04f30f4c61c72324d52af2442afdcf69f31765; DLL SHA c1e060ee… и архивный SYS SHA8da08533… побайтово совпали с выбранным legacy kit. Upstream ctl source/source hash и origin.json сохранены; официальный API не предоставляет asset digest, независимая сборка executable и identity загруженного драйвера не доказаны. Source `list` использует REFLECT/SNIFF/RECV_ONLY/NO_INSTALL; watch/kill/uninstall не вызываются. Подробнее источник в TOOLS_AND_REUSE.

Следующее действие пользователя, **без новой перезагрузки и без запуска ProxyBridge**, административный PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-VersionComparisonPreflight.ps1" -Phase LegacyIdleObservation -EvidenceDirectory "C:\src\ProxyBridge-TestLab\artifacts\version-comparison\preflight-20261002-072108-51203a"
```

Около30сек, fresh legacy-idle-* в этом root. При успехе LEGACY_IDLE_SCOPED_OBSERVED; при BLOCKED receipt сохраняется, handles не закрываются насильно. Затем разобрать результат и подготовить controlled TCP route/SMOKE той же4.0.0. Маршрутная/benchmark команда пока не готова; не запускать Driver или старый Driver-only RTT controller на этой загрузке.

PS5.1/7 AST/UTF8BOM и адресная saved-data inspection проверены; выявлено и исправлено обращение к несуществующему вложенному process_result в новой ветке до выдачи команды. Final observer integration не запускалась агентом (неadmin). Никакого продукта/нового трафика/build/install/autotests/subagents/commit/push/reboot в этом шаге. Core/driver/native/helper/default/progress gates прежние; прошлые96GiB benchmark и исторические ошибки не смешаны/не повторены; cleanupdone. Следующий шаг GPT-6.1 Sol/high.

## Предыдущая точка: перезагрузка между версиями согласована; подготовлен первый legacy lifecycle (2026-10-02)

Пользователь прямо выбрал reboot_between_versions. Создан `scripts/Invoke-VersionComparisonPreflight.ps1` с Prepare/LegacyLifecycle. Реальная Prepare прошла WindowsPS5.1 без продукта: `artifacts/version-comparison/preflight-20261002-072108-51203a/preflight.json`, FILES_AND_PROFILES_PREPARED. Обаidentityfilesverified/receiptchainverified/basecomponentsunchanged; current hashes CLI/Core/drivers/GUI/base receipts/upstreamsource/patchedsource/archives/official4installer совпадают. Отдельный read-only zip-entry check CLI source==пинованныйarchive entry оба. Это сверка savedreceipts/files, не независимая воспроизводимость build и не latestHEAD/source-to-release-binary proof; source_commit_verified/loaded_modules_verified остаютсяfalse.

Shared profile:2TCP PROXYrules pb_tcp_rtt_client.exe→127.0.0.1:54122 иctsTraffic.exe→54126 черезcontrolledSOCKS54123,localhostvia=true,domains unconstrained/IPforwarding. ExistingProductProfile adapter Driver/v4.0.0 форматсовместим, одинаковыеprocess/IP/port/proto/action/Id constraints проверены по savedadaptedprofiles; route ещёfalse.3profilefiles SHA pinned:driver-tcp,v4.0.0-tcp,v4.0.0-lifecycle. Lifecycle тольконесуществующий `ProxyBridge_TestLab_Lifecycle_Probe.exe`/DIRECT/127.0.0.1:54122/noProxyConfigs/noLogging — генераторне запускается.

Prepare сохраняетmachineguid/boot_time/OSbuild; LegacyLifecycle требуетadmin+сохранённуюпапку+тойжемашины/OSbuild+строгоболее новуюboot_time+неизменившиесяkitbundles/receipts/profilehashes+нетProxyBridgeGUI/CLI/knownloadedinterceptors+knownWFP querycompleteabsent. Затем толькостендовый4CLIstart/stop поexistingLifecycle adapter; fixedreadiness10s/stop10s, snapshotbefore/after, freshlifecycle subfolder/receipt, никаких stop чужихслужб/rebootавтоматом/globalreadytrue. Послефазы всегдаreboot переддругойверсией, дажееслиknownnamesabsent. Coldboot gates относятсякпровереннымнаблюдениям, не историивсехзагрузок илиглобальнойсертификациивсехсемейств. Пользовательдолжензапуститьэтаппервымпослерестарта, не запускатьдругойProxyBridge. Legacy runtimephase покаНЕисполнена, даже CLI--version не повторялся. Prepare не являетсяускорением/маршрутнымPASS/готовымA-B.

Первые draft Preparefailed dirspreflight-20261002-071607-4c7961 и preflight-20261002-071943-cea20a сохранены; причины толькоcanonicalProfilevalidator:missingGUItopfields, затемTargetPorts '*' не допустим егоformatcontract. Исправлен профильscript, не validator/Core/driver:полныеtopfields/портычислом/неиспользуемыйprocessName. Intermediate files-only prepared071727-395c2f historical. ОкончательнаяPrepare072108-51203a прошла, actualgeneratedprofiles/3SHA/sourceconstraints checked. PS5.1runtime/PS7finalAST/UTF8BOM passed. Первый separate read-only machinesnapshot failed WindowsExecutionPolicy (не auto-review), состояниеизнего не считатьнаблюдением; settings политикипостоянноне менялись. Agent tokenнеadmin, поэтомуmachine/runtimeпредпроверки legacy остаютсяпользователю.

Следующее действие пользователя: **перезагрузкаWindows**, затем административныйPowerShell, первымэтапом послеboot:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-VersionComparisonPreflight.ps1" -Phase LegacyLifecycle -EvidenceDirectory "C:\src\ProxyBridge-TestLab\artifacts\version-comparison\preflight-20261002-072108-51203a"
```

Около30–60сек, результатfresh `legacy-lifecycle-<UTC>-<id>` внутриpreflightroot, ready/stop/cleanupobservations, no generated traffic. Еслиошибка — receipt/cli-lifecycle сохраняются; не считатьнеизвестнуюочисткуPASS и не запускатьдругуюверсиюбезновойперезагрузки. Послеуспеха отдельно подготовить4.0.0 controlled route+SMOKE; A/Bcontroller новых нагрузок пока не готов и требуетэквивалентныхметрик/условий.

This turn newcontroller/files-only preparation/readonlyactualartifacts/docs; noproducttraffic/CLIruntime/driverinstall/build/autotests/subagents/commit/push/reboot. ExistingCore/driver/native/basehelper/default/progress untouched. Last NODELAYSTANDARD96GiB/37200echo/PASS сохранён; oldSTANDARD/history/WPRdiagnostics не смешивать. Cleanup21.729GiBdone/no repeat/globalversionfalse. KitDriver63be0eb/currentcheckout137d1286notprovenance/latestHEADnotverified. GPT-6.1 Sol/high для следующегоlegacy-result анализа/подготовки.

## Предыдущая точка: NODELAY STANDARD подтверждена; следующий приоритет — подготовка версионного A/B (2026-10-02)

`tcp-loaded-rtt-nodelay-standard-20261002-062937-0115e8`: COMPLETED/12×MEASURED/PASS/errors=[]/LIMITED_COMPARISON/errors=[]. Read-only reevaluation всех12 совпадает с originals; одинаковые traffic/tool/fixture/product/other-driver conditions, порядок3counterbalancedpairs/direction и все6paired deltas проверены.96GiB bulk/37200 verifiedecho inclwarmup (36000measured), failed0, >20ms0, maxRTT5,5088ms. Nativeprogress>=387/window, maxgap375,2853ms, min43320406bytes/s. PCcoverage>=99,731955%; NODELAY accepted_nodelay_v1/PROXY2owned+129explicitrefusedUDP каждый, OFFcreatedemptyoptions/no flows. ОтклонённыеUDPassociate — controlrequests, не UDPbenchmark.

Медианные показатели OFF/PROXY upload: p50 .228/.566,p95 .337/2.081,p99 .466/2.761ms; download:.214/.548,.325/2.358,.443/3.729ms. Медианные paired PROXY−OFF deltas upload/download: p50+.338/+.335,p95+1.744/+2.032,p99+2.316/+3.299ms. Разница медиан режимов НЕ заменяет медиану paired deltas. p50paired ranges upload+.3295…+.3481/download+.3288…+.3501ms. Throughput~537Mbit/s в обоих modes при RateLimit64MiB/s — ограниченный темп, не capacity/zerooverhead proof. CLI medianCPU .050746%upload/2.101685%download всего стенда/privateRAM3.276052/3.268240MiB; helper/генератор/receiver отдельно, driver-only/watts/leak freedom не устанавливаются.

Все6workers каждогоrun naturalexit0/unforced; все6CLI ready/graceful/poststop/capturetrue/errors=[], selectedserviceStopped/knownWFP querycomplete+absent/loadedquerycomplete+knownnamesabsent/selecteddrivernotloaded послекаждогоrun. Глобальная очистка/переключениеверсий false. Выводы изsavedpost-run evidence, текущее состояние отдельно не проверялось. Оригиналыreports/manifest/summary сохранены; старыйSTANDARD7retained/two8INCONCLUSIVE/last4pending иWPR/standalone diagnostics не объединять с этой новой серией. Результат подтверждает локальныйIPv4 fullpath TCP при cappedbulk+echo, не реальнуюигру/предельнуюёмкость/remote/4.0.0/latestHEAD/UDPdefect fix/Nagle solecause.

Новых повторов той же STANDARD не нужно. Следующее **предложение** — перейти к пункту2 текущего плана: происхождение/совместимость выбранных Driver и официальной4.0.0, семантическиэквивалентные правила и безопасная последовательная остановка/очистка/переключение перед первымA/B. Version readiness ещёfalse; новая runnableкоманда не подготовлена, не запускать4.0.0 одновременно сDriver и не выдавать измерения как versioncompare. KitDriver63be0eb, currentcheckout137d1286 без63be0ebobject неprovenance; отдельно решить актуальную выбранную ревизию до сборки. Не делать новую сборку/установку или producttraffic без подходящего следующего задания.

Этот шаг read-only saved-data analysis +docs only/no code/newtraffic/probes/build/install/autotests/subagents/commit/push. Strictnativeprogress/default/basehelper/Core/driver/native неизменны; cleanup21.729GiB done/no repeat. Следующая подготовка: GPT-6.1 Sol/high. Остальные6приоритетов/релизныеусловия вDEVELOPMENT_PLAN, многопоточность/длительнаянагрузка/remote/UI остаются открыты.

## Предыдущая точка: NODELAY парная SMOKE подтверждена; пользователь запускает STANDARD (2026-10-02)

`tcp-loaded-rtt-nodelay-smoke-20261002-062404-f7ec60`: COMPLETED/4×MEASURED/PASS/errors=[]/LIMITED_COMPARISON/errors=[]. Read-only actual reevaluation всех4 равна saved reports; traffic/tools/fixture/product/other-driver signature одинаковая. Подтверждены512MiB bulk/576echo includingwarmup/failed0; TCP_NODELAY fixture accepted_nodelay_v1: OFF optionsfile пуст/no connections, обаPROXY2workload+19explicitrefusedUDP, всеoptions confirmed. Это TCP benchmark, отклонённыеUDPassociate не являютсяUDPнагрузкой.

OFF/PROXY p50 upload0,224/0,566ms, download0,216/0,526ms; paired deltas+0,342/+0,310ms. p99 OFF/PROXY upload0,423/3,294ms, download0,359/3,705ms; paired deltas+2,871/+3,346ms. MaxPROXY3,794/3,874ms, >20ms0 во всехruns. По одной короткой паре/128 measured samples на режим: подтверждение готовности, не latency SLA/реальнаяигра/стабильность/максимальнаяёмкость/исправление ProxyBridge. Rate-capped8MiB/s, не смешивать с STANDARD64MiB/s. Nativeprogress16–17samples/window/maxgap344,658–359,635ms/min6229657bytes/s acrossruns. PC coverage93,77–98,32%; CLI sampledCPU0 обоихrun не означает zeroCPUcost, privateRAM3,34/2,95MiB — короткие наблюдения, не leak evidence/driver-only/watts.

Все6workers каждогоrun naturalexit0/unforced; обаCLI15300/13568 ready/graceful/poststop/capturetrue/errors=[]. SelectedserviceStopped/knownWFP querycomplete+absent/loadedquerycomplete+knownnamesabsent/selecteddrivernotloaded послекаждогоrun; global/versionfalse. Отсутствиеcli-lifecycle.json вOFF ожидаемо — CLI не запускался. Новое текущее состояние ресурсов не проверялось: вывод относится к сохранённомуpost-run evidence.

Следующая команда пользователя в административном PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-LocalTcpLoadedRtt.ps1" -Profile STANDARD -ProxyNoDelay
```

Свежая series12runs,3counterbalancedpairs/direction, по8GiB@64MiB/s/3000 measured+100warmup echoes, ориентировочно25–35мин.96GiB loopback payload безpayloadfiles, безWPR/ETL. Auto output `artifacts/local-route/tcp-loaded-rtt-nodelay-standard-<UTC>-<id>`. НеResume прежней серии: oldSTANDARD7retained/two8INCONCLUSIVE/last4pending сохраняется отдельно. НовыйResume при необходимости требуеттотже -ProxyNoDelay иточныйEvidenceDirectory, сохраняет history; не выдаватьResume до фактическогосбоя. Агент полныйrun не запускает, ждёт пользователя.

Этот шаг saved-data analysis/docs only; no code/newtraffic/probes/build/install/autotests/subagents/commit/push. Strictnativeprogress/payload/route/PC/cleanup/default/basehelper/Core/driver/native неизменны. Cleanup21.729GiB done/no repeat; selectedkit63be0eb/global-versionfalse/remote4.0.0notverified. Для разбора GPT-6.1 Sol/medium, high при расхождениях.

## Предыдущая точка: обычная NODELAY парная серия подготовлена; пользователь запускает SMOKE (2026-10-02)

Пользователь согласовал подготовку обычного TCP-стенда после результата без WPR `tcp-loaded-rtt-diagnostic-pull-standard-20261002-055449-32ade7`: MEASURED/errors=[]/8GiB+3100echo/native512active/whole receivingzeros0; p50 .494/p95 2.480/p99 2.981/max4.643ms/>20ms0. Read-only reevaluation совпадает. Большие скачки heavy ETW не повторились, вклад инструментирования — гипотеза, не solecause/fix/game-stability proof. Прямой базы нет; это не парный benchmark. Originals/analysis.md/json сохранены.

`Invoke-LocalTcpLoadedRtt.ps1 -ProxyNoDelay` теперь разрешён для обычного SMOKE/STANDARD/Resume, отдельный проверенный launcher переиспользован без изменения его файла и base-helper/Core/driver/native. Default без флага остаётся прежним. Новые обычные manifest/config имеют `tcp_fixture_revision=accepted_nodelay_v1` и `proxy_accepted_tcp_nodelay=true`, обе стороны используют тот же fixture/hash. PROXY — реальные options2owned flows плюс все explicitlyrefusedUDP; OFF — созданный пустой options log и отсутствие flows/rejectedUDP. Reporter сохраняет diagnostic_socket_observation для совместимости; paired summary/JSON явно маркируют настройку. Comparison/Resume проверяют совпадение config/manifest/options/revision; нельзя смешивать legacy/NODELAY или диагностический singleton с парной серией. Resume сохраняет old failed history и повторно проверенный prefix, требуется тот же флаг. Strict native-progress/route/data/PC/cleanup gates не ослаблены.

Проверка: PS5.1 5.1.26100.9444 +PS7 7.6.5 AST/UTF8BOM, Python syntax. Read-only actual saved reevaluation: no-WPR PROXY MEASURED, legacy OFF MEASURED, baseline ACK INCONCLUSIVE — точно совпали с originals; old STANDARD Resume read-only valid7retained/5remaining. Ни один сохранённый report не перезаписан. Ручной короткий idle-helper `artifacts/diagnostics/tcp-nodelay-idle-check-20261002-061602-ec6446`: PID5052/listener60353/options file empty/no flows/STDIN_STOP/naturalexit0. Первоначальная проверка ошибочно читала reason вместо shutdown_reason и считала библиотечный INFOstderr ошибками; проверено по настоящим сохранённым событиям, validation поправлен с описанием ошибки, helper не перезапускался. Это engine-only/no ProxyBridge/no product traffic, не подтверждение новой полной OFF/PROXY интеграции.

Следующая команда пользователя в административном PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-LocalTcpLoadedRtt.ps1" -Profile SMOKE -ProxyNoDelay
```

Четыре fresh OFF/PROXY runs, upload/download, по128MiB@8MiB/s +128 measured/16warmup echoes, ориентировочно2–5мин. Результат `artifacts/local-route/tcp-loaded-rtt-nodelay-smoke-<UTC>-<id>`. Full product integration пока pending, агент серию не запускает. После успешного разбора — fresh STANDARD с тем жефлагом,12×8GiB@64MiB/s/3000+100echo/25–35мин; не запускать до результата SMOKE. Старый STANDARD7retained/two8INCONCLUSIVE/last4pending сохранить отдельно; helper native-progress criterion неизменен. Обновлён раздел «Что осталось до готовности» в DEVELOPMENT_PLAN.

Cleanup21.729GiB выполнена, не повторять; global/version gatesfalse; kitDriver63be0eb, current sourcecheckout137d1286 без63be0ebobject не provenance. No WPR/new trace/new driver/Core/native changes/build/install/autotests/subagents/commit/push. Для обычного разбора GPT-6.1 Sol/medium, high при расхождениях/следующей разработке.

## Предыдущая точка: NODELAY download без WPR завершён; предлагается новая обычная парная серия (2026-10-02)

Пользовательский `tcp-loaded-rtt-diagnostic-pull-standard-20261002-055449-32ade7`: COMPLETED/MEASURED/errors=[]; read-only reevaluation совпала с оригиналом. 8 ГиБ/3100 echo проверены, failed0; p50 0,494/p95 2,480/p99 2,981/max4,643 мс, >20 мс0. Native512active/receivingzeros0 во всём журнале; RTT395progress/min50260691bytes/s/maxgap360,323ms. Accepted NODELAY1:2workload+133explicitrefusedUDP, socketgate confirmed. Все6workers naturalexit0; CLI10864 graceful/poststop/capturetrue, selectedserviceStopped/knownWFP+loadednamesabsent/global-versionfalse. CLI CPU1,791%wholePC/privateRAM3,286MiB; не driver-only/watts. WPR этим запуском не включался, ETL отсутствует; новое текущее состояние WPR не проверялось.

Большие RTT-скачки предыдущей тяжёлой ETW-записи здесь не повторились. Влияние инструментирования — поддержанная гипотеза, не доказанная единственная причина; один непарный запуск/разное время/фон. NODELAY наблюдения поддерживают гипотезу Нейгла в helper, не доказательство исправления ProxyBridge/стабильности игр. Прямой базы нет, overhead не вычислять. Подробности: `analysis.md/json` в текущем каталоге результатов.

Следующее **предложение для обсуждения**, ещё не реализовано: явный accepted TCP_NODELAY в обычном контролируемом TCP-стенде и свежая парная серия с прямым трафиком. Сейчас ProxyNoDelay разрешён только DiagnosticPull STANDARD, обычный STANDARD с ним недопустим. Новую команду дать после подготовки. Не менять/ослаблять progresspolicy; старый STANDARD7retained/two8INCONCLUSIVE/last4pending и оригиналы сохранить, не смешивать условия и не выбирать лучший diagnostic как benchmark. Core/driver/basehelper/native/defaults неизменны. Cleanup21,729GiB выполнена, не повторять. В этом шаге saved-data analysis/docs only; no newtraffic/code/build/install/autotests/subagents/commit/push. Для следующей подготовки GPT-6.1 Sol/high.

## Предыдущая точка: NODELAY результат повторился; RTT скачки и неполная ETW запись требуют запуска без WPR (2026-10-02)

Пользовательский повтор `tcp-pull-trace-20261002-053733-a8fc04`: MEASURED/errors=[]; read-only reevaluation точно совпала с saved report.8GiB/3100echo verified/failed0; helperPID12900/NODELAY1/135accepted=2workload+133explicit refusedUDP, socketgate confirmed.405nativeprogress/min9921784bytes/s/maxgap489.479ms/RTTwindow101.343s, zerosinsideRTT0. Один whole-log startupRecv0 TimeSlice0.003/observedQPC7075193.8467 раньшеRTTstart7078689.808; не заявлять absence любыхнулейвоwhole-run. Nativeactive521samples. **RTT29responses>20ms/max148.055ms/p9918.918ms**: MEASURED неозначает стабильную игровую задержку/latency SLA.

ETL3249012736bytes/SHA752D0E28...verified/receiptTRACE_SAVED_LIMIT_REACHED. Ordinary xperf отказался формироватьstats изза12lost buffers; явный-tle далpartialstats:LostBuffers12/LostEvents0. Rawlimitflagtrue/sumbefore2147745792, точныесырыеcollectorfilenames/sizes receipt несохраняет. Capskernel2GiB/state512MiB/ACK1GiBcircular; ранняяACK history uncertified. WPR liveEventsLost0 неотменяетfinal lostbuffers/cap. Нетwhole-run no-timeout/CPU-stall/cause inference; не увеличиватьcaps и не повторятьтяжёлуюзаписьвслепую. ВозможныйвкладETW вспайки — hypothesis, недоказаннаяпричина. Source/defaults/policy неизменны, originals preserved; `analysis.md/json`, `trace-statistics-partial.txt` вcurrentdir.

Все6workers exit0/unforced; CLI9280 graceful/poststop/capturetrue/errors=[],selectedserviceStopped/knownWFP+loadednames absent/global-versionfalse/WPRidle. Cfree~57.7GiB, cleanup21.729GiB ужевыполнен/неповторять. ДваNODELAYruns с measuredprogress безmid-windowzeros поддерживаютНейглhypothesis, неsolecause/fixproof/stability/benchmarkcompare; основнойSTANDARD7retained/two8INCONCLUSIVE/last4pending сохранён.

Следующий пользовательский admin запуск **того же isolated workload без ETW**, ужеготовыйcontroller, никакихновыхизменений:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-LocalTcpLoadedRtt.ps1" -Profile STANDARD -DiagnosticPull -ProxyNoDelay
```

Одинpull8GiB@64MiB/s+3100echo,3–5мин, auto fresh `artifacts/local-route/tcp-loaded-rtt-diagnostic-pull-standard-<UTC>-<id>`, ETL нет. Цель — progress/RTT spikes безheavyWPR, непарныйbenchmark. Agent fullrun НЕзапускает. Пока benchmarkdefaults/Core/driver/basehelper/native/progresspolicy не менять; исходныеhistoricalreports сохранить/no diagnostic mixing. Вэтомturn толькоsaved-data/hash/partialstats/docs, no code/runtime/build/install/autotests/subagents/commit/push. GPT-6.1 Sol/high дляследующегоанализа.

## Предыдущая точка: NODELAY прогон переоценён MEASURED; очистка фактически выполнена (2026-10-02)

Пользовательский `tcp-pull-trace-20261002-051553-4d84b4`: исходный отчётINCONCLUSIVE только из-за ошибочного socket-count gate.134accepted sockets включают2рабочих TCP flows/132UDP ASSOCIATE, каждый явно отклонён с UDP_NOT_CONFIGURED; обаworkload sockets before0→after1,PID4564/54123/peers61447bulk+61450echo совпадают сTCP_CONNECTED. Исправленный reporter требует ровно2совпадающихworkload options, правильныеPID/local/NODELAY1/noerror длявсехaccepted и Counter(extra peers)==Counter(explicit protoUDP addon_error peers) того жеPID. Никакие произвольные extras не игнорируются. Одно контрольноеUDPсоединение ETL53937 подтвержденоCLI13376→helper4564; все132callerPID индивидуально не атрибутированы. Не путать UDP associate control requests с UDP benchmark/дополнительными payload flows.

Read-only corrected reevaluation MEASURED/errors=[]; исходные workload report/FAILED manifest/receipt(workloadexit1) сохранены. Новый `diagnostic-reevaluation.json` и `analysis.md/json` отдельно, rule owned_flows_and_explicitly_rejected_udp_v2.8GiB+3100echo проверены, failed0,512native active rows/zero receive intervals0; RTT window394progress/min50450354bytes/s/maxgap372.921ms/98.627s. Прежний native progress gate НЕ менялся; baseline042738 всё ещё точно совпадает с savedINCONCLUSIVE/2zeros. Поддерживает гипотезуНейгл+ACK, не доказывает solecause/устранение всехпауз/стабильность/driver defect/benchmark acceleration.

ETL2103967744bytes/hash9D543743...verified/LostEvents0/LostBuffers0/TCPIP8616317actual events; в capturedtracestats нетDataTransferTimeout/RetransmitRound. HelperbulkTCBdf5862a0/54123→CLI61447; real getsockoptNODELAY1 +ETLSetTcpOption. CircularACK earlyhistory несертифицирована, отсутствие относится кcaptured events. Все6workers exit0/unforced,CLI graceful/poststop/capture true, selecteddriverStopped/knownWFP+loadednames absent/global-versionfalse/WPRidle. Текущий CsrcProxyBridge-Driver HEAD137d1286 неkit63be0eb; pinned63be0eb object в этомcheckout отсутствует, не использовать текущие source lines как provenance выбранного Core, не fetch/build/change безтаска.

Очистка реально удалила3targets/23331454976bytes=21.729GiB; всефайлы отсутствуют, current Cfree~61.6GiB. Сбой был ПОСЛЕ удаления: PS5.1 Measure-Object нечитает OrderedDictionary byteskey. Source исправлен наявный long sum/индексныйдоступ; PS5.1+7AST иbounded PS5.1 OrderedDictionary arithmetic нафактических saved sizes passed. Доошибочныйreceipt сохранён `disk-cleanup-20261002-before-accounting-repair.json`; currentreceipt COMPLETED_RECONCILED_AFTER_ACCOUNTING_ERROR/absencesverified/posthoc free отдельно, невыдумывать точныйfree-after cleanup. Повторно cleanup не запускать; completedETL/benchmark evidence/source сохранены. Агент новогоудаления неделал.

Следующая ручная команда дляпроверки воспроизводимости, не дляисправления уже полученных данных:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-TcpPullDiagnostic.ps1" -TcpAckTrace -ProxyNoDelay
```

Один isolatedSTANDARDpull8GiB@64MiB/s+3100echo,3–5мин+save/freshdir/free9GiB, ждём сохранения дажеприINCONCLUSIVE. Не менять benchmarkdefaults и не смешиватьinstrumenteddiagnostic сосновнойSTANDARD7retained/two8INCONCLUSIVE/last4pending; criterionrevision unapproved. Наэтомшаге только2bugfixes/saved-data reevaluation/scopedETLexports/docs; no new producttraffic/Core/driver/helper/native/build/install/autotests/subagents/commit/push. GPT-6.1 Sol/high дляследующегоанализа.

## Предыдущая точка: подготовлен отдельный NODELAY диагностический запуск; очистка требует ручного запуска (2026-10-02)

Следующие две команды пользователя, в административном PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Remove-AbandonedDiagnosticFiles.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-TcpPullDiagnostic.ps1" -TcpAckTrace -ProxyNoDelay
```

Очистка удаляет только3точно перечисленных файла:2rawETL прерванного DISK_FULL run tcp-pull-trace-20261001-190248-ba3e5b безmerged trace и616.6MiB ошибочной symbol download `.error`. Итого21.729GiB; completed ETL/исходники/benchmark evidence/малые failed receipts остаются. Агент НЕ удалил файлы: автоматическая проверка заблокировала batch и затем одно точное Remove-Item, причина `blocked by policy`. Все3файла ещё присутствуют; disk-cleanup-20261002.json statusBLOCKED_BY_AUTOMATIC_REVIEW/removed0. Ручной script проверяет resolved paths внутри repo/толькоfiles, безrecursive удаления, пишет список/результаты/free before-after. Только PS5.1/7AST проверен, фактическая очистка ещё не выполнена.

Новый opt-in `-ProxyNoDelay` через diagnostic wrapper/isolated controller выбирает `src/pb_tcp_nodelay_diagnostic.py`. Отдельный launcher проверяет SHA неизменённого base helper и wheel, создаёт subclassServer, перед существующим handshake ставит accepted TCP_NODELAY1/getsockopt и пишет `proxy-socket-options.jsonl` сPID/peer/local/before/after/error. Исходный helper/wheel/Core/driver/native и обычный benchmark default не менялись. Flag разрешён только DiagnosticPull STANDARD/newdir, нельзяResume/benchmark; записьconfig/receipt включает выбор и SHAlauncher/base. Reporter добавляет только условный diagnostic gate: ровно2owned flows/options с совпадающимиPID/endpoints/NODELAY1/noerror; прежний native progress gate не ослаблен. Историческая saved reevaluation по-прежнему совпадает с оригиналом INCONCLUSIVE.

Короткий manual engine-only no-ProxyBridge check `artifacts/diagnostics/tcp-nodelay-engine-check-20261002-050624/validation.json`: реальный launcher/Python/пинованный wheel,2SOCKS tunnels на2контролируемых ephemeral порта,2×3byte verified echo, оба accepted before0→after1, peers совпали сflow logs, receivers closed/helper STDIN_STOP exit0/no errors. PS5.1+7AST/UTF8BOM двух изменённых scripts/Python syntax passed. Это не full product/8GiB/strict-report integration и не доказательство причины/устранения пауз; долгий запуск не выполнялся.

Новый пользовательский run сохраняется отдельно в `artifacts/diagnostics/tcp-pull-trace-<UTC>-<id>`, один прежний8GiB@64MiB/s+3100echo,3–5мин+save/free9GiB, ACK collector1GiB Circular/kernel2GiB+state512MiB. Дождаться сохранения даже приINCONCLUSIVE; затем сравнить характер пауз и фактические options с предыдущей baseline ACK trace, без benchmark mixing/объявления исправления по одному успешному run. Строгая policy неизменна, STANDARD7retained/two8INCONCLUSIVE/last4pending. Нет нового product traffic/Core/driver/base-helper/native change/build/install/autotests/subagents/commit/push. Для результатов GPT-6.1 Sol/high.

## Предыдущая точка: подтверждена настройка Нейгла в SOCKS helper; причинность требует отдельной проверки (2026-10-02)

Пользовательский `tcp-pull-trace-20261002-042738-c86d35` повторно оценён read-only: результат полностью совпал с оригиналом, INCONCLUSIVE только native progress. 8GiB/3100echo проверены, ошибок нет;2receive zeros внутри RTT,395observations/maxgap379.488ms. Шесть workers естественно exit0; CLI graceful/owned post-stop/capture true; selected driver Stopped/known WFP+loaded names absent, global/versionfalse. ETL2294808576bytes/SHAverified/LostEvents0/LostBuffers0/8601042TCPIP events. Circular ACK history не сертифицирован целиком. Полный анализ и JSON: `artifacts/diagnostics/tcp-pull-trace-20261002-042738-c86d35/analysis.md`, `analysis.json`; исходные workload reports/history не перезаписаны.

На helper accepted TCBdfb68050/54123→CLI58572 обе целевые паузы306.608/307.586ms имеют один рисунок: окно~4MiB открыто,4096unacked, ещё15posts×4096 поднимают SendAvailable65536, новых processedACK нет доtimer. CLI в начале ещё получает20480+4096, послеtimer61399+41; отсутствие ACK не означает отсутствие доставки первого блока. TotalRT300/RTO600; classic zero-size retransmit не доказывает payload loss, internal SendTransmitted не wire proof. Raw headers отсутствуют. Изначальная причина отсутствия своевременного ACK/атрибуция компонентам/старым runs ещё не доказана.

Новая воспроизводимая настройка стенда: pinned asyncio-socks-server1.3.3 listener создан через socket.create_server(protocol0), accepted сохраняетproto0; bundled Python3.12.14 `_set_nodelay` проверяетproto6 и пропускает этотsocket. В helper/wheel позднего setsockoptNODELAY нет. Короткий ручной no-product probe того же factory/start_server/Selector реально прочитал acceptedNODELAY0 и обычный outboundNODELAY1; limits16/64KiB, explicit set→1,3+3bytes verified/owned sockets closed. `socket-options-probe.py/json` в diagnostic directory. Это воспроизведение конфигурации, не historical live getsockopt.

Гипотеза Нейгл+ACK wait/малые записи стала существенно сильнее, но причинность/устранение пауз ещё не проверены. Следующий предложенный шаг: отдельный opt-in launcher поверх неизменённого helper/wheel, accepted TCP_NODELAY1 с фактическим журналом каждого socket; один новый диагностический pull с теми же ACK instrumentation/traffic/strict criteria. НЕ реализован, команды нового режима пока нет. Не ослаблять критерий, не объявлять исправление и не менять обычные benchmark defaults/Core/driver/native. После подготовки пользователь запускает3–5мин+save/freshdir; не запускать долгий run самим и не смешивать с benchmark.

STANDARD остаётся7retained/two8INCONCLUSIVE/last4pending, revision unapproved. На завершение WPRidle/ProxyBridgeDrvStopped. Только saved-data анализ и маленький manual socket-option probe; никаких product traffic/helper source changes/build/install/autotests/subagents/commit/push. GPT-6.1 Sol/high для следующей подготовки.

## Предыдущая точка: подготовлена диагностика обработанных ACK/окна TCP (2026-10-02)

Следующая команда пользователя из административного PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-TcpPullDiagnostic.ps1" -TcpAckTrace
```

Один прежний isolated STANDARD pull PROXY:8GiB@64MiB/s +3100echo, около3–5мин плюс сохранение, новая папка `artifacts/diagnostics/tcp-pull-trace-<UTC>-<id>`. При workload INCONCLUSIVE дождаться сообщения о сохранении trace. Сама нагрузка/строгий progress gate/Core/driver/helpers/native binaries не изменены; основная STANDARD серия всё ещё7retained/two8INCONCLUSIVE/last4pending, revision unapproved. Дополнительное инструментирование не использовать как benchmark comparison.

Выбор метода: native PktMon проверен на малом loopback exchange сначала TCPIP component9, затем all components; оба0packets/пустойpcapng. Обе owned sessions stopped/filters cleaned to none. Не устанавливались Wireshark/Npcap и не делается общий вывод о невозможности любого PktMon loopback capture. Вместо обещания raw TCP headers используется ETW TCP metadata, реально работающая на этом ПК.

Новый opt-in `-TcpAckTrace` в wrapper включает state и `config/tcp-pull-ack-diagnostic.wprp`: прежний kernel2048MiB Sequential/state512MiB Sequential, дополнительный ACK1024MiB Circular collector/128KiB×128 buffers, тот же TCPIP GUID/Strict/NonPagedMemory/Level5. Только ACK event IDs1159,1160,1330,1331,1429,1587,mask0x300000000. Posted/transmitted bytes, processed cumulative/careful ACK, sequences/send-window. Это metadata всегоPC, отбор нужного TCB при анализе; не wire packet capture/нет payload. Ранние ACK events могут быть перезаписаны даже при LostEvents0; receipt schema3 явно НЕ сертифицирует полный ACK history. Требуется9GiB free для raw+merged, запись собственная/прежний idle/cleanup gate сохранён. Достижение caps/overwrite под полной нагрузкой не проверено.

Проверка exact final profile: `artifacts/diagnostics/tcp-ack-profile-check-20261002-041303/validation.json`. Controlled local3bytes+3bytes/PID10936/port58924: оба TCB привязаны к адресам;2SendPosted/2data SendTransmitted/2data CumAck по3bytes, SndWnd65280/SeqNo; отдельные2FIN ACK по1sequencebyte и3CarefulAck. Acked bytes не всегда application payload: FIN учитывается отдельно. ETL17825792bytes SHAverified/LostEvents0/LostBuffers0, owned sockets closed/recording stopped/idle. WPR profiledetails/XSD и PS5.1+7 AST/UTF8BOM wrapper passed. Полный wrapper с новым opt-in/продуктом не выполнялся; изменены только диагностический wrapper/profile и текущие записи, не автотесты/сборки/установка/Core/driver/helper/native/commit/push/subagents.

Причина старых пауз пока прежняя: TCP timeout/flush на helper→CLI, первоначальный ACK/window/Nagle/component trigger неизвестен. Следующий анализ — GPT-6.1 Sol, высокое усиление. Глобальная очистка/version-switch/4.0.0/remote/UDP выводы не подтверждены.

## Предыдущая точка: паузы связаны с TCP timer на SOCKS5 → CLI; первоначальная причина неизвестна (2026-10-02)

Пользовательская запись `tcp-pull-trace-20261002-034057-5b74e1`: INCONCLUSIVE только из-за строгого progress gate;8GiB и3100echo проверены, все owned workers/CLI остановились естественно, selected driver/known inventories absent, global/versionfalse. Native6 receiving zero intervals,4inside RTT;398samples/maxgap373.469ms. ETL1.43GiB/SHA verified/lost0; исправленный state provider записал115593 событий. Полный анализ: `artifacts/diagnostics/tcp-pull-trace-20261002-034057-5b74e1/analysis.md` и `analysis.json`.

Bulk TCB/helper54123→CLI52184:13 expire/retransmit-round/timeout событий,4096unacked/TotalRT300/RTO600. В4целевых окрестностях нулей gaps308.657–312.901ms и ещё соседний308.311ms. CLI bulk recv ждёт socket; после Ready12us доCPU, helper select7us. Resume stack TCP periodic timer→TcpFlushDelay→send/loopback/receive. На native server→helper отдельном TCB zero-window state первого gap310.726ms; на helper→CLI нет sender SWS/zero-window за lifetime, на CLI→native максимум3.678ms. Это уточняет механизм/участок, но не доказывает первоначальную причину ACK/window/Nagle, driver defect/ответственность компонента или причины старых runs. Zero-size classic retransmits не доказывают payload loss. Native/observed QPC/ETL эпохи не отождествлены; timeline kernel events доказан внутри одной ETL.

Повторно только прочитаны saved evidence и сформированы целевые экспорты; исходные reports не перезаписаны, workload/policy/Core/driver/helpers/native/code не менялись. WPR idle/ProxyBridgeDrv Stopped, Cfree43.85GiB. Нового traffic/build/install/autotests/subagents/commit/push не было. STANDARD7retained/two8INCONCLUSIVE/last4pending; revision unapproved, диагностику не смешивать с benchmark.

Следующий предлагаемый шаг: получить ACK/SEQ/advertised-window TCP headers для этого bulk-соединения ограниченным методом; сначала подготовить/проверить loopback capture/caps/cleanup. Такой метод и новая команда ещё не подготовлены, не предлагать запуск прежнего state profile вслепую. При необходимости отдельный SOCKS5 control без ProxyBridge для атрибуции (также не подготовлен). GPT-6.1 Sol, высокое усиление для следующей подготовки/анализа.

## Предыдущая точка: INCONCLUSIVE воспроизведён; исправлена фактическая запись TCP state (2026-10-02)

User tcp-pull-trace-20261001-195509-29f985: workload1/strict INCONCLUSIVE only insufficient native progress,8GiB+3100echo verified/no failures/route/PC/clean owned shutdown;6workers exit0/unforced/CLI graceful+poststop+capture, driver/known WFP+loaded names absent/global/versionfalse. Native zeros8.012/80.261/98.259 внутри382RTT samples/maxgap351.591ms;128.517после. Trace1.02GiB hash/lost0/span142.796s verified. ETW first gap~308ms on3legs; CLI recv waiting307.554ms, ctsclient/receiver WrQueue~308ms, Ready→CPU15–52us; resume stack TCP periodic timer/TcpFlushDelay, zero-size TCP retransmit. Это не доказательство Nagle/window/driver defect/старых причин; time epochs точно не синхронизированы. Analysis.md/extracts в diagnostic dir, partial network symbol export остановлен ownedPID16108, offline cached symbols export completed.

TCP state collector текущей user trace имеет0actual provider events (lost0 не coverage). Диагностическая настройка NonPagedMemory=false была ошибкой. Bounded6byte local socket/no-product probes: GUID/Strict/EventId filter безnonpaged0events, сnonpaged111; исправленный EXACT final profile16actualTCPIPevents/addresses/accept/connect, loss0/stop/trace saved/idle. Receipt artifacts/diagnostics/tcp-state-final-profile-check-20261001-201323. Invalid brace-GUID setup probe оставил собственную malformedWPR configuration; только она очищена после matching receipt/error, последующиеidle подтверждены. Без foreign cancellations/product runs. XSD/profile parsing/PS5.1+7AST/BOM passed. No full final profile workload yet.

Исправлен TCP state profile: exact GUID/Strict/NonPagedMemory=true/Level5/mask0x87 +24explicit IDs (no perpacket17, omit high-frequency timerstart/stop1064/1065), kernel2GiB+state512MiB caps/free6GiB. Wrapper recordsfilter/nonpaged, catches HRESULT start errors evenexit0/keeps accepted config owned for stop; default/workload policy/helpers/Core/driver/native unchanged. Next user admin same Invoke-TcpPullDiagnostic.ps1 -TcpStateTrace (~3–5min+save/newfolder), not blind main-series resume. Await trace before attribution; original7retained/two8INCONCLUSIVE/last4pending, progress revision NOT approved; no benchmark mixing/global/version/4.0.0/remote/UDP claims/autotests/build/install/commit/push/subagents. GPT-6.1 Sol/high next analysis.

## Предыдущая точка: TCP socket wait/таймер подтверждены; подготовлен TCP state trace (2026-10-02)

Пользовательский tcp-pull-trace-20261001-192930-c3a688 completed/workload0/TRACE_SAVED,8GiB+3100echo verified/failures0, strict reporter read-only reevaluation MEASURED/PASS/errors=[]. Trace1.02GiB SHA matched, xperf span144.764s/lost events+buffers0. Все6workers exit0/unforced, CLI ready/graceful/post_stop/outputcapture true/error empty, selected driver/known WFP/loaded names absent; global/version gates false. Во measured RTT382positive rows/maxgap354.627ms; native whole-transfer receive zeros1.518/124.518s вне RTT, поэтому verdict не означает отсутствие пауз. ETW показатели не смешивать с benchmark.

Read-only xperf late133–138s: bulk TCP gap~302ms на всех3legs. CLI9640 recv wait301.876ms/Python15008 select wait301.761ms, ctsclient3988WrQueue301.917ms/receiver2072WrQueue302.829ms; post-ready dispatch19–52us. Resume136.577s stack TcpPeriodicTimeoutHandler→TcpFlushDelay→TcpTcbSend/loopback, Python→CLI zero-size TcpRetransmit. Не делать driver/loss/Nagle/delayed ACK/zero-window claim: точное условие ожидания неизвестно, classic events не содержат advertised window/ACK state, process-local native TimeSlice точно не синхронизирован с ETL. Исторические причины двух INCONCLUSIVE не доказаны. Детали/compact evidence artifacts/diagnostics/tcp-pull-trace-20261001-192930-c3a688/analysis.md+analysis.json, exports/stats/symbols сохранены; symbols официальные Microsoft.

Подготовлен opt-in Invoke-TcpPullDiagnostic.ps1 -TcpStateTrace/config/tcp-pull-state-diagnostic.wprp: existing kernel2GiB cap + separate TCPIP512MiB cap, Level5/mask0x87(endpoint/listener/TCB/diagnosis) excludes packet-level17/SendPath+ReceivePath masks. Installed provider metadata verifies SWS/zero-window/timeout events; next inspect/correlate actual events, не обещать воспроизведение. Requirefree6GiB; merged extra, Sequential cap=incomplete warning. Default diagnostic/strict workload/helpers/Core/driver/native unchanged; unconditional console INCONCLUSIVE text corrected to preserved workload verdict. XSD/WPR profiledetails/PS5.1+7 AST/BOM and3s no-product/no-traffic elevated WPR setup passed bothcollectors/lost0/trace saved/stop/idle. Full state-trace workload not run. No builds/installs/autotests/subagents/commit/push.

Следующая пользовательская admin команда (~3–5мин+save, fresh auto directory): powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-TcpPullDiagnostic.ps1" -TcpStateTrace. Дождаться trace save even INCONCLUSIVE, сообщить папку. STANDARD7 retained/two8INCONCLUSIVE/last4pending; load policy revision NOT approved, no blind main-series retry, no global/version/4.0.0/remote/UDP claims. GPT-6.1 Sol/high next analysis.

## Предыдущая точка: исправлена запись diagnostic receipt в Windows PowerShell 5.1 (2026-10-02)

Попытка `artifacts/diagnostics/tcp-pull-trace-20261001-192702-d89a43` завершилась ДО запуска workload: Save-Receipt после WPR start вызвал File.Replace с $null, который PS5.1 преобразовал в empty string backup path, ArgumentException «Путь имеет недопустимую форму». Primary receipt остался PREPARING, полная финальная запись находится в diagnostic-receipt.tmp (FAILED, workload_exit_code=null). Finally всё же остановил WPR и сохранил cpu-network.etl16252928bytes; native stop exit0/trace saved, hash100A5F97B021F462E507E7CF26E35DCB98DC8C658C160BA317C7E6962342810D. Это короткая трасса без workload, не пригодна для расследования receiving zeros. Read-only сейчас WPR idle/ProxyBridgeDrv Stopped. Исторические primary/tmp сохранены без подмены статуса.

Invoke-TcpPullDiagnostic.ps1 теперь передаёт [Management.Automation.Language.NullString]::Value в backup path File.Replace. Ручная проверка .NET file API в реальном WindowsPS5.1: создание и две последовательные atomic замены прошли, конечное содержимое final (artifacts/diagnostics/receipt-write-check-20261002/receipt.json). PS5.1/7 AST0errors, UTF8 BOM сохранён. Это проверка записи файла, без WPR/product/traffic/build/автотестов кода/commit/push; полный wrapper ещё не выполнен с исправлением.

Пользователь повторяет ту же admin команду `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-TcpPullDiagnostic.ps1"`. Один diagnostic pull PROXY (~3–5мин плюс сохранение), новая папка, bounded raw WPR2GiB/merged extra; even workload INCONCLUSIVE дождаться trace save. Причина receiving zero-rate неизвестна, load policy не менялась/не согласована. Основная серия7retained+2INCONCLUSIVEattempts8/последние4pending; diagnostic не сравнивать с benchmark. GPT-6.1 Sol/high для анализа. Предыдущие точки ниже исторические.

## Предыдущая точка: диагностический запуск прерван заполнением диска; запись ограничена (2026-10-02)

Последний пользовательский diagnostic: `artifacts/diagnostics/tcp-pull-trace-20261001-190248-ba3e5b`. В workload/pull-pair-01-proxy/run-receipt.json FAILED с «Недостаточно места на диске» при workload и helper cleanup. diagnostic-receipt.json пуст, merged cpu-network.etl отсутствует. Сохранились raw WPR Event Collector 21885878272 bytes и System Collector 799014912 bytes; ряд JSON receipts пуст. Не объявлять workload/очистку подтверждёнными по повреждённым файлам. Старые raw файлы сохранены, не смешивать с новыми измерениями. Это установленная причина остановки диагностики, причина receiving zero samples основной серии всё ещё неизвестна.

Пользователь увеличил Hyper-V disk на50GiB и явно разрешил удалить recovery. Выполнены reagentc /disable, удаление только disk0 recovery partition4 и расширение C partition3 до160833715712bytes (~149.79GiB), NTFS Healthy; EFI/MSR сохранены. Receipt: artifacts/machine-setup/disk-expansion-20261002/expansion-result.json. WinRE disabled. Read-only после: ~51.97GiB свободно, ProxyBridgeDrv Stopped, целевые CLI/native/helper процессы отсутствуют, WPR idle; это текущее наблюдение, не восстановление отсутствующих исторических cleanup gates.

Заменён неограниченный built-in CPU+Network на `config/tcp-pull-diagnostic.wprp`: единственный kernel collector ProcessThread/Loader/CpuConfig/CSwitch/ReadyThread/SampledProfile/DPC/Interrupt/NetworkTrace, scheduling stacks, без широкого TCPIP event provider. MaximumFileSize2048MiB/Sequential прекращает запись при лимите (не кольцевое стирание); merged output требует дополнительное место, прежний free5GiB gate остаётся. Wrapper сохраняет profile copy/hash, raw bytes/limit flag; TRACE_SAVED_LIMIT_REACHED и warning означают неполную запись. Ошибка inspection/logging не должна пропускать остановку принадлежащей wrapper записи. diagnostic receipt теперь записывается через temporary+atomic replacement, чтобы не обнулять последнюю полную копию. Строгие workload/progress assertions не менялись.

Проверены WPR XSD и -profiledetails, PS5.1/7 AST и UTF8 BOM. Один ручной setup probe без продукта/трафика,3s: artifacts/diagnostics/wpr-bounded-profile-check-20261001-192455/receipt.json, started/stopped/trace_saved=true,error='', merged25165824bytes, lost events0, WPR idle после. Достижение2GiB на практике не проверялось, новый полный diagnostic ещё не выполнен; объём/полнота реальной трассы будут проверены после запуска. Нет сборок/установок/автотестов кода/commit/push/Core/driver/native изменений.

Следующая admin команда пользователя: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-TcpPullDiagnostic.ps1"`. Один pull PROXY8GiB@64MiB/s +3100echo,~3–5мин плюс сохранение trace; новая папка artifacts/diagnostics/tcp-pull-trace-<UTC>-<id>. Даже при workload INCONCLUSIVE дождаться сохранения trace и сообщить папку/консоль. Не запускать полную серию и не менять критерий без согласования. STANDARD7 retained, original+retry8INCONCLUSIVE, последние4pending. Диагностическая ETW нагрузка не сопоставляется с бенчмарком. GPT-6.1 Sol/high для следующего анализа; global/version/4.0.0/remote/UDP claims по-прежнему запрещены.

## Предыдущая точка: расследование нулевых receive samples; подготовлена Windows trace диагностика (2026-10-01)

Пользователь спросил, можно ли выяснить причину; начато расследование без изменения load policy. Из официального Microsoft ctsTraffic repository на pinned revision b0e2a48... получены шесть целевых source files (не сборка/установка/тесты): `artifacts/diagnostics/cts-zero-rate-20261001/source-receipt.json` с URL/SHA. ctsIOPattern.cpp:500–513 прибавляет bytes при завершении IO (Recv/Send), ctsPrintStatus.hpp:464–481 вычисляет interval rate, ctsStatistics.hpp:350–368 snapshot delta. RateLimitPolicy применяется к Send, не искусственно ограничивает клиентский Recv в pull. Консоль и CSV в обоих проблемных runs имеют одинаковые нули, следовательно ошибка CSV parsing TestLab не объясняет их. По source нулевая rate отражает счётчик completion приложения, а не прямое доказательство отсутствия TCP bytes на проводе/конкретного виновника.

Полные native status файлы показывают поДВА receiving zero intervals в каждом проблемном transfer: original27.507/126.015s, retry38.506/111.265s (в каждом внутри RTT только один, второй после RTT). Имеющиеся6 upload и1 direct download таких zero In-Flight status rows после1s не имеют. Около двух наблюдавшихся внутри RTT нулей sampler интервалы251–266ms, systemCPU2–5.7%, echo за±500ms продолжает отвечать, max2.31/1.78ms. Это не исключает задержку конкретного потока/IO; общей остановки всех участников не видно, конкретная причина не установлена. Native client/server CSV epochs не доказаны синхронными; не выводить направление/точную длительность блокировки только из совпаденияTimeSlice.

Подготовлены `scripts/Invoke-TcpPullDiagnostic.ps1` и opt-in `Invoke-LocalTcpLoadedRtt.ps1 -DiagnosticPull` (новый isolated STANDARD directory, только один pull PROXY run). Все прежние gate/нагрузка/binary/helpers неизменны; strict INCONCLUSIVE допускается как диагностическое наблюдение, не повышается до product pass. Wrapper сначала требует idle WPR, запускает built-in CPU+Network filemode, затем один8GiB@64MiB/s transfer+3100echo; always tries to save owned recording in finally, сохраняет WPR status/lost-event raw output/trace receipt/QPC timing/SHA. Не отменяет чужую запись; минимум5GiB свободного места для trace. ETW добавляет инструментирование, результаты этого run НЕ смешивать с основной серией/overhead comparison. Trace сохранение не означает workload correctness pass, receipt разделяет trace_saved и workload exit. Нельзя заранее обещать воспроизведение/точную причинную атрибуцию: нужны actual trace/events/loss quality/потоковые ожидания.

Проверено read-only: wpr.exe/pktmon/tracerpt уже есть; CPU profile CSwitch/ReadyThread/SampledProfile, Network provider Microsoft-Windows-TCPIP, WPA установлен; WPR не записывает. Официальный WPR CLI reference: https://learn.microsoft.com/en-us/windows-hardware/test/wpt/wpr-command-line-options. PS5.1/7 AST+BOM обеих изменённых scripts passed. Нет runtime trace/нового traffic/build/autotests/commit/push. Core/driver/native helpers не изменены.

Следующая пользовательская admin команда: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-TcpPullDiagnostic.ps1"`. Около3–5мин плюс сохранение trace, новая artifacts/diagnostics/tcp-pull-trace-<UTC>-<id>, cpu-network.etl и diagnostic-receipt.json. Даже при workload INCONCLUSIVE wrapper сохраняет trace, сообщаетпапку. После запуска исследоватьTCP legs/потоки вокругнулевого observedQPC; при невоспроизведении не объявлять fix. User has NOT approved changed progress criterion: предложение осталось pending/разъяснено, диагностический task не даёт согласия на ослабление. Полная STANDARD остаётся incomplete (7 retained, original+retry8 inconclusive,9–12not run). GPT-6.1 Sol/high для trace analysis; global/version/4.0.0/remote/UDP ограничения сохраняются.

## Предыдущая точка: повтор STANDARD тоже остановлен; пересмотр load-критерия предложен (2026-10-01)

Пользователь выполнил Resume: первые7 retained; `pull-pair-01-proxy-retry-20261001-184104-62b617` снова INCONCLUSIVE по единственному основанию Insufficient positive in-flight native load progress during RTT. Всего392 status observations внутри98,104s RTT-окна; одна RecvBps=0 (TimeSlice38.506), In-Flight1/Completed0/NetError0/DataError0. Нет пропусков наблюдения: max gap363ms, max gap положительных observations565ms. В исходной попытке387/388 положительных/max positive gap445ms; в повторе391/392. Обе попытки по8GiB и3100echo полностью проверены, failures0; повтор p50 0,545/p95 2,010/p99 3,071/max4,016ms, >20ms0. CPU/route/data/owned cleanup остальные gates прошли. Все6 workers exit0/unforced/capture complete, CLI ready/graceful/post_stop true/unforced/no error; known WFP detached/loaded names complete+absent после обеих. Не присваивать этим INCONCLUSIVE статус MEASURED в текущих отчётах.

Соединение/load running до окончания RTT; sender status около38.518 фиксирует SendBps79,8MB/s, client до/после нуля положительный. Epoch native client/server CSV не подтверждён как синхронный, точная причина нуля неизвестна. Не утверждать driver defect/сетевую паузу250ms только по status строке. Семь первых результатов сохранены, история original attempt сохранена в manifest failed_attempts; следующий повтор восьмого вслепую не предлагать.

Предложение пользователю (через async вопрос, ответа пока нет): пересмотреть требование положительного receiving progress в КАЖДОЙ выборке. Для бенчмарка сохранить нулевые/низкие интервалы как явный результат «нагрузка с паузами», измерять RTT только при достаточном подтверждённом прогрессе и живой сессии; одинаковый критерий OFF/PROXY, достаточные свежие observations/ограничение разрыва между положительными observations/route/data/identity/cleanup обязательны. Недостаток свидетельств/длительные провалы/ошибки не переводить в успешный замер. Точные правила/новый versioned report подготовить после согласования, исходные INCONCLUSIVE reports не переписывать, паузы/повтор не скрывать. Если одобрено, одинаково оценить все сохранённые raw runs; брать исходную восьмую, повтор отдельной диагностикой, не выбирать лучший по результату. Цель — исключить отбор только удачных прогонов и измерять возможные ухудшения. Предложение пока НЕ реализовано; старый критерий и scripts unchanged this turn.

Текущий шаг — await user decision, без новых product runs/команд до решения. Только evidence analysis/docs, без code/autotests/build/install/commit/push. GPT-6.1 Sol/high для согласованной переработки критерия/отчёта. Local IPv4 Driver63be0eb kit/global/version/4.0.0/remote/UDP limitations сохраняются. Предыдущая текущая точка ниже — историческая.

## Предыдущая точка: STANDARD остановлен на нулевой выборке нагрузки; подготовлен Resume (2026-10-01)

Пользовательский `tcp-loaded-rtt-standard-20261001-180353-a989a9`: manifest FAILED/TCP_EVIDENCE_NOT_CONFIRMED. Первые7 runs COMPLETED/MEASURED/PASS/errors=[]; восьмой pull-pair-01-proxy runtime receipt COMPLETED, но reporter INCONCLUSIVE: Insufficient positive in-flight native load progress during RTT. Восьмой полностью проверил8GiB bulk/3100 echo (3000 measured), failures0, route/hash/GUID/PC/cleanup остальные gates прошли; все owned workers/driver stopped=true. Ниже не повышать этот прогон до MEASURED.

Фактическая причина gate: единственная из388 наблюдаемых status rows внутри RTT-окна имеет RecvBps=0 (TimeSlice27.507, In-Flight1, Completed0, NetError/DataError0). Max observation gap360.7ms<1000ms, то есть это не пропуск журнала/наблюдений. До/после положительные53.5/74.6/83.1/54.8MB/s интервалы; native sender в соседнем по относительному времени27.501 status фиксировал SendBps57.2MB/s. Native CSV epochs не синхронизированы; это наблюдение не устанавливает конкретную причину паузы/driver bug. Нет повреждения payload/закрытия load до RTT; load_running_at_rtt_exit=true. Нулевой интервал получения нельзя спрятать или доказать исправление повтором.

Добавлен Invoke-LocalTcpLoadedRtt.ps1 -Resume для FAILED STANDARD: read-only --validate-resume повторно вычисляет evidence первых завершённых runs и сравнивает saved results; текущая7-run prefix прошла (RESUME_VALIDATED,remaining5). Проверяются порядок/конфигурация/engine+helper+Python digests/product bundle/действующая OFF driver inventory; удерживаются только непрерывный verified prefix, завершённая очистка неуспешной попытки обязательна. Перед записью сохраняется исходный manifest backup; retry в новой подпапке, original INCONCLUSIVE evidence не переписывается, failed_attempts включается в JSON/summary. Временной разрыв/исключённая попытка явно указаны; успешные повторы не доказывают отсутствие исходных пауз/сбоев. Критерии progress/route/payload/cleanup НЕ ослаблены. Core/driver/native/helpers/нагрузка не менялись, только controller Resume и reporter history/read-only validator. Проверены PS5.1/7 AST+BOM и Python compilation; реальная resume серия ещё не запускалась. Автотестов кода/commit/push нет.

Следующая команда пользователя (admin): `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-LocalTcpLoadedRtt.ps1" -Profile STANDARD -Resume -EvidenceDirectory "C:\src\ProxyBridge-TestLab\artifacts\local-route\tcp-loaded-rtt-standard-20261001-180353-a989a9"`. Повторяется восьмой и выполняются9–12, пять runs/40GiB loopback payload, примерно12–16мин. Не перезапускать первые7 без причины. Full comparison ещё отсутствует; завершённый upload можно анализировать отдельно, download пока incomplete. GPT-6.1 Sol/high при продолжающемся разборе этого случая, medium для штатного завершения. Local IPv4 selected kit/global/version ограничения сохраняются; UDP defects не проверялись.

## Предыдущая точка: TCP RTT под нагрузкой SMOKE подтверждён (2026-10-01)

Пользовательский `tcp-loaded-rtt-smoke-20261001-172113-5c7084`: COMPLETED4/4 PASS/MEASURED/errors=[], LIMITED_COMPARISON/errors=[]. Подтверждены512MiB bulk verify:data/ConnectionId и576 echo (512 measured+64 excluded warmup), failures0. Два controlled порта/два продуктовых PROXY правила/route и payload assertions прошли. Во всех RTT-окнах по16 свежих положительных native load progress samples, max gap343–357ms, min role PC coverage92,7–97,4%; передача была активна до завершения RTT. Все6 workers/run exit0/unforced/capture complete, обе CLI ready/graceful/post_stop/capture=true/forced=false/error empty. Receipts worker/driver stopped/receiver identity=true; known WFP detached и complete/absent known loaded names после всех4 runs. Global/version gatesfalse; UDP defects не проверялись.

Upload OFF/PROXY p50 0,220/0,576мс,p95 0,365/1,703,p99 0,410/2,326; paired deltas+0,355/+1,339/+1,916мс. Download p50 0,238/0,513,p95 0,371/1,822,p99 0,429/2,371; deltas+0,274/+1,451/+1,942мс. PROXY max2,438/2,432мс, >20ms0. Bulk67,48/67,53Mbit/s upload и67,48/66,65 download при настройке8MiB/s. Это по одной короткой паре/128 measured echoes в направлении, readiness/full instrumented path, не длительная устойчивость/driver-only/game claim. CLI CPU samples upload0,0%/download0,609% whole-PC, private RAM2,95/3,30MiB; ноль в коротком окне не отсутствие затрат. Старые unloaded условия не matched baseline.

Разбор только сохранённых evidence; код/движки/параметры не менялись, нового runtime/build/autotests/commit/push нет. План/память обновлены. Следующая пользовательская команда из admin PowerShell: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-LocalTcpLoadedRtt.ps1" -Profile STANDARD`.12 runs/3 counterbalanced pairs на направление,8GiB@64MiB/s/run (96GiB loopback payload, без payload файлов),3000 measured+100 warmup echo/run,512bytes/20ms pause; ориентировочно25–35мин. STANDARD ещё не выполнен; не смешивать цифры разных SMOKE/STANDARD нагрузок. Local IPv4 Driver63be0eb kit only, upstreamHEAD/4.0.0 A-B/remote/global/version переключение не подтверждены. GPT-6.1 Sol/medium для разбора, high при сбое; полную серию запускает пользователь.

## Предыдущая точка: подготовлен TCP RTT под одновременной передачей (2026-10-01)

По «Продолжай» подготовлен `scripts/Invoke-LocalTcpLoadedRtt.ps1` и `src/pb_tcp_loaded_rtt_report.py`. Переиспользуются pinned ctsTraffic2.0.3.9 (Apache2, verify:data) и существующий native TCP echo/QPC без изменения бинарника, выбранный Driver63be0eb CLI kit/Core/драйвер не менялись. RTT receiver54122 и bulk receiver54126 — независимые контролируемые порты; SOCKS54123 разрешает только эти два назначения. Два process-specific PROXY правила; OFF не запускает продукт, сохраняет одинаковые receiver/proxy/sampler и прежние SCM/WFP/loaded inventory gates. Разные направления push/pull, внутри каждого counterbalanced OFF/PROXY pairs. Обязательны payload/run/seq/SHA, native ConnectionId/data/volumes, socket/owned proxy flow byte counters, оба product PID/port/config-ID route observations, штатный exit/capture/cleanup. Не считать получение данных без route доказательством корректности.

SMOKE:4 runs,128MiB bulk@8MiB/s на запуск,128 measured+16 warmup echo,512bytes/20ms pause. Около2–5мин, readiness only. STANDARD (пока не запускать):12 runs,8GiB@64MiB/s/run,3000+100 echo, ориентировочно25–35мин/96GiB реального loopback payload без записи payload на диск. RateLimit — настройка, не строгий потолок; это ~2мин передачи на socket, не maximum capacity/hours stability. Для обоих профилей CPU/RAM измеряются в RTT-окне после прогрева, включая load_generator/load_receiver и прежние роли; driver-only/watts не измерены.

Генератор ctsTraffic запускается первым; RTT ждёт native status rate≥5% настройки и In-Flight=1. Реальные свежие CSV rows наблюдаются с QPC каждые100ms (native status250ms), BUFFERED progress journal; финальный отчёт сверяет их с настоящим native CSV/PID, строгий рост TimeSlice/QPC, минимум3 положительных samples внутри RTT-окна, разрыв≤1000ms, errors=0, load running при завершении RTT. Если load закончился раньше/свидетельств недостаточно — остановка/INCONCLUSIVE, не измерение unloaded под видом loaded. Интервальные observations не доказывают непрерывный одинаковый темп в каждый момент. Proxy helper opt-in дополнительный whitelist port; стандартные single-port calls сохранены, но helper SHA изменился. Старые unloaded/transfer reports не смешивать с новым профилем. RTT evaluator выделен для повторного использования; existing STANDARD pair-01-proxy повторно оценён read-only:MEASURED/errors=[], без изменения старого report.

Проверено: PS5.1/7 AST, UTF8 BOM; Python py_compile/CLI imports. Ограниченная ручная проверка движков **без ProxyBridge**: `artifacts/local-route/tcp-loaded-rtt-engine-check-20261001-171357-3f3ca6/manual-receipt.json`. Две диагностические SOCKS5 tunnels через существующий временный pproxy; actual controller workload переиспользован без product lifecycle. Push/pull: по128MiB verify:data/GUID/socket/owned helper bytes +144 exact echo (288 total), по2 SOCKS flows к разным controlled ports, все7 процессов/направление exit0/unforced. RTT окна4,172/4,203с, по17 native positive-progress observations внутри, max gap342/338ms; пять PC roles по15 samples/coverage~92,7%. Это готовность движков/наблюдения, **не полный product PASS/benchmark**. Диагностические tunnels не используются в пользовательской серии. ProxyBridgeDrv после подготовки Stopped; новых product/runtime/Core/driver изменений, автотестов кода, commit/push нет.

Следующая команда пользователя из admin PowerShell: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-LocalTcpLoadedRtt.ps1" -Profile SMOKE`. Полная связка/два продуктовых правила/loaded report ещё не проверены с ProxyBridge; STANDARD после успешного SMOKE и разбора. Новая evidence папка tcp-loaded-rtt-smoke-*. GPT-6.1 Sol/medium для разбора, high при сбое. Selected local IPv4 kit only; upstream HEAD/4.0.0 A-B/remote/global cleanup/version switching остаются неподтверждёнными. UDP regressions не проверялись.

## Предыдущая точка: TCP RTT STANDARD завершён (2026-10-01)

Пользовательский `tcp-rtt-standard-20261001-160242-e79c52`: COMPLETED,6/6 PASS/MEASURED/errors=[], comparison LIMITED_COMPARISON/errors=[].6600/6600 проверенных echo,600 warmup исключены,6000 measured (3000 OFF/3000 PROXY), failures0. Route/hash/run/sequence/one persistent socket/TCP_NODELAY/PC gates прошли. Все client/receiver/proxy/sampler exit0/unforced;3 CLI ready/graceful/post_stop=true/forced=false/error empty, receipt workers/driver stopped=true, known loaded names absent/query complete и known WFP detached after. Global/version gatesfalse. Процедура238,13с. UDP regressions не проверялись.

Медианы показателей3 прогонов OFF/PROXY: p50 0,221/0,508мс, p95 0,332/0,729мс, p99 0,460/0,874мс. Медианы парных ON−OFF разниц: p50+0,29125мс (пары+0,294/+0,291/+0,287), p95+0,4098мс, p99+0,4424мс. Медиана парных разниц не равна разности медиан режимов; не смешивать эти способы агрегации. Максимумы OFF0,844/PROXY2,208мс, >20мс0; все хвосты сохранены. В этой повторяемой низкотемповой loopback конфигурации добавка к медиане воспроизводится около0,29мс, но это полный SOCKS/helper/receiver-instrumentation путь, не отдельный driver overhead/реальный игровой ping. System CPU OFF0,64–0,82%/PROXY0,37–0,51%: фон различается, снижение не приписывать продукту. CLI sampled CPU median0,0082% whole-PC/privateRAM2,725MiB, helper отдельно0,0321%/19,606MiB; нет driver-only/watts.

Разбор — чтение сохранённых summary/manifest/comparison/run/process/cleanup evidence и обновление текущей памяти/плана; нового runtime/build/code/autotests/commit/push нет. Следующий предлагаемый срез — TCP RTT при одновременной длительной TCP-передаче и CPU/RAM: текущие transfer/RTT результаты измерены раздельно, высокий/длительный load не подтверждён. Новая команда ещё не подготовлена; использовать существующие ctsTraffic и echo harness, сохраняя direct baseline, независимые controlled receivers и route/hash assertions. Подготовка GPT-6.1 Sol/high, routine analysis medium. Полные серии запускает пользователь.

## Предыдущая точка: TCP RTT SMOKE подтверждён; следующий STANDARD (2026-10-01)

Пользовательский `tcp-rtt-smoke-20261001-155949-47368f`: COMPLETED, OFF/PROXY MEASURED/correctness PASS/errors=[], comparison LIMITED_COMPARISON/errors=[]. В каждом режиме144/144 проверенных echo,16 warmup исключены,128 измерены; всего288 valid/256 measured, failures0. Native/receiver payload/run/sequence/hash, один socket, TCP_NODELAY и owned direct/proxy/product route прошли штатный reporter. Workers client/receiver/proxy/sampler exit0/unforced, все receipt stopped=true; CLI ready/graceful/post_stop=true/forced=false/error empty; known loaded driver names absent/query complete after и wfp_detachment_observed=true. Global/version gatesfalse. Полная новая RTT связка подтверждена для этой конфигурации, UDP регрессии не проверялись.

RTT OFF/PROXY: p50 0,218/0,497мс (delta≈+0,2785мс), p95 0,345/0,753мс (+0,4080), p99 0,504/1,020мс (+0,5161), max0,666/1,023мс; >20мс0. Это один короткий paced loopback pair, полный путь с SOCKS/helper/receiver instrumentation, не отдельная стоимость драйвера/обещание реального игрового ping. PC14/15 samples, coverage3,60/3,90с; CLI sampled CPU0%, privateRAM2,738MiB, нулевые дельты не доказывают отсутствие CPU cost. Whole-system CPU OFF3,44%/PROXY0,54% показывает меняющийся фон, не снижение нагрузки от ProxyBridge. Процедура17,34с. Только чтение сохранённых evidence/обновление плана и памяти; новых runtime/build/autotests/code changes/commit/push нет.

Следующая подготовленная команда пользователя из admin PowerShell: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-LocalTcpRtt.ps1" -Profile STANDARD`. Три counterbalanced OFF/PROXY пары,1000 measured+100 excluded warmup/run,512 bytes/20ms pause;6000 measured/6600 total echoes, примерно3–6мин. Новая папка автоматически; это повторяемость RTT при низком темпе, не high-load/long-stability. GPT-6.1 Sol/medium для разбора, high при сбое.

## Предыдущая точка: подготовлен TCP request/response RTT SMOKE (2026-10-01)

Пользователь разрешил следующий срез после успешной TCP STANDARD: локальная SOCKS5 задержка относительно OFF. Переиспользуется существующий native pb_net_client.c persistent TCP stream и контролируемый pb_net_endpoint.py, существующие SOCKS library/Windows Selector wrapper/CLI lifecycle/SCM/PSAPI/psutil. Не создавался новый TCP/SOCKS протокольный движок. Рассмотрены PsPing (официальный интерфейс latency/histogram, не достаточное само по себе доказательство run/sequence/hash для нашего отчёта) и Microsoft Latte (MIT, binary releases; такой контракт не подтверждён): не скачаны/не приняты. Источники: https://learn.microsoft.com/en-us/sysinternals/downloads/psping и https://github.com/microsoft/latte. Throughput остаётся ctsTraffic; для RTT нужны существующие per-message evidence.

Native --tcp-rtt1: loopback IPv4/один TCP-сокет/один запрос в полёте; QPC непосредственно перед frame send и после полного recv, вне connect/build/hash/log/Sleep. 512-byte PB_NET identity payload с run-ID/sequence/phase/SHA, существующий 4-byte length frame, receiver echoes payload. TCP_NODELAY задаётся/читается на native сокете; receiver --tcp-nodelay задаёт и записывает actual accepted-socket setting. Receiver BUFFERED256KiB теперь не flush MESSAGE_RECEIVED/ECHOED; default FLUSH_EACH не менялся, SHA и все сообщения сохраняются. Native JSON flush между обменами сохранён, receiver обработка/проверка/буферный журнал входят в RTT; это стоимость полного инструментированного пути, не отдельного драйвера. Передача head/body двумя send_all входит в RTT; пауза20мс после ответа, не fixed offered rate. Соединение/ICMP/one-way/game capacity не измеряются.

Изолированная сборка bin/tcp-rtt/pb_tcp_rtt_client.exe из того же исходника, новый Build-Harness -OutputPath; MSVC14.51.36231 x64 /W4 /WX /O2, без warnings/errors; SHA35D31540D8F6B564839B135BF0C925A224D768519B33C0FAFA9290A3437E8D6A, source/EXE provenance receipt совпали. Стандартный bin/pb_net_client.exe (UDP) не перезаписан, SHA9501D27FE023C567044095194C680CD6C66A4F3D8941B4D25DD183BC87171857 прежний. Receiver source SHA изменён: не смешивать будущие измерения с историческими условиями. Core/driver/CLI kit неизменны.

Новый Invoke-LocalTcpRtt.ps1: SMOKE OFF→PROXY,128 measured+16 excluded warmup/run; STANDARD3 counterbalanced pairs,1000+100/run;512 bytes/20ms pause, ещё не запускались с продуктом. OFF требует service/known WFP/loaded driver absence, одинаковые idle proxy/receiver/sampler. PROXY rule только pb_tcp_rtt_client.exe→127.0.0.1:54122, target-owned receiver TCP listener/PID и active driver inventory; product TCP listener snapshot сохраняется. Reporter pb_tcp_rtt_report.py требует exact run/seq/expected payload SHA на native+receiver, один socket/receiver accept/owned proxy flow/frame byte counters, actual client/receiver TCP_NODELAY, selected proxy loop, product PID/destination/config-ID route, clean lifecycle/cleanup/inventory. Недостающая route — INCONCLUSIVE; warmup исключён из RTT/PC window, PC PID watch +3 samples/65% required. p50 median, p95/p99 nearest-rank; comparison quantiles — medians of run quantiles, paired ON−OFF deltas, max across runs/errors. No global/version pass.

Bounded non-product manual proof tcp-rtt-engine-check-20261001-155027-a72da9/manual-receipt.json: direct32 и diagnostic SOCKS5 tunnel32 запросов по512 байт, native/receiver hashes/run/seq matched, one socket, TCP_NODELAY observed, QPC positive/order validated, client/receiver/proxy exit0/no forced/no callback; proxy counters16512 up/16384 down и STDIN_STOP. Временный pproxy2.7.9 tunnel только в этом proof, не в product SMOKE. Это real-wire подготовка, не developer autotests/не ProxyBridge benchmark. Проверены MSVC build, Python py_compile/CLI --help, PS5.1/7 AST/BOM. Полный отчёт с продуктом и sampler gates ещё не подтверждён; fake driver/test fixtures не создавались. Во время одной ручной проверки import как package src.pb_tcp_rtt_report был неподходящим способом запуска; штатный script CLI --help/import dependencies подтверждены. Commit/push/subagents отсутствуют.

Следующая команда пользователя из admin PowerShell: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-LocalTcpRtt.ps1" -Profile SMOKE`. Около1–2мин, новая папка tcp-rtt-smoke-*. STANDARD не запускать до разбора этой полной связки. Следующий разбор GPT-6.1 Sol/medium, high при ошибке. Успешная transfer STANDARD остаётся предыдущей подтверждённой точкой.

## Предыдущая точка: новая TCP STANDARD-серия завершена (2026-10-01)

Пользовательский `tcp-socks5-standard-20261001-152718-4e2021`: COMPLETED,12/12 MEASURED/errors=[], comparison LIMITED_COMPARISON/errors=[].12×512MiB=6GiB проверенных данных, по3GiB OFF/PROXY;12 уникальных ConnectionId, verify:data/объёмы/маршрут/PC coverage подтверждены отчётами. Все конфигурации `_WindowsSelectorEventLoop`; proxy exit0/unforced/no callback errors во всех12 запусках. Workers/driver stopped=true во всех receipt, known loaded driver names absent/query complete after; все6 CLI ready/graceful/post_stop=true/forced=false/error empty. Финальный interception-after wfp_detachment_observed/current_driver_preparation_allowed=true. Предыдущий shutdown failure в этой серии не повторился; это не гарантия отсутствия всех будущих сбоев. Старые попытки tcp-socks5-standard-20261001-144355-8ccdb3 остаются FAILED отдельно, с новой серией не смешаны. Global/version gatesfalse.

Медианы полезной скорости OFF/PROXY: upload543,60/541,41Мбит/с; download543,39/541,61Мбит/с. Медианные парные изменения PROXY/OFF−1: upload−0,38%, download−0,34%. Download pair3 сохраняется с−3,60% (OFF542,50/PROXY522,95Мбит/с); причину по этой серии не установили, не удалять как выброс и не утверждать устойчивый overhead0,3%. RateLimit64MiB/s одинаковый, observed average может отличаться от настройки; это не строгая проверка cap. Одна передача длится7,90–8,21с, процессное окно7,98–8,29с, фактическая процедура143,30с. Coverage ролей93,5–99,6% окна. CPU CLI в процентах всегоПК: медиана upload0,067%, download2,026%; private RAM2,738/2,733MiB. SOCKS5 helper отдельно CPU2,555/2,468% и RAM19,769/20,084MiB; не приписывать его стоимость продукту. CPU драйвера отдельно/ватты не измерены.

Проверки этого разбора — только чтение фактических manifest/comparison/run receipts/process/cleanup evidence; повторных runtime, сборок, code autotests, code changes, commit/push нет. Вывод ограничен выбранным Driver kit, loopback IPv4 TCP/SOCKS5, одним соединением, контролируемым получателем и заданным темпом. Нельзя объявлять capacity/длительную стабильность/RTT/ping/4.0.0 A-B подтверждёнными. Предлагаемый следующий срез — TCP request/response RTT с прямой базой, p50/p95/p99 и ошибками; его команда ещё не подготовлена. Подготовка GPT-6.1 Sol/high; обычный разбор результатов medium. Полные серии продолжает запускать пользователь.

## Предыдущая точка: исправлен Windows TCP helper; нужна новая STANDARD-серия (2026-10-01)

Пользовательское Resume `tcp-socks5-standard-20261001-144355-8ccdb3` выполнило3 оставшихся запуска успешно (итого11 COMPLETED/MEASURED); последний `pull-pair-03-proxy` снова FAILED после проверенной передачи512MiB. Proxy forced/exit−1 после15с, две Proactor callback exceptions/WinError10054; client/receiver/sampler exit0, CLI ready/graceful/post_stop=true/forced=false, driver stopped/known loaded names after absent. Увеличение stop timeout проблему не решило; STANDARD comparison не завершён. Оба FAILED каталога и исходный manifest backup сохранены, не считать их успешными измерениями.

Локальный Python3.12.14 `Lib/asyncio/proactor_events.py`: `_call_connection_lost` вызывает socket.shutdown до socket.close/server._detach без обработки ConnectionResetError; наблюдаемый traceback прерывает освобождение transport. SOCKS library `_run` ждёт `srv.wait_closed()` ещё до своего bounded client-task shutdown. Это объясняет зависание при закрытии управляющих соединений, а не ошибку проверки данных TCP. Исправлен только Windows wrapper pb_controlled_tcp_proxy.py: стандартный SelectorEventLoop через asyncio.run(loop_factory), library1.3.3/wheel неизменны; readiness фиксирует actual event-loop class, отдельное событие SHUTDOWN_REQUESTED. Controller записывает ожидаемый `_WindowsSelectorEventLoop` в условия; reporter требует его наблюдение для новых запусков и указывает предел512 sockets. Не переносить этот helper на высокую параллельность без отдельной оценки ограничений. Официальные источники: https://docs.python.org/3.12/library/asyncio-platforms.html и https://docs.python.org/3.12/library/asyncio-runner.html.

Bounded non-product manual traffic proof `tcp-selector-close-check-20261001-152405-2b9712/manual-receipt.json`: ctsTraffic upload/download по2MiB verify:data/совпадающие GUID/оба endpoints exit0;40 SOCKS5 UDP ASSOCIATE управляющих TCP-соединений отклонены и закрыты клиентом с RST. UDP data workload не запускался. Временный pproxy2.7.9 tunnel только для этой диагностической связки; в STANDARD его нет. Actual `_WindowsSelectorEventLoop`,2 закрытых TCP flow, SHUTDOWN_REQUESTED и STOPPED/STDIN_STOP, proxy exit0, forced_processes=[], callback_error=false. Это проверка целевой библиотеки/закрытия реальных сокетов без ProxyBridge, не полный product runtime и не доказательство отсутствия всех будущих ошибок. Python syntax/PS5.1 и7 AST/UTF8 BOM проверены. Нет developer autotests, сборок, изменений native/Core/driver или commit/push.

Старые11 измерений сохраняются отдельно: сменился event loop и SHA helper, нельзя смешивать с новой серией или продолжать старый каталог. Следующая команда пользователя из admin PowerShell: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-LocalTcpBenchmark.ps1" -Profile STANDARD` (без Resume/EvidenceDirectory; новая папка автоматически).12 запусков/3 counterbalanced пары на направление/512MiB/RateLimit64MiB/s/verify:data; ориентировочно3–8мин. Полную связку после исправления ещё не проверяли. Следующий разбор GPT-6.1 Sol/medium, high при повторном сбое; global/version gates остаются false.

## Предыдущая точка: TCP STANDARD прерван; подготовлено узкое Resume (2026-10-01)

Пользовательский `tcp-socks5-standard-20261001-144355-8ccdb3`: восемь прогонов COMPLETED/MEASURED/errors=[], девятый `pull-pair-02-proxy` FAILED. Его передача 512MiB завершилась: client/receiver Succeeded/одинаковый GUID/exit0. CLI ready/graceful/post_stop=true, forced=false; receiver/sampler exit0. SOCKS5 helper не завершился за5с, был остановлен принудительно (exit−1). В stderr есть `Exception in callback _ProactorBasePipeTransport._call_connection_lost`/WinError10054; связь с зависанием предполагается, не доказана. Driver stop/known loaded absence после попытки подтверждены. Старый controller оставил error пустым; неудачная попытка не включается в сравнение.

Invoke-LocalTcpBenchmark.ps1 теперь записывает причины timeout/forced/nonzero helper exit; ожидание остановки помощников увеличено5→15с только после измерения, что не гарантирует исправления Python callback. Узкое одноразовое Resume допускает именно наблюдавшийся legacy-сбой остановки proxy после проверенной передачи на первом прогоне незавершённой пары. До записи проверяет завершённый префикс, workload/tool/Python/product hashes и inventory; на запуске требует текущий OFF gate. Сохраняет исходный manifest и каталог FAILED, удерживает8 готовых запусков, повторяет целиком оставшиеся две download-пары (4 запуска) в исходном порядке. Другие ошибки/повторные retry этим Resume не поддерживаются. Измеряемые proxy/sampler/engine bytes не менялись: совпадение текущих SHA с конфигурациями всех9 попыток вручную подтверждено. Reporter сохраняет failed_attempts/resume/deadline change и предупреждение о паузе; новая Python callback exception даёт INCONCLUSIVE даже при штатной остановке. UDP Resume не менялся.

Проверено: AST PowerShell5.1/7, UTF8 BOM, Python py_compile; повторная генерация сохранённого SMOKE comparison LIMITED_COMPARISON/errors=[]. Длинная серия/само Resume не запускались агентом, developer autotests/сборки/Core/driver/helper changes/commit/push отсутствуют. Исходный STANDARD manifest пока FAILED/9 entries/8 completed; полных STANDARD итогов нет. Следующая команда пользователя из admin PowerShell: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-LocalTcpBenchmark.ps1" -Profile STANDARD -Resume -EvidenceDirectory "C:\src\ProxyBridge-TestLab\artifacts\local-route\tcp-socks5-standard-20261001-144355-8ccdb3"`. Ориентировочно1–3мин. Если callback/stop снова сорвётся, потребуется исправить Windows helper и начать сравнение заново с одинаковыми инструментами; увеличение deadline само по себе не является исправлением первопричины. Анализ следующего результата GPT-6.1 Sol/medium, high при повторном сбое.

## Предыдущая точка: TCP SMOKE подтверждён; готов следующий STANDARD (2026-10-01)

`artifacts/local-route/tcp-socks5-smoke-20261001-142534-d3de96`: COMPLETED/LIMITED_COMPARISON/errors=[], четыре переноса по16MiB, всего64MiB (32MiB OFF/32MiB PROXY). Все client/receiver Succeeded/verify:data, объёмы и GUID совпали,4 разных GUID по прогонам. Direct socket path и PROXY owned-socket/flow + продуктовые PID/назначение/config-ID route подтверждены отчётчиком. PC actual PID/WATCHED/coverage подтверждены:6–7 выборок,1,55–1,83с coverage в1,99–2,01с процессном окне. Все процессы exit0/unforced, обе CLI ready/graceful/post_stop=true/forced=false/error empty; workers/driver stopped, known loaded names after absent/query complete. Global/version gatesfalse.

Upload OFF/PROXY70,20/70,16Мбит/с (парная delta -0,05%); download70,42/70,23Мбит/с (-0,26%). Native TimeMs1,906–1,913с, процедура25,61с. RateLimit8MiB/s — одинаковая настройка движка, короткий измеренный темп несколько выше номинала; соблюдение жёсткого rate cap не проверяется. Это проверка готовности ограниченного TCP-среза, не ceiling/устойчивый вывод об overhead/RTT/ping. CPU CLI0 в охваченных выборках, private RAM2,734MiB; нулевые краткие sample deltas не доказывают отсутствие нагрузки/стоимости драйвера. Reporter дополняет summary этой оговоркой и уточняет RateLimit; Python syntax и saved comparison regeneration LIMITED_COMPARISON/errors=[] прошли. Нового runtime/сборки/кодовых автотестов/изменений native/Core/driver/commit/push при разборе нет.

Следующая команда пользователя из admin PowerShell: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-LocalTcpBenchmark.ps1" -Profile STANDARD`. Ориентировочно3–8мин;12 прогонов,3 counterbalanced OFF/PROXY пары на upload и3 на download,512MiB/одно соединение/RateLimit64MiB/s, всего6GiB проверяемых данных (не файлы такого размера на диске). Эта реализация уже подготовлена; впервые полный STANDARD ещё не выполнялся. Это более длинный rate-limited перенос, не предел скорости/длительная стабильность; warmup не исключён. RTT-срез остаётся отдельной подготовкой. Анализ следующего результата GPT-6.1 Sol/medium, high при ошибке; полноценные серии по-прежнему запускает пользователь.

## Предыдущая точка: TCP SOCKS5 передача подготовлена; первый запуск SMOKE (2026-10-01)

Команда из административного PowerShell: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-LocalTcpBenchmark.ps1" -Profile SMOKE`. Ориентировочно2–5мин, новая папка tcp-socks5-smoke-*. Четыре прогона: upload OFF→PROXY, затем download OFF→PROXY;16MiB/одно TCP-соединение, sender cap8MiB/s, verify:data, оба endpoints завершаются сами. Это первый integration probe, не достаточное сравнение производительности/стабильности; RTT/ping не измеряется. STANDARD предусмотрен как3 чередующиеся пары в каждом направлении,512MiB/64MiB/s, но не запускать до разбора SMOKE.

Готовый Microsoft ctsTraffic2.0.3.9 x64/Apache-2.0 из официального репозитория, pinned binary commit b0e2a48f30fb7caaaa9994ee2dea2a177a4639e2, Git blob e3a140e8f250061df3c590e78554c5e19d860058 совпал, SHA256 0548089E59C872306CE2C98E7163E2A717119756010CF64D3CB3DA2854F632CF. Изолирован в bin/tools/ctstraffic-2.0.3.9; receiver переименован ctsTrafficReceiver.exe с теми же байтами, правило продукта только для ctsTraffic.exe. Windows native binary/help проверены; help штатно exit13 (справка, не сетевой запуск). Receiver/client CSV иногда UTF16 BOM, parser учитывает это. ConnectionId GUID должен совпасть на обоих endpoints, результаты Succeeded/volumes/data-verification banners подтверждаются; GUID уникальны между прогонами. Нет нового TCP/SOCKS-протокольного движка.

Новый TCP SOCKS5 host pb_controlled_tcp_proxy.py делегирует неизменённому asyncio-socks-server1.3.3 relay/handshake, hooks ограничивают loopback54122 и фиксируют исходящий сокет/flow counters. UDP запрещён, stdin STOP/watchdog, только lifecycle/flow записи (не per-buffer hashes); целостность проверяет ctsTraffic verify:data. Reporter сопоставляет receiver socket с owned proxy, требует продуктовый RELAY_ACCEPTED_REDIRECT с PID/назначением/config-ID; missing route остаётся INCONCLUSIVE. OFF не запускает продукт, требует stopped service/known WFP/loaded-driver absence до/после и прямой socket path; idle receiver/proxy/sampler одинаковы. Использует существующие CLI lifecycle/SCM/PSAPI и psutil7.2.2; actual process WATCHED/PID и минимум3 samples/65% coverage required. CPU относится к ограниченному окну процесса, не driver-only/watts. Rate cap обоих endpoints одинаков, warmup не исключён, capacity/RTT/stability не заявлять. Global/version gatesfalse.

Проверки подготовки: direct1MiB native proof client/receiver exit0/ConnectionId/volume match (`tcp-engine-check-20261001-140120`). Non-product bounded SOCKS5 proof `tcp-socks5-engine-check-20261001-141516/manual-receipt.json`: push/pull по2MiB, обе стороны verify:data/Succeeded/одинаковые GUID/exit0; SOCKS host два закрытых flow/STDIN_STOP/exit0. Для соединения native клиента с SOCKS в этом proof был временный pproxy2.7.9 tunnel; это дополнительная диагностическая прослойка, не измерение ProxyBridge и не движок полноценной серии. Предыдущая попытка tcp-socks5-engine-check-20261001-141340 не завершила harness receipt из-за чтения UTF16 CSV как locale encoding, proxy был остановлен принудительно; её native push CSV Succeeded, это ошибка подготовительного разбора, не дефект продукта. PS5.1/7 AST/BOM и Python py_compile обоих новых файлов прошли. Core/driver/native TestLab клиент не менялись, сборок/кодовых автотестов/commit/push нет. Полная связка ProxyBridge/route/PC/report пока не проверена; её запускает пользователь. Следующий шаг — разбор SMOKE, GPT-6.1 Sol/medium, high при ошибке; отдельный TCP RTT-срез ещё требует подготовки.

## Предыдущая точка: прямой ↔ SOCKS5 с BUFFERED завершён (2026-10-01)

Последнее уточнение пользователя: дальнейшие проверки/бенчмарки только SOCKS5 TCP/UDP. HTTP CONNECT отложен до практической необходимости или запросов пользователей; сейчас его не реализовывать и не расширять тестирование. Следующий согласованный срез — подготовка локального TCP SOCKS5 ↔ прямой трафик с контролируемым получателем и CPU/RAM; ещё не реализован. Сохранённые HTTP-свидетельства исторические. Изменены только план/память; код/окружение/runtime не менялись. Рекомендация для подготовки GPT-6.1 Sol/high.

`artifacts/local-route/udp-soak-multi-target-buffered-20261001-134200-0884d8`: COMPLETED/LIMITED_COMPARISON/errors=[], manifest BUFFERED. Все120000 echo подтверждены, по60000 OFF/PROXY;0missing/duplicate/unexpected/повреждённых данных. Политика журналов, receiver identity/PC OBSERVED, два потока/peak2/warmup barrier подтверждены во всех6. OFF PASS/MEASURED, все60000 PROXY-ответов от owned relay, строгий SOURCE_ENDPOINT_MISMATCH/MEASURED_WITH_SOURCE_DEFECT. Shared-target mixing NOT_EXERCISED; ни один известный дефект не объявлять исправленным.

Медианы по повторам OFF/PROXY: RTT0,111/0,399мс, p950,215/0,597мс, p990,296/0,724мс; достигнутый темп8243/3809echo/с. Парная медиана RTT delta+0,288мс (диапазон+0,271…+0,292), темпа -4386echo/с/-53,20% (пары -48,83/-53,20/-55,41%). Это весь инструментированный ProxyBridge/SOCKS5-путь, не выделенная цена только драйвера и не максимальная пропускная способность. Maximum RTT2,55/3,60мс,0ответов>20мс среди59400 измеренных на режим. Измерения OFF2,35–2,66с/PROXY5,13–5,28с; вся процедура3мин59,5с, не длительная стабильность. Не сравнивать эту серию напрямую с прежней FLUSH_EACH как доказательство ускорения/замедления: режим журналов и время запуска различаются.

CLI CPU median6,066% всего ПК (5,345–6,096%), private RAM median2,664МиБ (2,648–2,691). Общий CPU OFF46,13%/PROXY37,99% при разном достигнутом темпе; меньший общий CPU не доказывает эффективность продукта или стоимость драйвера. Driver-only/watts не измерены. Все native/helpers/sampler exit0, helpers forced=false; CLI graceful=true/forced=false/error empty, workers_stopped/driver_stop_observed true, loaded after inventories complete/known absent во всех6. Global cleanup/version switching остаются false.

Разобраны сохранённые reports/receipts/process/lifecycle/driver inventories, нового runtime/сборки/изменений кода/кодовых автотестов/commit/push нет. План/память обновлены. Для текущего UDP-среза достаточно; следующий согласованный шаг — подготовить локальное прямое↔TCP SOCKS5 сравнение с контролируемым получателем и CPU/RAM, используя существующие реализации. HTTP CONNECT исключён пользователем из текущего объёма. TCP-бенчмарк пока не реализован/не запускался; GPT-6.1 Sol/high. Полные серии запускает пользователь.

## Предыдущая точка: прямой ↔ SOCKS5 с BUFFERED подготовлен (2026-10-01)

Команда из административного PowerShell: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-LocalUdpSoak.ps1" -Profile MULTI_TARGET -EvidenceLogMode BUFFERED`. Ориентировочно 5–20 минут; новая папка `udp-soak-multi-target-buffered-*`. Три чередующиеся OFF/PROXY пары, два контролируемых UDP-порта, по10000 echo×1200 байт/warmup100 на сокет/pause0, всего20000/run120000/series. Параметры трафика прежнего MULTI_TARGET сохранены; LOG_FLUSH имел40000/run, поэтому не смешивать результаты как одинаковую нагрузку.

Новый EvidenceLogMode параметр wrapper/comparison передаёт BUFFERED обеим сторонам. FLUSH_EACH остаётся default. Manifest хранит helper_log_flush_mode; Resume требует ту же политику manifest/config, а для BUFFERED также подтверждённые helper-маркеры отчётчика. LOG_FLUSH/LOGGING продолжает сам выбирать flush режимы по варианту, внешнее BUFFERED для этого эксперимента отклоняется. Подтверждение текущей политики обязательно до COMPLETED. У обоих helpers буфер256KiB; общий существующий STOP/exit0 до чтения evidence действует и для OFF. Все записи/хеши/проверки данных, маршрута, источника и PC identity остаются; generator/product/native/Core/driver не менялись. Source-port дефект продолжает строгую проверку с узким допуском только для transport-performance; shared-target mixing NOT_EXERCISED.

Comparison report явно маркирует политику и показывает echo/s, парные delta темпа/проценты вместе с RTT; историческое отсутствие поля означает FLUSH_EACH, не BUFFERED. Проверены PS5.1/7 AST и BOM двух скриптов, Python py_compile отчётчика, вручную передача режима и одинаковый flush/STOP путь для OFF/RULES. Пересоздан comparison на реальном сохранённом MULTI_TARGET: LIMITED_COMPARISON/errors=[], исходные RTT delta/source counts неизменны, новый отчёт явно FLUSH_EACH. BUFFERED OFF/PROXY integration ещё не проверена; её запускает пользователь. Нового runtime/сборки/кодовых автотестов/commit/push нет, global/version gatesfalse. Следующий шаг — разбор результатов, GPT-6.1 Sol/medium; high при ошибке.

## Предыдущая точка: LOG_FLUSH завершён, влияние сброса журналов измерено (2026-10-01)

`artifacts/local-route/udp-log-flush-20261001-130033-365737`: COMPLETED/LIMITED_COMPARISON/errors=[], три чередующиеся пары FLUSH_EACH/BUFFERED, обе через ProxyBridge/SOCKS5 к двум разным портам. Все240000 echo подтверждены, по120000 на режим;0 потерь/дубликатов/неожиданных источников. Полнота packet/hash/route свидетельств, logging_policy_verified и PC OBSERVED/receiver identity подтверждены во всех6. Все ответы от owned relay, строгий SOURCE_ENDPOINT_MISMATCH остаётся; shared-target mixing NOT_EXERCISED.

Парные BUFFERED−FLUSH_EACH RTT delta: -0,0195/-0,12135/-0,0218мс; медиана -0,0218мс. Темп +161,7/+1071,1/+154,4echo/с, относительное изменение +3,47/+28,30/+4,07%; парная медиана +4,07%. Между прогонами есть существенная вариация: медианы режимов3792/4825echo/с нельзя трактовать как устойчивый прирост27%. Отчёт дополнен таблицей пар и пояснением различия агрегатов. Причина вариации не установлена. Измерения8,20–10,52с, вся процедура11мин57с, не длительная непрерывная нагрузка/предельная ёмкость.

Медианы CPU receiver6,71→5,62%, proxy12,66→11,99%, CLI6,05→6,14% всего ПК. Private RAM receiver+proxy32,51→33,09МиБ. CPU не нормирован на одинаковый темп, driver-only/watts не измерены; это лишь стоимость flush двух helper-файлов, генератор/продукт/hash/sampler неизменны. Maximum RTT3,02/2,44мс,0ответов>20мс. Helpers/sampler exit0/forced=false во всех6; CLI graceful=true/forced=false/error empty, workers_stopped/driver_stop_observed true, известные loaded driver names после отсутствуют. Global cleanup/version switching остаются false.

Разобраны сохранённые reports/receipts/lifecycle/process результаты, нового runtime/сборки нет. Python py_compile изменённого logging reporter и пересоздание текущего comparison report прошли, LIMITED_COMPARISON/errors=[]; кодовые автотесты/commit/push не выполнялись. FLUSH_EACH остаётся default, прежние серии не смешивать с BUFFERED. Предложение следующего шага: подготовить одинаковый BUFFERED режим для обеих сторон прямого↔SOCKS5 сравнения, сохранив все проверки и явную маркировку политики; сначала согласовать этот срез. GPT-6.1 Sol/high для подготовки, medium для разбора. Полные серии запускает пользователь.

## Предыдущая точка: LOG_FLUSH подготовлен для оценки сброса helper-журналов (2026-10-01)

Команда из admin PowerShell: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-LocalUdpSoak.ps1" -Profile LOG_FLUSH`. Ориентировочно5–20мин, новая папка udp-log-flush-*. Три counterbalanced пары FLUSH_EACH→BUFFERED, BUFFERED→FLUSH_EACH, FLUSH_EACH→BUFFERED, обе стороны — ProxyBridge/SOCKS5/RULES к двум контролируемым портам, два sockets по20000×1200bytes/warmup100, pause0 (40000/run240000/series). Меняется только flush файлов receiver/proxy: FLUSH_EACH после события против BUFFERED256KiB, все packet/hash записи сохранены, готовность/ошибки/остановка сбрасываются сразу. Это пользовательская буферизация/передача в ОС, не физическая fsync-долговечность. Native generator, продукт, CPU sampler и hash-вычисления неизменны; это часть расходов инструментирования, не полная цена логов/драйвера.

В UDP controller receiver/proxy штатно STOP после завершения workload/CLI, до чтения свидетельств: закрытие дописывает buffered tail, exit0 обязателен, затем обычный finally подтверждает capture/shutdown/драйвер. Самопровозглашённый log_flush_mode всех helper-событий проверяется per-run report; отсутствие/неполнота данных не PASS. ComparisonMode LOGGING имеет отдельный pb_udp_logging_report.py, проверяющий одинаковые config/dependencies/receiver helper/native traffic/bundle/sampler/other-driver условия кроме log mode и точный порядок пар. Вывод RTT/p99/max/>20ms, echo/s, CPU и helper RAM; режимы не маркируются как OFF. Source-port strict result сохранён, shared-target mixing NOT_EXERCISED. Resume этой новой серии пока не поддерживается; прежний узкий Resume других режимов сохранён.

PS5.1/7 AST/BOM и Python py_compile5 файлов прошли. NativeSHA9501D27FE023C567044095194C680CD6C66A4F3D8941B4D25DD183BC87171857 не изменён, сборки не было. Ручной bounded non-product proof `artifacts/local-route/helper-log-check-20261001-124940/manual-receipt.json`: в каждом режиме128 direct native echo +8 SOCKS5 echo (pproxy2.7.9 как временный диагностический UDP codec; engine прежний asyncio-socks-server1.3.3), receiver136/136, proxy8/8 outbound/return hashes, helpers exit0. BUFFERED доSTOP0 received records на диске, послеSTOP все136 сохранены; это подтверждает tail, не performance. ProxyBridge не запускался, SCM Stopped. Обратная совместимость per-run reporter проверена на сохранённом pair01-proxy MULTI_TARGET_LONG: MEASURED_WITH_SOURCE_DEFECT/40000 как прежде. Новая полноценная LOGGING/PC comparison integration пока не проверена, её запускает пользователь. Core/driver/установки неизменны; no code autotests/commit/push, global/version gatesfalse. Следующий шаг — результат LOG_FLUSH, GPT-6.1 Sol/medium, high при ошибке.

## Предыдущая точка: MULTI_TARGET_LONG завершён,240000 echo подтверждены (2026-10-01)

`artifacts/local-route/udp-soak-multi-target-long-20261001-111249-28f125`: COMPLETED/LIMITED_COMPARISON/errors=[], три чередующиеся пары, по120000 валидных echo на режим,0missing/duplicate/unexpected/payload errors. Два контролируемых порта, peak2/общий warmup barrier/receiver identity/PC OBSERVED подтверждены во всех6. OFF PASS/MEASURED; все120000 PROXY-ответов от текущего owned relay, строгий SOURCE_ENDPOINT_MISMATCH/MEASURED_WITH_SOURCE_DEFECT. Shared-destination mixing NOT_EXERCISED, не объявлять известный дефект исправленным.

Процедура72мин21с (11:12:49–12:25:10UTC), отдельные workloads OFF642,5–643,3с/PROXY645,5–646,7с, не одно72-минутное соединение. Темп суммарно~61,5–61,9echo/с на два потока, умеренная нагрузка1200bytes/пауза20мс после ответа, не capacity/high-load proof. Медианы по повторам RTT0,3334/0,6768мс, p95 0,4591/0,9438, p99 0,7509/1,1547. Парная медианная delta+0,3434мс (+0,3183…+0,4315), весь инструментированный путь. MaxRTT OFF7,7714/PROXY6,9266мс,0 ответов>20мс на119400 измеренных в каждом режиме; предыдущий52,3мс burst-outlier здесь не повторился, причина/порог при высокой нагрузке не установлены. На каждом прогоне22 окна RTT30с; PROXY оконные медианы0,626–0,789мс в общей наблюдавшейся серии, без утверждения отсутствия всех видов деградации.

CLI CPU0,02096–0,02296% всего ПК, private RAM mean~2,565–2,592МиБ, sample peak~2,644–2,672МиБ. Delta private RAM последних/первых10с -88/-92/-92KiB, роста по этим endpoints нет; это не доказательство отсутствия утечек. Driver-only/watts не измерены. Все native exit0/not timedout, workers_stopped/driver_stop_observedtrue, loaded after inventories complete/known namesabsent; global/version gatesfalse.

Разбор использовал сохранённые отчёты/receipts и30с окна, нового runtime/сборки/кодовых автотестов/native/Core/driver/reporters изменений/commit/push нет. Следующее предложение: оценить цену журналирования/генератора/получателя перед повышением нагрузки; не смешивать short/no-pause иlong/paced как одно A/B и не выводить цену драйвера из системной CPU delta. GPT-6.1 Sol/high для следующей подготовки; полноценные серии запускает пользователь.

## Предыдущая точка: MULTI_TARGET_LONG подготовлен для ручного запуска (2026-10-01)

Команда из административного PowerShell: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-LocalUdpSoak.ps1" -Profile MULTI_TARGET_LONG`. Три чередующиеся OFF/PROXY пары; два connected IPv4 sockets к контролируемым loopback-портам53122/53121, по20000×1200bytes/warmup100, пауза20мс после каждого echo. Всего40000 обменов на прогон/240000 на серию, после прогрева39800 на прогон. Ориентировочно65–80мин для процедуры, около10мин на каждом соединении; это шесть отдельных параллельных workloads, не единое часовое соединение. Это умеренная нагрузка с темпом, зависящим от Windows scheduling/RTT/журналирования, не максимум ёмкости.

Контроллеры допускают40000 всего, сохраняя максимум20000 на поток. Для новых больших parallel series deadline рассчитан по длине потока: native830с/helper860с; резервы существующих профилей не изменены. Новый prefix udp-soak-multi-target-long-; параметры40k/interval20/DISTINCT/streams2 сохраняются в manifest/Resume/signature. Resume остаётся узким: только последний no-workload failure, оценка длинного retry10–20мин. Существующие rtt_windows30с/maxRTT/>20ms/privateRAMfirst-last10s и source/payload/route/receiver identity gates переиспользованы; known source-port defect допустим только при проверенных payload/current owned relay. Общий-получатель cross-stream regression NOT_EXERCISED в этом профиле, её исправление нельзя выводить из успеха.

Проверены PS5.1/7 AST/UTF8 BOM всех3 изменённых скриптов, вручную сверены передача40k/2/20/1200/100 и бюджеты. Native/receiver/proxy/sampler/reporters не менялись; сборка/новый runtime/кодовые автотесты не выполнялись. Полная долговременная интеграция ожидает пользователя; предыдущий короткий MULTI_TARGET остаётся подтверждённым результатом ниже. Core/driver неизменны, global/version gatesfalse, commits/pushнет. Следующий шаг — разобрать ручной результат, GPT-6.1 Sol/medium, high если возникнет ошибка.

## Предыдущая точка: MULTI_TARGET завершён; отмечен единичный RTT52,3мс (2026-10-01)

`artifacts/local-route/udp-soak-multi-target-20261001-101619-26b1f7`: COMPLETED/LIMITED_COMPARISON/errors=[], три OFF/PROXY пары,120000/120000 подтверждённых echo, по60000 на режим; два sockets/порта53122/53121, peak2/общий warmup barrier/правильные цели подтверждены во всех6. OFF PASS/MEASURED; PROXY SOURCE_ENDPOINT_MISMATCH/MEASURED_WITH_SOURCE_DEFECT, все60000 от текущего owned relay,0missing/duplicates/unexpected/payload failures. Cross-stream regression к общему получателю NOT_EXERCISED/coveredfalse; НЕ делать вывод об исправлении известного смешивания. Подмена порта остаётся наблюдаемым дефектом.

Медианы по повторам RTT OFF0,0927 / PROXY0,34975мс, p95 0,1727/0,4551, p99 0,2455/0,5638. Парная медианная добавка+0,23295мс (диапазон+0,1836…+0,2708), весь инструментированный ProxyBridge/SOCKS5-путь, не выделенная стоимость продукта. Медиана темпа10282/4458echo/с (~98,70/42,80Мбит/с полезных данных в каждом направлении); диагностический burst, не предельная скорость. Измерения OFF1,91–2,53с, PROXY3,60–4,49с, процедура10:16:19–10:19:38UTC не непрерывный3-минутный workload. На59400 измеренных ответах PROXY один RTT52,3255мс (pair01-proxy/stream1/seq9664), OFF0 ответов>20мс и max1,6297мс. Причина выброса не установлена, не приписывать только ProxyBridge; низкий p99 не скрывает его.

CPU/RAM OBSERVED/receiver identitytrue во всех6. CLI CPU5,319–5,452% всего ПК (медиана5,448), private RAM2,707–3,195МиБ; receiver OFF11,31–15,33% / PROXY6,80–7,16%, generator OFF27,17–31,70% / PROXY9,22–13,01%, controlled proxy12,48–13,63%. Эти режимы имеют разный достигнутый темп; системная CPU delta не стоимость драйвера. Driver-only/watts/RAM trend/длительная стабильность не измерены.

Каждый native exit0/not timedout, workers_stopped/driver_stop_observedtrue, after inventories complete/known driver namesabsent; global/version gatesfalse. Reporter дополнен rtt_max_ms и суммарным числом ответов>20мс в JSON/RU-EN summary. Python syntax и пересоздание всех6 отчётов/сравнения по исходным сохранённым данным прошли; LIMITED_COMPARISON/errors[]/прежние квантильные результаты сохранены. Нового runtime/автотестов/native/Core/driver изменений/commit/push нет. Следующее предложение: подготовить длительный профиль двух разных портов для повторяемости выбросов/ресурсов, сохраняя shared-destination regression отдельной; оценка цены полного журналирования также остаётся открытой. GPT-6.1 Sol/high для подготовки; пользователь запускает серию.

## Предыдущая точка: MULTI_TARGET подготовлен; известные UDP-дефекты оцениваются отдельно (2026-10-01)

Пользователь подтвердил продолжение с двумя контролируемыми получателями/портами и уточнил: смешивание ответов уже известно, тестер должен заметить будущее исправление. Это не новая для автора проблема и не задача на изменение ProxyBridge. Сохранён PARALLEL с двумя сокетами к одному порту: его результат не привязан к версии. Reporter разделяет cross_stream_regression_covered/cross_stream_status и подмену источника: OBSERVED при доказанном ответе другого потока, NOT_OBSERVED только после полной проверенной серии с двумя реально перекрывающимися сокетами/общим прогревом, INCONCLUSIVE при неполноте; в OFF/UNRULED/двух разных портах NOT_EXERCISED. Если смешивание исчезнет, но подмена порта останется, первое будет NOT_OBSERVED, второе сохранит SOURCE_ENDPOINT_MISMATCH. Не обещать глобальное исправление по одному прогону; исправленная сборка пока не проверялась.

Команда пользователю из административного PowerShell: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-LocalUdpSoak.ps1" -Profile MULTI_TARGET`. Новый независимый результат udp-soak-multi-target-*: три пары OFF/PROXY, по10000×1200bytes/warmup100 на поток, пауза0, два connected IPv4 сокета одного процесса к127.0.0.1:53122 и:53121 одного контролируемого receiver-процесса. CPU/RAM generator/receiver суммарные. Профиль продукта включает оба отдельных порта; receipt проверяет ожидаемый порт каждого потока, proxy/receiver/hash/route/current-owned-relay assertions сохранены. Signature/manifest/Resume различают SHARED/DISTINCT, предыдущие manifests без destination_mode считаются SHARED. Успех MULTI_TARGET не устанавливает исправление смешивания при одном получателе; RU/EN отчёты/баннер явно сообщают ограничение. Shared-regression остаётся доступной через PARALLEL для выбранной новой сборки после подготовки проверенного комплекта.

MSVC x64 `/W4 /WX` собран, binarySHA256 `9501D27FE023C567044095194C680CD6C66A4F3D8941B4D25DD183BC87171857`; PS5.1/7 AST/BOM и Python syntax проверены. Короткий direct-only manual proof `artifacts/local-route/multi-target-generator-check-20261001-101128/manual-receipt.json`:512/512 native/receiver echo, два distinct source sockets и два правильных destination ports, peak_in_flight2, warmup barrier, all payload/source match, generator/receiver exit0. ProxyBridge не запускался; полная интеграция нового профиля с продуктом и PC report ещё ожидает пользовательского прогона. Saved failed PARALLEL report пересоздан: PAYLOAD_MISMATCH/INCONCLUSIVE, cross_stream OBSERVED/coveredtrue, без нового трафика. SCM Stopped, global/version gatesfalse. Core/driver/установки не менялись; native generator и текущие контроллеры/репортёры изменены; кодовых автотестов/commit/push нет. Следующий шаг — пользовательский MULTI_TARGET, разбор GPT-6.1 Sol/medium, high при проблеме.

## Предыдущая точка: PARALLEL выявил смешивание UDP-ответов между сокетами (2026-10-01)

Пользователь запустил `artifacts/local-route/udp-soak-parallel-20261001-095657-37cf88`: первый OFF завершён PASS/MEASURED,20000/20000 echo, два сокета и peak_in_flight2, warmup barrier подтверждены, PC OBSERVED/receiver identity true. Измерение1,737с, RTT median0,0728мс, p95 0,1510, p99 0,2014; достигнутый темп11397echo/с (~109,41Мбит/с в каждом направлении), короткий инструментированный burst — не максимум и не сравнение с PROXY.

Первый PROXY остановился на двух первых пакетах прогрева: stream1 seq1 получил SHA/данные stream2 seq10001; stream2 recvfrom10060 timeout, native exit10, accepted0,19998 обменов не предприняты. Получатель подтвердил оба идентифицированных пакета и оба echo; контролируемый proxy подтвердил outbound/return обоих SHA в одной association. Payload mismatch не разрешён политикой продолжения для известной подмены порта. Это наблюдаемая ошибка разделения потоков к одному получателю; не приписывать её только смене порта и не обходить проверку данных. В архивированных исходниках63be0eb `Windows/src/relay/pb_relay_udp.c:314` ответ сопоставляется по адресу/порту получателя с наиболее активным клиентом; это согласуется с наблюдением, но отдельный исправленный build не проверялся. Core/driver не менялись.

Reporter исправлен: PAYLOAD_MISMATCH имеет приоритет над SOURCE_ENDPOINT_MISMATCH; JSON/RU-EN summary содержат native_failure_counts, cross_stream_responses, response_timeouts. Исходные summary/report сохранены как before-payload-diagnosis-*; manifest/error остаются историческим выводом первоначального запуска. Python syntax и пересоздание отчёта на этих реальных сохранённых данных прошли; no runtime/no code autotests. PC sampler содержит36 SAMPLE; pc_metrics отсутствует из-за незавершённого workload, не из-за отсутствия семплирования. CLI graceful/output complete, forcedfalse/errorsempty; workers остановлены, driver Stopped, after loaded inventory complete/known names absent, global/version gates false.

Не повторять полный PARALLEL ради скорости и не Resume: провалившийся второй запуск содержит трафик, существующий Resume допускает только последний no-workload failure. Следующее предложение для обсуждения: сохранить PARALLEL с одним получателем как регрессионный сценарий и отдельно подготовить сравнение двух потоков к двум контролируемым портам/получателям, явно показывая другую топологию. Это не подтверждение корректности одного получателя и не исправление ProxyBridge. Такой профиль пока не реализован; после согласования GPT-6.1 Sol/high. Текущие изменения — только диагностика отчёта/память, без native/Core/driver изменений, commit/push.

## Предыдущая точка: PARALLEL подготовлен, полную серию запускает пользователь (2026-10-01)

Команда из административного PowerShell: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-LocalUdpSoak.ps1" -Profile PARALLEL`. Три чередующиеся пары OFF/PROXY, два connected IPv4 UDP-сокета внутри одного Winsock-процесса, по10000 обменов×1200байт, пауза0, прогрев100 на поток (200 всего). Получатель/прокси/самплер прежние, CPU/RAM генератора суммарные. Начало измерения — после общего барьера прогрева; глобальные sequence уникальны, отчёт проверяет оба сокета и фактическое перекрытие запросов. RTT variation вычисляется между соседними ответами внутри каждого потока. Сравнение сортирует записи по sequence и проверяет одинаковые параметры потоков/прогрева; Resume сверяет их и сохраняет старые одно-поточные manifests (отсутствие stream_count означает1).

MSVC x64 `/W4 /WX` собран; binary SHA256 `45FCDBBE6A12D65A387EBE65750F043C0E12FC15FF1A6DABDA8F16EF91DF7A8A`. PS5.1/7 AST/BOM, Python py_compile пройдены. Короткий ручной прямой loopback-прогон: `artifacts/local-route/parallel-generator-check-20261001-094940/manual-receipt.json`:512/512 native/receiver echoes, все payload/source совпали, два порта/socket IDs, peak_in_flight2, warmup barrier verified; generator/receiver exit0. Продукт не запускался, SCM до прогона Stopped. Полная интеграция двух потоков с ProxyBridge и CPU/RAM отчётом ещё не проверена — это следующий пользовательский запуск. Оценка5–20мин ориентировочная; это диагностический burst, темп включает RTT/полное журналирование, не предельная ёмкость и не длительная стабильность. SOURCE_ENDPOINT_MISMATCH остаётся строгой проверкой, continuation только для подтверждённого текущего relay. Core/driver неизменны, global/version gates false; автотестов/commit/push нет. GPT-6.1 Sol/medium для разбора результата; high при выявлении проблемы.

## Предыдущая точка: исправленный FAST завершён после Resume (2026-10-01)

`artifacts/local-route/udp-soak-fast-20261001-091125-9fc8d5`: COMPLETED/LIMITED_COMPARISON/errors=[], все6 прогона и120000 обменов подтверждены. Исходные5 сохранены, только последний PROXY выполнен в `pair-03-proxy-retry-20261001-092624-b6b985`. Manifest backup/failed_attempts исходного pair-03-proxy (без трафика) сохранены; resumed_from_error=CLI_PATH_VERIFICATION_FAILED, resumed_at09:26:24 UTC. Серия начата09:11:25, завершена09:27:16 с разрывом; это не непрерывная15-минутная нагрузка. Отдельные измерения OFF2,90–3,19с, PROXY7,88–8,52с, последовательные1200-byte/20000/warmup100/pause0 bursts.

По60000 валидных echo на режим, 0пропусков/дубликатов/неожиданных источников; каждый payload/socket/mode и каждый PROXY route подтверждён, после warmup RTT>20мс нет. OFF PASS/MEASURED; PROXY SOURCE_ENDPOINT_MISMATCH/MEASURED_WITH_SOURCE_DEFECT, все60000 ответов от текущего owned relay. Медианы по повторам RTT0,072/0,292мс, p95 0,133/0,456, p99 0,200/0,616. Парная медианная добавка+0,221мс (+0,220…+0,235); весь инструментированный SOCKS5-путь. Медиана достигнутого темпа OFF~6752echo/с (64,82Мбит/с в каждом направлении), PROXY~2518 (24,17). Это не максимальная скорость продукта, offered rate зависит от echo/журналирования.

Исправленный receiver CPU/RAM подтверждён во всех6: pc_metrics OBSERVED/receiver_identity_verified=true, helper/interpreter hashes сопоставимы. Receiver CPU OFF5,99–7,26%/PROXY3,25–3,45% всего ПК, private RAM11,55–11,68МиБ. CLI CPU3,29–3,63% (медиана3,37), privateRAM2,71–3,18МиБ (медиана2,71). Контролируемый proxy CPU7,64–7,88%, generator OFF15,71–16,46%/PROXY6,29–7,48%; driver-only/watts не измерены. Это разные достигнутые темпы, CPU delta не изолированная стоимость ProxyBridge. RAM trend на этих коротких сессиях не измерен, отсутствие утечек не заявлять.

Retry CLI actual_path правильный EXE/PATH_OBTAINED, ready/graceful_stop/output_capture_complete=true, forced=false/primary_error/cleanup_error пусты. Собственные процессы и выбранный драйвер остановлены во всех6, known loaded-name inventories complete/absent; global/version gates false. История неудачной no-workload попытки сохранена, не включена в120000 traffic count. Resume/path query подтверждены текущим реальным пользовательским запуском в этой конфигурации; это не гарантия отсутствия всех startup races.

В comparison reporter добавлены resumption metadata и RU/EN оговорка о разрыве/5сохранённых прогонах. Python syntax/пересоздание сравнения по сохранённым данным прошли, числовые результаты не изменились. Нового трафика/автотестов/Core/driver/native изменений/commit/push нет. Следующее предложение — оценить цену генератора/получателя/журналирования и подготовить многопоточную нагрузку с проверяемым маршрутом/источником; длинные серии запускает пользователь. GPT-6.1 Sol/high для подготовки, medium для разбора.

## Предыдущая точка: исправлен CLI path query; FAST готов к продолжению последнего прогона (2026-10-01)

`artifacts/local-route/udp-soak-fast-20261001-091125-9fc8d5`: первые5 прогонов COMPLETED, по20000 валидных обменов, pc_metrics OBSERVED/receiver_identity_verified=true. Реальный receiver CPU около6–7% всего ПК напрямую и3,3–3,5% через proxy, privateRAM11,55–11,62МиБ; исправленная идентификация подтверждена под трафиком. Всего100000 подтверждённых обменов (OFF60000,PROXY40000), полного3-pair сравнения ещё нет.

Последний pair-03-proxy остановился до генератора: CLI lifecycle actual_path=`C:\WINDOWS\SYSTEM32\ntdll.dll`, PATH_OBTAINED/attempt1, CLI_PATH_VERIFICATION_FAILED. stdout показывает настоящий CLI; ошибка чтения MainModule при раннем запуске, вероятная loader race. Receipt traffic_generated=false/cases0/workers_stopped=true/driver_stop_observed=true, loaded-driver inventory complete/known absent, CLI stop без forced stop/cleanup_error. Не признавать такую попытку измерением и не обходить проверку пути.

ProcessAdapter QueryActualPath теперь использует QueryFullProcessImageNameW с удерживаемым handle того же target, Win32 path flags0; MainModule fallback удалён, blank/query-timeout/expected-path mismatch остаются отказом. Проверены PS5.1/7 AST и компиляция C# внутри модуля; одна ручная проверка через реальный console host с коротким PowerShell process (без продукта/трафика) вернула ожидаемый powershell.exe, exit0. Это проверка нового path lookup, не доказательство отсутствия всех startup races ProxyBridge.

Добавлен узкий Resume в существующий launcher/controller: только FAILED manifest с полным подтверждённым prefix и единственной последней незавершённой попыткой без трафика и с подтверждённой остановкой. Параметры/порядок/receiver identity/ресурсные результаты prefix проверяются; backup исходного manifest, failed_attempts/resumed_from_error сохраняются, failed folder остаётся, новый last mode — в уникальном retry-folder. Пять COMPLETE не выполняются снова. Обычный запуск по-прежнему требует новую папку. При завершении полный comparison проверяет hashes/traffic/driver inventories всех6 как прежде; временной разрыв resumption сохраняется, не заявлять непрерывное выполнение. Resume runtime ещё не выполнен; его запускает пользователь.

Команда из PowerShell администратора: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-LocalUdpSoak.ps1" -Profile FAST -Resume -EvidenceDirectory "C:\src\ProxyBridge-TestLab\artifacts\local-route\udp-soak-fast-20261001-091125-9fc8d5"`. Ориентир1–5мин, только недостающий PROXY и итоговый анализ. Core/driver/native/receiver не менялись, новых продуктовых runtime/автотестов/commit/push нет. Global/version gates false. После результата проверить last receiver identity, весь comparison/cleanup/CPU-RAM/source defect; GPT-6.1 Sol/medium для разбора, high для расхождений.

## Предыдущая точка: исправленный receiver/sampler готов к ручному FAST (2026-10-01)

По продолжению пользователя выполнена ограниченная проверка связки receiver+sampler без ProxyBridge и трафика: `artifacts/local-route/receiver-sampler-check-20261001-090721`. Python3.11 receiver PID6048 совпал во всех8 LISTENING и в WATCHED/6 OBSERVED выборках; private RAM максимум12075008 байт (~11,52 МиБ). Самpler/receiver STOP→exit0, stderr пуст, принудительной остановки не было. Это подтверждение идентификации/сбора памяти на простаивающем получателе, не измерение CPU под нагрузкой и не новый продуктовый benchmark. Код не менялся, повторных syntax/build/autotестов/runtime ProxyBridge/commit/push нет.

Следующий ручной прогон — прежний FAST: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-LocalUdpSoak.ps1" -Profile FAST` из PowerShell администратора, новая автоматическая папка udp-soak-fast-<UTC>-<id>. Три OFF/PROXY пары по20000×1200 байт, warmup100, pause0; native830с/proxy+sampler860с, фактическая длительность предварительно несколько минут (старый FAST3мин26с, banner5–20мин). Запускает пользователь; не запускать/ожидать в чате. Новые helper/interpreter hashes и strict receiver identity gate обеспечивают отдельную сопоставимую новую серию; старые launcher CPU/RAM не исправлять задним числом и не объединять с новыми.

После результата проверить receiver identity по каждому прогону, OBSERVED/coverage всех ролей и CPU/RAM действительного обработчика, расходы генератора/прокси/CLI, RTT/temп/payload/source defect/cleanup. Полный исправленный product/resource runtime pending. Core/driver/native неизменны, global/version gates false. Для разбора GPT-6.1 Sol/medium, для сложных расхождений high.

## Предыдущая точка: FAST разобран; исправлена идентификация receiver (2026-10-01)

`artifacts/local-route/udp-soak-fast-20261001-084255-aac0df`: COMPLETED, исходный статус LIMITED_COMPARISON/errors=[], 08:42:55–08:46:21 UTC (3 мин 26 с всей процедуры). По 60000/60000 обменов на режим, 20000×1200 байт на socket, warmup100, pause0. Все payload/socket path/mode/PROXY route свидетельства подтверждены; пропусков/невалидных/дублированных/неожиданных ответов нет. OFF socket измерялся 2,81–2,98 с, PROXY 7,74–7,93 с — краткие burst, не sustained high-load. Достигнутый темп медиан по повторам: OFF ~6818 echo/с (~65,45 Мбит/с полезных данных в каждом направлении), PROXY ~2536 (~24,34). Это последовательный echo с проверкой/журналом, не максимальная скорость ProxyBridge.

RTT медианы OFF/PROXY 0,070/0,291 мс, p95 0,134/0,443, p99 0,201/0,578. Парная delta +0,222 мс (+0,219…+0,224), включает весь локальный SOCKS5-путь и инструментирование. После warmup RTT>20мс нет. Все 60000 PROXY ответов от owned relay сохраняют SOURCE_ENDPOINT_MISMATCH; исправление не обнаружено. CLI средний CPU 3,16–3,50% всего ПК, средняя private RAM 2,66–2,74 МиБ. Proxy CPU 7,65–8,07%, generator OFF около16%, PROXY около6,5%; отдельная стоимость драйвера не измерена. Сессии короче20с, endpoint RAM trend не рассчитывался; прежние PowerShell выводы деления null давали0, это не измеренное отсутствие роста. Собственные процессы/выбранный драйвер остановлены, known loaded names отсутствуют, proxy STDIN_STOP/exit0, global/version gates false.

Обнаружен дефект ресурсной идентификации: роль receiver наблюдала Windows venv python.exe launcher (private RAM ~0,7 МиБ/CPU0), фактический обработчик был дочерним процессом. Изолированная проверка runtime без нагрузки подтвердила launcher PID8092 vs Python PID14616. Старый pc_metrics OBSERVED подтверждал покрытие назначенного PID, но не полного обработчика. Это ограничивает ресурсные выводы FAST и прежних серий с тем же launcher; транспорт/RTT/CLI данные сохраняются. В FAST summary.md и comparison-report.json добавлено post-run уточнение; исходные значения не подменены, перезапуска FAST не было.

Исправление: receiver запускается напрямую через тот же Python3.11 base executable, разрешённый из venv; pp-proxy окружение не изменяется. Receiver JSONL содержит process_id, контроллер проверяет PID всех LISTENING, sampler наблюдает этот PID/путь, receiver-identity.json фиксирует interpreter/helper SHA. Reporter сверяет PID всех run-records с WATCHED и receipt; при отсутствии/несовпадении pc_metrics INCOMPLETE, comparison требует receiver_identity_verified и одинаковые interpreter/helper hashes. Исторические записи без PID не могут задним числом подтверждать receiver CPU/RAM; при новом формировании отчётов ресурсный gate их отклонит.

Проверено: Python syntax 3 файлов, PS5.1/7 AST контроллера. Ручной receiver startup/STOP без ProxyBridge/трафика: `artifacts/local-route/receiver-identity-check-20261001-085446`, PID11936 совпал во всех8 LISTENING, OS подтвердил4TCP+4UDP сокета, exit0. Полное product/traffic CPU/RAM после исправления ещё не выполнено. Core/driver/native не менялись, автотестов/commit/push нет. Следующий срез — подтвердить учёт реального receiver под нагрузкой и оценить цену генератора/прокси/журналирования перед многопоточностью. Ручной запуск пользователем; GPT-6.1 Sol/high для подготовки, medium для анализа.

## Предыдущая точка: FAST готов к ручному запуску (2026-10-01)

Следующий срез по разрешению пользователя: `Invoke-LocalUdpSoak.ps1 -Profile FAST`, тот же комплект Driver 63be0eb, 3 чередующиеся OFF/PROXY пары, 20000×1200 байт на socket, warmup 100, **пауза 0 мс**. Существующий native generator уже поддерживает этот режим: следующий запрос сразу после echo, один запрос в полёте. Измеряется достигнутый последовательный темп с RTT/проверкой payload/журналированием; это не фиксированная интенсивность поступления, многопоточность или предельная скорость. Оценка 5–20 минут общей процедуры предварительная; короткие сессии не подменяют LONG-покрытие устойчивости. Новая папка `artifacts/local-route/udp-soak-fast-<UTC>-<id>` и соседний console .log.

Launcher дополнен FAST, контроллеры допускают интервал 0; native timeout теперь считает минимум 20 мс бюджета на пакет независимо от фактической паузы. Для FAST 830 с генератор/860 с proxy+sampler, для прежних STANDARD/LONG значения сохранены. Таймеры не задают темп нагрузки. Source/route/resource/cleanup критерии не ослаблены; недостаточное покрытие или новые ошибки остановят сравнение. Проверены PS5.1/7 AST, BOM всех 3 изменённых скриптов, передача zero interval и ограничения native. HEAD upstream InterceptSuite/ProxyBridge:Driver повторно совпал с 63be0eb. FAST runtime ещё не выполнен, Core/driver/native/reporters не менялись, новых сборок/установок/автотестов/commit/push нет. Global/version gates false.

Команда из PowerShell администратора: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-LocalUdpSoak.ps1" -Profile FAST`. Запускает пользователь; не запускать/ожидать в чате. После сообщения проверить достигнутый темп, RTT/ошибки, CPU/RAM покрытие и строгую UDP source классификацию. Многопоточность и оценка цены инструментирования остаются отдельными срезами. Для разбора GPT-6.1 Sol/среднее усилие, для расхождений высокое.

## Предыдущая точка: LONG завершён и проверен (2026-10-01)

`artifacts/local-route/udp-soak-long-20261001-070921-7b06d3`: COMPLETED/LIMITED_COMPARISON/errors=[], три чередующиеся OFF/PROXY пары. 07:09:21–08:15:15 UTC, 65 мин 54 с всей процедуры; каждый socket измерялся 613–628 с (10,2–10,5 мин). По 60000/60000 подтверждённых 1200-byte обменов на режим, 20000 на socket, первые 100 warmup, пауза 20 мс после echo. Все payload/socket path/mode свидетельства подтверждены; для всех PROXY наблюдался продуктовый маршрут. Пропусков/невалидных ответов/дубликатов/неожиданных источников нет. Темп 31,68–32,46 echo/с: это последовательная умеренная нагрузка, не capacity/high-load результат.

Медианы по повторам: RTT OFF 0,266 / PROXY 0,709 мс; p95 0,352 / 0,879; p99 0,643 / 1,034. Парная медианная добавка +0,442 мс (точное 0,4425), диапазон +0,441…+0,443, все 3 пары с одним направлением. Измеряется весь инструментированный локальный SOCKS5-путь, не выделенная стоимость ProxyBridge. После warmup нет RTT>20 мс (59700 ответов/режим). 21 RTT окно на прогон; PROXY оконные медианы 0,653–0,731 мс, максимальный оконный p95 0,992 мс. Это описание выбранных сессий, не общий вывод о стабильности. Предыдущие 512-byte серии имели delta +0,533 мс, но размер/длительность/время запуска различаются: не заявлять ускорение или причинный эффект размера пакета.

Строгая корректность OFF PASS, PROXY SOURCE_ENDPOINT_MISMATCH (все 60000 ответов от текущего owned relay), performance MEASURED_WITH_SOURCE_DEFECT. Исправление UDP-источника не обнаружено. CPU/RAM OBSERVED во всех 6 прогонах. CLI private RAM средняя 2,573–2,592 МиБ, медиана 2,58, максимум 2,70; средние последние/первые 10 с delta −92/−92/−88 КиБ. Рост между этими окнами не наблюдался; отсутствие утечки не доказано. CLI средний процессный CPU 0,009–0,018% всего ПК; driver-only/watts не измерены. Собственные процессы штатно остановлены, proxy STDIN_STOP/exit0/no forced stop; выбранный драйвер Stopped по receipts, инвентаризация известных имён после каждого прогона полна/имена отсутствуют. Global cleanup/version_switch_ready=false.

Разбор только сохранённых manifest/report/receipts/CPU-RAM/RTT окон и driver inventory; нового runtime/автотестов/изменений кода/Core/драйвера/native/commit/push нет. Результат сохранён в плане. Следующий предлагаемый срез — повышать частоту/одновременность и оценить стоимость per-packet инструментирования, сохраняя проверяемый маршрут/источник. Подготовка отдельной команды, длинный запуск пользователем; GPT-6.1 Sol/высокое усилие для подготовки, среднее для обычного разбора. A/B 4.0.0 не запускать до разрешения version-switch gates.

## Предыдущая точка: LONG-профиль готов к пользовательскому запуску (2026-10-01)

Пользователь согласовал следующий срез с прежним порядком: агент готовит команду, пользователь запускает и сообщает окончание. `Invoke-LocalUdpSoak.ps1 -Profile LONG`: тот же Driver 63be0eb, 3 чередующиеся пары OFF/PROXY, 20000×1200 байт на один socket, warmup 100, пауза 20 мс после echo. Оценка около 10 минут на непрерывное соединение и 65–80 минут общей процедуры; длительность не фиксирована. Объём данных на прогон выше прежнего в 7,8125 раза, частота пакетов не увеличена; высокая/предельная нагрузка и стоимость инструментирования требуют отдельных срезов. Новая папка `artifacts/local-route/udp-soak-long-<UTC>-<id>` и соседний консольный .log. Запуск без Profile сохраняет прежний STANDARD 6000×512.

Перечитан HEAD именно исходной upstream ветки `InterceptSuite/ProxyBridge:Driver`: 63be0eb. Проверены AST PS5.1/7 и UTF-8 BOM launcher, селективно границы native/controller (20000 сообщений, payload 1200), helper/sampler (бюджет 860 с при native timeout 830 с). Переиспользуется существующая рабочая цепочка, её строгие source/route/resource/cleanup проверки сохранены. Native/Core/драйвер не менялись, сборок/новых установок/автотестов/продуктового runtime/commit/push в подготовке нет. LONG ещё не выполнен; не утверждать его успех заранее. Global/version gates false, v4.0.0 не запускать.

Команда из PowerShell администратора: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-LocalUdpSoak.ps1" -Profile LONG`. После сообщения пользователя проверить manifest, все шесть receipts/полноту CPU/RAM, RTT окна/длительность каждого socket/private RAM и источники ответов. Не ждать/не запускать долгую серию в чате. Рекомендуемая модель для разбора — GPT-6.1 Sol, среднее усилие; для сложных расхождений — высокое.

## Предыдущая точка: ручной UDP soak завершён и сопоставлен (2026-10-01)

`artifacts/local-route/udp-soak-20261001-053954-9ff700`: COMPLETED, 3 чередующиеся пары OFF ↔ PROXY/SOCKS5, LIMITED_COMPARISON/errors=[]; 05:39:54–06:00:03 UTC, около 20 минут всей процедуры. В каждом режиме 18000/18000 подтверждённых обменов; каждый прогон 6000×512 байт, warmup 100, пауза 20 мс после echo, один connected IPv4 UDP socket. Замер каждого соединения 182–188 с, не непрерывная 20-минутная сессия и не предельная нагрузка. Для каждого пакета подтверждены payload/socket path/mode, для всех PROXY — наблюдение продуктового маршрута. Отсутствующих/невалидных ответов, дубликатов и неожиданных источников нет.

Медианы по 3 повторам: RTT OFF 0,314 / PROXY 0,850 мс; p95 0,507 / 1,228; p99 0,792 / 1,348. Парная медианная добавка RTT +0,533 мс, диапазон +0,443…+0,553; направление одинаково во всех парах. Это стоимость всего инструментированного локального SOCKS5-пути, не выделенная стоимость ProxyBridge. После прогрева нет RTT>20 мс (по 17700 измеренных ответов/режим). Все 18000 PROXY ответов пришли от текущего owned relay: strict SOURCE_ENDPOINT_MISMATCH сохраняется, исправление UDP-источника не обнаружено; OFF PASS. PROXY MEASURED_WITH_SOURCE_DEFECT, игровая совместимость не подтверждена.

CPU/RAM OBSERVED во всех 6 прогонах; helper budget 300 с, STDIN_STOP/exit0/forced=false. CLI CPU среднего замера 0,024–0,038% всего ПК, средняя private RAM 2,48–2,65 МиБ (медиана 2,64); разница средних последних/первых 10 с −92/−92/−616 КиБ. Роста между этими окнами нет, отсутствие утечек не доказано. RTT окна 30 с формируются (7/прогон); значения изменяются внутри/между сериями, вывода о постоянной задержке нет. Системный CPU и driver-only/watts не атрибутируются ProxyBridge. Собственные процессы штатно остановлены, выбранный SCM Stopped, известные WFP объекты/имена драйверов отсутствуют после остановки; global cleanup/version_switch_ready=false.

Разбор выполнен по сохранённым manifest/report/per-packet receipts/resource/worker/driver inventory, повторного трафика не было. Убрана устаревшая формулировка reporter «p99 короткой серии близок к максимуму»; Python syntax и пересоздание сравнения по тем же raw данным прошли, числа/status не изменились. Автотестов кода/commit/push/изменений Core/драйвера/native нет.

Следующий предлагаемый срез: согласовать более интенсивную UDP-нагрузку и более долгую непрерывную сессию, включая цену журналирования. Не объявлять готовность A/B 4.0.0: переключение версий не проверено. Для подготовки следующего среза — GPT-6.1 Sol, высокое усилие; для обычного разбора — среднее. Длинные серии по-прежнему запускает пользователь.

## Предыдущая точка: исправлен таймер вспомогательного UDP-прокси (2026-10-01)

Первый пользовательский запуск `artifacts/local-route/udp-soak-20261001-051912-86a4ac` остановился после pair-01-off: все 6000/6000 исходных endpoint-ответов подтверждены, PASS/MEASURED, 5900 после прогрева за 184,20 с. Но idle SOCKS5 helper завершился ровно через 60 с из-за старого watchdog. Его CPU/RAM покрыли только 55,49 с замера; pc_metrics INCOMPLETE, поэтому сравнение правильно не продолжилось. Это ошибка подготовки стенда, не наблюдаемый дефект ProxyBridge. PROXY в этой попытке не запускался. Receipt подтверждает остановку собственных процессов и выбранного драйвера, product_off_verified=true; global/version gates false. Исходные доказательства и FAILED manifest сохранены.

UDP helper теперь принимает ограниченный срок; контроллер передаёт тот же бюджет, что sampler: ceil(native timeout / 1000) + 30 с, для текущего профиля 300 с. Бюджет записывается в dependencies и проверяется при сопоставлении. STOPPED содержит причину; текущий контроллер требует STDIN_STOP, преждевременный watchdog/EOF не считается штатным завершением. Проверка полноты CPU/RAM сохранена, отчёт и ошибка контроллера называют неполные роли. Сохранённый OFF-отчёт сформирован заново без трафика: неполная роль proxy, 7 RTT окон, результат сравнения остаётся неподтверждённым.

Проверено: Python py_compile, AST PS5.1/7 с сохранённым BOM. Отдельная ручная проверка helper без ProxyBridge/нагрузки: `artifacts/local-route/udp-proxy-budget-check-20261001-053433`, бюджет 300 с; после 65,02 с процесс жив и владеет слушающим портом, STOP → STDIN_STOP/exit0, принудительной остановки не было. Это проверка устранения прежнего 60-секундного ограничения, не успешный длительный benchmark. Полная серия и долгий PROXY RAM trend ещё не подтверждены.

Следующий шаг: та же команда Invoke-LocalUdpSoak.ps1 из PowerShell администратора, новая автоматическая папка. Не запускать/ожидать долгую серию за пользователя. Для разбора — GPT-6.1 Sol, среднее усилие; сложные расхождения — высокое. Core/драйвер/native не менялись, автотестов кода/commit/push нет.

## Предыдущая точка: подготовлен ручной длительный UDP-профиль (2026-10-01)

Команда: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\src\ProxyBridge-TestLab\scripts\Invoke-LocalUdpSoak.ps1"` из PowerShell администратора. Профиль: local OFF ↔ PROXY/SOCKS5, 3 чередующиеся пары, 6000 сообщений на серию, 512 байт с run/sequence/padding, 100 warmup, пауза 20 мс после ответа, один connected IPv4 UDP socket на серию. Ожидается примерно 20–30 минут; это умеренный sequential soak, не фиксированная частота/предел скорости/модель конкретной игры. Пользователь запускает длинную серию сам и сообщает о завершении. Папка автоматически `artifacts/local-route/udp-soak-<UTC>-<id>`, итог summary.md / comparison-report.json; полный путь печатается до старта.

Расширен существующий native benchmark (до 20000 сообщений только в opt-in benchmark; идентифицированный payload 256–1200 байт), receiver понимает padding, sampler/controller имеют ограниченный срок для длинной серии. Проверка источника прежняя: owned relay допускается только для измерения, strict SOURCE_ENDPOINT_MISMATCH сохраняется. Индексация seq/hash ускоряет сопоставление свидетельств; отчёт содержит RTT окна 30 с, порог RTT>20 мс и private RAM первых/последних 10 с (не доказательство утечки). CPU/RAM требуют покрытия длительности с допуском 1 с на границы. Default коротких команд/ID сохранены; Core/драйвер не менялись.

MSVC x64 /W4 /WX успешно, новый native SHA 3E15489C81C76F36773623C113D1B7BDD5EB911E27DE45CE720C87BD51AB5484; PS5.1/7 AST и Python py_compile прошли, PS кириллица сохраняет UTF-8 BOM. После первоначальной отмены elevation пользователь разрешил повтор. Короткая пара artifacts/local-route/udp-soak-smoke-1: LIMITED_COMPARISON, 128/128 ответов на режим, OFF PASS/MEASURED, PROXY SOURCE_ENDPOINT_MISMATCH/MEASURED_WITH_SOURCE_DEFECT (128 owned relay, 0 unexpected). Источники/пакеты 512 байт/маршрут и ресурсы подтверждены, процессы штатно завершены, выбранный драйвер/известные объекты/имена отсутствуют; global/version gates false. Первый OFF-отчёт выявил NameError из-за потерянного if в индексированном фильтре. Исправлен, отчёт восстановлен из уже записанных данных, затем выполнен только PROXY без повторения OFF; manifest сохраняет resumed_from_error. Повторный короткий smoke из длинного launcher убран. Сам длительный профиль, его 30-секундные окна/долгий RAM trend ещё не проверены длинным runtime. Автотестов TestLab/commit/push/новых установок/изменений защит не было. Ethr/iperf3 изучены, причины выбора текущего echo-клиента — TOOLS_AND_REUSE.md.

Следующий шаг: после сообщения пользователя прочитать новый manifest/report и per-run receipts, подтвердить полноту/сопоставимость, изменения RTT/RAM во времени и сохранение UDP-дефекта. Не запускать длительный профиль за пользователя и не ожидать его в чате. Для обычного разбора — GPT-6.1 Sol, среднее усилие; при сложных расхождениях — высокое.

## Предыдущая точка: прямой UDP ↔ ProxyBridge/SOCKS5 сопоставлены (2026-10-01)

Расширен существующий контроллер `Invoke-WfpUnruledComparison.ps1 -ComparisonMode ROUTED`; default UNRULED сохранён. Обе стороны получают одинаковый ID нагрузки `local-udp-path-comparison`, прежние самостоятельные ID сохранены. Нативный клиент/Core/драйвер не менялись. HEAD Driver перед запуском снова совпал с 63be0eb. До/после и при активном продукте проверяется наблюдаемое состояние драйверов. Сравнение допускает только проверенный owned relay для продолжения производительности, сохраняя строгий дефект источника и его счётчики; будущий исходный endpoint допускается по текущим данным.

`artifacts/local-route/off-routed-comparison-1`: три чередующиеся пары OFF→PROXY, PROXY→OFF, OFF→PROXY, по 64 connected IPv4 UDP echo (8 warmup), пауза 100 мс. Все 192/192 обмена в каждом режиме подтверждены, одинаковы параметры/инструменты/комплект и имена остальных загруженных драйверов; LIMITED_COMPARISON, ошибок сопоставимости нет. OFF PASS/MEASURED, PROXY SOURCE_ENDPOINT_MISMATCH/MEASURED_WITH_SOURCE_DEFECT: 192/192 от owned relay, 0 unexpected. Медиана медиан RTT OFF 0,292 / PROXY 0,838 мс; p95 0,440 / 1,093; p99 1,058 / 1,338 (максимум каждой короткой серии). Парная медианная delta +0,542 мс, диапазон +0,486…+0,599 мс. Разница включает SOCKS5-прокси и журналирование, не выделенную стоимость только ProxyBridge; это не доказательство совместимости игр, высокой нагрузки или длительной стабильности. Private RAM CLI около 3,18 МиБ, CPU драйвера/ватты отдельно не измерены.

Все native/receiver/proxy/sampler exit0, capture complete, forced=false; CLI в трёх PROXY штатно остановлен, post-stop подтверждён. После каждого прогона SCM Stopped, известные WFP-объекты и имена драйверов отсутствуют. Global cleanup/version_switch_ready=false, 4.0.0 не запускалась. GUI/remote не подключены. Проверены PS5.1/7 AST, Python py_compile, реальные пакеты/маршрут/состояние/cleanup receipts. Автотестов TestLab, commit/push, изменений защит Windows не было.

Следующий шаг: подготовить длительный/более интенсивный UDP-профиль с репрезентативными размерами и заданным темпом, выбирая готовый движок и оценивая влияние журналирования. Модель: GPT-6.1 Sol, высокое усилие.

## Предыдущая точка: прямой baseline и парное сравнение вне правил выполнены (2026-10-01)

Добавлен `-TrafficMode OFF`, ID `product-off-direct`, и `scripts/Invoke-WfpUnruledComparison.ps1`. OFF не запускает CLI/драйвер; перед/после проверяются отсутствие GUI/CLI, SCM Stopped, известные WFP-объекты и имена загруженных ProxyBridge/WinDivert-драйверов. Новый read-only PSAPI observer компилируется в PS5.1/7; SeDebugPrivilege включается только в текущем helper token на время запроса и восстанавливается. Это ограниченный gate выбранного продукта, не доказательство отсутствия всех фильтров Windows и не разрешение переключать версии.

Реальная серия `artifacts/local-route/off-unruled-comparison-1`: три пары OFF→UNRULED, UNRULED→OFF, OFF→UNRULED. Все шесть прогонов PASS/MEASURED, по 192/192 исходных UDP-echo в каждом режиме. Одинаковые native client, комплект, receiver/idle proxy/sampler, размеры/назначение/темп пакетов; имена остальных загруженных драйверов совпали до/во время/после. По 64 пакета, первые 8 исключены из времени, пауза 100 мс после echo. Отчёт LIMITED_COMPARISON: медиана медиан RTT OFF 0,259 / UNRULED 0,249 мс, медиана p95 0,366 / 0,339 мс. Парная разница медиан (ON−OFF) −0,011 мс, диапазон −0,014…−0,004 мс; отрицательная разница не доказывает ускорения. Разница p95 меняет знак. CLI private RAM около 2,75 МиБ; CPU драйвера отдельно и ватты не измерены. Серия короткая и loopback, не высокая нагрузка/игровая совместимость/длительная стабильность.

Все native/receiver/proxy/sampler exit0 и capture complete; CLI в трёх UNRULED штатно остановлен без forced stop, его post-stop подтверждён. Служба Stopped, known WFP objects/loaded driver names отсутствуют после каждого прогона. Global cleanup/version_switch_ready=false; v4.0.0 не запускалась. Routed UDP defect здесь не проверяется и не объявлен исправленным. GUI/remote/4.0.0 для новых режимов ещё не подключены.

Проверены PS5.1/7 AST, C# Add-Type и Python py_compile, результаты ограниченных реальных прогонов и завершения собственных процессов. Native binary не менялся/не пересобирался этим шагом. Автотесты TestLab не писались/не запускались; Core/драйвер, защиты Windows, commit/push не менялись. Следующий шаг: сопоставимое сравнение прямого UDP с перенаправлением через SOCKS5, сохраняя отдельный строгий результат подмены источника; затем увеличение нагрузки/длительности. Модель: GPT-6.1 Sol, высокое усилие.

## Предыдущая точка: режим «приложение вне правил» подтверждён (2026-10-01)

Согласованный режим добавлен в локальный исполнитель `-TrafficMode UNRULED` и отчёт RU/EN, ID `product-running-unruled`. Driver 63be0eb (HEAD проверен 2026-10-01), Core/драйвер неизменены. Профиль: одно PROXY-правило для другого EXE, тестовый pb_net_client.exe отсутствует, DIRECT-правила нет. В benchmark режиме используется --benchmark-source-policy exact, relay допуск отключён. Active CLI/driver, live загрузка правила и watch list, callback DIRECT выбранного PID/назначения + socket/run/sequence/payload получателя + отсутствие пересылки через прокси образуют доказательство; один журнал Direct недостаточен.

`artifacts/local-route/product-running-unruled-2`: PASS/MEASURED, 64/64 ORIGINAL_ENDPOINT, 0 relay/unexpected, direct socket и данные совпали. После 8 warmup: 56 пакетов за 6,12 с, RTT median 0,28 / p95 0,51 мс. CPU/RAM: 23 выборки с 5,91 с покрытия; CLI private RAM 2,79 МиБ, system CPU около 2,28%. Нулевой измеренный delta CPU CLI ниже дискретности малой нагрузки, не доказательство отсутствия накладных расходов. Это короткий paced loopback, не высокая нагрузка/стабильность. Краткий summary.md / udp-benchmark-report.json. GUI/remote/4.0.0 для нового режима не подключены/не проверены; product-off baseline и численные парные дельты отсутствуют.

Первая попытка `product-running-unruled-1` доставила все 64 ответа напрямую, но parser не распознал Direct (UDP), поэтому INCONCLUSIVE сохранён. Поддержка точного UDP-суффикса Direct/Blocked добавлена в ProxyBridgeEvidence.psm1; после исправления выполнен один повторный bounded прогон. Native MSVC x64 /W4 /WX без предупреждений; PS5.1/7.6 AST, Python py_compile. Автотесты TestLab не писались/не запускались; commit/push нет.

CLI Ctrl+Break/exit0, forced=false, capture complete; native/receiver/proxy/sampler exit0/capture complete, service Stopped, known WFP objects absent. Global cleanup/version_switch_ready=false, A/B закрыт. Режим вне правил не проверяет routed UDP: в отчёте явно routed_udp_source_regression_covered=false, его PASS не означает исправления relay-дефекта. Сравнение фона требует сопоставимого product-off прогона, старый PROXY-прогон с иной конфигурацией/временем не выдавать за причинную дельту.

Следующий шаг: подтвердить исходное состояние без перехвата и подготовить сопоставимую серию без ProxyBridge, затем чередующиеся повторы для фоновых накладных расходов. Модель: GPT-6.1 Sol, высокое усилие.

## Предыдущая точка: короткий UDP-бенчмарк и CPU/RAM выполнены (2026-09-30)

Реальный elevated прогон `artifacts/local-route/socks5-udp-benchmark-1`, Driver 63be0eb (HEAD InterceptSuite/ProxyBridge Driver повторно совпал), неизменённые Core/драйвер, необязательный стендовый CLI. Connected IPv4 UDP через локальный SOCKS5, LocalhostViaProxy=true; native client направляет трафик исходному получателю без собственного SOCKS5. Все 64 пакета/echo сопоставлены по run/sequence/хешам с получателем/UDP-прокси/журналом продукта. Подмена источника у 64/64: relay 34011 вместо receiver 53122; strict SOURCE_ENDPOINT_MISMATCH. Потерь/дубликатов/неожиданных источников в наблюдаемых 64 обменах нет.

После 8 пакетов прогрева: 56 за 6,12 с, median RTT 0,82 мс / p95 1,26 мс, 9,15 пакета/с, 8,64 кбит/с полезных данных в каждом направлении. Пауза 100 мс после ответа: это короткий замер заданного темпа, не предел скорости/высокая нагрузка/длительная стабильность. На RTT QPC send→recvfrom не включено последующее хеширование/JSON, но прокси/получатель инструментированы по пакетам.

psutil 7.2.2/BSD-3-Clause, PyPI Windows abi3 wheel SHA verified, извлечён в bin/tools без глобальной установки. Sampler PID/start/path, интервал 250 мс, фон/прогрев/замер/восстановление; в замере 23 выборки с 5,92 с покрытия. Средний CPU CLI 0,044% всего ПК / private RAM mean/max 2,75 МиБ; system CPU 2,26%. Proxy/receiver/generator/sampler записаны отдельно. CPU приблизителен при столь малой нагрузке; ядро драйвера отдельно не выделено, ватты не измерены. Краткий итог RU/EN: summary.md, полный udp-benchmark-report.json.

Реализовано: opt-in --benchmark-relay-ip/port в существующем pb_net_client; контроллер подтверждает relay из live stdout + Get-NetUDPEndpoint по owned CLI PID и проверенному EXE. ORIGINAL_ENDPOINT / OWNED_RELAY / UNEXPECTED проверяется у каждого ответа. Валидный echo от owned relay позволяет продолжение, но оставляет fail:udp_response_source; другие ошибки не допускаются. Exit0 benchmark client означает завершение серии, не correctness pass. Без benchmark-опций strict source assertion остаётся. Будущее исчезновение подмены определяется текущими данными, не версией/константой порта: достаточная серия с ORIGINAL_ENDPOINT может пройти все строгие критерии; mixed/insufficient не маскируются. На исправленной версии не проверено, сравнение исторических результатов и UI ещё не реализованы.

Остановка: CLI Ctrl+Break/exit0, forced=false, capture complete; proxy/receiver/sampler/native client exit0, stdout/stderr complete. Служба ProxyBridgeDrv Stopped, известные WFP-объекты отсутствуют. Global interception cleanup и version_switch_ready=false; v4.0.0 не запускалась, A/B закрыт. Дополнительный runtime после этого прогона не выполнялся; отчёт переформирован из сохранённых данных после исправления поля declared_source_commit и добавления краткого RU/EN итога.

Проверено: native MSVC x64 /W4 /WX без предупреждений; Python py_compile; PS5.1/7.6 AST; один реальный bounded UDP-прогон и receipts. Автотесты TestLab не писались/не запускались. GUI/Core/драйвер не изменялись, commit/push не было. Ранее подтверждены TCP SOCKS5 (`attempt-3`) и HTTP CONNECT (`http-tcp-1`); DIRECT фактически использовал SOCKS5 вопреки журналу, не использовать как успешный baseline. Источник готового GUI: dentatli/ProxyBridge codex/hlk-minimal; решение автора ожидается.

Уточнение пользователя после прогона: нужно сравнение с прямым трафиком для добавленной задержки/игр. План обновлён: прямой без ProxyBridge/прокси ↔ выбранный путь даёт суммарную разницу; явный тот же прокси без ProxyBridge ↔ перенаправление через ProxyBridge помогает выделить его добавленные расходы при сопоставимом клиенте. Приоритет RTT median/p95/p99, вариация, потери/поздние ответы, CPU/RAM; ICMP ping не заменяет UDP echo. DIRECT-дефект не использовать как baseline, отсутствие перехвата должно быть подтверждено. Новых запусков/изменений кода в обсуждении нет. Следующий шаг: подготовить достоверный прямой baseline и сопоставимый отчёт; затем длительный/более интенсивный профиль UDP с репрезентативными размерами/темпом и оценкой накладных расходов журнала. Отдельно остаётся безопасное сравнение версий; не запускать v4.0.0 при закрытом cleanup gate. Модель: GPT-6.1 Sol, высокое усилие.

## Предыдущая точка: локальный TCP/SOCKS5 подтверждён; DIRECT нарушен (2026-09-30)

`Invoke-WfpLocalRouteProbe.ps1` и тонкий host `pb_controlled_proxy.py` выполняют две короткие IPv4 TCP-передачи через неизменённые Core/драйвер Driver 63be0eb и необязательный стендовый CLI. HEAD upstream Driver перечитан — та же ревизия. Контролируемый loopback-получатель существующий, SOCKS5 — pproxy 2.7.9 (MIT, wheel SHA-256 сверён с PyPI, без глобальной установки). Выпуск 2024 года: только временная диагностика маршрута, не выбранный движок производительности. GOST 3.3.0 был заблокирован Windows при чтении архива; не запускался, исключения/защиты не менялись.

Итог `artifacts/local-route/attempt-3/route-probe-receipt.json`: ROUTE_MISMATCH. PROXY — ROUTE_OBSERVED: PID/назначение/конфиг в accepted redirect, соединение прокси, его исходящий socket совпал с peer получателя; 114 байт echoed с совпадающими хешами/run-ID. DIRECT — payload вернулся (115 байт), но тоже через SOCKS5, вопреки журнальному Direct: несовпадение подтверждено сокетом получателя и прокси. Исходники закреплённого архива: TCP relay сохраняет cfg=0 и вызывает общий connection_handler, который выбирает первый живой proxy config; отдельной ветки DIRECT там нет. Область наблюдения: LocalhostViaProxy=true, выбранный процесс с DIRECT/PROXY на разных портах, один локальный SOCKS5; на другие комбинации вывод не переносить. Core/драйвер не исправлялись.

CLI штатно Ctrl+Break/exit0, forced=false, полный сбор доставленных байтов; оба клиента exit0 с проверенным путём; receiver/proxy exit0, служба Stopped, известные WFP-объекты отсутствуют. Global cleanup/version switching всё ещё false; A/B/нагрузка не выполнялись. Проверены Python syntax и PS5.1/7.6 syntax, автотестов TestLab нет. Attempt-1 остановился из-за области видимости PS callback (исправлено); attempt-2 подтвердил PROXY и отклонённый запрос DIRECT к прокси; attempt-3 разрешил оба адреса получателя для доказательства фактического пути. Все попытки сохранены.

Следующий шаг: короткие контролируемые TCP/HTTP-proxy и UDP/SOCKS5 сценарии; DIRECT считать отдельным обнаруженным дефектом, не успешным baseline. Не менять ProxyBridge без отдельной задачи. Модель: GPT-6.1 Sol, высокое усилие.

## Предыдущая точка: Driver без GUI — запуск/остановка подтверждены (2026-09-30)

RuntimeEnvironment допускает отсутствие GUI и запускает существующую проверенную kernel-службу напрямую; ProductOnly исключает адреса/генератор/SSH из отдельной проверки lifecycle. Подготовлены Register-WfpDriverService.ps1 и Invoke-WfpLifecycleProbe.ps1. Синтаксис 4 PS-файлов и C# SCM-reader проверены PS5.1/7.6; автотестов нет. GUI-источник пользователя: dentatli/ProxyBridge codex/hlk-minimal, SHA149137f4ecb85cd39d4d33ac840a9f1cb24facd2; локальная копия совпала с удалённой, GUI не менялся.

Служба ProxyBridgeDrv зарегистрирована повышенным помощником для artifacts/product-builds/driver-63be0eb-testlab-cli/ProxyBridgeDrv.sys. В успешной попытке 15:47:56–15:48:00 UTC: служба загружена, CLI/Core стартовали, readiness=true, graceful_stop=true, forced_stop=false, exit0, output_capture_complete=true, stop_transport=ctrl-break-delivered-process-exited. Затем служба Stopped, известные WFP-объекты не наблюдаются. Генератор/получатель не запускались; маршрута/скорости это не доказывает. `artifacts/lifecycle/driver-63be0eb/lifecycle-receipt.json`: START_STOP_OBSERVED; interception_cleanup_verified/version_switch_ready=false (полнота видимости, идентичность загруженного кода и все WinDivert-семейства не доказаны). Служба остаётся зарегистрированной, остановленной; защиты Windows не менялись. Стендовый build-receipt обновлён, исходные комплекты сохранены.

До успеха: WMI не увидела новую регистрацию (заменено на SCM); Windows отклонила ImagePath с буквальными кавычками (исправлена только наша запись с проверкой происхождения); SCM нормализовал путь, из-за чего чрезмерная raw-проверка wrapper дала отказ после уже выполненной коррекции. Эти попытки сохранены рядом с успешной. Следующий шаг — первый короткий локальный прогон с контролируемым прокси/получателем и подтверждением маршрута; перед benchmark перечитать HEAD Driver и закрепить ревизию. Legacy runtime закрыт, A/B не запускать без подготовки последовательных чистых состояний. GPT-6.1 Sol, высокое усилие.

## Предыдущая точка: необязательные стендовые CLI собраны (2026-09-30)

Согласовано и зафиксировано в плане/AGENTS: основной путь — установленный ProxyBridge 4.0.0+, стендовый CLI необязателен. Build-TestLabCli.ps1 создаёт изолированные копии штатного CLI: unbuffered stdout/stderr, Stop в основном потоке, DLL сохраняется до выхода процесса, добавлен shellapi.h. Core/драйверы/GUI копируются без изменения, хеши проверены; исходные комплекты сохранены. Новые комплекты: artifacts/product-builds/driver-63be0eb-testlab-cli и v4.0.0-release-testlab-cli; receipts/product.env рядом. PB_PROXYBRIDGE_CLI_VARIANT=testlab-unbuffered-v1 выбирает pipe, по умолчанию upstream/ConPTY. Вариант CLI отражён в файловой идентичности как заявленный, не автоматически доказанный; полнота событий продукта=false.

Проверено: 4 PS-файла в PS5.1/7.6; оба CLI MSVC x64 /W4 /WX без предупреждений; вручную --version через ConsoleHost/ProcessAdapter — 4.0.13-Beta / 4.0.0, exit0, separate-text-streams, полный сбор байтов. Эта команда выходит до загрузки Core; штатные startup/Stop/Ctrl+Break ещё не проверены. Get-ProductBuildIdentity с настоящими product.env вернул FILES_VERIFIED для обоих. При первом ручном вызове передана неверная hashtable вместо требуемого generic dictionary; исправлен вызов, затем успешное чтение. Исправлен тип Environment у терминального декодера (принимает dictionary runner); вручную тот же реальный VT OSVersion декодирован с product.env. Автотестов, загрузки драйвера и трафика нет; сборка UI не требовалась, C# не менялся.

Следующий шаг — подготовка запуска без GUI для CLI-комплекта Driver: старый RuntimeEnvironment пока требует GUI и bootstrap службы через него. Не обходить проверки службы/перехвата, real v4.0.0 остаётся закрыт, version_switch_ready=false. Затем — контролируемый startup/Stop до трафика и первый короткий локальный прогон. TESTSIGNING активен. GPT-6.1 Sol, высокое усилие. Ниже — история.

## Предыдущая точка: декодирование наблюдаемых строк CLI (2026-09-30)

ConPTY-транспорт обоих CLI сохранён. Подключён pyte 0.8.2 + wcwidth 0.2.13: отдельные пакеты с лицензиями, wheels проверены по PyPI SHA-256, lock с хешами и скрипт повторной подготовки. Python восстанавливает наблюдаемые строки экрана 240×80; PS-адаптер проверяет завершение/версии/хеш входа. Runner разбирает наблюдаемые маршрутные записи, audit-export включает обезличенный отчёт декодера. Исправлен разбор официальных префиксов [CONN]/[LOG]. Исходный VT остаётся приватным.

Проверено: синтаксис четырёх изменённых PS-файлов в PS5.1/7.6; Python py_compile; UI build — 0 ошибок/предупреждений. Ручной OSVersion через ConPTY: helper exit0, pyte и PS-адаптер восстановили Microsoft Windows NT 10.0.26200.0 (DECODED_OBSERVATIONS). Ошибка первого вызова из-за раннего snapshot при инициализации pyte исправлена. Автотестов, запуска ProxyBridge, драйверов и трафика нет; Ctrl+C и настоящие маршрутные записи не проверены. Скрипт подготовки и release-упаковщик не запускались. Комплекты: artifacts/product-builds/driver-63be0eb и v4.0.0-release; receipts/product.env сохранены. Подробности — DEVELOPMENT_SETUP.md.

Граница: восстановление терминального экрана не доказывает полный журнал; source_event_stream_complete/source_event_order_preserved/channel_capture_completed=false. Следующий шаг — выбрать канал полных маршрутных событий и подготовить последовательный жизненный цикл версий (либо чистые состояния VM). Изменения ProxyBridge ради журнала сначала обсудить. Реальный legacy runner закрыт, version_switch_ready=false. При разрешённом продуктовом запуске сначала подтвердить startup/остановку, затем маршрут. TESTSIGNING активен, повторная перезагрузка не нужна. Рекомендуемая модель: GPT-6.1 Sol, высокое усилие. Ниже — история.

## Перед разрешённой перезагрузкой (2026-09-29)

Пользователь отключил Secure Boot и поручил выполнить скрипт. Повышенный процесс через UAC подтвердил Secure Boot=false; `scripts/Set-DriverTestSigning.ps1 -Mode Enable` завершился успешно. Независимое чтение `bcdedit /enum {current}` подтвердило `testsigning Yes`. Результат: `artifacts/machine-setup/354073f8a5b344bba0008cc74537338a.json`, журнал рядом `.log`. Первый запуск был остановлен ExecutionPolicy; повторный использовал `-ExecutionPolicy Bypass` только в дочернем процессе, постоянные политики не менялись. HVCI и прочие защиты не менялись.

Сейчас нужна разрешённая пользователем перезагрузка. После загрузки: проверить активный TESTSIGNING и новое время загрузки, затем продолжить подготовку идентифицируемых сборок Driver/4.0.0. Драйвер не устанавливался/не загружался, продуктовый трафик и автотесты не запускались. Все изменения проекта сохранены в рабочем дереве, без commit/push. Сборки и успешно выполненные проверки предыдущих шагов не повторять.

## Текущая точка: WFP-объекты и тестовая подпись (2026-09-29)

Добавлен `pb_wfp_state.exe`: read-only транзакция Windows WFP, запрос известных GUID ProxyBridge и подсчёт связанных видимых фильтров. Интегрирован в снимки InterceptionState и упаковку. Сопоставляются состояние службы и отсутствие известных объектов; полнота ACL-видимости/происхождение сборки не доказаны, legacy runtime остаётся закрыт. Следующий шаг — идентифицируемые сборки Driver/4.0.0 и подготовка их последовательных прогонов, с учётом буферизации stdout старого CLI.

Пользователь разрешил TESTSIGNING и необходимую перезагрузку. Машина: текущий процесс без elevation, BCD читать нельзя; Secure Boot в реестре = 1. Настройки не изменялись, перезагрузка не выполнялась. Подготовлен `scripts/Set-DriverTestSigning.ps1 -Mode Enable|Disable`; запуск нужен из повышенной оболочки после изменения Secure Boot в UEFI. Другие защиты не отключать. Инструкция — [DEVELOPMENT_SETUP.md](DEVELOPMENT_SETUP.md).

Проверено: WFP-помощник собран MSVC x64 `/W4 /WX`; синтаксис четырёх PS-файлов — PS 5.1/7.6; просмотр кода и diff. Автотесты, WFP-помощник, скрипт изменения BCD, ProxyBridge и трафик не запускались. UI в этом шаге не менялся и не пересобирался.

## История предыдущих шагов

## Наблюдение перехвата (2026-09-29)

Добавлен `modules/InterceptionState.psm1`, снимки до подготовки и после runtime-попытки, включение в audit-export. WFP: CIM-состояние службы, совпадение пути/хеша файла. WinDivert: необязательный доверенный `windivertctl.exe list` v2.2.2 с проверенной соседней DLL, фиксированные аргументы, контроль завершения и строгий разбор. Отсутствующий наблюдатель — `NOT_CONFIGURED`; ошибка настроенного наблюдателя, найденные handles или несовпадение WFP-файла блокируют дальнейший прогон. Службы и чужие процессы не меняются. Утилита не скачана и не поставляется.

Проверены синтаксис трёх изменённых PowerShell-файлов в PS 5.1/7.6, сборка UI (0 ошибок/предупреждений), diff и адресный просмотр кода. Автотесты, CIM-наблюдение, WinDivert, ProxyBridge и трафик не запускались. Практическая работа наблюдателя ещё не подтверждена.

**Граница:** снимок одной WinDivert-версии и CIM не доказывают глобальную очистку; `version_switch_ready=false`. У проверенного WFP SHA нет IOCTL чтения enable/config. Следующий шаг: контроль выгруженного WFP-драйвера/его фильтров для последовательных версий либо сравнение прогонов из чистых состояний одной VM; также остаются готовность legacy CLI и происхождение сборок. Подробности и ключи — [DEVELOPMENT_SETUP.md](DEVELOPMENT_SETUP.md). Реальный v4.0.0 по-прежнему закрыт.

## Управление собственным CLI (2026-09-29)

Добавлены `src/pb_console_host.c` и `scripts/Build-ConsoleHost.ps1`: скрытая отдельная консоль, ограниченное наследование handles, атомарная привязка CLI к Job Object, CTRL+BREAK после проверки состава консоли, принудительная очистка только собственной job при ошибке/таймауте. ProcessAdapter сохраняет настоящий PID/путь продукта, различает способы остановки, ограничивает ожидание stdout/stderr. Неожиданное/принудительное завершение после готовности останавливает runner с `CONTAMINATED`. Помощник обязателен для реальных запусков и включён в упаковщик; пакет не собирался.

Проверки: MSVC x64 `/W4 /WX` — успешно; синтаксис PowerShell и компиляция встроенного C# в PS 5.1/7.6 — успешно; ограниченный просмотр кода/diff. Автотесты, помощник, ProxyBridge, драйверы и трафик не запускались. Доставка сигнала в runtime ещё не подтверждена.

**Следующий шаг:** наблюдение WinDivert handles через официальный `windivertctl list` (REFLECT/NO_INSTALL), состояние WFP и решение буферизации readiness-сообщения CLI v4.0.0. Реальный legacy-режим остаётся закрытым, `interception_cleanup_verified=false`. Доставка сигнала и код выхода 0 не доказывают очистку драйвера. Затем — происхождение сборок и A/B orchestration. Схема и ссылки в [DEVELOPMENT_SETUP.md](DEVELOPMENT_SETUP.md).

## Идентичность комплекта и граница очистки (2026-09-29)

`modules/ProductBuild.psm1` читает хеши/размеры/версии файлов без запуска продукта: Driver — CLI/Core/driver и настроенный GUI; v4.0.0 — CLI/Core/WinDivert DLL/SYS и настроенный GUI. Реальный runner сохраняет `product-build.json` и требует совпадения ожидаемых хешей до подготовки окружения; UI автоматически вычисляет новый хеш Core. Файловые хеши и необязательный заявленный source SHA остаются в audit-export; пути/секреты редактируются. Совпадение файлов не доказывает source commit, контракт или загруженный драйвер.

Проверены синтаксис изменённых PowerShell-файлов в 5.1/7.6 и сборка UI — 0 ошибок/предупреждений. Выполнен ограниченный просмотр кода и diff. Автотесты и продуктовые запуски не выполнялись; фактический runtime нового сборщика идентичности не проверен.

Для v4.0.0 план CLI требует сообщение об успешном запуске. Cleanup-отчёт явно описывает только остановку собственного процесса; очистка перехвата не подтверждена. Продолжение этого шага — в актуальном разделе управления CLI выше. Подробности в [DEVELOPMENT_SETUP.md](DEVELOPMENT_SETUP.md).

## Адаптеры профиля (2026-09-29)

Добавлен `modules/ProductProfile.psm1`: проверка представимости исходного профиля и отдельная сериализация `driver`/`v4.0.0`. Старый формат не получает `TargetDomains` и `SendDomainToProxy`; значимое доменное ограничение и включённая передача имени блокируют преобразование. В runner добавлены выбор контракта, проверка относительно второй версии до старта продукта и явный режим передачи IP. Причины RU/EN сохраняются в `profile-compatibility.json`; формат и параметры описаны в [DEVELOPMENT_SETUP.md](DEVELOPMENT_SETUP.md). Пока `v4.0.0` разрешён только для подготовки (`-DryRun`). Идентификация реальных сборок, жизненный цикл WinDivert, UI выбора версий и исполнение A/B ещё не реализованы. Проверены синтаксис трёх изменённых PowerShell-файлов в 5.1/7.6 и сборка UI (0 ошибок/предупреждений). Автотесты, генерация пробных профилей и продуктовые запуски не проводились.

## Версии для A/B (2026-09-29)

Пользователь выбрал последнюю ревизию ветки `Driver` как основную и официальный `v4.0.0` как базовую. HEAD `Driver`, прочитанный 2026-09-29: `63be0ebf9bec92bfba95ef3d6729c375aa9af84e`; перед настоящим прогоном перечитать и закрепить новый полный SHA. Тег `v4.0.0`: `22e53445e44481fad0f63c2a088aa91c0deda3af`. Оба Windows CLI принимают `.pbprofile`, но `Driver` применяет `TargetDomains`, а v4.0.0 CLI его не читает. Методика общего набора правил и условия сопоставимости записаны в [DEVELOPMENT_PLAN.md](DEVELOPMENT_PLAN.md). Это исследование и план; версии не собирались, не устанавливались и не запускались.

## Current direction (2026-09-28, development reset)

Read [DEVELOPMENT_PLAN.md](DEVELOPMENT_PLAN.md) first. The user requested local/remote proxy choice, realistic benchmarks, version comparisons, simpler UI, reuse of existing tools and no automated tests of TestLab code. Task 3a below is preserved but is no longer the automatic next task. Product traffic assertions remain necessary. Environment preparation and the new plan do not prove runtime correctness.

## Current resume point (2026-09-07, Task 3a isolated profile constructor)

The offline isolated-profile constructor slice is complete and independently
reviewed CLEAN. See `task-3a-profile-report.md` and `task-3a-profile-review.diff`
under `artifacts/sdd/FULL_INTERNET_TRAFFIC_PLAN`.

- New `modules/NegativeProxyProfile.psm1` and targeted PS5.1 test
  `tests/Test-NegativeProxyProfile.ps1`: RED/GREEN, review repair RED/GREEN.
- One exact TCP PROXY rule, fresh profile/config identity and generated
  credentials; no operator configuration/template input. Canonical IPs and
  reserved managed-server ports. Ordinary ProfileAdapter remains untouched.
- Pure private in-memory output, no generated file or runtime integration.
  `runtime_authorized=false`; construction is not readiness proof.

Next: signed semantic receipt contract and its negative/offline fixtures,
followed by derived readiness, orchestration and no-fallback/cleanup assertions.
Bind profile GUID, run and attempt alongside numeric config ID. Wire the new
constructor only behind complete receipt validation; never publish its private
profile object in reports. Keep both negative scenarios CAPABILITY_GATED and
`isolated_proxy_negative_target=false`. Do not redo accepted foundation/profile
slices. All offline/no-commit/no-push restrictions and approved Windows plus
separate Linux architecture remain in force. Task 3a is still incomplete.

## Current resume point (2026-09-07, Task 3a Fix round 2 accepted)

Milestone 16 remains active. Fix round 2 is complete for the unpromoted
negative-proxy semantic foundation only; do not repeat its implementation or
already-passing tests. The topology clarification below remains authoritative.

- Regenerated `artifacts/sdd/FULL_INTERNET_TRAFFIC_PLAN/task-3a-review.diff`
  mechanically from exact hash-verified pre-task baselines: 11 scoped files,
  8 changed. Complete module and fixture changes are included. See the adjacent
  `rebuild-task-3a-review.py` and `task-3a-review-provenance.md` for provenance.
- Primary `git apply --numstat` succeeded. Independent read-only review was
  CLEAN: all 11 current scoped files match the after manifest and
  `git apply --reverse --check` succeeds against current source.
- No production source edits, repeated tests, build, runtime/network, deployment,
  commit or push occurred in this repair-package pass.

Next: continue Task 3a with test-first isolated run-owned profile and signed
semantic receipt contracts, then derived readiness, orchestration and fail-closed
evidence/cleanup assertions, following the existing brief. Keep
`isolated_proxy_negative_target=false` and both negative-proxy scenarios
`CAPABILITY_GATED` until the complete contract is reviewed. No runtime proof is
claimed. Preserve all existing work and offline restrictions. Superpowers is not
the workflow; grill-me is only for separately requested quizzes.

The September 3 section below is historical; its unfinished-diff blocker is now
resolved. Task 3a as a whole and Milestone 16 are not complete.

## Approved architecture clarification (2026-09-07)

The user approved one Windows + separate Linux deployment model. Windows hosts
TestLab, ProxyBridge and generators; Linux hosts the managed SOCKS5 proxy,
protocol receivers and metrics. Windows VM + Linux VM is the primary topology;
LAN and VPS deployments use the same model. There are no separate Lab/Remote
modes. Local-only and Windows-colocated proxy coverage are explicitly excluded.
Configuration and preparation remain UI-driven with key-only SSH. Gate tests on
observed network capabilities. See section 3 of FULL_INTERNET_TRAFFIC_PLAN.md.

This turn records the design only. No implementation, verification or runtime
acceptance is implied. The unfinished Task 3a Fix round 2 continuation below
remains the development resume point. Superpowers is no longer the requested
workflow; preserve its historical reports as evidence. Use grill-me for optional
read-only code-understanding quizzes, not as an implementation workflow.

## Current resume point (2026-09-03, proactive usage-limit checkpoint)

The user asked to begin checkpointing while the usage window was low. Preserve
the dirty working tree exactly. Do not commit/push, start the UI, deploy the
endpoint, or run a real browser, ProxyBridge, client, driver/service, SSH,
listener, loopback, systemd or external-network traffic merely to resume.

### Authoritative milestone state

- The original roadmap remains Milestones 14-20. SDD Task numbers are only
  internal review-sized slices and do not replace project milestone numbering.
- Milestone 14 remains complete and was not redone.
- Milestone 15 is complete and accepted. Task 1 browser lifecycle, Task 2a
  browser origin, Task 2b-core evidence/route assertions and Task 2b-UI derived
  capability/readiness integration passed their focused gates and independent
  review. The final bounded Milestone 15 offline gate passed 9/9 after one
  environment-only retry; only `canary-browser-download` was promoted. No real
  browser or product correctness is claimed.
- Milestone 16 is active as SDD Task 3, executed serially as 3a isolated
  negative proxy, 3b receipt-bound backend restart, and 3c TestLab-owned network
  impairment. Existing executable `failure-dns`,
  `failure-client-process-exit`, and `tcp-process-termination` are preserved and
  are not being reimplemented.

### Active Task 3a state

- `artifacts/sdd/FULL_INTERNET_TRAFFIC_PLAN/task-3a-negative-proxy-brief.md`
  defines the scope and safety contract. The first implementer was lost at the
  usage reset before RED or code changes; the resumed implementer started from
  that exact point.
- An unpromoted semantic foundation is present:
  `src/server_agent/negative_proxy.py`, disabled protocol configuration,
  immutable bundle inclusion, a distinct reserved unavailable port, fail-closed
  config validation and focused offline tests. There is no negative-proxy bind
  path or listener.
- Initial RED was captured by `tests/Test-FailureControl.ps1` with the expected
  missing `negative_proxy` module. GREEN then passed. The affected ServerProbe
  build passed with 0 warnings/errors and `tests/Test-ServerProvisioning.ps1`
  passed after its synthetic repository included the new immutable artifact.
- Initial independent review was NOT APPROVED. Fix round 1 corrected the real
  PLANNED-plugin catalog break, exact staging self-test mismatch, valid SOCKS5
  multi-method parsing, password-dependent principal digest, false declarative
  UNBOUND wording, both-port collision validation and missing protocol-fixture
  export. Focused failure-control and provisioning checks then passed.
- Fix round 1 re-review confirmed the production safety corrections but did not
  approve the review package: its incremental diff omitted current code and the
  failure-control fixture, the manifests omitted a changed provisioning test,
  the unavailable-port collision lacked its own regression, and report wording
  overstated semantic `relay_count=0` as runtime proof.
- Fix round 2/5 reached a safe checkpoint. The independent unavailable-port
  collision regression was added and `tests/Test-FailureControl.ps1` passed;
  comparable manifests now include the changed provisioning test and the report
  correctly limits `relay_count=0` to evaluator intent rather than runtime
  proof. The exact complete incremental Task 3a review diff is still unfinished,
  so Fix round 2 and the foundation are not accepted. The loopback
  `tests/Test-ProtocolVerticalSlice.ps1` remains deliberately NOT RUN because it
  starts a listener and traffic prohibited by this offline slice; export
  inclusion is covered statically instead.

### Truthful capability state and remaining blocker

- `isolated_proxy_negative_target` remains false.
- `failure-proxy-unavailable` and `failure-proxy-auth` remain
  `CAPABILITY_GATED`.
- Task 3a is not complete. Promotion still requires a run-owned isolated
  `.pbprofile`, signed semantic/listener-or-unbound/rollback receipt, safe
  orchestration, exact PROXY config identity, complete real-destination
  zero-delivery evidence, no-fallback assertions and cleanup proof. Absence of
  endpoint payload alone can never prove a negative-proxy PASS.

### Exact continuation order

1. Regenerate the exact complete Task 3a incremental review diff, including all
   current `negative_proxy.py` and failure-control fixture lines. Then obtain a
   fresh independent CLEAN re-review of the unpromoted foundation; do not rerun
   already-passing tests merely to regenerate review evidence.
2. Continue Task 3a with TDD for the run-owned profile, signed semantic receipt,
   derived capability/readiness, orchestration and fail-closed assertions.
   Promote the two scenarios only after the complete offline contract passes
   and is independently reviewed.
3. Continue Milestone 16 serially with Task 3b backend restart and Task 3c
   namespace-local bounded impairment. Privileged actions must remain inside a
   generated UI-reviewed, allowlisted, receipt-bound plan with verified cleanup.
4. Continue the approved roadmap in order: Milestones 17, 18, 19 and 20. Do not
   redo accepted work.

No prohibited runtime/network action, commit or push was performed in this
continuation.

## Current resume point (2026-09-01, later user-requested limit stop)

Work stopped immediately when the user reported that the usage limit was
ending. Preserve the dirty working tree exactly. Do not commit/push, start the
UI, deploy the endpoint, or run a real browser, ProxyBridge, client,
driver/service, SSH, listener, loopback or external-network traffic merely to
resume.

### Project milestone numbering (authoritative)

The project plan is still Milestones 14-20. The SDD `Task` names below are
internal review-sized slices, not a replacement roadmap:

| SDD slice | Project milestone | Meaning |
|---|---|---|
| Task 1 | Milestone 15 | isolated real-browser worker and Windows process-tree lifecycle |
| Task 2a | Milestone 15 | controlled server browser-origin and immutable provisioning artifact |
| Task 2b-core | Milestone 15 | worker registry, scenario, execution plan, route/evidence assertions and mocks |
| Task 2b-UI | Milestone 15 | automatically derived browser/server capability, selection readiness and final offline browser slice |
| Task 3 | Milestone 16 | remaining safe failure injection and isolated negative-proxy/impairment integration |
| Task 4 | Milestone 17 | native performance runner, synchronized metrics and bounded soak orchestration |
| Task 5 | Milestone 18 | optional LAN peer receipt/topology gate |
| Task 6 | Milestone 19 | run profiles, restart-safe resume, typed metrics and readable UI/reporting |
| Tasks 7-8 | Milestone 20 | offline audit, isolated-VM acceptance preparation and final verification |

Milestone 14 was already completed in the approved baseline and is not being
redone. Current work is therefore still **Milestone 15**, split only so each
load-bearing interface gets its own TDD and review gate.

### Completed and accepted in Milestone 15

- Task 1 browser worker/process lifecycle is complete after its recorded
  breaker adjudication and focused `tests\Test-BrowserPlugin.ps1` PASS.
- Task 2a browser origin is complete: marker compatibility, truthful ALPN,
  Transfer-Encoding fail-closed behavior and the complete `/browser-origin`
  namespace were reviewed CLEAN. The primary focused browser-origin and server
  provisioning tests passed.
- Task 2b-core is now complete. The final evidence contract proves the two
  closed browser TCP connections with distinct canonical server
  `remote_port` values and uses a verified product route as mandatory
  corroboration. Missing route remains HOLD, mixed actions remain
  CONTAMINATED, and incomplete external evidence cannot become a product
  verdict.
- Fix round 4 added the formerly missing `remote_port` mutation. It produces
  exact `FAIL_HARNESS`, excludes product errors, and was mutation-proven to fail
  under a temporary production validation bypass. Production was restored
  unchanged. The primary agent independently observed
  `PASS: fail-closed protocol runner lifecycle and assertions`; the scoped
  re-review returned CLEAN.
- Only `canary-browser-download` is promoted. WebRTC and screen sharing remain
  capability-gated. Detailed evidence is in the Task 1/2a/2b-core reports,
  snapshots and review diffs under
  `artifacts/sdd/FULL_INTERNET_TRAFFIC_PLAN/`.

### Active but interrupted: Task 2b-UI / Milestone 15

- The implementation contract is fixed in
  `artifacts/sdd/FULL_INTERNET_TRAFFIC_PLAN/task-2b-ui-brief.md`; the exact
  pre-change files are in `task-2b-ui-before`.
- TDD tests were started but the implementer was interrupted before production
  work and before writing `task-2b-ui-report.md`:
  - `ui/ProxyBridge.TestLab.Ui.RunProbe/Program.cs` now contains offline tests
    for `DerivedRunCapabilitySnapshot`, `RunCapabilityReadiness` and
    `RunCapabilityDocument`;
  - `tests/Test-RunOrchestration.ps1` now asserts that the public settings/UI
    surface exposes no manual browser path or SHA/hash control.
- No Task 2b-UI production file changed. In particular,
  `ui/ProxyBridge.TestLab.Ui/Services/RuntimeCapabilityService.cs` does not yet
  exist. The added RunProbe tests deliberately reference the not-yet-created
  production types and therefore represent the pending RED state.
- No focused build/test result was returned before interruption; do not claim
  RED execution or GREEN. No verification was run after the stop request.

### Exact continuation order

1. Do not redo Task 1, Task 2a or Task 2b-core. Resume the interrupted
   `browser_ui_implementer` task from the existing test edits and
   `task-2b-ui-brief.md`.
2. If strict RED was not actually captured before interruption, build the
   existing UI/RunProbe projects as required and run only
   `tests\Test-RunOrchestration.ps1` once to record the RED. Then implement the
   smallest shared derived-capability service and rerun only that focused test
   for GREEN.
3. Complete Task 2b-UI, still inside Milestone 15: derive
   `local_browser_runtime` only from allowlisted local image/version/hash and
   `server_browser_origin` only from a current receipt-verified server state;
   expose selection-aware English readiness without adding manual browser
   path/hash fields or `.env` setup. Use the same derived state for readiness,
   real-run capabilities and immutable preflight capabilities.
4. Create the narrow Task 2b-UI review diff/report, obtain an independent CLEAN
   review, then run the bounded final Milestone 15 offline gate and accept only
   `canary-browser-download`. Real browser/ProxyBridge correctness remains a
   later explicitly authorized isolated-VM acceptance run.
5. Continue the original roadmap in order: Milestone 16, 17, 18, 19 and 20.
   The internal Task 3-8 labels are only the review slices shown in the table
   above.

To resume, say: `Продолжи по верхнему checkpoint в docs/WORK_CHECKPOINT.md;
мы всё ещё завершаем Milestone 15, продолжи Task 2b-UI с текущего TDD RED.`

## Current resume point (2026-08-31, user-requested limit stop)

Work stopped immediately when the user reported that the usage limit was
ending. The only active Task 2a fix subagent was interrupted. It had not
changed any scoped implementation or test file after the review snapshot; the
current scoped files still match `task-2a-after`. Preserve the dirty working
tree. Do not commit/push, start the UI, deploy the endpoint, or run a real
browser, ProxyBridge, driver/service, SSH, or external-network traffic merely
to resume.

### Completed and independently verified

- Task 1, the isolated browser worker, is complete. Five delegated fix rounds
  exhausted the review breaker; the primary agent then adjudicated the two
  remaining load-bearing findings with a failing regression and a narrow
  repair. CRT descriptors transferred by `open_osfhandle` are now explicitly
  owned through reader construction and independently closed on failure. The
  Job-containment fixture no longer allows fallback process termination to
  mask a broken Job.
- The primary post-adjudication command
  `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-BrowserPlugin.ps1`
  passed with `PASS: isolated browser worker core`.
- Task 1 evidence is preserved in `task-1-after-adjudication` and
  `task-1-adjudication-review.diff`; the ledger and
  `task-1-browser-worker-report.md` record the breaker ruling. Do not redo
  Task 1.
- Task 2a's first implementation integrated exact versioned browser-origin
  page/download routing, deterministic evidence, runtime bundling and plugin
  registration. The primary agent independently observed:
  `PASS: browser-origin` and `PASS: guarded offline server provisioning`.
  Its scoped baseline/current snapshots and review package are
  `task-2a-before`, `task-2a-after`, and `task-2a-review.diff`.

### Open Task 2a review findings — implementation is not accepted yet

1. `browser_origin.py` emits `PROXYBRIDGE_TESTLAB_BROWSER_RESULT_V1`, while the
   completed browser worker requires `PB_TESTLAB_BROWSER_READY`. The test only
   checked the initial placeholder, so a real completed page would fail with
   `BROWSER_DOM_MARKER_INVALID`.
2. The secure listener advertises ALPN `h2`, but its request parser accepts
   only HTTP/1.1. Chromium can therefore negotiate a protocol the listener
   cannot parse. Make ALPN truthful; do not fake HTTP/2 support.
3. Browser-origin GET currently ignores `Transfer-Encoding`; a chunked request
   can be treated as bodyless and emit successful evidence. It must fail
   closed with no success evidence.
4. Only `/browser-origin/` is reserved. Bare `/browser-origin` and its query
   variant can fall through to generic header-bound HTTP. Reserve the complete
   namespace while allowing success only for exact versioned paths.

The Task 2a fix-round-1 subagent was stopped before it changed the scoped
files. No fix-round RED/GREEN evidence exists yet.

### Exact continuation order

1. Do not rerun or redispatch Task 1. Resume Task 2a fix round 1 from the four
   findings above, within the existing Task 2a scope plus the already approved
   narrow ServerProbe fixture update.
2. Add focused regressions that fail on the current code: completed marker
   compatibility (not merely the placeholder), truthful ALPN, chunked browser
   request rejection with zero success evidence, and bare/query namespace
   rejection even with generic TestLab headers. Then make the minimum server
   and fixture changes.
3. Run only `tests\Test-BrowserOrigin.ps1` and
   `tests\Test-ServerProvisioning.ps1`, update
   `task-2a-browser-origin-report.md`, create the fix-round incremental diff,
   and dispatch a fresh read-only re-review. Do not accept Task 2a or promote
   `canary-browser-download` until review is clean.
4. After clean Task 2a review, continue Task 2b: worker registry,
   ProtocolRunner, exact route correlation, derived capabilities/readiness and
   truthful promotion of only `canary-browser-download`. WebRTC and screen
   sharing remain capability-gated until their genuine contracts exist.
5. Continue Tasks 3-8 in `artifacts/sdd/FULL_INTERNET_TRAFFIC_PLAN/progress.md`
   without redoing completed milestones. Real isolated-VM acceptance and soak
   remain separate authorized runtime work.

To resume, say: `Продолжи по верхнему checkpoint в docs/WORK_CHECKPOINT.md;
сначала заверши Task 2a fix round 1 и clean re-review.`

## Current resume point (2026-08-30, user-requested limit stop)

Work stopped immediately when the user reported 20% remaining in the current
five-hour usage window. The only active implementation subagent was
interrupted and is no longer running. Preserve the dirty working tree. Do not
redo Milestones 9-14, commit, push, start the UI, deploy the endpoint, or run
ProxyBridge/SSH/external-network traffic merely to resume.

### What happened in this continuation

- Superpowers SDD/TDD workflow and Serena navigation were resumed from the
  previous checkpoint. The task ledger is
  `artifacts/sdd/FULL_INTERNET_TRAFFIC_PLAN/progress.md`.
- Task 1 remained strictly limited to
  `src/protocol_worker/plugins/browser.py`,
  `tests/Test-BrowserPlugin.ps1`, and `tests/fixtures/browser/`.
- The original interrupted worker was observed RED because it passed fake-only
  `--testlab-*` switches. Its first Chromium-style repair reached the focused
  GREEN, but independent review correctly rejected it: a late child could
  escape the stale PID snapshot, caller arguments could add another URL,
  partial directory setup was unsafe, and the fixture checks were incomplete.
- Fix round 1 reached the focused GREEN. Re-review still rejected it because
  Job assignment happened after process execution began, Job cleanup failure
  could be overwritten, directory ownership was racy, and the exact URL was
  not enforced.
- Fix round 2 now contains a custom Windows suspended-launch path, intended
  order `CreateProcessW(CREATE_SUSPENDED) -> assign Job -> resume`, monotonic
  cleanup state, ownership-tracked profile/download directories, exact URL
  validation, Job query/close/assign/resume negative injections, and a
  timeout-safe focused-test driver cleanup path.
- The first Fix round 2 focused run hung and was interrupted. Systematic
  debugging localized it to the injected Job-assignment failure: the exact
  root remained suspended and unassigned while the old `taskkill /T` cleanup
  could block. The implementation was then changed to bounded direct
  `TerminateProcess` cleanup for known PIDs. A suspended unassigned root cannot
  have created a child.
- `artifacts/sdd/FULL_INTERNET_TRAFFIC_PLAN/task-1-browser-worker-report.md`
  currently contains a Fix round 2 PASS claim, but the primary agent did not
  observe that final run before interruption. Treat the claim as **unverified**
  and do not accept Task 1 from it.
- Independent review artifacts are preserved under
  `artifacts/sdd/FULL_INTERNET_TRAFFIC_PLAN/`: `task-1-before`, `task-1-after`,
  `task-1-after-fix1`, `task-1-review.diff`, and
  `task-1-fix1-review.diff`.
- A future server-side brief was prepared at
  `artifacts/sdd/FULL_INTERNET_TRAFFIC_PLAN/task-2a-browser-origin-brief.md`.
  It has not started and no shared manifest/server/UI file was changed for it.
- No real browser, ProxyBridge product, driver/service, SSH, endpoint
  deployment, external network, commit, or push was performed in this
  continuation.

### Exact continuation order

1. Before running anything, inspect only the exact prior fixture process names
   if needed to prove the interrupted diagnostic left no test-owned process.
   Do not perform a general process audit.
2. Run exactly once:
   `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-BrowserPlugin.ps1`.
   If it hangs or fails, use the bounded test-driver cleanup and continue
   systematic debugging from the suspended assign-failure path. Do not weaken
   the assertions or revert to `taskkill /T` in production cleanup.
3. If the focused test is GREEN, create a Fix round 2 incremental diff from
   `task-1-after-fix1` to the current scoped files and dispatch a read-only
   re-review. The reviewer must verify atomic suspended assignment/resume,
   monotonic Job/handle cleanup, exact-PID termination, ownership-safe
   directory cleanup, exact URL/flag enforcement, and no false PASS.
4. Only after a clean re-review mark Task 1 complete in the SDD ledger. Then
   begin Task 2a from its brief. Do not promote `canary-browser-download`
   before the full browser-origin/runner/route/UI offline vertical slice.
5. Continue Tasks 2-8 in the existing ledger order. Real isolated-VM
   correctness and long soak remain separately evidenced acceptance runs; an
   offline test must never claim they passed.

To resume, say: `Продолжи по верхнему checkpoint в docs/WORK_CHECKPOINT.md;
сначала заверши Task 1 Fix round 2 и re-review.`

## Current resume point (2026-08-30, usage-limit pause)

Work stopped immediately at the user's request. The three active subagent tasks
were stopped; no background implementation should be assumed to continue after
this checkpoint. Preserve the dirty working tree. Do not redo Milestones 9-14,
commit, push, start the UI, deploy the endpoint, or run ProxyBridge/SSH/network
traffic merely to resume.

### Completed and checked in this continuation

- The stale M12-M16 checkpoint gate was executed before new work. Catalog,
  protocol-worker, protocol runner, server provisioning, UI shell and the
  M12-M16 offline vertical slice all passed.
- All 15 remaining `DECLARATIVE_ONLY` entries were moved to explicit, truthful
  capability gates rather than being presented as implemented traffic. Current
  catalog inventory is 205 total: 171 `EXECUTABLE`, 0 `DECLARATIVE_ONLY`, 22
  `CAPABILITY_GATED`, 5 `SYSTEM_CHECK`, and 7 `UNSUPPORTED_PRODUCT_SCOPE`.
  `tests/Test-Catalog.ps1` was observed RED before the catalog change and PASS
  after it.
- `config/capabilities.json` now names the missing browser, browser-origin,
  WebRTC-peer, synthetic-media, negative-proxy, restart-control, performance
  worker/origin, server-window and local-product-metric capabilities. They are
  disabled until their real readiness evidence exists.
- Automatic browser discovery was added to
  `ui/ProxyBridge.TestLab.Ui/Services/LocalArtifactService.cs`. It uses only a
  fixed Edge/Chrome/Chromium candidate list and derives path, version and image
  hash for the run-owned environment; there is no UI or `.env` browser-path
  field. The RunProbe test was observed RED before implementation. The Release
  build then passed and `tests/Test-RunOrchestration.ps1` passed. One nullable
  warning remains at `LocalArtifactService.cs` around the browser basename
  assignment and should be removed before the next build.
- The pure receipt-bound restart-control core is present in
  `src/server_agent/failure_control.py`, with an injected adapter and no direct
  systemd/network capability. `tests/Test-FailureControl.ps1` passed offline.
- The deterministic browser-origin core is present in
  `src/server_agent/browser_origin.py`. `tests/Test-BrowserOrigin.ps1` passed
  offline. It is not yet wired into the endpoint listener or provisioning
  manifest.
- The isolated native performance-worker source/build contract is present in
  `src/pb_perf_client.c`, `scripts/Build-PerformanceHarness.ps1` and
  `tests/Test-PerformanceWorker.ps1`. No C compiler was available; the test
  therefore completed only the explicit source/argument validation gate and
  did not claim a binary self-test.
- No product process, driver/service, SSH, server deployment, external network,
  commit or push was performed.

### Interrupted work that is not validated

- `src/protocol_worker/plugins/browser.py`, `tests/Test-BrowserPlugin.ps1` and
  `tests/fixtures/browser/` are a work in progress. The first draft incorrectly
  depended on fake-browser-only command-line flags. Review feedback required a
  real Chromium-supported surface (`--dump-dom` plus a bounded virtual-time
  budget and controlled-page marker), bounded actual-image probing, and all
  `browser-session` evidence fields. The subagent was interrupted while making
  that repair. Do not promote `canary-browser-download` to `EXECUTABLE` or trust
  this test until the implementation and test are reviewed and rerun.
- `tests/Test-PerformanceOrigin.ps1` exists in RED/incomplete state, but
  `src/server_agent/performance_origin.py` and its fixture were not created
  before the subagent was interrupted. Continue from the failing test; do not
  delete or silently weaken it.
- The new browser/failure/performance cores are not registered in shared
  manifests, endpoint artifacts, PowerShell dispatch, capability generation,
  reports, packaging or `tests/Run-All.ps1` yet.

### Exact continuation order

1. Review the interrupted browser worker diff. Replace every fake-only browser
   flag with the real controlled-page/DOM-output contract, add bounded observed
   image probing and process-tree cleanup evidence, then run only
   `tests/Test-BrowserPlugin.ps1`.
2. Integrate browser-origin and browser-worker through the protocol manifest,
   server plugin manifest/artifact builder, endpoint listener, ProtocolRunner,
   process-tree route correlation, automatically derived capability file and
   selection-aware UI readiness. Promote only `canary-browser-download` after
   the complete offline vertical slice passes. Keep WebRTC and screen-sharing
   gated until a genuine remote `RTCPeerConnection` contract exists.
3. Review and integrate `failure_control.py` only through a generated,
   allowlisted, receipt-bound privileged adapter. The negative-proxy and restart
   scenarios remain gated until the run-owned proxy/profile and rollback
   evidence contracts are complete.
4. Complete the already-written failing performance-origin test, then review
   the native worker. Do not enable performance scenarios until an x64 binary
   passes integrity/calibration self-test and synchronized local/server metric
   windows are implemented.
5. Continue Milestones 18-20 in the approved order: LAN-peer receipt gate;
   restart-safe run-profile/resume and typed metric UI; offline audit and
   isolated-VM acceptance preparation.
6. Update catalog counts only as complete gates become executable. Finish with
   the planned targeted tests, one final `tests/Run-All.ps1`, syntax/diff/gating
   checks and concise milestone reports. Real VM correctness and the 24-hour
   soak remain separate, explicitly authorized acceptance runs.

To resume, the user can simply say: `Продолжи по docs/WORK_CHECKPOINT.md с
пункта 1, не переделывая завершённое.`

## Current resume point (2026-08-29, latest pause)

Work was paused immediately at the user's request because the usage window was
ending. Preserve the current dirty working tree. Do not commit, push, restart
the UI, deploy the endpoint, or run ProxyBridge/SSH/external-network traffic
when resuming unless the user explicitly changes the approved plan.

### Completed and verified in the latest continuation

- Milestone 14 protocol work is complete: FTP/FTPS, SMTP/SMTPS, IMAP/IMAPS,
  POP3/POP3S, MQTT/MQTTS, AMQP/AMQPS, NTP, IRC/IRCS and controlled multi-peer
  transactions have client/server evidence contracts and passed the local
  loopback vertical slice. SFTP remains an explicit capability gate; FTP is not
  used as a substitute for SSH/SFTP.
- Milestone 15 controlled realtime work is present for STUN Binding, TURN
  Allocate, authenticated encrypted RTP/RTCP media and registered receive-only
  UDP. The M12-M15 loopback slice passed. Real browser/WebRTC coverage is not
  implemented and must not be claimed by synthetic UDP traffic.
- Milestone 16 controlled DNS SERVFAIL and supervised client-process
  termination are implemented. `failure-dns`, `failure-client-process-exit`
  and `tcp-process-termination` are executable protocol-worker scenarios.
- The Windows process-termination fixture was repaired so a TCP reset produced
  by `TerminateProcess` is accepted as disconnect evidence only after the full
  framed payload and its SHA-256 have already been validated. The updated
  M12-M16 protocol loopback vertical slice passed once:
  `PASS: Milestones 12-16 protocol loopback vertical slice`.
- A stale diagnostic Python process and only its exact
  `.failure-debug-f88949a1c88e497d9197cf67b981b7c6` directory were removed.
- No real ProxyBridge GUI/CLI, driver, SSH, endpoint deployment or external
  network test was run in this continuation.

### Latest edits not yet revalidated as a group

- `src/server_agent/failure_protocols.py` contains the Windows RST/EOF repair.
- `tests/Test-Catalog.ps1` was updated to the current expected catalog counts
  and to require the three completed Milestone 16 scenarios to be executable.
- `tests/Test-ProtocolWorker.ps1` now expects 19 implemented worker plugins.
- Those two updated targeted tests and the broader suite were **not run after
  the final expectation edits**, because work stopped immediately on request.
- Current catalog inventory measured immediately before the pause is:
  205 total, 171 `EXECUTABLE`, 15 `DECLARATIVE_ONLY`, 7 `CAPABILITY_GATED`,
  5 `SYSTEM_CHECK`, and 7 `UNSUPPORTED_PRODUCT_SCOPE`.

### Remaining 15 declarative scenarios

- Browser/realtime: `canary-webrtc`, `canary-screen-sharing`,
  `canary-browser-download`.
- Failure injection: `failure-proxy-unavailable`, `failure-proxy-auth`,
  `failure-backend-restart`, `udp-backend-restart`.
- Performance: `performance-latency`, `performance-throughput`,
  `performance-cpu`, `performance-memory`, `performance-handles`,
  `performance-threads`, `performance-flow-rate`,
  `performance-datagrams-per-second`.

The approved plan requires honest evidence. A real Chromium/browser adapter,
an isolated negative proxy, synchronized endpoint restart control, a native
performance generator and product/server metric windows must be implemented or
explicitly capability-gated. Do not relabel a synthetic approximation as real
browser, WebRTC, proxy-failure or performance coverage.

### Exact next actions

1. Run the narrow current-state checks: catalog, protocol-worker, protocol
   runner, server provisioning, UI shell and the M12-M16 vertical slice. Repair
   any stale count/fixture expectation before adding more functionality.
2. Finish Milestone 16: isolated negative-proxy and restart contracts, then
   TestLab-owned bounded impairment controls with rollback evidence. Keep all
   privileged actions inside the generated UI-reviewed server plan.
3. Finish Milestone 15 browser-dependent work with automatic browser discovery,
   an isolated profile/process tree and real browser-observed evidence. If no
   supported browser exists, return `SKIPPED_CAPABILITY`; never substitute the
   requested executable path for the observed process image.
4. Finish Milestone 17 with the native performance worker, same-run DIRECT
   baseline, synchronized local/server samples, bounded soak/cancellation and
   post-load recovery. Then complete optional Milestone 18 LAN-peer gating.
5. Complete Milestone 19 restart-safe resume, UI run-profile selection,
   readable per-test metrics/log explanations and sanitized export. Complete
   Milestone 20 offline audit and isolated-VM acceptance preparation last.
6. Only after all gates pass, update milestone reports and the final catalog
   counts. Commit and push remain prohibited.

---

## Current resume point (2026-08-29)

Work is intentionally paused at the user's request. Preserve the current dirty
worktree; do not commit, push, restart the UI, or run a live server/network gate
while resuming this checkpoint.

### Completed since the previous checkpoint

- Milestone 13 has a complete local vertical slice for HTTP/2, gRPC,
  WebSocket/WSS, QUIC/HTTP/3 and WebTransport, including client plugins,
  server listeners, catalog entries, runner integration and offline bundled
  dependencies.
- The last completed M13 checks passed: catalog, protocol runner lifecycle and
  assertions, the DNS/TLS/HTTP/1.1 plus M13 loopback vertical slice, UI shell,
  guarded offline server provisioning, and the Release UI/probe builds with
  zero warnings and zero errors.
- One first-run M13 vertical-slice invocation returned a transient
  `PROTOCOL_SERVER_ERROR UNEXPECTED_FAILURE`; the immediate bounded
  reproduction and the next targeted run passed. Repeat and investigate this
  before declaring M13 final so that a flaky startup cannot be hidden.

### In progress and not yet validated

- Milestone 14 source work has started for FTP/FTPS, SMTP/SMTPS, IMAP/IMAPS,
  POP3/POP3S, MQTT/MQTTS, AMQP/AMQPS, NTPv4, IRC/IRCS and a controlled
  two-peer TCP relay. SFTP remains explicitly capability-gated because a real
  SSH host-key and SFTP-subsystem contract is not implemented.
- The new M14 Python sources, server catalog/configuration, UI artifact builder,
  runner profiles and scenario catalog are present, but M14 is **not complete**.
- Initial Python/PowerShell/JSON static checks passed before the latest
  multipeer stream-lifetime fix. That fix has not been rechecked.
- The bundled protocol worker is stale relative to the M14 sources. C# has not
  been rebuilt after the M14 changes. Catalog counts and the vertical-slice
  fixture still reflect M13, and no M14 loopback transaction has run.
- The UI development process was stopped deliberately to release a locked DLL
  and has not been restarted. No live server gate was retried in this segment.

### Exact next actions

1. Re-run the bounded static checks after the latest multipeer fix.
2. Inspect and complete the SecurityProbe/ServerProbe M14 fixtures, then build
   the C# projects once.
3. Rebuild the offline protocol-worker bundle from the pinned dependencies.
4. Update the vertical-slice fixture for 25 listeners and add real M14
   transactions, including fail-closed negative cases.
5. Run and, where lifecycle stability requires it, repeat the targeted M13/M14
   checks; investigate the recorded transient M13 startup failure.
6. Recount and update catalog/UI expectations and documentation only after the
   executable M14 paths pass.
7. Proceed to Milestone 15 only after Milestone 14 is fully green.

Commit and push have not been performed.

---

Timestamp: 2026-08-28  
State: Milestones 9-11 complete; Milestone 12 offline gate passed; server discovery is `PLAN_READY`

## Authoritative state

- `docs/FULL_INTERNET_TRAFFIC_PLAN.md` remains the approved autonomous plan
  through Milestone 20. Continue without requesting approval between milestones,
  but keep every runtime action behind its declared readiness and evidence gate.
- Milestones 9 and 10 are complete: protocol contracts, the dependency-locked
  worker SDK, the offline bundle builder and their dependency-free tests exist.
- Milestone 11 is complete: the Debian/Ubuntu systemd server plugin catalog,
  agent, provisioning plan, trust/preflight handling, report and server tests
  are present.
- Milestone 12 server-side DNS, TLS, HTTP and HTTPS vertical slices are present:
  `pb_protocol_server.py`, fixed TestLab-owned ports, locally generated TLS
  material, server plugin declarations and provisioning/listener verification.
- Milestone 12 client-side DNS, TLS and HTTP/1.1 workers are implemented. A
  no-response expectation now produces explicit bounded evidence, while an
  unexpected response fails closed.
- The catalog/UI plumbing now carries `executor_kind`, `protocol_family` and
  `evidence_profile_id`; a selected protocol-worker test has a dedicated local
  runtime readiness gate.
- Automatic runner environment materialization now exposes protocol worker,
  manifest, evidence contract and CA paths with internally computed hashes.
  These hashes remain hidden from human settings fields.
- Runtime preflight optionally validates every protocol artifact when the
  protocol runtime is present, without adding Python to global process cleanup.
- `ProtocolRunner.psm1` and `Run-WfpMatrix.ps1` now execute protocol-worker
  plans through standard evidence filenames. DIRECT, BLOCK and PROXY mock
  integration passes without treating a complete zero-record BLOCK capture as
  missing evidence.
- A separate protocol-worker actual-path probe timeout and exact five-artifact
  prelaunch validation keep the CLI lifecycle contract unchanged.
- The protocol CA is persisted as a public PEM; the server private key remains
  inside the protected certificate store and server bundle only.
- The NTP default moved to port 42132 because 42123 overlapped the declared FTP
  passive range. The port catalog now rejects overlaps.
- No PowerShell test listener remains. The old `TcpListener` source that caused
  a Windows Firewall prompt was removed; ephemeral loopback ports are allocated
  by the isolated Python fixture server. The user can safely choose Cancel if a
  prompt from an already-running old test is still visible.
- No ProxyBridge GUI/CLI, driver action, external client or real traffic matrix
  has been run in this continuation.
- A private test server was reached with the configured SSH key. Windows
  `ssh-keyscan` failed on the server's newer KEX preference, so the UI now uses
  a protected, authenticated, ephemeral `known_hosts` fallback and deletes it
  after extracting the public host key. The user independently confirmed the
  first-use host identity; read-only discovery then verified supported Ubuntu,
  systemd, non-interactive sudo, Python and sufficient disk. The endpoint is not
  installed yet and the guarded workflow is now `PLAN_READY`. Private target,
  user, key path and fingerprint are deliberately absent here.
- Protected non-password fields now use text inputs with autocomplete disabled;
  they no longer trigger browser password-storage prompts.
- Environment Setup now presents five ordinary sections and groups timeouts,
  retention, interface values and technical ports under Advanced. SOCKS5 and
  Test network purposes are explained in user language. Async settings/server
  actions disable on the first click, reject repeat clicks and show a spinner
  plus an operation label until completion.
- Commit and push were not performed.

## Last completed checks

- PowerShell syntax: PASS (136 `.ps1`/`.psm1` files).
- Release UI/ServerProbe builds: PASS, 0 warnings, 0 errors.
- `tests/Run-All.ps1`: PASS (26/26 targeted tests under Windows PowerShell 5.1).
- `tests/Test-ProtocolMatrixIntegration.ps1`: PASS for the selected protocol
  DIRECT/BLOCK/PROXY orchestration path.
- Release UI build after the settings UX repair: PASS, 0 warnings, 0 errors.
- `tests/Test-UiSettings.ps1`: PASS after password-manager and repeat-click
  prevention plus the simplified settings projection.
- `tests/Test-ServerProvisioning.ps1`: PASS after the compatible host-key
  discovery fallback.
- Local bundled CPython 3.11 x64 protocol worker: 722 files, self-test PASS.

## Exact continuation point

1. Create and review the UI-generated exact server plan.
2. Apply it, and require matching hashes,
   plugin self-tests, active/enabled systemd state and every declared listener.
3. Run the authorized protocol-only server smoke without ProxyBridge, then
   complete `docs/MILESTONE_12_REPORT.md`.
4. Continue Milestones 13-20 in order, stopping on any false-positive risk,
   missing mandatory evidence or cleanup contamination.

## Files most recently edited at the pause

- `modules/Env.psm1`
- `modules/RuntimeEnvironment.psm1`
- `modules/ScenarioCatalog.psm1`
- `scripts/Export-UiCatalog.ps1`
- `src/protocol_worker/plugins/common.py`
- `src/protocol_worker/plugins/dns.py`
- `src/protocol_worker/plugins/tls.py`
- `src/protocol_worker/plugins/http1.py`
- `tests/Test-ProtocolVerticalSlice.ps1`
- `ui/ProxyBridge.TestLab.Ui/Models/CatalogScenario.cs`
- `ui/ProxyBridge.TestLab.Ui/Services/LocalArtifactService.cs`
- `ui/ProxyBridge.TestLab.Ui/Services/RunReadinessService.cs`
- `ui/ProxyBridge.TestLab.Ui/Services/SettingsSchema.cs`
- `ui/ProxyBridge.TestLab.Ui/wwwroot/app.js`
- `ui/ProxyBridge.TestLab.Ui/wwwroot/index.html`
- `ui/ProxyBridge.TestLab.Ui/wwwroot/styles.css`
- `tests/Test-UiSettings.ps1`
- `ui/ProxyBridge.TestLab.Ui.ServerProbe/Program.cs`
- `ui/ProxyBridge.TestLab.Ui.SecurityProbe/Program.cs`


# TCP setup 065347 разобран; причина ещё требует подтверждения (2026-10-06)

Все968связок уникальны,96ошибок. SYN→connect504–511мс толькоуfailed;success≤0,096мс. ПотериETW0,78originalfilesunchanged. Отказы связаны с199–202наблюдаемыми ожидающими приёма сокетами; actualkernelqueue имеханизмутратыcontext не прочитаны. [Разбор](C:\src\ProxyBridge-TestLab\artifacts\diagnostics\tcp-setup-review-20261006-065346/analysis.md). Новыйцелевой16eventtrace,samebinarykit,files/fakecheckspassed: [HANDOFF](C:\src\ProxyBridge-TestLab\artifacts\diagnostics\tcp-redirect-context-preparation-20261006-070917-d31f549e/verification/HANDOFF.md). NEXTUSERADMINInstall→manualreboot→Run2–4мин, дождатьсяcleanup/save. Старый064810RESTORED; прежние записи нижеисторические.


## 2026-10-07: unified capture receiver identity refusal

USER Run135055 / fullTrace135054: receiver successfully bound/listened but PID identity handshake failed before native client. Offline saved ETL:2786 selected,827 receiver events/4.7943681s; cancelled accepts at teardown. Original host forced cleanup retained, callback/exit ordering unavailable; no root-cause evidence for the original WFP context fault. Saved CLI/other helpers clean; original service path/hash/Stopped/detached restored in saved receipts.209 user files protected, old freeze/report not rewritten.

Opt-in startup ACK keeps receiver suspended until its retained process handle/path are confirmed; child exit and wait/callback QPC retained. Real CTS no-client controls PS5/7 ACK/default gracefulexit0; host READY/EOF/bad/timeout/earlyexit37 and adapter identity refusals verified;14 capture checks+8 frozen-plan checks each. Only console host rebuilt; no product/sys/sign/install/live capture/client.

Fresh tcp-redirect-context-preparation-20261007-140958-ae8a2209:PS5Prepare+PS5PS7Inspect FILES_VALIDATED,55+13 hashes exact,CLI/Core/sys acece5c3 and140 copied source files unchanged. Currenttoken nonadmin; NEXT USERADMIN new wrapper Install→onlysuccess manual reboot→Run2–4min plus trace save/decode→wait cleanup/Restore and send full trace root even error. No old refreeze/Resume. New audit tcp-wfp-full-start-review-20261007-135055;new verification/HANDOFF.md andhandoff.json;details docs/TCP_WFP_FULL_METADATA_DIAGNOSTIC.md. Exact original cause remains pending; no maintained product fix/capacity/performance claim. Source checkpoint/push authorized; captured/private/ignored artifacts excluded.


## 2026-10-07: XML fragment parsing fixed, saved baseline confirmed

USER150744/fullTrace150743 reached4native baseline connections with2MiB verified data/nativefail0/kernel4; load never started because netsh XML contains adjacent wfpstate+firewallState and single-root ET.parse refused. Only ownership parser changed: validates declaration, full fragment document/known roots, rejects malformed/trailing/DTD; callout IDs only from wfpstate. Saved baseline now COVERAGE_CONFIRMED in actual frozen Python:4owned Apply/classify/AFDaccept/TCP/data; identity between private objects/free still unproved. Actual saved ETL1960selected/loss0/10MHz,4XMLpositive10corrupt rejects13saved guards;223USER files unchanged,originalfailed receipts retained. Saved cleanup/Restore verified,currentglobalfalse.

Fresh151313-480f38a3 PS5Prepare/PS5PS7Inspect FILES_VALIDATED55runtime13outer exact. Product/sys/Core/CLI and140copiedsource unchanged, no build/sign/install/runtime. Currenttoken nonadmin; NEXT USERADMIN new151313 Install→onlysuccessmanualreboot→Run2–4min plus save/decode→waitcleanup/Restore/send trace evenerror. No oldrefreezeResume. Audit tcp-wfp-full-coverage-review-20261007-150744/newverificationHANDOFF;source checkpoint/push authorized,secrets/ignored capturekits excluded. Exact original cause remains pending.
