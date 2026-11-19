# T-018 — Проверять identity новых Git-коммитов

Статус: in_progress. База: main 6dd65d9. Блокирует штатное обновление PR #13.

## Зона файлов

- .githooks/pre-push
- scripts/lib/GitIdentity.psm1
- scripts/verify-git-identity.ps1
- tests/git-identity-regressions.ps1
- tasks/T-018-published-identity.md

## Приёмка

- Опубликованный squash из защищённой main не блокирует обновление ветки.
- Новый коммит с неверной атрибуцией отклоняется. Локальная tracking-ссылка не подтверждает публикацию.
- Ошибки GitHub API, несовпадение URL и отсутствие опубликованного объекта локально блокируют push.
- Охват сканирования секретов не меняется.
