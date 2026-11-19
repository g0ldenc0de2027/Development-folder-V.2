# T-028 — Включить каталоги ProjFS в проверку исходников

Статус: in_progress. Источник: воспроизведение после PR #6.

## Зона файлов

- `scripts/ide-cache.ps1`
- `tests/ide-cache-regressions.ps1`
- `tasks/T-028-projfs-source-scan.md`

## Приёмка

Реальный каталог ProjFS с тегом 0x9000001c перечисляет вложенный PowerShell-файл. Junction и неизвестные reparse-теги исключаются. IDE-кэш и остальные действующие исключения сохраняются.
