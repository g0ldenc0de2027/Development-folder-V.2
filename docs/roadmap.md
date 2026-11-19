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
- [ ] Приоритет P0: автоматизировать создание worktrees и полный task lifecycle. Отдельный fail-closed scope guard по карточке задачи подготовлен в T-008; до merge его нельзя считать активным в main. FR-002/AC-007 требуют актуального review и CI на этой ветке.
- [ ] Сверять base SHA и live origin/main до commit/publish.
- [ ] Проверить реальные границы защиты GitHub Free.

- [x] T-003 merged: PR #3, squash commit 9f98b28046ca605577e5a829e02818335f66174c; independent Antigravity review approved exact head. Historical pre-merge snapshot follows: T-003 remains open draft PR #3. Code-fix verification tuple: head 5c3eaf06dd5ee9a518659db015e4ffbc54b8a982, base c98a1922dee2dedeaed6eeb528d72098beb3a128, hosted run 43622066954 SUCCESS, event/test merge-result 5fb052c8094ceb3f530b306d8ba164416411d63f with exact parents. Copilot findings from bbd8abc (P2 copular false negative, P3 stale CI wording) were fixed in 5c3eaf0. Local quality gate and push preflight passed. GitHub Actions validates every later PR revision separately; fresh independent review on the latest PR head remains required and no GitHub-native review is present.
- [ ] Implement remaining no-App merge safeguards: owner remains the trust root; manual review and gate-change residual risk are documented in docs/github-workflow.md; evaluate any additional local-only controls separately.
- [ ] Verify both account email safeguards before the next GitHub-generated merge.
- [ ] T-004 — add a fail-closed push-size policy. No per-file blob or aggregate push-size gate exists yet. Set lower project defaults against GitHub limits: [public pushes above 50 MB may skip push protection](https://docs.github.com/en/code-security/reference/secret-security/secret-scanning-scope), [single Git objects above 100 MB are blocked](https://docs.github.com/en/repositories/creating-and-managing-repositories/repository-limits), and [a push is capped at 2 GB](https://docs.github.com/en/get-started/using-git/troubleshooting-the-2-gb-push-limit). Test exact size metrics and multi-ref pushes before claiming coverage.
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
