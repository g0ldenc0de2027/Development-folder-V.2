# T-154 — Строгие типы JSON в просмотрщике

Статус: in_progress. Исполнитель: Codex.
Основание: LOW-05 аудита Gemini 4 Neon от 2026-11-28.

## Зона файлов

- `scripts/lib/ProjectCbrFx.psm1`
- `scripts/lib/ProjectPeriod.psm1`
- `scripts/project-viewer.ps1`
- `tests/project-cbr-fx-regressions.ps1`
- `tests/project-viewer-regressions.ps1`
- `docs/project-viewer.md`
- `docs/handoff.md`
- `tasks/T-154-viewer-json-types.md`

## Приёмка

- Версия схемы в истории, evidence, прогрессе и кэше курса принимается только как целое число 1.
- Кэш принимает положительный числовой курс и отклоняет логические значения, строки и массивы.
- Некорректные снимки обрабатываются по существующим правилам ошибок и восстановления.
