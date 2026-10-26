# Подготовка физического PB-SUT для сравнения

Пользователь разрешил подготовить отдельный тестовый ПК и после предупреждения явно подтвердил наличие физического доступа и перезагрузку с отключением kernel debugging. Продуктовые исправления и анализ причин отказов не входят в задачу.

## Выполнено и проверено до перезагрузки

PB-SUT192.168.0.157: i3-10100,4ядра/8потоков,16ГБ RAM,Windows11Pro26200.9711,1GbEthernet. Исходно сеть через Microsoft Kernel Debug Network Adapter,debugYes,testsigningYes,HLKsvcRunning,Balanced,старый SYS3e5c3c70…;ProxyBridgeDrvStopped/Disabled.

Новый отдельный каталог C:/PB-TestLab-20261026-r1/payload: лаборатория preview.56, WFP4da324e и WinDivert4.3.0,1715файлов совпали по SHA256. Прежние files/history не удалялись. Существующий root PnP device обновлён штатным pnputil до oem25.inf1.1.0.0; установленный SYS5a29f6b7…совпадает с выбранной4daсборкой. После установки PnPdisabled/driverStopped,serviceManual. HLK остановлена/Manual (диагностические нагрузки не наблюдались),power HighPerformance8c5e7fda…,BCDdebugNo,testsigningоставленYes. Trust/Defender/изоляция/системныйproxy не менялись.

В preparation сохранены before.json, экспорт предыдущего драйвера,BCDbackup,RESTORE-SETTINGS.ps1. TaskProxyBridge-TestLab-Comparison:PB-USERInteractive/Highest/AtLogon,без сохранения пароля,контроллер привязан к loopback. На общем рабочем столе ярлык ProxyBridgeTestLab. Полные evidence/zip/скрипты только в ignored artifacts/sut-comparison-prep.

## Финальное состояние после перезагрузки

USER вошёлPB-USER/запустилWinRM. Boot2026-10-26T09:43:40.500Z;обычныйIntelI219-V/Ethernet1Gbps,debugNo,testsigningYes,HighPerformance,HLKStopped. TaskRunning,loopbackUIadmin/idle. Через штатныйCSRFAPI сохранены2сборки:WFPсinstalledSYSpath иWinDivert4.3.0. Предварительныйverify-readyвывелbuild_count1 из-за подсчёта envelope;smokeсчитаетbuilds.items иподтвердил2. Это не потеря сборки.

ДваSHORT/LOWloaded-rttнафизическомПКуспешны:Win`20261026-094946-2ec20707b2bc47c8b7972f538ba99083`,WFP`20261026-095050-22b1d8656b514427b27c95055114b123`. COMPLETE,errors[],exchangePASS,routeCOMPLETE,loadMET,CPU_NOT_SATURATED. Нужныеkernelмодулиувидены,lost0,drained/cleanuptrue. ФиналdriverStopped,active/busyfalse,своихETWнет. Wrapperclientcleanupбезошибок. Evidenceignoredartifacts/sut-comparison-prep/{ready-r1,smoke-r1}.

Готово к пользовательским полнымNORMAL/LOWбезsoak. Открывать ярлык на рабочем столеPB-SUT (localhost5178наSUT);управляющийVMlocalhost5178остаётсяотдельнойлабораторией. КонтроллерневыставленвLAN. НовыйstoreнаSUTнеполучалстарыеотчётыVM. Длительныенагрузки/результативноесравнениевсехпротоколовнаSUTещёнепроводились.

## Условия сравнения

Новые отчёты с физическогоПК не считать равными результатам agentVM. Обе сборки: одна56,одинhost/питание/сеть/темпы/длительность/профилировщик. Не отключать Defender ради хороших цифр. Режим низкой нагрузки сначалаNORMAL;ночные/full/HIGH/soakне запускались автоматически. Контрольidle/warmupодинаковый;повторы и обратный порядок уменьшают drift. Отдельный origin снимает конкуренцию с генератором/получателем, но существующий локальный режим использует тот же ПК — это ограничение throughput/systemCPU. Для пиковых сравнений нужен отдельный физическийorigin и подтверждённый headroom, а не только более мощный SUT.

Kernelexclusive-IP/taggedpool остаётся частичным учётом;отключениеKDNET не превращаетего в полныйfootprint. Продуктовую причинуошибок разбирать отдельно.
