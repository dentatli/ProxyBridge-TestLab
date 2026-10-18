# Lookup miss: результат четырёхсоединительной пробы

USER Run `pb-kd-lookup-four-run-20261018-084301-49f7a3bd` завершён. Все четыре native соединения успешны. Четыре uniquely correlated исходных запроса Core вернули api_return0/api_error0, по32 байта полного IPv4 контекста; peer ports55745..55748. Исходный10022 в этой пробе не воспроизведён. Native report остаётся `KD_LOOKUP_FOUR_NATIVE_EVIDENCE_CONFIRMED_DEBUGGER_PENDING`, errors[]. Оригинальные отчёты не менялись.

В console USER9868564e показаны новые2/3d, be2/be3, только2/3e с точными actions/адресами и отдельный g. Событий PBKDL EARLY_MISS/SEARCH_MISS/UNREADABLE нет. Ошибок Memory access/Syntax/Bad register не показано. Это не подтверждает исполнения тела failure-actions, доступности новых stack reads или полного kernel coverage. Не считать отсутствие строк доказательством отсутствия traps: +22e посещается и при успешном поиске.

WinDbg вывел `Unable to load image ... Ndu.sys, Win32 error 0n2`. Это сообщение загрузки образа отладчиком; по нему нельзя утверждать отказ Ndu.sys в VM или связь с10022. Затем показан ручной Break80000003, не crash. В конце bd2/bd3 без показанной ошибки и отдельный g, но post-disable bl отсутствует. Команды отключения подтверждены, финальный disabled inventory отдельно не наблюдался. Не запрашивать новый Break только ради этого; проверить inventory перед следующим согласованным enable.

Controller elapsed107.345397s, hold workload8s. Это разные интервалы; причина длительности не установлена. Не превращать эту диагностическую пробу в оценку скорости и не приписывать всё время точкам без дополнительного доказательства. Общая точка +22e сохраняет риск observer effect.

Workload COMPLETED, workers_stopped/driver_stop_observed=true; CLI graceful_stop/post_stop_verified=true, forced_stop=false, error пустой. Проверены все8291 frozen SHA, planSHA81FC33A6288B324DCB9880735728E0699729C5C804292FB07A2791C9DB4F3A24;39 inputs (run files и console) неизменны после read-only разбора. Console SHA25671d2d9839fe54d35e17f33f4d61eeab0e19b67259a44d74c6ee218b91f8a04c7. Private audit `artifacts/diagnostics/pb-kd-lookup-four-result-review-20261018`.

## Стоп

Four kit израсходован, не повторять Run и не запускать bounded/640 автоматически. Продукт/старые kits не менять. Новых фактов о выборе между двумя группами NOT_FOUND нет. Следующий офлайн шаг — пересмотреть места перехвата для сокращения traps успешного пути перед новым нагрузочным замером; не обещать одновременное полное покрытие всех исторических причин двумя точками. Runtime stack reads остаются pending. 10061 отдельно не расследовать. Любой новый профиль требует своего review/kit, а USER Break/enable — предупреждения об остановке всей VM/Codex/RDP и recovery bd2/bd3/bl/g по одной, g отдельно даже при ошибке. Агент debugger/Run не выполнял.
