# T-057 — Поведенческие регрессии политики pre-push

Статус: in_progress.

## Зона файлов

- `tasks/T-057-pre-push-regressions.md`
- `tests/git-identity-regressions.ps1`

## Приёмка

F09: настоящий shell-хук в синтетическом Git-репозитории возвращает ожидаемые ошибки для detached HEAD, неверного slug, удаления ref и non-fast-forward. Проверки PowerShell изолированы существующим shim. Снимок refs локального тестового remote сохраняется. Набор Git-identity завершает 32 сценария.
