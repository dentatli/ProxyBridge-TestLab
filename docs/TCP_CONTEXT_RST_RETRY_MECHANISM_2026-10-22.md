# Где расходятся TCP retry и перенос WFP redirect context

## Вывод

В совпадающем с PB-SUT образе tcpip.sys найдена конкретная несогласованность
путей: WFP receive inspection может отметить endpoint ещё до решения TCP
продолжить connect после RST; send-path с этим битом обходит привязку redirect
record к NBL повторного SYN. TCP при этом допускает retry вместо завершения
соединения. Связанный захват подтвердил этот механизм наблюдаемого10022; source context
в момент отказа сохранён.

Позднее получен [связанный kernel capture одного flow](TCP_CONTEXT_SINGLE_FLOW_CONFIRMED_2026-10-22.md):
RST writer, SYN gate/return, тот же NBL на accept и QUERY того же acceptedEP
сопоставлены с10022 исходного API. Механизм для исследованной сборки
подтверждён. Прямой опыт с изменением private bit не проводился и не нужен
для повторного подтверждения этой же наблюдаемой цепочки; точную коррекцию
закрытого исходного кода Windows должен подтвердить вендор.

## Почему RST не завершает connect

В TcpTcbCarefulDatagram проверка состояния2 ведёт к ветке SynSent; после
проверок ACK проверяется RST bit0x04 в TCP flags. Для RST+ACK есть холодный
участок функции, а не только обычный путь connection-refused:

| RVA | Статическое наблюдение |
| --- | --- |
| 0x56d5e -> 0x575d4 | RST flag ведёт к отдельной обработке |
| 0x575d4 -> 0x1bff84 | Ветка при наличии ACK |
| 0x1bffc8 | Проверка глобального ConnectFailFast |
| 0x1bffd1..0x1bffe9 | Дополнительные проверки flags и двух byte полей TCB |
| 0x1c0004..0x1c001e | В нефатальной ветке TcpStartTimerTcbInternal с500мс |
| 0x1c0028..0x1c003a | Альтернативная ветка abort, status0xc0000236 |
| 0x1c013f..0x1c0151 | Reason10 и возврат к пути discard |

Назначение двух byte полей без типов не объявляется известным. Значение
ConnectFailFast в загруженной памяти не читалось; наличие статической ветки
не означает разрешения менять глобальные TCP параметры.
Соседний вызов TcpTcbChangeFastopenState также не доказывает, что причиной
является включённый TCP Fast Open: probe его явно не включает. Не предлагать
отключение Fast Open или правку реестра на основании одного имени функции.

В существующем ETL выбранный TCB0xffffa18fbc08d010 трижды получает flags0x14
в SynSent. После каждого пакета он назначает retransmit timer500мс:

| RST receive UTC | Timer500мс UTC | Интервал |
| --- | --- | --- |
| 06:58:10.7869230 | 06:58:10.7869242 | 1.2мкс |
| 06:58:11.2867895 | 06:58:11.2867904 | 0.9мкс |
| 06:58:11.7887625 | 06:58:11.7887634 | 0.9мкс |

Затем тот же TCB устанавливает соединение. Таким образом, ранний RST и
успешный connect в наших результатах совместимы; это не основание считать
RST относящимся к другому flow. Private retry-timer-report.json получен из
исходного ETL, без нового runtime.

## Почему это затрагивает context

Порядок в TcpTcbReceive (с учётом chained unwind fragments):

1. RVA0x8df94 вызывает InetInspectReceiveTcpDatagram.
2. Его RVA0x22e42 вызывает WfpTlShimInspectRecvTcpDatagram.
3. В WFP receive RVA0x23670 выполняется lock OR endpoint+0x30,0x200000,
   если до того установлен bit0x100000. Это раньше последующей TCP обработки
   и её решения о retry/abort. Прежние PBW/PBT runtime captures фиксировали
   именно установку этого бита на RST+ACK.
4. После возврата TcpTcbReceive разбирает TCP header, затем через
   TcpTcbCarefulDatagram принимает описанное выше решение о RST.
5. В WfpTlShimInspectFastLoopbackSendDatagram проверка endpoint+0x30 bit21
   (RVA0xd7eb0, branch0xd7eb4) сразу уходит к эпилогу0xd7fcf. Она не проверяет,
   является ли текущий пакет повторным SYN, и обходит блок association key5.

Ключевое разделение: «WFP уже обрабатывал входящий пакет» не эквивалентно
«TCP handshake завершён и больше не понадобится перенос redirect metadata».
Это интерпретация поведения private bit, не его подтверждённое имя/описание.
Source record+context оставались доступны в прежних захватах, тогда как
accepted/query endpoint имел NULL record. Следовательно, говорить только
об освобождении буфера context как причине неправильно.

[Различающий опыт](TCP_CONTEXT_RST_DISCRIMINATION_2026-10-22.md) поддерживает
механизм: без ранних RST три retries сохраняют context; с ранними RST оба
getters дают10022. Это не заменяет single-flow observation самого bit и key5
в том же физическом опыте, но исключает простое «любой повтор SYN теряет context». Поздний связанный
захват закрыл указанный пробел для одного физического flow.

## Важная деталь разбора функций

Первый .pdata range TcpTcbReceive заканчивается0x8dec3, но это не конец всей
функции. UNW_FLAG_CHAININFO связывает ещё диапазоны0x8dec3..0x8f914 и
0x1c7efc..0x1c811d с её primary unwind. Для TcpTcbCarefulDatagram связаны
0x56588..0x57b57 и0x1bff20..0x1c0d9f. Поэтому анализ только первого range
пропустил бы RST retry. В текущем private reset-path-calls.json учитываются
все связанные диапазоны; прежние усечённые dumps не выдаются за всю функцию.

Формат: [Microsoft x64 exception handling / chained unwind](https://learn.microsoft.com/en-us/cpp/build/exception-handling-x64?view=msvc-170).
Образ и PDB хеши зафиксированы в предыдущем отчёте; target disk tcpip.sys
побайтно совпадает. Загруженная память целиком не сравнивалась.

## Что исправлять и что ещё осталось

В ProxyBridge уже подготовлен быстрый accept независимо от setup. Он уменьшает
queue refusal и соответствующие ранние RST; это корректное предотвращение
проверенного trigger, но не обещание восстановить metadata после любого RST.
При отсутствующем context нельзя угадывать original destination. Product
branch37e64c6 в этом этапе не менялась, новые тесты не добавлялись.

Кандидат исправления для владельца Windows stack: сохранить необходимую
привязку redirect metadata на SYN retry даже после раннего receive inspection,
с корректным lifetime/refcount. Это требование к поведению, а не готовый патч
private flag или предложение подавлять все RST.

Связанный захват уже выполнен и описан в итоговом отчёте. Старое предложение
такого захвата больше не является очередью действий. После завершения
физический PB-SUT проверен QUIESCENT, все точки отключены, g выполнен.
