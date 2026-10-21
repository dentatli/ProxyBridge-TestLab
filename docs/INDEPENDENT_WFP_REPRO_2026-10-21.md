# Независимая проверка redirect context на тестовом физическом ПК

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
