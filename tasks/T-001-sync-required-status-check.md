# T-001 — Синхронизировать manifest обязательного GitHub status check

**Статус:** ready for review
**Тип:** maintenance / GitHub configuration documentation
**Основание:** initial root commit `0641901e825fdede9e1fdabf3fa83078ce5ab8ad` прошёл hosted `quality-gate`; live ruleset `27253655` уже требует `quality-gate` от GitHub Actions App `15368` с strict актуальностью.

## Цель

Привести декларативный конфиг, инструкции и handoff V2 в соответствие с фактически включённым GitHub ruleset после первого успешного hosted CI.

## Зона файлов

- `config/github/main-ruleset.json`
- `README.md`
- `docs/development.md`
- `docs/github-research.md`
- `docs/github-workflow.md`
- `docs/handoff.md`
- `docs/roadmap.md`
- `tasks/README.md`
- `tasks/T-001-sync-required-status-check.md`
- `tests/quality-gate-regressions.ps1`
- `scripts/quality-gate.ps1`

## Критерии приёмки

- Manifest указывает `state: enforced`, `context: quality-gate`, `strict: true`, `integrationId: 15368`.
- README, workflow, development guide, research notes, handoff и этап 0 roadmap согласованы с тем, что exact check уже настроен; нет устаревших статусов.
- Live verifier с `-RequireStatusCheck` подтверждает live ruleset и manifest.
- Regression guard требует именно `enforced` и ожидаемый integration ID.
- Quality gate и regression scan перечисляют файлы относительно root worktree, не теряют покрытие при расположении checkout в `.worktrees/T-NNN`, и fail closed при нулевом охвате.
- Regression использует synthetic path fixture: файл в worktree-root включается, nested .worktrees исключается; production gate связан с тем же относительным path filter.
- Полный локальный quality gate проходит; hosted CI зелёный на точном PR merge-result до merge.

## Вне объёма

- Изменение live ruleset: он уже настроен и проверен; задача только синхронизирует репозиторный manifest и документы.
- Реализация прикладной функциональности или автоматизации task scope/worktree.
