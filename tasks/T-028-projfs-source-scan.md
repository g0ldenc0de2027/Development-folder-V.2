# T-028 — Включить каталоги ProjFS в проверку исходников

Статус: merged. Источник: воспроизведение после PR #6.

Интеграция: [PR #27](https://github.com/g0ldenc0de2027/Development-folder-V.2/pull/27), squash `ab80160fc626fb863555c2a4c369e77355a4d0bc`.

## Зона файлов

- `scripts/ide-cache.ps1`
- `tests/ide-cache-regressions.ps1`
- `tasks/T-028-projfs-source-scan.md`

## Приёмка

Реальный каталог ProjFS с тегом 0x9000001c перечисляет вложенный PowerShell-файл. Junction и неизвестные reparse-теги исключаются. IDE-кэш и остальные действующие исключения сохраняются.
