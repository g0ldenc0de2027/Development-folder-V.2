# T-055 — Сверять источник обязательного check по манифесту

Статус: in_progress. Источник: аудит ZCode V2Z-007, дублирование integration ID.

## Зона файлов

- `scripts/github/check-squash-preflight.ps1`
- `tasks/T-055-preflight-check-source.md`

## Приёмка

Preflight использует integrationId из манифеста main ruleset и отклоняет отсутствующую, неверную или нестрогую политику. Живой ruleset должен требовать strict quality-gate от указанного App. Проверки PR, CI и допуска сохраняются.
