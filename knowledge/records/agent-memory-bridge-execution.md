# Исследование: память, межагентная связь и выполнение

- **Проект:** Development Folder V2
- **Автор:** OpenAI Codex (GPT-6); текст перенесён из исходного исследования без изменения содержания соответствующего диапазона
- **Дата:** 2026-11-16
- **Версия:** v1.0.0
- **Диапазон:** §§22–26
- **Статус:** draft; исследовательский материал, не утверждённая архитектура
- **Происхождение:** agent-workflow-research@03a509d87fd8d41addca3f7a8a00833710e3d47df01f0a44a27732ad7856cac9; конкретные ссылки и pinned refs сохранены в тексте разделов

---
## 22. Дополнительный GitHub pass по памяти и связи агентов

Проверено read-only несколько новых pinned-источников и выбранных тестов. Код не запускался и не переносился.

| Источник | Вывод |
|---|---|
| [agent-comm-hub, provider map](https://github.com/JochenYang/agent-comm-hub/blob/9f9a716977509d32c1d9652fab57452202185ab2/README.md#L303-L370) и [restart test](https://github.com/JochenYang/agent-comm-hub/blob/9f9a716977509d32c1d9652fab57452202185ab2/test/e2e.mjs#L190-L207) | Ближайший MCP communication/UI reference для MiniMax, DeepSeek Harness, Codex и Gemini; SQLite mailbox переживает перезапуск. Loopback по умолчанию без auth, DB failure снижает режим до memory-only с предупреждением; для нас storage failure должен быть видимым и блокировать подтверждение сохранения. |
| [open-agent-bridge, исторический main snapshot](https://github.com/kevinArgueta96/open-agent-bridge/tree/391f605b65b7b85128621c1c7be55178cea59390) | Сохраняет прежние выводы только для той ревизии. Проверенная актуальная default branch `production` закреплена отдельно в `23; текущий security/Windows вывод берётся из неё. |
| [MemoryLedger admission](https://github.com/JiaXtian/MemoryLedger/blob/efac213747e5da27e70d77d08b7a31053900b6fe/src/memoryledger/policy.py#L109-L170) и [security tests](https://github.com/JiaXtian/MemoryLedger/blob/efac213747e5da27e70d77d08b7a31053900b6fe/tests/test_transactions.py#L263-L378) | Provenance, чувствительность, конфликты, quarantined tainted content и история исправлений; проект Alpha, scoring не переносить вслепую. |
| [agent-memory-lab bitemporal](https://github.com/agent-memory-lab/agent-memory/blob/2e9abd7a6dcf87e72f072058cf376cbb1afcc675/docs/BITEMPORAL_MEMORY.md#L3-L24) и [admission tests](https://github.com/agent-memory-lab/agent-memory/blob/2e9abd7a6dcf87e72f072058cf376cbb1afcc675/tests/test_admission_policy.py#L36-L81) | Хранить когда факт действовал и когда система его узнала; цитата даёт источник, но не доказывает истинность. Windows в pin не проверен. |
| [ai-crew-sync task claims](https://github.com/joaquinbejar/ai-crew-sync/blob/096611947e936565992335f38cd14cfe009b90fe/src/store/tasks.rs#L730-L778) и [inbox recovery](https://github.com/joaquinbejar/ai-crew-sync/blob/096611947e936565992335f38cd14cfe009b90fe/src/store/inbox.rs#L728-L841) | Идеи для будущего server-tier: ACL, atomic claim, durable receipts; требует сетевого PostgreSQL и Windows hooks/wake ограничены. |
| [Moo Tasks goal metrics](https://github.com/shekarsiri/moo-tasks/blob/55d5ab1e080e7f0af511b8cb908c20721460768a/src/services/goal-service.ts#L128-L177) и [acceptance checks](https://github.com/shekarsiri/moo-tasks/blob/55d5ab1e080e7f0af511b8cb908c20721460768a/src/services/verification-service.ts#L53-L128) | Acceptance checklist и возобновление полезны; процент — количество закрытых задач, не взвешенное покрытие, ETA не подтверждён. |
| [mnemos local retrieval/eval](https://github.com/arhuman/mnemos/blob/6d52edc589336ff375221815a4915bfccd52c7a8/README.md#L278-L314) | File-first corpus, FTS5, ссылки на file/section/line и retrieval eval; Windows/path confinement не проверены. |

| [Co-Messi/agent-peers-mcp](https://github.com/Co-Messi/agent-peers-mcp/blob/dc81db4dbe9b3ddb97d3ba64fd24d5b743ef868b/broker.ts#L632-L713) и [lease/ACK tests](https://github.com/Co-Messi/agent-peers-mcp/blob/dc81db4dbe9b3ddb97d3ba64fd24d5b743ef868b/tests/broker.test.ts#L520-L600) | Durable inbox, ограниченная lease, ACK адресатом/сессией, retry и idempotency. | Windows не подтверждён; POSIX permission checks не заменяют Windows ACL. Это идея протокола. |
| **HakAl/agent-comms**, [scope/dispatch/trust](https://github.com/HakAl/agent-comms/blob/b002a653aa66af4eec145693961baf41dd48fa63/README.md#L194-L236) | Bounded supervisor, dead-letter queue, runtime certification; неподдержанные тесты отображаются как SKIP, не PASS. | Claude/Codex и один workstation; actor-id — доверие к процессу, не auth; GPL-3.0; Windows не сертифицирован. |
| **ArkaAiAdmin/Agentic-Memory**, [Markdown/SQLite](https://github.com/ArkaAiAdmin/Agentic-Memory/blob/3bc57e41318c3937cd8e101d6b21ac6888bde29e/README.md#L18-L36), [configurable path](https://github.com/ArkaAiAdmin/Agentic-Memory/blob/3bc57e41318c3937cd8e101d6b21ac6888bde29e/infra/memory_config.py#L41-L89) | Markdown canon, rebuildable SQLite/FTS/graph, configurable root. | Optional LLM egress exists; README «no cloud» недостаточен. Injection scanner heuristic, не admission control. |
### 22.1. Синтез

Разделить: (1) каноническая общая БЗ с provenance, scope, valid/observed time и admission; (2) проектный snapshot/подвыборка с hash и явной синхронизацией; (3) пересоздаваемый индекс; (4) отдельная локальная operational SQLite для messages/tasks/events; (5) versioned provider adapters с реальными capability claims; (6) task ledger с lease и монотонным fencing generation; (7) UI с различением queued, delivered, presented, acknowledged, completed и доказательными статусами.

Прогресс вычислять из принятого взвешенного набора acceptance criteria, ETA — калиброванный диапазон или UNKNOWN. Storage failure не должен отображаться как success. Message/task payload — недоверенные данные. Сеть, исполнение, запись, изменение канона, публикация и egress имеют отдельные capabilities/gates.

Для local MVP нужны requirements/acceptance matrix по data-root+backup, admission/ACL, inbox/outbox, claim/fencing/recovery, progress/ETA, adapters и Windows lifecycle. Multi-PC — отдельный server phase. Никакой код/зависимость не выбраны; upstream tests, полный security/license audit, Windows E2E и внешний межпроизводительский review не выполнялись.

## 23. Delta source/test review: open-agent-bridge default branch (2026-11-16)

**Идентичность и pin.** `git ls-remote --symref` подтвердил `HEAD → refs/heads/production` на `c117ae93a8d3a86633fb2fd6d8f3365d44463ac8`; tree `945c47f0cbe27f11f7594a668a1a94fa41c3a989`. Это уточняет `22`: прежний `391f605…` — исторический снимок другой ветки, а не актуальная оценка default branch. Просмотрены pinned README, серверные маршруты/WebSocket, SQLite channel store, Antigravity LS adapter, package/lock, CI и относящиеся identity/ACK tests. Источники: [README и Antigravity adapter](https://github.com/kevinArgueta96/open-agent-bridge/blob/c117ae93a8d3a86633fb2fd6d8f3365d44463ac8/README.md#L425-L449), [server CORS](https://github.com/kevinArgueta96/open-agent-bridge/blob/c117ae93a8d3a86633fb2fd6d8f3365d44463ac8/src/registry/server.ts#L60-L69), [message/ACK/read routes](https://github.com/kevinArgueta96/open-agent-bridge/blob/c117ae93a8d3a86633fb2fd6d8f3365d44463ac8/src/registry/server.ts#L280-L376), [WebSocket identity/broadcast](https://github.com/kevinArgueta96/open-agent-bridge/blob/c117ae93a8d3a86633fb2fd6d8f3365d44463ac8/src/registry/server.ts#L517-L572), [SQLite store](https://github.com/kevinArgueta96/open-agent-bridge/blob/c117ae93a8d3a86633fb2fd6d8f3365d44463ac8/src/registry/channel-store.ts#L13-L92), [identity tests](https://github.com/kevinArgueta96/open-agent-bridge/blob/c117ae93a8d3a86633fb2fd6d8f3365d44463ac8/src/__tests__/identity-scoping.test.ts#L9-L72), [Antigravity LS port discovery](https://github.com/kevinArgueta96/open-agent-bridge/blob/c117ae93a8d3a86633fb2fd6d8f3365d44463ac8/src/client/antigravity-ls-client.ts#L139-L175), [CI](https://github.com/kevinArgueta96/open-agent-bridge/blob/c117ae93a8d3a86633fb2fd6d8f3365d44463ac8/.github/workflows/ci.yml#L1-L34).

### 23.1. Что действительно полезно как идея

- Provider-specific adapters дают разным клиентам отдельный путь доставки и учитывают особенности сессии. Для Antigravity `attach` передаёт адрес LS, CSRF token и активный conversation в адаптер; `SendUserCascadeMessage` с `WHEN_IDLE` может поставить сообщение в активную сессию, не обрывая выполняющийся ход. Это хороший источник требований к capability-профилю адаптера: способ пробуждения, необходимость открытой сессии/attach, разрешение пользователя, ограничения и подтверждённое состояние доставки.
- Durable mailbox на SQLite с WAL, busy timeout, идемпотентностью сообщений и ограничением хранения показывает полезные механизмы очереди для одного пользовательского компьютера. Его следует считать отдельным операционным состоянием, не канонической базой знаний.
- Связка SessionStart/Stop hook + MCP adapter — полезная гипотеза для UX: сообщение может дождаться ближайшей точки, где клиент разрешает запуск действия. README заявляет двунаправленную live-проверку пяти клиентов, но этот обзор её не повторял; исходный код и unit tests не заменяют E2E реального установленного приложения.

### 23.2. Ограничения и контрсвидетельства

- **Security boundary не подтверждена.** Сервер слушает `localhost`, однако просмотренные REST routes не имеют auth/authorization middleware; CORS выставляет `Access-Control-Allow-Origin: *`. WebSocket принимает соединение без проверки личности и рассылает snapshot/events всем подключённым; `identify` принимает присланный клиентом `agentId`. Это ограничивает риск локальным контуром, но не делает endpoint доверенным между локальными процессами и не подходит как готовая multi-user ACL-модель.
- **Identity namespace — фильтр клиента, не серверная изоляция.** Поле `identity` принимается из тела сообщения; API чтения возвращает conversations без проверки namespace. `identity-scoping.test.ts` тестирует функцию клиентского профиля на синтетических объектах, а не авторизацию HTTP/WS. Поэтому документационное утверждение «hard wall» нельзя переносить в нашу модель угроз.
- **ACK не подтверждает подлинность автора.** `/channel/acks` проверяет наличие полей, затем сохраняет переданные `actorId`, `actorType` и state. Связи между authenticated principal, сообщением и разрешённым переходом состояния в этом маршруте не видно. При открытом локальном API это не годится как доказательство, что агент действительно принял/выполнил задачу.
- **Восстановление SQLite предпочитает доступность сохранности.** Если файл БД удалён/перемещён и запись получает readonly error, store открывает новую БД и повторяет операцию; комментарий прямо отмечает потерю прежней истории. Для нашего контура подтверждение сохранения должно отличать «новая запись принята» от «предыдущая история восстановлена», а восстановление требовать backup/receipt.
- **Путь данных и Windows переносимость требуют проверки.** Default DB лежит в `homedir/.open-agent-bridge/registry.sqlite`; `RegistryServer` создаёт `ChannelStore()` без пользовательского data-root. Port fallback для Antigravity использует Linux-команду `ss`; CI запускается только на `ubuntu-latest`, а build scripts содержат POSIX-команды. Windows-сценарий, файловые ACL и установленный Antigravity E2E этой ревизией не подтверждены.
- `identity-scoping` не моделирует злоумышленника с доступом к локальному API; тесты persistence не подтверждают многопользовательскую изоляцию и disaster recovery. Upstream tests/build не запускались. Лицензия корневого `LICENSE` — MIT; это фиксируется как метаданные, а не разрешение брать код.

### 23.3. Чистовой вывод для нашего проекта

`open-agent-bridge` — **LAB / TRANSFORM_SECURITY**, не кандидат на прямое подключение или копирование. Берём только clean-room идеи: версионированные provider adapters с capability matrix; durable inbox/outbox отдельно от канонической БЗ; точные статусы `queued → delivered → presented → acknowledged → completed/failed`; явный attach/approval для wake, когда этого требует провайдер; idempotency и retry с доказуемым receipt.

Для нашей реализации потребуются серверная проверка identity/project/task ACL на чтении, записи, подписке и ACK; проверяемый actor и допустимые переходы state machine; безопасный local IPC/auth, ограниченный origin, schema/size/rate limits; настраиваемый переносимый data-root с backup/restore и fail-closed при потере истории; Windows CI и E2E каждого заявленного клиента. Входящее содержимое агента остаётся недоверенными данными, даже если транспорт сообщил `acknowledged`.

Код, пакет или зависимость не выбраны. Новых требований в спецификацию не добавлено, owner-admission не запрашивался, реализация не начиналась. Это точечный pinned static source/test review; runtime, full security audit, issue/PR history, dependency/advisory audit и Windows E2E не выполнялись.

## 24. GitHub source/test pass: память, durable queue и адаптеры агентов (2026-11-16)

### 24.1. Метод и закреплённые источники

Текущие default refs проверены через read-only git ls-remote --symref. Для выбора использованы GitHub views по commit-pinned URL и выборочные тесты. Два внутренних Codex subagents просмотрели разные пары проектов; это peer review одного производителя, а не DeepSeek/Antigravity или независимое межпроизводительское заключение.

| Кандидат и pin | Изученные доказательства | Применимость |
|---|---|---|
| LOCI — arko-sanyal/loci-coordination-bus; commit a4870aa798f78722fdb508f10bf98a15ec89eb9e; tree bf4a021e99e74f258c6935319841b92c6ae21f8b | [Event envelope/scope/idempotency](https://github.com/arko-sanyal/loci-coordination-bus/blob/a4870aa798f78722fdb508f10bf98a15ec89eb9e/coordination_bus/bus.py#L86-L143), [sender/replay/sequence verification](https://github.com/arko-sanyal/loci-coordination-bus/blob/a4870aa798f78722fdb508f10bf98a15ec89eb9e/coordination_bus/bus.py#L212-L246), [tamper/replay/scope tests](https://github.com/arko-sanyal/loci-coordination-bus/blob/a4870aa798f78722fdb508f10bf98a15ec89eb9e/tests/test_bus.py#L21-L45) | Event contract с project, sender, recipient, operation, base commit, allowed paths, payload, sequence, idempotency и expiry. |
| MARM — Lyellr88/marm-memory; commit a8534dd2a3692947ba3089f810ff335f3f765f53; tree 3651ca169c9e2df863bf7248c51b4efd39b78f5f | [Durable claim/lease queue](https://github.com/Lyellr88/marm-memory/blob/a8534dd2a3692947ba3089f810ff335f3f765f53/marm-mcp-server/marm_mcp_server/core/concept_queue.py#L33-L116), [lease token/content hash completion](https://github.com/Lyellr88/marm-memory/blob/a8534dd2a3692947ba3089f810ff335f3f765f53/marm-mcp-server/marm_mcp_server/core/concept_queue.py#L174-L186), [rollback test](https://github.com/Lyellr88/marm-memory/blob/a8534dd2a3692947ba3089f810ff335f3f765f53/marm-mcp-server/tests/test_concept_queue.py#L48-L62), [write queue](https://github.com/Lyellr88/marm-memory/blob/a8534dd2a3692947ba3089f810ff335f3f765f53/marm-mcp-server/marm_mcp_server/core/write_queue.py#L10-L83) | Durable SQLite queue, serialized claim, lease token, content hash, retry/backoff и parking. |
| Agent Orchestrator — Augani/agent-orchestrator; commit 8d9b897c49500e8e1b54ec8028352544db95618d; tree 9b2d2958f123f1bfcf8ab224f2daffb40b68488e | [Provider CLI argv](https://github.com/Augani/agent-orchestrator/blob/8d9b897c49500e8e1b54ec8028352544db95618d/plugins/agent-orchestrator/scripts/cli_agent_job.py#L324-L367), [scope drift guard/test](https://github.com/Augani/agent-orchestrator/blob/8d9b897c49500e8e1b54ec8028352544db95618d/tests/test_cli_agent_job.py#L1496-L1562), [dashboard auth test](https://github.com/Augani/agent-orchestrator/blob/8d9b897c49500e8e1b54ec8028352544db95618d/tests/test_dashboard_server.py#L319-L350) | Versioned CLI adapters, narrow context channel, separate workspace/review lifecycle and loopback UI ideas. |
| memk — Odd-C/memk; commit 04ca4189005de048e161457e241ecbef342ac48a; tree 23f0f8d99729e62eb3faaa03b286309497593be1 | [Evidence-based admission](https://github.com/Odd-C/memk/blob/04ca4189005de048e161457e241ecbef342ac48a/memk/admission.py#L112-L155), [read/write scope](https://github.com/Odd-C/memk/blob/04ca4189005de048e161457e241ecbef342ac48a/memk/scope.py#L15-L69), [integrity/admission self-test](https://github.com/Odd-C/memk/blob/04ca4189005de048e161457e241ecbef342ac48a/memk/selftest.py#L63-L100) | Provenance → candidate → evidence → review/admission; separate drafts from canonical retrieval. |

### 24.2. Контрпроверка и ограничения

- LOCI generic events() не перепроверяет подпись на чтении: тест показывает, что поддельная строка видна там и отбрасывается verified_events(). Потребитель должен использовать только проверенное чтение.
- Task row и event в LOCI фиксируются раздельными commit-операциями. Сбой может разнести представления состояния; атомарность не доказана. Claim выглядит как check-then-update без CAS/fencing, но конкурентная гонка не воспроизводилась. Завершение доверяет tests_passed=true от агента и форме SHA, а не CI receipt.
- MARM concept queue durable, но write_queue — in-process. Документация Windows описывает один HTTP-процесс на DB; это не доказательство runtime readiness.
- Agent Orchestrator проверяет scope drift после процесса, не на уровне ОС; job импортирует POSIX fcntl. Native Windows и одинаковые sandbox semantics не доказаны. Worktree не равен sandbox.
- В memk переданная role не доказывает identity процесса; Alice/Bob test не устанавливает Windows ACL/OS-user isolation. Это admission model, не coordinator и не multi-PC sync.
- Upstream tests/builds не запускались; полного security/issue/PR/dependency/advisory/license review и Windows E2E не было.

### 24.3. Чистовой синтез для нашего проекта

1. Каноническая versioned БЗ хранит уроки/решения; отдельный operational store — task/run state, inbox/outbox, events, ACK и leases. Индексы поиска/embeddings пересоздаваемы и не являются источником истины.
2. Любая новая память проходит capture с происхождением → quarantine/draft → проверку evidence, scope, актуальности и конфликтов → owner/reviewer admission. Retrieved факт показывает статус и источник.
3. Завершение доказывается coordinator receipt по task ID, точным commit/base SHA и требуемым checks. Самоотчёт агента о зелёных тестах не является evidence.
4. Claim фиксирует owner, lease expiry и монотонный fencing generation. Продление/завершение сравнивает token, generation и исходную ревизию; истёкший worker не может перезаписать актуальное состояние.
5. Task transition и outbox event коммитятся атомарно; relay использует idempotency key. UI различает queued, delivered, presented, acknowledged, accepted, rejected и failed.
6. Каждый provider adapter имеет versioned capability contract: transport/attach/wake, права, approval, состояния доставки и platform support. Неподдержанное действие остаётся ручным, а не имитируется ACK.
7. Worktree/channel задаёт организационный scope, но не изоляцию ОС; для worker нужен проверенный Windows sandbox. Меж-ПК режим требует отдельного authenticated API, конфликтной модели и восстановления. Live SQLite WAL нельзя размещать в синхронизируемой/SMB папке.
8. Панель показывает подтверждённый прогресс, пропуски и неизвестность по acceptance criteria и evidence, а не выдуманные проценты.

**Disposition:** memk/MARM — ADAPT для admission/очереди; Agent Orchestrator — ADAPT для адаптеров и review pipeline при отдельной проверке Windows; LOCI — TRANSFORM_SECURITY: берём только идеи event/authorization contract, добавив атомарный outbox, fencing и проверяемый CI receipt. Ни один не DIRECT_ADOPT. Код, prompts, схемы и зависимости не переносились.

Раздел уточняет существующий синтез; архитектура/стек не утверждены, новые требования не внесены, T-009 остаётся research, а coordinator/swarm — DRAFT/NOT READY.

## 25. Прогресс и ETA: отдельная атомарная запись (2026-11-16)

Выборочный GitHub source/test-pass по прогнозированию срока и подтверждённому прогрессу вынесен в самостоятельную draft-запись [progress-and-eta-research.md](progress-and-eta-research.md). Там закреплены pins, исходники/тесты, ограничения точности и clean-room синтез. Ключевой вывод: процент считается по неизменяемому принятому набору weighted acceptance criteria с evidence; труд и календарное ожидание разделяются; ETA остаётся диапазоном или UNKNOWN, пока локальная история не подтверждает калибровку. Требования и архитектура не утверждены.
## 26. Targeted GitHub source pass: OpenHands execution boundary (2026-11-16)

### 26.1. Закреплённая ревизия и evidence

Проверены README и выбранные файлы OpenHands Software Agent SDK на commit 5e49ddac5765f5dee428e3c9055028e829ccacfd. Tree SHA в этом проходе отдельно не получен. Upstream source читался статически по pinned URL; код, Docker-образ и тесты не запускались. Попытка найти точные тестовые пути не подтвердила их расположение, поэтому тестовое покрытие этого launcher-а не заявляется.

- [README: workspace modes и границы репозитория](https://github.com/OpenHands/software-agent-sdk/blob/5e49ddac5765f5dee428e3c9055028e829ccacfd/README.md#L173-L218) отделяет SDK/Agent Server, TypeScript client, UI и automation; рабочая среда выбирается отдельно и может быть local или ephemeral Docker/Kubernetes.
- [DockerWorkspace options и image defaults](https://github.com/OpenHands/software-agent-sdk/blob/5e49ddac5765f5dee428e3c9055028e829ccacfd/openhands-workspace/openhands/workspace/docker/workspace.py#L49-L116) задают Linux/amd64 и mutable image tag latest-python по умолчанию; forward_env включает DEBUG и два варианта session API key; volumes и optional network передаются caller-ом.
- [Сборка docker run](https://github.com/OpenHands/software-agent-sdk/blob/5e49ddac5765f5dee428e3c9055028e829ccacfd/openhands-workspace/openhands/workspace/docker/workspace.py#L199-L240) добавляет host mounts и выбранные env vars, публикует API на 127.0.0.1, а custom network применяет только если она передана. В этой команде нет явного запрета egress или настройки CPU/memory/PID quota, read-only root filesystem, capability drop и non-root user; фактические свойства image/daemon этим файлом не оценены.
- [Startup, health-check and cleanup path](https://github.com/OpenHands/software-agent-sdk/blob/5e49ddac5765f5dee428e3c9055028e829ccacfd/openhands-workspace/openhands/workspace/docker/workspace.py#L141-L152) останавливает контейнер при ошибке startup; [context exit и cleanup](https://github.com/OpenHands/software-agent-sdk/blob/5e49ddac5765f5dee428e3c9055028e829ccacfd/openhands-workspace/openhands/workspace/docker/workspace.py#L333-L369) пытаются остановить и удалить его. Detached --rm удаляет контейнер после остановки, но сам по себе не гарантирует остановку при аварийном завершении host process; это требует отдельной reconciliation-проверки.
- [Pinned workspace package metadata](https://github.com/OpenHands/software-agent-sdk/blob/5e49ddac5765f5dee428e3c9055028e829ccacfd/openhands-workspace/pyproject.toml#L243-L271) задаёт Python >=3.12 и отдельную optional dependency для Kubernetes Agent Sandbox. Это точка совместимости на pin, не рекомендация стека для нашей Windows-first portable версии.

### 26.2. Чистый синтез для нашего worker-runtime

Полезная идея — держать scheduler/ledger, agent provider adapter и execution workspace раздельными контрактами: одна и та же задача может работать с read-only local preview, выделенным task worktree или изолированным удалённым runtime. Но OpenHands implementation сама по себе не доказывает, что такой runtime безопасен для нашего профиля угроз.

Для собственного решения стоит проверить следующие acceptance cases:

1. Задача получает только свой worktree; общая/локальная БЗ, Git credentials, домашний профиль и другие проекты не монтируются внутрь по умолчанию.
2. Подключаемые mounts проходят allowlist, canonical path containment и проверку reparse points; запись за scope блокируется на уровне ОС/runtime, а не только post-run diff.
3. В sandbox передаются только явные short-lived task-scoped credentials; весь process environment не наследуется. Секреты не оказываются в argv, логах, build output или agent-visible files.
4. Image pin фиксирует digest и SBOM; mutable latest-теги не используются в воспроизводимой сборке. Egress по умолчанию запрещён либо проходит через отдельную allowlist gateway.
5. Runtime profile явно задаёт непривилегированного пользователя, filesystem mode, capabilities/devices, CPU/memory/process/time quotas и host port binding. Loopback exposure проверяется тестом с другого интерфейса/сегмента.
6. Cleanup подтверждается durable state: контейнер/VM ID, owner task/run, start/stop result, heartbeat и stale-resource reaper. Graceful close, process crash, host restart и повторный cleanup проверяются отдельно.
7. Negative tests подтверждают отсутствие чтения соседнего worktree/БЗ и записи marker-файла вне target при traversal, symlink/junction/reparse-point и timeout/crash сценариях.

**Disposition:** ADAPT для интерфейсного разделения control plane и workspace adapters; TRANSFORM_SECURITY для Docker launch contract; LAB для Windows runtime choice и host isolation. Loopback binding и явная workspace abstraction — полезные примеры; mutable image tag, неограниченный caller-supplied volume и унаследованные session keys не принимать как безопасные defaults. Не утверждается, что OpenHands в целом уязвим или что перечисленные меры отсутствуют во всех слоях: вывод ограничен выбранным pinned launcher-файлом.

Новые требования/стек не утверждены; это research candidate для будущего SECURITY/READY-TЗ. Код и зависимости не копировались.
