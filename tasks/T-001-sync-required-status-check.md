# T-001 — Синхронизировать manifest обязательного GitHub status check

**Статус:** merged; closeout записан с историческим пробелом review-доказательства
**PR:** #1 — https://github.com/g0ldenc0de2027/Development-folder-V.2/pull/1
**Ревизии:** PR head `890a52b73d98f686128ae02b94fee8b5f4e226bf`; base `0641901e825fdede9e1fdabf3fa83078ce5ab8ad`; CI merge-result `f04e83c16c82659d4b8ac2ee2df489a2a2dc6bc1`; merge commit `65b5ab35d46b81e5af1963c351d05ac5da0291dc`
**Review:** в GitHub PR record и доступных локальных материалах не найден независимый отчёт, привязанный к этому head SHA. Факт выполнения такого review не подтверждён; это исторический пробел доказательств, не утверждение о том, что review точно не было.
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
