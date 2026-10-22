# Отделение TCP accept от подготовки соединения

USER выбрал именно быстрый приём до обработки и запросил совместимость с
актуальной веткой автора и своим ещё не принятым PR243.

Проверенные исходные refs:

- InterceptSuite/ProxyBridge Driver:63be0ebf9bec92bfba95ef3d6729c375aa9af84e.
- PR243 head:9b5fff56ced41eacf0f50b7f1b43b54a1dbb093f.
- Новое исправление:0e5693d35e73fad6114c668be6a0da9cfa5aa546,
  [ветка в форке](https://github.com/dentatli/ProxyBridge/tree/codex/accept-before-setup).
- Локальная интеграция с PR:5c4dab4, tree
  bd0b7f2639c16ab289edd765c40341d2f793a875. Merge-tree и фактический merge
  дали одинаковое дерево, конфликтов нет. Удалённый PR243 не менялся.

## Объём правки

Единственный production file:Windows/src/relay/pb_relay_tcp.c.
Backlog остаётся SOMAXCONN, driver/IOCTL/PnP/install код не меняется.
accept loop передаёт socket/family/source-port/backend в заранее выделенную
очередь. Один новый setup worker выполняет прежние context query, process/rule
lookup и reporting, затем запускает прежний connection_handler.
Передача payload остаётся в существующих потоках, её алгоритм не изменён.

Очередь ограничена512 ожидающими сокетами плюс один setup in progress.
Полная очередь закрывает лишний socket. При ошибке context, BLOCK, allocation
или CreateThread socket закрывается без угадывания маршрута. При остановке
accept loop присоединяет setup worker; ожидающие сокеты закрываются до free
очереди. Уже выполняющийся синхронный callback должен вернуться, новая отмена
callback не добавлена. Активные data workers остаются вне лимита этой очереди.

Это минимальное по охвату разделение стадий, а не новый IOCP/data-plane.
Оно убирает медленную подготовку с accept thread; не гарантирует больший
payload throughput и не восстанавливает context уже повреждённого соединения.

## Проверки и границы

- Полная user-mode core DLL с16 source files собрана MSVC x64 exit0 на
  Driver+fix и PR243+fix. GUI/installer/kernel driver не собирались и не ставились.
- Native regression harness включает production relay, использует реальные
  loopback sockets и моки WFP/process/rule/config. На физическом PB-SUT exit0,
  шесть PASS. Первый mock context query удерживался, пока подключались ещё
  204 IPv4 и один IPv6 клиент; это не остановило accept.
- Проверены IPv4/IPv6 BLOCK, missing context без fallback, legacy handoff,
  failure создания data worker, bounded queue и stop с ожидающими sockets.
- В agent VM IPv6 connect запрещён даже вне relay (SocketException access
  denied). Первые локальные test runs неполны, за pass не считаются. Проверка
  физического ПК прошла без изменения сетевых настроек.
- Реальный WFP product runtime, IPv6 WFP metadata и HLK новой revision пока
  не проверены. Старые62 HLK passes относятся к PR243, не к новому исправлению.
- Ускорение payload не измерялось. Корректность предотвращения очереди ранее
  подтверждена отдельно независимым sample; не подменять им product validation.

Private evidence:artifacts/diagnostics/pb-accept-first-implementation-20261022-r1.
core-upstream/build.log, core-pr243/build.log, physical-test-r1/command-output.json.
physical-kit-r1/manifest.json связывает source/test SHA с подписанным test EXE.
Runtime был только у harness с mock queries; реальный драйвер не запускался.
Services sample/product на PB-SUT оставленыStopped, HLKRunning.

Рабочие копии:
C:\src\ProxyBridge-accept-first — feature branch, clean;
C:\src\ProxyBridge-accept-first-pr243 — локальный проверочный merge, clean.
Исходный C:\src\ProxyBridge-Driver не переключался/не редактировался.
Новый branch отправлен только в dentatli fork, remote SHA проверен.

Далее: отдельная интеграционная проверка продукта с действительным WFP driver
до объявления изменения production fix. Исследование Windows механизма
остаётся отдельным: KernelReadCapture/hidden kd из неудачной сессии не запускать.
