# Новый сеанс:подготовлена регистрация только двух отключённых query точек

**Регистрация завершена:** USER прислал emptybl→stage→только3/4обаd/exactactions/.bpcmds→отдельныйg безпоказанныхошибок. Подготовлен [новый four-only комплект для точного профиля двух зарегистрированных точек](KERNEL_QUERY_SESSION_FOUR_PREPARATION_2026-10-17.md). Старыйstage повторно не загружать; ниже сохранена завершённая последовательность переноса/регистрации.

**Новый USER результат:** физический PowerShell подтвердил SHA ZIP F39D165BD1BABFEB186C7E54F39540783703761D9022AFEBFD0643652D17FAF3 вD:\Загрузки, затем Expand-Archive вC:\PB-KD-Query-Stage-20261017 вернулся без показанных ошибок. Хеш отдельных распакованных файлов на хосте не измерялся. Передача архива подтверждена; следующий шаг — USER регистрация только двух отключённых точек по плану ниже, затем отдельныйg и reviewconsole до enable/Run.

**Предпочтение USER для следующих команд:** ожидаемый SHA сравнивать автоматически внутри PowerShell команды, при несовпадении throw до распаковки/следующего действия. Не просить пользователя вручную сравнивать длинные хеши и не повторять уже подтверждённую проверку без нового основания.

17 октября2026, Asia/Yekaterinburg. USER после перезагрузки восстановил kd>, подтвердил пустойbl и отдельныйg. Следующий присланный console11:16:48 подтверждает .reload/s, локальные PDB из `C:\PB-KD-Symbols-20261016`, .reload/f nt/tcpip без показанных ошибок, MASM и ETHREAD.Cid+508. tcpip headers TimestampD26770CA/CheckSum355D78/ImageSize35A000 совпали с currentdisk. Сравнены все16 присланных live инструкций в двух фрагментах с PE rawbytes: exact, обе RVA12157c/121733 совпали с ожидаемыми offsets функции. Проверка всего live function/image этим не выполнена. Отдельныйg записан, bp/be/Run не наблюдались.

В первом фрагменте read `[rdi+1c0]` приNULL выбирает C0000225, во втором EBX переносится вEAX перед epilogue. Это **статическое подтверждение кода**, не наблюдение C0000225 в новом отказавшем flow. Последний [полный контроль](REDIRECT_CONTEXT_CONTROL_RESULT_2026-10-17.md) по-прежнему подтверждает96 uniquely matched Core10022/nativefail, NTSTATUS в нём не измерен.

## Новый stage

- `scripts/debugger/pb-kd-query-two-stage-20261017.wdbg`: только bp3/немедленноbd3 и bp4/немедленноbd4, затемbl/.bpcmds. Файл не выполняет внешнийg и не запускает трафик; агент его не выполнял. Регистрация происходит только при остановленной VM и заранее пустомbl. До отдельногоg обе точки должны бытьd. Других точек в скрипте нет.
- `scripts/debugger/pb-kd-query-two-profile-20261017.json`: новый профиль с registeredIDs[3,4], point_count2, initialstateempty/finalstatedisabled. Тела QUERY_READ/QUERY_STATUS буквально взяты из прежнего проверенного stage, только остальные точки отсутствуют. Комментарии не содержат semicolon, чтобы не повторить прежнюю ошибку$$.

StageSHA `5867d6a10871d6ef1a14bc2b46951e31cba5e5d777a2c56507f4316a6d8d653a`; profileSHA `e7667aee879f9fd9e9ca1b4d15901e285eb3bfd0aa8876ef6a0483dfc4abc676`.

**Не загружать stage семи или25 точек.** Свежий stage применяется только к пустому списку. Не называть профиль новой registration подтверждённым до USER console. Прежний195830-aaf0be71 был подготовлен для выбора3/4 изexisting7; его policy/manifest не соответствуют новой регистрации только двух. Старый kit и все его источники сохранены; новый four-only kit с точным профилем и подтверждением регистрации будет подготовлен отдельно. Run-команды сейчас нет.

Архив на рабочем столе VM: `C:\Users\LabAdmin\Desktop\PB-KD-Query-Stage-20261017.zip`,2536bytes, SHA256 `F39D165BD1BABFEB186C7E54F39540783703761D9022AFEBFD0643652D17FAF3`. Внутри толькоstage/profile/README, CRC/roundtrip exact. Privateaudit `artifacts/diagnostics/pb-kd-query-two-stage-review-20261017/validation.json`,live-code-observation.json,protected-inputs.json и копии содержимого ZIP.9 prior inputs unchanged. Первичная проверка сравнивала uppercasePS SHA с lowercasePython строкой; это исправлено в offline audit, фактических hash mismatches0. Это не WinDbg/runtime ошибка. Архив/логи/audit не в Git.

## Завершённый USER шаг:перенос и hash

Скопировать новый ZIP с рабочего стола VM на физический ПК в `D:\Загрузки`. В PowerShell физического ПК:

```powershell
Get-FileHash -LiteralPath 'D:\Загрузки\PB-KD-Query-Stage-20261017.zip' -Algorithm SHA256
```

Только если SHA точно совпал, распаковать в новый каталог, безForce:

```powershell
Expand-Archive -LiteralPath 'D:\Загрузки\PB-KD-Query-Stage-20261017.zip' -DestinationPath 'C:\PB-KD-Query-Stage-20261017'
```

Передать результат, пока без Break/загрузки stage/enable/Run. Агент их не выполняет.

## Текущий USER шаг после подтверждения переноса

Перенос подтверждён, можно выполнять только эту регистрацию с отключением доg. Заранее сохранить на физическом ПК все шаги и recovery. **Break/регистрация/enable могут остановить всю VM, включая Codex иRDP.** При activekd> дополнительныйBreak не нужен. Каждую outer command вводить отдельно.

1. Break, затем `bl`. Если список не пуст, stage не загружать, отдельноg и передать весь inventory.
2. При пустомbl один раз `$<C:\PB-KD-Query-Stage-20261017\pb-kd-query-two-stage-20261017.wdbg`. Ожидаются толькоIDs3/4, обаd, два точных тела в .bpcmds.
3. При ошибке stage не загружать повторно. Отдельноbd3, отдельноbd4, затемbl, затем **отдельныйg даже после ошибки предыдущей команды**. При успехе тоже отдельныйg.
4. Прислать полный console. До его review не be/Run. Не считать registration доказательством выполнения actions/gc/metadata binding.

Далее свежий frozenfour-only kit и конкретное согласование USER одной пробы4, сначала reviewconsole и только потом решение о64/256. Две query точки не покрывают создание/прикрепление/освобождение record; отсутствие таких событий не доказывает отсутствие операций. ПорогRAM2ГиБ не снижать, штатно освободить память до опыта. Продукт/драйверную установку/BCD/гипервизор/питание/соседнюю рабочую копию не менять.
