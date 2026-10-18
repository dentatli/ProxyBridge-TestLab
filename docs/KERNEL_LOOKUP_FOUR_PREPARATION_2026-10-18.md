# Lookup miss: отдельная проба четырёх соединений

Основание: [новый профиль](KERNEL_LOOKUP_TWO_MISS_CANDIDATE_2026-10-18.md), подтверждённая регистрация только 2/3d и отдельный g. Новая проба не использует прежние retrieve/NULL kits. Продукт и общие модули не менялись.

Метод `redirect-kd-lookup-four-v1`: только четыре соединения, 512 KiB на соединение, hold 8 s, ConnectEx с pending limit 32, исходный listen без задержки и один исходный query. Нет load levels и recovery. Client wait 60 s, cohort budget 180 s, RAM gate 2 GiB; остановленная отладчиком VM не имеет гарантированного wall-time лимита. Active/registered IDs 2/3, inactive пусто. Точка 3 ловит также успешный общий lookup, условие ограничивает лишь вывод.

Четыре новых файла: Invoke-KdLookupFour.ps1, Invoke-KdLookupFourWorkload.ps1, pb_prepare_kd_lookup_four.py, pb_kd_lookup_four_report.py. Сохраняются пинованные CLI/Core/driver, изолированный Python, SHA всех файлов, mutex/lease, stable boot binding и запреты установки драйвера/автоматического управления отладчиком. Дополнительный guard запрещает повторный Run с тем же runtime-plan SHA. Run требует явных USER flags LookupFourProfileReviewed и DebuggerLoggerEnabled.

Подготовка привязана к проверенной загрузке: Kernel-General Event12 record16566, PrefetchBootId113, StartTime2026-10-18T06:22:30.5Z. Текущий read-only boot evidence совпал. Это не криптографическое удостоверение debugger session. В новый kit копируются и замораживаются отдельные registration review/console, live code console, candidate review и profile snapshot. Никакие старые captures/kits не переписываются.

Отчёт проверяет native/Core evidence, оставляет debugger coverage, frame reads, miss-actions runtime verification и root cause неподтверждёнными. Успешные четыре соединения без событий промаха не исполнят тело failure-actions и не докажут доступность новых стековых чтений. Отсутствие miss events не доказывает отсутствие предыдущего потребления/утраты контекста. Полная история create/associate/remove/free этим профилем не покрывается. 10061 отдельно не расследуется.

Проверки без продукта: Python AST; Windows PowerShell5.1 parser двух новых scripts и чистый four preset; адаптированная приватная копия прежнего четырёхсоединительного capture дала 4 query success, errors[], kernel pending. Старый point policy и 328 фаз отвергнуты. SHA98 старых source/module/profile файлов совпали. Это проверки файлов и fixtures, не новый Run. Private audit `artifacts/diagnostics/pb-kd-lookup-four-preparation-review-20261018`.

Следующий шаг после files-only Prepare — один USER Run четырёх соединений, после проверки plan SHA и inventory. Перед Break/каждым enable предупредить об остановке всей VM/Codex/RDP; recovery bd2/bd3/bl/g отдельно. Регистрацию не повторять. После Run или ошибки USER отключает 2/3, bl, отдельно g, присылает полный console и PowerShell output. При debugger ошибке прекратить пробу, не продолжать нагрузку. Старые kits не Resume/refreeze. Команды только в чате, без Desktop copies.

## Подготовка завершена

Source commit `78ff176`. Windows PowerShell5.1 Prepare завершён exit0, `KD_LOOKUP_FOUR_FILES_VALIDATED`: 8291 frozen files / 8197 runtime files. Новый каталог `artifacts/diagnostics/pb-kd-lookup-four-preparation-20261018-083735-2eb58055`; runtime-plan SHA256 `81FC33A6288B324DCB9880735728E0699729C5C804292FB07A2791C9DB4F3A24`. Повторный Inspect не запускался. После подготовки SHA98 защищённых старых файлов снова совпали. Это не runtime-ready: product_started/traffic_generated/driver_installed/debugger_control=false. Agent Run не выполнялся.

Следующий USER шаг: закрыть GPT при необходимости экономии памяти, проверить только существующие новые 2/3d, включить по одной с предупреждением об остановке всей VM, отдельно g, один Run с auto SHA comparison и flags LookupFourProfileReviewed/DebuggerLoggerEnabled. После завершения или ошибки отключение с bl/g отдельно и полный вывод. Никакой bounded/640 нагрузки этим комплектом.
