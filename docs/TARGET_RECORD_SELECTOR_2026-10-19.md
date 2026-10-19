# Одна точка создания записи: проверка выбора контрольного соединения

Статус: DISK_SELECTOR_REVIEWED_LIVE_PENDING. Новый Run/профиль не подготовлен,
точки не устанавливались. Цель следующего опыта — положительное наблюдение
создания private record для control, а не вся история transfer/free сразу.

## Что изменилось относительно прежнего наблюдения

Прежние association snapshots читали record+48/+c8. В дисковом caller поRVA10833a
это original/modified remote sockaddr кандидаты, поэтому client source port
не обязан присутствовать в этих двух областях. Отсутствие порта там не означает,
что запись нельзя выбрать по локальному адресу входного запроса.

Caller function108050..1083da передаёт пятым аргументом RBP-80, R8=RBP,
RDX=RBX+b0. AlepCreateRedirectRecord сохраняет пятый аргумент вR14 через[RBP+60].
После TCP endpoint assignment на+38f, вsite+396 доступны RDI=endpoint,
RAX=assigned record, R14=сохранённый пятый аргумент. Наблюдаемый код использует
R14 как sockaddr pointer. Кандидат — прочитать только family/port изR14,
проверить control port42201 (network raw word d9a4), затем записать одну
самодостаточную строку с endpoint/record/context pointer/size/refs.
Не читать context payload и не использовать текущий PID как доказанного owner.

Смысл caller RBP-80 как локального sockaddr ещё требует live/caller-проверки.
Для unbound адреса допустим0.0.0.0: нельзя требовать127.0.0.1 в этом запросе,
хотя конечный TCP tuple из native/Core имеет127.0.0.1.

Дополнительно прослежена передача metadata: record+1d0 получает аргумент6,
+1d8 — аргумент7,+1e0 — аргумент8,+1e8 — аргумент9. В выбранном caller значения
берутся из modified request offsets108/120/128/130. Это соответственно
redirect target PID/handle/context pointer/size для данного ABI, не native PID.
[Microsoft FWPS_CONNECT_REQUEST0](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/fwpsk/ns-fwpsk-_fwps_connect_request0)
описывает эти поля; их названия сами по себе не документируют private record.
Наш driver source236..239 задаёт selfPid/gRedirect/ctx/sizeof(*ctx) именно так.
Следовательно, фильтр по record+1d0 как PIDгенератора был бы неверным.

## Проверено без runtime

Текущий tcpip.sys SHA b0683bd7ed0f309e63b4e6e71675d8f04cfb0ea5533c3f5e8a13c6daca3b595a
совпал с прежним PE.23 instruction starts проверены напрямую поPE bytes,
direct call target108520 и обе function bounds подтверждены exception directory.
Private audit `pb-target-record-review-20261019/review.py`, `review.json`.
Это не проверка всех live bytes/исполнения/полноты ловушек.

## Физический host: следующий read-only шаг

Break приостановит всю VM PB-BUILD-W11-25H2, включая Codex/RDP. Заранее скопировать
команды; вводить по одной, g всегда отдельно. При ошибке сохранить её и выполнить
g, не исправлять flags/не регистрировать точки. Повторный bl без изменения
регистрации не нужен. Нового bp/be/single-step/Run в этом шаге нет.

После Break (если kd> уже доступен, повторный Break не нужен):

```
.reload /s
.reload /f tcpip.sys
u tcpip!AlepCreateRedirectRecord L0n24
u tcpip!AlepCreateRedirectRecord+0x36c L0n20
u tcpip+0x1082d1 L0n24
g
```

Символьный путь уже был настроен пользователем на локальные matching PDB.
Если он изменился/символы не разрешились, завершить g и прислать ошибку.
Не использовать принудительную загрузку неподходящих symbols.

После live-сверки нужен отдельный отключённый профиль и format/guard probe.
Только затем fresh plan с явным debugger observer: текущий target controller
умеет только ETW/zero points и не разрешает включать эту точку поверх его Run.
Нужна проверка positive event и связи с control source port; пропуск события
не доказывает отсутствие создания. Число traps до фильтра и once-per-flow
не установлены. Не возвращать прежние association PRE/POST как полное покрытие.
