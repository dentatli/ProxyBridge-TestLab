# Bounded accept/query: восемь NULL уже на accept join — 2026-10-17

В новом прогоне для восьми отказавших исходных запросов Core найдено по одному предшествующему ACCEPT_STATE с тем же endpoint и соответствующим native/Core peer port. В обоих наблюдениях record равен NULL. Это сужает поиск к пути до общего accept join внутри Windows. Исчезновение только после этой точки перед Core query не объясняет эти восемь наблюдений. Причина первоначального отсутствия record ещё не установлена.

## Источники и проверка целостности

Run `artifacts/diagnostics/pb-kd-accept-query-bounded-run-20261017-083559-98e4358e`, USER console attachment `a90d15fe-181b-49fd-8c98-f3216d18c8e5/Вставленный текст.txt`,117155 bytes,SHA256 `99c7926791ae6c06c71adcdb1285a0a49bb6f055a9889644649c6e1542ebeeab`. Копия console сохранена в отдельном private audit. Проверены56 sourceSHA native report,8334 frozen files и planSHA `D7127D4863C2D202F1708C2B0ADA3E18AF0D6C7721607C4EBA33F7301534B46D`.62 файла Run и исходный console неизменны после анализа. Исходные reports/manifests не переписаны.

Inventory: только2/3/4d → USERbe2/be3 → 2e/3e/4d → отдельныйg; после пробы USERbd2/bd3 → 2/3/4d → отдельныйg. Адреса/actions неизменны между четырьмя inventories. Показанных Memory access error/Syntax error/actual UNREADABLE нет. Это не проверка непосещённой ветви UNREADABLE или общей безопасности gc.

## Результат workload

| Фаза | Попытки | Успех | Query10022 | Native10061 без идентифицированного endpoint |
|---|---:|---:|---:|---:|
| baseline | 4 | 4 | 0 | 0 |
| load-64 | 64 | 64 | 0 | 0 |
| load-256 | 256 | 232 | 8 | 16 |
| recovery | 4 | 4 | 0 | 0 |
| Всего | 328 | 304 | 8 | 16 |

Core выполнил312 исходных queries, последовательности1..312, PID12844/TID16760; kernel QUERY_READ имеет тот же PID/TID, IOCTL980000dd и312 событий. CTXTIMING интервалы не перекрываются. По порядку и этим признакам восемь NULL query соответствуют seq301..308/API10022;304 остальных QUERY_READ имеют ненулевой record и соответствуют успешным запросам.

Native ошибки этих восьми — ErrorNotAllDataTransferred. Ещё16native10061 не получают идентифицированной Core/query пары и не считаются redirect-context failure. Предыдущее8/32 и новое8/16 — разные прогоны, не одни и те же соединения. Снижение числа10061 не доказывает улучшение продукта.

Workload и четыре phase receipts завершены; workers_stopped=true, CLI graceful_stop/post_stop_verified=true, forced_stop=false, ошибок cleanup нет. Сохранённый after snapshot: serviceStopped, известных WFP объектов не наблюдалось, productprocessesempty; полная видимость interception не доказана. Wrapper FAILED после native report: `CONNECTION_REDIRECT_DIAGNOSTIC_CAPTURE_INCOMPLETE`, sole report error `load-256: UNIDENTIFIED_NATIVE_CONNECT_FAILURE_10061: 16`. Это штатное отклонение полноты доказательств, не новый сбой логгера и не crash продукта.

Wrapper08:35:59.633–08:39:00.833UTC (13:35:59–13:39:00 местного времени),181.200s. Phase elapsed≈8.294/36.494/115.841/7.986s. Query elapsed122.0773–413.9951ms, mean130.5727ms. Эти измерения включают KD и другие задержки; не оценка чистой скорости/ёмкости. Load256 близок к120s clientwait, поэтому расширять нагрузку без нового обоснования не нужно.

## Восемь конкретных пар

| Core seq | Peer port | Строка ACCEPT_STATE | Строка QUERY_READ | Record accept → query |
|---|---:|---:|---:|---|
| 301 | 50017 | 454 | 622 | NULL → NULL |
| 302 | 50019 | 455 | 623 | NULL → NULL |
| 303 | 50022 | 456 | 624 | NULL → NULL |
| 304 | 50027 | 457 | 625 | NULL → NULL |
| 305 | 50025 | 458 | 626 | NULL → NULL |
| 306 | 50028 | 459 | 627 | NULL → NULL |
| 307 | 50030 | 460 | 628 | NULL → NULL |
| 308 | 50037 | 461 | 629 | NULL → NULL |

У каждого из восьми endpoint ровно одно ACCEPT_STATE и одно QUERY_READ во всём присланном console; у peer port ровно один предшествующий accept. Localrawda84 соответствуетCore34010. Peer port независимо сопоставлен с native CSV и Core; client-launch подтверждает PID7108 дляload256. Kernel→Core seq binding зависит от полноты USER console и порядка запросов, независимого kernel socket/seq/sharedQPC нет. Endpoint lifetime между событиями не наблюдался полностью.

Все восемь NULL accept идут подряд, с одинаковыми thread/scope и адресом NBL `ffffc20a6009fc30`, currentPID0xb1c (2844). Это не native PID7108 и не Core PID12844. Current PID в kernel accept — контекст выполнения, его нельзя использовать как идентификатор владельца соединения. Совпадение адреса NBL не доказывает один пакет или один живой объект: reuse/разбор агрегата/другие варианты здесь не различены.

## Покрытие ограничено сильнее, чем разность310−312

Прислано310ACCEPT_STATE и312QUERY_READ. После проверки по endpoint/port/order:

- 300 queries имеют ровно одну accept пару с тем же record, включая все8NULL failures;292 из них успешны.
- Ещё5 успешных seq6/69/167/232/244 имеют по два accept кандидата с одинаковым record и NBL. Значения согласованы с query, но нельзя объявлять эти пути однократными.
- У7 успешных seq71/102/161/228/263/264/273 нет accept кандидата ни по порту, ни по endpoint до query. Причина отсутствия не установлена. Это не доказательство пропуска конкретной ветви Windows; возможны также ограничения регистрации/доставки/копирования вывода.
- Все310 accept событий относятся к этим кандидатам, чужих отобранных портов не найдено.293 уникальных accept endpoint и300 query endpoint: повторное использование адресов нельзя игнорировать.

Два счётчика310/312 сами по себе скрывали пять повторов и семь отсутствующих событий. Нельзя объявлять весь logger полным или трактовать отсутствие события как отсутствие Windows record. Для восьми отказов обе точки присутствуют и перечисленные неоднозначности не обнаружены.

## Что говорит код и чего он не говорит

Повторно офлайн сопоставлены19 инструкций gate/retrieve/store/join с текущим `tcpip.sys` SHA `b0683bd7ed0f309e63b4e6e71675d8f04cfb0ea5533c3f5e8a13c6daca3b595a`. PE import IAT RVA24de00 разрешается в `fwpkclnt.sys!FwpsNetBufferListRetrieveContext0`. На обычном пути:

1. RVA15649 проверяет flags bit24, затем ESI. Если бит установлен иESI=0, код вызывает получение context key5 с output `[rbp-28h]`.
2. RVA1567b (`WfpAleAuthorizeAccept+0xcaf`) проверяет EAX — результат вызова. При ненулевом результате переходит кjoin без store.
3. При EAX=0 загружает output и пишет в `[rdi+1c0]` наRVA15683.
4. Наш ID2 расположен наRVA1568a/+cbe, общем join. Его `status_esi` не является EAX результата retrieval.

У всех310accept, включая8NULL, flags=09001641 (bit24 установлен), ESI=0. Это согласуется с ветвью, где retrieval должен выполняться, но трасса не записала его EAX/output и не является прямым наблюдением выбранного входа вjoin. Поэтому ещё нельзя объявить retrieval C0000225, success+NULL, конкретный bypass, раннее освобождение или дефект Windows/драйвера доказанными.

QUERY_STATUS4 отключена. NTSTATUS нового query также не измерен: `ntstatus_observed=false` правильно. Прежнее отдельное наблюдение C0000225 и известная NULL-ветвь query поддерживают гипотезу того же механизма, но не заменяют измерение NTSTATUS в этом Run.

Очередь/повторная передача остаются обоснованной рабочей гипотезой с учётом прежних traces и результата backlog1024. Новый результат переносит проверку к получению/прикреплению до accept join; он не доказывает размер очереди или виновника. Возможность, что record сначала был создан, а затем потерян ещё доjoin, не исключена. Увеличение очереди пока только устраняет условия воспроизведения в прежних опытах.

## Следующий минимальный шаг и стоп-пункт

Текущий согласованный Run завершён; повтор/увеличение нагрузки не разрешены. Все2/3/4d и отдельныйg подтверждены. Сейчас только офлайн подготовка следующего наблюдения, без изменения продукта.

Рекомендация: заменить ID2 (accept join) точкой на возврате retrieval `tcpip!WfpAleAuthorizeAccept+0xcaf`, сохранив ID3QUERY_READ и отключённую4. Это по-прежнему две активные точки. Записать EAX, output `[rbp-28h]`, endpoint, local/peer ports и NBL pointer; фильтрCore34010 и проверки доступности до всех чтений. EAX ненулевой даст прямой результат получения; EAX0+NULLoutput выявит иной путь; EAX0+nonzerooutput и последующийNULLquery локализует изменение после возврата. Если retrieval event отсутствует, считать capture неполным, а не объявлять bypass доказанным.

Не выводить EAX из нынешнегоjoin как универсальный status: на успешном пути RAX уже заменён output pointer. Предыдущий USER live осмотр подтверждал байты `85c0` по+0xcaf; это не новое runtime подтверждение и не разрешение установки. Новый action/profile требует собственного disabled review и короткой пробы перед нагрузкой. Старый frozen328kit не менять/не переиспользовать для нового профиля; stage поверх существующей2 не загружать. Сначала подготовить конкретный вариант замены и восстановления, затем отдельно согласовать USER debugger/runtime шаги. Перед каждымBreak/enable предупреждать об остановке всейVM/Codex/RDP; команды по одной/g отдельно даже при ошибке.

Private audit `artifacts/diagnostics/pb-kd-accept-query-bounded-result-review-20261017/`: неизменённая копия console, protected-inputs, events/query-pairs/failed-pairs/missing-accept/unmatched-accept, review.json, static-next-step.json и scripts. CSV в этом Run имеет UTF16 BOM; offline reader исправлен для определения BOM. Ошибка первого чтения CSV относилась только к анализатору и не запускала продукт. Приватные captures/комплекты вGit не добавлять.
