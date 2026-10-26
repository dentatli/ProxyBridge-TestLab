# «На этом ПК» — checkpoint 26 октября 2026

Лаборатория **preview.53**, source `cdd9e5034f0a0e546f39dcad7407b559a989e1b7`, запущена после выключения машины: admin **http://127.0.0.1:5178**, PID12212. Package `C:/src/ProxyBridge-TestLab/artifacts/releases/ProxyBridge-TestLab-0.3.0-local-preview.53-win-x64`. UI «Результаты» открыт; busy=false, ProxyBridgeDrv Stopped, worker/origin/Core отсутствуют, stderr пуст. Новую сетевую нагрузку не запускали.

## Последние пользовательские полные прогоны

[Полный разбор и границы сравнения](FULL_RUN_COMPARABILITY_2026-10-26.md).
- WinDivert4.3: `20261025-160707-5e2eaa8c397e4115bb8715943f2873db`, **33PASS/11FAIL**.
- WFP4da: `20261025-164617-d189642ae3a143cd91f4e742b2fe0500`, **43PASS/1UNVERIFIED**; 128UDPflows: 2716/383945 непокрытых пакетов (0.7074%), все flow loss≤1%, темпMET, received fingerprints совпали, strict accountingPARTIAL. Причина потери не локализована.
- 50→44 у обоих; **44 пары matching conditions**, 33PASS/PASS; **26 пар** проходят quality/rate/CPU guard для рейтинга. 92raw SHA совпали, recompute stage/report quality и workload_resources — 0 расхождений. Cleanup product/local/native=true у обоих, capture complete, forced_stop=false. Raw и отчёты не изменены.
- WinDivert UDP flow mismatch при достигнутом темпе, HTTP3/QUIC/DNSUDP и связанные mixed/stability failures сохраняются. Не объявлять установленную корневую причину продукта.
- Оба SFTP ниже100/s; WinDivert loaded probe51.93/s; WFP bulk/loaded/mixed/stability CPU≈98–100%, UDP stability иногда57–81/s. Функциональный PASS не означает темпMET или maximumcapacity. Низкий общий CPU не исключает single-core/другой bottleneck. Все ресурсы клиента — process, **kernel WFP measurement отложен пользователем**.

## Реализовано и уже проверено

[Методика preview.53, source и проверки](COMPARISON_QUALITY_2026-10-25.md). Exchange/route/rate/windows/CPU quality раздельны; phase resources, CPUcost, signed memory безwinner/%; fixedprobe100/s, UDPabsolute deadline bounded4slots. Strict route/capture/cleanup не ослаблены. 51ID/10групп, saved suites и archive сохранены. Полные53 данные подтвердили guards; код в этом анализе не менялся.

Не повторять без новых входов:35nativecontractPASS, controller7protocol+5schedulerPASS, actualJS88historicalrender/RUEN/ranking/PASS, package1685SHA matched; финальная matched3×2SHORT88.72s WFP3PASS/WinTCP+HTTPS PASS/UDPFAIL, cleanup/Core1/1, allrateMET. Evidence `artifacts/engine-migration/quality53-admission.json`, `matched-smoke-1792943755467427800.json`. Ранние fullpreview50 [отдельно](FULL_RUN_COMPARABILITY_2026-10-25.md); не смешивать с53 из-за методики.

## Границы и продолжение

Запрос анализа завершён. Продуктовую причину отказов и kernel attribution разбирать отдельно. Для следующего улучшения равной нагрузки loaded RTT/stability нужен ограниченный одинаковый фон с запасом стенда; не запускать новый full/HIGH/soak автоматически. Текущие результаты годятся для функционального и ограниченного численного сравнения, не полного ранжирования архитектур.

Worktree `C:/Users/LabAdmin/.codex/worktrees/testlab-development/ProxyBridge-TestLab`, branch `codex/development-functional-completion`, согласованнаябазаd5b51f3 сохранена. Main `C:/src/ProxyBridge-TestLab`, branch `codex/checkpoint-20261007`: чужиеhandoffchange/KernelReadCapture.cs не трогать/не читать; ветки вслепую не сливать. Commit/push безforce, privateartifacts неGit. Последние лимиты primary3%used/weekly31%used; ≤5%remaining — recoverable checkpoint и стоп.

Справки: [движокC#](CSHARP_TRANSPORT_ENGINE_2026-10-25.md), [этапы](OBJECTIVE_RESULTS_2026-10-25.md), [таблица](COMPARISON_TABLE_2026-10-24.md). История — свидетельства, не очередь действий.
