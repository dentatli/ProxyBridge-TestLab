# QUIC close timer — preview.61, 27 октября 2026

Исправлен критерий завершения из [H2-аудита60](PB_SUT_WINDIVERT_H2_60_AUDIT_2026-10-27.md). После отправки CONNECTION_CLOSE клиент использует публичный conn.get_timer() закреплённой aioquic, а не фиксированные2с. Включён первый pump(0), который начинает библиотечный closing period. При достижении таймера обрабатывается его событие; небольшая scheduling grace не превращает отсутствие события в PASS.

Общий бюджет закрытия8с, с запасом под5с handshake и запуск процесса в существующем15с grace изолированного worker. Внешние deadlines не увеличены. Невыполненный close/неизвестный timer/отмена остаются неуспехом, ошибки явные (CLOSE_BUDGET_EXCEEDED/CLOSE_TIMER_EXCEEDED/CLOSE_TIMER_UNAVAILABLE/TRAFFIC_CANCELLED). Записываются close_timer_seconds, close_wait_budget_seconds, close_wait_limit_seconds, close_wait_elapsed_seconds иclose_verified. Проверки сертификата, данных, маршрута и remote idle сохранены. Одна функция используется QUIC/HTTP3 в обычном и длительном режимах, независимо от WFP/WinDivert.

## Подтверждения

- В существующем tests/test_traffic_quic.py добавлены2необходимые regression-проверки (подслучаи immediate/0.1/3.3с, превышение8с, отсутствие события, отмена). Все6QUICпроверок PASS. Для сравнения вещественных timestamp учтён rounding tolerance1e-9; это поправка теста, не ослабление времени приложения.
- Реальная aioquic1.3.0 + Pythonorigin/C#relay + официальный WinDivert4.3.0Core наVM. Только в контрольном harness увеличен локальный PTO при начале закрытия; прикладной обмен и cryptographic/route gates не подменялись. QUIC и HTTP3 прошли с таймером3.3с/ожиданием3.375с, close_verified=true, маршрут подтверждён. При таймере12с клиент остановился через8.015с с явным CLOSE_BUDGET_EXCEEDED, complete=false; scheduler может добавить миллисекунды к бюджету.
- Corecleanup подтверждён,forcedstopfalse; после выхода нет ownedпроцессов/WinDivertслужб. ProductDLL/SYS,BCD/trust/установкаWFP не менялись. Сокращённые проверки проходят в прежнем разрешённом scope официальной4.3.0, без реального WFPпрогона.

Evidenceignored: artifacts/endurance-check/check61-close-confirmed.log/.exit иprobe-1793096052249287900 (quic/http3/overlimit-close61.json). Первая harness-попытка имела неправильный run_id вне разрешённого queue prefix, relay правильно отклонил обмен; после исправления только harness-ID подтверждения выше прошли. Исходные отчёты/SUTистория не исправлялись.

Код не доказывает, что исторический QUICFAIL60 был вызван именно3PTO>2с: его таймер не записан. Исправлена подтверждённая методическая ошибка; новый H2/24ч после исправления ещё не выполнялся. Действия PROXY/DIRECT/BLOCK и прежний профиль60 сохранены.
