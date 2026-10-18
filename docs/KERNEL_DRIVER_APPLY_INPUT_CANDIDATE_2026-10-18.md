# Одна точка: входные данные драйвера перед Apply

## Результат four: три корректных снимка при четырёх успешных соединениях

Run `pb-kd-session-run-20261018-171904-ce75c787`:4 native success,4 Core IPV4_CONTEXT_AVAILABLE/32bytes, errors[], manifest COMPLETED; после USER bd2/отдельногоg SCM read-only Stopped. USER console: после t0=0/be2/g три APPLY_INPUT с hit1..3, TOTAL3, без показанных UNREADABLE/IMAGE_MISMATCH. Все3 содержат ненулевой ctx,size20h=32,redirect1000e,image61000,targetPID3e2c=15916, совпадающий с Core. Частичная работа action и привязки после load наблюдается; полнота не доказана.

local0 dbdd0002/d9dd0002/dcdd0002 декодированы как AF_INET, порты56795/56793/56796; local address в этих8байтах нулевой. Порты сопоставлены с уникальными native/Core строками этого короткого run, remote0 задаёт127.0.0.1:34010. У четвёртого native/Core соединения порт56794 и успешный query32bytes, но снимка Apply нет. Эти события не содержат nativePID/QPC, поэтому совпадение port+relayPID в данном run не превращается в полную историю Windows record. Нулевого context на измеренных входах нет; это успешные соединения, не исходный failed lifetime.

Private review `pb-driver-apply-four-result-review-20261018/review.json`; источник console — chat paste, не независимо сохранённый raw файл. Counter3 подтверждает три выполненных actions, не число всех Apply calls. Причина отсутствия четвёртого снимка неизвестна; software breakpoint capture остаётся гипотезой, не установленной ошибкой WinDbg. Не переходить к bounded и не повторять использованный plan. Следующий офлайн шаг — проверить пригодность одной аппаратной execute точки `ba e1` на том же адресе, особенно загрузку/выгрузку драйвера; готового профиля/команд регистрации/Run ещё нет. [Microsoft описывает ba e1 и действие kernel breakpoint на всех процессорах](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/ba--break-on-access-); это не гарантия устранения пропусков в нашем захвате.

## Именованная отключённая точка подтверждена на хосте

Files-only Prepare завершён exit0: `pb-kd-session-plan-20261018-171328-b9b861da/runtime-plan.json`, SHA256 `6E501BF56B1B37B1CA151BEE6A7F8C8383EB290E4E473B23F11E714C0D64FAB3`. Общие ресурсы переиспользованы, продукт/трафик/WinDbg не запускались. Policy проверена: four/4, active+registered2, original single query/listener, 8s. Plan ещё не использован, runtime результата нет.

USER console: matching private PDB загружен из `C:\PB-KD-Symbols-20261016\ProxyBridgeDrv.pdb`; module base fffff8026c2c0000, ImageSize61000, timestamp6ABD1109/checksum143BA. `ClassifyCore` RVA12b8; `+3de` точно call FwpsApplyModifiedLayerData0, bytes e8d3110000, затем 488b4de8. Старую unqualified bu2 удалили; новая `bu2 ProxyBridgeDrv!ClassifyCore+0x3de` и `bd2` подтверждены `.bpcmds`, затем отдельный g. Предшествующие предупреждения WUDFRd/IndirectKmd относятся к старому выражению до bc2, не к новой точке. Agent read-only SCM подтвердил Stopped после USER unload.

Private registration review: `pb-driver-apply-symbol-registration-review-20261018`. Источник — USER chat paste, не raw console с независимым SHA; review разрешает только four с новым точным profile SHA и текущим boot. Работа action, чтение request, ненулевой client port/корреляция, автоматическая привязка при следующей загрузке и полнота событий ещё не проверены. Продукт и предыдущие профили не менялись; агент Run/WinDbg не выполняет. Следующая проба — четыре соединения только с2; после неё отключить2 и отдельно g даже при ошибке, разобрать console до любой нагрузки.

## Перенос PDB подтверждён, загрузка символов ещё не проверена

USER вывел `PDB_SHA_OK` после guarded copy на физическом хосте. Это подтверждает сравнение SHA подготовленного файла и destination `C:\PB-KD-Symbols-20261016\ProxyBridgeDrv.pdb`, но не его загрузку WinDbg. Private observation сохранён в `pb-driver-symbol-binding-review-20261018/host-copy-observation.json`.

Следующий шаг объединяет один USER ADMIN load/read/unload с проверкой matching PDB и заменой отключённой unqualified bu2 на `ProxyBridgeDrv!ClassifyCore+0x3de`. Сначала `.reload /f ProxyBridgeDrv.sys`, `lmvm`, `x` и `u` должны подтвердить символ и call RVA1696. При ошибке остановить регистрацию, отдельно g и выгрузить драйвер. При совпадении bc2, qualified bu2, немедленно bd2, .bpcmds и отдельно g; затем USER Stop-Service/WaitStopped. Предупредить перед Break и созданием bu об остановке всей VM/Codex/RDP; recovery bd2 и отдельный g. Нагрузки, be и нового runtime plan пока нет. Краткий load/read/unload уже согласован; агент сам драйвер не загружает. Предыдущие профили и комплекты сохранены.

## Текущий стоп: предупреждение unqualified, подготовлен matching PDB и target v2

USER bu2 module+1696 был создан и .bpcmds показал именноbu2/bd2; TOTAL0 иотдельныйg подтверждены. Но WinDbg предупредил contains symbols not qualified with module name. Это не успешная проверка автоматической привязки. Не включать/неRun и не игнорировать предупреждение только потому, что запись появилась. Выражениебезmodule!symbolбылонедостаточнонадёжнымвыбором; теперьперейтикквалифицированномусимволу, неугадыватьдругойabsolute/moduleoffset.

Matching PDB найден в сохранённой исходной сборке:610304bytes, SHA256 `8196d1d70ff10317bb460390f125f3906a1cfb8ad1a90130122ebd03e039d1d6`, GUID9edddca7-4d9e-4bad-be1d-2bfc2d491344, DBIage1. GUID/age совпали сRSDS diskSYS3cd. MSF-проверка сначала отклонила ошибочно заданную длинуprefix24; исправлено startswith, исходныйPDBне менялся. Privateaudit `pb-driver-symbol-binding-review-20261018` сохраняетreview/qualified-symbol/transfer-and-profile.

Локальный DbgHelp в отдельномPythonпроцессе, толькоfile-symbol-read: SymFromName(ProxyBridgeDrv!ClassifyCore) далRVA12b8; +3de=1696. Драйвер не загружался, DriverEntry/WinDbg не исполнялись. Это доказательство соответствия symbolRVA/PDB/disk, не проверки загрузки PDB на физическомхосте. COFFsymbolcountSYS0; наличиесимволоввdumpbinобъясняетсядоступностьюmatchingPDBвVM, анеэкспортомClassifyCoreизSYS.

ДляпереносаподготовлентолькоPDB+manifest: `artifacts/diagnostics/pb-driver-symbols-20261018/ProxyBridgeDrv.pdb`. Копияпобайтносовпала. Никакихновыхruntime/продуктовыхбинарников/архиваинструкцийнаDesktop. Новый JSON `pb-kd-driver-apply-input-symbol-candidate-20261018.json`, SHA256 `c8ff03a683cbc1e267dad6dc00a6c7443b44cb596b206fa1d8fff6873752bf10`, target `ProxyBridgeDrv!ClassifyCore+0x3de`. Actionровнопрежняя; старыйunqualifiedprofileсохранён. ХостоваязагрузкаPDB/регистрацияv2/егоreloadbindingпокаpending, плана/Runнет.

Следующий USER шаг — перенести подготовленныйPDBизVMнаphysicalhostвD:/Загрузки/ProxyBridgeDrv.pdb икомандойсавтосравнениемSHAдобавитьвсуществующуюC:/PB-KD-Symbols-20261016/ProxyBridgeDrv.pdb. СуществующийdestinationсдругимSHAнеперезаписывать; приодинаковомSHAпереиспользовать. Проверитьпослекопирования, вывестиPDB_SHA_OK. Пока никакихBreak/be/driverload/Run. Послеhostcopy — отдельныйсогласованныйload/read/qualifiedsymbolreviewиdisabledregistration; разрешениеload/read/unloadUSERужеесть, ноагентнеповышен иStartServiceнеповторять. Неоставлятьunqualifiedbuактивной. СтарыеNT/TCPIP/FWPKPDBне менять, unsafeignore-symbol-mismatchflagsне применять.

## Свежий live-код и очистка подтверждены

USER выполнил административный load/read/unload: показаны Running, Stopped и отдельныйg. Дополнительный read-only Get-Service подтвердил Stopped. Live module base fffff8026c130000/end fffff8026c191000, ImageSize61000, timestamp6ABD1109/checksum143BA совпали с текущим diskSYS SHA3cd79cfc... . Двадцать четыре инструкции начиная сRVA1650 и одна инструкция thunk286e побайтно совпали с файлом. WinDbg показал Unable to load image/Win32error2, но вывел эти25инструкций из target memory; предупреждение не превращается в утверждение о неработающем драйвере. При MASM L18 означает24инструкции, не18десятичных.

Private `pb-driver-image-live-review-20261018/review.json` сохраняет параметры сверки; источник — USERchatpaste, не отдельный rawconsoleSHA. Это выборочная сверка кода иPEметаданных, не SHA всего загруженного образа. Старые unloadedranges66000 против новогоSizeOfImage61000 остаются необъяснёнными; предыдущие capture-файлы loaded-drivers-active хранят имена, не base/size/timestamp/code. Не объявлять причину разницы или автоматически привязывать старые failed lifetimes к этому source. Факт старых native↔Core10022 от этого не исчезает.

## Кандидат профиля

`scripts/debugger/pb-kd-driver-apply-input-candidate-20261018.json`, SHA256 `708701ce738701a41bd9846693c60ac2fd8802873464c385ba15adbd2cac8955`.

Только зарегистрированная/активная2; старые2/3заменяются. Target `ProxyBridgeDrv+1696` перед вызовом FwpsApplyModifiedLayerData0. RCX=classifyhandle/RDX=request/R8d0 проверены кодом. Action увеличиваетt0, проверяет доступность request138bytes и поля SizeOfImage заголовка module+138, допускает обычный снимок только приSizeOfImage61000. Затем одной строкой пишет hit/thread/request, первые8байт local/remote SOCKADDR, targetPID, redirecthandle, ctx/size иimage_size. Нет чтений context payload, stack илиETHREAD.Cid. Никаких предположений о private fields Windows record.

local0/remote0 — сырые байты, дляIPv4 содержатfamily/port/address. Поддержка полногоIPv6tuple не заявляется. request.targetPID — PIDrelay, неnativeclient. Ненулевой local port и сопоставление с native/Core ещё не проверены. Если raw содержитfamily, который не поддерживает наш разбор, или IMAGE_MISMATCH/UNREADABLE, coverage неполон. Счётчик считает выполненныеactions, а не всеkernelcalls.

В отличие отPRE/POST, каждый снимок самодостаточен: не надо связывать две команды на разных точках. Но он подтверждает лишь данные перед входом вApply; результатApply, создание/доставкуWindowsrecord, Corequery иполнуюисториюнепокрывает. УказательctxNULL/size0 нельзя автоматически приравнивать кQUERY_NULL Windowsrecord. Отсутствиеeventнеявляетсядоказательствомотсутствиявызова.

## Загрузка и отложенная привязка

Текущий драйвер опять выгружен; абсолютный адрес прошлогоloadне использовать. Регистрациякандидата — bu2 сmodule+RVA, сразуbd2. [Microsoft bu](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/bp--bu--bm--set-breakpoint-) поддерживает отложенную привязку иповторныезагрузкимодуля. Но именно выражение module+RVA/разрешениевэтомWinDbgиавтопривязкавнашемпервомfour остаютсяruntimepending. Не утверждатьуспехпоканеполученconsole. Еслиbuошибается, неугадыватьabsoluteaddress иневключатьничего.

Офлайнпроверены guards/ranges, escape roundtrip,3форматаprintfиаргументы, delimiter balance/finalgc иpolicyfour общегозапускателя. Privateaudit `pb-driver-apply-input-candidate-review-20261018`. Старыеprofiles/source/kitsнеизменены; новогоplan/Runнет. Передновымfour понадобятся новыйregistrationreview/profileSHA/bootbinding иобщиймаленькийplan, безкопированияruntime.

Следующий USER шаг толькоdisabled registration: beforeBreak wholeVM/Codex/RDPwarning/recoverybd2/отдельныйg. Известные2/3d, исходныйblнеповторять. bc2/bc3поодной; beforebu2warninitiallyenabled/VMstopped, bu2/bd2поодной, r@$t0=0, .bpcmdsдляпроверкиименноbuиdisabled, отдельныйprintfPBDITOTALожидается0, отдельноg evenerror. Успешнаяотложеннаяточкаможетпоказыватьсяunresolved — этоожидаетсяпривыгруженноммодуле, неvalidationruntimebinding. Неbe/неStart-Service/неRunнаэтомшаге. Продуктнеизменён,10061внеразбора.
