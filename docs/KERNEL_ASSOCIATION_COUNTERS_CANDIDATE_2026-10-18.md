# Проверка полноты наблюдения association без дополнительных точек

## Регистрация принята, готов один four-plan

USER прислал команды регистрации и итоговый bl: только ID2d поfffff8026a817f14 иID3d поfffff8026a817f20, обе action совпадают с counters JSON. Отдельные r@$t0=0/r@$t1=0 и TOTAL pre=0 post=0 показаны, затем отдельныйg. Ошибок в сообщении не видно. Это проверяет регистрацию/инициализацию/чтение переменных, но не увеличение счётчиков при срабатывании. Источник — chat paste; SHA полного console не заявляется.

Boot16566/113 совпал с предыдущими live reviews. Общий Prepare через WindowsPS5 завершился exit0 и встроенной проверкой файлов/runtime. Новый plan `pb-kd-session-plan-20261018-135304-62f88e06/runtime-plan.json`, SHA256 `7BA88CCD8F321EB069C7535380925E23ACE85903A8D08C78F0DD521732C02C48`.6metadata files/24119bytes/65frozenrefs;53общих reference с прежним association four-plan имеют прежниеSHA. Новых runtime/product binary copies0. Run/run-claim/трафика/agent debugger control нет. Private audit `pb-kd-association-counters-four-preparation-review-20261018` содержит observation/boot/review/preparation-result; allowed_workloads толькоfour.

Следующий USER шаг: beforeBreak/каждыйbe wholeVM/Codex/RDP warning; recovery bd2/bd3/bl/TOTAL/отдельныйg даже приошибке. Исходныйblнеповторять, безизмененийWinDbg исходные0/0 уже подтверждены и повторныйreset не нужен. be2/be3/g поодной, один USER Run с новымPlanPath/PlanSha/ProfileReviewed/DebuggerLoggerEnabled. Можно закрытьGPT радипамяти. ПослеRun/error передBreak предупредитьwholeVM, bd2/bd3/bl, отдельноprintfTOTAL изprofile.counter_read_command, отдельноg, прислатьвесьPS/console. Еслиошибкаprintf, всёравноg; неresetсчётчики/неrepeatRun/не256. Послеreconnect/неизвестныхизменений не полагаться на сохранённые нули/регистрацию/boot. Старые планы неиспользовать.

Основание: [предыдущая проба](KERNEL_ASSOCIATION_PAIR_CANDIDATE_2026-10-18.md) дала7PRE/6POST и5полных пар. USER подтвердил, что скопировал весь видимый вывод. Причина недостающих событий неизвестна. Продуктовая проба успешна, но переход к bounded не обоснован полнотой kernel capture.

## Новый профиль

`scripts/debugger/pb-kd-association-counters-candidate-20261018.json`, SHA256 `48928a28d7b24453bc6febf0499907d2e6bd4b40ab0113be56b281f3cf6d2152`.

Адреса точек не меняются: ID2 TCP/IP caller+94, ID3 caller+a0. В начале action2 увеличивается @$t0, в начале action3 — @$t1. Каждая action печатает ровно одну строку с собственным hit и заканчивается gc. Это переменные отладчика, записываемые командой r: [Microsoft, Pseudo-Register Syntax](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/pseudo-register-syntax). Целевые регистры/память продукта командами счётчиков не изменяются. Новых trap sites нет.

PRE сохраняет точные record R9/NBL RDX/source endpoint RBX, POST — result RAX/NBL RBP/source endpoint RBX; оба сохраняют thread/RSP для сопоставления. RAW16 убран: прежняя проба подтвердила чтение двух общих адресов, но они не содержат клиентского порта. В новом профиле нет явных чтений памяти VM, включая stack, record и ETHREAD.Cid. Это уменьшает количество строк и меняет диагностическую работу action; не считать будущую разницу во времени чистым измерением влияния только счётчиков.

Счётчики считают выполнение command list, а не все реальные вызовы ядра. Полнота всех traps ими не доказывается. PRE hit и POST hit — независимые последовательности; одинаковые номера не означают один вызов. Пары сопоставляются прежним thread+scope+source_ep+nbl и порядком открытого интервала.

Перед пробой при отключённых точках USER обнуляет оба счётчика отдельными командами r @$t0 = 0 и r @$t1 = 0. После пробы сначала bd2/bd3, затем отдельный снимок `.printf "PBKDAC TOTAL pre=%I64x post=%I64x\n", @$t0, @$t1`; не обнулять до сохранения результата. hit и TOTAL печатаются в hex. Проверить начальные нули, монотонность каждой последовательности при разных потоках, пропуски/повторы номеров, максимальный номер и итог, затем содержимое пар. Изменения счётчиков извне/reconnect/reset делают сравнение недостоверным.

Если итог больше числа видимых строк или внутри последовательности есть пропуски, подтверждается расхождение вывода с выполненными actions при условии непрерывной работы счётчиков. Если итоги совпадают со строками, а пары неполны, этот тест не объясняет причину: остаются охват срабатываний/поток исполнения/ограничения состояния отладчика. Даже равные итоги PRE и POST не доказывают правильное индивидуальное pairing. При немонотонности/несогласованном снимке сначала исследовать поведение счётчиков, а не объявлять потерю строк. Не обещать исправление полноты или отсутствие observer effect.

## Проверки и текущий стоп

Private audit `pb-kd-association-counters-candidate-review-20261018/review.json`: прежний профиль побайтно сохранён, те же два targets/RVA, count format arguments/escaping/final gc/одна printf на action/no memory reads/policy four проверены офлайн. WinDbg parser/actions/counters ещё не проверены. Первая поисковая команда ошибочно передала rg literal wildcard paths; исправлено реальными каталогами и -g, без изменения продукта. Обходов Dejavu не было.

Выборочный разбор текущих caller sites RVA41643/7d731/d724c и исторических имён не установил проверенный offset клиентского порта. В новом профиле порт не добавлен, индивидуальная kernel↔Core корреляция не заявляется. Продолжить этот вопрос отдельно по точному dataflow; не читать произвольные offsets endpoint или освобождённые указатели из прошлой пробы.

Следующий USER шаг — только замена actions и регистрация отключёнными: beforeBreak wholeVM/Codex/RDP warning/recoverybd2/bd3/bl/g отдельно. Исходные2/3отключены; без изменений исходныйblне нужен. bc2/bc3, beforeкаждыйbp initially-enabled warning, новыйbp2/bd2 иbp3/bd3 поодной. Обнулить t0/t1, один итоговыйbl и TOTAL с ожидаемыми0/0, отдельноg evenerror. Приошибке прекратить регистрацию, bd2/bd3/отдельныйg и прислать вывод. Никакихbe/Run. После console review подготовить новый four-plan общим launcher, а не повторять старый Run. Bounded не подготовлен. Старые профили/комплекты/журналы и продукт не менять,10061 вне разбора.
