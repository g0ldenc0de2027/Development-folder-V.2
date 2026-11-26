# T-103 — Панель хода разработки

Статус: in_progress
Исполнитель: Codex

Основание — [утверждённый первый выпуск](../spec/project-progress-panel.md).

## Зона файлов

- `spec/project-progress-panel.md`
- `spec/СОСТОЯНИЕ.md`
- `tasks/T-103-project-progress-panel.md`
- `scripts/project-viewer.ps1`
- `scripts/project-viewer.html`
- `tests/project-viewer-regressions.ps1`
- `docs/project-viewer.md`

## Приёмка

- Проверить пять требований PTR-VIS из спецификации на двух проектах с совпадающим ID задачи и разными состояниями.
- Повторить штатные HTTP-регрессии, включая восстановление проекта и очереди из T-102.
- Проверить в браузере переключение видов, клавиатуру, узкое окно, отказ и восстановление источника. Сверить размер снимка и время обновления.
