# TCP DIRECT benchmark checkpoint — 2026-10-23

USER запросил лабораторный benchmark изменения TCP DIRECT.
Работа остановлена по правилу: usage primary used95%, remaining5%.
Новых прогонов/исследований после порога не начинать до доступного лимита.

Product unchanged: codex/tcp-direct-route commit340bdc839bed3c02d75dceb996cee68f39ecf045,
base driver b359627. Предыдущий correctness gate11/11 остаётся валиден;
нового подтверждённого performance comparison пока нет.

Подготовлен ignored bounded runner с нативным Lab client D6973B..., Lab
pb_net_endpoint.py и controlled TCP SOCKS helper (asyncio-socks-server1.3.3).
План: 3 alternating before/after repeats × DIRECT/PROXY × RTT/echo =24 runs.
RTT:1088 replies,64warmup,512bytes,1ms pause. Echo:2112 replies,64warmup,
1200bytes,zero pause,one inflight. Echo payload MiB/s НЕ capacity benchmark.
CPU/private/handles относятся к Python-host+Core, не изолированному CLI/kernel.
Before Core37c157..., afterad514e...; driver baseline3e5c3c... unchanged.

Fresh preparations/evidence:
- artifacts/diagnostics/tcp-direct-benchmark-20261023-r1
- artifacts/diagnostics/tcp-direct-benchmark-target-20261023-r1
- artifacts/diagnostics/tcp-direct-benchmark-20261023-r2
- artifacts/diagnostics/tcp-direct-benchmark-target-20261023-r2

r1 FAILED до трафика: controlled TCP proxy requiresPython>=3.12, portable
PB-SUT runtime3.11. В fresh r2 только ignored helper copy адаптирован:
asyncio.Runner(loop_factory=create_loop) вместо asyncio.run(loop_factory=...)
и version guard3.11. Исходники Lab/product не изменены.
r2 первый case1-rtt-1-before FAILED с ValueError:WRONG_ROUTE. По runner этот
этап достигается после проверки native exit/count/hash/payload; route gate
ожидает ровно один TCP_CONNECTED у proxy. Причина несовпадения пока НЕ исследована.
Нужно посмотреть core.log/proxy.jsonl/client.jsonl/receiver.jsonl этого case,
проверить фактический перехват/имя процесса и ожидание числа proxy событий,
не ослабляя evidence gates. Не считать failure доказательством нового дефекта Core.

Оба run-result: restored=true, SYS3e5c3c..., Stopped/Disabled/problem32,
forced_cleanup=[], installation_attempted=false. r2 Stop=1. Wrapper collect
results сохранены в target evidence. Ни package/trust/BCD/systemproxy, ни
ProgramFiles не менялись. После достижения5% runtime больше не запускался.
Frozen roots не изменять/Resume не делать; последующий trial только fresh r3.
Credential/wrapper references и минимальный TCP fix описаны в
TCP_DIRECT_FIX_VALIDATION_2026-10-23.md и предыдущем диагностическом handoff.

До завершения24 валидных runs не публиковать численный вывод о регрессии,
ускорении или ресурсах. Baseline DIRECT реально проксирует: даже успешные
цифры до/после DIRECT описывают разные пути, не равнозначные архитектуры.
