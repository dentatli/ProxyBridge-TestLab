# Причина отсутствия контекста: проверка кода после успешной пары accept

## Разбор после060837: gate блокирует две найденные ветки привязки

В receive-блоке+182..198 бит21 ставится при bit20; внутри этого блока нет
отдельной проверки TCPflags, поэтому наблюдённый RST может пройти тот же
механизм, что healthy ответ. Это не утверждение о всех ранних gates функции.
FastLoopbackSend при bit21 выходит с EAX=0 (EDI обнулён на входе), обходя
association. В рассмотренном caller RVA7d736 ноль ведёт к7d3a3, не к ошибке.

Проверен и второй статический callsite key5: RVA1bcc9c. На рассмотренном входе
его закрывает тот же bit21:211ad/211b0/211b4. При bit21clear и дополнительных
условиях211c3 ведёт в1bcb5e; TCP ветка1bcbb0 берёт sourceEP+1c0, затем
1bcc54..1bcc9c увеличивает refs и вызывает association(key5). Таким образом,
второй найденный путь не является безусловной компенсацией FastLoopback skip.
Не доказано, что иных путей propagation вообще нет. Имя parent-функции и
второй участок ещё требуют current live-code read; никаких точек не добавлено.

Совместное объяснение: paused listener/RST может оставить receive gate,
при retry этот gate подавляет association, затем accepted query не находит
контекст при сохранённых source references. Статические условия и разные
Run вместе поддерживают этот механизм; это ещё не единая packet causal chain
и не окончательная атрибуция ошибки Windows против контракта callout-драйвера.
Private review содержит выделенные инструкции и явные ограничения, без payload.

## Run060837: одновременное сравнение source и accepted NBL получено

Source-at-ACCEPT report SOURCE_RECORD_REFERENCED_ACCEPT_CONTEXT_MISSING/errors[].
Native uniquequery201/controlPID10964/API10022/bytes0, cleanup[]. CREATE record
7d5e54f0/context6d56bc30/size32 остаются в sourceEP7e092a50 в остановке ACCEPT;
flags1301641. AcceptedNBL75876c10 имеет info_raw1/info0/root0/key5absent;
retrievalc0000225/output0. FINAL1/0/1/error0, SEND3 не включалась.
Это прямое подтверждение сохранённых source references одновременно с missing
accepted context. Содержимое context/lifetime/allocation не проверялось;
packet propagation и виновник по-прежнему не доказаны. Предыдущий SKIPgate
bit21 обходит association; применять его как объяснение именно этого accepted
packet без дополнительной причинной связи нельзя. Не повторять прежний захват.

## Текущий наблюдатель: source reference в момент ACCEPT

Run053802 RAW counters1/200/14hex подтверждают512 общих попаданий SEND3
при двух выбранных снимках; прежний history-захват не повторять.
Новый source-accept профиль держит3 выключенной всегда. CREATE2 проверяет
исходную запись; ACCEPT4 читает sourceEP record/context/flags и состояние
accepted NBL в одной остановке. Действия2/4 изменены вручную, JS helper тот же.
Это отдельный вопрос о сохранении ссылки, а не замена packet-identity проверки.
Сохранённая ссылка не доказывает allocation lifetime; missing accepted tag не
доказывает виновность Windows или драйвера. Следующий результат может остаться
неполным. Caps2/4=32/512; общийSEND/динамическиеwatch/stackdump отсутствуют.
Четыре коротких CDB fixture прошли без продукта/сети/kernel; это логическая
проверка команд, не доказательство приемлемого влияния на реальную VM.
Freshplan055619 prepared, host disabled redefinition pending; см. handoff.

## Подготовлен retry-history v2 вместо одного SKIP

Новыйhelper/profile сохраняет до8selectedSKIPнаблюдений с одинаковымsourceEP,
record/context32иSYNsequence. На8м отключаетсятолько3; ACCEPT4продолжаетждать
впределахпрежнегоrawcap. ПриACCEPT вычисляются все совпавшиеNBLадреса, последний
match_hit иmatch_count. Повторные вызовы с тем жеNBL не считаются разными
физическимипакетами. Дажеaddressmatch не закрываетreuse/lifetimeоговорку.
При8снимках/accept9безсовпадения результат остаётсяinconclusive, неошибкадрайвера.

RegisterновогоhelperсодержитCREATEarming, hostвключаеттолько2. Sites/capsне
расширялись; динамическихhardwarewatch/stackdumpнет. 5реальныхCDBcases иparser
провереныбезпродукта/сети/kernelconnection. Пакетныеистории вмодели искусственные,
не фактическинаблюдавшийсяWindowsTCP. Новаяверсия ещё не загружена наhost и
не измерена вruntime. СтарыйRun/profile/helper сохраняются безизменений.

## Run051728: сравнение в одном соединении получено, NBL join остаётся открытым

CREATE record/context32 -> выбранный SKIPgate с теми же sourceEP/record/context
и key5absent -> ACCEPT statusc0000225/key5absent -> исходныйAPI10022/0bytes.
Native/TCPtuple correlation прошла, cleanup[], sourcecontextприSKIPнеNULL.
Однако SKIP NBL769cc7c0 и ACCEPT NBL7e90c7f0 различны: exactreport
RETRY_CHAIN_INCONCLUSIVE, а не полная packet causal chain.

ETWэтогожеcontrol содержит4SO_PAUSE_ACCEPT SYNdrops и4connectretries.
ПервыйвыбранныйSKIP мог быть более ранней попыткой, чем дошедшая доACCEPT;
возможное другое представление NBL тоже не исключено. Это объяснения-кандидаты,
не установленный фактклонирования/повреждения/потери. Большеобщихточекне нужно:
кандидат следующегоизменения — сохранитьнесколькоselectedSYN доACCEPT, сжёстким
небольшимлимитом, вместопервого. НовыйhelperпокаНЕреализован/НЕпроверен/НЕзапущен.

## После Run045723: изменено окно включения, helper и лимиты прежние

Сохранённые USER counters create0/skip200hex/accept15hex устанавливают, что
SKIP-point исчерпала512 попаданий ДОCREATE; accept имела21 попадание.
Новый create-armed профиль включает наhost только2. Приmatchingsource42201
её action включает3/4, затем вызывает прежний pbccreate. Между этими командами
ядро не исполняется; guardfailure прежнегоhelper снимаетвсё доgc.
Это прежняя согласованная схема arming-after-CREATE; инструкцияUSER приREADY
теперь be2/g/C, не be2/be3/be4. Дляперехода надоодинраз заменить action2,
не перезагружать JS и не вызывать старый pbcRegister поверхновойaction.

СтарыйhelperSHA/прочиедействия/caps не менялись. Новыйprofile4453ed56...,
3новыхrealCDBcases (cold600доCREATE,guardfailure,capпослеCREATE) passed;
no kernel/product/network. Targetэффект/вмешательство новойсхемы ещёнеизмерены.
Прежние healthy/failure evidence сохраняются; новый plan051301 не запускался.

## Обновление: candidate v1 реализован и проверен в изолированном CDB

USER показал current-boot CREATE+396, SEND+2d/+14f; адресаbase5d... совпадают
с actualsessionCONFIG. +14f действительно сохраняет нужные регистры, но является
ОБЩИМ выходом обеих веток. Поэтому средняя точка перенесена на +34 перед jb:
MASM требует bit21 изEAX иCF1 послеbt. Снимок означает выбранное условие обхода,
а не отдельную инструкционную трассу выполненного перехода.

Новые файлы: scripts/debugger/pb_retry_chain.js, src/pb_retry_chain_profile.py,
pb_retry_chain_fixture.py, pb_retry_chain_report.py, exactJSONprofile/stage.
IDs2/3/4 software, только USERhost включает все три; automaticenable=false,
нет hardwarewatch/новыхdynamicpoints. CREATE и выбранный SKIP снимают себя,
первый выбранный ACCEPT снимает все. Это три события, НЕ три trap на всюVM.
Rawcaps32/512/512 (1056total): background200/retries не вызываютJSsnapshots,
но расходуют счётчики и могут снова исчерпатьbudget. Старые caps/профили не менялись.
Новый cap512 для общихsend/accept выбран с запасом на200fillers; это не безлимит.
RAW_LIMIT теперь выставляет error1 и выключает все три.

Фактический CDB proof-r1: 5/5 passed — missing, background200, sourcechanged,
earlyhealthy, rawlimit; безkernelconnection/product/network. Parser техже5логов
и2подменыidentity/flags отклонены; model-header substitution отмечен только
вparserfixture, не выдаётся заkernelcapture. PSentryparseOK и4старыхsingleprobe
tests passed. Полные historical suites/сборки не запускались.

Native runner сохраняет200fillers +onecontrol, gate15sec иsameboothealthy040741.
Новыйprofilehelper не считается подтверждённым наhost доCONFIGmodel0/Registertrue.
Продукт/драйвер/старые frozenkits не изменены. Новаяполитика target-only;
она не расширяет доказательную область прежнего healthyobserver.

## Результат проверки

Последний Run042210 подтверждает отсутствие WFP info/key5 ДО Retrieve и
STATUS_NOT_FOUND после него, вместе с единственным исходным10022/0bytes.
Это исключает потерю записи внутри данного вызова поиска. Это не доказывает
удаление record, повреждение памяти или ответственность конкретного драйвера.

Рассмотрен сохранённый исходник сборки63be0eb:
`artifacts/product-builds/ProxyBridge-63be0ebf9bec92bfba95ef3d6729c375aa9af84e/Windows/driver/src/ProxyBridgeDrv.c`.
Его прежняя source/disk/live привязка описана в KERNEL_DRIVER_SOURCE_REVIEW_2026-10-18.md
и KERNEL_DRIVER_APPLY_INPUT_CANDIDATE_2026-10-18.md; это не новая полная сверка
загруженного в текущем boot бинарника.

## Что делает ProxyBridge

- ClassifyCore185..197 выделяет nonpaged context и сохраняет исходное назначение.
- 236..241 задаёт localRedirectHandle, targetPID, context и размер, затем вызывает
  FwpsApplyModifiedLayerData0 с flags0 для inline classify.
- 242 освобождает classify handle; context после Apply драйвер не освобождает.
  Это соответствует владению WFP, описанному Microsoft. Добавлять ExFree здесь
  как предполагаемое исправление нельзя.
- В рассмотренном пути драйвер не получает TCP SYN/NBL и не переносит context
  вручную на каждый повторный SYN. Размещение key5 на NBL наблюдается внутри
  tcpip!WfpTlShimInspectFastLoopbackSendDatagram.

Две ранее найденные проблемные ветки сохраняются: allocation failure допускает
redirect с ctxNULL/size0; direct-loopback return после AcquireWritable не вызывает
парный Apply. Они не являются новыми находками и не доказаны участниками Run042210.
Их исправление не заменяет установление причины наблюдаемой retry-ветки.

## Конкретная ветка TCP/IP

Сохранённый send-gate-disassembly.txt из review084117:

1. +2d читает sourceEP+30.
2. +30 проверяет bit21, +34 при единице прыгает на +14f.
3. Этот переход обходит чтение sourceEP+1c0 и вызов association с key5.

В прежних source/send наблюдениях record/context были ненулевыми/32bytes,
первый SYN имел bit21=0 и key5present, повторные SYN с тем же sequence —
bit21=1 и key5absent. В отдельном receive/write захвате084117 бит установлен
в RecvTcpDatagram при входящем RST|ACK34010->42201. Сам bit21 встречается и в
healthy receive: считать любое его установление ошибкой нельзя.

Вывод по совокупности: ведущий механизм — пропуск association для retry после
изменения состояния endpoint в TCP/IP. Этапы взяты из разных Run; единой
наблюдённой causal chain пока нет. Source lifetime/allocator failure текущей
ошибочной связи accept-пара сама не измеряла.

## Следующий захват: три события одного выбранного соединения

Повторять глобальную PRE/POST пару или поднимать её rawcap не требуется.
Кандидат — три ограниченные точки, без аппаратного read-watch, stack dump,
CurrentMdl identity и логирования каждого фонового пакета:

1. CREATE: фильтр source42201, record/context/size/EP; снимает себя после выбора.
2. SKIP: выход +14f у того же sourceEP, bit21=1; snapshot record на source,
   NBL и одного SYN header; снимает себя после первого выбранного события.
   До включения нужно проверить полный выход функции и сохранность регистров.
3. ACCEPT return: tuple34010/42201, NBL/status/output и bounded WFP info/key5
   snapshot; автоматически снимает оставшиеся owned точки.

Не выдавать три события за полную физическую lifetime NBL. Адрес NBL без
контроля lifetime не исключает повторное использование. Несовпадение NBL,
отсутствие события либо другой native result дают неполную цепочку, а не
подтверждение противоположной гипотезы. Пропуск SKIP при отсутствующем source
record требует пересмотра исходной гипотезы, а не автоматического роста caps.

На этом шаге подготовлен только дизайн. Нет нового helper/profile/frozenkit/
runtime plan, тестов, сборки или Run. Для безопасной регистрации нужны actual
current-boot disassembly CREATE+396, SEND+2d и SEND+14f. USER читает их на
physical host; перед Break предупреждать wholeVM/Codex/RDP, g отдельной строкой
даже после ошибки. Старые2/3 остаются disabled. Драйвер не перезапускать.

## Контракт Microsoft, проверен 2026-10-21

- [FWPS_CONNECT_REQUEST0: ownership localRedirectContext](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/fwpsk/ns-fwpsk-_fwps_connect_request0).
- [Inline connect redirection: driver/engine/proxy roles](https://learn.microsoft.com/en-us/windows-hardware/drivers/network/using-bind-or-connect-redirection).
- [Apply: void, flags0 inline, matching call required](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/fwpsk/nf-fwpsk-fwpsapplymodifiedlayerdata0).

Эти контракты не описывают private bit21 и сами по себе не доказывают Windows bug.
