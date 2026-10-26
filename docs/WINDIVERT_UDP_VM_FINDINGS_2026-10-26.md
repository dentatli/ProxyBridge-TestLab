# UDP WinDivert 4.3.0: локализация на VM, 26 октября 2026

## Вывод и граница доказательства

В исходнике официального релиза обнаружен дефект изоляции UDP-клиентов в user-mode Core: общий SOCKS5 UDP association на proxy config, обратная доставка по адресу назначения самому недавно активному клиенту. При нескольких клиентах одного назначения этого недостаточно для определения владельца ответа. Неизменённый блок выбора получателя воспроизвёл смешение потоков в изолированном C-harness на agent VM.

Это установленный дефект исходника и объяснение сохранённой картины отказа. Новый запуск официального DLL/драйвера, захват его пакетов и подтверждение соответствия исполняемого кода исходнику не выполнялись. Поэтому не объявляем бинарный A/B или исправление продукта подтверждёнными. Оснований возлагать причину на WinDivert64.sys нет.

## Scope / ревизии

- Только agent VM. Никаких обращений к PB-SUT/192.168.0.157, даже read-only; пользователь проводит там свой опыт.
- Исходный [VM-only handoff](WINDIVERT_UDP_VM_HANDOFF_2026-10-26.md) и его ограничения действуют.
- TestLab development HEAD перед этим checkpoint: `59e34e120bddb03cc5438380be612850e6e99ad2`; runtime preview57 source `592aa65f422f0691f2ccc0dda006b7d2b2f50c1d`. Main checkout не использовался как актуальный runtime.
- Официальный [релиз](https://github.com/InterceptSuite/ProxyBridge/releases/tag/v4.3.0_Windows), tag commit `8cb9dceeed582fcd7c2baed8d20eec34934732fc` (git ls-remote). Получен через GitHub connector; pb_relay.c по tag и полному SHA совпали.
- Локальный официальный ProxyBridgeCore.dll SHA256 `1996d5564a6c6f9b58a25e64781acbc07720cbac530e2706ce4a58f20ea18d14` совпал с сохранённым inspection receipt. Это не доказательство воспроизводимой сборки из tag.

## Наблюдения из сохранённого экспорта SUT

Attempt `20261026-095445-98e2c2dc226540488f96d12d6b822c20`; это SUT evidence, не результат нового VM product run.

| Стадия | Потоки | Sent | Valid replies | Invalid replies | Origin / proxy replies |
| --- | ---: | ---: | ---: | ---: | ---: |
| UDP connected | 3 | 6750 | 2250 | 4500 | 6750 / 6750 |
| UDP unconnected | 3 | 6750 | 2250 | 4500 | 6750 / 6750 |
| Connections baseline | 1 | 750 | 750 | 0 | 750 / 750 |
| Connections 8 | 8 | 6000 | 766 | 5234 | 6000 / 6000 |
| Connections recovery | 1 | 750 | 750 | 0 | 750 / 750 |
| Sweep 64 bytes | 2 | 3000 | 1500 | 1500 | 3000 / 3000 |

В connected два flow имеют received=0/invalid=0; третий received=2250/invalid=4500. В unconnected получателем всех ответов оказался другой flow. Invalid reason — DATAGRAM_FLOW_MISMATCH; C# worker проверяет HMAC и run-id раньше flow-id. Origin: udp_reply_errors=0. В connected все наблюдаемые origin peers успешного flow — один endpoint 127.0.0.1:54540.

Счётчики показывают доставку всех ответов обратно в worker-процесс с неправильным распределением, а не простую потерю/CPU overload. Нет сырых заголовков каждого invalid reply или actual-vs-expected flow-id: текущий C# worker сохраняет счётчик причины, но не первый flow mismatch. Пакетный путь до конкретной функции DLL этими отчётами не доказан.

UNRULED-control этого кейса — TCP echo. Его PASS **не является** direct UDP control. Отдельный live explicit SOCKS5 UDP control в этом этапе не выполнялся.

## Механизм в исходнике релиза

- [pb_relay.c:165–205](https://github.com/InterceptSuite/ProxyBridge/blob/8cb9dceeed582fcd7c2baed8d20eec34934732fc/Windows/src/pb_relay.c#L165): outbound определяет клиента по порту, но посылает через cfg->udp_send_sock, общий для proxy config.
- [pb_socks5.c:452–491](https://github.com/InterceptSuite/ProxyBridge/blob/8cb9dceeed582fcd7c2baed8d20eec34934732fc/Windows/src/pb_socks5.c#L452): UDP ASSOCIATE/UDP socket принадлежат cfg.
- [pb_relay.c:270–317](https://github.com/InterceptSuite/ProxyBridge/blob/8cb9dceeed582fcd7c2baed8d20eec34934732fc/Windows/src/pb_relay.c#L270): ответ содержит remote IP/port; reverse bucket ищет все совпадающие назначения и выбирает максимальный last_activity, затем обновляет timestamp победителя. Исходный клиент ответа не определяется; proxy_config_id в этом фильтре также отсутствует.
- [pb_conntrack.c:174–196](https://github.com/InterceptSuite/ProxyBridge/blob/8cb9dceeed582fcd7c2baed8d20eec34934732fc/Windows/src/pb_conntrack.c#L174): IPv6 использует тот же принцип выбора по активности; runtime IPv6 здесь не проверялся.
- Это не SOCKS5 protocol error: стандартный reply не содержит исходный локальный клиентский порт. Потерянную при объединении потоков идентичность нельзя восстановить выбором самого активного клиента. Содержимое прикладного payload разбирать для маршрутизации недопустимо.
- Работа Discord совместима с этим механизмом: одиночный клиент или разные remote endpoints не создают ту же неоднозначность; это объяснение, а не проведённый тест Discord.

TestLab origin формирует ответ из authenticated request, сохраняя flow-id, и посылает received.RemoteEndPoint. TestLab SOCKS relay имеет отдельный origin-side socket на ассоциацию; RelayDatagram отвечает её сохранённому client endpoint, не выбирает последний flow-id.

## Проверки на VM

Локальная занятость перед harness: UI PID9288, product/TrafficEngine/debugger processes не обнаружены; GET только 127.0.0.1:5178/api/v1/lab/run: administrator=true, run=null, suite=null. Продуктовые Run/driver start/install, системные настройки и подключения к SUT не выполнялись.

1. MSVC собрал изолированный selector_replay.c с **неизменёнными строками274–307 pb_relay.c**, минимальными структурами/одним bucket и Windows lock/time primitives. Три synthetic клиента одного назначения, по2250 ответов: valid=2250,0,0; invalid=4500,0,0. Single-client и unmatched-destination controls PASS. Это точное выполнение блока выбора в модели, не запуск DLL, не симуляция всей очереди/таймингов.
2. Реальные Python методы TestLab SocksProxy.datagram/RelayDatagram вызваны с mocked transports. Три отдельные ассоциации и одна общая: все payload bytes и endpoint владельца сохранены. PASS. Ни сокетов, ни сети; это проверка маршрутизации методов, не end-to-end authentication/traffic acceptance.
3. Первый запуск fixture завершился AttributeError из-за отсутствующего fake-agent.metrics; исправлен только fixture, повтор PASS. Код TestLab/продукта не менялся. Gates не отключались.
4. Все harness процессы завершились; не создавались product services, traffic sessions или фоновые процессы. Capture/kit не изменялись.

Evidence (ignored/private, не коммитить):
`C:/Users/LabAdmin/.codex/worktrees/testlab-development/ProxyBridge-TestLab/artifacts/windivert-udp-vm-20261026/`
— скачанные исходники, selector_replay.c/.exe, compile.log, selector-replay.log, relay_contract.py, relay-contract.log, evidence-summary.json (выбранные счётчики и SHA256).
Исходный экспорт остаётся в artifacts/sut-normal56/<attempt>; повторный full audit не делался.

## Следующий шаг / ограничения

Диагностический результат этого этапа: дефект выбора владельца локализован в исходнике user-mode relay и воспроизведён offline. Продукт не исправлялся. Для окончательной атрибуции официального бинарника нужен отдельный минимальный VM-only live опыт с direct UDP, explicit SOCKS5 UDP и официальным product path; захватить association/socket identity и ответы двух клиентов одного remote endpoint. Не запускать full/HIGH/soak, не устанавливать драйвер без соответствующей отдельной авторизации. Текущие gates/занятость проверять заново.

Направление исправления: сохранять однозначное владение association/socket для каждого клиента/назначения, включая адресное семейство и proxy config; обеспечить disposal/reuse isolation. Не менять last_activity heuristic и не ослаблять flow-id gate ради PASS. Новая продуктовая реализация — только отдельная ветка от dentatli/driver с учётом того, что она уже WFP, а изученный официальный релиз использует WinDivert; не переносить патч в другую архитектуру вслепую. PR/merge не разрешены. Тесты в продуктовую ветку не добавлять.

Чужие modified docs/CHAT_HANDOFF_DEVELOPMENT.md и untracked KernelReadCapture.cs в main сохранены; .cs не читался. README остаётся отдельным следующим scope. Лимиты последней проверки: primary33%used, weekly28%used; порог остановки не достигнут.
