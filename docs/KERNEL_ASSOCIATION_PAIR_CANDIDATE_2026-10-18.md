# Две точки вокруг прикрепления redirect record

## Результат первой пробы: положительные события есть, полнота пар не подтверждена

Запуск `pb-kd-session-run-20261018-123050-188878dc` завершился: четыре native соединения передали по524288байт, четыре исходных Core query вернули api_return=0/api_error=0/bytes=32. Native порты60393..60396 независимо совпали с peer_port Core. Workload и cleanup имеют COMPLETED; CLI завершён graceful, forced_stop=false, post_stop_verified=true, ошибки пусты. Контроллер работал16.441541с, интервал socket snapshot5420.2279мс; это не тест производительности и не доказательство отсутствия влияния точек.

Console attachment `ce7bc915-0b4f-4421-bc82-9ef301175427`, SHA256 `6187537dff05ffbe1475db1c5c5116c2957613c5581a1a76cb05b30d68e15a1c`: 2/3d → be2/be3/g → события → bl2/3e → bd2/bd3/отдельныйg. Post-disable bl не показан; повторный Break только ради проверки не требуется. Видимых UNREADABLE/Memory access/Syntax/Bad register ошибок нет. USER отдельно подтвердил: скопирован весь видимый вывод. Не объяснять расхождение неполным копированием как установленным фактом.

Наблюдались7ASSOC_PRE,7RECORD_RAW16 и6ASSOC_POST; по thread+scope+source_ep+nbl получились только5полных пар. Все6наблюдаемых POST имеют result_raw=0. Без POST остались PRE endpoint ffff998765e2a010 на scopes ffff818788b61130 иffff818788b61560; POST endpoint ffff998774b3ec80/scope ffff818788b53560 не имеет PRE. Это неполнота наблюдаемой цепочки, а не доказательство отказа прикрепления или ошибки продукта. Причина отсутствия событий пока неизвестна; не объявлять потерю console output, пропуск software breakpoint или необычный возврат доказанными.

В7PRE видны4различных source endpoint,4record и4NBL address. Один набор указателей наблюдается неоднократно; это подтверждает повторные вызовы выбранного участка с теми же значениями, но не тождество packet lifetime и не TCP retransmit. Частота один раз на соединение не подтверждается.

Все RAW16 декодируются одинаково: A=127.0.0.1:54122, B=127.0.0.1:34010. Первый адрес совпал с заданным получателем native workload и dest в Core, второй — с локальным relay Core. Это положительное наблюдение адресов до прикрепления; называть их полной парой клиент/сервер нельзя. Исходный клиентский порт60393..60396 в этих полях отсутствует, поэтому независимо связать каждый kernel record с конкретным native connection/Core seq не удалось. Равенство числа4 не заменяет такой связи.

Private audit `pb-kd-association-four-result-review-20261018` сохраняет неизменённый console, events/pairs, review.json и SHA входов. Проверены64frozen references и SHA общего assets manifest;38capture inputs не изменились за разбор. Исходный отчёт остаётся KD_SESSION_NATIVE_EVIDENCE_CONFIRMED_DEBUGGER_PENDING и не переписывался. Локальная попытка прочитать необязательное workload/manifest.json обнаружила отсутствие такого файла; дальнейший разбор использует реально существующий comparison-manifest.json, это не ошибка запуска.

Стоп: план использован, не повторять Run и не готовить bounded до решения двух вопросов — полноты наблюдения и индивидуальной корреляции. Следующий офлайн шаг: рассмотреть независимые счётчики срабатываний существующих двух точек (без дополнительных trap sites), чтобы отличать недостаток строк от недостатка срабатываний; отдельно найти по проверенному коду источник клиентского порта. Счётчики пока не реализованы/не проверены, причина неполноты неизвестна. Старые профили/планы не редактировать, продукт не менять,10061 не исследовать. Точки оставить отключёнными, новых USER команд на этом стопе нет.

## Регистрация проверена, four-plan готов

USER прислал регистрацию: bc2/bc3, пустой bl, новые bp2/bd2 и bp3/bd3, итоговый bl только2d поfffff8026a817f14 и3d поfffff8026a817f20, отдельныйg. Actions вручную сопоставлены с JSON; видимых ошибок нет. Это подтверждение регистрации, не исполнения action/guards. Источник — сообщение USER, отдельный rawconsole/SHA полного сообщения не заявляется.

Boot Event12record16566/Prefetch113 совпал с предыдущим review. Private audit `pb-kd-association-four-preparation-review-20261018`: registration-observation.json, boot-session.json, session-review.json (толькоfour), preparation-result.json. Prepare общим wrapper через WindowsPS5 завершился exit0, встроенная проверка файлов/runtime успешна. Новый plan `pb-kd-session-plan-20261018-122340-181c1036/runtime-plan.json`, SHA256 `196A422BB1AEE67AD1D72CE95116C0CD56CD83C5D1125E8345D63B2562336006`.6metadata files/24218bytes/64frozenrefs,51общийreference с предыдущим bounded-plan имеет тотжеSHA. Ноль новых runtime/product binary copies; run-claim отсутствует, Run не выполнялся.

Следующий USER шаг — один four Run, active2/3. Перед Break и каждым be предупреждать об остановке всейVM/Codex/RDP; recoverybd2/bd3/bl/g поодной, g отдельноevenerror. Исходныйblнеповторять безизмененийсостояния. be2/be3/g поодной; USER Invoke-KdSession -Phase Run с новымPlanPath/PlanSha/ProfileReviewed/DebuggerLoggerEnabled. ПослеRun/error передBreak предупредитьwholeVM, bd2/bd3/bl/отдельныйg и полныйPS/console. Неrepeat/не256. Положительные PRE/POST/RAW16 и связь адресов с native/Core покаpending; частота/задержкинеизмерены, fullhistoryнепокрыта. Продукт не менялся.

## Основание и границы

Продолжение [live review](KERNEL_REDIRECT_ASSOCIATION_PLAN_2026-10-18.md). USER дополнительно прислал uf AleAcceptRedirectProxyNblTag: live RVA d7ff4, association call d8069, return d806e, key9 в caller rsp+20. Это другой ключ, не key5 redirect record. Показаны только2/3d и отдельный g, ошибок нет. Источник — текст сообщения, не отдельный raw attachment; не утверждать SHA полного console.

Новый профиль `scripts/debugger/pb-kd-association-pair-candidate-20261018.json`, SHA256 `b72e086ca81cf961d54f9c73da9032bd0d66cd78fd9b50977ef7daec9342d6ef`. Заменяет только2/3: обе новые точки находятся внутри TCP/IP caller key5, не в общей функции fwpkclnt. Без port-фильтра: значение адресных полей пока не установлено, поэтому фильтрация по предполагаемому порту могла скрыть нужные события. Не обещать малую частоту: caller может посещаться многократно на соединение.

| ID | Место | Наблюдение |
| --- | --- | --- |
| 2 | WfpTlShimInspectFastLoopbackSendDatagram+94 | До call: точные R9 record, RDX NBL, RBX source endpoint, thread/RSP. После проверок доступности —16сырых байт из каждого record+48/+c8. |
| 3 | Та же функция+a0 | Непосредственно после live call: RAX result_raw, RBP NBL, RBX source endpoint, thread/RSP. Только регистры. |

RSP не меняется между этими местами caller; RBX/RBP nonvolatile. Сопоставлять PRE/POST по thread+scope+source_ep+nbl и порядку открытого вызова, отклоняя неполные/неоднозначные пары. Нельзя считать NBL/endpoint address глобальным ID lifetime. POST не перечитывает record из endpoint и не выдаёт возможный новый указатель за аргумент PRE. Нулевой результат соответствует продолжению caller; ненулевой приводит к его ветке ошибки. Название result_raw не приписывает значению неподтверждённый тип NTSTATUS.

RAW16 — два qword на поле. Для IPv4 это16байт структуры; IPv6 полностью не помещается, поэтому полный IPv6 tuple не заявляется. Имена local/remote/original/redirected пока не подтверждены. Связь с Core должна проверяться по фактическим адресам/портам, фазе и сохранённым native/Core данным, не по совпадению количества событий.

Эти точки наблюдают attempt/result только данного caller. Они не наблюдают создание, освобождение, все возможные association callsites, retrieval или QUERY_NULL. Успешный POST сам по себе не доказывает наличие записи на пакете, который позже дошёл до accept. История32прежних failed lifetimes не восстанавливается новым запуском.

## Проверки и следующий стоп

Private audit `pb-kd-association-pair-candidate-review-20261018/review.json`: JSON/policy four, escape roundtrip registration_command, сбалансированные delimiters, guards перед4чтениями в16байтных диапазонах, gc вне guards. Нет stack-memory reads или глобальных псевдорегистров. Первичная проверка ошибочно искала substring bp и отклонила регистр rbp; исправлена проверка границ команды, профиль из-за этого не менялся. WinDbg parser и исполнение actions ещё не проверены; это не runtime validation.

Следующий USER шаг — только регистрация обеих отключёнными: beforeBreak wholeVM/Codex/RDP warning, recovery bd2/bd3/bl/g по одной. Исходные2/3d известны; без reconnect/reboot/изменений дополнительный исходный bl не нужен по предпочтению USER. bc2, bc3, затем новый bp2 и сразу bd2, новый bp3 и сразу bd3; каждая наружная команда отдельно. Перед каждым bp предупредить, что точка изначально включена и VM остаётся остановленной. После изменения один bl для проверки результата, затем отдельный g даже при ошибке. При ошибке прекратить регистрацию, отключить доступные2/3, восстановить выполнение, прислать вывод; не продолжать цепочку слепо.

Не be/не Run на этом шаге. После console review подготовить новый маленький four-plan общим запускателем, без копирования runtime/продукта. Пробу проводить только USER. Bounded сейчас не подготовлен/не разрешён; после four нужны положительные события, pairing, адресная корреляция, проверка ошибок/cleanup/задержки. Продукт и старые комплекты сохранены.
