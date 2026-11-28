# T-149 — Проверка JavaScript панели в GitHub CI

Статус: in_progress. Исполнитель: Codex.
Основание: часть GATE-01 аудита Gemini 4 Neon от 2026-11-28.

## Зона файлов

- `.github/workflows/quality-gate.yml`
- `tasks/T-149-viewer-js-syntax.md`

## Приёмка

- Hosted quality-gate проверяет синтаксис встроенного JavaScript без выполнения кода панели.
- Ошибка синтаксиса, отсутствие Node или неожиданный состав блока scripts останавливают job.
- Локальная команда pre-push сохраняет прежние требования.
