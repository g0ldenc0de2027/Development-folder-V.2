# T-023 — Изолировать Git при откате core.bare

Статус: in_progress. База: 3dea0fda3aa2cd68de47a9e91079220c25dc5d51.
Источник: follow-up ревью Antigravity в карточке T-015.

## Зона файлов

- `scripts/lib/GitIdentity.psm1`
- `tests/git-identity-regressions.ps1`
- `tasks/T-023-isolate-git-rollback.md`

## Приёмка

Проверить допустимость миграции до создания admin override. При отказе общего Git config убрать только admin override, добавленный текущим вызовом, через тот же изолированный Git runner. При отказе самого отката выдать отдельную диагностику. Проверить регрессией отказ при занятом config.lock, сохранность общего config и возможность штатной повторной миграции.
