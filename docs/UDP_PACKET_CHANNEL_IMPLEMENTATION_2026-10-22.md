# UDP packet channel: реализация и граница сквозной проверки

**Последующее обновление:** [первый реальный driver trial](UDP_DRIVER_TRIAL_CHECKPOINT_2026-10-22.md)
выполнен по разрешению USER: kernel gate не пройден, driver return injection
error после успешного SOCKS roundtrip. Baseline восстановлен. Описание ниже
фиксирует подготовку до этой установки, а не актуальный запрет на её выполнение.

## Состояние

Реализация опубликована в `dentatli/ProxyBridge:codex/udp-map-source-key`, commit
`30b4ec7115291f396cdd2dad77045f287d6e4948`. Рабочая копия
`C:/src/ProxyBridge-accept-first` чистая; remote SHA проверен. `driver` осталась
на `b3596272a8dc8898790b016d1e4c488c2fdc917d`; PR/merge не создавались.

Это **экспериментальный backend с незакрытым kernel runtime gate**, не готовая
проверенная замена установленного драйвера. Реальный SYS ещё не загружался;
производительность и расход памяти под нагрузкой не измерены.

## Что изменено

- UDP больше не идёт через source → последнее назначение и общий loopback
  relay. ALE_AUTH_CONNECT сохраняет endpoint/image, DATAGRAM_DATA получает
  фактические адреса каждого пакета, ALE_ENDPOINT_CLOSURE инвалидирует ID.
- Один контракт Core/driver: 84-byte record header, payload и ограниченные
  ancillary bytes. Kernel pointers/handles не передаются. ABI проверяется
  перед включением; старый Core также отклоняется новым SET_CONFIG.
- Core использует IOCP и асинхронные ConnectEx/SOCKS/auth/DNS/UDP/device I/O.
  Ассоциация разделяется по endpoint generation, local family/address/port,
  compartment и proxy config. Дополнение local address необходимо для
  wildcard-сокета, отправляющего с нескольких адресов.
- Ответ определяется своим upstream socket/association и remote tuple.
  Глобальная эвристика last_activity исключена. Direct и proxy return
  используют transport injection; packet builder формирует IPv4/IPv6 и checksum.
- Добавлены ограниченные очереди, лимиты endpoints/sessions/I/O, отмена и
  draining, счётчики ошибок и их вывод в лог. SOCKS/правила остаются в user mode.

Точные лимиты и ограничения в продукте:
[Windows/driver/UDP.md](https://github.com/dentatli/ProxyBridge/blob/30b4ec7115291f396cdd2dad77045f287d6e4948/Windows/driver/UDP.md).
Среди них: IPv4 proxy TCP transport, отсутствие SOCKS fragment reassembly и
domain-form UDP response headers, ограничения encapsulated payload и offload
aggregates. Существующий Stop/owner-cleanup выключает фильтрацию; постоянная
блокировка после падения Core этим изменением не реализована. Отдельный выбор
такой политики требует изменения lifecycle, а не только UDP packet channel.

## Выполненные проверки

1. Release Core/CLI: exit0, compiler diagnostics0.
2. KMDF Release compile/link + native code analysis: exit0, diagnostics0.
   Первое предупреждение анализа о границе копирования устранено явной
   проверкой размеров и аннотированным bounded helper.
3. Standalone x64 InfVerif `/w`: exit0. WDK MSBuild PackageVerifier оказался
   неисправен из-за отсутствующего `x86/InfVerif.dll`; финальная сборка явно
   использовала SkipPackageVerification=true, INF отдельно проверен штатным
   x64 инструментом. Это не заявление о прохождении HLK/DVL текущей ревизией.
4. Фактический product packet builder: **28/28** offline случаев IPv4/IPv6,
   receive/direct, payload 0/1/2/7/1200/65000/65507; независимая Python-проверка
   адресов, портов, длины, payload, UDP и IPv4 header checksum.
5. Фактический Core IOCP/SOCKS-код через **имитацию device channel** на PB-SUT:
   IPv6 BND relay, domain BND relay, username/password authentication.
   В каждом финальном режиме 7/7 ожидаемых writes, wrong_owner_or_payload=0,
   drops=0, io_errors=0; после Stop I/O=0, sessions=0.
   Проверены два клиента одного remote, разные remotes и разные local addresses
   одного endpoint, IPv4/IPv6 payload header, zero payload, direct/block,
   передача ancillary bytes и намеренная перестановка ответов.
6. Отказ SOCKS и отмена зависшего handshake: ожидается только direct write;
   6 proxy payload учитываются как dropped, неверных доставок0, после Stop
   I/O/sessions0. Новых тестов в product branch не добавлено; harness только
   в private/ignored TestLab artifacts.

Ограничение: simulated-device проверка не подтверждает WFP metadata, injection,
connected/wildcard поведение настоящего socket, kernel/PnP/power teardown,
полный CLI/TestLab Run либо ускорение обработки трафика.

История fixture: IPv6-проверка r1 на PB-SUT не прошла, потому что native UDP
echo завершал receive loop на Windows10054 после ответа закрытому control
socket. Это подтверждено control/event log и исправлено обработкой10054;
финальные r2/r3 проходят. Отдельные неуспехи IPv6 control в управляющей VM
не объявляются дефектом продукта и не исправлялись системными настройками.
Нормальные reset/10038 при закрытии fixture сохранены в исходных captures.

## Подготовленный пакет и восстановление

Candidate: `artifacts/diagnostics/udp-implementation-20261022-r1/candidate`.
SYS 39320 bytes, SHA256:
`ed3c635149d1a480a9633bec3be77b40b1e014b059888ec78099663aca79c2fe`.
Core SHA256:
`50a3ddc7e360e01ed2b7aec0072c68819e84aaacbe4f60e4e039beaf57f2a79c`.
SYS и regenerated CAT подписаны существующим lab certificate
`4544323109A45FC4761819E079BBDBD5E0BFE8D6`; signature/catalog verification
успешны. Сертификаты, BCD и trust не изменялись. Пакет не устанавливался.

На PB-SUT заранее экспортирован `oem14.inf` в
`C:/PB-UDP-Recovery-20261022-r1/baseline-package`. Его SYS hash равен baseline
`3e5c3c709ee8c8800628f04b5550f3a82377deb264b045ab2f2ccbab3fd8fb4c`.
Существующий signer уже доверен в Root и TrustedPublisher; нового trust не нужно.
Driver остался Stopped/Disabled/problem32; финальные Core probes не оставили
процессов. Клиентский WinRM/TrustedHosts восстановлены wrapper.

Подготовлен, синтаксически проверен, **не выполнен** runner
`artifacts/diagnostics/udp-driver-trial-20261022-r1/trial.ps1`:
временный forced update того же devnode, fresh matrix direct/explicit controls
до Core, остановка на первом failure, deadline60s, затем forced baseline rollback
и проверка hash/Stopped/Disabled/problem32. Автоматического reboot нет.
При kernel crash или hang finally не гарантирован: может понадобиться
физическая консоль PB-SUT. Runtime installer — следующий отдельный шаг,
требующий разрешения по правилам изменения product driver installation.

Payload ZIP SHA256:
`e96da33a4015aec77bee98479f5281569d37dabdcbc1bb5cf172aa78f8892b53`.
Runner SHA256:
`87828391c20647ec39a70785d491480a779229aa19c8c5d4440da57940151fcc`.
Не запускать runner заново в старом каталоге; новые trials требуют свежего
evidence/remote directory. Frozen captures не возобновлялись.

## Evidence checkpoint

Private/ignored roots:
`udp-implementation-20261022-r1`, `udp-core-iocp-probe-20261022-r1`,
`udp-core-iocp-target-20261022-r1/r2/r3`, `udp-recovery-target-20261022-r1`,
`udp-driver-trial-20261022-r1` под `artifacts/diagnostics`.
Offline review: PASS_WITH_KERNEL_RUNTIME_GATE. Manifest SHA256:
`af25a819601bcb4c62bb1bb2e7d30b639501a6cfdd4fb2c7584a9bc7271d576e`.
Captures, binaries, package export, credentials и harness не включены в Git.
