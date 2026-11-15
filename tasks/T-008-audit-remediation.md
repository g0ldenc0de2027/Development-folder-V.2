# T-008 — Исправления аудита и понятная передача следующему агенту

**Статус:** implementation in progress; опубликованная точка входа — remote branch `task/T-008`.
**База:** `f577dc70e58d75ab5fd61d0c2e712c27b590713a` (origin/main при старте).
**Задача:** устранить воспроизводимые дефекты аудита 2026-11-15 и оставить полный реестр остатка.
**Аудит:** `2026-11-15_Критический-аудит_Development-Folder-V2_OpenAI-Codex-GPT-6.md` в каталоге аудитов владельца; абсолютный локальный путь в публичный репозиторий не переносить.

## Зона файлов

- `.githooks/pre-push`
- `scripts/quality-gate.ps1`
- `scripts/verify-task-scope.ps1`
- `scripts/kb.ps1`
- `docs/local-knowledge.md`
- `docs/github-workflow.md`
- `docs/roadmap.md`
- `tasks/README.md`
- `tasks/T-008-audit-remediation.md`
- `README.md`
- `CHANGELOG.md`

## Изменения этой ветки

- Hook разрешает публикацию только с текущей ветки `task/T-NNN` в одноимённую remote branch; detached HEAD, tags, deletion, сторонний ref и non-fast-forward отклоняются.
- Диапазоны refs передаются одним CSV аргументом и повторно разбираются quality gate. Записи hook ограничены 20 на вызов.
- До quality gate hook вызывает scope guard. Точная зона берётся из единственной карточки `tasks/T-NNN-*.md`; dedicated linked worktree и task branch `origin/main...HEAD` проверяются с учётом rename как delete+add, дерево должно быть чистым.
- KB secret detector проверяет свободные строковые поля каталога, возвращаемые как контекст: title, sources, reviewer и evidence.
- Для известного sourceCollectionId/version канонической поставки RULES 0.2.0 проверяются все девять ожидаемых файлов. Это предотвращает случайный частичный snapshot; hashes и source ID не удостоверяют издателя.
- `context` отказывает с `KB_CONTEXT_RECORD_LIMIT`, если не может выдать весь выбранный набор; `search` сообщает totalMatches/returned/truncated. По умолчанию Limit=100, максимум 1000.
- README, changelog и руководство KB указывают на новую точку передачи и новые коды результата.

## Реестр всех замечаний из аудита

Статусы относятся к main до этой ветки, если явно не указана проверяемая ветка. `В работе` не означает, что изменение уже слито в main.

| ID | Приоритет | Статус | Решение / следующее действие |
|---|---|---|---|
| F01 | P1 | Исправление в T-008 | Scope guard проверяет committed diff от `origin/main`, task branch/worktree и clean state по scope единственной task card. Review и CI этой ветки обязательны перед merge. Guard процедурный: авторитетность scope карточки подтверждает owner review. |
| F02 | P1 | Исправление в T-008 | Все диапазоны идут одним CSV argument; quality gate валидирует каждый токен. Действующая pre-push gate должна пройти перед публикацией. |
| F03 | P1 | Исправление в T-008 | Hook отвергает detached HEAD, tags, push чужой локальной ветки и destination ref, не совпадающий с task ref. Разрешена только `task/T-NNN` в одноимённую remote ref. |
| F04 | P1 | Исправление в T-008 | Существующая ветка проходит только если remote SHA ancestor локального SHA; неизвестный объект блокирует push. |
| F05 | P1 | Исправление в T-008 | Ограниченный secret detector применяется к title, sources, review.by, review.evidence и body. Это не PII/DLP и не универсальный сканер секретов. |
| F06 | P1 | Исправление в T-008 | Для известного sourceCollectionId RULES 0.2.0 обязательны все девять файлов. Не защищает от намеренной замены lock/package и не аутентифицирует автора. |
| F07 | P1 | Принятый остаточный риск | No-App — решение владельца. Внешний GitHub App не добавлять; нужна ручная проверка diff workflow/gate на текущем head и точной SHA evidence. Owner approval технически не enforced. |
| F08 | P2 | Исправление в T-008 | Context fail-closed на ограничении числа записей; search сообщает полную метаинформацию truncation. Локальный/hosted evidence ещё надо зафиксировать. |
| F09 | P2 | Открыто | Сократить хрупкие проверки старого текста/SHA, добавить поведенческие сценарии hook/verifier. Regression suite не редактировалась в этом срезе. |
| F10 | P2 | Другая открытая ветка | PR #7/T-007 обновляет handoff и closeout T-004. Проверить свежий base/head/CI/review; не считать исправленным до merge. |
| F11 | P2 | Открыто | Определить hash-verified cache, timeout/retry и runtime matrix; один Windows run не подтверждает весь диапазон. |
| F12 | P2 | Другая открытая ветка | PR #6/T-006 обрабатывает `.vs` и tracked cache; проверить свежий diff и интеграцию после обновления base. |
| F13 | P2 | Открыто | Определить размеры уникальных Git blobs и предел push для всех ref updates; сначала утвердить метрики, проектные пороги и отрицательные сценарии. |
| F14 | P2 | Открыто | Добавить redacted identity preflight и проверку author/committer после GitHub squash; не печатать адреса и не переписывать историю автоматически. |
| F15 | P2 | Открыто | Отдельно спроектировать версионированные observedAt/scope/recheckAfter/revocation поля; schema 1 молча не мигрировать. |
| F16 | P2 | Открыто | Согласовать backup contract и выполнить restore drill в staging, включая ignored inbox и отсутствие старых полномочий. |
| F17 | P2 | Открыто | После READY подготовить синтетический проект и провести pilot от bootstrap до handoff/recovery. |
| F18 | P3 | Частично | Руководство дополнено новыми error codes/context contract. Полный PowerShell comment-based help и симметричные RU/EN сценарии остаются открыты. |
| F19 | P3 | Открыто | Согласовать смысл marker project_id и catalog projectId до межполевой проверки. |
| F20 | P3 | Частично | Карточка фиксирует очередь аудита; единый task index и номера следующих задач синхронизировать после PR #5–#7. |

## Передача следующему агенту

Начинать с этой карточки и свежего состояния `origin/main`; не считать статус ветки доказательством merge. Перед работой прочитать `AGENTS.md`, `README.md`, `docs/handoff.md`, `rules/RULES.md`, `knowledge/README.md` и применимые модули. Проверить branch, HEAD, remotes, worktree и `git status`. Реализация находится в отдельном worktree `.worktrees/T-008`, branch `task/T-008`.

Перед публикацией выполнить предписанный `docs/development.md` quality gate: hook запускает scope guard и полный quality gate, а точное состояние worktree и branch проверяет сам. После публикации сверить pushed HEAD, открыть/обновить reviewable PR по `docs/github-workflow.md`, дождаться CI на текущей паре head/base и проверить review именно этого head. Обновлять этот реестр только с актуальными evidence; записывать локальный PASS, hosted CI, review, merge SHA и остаточный риск отдельно.

Открытые PR при старте T-008: #5/T-005 (черновик требований прогресса), #6/T-006 (IDE cache), #7/T-007 (closeout T-004). Их worktrees — отдельные write-set; не изменять и не удалять их. При изменении base обновить ветку по утверждённому workflow и заново записать SHA evidence.

## Проверки

Регрессионные suites и quality gate не запускались в процессе подготовки этой ветки. До merge должны пройти команды, предписанные `docs/development.md`, на финальном HEAD; результаты фиксируются ниже.

- Локальный quality gate: PENDING.
- Live settings verifier: PENDING / конфигурация в этой задаче не менялась.
- Hosted `quality-gate`: PENDING.
- Независимое review exact head: PENDING.
- Scope/чистота worktree перед push: PENDING.

## Итоговые SHA и приёмка

- Base SHA: `f577dc70e58d75ab5fd61d0c2e712c27b590713a`.
- Branch head: заполнить после commit/push.
- PR head/base/merge-result: заполнить из актуального PR.
- Merge SHA: оставить пустым до фактического merge.
