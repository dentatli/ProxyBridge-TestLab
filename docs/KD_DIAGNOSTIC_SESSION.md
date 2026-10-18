# Общий запускатель диагностики

`scripts/Invoke-KdSession.ps1` заменяет создание новых копий wrapper/workload/preparer/reporter для каждого замера. Старые скрипты и комплекты остаются воспроизводимой историей. Новый запускатель не меняет продукт и не управляет WinDbg.

## Что переиспользуется

Один исполнитель `Invoke-KdSessionWorkload.ps1`, общий модуль подготовки/проверки `pb_kd_session.py` и отчёт `pb_kd_session_report.py`. Существующие cohort modules задают проверенные формы `four` (4) и `bounded256` (4→64→256→4,328). Поддержки640 и произвольного увеличения нагрузки нет.

RegisterAssets один раз проверяет исходный замороженный план по ожидаемому SHA, его файлы и изолированный Python, затем создаёт небольшой общий manifest ссылок. Runtime и продуктовые бинарники не копируются, не перемещаются и не изменяются. Сейчас используются файлы сохранённого lookup-four kit. Это использование файлов как общих ресурсов, а не повторный Run/Resume старого плана и не подтверждение нового профиля старым kit. Каталог-источник нельзя удалять, пока нужны ссылающиеся планы.

Каждый Prepare создаёт только новый каталог `pb-kd-session-plan-*`: runtime-plan, точную копию JSON-профиля, review, boot evidence и маленькие receipt/product.env. Все исходные байты профиля сохраняются, включая BOM/пробелы: SHA review не меняется из-за сериализации. План хранит SHA общего manifest и своих исходников/модулей/зависимостей; manifest хранит SHA runtime inventory и общих файлов. При Inspect/Run проверяются реальные SHA, включая все8197 файлов Python и его точный inventory. Новый профиль или нагрузка не требуют копирования Python или изменения кода исполнителя.

## Параметры

| Phase | Обязательные параметры | Действие |
| --- | --- | --- |
| RegisterAssets | SeedPlan, ExpectedSha | Проверить прежний immutable kit, зарегистрировать общие ресурсы |
| Prepare | SharedAssets, SharedAssetsSha, DebuggerProfile, RegistrationReview; Workload=four/bounded256 | Новый маленький план, без продукта/трафика |
| Inspect | PlanPath, PlanSha | Проверка файлов, runtime_ready=false |
| Run | PlanPath, PlanSha, ProfileReviewed, DebuggerLoggerEnabled; для bounded также BoundedLoadReviewed | Один USER замер |

ExpectedSha/SharedAssetsSha/PlanSha сравниваются автоматически, несовпадение останавливает действие. Никакого выбора старого плана по имени «latest». Run проверяет стабильную загрузку VM по Event12/PrefetchBootId, admin, общий mutex/lease, старые legacy/interrupted-run gates и создаёт одноразовый run-claim через CreateNew. Использованный план не возобновляется даже после ошибки. Исходный runtime и остальные планы при этом остаются общими.

RegistrationReview — отдельный приватный JSON после проверки console/кода. Поля: schema_version1, registration_reviewed=true, profile_sha256, boot_identity (точные поля из Get-KdBootSessionEvidence.identity), allowed_workloads, evidence_files[{path,sha256}], root_cause_proven=false, automatic_debugger_control=false. Для bounded требуется prior_four_review с native_probe_complete=true, теми же profile_sha256/boot_identity и path/sha256 разобранного результата. Эти поля описывают рассмотренные данные, а не автоматически подтверждённую работу отладчика. Наличие bounded256 в коде не разрешает его запуск и не доказывает полноту kernel coverage. Новая загрузка VM требует нового live review/плана, но не нового runtime при неизменных файлах.

Отчёт получает ожидаемую policy из плана, а не угадывает её по результатам. Он оставляет kernel coverage, frame reads и miss-actions verification pending. Неидентифицированные10061 сохраняют capture incomplete, но не становятся отдельным предметом расследования. Без console нельзя объявлять отсутствие событий доказательством работы фильтра. Исходные capture reports не переписываются при проверках на адаптированных fixtures.

## Проверки и ограничения

Unit tests `tests/test_kd_session.py` проверяют изменение SHA/boot/profile, неподтверждённую bounded-нагрузку, prior-four binding, несогласованные IDs, повторную запись immutable файла, точность байтов snapshot и добавленный runtime файл. Чистые проверки PowerShell5.1 проверяют parser и оба presets, без запуска cohort. Приватные копии трёх captures проверяют отчёт: четыре успеха;32исходныхCore10022;42отказа, включая18неидентифицированных10061 (incomplete). Старая point policy отвергнута.

При первоначальной проверке обнаружены ошибки кодировки в локальном генераторе проверки и перекодированная строка нового PS wrapper; исправлены явным UTF-8 и UTF-8 BOM для PS5.1. Это офлайн-ошибки подготовки, продукт/WinDbg не запускались. Старые source/module/profile SHA сохранены. Private audit: `artifacts/diagnostics/pb-kd-session-implementation-review-20261018`.

Runtime исполнения нового универсального пути пока не проверен. Тест продукта/нагрузки агентом не выполняется. Перед каждым USER Break/enable/single-step предупреждать: вся VM, Codex и RDP могут остановиться; заранее иметь bd для проверенных IDs, bl и отдельный g, даже после ошибки. Регистрацию точек и текущее состояние WinDbg общий запускатель не меняет и автоматически не проверяет. Инструкции только в чате, без Desktop copies.

## Проверенный files-only переход, 2026-10-18

Source `4ede8e4`. Восемь unit tests прошли; три capture fixtures, оба presets и parser Windows PowerShell5.1 проверены.102старых source/module/profile SHA совпали. RegisterAssets и Prepare через новый wrapper завершены exit0, без продукта/трафика/управления WinDbg. Новый Inspect не повторялся: Prepare уже вызывает полную проверку плана и ресурсов.

Общий manifest `artifacts/diagnostics/pb-kd-shared-assets/81fc33a6288b324dcb9880735728e0699729c5c804292fb07a2791c9db4f3a24.json`, SHA256 `F14A2FADC257C3167655264C7C11AB2D5AE2D1561C197164AD4ABFDDD945E52D`. Runtime находится в неизменённом lookup-four kit083735-2eb58055. Использованный four Run этого kit не повторялся.

Демонстрационный план `artifacts/diagnostics/pb-kd-session-plan-20261018-090504-775342a7/runtime-plan.json`, SHA256 `FCA04367212E88830057A123E0D9D4C6EBB0F8A4E5D8AE3A19E3520B96EC5B47`:6новых файлов/24169байт/62frozen references, ноль новых runtime/product binary copies. Review ограничен four и явно сохраняет runtime_actions_verified=false и отсутствие post-disable inventory. Это проверка миграции файлов, не назначение повторной четырёхсоединительной пробы. Bounded256 этим review не разрешён. Точки не включать и ничего не запускать по одному факту готовности универсального кода. Следующий диагностический шаг остаётся офлайн-пересмотром общего lookup trap перед замером256.
