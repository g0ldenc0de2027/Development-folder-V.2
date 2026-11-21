# T-036 — Отвязать актуальный handoff от исторического PR

Статус: in_progress. Аудиты ZCode V2Z-003 и Kimi L-1.

## Зона файлов

- `docs/handoff.md`
- `tests/quality-gate-regressions.ps1`
- `tasks/T-036-handoff-live-links.md`

## Приёмка

Актуальный handoff ведёт к live PR и Actions репозитория из политики. Номер исторического PR не обязателен. Проверки против закрепления изменчивых SHA и статусов сохранены. Прежние свидетельства остаются в исторической части.
