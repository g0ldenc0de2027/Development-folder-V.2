# T-038 — Разделить вывод и диагностику Git при аудите worktree

Статус: merged. [PR #37](https://github.com/g0ldenc0de2027/Development-folder-V.2/pull/37), squash c19c27eb4ff486ac932e30a94fa990f10b1a426b. [CI main #44862514834](https://github.com/g0ldenc0de2027/Development-folder-V.2/actions/runs/44862514834) завершился успешно. Аудиты ZCode V2Z-008 и Qoder B-013.

## Зона файлов

- `scripts/task-worktree-audit.ps1`
- `tests/task-worktree-regressions.ps1`
- `tasks/T-038-worktree-git-output.md`

## Приёмка

Разбор Git получает только UTF-8 stdout. Предупреждения доступны в verbose, ошибки Git сохраняют отказ и stderr. Изоляция Git-конфигурации и временный индекс commit сохраняются.
