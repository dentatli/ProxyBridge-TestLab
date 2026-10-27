# Endurance60: PROXY, DIRECT и BLOCK одновременно — 27 октября 2026

## Покрытие и нагрузка

К длительному режиму добавлены четыре контрольных канала, выполняемые параллельно с прежним PROXY-профилем и во время затишья: DIRECT TCP/UDP (42541/42542) и BLOCK TCP/UDP (42543/42544). Раз в минутном окне — один короткий обмен/попытка на канал. Нагрузка фиксирована, отдельного выбора нет. Клиент продолжает работать, глобальный выключатель не переключается. HTTP/HTTPS/HTTP2/SFTP/DNS-TCP/QUIC остаются периодическими PROXY-операциями; DIRECT/BLOCK проверяются на транспортном TCP/UDP уровне, не утроением всех прикладных профилей.

Четыре правила ограничены nativeworker, текущим loopbackhost, конкретным портом и TCP/UDP. Для DIRECT ниже по приоритету добавлено точное BLOCK-правило на его два порта: успешная доставка подтверждает действие DIRECT поверх него, а не default-direct при отсутствии правила. Основные PROXY правила, process/PID/path identity и проверка payload/route сохранены. Для обычных сценариев новые слушатели/правила не создаются. Нет глобального catch-all и доступа к чужому трафику.

## Доказательства

DIRECT требует аутентифицированный успешный обмен, приращение счётчика получателя и DIRECT-события от Core без SOCKS5/PROXY/BLOCKED. BLOCK требует ожидаемую неуспешную попытку, BLOCKED-событие от Core, ноль TCPaccept/UDPdatagrams на получателе и отсутствие SOCKS5-доставки. Перед каждой группой origin выполняет собственный аутентифицированный обмен с блокируемыми портами из неохватываемого правилами процесса: неработающий получатель не может превратиться в «успешную блокировку». Неизвестный worker/control/health прекращает попытку. Тайм-аут без остальных доказательств не является успехом.

Policy-ответы Core содержат ACK пяти ruleID и counters по четырём портам; identity фиксируется, команды сериализованы. Счётчики origin включают сырые TCPaccept/UDPdatagrams, даже если прикладная аутентификация не началась. Ожидаемые BLOCK-ошибки не попадают в потери PROXY-профиля. Четыре результата сохраняются отдельными компактными строками; полные HMAC/счётчики/health находятся в append-only policy-observation journal. Ошибки sticky, общий PASS невозможен без реально выполненных четырёх контролей. Метод изменён на endurance-fixed-cycle-v2-policies; предыдущие H2 не являются эквивалентным профилем для ресурсного сравнения.

## Проверки

- C#engine/UI сборки:0warnings/0errors; MSVC CoreHost /W4 /WX успешно.
- Реальный официальный WinDivert4.3.0Core наVM:70с private admission, все6apps и PROXY TCP/UDP/bulk/churn успешны; DIRECT TCP/UDP и BLOCK TCP/UDP по10успешных контролей, nativejobs0. Без explicittest_proxy. Пять policyправил и оба обычных подтверждены ACK.
- Реальные отрицательные проверки: отключённый DIRECT приводит к нижестоящему BLOCK и не проходит; отключённый BLOCK приводит к доставке TCP/UDP и не проходит. Никакой falsePASS по одному отсутствию ответа.
- Отмена с контрольными задачами:1.719с, nativeworker и nativeorigin jobs0, Corecleanuptrue/forcedstopfalse. После выхода ownedпроцессов/WinDivertслужб нет. WFP APIветка использует те же exact-port/protocol/action/ACK checks, но реальный WFPпрогон здесь не выполнялся.
- 35 существующих native wire/route/capacity/cancel/falsePASS проверок PASS; 3 проверки portscope PASS; 2 целевые проверки BLOCKдоказательств PASS (нетсобытия/естьдоставка/неисправныйполучатель неуспех). ActualJS:250сохранённыхотчётов,совместимость,четыреpolicyстрокиизреальногоrawбезNaN PASS.

Evidence ignored: artifacts/endurance-check/check60-guarded-product.log, probe-1793083989127074400; check60-cancel.log, probe-1793084214223596400; contracts60.log, engine-contract-1793084129640700200; ui60.log; tests/test_traffic_endurance_policy.py. Ранее снятый admission до добавления нижестоящего guard — отдельная промежуточная проверка, не доказательство финального guard.

2/24/48/72ч с новым профилем ещё не запускались. Эта проверка расширяет покрытие действий правил и их приоритета; она не заменяет отдельные проверки доменных правил, IPv6 и всех вариантов многопоточности/UDPownership. Продуктовые DLL/SYS не менялись; нет BCD/trust/установки WFP. Тесты используют ранее разрешённую временную загрузку официальногоWinDivert, состояние очищено.

## Развёртывание

Preview60 source df1a002dd635ad6be339933ce7be1661825d5dd5 установлена/запущена на VM и PB-SUT(payload/lab60). 1704SHAнакаждойкопиисовпали;admintrue/activefalse/busyfalse;2сборки,историяVM10/SUT12,unreadable0. Storesсохранены,Comparisontaskобновлена,старыепакетыоставлены,clientcleanupбезошибок. Многочасовойтестне запускался. Evidence ignored: package60-verified.json/sut-upgrade60-r1 и VM artifacts/endurance60-vm-ready.json.
