# T-034 — Единый UTF-8 вывод локальной БЗ

Статус: merged. Аудит Qoder A-001.

Интеграция: [PR #33](https://github.com/g0ldenc0de2027/Development-folder-V.2/pull/33), squash `3780967973dd12719e4febf86ec70d20c3efb25a`.

## Зона файлов

- `scripts/kb.ps1`
- `tests/kb-regressions.ps1`
- `docs/local-knowledge.md`
- `spec/local-knowledge.md`
- `tasks/T-034-kb-utf8.md`

## Приёмка

Успешный ответ CLI — JSON в UTF-8 без BOM с завершающим LF. Бюджет context учитывает LF. Точная граница проходит, превышение даёт KB_CONTEXT_LIMIT и пустой stdout. Контракт search/get сохраняется.
