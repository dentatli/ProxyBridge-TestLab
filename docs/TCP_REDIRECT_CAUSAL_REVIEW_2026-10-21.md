# Причина отсутствия контекста: проверка кода после успешной пары accept

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
