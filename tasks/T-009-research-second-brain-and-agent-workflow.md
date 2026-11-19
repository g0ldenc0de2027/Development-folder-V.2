# T-009 — Исследование второго мозга и мультиагентного рабочего контура

- **Статус:** research_updated; targeted research продолжается; уточнена портфельная модель двух БЗ, крупное исследование разделено на контекстно-доступные модули; записи остаются draft
- **Версии:** agent-workflow foundation v1.22.0; шесть тематических модулей v1.0.0; progress-and-eta v1.1.0; agent-coordination v1.6.0; credential-brokering v1.0.0; kb-system-architecture v1.2.0; local-first ADR уточнён 2026-11-16
- **База:** f577dc70e58d75ab5fd61d0c2e712c27b590713a (origin/main при создании, 2026-11-15)
- **Ветка/worktree:** task/T-009
- **Автор:** OpenAI Codex (GPT-6); §§21–22 включают пять внутренних read-only Codex source/test passes; §§23–24 дополнены targeted source/test review с двумя внутренними Codex subagents; отдельная запись о координации дополнена pinned GitHub-пассами по памяти, координации, доскам и workflow-контрактам; три внутренние роли Codex проверили направления память/доска/workflow; credential research вынесен в самостоятельную draft-запись; внешнее межпроизводительское ревью не проводилось
- **Независимое ревью другой модели/производителя:** не проводилось

## Цель

Собрать проверяемые идеи открытых решений для локальной проектной/общей памяти и будущего мультиагентного рабочего контура. Сопоставить их с решениями владельца: основной ПК, автономная и переносимая работа на произвольных дисках/ПК, локальная обработка по умолчанию, явный контроль внешней передачи, несколько AI-провайдеров, задачи/сообщения, восстановление и безопасность.

Это исследовательский срез. Он не утверждает архитектуру, стек или изменение схемы БЗ и не разрешает реализацию нового функционала до READY соответствующих требований.

## Зона файлов

- `tasks/T-009-research-second-brain-and-agent-workflow.md`
- `knowledge/records/agent-workflow-research.md`
- `knowledge/records/agent-workflow-coordination-r1.md`
- `knowledge/records/agent-memory-sync-synthesis.md`
- `knowledge/records/agent-workflow-source-ip.md`
- `knowledge/records/agent-admission-coordination.md`
- `knowledge/records/agent-source-review-runtime.md`
- `knowledge/records/agent-memory-bridge-execution.md`
- `knowledge/records/credential-brokering-research.md`
- `knowledge/records/progress-and-eta-research.md`
- `knowledge/records/agent-coordination-research.md`
- `knowledge/records/local-first.md`
- `knowledge/records/kb-system-architecture-research.md`
- `knowledge/catalog.json`

В этой итерации изменены/созданы только перечисленные scoped paths; Git status проверяется отдельно ниже.

## Исходное состояние и решения владельца

- Локальная БЗ V2 уже имеет schemaVersion 1, каталог с draft-записями, CLI и правила capture/admission. Существуют отдельные черновые записи local-first и swarm-boundaries.
- В текущем срезе знания отделены от оперативного состояния; общий coordinator, автодиспетчеризация, UI, embeddings и универсальные adapters не реализованы.
- Спецификация продукта остаётся DRAFT/NOT READY. Допуск T-004 не распространяется на проектирование реализации роя.
- Пользовательские решения о главном ПК, переносимости и локальной обработке приняты как исходные, не запрашивались повторно.

## Выполнено

- Исследовательская запись добавлена в локальную БЗ: `knowledge/records/agent-workflow-research.md`, ID `agent-workflow-research`.
- Catalog связан с записью SHA-256; статус записи и review оставлены `draft` / `null`.
- Сравнены локальная память, долговременная knowledge, state/run, task DAG/claim, agent messaging, workflow/HITL, security/sandbox, progress/ETA, межпровайдерная связь и переход к нескольким ПК.
- Добавлен targeted GitHub-раунд по temporal memory, additive admission, ACL поиска и path containment: Graphiti, Mem0 OSS v3, Open WebUI, AnythingLLM и GHSA-3f4c-xj8r-h4cr. Три репозитория закреплены по HEAD SHA 2026-11-16; проверен source-level write guard в выбранной ревизии AnythingLLM. Полные upstream-аудиты и runtime tests не выполнялись; подробности — §13.9 research-записи.
- Продолжен GitHub-раунд по переносимой памяти и агентским context adapters: OptMem, Mnemoverse, TencentDB Agent Memory, rohitg00/agentmemory, jayzeng/agentmemory. Пять refs проверены через git ls-remote --symref на 2026-11-16. Выводы и ограничения — §13.10; только OptMem получил выборочную source-level проверку, остальные новые claims помечены README-level.
- Проведены три раунда внутренних ролевых critique: 9 внутренних Codex subagents по локальной памяти/оркестрации/privacy, расширению памяти/координации и multi-PC sync (архитектура/эксплуатация/безопасность). Все одного производителя; это не внешний/межпроизводительский review.
- Добавлен targeted GitHub-раунд по multi-PC и переносимой синхронизации: Syncthing, Automerge + Keyhive, CouchDB, Electric; refs сверены, документы прочитаны на pinned revisions; результаты и acceptance matrix — §13.11. SQLite/WAL ограничение перепроверено по официальной документации. Три внутренних Codex critique (архитектура, эксплуатация, безопасность) не являются внешним review.

- Добавлен targeted GitHub-раунд по local-first client sync и durable event outbox: PowerSync, RxDB, PouchDB, Zero и durable-sync; текущие refs сверены. Для durable-sync выборочно просмотрены README, код и связанные тесты; другие выводы обозначены docs-level. Идеи и ограничения — §13.12, provider identity/head/tree — §14; код не запускался и не переносился.

- Добавлен targeted GitHub-раунд по review-gated admission, лестнице достоверности знаний, durable claims/leases/fencing, доставке сообщений, handoff, local data-root и границе MCP/auth: 9 проектов, 4 поисковых запроса, ссылки закреплены по HEAD; подробности и ограничения — §16. Проверялись README/выбранные docs/LICENSE, код не запускался и не копировался.

- Добавлен targeted GitHub-пасс по локальной доске, workflow-графу, provider adapters и честным статусам результата: `agent-comms`, AgentFlow, Task Dashboard и Agentic Coding Harness. Четыре source pins закреплены; для двух новых кандидатов выборочно прочитаны код и тесты. Полезные механизмы, permission-bypass анти-паттерн, ограничения и чистовой синтез — §17. Upstream tests/builds не запускались.
- Добавлен следующий GitHub-пасс по локальным control plane, mailbox, worktree-доскам и multi-provider UI: Okto Nexus, Agentic Kanban, Kandev, Agent Bus и Hive закреплены по текущим HEAD; в §18 сравниваются lifecycle, permission/auth boundaries, side effects, Windows readiness и licensing. Подтверждены важные anti-patterns: plaintext session secrets, unauthenticated board/bus surfaces, silent repo scaffolding и CLI presets с bypass approvals. MCO issue status перепроверен по истории, а не заголовку. Код и тесты upstream не запускались.
- Проведён source-level pass §19 по `Okto Nexus`, `Agent Bus`, `Hive` и `Agentic Kanban`: inspected pinned implementation/tests по транзакционному claim, delivery/ACK, recovery, worktree и scaffold side effects. Зафиксированы сильные паттерны и точные ограничения; generic inbox Agent Bus race помечен статическим риском, не воспроизведённой уязвимостью. Bare partial snapshots удалены; upstream-код и тесты не запускались.

- Проверен актуальный default branch `production` репозитория `open-agent-bridge` на commit `c117ae93a8d3a86633fb2fd6d8f3365d44463ac8`; §23 фиксирует рабочую идею Antigravity wake/adapters и подтверждённые source-level ограничения auth, server-side ACL, ACK, data recovery и Windows. Вывод: LAB / TRANSFORM_SECURITY; код не запускался и не копировался.

- Добавлен pinned GitHub source/test pass для LOCI, MARM, Agent Orchestrator и memk. Проверены event/queue/admission contracts, выбранные исходники и тесты; сохранены контрпримеры и Windows/security ограничения в §24. Два внутренних Codex subagents — не внешний review; upstream tests/builds не запускались.

- Создана отдельная draft-запись `knowledge/records/progress-and-eta-research.md`: agent-estimate и Planaco закреплены по exact HEAD/tree/repository ID; разобраны контракты, выбранные исходники и тесты; добавлены evidence, ограничения и чистовой синтез. Обе записи остаются draft. Код и upstream tests не запускались; точность моделей на наших данных не проверялась.

### Delta-pass 2026-11-16 — evidence-backed progress и agent ETA

Четыре дополнительных GitHub-запроса и три pinned source/test passes расширили отдельную запись progress-and-eta-research.md до v1.1.0. Добавлены ScopeTrace (evidence, актуальность и блокеры), agent-time (estimate/actual и калибровка) и Agent ETA (abstention, forecast receipts и holdout). Чистовой синтез отделяет процент по доказанному baseline от календарного ETA, запрещает числовую точность при недостатке данных и сохраняет факты локально. Upstream-код не запускался и не копировался; проектная схема/архитектура не утверждены, запись остаётся draft.

### Delta-pass 2026-11-16 — связь памяти и рабочей координации

Проведены четыре GitHub-запроса; три новых pinned source/test passes — Open Multi-Agent, taskgraph и Exocortex — занесены в отдельный draft agent-coordination-research.md v1.0.0. Синтез разделяет каноническую БЗ, operational event ledger и agent-private context; выделяет dependency-only context, durable claims/handoffs, точное human approval, memory admission и local-first data root. У каждого донора записаны ограничения доверия и эксплуатации. Код не копировался и не запускался.

### Delta-pass 2026-11-16 — дополнительные GitHub-аналоги

В agent-coordination-research.md добавлен §6 с pinned source/test review Captain Memo. Он добавляет к shortlist cross-AI memory, homework queue и work-board, но также выявляет существенные для нас ограничения: Windows guard лишь предупреждает, hook fail-open при недоступном worker, default auth warn и hosted embeddings по умолчанию. Их не переносим. Идеи остаются кандидатами, код не переносился; схема/стек и реализация не утверждены.
## Результат и ограничения

Синтез также отделяет каноническую БЗ от agent-private MemFS, session context, coordinator task/run/inbox state и derived graph/vector/search indexes. Для импорта данных и egress нужны отдельные policy gates. Все выводы остаются проектными предложениями, не утверждёнными требованиями.

Ни один репозиторий не выбран как основа и ни одна идея не утверждена как требование. Сохранённые источники, ограничения, предлагаемые этапы, открытые вопросы и рекомендации находятся в research-записи.

**Глубина:** R2 / targeted research. Поиск не объявляется исчерпывающим: web search не предоставил totals/pagination/incomplete-results; не проверялись полные исходники, issues/PR, releases/assets, зависимости, advisories и лицензии всех источников. В записи указан limitation report `SDR-T009-GCI-01` и вердикт `CONTINUE_TARGETED_RESEARCH`. Для выбора стека/реализации понадобится короткий целевой проход по shortlist и решение владельца.

- Delta-pass 2026-11-16: HEAD/published metadata, license signal, latest stable/pre-release snapshot and selected public advisories for shortlist; GitHub REST API later returned anonymous rate-limit 403. См. §15 research-записи.

## Проверки

- Historical snapshot от предыдущего прохода: тогда было 7 записей и catalog SHA-256 0aeef40e38ec94c15c4c699b70087c261f1c4c2635eed7b04004d352eefa0111. Это не текущая проверка; текущий результат приведён ниже.
- `tests/kb-regressions.ps1`: последний известный запуск PASS, 44 passed, 0 failed до §23; после §23–25 suite не запускался.
- `scripts/quality-gate.ps1 -BaseRef origin/main`: PASS (exit 0) on HEAD f577dc70e58d75ab5fd61d0c2e712c27b590713a plus the T-009 tree before the §23 documentation-only delta. That run covered privacy (39 Markdown files and test source), hygiene (57 text files), actionlint and Gitleaks. The full gate was not rerun after the later research deltas and split.
- Historical метрики до добавления новых записей: 7 records и прежние source counts/hash. Не использовать как состояние текущего worktree.
- Historical snapshot: на момент раннего прохода было пять scoped paths; он предшествует добавлению отдельных draft-записей и не описывает текущий status.
- Research is static; donor builds/tests, full license/security/dependency/advisory audits, native Windows E2E, and external multi-vendor review were not run. The OpenHands pass inspected selected pinned source but did not resolve its exact test paths or run any tests. One public Kopia issue/PR and the pinned restore path were inspected; the linked advisory page was inaccessible and no exploit was executed. No application stack is selected, so stack build/dependency audit is NOT COVERED.
- Ровно пять scoped T-009 paths изменены/созданы. Commit/push не выполнялись, upstream-код не запускался; временные metadata snapshots удалены.

## Открытые действия

1. Владелец рассматривает черновую research-запись; она не считается принятым знанием или утверждённой архитектурой.
2. При согласии — отдельная targeted проверка shortlist по поддержке, лицензиям, коду/тестам, issues/releases/security и совместимости, затем оформление решений и требований в spec.
3. Не начинать реализацию общего coordinator/agent swarm до статуса READY и явного среза.

Никаких commit, push, установки зависимостей и изменений исходного кода не выполнялось. GitHub использовался только для read-only исследования публичных репозиториев.


### Delta-pass 2026-11-16 — PurpleFlow source/test review

§20 research-записи сверяет pinned implementation/tests: recovery очереди и stash, двойную запись run state, ручные gates и тот факт, что verifyBlocking повторно маршрутизируется через ту же reviewer role/model. Windows в README имеет experimental статус. Проверки upstream не запускались; выводы остаются архитектурными идеями, PurpleFlow не выбран.


### Delta-pass 2026-11-16 — additional GitHub source review

§21 добавил source/test evidence для agent-coord (локальный control-plane UX плюс fail-open/нет ACL caveats), DmarshalTU/coord (подтверждённый stale-lease completion defect в конкретной ревизии), Letta Code (ограниченная передача памяти) и Graphiti (источник и временная актуальность фактов). Два внутренних read-only Codex subagents; это не внешний review. Upstream-код не запускался, стек и требования не утверждены.

### Delta-pass 2026-11-16 — второй мозг и агентская координация

Добавлен §22 по pinned GitHub-источникам: межпровайдерный MCP, durable inbox/lease/ACK, provider wake, provenance/admission, локальный retrieval, task acceptance/progress и отдельный server-tier. Проведены read-only внутренние Codex source/test passes; это не внешнее межпроизводительское review. Новых зависимостей и кода нет; ТЗ остаётся DRAFT/NOT READY.
### Delta-pass 2026-11-16 — кураторская подборка под сценарии владельца

В agent-coordination-research.md добавлен §7 с закреплёнными GitHub-источниками по переносимой памяти, локальным доскам, очередям и durable workflow-контрактам. Синтез разложен по потребностям: общий и проектный канон, private context, task/run ledger, общение и доставка, роли/ACL, admission, backup/restore, внешний egress и будущая multi-PC работа. Отдельно отмечены license-, ACL- и default-bind риски; идеи не являются утверждёнными требованиями, код не копировался. Три внутренние ролевые Codex-прохода не являются межпроизводительским review.

### Delta-pass 2026-11-16 — сверка лицензионных формулировок по pinned-файлам

Исправлена лицензионная атрибуция §7: OpenWOP на закреплённой ревизии объявляет Apache-2.0 для репозитория, а отдельный scope CC BY 4.0 для спецификации не подтверждён артефактом в этом дереве; Invoker описан по FSL-1.1-ALv2 и NCV Addendum без упрощённого вывода «коммерческое использование запрещено». Сверены pinned README/LICENSE и точный текст дополнения. Новые требования и код не добавлены; внешнее юридическое заключение не проводилось.

### Delta-pass 2026-11-16 — durable control plane и переносимая память

Добавлен pinned GitHub-проход по taimen-ai/control-plane и xianlinyi/agent-memory. Первый даёт контрактные идеи для transactional outbox, leases/fencing, authorization и отделения operational state от optional memory service, но требует Python/PostgreSQL/Docker и не подтверждает Windows-ready переносимую первую версию. Второй показывает настраиваемый Markdown vault и перестраиваемый SQLite FTS5 индекс, но стандартный Copilot SDK вызывается при ingest/query; это не соответствует локальной обработке без отдельного решения по local provider. Проверены README, architecture docs и LICENSE; upstream source/tests не запускались, код не копировался, требования и стек не утверждены.
### Delta-pass 2026-11-16 — backup integrity и безопасное восстановление

Добавлен targeted pinned pass по restic и Kopia: проверка структуры отдельно от payload, restore verification в отдельном target, клиентское шифрование и восстановление ключа. В pinned Kopia restore walker обнаружен небезопасный join имён из snapshot; issue #5700 открыт, PR #5719 с фиксом на момент просмотра не слит. Добавлены требования staging, path confinement, manifest/hash receipt, adversarial restore tests и rollback. Tree SHA не сняты; upstream-код/тесты не запускались, advisory page не открылась, код и зависимости не копировались; research остаётся draft.
### Delta-pass 2026-11-16 — OpenHands runtime boundary

Расширен ранее README-only разбор OpenHands Software Agent SDK по pinned DockerWorkspace source. Подтверждены loopback port mapping, mutable latest-python default image, caller-supplied mounts/network и environment-forwarding session API keys; перечислены отсутствующие в этом launcher явные runtime limits/hardening flags с оговоркой, что image/daemon не аудировались. Сформирован clean-room acceptance checklist для task-scoped workspace, минимальных credentials, pinned images, egress, quota, cleanup/reaper и path containment. Тестовые пути не подтверждены; upstream-код не запускался. Требования и выбор Windows sandbox не утверждены.

### Delta-pass 2026-11-16 — credential authority and reliability follow-up

Credential-brokering research is split into knowledge/records/credential-brokering-research.md to keep catalog entries below the KB file-size ceiling. Coordination section 8 links the module. Local KB reliability is the next targeted research pass. No architecture/product choice was approved.
### Delta-pass 2026-11-16 — модель двух баз и форматы файлов

Исторический срез модели двух БЗ v1.0.0/v1.1.0 предложил проектный namespace, происхождение, классификацию, аудитории, admission и обработку файлов. В нём недостаточно явно были отражены прямые записи владельца на любые темы и обязательный поиск в общей БЗ в начале работы. Это исправлено отдельным Delta-pass ниже; прежняя запись сохранена как история, а не как полное описание решения.

Предыдущий snapshot до разбиения большого исследования: HEAD `f577dc70e58d75ab5fd61d0c2e712c27b590713a`; тогда `scripts/kb.ps1 check` прошёл на 9 records; его catalog SHA-256 `a3bffaa4e40333f2e9ee11e7bda656336793f6bfbee696a844860c3d053b63ff`. Текущая проверка после разбиения приведена в последнем Delta-pass. `context -Id kb-system-architecture-research` PASS. В том историческом срезе до разбиения `context -Id agent-workflow-research` возвращал `KB_CONTEXT_LIMIT`; после модульного разбиения эта ошибка устранена и default-budget probes проходят. Общая БЗ: HEAD `283ec02c47b7a1228ebaf878f75d400dd734e406`, до capture `check` PASS, 2 canonical records; свежая проектная заметка сохранена capture ID `780ba019-c129-42c9-863d-ae981a22ee7b`, SHA-256 `772370b22166d83d4573c6961068c125f6d7bd9204329714dd3f338027ed6def`, `draft`, `admitted=false`, ignored inbox. Она ещё не стала частью каталога/поиска и не опубликована через Git.

Актуальные ограничения реализации: T-004 общая база обнаруживается как `available_not_validated`, но совместимость и federated search не реализованы; schema catalog v1 не содержит project namespace/ACL; обе поставки пока ограничены Markdown/JSON/PowerShell и не реализуют ingestion перечисленных типов. Проверка всех форматов, parser sandbox, межпроектных утечек, backup/restore и производительности не проводилась. Нормативное изменение модели знаний отслеживается отдельно в T-010 PR #9; live-страница PR на 2026-11-16 показывает его как Draft, поэтому не считать изменение слитым в main. Даже после формулировок правил потребуются READY-спецификация, схема и проверяемая реализация.

### Delta-pass 2026-11-16 — уточнение назначения двух БЗ и потока поиска

По прямому уточнению владельца локальная БЗ ограничена одним проектом/одной папкой разработки; общая БЗ принимает (а) отобранные ценные знания из проектных баз и (б) самостоятельные записи владельца на любые темы. В начале содержательной задачи локальная база обращается к общей за нужным контекстом. При отсутствии, недостаточности или возможном устаревании знаний проводится исследование; в сложных, неясных или дорогих при ошибке случаях владелец требует OSINT/Deep Research и профильные экспертные роли. Исследовательские выводы и доказательства сначала сохраняются локально; в общую предлагается только полезное портфелю после проверки provenance, прав, секретов/PII, свежести и scope. Это фиксирует намерение владельца, но не означает, что поиск, федерация, admission или права доступа уже реализованы.

`knowledge/records/local-first.md` и `knowledge/records/kb-system-architecture-research.md` согласованы с этим решением; версия архитектурного исследования повышена до v1.2.0, catalog hashes обновлены. Схема, ACL/audience, правила прямой записи, статус доказательств, передача между ПК, conflict/revoke и мультимодальная обработка остаются проектными решениями для READY-спецификации. Результат записи владельца не помечается как независимо подтверждённый только по факту происхождения.
### Проверки после уточнения модели — 2026-11-16

`pwsh -NoProfile -File scripts/kb.ps1 check`: PASS, 15 записей, целостность PASS; truth=`not_assessed`, review identity=`not_authenticated`; catalog SHA-256 `09d64b26d7a17c79d913c0ea83296ad0481ca71f7b3345de4d8132bc316bde69`. Адресные `context` для `local-first` и `kb-system-architecture-research` завершились с exit 0. `git diff --check`: PASS.

`pwsh -NoProfile -File scripts/quality-gate.ps1 -BaseRef origin/main`: PASS, exit 0; privacy охватил 49 Markdown-файлов и источник регрессий; hygiene — 67 текстовых файлов; KB regressions — 44 passed / 0 failed; Actionlint и Gitleaks PASS (47 commits). Application stack build/dependency audit: NOT COVERED — стек шаблона не выбран. Межпроизводительского ревью нет: ответ Antigravity из текущей сессии — NOT REVIEWED из-за недоступности GitHub/worktree в его среде. Изменения не коммитились и не публиковались.
Источники и pinned revisions, ограничения и предложения: `knowledge/records/kb-system-architecture-research.md`; применённые ссылки включают OWASP File Upload, SQLite FTS5/WAL и pinned GitHub-документацию. Внутренние Codex-роли помогли с retrieval, памятью и надёжностью; это не внешнее и не межпроизводительское review.

### Текущие действия и границы

1. Назначение двух БЗ и поток «сначала общий поиск → локальное исследование → контролируемое предложение в общую» уже заданы владельцем и отражены в v1.2.0. Для READY-спецификации остаётся определить namespace, классификацию, ACL/audience, admission/review, отзыв доступа и правила выдачи.
2. После уточнения оставшихся design decisions подготовить READY-спек на data model, local-to-common admission/common-to-project delivery, conflict/revoke, file-format support matrix, безопасный extraction, search/index, backup/restore и cross-project privacy tests.
3. Не выбирать parser/database/vector stack и не начинать реализацию до готовности соответствующего среза ТЗ. Restore drill, file parser security/compatibility tests, масштабный benchmark и независимое межпроизводительское review не проводились.

Commit/push не выполнялись.
### Delta-pass 2026-11-16 — доступность research через ограниченный context

Большая запись `agent-workflow-research` (256752 bytes) проходила integrity-check, но `context` завершался `KB_CONTEXT_LIMIT`, поскольку полный текст вместе с закреплёнными правилами превышал потолок ответа. Содержимое разделено на исходную базовую запись §§1–12 и шесть тематических draft-модулей §§13–26. Навигация и catalog links добавлены. Исходную последовательность восстановили из модулей: 256752 bytes и SHA-256 `03a509d87fd8d41addca3f7a8a00833710e3d47df01f0a44a27732ad7856cac9` совпали точно; перенос содержания без потерь подтверждён.

После разбиения `pwsh -NoProfile -File scripts/kb.ps1 check`: PASS, 15 records, 9 rule files, integrity=pass, truth=not_assessed, reviewIdentity=not_authenticated; catalog SHA-256 `9518ad7913c1e628bb2a03cd852fce253976ac8193f1fb01cbfe6fe55c710d77`. `context` с default MaxBytes=131072 прошёл для базовой записи и всех шести новых модулей: `agent-workflow-research`, `agent-workflow-coordination-r1`, `agent-memory-sync-synthesis`, `agent-workflow-source-ip`, `agent-admission-coordination`, `agent-source-review-runtime`, `agent-memory-bridge-execution`.

На момент этого среза состояние общей БЗ не менялось: capture proposal `780ba019-c129-42c9-863d-ae981a22ee7b` остаётся draft в ignored inbox; он не опубликован, не индексирован и не вошёл в Git. Её `check` PASS, 2 canonical records. `git diff --check` локальной задачи PASS; контроль UTF-8/LF/BOM/trailing whitespace — PASS. Полные KB regressions, quality gate, внешнее review, benchmark, parser/restore tests не запускались.

Польза: знания теперь можно адресно передавать агенту по одной теме в рамках стандартного контекстного бюджета. Это устраняет конкретный `KB_CONTEXT_LIMIT`, но не меняет сам CLI и не подтверждает масштабируемость поиска по большим коллекциям.

Commit/push не выполнялись.
### Delta-pass 2026-11-16 — единый план поддержки форматов

`kb-system-architecture-research.md` обновлена до v1.1.0: добавлены уровни A–D для основного текста/кода/данных, Office/PDF/email, OCR/ASR медиа и opaque/опасных бинарных файлов; указаны отдельные статусы текущей реализации и целевого плана. Для обеих баз предложена единая версионируемая capability matrix, при этом проектный scope и portfolio ACL остаются разными. Parser stack не выбран, извлечение файлов не реализовано.

Предложение в общей БЗ обновлено на source v1.1.0 и остаётся draft, `admitted=false`, без Git publication; его SHA-256 `772370b22166d83d4573c6961068c125f6d7bd9204329714dd3f338027ed6def`. Локальный `kb.ps1 check`: PASS, 15 records, integrity=pass, catalog SHA-256 `ce7b7fc73ddeecd46760f3de90144c1dc610d1bf4459463bcae7a7c2fa3742b8`; `context -Id kb-system-architecture-research` PASS при default budget. Обе базы остаются исследовательскими/текстовыми, а не мультимодально готовыми.

### Текущий срез для публикации — 2026-11-17

- Проверено 14 изменённых/новых путей; все 14 входят в зону этой карточки, вне зоны и отсутствующих заявленных путей нет.
- До записи этого раздела полный scripts/quality-gate.ps1 -BaseRef origin/main завершился PASS (exit 0), git diff --check — PASS; KB regressions — 44/44, Actionlint и Gitleaks — PASS. Полный gate повторяется после этой записи.
- Исследовательские записи остаются draft; независимое межпроизводительское ревью текущего снимка не проводилось. Результаты не утверждают READY, выбор стека или реализованные возможности.
- Следующий этап: повторить полный gate на финальном дереве, зафиксировать только 14 scoped paths, опубликовать обычную ветку задачи и запросить независимое read-only review; не сливать PR до review и штатных проверок.
