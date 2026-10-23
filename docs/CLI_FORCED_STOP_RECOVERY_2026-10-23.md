# Почему preview.14 остановил комплексный прогон

Attempt20261023-150312-e2e4a8c8e2aa45c1a639230127030f40, WinDivert4.3.0,50NORMAL/LOW безsoak. Итог:2PASS (tcp-duplex,tcp-multistream),5FAIL,43SKIPPED. Guard действительно разрешил продолжение после4 обычных ошибок/крашей при свежем OFF и подписанном idle-origin. Новая политика по умолчанию работала.

Остановка на7-м loaded-rtt: CLI не завершился в5s; native console host завершил только принадлежащую ему job. Native retained child handle дал exit11, host exit11, path_verified=true. Но Product.close ошибочно возвращал forced_stop=false и exit_verified=false, потому что exit proof требовал host exit10 (штатный Ctrl+C). Поэтому finally не смог восстановить WinDivert, SYS остался Running при отсутствии product processes; очередь корректно остановилась с TRAFFIC_CLEANUP_NOT_VERIFIED. CLI hang — продуктовый результат, неверная классификация exit/cleanup — ошибка лаборатории.

## Восстановление

Вне исходных frozen/evidence файлов создан sidecar %LOCALAPPDATA%/ProxyBridge-TestLab/traffic-lab/<attempt>/verified-forced-exit-recovery: исходный native exit/path proof и hash оригинального report. Точная связанная WinDivert служба остановлена штатным gate с проверкой bound SYS SHA256, нулевых WinDivert handles, отсутствия других product processes/известных WFP objects. Gate exit0: off_verified=true, known_driver_names_absent=true, product_process_count=0. ProxyBridgeDrv остался Stopped/Manual с прежним63be0eb path. Оригинальные FAIL/UNVERIFIED не переписаны; позднее восстановление не превращает попытку вPASS.

## Исправление b154c7e

- Native exit proof отделён от успешного shutdown: retained handle с фактическим exit!=STILL_ACTIVE и проверенным path позволяет убрать только свою driver service и после natural crash/forced job exit.
- Host11 корректно отмечается forced_stop=true. Штатный cleanup по-прежнему требует host10/child0/no forced; forced case не может статьPASS.
- Queue guard после известной ошибки допускает переход и после forced exit, только если native exit/path/capture/retention подтверждены, final cleanup/OFF прошли, runtime identities не изменились, затем повторно пройдены fresh OFF и подписанный idle-origin. Unknown/system errors, отмена, незавершённые процессы, неподтверждённое восстановление/файлы/получатель останавливают очередь.
- UI RU/EN поясняет forced close, включая старые отчёты с native host11. Raw metadata/история не изменены.

Проверки:16 lifecycle/guard checks, отдельная классификация host-error/natural child exit, реальные native host/retained-process handles на инертной программе, игнорирующей Ctrl+C (child11/host11, forced=true, exit_verified=true, cleanup=false), JS syntax. Инертный helper не открывал сеть и не загружал SYS. Новых tracked tests или сценариев нет. Пакетpreview.15 изb154c7e:1466 SHA256 verified, admin launcher PASS, UI forced explanation проверено. Продукт не менялся, SYS/BCD/trust/signing не переустанавливались.

## Продолжение существующей проверки

На preview.15 запущен новый attempt20261023-152424-119d732145034178beb882f95ebfe10f:44NORMAL/LOW, начиная с loaded-rtt, затем43 ранее пропущенных; первых6 не повторяем. API ContinueAfterFailure не передавался явно, подтверждён default=true. Это новая попытка, а не Resume/переписывание старой. Идентичность/условия каждого запуска сохраняются отдельно; не объединять метрики как один непрерывный benchmark. Итог ещё ожидается. Исходный набор50 по-прежнему сохранён.

Private evidence: artifacts/local-completion/official430-all50-preview14-final.json; forced-close-verification/result.json; remaining44-normal-low.json; official430-remaining44-preview15-start.json. Чат не нужен для дальнейшего исполнения, результаты сохраняются приложением.
