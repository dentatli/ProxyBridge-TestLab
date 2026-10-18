# Проверка драйвера ProxyBridge перед дальнейшими точками

USER уточнил, не находится ли причина в WFP-драйвере. Приоритет следующего шага изменён: перед сравнением bp/ba проверить, что сам драйвер передаёт WFP. Аппаратный comparator не подготовлен и не зарегистрирован. Продукт, driver installation, BCD и старые диагностические материалы не менялись.

## Какая версия рассмотрена

Диагностические планы используют ProxyBridgeDrv.sys SHA256 `3cd79cfc2a9ec6e45a11b2c225d11cb18c504fec3535e3ef1cb730e0e7732c9e`. Файл и base build receipt `9f429a1326f7ed694ceacaa0dd5b3c6aaa87519ae34aa6f3d1257138d23e9dcb` проверены. Build/signing receipts связывают этот файл с исходной сборкой63be0eb; CLI testlab-вариант переиспользует тот же SYS. Это имеющаяся цепочка происхождения, не новая воспроизводимая сборка или SHA всего загруженного образа.

Пять файлов из сохранённого source archive сравнили с Git commit `63be0ebf9bec92bfba95ef3d6729c375aa9af84e`: ProxyBridgeDrv.c, ProxyBridgeDrv_ioctl.h, pbdrv_state.c/.h иvcxproj. Совпали при нормализацииCRLF/LF. Git-объект найден в C:/src/ProxyBridge-228; текущий HEAD другого C:/src/ProxyBridge-Driver не использован как доказательство версии. Обе рабочие копии читались без изменений/переключений. Runtime interception receipt подтверждает service/file SHA, но сам оставляет loaded_binary_verified=false. Live driver code ещё не сопоставлен.

Private audit `pb-driver-source-review-20261018` содержит review.json, readonly dumpbin imports/disassembly. Первая попытка найти прямой IAT operand в callsite ничего не нашла: код вызывает отдельный import thunk. Исправлено проверкой E8 displacement до thunk и FF25 displacement от thunk до IAT; старое предположение не использовалось для точек.

## Наблюдения в исходниках, не установленная причина отказа

1. ProxyBridgeDrv.c:185..241: после ExAllocatePool2, если ctx=NULL, драйвер всё равно меняет назначение и вызывает Apply, передавая localRedirectContext=NULL/size0. Это реальная ветка исходного кода; нет наблюдения allocation failure у конкретного failed connection. Отсутствие driver payload и отсутствие Windows redirect record — разные состояния. Ранее наблюдаемый QUERY_NULL относится к Windows record; связь с allocation-null нельзя объявлять доказанной.

2. ProxyBridgeDrv.c:172..181: после успешного AcquireWritable при redirectLoopbackApps=0 и loopback destination есть ReleaseClassifyHandle/return без ApplyModifiedLayerData. [Документация Microsoft AcquireWritable](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/fwpsk/nf-fwpsk-fwpsacquirewritablelayerdatapointer0) требует соответствующий Apply даже без изменений. Это статическое несоответствие контракту отдельной ветки. Наш сценарий заявляет Localhost via proxy, а source pb_driver.c:240 задаёт этот флаг из g_localhost_via_proxy; ожидается другая ветка. Сам gConfig в момент failed flow ещё не измерен, поэтому ни участие этой ветки, ни её причинная связь не доказаны. Не разворачивать отдельное расследование10061 и не исправлять продукт в рамках этого наблюдения.

3. Контекст после Apply не освобождается драйвером. Это согласуется с [контрактом FWPS_CONNECT_REQUEST0](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/fwpsk/ns-fwpsk-_fwps_connect_request0): начиная сWindows8 владение памятью localRedirectContext принимает WFP. Само отсутствие ExFree здесь не является найденной утечкой/ошибкой.

4. В просмотренном TCP redirect path не найден лимит собственной таблицы TCP контекстов. Event ring2048 хранит журнальные события и при заполнении отбрасывает старую запись; UDP map2048buckets используется дляUDP. Эти структуры не являются доказательством переполнения TCP redirect record table. Не обобщать выборочный просмотр на отсутствие любых возможных ограничений драйвера/Windows.

## Кандидат одной самодостаточной точки в драйвере

В текущем diskSYS найден ClassifyCore RVA12b8. Перед Apply на RVA1696: RCX=classify handle, RDX=FWPS_CONNECT_REQUEST0*, R8d=0. Вокруг места11выбранных инструкций проверены по байтам. E8d3110000 ведёт в import thunk RVA286e; FF2514280000 ведёт в IAT5088, имяимпорта FwpsApplyModifiedLayerData0. ImageSize61000.

Код записывает request+120 redirect handle, +108 targetPID, +128 context, +130 context size; размерctx формируется как32или0. FWPS_CONNECT_REQUEST0 также содержит localAddressAndPort с локальным портом и remoteAddressAndPort. Для IPv4 local port находится вSOCKADDR по+2. Доступность/ненулевое значение в этой точке и индивидуальная связь с native/Core ещё не проверены. Структуру/указатель/семейство/диапазоны надо проверять перед чтением; никаких прежних произвольных stack reads.

Будущая одна точка доApply могла бы одновременно показать local endpoint, изменённое назначение, targetPID и context pointer/size. Это снимок входа вAPI, не доказательство успешного Apply/создания Windows record/доставки доCore. Но для положительной корреляции не потребовалась бы параPRE/POST. Пропуски событий по-прежнему не будут доказательством отсутствия вызовов. Пока это кандидат, JSONprofile/stage/plan/Run не подготовлены.

## Следующий USER шаг — только live чтение

Перед Break предупредить: всяVM PB-BUILD-W11-25H2, Codex иRDP остановятся. Известные2/3отключены итоговымbl предыдущейпробы, повторныйисходныйblне нужен безизменений. Не менять/не включать точки. Поодной: lmvm ProxyBridgeDrv; u ProxyBridgeDrv+0x1650 L18; u ProxyBridgeDrv+0x286e L1; отдельноg дажеприошибке. Приотсутствующемmodule/ошибкеразрешениянеугадыватьадрес, отдельноg ивывод. Полныйвывод вчат, безDesktopinstructions/обязательногоlogopen.

После сопоставления live кода выбрать минимальный профиль; старые Run не повторять, bounded не готовить до проверки новой четырёхсоединительной пробы. До установления механизма исходного отказа продукт не менять.
