# Handoff — T-014, 2026-11-18

- T-014 остаётся `in_progress`; branch `task/T-014-bounded-kb-output`; проверенный diff содержит только шесть путей своей зоны поверх parent HEAD `4860a453b241a1c7dd135e03bcadc401a5253484` и base `origin/main` `f577dc70e58d75ab5fd61d0c2e712c27b590713a`.
- Ограниченный JSON stdout, точный девятифайловый RULES lock и read-buffer optimization прошли прежние проверки; их исторические SHA/run подробно сохранены в карточке T-014.
- LKB-003 hard-link alias fix covers catalog, record bodies and `.etalon.json`; `fsutil` is used through 24 records, same-handle API above that; known local Windows filesystems only. Pinned rules remain SHA-256 locked; same-user filesystem races are not eliminated.
- Final local full gate on this six-file diff over parent HEAD `4860a453b241a1c7dd135e03bcadc401a5253484`: PASS, 57/57 KB regressions; parse, privacy/hygiene, Actionlint, Gitleaks and `git diff --check` passed. Hosted CI and independent review remain pending.
- Six-run local KB-check median on the small corpus: 861.5 ms baseline vs 965.4 ms adaptive mode (about +12%); always-compiled P/Invoke was rejected at about +46%, while 25-record regression covers adaptive same-handle mode.
- Next: publish the scoped task change to PR #12, then verify its exact head/base/merge-result, fresh hosted CI and independent review; do not merge until they pass. Old hosted run is historical. Stack build/dependency audit is NOT COVERED.
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
