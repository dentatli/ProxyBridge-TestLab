# Dejavu Gates и обязательная проверка retrieve stage — 2026-10-17

По запросу USER подключён [WhiteBite/dejavu-gates](https://github.com/WhiteBite/dejavu-gates), версия2.59.0, commit5b17094c76876b45b78ce6a891749e533c7789ac. Это CLI/hook engine, не MCP. Исходники находятся внеTestLab в пользовательскомкаталогеCodex; установлены companion skilldejavu и проектныеPreToolUse/PostToolUse hooks. ГлобальныйPATH/продукт/драйвер/BCD/гипервизор/питание/debugger не менялись.

## Что фактически проверено

Bun1.4.3 установлен переносимо в пользовательскомкаталогеCodex, официальныйGitHub release bun-windows-x64-baseline.zip проверен поassetSHA256 d7a7d3eb216614544aab0cde2d8d9f2e4e87839bf5a30a1cd11d077f02d84e0c. Runtime dependencies черезnpm/buninstall не устанавливались: CLI использует исходники и встроенные модули.

Штатный installer сначала выполнен dryrun, затем `install --harness codex --project`; создан `.codex/hooks.json` с абсолютнымипутями Bun иcli.ts. `hooks --check` сообщилok и предупреждение оBun вминимальномGUI PATH. Послеэтого фактическаясконфигурированнаяpre-hookкоманда проверена черезcmd.exe сPATHтолькоSystem32: exit0,stdout{},stderrпустой. Такимобразом выбраннаяabsoluteкомандаработаетбезглобальногоPATH. Это не доказываетавтоматическийперехватвсехвызововвужезапущенномdesktopчате. Активация/доверие/hotreload hooks зависитотхоста; не выдаватьручнойprobeзадоказательствоактивациивчате.

Companion skill установленштатнымskill-installer изskills/dejavu того жеcommit в `C:\Users\LabAdmin\.codex\skills\dejavu`. Инструкции прочитаны и применены; автоматическоеобнаружениеустановленногоskill доступнососледующегохода. Его протокол запрещаетручное созданиеgates и повторidenticalcallпослеREMINDER; correctionзаписываетсячерезlesson --authoragentнасуществующийgate. НеобходитьBLOCK/REPEATSTOP безсоответствующегоявногооснования.

## Реальная запись об ошибке

Старыйошибочныйstage одинраз проверенновымofflinevalidator; он действительно отклонён exit2 cCOMMENTS_FORBIDDEN/CRLF/command-contract errors. Выводэтойреальнойпроверкипередан штатномуCodexpost-handlerвручную, каксобытиетекущейоднойсессии. Первыйcallbackиспользовал полеoutput вместоstdout, из-заэтогоfailure не появилсявstore; послеизученияadapterpayloadисправлен и тотжереальныйрезультатзаписанодинраз. WinDbg неисполнялся, pastWinDbgсессии не подделывались.

В `.opencode/dejavu/gates.json` появилсямеханическийpattern9596245713aa, count1/sessions1/statuswatching. Через `lesson --store <root> --author agent set <key> <correction>` сохраненоисправление:

> Use the r2 retrieve stage with exactly bp2, bd2, bl, .bpcmds as four ASCII CRLF lines; put comments in README and run pb_validate_retrieve_stage.py before packaging.

Никакогоручногоповышениявblocking/reminding, искусственныхсессийилиповторныхфиктивныхошибок. Вwatching автоматическойблокировкиещёнет; нельзя заявлять, чтосамDejavuуже блокируетэтотклассошибок. `report` завершилсяOK/no pathologies; discoverabilityвAGENTSноситинформационныйхарактер. Gate/correctionсохраненылокально, приватныемашинныеhooks/store исключеныизGitчерез.git/info/exclude.

## Проверка, которая предотвращает выдачу такого stage уже сейчас

Новый `src/pb_validate_retrieve_stage.py` проверяет узкийretrieve/queryконтракт, анепроизвольныйWinDbgязык:

- ASCIIбезBOM/NUL, ровночетыреCRLFстроки сзаключительнымCRLF.
- Никакихcomments/инструкцийдляпользователявисполняемомфайле.
- Только точныйbp2+0xcafизprofile, затемbd2,bl,.bpcmds; никакихвнешнихbe/bc/g/step.
- СоответствиеSHAstage/profile, окончаниеactiongc иguardbeforeoutputread.

Сопоставлениеactionсprofile и этиchecks неравныWinDbgparserexecution/безопасностивсехчтений/flowcoverage. Новыйruntime всёещёнужно проверитьнакороткойпробе.

Опция`--archive`выполняетпроверкуДОсозданияновогоZIP, требуетотдельныйREADME, запрещаетoverwrite и послеупаковки проверяетCRC/byteidentity. Все следующиеretrieveпакеты выдаватьтолькочерезэтотпуть; не обходитьпрямымZipFile/Compress-Archive. Пример(путиoutput должныбытьновыми):

```powershell
& $pbPython -B src/pb_validate_retrieve_stage.py --stage scripts/debugger/pb-kd-retrieve-query-add-disabled-20261017-r2.wdbg --profile scripts/debugger/pb-kd-retrieve-query-candidate-20261017-r2.json --archive '<fresh-output.zip>' --readme '<instructions.txt>'
```

Фактическаяпроверка: старыйstageотклонён, ZIPнесоздан; r2прошёл,новыйприватныйverificationZIPсозданипроверен. Уже выданныйDesktopr2ZIP иегоSHA4c05d7d875c14c406b85c79e1ffa64ff2787edac19df42bea94bc136a83258c3 осталисьнеизменными. Историческиекомплекты/profile/capturesнепереписаны.

Privateaudit `artifacts/diagnostics/pb-dejavu-setup-20261017/` хранитinstallpreview/result,hookcheck/minimalenvprobe,реальныйfailurepayload,packagingpositive/negative,validation/report. ВGitнетthirdpartyclone/Bun/машинногоhooks/store/audit.

## Диагностический стоп остаётся прежним

Новый r2 stage ещёнепровереннаhost. Последнийподтверждённыйinventoryтолько3/4d иотдельныйg. ТолькоUSERdisabledregistrationr2послепредупрежденияwholeVM/Codex/RDP, затемconsole review, freshfourkit икороткаяпроба. НиbeниRunнаоснованииустановкиDejavu. ИсправлениеTCP/драйвера/Windows/tableoverflowпоканедоказано.
