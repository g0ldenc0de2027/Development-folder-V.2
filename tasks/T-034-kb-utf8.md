# T-034 — Единый UTF-8 вывод локальной БЗ

Статус: in_progress. Аудит Qoder A-001.

## Зона файлов

- `scripts/kb.ps1`
- `tests/kb-regressions.ps1`
- `docs/local-knowledge.md`
- `spec/local-knowledge.md`
- `tasks/T-034-kb-utf8.md`

## Приёмка

Успешный ответ CLI — JSON в UTF-8 без BOM с завершающим LF. Бюджет context учитывает LF. Точная граница проходит, превышение даёт KB_CONTEXT_LIMIT и пустой stdout. Контракт search/get сохраняется.
