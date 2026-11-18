# Handoff — T-014, 2026-11-18

- T-014 implements bounded JSON stdout for local KB `search/get` through `-MaxOutputBytes` (131072 default, 512–2097152 range); oversized output fails closed as `KB_OUTPUT_LIMIT` with no stdout or truncation.
- The complete response is serialized to UTF-8 bytes before writing; `context -MaxBytes` retains its prior contract. The output limit does not cap corpus reading or serialization memory.
- Read-Bytes sizes its capped read buffer from the opened file length instead of always allocating 256 KiB. On 1,000 synthetic 1-KiB records, calculated temporary buffer allocations dropped from about 250 MiB to 0.98 MiB; one local run was 16.1% faster and reduced sampled private peak from 82.9 to 75.1 MiB. Parsed JSON values matched. This is an allocation optimization, not an aggregate memory guarantee.
- T-014 also closes a verified LKB-001 gap: `check` now requires the exact nine canonical RULES package paths; an index-only, incomplete, substituted, extra, duplicate, changed or unpinned package is rejected.
- LKB-009 remains the only new product slice; LKB-001 is a corrective completion of an existing requirement. The overall project remains `DRAFT / NOT READY`.
- Historical T-014 evidence before the read-buffer optimization: the uppercase SEARCH/GET bypass was fixed and a full gate passed on the earlier diff at HEAD 7715450d0664eb9c64a3f0e5e42eb814f187ac37 with 52 KB regressions. Hosted run #44192782023 covers only its then-current earlier PR head.
- The read-buffer allocation optimization is committed as 440a792; full local quality gate passed on that exact commit. Use live PR #12 for the current head/base/hosted-CI/review tuple; run #44192782023 is historical and does not validate later commits.
- Hosted run `#44192782023` is historical and applies only to the pre-follow-up head. Use live PR #12 for the current head, CI and review status; merge only after its gate and fresh independent review pass on the exact head. Application stack build/dependency audit is not covered because the template has no selected stack.

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
