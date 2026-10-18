# Контрольное соединение при заполненной очереди: подготовка

Статус: диагностический Core с управляемым барьером собран; runtime-контроллер
и sealed Run ещё не подключены. Не запускать этот Core вручную вместо рабочего.
Повтор обычной328-нагрузки не требуется. Продуктовые исходники, старые captures,
frozen kits и установка драйвера не менялись.

## Подготовленная часть

`pb_prepare_target_accept.py` проверяет SHA родительских Core/relay/CLI/SYS,
parent source manifest, создаёт новый каталог только внутри diagnostics и
проверяет точную обратимость изменения relay. Меняется только копия Core:
перед первым IPv4 accept появляется одноразовый барьер, header добавлен отдельно.
Исходный query не перемещён, повторных запросов нет. Backlog остаётся original.

Контроллер должен заранее создать два manual-reset named event с новым
случайным32hex token; Core только открывает их. После первого queued соединения
Core сигнализирует ready и ждёт release. Timeout30секунд, отмена через running,
ошибка/неверный selector завершают цикл без accept; handles закрываются,
исходный WSA error восстанавливается. Работа разрешается только с
PB_TESTLAB_ROUTE_CASE=original. Это диагностическое управление accept, не
setsockopt(SO_PAUSE_ACCEPT), не исправление продукта и не Sleep650.

`TargetAcceptCohort.psm1` содержит создание/закрытие событий и callback-последовательность:
fillers start →Core ready→подтверждение fillers→control start→control SYN→
короткое удержание→release→collect. При любом сбое release вызывается до cleanup;
cleanup выполняется и при исключении release. Повторное использование Gate запрещено.
Callback обязан учитывать все запущенные процессы, включая частично запущенные.

Проверено:10 C fake-API сценариев без реальных events/sockets/waits/driver,
9 fault/success сценариев последовательности без процессов/сети,
PS5 parser и отдельный real named-event smoke без трафика.19Core exports совпали.
Первый fake build r1 упал на shadowing warning, исправлено имя fixture variable;
новый r2 успешен. Старый r1 сохранён, не объявляется успешным.
Попытка smoke в shell без ExecutionPolicy bypass не выполнила Import-Module;
напечатанная там строка OK недостоверна. Исправленная проверка через отдельный
`powershell.exe -NoProfile -ExecutionPolicy Bypass -File .../verification/check.ps1`
с ErrorActionPreference Stop завершилась exit0 и записала check-result.json.

Private build `pb-target-accept-preparation-20261019-r2`: CoreSHA
`e04fc3e39092328b8cb5a7edabf040dcf3f0906f39f88371b04eb3ea9111b720`,
status DIAGNOSTIC_BUILD_PREPARED_NOT_RUNNABLE. Нет runnable product.env/Run claim.
CLI/SYS повторно использованы побайтно; SYS SHA3cd79cfc... известной версии.

## Оставшаяся интеграция перед первым Run

Нужен ограниченный контроллер native fixture и role-aware report, не обход
проверок универсального runner: его прежний report предполагает один client PID
на фазу, а здесь fillers и control имеют разные PID.

Кандидат:200fillers с -LocalPort:[57001,57200] и один control с -LocalPort:57201.
Опция LocalPort подтверждена в сохранённом ctsConfig.cpp, но новая командная
строка ещё не выполнялась.200 — стартовый параметр опыта, не измеренная ёмкость.
Перед использованием обязательны проверки занятости всех портов/ролей,
SHA бинарников, памяти, boot, exclusive lease/claim, driver resident pre/post,
Core DLL binding и временных бюджетов. Не включать SO_REUSEADDR для обхода port collision.

Fillers должны быть подтверждены по PID/полным tuples до запуска control;
release должен произойти после его первого SYN, но до успешного повторного
приёма. Связь проверяется ETW, не предполагается из одного Sleep/SynSent snapshot.
Успех подготовки runtime: именно control tuple имеет1214Reason30/1186,
потом accept/Core original query10022, fillers отделены по PID/портам,
ETW loss0, исходный query ровно один, штатная очистка. Иной результат INCONCLUSIVE.

Только после этого можно проектировать наблюдение одной внутренней записи
Windows. Точки WinDbg пока не ставить; старые адреса не использовать.
30секундный watchdog может истечь при debugger pause: это неполный опыт,
не повод незаметно отключать timeout или объявлять проблему устранённой.
