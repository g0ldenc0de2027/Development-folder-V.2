# T-054 — Поддержать буквальные пути к checkout

Статус: in_progress. Источник: аудит ZCode V2Z-011.

## Зона файлов

- `scripts/github/configure-local.ps1`
- `scripts/github/verify-settings.ps1`
- `scripts/verify-runtime.ps1`
- `scripts/verify-task-scope.ps1`
- `tests/task-scope-regressions.ps1`
- `tests/ide-cache-regressions.ps1`
- `tests/pr-merge-result-regressions.ps1`
- `tasks/T-054-literal-checkout-path.md`

## Приёмка

Определение корня checkout трактует путь буквально. Штатные сценарии проверки области задачи выполняются в изолированном checkout с квадратными скобками. Параметры и ограничения runtime, GitHub и scope сохраняются.

Остаток A15 проверяется отдельным checkout с квадратными скобками. В нём запускаются регрессии IDE-кэша и PR merge-result. Итоговые head/base, результаты и проверка очистки фиксируются в PR #53.
