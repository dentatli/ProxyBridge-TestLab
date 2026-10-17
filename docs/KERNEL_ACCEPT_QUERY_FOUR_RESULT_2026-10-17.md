# Результат accept/query пробы на четырёх соединениях — 2026-10-17

USER выполнил единственный согласованный Run комплектом `pb-kd-accept-query-preparation-20261017-081124-5b6ae9b8`, planSHA `40F9DB349FF8DD13FC74A43AE10D3E16252956882F6D42787C684C45702FD766`. Каталог результата: `artifacts/diagnostics/pb-kd-accept-query-run-20261017-082243-9c4296cc`. Контроллер завершился 08:22:43.590–08:23:00.588 UTC (13:22:43–13:23:00 местного времени); ошибка пуста. Агент runtime не запускал.

## Наблюдения

USER console `cf7fe9db-8259-4196-98bc-e1b01ee16bd3/Вставленный текст.txt`, 10466 bytes, SHA256 `8ef953d0ce3801e3b34113fec76f5cd6d55520397e410da98b6d6b2417ff03a9`: исходные2/3/4d → be2/be3 → 2e/3e/4d → отдельныйg → четыре ACCEPT_STATE и четыре QUERY_READ → USER Break → bd2/bd3 → итоговые2/3/4d → отдельныйg. Адреса/actions во всех четырёх inventories совпадают. Показанных ошибок чтения/синтаксиса и actual UNREADABLE нет.

Все четыре ACCEPT_STATE имеют local_raw=da84 (34010), PID=0x2f34 (12084, native client). QUERY_READ: PID=0x1b80 (7040, Core), TID=0x2fe8 (12264). В каждом наборе четыре уникальных endpoint; каждое событие приёма предшествует запросу соответствующего endpoint. Четыре Core query идут последовательно, без перекрытия интервалов CTXTIMING.

| Core seq | Socket | Native/Core peer port | Endpoint | Record при приёме и перед query | Query elapsed, ms |
|---|---|---|---|---|---|
| 1 | 520 | 53006 | ffffc20a5f32c960 | ffffc20a6175c7e0 | 207.6849 |
| 2 | 516 | 53005 | ffffc20a61640910 | ffffc20a60116da0 | 128.6358 |
| 3 | 536 | 53004 | ffffc20a63ea4c90 | ffffc20a60302050 | 130.9028 |
| 4 | 556 | 53007 | ffffc20a60d69b20 | ffffc20a60233500 | 133.0679 |

Привязка основана на уникальном endpoint accept→query, PID/TID и порядке неперекрывающихся Core queries, совпадении swapped peer_raw с Core peer_port и native LocalAddress. Native/receiver CSV дополнительно совпадают по ConnectionId: четыре Succeeded, по524288 bytes отправлено/получено. Owned-socket-snapshot содержит отдельное исходящее Core→SOCKS плечо; его порты53008/53009/53011/53013 не подменяют native peer ports53004..53007.

Все исходные query: api_return=0/api_error=0/bytes=32, complete IPv4 context, ctx_pid12084. Native failure/10022 нет. Query elapsed включает влияние KD; phase elapsed8185.5374ms, весь wrapper≈16997.8591ms. Эти величины не являются измерением собственной задержки TCP или доказательством улучшения производительности.

CLI graceful_stop/post_stop_verified=true, forced_stop=false, capturecomplete=true; workload COMPLETED/workers_stopped=true. Сохранённый after snapshot: serviceStopped, известных WFP объектов не наблюдалось, productprocessesempty. Полная видимость interception и выгрузка всех механизмов этим не доказаны.

## Что установлено и ограничения

На этих четырёх успешных путях выполнены реальные чтения нового ACCEPT_STATE и QUERY_READ, отбор дал ожидаемые четыре порта; record в двух наблюдениях одинаков и ненулевой. Связь с четырьмя Core/native соединениями согласуется со всеми перечисленными признаками. Проба не показывает отсутствующий record и не устанавливает механизм исходного отказа.

Независимого kernel socket/seq/sharedQPC нет; связка seq зависит от полноты USER console и последовательности Core queries. Между точками не наблюдаются все записи/освобождения/reuse endpoint, поэтому непрерывное существование record не доказано. Общий accept join не доказывает выполненный store. status_esi=0 — сырое ESI, не retrieval NTSTATUS. QUERY_STATUS4 отключена: kernel NTSTATUS в этой пробе не измерен. Общая безопасность gc/ветки UNREADABLE и полное покрытие фильтра не доказаны. Количество программных breakpoint hits вне печати не измерено.

Исходные runtime отчёты сохранены без переписывания: `KD_ACCEPT_QUERY_NATIVE_EVIDENCE_CONFIRMED_DEBUGGER_PENDING` отражает native-only reporter. Отдельный offline review: `ACCEPT_QUERY_FOUR_OBSERVED_PAIRS_REVIEWED`. Private audit `artifacts/diagnostics/pb-kd-accept-query-result-review-20261017/`: копия console, review.json, protected-capture-inputs.json. Все38 файлов capture неизменны после анализа; sourceSHA из native report проверены отдельно. Приватные материалы не добавлять в Git.

## Следующий стоп-пункт

Четырёхсоединительная проверка завершена; повторять её автоматически не нужно. Точки2/3/4 отключены, отдельныйg показан. Далее допустима файловая подготовка нового ограниченного accept/query комплекта с теми же двумя активными точками2/3 и отключённой4. Предлагаемый профиль4→64→256→4 (328) достигает фазы прежних восьми NULL-query failures; прогон640 не нужен на этом шаге. Это новый контракт, существующий four-only kit для него не подходит и не изменяется.

Для bounded результата отдельно учитывать native10061 и возможную неоднозначность endpoint/order binding; не считать их redirect-context failures и не обещать полноту. При исходном сбое сравнить record в двух точках для конкретной проверенной пары. Ненулевой→NULL сузит интервал изменения; NULL→NULL укажет, что отсутствие уже видно на общем accept join, но само по себе не докажет причину. Runtime нового профиля требует отдельного согласования USER после файловой подготовки; сейчас не согласован, не выполнять Break/be/Run. Продукт не менять.
