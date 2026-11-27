# T-100 — Пилот единого трекера проектов

Статус: draft
Исполнитель: Codex

## Зона файлов

- `spec/project-tracker-pilot.md`
- `spec/СОСТОЯНИЕ.md`
- `tasks/T-101-project-tracker-readonly.md`
- `tasks/T-100-project-tracker-pilot.md`
- `tests/quality-gate-regressions.ps1`
- `tests/git-identity-regressions.ps1`
- `tests/ide-cache-regressions.ps1`

Первый push остановился при чтении пути общего каталога Git с кириллицей. В зоне T-100 дополнительно исправлено декодирование вывода Git в этой проверке TempRoot.

## Приёмка

Зафиксированы источники данных, ключи связи, поведение при сбоях и проверяемые критерии пилота. Конкретную пару проектной задачи и задания подтверждают до прогона. Независимое ревью и hosted quality-gate прошли на `0229d3b7f72b493826c58460759e015cd6b2b35d`. Допуск владельца ограничен пилотом в режиме чтения. Реализация выделена в [T-101](T-101-project-tracker-readonly.md).
