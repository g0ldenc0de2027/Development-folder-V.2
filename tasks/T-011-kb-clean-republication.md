# T-011 — Чистая повторная публикация проектной и портфельной модели БЗ

- **Статус:** in_progress; повторная публикация исправленного среза без переписывания опубликованной истории T-010/PR #9
- **Версия задачи:** v1.0.0 · 2026-11-16
- **База:** `f577dc70e58d75ab5fd61d0c2e712c27b590713a` (`origin/main` на момент создания)
- **Ветка/worktree:** `task/T-011-kb-clean-republication` / `.worktrees/T-011`
- **Автор:** OpenAI Codex (GPT-6)
- **Причина:** PR #9 содержит опубликованные коммиты с fixture-автором `Scope Fixture`; историю не переписывать. DeepSeek выявил ошибки, требующие исправления в текущем содержимом до повторного review.

## Цель

Опубликовать согласованный с владельцем project-only / portfolio-wide KB scope, исправить замечания DeepSeek и Copilot, сохранить границы текущей реализации и выпустить содержание новым task branch с проверенной GitHub noreply-идентичностью автора. Старые PR #9 и ветку T-010 не переписывать и не удалять.

## Зона файлов V2

- `README.md`
- `docs/handoff.md`
- `docs/local-knowledge.md`
- `knowledge/README.md`
- `rules/COVERAGE.md`
- `rules/RULES.md`
- `rules/modules/01-knowledge-and-calibration.md`
- `rules/modules/07-research-and-decisions.md`
- `rules/policy-lock.json`
- `spec/local-knowledge.md`
- `spec/portfolio-kb-agent-workflow.md`
- `spec/СОСТОЯНИЕ.md`
- `specification-system/tz_state.md`
- `tasks/T-010-align-project-and-portfolio-kb-scope.md`
- `tasks/T-011-kb-clean-republication.md`

Каноническая общая БЗ обновляется отдельно в её существующей ветке PR #2. Пять нормативных файлов пакета должны совпасть побайтно между репозиториями, а lock — проверяться штатным gate.

## Критерии приёмки

1. Фактические возможности схемы и CLI описаны отдельно от цели: текущая БЗ не заявляет существующие record ACL, классификацию, аутентификацию или фильтрацию.
2. В общую коллекцию не предлагается помещать закрытые/конфиденциальные данные до реализации и проверки ACL; правило 20 ограничивает внешнюю передачу и требует минимизации/redaction либо остановки передачи.
3. Правила 1, 17 и 20 и пакет v0.5.0 побайтно согласованы с каноном; `policy-lock.json` проходит штатную проверку.
4. Архитектурная спецификация остаётся `DRAFT / NOT READY`, содержит решение по at-rest encryption/key management как открытый вопрос и не заявляет нереализованные механизмы.
5. Карточка T-010, README и handoff ясно различают исторический PR #9, заменяющую T-011 и актуальные действия; старые CI/review не приписываются новому SHA.
6. Все изменения входят в перечисленную зону; индекс чист до подготовки финального набора, секретов/личных адресов нет.
7. Ветка T-011 основана на актуальном `origin/main`; автор каждого нового коммита — проверенная GitHub noreply-идентичность `g0ldenc0de2027`, trailer `Assisted-by: Codex:GPT-6`; чужая история не переписывается.
8. Пройти `scripts/quality-gate.ps1 -BaseRef origin/main` в V2, `scripts/kb.ps1 check` и regressions в общей БЗ, байтовую сверку зеркала и `git diff --check`.
9. После обычного push открыть replacement PR; зафиксировать live head/base/test merge-result SHA; получить зелёный hosted gate и независимый cross-vendor review на точном head до любого merge.
10. Текущая документация не маркирует пакет 0.5.0 как 0.4.0; исторические SHAs/run IDs и старые review привязаны к точным исходным ревизиям.

## Локальная проверка (2026-11-16; content commit c8c5b04)

- V2 `quality-gate.ps1 -BaseRef origin/main`: PASS, exit 0; base `f577dc70e58d75ab5fd61d0c2e712c27b590713a`; 40 Markdown и test source проверены privacy scan, 58 текстовых файлов — hygiene, 44 KB-регрессии PASS, actionlint PASS, Gitleaks PASS (47 commits). Стек приложения не выбран — build/dependency audit `NOT COVERED`.
- Общая БЗ: `kb.ps1 check` PASS (integrity=pass, 2 records, 9 rule files); `kb-regressions.ps1` — 44/44; `diff-regressions.ps1` — 11/11; `security-ci.ps1` Gitleaks/actionlint PASS; `git diff --check` PASS. Commit `f7a2a4dc1cc37bda5405fea1805b743e886c0568` pushed to PR #2; hosted run #43858637248 SUCCESS on exact head, base `283ec02c47b7a1228ebaf878f75d400dd734e406`.
- Пять файлов rule package совпадают побайтно между каноном и V2. Lock SHA-256: `73950eea937bed9501feb4fcd11b89bc49c5e5f4d6fb8fd34bf0d6ca52bc9022`.
- Первый T-011 gate выявил CRLF в созданной карточке; line endings нормализованы до LF, полный gate после исправления прошёл.
- Content commit `c8c5b04f55766c9d87b2d94f98a4c64ff567a140` создан с проверенным account-ID noreply author/committer и trailer `Assisted-by: Codex:GPT-6`; его полный локальный gate прошёл. На момент этого снимка перед публикацией T-011 ещё не pushed; hosted CI и свежий независимый review T-011 не проводились.
## Initial hosted evidence snapshot (2026-11-16)

- V2 PR #10 initial head `558ee654903920f752a0bc60d21be2d691df03fc`, base `f577dc70e58d75ab5fd61d0c2e712c27b590713a`; run #43860729578 SUCCESS on merge-result `efaa6aa96dfe950ab6e8cd12b4b696c5007adcc4` with exact parent pair.
- GitHub-native reviews at this snapshot: 0; independent cross-vendor review pending. PR #10 remained Draft.
- This evidence is bound only to the listed head/base. The subsequent handoff-only commit advances the PR head; this run does not validate that later head. Before merge, refresh the live tuple and require CI/review on the current head.
## Ограничения

T-011 не реализует федеративный поиск, record ACL, publisher, ingestion/parsers, OCR/ASR, агентский coordinator или прикладной стек. Старый PR #9 не закрывать до проверки замещающего PR и отдельного решения о завершении старого PR.
