# PB-SUT: аудит двух NORMAL/LOW прогонов preview.56

Read-only анализ пользовательских результатов. Новые нагрузки/установки/изменения продукта или отчётов не выполнялись. Доступ WinRM через существующий wrapper; клиентские WinRM/TrustedHosts восстановлены без ошибок. Private evidence в ignored artifacts/sut-normal56 и artifacts/sut-normal56-analysis; не публиковать исходные захваты/DPAPI/PKI.

| Подход | Попытка | Время Екатеринбург, 26 октября | Результат |
|---|---|---|---|
| WinDivert 4.3.0 | `20261026-095445-98e2c2dc226540488f96d12d6b822c20` | 14:55–15:33 | 33 PASS / 11 FAIL |
| WFP driver 4da324e | `20261026-104012-78048b4e98314ddbba8c5e0a91c8cc2a` | 15:40–16:28 | 43 PASS / 1 UNVERIFIED (queue state FAILED) |

## Согласованность данных

275экспортированныхфайловSHA256совпали;92rawSHAпроверены. Пересчитаны все92summary:stage metrics/overall/histograms/resources/workload_resources/comparison_quality/kernelmetadata —0расхождений. Все44пары имеют одинаковые записанные conditions (кроме намеренно исключаемой productidentity/локальныхTLS/SSHключей),NORMAL/LOW,одинаковый порядок и состав,методuser-workload-v2-fixed-session. Native/runtime fingerprint69ca8b2059aa8ecf5585a5bd558f3320d288595b6d7e33015883ffb126d55149. CoreStart/Stop1/1уобоих,capturecomplete=true,forcedstop=false;product/local/nativecleanuptrue.

ActualJSпроверен на этих88строках:33PASSпары совпадают по условиям;29пар проходят exchange/route/load/headroom gates,10пар имеютCPUпроцесса>=0.25CPU-собеихсторон. Все88objective rendersбезNaN;UDPconnectionsWFPпомечаетсяUNVERIFIED,WinFAIL;kernelwinnerникогда не подсвечивается. Неполные/ненадёжные результаты не превращаются в победителей.

## Где сравнение допустимо

29пар умеренных профилей пригодны как наблюдения этого запуска. Для CPUпроцесса10пар:loaded-rtt,tcp-connections,flow-rate,grpc-server-stream,HTTP/HTTPS/WSS/HTTP2payloadsweep,SFTP,AMQPS. Порог0.25CPU-с — правило отображения, не оценка статистической значимости. Повторы нужны для устойчивого рейтинга.

| Наблюдение | WFP | WinDivert |
|---|---:|---:|
| Loaded TCP: RTT p99, мс | 0.987 | 5.864 |
| Тот же профиль: CPU процесса, % всего ПК | 0.321 | 2.297 |
| Тот же профиль: общий CPU ПК, % | 9.03 | 10.74 |
| Flow-rate: завершённые сеансы | 180 | 180 |
| SFTP: подтверждённые циклы | 900 | 900 |
| SFTP: CPU процесса за нагрузку, с | 1.125 | 6.421875 |
| TCPconnections: private commit процесса, пик МиБ | 45.227 | 8.402 |

Одинаковый workload не означает фиксированное число любых обменов: при ограничении по времени быстрый подход может выполнить больше. Для сравнения количества нужна одинаковая заданная работа либо нормализация;сами счетчики не являются универсальным рейтингом. CPUпроцесса не содержит полного отдельного WFPkernelcost. Пик памяти не доказывает утечку. Отличия в этих единичных прогонах не доказывают превосходство во всех сценариях.

Четыре unbounded TCPcapacityпрофиля не проходят обычный boundedloadgate. У WFP upload/duplex/multistream естьCPU_SATURATED;upload96.33%,duplex96.62%CPUПК. Download89.21%тоже рядом с насыщением. На локальномПК одновременно работают product/генератор/получатель/relay;это предел общего стенда,не установленный максимум драйвера. WFPduplex467.33MiB/sнаружу и1.26обратно,Win85.81/68.35:суммирование скрывает сильную асимметрию. Причину без отдельного опыта не приписывать продукту. Для оценки пиков нужен отдельныйorigin и контроль каждого направления/потока,а не только общейсуммы/среднегоCPU.

## Ядро

Во всех44SOCKS5сценариях каждого подхода:точный ожидаемыйSYSsha,WFP5a29f6b7…/Win8da08533…,moduleobserved=true,ambiguous=false,interval10000×100нс=1мс,logicalCPU8. Lost0,consumerdrained=true,intervalchanged=false,poolquery/pollerrors0,cleanuptrue. QPCграницы не пересекаются;formula samples×interval проверена,малыеcountsне превращены в0CPU. 84WFP/68Winизмеренныхфаз(различие из-за прекращённых неуспешных подэтапов),всеpoolstateTAGGED_GLOBAL.

Достаточно выборок для отображенияexclusiveCPUв6WFPсценариях и17Win. **Ни одной успешной сопоставимой пары с достаточнымCPUдрайвера у обеих сторон нет.** WFP TCPпрофили часто0выборок,но UDPдает43/36/97и485выборок:привязка к модулю работает;нулевойcountне означаетнулевойполныйCPUрасход. Win и WFP выполняют разную долю работы в собственномSYS/общихWindowsмодулях;exclusive-IPне охватывает последнюю. Поэтому нельзя складывать сCPUпроцесса или выводить общий ресурсный выигрыш.

Отношение all_samples к длительности×8CPU×1kHz на физическомПК6–97%,а не~100%каквстаромVMpilot. Само по себе это неloss:выборки отражаютактивность CPU,а не гарантированнуюполнуюсеткувсехidleCPU. Независимаяпроверка сGetSystemTimes-basedWindowsCPU по фазам:medianabsoluteразница0.164п.п.WFP/0.307п.п.Win;максимум2.10/3.68п.п. Это поддерживает согласованность времени/масштаба,не доказываетточностьexclusiveattribution. CPUнизкоуровневыхкороткихDPC/ISR может бытьслабо представлен. См.[MicrosoftCPUAnalysis](https://learn.microsoft.com/en-us/windows-hardware/test/wpt/cpu-analysis):samples/weight/idle и ограничения короткихопераций.

Taggedpool—общесистемные выделения по известнымтегам,observedmax/last,неполнаярезидентнаяRAM/всебуферыWindows. Видимыеразличиядопустимопоказыватькакнаблюдения,нонекакполнуюэкономиюпамяти. OverheadETWнаэтоймашине повторнымиoff/onпарами неоткалиброван. Болеедлинныйпрогон сам по себе не исправит неполныйscope.

## Неуспешные этапы

WFPUDPconnections:1/8/32потоковуспешны;128потоковвсеidentityподтверждены,invalid0,senderrors0,loadMET,CPUПК24.16%. Sent96002,receiver95932,proxyudp_sent/received95932,expired70,65потоковс1–2потерями,maxflowloss0.2667%,общаяloss0.0729%. Это ниже действующего порога потерь,поэтомуexchangePASS/всеflowscomplete;но70отправленныхпакетовнепокрытыучётомреле=>routePARTIAL=>итогUNVERIFIED,безрейтинга. Recovery750/750успешен. Это реальное расхождение наблюдаемых счётчиков,не arithmetic/hashошибка. Потеря могла быть до наблюдаемого relaycounter на путиworker/Windows/драйвер/relay;локализация виновника здесь не проводилась. ReportTRAFFIC_LOAD_HALTED_AFTER_STAGE_FAILURE не доказывает транспортныйкрах:причина gatesвrouteaccounting. ОбщийFAILEDне означает,что43PASSневалидны.

Winтеже11UDP-relatedFAIL:UDPconnected/unconnected/sweep/connections,HTTP3single/sweep,QUICsingle/multiplex,DNSUDP,mixed,stability. UDPconnected6750sent/2250received/4500invalid,invalidreasonDATAGRAM_FLOW_MISMATCH,CPUПК7.95%. Это воспроизводится на физическомПКбезKDNET при умереннойнагрузке. Пересчёт/сохранениеправильные,ноотделитьпродуктотсовместимостисreceiver/relay по одномуотчётунельзя;rootcauseотложен.

## Итог и следующий шаг

Сбор/сохранение/расчёт обычных метрик и защитные gates подтверждены на этих файлах;допустимо сравнивать наблюдаемые RTT,CPUпроцесса и прикладнуюработу в29eligibleпарах. ПолныйCPU/RAMрейтингдвухархитектур и максимальнаяпропускнаяспособность всёещё не установлены. Не просить повторять всёрадиформальности:дляустойчивости сначала2дополнительныхповтораloaded-rtt/flow-rate/SFTP/TCPconnectionsнакаждомподходе,одинаковаяочередь,LOW/NORMAL,желательнообратныйпорядок. ПовторWFPUDP128отдельно нужен длявоспроизводимости,но невычисляетвиновника. Дляпиков —внешнийorigin;дляполногоkernelaccounting—отдельнаяметодикаатрибуции/калибровки,непростоLONG.

Состояние при сборе:PB-SUTidle,ProxyBridgeDrvStopped,HLKStopped,debugNo,HighPerformance,тотжеboot09:43:40Z,своихETWнет. Текущеепитание/NICпослепрогона подтверждены;температура/частоты/внешнийфон во всехокнах не записаны,полнойстационарностинеобещать. VMрезультатысSUTнеприравнивать. Длительныйsoakнеразбирался.
