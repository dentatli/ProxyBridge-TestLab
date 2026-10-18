# Одна точка: входные данные драйвера перед Apply

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
