# T-137 — Видимый отказ файла истории активности

Статус: merged. Исполнитель: Codex.
Основание: BUG-05 аудита Gemini 4 Neon от 2026-11-28.

Слияние: [PR #125](https://github.com/g0ldenc0de2027/Development-folder-V.2/pull/125), squash-коммит `7013b20046e16d55dd138be2c1eb2b8feab73be5` в main.

## Зона файлов

- `scripts/project-viewer.ps1`
- `scripts/project-viewer.html`
- `tests/project-viewer-regressions.ps1`
- `docs/project-viewer.md`
- `tasks/T-137-history-source-status.md`

## Приёмка

- PTR-VIS-005: отказ файла истории при читаемом журнале даёт partial и видимую отметку.
- Подтверждённые приёмки остаются доступны. Метрики без покрытия обозначены как неполные.
- Ошибка агрегации возвращает недоступность истории без частичных чисел.
