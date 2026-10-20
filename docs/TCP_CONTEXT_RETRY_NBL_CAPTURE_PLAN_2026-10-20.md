# Следующая проба: состояние контекста выбранного повторного SYN

## Готов отдельный вариант NBL64

USER разрешил cap64 плюс bounded reject diagnostics. Новый helper
`scripts/debugger/pb_nbl_context64.js`, SHA
`90c64083137e2609d3788721544e950884fd8c6e801410bce37ddd3976924173`.
Старый helper/profile/captures остаются неизменными. Registered actions2/3
побайтово совпадают с прежними; длинную регистрацию повторять не нужно.
Новый profile `pb-kd-selected-nbl64-context-profile-20261020.json` SHA
`fdfebfccb1f24d0a7e79e2618010b1e1ca7628c33e7b44dda5c02db1ba4374c5`.
Cap16 CREATE +64 source +64 NBL=144; ни global ACCEPT, ни нагрузки сверх
прежних200 fillers +1 control нет. Max4 REJECT samples и одна SUMMARY,
шесть mutually exclusive reject counters, тот же строгий receive selector.
POLICY read_limit40/sample4/version2: значения в hex, 40 означает64.

27 helper CDB cases и7 integrated CDB cases passed. Проверены поздний match21,
match64 и cap64, bounded output и все6 причин reject. 142 target и12 report
unittest passed. Combined proof inventory175 файлов. Модель не является
kernel coverage. Новый reporter требует POLICY/SUMMARY и непротиворечивые
counts/sample order, иначе INCOMPLETE; rootcause остаётся false.

Fresh plan `pb-target-accept-plan-20261020-181920-818a5a39/runtime-plan.json`,
SHA `2F12EB52658BDB17E009EA44A2255C55F2FB23559A59B06D0E85C56F4DCFDE22`,
PREPARED_NOT_RUN/exit0/productfalse/trafficfalse, boot118. Build19-r2 reused.
Host helper64 initialization пока pending. Source calibration131915 того же
boot переоценена, старые подготовки не refreeze/Resume.
Опубликованный helper скачан и проверен по SHA; pinned source commit
`bb02028215ba3a81d99fa4c9cac05e849e004cac`. USER получает команды PowerShell
download+hash, затем WinDbg oldStop/unloadOld/loadNew/init/reset/g. До вывода
CONFIG model0/POLICY40/true Run не запускать. Host actions USER-only; warning
wholeVM/Codex/RDP перед Break/enable. После PREFILL_READY только be2/g и C
в VM. Никакой диагностический Run агентом не выполнялся.

## Результат Run180714

На выбранном retry NBL при SENDskip получено info_raw=1, masked info=0,
root=0, key5=absent. Source EP+0x1c0 в той же SEND-точке сохранял исходный
record. Следовательно наблюдается отсутствие перенесённого контекста у
этого NBL, а не доказанное освобождение record.

После замены адресной watch зарегистрировано16 обращений, ни одно не прошло
полный RECEIVE selector; READ_LIMIT завершил наблюдение. Значение false из
JS callback не является NTSTATUS или сетевой ошибкой. Причины отклонения
сейчас не логируются. Отсутствие RECEIVE не доказывает отсутствие приёма.
Native исходный query201 вернул10022/0bytes; cleanup[] и ETWloss0.
Полный NBL вердикт остаётся INCOMPLETE. Private review:
`pb-selected-nbl-review-20261020-180714/review.json`.

Рекомендация для отдельной следующей подготовки: cap64 только выбранного
NBL и ограниченная сводка причин reject. Не добавлять глобальную ACCEPT-точку
и не увеличивать нагрузку. Новый вариант helper/proof/profile/plan пока
не подготовлен; Run180714 и его замороженные файлы не повторять/не менять.

Статус: выбранные live-смещения NETIO/fwpkclnt подтверждены пользователем.
Загрузка helper и `pbNblInitKernel()` прошли на физическом хосте: model=0/true.
Отключённый профиль подготовлен и проверен в CDB; USER подтвердил новую
регистрацию через .bpcmds. Новый runtime plan и reporter подготовлены.
Следующий шаг — один USER Run; агент нагрузку не запускал.

## Что установлено по коду

В `WfpTlShimInspectFastLoopbackSendDatagram` проверка bit21 при установленном
бите ведёт сразу в эпилог (`+0x14f`). Внутри этого helper обходятся обе
ассоциации key5/key4 и вызов `AleAcceptRedirectProxyNblTag` с key9.
Это не исключает другие функции, работающие с пакетом после возврата.

В `WfpAleAuthorizeAccept` путь key5 имеет отдельные условия: bit24 в поле
принимающего endpoint+0x30 и успешный предшествующий результат ESI.
При выполнении условий `FwpsNetBufferListRetrieveContext0` вызывается с
consume=1. Только при status0 результат сохраняется в принимающий EP+0x1c0.
Непосредственный вызов этой функции из отладчика непригоден: он способен
изменить исследуемое состояние.

`NETIO!WfpNblInfoGet` читает NBL+0xe0 и маскирует два младших бита указателя.
Импорт fwpkclnt RVA0x4f148 разрешён через PE import table именно в эту функцию.
Helper fwpkclnt RVA0x3760 после проверки null/MmBadPointer читает info+0x10.
Для key5 код Retrieve не использует фиксированные fast slots: выбирается
список, рассматриваются key в node+0x10, value в node+8 и inactive в node+0xb8.
Связи списка проходят через node+0x80. Незавершённый или нечитаемый обход не
позволяет объявить отсутствие key5.

Проверенные файлы:

| Файл | SHA256 |
| --- | --- |
| NETIO.SYS | a1b7596663a9da6ed39ea2241bbcdf810bbd6b48606dbe4158cf55bb332518ab |
| fwpkclnt.sys | fae91d16768b1e0827eeaae71287ef12ef65dfcfd8e9209b4daf7b6a81001066 |

Это хеши файлов на диске, а не всего загруженного образа. Присланные USER
инструкции подтверждают выбранные смещения. Импортный вызов преобразован
в mov r10/direct call той же длины; происхождение преобразования независимо
не установлено. Полного побайтового совпадения образов не заявляем.
Дизассемблирование, выбранные байты и расчёт кадров сохранены в private
`artifacts/diagnostics/pb-retry-receive-offline-review-20261020/`.

## Предлагаемое наблюдение

1. В существующем SEND-срабатывании с установленным bit21 прочитать состояние
   key5 выбранного NBL. Новый глобальный breakpoint для этого не нужен.
2. Рассмотреть замену существующей адресной watch3 на чтение NBL+0xe0 именно
   этого NBL. При попадании в `NETIO!WfpNblInfoGet` отличать запрос из
   RetrieveContext/AuthorizeAccept от прочих обращений по проверенным кадрам.
3. При совпадении прочитать состояние до штатного consume и сопоставить его
   с SEND-снимком, record и TCP-заголовком. Сохранить исходный native query.

Для прямого вызова WfpNblInfoGet из Retrieve: глубина кадра NETIO=0x38,
возврат NETIO находится по rsp+0x38; глубина Retrieve=0x68, его caller return
по текущему rsp+0xa8. Сохранённые RBP/RDI вызывающего Accept ожидаются по
rsp+0x98/rsp+0xb8. Они проверены на реальных CPU-кадрах модели CDB, но ещё
не проверены новым kernel runtime-захватом.

Ограничения будущего профиля необходимо проверить отдельно: ограниченный
обход списка, ограниченные адресные чтения, снятие после нужного события,
guard для текущего TCP tuple/sequence и завершение без полного вердикта при
лимите, смене identity или нечитаемой памяти. Никаких вызовов функций ядра,
записей в память продукта или общей ACCEPT-точки.

## Как читать результат

- Нет key5 уже в SEND-снимке: записи нет в выбранном пакете в этой точке;
  возможные последующие пути переноса всё ещё требуют наблюдения.
- На SEND key5 есть, перед штатным извлечением его нет: изменение произошло
  между двумя наблюдениями, включая возможный clone/consume path.
- Перед извлечением key5 есть: нужно проверить состояние записи и результат
  штатного извлечения, а не предполагать потерю на передаче.
- Совпавшего receive-события нет: захват неполный. Это не доказательство,
  что пакет не принимался; NBL может заменяться или клонироваться.

## Подготовленный helper и проверка

`scripts/debugger/pb_nbl_context.js` SHA256:
`A596999C104CBB049DFA73FA7602DD047A30BD5B0248A05E23C5AD5A46576236`.
Загрузка скрипта и `pbNblInitKernel()` не меняют точки. Инициализация проверяет
pins NETIO/Retrieve/Accept и 64-битную арифметику. Runtime допустим только с
`model=0`; отдельный model=1 предназначен исключительно для fixture.

Будущий `pbNblArm` вызывается из выбранного SENDskip: снимает прежнюю source
watch3 и заменяет её адресной r8 на NBL+e0. Max16 чтений выбранного поля,
max8 узлов списка; никакой общей ACCEPT-точки. Подходящий вызов определяется
по RIP, key5/consume1, двум return addresses, сохранённым RBP/RDI и tuple.
Сверяются NB/MDL/header/sequence/SYN, допускается продвижение NB data offset.
На ошибке/лимите наблюдение завершается как INCOMPLETE; после receive watch
снимается. `pbNblStop()` допускает уже выполненное внешнее снятие точки.
Ядерные функции не вызываются; записей в память продукта нет.

`src/pb_nbl_context_fixture.py` проверяет это в отдельном процессе с реальными
CDB/JsProvider, CPU-кадрами, адресной watch и заменой watch из её callback.
Итог private `pb-nbl-js-proof-20261020-r7/proof-suite.json`: 21/21 passed.
Покрыты наличие/отсутствие/смена key5, high pointers, inactive, неверная info,
пустой root, ring8/cycle/ring9, config missing, внешний clear, нечитаемость,
лимит, другой caller, изменившийся packet и неверный tuple. Это не kernel
coverage, не продуктовый тест и не доказательство причины сбоя.

USER загрузил helper и получил CONFIG model=0/true, затем выполнил g.
Это проверяет совместимость JS и code pins в текущей сессии, но не kernel
срабатывание новой watch. Kernel стоимость и полнота пока не измерены.

## Профиль регистрации

Генератор `src/pb_selected_nbl_profile.py` создаёт новый профиль и stage,
не меняя старые frozen kits. Profile SHA:
`88403355b93398e39a9068305c720e90ad84dc9f54c67f918b49abbe731b3398`.
Stage `scripts/debugger/pb-kd-selected-nbl-context-update-20261020.wdbg` SHA:
`fabb7ee5b1f080be65ddd08cf201a7c7dc45d744e409cd62c0d79c63b039dd2c`.
Stage отключает 4, заменяет 2, оставляет 2 отключённой; динамическая 3 до Run
отсутствует. Новые actions используют прежний SEND observer, но на skip вместо
простого снятия вызывают `pbNblArm`. На невалидном заголовке arm не вызывается.
Служебный t19 предотвращает снятие новой watch, если передача пришлась точно
на source raw64. Общий предел 16 CREATE +64 source +16 NBL =96 срабатываний.

`src/pb_selected_nbl_fixture.py`: 7/7 passed, private proof
`pb-selected-nbl-integration-proof-20261020-r5/proof-suite.json`. Проверяется
настоящая регистрация bp2 и её callback, source watch и замена на NBL watch,
включая границу raw64, bad header, смену packet identity и NBL limit.
Замены $vvalid/thread/gate адреса ограничены user-mode fixture; kernel/traffic
coverage нет. Ранние r3/r4/debug с bp около текущей int3 не сработали;
финальная fixture вызывает отдельный CREATE stub. Helper не изменялся.

Следующий шаг USER: скопировать stage вне Desktop/frozen symbol kit, проверить
SHA, после wholeVM warning выполнить Break, `$$><` stage, `.bpcmds`, отдельный
`g` даже при ошибке. Точки не включать, старые планы не запускать. Затем нужны
новые plan bindings, проверка proof, reporter и свежий runtime plan.
При будущем recovery сначала `bd2`, `dx @$scriptContents.pbNblStop()`, затем
conditional t8/bc3, `bd4` и отдельный `g`. Инициализация перед новым Run
допускается только после снятия активной watch.

## Свежий план после регистрации

План `pb-target-accept-plan-20261020-180357-3ce75acb/runtime-plan.json`, SHA
`233A90C003903284CAFE2E49E2F5935C5E1C4A451815E20471EE1EBBB4A774E5`:
PREPARED_NOT_RUN, exit0, product_started=false, traffic_generated=false.
Новый вариант policy связан с profile/helper SHA, обеими CDB suites и boot118.
Существующий здоровый source control131915 проверен на том же boot; его
профиль не выдаётся за новый и не перезамораживается. Регистрация USER остаётся
attestation без независимого host-proof. Повторный bl не требуется.

Новый `pb_selected_nbl_report.evaluate(capture, console)` требует один CONFIG
model0, SENDskip с повторным SYN, два STATE одного NBL, RECEIVE key5/consume1,
DONE и полный native10022 join. Порядок/identity/лимиты/нечитаемость/cleanup
не позволяют повысить неполный захват до verdict. Статус полного наблюдения
`SELECTED_NBL_CONTEXT_AND_NATIVE_FAILURE_OBSERVED`; он не доказывает виновника
и не измеряет результат штатного Retrieve. Generic native reporter сохраняет
pending debugger verdict. 142 прежних +7 новых unittest passed.

USER предпочитает прямую вставку команд. Перед Run заранее инициализировать
helper и обнулить t1/t3/t8 при отключённых точках, затем g. При PREFILL_READY
нужны только Break/be2/отдельныйg и C в VM в пределах15sec. Recovery выше.
Перед Break/enable предупреждать о паузе всей VM/Codex/RDP. Не повторять Run.
