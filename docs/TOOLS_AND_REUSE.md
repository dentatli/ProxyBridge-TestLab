# Инструменты и повторное использование

## WinDivert: наблюдение дескрипторов, 2026-10-02

Взят готовый x64 `windivertctl.exe` из [официального WinDivert 2.2.2](https://github.com/basil00/WinDivert/releases/tag/v2.2.2), архив WinDivert-2.2.2-A.zip. Локально сохранены SHA/URL/source/лицензия (LGPLv3 или GPLv2) в bin/tools/windivert-2.2.2/origin.json и LICENSE. DLL и driver archive entry побайтово совпали с файлами комплекта4.0.0; driver не извлекался/не устанавливался. Asset digest не опубликован API, SHA закрепляет скачанные байты, а не независимую воспроизводимость binary build или загруженного драйвера.

Используется только `list`: [upstream source](https://github.com/basil00/WinDivert/blob/v2.2.2/examples/windivertctl/windivertctl.c) открывает REFLECT с SNIFF/RECV_ONLY/NO_INSTALL и ограничивается текущими открытыми дескрипторами совместимого семейства. Новый протокольный/driver engine не написан; watch/kill/uninstall не вызываются. Existing InterceptionState.psm1 проверяет SHA и полноту захвата, сохраняет PID/layer/flags/priority без частных filter/path. LegacyIdleObservation pending user-admin execution; пустой snapshot не означает глобальную очистку или возможность переключиться на Driver без согласованной перезагрузки.

## TCP: ctsTraffic, подготовка 2026-10-01

Выбран [Microsoft ctsTraffic](https://github.com/microsoft/ctsTraffic) для TCP bulk upload/download: готовый Windows x64 2.0.3.9, Apache-2.0, CSV per-connection с общим ConnectionId, счётчиками данных и результатом verify:data. Официальный бинарник закреплён на commit b0e2a48f30fb7caaaa9994ee2dea2a177a4639e2; Git blob сверён, SHA256/URL/лицензия в bin/tools/ctstraffic-2.0.3.9/origin.json. Никакой глобальной установки/сборки. Два имени одного binary позволяют назначить правило только генератору. Подготовительные прямой и SOCKS5 прогоны подтвердили реальные байты/совпадающие GUID/естественные exit0; полная SMOKE-связка через ProxyBridge проверена пользовательским запуском tcp-socks5-smoke-20261001-142534-d3de96 (4×16MiB/Succeeded/полные route/PC/cleanup свидетельства), STANDARD ещё ожидает пользователя. CSV parser поддерживает UTF16 BOM и UTF8. TimeMs не RTT. NTttcp рассматривался, но для этого среза ctsTraffic даёт подходящие коррелируемые receiver/client отчёты и проверку каждого буфера; его не скачивали.

TCP proxy host использует уже закреплённый asyncio-socks-server1.3.3/MIT и библиотечный relay, только hooks/control/наблюдение сокета; core библиотеки не менялся. pproxy2.7.9 использован исключительно как временный диагностический tunnel в non-product proof. Полноценная серия использует SOCKS5 host без этой дополнительной прослойки, product route требует независимых socket + CLI свидетельств. Потребление самого контролируемого proxy входит в полный путь, не считается выделенной стоимостью ProxyBridge. HTTP CONNECT отложен по решению пользователя.

Проверка 2026-09-28. Это shortlist, а не команда установить всё сразу. Экономия токенов количественно не измерялась.

## Уже доступно

- **Serena**: MCP подключён, проект активирован, PowerShell-символы доступны. Использовать точечный поиск символов/ссылок, затем читать нужный метод. [Проект](https://github.com/oraios/serena).
- **GitHub**: каталог плагинов подтвердил установленное подключение. Использовать для поиска готовых реализаций, изучения issues и диффов; локальный Git — для обычной работы с файлами.
- **Browser / computer use**: уже есть средства просмотра интерфейса. Отдельный Playwright MCP сейчас дублировал бы часть возможностей; не установлен.
- **Visualize**: доступен для согласования интерфейса/сравнений. Documents/PDF/Spreadsheets/Presentations нужны только для соответствующих артефактов, не для обычной правки кода.
- **grilling**: установлен пользовательский навык; вызывать только по запросу, один вопрос за раз.

## Подключённое дополнение

**Context7** установлен и подключён. Проверены поиск ASP.NET Core и получение документации о завершении BackgroundService из официального репозитория `dotnet/aspnetcore.docs`. Использовать по конкретному вопросу API, не на каждый шаг. Результаты могут включать фрагменты для старых версий: проверять соответствие .NET 10, а не считать любой ответ автоматически актуальным. [Upstash Context7](https://github.com/upstash/context7).

Не добавлять ещё один GitHub, browser или общий «агентный workflow» ради предполагаемой экономии. Навыки подходят для повторяемых процедур; MCP — для доступа к инструментам/данным. [Документация OpenAI](https://developers.openai.com/plugins/concepts/skills).

## Готовые компоненты для benchmark-продукта

Источник пользователя для GUI ProxyBridge: [dentatli/ProxyBridge, codex/hlk-minimal](https://github.com/dentatli/ProxyBridge/tree/codex/hlk-minimal). На 2026-09-30 локальная копия `C:/src/ProxyBridge-HLK-minimal` и удалённая ветка совпали по SHA `149137f4ecb85cd39d4d33ac840a9f1cb24facd2`; исходники Windows GUI доступны. Автор ещё рассматривает решение. Использовать как источник для последующего изучения/переиспользования; GUI в этой работе не собирался и не менялся, ветка не подмешивалась в закреплённый Driver-комплект.

| Компонент | Предлагаемое применение | Ограничение / решение |
|---|---|---|
| [curl/libcurl](https://github.com/curl/curl) | HTTPS, загрузка/отправка файлов, явный proxy-baseline | Сохранять версию и возможности конкретной сборки; в серии ProxyBridge отключать явный прокси клиента |
| [Playwright](https://github.com/microsoft/playwright) | Реальный браузер как генератор пользовательской нагрузки | Это адаптер нагрузки продукта, не автотест UI TestLab; версия браузера фиксируется, расход ресурсов учитывается |
| [NTTTCP](https://github.com/microsoft/ntttcp) | Нативная Windows-нагрузка для пропускной способности | Кандидат на отдельный backend; до включения проверить маршрут через ProxyBridge, получатель и формат результата |
| [k6](https://github.com/grafana/k6) | Готовый планировщик HTTP-нагрузки | Опционально; AGPL-3.0, вопрос поставки решать до включения; не универсальный генератор всех протоколов |
| Существующие aioquic/h2 и native workers | Уже реализованные протоколы и точные socket/WFP-сценарии | Переиспользовать имеющиеся адаптеры, не заменять без конкретной выгоды |

Для iperf3 учитывать отсутствие официальной поддержки Windows: не выбирать его единственным обязательным Windows-движком. [Позиция ESnet](https://lightbytes.es.net/2024/05/01/why-doesnt-esnet-support-iperf3-on-windows/).

Перед добавлением зависимости: проверить поддержку нужного режима, лицензию, фиксируемую версию/хеш, машинный вывод, остановку процесса и реальный путь трафика. Не писать собственный TLS/HTTP/QUIC-движок при наличии подходящей библиотеки. Наличие генератора само по себе не доказывает корректность ProxyBridge.

Для первой проверки маршрута 2026-09-30 использован [pproxy 2.7.9](https://pypi.org/project/pproxy/2.7.9/) / [исходники](https://github.com/qwj/python-proxy), MIT, pure Python. Wheel загружен отдельно в `bin/tools/pproxy-2.7.9`, SHA-256 `a073d02616a47c43e1d20a547918c307dbda598c6d53869b165025f3cfe58e80` сверён с PyPI; загружается прямо из wheel, глобальной установки нет. `pb_controlled_proxy.py` делегирует handshake/relay библиотеке и записывает JSONL реальных сокетов, ограничивает назначения двумя loopback-портами получателя и время жизни 60 сек. Windows/Python 3.11.9: фактическая TCP/SOCKS5 передача и STOP/exit0 подтверждены. Последний выпуск — 2024-01-16: временный диагностический компонент, не выбор для throughput/длительной нагрузки. GOST 3.3.0 (готовый Windows x64, MIT, JSON logs) рассматривался первым, но архив был заблокирован Windows до проверки digest/извлечения; не запускался, защита не обходилась.

Продолжение 2026-09-30: тот же host/pproxy подтвердил TCP через HTTP CONNECT. В SOCKS5 accept у pproxy реализована только команда CONNECT; отдельный UDP server не заменяет UDP ASSOCIATE, который требует ProxyBridge. Для UDP взят [asyncio-socks-server 1.3.3](https://pypi.org/project/asyncio-socks-server/1.3.3/) / [исходники и addon hooks](https://github.com/Amaindex/asyncio-socks-server), MIT, выпуск 2026-08-25, Python >=3.12, без внешних зависимостей. Wheel SHA-256 `5190d3ae00a29325ec9048306fcd8bd08f8e89ddd75c535cc01d1d646f105344` сверён с PyPI; путь `bin/tools/asyncio-socks-server-1.3.3`. Для запуска уже есть Codex bundled Python 3.12.14; путь передаётся `-UdpProxyPythonPath`, версия/путь сохраняются в dependencies.json. `pb_controlled_udp_proxy.py` использует готовый relay и hooks, заменяет неподдерживаемый Windows loop.add_signal_handler на bounded stdin shutdown; библиотечные байты/ядро протокола не изменены. SOCKS5 handshake, UDP туда/обратно и STOP/exit0 наблюдались на Windows; прозрачность ответа ProxyBridge не прошла из-за смены порта источника. API private relay/server привязаны к точной версии wheel; TCP listener loopback, ephemeral UDP binds wildcard по штатному коду, адреса пересылки ограничены получателем. Это диагностический компонент; sustained throughput/мультиклиентный режим ещё не подтверждены.

## Экономия процесса

Подготовка длительного UDP echo, 2026-10-01: [Ethr](https://github.com/microsoft/ethr#status) имеет native Windows и MIT, но его таблица Status отмечает UDP latency как No; это кандидат для отдельных UDP bandwidth/packets-per-second сценариев, а не замена текущей проверки RTT/источника каждого echo. [Официальный FAQ iperf3](https://software.es.net/iperf/faq.html) сообщает об отсутствии официальной поддержки Windows и рекомендует iperf2. Для первого soak расширен существующий Winsock echo-клиент TestLab (размер идентифицированного payload/число сообщений), уже используемый asyncio-socks-server и psutil; новый UDP/SOCKS движок не написан. Высокая нагрузка с готовым двигателем остаётся отдельным выбором с проверкой реального прохождения ProxyBridge и формата доказательств. Ни Ethr, ни iperf в этом срезе не скачивались/не устанавливались.

Один текущий план и короткие инструкции в AGENTS.md. Старые отчёты читать адресно. Компактные результаты команд и поиск символов вместо полного чтения больших файлов. Без обязательных TDD, автотестов кода, подагентов и повторных успешных проверок. Ненужные плагины не удалялись и глобальные настройки пользователя не менялись.

## Ресурсы ПК: использован psutil

2026-09-30: [psutil 7.2.2](https://pypi.org/project/psutil/7.2.2/) (BSD-3-Clause, Windows, cp37-abi3-win_amd64 wheel подходит существующему Python 3.12.14). Wheel SHA-256 `eb7e81434c8d223ec4a219b5fc1c47d0417b12be7ea866e24fb5ad6e84b3d988` сверён с PyPI metadata; origin.json и файлы лицензии сохранены в bin/tools/psutil-7.2.2. Изолированная распаковка, без глобальной установки. `pb_pc_sampler.py` делегирует готовой библиотеке системные/process CPU/memory, проверяет PID/start/path; stdout не служит журналом метрик. Реальный сбор и STOP/exit0 подтверждены в socks5-udp-benchmark-1. Не измеряет отдельную стоимость WFP-драйвера или ватты. Старый pb_perf_client — offline fixture placeholder; его вывод не использовать как benchmark реального трафика. Новая короткая UDP-серия переиспользует существующий native сетевой клиент и asyncio-socks-server 1.3.3; новый SOCKS-движок не написан.
