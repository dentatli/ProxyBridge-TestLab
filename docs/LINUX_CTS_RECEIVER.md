# Linux-получатель для контроля WFP context

Парный product-контроль подготовлен 2026-10-07: [новый local/Linux kernel/Core/TCP/Winsock опыт](TCP_CONTEXT_EXTERNAL_RECEIVER_CONTROL.md), FINAL093635-91ea36ae, все три бинарника прежние. Реальный paired Run ещё не выполнен. Linux SSH Inspect подтвердил установленный receiver; новый слушатель не запускали. Обычный UI remote controller остаётся заблокирован.

2026-10-07: root SSH по отдельному ключу проверен, Linux receiver установлен и его SHA256 совпадает с локальным файлом. Ubuntu 22.04.5 LTS, Python 3.10.12, systemd. Адреса, приватный ключ и connection profile находятся в LocalAppData вне публичного конфига. Ключ хоста закреплён в отдельном known_hosts по явному поручению пользователя проверить уже доступное SSH-соединение; это не независимая консольная проверка.

## Реальные проверки

**USER Run 2026-10-07 завершён:** настоящий Windows ctsTraffic подтвердил 4/4 соединения, 2 MiB, NetworkErrors=0/ProtocolErrors=0, natural exit0. Linux подтвердил те же GUID, шаблон/hash/DONE и clean service stop/exit0. Первоначальный strict v1 отчёт остался INCOMPLETE из-за требования одинаковых адресов/портов на двух машинах. Windows — Hyper-V VM; native local и Linux peer различаются, что совместимо с NAT, но его механизм не наблюдался. Отдельная переоценка сохранила все 19 USER-файлов и подтвердила wire/data совместимость без повторного прогона: `artifacts/diagnostics/linux-cts-compat-review-20261007-080842/reevaluated-final/summary.md`.

Первый короткий Linux-прогон подтвердил LISTENING → контролируемый STOPPED → ExecStopPost exit 0 без соединений. Второй использовал независимый Python-клиент на самой VM: четыре одновременные передачи по 512 KiB прошли, четыре неблагоприятных случая (повреждённый байт, ранний EOF, лишний байт, reset до завершения) отклонены. SHA журналов, счётчики и exit receipt проверены. Получатель остановлен; файлы и журналы сохранены.

Это не проверка настоящего Windows CTS, внешнего маршрута ProxyBridge или ёмкости внутренних таблиц. CAPTURE_COMPLETE означает полноту журнала и остановки: ошибки передачи в нём могут присутствовать.

## Реализация

`src/pb_cts_push_receiver.py` независимо реализует только IPv4 TCP push/data-only для CTS 2.0.3.9, commit `b0e2a48f30fb7caaaa9994ee2dea2a177a4639e2`, SHA Windows exe `0548089e59c872306ce2c98e7163e2a717119756010cf64d3cb3da2854f632cf`. Сервер отправляет UUID (36 ASCII + NUL), проверяет объём последовательности uint16 LE с периодом **65536 байт**, затем отправляет `DONE` (4 байта). Reset после DONE сохраняется как наблюдение закрытия; reset до него — ошибка. Основание: [Microsoft ctsIOPatternState.hpp в закреплённом commit](https://github.com/microsoft/ctsTraffic/blob/b0e2a48f30fb7caaaa9994ee2dea2a177a4639e2/ctsTraffic/ctsIOPatternState.hpp), соседние ctsIOPattern.cpp/ctsStatistics.hpp и проверенный локальный source receipt. Штатное закрытие и производительность Windows receiver не воспроизводятся автоматически.

`src/pb_linux_cts_control.py` принимает ограниченный JSON stdin через SSH. Versioned deployment по SHA, transient systemd/DynamicUser/LimitNOFILE=2048/NoNewPrivileges, точный адрес источника, лимиты времени/числа соединений/журнала. Глобальный firewall и SSH-конфиг не меняются. Остановка только собственного unit; ошибка readiness вызывает его остановку с сохранением первоначального отказа. ExecStopPost сохраняет завершение после выгрузки transient unit из systemd.

`scripts/Invoke-LinuxCtsReceiver.ps1` использует private profile, строгий host key и ключевую аутентификацию. Collect допускается после остановки, сверяет SHA байтов и сохраняет журнал без вывода base64. Данные запроса не интерполируются как shell-код.

## Настоящий Windows CTS: короткий контроль

`scripts/Invoke-LinuxCtsCompatibility.ps1`: Prepare / Inspect — только файлы; Run — четыре прямых соединения по 512 KiB @ 64 KiB/с, ConnectEx/32, verify:data, shutdown:rude. ProxyBridge не запускается. Plan закрепляет источники, exe, Python, private profile/known_hosts/public key и базовые файлы продукта. Перед/после сохраняются обязательные WFP/WinDivert/loaded-drivers/process observations. Общие mutex/lease исключают параллельный lab Run. Запись восстановления диагностического драйвера и история legacy/interrupted jobs требуют новой загрузки Windows, где применимо. Receiver останавливается и собирается также при ошибке клиента.

`pb_linux_cts_compatibility_report.py`: default strict-reciprocal/v1 сохраняет прежний результат. Opt-in guid-correlated/v2 подтверждает wire/data по точным уникальным GUID, destination/allowed source, объёму/hash, согласованности accepted/verified/end/order и полной остановке. Различие native local ↔ receiver peer выводится явно; direct_endpoint_reciprocity_verified и translation_mechanism_verified отделены от native_client_compatibility_verified. Это не доказательство NAT-конфигурации или непрерывного packet route. Неполные данные/ошибки/неизвестный источник/другие GUID/hash остаются INCOMPLETE. Проверены saved positive, synthetic v2 positive, прежний strict positive/точно прежний USER failure и 23 повреждённых варианта.

Первоначальный handoff `linux-cts-foundation-review-20261007/HANDOFF.md` выполнен пользователем и больше не является NEXT-командой. Новый v2 files-only план `linux-cts-compatibility-preparation-20261007-081522-8d38f129` имеет отдельный method/endpoint_policy; PS5Prepare/PS5PS7Inspect FILES_VALIDATED. Старый план отказывает, не refreeze/Resume. Новая offline переоценка требует свежий --output-directory и не перезаписывает оригинал. Нового runtime не было: ради исправления отчёта повторять успешную передачу не требуется. Агенту разрешены проверки менее 5 минут; обход UAC/парольный вход не разрешён.

## Следующая стадия

Native контроль завершён. Следующий опыт — opt-in local/external с прежним локальным SOCKS5 и исходной очередью Core, с учётом смены адресов. Нужны kernel/Core/NTSTATUS/TCP evidence всех участков и топология VM/хостов; QPC двух машин не объединять. Успех внешнего опыта без повторного SYN/drop не различает гипотезы.

UI remote benchmark всё ещё REMOTE_CONTROLLER_PENDING. Получатель и SOCKS5 — разные роли. Обычные контроллеры, Core/driver и старые frozen-планы этой подготовкой не менялись.
