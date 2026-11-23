# T-035 — Изолировать Git-окружение регрессий merge-result

Статус: merged. Аудит ZCode, V2Z-005.

Интеграция: [PR #34](https://github.com/g0ldenc0de2027/Development-folder-V.2/pull/34), squash `5870385d0ffe131500538f8fd30210dbe560c211`.
CI после слияния: [run #44717430713](https://github.com/g0ldenc0de2027/Development-folder-V.2/actions/runs/44717430713), success на указанном squash-коммите.

## Зона файлов

- `tests/pr-merge-result-regressions.ps1`
- `tasks/T-035-isolate-merge-fixtures.md`

## Приёмка

Git-фикстура и дочерний валидатор получают только явно заданное Git-окружение. Исходные переменные процесса восстанавливаются в finally. Все сценарии проходят в отдельном временном каталоге.
