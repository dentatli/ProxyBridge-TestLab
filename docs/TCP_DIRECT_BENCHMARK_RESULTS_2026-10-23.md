# TCP DIRECT — лабораторный before/after benchmark, 2026-10-23

## Итог и область вывода

48 измерительных прогонов завершены: 24 RTT/echo и 24 ctsTraffic transfer.
В исправленной версии фактический DIRECT обходит SOCKS5, PROXY остаётся через
SOCKS5; все проверяемые ответы/данные корректны. До исправления DIRECT в этом
сценарии ошибочно проходит через SOCKS5 — это воспроизведённый дефект, а не
функционально исправная performance baseline. Сравнение DIRECT показывает
замену фактического маршрута, не сравнение эквивалентных сетевых путей.

В unpaced echo DIRECT получил меньшие RTT и больший темп обмена. PROXY
в этом тесте близок до/после. Paced RTT имеет существенный разброс, в том
числе увеличение медианы run-p99 DIRECT; отсутствие регрессии всех хвостовых
задержек не доказано. Потребление одного Core-хоста изменилось неравномерно.
Предельная throughput/capacity, длительная устойчивость, минимальность ресурсов
и готовность всего продукта этими измерениями не установлены.

## Что сравнивалось

- Before: fork `driver` b3596272a8dc8898790b016d1e4c488c2fdc917d,
  Core SHA256 `37c1575ee688d5de0227b89b9c26257f1364828f4f6a44235ae6676ae8466b83`.
- After: `codex/tcp-direct-route` 340bdc839bed3c02d75dceb996cee68f39ecf045,
  Core SHA256 `ad514e88f8b7eb2bf2f63f94f7ad724b963a6898de69033839cf36e3a86ee08c`.
  Это отдельная ветка непосредственно от driver, без UDP packet-channel patch.
- Один установленный baseline SYS на физическом PB-SUT192.168.0.157:
  `3e5c3c709ee8c8800628f04b5550f3a82377deb264b045ab2f2ccbab3fd8fb4c`.
  Пакет драйвера не переустанавливался; service/devnode запускались на время тестов.
- Core загружался по абсолютному проверенному пути через ctypes в отдельном
  Python3.11 процессе на каждый run. GUI/CLI в этом benchmark не используются.
  Каждый run использует новый Core-хост и одну TCP-сессию.
- На один client exe: целевое правило DIRECT или PROXY на порт54122.
  Для DIRECT дополнительно PROXY на неиспользуемый порт54125 того же exe:
  смешанный набор правил включает приложение в watchlist и воспроизводит
  именно исправленный relay path. Приложения только с DIRECT обходят relay
  в kernel и данным исправлением не затрагиваются.
- В каждом наборе три повтора; before/after порядок меняется во втором повторе.
  Receiver/proxy/driver/options одинаковые. Локальный IPv4 loopback режим.

## RTT и echo

Использованы нативный Lab client SHA256
`d6973b8976418faf5633b457deacbdb1e340f43be3317be40b68d8da6d123d8c`,
`pb_net_endpoint.py` с TCP_NODELAY/BUFFERED log и controlled SOCKS5 host на
неизменённой asyncio-socks-server1.3.3. Только ignored copy Python launcher
адаптирована с asyncio.run(loop_factory=...) на Python3.11
asyncio.Runner(loop_factory=...); Selector loop сохранён. Исходники Lab и
продукта этим не менялись. Все версии используют один и тот же launcher.

Paced RTT:512-byte echo,256warmup+1024measured,1ms requested pause.
Unpaced echo:1200-byte echo,256warmup+2048measured,zero pause.
Один request in flight; полезный echo MiB/s считает payload в одном направлении
по измеряемому окну. Это темп последовательного echo с hash/JSON processing,
не maximum streaming throughput. RTT считает время до полного echo,
не connect time. Warmup и получение снимка сокета исключены из измеряемого окна.
В таблице — медианы трёх run-p50/run-p99, а не pooled percentile.

| Workload | Action | Build | RTT p50, ms | RTT p99, ms | Echo payload MiB/s |
|---|---|---|---:|---:|---:|
| rtt | DIRECT | before | 0.4529 | 0.5370 | 0.244 |
| rtt | DIRECT | after | 0.3456 | 0.9413 | 0.194 |
| echo | DIRECT | before | 0.2291 | 0.3123 | 3.499 |
| echo | DIRECT | after | 0.1323 | 0.2017 | 5.007 |
| rtt | PROXY | before | 0.6324 | 0.6802 | 0.242 |
| rtt | PROXY | after | 0.4523 | 0.5082 | 0.244 |
| echo | PROXY | before | 0.2287 | 0.3331 | 3.507 |
| echo | PROXY | after | 0.2267 | 0.3324 | 3.476 |

Run-p99 диапазоны paced DIRECT: before0.506–1.792ms, after0.372–0.944ms.
Медиана run-p99 выросла0.537→0.941ms; значения перекрываются и N=3.
Это наблюдение сохранено; оно не позволяет ни гарантировать отсутствие
регрессии хвоста, ни уверенно приписать её патчу. Аналогичный разброс есть
в before paced PROXY. Для unpaced DIRECT улучшение RTT повторилось во всех
трёх runs: p50 before0.229–0.231ms, after0.131–0.135ms.

Независимая сверка: **43 008/43 008** replies с matching sent/received size,
payload/response SHA256, response_count1, actual_result=pass, wsa_error0.
Из них after21 504 replies; измеряемых after18 432. В before DIRECT payload
корректен, но неверный маршрут помечен OBSERVED_WITH_BASELINE_ROUTE_DEFECT.

Маршрут проверен по accepted-redirect PID/destination/action, одному
Core-owned established socket ДО измеряемого окна, контролируемому
SOCKS TCP_CONNECTED count и receiver peer tuple с каждым payload hash.
After DIRECT — Core socket к54122 и ноль SOCKS connections. PROXY и before
DIRECT — Core socket к54123 плюс один matching controlled-proxy outbound.
Gate штатного Invoke-WfpLocalRouteProbe для DIRECT не менялся: его требование
исходного client port сохраняет INCONCLUSIVE для Core-relayed DIRECT.
Здесь используется отдельная явная проверка владельца сокета, а не снятие gate.

## Длительная передача данных и ресурсы

Штатные бинарные ctsTraffic/ctsTrafficReceiver2.0.3.9 из лаборатории,
SHA256 обоих `0548089e59c872306ce2c98e7163e2a717119756010cf64d3cb3da2854f632cf`.
24 runs: три повтора × push/pull × DIRECT/PROXY × before/after.
В каждом64MiB,64KiB ctsTraffic buffers,rate limit8MiB/s,one connection,verify:data.
Data-only профиль с `-shutdown:rude`, как в Lab TransferOnly:
обычное FIN/half-close завершение здесь не проверяется.

Все24 native client/receiver exits0, оба CSV Result=Succeeded,
ConnectionId совпадает, объёмы ровно64MiB в заданном направлении и0 в обратном.
Всего проверено **1 610 612 736 bytes (1.5GiB)**; after768MiB.
Каждый origin tuple соответствует наблюдаемому владельцу соединения;
для SOCKS проверены TCP_CONNECTED/FLOW_CLOSED id и byte count.
Эта независимая сверка выполнена после получения всех captures.

CPU/RAM/handles ниже относятся к **Python Core-хосту**, включая ctypes,
служебные потоки и sampler. Это не выделенный GUI/CLI и не полный kernel cost.
GetProcessTimes измеряет CPU-время, QueryProcessCycleTime — CPU cycles;
cycles/MiB — наблюдаемые циклы, без пересчёта в энергию или частоту CPU.
Core-host, proxy, receiver и generator учитывались раздельно, samples каждые100ms;
каждая роль имеет >=50 samples/run. CPU% нормирован на всю машину.
Core+proxy сумма включает лабораторный SOCKS-процесс и исключает receiver,
generator, DPC/interrupt cost. Для удалённого SOCKS это не локальный расход приложения.
Медианы трёх repeats; rate limited transfer поддержал примерно8MiB/s:
не доказательство предельной скорости.

| Action | Direction | Build | Transfer MiB/s | Core-host CPU%, whole machine | Core-host cycles/MiB, millions | Core-host private MiB | Core+proxy cycles/MiB, millions |
|---|---|---|---:|---:|---:|---:|---:|
| DIRECT | push | before | 8.095 | 0.193 | 8.259 | 14.54 | 82.104 |
| DIRECT | push | after | 8.100 | 0.337 | 10.873 | 14.41 | 12.353 |
| DIRECT | pull | before | 8.091 | 1.514 | 58.126 | 14.11 | 132.315 |
| DIRECT | pull | after | 8.100 | 0.193 | 10.643 | 14.06 | 12.104 |
| PROXY | push | before | 8.084 | 0.144 | 8.212 | 14.16 | 82.558 |
| PROXY | push | after | 8.084 | 0.265 | 8.275 | 14.33 | 85.879 |
| PROXY | pull | before | 8.079 | 1.606 | 59.141 | 14.17 | 132.918 |
| PROXY | pull | after | 8.089 | 1.682 | 62.280 | 14.35 | 137.580 |

DIRECT upload: Core-host cycles/MiB **+31.65%** (8.259M→10.873M), приём
**−81.69%** (58.126M→10.643M). Сумма Core-host+controlled SOCKS уменьшилась
примерно85%/91% соответственно, поскольку SOCKS перестал обслуживать DIRECT.
Это не означает равномерного уменьшения CPU самого Core.

PROXY upload Core-host cycles/MiB +0.76%, pull +5.31%; диапазоны трёх повторов
перекрываются. Скорость при заданном rate limit сохраняется; этот профиль
не позволяет оценить изменение максимальной throughput или минимальные ресурсы.
Private RAM Core-хоста около14MiB включает Python; Core-host handles peak
230–233 в этих отдельных runs. Длительные
утечки/reuse-capacity и потребление самого standalone-приложения не измерялись.
Короткие RTT/echo CPU% менее пригодны для сравнения из-за короткого окна и
крупных шагов process CPU time; их сырые значения сохранены в analysis JSON.

Размер Core DLL:216064→216576bytes, **+512bytes**. SYS/CLI/GUI/installer
в этой работе не изменялись/не пересобирались; размер полного дистрибутива
и объединённой TCP+UDP версии этим не установлен.

## Восстановление, evidence и история отказов подготовки

После обеих успешных серий: baseline SYS hash совпадает,
Stopped/Disabled/problem32, restored=true, forced_cleanup=[],
installation_attempted=false, все Core Stop=1. Remote wrapper COLLECTED,
identity_confirmed=true, cleanup_errors=[], client WinRM Stopped и TrustedHosts
восстановлены. BCD/trust/system proxy/power/ProgramFiles не менялись;
WinDbg не использовался. Product source/driver integration branch не менялись,
нового PR/merge нет.

Предыдущие captures сохранены:
- benchmarkr1: helper отказался запускаться на Python3.11 до трафика;
- benchmarkr2: DIRECT-only rules дали watched0, процесс шёл напрямую в kernel,
  поэтому route expectation отвергнут. Это ошибка подготовки сценария;
  данные r2 исключены из сравнения. Root cause подтверждён кодом watchlist,
  core.log и отсутствием SOCKS events. В r3 добавлен unused-port PROXY anchor;
- первый non-elevated запуск r3 остановился до контакта с PB-SUT, WinRM
  service access denied; client остался Stopped, TrustedHosts не менялся.
  Затем тот же ещё не исполнявшийся target trial запущен штатным RunAs.

Успешные evidence roots (ignored/private; не включены в Git):
- `artifacts/diagnostics/tcp-direct-benchmark-target-20261023-r3-elevated`
- `artifacts/diagnostics/tcp-direct-transfer-target-20261023-r1`

Preparations: `tcp-direct-benchmark-20261023-r3`, `tcp-direct-transfer-20261023-r1`.
Новые directories, без Resume/refreeze старых captures. Ledger hashes проверены
независимо после сбора (513 и646 files):
- `tcp-direct-benchmark-evidence-ledger-20261023-r3.json`, SHA256
  `bd26d2fc3de7895059e1fc141bf2a8d19a63e6c23ebb52c661afcd4713b62ef5`;
- `tcp-direct-transfer-evidence-ledger-20261023-r1.json`, SHA256
  `44afc6b8cc06a94504363c7907f84da290bf11eaf0c0e5b3b0061ae5e96a671a`.

Analysis JSON/scripts хранятся отдельно в artifacts/diagnostics:
`tcp-direct-benchmark-analysis-20261023-r3.json`,
`tcp-direct-transfer-analysis-20261023-r1.json`,
`analyze-tcp-direct-benchmark-r3.py`, `analyze-tcp-direct-transfer-r1.py`.
Их результаты — INDEPENDENTLY_VERIFIED; исходные Lab receipts не переименованы
в успешные и штатные gates не ослаблялись.

External network, IPv6 performance, multiple connections, peak throughput,
long soak, GUI/CLI resource isolation, normal FIN/half-close и объединённая
UDP-ветка в performance comparison не проверялись. Предыдущий функциональный
IPv4/IPv6 DIRECT/PROXY/BLOCK gate11/11 описан в
[TCP fix validation](TCP_DIRECT_FIX_VALIDATION_2026-10-23.md).
