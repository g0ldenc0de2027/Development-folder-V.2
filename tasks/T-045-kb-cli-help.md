# T-045 — Дополнить справку локальной БЗ

Статус: merged (PR #44, squash 6a104c7a3ac6b33dc949196109d08a0b9ad93a99). Критический аудит F18.

## Зона файлов

- `scripts/kb.ps1`
- `docs/local-knowledge.md`
- `tasks/T-045-kb-cli-help.md`

## Приёмка

Get-Help выдаёт справку без запуска операций БЗ. Руководство поясняет различие check и doctor, нулевой результат поиска, Compact и границы Limit/MaxBytes/MaxOutputBytes. Строка невыдаваемой ошибки удалена. Исполняемый контракт CLI сохраняется.
