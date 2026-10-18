# Retrieve/query: разбор сохранённой пробы четырёх соединений

Run `pb-kd-retrieve-query-run-20261017-182317-8004fd9a` выполнен пользователем 17 октября, 18:23:17–18:23:35 UTC. Анализ выполнен 18 октября после выключения физического ПК. Повторного Run не было.

## Наблюдения

Четыре запрошенных соединения успешно передали по 512 KiB. Четыре исходных запроса Core вернули IPv4 context, API return/error 0/0. Native report оставлен исходным, со статусом DEBUGGER_PENDING; результаты kernel review сохранены отдельно.

Присланный console `8a6a40be-4b78-4a54-b250-3a7cea71f877` побайтно совпадает с сохранённым Desktop `Текстовый документ.txt`: SHA256 `6995f8fc4999e9dd6cb2ef85c0a5c255298f2a53915299c83d1cfe62845cfd6f`. В нём четыре RETRIEVE_RESULT и четыре QUERY_READ. Каждый endpoint имеет ровно одного кандидата retrieval и query. Во всех retrieval EAX=0, output_raw ненулевой и равен последующему query record.

| Core seq | Порт клиента | Endpoint | Полученный и прочитанный record |
| --- | ---: | --- | --- |
| 1 | 62218 | ffffc20a6002e010 | ffffc20a61a652a0 |
| 2 | 62219 | ffffc20a604e1c60 | ffffc20a6145b2a0 |
| 3 | 62217 | ffffc20a59fb7c60 | ffffc20a605d8900 |
| 4 | 62220 | ffffc20a5f480c70 | ffffc20a5fc96890 |

Порты проверены преобразованием raw network-order word и сравнением с native/Core. Kernel QUERY_READ PID/TID 0x3ed8/0x4b50 совпадают с Core 16088/19280. Последовательность четырёх неперекрывающихся CTXTIMING интервалов согласуется с console query order и портовой привязкой. Независимых kernel socket/seq/shared QPC нет: вывод условен на полноту сохранённого console, непрерывный lifetime не доказан.

В console initial 2/3/4d → active 2/3e,4d → восемь событий → manual Break → bd2/bd3 → final bl 2/3/4d → отдельный g. Не показано Memory access/Syntax/Bad register errors, actual UNREADABLE events отсутствуют. Это подтверждает исполнение наблюдавшихся успешных actions и продолжение VM между событиями; не проверяет ветку UNREADABLE и общую безопасность gc.

Wrapper вернулся, workload COMPLETED, receipt workers_stopped/driver_stop_observed=true. CLI forced_stop=false. After snapshot: служба Stopped, известных WFP objects не наблюдалось, visibility_complete=false. Полную системную очистку не утверждаем; отдельный CLI interception_cleanup_verified=false сохранён как есть.

Проверены SHA всех 8297 frozen files плана, включая runtime snapshot. Исходные capture files и console не изменились за время анализа. Приватный воспроизводимый audit: `artifacts/diagnostics/pb-kd-retrieve-query-four-review-20261018/review.py`, `review.json`, `saved-console.txt`; не добавлять в Git.

## Ограничения и следующий замер

Отказа в этой пробе нет. Retrieval EAX измерен непосредственно, но query kernel NTSTATUS не измерен: ID4 был отключён. Record creation, association, фактическая инструкция store и освобождение здесь не наблюдались. Один общий NBL address не доказывает один пакет или один lifetime. Причина исходных отказов и гипотеза влияния очереди остаются открытыми.

Предлагаемый следующий контракт: 4→64→256→4 (328), те же две активные точки 2 retrieval return +0xcaf / 3 query read +0x2c4, ID4 отключён. Это ещё не готовый и не запущенный комплект. Ожидание клиента 120 s, бюджет cohort 240 s и RAM gate 2 GiB — ориентиры прежнего bounded; пауза всей VM не имеет гарантированного wall-time предела. Ошибки connect 10061 учитывать отдельно от Core query 10022. Пропуски/дубли событий не считать доказательством bypass.

EAX≠0 у конкретного failed flow будет свидетельством неуспешного retrieval, а не доказательством причины более ранней потери. EAX0+nonnull output и поздний NULL сузят интервал до пути после retrieval; прямое выполнение store/lifetime всё ещё требует отдельного доказательства. Отсутствующий RETRIEVE_RESULT не разрешает выбрать одну из этих версий.

18 октября read-only boot evidence показывает новый Event12 record16566 / BootId113 / StartTime06:22:30.5Z вместо16348/112. Старые kits не запускать/не Resume/не refreeze. Нужны USER inventory и live code нового сеанса, затем отдельный профиль/комплект с новой boot binding; общее число активных точек не увеличивать.

Следующий USER шаг — подключить WinDbg к прежнему serial pipe, без загрузки stage и без be. Перед Break предупредить о паузе всей VM/Codex/RDP; команды вводить отдельно, g отдельно даже после ошибки. Сначала bl. Если есть активные или неизвестные точки, новый stage не загружать, прислать inventory. При пустом bl: .reload /s, .sympath C:\PB-KD-Symbols-20261016, .reload /f nt, .reload /f tcpip.sys, .expr, lmvm tcpip, dt nt!_ETHREAD Cid, u tcpip!WfpAleAuthorizeAccept L30, u tcpip!WfpAleAuthorizeAccept+0xcaf L8, u tcpip!WfpAleProcessSocketOption+0x2c4 L8; затем g отдельно. Повторный Run не выполнять до review и нового комплекта.
