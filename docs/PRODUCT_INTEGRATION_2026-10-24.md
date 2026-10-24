# Продукт: UDP и TCP DIRECT объединены в driver

Актуальный checkpoint после явного разрешения USER на слияние, сборку,
установку нового драйвера, удаление старого и очистку продуктовых веток.
Лабораторный трафик USER запускает самостоятельно.

## Единая версия

- `dentatli/ProxyBridge:driver` = `4da324edff84d566ebc1de1acaab1ba077fcab31`.
- UDP: [PR3](https://github.com/dentatli/ProxyBridge/pull/3), squash
  `837e4f4e50678503ec2004d0ba7afca4c89aa753`, исходный head b993913.
- TCP DIRECT: [PR4](https://github.com/dentatli/ProxyBridge/pull/4), squash
  `4da324edff84d566ebc1de1acaab1ba077fcab31`, исходный head340bdc8.
- Обе правки теперь действительно входят в driver. Старый preview41 full50
  36PASS/14FAIL относится к b359627 + baseline SYS, а не к новой версии.

## Сборка и установленный пакет на agent VM

Новый комплект CLI/Core/SYS для лаборатории:
`C:/src/ProxyBridge-TestLab/artifacts/product-builds/driver-4da324e-combined-20261024-r1/release`.
Точная provenance и hashes — `manifest.json`; исходники были чистыми.
Core/CLI compile exit0; driver Release/native analysis exit0 без диагностик;
standalone InfVerif /w, подпись SYS и каталог — exit0. MSBuild использовал
SkipPackageVerification=true из-за известного отсутствующего x86 verifier;
отдельный штатный x64 InfVerif выполнен. HLK/полный runtime suite не запускались.

Установлен `oem4.inf`, версия1.1.0.0, на прежний devnode
`ROOT\INTERCEPTSUITE_PROXYBRIDGE\0000`. SYS SHA256
`5a29f6b7af37ec2a266520187e5fda304cf1526520e074c0fadeb8dc79f11cce`.
Core SHA256 `d442a5e6807f1d637c202e6d140a58ecff86bb095164a9d4e8ed49fa4770df4e`.
Driver был активирован: PnP problem0, service Running, живой UDP_CAPS вернул
ABI1, record84, maxPayload65507, batch262144. После проверки возвращён исходный
idle режим: PnP disabled/problem22, service Stopped/Manual. Лаборатория включает
devnode на очередь и отключает после неё. Это не результат проверки трафика.

Старый `oem3.inf`1.0.0.1 удалён из DriverStore после проверки нового пакета;
экспорт для отката сохранён в `install-evidence-r2/baseline-package` рядом
с release. Итог — `install-evidence-r2/result.json`. Первый проход откатился
из-за устаревших WMI метаданных; r2 читает прямые PnP properties, завершился
успешно. Первые logs/evidence сохранены. Trust/BCD/proxy/power не менялись,
reboot не запрашивался. Физический PB-SUT этим этапом не изменялся.

## Лаборатория и следующий шаг

Через штатный API файлового выбора сохранён **WFP driver 4da324e (UDP + TCP DIRECT)**.
Build ID `build-e513fd527f8310ac13b0782bd45800af2e00c69735e2ec76b6df23c63a33c633`.
Bundle SHA256 `8d0c92ee45031cd1eef6bf49a5e84392d083945d4e95560a9b21e4c5b6ce7b68`.
Повторное чтение подтвердило выбор; controller busy=false/active=false.
После попытки `20261024-171408-a5ac866bf16846c88dfa3f19d958ebbc` исправлен
DriverPath выбранного build: вместо SYS из release указан установленный SYS
в DriverStore. Файлы имеют одинаковый hash, но guard требует также совпадение
пути с SCM. Попытка остановилась до Core Start/трафика; её raw reports сохранены.
После исправления штатный Assert-TrafficLabIdle.ps1 вернул exit0,
off_verified=true/file_verified=true. Build ID и bundle hash не изменились;
карта путей обновлена в каталоге через API. Сетевые тесты не запускались.
Evidence: `idle-installed-path-result.json`, `lab-selection-installed-path.json`
рядом с release. Эта проверка закрывает только причину ошибки подготовки.
Статус VALIDATION_REQUIRED: файлы выбраны, но совместимость и новый full50
ещё должен проверить USER. Не подменять этот результат прежними UDP/TCP gates.
Новые диагностические socketpair trials не запускались: выбрана интеграция
готовых исправлений и пользовательская проверка через лабораторию.

## Ветки и сохранность истории

В fork остались `driver` и стандартная `master`; локально в продуктовом repo
только driver.11 старых удалённых branch refs заменены проверенными архивными
тегами `archive/20261024/<прежнее-имя-ветки>`; две прежние local-only ветки
сохранены локальными тегами `archive/20261024/local/<имя>` без публикации.
Не все архивные альтернативы входят в driver; их код сохранён тегами.
Полная карта13refs — `branch-archive.json` рядом с release. Force-push не было.
Обе дополнительные продуктовые worktree сохранены detached; чужие изменения
TestLab и KernelReadCapture не затрагивались. Прежний offline-разборcb84e70
сохранён архивным тегом и файлами `historical-*.md` рядом с release.
