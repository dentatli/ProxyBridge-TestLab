# ETW наблюдение TCP redirect

Опциональный профиль `scripts/debugger/pb-etw-tcpip-redirect-v1.json` использует
общий `Invoke-KdSession.ps1` и прежний workload. Активных точек WinDbg нет;
имеющаяся аппаратная 2 остаётся зарегистрированной и отключённой. Драйвер
остаётся загруженным, до/после работы сохраняются resident DISABLE receipts.
Этот режим не устанавливает драйвер и не управляет отладчиком на физическом хосте.

Prepare/проверка SHA/boot/одноразовый claim/межпроцессная блокировка остаются
прежними. Run требует `-ProfileReviewed -DebuggerPointsDisabled`; параметр
`-DebuggerLoggerEnabled` с ETW профилем отклоняется. Bounded256 требует отдельного
review завершённой четырёхсоединительной пробы с тем же профилем и boot.

`EtwRedirectCapture.psm1` создаёт только собственную сессию
`PBRedirect-<GUID>` провайдера Microsoft-Windows-TCPIP
`2f07e2ee-15db-40f1-90ef-9d7ba282188a`, keywords `0x2080`, level 5.
Это объединение TcpipDiagnosis и TcpipCsDiag: собираются и другие события,
соответствующие маске, включая сведения о фоновых соединениях. Стековый сбор
и захват содержимого пакетов не включаются. ETL ограничен 128 MiB; файлы
сохраняются вне workload, чтобы запись ETL не меняла хешируемую native evidence.

Завершение использует ControlTrace STOP и сохраняет итоговые EventsLost,
LogBuffersLost, RealTimeBuffersLost. При ошибке допустима остановка только этой
сессии через logman; отсутствие итоговых счётчиков всё равно делает захват
неполным. Tracerpt XML дополнительно проверяется по header EventsLost/BuffersLost
и ошибкам декодирования TCPIP. Другие сессии не останавливаются.

`pb_etw_redirect_report.py` пока строит проверенный по потерям инвентарь и
сохраняет исходные поля 1553/TcpAcceptRedirect и
1315/TcpCreateNotificationChannelRequestProcessing. CodePath не интерпретируется.
Наличие события ещё не доказывает принадлежность тесту; нужна корреляция с
native/Core адресами и портами. Отсутствие события не доказывает отсутствие
kernel path. Native report отдельно остаётся pending ETW review. Это не тест
производительности и не доказательство причины 10022.

Пассивная проба 2026-10-18: start/stop/export подтверждены, итоговые и header
потери нулевые, XML содержит TCPIP 1553 v0 с декодированными sockaddr.
Она включала только фоновую активность, без запуска ProxyBridge workload.
Первый новый профиль допускает только четыре соединения; масштабирование —
после разбора фактической полезности событий и полноты native evidence.

Первый four Run 185434-dad241dc остановлен до запуска native client/receiver:
free physical 1 098 813 440 bytes меньше существующего порога 2 147 483 648.
Дисковый порог выполнен. Клиентских CSV/Core query нет, 10022 не оценивался.
ETW final/header loss=0, helpers stopped, resident DISABLE after completed,
служба Running; независимого readback gEnabled нет. План использован, не повторять.
Добавлена предварительная проверка тех же 2 GiB до run-claim/ETW/worker start,
порог не снижен; действующая проверка внутри cohort сохраняется.

После reboot и подтверждения USER `bc2`/отдельного `g` применяется новый
`scripts/debugger/pb-etw-tcpip-no-points-v1.json` с пустыми registered/active/
inactive/points. Предыдущий профиль с отключённой2 не изменяется.
Проба190824-00e55c9d:4native successes/4Core queries32bytes/errors[],
ETWfinal+header loss0. Для каждого Corepeer найден ровно один1553v0 с тем же
local/remote sockaddr. Во всех четырёх Succeeded1, Redirected0, CodePath2;
значение Redirected этого event нельзя считать индикатором отсутствия
WFP redirect context, поскольку Core его получил.1315 не наблюдался.
Нет доказательства причины10022/полноты kernel lifecycle; нужны failure-side
данные. Драйвер остаётся Running после completed DISABLE, ETW остановлен.
