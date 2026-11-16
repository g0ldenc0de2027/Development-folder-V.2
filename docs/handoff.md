# Handoff — T-011, 2026-11-16

- Общая БЗ: PR #2 head `f7a2a4dc1cc37bda5405fea1805b743e886c0568`, base `283ec02c47b7a1228ebaf878f75d400dd734e406`; hosted run #43858637248 SUCCESS на merge-result `11be6c3ff86a4091eff211920c0b132bb097ec19` с точными родителями.
- V2 replacement PR #10 открыт Draft: head `558ee654903920f752a0bc60d21be2d691df03fc`, base `f577dc70e58d75ab5fd61d0c2e712c27b590713a`; hosted run #43860729578 SUCCESS на merge-result `efaa6aa96dfe950ab6e8cd12b4b696c5007adcc4`, чьи родители совпадают с base/head. GitHub-native reviews нет; независимые cross-vendor отзывы ещё нужны.
- Контент T-011 локально прошёл полный quality-gate, push-preflight и hosted CI; commits используют подтверждённую account-ID noreply identity с `Assisted-by: Codex:GPT-6`. Canonical rules package 0.5.0 и V2 mirror совпадают побайтно по пяти файлам.
- T-011 исправляет описание current schema/ACL, ограничения egress Rule 20, открытую encryption/key-management развилку, stale version/SHA и атрибуцию; PR #9 сохранён без переписывания истории.
- Ограничения остаются: ACL, федеративный поиск, publisher, ingestion/OCR/ASR и coordinator не реализованы; portfolio workflow `DRAFT / NOT READY`; app stack audit `NOT COVERED`.
- Перед любым merge заново считайте live head/base/test SHA, требуйте hosted gate и независимое review для одного и того же текущего head. Следующий шаг — получить независимые отзывы по точным diff/SHA; unresolved CI-parent assertion вынесен отдельно.
## Исторический handoff T-004 — 2026-11-15

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
