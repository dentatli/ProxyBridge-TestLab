# Управление ветками продукта

Решение пользователя от 22 октября 2026: `dentatli/ProxyBridge:driver` —
контролируемая пользователем интеграционная ветка и база новых изменений.
Новые работы выполнять в отдельных ветках от неё. PR в `driver` открывать
только по явному требованию пользователя после его проверки; разрешение
создать PR не является разрешением слить его. Разрешение двух перечисленных
ниже PR не распространяется на будущие PR.

## Выполненная подготовка

- Fork `driver` обновлён fast-forward с `137d128` до upstream
  `InterceptSuite/ProxyBridge:Driver` на
  `63be0ebf9bec92bfba95ef3d6729c375aa9af84e`. Force-push не использовался.
- [PR #1](https://github.com/dentatli/ProxyBridge/pull/1):
  `codex/hlk-minimal-fixes` (`9b5fff5`) → `driver`.
- [PR #2](https://github.com/dentatli/ProxyBridge/pull/2):
  `codex/accept-before-setup` (`37e64c6`) → `driver`.
- Оба PR открыты и затем слиты по отдельному прямому запросу пользователя.
  PR #1 merge commit: `5408efae0e6fb1cbf376072ebb92168ca61d976d`;
  PR #2 merge commit: `eb8c1a72ed30dd8e6a2b5414d4086fe0a6bd7c06`.
  Использован merge с проверкой ожидаемого head SHA; конфликты не возникли.
  Новые builds/runtime/HLK/install не выполнялись.
- Новая ветка [codex/udp-map-source-key](https://github.com/dentatli/ProxyBridge/tree/codex/udp-map-source-key)
  первоначально создана от `driver` на `63be0eb`, после слияния обоих PR
  обновлена fast-forward до новой `driver` на
  `eb8c1a72ed30dd8e6a2b5414d4086fe0a6bd7c06`. UDP-патча и PR из неё пока нет.
  Включение обоих исходных head проверено через merge-base --is-ancestor.

Для новой ветки переиспользована чистая рабочая копия
`C:\src\ProxyBridge-accept-first`; её имя каталога историческое.
Она теперь находится на `codex/udp-map-source-key`, tracking
`dentatli/codex/udp-map-source-key`. Ветка `codex/accept-before-setup`
и её коммит сохранены. Диагностическая TestLab-копия не переключалась.

Fork `driver` и UDP-ветка сверены через ls-remote: обе указывают на
`eb8c1a72ed30dd8e6a2b5414d4086fe0a6bd7c06`. Upstream `Driver` при
синхронизации был `63be0eb`; новые merge commits добавлены только в fork.
Исторические captures и результаты
относятся к своим записанным версиям, а не к будущему объединённому продукту.
