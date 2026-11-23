# T-026 — Проверка источника файлов PowerShell-скана по AST

Статус: merged. Источник: дополнительное ревью PR #23.

Интеграция: [PR #25](https://github.com/g0ldenc0de2027/Development-folder-V.2/pull/25), squash `a865cba3670585ab2a8ca6d34cf09659da886be9`.
CI после слияния: [run #44561398850](https://github.com/g0ldenc0de2027/Development-folder-V.2/actions/runs/44561398850), success на указанном squash-коммите.

## Зона файлов

- `tests/quality-gate-regressions.ps1`
- `tasks/T-026-parse-scan-ast.md`

## Приёмка

Назначение списка PowerShell-файлов начинается с Get-ProjectFiles. Замена перечислителя в этом назначении отклоняется, даже если прежняя строка осталась в комментарии. Проверка структурная. Поведение перечисления покрывается IDE-фикстурой.
