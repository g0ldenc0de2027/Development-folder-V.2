# Specification state

Canonical source: spec/ТЗ.md
Version: 0.1.0-draft
Status: DRAFT / NOT READY
Implementation admission: blocked for product features
Infrastructure bootstrap: allowed and underway
Open decisions: supported operating systems; stack-profile inventory; local knowledge integration; project progress/ETA model; release and backup policy.

## Допуск T-004 от 2026-11-15

По прямому поручению владельца READY только срез RULES и файловой локальной БЗ, описанный в spec/local-knowledge.md (LKB-001…008). Остальной продукт остаётся DRAFT / NOT READY. Автоматический рой, общий publisher, миграция V1 и внешние adapters в допуск не входят. Реализация среза прошла локальный gate и 44 KB-регрессии; точные CI/review свидетельства ведутся в PR #4; состояние задачи — tasks/T-004-rules-and-local-knowledge.md.


## T-013 — оркестрация ИИ-агентов

- Статус: DRAFT / NOT READY; реализация заблокирована.
- Версии: спецификация 0.18.2-draft; roadmap 0.18.2-draft; исследование 2.9.4.
- Исследование: knowledge/records/agent-orchestration-research-2026-11-16.md.
- Спецификация: spec/agent-orchestration.md.
- План этапов: docs/agent-orchestration-roadmap.md.
- Начальный режим владельца: локальная доска и ручная передача; автоматические adapters не допущены.
- Открытые решения M0: полный перечень 19 вопросов находится в spec/agent-orchestration.md, раздел 10; группы решений охватывают UI/ОС и data-root, хранение/backup/encryption/recovery, классы данных/egress и точные provider surfaces, permissions/review/security acceptance, лимиты импорта, usage/cost budgets, NFR/accessibility, обновления/release и измерение прогресса/ETA.
- Исследование R3/R5/R6: 73 уникальных GitHub repositories / 77 repository+commit pins; глубина review различается, полный market/source audit не заявляется. DeepSeek и Antigravity подтвердили прежний семипутевой snapshot (704 bytes, manifest 5fea239169c86e0136996521a953d292e654d3ed66101a6c0128a9bc334e306d). DeepSeek отметил P2 по атомарному отзыву assignment/permits для stop states, Windows device aliases и дублированному permit binding; Antigravity — P2 по условности cross-vendor review. Все пункты внесены в текущую DRAFT-редакцию; оба отзыва относятся только к прежнему snapshot и не являются approve текущих байтов.
- Реализации оркестрации нет. DRAFT-версии: spec/roadmap 0.18.2-draft, research 2.9.4.
- Исторический статусный снимок T-016, 2026-11-18: до этой документационной правки recovery worktree прошёл полный локальный quality gate и `git diff --check`. На момент снимка live PR #15 имел head `5195af19787c84e8bfba3aa4e02f249be56cf19f`, base `f577dc70e58d75ab5fd61d0c2e712c27b590713a`; hosted run [#44210090547](https://github.com/g0ldenc0de2027/Development-folder-V.2/actions/runs/44210090547) завершился SUCCESS для события `pull_request`, а его `head_sha` совпал с PR head. Этот снимок не утверждает SHA checkout/test merge-result; GitHub-native reviews: 0. Текущую ревизию и проверки после правок сверять по live PR #15. Application stack build/dependency audit — NOT COVERED, стек не выбран.
- Новые проектные требования: каждый переход в BLOCKED/CANCEL_REQUESTED/CANCELLED/REJECTED/CLOSED/CLOSED_WITH_RISK атомарно отзывает незадействованные permits и assignment generation; PREPARED run можно abandon только с доказательством no-dispatch, иначе DELIVERY_UNKNOWN/reconciliation и запрет retry. Permit включает digest account-memory snapshot; Windows device-name vectors покрывают COM/LPT superscripts, CONIN$/CONOUT$ и консервативный CLOCK$; M5 review follows owner-approved M0 review_policy, cross-vendor только если выбран.
- Provider roster — перечень желаемых продуктовых семейств, не подтверждённые профили. Точные surface/hosting/runtime, auth, permissions, egress, retention и cost evidence остаются UNKNOWN, пока не проверены для выбранного build.
- Учет расхода и fail-closed caps — требования DRAFT. Неизвестный ручной расход блокирует egress до M0 policy; возможное исключение permit-bound, одноразовое и не является техническим cap внешнего UI. Автоматический dispatch не реализован и остаётся заблокирован при UNKNOWN/недоказуемом hard cap.
- Историческая запись о раннем ограниченном запуске, superseded последующим актуальным снимком ниже: quality gate не прошёл до конца:

### Исторический provider-source snapshot — 2026-11-17 (до уточнения разделителя manifest)

- Спецификация 0.16.0-draft и исследование 2.7.0 остаются DRAFT / NOT READY; реализация заблокирована. OpenAI Codex остаётся ведущим по решению владельца; остальные provider profiles ещё не подтверждены на этой машине.
- Проверенные публичные refs: Qwen Code v0.27.4 @ f35dde84157f992bc324c0a3f59b1119344a683d; DeepSeek Harness v0.2.2-rc.3 @ 38a6a5c965aa99ab525161efb7cc5cf1fe62fced; отдельная текущая telemetry-документация Harness @ 39163dd30f703a79079e2d2446545cff3c453738. Версии/авторизация/настройки владельца не проверены.
- Зафиксированы отдельные egress-границы: SDK session-log в model request, отдельно deployment-configured telemetry; profile-specific danger-full-access; Qwen Managed Agent local-directory grants не обобщаются на local CLI.
- R3 donor inventory остаётся 68 repositories / 71 pinned refs; глубина неодинакова, не полный market/source audit. Cross-vendor review exact current manifest и решения владельца M0 всё ещё нужны.
- Полный pwsh -NoProfile -File scripts/quality-gate.ps1 -BaseRef origin/main: PASS (exit 0); privacy 41 Markdown + regression source, hygiene 59 text files, KB 44/44, actionlint PASS, Gitleaks PASS (54 commits и supplied push range). git diff --check: PASS. Application stack build/dependency audit — NOT COVERED, стек не выбран. Worktree T-013: six-file scope modified, commit/push нет по причине неразрешённой attribution прежних commits.
### Исторический снимок до повторного профильного ревью — 2026-11-16

- Проверенный committed HEAD остаётся 88342060af7c6c18a163d3b6fa6727ab5c17fd7e; текущий статус относится к незакоммиченному worktree и должен быть связан с новым content manifest.
- Read-only Git status вне ограниченного запуска подтвердил шесть scoped T-013 изменений; `git diff --check`: PASS. Полный локальный `scripts/quality-gate.ps1 -BaseRef origin/main`: PASS (exit 0), включая 44/44 KB-регрессии, privacy/hygiene, actionlint и Gitleaks. Прикладной stack build/dependency audit — NOT COVERED.
- Спецификация 0.7.0-draft; исследование 2.2.1; 25 уникальных GitHub-репозиториев / 26 закреплённых пар repository+SHA. Core-manifest четырёх deliverable-файлов: 5f8c43a7a95924f34137974ab918ec9b8c341cd767590ab8b8b0ef8b13331eb6. Проверенный Git HEAD 88342060af7c6c18a163d3b6fa6727ab5c17fd7e остаётся базовым и не включает рабочий diff; PR/commit и свежий внешний review не выполнены. Реализации нет; T-013 остаётся DRAFT / NOT READY, M0 требует решений владельца.

### Исторический снимок после профильных исправлений — 2026-11-16 (до Copilot и последующего specialist review)

- T-013: DRAFT / NOT READY; реализация заблокирована. Автор — OpenAI Codex, GPT-6; спецификация и roadmap 0.7.0-draft; исследование 2.2.1.
- Проверенный committed HEAD `88342060af7c6c18a163d3b6fa6727ab5c17fd7e`; base `f577dc70e58d75ab5fd61d0c2e712c27b590713a`; шесть scoped T-013 файлов изменены локально, commit/push не сделаны.
- Research: 25 уникальных GitHub-репозиториев / 26 закреплённых пар repository+SHA. Каталог совпадает с SHA-256 записи.
- Core manifest четырёх deliverables: `8c55887a8dbe88be8c85f39487fb7a59ff1fb0a9d67181d911fb2e6f0ec66890`. `pwsh -NoProfile -File scripts/quality-gate.ps1 -BaseRef origin/main`: PASS (exit 0), KB regressions 44/44, privacy/hygiene, actionlint and Gitleaks PASS; application build/dependency audit NOT COVERED. Свежий независимый внешний review ещё не выполнен.
- Реализации нет; application stack build/dependency audit — NOT COVERED; открыты решения M0 из `spec/agent-orchestration.md`.

### Исторический снимок после Copilot и профильного follow-up — 2026-11-16

- T-013 остаётся DRAFT / NOT READY; реализация отсутствует и заблокирована до решений M0. Спецификация/roadmap 0.13.0-draft, исследование 2.3.7.
- Отчёт владельца атрибутирован продукту GitHub Copilot, target — committed HEAD `88342060af7c6c18a163d3b6fa6727ab5c17fd7e`; underlying model/provider UNKNOWN. Отчёт и прежний DeepSeek review не относятся к текущему рабочему snapshot.
- В текущем worktree изменены ровно шесть scoped-файлов; committed HEAD `88342060af7c6c18a163d3b6fa6727ab5c17fd7e`, base `f577dc70e58d75ab5fd61d0c2e712c27b590713a`; commit/push не выполнялись.
- Дополнены: lifecycle recovery до terminal/reconcile и owner confirmation, включая нулевое число pending requests; role/capability permission matrix; CURRENT-only aggregation; M1 egress gate; различие copy/export, owner-reported dispatch и provider receipt; guards INITIAL_INTEGRATION/REMEDIATION; golden acceptance set; canonical M0 manifest с Unicode 18.0.0 case-fold pin и независимый security review exact READY snapshot. Это DRAFT требования.
- Core-manifest четырёх deliverable-файлов (roadmap, catalog, research record, spec), format 1: `a1023ece6b7b1dc75faf9d53381134fd494b2a77b1998dfcd4f56bbb7acc2f4a`; catalog contentSha256 записи: `4d3426d6fc690503b6991482793d3d55b4a0ef61740764637b2f5fe168a6a6f1` (совпадает с SHA-256 файла).
- `pwsh -NoProfile -File scripts/quality-gate.ps1 -BaseRef origin/main`: PASS (exit 0) on the current draft contents; privacy 41 Markdown documents plus regression source, hygiene 59 text files, KB regressions 44/44, actionlint PASS, Gitleaks PASS (54 commits and supplied push ranges); final exact-snapshot gate rerun after evidence sync: PASS. Application stack build/dependency audit is NOT COVERED because no stack is selected.
- Нужен свежий независимый внешний review итогового content manifest; internal Codex review не является cross-vendor review. Application stack build/dependency audit NOT COVERED; реализация, commit и push отсутствуют.
### Исторический снимок после устранения review-findings — 2026-11-17 (до дополнения R3)

- T-013: `DRAFT / NOT READY`; реализация заблокирована до owner decisions и независимого security review точного READY scope.
- Версии: spec/roadmap `0.14.1-draft`, research `2.3.9`; review-generation retry, M1/M2 recovery, manifest path safety и clipboard egress требования синхронизированы между spec, roadmap, research и task. Windows manifest уточняет по-компонентное no-follow открытие; один `FILE_FLAG_OPEN_REPARSE_POINT` для полного пути недостаточен.
- Worktree `.worktrees/T-013`, branch `task/T-013-agent-orchestration-research`; HEAD `88342060af7c6c18a163d3b6fa6727ab5c17fd7e`, base `f577dc70e58d75ab5fd61d0c2e712c27b590713a`; шесть scoped-файлов изменены, commit/push нет.
- Core manifest format 1 (4 deliverables): `c0e367f7fefd9a61ecbbbb3b8f7cbb7242d8d15ec14d5d155566dc0a4befb97e`; research record SHA-256 и catalog совпадают: `7bf9766101ad76479174dece84d566aff8267f2e2277743081513ba500c0f9bd`.
- Six-file manifest включает task/tz_state; его digest вычисляется вне этих файлов и передаётся reviewer отдельно, чтобы избежать самоссылки.
- После Windows API уточнения: `git diff --check` PASS; `pwsh -NoProfile -File scripts/quality-gate.ps1 -BaseRef origin/main` PASS (exit 0); privacy 41 Markdown + regression source, hygiene 59 text files, KB regressions 44/44, actionlint PASS, Gitleaks PASS (54 commits + supplied range). Stack build/dependency audit — NOT COVERED: stack not selected.
- Три internal Codex reviewers независимо пересчитали и одобрили exact six-file manifest `979bf03dad1b54b07d16d2fec25178e437dcf3c620777a78186c554b73640eef` (static review, runtime не проверяли). Итоговый manifest для внешнего cross-vendor review пересчитывается отдельно; external review остаётся обязательным до реализации. Предыдущие Copilot/DeepSeek отчёты относятся к старому committed HEAD; код/runtime и прикладной stack не проверены.

### Исторический снимок T-013 до provider-surface follow-up — 2026-11-17

- T-013: DRAFT / NOT READY; продуктовая реализация не начата. Версии spec/roadmap 0.15.2-draft, research record 2.4.2.
- R3: 50 уникальных GitHub repos / 53 repository+SHA pins по всему исследовательскому документу; проверена и описана неодинаковая глубина источников. Проектная и общая KB проверены в пределах индексируемых записей.
- M1 имеет два честных исхода: board-only либо board плюс ручной owner-mediated handoff для профиля, прошедшего M0 acceptance. Без такого профиля передача данных агенту и экспорт/импорт выключены.
- Copilot findings по lifecycle и полномочиям интеграции устранены в draft. Предыдущие same-vendor internal critiques привели к фиксации source locators и M1 gate; cross-vendor review текущего snapshot ещё требуется.
- Research record SHA-256: f7acf0bf904209e995d25faf9b912f726c72989e7d17c5226f68638a673120b8; contentSha256 каталога совпадает. Core manifest format 1 (roadmap, catalog, research, spec): edc29c36c7cc2be3a3218dd8e2e422ce2db417bf48f2b08fe89659d593fd18a3. Six-file digest рассчитывается вне этих документов и передаётся reviewer отдельно.
- git diff --check: PASS. Полный quality-gate на текущем draft snapshot: PASS (exit 0); privacy 41 Markdown + regression source, hygiene 59 text files, KB regressions 44/44, actionlint PASS, Gitleaks PASS (54 commits + supplied range). Application build/dependency audit: NOT COVERED, stack не выбран.
- Worktree .worktrees/T-013, branch task/T-013-agent-orchestration-research; committed HEAD 88342060af7c6c18a163d3b6fa6727ab5c17fd7e, base f577dc70e58d75ab5fd61d0c2e712c27b590713a; шесть scoped-файлов изменены. Commit/push нет из-за fixture-attribution двух прежних commits; историю не переписывали.
- Следующий шаг: независимый cross-vendor read-only review точного six-file manifest; реализацию не начинать до M0 owner decisions, READY spec и независимого security review.


### Исторический снимок T-013 до local-storage follow-up — 2026-11-17

- T-013: DRAFT / NOT READY; версии spec/roadmap 0.15.3-draft, research 2.4.3; продуктовая реализация не начата.
- R3: 50 уникальных GitHub repos / 53 repository+SHA pins; текущий follow-up расширил официальные provider surfaces, но не добавлял новые donor repository pins.
- M1 фиксирует точные профили product/surface/runtime и отдельный ручной KnowledgeLookup evidence для локальной и общей KB. Без owner-approved профиля допускается только board-only.
- M1 процент/ETA не показывает. M2 percentage использует versioned owner-approved complete baseline и веса, считает owner-accepted deliverables; ETA — обоснованный интервал или NOT_ESTIMABLE.
- Исследование выполнено официальными источниками и тремя внутренними Codex specialist reviews; аккаунты, авторизация, установленные приложения и runtime не проверялись. Это не external cross-vendor review.
- Research record SHA-256: 7aacd1b9bff19a7f2f6db96b91194e37c3e04ed6ac04fb4a8b6f61ee44a3e71d; catalog contentSha256 совпадает. Core manifest format 1 (roadmap, catalog, research, spec): 0a611a9834a1f2582d420f1e5c8a60e54269060408d42b3c12069fc990ad89c6.
- Полный quality gate PASS (exit 0): privacy 41 Markdown + regression source; hygiene 59 text files; KB integrity PASS, truth NOT ASSESSED; KB regressions 44/44; actionlint PASS; Gitleaks PASS (54 commits + supplied push range). git diff --check PASS. Application stack build/dependency audit NOT COVERED, стек не выбран.
- Требуется свежий независимый cross-vendor review точного six-file snapshot до реализации; GitHub-native review не заявляется.

### Исторический снимок T-013 после local-storage follow-up — 2026-11-17

- T-013: DRAFT / NOT READY; spec/roadmap 0.15.3-draft, research 2.4.4; продуктовая реализация не начата.
- R3 дополнен официальными источниками SQLite WAL/backup/atomic commit и Microsoft file flush. SQLite остаётся кандидатом; сетевой и cloud-synced live data-root не допускается без отдельного доказательства. Целевой single-writer и recovery contract остаются требованиями, не реализованными функциями.
- Research record SHA-256: 9363264cd77334d627db6ea62f310351955473f1b01ea3e3b3a5f3dca145b1fa; catalog contentSha256 совпадает. Core manifest format 1 (roadmap, catalog, research, spec): aa69d1c6ef3aada4d014f7edc2d9c6fd342529cc15930621e19f05e9169dafda.
- Внутренний Codex architecture critic согласился с границами рекомендации; cross-vendor review точного изменённого snapshot отсутствует. Storage runtime/crash/restore не тестировались.
- Fresh quality gate после дополнения не запускался; предыдущий PASS не переносится на новый snapshot. Требуется повторный gate и независимый review.
- Worktree T-013 содержит шесть scoped-файлов; committed HEAD 88342060af7c6c18a163d3b6fa6727ab5c17fd7e; commit/push нет из-за неразрешённой attribution двух предыдущих commits.

### Исторический снимок T-013 до cancellation follow-up — 2026-11-17

> Сохранён для истории. Версии, gate-status и следующий шаг ниже описывают состояние до post-claim cancellation refinement; актуальные версии и результат gate указаны в верхнем статусе и последней записи задачи T-013.

- T-013 DRAFT / NOT READY; spec/roadmap 0.15.4-draft, research 2.4.5; implementation не начата. Новых GitHub-репозиториев и SHA pins не добавлено; source-level review углубил три уже закреплённых донора.
- Новый синтез требует fail-closed при повреждённом/нечитаемом store без автоматического seed, атомарного локального approval/mutation/outcome, durable external intent до dispatch и постоянного operation-level idempotency key, отдельного от `run_id`; crash-gap оставляет UNKNOWN без автоматической переотправки. Это требования DRAFT, не реализованные функции.
- Research record SHA-256: `33ca9e6a174b30989effdf0b7effab10129e7778c0fcc7d64f6df690d2d1bb2c`; catalog contentSha256 совпадает. Core manifest четырёх deliverables: `837f6d47c70e96b5ccb8ece7ce5566e05ed0afa7cb91aea80cb432d41ec2e512`; точный рецепт и SHA каждого файла записаны в `tasks/T-013-agent-orchestration-research-and-spec.md`. Hashes task card/tz_state исключены из core manifest во избежание самоссылки.
- Внутренний Codex architecture review включён с явной атрибуцией; cross-vendor review точного нового snapshot отсутствует. Доноры не запускались, crash/runtime/restore проверки не проводились.
- Read-only `git status` с повышенным доступом подтвердил `task/T-013-agent-orchestration-research`, `ahead 2` и ровно шесть scoped-файлов. `.git/config` содержит `core.bare=true`, но её причинная связь с sandbox-ошибкой не установлена; конфигурация не менялась.
- `git diff --check` PASS (exit 0) на LF-only snapshot. `pwsh -NoProfile -File scripts/quality-gate.ps1 -BaseRef origin/main`: PASS (exit 0); privacy/hygiene, KB regressions 44/44, actionlint и Gitleaks прошли. Стековая сборка и dependency audit не применимы: стек не выбран. Коммит/публикация не выполнялись; attribution двух прежних commits остаётся открытой.
- Следующий шаг: полный quality gate на текущем snapshot, свежий независимый cross-vendor review exact six-file manifest и отдельное решение по attribution/recovery; реализация блокируется M0 и READY/security gates.


### Исторический снимок T-013 после R3 donor follow-up — 2026-11-17

- Статус DRAFT / NOT READY; spec/roadmap 0.15.8-draft, research 2.5.0; реализации нет.
- R3 расширен на девять новых GitHub-кандидатов; сводный перечень — 59 уникальных repositories и 62 commit pins. Source/test, README и issue coverage различаются; API 403 и отсутствие Search pagination задокументированы как пробел покрытия.
- В текущем draft отражены переходы task/run/review/integration, раздельное owner authorization, atomic state+event, fencing поколения и проверяемое unknown/recovery поведение. Это требования, не реализованные возможности.
- Quality gate на изменённой рабочей копии проходит: privacy 41 Markdown + regression source; hygiene 59 text files; KB 44/44; actionlint и Gitleaks PASS; KB integrity PASS. Commit SHA остаётся 88342060af7c6c18a163d3b6fa6727ab5c17fd7e и не содержит текущих изменений; привязка точной редакции задаётся six-file canonical manifest.
- Worktree .worktrees/T-013, branch task/T-013-agent-orchestration-research, base f577dc70e58d75ab5fd61d0c2e712c27b590713a; изменены шесть scoped-файлов. Commit/push отсутствуют из-за неразрешённой attribution двух прежних commits.
- Готово: quality gate и git diff --check на итоговой редакции; canonical manifest format 1 рассчитан для шести файлов, digest передаётся reviewer вне scope. Следующее: свежий independent cross-vendor review точного manifest и решения владельца M0. Build/dependency audit прикладного стека NOT COVERED — стек не выбран.


### Исторический снимок T-013 после conformance/mailbox/worker-boundary follow-up — 2026-11-17

- Статус DRAFT / NOT READY; spec/roadmap `0.15.9-draft`, research `2.6.0`; реализации нет.
- R3 добавил девять новых repository identities и закреплённые source/test pins; сводный адресный охват — 68 репозиториев / 71 repo+commit pin. Включены canonical AionUi/AionCore, ACP TCK/SDK, CarryCtx, Dispatcher и worker-bridge; исходники не копировались, донорские тесты не запускались.
- В требованиях закреплены durable task-linked handoff/mailbox с at-least-once + idempotency, индивидуальные статусы conformance cases (`SKIPPED`/`NOT_TESTED` не PASS), точный adapter/runtime profile, worker fail-closed без direct/in-place fallback и ограничение stdout/stderr во время чтения.
- Full `quality-gate.ps1 -BaseRef origin/main`: PASS (exit 0) после обновления spec/research/catalog/roadmap; 41 Markdown + regression source, 59 text files, KB 44/44, actionlint, Gitleaks 54 commits и supplied ranges. Build/dependency audit приложения NOT COVERED: стек не выбран. Финальный повтор gate и diff-check выполнены после добавления этой status-записи.
- Worktree `.worktrees/T-013`, branch `task/T-013-agent-orchestration-research`, committed HEAD `88342060af7c6c18a163d3b6fa6727ab5c17fd7e`, base `f577dc70e58d75ab5fd61d0c2e712c27b590713a`; изменены ровно шесть scoped paths. Commit/push не выполнялись: identity двух предыдущих task commits остаётся `Scope Fixture` и не разрешена.
- Свежий cross-vendor review этого среза не получен; внутренние Codex subagent analyses не являются внешней оценкой. Следующее: передать точный manifest reviewer-ам, получить независимый read-only review и закрыть owner M0 decisions; до READY реализация заблокирована.

### Исторический снимок T-013 после adversarial review — 2026-11-17 (до официального provider-surface review)

- DRAFT / NOT READY; spec/roadmap `0.15.9-draft`, research `2.6.0`; реализации нет.
- Закрыты внутренние замечания: N/A больше не обходит обязательный conformance gate; stale snapshot помечен историческим; AionCore ACK и точность source locators исправлены. R3 охват — 68 repos / 71 pins; неизвестный dispatcher locator и rate limit указаны явно.
- Полный quality gate и `git diff --check` PASS после добавления этой записи: privacy 41 Markdown + regression source; hygiene 59 text files; KB 44/44; actionlint; Gitleaks 54 commits + supplied ranges. Stack build/dependency audit `NOT COVERED`.
- Worktree `.worktrees/T-013`, branch `task/T-013-agent-orchestration-research`, committed HEAD `88342060af7c6c18a163d3b6fa6727ab5c17fd7e`, base `f577dc70e58d75ab5fd61d0c2e712c27b590713a`; шесть scoped files, commit/push не выполнялись из-за неразрешённой Git attribution. Свежий cross-vendor review отсутствует; реализация заблокирована до M0/READY.

### Исторический срез T-013 после manifest-уточнения — 2026-11-17

- T-013 — DRAFT / NOT READY; spec/roadmap 0.16.0-draft, research 2.7.0; реализации нет.
- Provider source pins и ограничения R4 обновлены по точным официальным refs. Установленные продукты, учётные записи, runtime и эффективные egress settings на машине не проверялись.
- В canonical manifest format 1 устранена неоднозначность: LF используется между соседними записями; последняя запись не завершается LF. Это требование к будущему manifest verifier; сам verifier не реализован.
- R3 покрывает 68 уникальных GitHub repositories / 71 repo+commit pins; глубина различается, полного рынка/исходникового аудита не заявлено. Свежий независимый cross-vendor review точного среза отсутствует.
- Worktree T-013: committed HEAD 88342060af7c6c18a163d3b6fa6727ab5c17fd7e, base f577dc70e58d75ab5fd61d0c2e712c27b590713a; изменены шесть scoped files. Commit/push не выполнялись из-за неразрешённой attribution двух предыдущих commits.
- После уточнения manifest полный pwsh -NoProfile -File scripts/quality-gate.ps1 -BaseRef origin/main завершился PASS (exit 0); git diff --check PASS. Privacy: 41 Markdown + regression source; hygiene: 59 text files; KB: 44/44; actionlint и Gitleaks PASS (54 commits + supplied ranges). Stack build/dependency audit NOT COVERED: стек не выбран. Финальный повтор после записи этого результата выполнен: PASS (exit 0).
- Реализация блокируется до решений владельца M0, READY-приёмки и независимого security review точного будущего scope.

### Историческая запись статуса после DeepSeek/Copilot findings — 2026-11-17 (снимок superseded)

- На прежнем six-file snapshot reviewers подтвердили manifest `64d0694e…` и вернули CHANGES REQUIRED; к текущему семифайловому snapshot их вердикты не относятся.
- Это исторический промежуточный статус до R6 и текущих исправлений; его требование повторить gate относилось к предыдущей редакции. Проверки новых семи путей запускаются заново и будут отражены только в верхнем актуальном срезе.
- T-013 остаётся DRAFT / NOT READY. Коммит и push заблокированы до устранения attribution; новый manifest нужно передать reviewer-ам вне включённых в него документов.

## T-016 — восстановление происхождения T-013

- Статус: recovery-срез отделён от исходной ветки; PR #15 открыт/Draft, первый hosted gate прошёл; свежее независимое review актуального PR head ожидается.
- Исходный источник: T-013, committed HEAD 88342060af7c6c18a163d3b6fa6727ab5c17fd7e, семь локально изменённых файлов; Format 1 snapshot 704 bytes, SHA-256 39fc2f2f042d15e546b778cff626ab8e60d1eaf0adf3383b80868fb64e9cc37f.
- Историческая атрибуция исходных фрагментов UNKNOWN; fixture commits и исходный worktree сохранены. Recovery создаётся отдельной веткой от live origin/main без переноса старых commit objects.
- Изменение Unicode preview policy включено только в DRAFT / NOT READY; продуктовая реализация не начата.
