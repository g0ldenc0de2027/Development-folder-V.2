# T-023 — Изолировать Git при откате core.bare

Статус: merged. База: 3dea0fda3aa2cd68de47a9e91079220c25dc5d51.

Интеграция: [PR #22](https://github.com/g0ldenc0de2027/Development-folder-V.2/pull/22), squash `4fcb7f8557d4337b8e865305eab4537ca891c8a7`.
Источник: follow-up ревью Antigravity в карточке T-015.

## Зона файлов

- `scripts/lib/GitIdentity.psm1`
- `tests/git-identity-regressions.ps1`
- `tasks/T-023-isolate-git-rollback.md`

## Приёмка

Проверить допустимость миграции до создания admin override. При отказе общего Git config убрать только admin override, добавленный текущим вызовом, через тот же изолированный Git runner. При отказе самого отката выдать отдельную диагностику. Проверить регрессией отказ при занятом config.lock, сохранность общего config и возможность штатной повторной миграции.
