# T-061 — Проверять все разрешения Actions из аудита A07

Статус — в работе. Источник — аудит V2, A07.

## Зона файлов

- `config/github/actions-policy.json`
- `scripts/github/verify-settings.ps1`
- `tests/quality-gate-regressions.ps1`
- `tasks/T-061-verify-actions-policy.md`

## Приёмка

- Read-only проверка сравнивает enabled, github_owned_allowed и verified_allowed с манифестом.
- Отсутствующее поле, неверный тип и расхождение завершают проверку отказом.
- Манифест закрепляет текущую политику. GitHub settings и правила merge эта задача не меняет.
- Точный head, аудит Windows и CI фиксируются в PR.
