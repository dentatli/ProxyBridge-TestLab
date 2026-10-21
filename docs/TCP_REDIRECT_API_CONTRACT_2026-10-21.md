# Проверка контракта API и двух альтернативных объяснений

На PB-SUT получены два различающих результата: отказ сохраняется с корректными
inline flags и сохраняется при QUERY_RECORDS перед QUERY_CONTEXT. Это исключает
эти два нарушения как необходимые условия воспроизведения. Локализация сбоя —
доступность redirect record у принятого соединения после queue-refused SYN/retry.
Точная внутренняя причина пропуска привязки в Windows ещё требует исследования.

## Inline flags: обнаруженное нарушение не устранило отказ

Документация `FwpsApplyModifiedLayerData0` требует flags0 для inline classify;
REAUTHORIZE_IF_MODIFIED_BY_OTHERS разрешён только для pended classify. При этом
проверенный WFPSampler revision bb68ed5e770bce04dc5395ec9258dafab034184d всегда
передаёт этот флаг в syslib/HelperFunctions_RedirectData.cpp:85, в том числе с -in.
[Контракт API](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/fwpsk/nf-fwpsk-fwpsapplymodifiedlayerdata0).

Создан отдельный source archive, исходный clone/kit не менялись. Единственное
изменение tracked source: flags выбираются по isPended, inline получает0.
Patch сохранён в scripts/patches/wfpsampler-inline-apply-flags.patch. Сборка
solution Release/x64 с WDK28000 успешна, API validation Universal. SYS подписан
существующим сертификатом, loaded service path/SHA проверены на PB-SUT.
DriverSHA d09a6871038f1f5e4dfb6c6266262d582691ae843f4cbbd6cdbb53fdefe92b95.

Healthy успешен; новый Target с source42202 дал201 query,200 успешных filler
contexts/data512KiB, один original context10022/0. ETW: два1214Reason30 и
1186RexmitCount1/2 по той же паре, EventsLost0/BuffersLost0. Только intended
source file отличается от archive; все evidence checks true.

Первый flags-target-r1 до этого не достиг различающего этапа: address-in-use
на control после healthy. Он INCOMPLETE, не negative result. Контроллер теперь
принимает отдельные ControlPort/FillerBasePort, чтобы не повторять TIME_WAIT
tuple. Смена source port отражена в параметрах, старые планы не использовались.

Текущий исходник ProxyBridge-Driver commit137d1286f55311f39fda06cf717c993bdd5747a4
также содержит Apply(...,0). Это read-only проверка source, не новое доказательство
соответствия старого VM loaded image этому commit; продукт не менялся/не собирался.

## QUERY_RECORDS перед QUERY_CONTEXT: отказ обоих getters

Тестер дополнен опцией --records-first1: один QUERY_RECORDS с buffer65536,
затем ровно один original QUERY_CONTEXT с buffer4096. Нет повторного context
query, setter/fallback или нового outbound proxy socket. Echo-проба не создаёт
outbound connection, поэтому SET_RECORDS для такого сокета неприменим.
[Документированная последовательность](https://learn.microsoft.com/en-us/windows-hardware/drivers/network/using-bind-or-connect-redirection),
[query contract](https://learn.microsoft.com/en-us/windows/win32/winsock/sio-query-wfp-connection-redirect-context).

Новая probe build/help exit0, signatureValid; same corrected SYS, user-mode
sample binaries прежние. Healthy: RECORDS0/970bytes, CONTEXT0/256bytes,
исходное назначение верно,512KiB в обе стороны.

Target с fillers43001..43200/control43201:200fillers успешно выполнили оба getter
и обмен512KiB; у единственного дополнительного соединения RECORDS-1/10022/0,
затем CONTEXT-1/10022/0. ServerPID19036/TID19076. Всего201 уникальный query row.
ETW: та же пара34010←43201, дваReason30 и retries1/2; EventsLost0/BuffersLost0.
Следовательно, перестановка getters не восстанавливает record/context в этом
сценарии, и отказ не ограничен размером/разбором пользовательского context blob.

## Остальная проверка соответствия

В рассмотренных путях sample:

- Redirect handle создаётся при device initialization, кэшируется, уничтожается
  при device cleanup; не уничтожается после каждого соединения.
- Проверяется redirect state для предотвращения повторного перенаправления.
- Classify handle и writable layer data получаются через соответствующие API;
  Apply использует тот же pointer и предшествует release classify handle.
- Context — отдельная NonPagedPoolNx allocation256, original remote/local tuple
  копируются до remote rewrite. После Apply sample его не освобождает.
- Local redirect handle/PID выставляются, local tuple в нашем профиле не меняется.
- Приложение запрашивает данные на accepted TCP socket, inputNULL/0, достаточно
  большие buffers; healthy controls подтверждают формат и назначение.

Это адресная проверка путей, не доказательство корректности всего sample или
всего ядра. WFP принимает владение context allocation по
[FWPS_CONNECT_REQUEST0](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/fwpsk/ns-fwpsk-_fwps_connect_request0).
В рассмотренных документах нет требования прикладывать его вручную к каждому
повторному SYN. Точное назначение private endpoint bit0x200000 не документировано.

В старых VM captures source record/context сохранялись, query endpoint+1c0 был
NULL; отдельно наблюдались endpoint flag transition и пропуск send-gate. Нельзя
склеивать эти разные captures в непрерывный single-NBL trace. Поэтому причина
самого пропуска привязки/конкретная инструкция Windows пока не объявляется
доказанной, хотя две конкретные альтернативы API теперь исключены экспериментом.

## Private evidence и состояние

- pb-independent-inline-flags-20261021-r1: archive/change/builds; первый sys-only
  build не нашёл зависимую lib, второй wrapper не запустил build из-за nested
  JSON array, build-r3 solution exit0. Не выдавать первые попытки за успех.
- pb-independent-wfp-kit-20261021-r3: исправленный SYS и прежний probe.
- pb-independent-flags-healthy-20261021-r1 / flags-target-20261021-r2:
  raw outputs и flags-counterfactual-report.json,
  INLINE_FLAG_MISUSE_EXCLUDED_AS_NECESSARY_CAUSE.
- pb-independent-wfp-kit-20261021-r4: тот же SYS, records-first probe.
- pb-independent-records-healthy-20261021-r1 / records-target-20261021-r1:
  raw outputs и records-order-report.json,
  RECORDS_FIRST_DOES_NOT_PREVENT_RETRY_FAILURE.
- pb-independent-records-final-state-20261021-r1: sample filters0, sample services
  Stopped, ProxyBridgeDrvStopped, HLKRunning, probe/listener отсутствуют.

Все эти captures/keys/binaries остаются вне Git. Отправки третьим лицам нет.
Следующий шаг требует новой наблюдаемости внутри Windows на PB-SUT, а не
повторения того же user-mode опыта.
