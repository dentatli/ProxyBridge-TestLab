# UDP: первый настоящий driver trial и продолжение через TestLab

## Авторизация и обязательный следующий объём

USER явно разрешил **установку и проверку** подготовленного драйвера и попросил
использовать разработанную лабораторию для сравнения **всего до/после**.
Разрешение действует; повторно спрашивать о замене пакета в рамках этой работы
не нужно. Не создавать PR/merge в driver без отдельного запроса.

Сравнение ещё не выполнено. Не выдавать диагностическую matrix или simulated
device probes за законченный лабораторный before/after benchmark.

## Фактически выполнено

Свежий physical PB-SUT trial `C:/PB-UDP-DriverTrial-20261022-r1`, source product
`30b4ec7`, signed SYS SHA256
`ed3c635149d1a480a9633bec3be77b40b1e014b059888ec78099663aca79c2fe`,
Core `50a3ddc7e360e01ed2b7aec0072c68819e84aaacbe4f60e4e039beaf57f2a79c`.
Новый package установлен forced update того же root devnode и реально запущен.
Trust/BCD/system proxy/power не менялись; автоматического reboot не было.

- Direct controls: **12/12**.
- Explicit SOCKS5 controls: **12/12**.
- Core: **0/1**, остановка на первом отказе, connected IPv4 implicit bind.
- Core AddProxyConfig=1, AddRule=1, Start=1, Stop=1, cleanup_verified=true.
- Единственный product payload SHA256
  `12754d91479e3ad3fd3addb2f27a510426bfcf3e1e970af59c65d9c7935152d6`
  прослежен через proxy_out → origin → proxy_return с тем же hash.
  Worker `127.0.0.1:59380` ожидал ответ от `127.0.0.1:61019` и получил timeout.
- Core log: `UDP driver: queue_drop=0 alloc_drop=0 metadata=0 inject_error=1 endpoint_limit=0 stale=0`.
  Core channel: drops=0, malformed=0, io_errors=0.

**Наблюдение:** outbound packet channel и реальный SOCKS roundtrip работают в
первом случае, отказ локализован в обратной driver injection. Точная причина
ошибки NBL ещё не установлена: счётчик не сохраняет NTSTATUS. Нулевой/неверный
interface index при receive injection — гипотеза, не доказанный вывод.
Следующий шаг — получить точный completion status и metadata, затем исправлять.
Не запускать нагрузку, пока этот correctness gate не пройден.

## Восстановление проверено

Runner finally вернул исходный пакет. SYS SHA256 снова
`3e5c3c709ee8c8800628f04b5550f3a82377deb264b045ab2f2ccbab3fd8fb4c`;
service **Stopped**, startup **Disabled**, PnP **problem32**, restored=true.
Wrapper: COLLECTED, target identity=true, cleanup_errors=[], клиентский WinRM
Stopped, TrustedHosts восстановлен. Reboot не требовался.
Runner python_exit=null: нельзя трактовать как проверенный exit0; результат
отказа подтверждён matrix JSON, Core logs и восстановлением. Lifecycle reader
ExitCode в runner также стоит исправить перед следующим свежим trial.

Evidence (private/ignored):
`artifacts/diagnostics/udp-driver-target-20261022-r1`:
`command-output.json`, `result.json`, `target-files/results/result.json`,
`target-files/run-result.json`, stdout/stderr и transferred payload.
Trial r1 **потреблён**, не возобновлять и не повторять в том же каталоге.
Подготовка `udp-driver-trial-20261022-r1` запечатана прежним manifest;
для правок runner/product build создать новые artifact/evidence directories.

## Лаборатория: найденные штатные возможности

- `scripts/Invoke-LocalUdpSoak.ps1`: STANDARD/FAST/PARALLEL/MULTI_TARGET и другие
  профили, через штатный `Invoke-WfpUnruledComparison.ps1`.
- `Invoke-WfpUnruledComparison.ps1`: управляемые OFF/PROXY или OFF/UNRULED пары,
  сопоставимые packet count/size, warmup, interval, streams, destinations и logs.
- `scripts/Invoke-WfpLocalRouteProbe.ps1`: реальный lifecycle, profile, route,
  native client, controlled proxy/receiver, samples и cleanup gates.
- `src/pb_udp_benchmark_report.py`: payload/hash/source correctness, drops,
  cross-stream replies, latency/performance и scoped CPU/RAM evidence.
- `Invoke-VersionComparisonPreflight.ps1` сейчас ориентирован на исторические
  driver/v4.0.0 TCP kits и reboot-between-versions; это не готовый допуск для
  текущей пары b359627/30b4ec7. Не использовать его старые receipts как новые.

Текущий checkout TestLab расположен на управляющей VM; штатные local scripts
исполняют продукт на своём host. Для сравнения на физическом PB-SUT требуется
корректно развернуть/адаптировать штатные компоненты, paths и build identity,
сохранив route/cleanup/lifecycle gates. Старый CLI readiness отказ остаётся
границей, которую нельзя скрыть снятием проверок или заменой API без явной
маркировки. Linux-origin USER ранее исключил; нужен локальный режим PB-SUT.

Сравнение должно использовать согласованные old/new Core+SYS комплекты,
одинаковые условия и отдельные свежие результаты каждой ревизии. Сначала
полная корректность UDP (и регрессии TCP по допустимым штатным сценариям),
затем потери/задержки/throughput/CPU/RAM/handles; сравнение размера отдельно.
Не дробить длинный suite для обхода длительности и не выдавать сбой за baseline
производительности. Приоритеты: надёжность → скорость → ресурсы → размер.

## Причина остановки

Usage tool сообщил primary usedPercent=95, remaining=5%; weekly used=27%.
Остановлено по правилу лимита, не из-за отсутствия разрешения пользователя.
Новых product edits/commits после `30b4ec7` в этом этапе нет; integration
driver не менялась, PR нет. Сначала проверить новый доступный остаток лимита,
затем продолжить с сохранённого отрицательного kernel gate.
