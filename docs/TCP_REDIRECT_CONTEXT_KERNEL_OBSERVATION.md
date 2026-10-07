Актуализация 2026-10-06: первый USER kernel опыт052735-313c10ce остановлен resource guard до native workload; сохранённый baselineRestore подтверждён. Новые лабораторные resource receipts/preinstall gate проверены PS5/7, floor2GiB RAM/256MiB disk сохранён. Новый комплект с теми же подписанными бинарными файлами tcp-redirect-context-preparation-20261006-053310-e548deac, files-only Prepare/Inspect passed/42freeze. NEXT USERfreeRAM→ADMINInstall(newroot)→onlysuccess reboot→Run2–4min/guardedRestore. Details docs/WORK_CHECKPOINT.md и newcandidate/verification/HANDOFF.md. Старый185952 root не refreeze/Resume; истинная причина10022/10061 пока не доказана. Проект ниже исторический.

# Следующий этап: наблюдение в диагностической копии driver

Статический проект после112accepted contextfail /336latefail /10positiveRECORDS и32endpointless10061 в183525-74582558. Ниже сохранён первоначальный проект; текущая подготовка и команды описаны в актуализации выше.

## Один опыт для нескольких гипотез

Сохранить одну ConnectEx32 серию4→64→256→640→4 и recovery на том же CLI, без задержек/повторных query нового v3 Core. Параллельно собрать metadata kernelclassify и original user-query. Диагностические timings не сравнивать со скоростью обычных сборок.

Наблюдения нужны в этих границах исходногоClassifyCore:

| Гипотеза | События/поля | Подтверждение/ограничение |
|---|---|---|
| ctx allocationNULL | PID/protocol/family/original endpoints/QPC, allocation attempted, pointer present/size | Сопоставленный NULL объясняет отсутствиеназначенногоконтекста; не доказываетRAMexhaustion |
| attachment/Apply path | AcquireClassifyHandle and WritableLayerData NTSTATUS, req present, localRedirectHandle present, targetPID, ctx present/size; before/afterApply | Apply возвращаетvoid; это наблюдение пути, неWFPcommit-success |
| повторная/иная classify | metadataflags/redirectstate/branchreason/PID/tuple доизменения ипосле/rights/action | order alone не связывает classify→accept; 0localport оставляет неоднозначность |
| initial10061 отдельно | timestamps/phase/clientlaunch + nativefailurecsv; available kernel tuple/branch | endpointlessCSV нельзя выдать за matched query; еслинетуникальнойсвязи, INCOMPLETEсохраняется |

## Конкретный объём кандидата

- Отдельная копия pinned138sources; baselineCLI/Core/sys/archive не менять. Отдельный receiptmethod/source-SHA/diagnostic-onlykit, обычные benchmark adapters его отвергают. Никаких измененияpermit/redirect/drop/retry/action/ctxownership/backlog.
- Выделить отдельный ограниченный ring telemetry, например8192records с фиксированным размером; только metadata controlledTCP, безpayload/произвольныхпутей. Записать sizeof/allocatedbytes вreceipt; initfailure/dropped/overwritten/readsequence явно сохраняются. Не использовать существующий connection-event ring как будто это packettrace.
- Classify только кладёт record подкороткойсинхронизацией: никаких файлов/HTTP/usercallbacks/ожиданий/perflow loggingallocations вkernel. Вспомогательное получение counters/drain через отдельный diagnostic IOCTL; нулевой/отсутствующий logger не меняет upstream verdict.
- Newsourceharness сверяет исходные branches/status/ownership/actions и fault/drop-accounting; подпись+архитектура+зависимости и source binding проверяются после разрешённой сборки. Kernel unload/install/runtime не выдаются за подтверждённые по staticchecks.
- Передruntime проверить identityexistingdriver/service/pinnedcandidate, обеспечить отдельнуюrecoverable baseline+candidate installation procedure, сохранённыйinstallreceipt ивозвраткbaseline. Старыеbaselinehash/servicegates не ослаблять; добавляется diagnostic-only признание candidate identity. При необходимости смены драйвера — явный rebootэтап пользователя, без автоматической перезагрузки.
- Unique matching поPID/protocol/семейство/original and translated tuple/QPC. Localport0/duplicate branches/droppedrecords/missingquery остаютсяunconfirmed, безnearest-orderfallback.

## Историческая запись о разрешении (до USER «Хорошо, приступай»)

Действующие ограничения AGENTS.md не разрешают agent kernelbuild/sign/install. Исходный product не исправляется. Для реального следующего этапа требуется отдельное разрешение на сборку, подпись и временную установку диагностической копии собственного драйвера. Подготовка этой заметки и разбор183525 ничего не установили и не меняли состояние драйверов.
