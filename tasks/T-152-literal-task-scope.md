# T-152 — Буквальные пути в зоне задачи

Статус: in_progress. Исполнитель: Codex.
Основание: GATE-03 аудита Gemini 4 Neon от 2026-11-28.

## Зона файлов

- `scripts/verify-task-scope.ps1`
- `tests/task-scope-regressions.ps1`
- `tasks/README.md`
- `tasks/T-152-literal-task-scope.md`

## Приёмка

- Зона содержит точные пути. Шаблоны отклоняются до сравнения путей.
- Unicode, регистр Windows, проверка чистоты и точные ревизии сохраняются.
- Регрессии зоны и сохранности состояния Git проходят.
