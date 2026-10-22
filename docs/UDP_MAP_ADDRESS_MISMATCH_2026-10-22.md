# UDP/SOCKS5: несовпадение адреса в ключе UDP map

## Установленный результат

На управляющей VM воспроизведён отказ connected IPv4 UDP через существующий
комплект `driver-63be0eb-testlab-cli`. Драйвер сохраняет исходное назначение
под wildcard local address `0.0.0.0`, тогда как relay ищет запись по конкретному
адресу отправителя `127.0.0.1`. Точное сравнение адресов даёт промах lookup.
В одном запуске продукта явный bind клиента на `127.0.0.1` меняет ключ,
устраняет промах и обеспечивает обмен через SOCKS5 без изменения продукта.

Это отдельный дефект от ранее исследованного TCP redirect-context failure.
Новый WinDbg/kernel capture не использовался. Продуктовые исходники,
поддерживаемые tests, бинарные файлы и установка драйвера не менялись.

## Свидетельства

1. Более свежий сохранённый запуск TestLab
   `20261014-155137-28a38b81ab784a29b1fb09463ae2af43` уже имеет проверенный
   startup profile: один SOCKS5 config, одно правило, config ID 1. CLI сохранил
   успешный UDP ASSOCIATE и listener 34011. UDP report: sent=2167,
   expired=2167, received=0, send_errors=0. OFF/UNRULED по-прежнему проверяли
   TCP, поэтому прямой UDP из этих controls не следует.
2. Свежая component-only проверка текущей development-копии `d5b51f3`:
   direct/explicit SOCKS5 × connected/unconnected, по четыре отправки и четыре
   ответа, без ошибок. Использованы существующие Agent, SocksProxy и udp_flow,
   loopback и ephemeral ports; продукт не запускался на этом этапе.
3. Product run-r2: один UDP пакет; read-only IOCTL QUERY_UDP по реальному
   source endpoint даёт found=0, по `0.0.0.0` с тем же портом — found=1,
   правильные original destination и PID. Ответ не получен, origin UDP count=0.
4. Различающий product run-r3: origin/SOCKS5 работают в обычном python.exe,
   watched client — отдельный `pb_udp_probe.exe` (копия того же Python
   interpreter с исходным PYTHONHOME). Это исключает перехват собственных
   сокетов origin/proxy. Один CLI lifecycle, одно правило, два последовательных
   клиента, по одному пакету:

| Клиент | Фактический source | Lookup exact | Lookup wildcard | Результат |
| --- | --- | --- | --- | --- |
| Без bind, PID 12092 | 127.0.0.1:52544 | found=0 | found=1, original 127.0.0.1:52541 | TimeoutError; origin=0 |
| bind 127.0.0.1, PID 12588 | 127.0.0.1:59813 | found=1, original 127.0.0.1:52541 | found=0 | Подписанный ответ и payload проверены; origin=1; proxy sent/received=1/1 |

В обоих случаях getsockname возвращает конкретный адрес после connect;
getsockname не доказывает, что этот адрес уже был конкретным при classify.
IOCTL завершались успешно, возвращали 52 bytes; found=0 здесь не ошибка IOCTL.
Для успешного клиента recvfrom сообщил reply peer 127.0.0.1:34011.

## Связь с исходниками

Закреплённый source directory:
`artifacts/product-builds/ProxyBridge-63be0ebf9bec92bfba95ef3d6729c375aa9af84e`.

- `Windows/driver/src/ProxyBridgeDrv.c:204`: UdpMapPut получает адрес из
  req->localAddressAndPort без нормализации wildcard.
- `Windows/driver/src/pbdrv_state.c:116..130`: UdpMapGet требует точного
  совпадения family, source port и source address.
- `Windows/src/relay/pb_relay_udp.c:149,176`: recvfrom source передаётся в
  pb_driver_udp_orig; при отсутствии записи пакет не пересылается в SOCKS5.
- Текущий worker.py connected path вызывает connect без предварительного bind.

Свежая проверка всех трёх бинарных hashes совпала с build receipt:
CLI `ad83b3aad22252be0ab20a6c26470f7c364930af35089e9904f1dd0d29bb40ca`,
Core `fb22ac11639a075433e6925cdfa5f32999217a99a7073d2335db96b41a7032b9`,
Driver `3cd79cfc2a9ec6e45a11b2c225d11cb18c504fec3535e3ef1cb730e0e7732c9e`.
Это идентичность receipt/files, не новая аттестация source-to-binary build.

## Границы и состояние

Product runtime выполнялся на управляющей VM, не на физическом PB-SUT.
WinDbg не запускался; driver service до опытов был Stopped и указывал на
тот же существующий комплект. После опытов CLI cleanup_verified=true,
forced_stop=false; driver service возвращён в Stopped, тестовых процессов нет.
Профили с временными credentials удалены штатным finally; captures сохранены
приватно. Proxy/BCD/trust/signing/hypervisor не менялись.

PB-SUT проверен только read-only через штатный WinRM wrapper: identity
подтверждена, build 26200.9711, продукт/sample services Stopped, probe_count=0,
HLKsvc Running. Клиентский WinRM и TrustedHosts восстановлены, cleanup_errors
пуст. На PB-SUT установлен другой driver hash
`3e5c3c709ee8c8800628f04b5550f3a82377deb264b045ab2f2ccbab3fd8fb4c`;
результат исходного комплекта на него автоматически не переносится.

Не проверены IPv6, внешние назначения, unconnected UDP через продукт,
многопоточная нагрузка, lifetime/reuse map и текущая другая сборка PB-SUT.
Direct-строка к 34011 в старом CLI не доказывает исходное правило Direct:
monitor может видеть уже переписанное назначение; она не заменяет map query.

## Решение: исправлять формирование ключа в драйвере

После дополнительного files-only разбора выбрано место исправления:
`ClassifyCore` / регистрация `UdpMapPut` в `Windows/driver/src/ProxyBridgeDrv.c`.
Relay правильно передаёт фактический source из recvfrom; исходный wildcard
из req->localAddressAndPort не является этим фактическим адресом. Драйвер
владеет и выбором redirect target, и таблицей исходных назначений, поэтому
согласование представления адреса относится к драйверу.

Предлагаемый минимальный алгоритм для нынешней схемы local redirect:

1. Сохранить исходное назначение в ctx, как сейчас.
2. Вычислить адрес назначения local relay по существующему правилу: при
   конкретном local address использовать его; при wildcard — loopback.
3. Записывать UDP map по эффективному source адресу, ожидаемому на стороне
   relay: конкретный local address либо выбранный loopback при wildcard,
   плюс исходный local port и family. Значение записи — прежний ctx original
   destination и PID. Перенести регистрацию после вычисления redirect target
   или использовать одну общую переменную адреса для выбора target и ключа.
4. Сохранить точный lookup и существующий IOCTL layout. Не подменять адрес
   запроса в relay на 0.0.0.0 и не выбирать первую запись по одному порту.

Это проект исправления подтверждённого mismatch, **не реализованный и не
проверенный патч**. A/B доказал рабочий конкретный ключ в IPv4 loopback;
производные правила для других адресов/IPv6 требуют проверки на целевой сборке.
Содержимое req->localAddressAndPort при этом менять нельзя: Microsoft
разрешает изменение local tuple только на bind-redirect слое.
Выбор remote loopback для wildcard и сохранение конкретного bound address
соответствует [официальному примеру connect redirection](https://learn.microsoft.com/en-us/windows-hardware/drivers/network/using-bind-or-connect-redirection).

Слепой wildcard fallback отвергнут по конкретным свойствам реализации:
UdpMapGet возвращает первое точное совпадение; UdpMapPut перезаписывает
destination/PID при совпадении ключа; UDP_ENTRY не содержит endpoint identity
или поколения. В просмотренном драйвере UdpMapClear вызывается только из
DriverUnload, IOCTL_DISABLE лишь выключает gEnabled; endpoint closure callout
не зарегистрирован. Поэтому fallback расширяет поиск на записи, актуальность
и принадлежность которых из текущего IOCTL установить невозможно.
Один exact-first fallback не решает stale/reused-port и multiple-destination
неоднозначность. Это вывод по исходникам, не новый runtime collision capture.

Для полноценного исправления таблицы нужны отдельные требования к владению
endpoint и удалению записей при его закрытии, обработке повторного использования
порта и отказу от неоднозначного результата. WFP предоставляет
[ALE_ENDPOINT_CLOSURE для закрытия UDP endpoint](https://learn.microsoft.com/en-us/windows/win32/fwp/ale-layers);
конкретную схему endpoint identity и синхронизации ещё предстоит реализовать
и проверить. Эти изменения также принадлежат драйверу, а не эвристике relay.
Нормализация ключа сама по себе не объявляется решением всех UDP-сценариев.

Продуктовый bind со стороны клиента — только различающий контроль, не
исправление прозрачного проксирования. Поддерживаемые продуктовые tests не
добавлять по запрету пользователя. В этом этапе новых runtime/build/install
не было; продуктовая рабочая копия оставлена без изменений.

## Приватные файлы

Все новые probes/results находятся вне Git в
`artifacts/diagnostics/udp-component-20261022-r1`. SHA256:

- component result.json: `380f5f40682f51f638ca4c33e02b42cbe9afaf45691e9865916506532e56915a`;
- product-run-r2/result.json: `20642dc25870f6348870e0193cc04441b081f7a2c02512349ed75f5b413e8b60`;
- product-run-r3/result.json: `da84c339446bf3c32da2c093e8d5e271f0011ab864fb967fdb85c44c2d998a7a`;
- manifest.json: `de61a8423a572bed6544800ddcef9899f58c89911b81938950e49512b1d300d3`.

run-r1 — первичная проверка без wildcard query; run-r2 — добавлена wildcard
query; run-r3 — A/B bind с отдельным watched executable. Не смешивать их.
Source для r2 сохранён как product-probe-r2.py; актуальный product-probe.py
воспроизводит r3 и откажется перезаписывать существующий каталог результата.
