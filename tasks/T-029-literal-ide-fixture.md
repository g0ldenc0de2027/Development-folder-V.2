# T-029 — Исправить захват диагностики в тестах IDE-кэша

Статус: merged. Источник: независимое ревью PR #27, сценарий с квадратными скобками в TempRoot.

Интеграция: [PR #28](https://github.com/g0ldenc0de2027/Development-folder-V.2/pull/28), squash `60df54b137793e24bb4094d6f084657aa3474357`.

## Зона файлов

- `tests/ide-cache-regressions.ps1`
- `tasks/T-029-literal-ide-fixture.md`

- `tests/quality-gate-regressions.ps1`

- `scripts/quality-gate.ps1`
- `tests/task-scope-regressions.ps1`

## Приёмка

Временная фикстура со скобками в имени проходит все три сценария IDE-cache suite. Отказ на обычном CRLF-файле и отслеживаемом VS-кэше подтверждается кодом выхода и диагностикой дочернего PowerShell. Фикстура удаляется после прогона.
