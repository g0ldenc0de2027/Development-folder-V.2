# T-084 — Ограничить ожидание Git при проверке атрибуции

Статус: in_progress.
Источник: V2-GIT-TIMEOUT-002 и V2-GIT-TIMEOUT-CONTRACT-001.

## Зона файлов

- `scripts/lib/GitIdentity.psm1`
- `scripts/verify-git-hook-context.ps1`
- `tests/git-identity-regressions.ps1`
- `tasks/T-084-git-identity-timeout.md`

## Приёмка

Штатные stdout, stderr и код выхода сохраняются. Таймаут завершения процесса и таймаут чтения вывода имеют разные коды и не запускают автоисправление identity. Закрытие ресурсов обязательно, остановка потомков выполняется в пределах возможностей Process.Kill.
