# WFP и WinDivert: выполнение согласованного сравнения

Scope: сравнение существующих50сценариев, NORMAL/LOW, без суточного soak, локальный режим. Не исследовать и не исправлять причины ошибок продукта. User явно разрешил установку подготовленного WFP; отдельно разрешил «Добавь и оставь» сертификат в TrustedPublisher и автоматическую подготовку нужного доступа брандмауэра. Product branches/PR не изменяются.

## Комплект и установка

CLI/Core b3596272a8dc8898790b016d1e4c488c2fdc917d, сохранённый SYS SHA3e5c3c709ee8c8800628f04b5550f3a82377deb264b045ab2f2ccbab3fd8fb4c из baseline package с matching preparation receipt. SYS не пересобирался; provenance нельзя выдавать за новую kernel build из этого commit. Bundle `artifacts/product-builds/driver-b359627-wfp-comparison-20261024-r1`,5public files/manifest. Native Windows/installer/driver-setup.c exact b359627 собран MSVC18 /W4/WX; helperSHA519054c485596f8c2f04e9324897151450982878216b493ac4d9a61b4a31aaf6.

- r1: Windows отказала импортировать каталог с0xE0000242 (издатель не trusted). Предыдущий legacy63service восстановлен; файлы/логи сохранены отдельно.
- Root уже содержал сертификат CN=ProxyBridge Test Signing/4544323109A45FC4761819E079BBDBD5E0BFE8D6. После отдельного ответа пользователя тот же сертификат добавлен только в LocalMachine TrustedPublisher и **должен остаться**. Root/BCD/signature mode не менялись. Это соответствует документированному [требованию Plug and Play к издателю](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/trusted-publishers-certificate-store).
- r2: native install0. Попытка применить legacy SCM Stop к PnP-драйверу отказала. Owned remove вернул3010; root node/package удалены, native наблюдение подтвердило отсутствие загруженных interception drivers/известных WFP объектов. Оставшаяся Stopped SCM-конфигурация уже отсоединённого пакета восстановлена к точной legacy-конфигурации без удаления PnP-owned службы; registry/SDDL/Stopped/Manual сверены. **Перезагрузки не было**. Native stderr reg.exe с success первоначально прервал wrapper; обработка исправлена, rollback завершён и verified. Не скрывать эти неуспешные попытки.
- r3: свежая установка0; вместо SCM Stop устройство отключено штатным PnP API. Instance ROOT\INTERCEPTSUITE_PROXYBRIDGE\0000, problem22, serviceStopped/Manual. Installed path `C:/WINDOWS/system32/DriverStore/FileRepository/proxybridgedrv.inf_amd64_5c4d115994d90995/ProxyBridgeDrv.sys`, SHA соответствует baseline. Никаких экспериментальных SYS/tcp-direct-route.

Логи, SCM registry/SDDL backups, helper и управляющие scripts только ignored `C:/src/ProxyBridge-TestLab/artifacts/wfp-comparison-20261024-r1/r2/r3`. Не возобновлять старые диагностические trials, не менять их manifests. Текущая установка — отдельный новый scope.

## Исправление лабораторного жизненного цикла

Source87c8d05/preview36: локальный WFP использует один PnP Enable до Core и Disable после закрытия Core, один lease на очередь. Между case только rules. Проверяются binding id, instance id/hardware id/service, configured path/SHA, исходный disabled22+Stopped+unloaded+known-WFP-detached, отсутствие других product processes;_DISABLE разрешён только владельцу lease. Lease сохраняется до Enable, чтобы cleanup работал и при частичном запуске. Итог требует disabled22/Stopped/unloaded/known-WFP-detached. Неудача не даёт PASS. WinDivert и remote обходят этот локальный adapter; legacy WFP без rootnode не меняется.2необходимых regression tests PASS; live отдельный Enable0/Disable22 cycle PASS.

Штатный gate36 `20261024-091030-9ce22789e0c540a2be1f5e489ec9c6d1`: TCP RTT SHORT/LOW **PASS**, UDP connected **FAIL** (transport/route/loss). Start1/Stop1, device_start/device_restore verified, обе cleanup=true. Сетевые причины продукта не исследовались.

## Автоматическая подготовка брандмауэра

По просьбе пользователя sourcee4d083c/preview37 заранее создаёт две scoped inbound allow rules для exact path pb_core_host.exe и встроенного python.exe, до их сетевых операций. Все profiles, но LocalAddress и RemoteAddress только127.0.0.0/8; никаких входящих из LAN/Internet. NetSecurity отвергает IPv6 loopback literal, IPv6Any взамен не открывается. Прежние profile settings/notifications/firewall enablement и чужие правила не меняются. Per-path stable rule id/group, проверка ActiveStore, action/direction/protocol/address scopes, отказ при несовпадении собственного rule. JSON evidence local-firewall.json сохраняется в private attempt. [Microsoft описывает предварительные application rules как способ избежать запроса](https://learn.microsoft.com/en-us/windows/security/operating-system-security/network-security/windows-firewall/rules).

Preview37:1483SHA matched, .NET publish успешен, controller admin/5178. Gate `20261024-091936-b792562550cd4f6dbd0e75413f170f22`: TCP SHORT/LOW **COMPLETE**, обе cleanup=true, firewall rules автоматически created=true/verified. Desktop inventory после gate не содержит диалога Windows Security. Профили не менялись. Старые36per-path loopback rules оставлены, записи не расширены до внешней сети.

## Полные попытки

WFP full50 `20261024-092130-df12a766a3b8486d85e3a58bd45f3c6b` на37 завис на SSH после36 сценариев. По новому явному разрешению пользователя остановлен, WFP восстановлен в disabled/Stopped;36 исходных отчётов сохранены.25 workload complete/11 failed — частичные измерения, финальная capture gate отсутствует, итогового сравнения нет. Подробности и минимальное исправление: [SSH/SFTP deadline](SSH_WORKER_DEADLINE_2026-10-24.md). Полный50 автоматически не перезапускать; WinDivert на той же актуальной версии ещё не запускался. Старые runtime и captures неизменны. Продуктовые причины FAIL отложены в отдельный чат.
