# Handoff — T-008, 2026-11-19

- Current T-008 state: branch task/T-008 HEAD and origin/task/T-008 are e8653345c5a62382be02bf8957e459a4def28e6a; backup ref backup/2026-11-19-T-008-before-identity-repair retains ff6499005837312f8832b484d8fc51e52c08d628. The mixed reset preserved file content; 11 local paths (9 modified, 2 untracked), no new commit/push.
- Воспроизведена причина Git fatal: внешний TempRoot давал GIT_DIR 221 UTF-8 byte при 196 символах .NET. Gate использует короткий корень и fail-fast проверку 200-байтового бюджета до записи.
- Исторический full gate PASS был на pre-recovery candidate ff6499005837312f8832b484d8fc51e52c08d628 и не подтверждает текущие 11 путей. Read-only T-015 audit сейчас BLOCKED только из-за T-008 (11 путей) и T-015 (9); остальные 15 registered worktrees, включая main, CLEAN. T-015 targeted suites 31/31 и 25/25; его полный gate ещё не выполнен. Сначала завершить T-008, затем повторить audit.
- Live PR #8 read-only: OPEN/Draft, head e8653345c5a62382be02bf8957e459a4def28e6a, base f577dc70e58d75ab5fd61d0c2e712c27b590713a. Run #44402452200 SUCCESS на merge-result 66c80a08d0f4f8569efd0c6e944a9b0dc8ba3cc0 с точными родителями base/head. GitHub-native reviews: 0; независимое review этого head требуется до merge.

## Исторический bootstrap-снимок до слияния T-003 (не текущие статусы задач)

# Handoff

- V2 остаётся публичным по решению владельца; PR #2 / T-002 слита, локальная main чистая на c98a1922dee2dedeaed6eeb528d72098beb3a128. Полный PR/review/CI revision tuple находится в карточке tasks/T-002-reconcile-github-settings-and-closeout.md.
- Владелец выбрал no-App: владелец — корень доверия. У ruleset нет обязательных approvals и CODEOWNERS, поэтому review владельцем — организационный контроль, а не GitHub-enforced gate. PR может изменить собственный workflow/gate и пройти изменённую проверку; это остаточный риск, описанный в docs/github-workflow.md.
- PR #3 / T-003 остаётся draft. Copilot CHANGES REQUIRED на head bbd8abc: P2/P3 закрыты в code-fix commit 5c3eaf06dd5ee9a518659db015e4ffbc54b8a982. Его проверенная пара: base c98a1922dee2dedeaed6eeb528d72098beb3a128, hosted run 43622066954 SUCCESS, checkout/test merge-result 5fb052c8094ceb3f530b306d8ba164416411d63f с точными родителями base/head. GitHub Actions проверяет каждую последующую ревизию отдельно; актуальный статус смотреть в PR #3. GitHub-native review отсутствует; свежий независимый review последнего head требуется.
- В публичных документах нельзя публиковать email или local-part. email=null в публичном профиле не подтверждает приватность commit email. История не переписывается; адрес учётной записи перед следующим merge владелец проверяет отдельно. Claim detector — ограниченная эвристика, её покрытие определяется fixtures, а не произвольным смысловым анализом.
- T-003: локальная regression suite, полный quality gate и pre-push gate прошли на code-fix commit 5c3eaf0; hosted CI прошёл на его точной паре SHA. Каждая последующая PR-ревизия получает отдельный hosted gate. Независимый review последнего head остаётся открытым.
- После T-003 продолжить отдельные задачи no-App merge controls, Git identity/push-size controls и P0 scope/worktree guard; прикладную реализацию не начинать до READY в спецификации.
