# T-021 — Команда squash с проверкой допуска

Статус: merged. База: 6b32887.

Интеграция: [PR #20](https://github.com/g0ldenc0de2027/Development-folder-V.2/pull/20), squash `07ed7bd8214e14c1bff7e4a2befbd53295ace636`.
CI после слияния: [run #44518815941](https://github.com/g0ldenc0de2027/Development-folder-V.2/actions/runs/44518815941), success на указанном squash-коммите.

## Зона файлов

- `scripts/github/merge-reviewed-pr.ps1`
- `tasks/T-021-squash-command.md`

## Приёмка

По умолчанию выполняется только preflight. Запись требует Execute и AcceptedHeadSha, совпадающего с проверенной ревизией. Перед использованием проверить независимое ревью и получить решение владельца по точному diff. Команда повторно проверяет head и base, отправляет expectedHeadOid и явный noreply. При неопределённом результате сверить статус PR перед повтором. Синхронизация локальной main и проверка post-merge CI выполняются отдельно.
