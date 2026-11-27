# T-080 — Читать статус карточки в Markdown-списке

Статус: in_progress. Источник: PTR-002 и ревью T-039.

## Зона файлов

- `scripts/project-viewer.ps1`
- `tests/project-viewer-regressions.ps1`
- `tasks/T-080-viewer-list-status.md`

## Приёмка

Просмотрщик распознаёт статус в строке Markdown-списка. Обычные поля, статус без маркера списка и привязка доказательств сохраняют поведение.
