# T-134 — Чтение журнала решений с UTF-8 BOM

Статус: in_progress.
Исполнитель: Codex.
Основание: аудит Gemini 4 Neon от 2026-11-28, BUG-08.

## Зона файлов

- `scripts/lib/ProjectDecisionJournal.psm1`
- `tests/project-decision-journal-regressions.ps1`
- `tasks/T-134-decision-journal-bom.md`

## Приёмка

- PRG-003: один начальный UTF-8 BOM не мешает чтению корректного журнала.
- Идентичный JSON без BOM читается как прежде. Строгая UTF-8 и проверка JSON сохраняются.
