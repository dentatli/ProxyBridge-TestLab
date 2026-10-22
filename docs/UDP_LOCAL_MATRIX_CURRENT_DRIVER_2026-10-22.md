# UDP: локальная проверка актуальной driver на физическом PB-SUT

Дополнение после матрицы: [установленная причина и новый опыт одного сокета
с двумя назначениями](UDP_FLOW_IDENTITY_ROOT_CAUSE_2026-10-22.md).
Map перезаписывает назначение уже поставленного в очередь пакета;
wildcard-only исправление недостаточно. Сама матрица ниже сохранена.

## Итог

На базе `dentatli/ProxyBridge:driver` / `codex/udp-map-source-key`,
commit `b3596272a8dc8898790b016d1e4c488c2fdc917d`, подтверждены три разных
дефекта UDP-пути:

1. **Ключ UDP map в драйвере.** Connected UDP с неявной/wildcard привязкой
   сохраняется под wildcard source address, а relay получает конкретный
   адрес. Это воспроизведено прямыми IOCTL для IPv4 и IPv6 на установленном
   текущем KMDF-драйвере. IPv4 Core A/B повторяет первоначальный отказ.
2. **IPv6 UDP relay в Core.** Все шесть IPv6-вариантов через Core не проходят,
   хотя direct и explicit SOCKS5 controls проходят. Driver-only опыт доставил
   все IPv6-пакеты в локальный relay. В `pb_relay_udp.c` IPv6-ветка использует
   старый get_connection_full_v6, а WFP QUERY_UDP вызывается только в IPv4-ветке.
3. **Демультиплексация IPv4-ответов в Core.** Для двух клиентов одного origin
   ответ A доставлен клиенту B, клиент A получил timeout. В explicit SOCKS5
   control оба клиента получили собственные ответы. Хеш принятого B payload
   точно равен ожидаемому payload A и отличается от ожидаемого payload B.

Следовательно, прежнее решение «исправлять в драйвере» верно для конкретного
wildcard mismatch, но **для исправности всего UDP нужны также изменения Core**.
Продукт не исправлялся в рамках этой проверки; его рабочая копия чистая,
новых product commits/PR нет.

## Объём и идентичность

По уточнению USER использован **локальный режим**: client, origin и SOCKS5
работали на физическом PB-SUT, 192.168.0.157, Windows 26200.9711. Управляющая
VM только собирала код и управляла проверкой. Удалённый Linux-origin исключён
из задания после его SSH timeout; внешние назначения здесь не проверены.
WinDbg, KernelReadCapture, hidden kd и kernel patches не использовались.

CLI и Core свежесобраны из чистого `b359627` штатными MSVC flags в новый private
каталог без запуска общего compile.ps1 с его удалением output/остановкой apps:

- Core SHA256 `37c1575ee688d5de0227b89b9c26257f1364828f4f6a44235ae6676ae8466b83`;
- CLI SHA256 `e9f59cea74918b6a3efa49d595d2afb284fa050b36a937546f23405e3dfd218e`.

Драйвер не пересобирался и не переустанавливался. Использован уже установленный
подписанный HLK-комплект с SYS SHA256
`3e5c3c709ee8c8800628f04b5550f3a82377deb264b045ab2f2ccbab3fd8fb4c`.
Его исходники и vcxproj совпадают с записанным `a75735e`; между ним и текущей
базой в Windows/driver отличается только HLK.md. Это сверка с ранее записанной
идентичностью, а не новая аттестация driver source-to-binary.

В зачтённых product опытах Core вызывался через неизменённый публичный API:
AddProxyConfig=1, AddRule=1, Start=1, Stop=1. Worker — отдельный
`pb_udp_probe.exe` (копия Python interpreter); origin/proxy выполнялись в
controller, чей PID исключён из redirect. Временный Python runtime и DLL
развёрнуты только в новых `C:\PB-UDP-Matrix-20261022-r*`, не в установку продукта.
Полный пользовательский Run TestLab и CLI lifecycle не подтверждены: попытка
захвата оригинального CLI остановилась на readiness gate из-за отсутствия
видимого startup вывода. CLI был собран, но успешный CLI runtime не заявляется.

## Матрица одного пакета

Каждая строка — один неповторяемый nonce payload, connected/send либо
unconnected/sendto, отдельный клиент; deadline ответа 0.8 s. Успех proxy-пути
требует совпадения payload и событий proxy_out → origin → proxy_return.
Это функциональные discriminants, не benchmark и не оценка вероятности потерь.

| Socket / bind | Direct IPv4/IPv6 | Explicit SOCKS5 IPv4/IPv6 | Core IPv4 | Core IPv6 |
| --- | --- | --- | --- | --- |
| connected / implicit | PASS / PASS | PASS / PASS | timeout, до SOCKS5 не дошёл | timeout, до SOCKS5 не дошёл |
| connected / wildcard | PASS / PASS | PASS / PASS | timeout, до SOCKS5 не дошёл | timeout, до SOCKS5 не дошёл |
| connected / concrete loopback | PASS / PASS | PASS / PASS | PASS | timeout, до SOCKS5 не дошёл |
| sendto / implicit | PASS / PASS | PASS / PASS | PASS | timeout, до SOCKS5 не дошёл |
| sendto / wildcard | PASS / PASS | PASS / PASS | PASS | timeout, до SOCKS5 не дошёл |
| sendto / concrete loopback | PASS / PASS | PASS / PASS | PASS | timeout, до SOCKS5 не дошёл |

Direct controls: 12/12. Explicit SOCKS5 controls: итоговые 12/12.
Core: IPv4 4/6, IPv6 0/6. В зачтённых IPv4 successes SOCKS5 route подтверждён;
прямой обход продукта за proxy PASS не выдавался.

## Driver-only IOCTL и lifetime

Текущий KMDF-драйвер допускает одного владельца device session, поэтому
параллельное открытие read-only handle во время Core работы дало error 5.
Это не found=0 и не свидетельство отсутствующей map. Ограничение не обходилось.

В отдельном опыте r5 controller стал единственным владельцем, штатными IOCTL
задал config/watchlist одного probe image и включил redirect. Его обычные UDP
relay sockets получили и вернули все 12 пакетов. QUERY_UDP выполнялся тем же
owner handle прямо при приёме пакета, а затем после выхода worker:

- connected + implicit/wildcard: exact lookup=0, wildcard lookup=1;
- connected + concrete и все sendto: exact lookup=1, wildcard lookup=0;
- результат одинаков для IPv4 и IPv6; найден original destination соответствовал
  заданным 127.0.0.1:46001 / [::1]:46001, IOCTL успешно вернул 52 bytes;
- сразу после выхода каждого worker соответствующая запись всё ещё found=1.

Это отдельные driver-only flows, а не IOCTL из Core потоков r4/r6. В новом
KMDF варианте PbResetSession очищает map при завершении owner session;
внутри живой session endpoint closure cleanup не реализован. Нужны требования
к endpoint lifetime/port reuse; слепой wildcard fallback остаётся неприемлемым.

## Два клиента одного IPv4 origin

Для этого отдельного опыта timeout=2 s. Origin удержал payload A до получения B,
затем вернул оба. Explicit SOCKS5 использовал разные association: A/B PASS.
Core использовал общий UDP association proxy config: A timeout, B получил A.

В `Windows/src/relay/pb_relay_udp.c` reply path выбирает наиболее недавно активного
клиента по одному remote IP/port. Это не однозначная идентичность клиента.
Исправление должно сохранять принадлежность ответа, например выделением
различимых upstream UDP flows/associations; разбирать содержимое пользовательских
пакетов или выбирать «последнего клиента» для этого нельзя.

## Методические границы и разделение попыток

- r1: driver service был Disabled / PnP code32, workload не начался.
- r2: informational stderr SOCKS server прервал PowerShell collector; только
  progress одного direct case, полного результата нет, PASS серии не заявляется.
- r3: direct 12/12 пригодны. Explicit controls некорректно использовали
  advertised BND.ADDR 0.0.0.0; CLI readiness не прошёл. Product checks отсутствуют.
- r4: исправлена подстановка TCP peer вместо wildcard BND.ADDR в probe;
  public Core API дал пригодные IPv4 matrix и paired-client capture.
  IPv6 explicit control не дошёл до origin, поэтому IPv6 вывод из r4 не засчитан.
- r5: отдельный single-owner driver IOCTL опыт, все 12 raw relay exchanges получены.
- r6: только IPv6 cases; диагностический adapter передаёт IPv6 sockaddr как
  четырёхэлементный tuple в Windows asyncio. После этого explicit 6/6,
  Core 0/6. Pinned asyncio-socks-server wheel 1.3.3 сохранён без изменения;
  runtime adapter находится в исходнике probe и раскрыт в payload manifest.

Успешные IPv4/direct cases повторно ради итоговой таблицы не запускались.
Нагрузочные HIGH, многодестинационный UDP одного сокета, external routing,
reconnect/reuse endurance и производительность не проверены.
Поддерживаемые product tests не добавлялись по запрету USER.

## Восстановление и свидетельства

Изначально установленная служба была Stopped/Disabled, PnP problem32. Для
ограниченных опытов она временно переводилась в Manual и перезапускалось только
её root PnP device. Финальный read-only capture подтвердил возврат в
Stopped/Disabled/problem32; HLKsvc Running, sample services Stopped,
listeners34010/34011=0, probe/controller/CLI processes=0. Installed product files
в Program Files и SYS сохранили исходные hashes. BCD, trust/signing, system proxy,
hypervisor, питание ОС и установка драйвера не менялись. WinRM wrapper восстановил
клиентские service/TrustedHosts, cleanup_errors пусты.

Private source/build/manifest/review:
`artifacts/diagnostics/udp-current-matrix-20261022-r1`.
Captured results: `artifacts/diagnostics/udp-current-target-20261022-r{3,4,5,6}`;
final state: `udp-current-final-state-20261022-r1`.
`review.py` проверил route events, payload cross-delivery, map values, Core hash,
неизменность installed files и финальное состояние.

SHA256 result.json:

- r3: `c1d40f53cb1a0819dcaf1b457e5b24a55d3cbe0ec820f59023313f22f419f283`;
- r4: `abb9e0234d0f3bf18b24d6b1364911c5a05d194006ce5d06ca4fce72e05e0121`;
- r5: `2eeb4d30010310a1ab3a4d5f200572a4aa5314593a970b1a8da1e2854daf7629`;
- r6: `0e51d8de348bb41044b20c834442415cdf1429c40f5ef6a79e67ee1a72d85dec`.

Следующее product исправление готовить только в `codex/udp-map-source-key`.
PR/слияние в `driver` — по отдельному требованию USER, Squash and merge.
