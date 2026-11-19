# Handoff — GitHub reliability and T-015, 2026-11-19

## Evidence snapshot before the documentation follow-up

- T-015 implementation commit `1c675cc61ba47b7280e3b05083ce66539bfbf4d2` was pushed to PR #11. At this snapshot PR #11 was OPEN/Draft, head `1c675cc61ba47b7280e3b05083ce66539bfbf4d2`, base `f577dc70e58d75ab5fd61d0c2e712c27b590713a`.
- Hosted `quality-gate` run [#44471405219](https://github.com/g0ldenc0de2027/Development-folder-V.2/actions/runs/44471405219) succeeded on event `pull_request`; checkout/test merge-result `a28d75c53172ac1bde86ed33de43ded53582d671` has exactly the stated base and head as parents.
- Local full gate and pre-push gate passed on the implementation: identity 31/31, worktree 25/25, KB 44/44, privacy 41 Markdown files plus regression source, hygiene 69 text files, actionlint and Gitleaks PASS. Stack build/dependency audit does not apply because no application stack is selected.
- Read-only `scripts/github/verify-settings.ps1 -RequireStatusCheck` returned `GITHUB_SETTINGS_AUDIT=PASS_WITH_RECORDED_LIMITS`; expected repository, main ruleset, Actions, Dependabot and secret-scanning settings matched. Generic GitHub secret patterns and validity checks remain disabled and are recorded limitations.
- The repo-wide inventory found 12 open Draft PRs (#5–#16), all based on `main@f577dc70…`; green checks do not mean these tasks were reviewed, accepted, or integrated. Process task PRs sequentially against the current base.

## Current acceptance rule

- PR #11 remains unmerged. No GitHub-native review was present at this snapshot. After this documentation/policy update, read the live PR for the final head/base and hosted check; obtain an independent read-only review naming that exact head. Do not merge until current-head review, hosted CI, scope acceptance and integration checks all pass.
- AGENTS.md now requires agent-owned per-run temp paths, `try/finally` cleanup and post-cleanup verification; it explicitly protects user data, inbox, backups and unowned artifacts from broad deletion.
- Evidence for commit 55970f4d7db0429a2c5d9c64c7f617965d0d5815: pre-push passed with 69 local text files; hosted quality-gate #44484559621 passed on merge-result 40dccdbe36672be9c7638a745ea846396e309f2c with 65 hosted text files. These counts describe separate runs. The earlier unpublished recovery checkpoint is preserved locally and is outside this evidence.
- For every action, confirm the target repository, branch, full SHA and current live remote state from the linked worktree. The bare admin repository is not a working tree. Never infer success from a stale run, an empty review decision, or a command wrapper that hides a nonzero child exit.

---

## Historical snapshot — T-015, 2026-11-17

- База task/T-015 — `ff48a0fd7a412a5112477d86dfe5ff3122709fb0`; существующий draft PR #11 до новых исправлений указывал на эту ревизию. Основной scoped-набор сохранён локальным commit `7a5ce92`; исправление regression harness ожидает отдельного commit.
- Инициализация linked-worktree Git config безопасно разделила bare admin и T-015; все 14 linked worktrees читают `git status`. Пять worktrees сохраняют прежние правки без потерь: T-009, T-012, T-013, T-014 и T-015.
- T-015: 22/22 регрессии, полный quality gate, Git identity verifier и `git diff --check` прошли на текущем рабочем содержимом. Первая попытка pre-push корректно заблокировала публикацию из-за бага обнаружения Git shell в regression harness; поиск исправлен, добавлена проверка вложенного `git.exe`.
- Полный gate повторён после обновления handoff и исправления harness; следующий шаг — зафиксировать только тест, карточку и handoff, затем выполнить обычный push в task/T-015. Первая публикация осталась заблокирована штатным hook, история не переписывалась и проверки не обходились.
- После публикации проверить hosted CI на точной ревизии и запросить свежее независимое read-only review нового head. PR не сливать до нового review и зелёного CI.
- Historical T-004/bootstrap notes below are preserved as historical records.
# Handoff — T-004, 2026-11-15

- T-003 слита PR #3 в main (squash commit 9f98b28046ca605577e5a829e02818335f66174c); task/T-004 объединяется с новой main.
- Повторная сверка: RULES 0.2.0, семь модулей, COVERAGE и schema 2 lock всего пакета; восстановлен утверждённый список языков.
- Общая БЗ — редактируемый канон, здесь точная закреплённая копия; путь подключения произвольный и локальный.
- Реализован файловый CLI; новые проверки охватывают весь пакет и optional/null marker. Актуальные test/CI evidence и точные SHA — PR #4.
- Перед merge нужны свежие independent review/CI и последовательная интеграция после T-003. Swarm, прикладная матрица, security-watch и валидатор переводов ещё не готовы; детали в rules/COVERAGE.md.

## Исторический bootstrap-снимок до слияния T-003 (не текущие статусы задач)

# Handoff

- V2 остаётся публичным по решению владельца; PR #2 / T-002 слита, локальная main чистая на c98a1922dee2dedeaed6eeb528d72098beb3a128. Полный PR/review/CI revision tuple находится в карточке tasks/T-002-reconcile-github-settings-and-closeout.md.
- Владелец выбрал no-App: владелец — корень доверия. У ruleset нет обязательных approvals и CODEOWNERS, поэтому review владельцем — организационный контроль, а не GitHub-enforced gate. PR может изменить собственный workflow/gate и пройти изменённую проверку; это остаточный риск, описанный в docs/github-workflow.md.
- PR #3 / T-003 остаётся draft. Copilot CHANGES REQUIRED на head bbd8abc: P2/P3 закрыты в code-fix commit 5c3eaf06dd5ee9a518659db015e4ffbc54b8a982. Его проверенная пара: base c98a1922dee2dedeaed6eeb528d72098beb3a128, hosted run 43622066954 SUCCESS, checkout/test merge-result 5fb052c8094ceb3f530b306d8ba164416411d63f с точными родителями base/head. GitHub Actions проверяет каждую последующую ревизию отдельно; актуальный статус смотреть в PR #3. GitHub-native review отсутствует; свежий независимый review последнего head требуется.
- В публичных документах нельзя публиковать email или local-part. email=null в публичном профиле не подтверждает приватность commit email. История не переписывается; адрес учётной записи перед следующим merge владелец проверяет отдельно. Claim detector — ограниченная эвристика, её покрытие определяется fixtures, а не произвольным смысловым анализом.
- T-003: локальная regression suite, полный quality gate и pre-push gate прошли на code-fix commit 5c3eaf0; hosted CI прошёл на его точной паре SHA. Каждая последующая PR-ревизия получает отдельный hosted gate. Независимый review последнего head остаётся открытым.
- После T-003 продолжить отдельные задачи no-App merge controls, Git identity/push-size controls и P0 scope/worktree guard; прикладную реализацию не начинать до READY в спецификации.
