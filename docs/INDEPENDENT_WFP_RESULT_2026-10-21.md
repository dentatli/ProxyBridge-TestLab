# Независимое воспроизведение отказа WFP redirect context

Ошибка `SIO_QUERY_WFP_CONNECTION_REDIRECT_CONTEXT → 10022 / 0 bytes`
воспроизведена на физическом PB-SUT с официальным Microsoft WFPSampler и
отдельным Winsock-тестером. ProxyBridgeDrv был остановлен и отключён; код
ProxyBridge и активные точки WinDbg для воспроизведения не требовались.

Это подтверждает воспроизводимость сценария вне ProxyBridge. Наиболее сильная
текущая гипотеза — нарушение переноса redirect context при повторном SYN после
отказа очереди listener в Windows TCP/IP/WFP. Точная внутренняя инструкция,
исправление Windows и отсутствие возможной общей ошибки использования API в
WFPSampler этим опытом не доказаны. Не объявлять весь драйвер ProxyBridge
проверенным или Microsoft bug окончательно установленным.

## Условия

- PB-SUT, Windows11Pro25H2 x64, build **26200.9711**, boot
  `2026-10-21T15:29:34.5Z`. До перезагрузки UBR был9457; после неё проверен9711.
  Исходная VM использует26100, поэтому это независимое воспроизведение на другом
  build, а не точный контроль старого ядра.
- Microsoft Windows-driver-samples revision
  `bb68ed5e770bce04dc5395ec9258dafab034184d`; исходники sample не менялись.
  Release/x64, WDK28000, API validation Universal.
- WFPSamplerCallouts загружен через SCM как demand-start non-PnP KMDF.
  CLI/service/SYS/probe подписаны существующим тестовым сертификатом, без нового
  импорта trust или изменения BCD. При первой попытке unsigned service EXE
  был отклонён CodeIntegrity3004; защита не отключалась.
- Узкая volatile policy: IPv4/TCP, probe app, исходное назначение
  `127.0.0.1:54122`, перенаправление на `127.0.0.1:34010` и фактический PID
  отдельного server process. Local tuple не переписывался, remote-service mode
  не использовался.
- Один original query на accepted socket, buffer4096, ожидаемый sample
  context256байт. Повторных queries и fallback нет. Payload512KiB в каждую
  сторону с проверкой содержимого.

## Наблюдения

| Проверка | Результат |
| --- | --- |
| Обычный контроль, один connect/accept | Query0, context256, исходное назначение совпало;512KiB в обе стороны, данные верны |
| Заполнение очереди | 200 Established соединений принадлежат fillerPID; native TCP table показывает перенаправленный порт34010 |
| 200 filler accepts | 200 успешных context queries и проверенных обменов512KiB |
| Дополнительное соединение, source42201 | Connect/accept состоялись; единственный original query вернул-1/10022/0bytes |
| TCPIP1214 для34010←42201 | Два отброшенных SYN, Reason30/SO_PAUSE_ACCEPT |
| TCPIP1186 для42201→34010 | Повторные connect attempts с RexmitCount1 и2 |
| ETW | 426438 событий; EventsLost0, BuffersLost0 |
| Cleanup | Trial cleanup_errors пуст; проверено отсутствие sample filters, probe processes и listener34010 |

Выбранный query: serverPID8632/TID7000, source42201, local34010,
queryBeginQpc5190049228/queryEndQpc5190052175, frequency10000000.
Всего201 query row и201 уникальный peer port; единственная query failure — control.

Первый target-r1 не является отрицательным опытом: controller отфильтровал
native TCP table по исходному порту54122 и остановился до control. В target-r2
таблица сначала сохранена полностью, затем учтён фактический redirected tuple.
Healthy и target-r2 успешны как сбор свидетельств; child ExitCode поля получились
null, поэтому native exit0 не заявляется. Результат опирается на полные role
summaries,201 per-socket rows, payload checks и ETW, а не на эти пустые поля.

## Свидетельства

Private каталоги под `artifacts/diagnostics/` не включены в Git:

- `pb-independent-healthy-20261021-r1/target-files`: здоровый контроль.
- `pb-independent-target-20261021-r2/target-files`: native rows/summaries,
  readiness/ownership/TCP state, ETL и policy/cleanup logs.
- `pb-independent-target-20261021-r2/independent-evidence-report.json`:
  `INDEPENDENT_REPRODUCTION_CONFIRMED`, девять evidence checks true,
  selected drop/retry records и hashes.
- `pb-independent-final-state-20261021-r2`: 0sample filters среди288 записей,
  sample driver/service Stopped, ProxyBridgeDrv Stopped, HLKsvc Running,
  нет probe processes/listener.
- `pb-independent-os-after-20261021-r1`: фактический build26200.9711 и boot.

ETL SHA256:
`f06b7125aaaf150e8f04f399a64e6d66fe93d7ed788ede5d8d276caf14334bfa`.

Подготовлены source/controller/reporting материалы для разбора с Microsoft.
Новый Run и новые точки не нужны для подтверждения этого результата. Следующее
полезное действие — разбор независимого sample/API contract либо оформление
сообщения об ошибке с воспроизводителем; отправка кому-либо ещё не выполнялась.

## Оставленное состояние ПК

WFPSampler и WFPSamplerCallouts установлены с запуском по требованию, остановлены.
Временные filters удалены. ProxyBridgeDrv оставлен Disabled/Stopped по разрешению
USER работать без обязательного отката. HLKsvc работает, его startup не менялся.
На ПК остаются каталог комплекта/свидетельства, sample provider/sublayer и
SafeBoot keys официального sample service installer. Не считать это полным
удалением установленного sample. Клиентские временные WinRM/TrustedHosts
изменения восстановлены, cleanup errors пуст.
