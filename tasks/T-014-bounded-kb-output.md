# T-014 — Ограничение объёма выдачи локальной БЗ

- **Статус:** in_progress
- **Ветка/worktree:** `task/T-014-bounded-kb-output` / `.worktrees/T-014`
- **База:** `f577dc70e58d75ab5fd61d0c2e712c27b590713a` (`origin/main`; сверена с live `origin/main` 2026-11-17)
- **Автор:** Codex, GPT-6
- **Основание:** прямое поручение владельца от 2026-11-17 провести полный аудит и улучшать локальную БЗ.

## Проблема

Воспроизведено на T-009: `search -Query local-first -Limit 1 -MaxBytes 512` завершился успешно и выдал 75 629 UTF-8 байт, включая тело записи 71 854 байта. `MaxBytes` документирован только для `context`; у `search/get` нет явного ограничения ответа. Это не нарушение прежнего контракта, а подтверждённый риск неконтролируемого размера ответа.

## Решение

Добавить отдельный параметр `-MaxOutputBytes` для полных JSON-ответов `search` и `get`: default 131072 байта, диапазон 512–2097152. При превышении возвращать `KB_OUTPUT_LIMIT`, exit 1 и пустой stdout. Не урезать JSON/записи. Существующий `-MaxBytes` и код отказа `KB_CONTEXT_LIMIT` для `context` оставить без изменений. Текущие поля и полные тела записей при успешном ответе сохранить.

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
2. `search` и `get` не пишут частичный/полный JSON в stdout при превышении бюджета; stderr содержит только короткий стабильный код.
3. Regression cases покрывают Unicode byte-count (многобайтный текст), превышение бюджета обеими командами, пустой stdout при отказе и успешную полную выдачу при достаточном бюджете.
4. Контракт `context -MaxBytes` и существующие проверки остаются прежними.
5. Локальные KB-регрессии и quality gate проходят на точном HEAD/рабочем diff; scope, handoff и `git diff --check` согласованы.

## Ограничения

Лимит ограничивает stdout-ответ, но не обещает ограничить объём чтения/внутреннюю память до сериализации. Не менять схему каталога, статус admission знаний, поиск по shared KB или transport к AI-провайдерам.

## Текущая проверка

- На рабочем diff от base `f577dc70e58d75ab5fd61d0c2e712c27b590713a`: KB-regressions — 48/48 PASS; полный quality gate — PASS; `git diff --check` — PASS.
- Gate охватил privacy (38 Markdown + test source), hygiene (56 text files), Actionlint и Gitleaks; application stack build/dependency audit — NOT APPLICABLE, стек не выбран.
- Эти результаты относятся к рабочему содержимому, не к commit SHA. Commit, push, hosted CI и независимое review ещё нужны.
