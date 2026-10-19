# Следующий наблюдатель: отправка и ассоциация контрольного SYN

Статус: offline design, не runnable профиль. Старые consumed планы не менять.
Точки2/3 отключены пользователем,4 оставлена отключённой; VM resumed.

## Проверенные статические переходы

Исходник анализа — сохранённый disassembly tcpip.sys SHA256
`b0683bd7ed0f309e63b4e6e71675d8f04cfb0ea5533c3f5e8a13c6daca3b595a`.
Ниже RVA; новые live-участки ещё не проверены пользователем.

- `TcpRetransmitTimeout`51150 вызывает `TcpRtoTimeout`51650, который вызывает
  `TcpUpdateTcbSend`46564. Последний обновляет tracker через `TcpLocateTcbSend`.
  Само по себе это не доказывает прямой синхронный вызов отправки.
- `TcpTcbSend`94bb0 перед вызовом `InetFastSendDatagramsOnPathAf`953c2 держит
  TCB в RDI, packet/NBL в R13. Передаёт TCB+388 в stack argument9 (caller+40).
  В callee этот аргумент попадает в RSI и далее request+8: инструкции95fd6,
  961b0/961b4. Не путать с TCB+390, который идёт другим аргументом.
- В `IppSendDatagramsCommon` request+8 становится RCX при вызове
  `WfpTlShimInspectFastLoopbackSendDatagram`7d731. Это источник ALE endpoint
  для уже изученной привязки record+1c0.
- Локальный raw-port TCB+74 подтверждается `TcpBeginTcbSend`96a70..96a82:
  значение передаётся R9w в `InetFormatLocalSockAddrAtDispatchLevel`, который
  записывает его в sockaddr+2. TCB+76 используется для peer-port; фильтр должен
  проверять оба порта и семейство, а не только equality адреса endpoint.
- Участок d7e80..d7ecf проверяет endpoint!=0, endpoint+30 bit21 и endpoint+34
  bit13. При разрешённой привязке берёт endpoint+1c0 и вызывает AssociateContext
  d7f14; после вызова d7f20 проверяет RAX. Live call может быть hotpatched,
  поэтому сохранённый disk opcode не подменяет обязательное live-чтение.

## Пять точек вместо повторения REMOVE

1. ID2: прежний CREATE+396, один control raw-port d9a4/family2. Сохраняет record
   в t1 и source endpoint в t2; повторный CREATE явно отмечать как неоднозначность.
2. ID3: `TcpTcbSend+812` (RVA953c2), непосредственно перед fast-send call.
   Guarded TCB reads: family через TCB+18, local+74, peer+76, source_ep+388.
   Отбор family2/locald9a4/peerda84. Печатать thread/scope/TCB/NBL/source_ep,
   отдельно состояние endpoint+30/+34/+1c0 при ненулевом читаемом указателе.
   Нулевой или другой endpoint не скрывать фильтром t2.
3. ID4: `WfpTlShimInspectFastLoopbackSendDatagram` entry, RCX=t2, R8=NBL.
   Печатать состояние endpoint и record. Ограничение: другой/нулевой source_ep
   будет виден в SEND, но не обязан попасть под этот observer.
4. ID5: та же функция+а0 (RVAd7f20), после ассоциации key5: RBX=source_ep,
   RBP=NBL, RAX=result_raw. Фильтр RBX=t2, thread/scope для сопоставления;
   не называть произвольный raw-return NTSTATUS без контракта.
5. ID6: прежний `WfpAleAuthorizeAccept+caf`, family/ports selector по уже
   проверенному frame. Печатать status/output_raw/NBL/accept_ep; output при
   неуспехе не считать успешно возвращённой record.

Без стеков и packet payload. Печать только выбранного соединения, но стоимость
попадания в software breakpoint сохраняется и для остальных вызовов.
Новое наблюдение не обещает полного lifetime или гарантированной причины10022.
Два SEND не объявлять retry только по порядку строк: сопоставить native/ETW,
идентификаторы и окно control; недостающие строки означают неполное покрытие.

## До подготовки Run

Прочитать live `TcpTcbSend+7b0 L20`, `InetFastSendDatagramsOnPathAf+3f L3`,
`InetFastSendDatagramsOnPathAf+220 L3`, loopback entry L24 и +94 L7.
Это только disassembly, не регистрация/активация. Затем создать отдельный
profile/stage и проверить реальные actions через CDB с безопасными fixture
ветвями. Интегрировать новый точный контракт в существующий универсальный
launcher; прежние профили и positive baseline не объявлять проверкой нового.
Prepare до живой сверки не выполнять. Нагрузку не запускать автоматически.

Before Break/be: предупредить о паузе всей VM, Codex и RDP. Recovery для будущего
набора: отдельные bd2,bd3,bd4,bd5,bd6 и отдельноg даже при ошибке. Activation и
Break остаются у пользователя на физическом хосте. Общий комплект дать после
проверок, без дополнительного промежуточного разрешения на регистрацию.
