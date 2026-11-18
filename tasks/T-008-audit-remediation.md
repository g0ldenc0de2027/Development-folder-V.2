# T-008 — Исправления аудита и понятная передача следующему агенту

**Evidence checkpoint (2026-11-15):** Перед этой записью PR #8 был OPEN/Draft, head 337de0d48f8edfeb521167270306516ac3cdb476, base f577dc70e58d75ab5fd61d0c2e712c27b590713a. Hosted quality-gate run 43753125152 SUCCESS на merge-result 184666c6328cd68da399746804217cf30b91bb0c с точными родителями base/head; локальный и pre-push gate прошли. На том head GitHub-native reviews/comments отсутствовали; независимый review PENDING. Эта карточка — контрольная точка: актуальный head/base/checks после её изменения следует брать из live PR #8.
**PR:** https://github.com/g0ldenc0de2027/Development-folder-V.2/pull/8
**База при старте:** `f577dc70e58d75ab5fd61d0c2e712c27b590713a` (origin/main).
**Head при первой публикации:** `e4d580304333d15b80b7327bc559ab309ec12f56`. После обновления этой карточки head изменится; всегда сверяйте live head/base в PR #8.
**Задача:** устранить воспроизводимые дефекты аудита 2026-11-15 и оставить полный реестр остатка.
**Аудит:** `2026-11-15_Критический-аудит_Development-Folder-V2_OpenAI-Codex-GPT-6.md` в каталоге аудитов владельца; абсолютный локальный путь в публичный репозиторий не переносить.

## Зона файлов

- `.gitignore`
- `.github/workflows/quality-gate.yml`
- `.githooks/pre-push`
- `AGENTS.md`
- `scripts/quality-gate.ps1`
- `config/runtime-support.json`
- `scripts/verify-runtime.ps1`
- `scripts/verify-task-scope.ps1`
- `scripts/kb.ps1`
- `knowledge/catalog.json`
- `knowledge/УРОКИ.md`
- `knowledge/records/task-isolation.md`
- `docs/development.md`
- `docs/local-knowledge.md`
- `docs/github-workflow.md`
- `docs/roadmap.md`
- `spec/ТЗ.md`
- `spec/СОСТОЯНИЕ.md`
- `spec/local-knowledge.md`
- `tests/quality-gate-regressions.ps1`
- `tests/task-scope-regressions.ps1`
- `tasks/README.md`
- `tasks/T-008-audit-remediation.md`
- `README.md`
- `CHANGELOG.md`

## Изменения этой ветки

- Дополнение по аудиту 2026-11-18: `.work/` и `.manus/` добавлены в `.gitignore`; точные scratch-сегменты исключены из рекурсивных syntax/privacy/hygiene обходов, но Gitleaks остаётся на полном дереве.
- Формат веток унифицирован: `task/T-NNN` и `task/T-NNN-<lowercase-hyphenated-slug>`; scope guard принимает только валидный ID и slug, pre-push передаёт задаче первые пять символов ID. Фикстуры проверяют допустимый и недопустимый формат.
- Урок изоляции задач усилен по повторению; его catalog SHA обновлён и проверяется `kb.ps1 check`.
- Git-fixture suite и quality gate отказываются от TempRoot внутри любого Git-репозитория (worktree или bare) до записи; quality gate принимает явный TemporaryRoot для проверки границы без изменения TEMP процесса. Fixtures запускаются только из внешнего временного корня; suite сравнивает HEAD, refs, index и status источника до и после.
- Матрица среды вынесена в config/runtime-support.json: проверенная Windows 11 x64 GA 26H2/build 26300 на ge_release; PowerShell 7.6 LTS не ниже 7.6.10; CI — Windows Server 2025 base build 26100. Hosted runner фактически запускал 7.6.9, поэтому workflow каждый run скачивает официальный PowerShell 7.6.10 win-x64 ZIP, проверяет pinned SHA-256, версию и CI baseline, затем запускает gate явным бинарником. quality-gate, scope guard и KB CLI используют общий fail-closed runtime verifier.
- Hook разрешает публикацию только с текущей ветки `task/T-NNN` либо валидной `task/T-NNN-<lowercase-hyphenated-slug>` в одноимённую remote branch; detached HEAD, tags, deletion, сторонний ref и non-fast-forward отклоняются.
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
| F03 | P1 | Исправление в T-008 | Hook отвергает detached HEAD, tags, push чужой локальной ветки и destination ref, не совпадающий с task ref. Разрешены `task/T-NNN` и валидный `task/T-NNN-<lowercase-hyphenated-slug>` в одноимённую remote ref; scope guard подтверждает точный ID. |
| F04 | P1 | Исправление в T-008 | Существующая ветка проходит только если remote SHA ancestor локального SHA; неизвестный объект блокирует push. |
| F05 | P1 | Исправление в T-008 | Ограниченный secret detector применяется к title, sources, review.by, review.evidence и body. Это не PII/DLP и не универсальный сканер секретов. |
| F06 | P1 | Исправление в T-008 | Для известного sourceCollectionId RULES 0.2.0 обязательны все девять файлов. Не защищает от намеренной замены lock/package и не аутентифицирует автора. |
| F07 | P1 | Принятый остаточный риск | No-App — решение владельца. Внешний GitHub App не добавлять; нужна ручная проверка diff workflow/gate на текущем head и точной SHA evidence. Owner approval технически не enforced. |
| F08 | P2 | Исправление в T-008 | Context fail-closed на ограничении числа записей; search сообщает полную метаинформацию truncation. Локальный/hosted evidence ещё надо зафиксировать. |
| F09 | P2 | Частично | В quality gate добавлены поведенческие сценарии scope verifier: несколько изменённых путей, Unicode path, dirty worktree, отказ на посторонний файл и изоляция унаследованного Git hook environment с проверкой неизменности HEAD исходного репозитория. Поведенческие сценарии самого pre-push hook и хрупкие старые текст/SHA проверки остаются открыты. |
| F10 | P2 | Другая открытая ветка | PR #7/T-007 обновляет handoff и closeout T-004. Проверить свежий base/head/CI/review; не считать исправленным до merge. |
| F11 | P1 | Реализовано и проверено на 337de0d | Host matrix ограничена подтверждённой Windows 11 x64 GA 26H2/build 26300/ge_release; неподтверждённые и preview builds блокируются. CI отделён: Windows Server 2025 base build 26100; встроенный runner pwsh может быть старее, поэтому официальный PowerShell 7.6.10 win-x64 архив загружается на каждом hosted run, SHA-256 сверяется с manifest, заданы timeout и 3 попытки. Локальный/hosted gate и run #43753125152 прошли. Кэш архива не включён: текущая allowlist разрешает только actions/checkout; добавление cache action требует отдельного изменения политики. Timeout/retry/cache загрузок actionlint/Gitleaks в локальном gate остаются открытыми. |
| F12 | P2 | Другая открытая ветка | PR #6/T-006 обрабатывает `.vs` и tracked cache; проверить свежий diff и интеграцию после обновления base. |
| F13 | P2 | Открыто | Определить размеры уникальных Git blobs и предел push для всех ref updates; сначала утвердить метрики, проектные пороги и отрицательные сценарии. |
| F14 | P2 | Открыто | Добавить redacted identity preflight и проверку author/committer после GitHub squash; не печатать адреса и не переписывать историю автоматически. |
| F15 | P2 | Открыто | Отдельно спроектировать версионированные observedAt/scope/recheckAfter/revocation поля; schema 1 молча не мигрировать. |
| F16 | P2 | Открыто | Согласовать backup contract и выполнить restore drill в staging, включая ignored inbox и отсутствие старых полномочий. |
| F17 | P2 | Открыто | После READY подготовить синтетический проект и провести pilot от bootstrap до handoff/recovery. |
| F18 | P3 | Частично | Руководство дополнено новыми error codes/context contract. Полный PowerShell comment-based help и симметричные RU/EN сценарии остаются открыты. |
| F19 | P3 | Открыто | Согласовать смысл marker project_id и catalog projectId до межполевой проверки. |
| F20 | P3 | Частично | Карточка фиксирует очередь аудита; единый task index и номера следующих задач синхронизировать после PR #5–#7. |
| V2-02 | P2 | Исправляется в T-008 | Локальные `.work/` и `.manus/` игнорируются Git и исключаются только из syntax/privacy/hygiene обходов; Gitleaks сохраняет полный охват; поведение проверяется path-boundary regression. |
| V2-19 | P2 | Исправляется в T-008 | Hook и scope guard поддерживают один документированный формат task ID и lowercase slug; поведение закреплено fixture для принятого и отклонённого имени. |

## Передача следующему агенту

Начинать с этой карточки и свежего состояния `origin/main`; не считать статус ветки доказательством merge. Перед работой прочитать `AGENTS.md`, `README.md`, `docs/handoff.md`, `rules/RULES.md`, `knowledge/README.md` и применимые модули. Проверить branch, HEAD, remotes, worktree и `git status`. Реализация находится в отдельном worktree `.worktrees/T-008`, branch `task/T-008`.

Перед публикацией выполнить предписанный `docs/development.md` quality gate: hook запускает scope guard и полный quality gate, а точное состояние worktree и branch проверяет сам. После публикации сверить pushed HEAD, открыть/обновить reviewable PR по `docs/github-workflow.md`, дождаться CI на текущей паре head/base и проверить review именно этого head. Обновлять этот реестр только с актуальными evidence; записывать локальный PASS, hosted CI, review, merge SHA и остаточный риск отдельно.

Открытые PR при старте T-008: #5/T-005 (черновик требований прогресса), #6/T-006 (IDE cache), #7/T-007 (closeout T-004). Их worktrees — отдельные write-set; не изменять и не удалять их. При изменении base обновить ветку по утверждённому workflow и заново записать SHA evidence.

## Проверки

Последний проверенный кодовый head перед ledger-only обновлением: 337de0d48f8edfeb521167270306516ac3cdb476; base f577dc70e58d75ab5fd61d0c2e712c27b590713a:
- Task-scope pre-push: PASS, 21 changed paths / 21 allowed paths; branch task/T-008, worktree clean.
- Локальный pwsh -NoLogo -NoProfile -File scripts/quality-gate.ps1 -BaseRef origin/main: PASS; 44 KB-регрессии, 3 task-scope регрессии, actionlint, Gitleaks working tree/history/push range.
- Pre-push gate перед публикацией: PASS на commit 337de0d; проверил scope, полный quality gate и incoming range.
- Hosted quality-gate: run [#43753125152](https://github.com/g0ldenc0de2027/Development-folder-V.2/actions/runs/43753125152) SUCCESS (pull_request); checkout/test merge-result 184666c6328cd68da399746804217cf30b91bb0c, родители — точные base/head выше.
- В hosted log подтверждено: bootstrap PowerShell 7.6.9, официальный архив PowerShell 7.6.10 скачан и SHA-256 проверен; CI runtime и quality gate работали под 7.6.10.
- Live PR #8: OPEN, Draft; GitHub-native reviews/comments отсутствуют на текущем head. Независимое review текущего head PENDING; merge не разрешён до его получения и принятия.
- Stack build/dependency audit: NOT COVERED; эталон не содержит выбранного прикладного стека.

Результаты до 337de0d и hosted run #43753125152 — исторические и не доказывают проверки последующих ревизий.

### Дополнение по изоляции Git-fixtures (2026-11-18)

- Проверена кандидатная рабочая копия `task/T-008` с исходным HEAD `7fc1d81a89abda42e067cb24da0bdf2ee3018a59` и 14 изменёнными путями; индекс до проверки был пуст.
- После исправления защиты временных каталогов полный локальный `quality-gate.ps1 -BaseRef origin/main -TemporaryRoot <внешний-каталог>` завершился `QUALITY-GATE=PASS`: KB-регрессии 44/44, task-scope регрессии 5/5, privacy/hygiene, actionlint и Gitleaks прошли. Gitleaks проверил рабочее дерево, историю и push range (92 достижимых коммита).
- `git diff --check`, PowerShell AST-проверка и сверка SHA-256 lesson с `knowledge/catalog.json` прошли. Source HEAD, refs, index и status остались неизменны после fixture suites; внешний временный каталог очищен.
- Это только локальная проверка кандидатной рабочей копии. Для нового коммита hosted CI и независимое review ещё не получены; исторический run выше их не заменяет.

## Итоговые SHA и приёмка

- Base SHA PR #8: f577dc70e58d75ab5fd61d0c2e712c27b590713a.
- Последний проверенный кодовый head перед обновлением этой карточки: 337de0d48f8edfeb521167270306516ac3cdb476.
- Hosted CI merge-result: 184666c6328cd68da399746804217cf30b91bb0c; parents совпадают с base и head.
- Hosted run: 43753125152, SUCCESS; прямой URL указан в разделе «Проверки».
- Карточка обновлена после указанного code head и сама продвигает PR head; live PR #8 — источник текущего статуса CI/review. PR остаётся OPEN/Draft; independent review и merge SHA: PENDING.
