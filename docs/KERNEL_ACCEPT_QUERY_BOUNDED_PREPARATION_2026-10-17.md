# Ограниченный accept/query комплект — 2026-10-17

Цель: на исходном отказе проверить состояние endpoint record в двух местах: общем join `WfpAleAuthorizeAccept+0xcbe` (ID2) и непосредственно перед чтением для исходного Core query `WfpAleProcessSocketOption+0x2c4` (ID3). QUERY_STATUS4 остаётся зарегистрированной и отключённой. Новых точек нет; stage повторно не загружать.

## Что добавляет пара точек

| Record при accept join | Record перед query | Допустимый вывод для однозначно связанного соединения |
|---|---|---|
| Ненулевой | NULL | Два наблюдения различаются; искать изменение между ними. Само освобождение/обнуление не наблюдалось. |
| NULL | NULL | Отсутствие видно уже на общем accept join; искать предыдущий путь получения/прикрепления. Join не доказывает выполненный store. |
| Ненулевой | Тот же ненулевой | В обеих точках значение совпадает. Непрерывность lifetime между ними не доказана. |
| Любой | Иной ненулевой указатель | Проверить изменение и привязку/lifetime; одной этой пары недостаточно для вывода о механизме. |

Одна точка query оставляла обе первые возможности открытыми. Две точки способны сузить место возникновения отсутствия record, но не гарантируют воспроизведения или установления причины. CREATE/RETRIEVE/FREE, все присваивания, TCPtuple/kernel socket/seq/sharedQPC не охвачены. status_esi не является retrieval NTSTATUS. Точка4 отключена: независимого kernel NTSTATUS этот профиль не даёт. NULL не исключён фильтром.

Под нагрузкой endpoint может повторно использоваться. Accept peer port должен совпасть с Core/native endpoint, последовательность query должна быть полной и неперекрывающейся по PID/TID/QPC, учитываются границы phase и lifetime. Если несколько accept/query кандидатов, пропуски console, UNREADABLE или неоднозначность — отметить ограничение и не объявлять flow доказанным по одному адресу endpoint. Нет измерения стоимости всех software hits; меньше напечатанных строк не гарантирует меньшие лаги.

## Контракт файлов

Новый метод `redirect-kd-accept-query-bounded-v1`, отдельные `Invoke-KdAcceptQueryBounded.ps1`, `Invoke-KdAcceptQueryBoundedWorkload.ps1`, `pb_prepare_kd_accept_query_bounded.py`, `pb_kd_accept_query_bounded_report.py`. Изменений продукта, сборок/установок и новых debugger actions нет. Предыдущие sources/kits/captures сохранены.

Профиль4→64→256→4 (328 попыток),512KiB/8s на соединение, ConnectEx/pending32, original listener/delay0, один исходный query. Тот же пинованный CLI/Core/driver. Существующий `KdQueryBoundedConnectionLoad.psm1` переиспользован без правок; его уровни64/256, RAMgate2GiB, clientwait120s/cohortbudget240s. Startup/hash/cleanup вне cohortbudget; остановленнаяVM не обеспечивает жёсткий walltime предел. Уровня640 нет. Native10061 с неустановленным endpoint учитывается отдельно, не как query-context failure.

Приготовление фиксирует прежнюю static/live/registration proof и новую four proof: reviewed4ACCEPT/4QUERY/nonzeroequalrecord, consoleSHA8ef953d0ce3801e3b34113fec76f5cd6d55520397e410da98b6d6b2417ff03a9, reviewSHAde6de15974214065425c5bdc4516b0382013ce1aa99a7fbb573374d0a621963d, все38 capture files скопированы и хешированы. Исторические false flags исходного candidate/registration profile не переписываются. Bootguard Event12/BootId16348/112 и mutex/lease/legacy/interrupted gates сохранены, включая обе accept/query серии.

## Проверки без runtime

PS5.1/7 parse новых scripts и вызов только Get-ConnectionLoadPreset прошли. PythonAST проверен. На адаптированной приватной копии старого328 capture новый reporter сохранил40nativefail/8uniquelycorrelatedquery10022/32unidentified10061 и статусCAPTURE_INCOMPLETE; единственная ошибка относится к32unidentified10061. Four-only capture отвергнут по фазам; неверная active-point policy отвергнута. Это synthetic file checks, не новый Run/тест продукта.16613 защищённых файлов проверены неизменными перед подготовкой.

Private audit `artifacts/diagnostics/pb-kd-accept-query-bounded-preparation-review-20261017/` хранит генератор, protected inputs, parser/preset verification, адаптированные fixtures/reports и Prepare console. В Git не добавлять.

## Свежий комплект готов

Windows PowerShell5.1 Prepare завершился exit0 и встроенным `KD_ACCEPT_QUERY_BOUNDED_FILES_VALIDATED`:8334 frozen files,8197 snapshot files. Повторный Inspect не выполнялся. После подготовки все16613 защищённых старых inputs неизменны.

Каталог: `C:\src\ProxyBridge-TestLab\artifacts\diagnostics\pb-kd-accept-query-bounded-preparation-20261017-082924-61fa8d38`.

PlanSHA256: `D7127D4863C2D202F1708C2B0ADA3E18AF0D6C7721607C4EBA33F7301534B46D`.

Полная инструкция для сохранения на физическом хосте: `C:\Users\LabAdmin\Desktop\PB-KD-Accept-Query-Bounded-20261017.txt`. Содержит warnings/recovery, проверку inventory2/3/4d, USERbe2/be3/bl/g, ожидаемые2e/3e/4d, Run с автоматическим SHAcompare/throw и тремя acknowledgement flags, финальныеbd2/bd3/bl/g даже при ошибке. Работать с закрытымGPT возможно; stage повторно не загружать. Инструкция подготовлена для одного Run после отдельного согласования, не является подтверждением запуска.

Product_started/traffic_generated/driver_installed/debugger_control/runtime_ready остаютсяfalse. Замораживание проверяет файлы и prerequisites, не runtime готовность. Исходники этого нового контракта зафиксированы в7909d7a; документация не входит в frozenfiles.

## Стоп-пункт

Разрешена файловая подготовка; USER Run328 ещё не согласован и не выполнялся. После завершения подготовки предоставить проверяемые path/planSHA и полную инструкцию для закрытогоGPT, затем согласовать один Run328. Перед каждым USER Break/enable предупредить об остановке всейVM/Codex/RDP; команды по одной/g отдельно даже при ошибке. Recovery заранее на физическом хосте:bd2,bd3,bd4,bl,g по одной. До согласования не Break/be/Run. После Run — bd2/bd3/bl/g,4остаётсяd; никакого автоматического повтора/увеличения нагрузки.
