# T-132 — Уточнить единицу учёта в отчёте за период

Статус: in_progress.
Исполнитель: Codex.
Основание: PTR-VIS-005 и T-126.

## Зона файлов

- `docs/project-viewer.md`
- `spec/project-period-report.md`
- `tasks/T-132-period-result-docs.md`

## Приёмка

- Спецификация различает результаты с itemId и прежние события без itemId.
- Руководство объясняет эффект отзыва одного из двух результатов.
- Сверено с ProjectPeriod.psm1 и выводом панели. На базе 57cab22 прошла действующая проверка tests/project-period-result-regressions.ps1.
