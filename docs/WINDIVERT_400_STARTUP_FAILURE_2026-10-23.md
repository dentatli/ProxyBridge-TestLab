# WinDivert 4.0.0: причина FAIL, 2026-10-23

Запрос: выяснить FAIL официального 4.0.0, включая гипотезу о поздно принятом окне подтверждения. Scope — только startup/output/shutdown CLI, без TCP/UDP driver diagnosis, WinDbg, изменений продукта или системных настроек.

## Подтверждено

1. Последняя лабораторная попытка `20261023-114114-ae1dc178a7674bc184717e59198a1bcb` остановлена на UNRULED control до измерений: `TRAFFIC_CLI_READINESS_FAILED`; затем `TRAFFIC_CLI_CRASHED`, child exit `0xC0000005`. Исходные отчёты сохранены.
2. В capture присутствуют успешный запуск Core, `ProxyBridge is running`, затем `Stopping ProxyBridge` и `ProxyBridge stopped`. Наличие строки в итоговом capture само по себе не означает, что она была доступна во время ожидания READY.
3. Различающий короткий опыт с неизменённым официальным CLI/Core, тем же packaged Product/ConPTY host, одним несовпадающим DIRECT-правилом и без workload подтвердил задержку stdout. До15s ожидания поступили только16 байт terminal escape. На t=15.875s контроллер запросил STOP: CLI жив, READY ещё не наблюдалась. На t=16.203s поступил накопленный блок1913 байт, содержащий одновременно READY и Stopping. Child exit0; OFF после остановки подтверждён. Это не acceptance сетевых сценариев и не основание смягчать gates. Первый подготовительный опыт с пустыми rules был отвергнут CLI как некорректный профиль; он не использован для вывода о неисправности продукта.
4. Windows Application event1000 для последнего реального FAIL: UTC11:41:34.1832425, CLI PID0x1278 (4728), `ModuleName=ProxyBridgeCore.dll_unloaded`, `ExceptionCode=c0000005`, `FaultingOffset=0x59ce`. Путь соответствует официальному4.0.0. Более ранний4.0 event11:16:43 имеет тот же unloaded module и offset0x595c. Ошибка — user-mode обращение к выгруженной DLL, не доказанный сбой SYS.

## Механизм по официальному исходнику

Тег4.0.0 указывает на commit `22e53445e44481fad0f63c2a088aa91c0deda3af`.

- [CLI main.c](https://github.com/InterceptSuite/ProxyBridge/blob/22e53445e44481fad0f63c2a088aa91c0deda3af/Windows/cli/main.c#L959): строка READY печатается `printf` без `fflush(stdout)` или startup `setvbuf`. В используемом console host вывод сохраняется в буфере до остановки. Ожидание TestLab15s не может увидеть ещё не переданные байты; простое увеличение тайм-аута не устраняет этот механизм.
- [ctrl_handler](https://github.com/InterceptSuite/ProxyBridge/blob/22e53445e44481fad0f63c2a088aa91c0deda3af/Windows/cli/main.c#L448) сначала сбрасывает `g_running`, затем вызывает `g_Stop`. Главный поток после сброса флага выходит из цикла и делает `FreeLibrary(g_hDll)` без ожидания завершения handler/Stop. Поэтому возможна выгрузка Core, пока другой поток ещё исполняет его код.
- [Core Stop](https://github.com/InterceptSuite/ProxyBridge/blob/22e53445e44481fad0f63c2a088aa91c0deda3af/Windows/src/ProxyBridge.c#L4827) дополнительно использует bounded waits1000ms и закрывает thread handles без проверки результата ожидания. Это ещё один потенциальный путь выгрузки с живыми потоками. Без crash dump нельзя строго назвать упавший поток и точную ветвь гонки; unloaded-DLL crash подтверждён журналом.

Таким образом исходный readiness FAIL связан с несовместимостью наблюдения stdout штатного4.0.0 и адаптера TestLab; последующее падение при остановке — отдельный дефект lifecycle продукта. Связь с пользовательским окном подтверждения не установлена; наличие и влияние исходного окна не измерялись. Буферизация подтверждена отдельным опытом. Не утверждать, что в исходной попытке окно точно отсутствовало.

## Доказательства и состояние

В worktree `testlab-development/ProxyBridge-TestLab/artifacts/local-completion`:

- `official400-user-confirmation-retry-{start,final}.json` — исходный FAIL;
- `official-cli-crash-events-20261023.json` — выбранные event1000;
- `official400-startup-timing-20261023-165817/result.json` и `console.jsonl` — timing опыта;
- `diagnose400_startup.py` — одноразовый observer существующего Product.capture/close, записывает время получения bytes, не изменяет продукт/пакет; вне Git.

После опытов OFF verified, product processes0; ProxyBridgeDrv Stopped/Manual, прежний path; WinDivert отсутствует. Product source/binaries, установщик, BCD, signing/trust не менялись. Текущий пакет preview.11 не модифицирован. Автотесты в репозиторий не добавлены.

Исправление здесь не реализовано. Корректное продуктовое решение: явный flush READY/логов и сериализованная остановка с доказанным завершением потоков до unload. Возможную адаптацию TestLab надо проверять отдельно; запрещено считать отсутствие READY успехом или подменять официальный CLI старым patched testlab-cli.
