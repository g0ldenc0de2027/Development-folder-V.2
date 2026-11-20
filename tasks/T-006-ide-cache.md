# T-006 — не блокировать проверки кэшем Visual Studio

Статус: merged · Исполнитель: Codex · 2026-11-15.

Интеграция: [PR #6](https://github.com/g0ldenc0de2027/Development-folder-V.2/pull/6), squash `bee6648c5f786629d514cc50d98a66a650418da0`.
Основание: локальный gate T-004 ошибочно проверял `knowledge/.vs/ProjectSettings.json`
и блокировался на CRLF, хотя это служебный кэш IDE, не исходник проекта.

## Зона файлов

- `.gitignore`
- `scripts/ide-cache.ps1`
- `scripts/quality-gate.ps1`
- `tests/quality-gate-regressions.ps1`
- `tests/ide-cache-regressions.ps1`
- `docs/development.md`
- `tasks/T-006-ide-cache.md`

## Приёмка

Приёмка: вложенный неотслеживаемый `.vs` с CRLF и некорректным PS1 не мешает
обычному gate; принудительно добавленный в Git `.vs` приводит к явному отказу;
неигнорируемый проблемный исходный файл по-прежнему блокирует проверку. Проверить
в изолированном синтетическом репозитории. Не считать это гарантией безопасности
всего содержимого игнорируемых папок.
