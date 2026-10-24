# Общий приёмный UDP buffer для WFP и WinDivert

Пользователь разрешил исправить [подтверждённое ограничение лаборатории](UDP32_LAB_RECEIVER_ANALYSIS_2026-10-24.md), сохранив корректность обоих продуктов. Preview42 меняет только общий локальный origin лаборатории.

В local-windows-v1 UDP socket получает SO_RCVBUF4MiB до bind/начала приёма. Эффективный размер читается обратно; если меньше запрошенного, подготовка завершается ошибкой, socket закрывается. Подписанный metrics response содержит `origin_udp_receive_buffer` с requested/effective bytes. Локальный origin общий для WFP и WinDivert; выбор product contract/adapter на размер буфера не влияет. Перепроверки файлов/identity, source/HMAC/flow/payload, rate/duration/load, порог потерь1%, routes/isolation/final cleanup не менялись. Это ресурс стенда, не драйвера.

Удалённый режим сохраняет прежний путь создания socket: его настройки/платформенный допуск не расширялись. Общие DNS/QUIC/прокси socket не изменялись: контроль локализовал проблему на общем measurement origin UDP socket. Системные buffer defaults/firewall profiles/продукт/драйвер/trust не меняются этим исправлением.

Минимальные проверки до упаковки:2 regression tests (реальный подписанный UDP exchange на новом endpoint; отказ при недостаточном фактическом buffer до bind/traffic),4 failure/source evidence tests PASS. Прежние компонентные контроли показали83702/91595 с обычным buffer и91793/91793 при увеличенном, без ProxyBridge. Это обоснование изменения, а не аттестация нового runtime.

Упаковка42 и bounded UDP-connections SHORT/LOW для WFP4da324e и официального WinDivert4.3 ещё предстоят. Ожидается один и тот же эффективный буфер; PASS продукта заранее не предполагается, прежние реальные UDP-дефекты WinDivert не скрываются. Полный50/soak автоматически не запускается, исторические raw/manifests остаются неизменными.
