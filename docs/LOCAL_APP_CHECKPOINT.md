# «На этом ПК» — checkpoint 26 октября 2026

Текущая версия **preview.55**, source `d2604ae14cfe178995823c36a51903abeb94a395`,1685SHA matched, admin **http://127.0.0.1:5178**. Package `C:/src/ProxyBridge-TestLab/artifacts/releases/ProxyBridge-TestLab-0.3.0-local-preview.55-win-x64`.2сборки/история сохранены, active/busy=false.

## Новый запрос: ресурсы ядра и длительные проверки

[Проверенные возможности, аудит soak и предлагаемая методика](KERNEL_RESOURCES_AND_SOAK_REVIEW_2026-10-26.md). Пользователь возобновил тему kernelaccounting; исследованы код и официальнаядокументация, **трассировки/продуктовые/суточные тесты не запускались**. WPR/WPA/xperf установлены, readonlyprofilesCPU/Poolесть. У4daсобственныеtagsPBfp/PbDu; частьNDIS/WDF/sharedmemoryотдельно. ETWexclusive/inclusive/DPC/processCPUне складыватьбезустраненияпересечений; не обещатьабсолютноточныйполныйfootprint. Первое предложение — короткийTCPA/Bpilotнастарыхбинарникахсодинаковойработой,оценкойcoverage/lostevents/overhead,безизмененийдрайвера. Runtimeостаётся55.

Soak24/48/72сейчас1440/2880/4320минутныхсвежихTCP/UDP/probeсессий, бездолгоживущих/прикладныхканалов; перваяошибкаоставляеттолькорecovery. Журналесть,ноJSONрастётипереписываетсяцеликом. Предложение:одиндлительныйсценарийспостояннымисессиями+churn+приложения+quiet/burst/drain,2hрегрессия/24hприёмка/48–72толькообоснованно,boundedmonitor/выборочныйETW/фиксированнаясводка. Это **проект пересмотра, не реализованный результат**. Существующую5minграницуавтопроверокнеснимать; пользовательскоевмешательство/новаяавторизациянужнытолькодляследующеговнешнегодействияпоегофактическомуscope.

## Последние пользовательские NORMAL/LOW

[Подробный анализ](NORMAL_RUNS_PREVIEW55_2026-10-26.md). WFP `20261026-064603-e89b4d841fbf424499adcdd9a6b0e5db` **44PASS**; WinDivert `20261026-073142-90ca8c8a86944ca4b03516267a138616` **33PASS/11FAIL**. Все44conditions совпали;92rawSHA иquality/resourcesrecompute0diff;Core1/1,capture/cleanuptrue. Код/отчёты не меняли, новых проверок не запускали.

Нагрузка достигнута в успешных boundedcases. Flow-rate180сессий/11520Bнаправление у обоих, fixed1×64B проверен. SFTP900цикловeach; loadedRTTp99WFP0.930/Win6.477ms приfixed6MiB/s/probe15s, CPUПК7.3/11.2%. WFPUDP12896000/96000/fullroute,stability8/8/no loss/CPU≈9%; Winтеже11UDP/HTTP3/QUIC/DNSUDP/mixed/stabilityотказов приумеренномCPU, корень не локализован. СравнимыхPASSпар33,qualityadmitted29; CPUbudget≥0.25у обоих только7пар(loaded,connections,flowrate,HTTPsweep,WSSsweep,SFTP,AMQPS), ещё22недостаточны дляCPUрейтинга даже30s. BulkWFP≈98%CPU — пределобщегостенда. TCPconnections privatepeakWFP45.25MiB/Win3.56, неleakclaim. Фактического WFPkernelattribution пока нет; исследование см. выше. Evidence `artifacts/comparison-preview55-normal/` и`artifacts/comparison-preview55-normal-summary.txt`.

## Реализовано / уже проверено

[Compact/fixed-session55](FIXED_SESSION_COMPACT_2026-10-26.md):metric66→47.5px,group50→30,sticky/expand/4columns. Nativeflow-rate1verified64B echo/session вместоunbounded50ms. Method `user-workload-v2-fixed-session`; raw/phasefixedsessionmetadata, старыйflow-rateнерейтинговатькакравнуюработу. CPU/CPUcostприbudget<0.25CPU-слибоmissing — безwinner/relative%, значения+tooltipостаются. ПорогUIнеstatisticaltest; NORMAL30/LONG120помогают,ноне гарантируют информативность; нужныповторы.

35existingnativecontractPASSсfixedcount/byteassertionsC#→Python(direct/proxy),cancel/falsePASS. ActualJSbudget/percent/memory/legacyи132renderPASS. MatchedflowSHORT×2за79.58s:WFP`20261026-063834-feffe5256c434166941c656985586d31`,Win`20261026-063915-37ef3b4e8aaa42348adf2f617213aebe`:36sessions/2304Bнаправлениеeach,PASS/MET/cleanup. Evidence `artifacts/fixed-session55-proof.json`; screenshot`artifacts/compact-comparison55.png`. Не повторять успешные проверки без изменениявходов.

[Все51сценарий LOW/HIGH иназначение](USER_LOAD_PROFILES_2026-10-26.md):moderate/intensiveсинтетическиепрофили,2appconnections,SFTP15/25cycles/s,HTTP6/10,DNS3/5; TCPфон6/10MiB/s/направление,probe15/25s,stabilityTCP50/100/125/100%,UDPconstant. UDPмасштабирование25pps/flow,max128/192. Максимальнаяскоростьотдельноunbounded.51ID/10групп,импорт/covers50→44 сохранены;306remoteplansравныпрежним. Новыхотдельныхtrackedавтотестовнет.

## Сохранённые данные и границы

После явного сброса старыйstore в `C:/Users/LabAdmin/AppData/Local/ProxyBridge-TestLab-archive-20261026T050512Z`, приватныеconfig/evidence/keysнепубликовать. Active `%LOCALAPPDATA%/ProxyBridge-TestLab` содержит новые пользовательские54/55 и2коротких55checks. Драйверы/продуктовыефайлы/frozenkits/captures/immutablepackages не удалялись, trust/BCD/systemproxy не менялись. Browserstoreidentityisolatedreset; обычныйupgradeбезexplicitresetсохраняетchoices.

ПредыдущийSHORT54анализ: [44WFP/33Win;CPUduration/flowlimit](COMPARABILITY_PREVIEW54_2026-10-26.md). СтарыеNORMAL53 [анализ](FULL_RUN_COMPARABILITY_2026-10-26.md) — данные теперьвarchive. Не смешивать54/55,SHORT/NORMALкакодинаковыеусловия. Не запускать full/HIGH/soak автоматически. Productrootcause/kernelmeasurement отдельно;30s/8intervals не подтверждаютсуточнуюустойчивость. Дляанализа будущихпрогонов использоватьrawSHA итежеadmissionguards.

Worktree `C:/Users/LabAdmin/.codex/worktrees/testlab-development/ProxyBridge-TestLab`,branch `codex/development-functional-completion`,базаd5b51f3 сохранена. Main `C:/src/ProxyBridge-TestLab` branch `codex/checkpoint-20261007`:чужиеhandoffchange/KernelReadCapture.csнетрогать/нечитать. Лимиты primary20%used/weekly3%used; ≤5%remaining—checkpoint/стоп. Commit/pushбезforce/privateartifacts/PR. Диагностикавдругомчате; не делегироватьбезпрямогозапроса.
