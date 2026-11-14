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
- [ ] Приоритет P0: автоматизировать создание изолированных worktrees и fail-closed проверку scope до push/PR; FR-002 и AC-007 пока не выполнены.
- [ ] Сверять base SHA и live origin/main до commit/publish.
- [ ] Проверить реальные границы защиты GitHub Free.

- [ ] T-003 remains open draft PR #3. Copilot and Antigravity both reviewed head b272622eb93d1881960a164671fcb30836e99b6f: Copilot APPROVE (metadata/docs/hosted CI; no targeted scanner probes), Antigravity CHANGES REQUIRED (reproduced privacy-claim and path/email-scanner gaps). Codex added adversarial fixtures and fixes; targeted suite and full quality gate pass locally (QUALITY-GATE=PASS against origin/main). Re-run gate after publishing the final SHA. The reviews and run #43614751907 are stale after the next commit; obtain fresh independent reports and hosted CI for the final exact head/base pair.
- [ ] Implement remaining no-App merge safeguards: owner remains the trust root; manual review and gate-change residual risk are documented in docs/github-workflow.md; evaluate any additional local-only controls separately.
- [ ] Verify both account email safeguards before the next GitHub-generated merge.
- [ ] Define total pushed-object limit separately from the existing per-file staged-blob limit.
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
