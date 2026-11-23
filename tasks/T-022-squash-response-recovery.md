# T-022 — Сверка состояния PR при неоднозначном ответе squash

Статус: merged. База: 07ed7bd8214e14c1bff7e4a2befbd53295ace636.

Интеграция: [PR #21](https://github.com/g0ldenc0de2027/Development-folder-V.2/pull/21), squash `3dea0fda3aa2cd68de47a9e91079220c25dc5d51`.
CI после слияния: [run #44527617702](https://github.com/g0ldenc0de2027/Development-folder-V.2/actions/runs/44527617702), success на указанном squash-коммите.

## Зона файлов

- `scripts/github/merge-reviewed-pr.ps1`
- `tasks/T-022-squash-response-recovery.md`

## Приёмка

Ошибки команды или GraphQL, повреждённый ответ и отсутствие подтверждения squash ведут к одному read-only запросу состояния PR. Скрипт отказывает без автоматического повтора мутации и без вывода email. Полностью подтверждённый результат завершается успешно. Проверить сценарии с подставной GitHub CLI без сетевых операций.
