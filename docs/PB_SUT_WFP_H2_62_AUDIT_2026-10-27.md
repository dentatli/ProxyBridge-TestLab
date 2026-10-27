# PB-SUT: WFP H2 на preview.62 — 27 октября 2026

Последний пользовательский прогон `20261027-131017-401aef43458d48109dc0710697f2a05b`, WFP driver4da324e, Core SHA256 `d442a5e6807f1d637c202e6d140a58ecff86bb095164a9d4e8ed49fa4770df4e`. PB-SUT app lab62/source2f6f0bb. Read-only аудит: новую нагрузку, перезапуски и изменения продукта не выполняли.

## Итог

**COMPLETE, ошибок нет.** Начало27октября13:10:34Z, завершение15:10:55Z (18:10:34–20:10:55 Екатеринбург). Запланированные7200с нагрузки выполнены, raw elapsed7204.422с с завершением. Обмен и маршрут подтверждены для всех212 завершённых работ; summary comparison_quality exchangePASS/routeCOMPLETE, error/failure_context пусты.

- Постоянный TCP:14400 подтверждённых обменов, TX=RX7372800байт, одна сессия, полная конечная сверка.
- Постоянный UDP:36000 отправлено/36000 получено, invalid/expired0, потерь нет, одна ассоциация.
- 96 bulk-окон и18 churn-окон успешны.
- HTTP,HTTPS,HTTP/2,SFTP,DNS-TCP,QUIC:по16 успешных окон. QUIC close подтверждён16/16, максимальное ожидание3.5с; граница последнего окна короче60с учитывается профилем, не означает незапущенный этап.
- DIRECT/BLOCK:116 серий×4=464/464 PASS. Независимо пересчитаны Core after-before deltas и origin receiver arrivals: DIRECT имеет событие и доставку, BLOCK событие и нулевую доставку; все health probes успешны, нет PROXY на этих каналах. PID14264 и ruleIDs3/4/5/6 постоянны. CoreStart/Stop1/1. Ложные ошибки callback-дедупликации из61 не повторились.
- Прежней остановки примерно через час нет. В завершённых работах нет control_recovery: чтение результата не потребовало записанного восстановления. Это подтверждает успешный повтор, но не устанавливает причину исторического RPC-отказа.

## Ресурсы и границы

6270 наблюдений процесса/ОС, unavailable0. Процесс Core host: handles91→82 (max126), threads12→7 (max19), private memory2.31→2.38MiB (max4.55MiB). Явного накопления этих ресурсов за этот прогон нет; единственный H2 не доказывает отсутствие всех утечек. CPU процесса mean0.392% всего ПК, Windows mean7.20%: это разные области измерения, не складывать. ETW ядра в soak отключён; стоимость WFP kernel и преимущество над WinDivert по этим значениям не выводить.

## Очистка и целостность

Attempt/product/localorigin/nativecleanup_verified=true, forced_stop=false. device_restore verified=true: problem22, ProxyBridgeDrv Stopped. App после прогона idle. Экспортированы9 файлов: ZIP SHA256 `e13efaba52e76edcba9c38386125153655ea150c2f943f0a9bd3cc2d015f9eae`. SHA всех файлов, raw/measurement hash, journal SHA/444 записи (116policy+212completed+116minute), console prefix SHA сверены; summary пересчитана, расхождений0. Console хранит ограниченный prefix4194084байт/truncated=true, не полный текст2ч; чтение и учёт продолжались, append-only stage journal полный.

Evidence только ignored: `artifacts/endurance-check/sut-h2-62-read-r1`, `sut-h2-62-export-r1/target-files/evidence`, `audit-h2-62.py/.log`. WinRM/TrustedHosts клиента восстановлены без ошибок. Исходные отчёты не изменялись.

Длительный WFP H2 в проверенной области принят. Это не доказательство покрытия всех видов трафика Windows или ресурсоёмкости ядра. Следующий шаг определяется пользователем; новых прогонов автоматически не запускать.
