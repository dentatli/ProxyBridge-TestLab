# Передача новому чату: UDP/SOCKS5 и физический PB-SUT

## Обновление: причина локализована на исходном комплекте

См. [UDP map address mismatch](UDP_MAP_ADDRESS_MISMATCH_2026-10-22.md).
Свежий bounded A/B на управляющей VM с существующим комплектом 63be0eb:
неявный bind даёт wildcard map key и промах lookup по фактическому адресу;
явный bind 127.0.0.1 даёт точный lookup и подписанный ответ через SOCKS5.
Компоненты direct/explicit SOCKS5 работают. Продукт/драйвер не менялись,
driver service возвращён в Stopped. PB-SUT проверен только read-only;
его другой установленный driver этим результатом не аттестован.
Место исправления определено: нормализовать ключ при регистрации UDP map
в драйвере ClassifyCore/UdpMapPut; точный lookup relay сохранить. Слепой
wildcard fallback отвергнут из-за stale/ownership неоднозначности таблицы.
Алгоритм и границы описаны в отчёте; патч продукта ещё не реализован.
Ниже сохранена исходная передача; её план первых проверок уже частично выполнен.

## Предлагаемая следующая проблема

Разобрать отсутствие UDP-ответов через SOCKS5 в сценарии лаборатории.
Это отдельная задача от уже установленного механизма TCP10022. Пока не
объявлять её ошибкой драйвера: старые свидетельства содержат проблемы
методики и неполную видимость маршрута.

В попытке14октября четыре UDP flows отправили по одному пакету и получили0
ответов; процессы записали UDP_TRANSPORT_FAILED, без исходного OSError.
Завершение произошло быстро, expired=0: это не четыре доказанных таймаута.
OFF/UNRULED controls проверяли TCP echo, а не прямой UDP. Подробности:
[исходный разбор](TRAFFIC_FAILURE_OFFLINE_REVIEW_2026-10-14.md).

В том разборе найден числовой ProxyConfigs.Port при string-only CLI. На момент
передачи актуальная development-копия уже содержит str(binding["proxy_port"])
в src/trafficlab/runner.py:50, а product.py сохраняет вывод CLI и проверяет
startup config/rules. Не чинить это повторно по старому документу: сначала
проверить текущую ревизию, применяемую сборку и существующие свежие captures.
Статическая правка не равна доказанному исправлению UDP runtime.

Первые различающие шаги нового чата:

1. Прочитать AGENTS.md, проверить Git status и текущую реализацию.
2. Установить, остался ли отказ после исправления профиля; проверить реально
   загруженный SOCKS5 config и правило, сохранить исходные ошибки.
3. Разделить прямой UDP, явный SOCKS5 UDP ASSOCIATE и маршрут через продукт.
   TCP control не заменяет UDP control. Нужны подтверждения доставки в обе
   стороны, корректного relay endpoint и владения UDP mapping.
4. Начать с короткого bounded обмена, без HIGH и WinDbg. К ядру переходить
   только если захват пакетов/логи локализуют проблему именно там.

В этом чате новая диагностика UDP и новые target workloads не начинались.
Пользователь просит экономить лимит Codex: адресные чтения и один
различающий опыт за раз, без сотен проверок и повторов успешных проверок.
Пользователь запретил добавлять тесты в продуктовую ветку.

## Рабочие копии и закрытый TCP вопрос

Актуальный [порядок работы с ветками продукта](PRODUCT_BRANCH_WORKFLOW.md):
fork `driver` синхронизирован с upstream `Driver` (`63be0eb`); два запрошенных
PR в fork открыты, но не слиты. Каталог `C:\src\ProxyBridge-accept-first`
теперь на новой `codex/udp-map-source-key` от fork `driver`; ниже прежняя
привязка этого каталога к accept-before-setup описывает состояние передачи.
Новые PR в `driver` — только по явному требованию пользователя.

- Диагностика: C:\src\ProxyBridge-TestLab, codex/checkpoint-20261007.
- Разработка: C:\Users\LabAdmin\.codex\worktrees\testlab-development\ProxyBridge-TestLab,
  codex/development-functional-completion. HEAD при чтении d5b51f3; status clean.
  Не переключать/переписывать эту копию из диагностической задачи.
- Изменение продукта accept-before-setup: C:\src\ProxyBridge-accept-first,
  codex/accept-before-setup, commit37e64c6e835a64833f1d3ae385052bb2125b93e6.
- [Issue ProxyBridge273](https://github.com/InterceptSuite/ProxyBridge/issues/273)
  создан от dentatli; название начинается [Windows]:[Driver]. Автору задан
  вопрос, нужен ли отдельный PR. Сам PR пока не создан.
- [Механизм TCP](TCP_CONTEXT_SINGLE_FLOW_CONFIRMED_2026-10-22.md) подтверждён:
  ранний RST → bit0x200000 → SYN retry без redirect metadata → acceptedEP без
  record →10022. Не открывать старую серию заново ради этого же вывода.
- [Отчёт Microsoft](MICROSOFT_WFP_REDIRECT_CONTEXT_BUG_REPORT_2026-10-22.md)
  подготовлен, но не отправлен. Подтверждения Microsoft/source fix ещё нет.

Untracked src/independent_wfp/KernelReadCapture.cs сохранён как свидетельство;
не запускать, не коммитить, не удалять как «лишний файл».

## Физическая тестовая машина

Есть отдельный физический ПК PB-SUT, IPv4 **192.168.0.157**, Windows build
26200.9711 на последней проверке. Ранее использовался для HLK. Это target;
VM с Codex — управляющий host. Доступны WinRM/PowerShell Remoting и RDP.
Правильный пользователь **PB-SUT\PB-USER**, не ранее ошибочно названный PR-USER.
Пользователь разрешил управление тестовым ПК; повторно спрашивать о наличии
машины/доступа не нужно. Новые действия выбирать по текущей задаче и AGENTS.md.

Учётные данные сохранены **вне Git**, Windows DPAPI:
`C:\Users\LabAdmin\.codex\private\pb-sut-winrm.credential.clixml`.
Файл создан и успешно прочитан под текущим LabAdmin, ACL только этому SID и
SYSTEM. Пароль не выводить и не записывать в исходники, отчёты, аргументы
процессов или чат. Import-Clixml работает только в соответствующем контексте
Windows; не переносить этот файл на другой ПК как обычный credential.

### Проверенный способ WinRM

Использовать существующий wrapper
`C:\src\ProxyBridge-TestLab\scripts\Invoke-IndependentWfpRemote.ps1`.
Он проверяет имя target, временно включает **клиентский** WinRM и добавляет
только target в TrustedHosts, затем восстанавливает клиентские настройки.
Вызов требует elevated PowerShell; CoS Core exec_command в этой сессии имел
такой доступ. Обычный builtin exec_command не был elevated. Не менять
ExecutionPolicy глобально. ScriptPath выполняется на PB-SUT, не локально.

Подготовлена только read-only проверка target:
`C:\src\ProxyBridge-TestLab\artifacts\diagnostics\pb-next-chat-20261022\read-state.ps1`.
Файл существует локально, но не в Git; в этой передаче он ещё не запускался.

Пример первого вызова из elevated PowerShell, из C:\src\ProxyBridge-TestLab:

```powershell
$credential = Import-Clixml 'C:\Users\LabAdmin\.codex\private\pb-sut-winrm.credential.clixml'
$evidence = Join-Path 'C:\src\ProxyBridge-TestLab\artifacts\diagnostics' ('pb-sut-inventory-' + [guid]::NewGuid().ToString('N'))
$wrapper = Get-Content 'C:\src\ProxyBridge-TestLab\scripts\Invoke-IndependentWfpRemote.ps1' -Raw -Encoding UTF8
& ([scriptblock]::Create($wrapper)) -ComputerName '192.168.0.157' -ExpectedComputerName 'PB-SUT' -Credential $credential -ScriptPath 'C:\src\ProxyBridge-TestLab\artifacts\diagnostics\pb-next-chat-20261022\read-state.ps1' -EvidenceDirectory $evidence
```

Проверять result.json и command-output.json, а не только exit shell.
Каждый evidence directory должен быть новым. RemoteCollectDirectory wrapper
может собрать уже существующий каталог target без повторного Run.
При потере WinRM сначала проверить, не paused ли target в WinDbg. Если это
не пауза — пользователь раньше восстанавливал доступ входом PB-USER по RDP;
на машине может быть сессия HLK. Не останавливать HLKsvc без причины.

## WinDbg: только физический target

Пользователь явно разрешил запуск и управление WinDbg внутри agent VM для
PB-SUT. VM с Codex **никогда не должна быть debuggee**. Старый named pipe
PB-Context-KD к agent VM не использовать.

Уже установлен GUI:
`C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\windbg.exe`,
версия10.0.28000.2526. На последней проверке один GUI process PID12264,
подключён к физическому target; PID и состояние надо перепроверить, не
запускать второй debugger вслепую. Нейтральный title начинался PB-SUT-physical.
UI управлялся через computer-use skill и @oai/sky; перед использованием
прочитать skill. Окно запущено без elevation для доступности UIA.

KDNET target настроен на host192.168.0.136:50055. Это адрес настройки того
сеанса, а не обещание неизменности сети. Transport key/спецификация сохранены
приватно в
`C:\src\ProxyBridge-TestLab\artifacts\diagnostics\pb-gui-single-flow-20261022-r1\private-transport.txt`.
Не печатать содержимое, process CommandLine или ключ в title/screenshot/log.
При новом GUI запуске задавать нейтральный -T; не переустанавливать/не менять
BCD/KDNET лишь ради обычной проверки UDP.

Перед Break/enable/step предупредить о паузе **физического PB-SUT**, включая
WinRM/RDP, и заранее приготовить снятие своих точек + отдельный g.
К agent VM эта пауза относиться не должна. GUI command files — ASCII/CRLF,
`$<file` выполняет строки отдельно; g может быть последней отдельной строкой.
`$$><` склеивает строки; .sympath/.wtitle могут поглотить остаток команды.

**Не использовать KernelReadCapture и hidden kd с redirected stdout/stderr:**
этот прежний путь сопровождался зависанием VM. См. VM_FREEZE_2026-10-21.md.
Разрешённый GUI использует внутренний -logo; это другой путь вывода.

## Последнее проверенное состояние, не текущая гарантия

После TCP capture22октября: PB-SUT возобновлён g; software IDs2/4/5/6 disabled,
hardware3 удалён; sample filters0, probe0, listener34010 отсутствует.
WFPSampler, WFPSamplerCallouts, ProxyBridgeDrv Stopped; HLKsvc Running.
Новый чат обязан сверить состояние перед нагрузкой, особенно после reboot.
На target остался C:\PB-Independent-Wfp-20261022-r7: это диагностический
комплект sample, **не** установленная новая версия ProxyBridge.
Frozen kits/captures сохранять; consumed trials не повторять/Resume/refreeze.

Этот файл передаёт инфраструктуру и новую задачу, а не очередь всех старых NEXT.
