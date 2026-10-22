# Управление ветками продукта

Решение пользователя от 22 октября 2026: `dentatli/ProxyBridge:driver` —
контролируемая пользователем интеграционная ветка и база новых изменений.
Новые работы выполнять в отдельных ветках от неё. PR в `driver` открывать
только по явному требованию пользователя после его проверки; разрешение
создать PR не является разрешением слить его. Разрешение двух перечисленных
ниже PR не распространяется на будущие PR.
Способ будущего слияния — **Squash and merge**: один законченный PR,
один коммит в `driver`.

## Актуальное состояние после очистки истории

По явному требованию пользователя обычные merge commits заменены двумя
squash-коммитами поверх upstream `63be0eb`:

- `3624e620189bff243c2c0462df9aff981944b2e6` — изменения PR #1, HLK/KMDF;
- `b3596272a8dc8898790b016d1e4c488c2fdc917d` — изменения PR #2, accept-before-setup.

Fork `driver` и `codex/udp-map-source-key` опубликованы на `b359627` одним
atomic push, с отдельным force-with-lease по ожидаемому старому SHA каждой
ветки. Это разовое явно разрешённое переписывание; будущие force-push этим
не разрешены. Проверено: ровно два коммита поверх `63be0eb`, оба без merge
parents; итоговое Git tree полностью совпадает с прежним `eb8c1a7`, дерево
первого squash совпадает с прежним результатом PR #1. Код не менялся,
build/runtime не повторялись.

GitHub PR #1/#2 сохраняют исторические записи первоначального merge;
уже состоявшийся способ слияния в карточке PR задним числом не меняется.
Новая история веток построена эквивалентными squash-коммитами.

В Git repository рабочей копии `C:\src\ProxyBridge-accept-first` прежний
`eb8c1a7` сохранён локально в
`refs/codex-backups/driver-before-squash-20261022` и
`refs/codex-backups/udp-map-before-squash-20261022`.
Существовавшая старая локальная `driver` имела отдельный коммит и сохранена
как `archive/driver-before-cleanup-20261022`; новая локальная `driver`
соответствует `dentatli/driver`. Рабочая UDP-ветка чистая и также на `b359627`.
Исходные feature-ветки PR не переписывались. Новый UDP PR не создавался.

## Предыдущая подготовка до очистки истории

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
Она находится на `codex/udp-map-source-key`, tracking
`dentatli/codex/udp-map-source-key`. Ветка `codex/accept-before-setup`
и её коммит сохранены. Диагностическая TestLab-копия не переключалась.

Перед очисткой fork `driver` и UDP-ветка были сверены через ls-remote на
`eb8c1a72ed30dd8e6a2b5414d4086fe0a6bd7c06`. Upstream `Driver` при
синхронизации был `63be0eb`; новые merge commits добавлены только в fork.
Исторические captures и результаты
относятся к своим записанным версиям, а не к будущему объединённому продукту.
