# Исследование: память агентов и операционная координация

- **Проект:** Development Folder V2
- **Автор:** OpenAI Codex (GPT-6); read-only GitHub research и статический просмотр выбранных docs/source/tests; §§5–7 — pinned review GitHub-аналогов; §7 дополнен внутренними ролевыми Codex-проходами и целевым backup/restore pass; §8 — credential authority pass, это не внешнее межпроизводительское ревью
- **Дата:** 2026-11-16
- **Версия материала:** v1.6.0
- **Тип:** research
- **Статус:** draft — идеи для обсуждения; не утверждённые требования, архитектура или выбор продукта
- **Связь:** T-009; дополняет agent-workflow-research.md и progress-and-eta-research.md

## Область и метод

**Вопрос:** как связать вторую память, рабочее состояние нескольких агентов, назначения, передачи, проверки и общую доску, сохраняя локальный режим и контроль владельца.

Проведены четыре целевых GitHub-запроса о local-first multi-agent memory, provenance/admission, durable task coordination и desktop/workspace orchestration. Четыре проекта закреплены по текущим main SHA и деревьям; три новых проекта проверены по README, выбранным документам, исходникам и/или тестам. Для Open Multi-Agent просмотрены документы и тесты, но не реализация store целиком. Ранее исследованный MemoryLedger найден снова поиском и не считается новым source-level review этого прохода.

Это исследовательский синтез. Поиск не предоставил количества результатов, пагинации или статуса неполного ответа, поэтому он не исчерпывающий. Upstream-код не скачивался целиком, не запускался и не копировался в проект.

## 1. Источники и проверенные механизмы

### Open Multi-Agent — точность контекста и durable approvals

[Shared memory и передачa результата по зависимостям](https://github.com/open-multi-agent/open-multi-agent/blob/a1744e3b12692a52c21da27c6e3d1e0552a74e5e/docs/shared-memory.md#L234-L241), [durable approval lifecycle](https://github.com/open-multi-agent/open-multi-agent/blob/a1744e3b12692a52c21da27c6e3d1e0552a74e5e/docs/durable-approvals.md#L169-L179), [проверка восстановленного запроса и ограничения CAS/store](https://github.com/open-multi-agent/open-multi-agent/blob/a1744e3b12692a52c21da27c6e3d1e0552a74e5e/docs/durable-approvals.md#L232-L265), [тесты namespacing, redaction и expiry](https://github.com/open-multi-agent/open-multi-agent/blob/a1744e3b12692a52c21da27c6e3d1e0552a74e5e/packages/core/tests/shared-memory.test.ts#L29-L86) и [неразрушающего чтения истёкшей памяти](https://github.com/open-multi-agent/open-multi-agent/blob/a1744e3b12692a52c21da27c6e3d1e0552a74e5e/packages/core/tests/shared-memory.test.ts#L2043-L2070). Проверены main commit a1744e3b12692a52c21da27c6e3d1e0552a74e5e, tree bf1fc100bad31291bfeb4037b013358b6bf9002b, repository ID 1197656406. Корневой LICENSE — MIT.

Подтверждённая идея: результат завершённой задачи записывается в namespace агента и автоматически передаётся задачам-зависимостям. По умолчанию следующая задача получает только прямые зависимости; весь общий summary открывается явной настройкой. Payload может быть raw или структурированным, имеет ограничение размера, а некорректное structured-представление приводит к отказу задачи, а не к пустому контексту. Тесты проверяют разделение namespace, masking/redaction при записи и фильтрацию expiry без удаления источника на чтении.

Durable approval сохраняет точный reviewed request отдельно от telemetry, повторно валидирует ввод при восстановлении и отказывает при изменившемся содержимом или неподходящем хранилище. Это хорошая дисциплина связывания «что именно одобрено» с «что именно будет исполнено».

Ограничения важны: FileStore даёт CAS только нескольким callers одного экземпляра и не обеспечивает межпроцессную блокировку. CAS решения не закрепляет единственного владельца resume. Встроенных UI, reviewer transport, reviewer identity/authentication и audit-процесса показа нет; их обязан создать интегратор. Трасса и квитанция — производные данные, авторитетом остаётся primary approval row. Это библиотечная часть, не готовая общая доска.

### taskgraph — долговечный локальный граф задач

[Состояния, таблицы и локальная SQLite-модель](https://github.com/BudEcosystem/taskgraph/blob/679ae68d92afb6a7b8503762f656dd89b0d6483e/README.md#L176-L207), [claim/start/heartbeat/progress](https://github.com/BudEcosystem/taskgraph/blob/679ae68d92afb6a7b8503762f656dd89b0d6483e/README.md#L277-L293), [durable sleep/wake](https://github.com/BudEcosystem/taskgraph/blob/679ae68d92afb6a7b8503762f656dd89b0d6483e/README.md#L294-L316), [events, MCP и SSE](https://github.com/BudEcosystem/taskgraph/blob/679ae68d92afb6a7b8503762f656dd89b0d6483e/README.md#L510-L535), [конкурентный claim test](https://github.com/BudEcosystem/taskgraph/blob/679ae68d92afb6a7b8503762f656dd89b0d6483e/src/db/tests.rs#L77-L136), [idempotent wake/reclaim regression](https://github.com/BudEcosystem/taskgraph/blob/679ae68d92afb6a7b8503762f656dd89b0d6483e/src/db/tests.rs#L973-L1024). Проверены main commit 679ae68d92afb6a7b8503762f656dd89b0d6483e, tree f9f2d4d3daae9ecf2b46cd0dd125e5694ce515c8, repository ID 1173242603. Корневой LICENSE — Apache-2.0.

В выбранной ревизии README описывает SQLite-проект, задачи, зависимости, artifacts, notes, затронутые файлы, process observation state, retryable outbox и event log. Claim-ready-work заявлен атомарным; тест claim_task_concurrency_single_winner проверяет единственного победителя. Результат и заметки становятся контекстом downstream-задач. Sleep сохраняет идентификатор логического агента и opaque state reference, очищает heartbeat, задаёт wake time; раннее или устаревшее возобновление отклоняется. Тест проверяет, что wake event не дублируется, а sleeping-задача не отбирается по истечении heartbeat.

Для нашей доски интересны понятные статусы, DAG, ownership/heartbeat, durable pause/wake и наблюдаемый журнал событий. MCP и SSE — интерфейсы к одному состоянию, не отдельные источники истины.

Ограничения: README прямо ориентирует проект на небольшие и средние workloads, а не тысячи распределённых workers или строгие cross-region workflow guarantees. HTTP/SSE сервер, callbacks, subprocess observation и MCP увеличивают поверхность безопасности; этот проход не является аудитом auth, bind address, ACL, sandbox, dependency health, Windows install или аварийного восстановления. Наличие SQLite не означает, что файл БД можно безопасно разместить на сетевом диске или совместно открыть с нескольких ПК.

### Exocortex — provenance и границы доверия

[Позиционирование, память, tool policy, worktree и threat boundary](https://github.com/xD4O/exocortex/blob/e762971405073ec8489f0777a423e941e6e6e8c9/README.md#L171-L182), [поиск кандидатов на повышение confidence](https://github.com/xD4O/exocortex/blob/e762971405073ec8489f0777a423e941e6e6e8c9/src/exocortex/memory/promotion.py#L41-L84), [применение и audit event](https://github.com/xD4O/exocortex/blob/e762971405073ec8489f0777a423e941e6e6e8c9/src/exocortex/memory/promotion.py#L87-L122), [тесты разных и повторных источников](https://github.com/xD4O/exocortex/blob/e762971405073ec8489f0777a423e941e6e6e8c9/tests/unit/test_promotion.py#L53-L162). Проверены main commit e762971405073ec8489f0777a423e941e6e6e8c9, tree 412c40dc90d94f8f0a33ef87bdbeb187438df805, repository ID 1221935722. Корневой LICENSE — MIT.

README заявляет SQLite-backed shared memory с provenance на записях, policy middleware перед tool execution, operator approval для рискованных инструментов, отдельный git worktree на задачу и append-only replayable audit log. В выбранном коде confidence promotion ищет похожие записи и считает различные source-строки; тесты проверяют порог разных источников и то, что повтор одного источника не считается множественным подтверждением. Изменение уровня сопровождается audit event.

Это полезные идеи для provenance, изоляции рабочего дерева и явной лестницы доверия. Однако автоматическое повышение confidence не доказывает истинность записи: независимость agent identity и отсутствие сговора не устанавливаются одним числом source IDs. README прямо ограничивает threat model доверенным локальным оператором и не пытается защищать от злонамеренного агента или hostile multi-tenant среды. Поэтому consensus между агентами не должен автоматически делать утверждение каноническим или разрешать внешнее действие.

## 2. Синтез под требования владельца

Следующие пункты — концептуальная целевая модель для будущего ТЗ, не утверждённая схема или выбор технологий.

1. **Разделить три вида состояния.** Каноническая БЗ хранит допущенные решения/уроки с происхождением и версией; operational ledger хранит task/run/message/approval events; приватный рабочий контекст агента содержит временные заметки и черновики. Их нельзя сваливать в одну «общую память» без namespace и правил допуска.
2. **Давать контекст по необходимости.** По умолчанию агент получает ТЗ/карточку, явно разрешённые файлы и результаты прямых зависимостей. Полный проектный/общий memory summary — только по разрешённому scope. Каждая запись несёт источник, владельца/agent ID, проект и задачу, время, confidence/status, ACL и правила expiry/retention. Внешний текст остаётся недоверенными данными, пока не пройдёт admission.
3. **Сделать журнал первичным, доску — представлением.** Назначение, claim, heartbeat, вопрос, ответ, handoff, artifact, блокировка, approval и closeout — типизированные события с устойчивыми IDs, actor, timestamp и correlation/task ID. Доска, chat timeline и dashboard строятся как проекции; восстановление пересобирает проекции из проверяемого состояния.
4. **Не допускать двойное выполнение.** Claim должен быть атомарным и ограниченным проектом/задачей, с owner, lease/expiry, heartbeat, fencing/version и явным восстановлением просроченной работы. Повторные callbacks/event delivery должны иметь idempotency key. Sleeping/paused/review/blocked не следует считать ready.
5. **Оформлять передачу как durable handoff.** Передавать структурированный output, ссылки на artifacts, изменённые пути, evidence, известные ограничения, открытые вопросы и следующий шаг. Task graph владеет retries, dependency readiness и wake; адаптер агента владеет provider-specific conversation/checkpoint. Opaque ref отделяет данные orchestration от больших provider state.
6. **Одобрение привязывать к содержимому и исполнителю.** Approval request immutable; включать exact payload/hash, область действия, кто и что проверил, reviewer identity и expiry/revocation policy. Перед выполнением повторно валидировать payload и конфигурацию. UI-галочка или лог-сообщение не являются gate; отсутствие durable approval store, reviewer identity или актуального hash должно отказывать.
7. **Память повышать постепенно.** Наблюдение → предложенная запись → provenance/дедуп → проверка правил и конфликтов → человеческое принятие для канонической БЗ. Согласие нескольких моделей можно показывать как supporting signals, а не как доказательство факта. Исходный event остаётся доступным по retention policy.
8. **Оставить local-first переносимым.** Владелец задаёт data root при установке/doctor; внутренние ссылки используют IDs и относительные пути внутри проверенного root. Перенос между дисками/ПК — отдельный export/import/sync protocol с manifest, hashes, conflict handling, backup/restore и проверкой места/прав. Не считать общий SQLite-файл безопасным межсетевым транспортом.
9. **Контролировать egress.** По умолчанию не отправлять модели чужие логи, prompts, полный chat history, исходники и сведения о других проектах. Каждый внешний context bundle ограничен task scope и классификацией данных; передача имеет объяснимый preview, источник, provider и журнал разрешения владельца.

### Идеи для дальнейшей проработки

| Направление | Что взять как ориентир | Что обязательно перепроектировать |
|---|---|---|
| Контекст между задачами | OMA: dependency-only по умолчанию, полный общий контекст только opt-in | ACL/namespace на нашей модели проектов и агентов; размер и классификация контекста |
| Операционная доска | taskgraph: DAG, atomic claim, heartbeat, durable sleep/wake, события и artifacts | транспорт/ACL, multi-PC sync, Windows/portable data root, модель восстановления |
| Доверие к памяти | Exocortex: provenance, аудит, worktree isolation, отдельные этапы confidence | threat model: злонамеренный/ошибающийся агент, owner approval для canonical memory, проверяемая identity и правила против consensus-as-truth |

## 3. Не переносить как есть

- Привязку к конкретному TypeScript, Rust, Python, SQLite, MCP, HTTP или web UI: это кандидаты/примеры, не выбранный стек.
- Открытие всей памяти каждому следующему агенту.
- Автоматическое принятие знаний или повышение «истинности» только на основании совпадения ответов агентов.
- Approval без отдельного авторизованного reviewer, durable primary record и повторной проверки exact content.
- Предположение, что локальный файл-БД автоматически является безопасным multi-PC sync backend.
- Запуск upstream install scripts, зависимостей, агентов или инструментов в нашей среде.

## 4. Ограничения и пределы доказательств

Четыре целевых GitHub-запроса; четыре репозитория получили pinned commit/tree/repository ID, три новых источника рассмотрены по выбранным docs/source/tests. Поиск не exhaustive. Данные о количестве результатов недоступны. GitHub REST API metadata endpoints не удалось прочитать через search tool; HEAD проверялся через git ls-remote, tree — через filtered metadata fetch без blob objects, repository ID — по публичным метаданным GitHub. Root LICENSE прочитан по pinned revisions.

Не проводились upstream build/test runs, полные license/issue/release/advisory/dependency audits, threat-model verification, Windows end-to-end и multi-PC recovery tests. Описанные в репозиториях тесты не запускались, их реальные CI результаты в этом проходе не проверялись. GitHub README statements отдельно помечены как утверждения авторов, не как проверенные гарантии продукта.

Ни один продукт, библиотека, язык, база, протокол или архитектура не выбраны. Код, тексты и схемы не копировались. ТЗ остаётся DRAFT/NOT READY; для реализации требуется отдельное ТЗ с критериями и испытаниями по выбранным решениям владельца.

## 5. Дополнительный GitHub pass: память, coordination UI и восстановление (2026-11-16)

**Метод.** Текущие `HEAD → main` сверены read-only через `git ls-remote --symref`; выбранные README/исходники/тесты/CI просмотрены на этих SHA. Donor code/tests не запускались и не копировались.

### The Vault — близкий UX «память + рабочая доска»

[README](https://github.com/aliihsaad/the-vault/blob/6ec2485b83bb2062bc052b780b01701a4c711b8c/README.md), [typed collaboration model](https://github.com/aliihsaad/the-vault/blob/6ec2485b83bb2062bc052b780b01701a4c711b8c/packages/core/src/types/vault-collab.ts), [launch approval/actions](https://github.com/aliihsaad/the-vault/blob/6ec2485b83bb2062bc052b780b01701a4c711b8c/packages/core/src/services/vault-collab-actions.service.ts) просмотрены на `6ec2485b83bb2062bc052b780b01701a4c711b8c` (MIT). README описывает опциональный coordination extension со своей локальной SQLite БД, которую memory engine только читает; агенты получают свои inbox через receive loop. Модель содержит heartbeat/freshness, возможности сессии, claims/leases, зависимости handoff, события, обсуждения и launch requests. Выбранный action code требует approve и затем строит команду, а README заявляет видимое окно Windows worker и copyable fallback.

**Для нас:** доска и принятая долговременная БЗ должны иметь разные owner stores и lifecycle; агентский snapshot должен иметь время/heartbeat и состояние `stale/unknown`; запуск обязан иметь проверяемую авторизацию, preview команды и ручной fallback. README/source excerpt не доказывают полноценную Windows sandbox или безопасность процессов.

### Agent-Memory-OS (a2578348864a-sys) — лёгкий admission для локальной БЗ

[README](https://github.com/a2578348864a-sys/Agent-Memory-OS/blob/06ee0e599b4629ee9fc33b2325cea5e0153c1556/README.md), [Codex instructions](https://github.com/a2578348864a-sys/Agent-Memory-OS/blob/06ee0e599b4629ee9fc33b2325cea5e0153c1556/CODEX.md), [Windows CI definition](https://github.com/a2578348864a-sys/Agent-Memory-OS/blob/06ee0e599b4629ee9fc33b2325cea5e0153c1556/.github/workflows/windows-ci.yml) проверены на `06ee0e599b4629ee9fc33b2325cea5e0153c1556` (MIT). README показывает Markdown-карточки, фиксированный шаблон, draft→promotion, локальную write lease, snapshot backup с SHA-256 manifest и Windows CI. Сам автор прямо ограничивает lease собственным knowledge vault, не исходным репозиторием.

**Для нас:** адаптировать понятия проверяемого draft, receipt/manifest backup и область владения записью. Lease — кооперативная блокировка содержимого БЗ, не security boundary и не lock для task worktree. README заявляет Windows PowerShell 5.1+, несовместимый с нашей поддерживаемой политикой `pwsh` 7; workflow прочитан, CI-run и behavior не запускались.

### Praxia — постепенное продвижение знания

[Memory-cycle design](https://github.com/praxia-dev/praxia/blob/689925604a95ba959962cf65ad15a86166ded6ec/docs/memory-cycle.md) и [privacy policy](https://github.com/praxia-dev/praxia/blob/689925604a95ba959962cf65ad15a86166ded6ec/docs/legal/PRIVACY.md) просмотрены на `689925604a95ba959962cf65ad15a86166ded6ec` (Apache-2.0). Модель разделяет personal memory, candidate consolidation, общую память и review-управляемый Markdown-канон; описаны сигналы promotion: частота, outcome и LLM self-evaluation, а также opt-out. Privacy template указывает, что hosted LLM может получить prompt и retrieved context, и сам помечен незавершённым/не прошедшим counsel review.

**Для нас:** применима только граница private→candidate→shared/canonical с provenance и явной приёмкой. Автоматический score или совпадение агентов не должны сами изменять общую БЗ; внешняя передача остаётся запрещённой без явного разрешения.

### MIRA — переносимость и безопасное восстановление

[Backup guide](https://github.com/Vexillon-ai/MIRA/blob/f5b2db1f1f9453429cea45b045bec857716bfcc9/docs/guides/backup-and-restore.md), [admin backup/restore handler](https://github.com/Vexillon-ai/MIRA/blob/f5b2db1f1f9453429cea45b045bec857716bfcc9/src/server/handlers/backup.rs) и [crypto framing](https://github.com/Vexillon-ai/MIRA/blob/f5b2db1f1f9453429cea45b045bec857716bfcc9/src/install/backup_crypto.rs) просмотрены на `f5b2db1f1f9453429cea45b045bec857716bfcc9` (AGPL-3.0-or-later). Руководство описывает полный data-dir archive, включая мастер-ключи/provider API keys; код задаёт version-tagged формат, AES-256-GCM + Argon2id, admin-gated restore, staging и restart/swap. Документация также заявляет сохранение pre-restore data и запрет restore при несовместимой major version.

**Для нас:** backup manifest должен явно перечислять включённые данные и секреты; экспорт за пределы ПК требует шифрования; restore — проверить до замены, подготовить rollback и отклонять неподдерживаемую версию. Полная криптографическая/архивная безопасность выбранного кода не проверялась. AGPL noted только для будущей IP-проверки: код не используется.

### 5.1. Clean-room синтез

1. Оперативная coordination store: task/run/session/inbox/outbox/heartbeat/lease/event/receipt; долговременная БЗ: только принятые и версионируемые записи; приватный контекст агента не повышается автоматически.
2. Межагентное сообщение — транспорт/уведомление; authoritative task state — отдельная запись состояния с историей. Устаревшие heartbeat/lease отображать как stale/unknown; claim дополнить fencing generation, проверяемой при каждом изменении.
3. Запись в БЗ — capture с происхождением → draft → проверки privacy/scope/conflict → review/accept → immutable revision/supersedes. Модели могут предлагать и ранжировать; не являются approver фактов.
4. Переносимость требует owner-selected data root вне install path и versioned export/import/restore. Один SQLite/WAL файл не становится multi-PC sync только потому, что лежит на общем диске.
5. Отдельно показывать backup scope и наличие secrets; не передавать полный backup/полную историю облачному агенту или внешней модели автоматически.

### 5.2. Качество и границы

Это точечный R2 pass, не полный аудит доноров. Выбранные sources статически прочитаны; builds, tests, GitHub Actions run, releases, complete dependency/advisory review, Windows E2E и adversarial concurrency/recovery testing не выполнялись. GitHub search дополнительно показал `colemclauchlan/agentic-os`, но `git ls-remote` вернул `Repository not found`; выводы по нему исключены. Поиск не exhaustive: search API не показал totals/pagination. Лицензии проверены по pinned LICENSE snapshot и не являются юридическим заключением. Ни один продукт/стек не выбран; требований и implementation readiness это не меняет.

## 6. Captain Memo: cross-AI corpus, homework и work-board (2026-11-16)

**Идентичность и доказательства.** Текущая default branch `master` сверена через `git ls-remote --symref`: `f04261f697a378fa4df5bc515fe811ccbb488cd7`. Проверены pinned [README](https://github.com/kalinbogatzevski/captain-memo/blob/f04261f697a378fa4df5bc515fe811ccbb488cd7/README.md), [work-note store](https://github.com/kalinbogatzevski/captain-memo/blob/f04261f697a378fa4df5bc515fe811ccbb488cd7/src/worker/work-notes.ts), [PreToolUse hook](https://github.com/kalinbogatzevski/captain-memo/blob/f04261f697a378fa4df5bc515fe811ccbb488cd7/src/hooks/pre-tool-use.ts), [auth gate](https://github.com/kalinbogatzevski/captain-memo/blob/f04261f697a378fa4df5bc515fe811ccbb488cd7/src/shared/worker-auth.ts), выбранные [lease tests](https://github.com/kalinbogatzevski/captain-memo/blob/f04261f697a378fa4df5bc515fe811ccbb488cd7/tests/unit/work-notes.test.ts) и [auth tests](https://github.com/kalinbogatzevski/captain-memo/blob/f04261f697a378fa4df5bc515fe811ccbb488cd7/tests/unit/worker-auth.test.ts). Лицензия — Apache-2.0 по pinned [LICENSE](https://github.com/kalinbogatzevski/captain-memo/blob/f04261f697a378fa4df5bc515fe811ccbb488cd7/LICENSE). Код и тесты не запускались.

**Подтверждённые решения:**

- Один локальный worker координирует несколько AI-клиентов через MCP и нативные lifecycle hooks. Память, метаданные и временные work notes принадлежат worker; рабочие заметки в выбранном коде хранятся через KV-port, имеют `session_id`, intent, paths/topics, TTL, heartbeat/age и опциональные repo/branch/dirty/PID сведения.
- Отдельная очередь `homework` хранит идею, которую надо отложить, с понятным циклом `open → claimed → done`; это хороший UX-паттерн для защиты текущей задачи от внезапного переключения на новую просьбу.
- Конфликт определяется не только glob-файлами, но также темой, репозиторием и смысловой близостью. Протухшие или повреждённые claim entries фильтруются/удаляются при чтении; тесты фиксируют TTL, heartbeat, reap и сообщения о конфликте.
- Короткая session-start инструкция сообщает, какие операции поддерживает конкретный AI; unsupported integration использует ручной MCP/skill fallback вместо притворного авто-подхвата.

**Критические границы применимости для нашего Windows-first проекта:**

1. README этой ревизии прямо говорит: process lookup для guard на Linux; macOS lookup написан, но не проверен; Codex/Gemini claims на Windows дают только предупреждения. Это advisory work board, не cross-process lock и не безопасная изоляция. В `pre-tool-use.ts` заявлен fail-open контракт: outage worker, ошибка payload и timeout не должны блокировать запись. Для нас такой механизм может информировать, но защиту должны обеспечивать отдельный worktree на агента, точная зона файлов и обязательный gate, не зависящий от board.
2. В `worker-auth.ts` есть per-install token, timing-safe compare и owner-only файл; однако default mode — `warn`, где tokenless HTTP-запрос обслуживается и только логируется. Тест явно проверяет такое поведение. Режим `enforce` надо включать отдельно. Это полезная миграционная совместимость, но не подходит как наш default: координатор/локальный API должен отказывать при неавторизованном запросе, а status UI — показывать деградацию.
3. README рекомендует hosted Voyage embedder; chunks отправляются внешнему провайдеру, а `CAPTAIN_MEMO_EMBED_REDACT=1` включается отдельно. Local sidecar — опция с заметной стоимостью/предпосылками. Поэтому метка local-first не означает local-processing-by-default. Для нашей настройки default должен быть локальный, egress — видимо разрешаемый и журналируемый.
4. Автосбор transcript/notes от нескольких AI удобен, но широкая индексация повышает риск секретов, личных данных и prompt injection в память. Не индексировать всё подряд: source allowlist, классификация, secret scan, provenance, retention/forget и ручное продвижение в общий канон нужны до авто-захвата.
5. Межмашинная функция у автора отделена в коммерческий Fleet; README описывает запросы/ответы с атрибуцией источника и отказ от автоматического объединения памяти. Это интересный паттерн federated query без общего truth, но не равно автономной переносимой синхронизации; paired device получает тот же tool access, что и локальный клиент.
6. Для native Windows x64 используется Bun, SQLite/vector native extension и Scheduled Task; `win32-arm64` не поддерживается. Это конкретный integration example, не основание выбирать стек для V2.

### 6.1. Решение для нашей подборки

Captain Memo — **сильный UX/operational-flow reference**, но **не security blueprint** для нашего проекта. Забираем как идею раздельные active claims vs homework vs permanent memory, heartbeat/stale display, topic-aware collision notice, source attribution и provider-capability fallbacks. Перепроектируем enforcement, default auth, Windows process identity, egress, automatic capture, per-agent authorization и portable multi-PC sync. Ни один из этих feature claims не принят как требование; общий coordinator остаётся DRAFT/NOT READY.

**Предел проверки:** README + выбранные source/test файлы статически просмотрены на одной текущей pinned ревизии; test claims в исходниках не запускались, GitHub Actions result не проверялся, весь install/upgrade/security surface не аудировался, Windows E2E не выполнялся. Версия package на pin — `0.58.9`, Bun `>=1.1.14`; версия быстро меняется, для будущего выбора нужна свежая проверка. Никаких donor files, prompts или dependencies в V2 не добавлено.
## 7. Подборка решений под потребности V2 (2026-11-16)

**Метод и границы.** Проведён адресный поиск по переносимой памяти, локальным доскам и долговечным workflow-контрактам. Текущие refs выбранных репозиториев сверены через git ls-remote --symref на 2026-11-16; ниже выводы привязаны к SHA и конкретным README, спецификациям, документам безопасности и исходникам. Публичные GitHub-страницы доступны, но анонимный REST metadata endpoint в этом проходе вернул rate-limit 403; поиск не показал totals/pagination/incomplete-results. Это целевая выборка, не исчерпывающая карта рынка. Upstream-код и тесты не запускались, зависимости не устанавливали и файлы не копировали.

### Что полезно для нашей памяти

| Аналог и закреплённая ревизия | Полезный механизм | Ограничение для V2 |
|---|---|---|
| [second-brain](https://github.com/stancsz/second-brain/tree/9d7b8c465562944dc062d6f388753fccf8ae3704), MIT, beta | Канон — переносимый Markdown bundle со стабильными ID; SQLite — перестраиваемый поиск; Git синхронизирует текстовый канон, snapshots служат резервным восстановлением. Описаны receipts/journal записи и проверяемый staging для восстановления. | Это не доказательство совместимости со всеми AI-hosts. Индексы могут содержать текст. Backup не является multi-writer протоколом для общей БД. |
| [memory-forest](https://github.com/hyungchulc/memory-forest/tree/a9f2ec1588d0865ddc49c4c2db5b64b8d3dca442), GPL-3.0 | Retrieval сначала возвращает ограниченные метаданные/маршрут; полный текст открывается только для выбранного источника. Документ отдельно подчёркивает: локальный CLI не делает локальной саму обработку подключённой модели; память — недоверенные данные и не выдаёт разрешений. | Источник правил доверия и минимизации контекста, не готовая ACL или security boundary. Лицензия исключает использование кода без отдельного решения. |
| [schist](https://github.com/yibeichan/schist/tree/a4b4bba7176f6386c95e519d266b38e893835f2c), смешанные лицензии по артефактам | Git-версионируемые Markdown/YAML как источник истины, SQLite как производный индекс, предложение и человеческое принятие изменений общей памяти. | SECURITY.md сообщает, что MCP reads не имеют caller-level read ACL: подключённый caller способен читать настроенное хранилище. Это контрпример идее «локально значит ограниченно». Лицензию проверять для каждого файла. |

### Что полезно для доски и обмена работой

| Аналог и закреплённая ревизия | Полезный механизм | Ограничение для V2 |
|---|---|---|
| [agent-comms](https://github.com/pbroom/agent-comms/tree/1777b01f268f487c0594682dd27d93cb5b94c23a), MIT; основной обзор — agent-workflow-research.md §§17, 19 | Серверная identity, ограниченные сообщения со ссылками на ревизии, атомарный claim, expiring lease, bounded inbox/conversation и право человека финализировать решение. | Локальный control-plane reference, не доказательство безопасности или Windows-совместимости. Существующий обзор проекта не дублируется. |
| [OpenBoard](https://github.com/asasemahmed/openboard/tree/5d0ab6dbb19f0371d5e2a9498a9e418afc586eeb), PolyForm Noncommercial 1.0.0 | Типизированные карточки и связи, история/отмена, предложения при правке чужого содержимого и ограничение выдаваемого контекста. Источник UX-паттернов для доски и claims. | Документация говорит, что нет прав чтения по доскам; editor-агенты видят рабочие summaries. Non-commercial лицензия ограничивает коммерческое использование без отдельного разрешения. |
| [Collattice](https://github.com/MrBildo/collattice/tree/665341ff557f0084c6178c5ad53f92cdc20ecae7), MIT | Локальный board/API с настраиваемым путём базы и примерами Windows/PowerShell; ориентир для диагностики и настройки data root. | Hosting:ListenAddress в README по умолчанию 0.0.0.0. Сетевую привязку нужно проверять; ключи вызова инструментов не заменяют сетевой периметр и ACL. |
| [Atrium](https://github.com/useatrium/atrium/tree/599870ce92c079375ba8d08bd4c2ced9af0c86c5), AGPL-3.0 | Append-only журнал и версионируемые artifacts сохраняют обе конфликтующие версии; отдельный host-side broker передаёт данные sandbox без ingress в рабочий sandbox. | Тяжелее локального первого этапа: Docker, PostgreSQL и S3-compatible storage. Worktree и lease не являются OS sandbox. Код не переносить. |

### Что полезно для надёжных процессов

- [OpenWOP v2](https://github.com/openwop/openwop/tree/3936a204d46cb314004faabc8ce8c9a7dfa8bcf8) — исследована спецификация, а не совместимость готовых реализаций. Закрытые схемы interrupt/approval, журнал событий, повторный вход, идемпотентность побочных эффектов и разрешение ровно одного из параллельных ответов дают хорошие кандидаты для контракта coordinator. В закреплённой ревизии README и корневой LICENSE указывают Apache-2.0 для репозитория; отдельную CC BY 4.0 лицензию спецификации на этом дереве подтвердить не удалось, поэтому её охват оставлен неразрешённым и не используется как основание для повторного использования. [README](https://github.com/openwop/openwop/blob/3936a204d46cb314004faabc8ce8c9a7dfa8bcf8/README.md), [LICENSE](https://github.com/openwop/openwop/blob/3936a204d46cb314004faabc8ce8c9a7dfa8bcf8/LICENSE), [Interrupt](https://github.com/openwop/openwop/blob/3936a204d46cb314004faabc8ce8c9a7dfa8bcf8/spec/v2/core/interrupt.md) и [idempotency](https://github.com/openwop/openwop/blob/3936a204d46cb314004faabc8ce8c9a7dfa8bcf8/spec/v2/core/idempotency.md).
- [Invoker](https://github.com/Neko-Catpital-Labs/Invoker/tree/54877e0d891a28b22c1a2351d3c56db5e5749bc8), FSL-1.1-ALv2 с дополнением NCV: пример workflow/DAG и ручных точек контроля; лицензия допускает разрешённые цели, исключает competing use, а коммерческие изменения/распространение обязывает оставить open source. Дополнение также запрещает использовать продукт (кроме оценки/тестирования) для замены сотрудников или сокращения соответствующих ролей в течение шести месяцев после первого production use. Перед любым заимствованием требуется отдельная юридическая проверка; Task worktree не является изоляцией ОС.
- [MELRA](https://github.com/XAGI-Lab/melra/tree/ab59ffa134decd9613a378c7bd8a0e8d495c7e89), AGPL: интересная последовательность authorize → approve → budget → execute → verify → receipt/recovery и явный unknown для неоднозначного результата side effect. Лицензии артефактов требуют отдельной проверки.
- [agentic-kanban](https://github.com/zepinto/agentic-kanban/tree/abf401e22eb81c130c4505d0fce5b5c855191fa5), MIT: UX-цикл «анализ → одобрение владельца → запуск агента → проверка результата». README ориентирован на конкретные AI-hosts и указывает Windows через WSL2; это не подтверждает Windows-native совместимость или безопасность API.

### Дополнительный pinned GitHub-пасс: control plane и переносимая память (2026-11-16)

**Метод и предел проверки.** Текущие default-branch refs подтверждены через git ls-remote --symref: taimen-ai/control-plane c1c1ad195906cd3dadb8357677f1509019987dd1 и xianlinyi/agent-memory cede2457c3482096f81f680d2ebfc55b01d43608. Изучены pinned README, архитектурная документация и LICENSE; исходники и тесты этих двух репозиториев не запускались и в этом проходе не проверялись. Выводы ниже описывают документированный контракт и архитектуру, а не подтверждённую эксплуатационную готовность.

#### Taimen Control Plane — ориентир для будущей координации

[README](https://github.com/taimen-ai/control-plane/blob/c1c1ad195906cd3dadb8357677f1509019987dd1/README.md), [архитектура](https://github.com/taimen-ai/control-plane/blob/c1c1ad195906cd3dadb8357677f1509019987dd1/docs/architecture.md), [Apache-2.0 LICENSE](https://github.com/taimen-ai/control-plane/blob/c1c1ad195906cd3dadb8357677f1509019987dd1/LICENSE).

- Документация задаёт общую модель координации для людей, агентов и процессов: principal, workspace/roles/capabilities, зависимости задач, claim, execution run, approval и artifacts.
- PostgreSQL содержит нормализованное текущее состояние. Domain events — append-only журнал аудита и доставки, а не event sourcing. Документированный mutation path в одной транзакции обновляет состояние, событие и outbox; concurrency опирается на DB locks/constraints, optimistic version, lease, fencing token и idempotency.
- Контекстная память вынесена в отдельный необязательный сервис с HTTP-границей и durable cursor/дедупликацией. Это полезный пример отделения оперативной координации от долговременного знания.
- Ограничение для нашего старта: документация требует Python 3.12+, PostgreSQL 16 и Docker; API и worker — отдельные процессы. Поддержка Windows не заявлена в просмотренной README. Поэтому извлекаем контракты и инварианты, но не выбираем этот backend для первой переносимой локальной версии. Тесты, перечисленные README, не запускались.

#### xianlinyi/agent-memory — ориентир для локального каталога знаний

[README](https://github.com/xianlinyi/agent-memory/blob/cede2457c3482096f81f680d2ebfc55b01d43608/README.md), [архитектура](https://github.com/xianlinyi/agent-memory/blob/cede2457c3482096f81f680d2ebfc55b01d43608/docs/ARCHITECTURE.en.md), [MIT LICENSE](https://github.com/xianlinyi/agent-memory/blob/cede2457c3482096f81f680d2ebfc55b01d43608/LICENSE).

- Человекочитаемый vault хранится в Markdown в выбранной локальной папке; рядом SQLite FTS5 держит поисковый и relational/graph индекс, который документация позволяет перестроить после ручных правок. CLI принимает явный путь vault, а конфигурация задаёт его местоположение.
- ModelProvider отделён интерфейсом, но README указывает Copilot SDK как стандартный provider; ingest и query вызывают эту модель. Локальное хранение файлов само по себе не обеспечивает локальную обработку: нужен явно настроенный локальный provider либо отказ от модельной обработки.
- Ограничения по документации: Node.js не ниже 22.13; векторный поиск — только extension point/no-op по умолчанию; совместимость старого формата vault и полноценные миграции SQLite пока отсутствуют. В README перечислены тесты на ingest/query/rebuild/export, но мы их не запускали и качество реализации не подтверждали.
- Для V2 полезны явный data root, человекочитаемое содержимое, общий engine/API для CLI и будущего интерфейса, диагностика и восстановимый индекс. До проектирования требуется отдельно определить, какие файлы являются каноном, а какие — производными данными.

**Применение.** Taimen полезен как контрактный ориентир для будущей multi-PC/многопользовательской координации; xianlinyi — как формат локальной памяти и UX. В первой версии оставляем независимыми переносимый knowledge canon, перестраиваемый локальный индекс и operational ledger. Не переносим backend, provider defaults или код. Выбор схемы, технологии и требований остаётся за отдельным READY-ТЗ; research остаётся DRAFT.

### Дополнительный pinned GitHub-пасс: проверяемые backup/restore и path confinement (2026-11-16)

**Границы прохода.** Текущие refs master ранее сверены через git ls-remote --symref: restic 55abaa6de8cc82d563b916e2c46b31ce10ef8a2f; Kopia b6272a4ead04131cb09e3cfeb041f60410e97b05. Проверены закреплённые инструкции команд restic, функции восстановления и LICENSE обоих проектов; у Kopia дополнительно просмотрены pinned restore source, feature docs, публичные issue/PR. Tree SHA отдельно не зафиксированы. Upstream-код и тесты не запускались; это targeted static research, а не выбор бэкап-продукта.

#### restic — различать проверку каталога и чтение полезных данных

[Команда check на закреплённой ревизии](https://github.com/restic/restic/blob/55abaa6de8cc82d563b916e2c46b31ce10ef8a2f/doc/man/restic-check.1#L510-L567), [восстановление с целевой папкой и проверкой файлов](https://github.com/restic/restic/blob/55abaa6de8cc82d563b916e2c46b31ce10ef8a2f/doc/man/restic-restore.1#L774-L781), [BSD-2-Clause LICENSE](https://github.com/restic/restic/blob/55abaa6de8cc82d563b916e2c46b31ce10ef8a2f/LICENSE#L1-L12).

- Документация чётко разделяет проверку структурной согласованности snapshots/trees/pack files и чтение самих сохранённых данных через --read-data либо --read-data-subset. Успешная metadata-only проверка не доказывает читаемость каждого payload.
- У restore есть явный --target; --verify сравнивает содержимое восстановленных файлов. Это превращается в полезную модель доказательств: «копия создана», «метаданные проверены», «payload проверен полностью/частично», «пробное восстановление прошло» — отдельные статусы с указанием фактического покрытия.
- Ограничение доказательства: в этом проходе просмотрена документация CLI, а не реализация и тесты restic; гарантия не переносится на нашу будущую программу без собственных тестов.

#### Kopia — переносимое шифрованное хранилище и security-контрпример восстановления

[Возможности на закреплённой ревизии](https://github.com/kopia/kopia/blob/b6272a4ead04131cb09e3cfeb041f60410e97b05/site/content/docs/Features/_index.md#L234-L245), [pinned restore walker](https://github.com/kopia/kopia/blob/b6272a4ead04131cb09e3cfeb041f60410e97b05/snapshot/restore/restore.go#L349-L381), [Apache-2.0 LICENSE](https://github.com/kopia/kopia/blob/b6272a4ead04131cb09e3cfeb041f60410e97b05/LICENSE#L1-L5), [issue #5700](https://github.com/kopia/kopia/issues/5700), [открытый upstream PR #5719](https://github.com/kopia/kopia/pull/5719).

- Документы описывают mount, полное и выборочное восстановление; end-to-end encryption с пользовательским ключом защищает данные и имена файлов до отправки в storage. Та же документация предупреждает: потеря пароля делает backup невосстановимым — значит, безопасность ключа должна сопровождаться проверяемой процедурой его сохранения и восстановления.
- В pinned snapshot/restore/restore.go цикл copyDirectoryContent объединяет целевой путь с именем записи (path.Join(targetPath, e.Name())) и не выполняет локальную проверку имени перед постановкой дочернего элемента в очередь. GitHub issue #5700 описывает выход записи .. за restore target; открытый PR #5719 предлагает reject для пустых имён, ., .. и разделителей и добавляет тесты на отсутствие записи вне target. PR пришёл из форка и на момент просмотра открыт, поэтому его исправление не считается частью pinned upstream.
- Issue ссылается на advisory GHSA-9rpx-2vhm-38v3 и сообщает затронутые версии <= 0.23.1; сама страница advisory в этом проходе не открылась. Статический просмотр pinned-кода подтверждает аналогичный небезопасный join в этой конкретной ревизии, но мы не запускали exploit/тест и не делаем вывод о каждом релизе или конфигурации.

#### Что извлечь для нашей БЗ

- Backup health должен сообщать уровень проверки и покрытие данных, а не один зелёный статус; частичный scan нельзя называть полной проверкой.
- Restore не пишет сразу в рабочий canon: сначала отдельный staging-root, валидация manifest/schema/хэшей/количества записей и пробное чтение; только потом — проверяемая promotion с резервной копией и rollback.
- Каждый импорт и restore проверяет canonical containment до создания файлов: отклоняет абсолютные пути, .., drive/UNC/alternate separators, небезопасные symlink/junction/reparse-point переходы и выход из staging-root. Одних строковых path.join/resolve проверок недостаточно при существующих links и гонках; нужны безопасное создание без follow-links и отдельные adversarial fixtures, доказывающие, что marker вне target не создан.
- В receipt восстановления записывать snapshot ID, версии формата/инструмента, manifest digest, target staging root, проверенные объекты/байты, хэш-сверку, exit status, ошибки/пропуски и факт последующего rollback/promotion.
- Для БЗ, Git и operational DB нужны разные политики хранения и восстановления. Живой SQLite/WAL не синхронизировать файловым копированием; использовать согласованный snapshot/API БД, затем проверять восстановление в отдельную папку.
- Это clean-room требования, а не рекомендация подключать restic/Kopia как dependency. Выбор backup-tool, формат manifest и key-management остаются отдельными решениями; лицензии здесь зафиксированы лишь как сигналы по корневым LICENSE, не как юридическое заключение.

### Чистовой синтез для нашей архитектуры

Это кандидаты для собственного ТЗ, не утверждённый дизайн и не выбор стека.

1. **Три отдельные зоны данных.** Общая каноническая БЗ хранит только принятые знания; проектная БЗ хранит контекст проекта; operational ledger хранит задания, запуски, сообщения, доставку, ACK, lease, approval и результаты. Отдельно сохраняется приватный временный контекст каждого агента. Доска и dashboard — проекции ledger, а не новая истина.
2. **Переносимый канон, перестраиваемые индексы.** Канонический формат читается без приложения и имеет стабильные ID, provenance, версию и статус. Поиск, граф и embedding — производные индексы, которые можно восстановить из канона. Git может версионировать текстовую БЗ, но не синхронизирует одновременно изменяемую SQLite.
3. **Контекст только по необходимости.** По умолчанию агент видит задачу, ограничения, разрешённые пути и прямые зависимости. Сначала выдаются метаданные и ссылки; полное содержимое открывается только для выбранной записи. Retrieval содержит provenance/актуальность; память и внешний текст — данные, не команды или полномочия.
4. **Явный автомат задачи.** Различать queued → assigned → delivered → acknowledged → claimed → running → review → accepted/rejected, а также blocked, waiting-owner, stale/unknown и cancelled. Создание, доставка, начало исполнения и завершение — отдельные события с evidence.
5. **Конкурентная координация.** Claim атомарный и ограничен проектом/задачей; lease имеет heartbeat и fencing generation, проверяемую при записи результата. Нужны idempotency keys и ACK; expired claim восстанавливается явно. Lease без fencing не защищает от старого worker после переназначения.
6. **Одобрение привязано к содержимому.** Approval связан с immutable payload/hash, областью файлов/действий, reviewer identity и временем; перед исполнением payload и права проверяются снова. Только владелец разрешает публикацию, удаление, изменение аккаунта и внешнюю передачу данных.
7. **Admission памяти.** Transcript и логи не импортируются автоматически. Сначала предложение с источником, владельцем, задачей, классификацией и retention; затем проверки секретов, дублей, конфликтов и актуальности; затем human review и новая каноническая версия. Согласие моделей — сигнал, не доказательство.
8. **Портативность отдельно от синхронизации.** Установка принимает произвольный data root; внутренние ссылки используют ID, а валидатор проверяет выход из root и reparse points. Backup/export имеет manifest и хэши. Restore идёт в staging с проверкой и rollback. Multi-PC требует отдельного протокола конфликтов и отзыва доступа.
9. **Контроль egress и сетевой границы.** По умолчанию наружу уходит только явно выбранный минимальный контекст; для внешнего provider показываются preview, классификация, secret redaction и запись разрешения. Локальный API по умолчанию слушает loopback; чтение и запись имеют отдельные project/agent ACL.

### Практический порядок этапов

- **Этап 1 — portable KB:** произвольный data root, форматы общей и проектной памяти, provenance/admission, локальный поиск, manifest backup/restore, проверка переноса между дисками. Знания вносит человек.
- **Этап 2 — локальный control plane:** доска, журнал событий, inbox/outbox, состояния «доставлено / подтверждено / работает / готово», ручное назначение, история, роли и ACL. Автоматического запуска команд нет.
- **Этап 3 — AI adapters:** capabilities каждого host, ограниченные задания и сообщения, артефакты и тесты unknown outcome/recovery; сначала по одному проверенному адаптеру.
- **Этап 4 — безопасная автоматизация:** leases/fencing/idempotency, approvals, audit trail, квоты и egress; локальный sandbox отделён от Git worktree.
- **Этап 5 — несколько ПК:** после проверенных export/import, модели конфликтов, отзыва ключей, backup/restore drill и офлайн-восстановления. Живую SQLite/WAL БД не использовать как transport в синхронизируемой папке.

### Что не принимать из аналогов

Не давать всей команде полный доступ к общей памяти; не считать MCP, Git, worktree, локальную сеть или локальную БД границей авторизации; не считать ACK доказательством завершения; не продвигать знания по частоте или согласию ИИ; не отправлять transcripts/index внешнему provider без допуска; не разрешать агентам читать все проекты; не выбирать стек, продукт или донорский код по одному README.

**Вывод этапа:** подборка усилила направления «переносимый канон + производный поиск», «операционный журнал + доска-проекция», «bounded context + ручной admission», «durable workflow contract + отдельная изоляция». Требования, схема, стек, продукт и границы MVP не утверждены; T-009 остаётся research, спецификация — DRAFT/NOT READY.

**Глубина и предел проверки:** три внутренних Codex-ролевых прохода (память, доска, workflow) дополнили прямое исследование. Это один производитель; такое review не заменяет DeepSeek/Antigravity или security-аудит. Для большинства доноров изучены только выбранные источники на pinned revision; полный source review, upstream builds/tests/CI, Windows E2E, аудит всех releases/dependencies/advisories, юридическое заключение и adversarial multi-process/recovery проверки не выполнялись. Возможности остаются заявлениями проекта до воспроизведения.

## 8. Полномочия и credentials агентов (2026-11-16)

Предварительное направление для обсуждения, связанное с отдельной записью knowledge/records/credential-brokering-research.md:

- Task board, память, роль и статус running не выдают право на внешнее действие. Grant создаётся владельцем отдельно и привязывается к задаче, сессии, операции, target и сроку.
- Operational store записывает credential/grant ID и outcome; ключи и refresh tokens не попадают в события, сообщения, ошибки, логи, резервные копии и экспорт.
- Если host identity не проверяется, запись «Codex»/«Antigravity» — заявленная метка, не доказанная идентичность процесса. До проверенной изоляции владелец остаётся корнем доверия; общего автоматического секрета агентам не выдаём.
- Внешняя операция проходит проверку полномочия и egress независимо; секрет используется внутри broker/adapter, агент получает отфильтрованный результат. MCP/OIDC credentials ограничены собственным resource/audience.
- Первая версия БЗ может обходиться без автоматической выдачи credentials. Не читать конфигурации, profiles, environment и secret stores чужих AI-клиентов. Технология локального vault не утверждается.

Это исследовательское направление; модель identity, OS isolation, vault, API и интерфейс не выбраны.
