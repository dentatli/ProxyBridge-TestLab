# «На этом ПК» — checkpoint 26 октября 2026

## Текущее состояние

**preview.56**, source `6bce96b6f3a2a40d07c248a82e110ae8cd86326a`,1698SHA совпали. Admin **http://127.0.0.1:5178**; package `C:/src/ProxyBridge-TestLab/artifacts/releases/ProxyBridge-TestLab-0.3.0-local-preview.56-win-x64`. Active/busy=false,2сборки/история сохранены,добавлены2короткихконтрольныхпрогона. Dev5188остановлен. Не запускать full/HIGH/soak автоматически.

## Новый запрос — физический стенд

[Подготовка PB-SUT](PB_SUT_COMPARISON_PREPARATION_2026-10-26.md):файлы56/обесборкиперенесены,1715SHAverified,driverобновлёнoem25/4da/1.1,backupсохранён,HLKStopped/Manual,HighPerformance,debugNo,testsigningнеизменён. USERподтвердилфиздоступ/перезагрузку.Rebootпринят,RDPвернулся,WinRM5985покаclosed. ЖдёмвходPB-USER/Start-ServiceWinRM;затемpreparedverify-ready.ps1. ПослеребутаготовностьUI/NICнеподтверждена,тестовнет. VM5178остаётся56безизменений.

## Последнее изменение — ресурсы ядра

[Метод, реализация, проверки и ограничения](KERNEL_COLLECTION_PREVIEW56_2026-10-26.md). Пользователь одобрил отдельные прогоны WFP/WinDivert с последующим сравнением; чередование не обязательно. Реализованы exclusive-IP ETW CPU samples выбранного SYS и общесистемные tagged pool snapshots, без изменения продукта/установки/trust/BCD. No sum cprocessCPU, no full footprintclaim, no winner/relative%forkernel. Missing/loss/low samples=>unknown,не0CPU. Длительный прогон исключён из нового сбора и отложен.

35nativecontractsPASS;222старыхJSrenderings+kernelunit/scope/unknown/rankingguardsPASS. PoolMonнезависимаясверкаlayout/bytesPASS. Пилот4SHORTloadedoff/onWFP/Win180.64sCOMPLETE,новыйпакет2SHORTloaded91.59sCOMPLETE. RawSHA/recompute/QPCcoveragePASS,lost0,drain/cleanuptrue,модулиоднозначны. CPUвыборкипакетаWFP0/Win18=>прочерквобоих. Короткийпилотнеподтверждаетполноересурсноепревосходствоинакладныерасходытрассировкистатистическинеоткалиброваны. Новые пользовательские сравнения выполнять на одной56.

WFP`20261026-092520-91ef402fff1443f685bc1aacd87abd10`,Win`20261026-092605-f24a643b5a4d48a19b3c89f27972631a`;втаблицевыбранаэтапара. UI/report/kernelgroup/tooltipsпроверены,скриншот`artifacts/kernel-pilot/comparison56.png`. СвоихETWсессий/Core/worker/originнет,ProxyBridgeDrvStopped. Evidence`artifacts/kernel-pilot/`и`artifacts/engine-migration/kernel-pilot-*.json`приватные,вGitневключать.

## Подтверждённая база и границы

[Пользовательские NORMAL55](NORMAL_RUNS_PREVIEW55_2026-10-26.md):WFP44PASS,Win33PASS/11UDP-relatedFAIL.44conditionsравны,92rawSHA/recompute0diff,29qualityadmittedpairs,7CPUbudgeteligiblepairs. Productrootcauseвдругомчате. [Fixed-session/compact55](FIXED_SESSION_COMPACT_2026-10-26.md),[51LOW/HIGHпрофиль](USER_LOAD_PROFILES_2026-10-26.md),[исследованиеядра/отложенныйsoak](KERNEL_RESOURCES_AND_SOAK_REVIEW_2026-10-26.md). Не смешиватьстарые/новыеметоды,SHORT/NORMALкакравныеусловия.

Worktree `C:/Users/LabAdmin/.codex/worktrees/testlab-development/ProxyBridge-TestLab`,branch `codex/development-functional-completion`,базаd5b51f3сохранена. Main`C:/src/ProxyBridge-TestLab`branch`codex/checkpoint-20261007`:чужиеhandoffchange/KernelReadCapture.csнетрогать/нечитать. Историядоexplicitresetв`C:/Users/LabAdmin/AppData/Local/ProxyBridge-TestLab-archive-20261026T050512Z`. Неудалятьfrozenkits/captures/productfiles. Коммит/пушбезforce/PR/privateartifacts,неделегировать. Последниелимитыprimary75%used/weekly12%used;проверитьпереддолгойработой,при<=5%remainingcheckpoint/стоп.
