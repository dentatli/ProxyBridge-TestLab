# Независимая проверка redirect context на тестовом физическом ПК

## Результат получен

[Независимый опыт](INDEPENDENT_WFP_RESULT_2026-10-21.md) подтвердил original
query10022/0 после queue-refused SYN/retries с Microsoft WFPSampler, без
работающего ProxyBridgeDrv. Healthy и200fillers успешны; ETW loss0. Фактический
build после restart26200.9711. Все временные filters удалены, sample службы
остановлены, HLK работает. Точная внутренняя причина/исправление Windows ещё
не доказаны. Ниже история подготовки, а не очередь повторных запусков.

## Продолжение с расширенным разрешением USER

USER разрешил необходимые действия до результата без обязательного отдельного
отката. Комплект скопирован на target. Первая установка остановилась до создания
sample services: ProxyBridgeDrv отказал в stop с1052. Его startup переключён
с Manual на Disabled, запланированный restart вернул0. Новый boot и состояние
HLK после restart пока не подтверждены; RDP доступен, WinRM закрыт. USER получил
команду Start-Service WinRM. Это блокер доступа, не результат сетевого опыта.

`Install-IndependentWfpSample.ps1` использует SCM/demand-start для KMDF non-PnP,
затем официальный service -i (включая его SafeBoot keys), переводит sample
user service на demand-start. Новый trust, INF, BCD не требуются.
[Microsoft: installing a non-PnP KMDF driver](https://learn.microsoft.com/en-us/windows-hardware/drivers/wdf/installing-a-non-pnp-driver).

`Invoke-IndependentWfpTrial.ps1` подготовлен и прошёл PS5 parser, но ещё не
запускался. Healthy должен подтвердить context256/один query/512KiB; Target
проверяет200fillers и один control с ETW. ETW_PENDING статусы требуют отдельного
анализа trigger/loss; они не доказывают Windows root cause. Во время остановки
доступа дальнейших workload/установок не выполнялось. Точный текущий checkpoint
и private evidence paths — в diagnostic handoff.

## Текущий результат подготовки

WinRM реально проверен на PB-SUT с административными правами под подтверждённым
USER аккаунтом. Remote wrapper восстанавливает client TrustedHosts и состояние
client WinRM; cleanup errors пуст. Пароль не записан в repo/evidence. Target:
Windows11Pro26200.9457/x64/16GiB, SecureBootOff/testsigningYes; ProxyBridgeDrv
Running/Manual, HLKsvc Running/Auto. Target driver и OS отличаются от исходной VM.

Официальный sample закреплён на revision
`bb68ed5e770bce04dc5395ec9258dafab034184d`, собран Release/x64 с WDK28000,
build exit0/API validation Universal. Исходники Microsoft не менялись.
Отдельный `src/independent_wfp/WfpContextProbe.cs` собран с warnings-as-errors,
help exit0, без открытия sockets. Он делает один query на accept, проверяет
256байт sample context и исходное назначение, передаёт/проверяет512KiB.

Private staged kit содержит sample CLI/service/SYS и probe. Копия SYS подписана
существующим сертификатом: sign exit0, Authenticode Valid. Target уже доверяет
этому сертификату; trust/BCD не менялись, private key не экспортировался.
Это ещё не installation-ready kit: trial controller, ETW и установка/откат
требуют завершения. Никакого независимого runtime результата пока нет.

Штатный INF BOOT_START не подходит для временной установки по умолчанию.
DriverEntry использует KMDF1.15/non-PnP: framework binding надо учесть до выбора
способа установки. Не запускать штатный глобальный installer. Первый опыт
провести без KD points, временно исключив ProxyBridgeDrv и восстановив его
состояние; HLKsvc не останавливать. Исторические pending-статусы ниже сохранены
для контекста и заменены этим checkpoint.

## Доступ к физическому ПК: текущий checkpoint

RDP подключён, через SystemInformation наблюдены имя PB-SUT, Windows11Pro
build26200/x64/16GiB и SecureBootOff. Точный UBR пока не получен. Driver status
не проверен; desktop icons не являются его доказательством. Исходная VM имеет
build26100: отличие OS учитывать в выводах, не менятьtargetOS автоматически.
Адрес и access audit сохраняются private, credentials не включать вkit/docs.

SSH/WinRM ports пока недоступны; DCOM OSquery завершился timeout. Настройки
target не менялись. Следующий шаг USER — включить встроенный WinRM в ADMIN
WindowsPowerShell непосредственно на target. Это запускает/настраивает WinRM
service, listener и firewall; отдельная установка приложения не требуется.
Default public-network rule сохраняет local-subnet scope. Не добавлять
AllowUnencrypted/Basic/широкий TrustedHosts для этого шага.

[Enable-PSRemoting](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/enable-psremoting?view=powershell-5.1).
Автоматизация терминала черезRDP UI не применяется; после ручной настройки
проверить фактическое remote execution и затем запускать inventory script.

## Исходный план

USER предложил отдельный физический Windows ПК в той же LAN и удалённое
управление. IP/имя и существующий канал доступа пока ожидаются. Не предполагать
наличие SSH/WinRM, совпадение OS build, тестовой подписи или разрешённого KDNET.
Пароли и debugging keys не помещать в чат/коммиты. Сначала read-only inventory.

## Что сравниваем

Проверяем воспроизведение queue-refused SYN -> retry -> accepted endpoint без
redirect context с независимым callout Microsoft WFPSampler и отдельным маленьким
Winsock-тестером. ProxyBridge Core/драйвер не входят в независимый опыт.
На целевом ПК не должны одновременно работать redirect policies ProxyBridge
и тестового sample; прочие callout/состояние WFP нужно зафиксировать до Run.
Отсутствие ошибки на другой Windows build не оправдывает исходный стек:
сначала сравнить полную Version/Build/UBR и сохранить различия.

## Последовательность

1. Получить target IP/hostname и канал доступа. Для команд/файлов — SSH либо
   WinRM; WinDbg служит отдельным каналом диагностики ядра. Без открытого доступа
   пользователь выполнит одну конкретную настройку локально; команды зависят от
   выбранного канала. Пока никакие порты/firewall/services не менялись.
2. Выполнить на TARGET Get-IndependentWfpTargetInventory.ps1. Он только читает
   Windows version/UBR/архитектуру/память, состояния SSH/WinRM и matching driver
   services, SecureBoot registry. Ошибки получения optional SecureBoot сохраняются,
   а не превращаются в утверждение SecureBoot=off. Не запускать вместо этого на
   PB-BUILD и не считать output оттуда инвентаризацией физического ПК.
3. Зафиксировать revision/hash официального sample, подготовить отдельную копию
   источников/комплект и команды установки/возврата. Сборка, подпись, установка,
   trust/BCD/reboot — отдельные явные шаги после inventory, не автоматический
   запуск штатного WFPSamplerInstall.cmd. При необходимости изменения SecureBoot/
   подписи заранее показать точный план; исходную лабораторную VM не менять.
4. Независимый tester сначала запускает listener и сообщает PID для local proxy
   policy. Sample filter должен совпадать только с IPv4/TCP test loopback tuple/
   original destination port и нужным test application. Не использовать broad
   redirect и не выполнять глобальный WFP clean-all. Только remote-destination
   redirection; -pla/-plp (изменение local tuple) для этого опыта не применять.
5. Сначала healthy control: один connect/accept, один исходный context query,
   проверка размера/оригинального назначения. Затем один отдельный target trial:
   известный prefill, удержание accept, один control connect, release/drain и
   один original query на каждом accepted socket. Все сокеты ограничены timeout,
   результаты привязаны к PID/TID/tuple; failure не маскировать повторным query.
6. ETW должен подтвердить именно queue-refused SYN/retry и отсутствие потерь.
   Неполный trigger или другие ошибки дают INCONCLUSIVE. Первые trials без
   активных WinDbg breakpoints. KD подключать только если он даст недостающие
   данные; Break приостановит весь целевой физический ПК, включая его RDP/SSH.
7. Сохранить manifest/исходный API error/bytes/context size, ETW и cleanup.
   Удалять только созданные sample policies/services по их ownership. После
   failure не повторять тот же consumed trial автоматически.

## Две важные особенности официального sample

В проверенном upstream ClassifyFunctions_ProxyCallouts.cpp context содержит
два SOCKADDR_STORAGE, то есть256байт. Тестер должен учитывать этот формат;
32-байтовый буфер ProxyBridge здесь неприменим. Размер фиксируется по выбранной
revision; healthy control обязателен до интерпретации10022.

В Scenarios_Proxy.cpp опция -prs означает remote service, а -plspid задаёт PID
local service. Для local loopback test -prs применять нельзя: иначе изменяется
сам проверяемый механизм local redirection. Точные готовые команды policy
будут выданы после pin revision, проверки CLI и определения TARGET listener PID.

## Интерпретация

Если независимый sample/tester воспроизводит тот же signature на сопоставимом
OS build, это серьёзное основание для Windows issue без участия ProxyBridge.
Если нет — проверить совпадение trigger/редиректа/версий и затем сравнивать
реализации. Ни отсутствие повторения, ни один лишь backlog1024 не доказывают fix.

На этом checkpoint подготовлены inventory script и этот план. Source download,
reference build/tester implementation, target connection/install/traffic/KDNET
ещё не выполнены. Исходные captures/kits/driver installation не менялись.

## Официальные источники

- [WFPSampler и компоненты](https://learn.microsoft.com/en-us/samples/microsoft/windows-driver-samples/windows-filtering-platform-sample/).
- [Sample context allocation](https://github.com/microsoft/Windows-driver-samples/blob/main/network/trans/WFPSampler/sys/ClassifyFunctions_ProxyCallouts.cpp).
- [Sample proxy CLI](https://github.com/microsoft/Windows-driver-samples/blob/main/network/trans/WFPSampler/exe/Scenarios_Proxy.cpp).
- [Bind/connect redirection contract](https://learn.microsoft.com/en-us/windows-hardware/drivers/network/using-bind-or-connect-redirection).
