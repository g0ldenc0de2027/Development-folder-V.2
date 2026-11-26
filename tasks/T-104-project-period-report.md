# T-104 — История и отчёты за период

Статус: in_progress
Исполнитель: Codex

Основание — [утверждённый этап B](../spec/project-period-report.md). Ветка опирается на T-103. Перед публикацией сверить её с итоговым деревом PR #91.

## Зона файлов

- `spec/project-period-report.md`
- `spec/СОСТОЯНИЕ.md`
- `tasks/T-104-project-period-report.md`
- `scripts/lib/ProjectPeriod.psm1`
- `scripts/project-viewer.ps1`
- `scripts/project-viewer.html`
- `tests/project-viewer-regressions.ps1`
- `docs/project-viewer.md`

## Приёмка

- Выполнить сценарии из спецификации на двух проектах с одинаковыми ID задач.
- Сверить карточки, историю, фильтры, детализацию и экспорт в браузере.
- Прогнать регрессии просмотрщика и штатный quality-gate.
