# T-050 — Сохранять UTF-8 в тестах worktree

Статус: in_progress. Неблокирующее замечание ревью T-038.

## Зона файлов

- `tests/task-worktree-regressions.ps1`
- `tasks/T-050-worktree-test-utf8.md`

## Приёмка

Помощник тестов явно декодирует stdout и stderr Git как UTF-8. Все штатные worktree-регрессии проходят при прямом запуске с Console.OutputEncoding 866, включая проверку с кириллическим путём remote.
