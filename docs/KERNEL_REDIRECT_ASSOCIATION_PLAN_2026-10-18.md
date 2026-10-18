# Создание и прикрепление redirect record: следующий шаг

## Live review получен 2026-10-18

Console attachment `427bf7fb-2133-4be4-a219-8e2ca524b9fa`, SHA256 `9e1cf84fc2431f976db6edd49d61e99ef6288cbf317029c68b330570c9ef1e96`: исходный bl показывает только2/3d; обе uf выполнены, отдельный g показан. Ошибок чтения/дизассемблирования в выводе нет. Private audit `pb-kd-association-live-review-20261018` сохраняет raw console и review.json. Из345инструкций337 совпадают с текущим диском; оставшиеся8 образуют4пары import-call rewrite (disk indirect call+NOP, live mov r10+direct call). Это сравнение присланных инструкций, не runtime trace выполнения функций.

Текущие live symbols подтвердили WfpTlShimInspectFastLoopbackSendDatagram RVA d7e80 и AlepCreateRedirectRecord RVA108520. Для key5 association live call находится на+9b, return/test RAX на+a0. Аргументы совпадают с офлайн-разбором: RBX source endpoint, RBP NBL, R9 record из endpoint+1c0, key5 в caller rsp+20. Ненулевой результат проходит ветку+a5 и пропускает следующий key4 association. Эти наблюдения подтверждают расположение кода, но не факт вызова/успеха для failed connection.

Create-функция выделяет228h bytes, копирует16/28байт из двух входных адресов в record+48/+c8 в зависимости от family, заполняет метаданные, сохраняет прежний endpoint record в new_record+30, если он был. В TCP-ветке с очищенным битом10h endpoint+30 сохраняет новый указатель в endpoint+1c0 на+38f; на+396 уже следующий jump. Имена local/remote/original/redirected для скопированных адресов ещё не подтверждены caller-разбором. Не вводить port-фильтр по предположению о значении +48/+c8. Имеется и отдельная hash-table ветка для других условий; наличие её кода не доказывает переполнение таблицы.

После key5/key4 участков caller вызывает AleAcceptRedirectProxyNblTag. В текущем disk-листинге его RVA d7ff4..d8073 содержит association с key9, а не5; текущий live body ещё не получен. Следующий короткий USER read-only шаг: beforeBreak wholeVM/Codex/RDP warning, recovery bd2/bd3/bl/g отдельно; bl только2/3d, затем uf tcpip!AleAcceptRedirectProxyNblTag, отдельно g даже после ошибки. Ниbp/be/step/Run. Это проверка границы key5/key9 перед выбором минимального профиля, не новая нагрузочная проба. Затем продолжить офлайн корреляцию адресов record с Core; новые stage/plan пока не подготовлены.

Продукт и существующие профили не менялись. Причина10022, частота выбранных callsites и полная история failed lifetimes остаются неустановленными. Ниже исходный план до получения live-кода.

Основание — [одноточечный bounded результат](KERNEL_EARLY_MISS_QUERY_NULL_CANDIDATE_2026-10-18.md):32Core10022 и32QUERY_NULL, без прямой связи kernel-события с конкретным socket/seq. Само повторение NULL дальше не объяснит предшествующее отсутствие записи. Продукт, точки и нагрузка агентом не менялись.

## Проверено по текущему дисковому образу

Текущий tcpip.sys SHA256 `b0683bd7ed0f309e63b4e6e71675d8f04cfb0ea5533c3f5e8a13c6daca3b595a`. MSVC dumpbin использован только для чтения образа. Preferred image base этого PE —140000000, не180000000. Исторический абсолютный адрес/предположение о расположении функций не прошли проверку prologue по RVA d68e0; эта попытка сохранена как rejected-layout, не как соответствующий текущий код. Участок найден заново по текущей IAT, без переноса старых абсолютных адресов.

В IAT RVA24dde8 подтверждён импорт fwpkclnt!FwppNetBufferListAssociateContext. В текущем коде найден caller с функцией RVA d7e80..d7fec, подтверждённой exception directory. По историческому имени это кандидат `tcpip!WfpTlShimInspectFastLoopbackSendDatagram`; соответствие имени текущим live symbols ещё не проверено. Проверены20инструкций prologue/условий/аргументов/возврата.

Ветка проверяет бит13 поля исходного endpoint+34. В неё поступает record из[RBX+1c0], перед вызовом увеличивается счётчик по record+1f0. В аргументах: источник endpoint=RBX, NBL=RDX/RBP, record=R9, key5 в caller[RSP+20], callback в caller[RSP+40]. Это схема конкретного caller, не восстановление stack offsets старой неисправной точки17.

В дисковом образе call начинается на function+94; аппаратный return address +9b, затем NOP и test RAX на+a0. На+a5 находится ветка ненулевого результата прикрепления; нулевой результат caller пропускает дальше. Называть test на+a0 фактическим live return address нельзя до чтения загруженного import call. Частота участка не измерена, выполнение один раз на соединение не доказано: такой путь может посещаться для нескольких пакетов. Фильтр по порту сократит вывод, но не обязательно traps.

Отдельно найдена запись [RDI+1c0]=RAX по RVA1088af, offset38f функции108520..10894a. Это кандидат `AlepCreateRedirectRecord` из прежнего плана. Проверены6инструкций вокруг store: ветка с[endpoint+28]==6 и дополнительным условием поля+30; после store следует jump на функцию+396. Это подтверждает наличие assignment в текущем disk-коде, но не выполнение создания для32failed lifetimes. Происхождение record и смысл адресных полей для корреляции ещё не проверены.

Private audit `artifacts/diagnostics/pb-kd-association-offline-review-20261018`: current dumpbin listing, PE import/unwind/bytes checks, store candidates, rejected-layout. Приватные листинги не добавляются в Git.

## Что нужно узнать дальше

Текущий live-код двух функций: фактическая форма вызова прикрепления, условия выбора ветки и заполнение record перед store. Затем выбрать минимальные наблюдения, которые дадут положительную цепочку: record существует → попытка прикрепления с известным NBL → результат. Для связи с Core нужен проверенный tuple или другая устойчивая идентичность; равенство одного NBL/endpoint address при возможном reuse недостаточно. Создание, попытка прикрепления и его успех — разные наблюдения. Ранее измеренный retrievalC0000225 нельзя приписать новым lifetimes.

Нового logger profile/stage/kit/Run пока нет. Не возвращать общий FwppNetBufferListAssociateContext или прежнюю17; не обещать полную цепочку двумя точками. При необходимости использовать отдельные фазы наблюдения через общий запускатель, с честным ограничением coverage.

## Только USER чтение кода

Перед Break предупредить: остановится вся VM PB-BUILD-W11-25H2, включая Codex/RDP. Заранее recovery bd2/bd3/bl/g по одной; g отдельно даже при ошибке. Проверить bl: только зарегистрированные2/3, обеd; при другом inventory прекратить этот шаг, восстановить выполнение и прислать вывод. Затем по одной uf tcpip!WfpTlShimInspectFastLoopbackSendDatagram и uf tcpip!AlepCreateRedirectRecord. Закончить отдельным g даже при ошибке. Никаких bp/be/step/Run. Не делать reload со снятием проверки соответствия symbols. Полный вывод прислать в чат, без Desktop instructions или обязательного logopen.

После вывода сопоставить live symbols/RVA/байты с disk. Только затем готовить конкретные точки и plan. Старые комплекты не Resume/refreeze, продукт не менять,10061 отдельно не расследовать.
