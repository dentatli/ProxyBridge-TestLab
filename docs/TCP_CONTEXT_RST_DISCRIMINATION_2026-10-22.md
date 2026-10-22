# Ранний RST отличает отказ контекста от успешной повторной передачи SYN

## Результат

На независимом sample воспроизведено различие: блокирование первых SYN с
ответными RST приводит к10022 обоих getters; такое же блокирование с дополнительным
точным TRANSPORT_DISCARD block подавляет зарегистрированные RST, и context
сохраняется даже после трёх SYN retries. Это сильное свидетельство участия
обработки раннего RST, а не просто повторной передачи SYN или переполнения
очереди. Указание точной внутренней ошибочной инструкции остаётся гипотезой.

## Исправление предыдущего анализа

В [первом разборе single-flow](TCP_CONTEXT_SINGLE_FLOW_DROP_2026-10-22.md)
был проверен1184/TcpConnectionTerminatedRcvdRst. Его время действительно на
2.0419мс позже окончания query. Но это событие означает завершение соединения
по RST, а не приём любого RST. Не проверенные первоначально1479/TcpRstSend и
1601/TcpRx в том же ETL показывают три более ранних RST+ACK в SynSent.

TCB0xffffa18fbc08d010, ACK4232612764, flags20decimal=0x14:

| UTC приёма | Состояние |
| --- | --- |
| 06:58:10.7869230 | SynSent |
| 06:58:11.2867895 | SynSent |
| 06:58:11.7887625 | SynSent |

Перед каждым есть отправка RST от34010 к48801, Reason Receive discarded.
Позже тот же TCB переходит SynSent -> Established. Поэтому утверждение,
что в этом опыте RST появился только после10022, неверно и отозвано.
Private reset-history.json сохраняет65связанных событий, не только1184.

## Различающие опыты

Один boot2026-10-22T05:12:09.5Z, PB-SUT OS26200.9711; kit-r7/corrected sampleSYS
d09a6871…, productStopped. Отладчика,200fillers и переполнения очереди нет.
Тот же probe, records-first, один запрос каждого getter на accepted socket.
Точный временный inbound transport block ограничен TCP127.0.0.1:source ->
127.0.0.1:34010. В варианте добавлен BASIC_ACTION_BLOCK на
FWPM_LAYER_INBOUND_TRANSPORT_V4_DISCARD с теми же условиями. Остальные
соединения, включая WinRM, этим правилом не охватываются.

| Условие / source port | SYN retries | RST send / client receive по ETW | Результат |
| --- | --- | --- | --- |
| Исходный block,48801 | 1/2/3 | Три ранних RST+ACK; ещё один терминальный | RECORDS10022/0, CONTEXT10022/0 |
| Block + discard block,48803 | 1 | 0 / 0 | records970/context256,512KiB обе стороны pass |
| Обратный контроль без discard block,48804 | 1/2 | 3 / 3 всего, включая терминальный | RECORDS10022/0, CONTEXT10022/0 |
| Block + discard block, удержание3500мс,48805 | 1/2/3 | 0 / 0 | records970/context256,512KiB обе стороны pass |

Во всех новых опытах loss0; queries1, controllererrornull, summarieserrornull,
cleanup_errors[]. В длинном варианте три Reason7 drops; retries1/2/3,
но RST events1479 отсутствуют для tuple и RST flag в1601 отсутствует для TCB.
Таким образом, успех нельзя объяснить отсутствием повторной передачи или
только меньшим числом SYN retries. Точные интервалы и source ports различаются;
это ограниченный набор опытов одной ОС, не универсальное статистическое доказательство.

## Сопоставление с кодом

Дисковые tcpip.sys физического ПК и VM побайтно одинаковы:
SHA256 b0683bd7ed0f309e63b4e6e71675d8f04cfb0ea5533c3f5e8a13c6daca3b595a,
версия файла26100.8875. Поэтому ранее разобранные RVA и branch относятся
к тому же дисковому коду. fwpkclnt/netio имеют версии26100.9711; не считать
их идентичность старым модулям автоматически доказанной.

Прежние runtime captures показывали: receive RST+ACK устанавливает source
endpoint+0x30 bit0x200000; последующий send gate обходит association key5;
source record остаётся, а query endpoint имеет NULL record. Новый опыт
поддерживает эту причинную модель, разделяя RST и саму retransmission.
При этом полный single-flow join каждого NBL от source до accepted endpoint
и назначение private flag ещё не доказаны. Не склеивать отдельные captures
в одну будто непрерывную трассу и не предлагать патч private bit как API fix.

Поиск immediate200000h по .text с disassembly от .pdata нашёл один прямой
OR этого значения в поле+0x30 — receive function. Остальные найденные
инструкции относятся к иным полям или test/and. Это не полный анализ всех
записей поля: возможны bts, записи всего поля, другие модули/alias offsets.
После association helper AleAcceptRedirectProxyNblTag найден отдельный key9;
не смешивать его с redirect record key5.

## Практическое значение и состояние

Accept-before-setup остаётся обоснованным предотвращением queue-refusal/RST
под нагрузкой. Он не обещает исправить все внешние причины RST. Discard block
использован исключительно как различающий диагностический фактор: blanket
suppression RST в продукт не добавлялось и как готовое исправление не предлагается.
User product branch37e64c6 не менялась; тесты в неё не возвращались.

Существующий sample запущен без переустановки. После опытов проверено:
sample filters0/probe0/listener0, sample servicesStopped, productStopped,
HLKRunning. Удаление собственного discard filter выполнено в finally.
Артефакты private/ignored: pb-independent-discard-block/control/long-20261022-r1,
их flow-history.json, pb-independent-discard-final-state-20261022-r1,
pb-physical-static-images-20261022-r1 и bit21-candidates.json.

Дальнейшая узкая задача: проверить, является ли установленный до завершения
TCP handshake receive flag причиной пропуска key5association, либо только
сопутствующим состоянием. Не требуется повторять широкие packet breakpoints.
Для поставщика ОС уже есть независимое one-flow воспроизведение и отличие
с сохранением retries; это полезнее дополнительного повышения raw limits.

Документированный принцип: [TCP Packet Flows](https://learn.microsoft.com/en-us/windows/win32/fwp/tcp-packet-flows)
описывает подавление соответствующего RST блокированием на TRANSPORT_DISCARD;
[пример Microsoft](https://learn.microsoft.com/en-us/windows/win32/fwp/preventing-port-scanning)
показывает built-in silent-drop callout. Наш вариант использует BASIC_ACTION_BLOCK,
а не выдаётся за побайтное повторение примера; эффект проверен по ETW.
