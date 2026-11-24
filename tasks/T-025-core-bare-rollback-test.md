# T-025 — Регрессия отказа отката core.bare

Статус: merged. Источник: независимое ревью PR #22.

Интеграция: [PR #24](https://github.com/g0ldenc0de2027/Development-folder-V.2/pull/24), squash `ab52f94fa148d6df4786cde36a3643941054ecc7`.
CI после слияния: [run #44553940409](https://github.com/g0ldenc0de2027/Development-folder-V.2/actions/runs/44553940409), success на указанном squash-коммите.

## Зона файлов

- `tests/git-identity-regressions.ps1`
- `tasks/T-025-core-bare-rollback-test.md`

## Приёмка

В синтетическом bare-репозитории заблокировать общий config и поставить блокировку config.worktree после записи временного core.bare. Проверить отдельную ошибку отказа отката, неизменность общего config и сохранность временного значения. После освобождения блокировок проверить повторную миграцию.
