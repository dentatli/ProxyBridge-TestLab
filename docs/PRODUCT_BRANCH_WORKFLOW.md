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
- Оба PR открыты по прямому запросу пользователя, не слиты. Локальный
  `git merge-tree --write-tree` для каждого head с актуальной базой прошёл
  без конфликтов. Новые builds/runtime/HLK/install не выполнялись.
- Новая ветка [codex/udp-map-source-key](https://github.com/dentatli/ProxyBridge/tree/codex/udp-map-source-key)
  создана и опубликована ровно от `driver` на `63be0eb`. UDP-патча и PR
  из неё на момент подготовки нет. Изменения двух открытых PR в неё пока
  не входят; после их слияния пользователем потребуется обновить базу.

Для новой ветки переиспользована чистая рабочая копия
`C:\src\ProxyBridge-accept-first`; её имя каталога историческое.
Она теперь находится на `codex/udp-map-source-key`, tracking
`dentatli/codex/udp-map-source-key`. Ветка `codex/accept-before-setup`
и её коммит сохранены. Диагностическая TestLab-копия не переключалась.

Upstream `Driver`, fork `driver` и новая UDP-ветка сверены через ls-remote:
все три указывают на полный SHA выше. Исторические captures и результаты
относятся к своим записанным версиям, а не к будущему объединённому продукту.
