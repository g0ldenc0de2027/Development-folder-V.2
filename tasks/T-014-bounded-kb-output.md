# T-014 — Ограничение объёма выдачи локальной БЗ

- **Статус:** in_progress
- **Ветка/worktree:** `task/T-014-bounded-kb-output` / `.worktrees/T-014`
- **База:** `f577dc70e58d75ab5fd61d0c2e712c27b590713a` (`origin/main`; сверена с live `origin/main` 2026-11-17)
- **Автор:** Codex, GPT-6
- **Основание:** прямое поручение владельца от 2026-11-17 провести полный аудит и улучшать локальную БЗ.

## Проблема

Воспроизведено на T-009: `search -Query local-first -Limit 1 -MaxBytes 512` завершился успешно и выдал 75 629 UTF-8 байт, включая тело записи 71 854 байта. `MaxBytes` документирован только для `context`; у `search/get` нет явного ограничения ответа. Это не нарушение прежнего контракта, а подтверждённый риск неконтролируемого размера ответа.

Дополнительно в ходе аудита локальной БЗ воспроизведён разрыв LKB-001: schema 2 lock только с `rules/RULES.md` и индекс без локальных ссылок проходил `check` с exit 0, хотя READY-контракт требует полный пакет из индекса, семи модулей и карты охвата. Тест `LKB-001 index-only policy package is refused` зафиксировал прохождение такого fixture до исправления.

## Решение

Добавить отдельный параметр `-MaxOutputBytes` для полных JSON-ответов `search` и `get`: default 131072 байта, диапазон 512–2097152. При превышении возвращать `KB_OUTPUT_LIMIT`, exit 1 и пустой stdout. Не урезать JSON/записи. Существующий `-MaxBytes` и код отказа `KB_CONTEXT_LIMIT` для `context` оставить без изменений. Текущие поля и полные тела записей при успешном ответе сохранить.

PowerShell принимает значения `Command` из `ValidateSet` без учёта регистра. Поэтому проверка бюджета обязана одинаково охватывать все принятые варианты написания команды; верхний регистр нельзя трактовать как обход.

Для уже принятого LKB-001 проверять в schema 2 lock точное множество девяти канонических путей RULES: индекс, модули 01–07 с фиксированными именами и `rules/COVERAGE.md`. Отсутствующие, заменённые, лишние и повторные пути отклонять как `KB_POLICY_LOCK`, даже если индекс перестал ссылаться на пакет; ссылку на незакреплённый файл — как `KB_POLICY_LINK`.

## Зона файлов

- `scripts/kb.ps1`
- `tests/kb-regressions.ps1`
- `spec/local-knowledge.md`
- `spec/СОСТОЯНИЕ.md`
- `specification-system/tz_state.md`
- `docs/local-knowledge.md`
- `docs/handoff.md`
- `tasks/T-014-bounded-kb-output.md`

## Приёмка

1. Спецификация определяет параметр, default/range, подсчёт UTF-8 байтов сериализованного JSON вместе с завершающей новой строкой, fail-closed поведение и отсутствие обрезания.
2. `search` и `get` не пишут частичный/полный JSON в stdout при превышении бюджета; stderr содержит только короткий стабильный код. Любые написания команд, принимаемые `ValidateSet` (включая `SEARCH` и `GET`), имеют тот же предел.
3. Regression cases покрывают Unicode byte-count (многобайтный текст), превышение бюджета обеими командами в нижнем и верхнем регистре, пустой stdout при отказе и успешную полную выдачу при достаточном бюджете.
4. Контракт `context -MaxBytes` и существующие проверки остаются прежними.
5. Локальные KB-регрессии и quality gate проходят на точном HEAD/рабочем diff; scope, handoff и `git diff --check` согласованы.
6. Fixtures моделируют полный девятифайловый пакет; сокращение lock до одного индекса, пропуск канонического модуля, изменение его байтов, отсутствие файла, незакреплённая ссылка и дубликат отклоняются ожидаемыми кодами.

## Ограничения

Лимит ограничивает stdout-ответ, но не обещает ограничить объём чтения/внутреннюю память до сериализации. Не менять схему каталога, статус admission знаний, поиск по shared KB или transport к AI-провайдерам.

## Проверка исходного среза (до case-variant follow-up)

- Полный gate выполнен на рабочем содержимом поверх committed HEAD `3f75090c6e236aca7ffb5533a83e7f7302e71f18` и базы `origin/main` `f577dc70e58d75ab5fd61d0c2e712c27b590713a`: KB-regressions — 52/52 PASS; PowerShell AST и `git diff --check` — PASS. Scoped commit содержит ровно это проверенное содержимое.
- `quality-gate.ps1 -BaseRef origin/main` — PASS: 6 PowerShell files parsed; privacy — 38 Markdown plus regression source; hygiene — 56 text files; Actionlint PASS; Gitleaks PASS (64 reachable commits, рабочее дерево и supplied push range).
- Application stack build/dependency audit — NOT COVERED, стек не выбран. Hosted CI и независимое review требуются на опубликованном SHA этой правки; результаты старого PR head не переносятся.

## Follow-up проверка регистра (2026-11-18)

- Внутренний read-only review точного PR head `7715450d0664eb9c64a3f0e5e42eb814f187ac37` обнаружил обход: `ValidateSet` принимает команды без учёта регистра, а `-cin` пропускал `SEARCH/GET` мимо лимита. Новые фикстуры воспроизвели дефект до исправления; после замены на `-in` регрессии прошли 52/52 (exit 0).
- Полный `pwsh -NoProfile -File scripts/quality-gate.ps1 -BaseRef origin/main` на текущем working diff поверх HEAD `7715450d0664eb9c64a3f0e5e42eb814f187ac37` и base `f577dc70e58d75ab5fd61d0c2e712c27b590713a`: **PASS, exit 0**; KB regressions 52/52, PowerShell/JSON parse PASS, privacy 38 Markdown + regression source, hygiene 56 text files, Actionlint PASS, Gitleaks PASS (65 commits, working tree и push range). `git diff --check`: **PASS, exit 0**.
- Hosted run `#44192782023` относится к прежнему head и fix не подтверждает. Перед merge нужны свежие CI и независимое review точного live head; стековая сборка/dependency audit не применяются к docs-only template без выбранного стека.
