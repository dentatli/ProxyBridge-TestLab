# Статически обоснован отбор accept по порту, live проверка ещё нужна

Следующий вопрос после [восьми исходных отказов](KERNEL_QUERY_BOUNDED_RESULT_2026-10-17.md) — состояние redirect record у того же принятого endpoint до исходного запроса Core. USER просит минимум точек/тормозов. Выбран кандидат с двумя активными точками: новый ACCEPT_STATE на общем accept join и прежний QUERY_READ; QUERY_STATUS остаётся отключённой. Это не полный lifecycle capture и не новый Run.

## USER live inspection проверен — 2026-10-17

USER показал только прежние3/4d с точными адресами/actions, slot2 отсутствует, MASM, пролог WfpAleAuthorizeAccept и восемь инструкций от+caf, затем отдельныйg. Из56 показанных инструкций55 exactdisk; сохранения портов `[rbp-7c]`/`[rbp-7a]`, frame setup и return/store/join совпадают. НаRVA14a8d отличается rel32 цели call: diskmemsetRVA1b78c0, live_memset_spec_ermsbRVA1b7b00. Оба символа проверены matchingPDB; источник переписывания вызова не установлен, loader rewrite не объявлять доказанным. Это отличие не инструкция сохранения/чтения наших port slots. Полной byteidentity функции/образа не утверждать.

Private `live-review.json` и selected instruction transcriptionSHA `f2da21a235837a518e836098e7956b5d7054a2e365ce42ce06f7e2cbb9d984d7` сохраняют границы: пользовательский chat, не независимыйhostlog. Точка2 ещё не регистрировалась, реальные port values/action/gc/flowbinding не проверены. Текущий шаг — hostcopy ниже, без новых Break/загрузки/enable/Run до результата переноса.

## Что удалось установить офлайн

В executable sections текущего tcpip.sys найден один прямой E8-вызов WfpAleAuthorizeAccept, RVA135c4. По matching PDB он относится к TcpInspectListenerReceive. Скан не исключает косвенных вызовов/других модулей. Caller и entry разобраны ограниченными disassembly ranges, а не выполнением кода.

Caller обращается к двум начальным 16-битным полям TCP-заголовка и к data-offset byte0c. Порядок Source Port / Destination Port соответствует локальному WDK `TCP_HDR` в netiodef.h и [RFC9293, формат заголовка](https://www.rfc-editor.org/rfc/rfc9293.html#section-3.1). Dataflow по проверенным инструкциям:

| Значение | Caller | WfpAleAuthorizeAccept |
| --- | --- | --- |
| TCP destination port, raw network bytes | `[rdi+2]` → `[rsp+7a]` → R8W | R8W → `[rbp-7c]` |
| TCP source port, raw network bytes | `[rdi]` → `[rsp+78]` → шестой аргумент | `[rbp+158]` → `[rbp-7a]` |

Ожидаемый destination для перенаправленного listener Core —34010. Его network bytes84da, а little-endian word read даёт0xda84. Преобразования порядка байтов на показанной цепочке нет. Слот source port позволяет добавить порт клиента независимо от record и затем сопоставить его с peer_port в Core/native metadata. Это ещё не полный TCP tuple/общая QPC шкала и не доказанная runtime привязка.

Frame:8 pushes, `rbp=rsp-e8`, allocation248h; при выбранном join `[rbp-7c]` соответствует текущему `rsp+e4`, `[rbp-7a]` — `rsp+e6`. Они находятся внутри fixed frame. Сохранение исходного R8W в локальном слоте видно в коде; r13 на отдельных ветвях переиспользуется под diagnostic string и **не используется как фильтр**.

881 инструкция сохранённого accept disassembly и250 caller/entry instructions заново побайтно сопоставлены с текущим PE; SHA tcpip.sys `b0683bd7ed0f309e63b4e6e71675d8f04cfb0ea5533c3f5e8a13c6daca3b595a` совпал с прежней metadata. Это доказательство дисковых байтов/dataflow, не подтверждение живого frame, реального значения порта у наших flows или покрытия failed paths.

## Подготовленный stage-кандидат

- `scripts/debugger/pb-kd-accept-query-add-disabled-20261017.wdbg` добавляет **только bp2** на WfpAleAuthorizeAccept+cbe, сразу bd2, затем bl/.bpcmds. Новая bp первоначально enabled: при будущей USER регистрации VM должна оставаться остановленной до bd2. Никаких be/внешнегоg/трафика.
- `scripts/debugger/pb-kd-accept-query-candidate-20261017.json` описывает precondition: только существующие точные3/4d, слот2 отсутствует. Кандидат registered IDs2/3/4, active2/3, inactive4. Предусловия проверяет USER по inventory; сам stage не защищает от повторной загрузки/перезаписи bp2.
- Сначала проверяется `$vvalid(rbp-7c,4)`, только затем читаются оба port words. Вывод только при rawlocal0xda84. После отдельных guards читаются Cid, endpoint field1c0 и flags30. Record может быть NULL: это не условие отбрасывания. NBL только как указатель, без dereference; context/payload не читаются.
- Action сохраняет thread/PID/TID/scope/endpoint/NBL/record, local_raw/peer_raw, flags и rawesi. ExecutingPID не owner filter. Общий join не объявляется выполненным store/retrieval. gc снаружи всех веток; отсутствие ошибок/продолжение ещё должны проверяться на живой пробе, общая gc safety не доказана.
- Прежний QUERY_READ action не переписывается. QUERY_STATUS4 остаётся зарегистрированной и отключённой. В новом capture её NTSTATUS не измеряется независимо; результат API сохраняет Core.

Отбор уменьшает вывод посторонних accept, но общий software breakpoint всё равно может иметь издержки на отброшенных hits. Не обещать уменьшение тормозов по одному числу точек. Сначала новая четырёхсоединительная проба после регистрации/review; отсутствующий ACCEPT_STATE не доказывает отсутствие записи — это может означать непокрытый путь или проблему отбора.

## Файловая проверка и пакет

Private audit `artifacts/diagnostics/pb-kd-accept-filter-review-20261017/`: direct-call-candidates, bounded disassembly, dataflow/static-validation, stage generator и package-validation. Вложенное quoting декодировано обратно точно в action;11 specifiers/11 arguments, сохранённые query action/registration roundtrip exact. Stage ASCII/CRLF, комментарии без semicolon, единственные внешние команды bp2/bd2/bl/.bpcmds. Это синтаксические офлайн проверки, не действие WinDbg.

Все8294 старых frozen files и63 inputs предыдущего результата проверены неизменными. Raw user console дополнительно скопирован в private audit с прежним SHAf5233813…879cdf. Начальная private package-проверка прочитала Unicode path map с системной кодировкой и не нашла имя; исправлено чтение UTF-8, исходный файл существовал и полный SHA совпал. Продуктовые источники/установка/BCD/VM settings не менялись.

Desktop `PB-KD-Accept-Query-Candidate-20261017.zip`,3603bytes,SHA256 `F12E10AFE5ABA682A1412F0C6223662BAE37A332A06CAB618BE5C902C77F584B`. ZIPCRC и byte roundtrip всех4entries exact. StageSHA `0cae2e9f96ec148f0f44a54a61e7f93ff4477e322a8a0b3a32fc177be93e5d2c`, profileSHA `0eea0b0cf65c91c3e0008bf0e57bc15dfb848cd658a09491dec6cefa25e89e6a`. Это подготовленный кандидат; live selected code/inventory review теперь выполнен выше, **host copy/registration ещё не выполнены**, реальные port reads pending. Runtime kit для нового профиля ещё не создан; старые preparations не подходят.

## Завершённый USER шаг — read-only live inspection

Не загружать stage и не включать точки до проверки следующего console. Заранее сохранить команды на физическом хосте. **Break останавливает всю PB-BUILD-W11-25H2, включая Codex и RDP.** Recovery для нынешних известных3/4: bd3,bd4,bl, затем отдельныйg. Каждая команда отдельно, g даже после ошибки.

USER Break, если ещё нет kd>. По одной: `bl`, `.expr`, `u tcpip!WfpAleAuthorizeAccept L30`, `u tcpip!WfpAleAuthorizeAccept+0xcaf L8`, затем обязательно **отдельный `g`**. Ожидаем только известные3/4d/слот2нет/MASM и matching frame/retrieve/store/join bytes. Если inventory другой — никаких загрузок/enable; прислать полный console. Это не Run и не регистрация.

После live review — автоматический SHA compare перед переносом/распаковкой нового ZIP на host, отдельная USER disabled registration одной2, reviewbl/.bpcmds, затем fresh four-only kit с новым контрактом registration/active IDs и новое согласование конкретного USER Run. Не reload stage поверх существующих точек, не refreeze/Resume/reuse старые kits. Перед каждым будущим USER Break/register/enable предупредить о паузе всейVM/Codex/RDP, recovery после регистрации включает только нашу проверенную2 и3/4, все команды по одной/g отдельно. Причина исходного отсутствия record всё ещё не установлена.

## Ближайший USER шаг — host copy с автоматическим SHA compare

Скачать новый ZIP на физический ПК в `D:\Загрузки`. Весь блок в host PowerShell (не VM):

```powershell
& {
    $ErrorActionPreference = 'Stop'
    $pbZip = 'D:\Загрузки\PB-KD-Accept-Query-Candidate-20261017.zip'
    $pbDestination = 'C:\PB-KD-Accept-Query-Candidate-20261017'
    if ((Get-FileHash -LiteralPath $pbZip -Algorithm SHA256).Hash -ine 'F12E10AFE5ABA682A1412F0C6223662BAE37A332A06CAB618BE5C902C77F584B') {
        throw 'ARCHIVE_SHA_MISMATCH: распаковка не выполнялась'
    }
    if (Test-Path -LiteralPath $pbDestination) {
        throw 'DESTINATION_EXISTS: существующий каталог не изменялся'
    }
    Expand-Archive -LiteralPath $pbZip -DestinationPath $pbDestination
    'ARCHIVE_SHA_OK_AND_EXTRACTED'
}
```

Прислать результат. Без Break/stage/enable/Run на этом шаге. Существующий архив/каталог не перезаписывать и не удалять при ошибке. После подтверждения hostcopy будет отдельная регистрация одной2 в disabled state с предупреждением о паузе всейVM, не загрузка старого7/25 stage и не перерегистрация существующих3/4.
