# Следующий замер: возврат retrieval и исходный query, 328 соединений

Основание — [четыре успешные retrieval/query пары](KERNEL_RETRIEVE_QUERY_FOUR_RESULT_2026-10-18.md) и ранее наблюдённые восемь отказов с NULL уже на accept join. Цель — измерить EAX и output_raw непосредственно после retrieval у конкретного отказавшего соединения и сопоставить с query record. Причина до этого измерения не установлена.

## Текущий сеанс и регистрация

После выключения физического ПК новая загрузка VM: Event12 record16566 / Prefetch BootId113 / StartTime2026-10-18T06:22:30.5Z. USER показал пустой bl и отдельный g. Live console69ef2137 SHA277062ca5cfefddb0a283b0efd904b1fadb50f1602acd27560f059c78538bb73 подтверждает MASM, ETHREAD.Cid508 и прежний tcpip timestampD26770CA/checksum355D78/size35A000. Новая базаfffff8026a740000; проверены16critical instruction byte ranges и frame/stack-save признаки. Это выбранные участки, не побайтное покрытие всего модуля.

Затем USER отдельно зарегистрировал bp2+0xcaf/bd2 и bp3+0x2c4/bd3. В показанных bl/.bpcmds только2/3d, точные прежние actions и новые адресаfffff8026a75567b/fffff8026a86157c, затем отдельныйg. ID4 отсутствует. Ошибок регистрации не показано. Review опирается на текст сообщения пользователя; отдельного raw console attachment этой регистрации нет. Приватный registration-review честно помечен source_kind=review_of_user_chat_paste_not_raw_console_file. Исполнение actions в новом сеансе ещё не наблюдалось; их прежняя four-проверка остаётся ограниченным свидетельством успешного пути.

Новый профиль `scripts/debugger/pb-kd-retrieve-query-registered-20261018.json`: registered/active=[2,3], inactive=[]. Старые stage/профили/комплекты не менялись и не загружались. Нового executable stage/ZIP нет: использованы отдельные USER команды. Минимум две активные точки не устраняет остановки на прочих системных вызовах до исполнения фильтра.

## Контракт

Метод redirect-kd-retrieve-query-bounded-v1. Фазы4→64→256→4,328 соединений,512KiB/соединение,8s hold,ConnectEx/pending32,оригинальный listener и один исходный query,delay0. Точка2 — retrieval return+0xcaf(EAX/output_raw/порты/endpoint/NBL), точка3 — query read+0x2c4(record/CID). Статус самого query ядром не измеряется, QUERY_STATUS не зарегистрирован. Reporter native-only/kernelpending; EAX из console разбирается отдельно. Не приписывать ему C0000225 из других запусков.

Ожидание клиента120s/cohort budget240s,RAM gate2GiB; startup/hash/cleanup вне cohort budget. Это не гарантированный wall-time предел при остановленной VM и не тест скорости/ёмкости. Нагрузка640 не входит. Ошибки10061 отдельно, не включать их в контекстные10022; при неполном capture не выдавать PASS.

Новые отдельные wrapper/workload/preparer/reporter (source commit b48dfdd), shared bounded/boot модули неизменны. Сохранены mutex/lease, legacy/interrupted gates для старых и новых серий, пинованные CLI/Core/driver, component/file SHA и boot guard. Run требует RetrieveQueryProfileReviewed/DebuggerLoggerEnabled/BoundedLoadReviewed. Автоматического управления WinDbg, установки драйвера, build или product patch нет.

## Файловые проверки

PS7 parse и PS5.1 parse/pure preset прошли; первая попытка запуска отдельного PS5 проверочного файла без process ExecutionPolicy Bypass была отклонена политикой и не исполнила файл. Повтор с явно указанным process Bypass прошёл, системная политика не менялась. Python AST прошёл. На адаптированной приватной копии прошлого bounded capture reporter сохранил24native failures=8Core10022+16unidentified10061 и статус CAPTURE_INCOMPLETE. Чужой профиль с зарегистрированной4 и four-only фазы отвергнуты. Это проверки кода на сохранённых файлах, не новый Run.

28 старых source/module файлов проверены неизменными. Preparer отдельно сверяет и копирует four capture inputs, новый live console/review, registration review, профиль и four review; runtime snapshot изолирован. Старый four report не переписан. Приватный audit `artifacts/diagnostics/pb-kd-retrieve-query-bounded-review-20261018` не добавлять в Git.

## Интерпретация будущего результата

EAX≠0 на uniquely bound failed flow докажет неуспех retrieval в этой точке; output_raw при этом не трактовать как валидный результат. Это не объяснит, почему retrieval неуспешен. EAX0/nonnull output и поздний query NULL сузят интервал после retrieval, но не докажут фактический store/свободный lifetime. Отсутствие/дубли retrieval или неоднозначная привязка означают incomplete evidence; возможный gate bypass не объявлять доказанным по отсутствию строки. Ports/endpoint/order/PID/TID согласуются лишь при проверенной полноте console, без независимого kernel socket/seq/shared QPC. Непрерывный create/associate/store/free lifetime и причина исходного сбоя остаются вне полного покрытия.

## Стоп-пункт подготовки

WindowsPS5.1 Prepare завершён exit0 со встроенным FILES_VALIDATED:8330frozen files/8197runtime files. Отдельный повтор Inspect не выполнялся. Новый комплект `artifacts/diagnostics/pb-kd-retrieve-query-bounded-preparation-20261018-064359-6cb715b3`, SHA256 runtime-plan.json `D9B8DBA66645527FB5D4CB9A191651687CF8AC27BA8B7E8E66F3896F73518200`. После Prepare28oldsourceSHA снова совпали. Ни продукта, ни трафика, ни установки/управления WinDbg агент не выполнял.

Полный порядок одного USER Run с закрытым GPT сохранён на Desktop `PB-KD-Retrieve-Query-Bounded-20261018.txt`: auto SHA compare/throw, RetrieveQueryProfileReviewed/DebuggerLoggerEnabled/BoundedLoadReviewed. Последний USER inventory2/3d,g; до запуска только USER предупреждённый Break, bl2/3d, отдельныеbe2/be3/bl/g; после результата или ошибки bd2/bd3/bl/g отдельно. Перед каждым Break/enable предупреждать: пауза всей VM, включая Codex/RDP; recovery заранее на физическом ПК. При любой ошибке debugger — recovery, не Run. Stage не reload. Новая перезагрузка требует нового review/kit, старый не Resume/refreeze. После одного Run сохранить весь console/PS/result directory и не повторять до разбора. Готовность файлов не подтверждает runtime coverage или причину исходного сбоя.
