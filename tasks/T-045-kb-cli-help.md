# T-045 — Дополнить справку локальной БЗ

Статус: in_progress. Критический аудит F18.

## Зона файлов

- `scripts/kb.ps1`
- `docs/local-knowledge.md`
- `tasks/T-045-kb-cli-help.md`

## Приёмка

Get-Help выдаёт справку без запуска операций БЗ. Руководство поясняет различие check и doctor, нулевой результат поиска, Compact и границы Limit/MaxBytes/MaxOutputBytes. Строка невыдаваемой ошибки удалена. Исполняемый контракт CLI сохраняется.
