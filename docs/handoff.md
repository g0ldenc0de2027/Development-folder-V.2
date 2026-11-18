# Handoff — worktree isolation and attribution, T-015, 2026-11-18

- Root cause: no mandatory global worktree audit; old hooks checked current commit/push identity, not all registered trees, untracked files, or ignored .vs; bare admin root is not a worktree.
- Fix: mandatory all-worktree admission audit, repeat fail-closed checks in pre-commit and pre-push, staged-only current-task write set, explicit interruption handoff, and regressions. Nested Git calls isolate hook-provided repository variables; no automatic cleanup or recovery action.
- T-013 raw snapshot: archive Development-Folder-V2_T-013-source-snapshot-2026-11-18_91bb56d5.zip; archive SHA-256 734f27b8027e4a0aaa2f1aeca5868ba242249766fca26e975fcb718c60602d99; Format 1 manifest SHA-256 91bb56d5de1822cfb64a9fad0270c83d41d5b00c110e6740d2804c9e96c2d4f3.
- Backup ref backup/2026-11-18-T013-source-base pins original HEAD 88342060af7c6c18a163d3b6fa6727ab5c17fd7e; source worktree is clean on the same branch and HEAD; commit history is unchanged.
- T-016 status correction is saved locally as commit e1a4aaea9ae837977f7a6e1c834e0fa2b220e475; it is not pushed, so PR #15 CI/review evidence predates that commit and must be refreshed before merge.
- Validation on this content: quality-gate PASS; Git identity 22/22, worktree 12/12, KB 44/44, privacy/hygiene, actionlint and Gitleaks PASS. Application stack build/dependency audit is NOT COVERED because this template has no selected stack.
- Next: create the scoped T-015 commit, then refresh PR/CI/review evidence on exact current SHAs. Local hooks reduce accidental recurrence but cannot prevent intentional bypass or concurrent changes after audit.

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
