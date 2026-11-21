# T-038 — Разделить вывод и диагностику Git при аудите worktree

Статус: in_progress. Аудиты ZCode V2Z-008 и Qoder B-013.

## Зона файлов

- `scripts/task-worktree-audit.ps1`
- `tests/task-worktree-regressions.ps1`
- `tasks/T-038-worktree-git-output.md`

## Приёмка

Разбор Git получает только UTF-8 stdout. Предупреждения доступны в verbose, ошибки Git сохраняют отказ и stderr. Изоляция Git-конфигурации и временный индекс commit сохраняются.
