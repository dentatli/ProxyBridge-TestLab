# Две точки вокруг прикрепления redirect record

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
