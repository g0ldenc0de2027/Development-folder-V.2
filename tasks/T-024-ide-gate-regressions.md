# T-024 — Регрессии обхода файлов и изоляции Git-индекса

Статус: merged. Источник: ретроспективное ревью PR #6.

Интеграция: [PR #23](https://github.com/g0ldenc0de2027/Development-folder-V.2/pull/23), squash `69e97a9c8eed66198d4c59f981b06f2a2d64afe7`.
CI после слияния: [run #44549731506](https://github.com/g0ldenc0de2027/Development-folder-V.2/actions/runs/44549731506), success на указанном squash-коммите.

## Зона файлов

- `tests/ide-cache-regressions.ps1`
- `tests/quality-gate-regressions.ps1`
- `tasks/T-024-ide-gate-regressions.md`

## Приёмка

Проверка исходника gate ловит замену перечислителя в PowerShell parse-скане. Фикстура проверяет служебные каталоги и видимость похожего имени. SHA-256 проверяет неизменность индекса до и после. Поведение не-ссылочных reparse points требует отдельного воспроизведения.
