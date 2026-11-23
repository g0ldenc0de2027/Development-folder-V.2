# T-036 — Отвязать актуальный handoff от исторического PR

Статус: merged. Аудиты ZCode V2Z-003 и Kimi L-1.

Интеграция: [PR #35](https://github.com/g0ldenc0de2027/Development-folder-V.2/pull/35), squash `f1a90f7e4fdaa6de23410f2e71f0d09872b3b85f`.
CI после слияния: [run #44743684957](https://github.com/g0ldenc0de2027/Development-folder-V.2/actions/runs/44743684957), success на указанном squash-коммите.

## Зона файлов

- `docs/handoff.md`
- `tests/quality-gate-regressions.ps1`
- `tasks/T-036-handoff-live-links.md`

## Приёмка

Актуальный handoff ведёт к live PR и Actions репозитория из политики. Номер исторического PR не обязателен. Проверки против закрепления изменчивых SHA и статусов сохранены. Прежние свидетельства остаются в исторической части.
