# T-029 — Исправить захват диагностики в тестах IDE-кэша

Статус: in_progress. Источник: независимое ревью PR #27, сценарий с квадратными скобками в TempRoot.

## Зона файлов

- `tests/ide-cache-regressions.ps1`
- `tasks/T-029-literal-ide-fixture.md`

- `tests/quality-gate-regressions.ps1`

- `scripts/quality-gate.ps1`
- `tests/task-scope-regressions.ps1`

## Приёмка

Временная фикстура со скобками в имени проходит все три сценария IDE-cache suite. Отказ на обычном CRLF-файле и отслеживаемом VS-кэше подтверждается кодом выхода и диагностикой дочернего PowerShell. Фикстура удаляется после прогона.
