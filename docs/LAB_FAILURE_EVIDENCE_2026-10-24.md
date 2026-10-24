# Исправление недостатков диагностических данных лаборатории

Scope пользователя: продуктовые ошибки [зафиксированы отдельно](PRODUCT_FAILURES_DEFERRED_2026-10-24.md); исправить связанные с лабораторией проблемы. Исторические отчёты40 не переписывать и не переоценивать.

Preview41:

- TCP churn хранит первые64 обычных samples и независимо первые8 failed results, с флагом усечения. Поздняя ошибка больше не теряется. TCP errors содержат этап connect/auth, workload или origin evidence, errno/WinError без текста системной ошибки или credentials.
- DNS/QUIC source gate сохраняет первый expected/actual endpoint, фазу и счётчик несовпадений. Адресная проверка остаётся обязательной; данные пакетов не сохраняются.
- Обычный UDP прежде не проверял source endpoint. Теперь даже подписанный ответ с правильным payload, пришедший с неверного ip:port, даёт FAIL. Полученные payload-счётчики не подменяются; unexpected source считается отдельно. IPv6 flowinfo/scope tuple не принимается за другую длину endpoint.
- UDP invalid разделён на неверную подпись, run, flow, payload и malformed. Набор причин фиксирован; произвольные сетевые данные/исключения не попадают в reason keys. Размер evidence ограничен.

Не изменены product binaries/драйвер, allowlist, маршрутизация и правила изоляции.17 пропущенных внутренних нагрузок прошлого прогона — штатная остановка нагрузки после отказа, не ошибка оркестрации. Не выполнять нагрузку поверх неподтверждённого состояния ради формального охвата.

Проверено до упаковки:4 целевых regression tests, включая отказ TCP после64samples и настоящий loopback UDP с правильной подписью/правильным и подменённым source port;4 QUIC,7 encrypted DNS,3 SSH deadline/snapshot tests PASS. Новых WFP/WinDivert/полных нагрузочных прогонов не запускалось. Упаковка41/.NET publish успешны,1485SHA matched, controller admin5178/PID13864, active/busy=false.4 failure-evidence и3 deadline/snapshot tests повторно прошли на Python и исходниках упакованной41. History API сохранил прежний full50:35PASS/15FAIL, cleanup=true, unreadable0. Продуктовые проверки41 не запускались; результаты40 не являются проверкой41. Source7e40248 запушен.
