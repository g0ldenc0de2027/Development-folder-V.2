# Исследование: второй мозг и мультиагентный рабочий контур

- **Проект:** Development Folder V2
- **Автор:** OpenAI Codex (GPT-6); основной анализ и синтез; §§21–22 включают пять read-only внутренних Codex source/test passes; §§23–24 дополнены targeted source/test review с двумя внутренними Codex subagents; §25 выполнен Codex read-only по GitHub; §26 — targeted static source review OpenHands; внешнее межпроизводительское review не проводилось
- **Дата:** 2026-11-16
- **Версия материала:** v1.22.0
- **Тип:** research
- **Статус:** draft — материал для обсуждения владельцем, не утверждённая архитектура

## 1. Цель и исходные решения владельца

Нужно спроектировать среду для будущих программных проектов: долговременную память, обмен контекстом между Codex, Claude, DeepSeek, Antigravity, MiniMax и другими инструментами, выдачу и приём задач, изоляцию параллельной работы, проверяемый прогресс, безопасность, перенос между папками/дисками/ПК и работу локально без постоянного интернета.

Уже заданы ограничения владельца: основной режим — автономная работа на основном ПК с переносимостью на другие ПК; локальная обработка включена по умолчанию; данные наружу отправляются только по явно разрешённому правилу. Чужие идеи изучаются, код и готовые решения не копируются. В V2 локальная файловая БЗ T-004 реализована как первый срез; автоматический рой, диспетчеризация и универсальные адаптеры не реализованы. Спецификация продукта остаётся DRAFT, поэтому эта запись не разрешает начинать реализацию функций роя.

## 2. Метод и границы исследования

На GitHub проверялись публичные README, архитектурные/безопасностные документы, отдельные исходники/тесты и официальные справки. Для кандидатов записаны полные refs, полученные read-only через git ls-remote; выборочные файлы читались по commit-pinned raw URL. В этой итерации GitHub REST API version 2026-03-10 использовался для ограниченного перечисления деревьев; затем Contents/search доступ достиг анонимного rate limit 403. Просмотрены официальные страницы OpenAI и SQLite; у них нет Git commit pin, поэтому указана дата доступа.

В проходах до §19 репозитории не клонировались. Для §19 использованы четыре временных bare partial-clone snapshots, привязанных к зафиксированным commit SHA; для §20 — один snapshot PurpleFlow. Checkout, установка, сборка и выполнение donor-кода не проводились. Все snapshots удалены после чтения. В проектную БЗ не переносились исходники, конфигурации или prompts. Это выборочный архитектурный и source/test review, а не полный аудит репозиториев, security certification, нагрузочный тест или независимое подтверждение всех заявлений авторов.

## 3. Аналоги и полезные решения

| Проект / источник | Что полезно для нас | Ограничения и что не копировать |
|---|---|---|
| [PurpleFlow, 8a27a33d](https://github.com/PurpleSchool/purpleflow/tree/8a27a33d62d3b90d97917a6d4b88e2b89075f3af) | Оркестратор отдельно от UI; этапы с явными паузами владельца; отдельный Git worktree; состояние run и следующего шага в run.json; возобновление незавершённого этапа; повторный review-pass с проверкой блокирующих замечаний и ограниченные циклы исправления. Особенно близок к процессу разработки кода. | Использует локальные CLI Claude/Codex, а не любой аккаунт/приложение. Во втором review-pass вызывается та же reviewer role/model, поэтому межпроизводительская независимость не гарантируется. Worktree не изолирует ОС, сеть, секреты или исполняемый код. В рассмотренной версии Windows описана как экспериментальная/неполностью проверенная среда. |
| [Beads, 8cdfa796](https://github.com/gastownhall/beads/blob/8cdfa796a8f571266f2687f8b80365cbe26a943d/README.md) | Граф задач/зависимостей; ready-очередь незаблокированных задач; атомарный claim; закрытие узла снимает блокеры; связи blocks/duplicates/supersedes/replies-to. Полезно для очереди, чтобы агенты не брали заблокированную работу. | Task tracker на Dolt, а не проверенная система прав и не замена курируемой БЗ. Заявления о кросс-платформенности требуют отдельной проверки на нашей версии Windows. Не подключать как зависимость до пилота. |
| MCP Agent Mail Rust — [pinned LICENSE](https://github.com/Dicklesworthstone/mcp_agent_mail_rust/blob/2fee578fc8ce92b06c88eb5dc3a4340032a5835b/LICENSE) | На зафиксированной лицензии виден специальный OpenAI/Anthropic rider; GitHub API классифицирует лицензию как `NOASSERTION`. | `IP_REVIEW / EXCLUDED`: технический разбор источника прекращён, код и особенности реализации не используются; дальнейшее рассмотрение требует правовой оценки и письменного разрешения правообладателя. |
| [LangGraph persistence, 8740a065](https://github.com/langchain-ai/docs/blob/8740a06595c90320c2377065af572425f0aee4d4/src/oss/langgraph/persistence.mdx) | Разделяет checkpoint текущего thread/run и долгоживущий store между threads. Полезно для разделения «память этой работы» и «знания, которые переиспользуются». | Framework-механизм не становится общей памятью всех приложений сам по себе. Нужны retention, миграции и проверка достоверности записей. |
| [Temporal approval pattern, 882a9dec](https://github.com/temporalio/documentation/blob/882a9dececd9ddcf7d3e18d4934b191c7e82a161/docs/design-patterns/approval.mdx) | Долговременное ожидание решения владельца: кто решил, причина, время; approve/reject/escalate; timeout и восстановление после перезапуска worker. Референс для human gate и неизвестного исхода. | Полный Temporal stack тяжёл для локального MVP на одном ПК. Берём durable waits/signals/timeout как идеи; отдельный workflow engine нужен только при доказанной потребности. |
| [Microsoft Conductor, c161d69b](https://github.com/microsoft/conductor/blob/c161d69bb1461f4037addea1be838e40e4a5bbef/README.md) | YAML-workflows с детерминированным роутингом без LLM-решателя; parallel/loop; agent/script/MCP/human-gate; явное завершение со статусом и причиной; лимиты, timeout, dashboard и fleet view. | Provider/stack и experimental-модули меняются быстро. Workflow-файл не должен стать единственным хранилищем live-state или механизмом доступа к файлам. |
| [OpenHands Software Agent SDK, 5e49ddac](https://github.com/OpenHands/software-agent-sdk/tree/5e49ddac5765f5dee428e3c9055028e829ccacfd) | Разделяет Agent Server/SDK, клиентский UI и automation; local workspace против ephemeral Docker/Kubernetes workspace; API/event-stream и workspace abstraction. Референс разделения control plane и execution plane. | SDK не заменяет task/ACL/approval model. Локальная папка не равна sandbox. Контейнеры требуют отдельного контроля образов, сети, секретов и эксплуатации. |
| [Letta Code, eadef1c6](https://github.com/letta-ai/letta-code/tree/eadef1c6c3594d1bf81517efd4b68fce54644ad4) | Память привязана к identity агента; git-backed MemFS, поиск сообщений, подагенты, global/project/agent skills, messaging и удалённые машины. Полезно для раздельной памяти профиля и проекта. | Самоизменение prompts/skills/harness и облачная память повышают риск занести ошибку в «ядро» или отправить данные наружу. На Windows auto-reflection отключён по умолчанию. Допускать только предложения в review, не автоматическое утверждение фактов/правил. |
| [Mem0, f1791daa](https://github.com/mem0ai/mem0/tree/f1791daa86d469249c9b002f62644d58a1eb96a0) | Раздельные user/agent/session/run scopes, metadata filters, expiration; выбор между хранением сообщений и извлечением фактов. Это идеи для schema и контекстной фильтрации. | В OSS v3 графовая память вынесена в Platform; managed API и extraction требуют решения о data egress, retention, удалении и верификации. Автоматически извлечённое не является достоверным знанием. Не подключать в локальном первом срезе. |
| [Microsoft Agent Framework, e2f52bc5](https://github.com/microsoft/agent-framework/tree/e2f52bc5a0c4b5e26901f63102fe509e51b48a92) | Текущий Python/.NET/Go framework описывает sequential/concurrent/handoff/group workflows, durability, restartability, observability, governance и human-in-the-loop. Следить как за референсом framework-сценариев. | Это библиотечная экосистема, не мост к любой desktop/CLI-сессии или аккаунту. Сначала потребовался бы маленький spike; наша архитектура не должна зависеть от одного framework. |
| [AutoGen, 83909851](https://github.com/microsoft/autogen/tree/8390985108cb1e3881f5f7297765758d8ad2540c) | Исторические идеи event/message-driven runtime и group chat. | README проверенной ревизии говорит, что AutoGen archived/no longer maintained, и рекомендует Microsoft Agent Framework. Не использовать как основу нового продукта. |
| [OpenAI Sign in with ChatGPT / Codex app-server](https://developers.openai.com/siwc/token-sharing-open-source/codex-app-server), [preview limits](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations), [accounts/sessions](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions), [ChatGPT plan in apps](https://help.openai.com/en/articles/20001542-using-your-chatgpt-plan-in-other-apps-and-sites) | Официальный механизм позволяет участвующему приложению получить отдельно одобренное разрешение для eligible requests; Codex app-server говорит JSON-RPC по stdio, умеет start/stream/resume. Профили аккаунтов и credentials нужно разделять. | Подключение само по себе не даёт историю чатов и память ChatGPT. Текущие preview limits исключают ряд hosted tools, включая file search, Code Interpreter, native computer use, hosted MCP и tool search; usage limits могут быть общими между приложениями. Это не подключение к открытому чату другого аккаунта. Сначала проверить eligibility/consent и провести малый spike; не использовать cookies или browser scraping. |
| [SQLite WAL](https://www.sqlite.org/wal.html), [подходящие сценарии SQLite](https://www.sqlite.org/whentouse.html) | SQLite подходит как кандидат для однохостового локального operational store без отдельного сервера. | Официальная документация требует для WAL процессы на одном host; для нескольких машин с прямым доступом рекомендует клиент-серверную БД. Не размещать общий live WAL-файл на SMB/синхронизируемом диске. |
## 4. Архитектурный синтез: «второй мозг» — несколько связанных слоёв

Не следует автоматически сливать все чаты, задачи и ответы моделей в один файл: оперативный статус загрязнит знания, ошибка станет «фактом», а общий context pack может открыть данные чужого проекта. Разделить классы данных и связывать их стабильными IDs:

1. **Канон общей БЗ:** правила, общие уроки, проверенные решения и материалы. Версия, provenance, владелец, статус, дата проверки/review, supersedes/revocation. Без credentials и полных чатов.
2. **Локальная БЗ проекта:** карта проекта, принятые решения/уроки, ограничения и ссылки. Она не обязана быть побайтной копией общей БЗ: общий канон и закреплённый project snapshot — разные источники с разными обязанностями.
3. **Оперативное состояние:** задачи, зависимости, assignments, попытки, run/checkpoint, события, сроки, blockers, тесты, review и статусы. Это транзакционные данные, не долговременные знания.
4. **Сообщения и артефакты:** треды по task/run; большие diffs, логи и отчёты отдельными артефактами с hash/access/retention. В БЗ записывается отобранный вывод и ссылка на evidence, не весь mailbox.
5. **Поиск и context cache:** производные индексы, пересоздаваемые из канонических текстов. До доказанного преимущества embeddings хватает lexical search + metadata; index не источник истины.

V2 уже следует части модели: Markdown/JSON catalog, draft-статусы, hash тела, отдельные task cards/worktrees, capture в ignored inbox без автоматического approval. Эти границы нужно сохранить.

## 5. Задачи, сообщения и запуск работы

**Task contract** должен содержать task_id, цель, scope файлов, acceptance criteria, зависимости, приоритет, deadline, data sensitivity, project/KB context, лимиты повторов/стоимости и ответственного. Ready-очередь учитывает зависимости; claim атомарный и выдаёт assignment_id/generation, срок lease и fencing token. Старый worker не должен перезаписать результат более нового assignment.

**Run state machine** фиксирует попытки, шаги, вход/выход adapter, head/base SHA, workspace, тесты, ошибки, timeout/cancel, незавершённый effect и checkpoint. Состояния: queued, assigned, running, waiting_owner, result_submitted, verification, review, rework, accepted, merged, blocked, failed, cancelled, interrupted/unknown. LLM может предложить переход, но не одобряет собственную работу: accepted выдаётся по критериям и evidence владельцем/главным ИИ.

**Message envelope**: message_id, idempotency key, task_id/run_id/thread_id, sender/recipient, тип, UTC timestamp, sequence/correlation, sensitivity, ссылка/hash артефакта и статус. Доставку отмечать отдельно: queued → submitted → delivered → acknowledged → processed → result_received. Если поверхность не подтверждает доставку, показывать unknown. Повторная доставка должна быть безопасной/idempotent.

Для первой версии достаточно координатора с адресными тредами/inbox/outbox и короткими handoffs. Не нужен свободный mesh-чат: агент получает scoped context pack, возвращает question/finding/result, а задачу назначает владелец/главный ИИ. Так меньше циклов, спама, prompt injection и неясной ответственности.

## 6. Память, переносимость и базы

У знаний, текущего run и профиля агента разные scopes: owner/global, project, task, agent-profile, run/session, ephemeral. Контекст содержит происхождение, scope, свежесть и разрешённость выбранному provider. Ошибка в памяти должна иметь correction/delete/revoke путь; при конфликте не считать автоматически истинным самый новый текст.

Будущая schema может потребовать source artifact/version, observed_at, last_verified_at, review_after/expires_at, sensitivity, owner, evidence, status, supersedes/revocation. Это предложение, не молчаливое изменение catalog schema 1. Нужны отдельные требования и миграция.

Хранить в Git канонические тексты/манифесты, не absolute user paths, локальные базы, ключи и выгрузки. Путь общей БЗ пользователь выбирает; он хранится локально вне Git и проходит doctor. Явно недоступная БЗ даёт диагностическую ошибку без fallback на случайный каталог.

Для одного ПК можно исследовать SQLite operational DB. WAL допустим только процессам того же хоста; каталог на другом диске — всё ещё тот же хост. Для одновременной работы нескольких ПК нужен сервис/API с серверной БД (кандидат — PostgreSQL), auth/ACL, offline queue и конфликтной политикой. Не открывать общий SQLite WAL-файл нескольким компьютерам.

Бэкап отделить от синхронизации: определить retention, encryption, RPO/RTO, проверку целостности и restore drill. Restore не должен включать активные credentials, старые сессии/leases и полномочия.

## 7. Безопасность и полномочия

- Владелец остаётся корнем доверия; no-App решение сохраняется. Локальный сервис по умолчанию loopback-only. Удалённый доступ требует identity, auth, ACL и threat model.
- Provider adapter объявляет capability: запуск, streaming, resume/cancel, файловые права, sandbox, network egress, account, лимиты, неопределённые исходы. «Connected» не означает доступ ко всем возможностям.
- Каждый аккаунт — отдельный credential profile. Provider получает только контекст задачи после data classification и явно разрешённой политики. Credentials не попадают в БЗ, сообщения и logs.
- Файлы, сайты и сообщения — недоверенные данные; нужны границы инструкций/цитат, allowlist tools, проверка параметров, ограничения команд/путей/сети.
- Worktree/task scope снижает конфликт, но не является sandbox. Для недоверенного кода нужен ограниченный VM/container, отдельные credentials, сеть закрыта по умолчанию, CPU/RAM/time quotas.
- Push, merge, release, изменение прав/секретов, удаление и внешняя передача чувствительных данных — human gate с actor/reason/SHA/time в журнале.

## 8. Поэтапная схема (предложение для будущего ТЗ)

**Этап 0 — ручная основа:** текущие task cards, worktrees, локальная БЗ, handoff, PR/review/CI. Codex как главный агент проверяет отчёты других ИИ по точным SHA. Процесс полезен без автоматизации внешних чатов.

**Этап 1 — локальный coordinator MVP:** после ТЗ/threat model — board как projection, durable event log, typed state machine, SQLite-кандидат для одного хоста, task graph, inbox/outbox, ручная передача внешним ИИ, артефакты по hash, resume после перезапуска, portable data root, backup/restore. Desktop stack выбрать после проверки Windows и требований.

**Этап 2 — официальные адаптеры:** по одному документированному CLI/app-server/API; capability manifest, auth isolation, conformance tests, cost/rate limits, retry/cancel/unknown outcomes. Возможно проверить Codex app-server как один adapter. Остальных подключать только через поддерживаемую поверхность. Не применять browser-cookie/UI scraping.

**Этап 3 — несколько ПК:** локально размещаемый API/серверная БД, TLS/auth/roles, offline queue, conflict resolution, remote workers в sandbox, observability и recovery.

**Этап 4 — расширенный поиск:** измерить lexical retrieval; сравнить metadata filtering/embeddings/reranker на обезличенном наборе. Авто-summary и dynamic swarm включать только после оценки пользы, приватности и отзыва ошибочного содержания.

### Progress и ETA

Процент вычисляется из утверждённого denominator: требования, веса/acceptance criteria, зависимости и deliverables. Выполнено только принятое с evidence; blocked/skipped/pending отдельно. ETA — диапазон по длительности аналогичных этапов, объёму остатка и ожиданию владельца/CI. Для калибровки сохранять estimated/actual start/end, blocked duration, task class, confidence. Без denominator нельзя выдавать искусственный процент.

## 9. Что брать / чего не брать

**Полезные принципы:** этапы/ожидание/возобновление (PurpleFlow/Temporal); dependency graph и готовность задач (Beads); долговременные checkpoints и human gate (LangGraph/Temporal); разделение проверенных документов и agent-written notes с provenance (agent-lore); сообщения/Task envelope между провайдерами (A2A); logical claims/leases и явный recovery (agent-loom); durable event outbox и точные ACK (durable-sync).

**Не брать:** один framework как универсальный управляющий всеми аккаунтами; общий чат без task ID/ACL/delivery; SQLite WAL на сетевой папке; auto-approval модельных воспоминаний; lease как permission; worktree как sandbox; широкие права CLI/bypassPermissions; browser scraping; бессрочное хранение всех диалогов; embeddings до измерения.

**Технический вывод сейчас:** оставить локальную V2 БЗ на Markdown/JSON/PowerShell CLI. Не подключать найденные продукты как зависимости до READY-ТЗ и отдельного Windows/security/compatibility пилота. MCP Agent Mail Rust исключён из технического shortlist из-за лицензионного rider; его технические детали в этом документе не сохраняются.

## 10. Вопросы для спецификации

1. В MVP один ПК плюс ручной exchange или второй ПК одновременно с первого релиза?
2. Какие классы данных может видеть каждый provider (public/project-internal/owner-private/prohibited), кто разрешает исключение?
3. Для каждого ИИ: официальный CLI/app-server/API или ручной relay; какие функции обязательны без browser automation?
4. Shared KB — канон с однонаправленными snapshots или reviewable contribution из проекта?
5. Что агент может только предложить; что требует approval; как revoke/delete распространяется на копии?
6. Retention run/chats/logs/attachments, бэкап, RPO/RTO?
7. Denominator прогресса: FR, acceptance criteria, задачи, этапы или комбинация; какие данные нужны ETA?
8. Лимит параллельных задач/writers для одного ПК и multi-PC?

Ответы владельца о главном ПК, переносимости и локальной обработке считать исходными, не спрашивать повторно.

## 11. Следующий шаг и качество источников

Главный ИИ превращает подтверждённые ответы в IDs требований, data contracts, security model и acceptance criteria; обновляет spec/ТЗ.md и spec/СОСТОЯНИЕ.md. Исследовательскую запись оставить draft до согласования владельцем и независимого review другого производителя. Новые providers, runtime, DB или framework не подключать до READY и минимального spike.

Upstream README/docs — первичные описания возможностей, не независимая оценка качества. Рассмотрены только перечисленные документы; исходники/тесты не запускались, практический Windows/portable multi-PC пилот не проводился.

## 12. Источники и точные ревизии

Первичный проход GitHub SHA: 2026-11-15. Указанные здесь SHA main получены через git ls-remote; исследовались только связанные документы. Дополнительные refs main повторно сверены 2026-11-16 (см. разделы 13–14).

- PurpleFlow 8a27a33d62d3b90d97917a6d4b88e2b89075f3af: [README](https://github.com/PurpleSchool/purpleflow/blob/8a27a33d62d3b90d97917a6d4b88e2b89075f3af/README.md), [architecture](https://github.com/PurpleSchool/purpleflow/blob/8a27a33d62d3b90d97917a6d4b88e2b89075f3af/ARCHITECTURE.md), [guide](https://github.com/PurpleSchool/purpleflow/blob/8a27a33d62d3b90d97917a6d4b88e2b89075f3af/docs/guide.md).
- Beads 8cdfa796a8f571266f2687f8b80365cbe26a943d: [README](https://github.com/gastownhall/beads/blob/8cdfa796a8f571266f2687f8b80365cbe26a943d/README.md).
- MCP Agent Mail Rust: только LICENSE-проверка на `2fee578fc8ce92b06c88eb5dc3a4340032a5835b`; ссылок на технические файлы не сохраняем.
- LangGraph persistence 8740a06595c90320c2377065af572425f0aee4d4: [persistence.mdx](https://github.com/langchain-ai/docs/blob/8740a06595c90320c2377065af572425f0aee4d4/src/oss/langgraph/persistence.mdx).
- Temporal 882a9dececd9ddcf7d3e18d4934b191c7e82a161: [approval pattern](https://github.com/temporalio/documentation/blob/882a9dececd9ddcf7d3e18d4934b191c7e82a161/docs/design-patterns/approval.mdx).
- Conductor c161d69bb1461f4037addea1be838e40e4a5bbef: [README](https://github.com/microsoft/conductor/blob/c161d69bb1461f4037addea1be838e40e4a5bbef/README.md).
- OpenHands SDK 5e49ddac5765f5dee428e3c9055028e829ccacfd: [README](https://github.com/OpenHands/software-agent-sdk/blob/5e49ddac5765f5dee428e3c9055028e829ccacfd/README.md).
- Letta Code eadef1c6c3594d1bf81517efd4b68fce54644ad4: [README](https://github.com/letta-ai/letta-code/blob/eadef1c6c3594d1bf81517efd4b68fce54644ad4/README.md).
- Mem0 f1791daa86d469249c9b002f62644d58a1eb96a0: [README](https://github.com/mem0ai/mem0/blob/f1791daa86d469249c9b002f62644d58a1eb96a0/README.md).
- Microsoft Agent Framework e2f52bc5a0c4b5e26901f63102fe509e51b48a92: [README](https://github.com/microsoft/agent-framework/blob/e2f52bc5a0c4b5e26901f63102fe509e51b48a92/README.md).
- AutoGen 8390985108cb1e3881f5f7297765758d8ad2540c: [README](https://github.com/microsoft/autogen/blob/8390985108cb1e3881f5f7297765758d8ad2540c/README.md) — historical reference; README marks it archived.
- OpenAI official docs, accessed 2026-11-15: [Codex app-server](https://developers.openai.com/siwc/token-sharing-open-source/codex-app-server), [preview limits](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations), [accounts and sessions](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions), [ChatGPT plan in apps](https://help.openai.com/en/articles/20001542-using-your-chatgpt-plan-in-other-apps-and-sites).
- SQLite official docs, accessed 2026-11-15: [WAL](https://www.sqlite.org/wal.html), [appropriate uses](https://www.sqlite.org/whentouse.html).

---
## Навигация по исследовательским модулям

Запись разделена по темам, чтобы каждый раздел помещался в ограниченный контекст `kb.ps1 context` вместе с обязательными правилами. Текст §§13–26 перенесён в отдельные draft-модули; исходная запись до разбиения имела SHA-256 `03a509d87fd8d41addca3f7a8a00833710e3d47df01f0a44a27732ad7856cac9`.

- §§1–12: эта запись — исходные решения, метод, базовый синтез и первоначальные источники.
- §§13–13.6: `agent-workflow-coordination-r1` — ранние GitHub-проходы.
- §§13.7–13.12: `agent-memory-sync-synthesis` — память, синхронизация, локальная/общая БЗ.
- §§14–15: `agent-workflow-source-ip` — source pins, лицензии и shortlist.
- §§16–18: `agent-admission-coordination` — admission, task boards и workflow.
- §§19–21: `agent-source-review-runtime` — выбранные source/test проверки и safety boundaries.
- §§22–26: `agent-memory-bridge-execution` — memory/coordination, OpenHands и worker runtime.
- Прогресс/ETA дополнительно выделен в `progress-and-eta-research`.

Все новые записи остаются `draft`; разбиение не меняет утверждённость выводов и не разрешает реализацию.
