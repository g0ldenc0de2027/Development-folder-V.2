# T-141 — Не предлагать автоматическое действие для completed

Статус: in_progress.
Исполнитель: Codex.
Основание: LOW-03 аудита Gemini 4 Neon от 2026-11-28.

## Зона файлов

- `scripts/project-viewer.ps1`
- `tests/project-viewer-regressions.ps1`
- `tasks/T-141-viewer-completed-action.md`

## Приёмка

- HTTP-сводка сохраняет статус completed и исходный блокер, но не предлагает автоматическое действие.
- Явное указание владельца сохраняет приоритет. Остальные статусы не меняются.
