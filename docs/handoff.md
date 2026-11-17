# Handoff — attribution recovery T-016, 2026-11-17

- T-013 остаётся DRAFT / NOT READY; agent orchestrator/adapters не реализованы. Draft spec/roadmap 0.18.2, research 2.9.4.
- Исходная T-013 ветка сохранена без изменений: HEAD 88342060af7c6c18a163d3b6fa6727ab5c17fd7e, два fixture-authored commits и семь modified paths. Историческая атрибуция UNKNOWN; exact input manifest 704 bytes / 39fc2f2f042d15e546b778cff626ab8e60d1eaf0adf3383b80868fb64e9cc37f. В T-016 семь файлов побайтно скопированы от origin/main f577dc70e58d75ab5fd61d0c2e712c27b590713a без переноса старых commit objects.
- T-016 добавляет в DRAFT FR-AOR-006 версионированную Unicode 18.0.0 display policy; implementation remains blocked. Review findings про assignment, account-memory digest, COM¹/LPT¹ и M5 уже покрыты текстом; Unicode gap закрывается формальным правилом. Прежние review snapshots не относятся к T-016.
- PR #10/T-011: OPEN/DRAFT, head 2298597c76dddf3deb9d0b11ca9b9f758cea50b5, hosted run #43866666822 SUCCESS. PR #11/#12/#13/#14: OPEN/DRAFT, hosted quality-gate SUCCESS на head, перечисленных в актуальных PR; merge не выполнялся.
- T-016 recovery опубликован в [draft PR #15](https://github.com/g0ldenc0de2027/Development-folder-V.2/pull/15). Первый hosted run `#44173816019` прошёл на head `a6e458e6972aeda409a9520c6bc0fd2d47d4f7d5` и merge-result `571d79398c150fd8d46dafd257f56fbe571f7ca4` с точными родителями; актуальные head и CI после статусного обновления смотреть в PR. Свежее независимое review ожидается; исходную T-013 копию сохранять без изменений.

## Исторический bootstrap-снимок до слияния T-003 (не текущие статусы задач)

# Handoff

- V2 остаётся публичным по решению владельца; PR #2 / T-002 слита, локальная main чистая на c98a1922dee2dedeaed6eeb528d72098beb3a128. Полный PR/review/CI revision tuple находится в карточке tasks/T-002-reconcile-github-settings-and-closeout.md.
- Владелец выбрал no-App: владелец — корень доверия. У ruleset нет обязательных approvals и CODEOWNERS, поэтому review владельцем — организационный контроль, а не GitHub-enforced gate. PR может изменить собственный workflow/gate и пройти изменённую проверку; это остаточный риск, описанный в docs/github-workflow.md.
- PR #3 / T-003 остаётся draft. Copilot CHANGES REQUIRED на head bbd8abc: P2/P3 закрыты в code-fix commit 5c3eaf06dd5ee9a518659db015e4ffbc54b8a982. Его проверенная пара: base c98a1922dee2dedeaed6eeb528d72098beb3a128, hosted run 43622066954 SUCCESS, checkout/test merge-result 5fb052c8094ceb3f530b306d8ba164416411d63f с точными родителями base/head. GitHub Actions проверяет каждую последующую ревизию отдельно; актуальный статус смотреть в PR #3. GitHub-native review отсутствует; свежий независимый review последнего head требуется.
- В публичных документах нельзя публиковать email или local-part. email=null в публичном профиле не подтверждает приватность commit email. История не переписывается; адрес учётной записи перед следующим merge владелец проверяет отдельно. Claim detector — ограниченная эвристика, её покрытие определяется fixtures, а не произвольным смысловым анализом.
- T-003: локальная regression suite, полный quality gate и pre-push gate прошли на code-fix commit 5c3eaf0; hosted CI прошёл на его точной паре SHA. Каждая последующая PR-ревизия получает отдельный hosted gate. Независимый review последнего head остаётся открытым.
- После T-003 продолжить отдельные задачи no-App merge controls, Git identity/push-size controls и P0 scope/worktree guard; прикладную реализацию не начинать до READY в спецификации.
