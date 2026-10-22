# UDP: loopback injection и сравнение штатным TestLab

## Итог локального этапа

Локальная проверка завершена: [итоговые before/after результаты](UDP_TESTLAB_BEFORE_AFTER_RESULTS_2026-10-22.md).
Штатный TestLab15072/15072 через новую версию (включая1536 на финальном
штатном CLI); final package1.1.0.0 —
42/42 Direct,42/42 explicit SOCKS,39/39 Core включая stalled-proxy isolation.
Восстановление исходного пакета подтверждено. Отдельный старый TCP DIRECT
route defect воспроизведён до/после и не исправлен. Ниже — журнал этапов,
не очередь возобновления старых trial. PR нет, integration driver не менялась.

Последний product code head735b9fa, CLIbe95c16e, Core7a02e79b, final SYSc1ab4193.
CLI Stop теперь принадлежит main, readiness flush-ится; upstream/ConPTY gate
прошёл3 запуска без forced stop. Headless review kit сохранён отдельно.

## Текущий объём

USER разрешил установку и проверки, потребовал сравнение до/после штатной
лабораторией. Разрешение действует. PR/merge в integration `driver` не разрешены.
Приоритеты: надёжность → скорость → ресурсы → размер.

## Подтверждённое исправление

Product branch `codex/udp-map-source-key`, commit
`5ca31ac69df4a0440585eb36554df7c8f3ad8488`, опубликован и remote проверен.
В `driver` ничего не вливалось.

Свежий r3 physical trial получил точный completion status:
`0xC000021B STATUS_DATA_NOT_ACCEPTED`, stage=2, family=2, kind=RECEIVE,
compartment=1, interface=1, subinterface=0. Гипотеза про нулевой interface
для этого случая не подтвердилась. Outbound/SOCKS roundtrip имел верный hash.
NBL для loopback-ответа отклонялся при transport receive injection.

В r4 изменён путь только для ответов с обеими loopback addresses: network send
с отдельными injection handles/self-injection checks и штатным rundown. Полный
IP/UDP header и исходный source tuple сохранены. Для non-loopback остаётся
transport receive. Native analysis/сборка/INF/signature verification прошли.

Actual signed SYS SHA256:
`482940c023d2e4f763d298abc8ffb032f8fb9819a9ebb541b6d82d54525310c3`.
Пакет lab INF version `1.0.0.102`, published oem23.inf; PnP state Running/problem0
и точный загруженный файл проверены перед трафиком. Версии lab package различаем:
повторно использованный одинаковый INF/version ранее не подтвердил новый SYS
(r2, остановка до трафика); отдельная версия 1.0.0.101 загрузила нужный файл.

Runtime gate r4: Direct12/12, explicit SOCKS12/12, Core12/12. Покрыты IPv4/IPv6,
connected/unconnected, implicit/wildcard/concrete bind. Дополнительно paired
двух клиентов к одному origin: оба получили собственные hash и исходный peer.
Core channel drops=0/malformed=0/io_errors=0. Это не нагрузочный benchmark.
Исходный пакет восстановлен: SYS
`3e5c3c709ee8c8800628f04b5550f3a82377deb264b045ab2f2ccbab3fd8fb4c`,
Stopped/Disabled/problem32, restored=true, wrapper cleanup_errors=[].

Evidence private/ignored: `artifacts/diagnostics/udp-driver-target-20261022-r3`
и `...-r4`; подготовки `udp-driver-trial-20261022-r2/r3/r4` потреблены.
Runner теперь удерживает process handle и читает exit code через Win32;
python exit0 сам по себе не доказывает PASS (matrix сохраняет fatal отдельно).

## Адаптация TestLab — пока не законченный before/after

Добавлены opt-in PnP lifecycle (строго выбранный root devnode, service/path/hash
и published INF), PACKET_CHANNEL capture mode, exact source policy и проверка
активного канала по логу принадлежащего CLI. Legacy defaults сохранены.
Product-only checks могут использовать отдельный Python по PB_LOCAL_PYTHON_EXE.
Runtime preparation tests проходят, включая negative guards без hardware.

Штатный CLI lifecycle сначала отказал с CLI_READINESS_TIMEOUT, workload не
запускался; итоговый лог содержал строку готовности. Предположение о reader
не подтвердил отдельный short-output/UTF8 test: старый и новый reader прошли
на pwsh7 и Windows PowerShell. Экспериментальная правка reader убрана.

Для сравнения применяется существующий `testlab-unbuffered-v1` CLI, SHA256
`ad83b3aad22252be0ab20a6c26470f7c364930af35089e9904f1dd0d29bb40ca`.
Один и тот же файл для обоих Core; production Core/driver не подменяются.
Его receipt/source hash проверены. Отличия CLI: unbuffered stdout/stderr,
Stop в main thread, DLL остаётся загруженной до process exit, shellapi.h.
Нельзя выдавать эту модификацию за полностью неизменённый upstream CLI.
Оригинальный CLI source между 63be0eb и b359627 отличается только shellapi.h;
между b359627 и 5ca31ac идентичен. Readiness gate с этим CLI пройден.

На PB-SUT Restricted execution policy мешала -File; только дочерний процесс
лаборатории запускается с Process RemoteSigned. Постоянная политика, trust,
BCD, system proxy не менялись. Все состоявшиеся попытки восстановили baseline.

Последняя подготовка `udp-testlab-20261022-r5`, target
`C:/PB-UDP-TestLab-20261022-r5`, evidence `udp-testlab-target-20261022-r5`:
штатный route probe, IPv4, 2 streams/one origin, 64 packets,512 bytes,10ms,
8 warmup/stream, PACKET_CHANNEL. При записи этого checkpoint результат ещё
нужно прочитать: не повторять этот trial и не объявлять PASS до receipt/report.
Предыдущий r4 Lab прошёл readiness, но новая запись ownership evidence вызвала
scope error PowerShell closure; исправлена запись прямо в closure. Product
packet defect этим отказом не установлен. Короткий gate предшествует полному
одинаковому before/after, TCP regression и более длинным UDP профилям.

Непокрытые риски: настоящий non-loopback return path, direct/block через новый
driver channel, zero/large datagrams, multi-destination одного сокета,
endpoint reuse/teardown/ошибки proxy; CPU/RAM/latency/throughput ещё не измерены
в сопоставимой серии. Старые simulated device checks их kernel путь не доказывают.

## Продолжение

### Обновление: r8 functional PASS

Product head `959ec92a06dd9361a7ce050cc82e2a303a9c4006` опубликован/проверен:
Core теперь сообщает успешный UDP_ASSOCIATE после настоящего handshake.
Новый Core SHA `7a02e79b4cbb5bae55c3323fe1984c8468622d0f6bbfdcdf766dac992c070104`,
SYS прежний 482940c0. TestLab r7 доставил 64/64 с exact source, но route gate
не имел прежнего сообщения ASSOCIATE. В r8 route/payload/source/lifecycle gates
прошли: **64/64, correctness PASS, performance MEASURED**. No drops/mismatch/
timeouts, Core graceful stop, workers stopped, driver detached, rollback verified.

Короткая измерительная фаза ~0.33 s не дала полных 250ms resource intervals:
pc_metrics=INCOMPLETE. Markdown renderer падал при форматировании None; теперь
выводит unavailable, не меняя gates. Проверено отдельным reanalysis в новом
каталоге `udp-report-short-reanalysis-20261022-r1`; исходный r8 evidence не менялся.
Wrapper r8 FAILED/BENCHMARK_REPORT_FAILED — именно ошибка renderer, не потеря
пакетов; нельзя подменять исходный receipt новым PASS. Новый длиннее trial нужен.

Перед этим native client parser запрещал exact-source + expected PROXY:
исправлена независимость source policy и routing action, BLOCK не разрешён.
Shared native binary SHA `d6973b8976418faf5633b457deacbdb1e340f43be3317be40b68d8da6d123d8c`,
source SHA `e6f99795b6ce65a5342c5c2a9f297f76d8e3519469cd242c0a5be1ca72ede3a7`.
Compiler W4/WX build и Test-ClientContract/Test-RuntimePreparation PASS.
Test-ProcessLifecycle имеет прежнее несовместимое ожидание empty ReadyRegex
(`New-ProxyBridgeCliPlan` давно подставляет обязательную строку); этот suite
в этом этапе не PASS, production readiness gate не ослаблялся.

Дальше: matched до/после с одинаковым instrumented CLI/native client, более
длинной CPU/RAM фазой, TCP smoke и дополнительной two-stream UDP серией.

Все описанные trial потреблены; не повторять/Resume/reseal. Для следующей
проверки — свежие directories и final SYS c1ab4193/Core7a02e79b, package1.1.0.0.
Локальный UDP объём завершён. Дальнейшее расширение: отдельный TCP DIRECT fix,
external paths, multihoming одного endpoint, длительная нагрузка/power/HLK,
политика owner crash. User сам проверяет перед запросом PR; не создавать PR
автоматически. Посторонний untracked KernelReadCapture.cs не трогать/не запускать.
