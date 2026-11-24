# План Development Folder V2

## Этап 0 — чистый GitHub foundation
- [x] Создать новый репозиторий без переноса истории и файлов V1.
- [x] Активировать ruleset main и read-only Actions permissions.
- [x] Включить GitHub secret scanning/push protection и Dependabot alerts/updates; dependency graph прямо проверяется через SBOM endpoint (SPDX-2.3), а не inferred из Dependabot.
- [x] Первый hosted CI прошёл; exact `quality-gate` от GitHub Actions App `15368` установлен как strict required status check и подтверждён live verifier.
- [x] Проверен полный initial diff; root commit `0641901e825fdede9e1fdabf3fa83078ce5ab8ad` опубликован в подтверждённо пустой remote.

## Этап 1 — specification readiness
- [ ] Согласовать scope, матрицу ОС, стековые профили, локальную базу знаний, прогресс/ETA.
- [ ] Исследовать ecosystem profiles по актуальным официальным источникам.
- [ ] Обновить ТЗ, критерии приемки и readiness до READY.

## Этап 2 — надежное task lifecycle
- [ ] Приоритет P0: автоматизировать создание worktrees и полный task lifecycle. FR-002/AC-007 сохраняют требования к полному циклу задачи.
- [x] Локальная проверка worktree и файловой зоны по карточке задачи действует в pre-push после [PR #8](https://github.com/g0ldenc0de2027/Development-folder-V.2/pull/8).
- [ ] Сверять base SHA и live origin/main до commit/publish.
- [ ] Проверить реальные границы защиты GitHub Free.

- [x] T-003 merged. [Карточка T-003](../tasks/T-003-closeout-and-email-privacy-plan.md) содержит историю ревью и CI.
- [ ] Implement remaining no-App merge safeguards: owner remains the trust root; manual review and gate-change residual risk are documented in docs/github-workflow.md; evaluate any additional local-only controls separately.
- [ ] Verify both account email safeguards before the next GitHub-generated merge.
- [ ] Add a fail-closed push-size policy. No per-file blob or aggregate push-size gate exists yet. Set lower project defaults against GitHub limits: [push protection skips public-repository pushes above 50 MB](https://docs.github.com/en/code-security/reference/secret-security/secret-scanning-scope), [single Git objects above 100 MB are blocked](https://docs.github.com/en/repositories/creating-and-managing-repositories/repository-limits), and [a push is capped at 2 GiB](https://docs.github.com/en/get-started/using-git/troubleshooting-the-2-gb-push-limit). Test exact size metrics and multi-ref pushes before claiming coverage.
## Этап 3 — reusable project profiles
- [ ] Сервер/web/API, сайты и dashboards.
- [ ] Mobile и desktop.
- [ ] Data engineering, analytics, ML/AI.
- [ ] Databases, queues, cache, search.
- [ ] CLI, libraries, integrations, infrastructure.
- [ ] Для каждого профиля определить поддерживаемые версии, lockfiles, tests, security, build, SBOM и deployment.

## Этап 4 — прогресс и база знаний
- [ ] Измеримый denominator требований и приемки.
- [ ] Фактическая скорость, прогноз сроков и неопределенность.
- [ ] Безопасное подключение общей базы знаний с provenance, ACL и явным отказом при недоступности.
- [ ] Dashboard состояния эталона и создаваемых проектов.
