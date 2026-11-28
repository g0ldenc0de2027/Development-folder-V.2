# T-136 — Граница снимка на графике остатка

Статус: in_progress. Исполнитель: Codex.
Основание: BUG-06 аудита Gemini 4 Neon от 2026-11-28.

## Зона файлов

- `scripts/lib/ProjectRemainingWork.psm1`
- `tests/project-remaining-work-regressions.ps1`
- `tasks/T-136-remaining-work-cutoff.md`

## Приёмка

- PRG-008: график учитывает события ровно на дату снимка при подтверждённом покрытии.
- PRG-008: событие в локальную полночь входит в новый день.
