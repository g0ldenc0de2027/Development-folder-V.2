# T-055 — Сверять источник обязательного check по манифесту

Статус: merged (PR #54, squash b6c28cf1c00be0fa0b1d1a7c0c351618ff3fc711). Источник: аудит ZCode V2Z-007, дублирование integration ID.

## Зона файлов

- `scripts/github/check-squash-preflight.ps1`
- `tasks/T-055-preflight-check-source.md`

## Приёмка

Preflight использует integrationId из манифеста main ruleset и отклоняет отсутствующую, неверную или нестрогую политику. Поле strict должно быть JSON boolean true. Строковые и числовые значения отклоняются. Живой ruleset должен требовать strict quality-gate от указанного App. Проверки PR, CI и допуска сохраняются.
Ответ GitHub должен содержать целочисленный integration_id. Неполные параметры правила не проходят проверку и приводят к штатному сообщению об отсутствии обязательного check.
