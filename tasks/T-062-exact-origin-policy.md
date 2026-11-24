# T-062 — Согласовать адрес origin и хост GitHub

Статус — в работе. Источник — аудит V2, A09.

## Зона файлов

- `scripts/github/configure-local.ps1`
- `scripts/github/verify-settings.ps1`
- `tests/quality-gate-regressions.ps1`
- `tests/task-worktree-regressions.ps1`
- `tasks/T-062-exact-origin-policy.md`

## Приёмка

- Настройка принимает единственные fetch и push URL origin только в точном виде, который допускает pre-push.
- Сверка аккаунта и проверка настроек обращаются явно к github.com.
- Синтетический hook использует заглушку для закреплённого хоста. Варианты регистра и завершающий слеш отклоняются до проверки аккаунта.
- Проверки и точные ревизии ведутся в PR.
