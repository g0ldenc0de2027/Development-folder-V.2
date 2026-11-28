# T-140 — Диагностика подключения общей БЗ из worktree

Статус: in_progress.
Исполнитель: Codex.
Основание: BUG-09 сверки аудита Gemini 4 Neon от 2026-11-28.

## Зона файлов

- `docs/local-knowledge.md`
- `tasks/T-140-kb-worktree-discovery-docs.md`

## Приёмка

- Руководство объясняет выбор локального маркера в linked worktree и настройку пути на текущий сеанс.
- Описаны состояния not_configured, KB_SHARED_UNAVAILABLE и available_not_validated.
- На базе 57cab22 doctor без явной настройки вернул not_configured. Путь из маркера административного корня, переданный явно, вернул KB_SHARED_UNAVAILABLE. Содержимое общей БЗ не проверялось.
