# T-151 — Дата среза готовности в часовом поясе проекта

Статус: in_progress. Исполнитель: Codex.
Основание: LOW-04 аудита Gemini 4 Neon от 2026-11-28.

## Зона файлов

- `scripts/project-viewer.ps1`
- `scripts/project-viewer.html`
- `tests/project-viewer-regressions.ps1`
- `tasks/T-151-viewer-progress-local-date.md`

## Приёмка

- Дата среза готовности рассчитывается на сервере в том же часовом поясе, что и дата прогноза.
- Без шкалы этапов применяется UTC. Исходный момент asOf сохраняется.
