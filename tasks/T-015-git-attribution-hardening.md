# T-015 — Изоляция и проверка Git-атрибуции

- **Статус:** in_progress
- **Основание:** владелец поручил устранить повторяемые ошибки Git attribution и добавить безопасную автокоррекцию.
- **База:** `f577dc70e58d75ab5fd61d0c2e712c27b590713a` — live `origin/main` при создании worktree.
- **Ветка/worktree:** `task/T-015-git-attribution` / `.worktrees/T-015`.
- **Исторические исходные факты при создании задачи:** common .git/config задавал user.name=Scope Fixture; worktree-specific identity отсутствовала; extensions.worktreeConfig=true. Старый configure-local.ps1 использовал git config --local, изменяя общий конфиг. PR #9/T-010 содержит опубликованные commits с fixture attribution; T-013 имеет два локальных fixture-attributed commits без обнаруженного remote branch. Два последних опубликованных T-011 commits имеют ID-based noreply association, но некорректный display name.

## Цель

Перестать создавать commits с placeholder, чужой или некорректно интерполированной личностью; настраивать identity только в целевом linked worktree после подтверждения GitHub account. Не переписывать существующую историю и не выдавать автоматическую настройку за исправление уже созданных commits.

## Зона файлов

- `AGENTS.md`
- `config/github/repository.json`
- `scripts/github/configure-local.ps1`
- `config/git-empty.config`
- `scripts/verify-git-hook-context.ps1`
- `scripts/verify-git-identity.ps1`
- `scripts/lib/GitIdentity.psm1`
- .githooks/pre-commit
- .githooks/pre-push
- `scripts/quality-gate.ps1`
- `tests/git-identity-regressions.ps1`
- `docs/git-identity.md`
- `docs/development.md`
- `knowledge/УРОКИ.md`
- `knowledge/records/git-attribution-worktrees.md`
- `knowledge/catalog.json`
- `tasks/T-015-git-attribution-hardening.md`
- `docs/handoff.md`
- `scripts/task-worktree-audit.ps1`
- `tests/task-worktree-regressions.ps1`
- `config/worktree-quarantine.json`
- `tasks/README.md`
- `docs/github-workflow.md`
- `knowledge/records/task-worktree-recovery.md`
- `knowledge/УРОКИ.md`

## Приёмка

1. GitHub author profile фиксируется открытыми полями `login` и `userId`; секреты и email не записываются в tracked files.
2. Настройка сверяет live gh api user с repo policy, пишет user.name, ID-based noreply email и user.useConfigOnly только через git config --worktree. Common user.name/email сохраняются; стандартные hooks/fetch/pull/push параметры настраиваются отдельно.
3. Инициализация проверяет .git marker и регистрацию worktree, включает extensions.worktreeConfig, переносит core.bare=true из общего конфига в config.worktree bare admin root и задаёт core.bare=false выбранной worktree. Неоднозначный common core.worktree и конфликтующие значения завершаются fail-closed; после настройки проверяются root и git status.
4. pre-commit проверяет effective default identity и безопасно исправляет обычный drift после проверки account. Не утверждай, что `git commit --author` всегда блокируется до создания commit: pre-push проверяет фактические author/committer metadata всех outgoing commits до отправки. Неверную историю он не исправляет автоматически.
5. Pre-push передаёт несколько обновляемых ref ranges одним однозначным параметром; verifier и quality gate разбирают каждую строку отдельно.
6. 27 identity-regression cases покрывают common placeholder, изоляцию, account mismatch, author/committer environment/config injection, разрешённые identity, неверные author/committer name/email, multi-ref hook execution, автокоррекцию, безопасную bare-admin migration, будущий worktree bootstrap, неоднозначный common core.worktree, нормализацию регистра login, поиск shell root при вложенном `git.exe` и проверку hook `GIT_EDITOR`/`GIT_EXEC_PATH`. Регрессия quality gate требует отключения pager во всех его прямых Git-вызовах и diff-проверках.
7. Полный `quality-gate.ps1 -BaseRef origin/main`, регрессии и `git diff --check` проходят. Успехи привязаны к точному HEAD/содержимому.
8. Правила документируют безопасное автолечение только до commit при подтверждённой identity; после commit — только отдельная recovery-задача и новая история, без amend/rebase/filter/rewrite. Опубликованные T-010/T-011/T-013 refs не изменяются.

9. Перед началом задачи глобальный audit обнаруживает dirty tracked/untracked worktree, missing/prunable worktree, task ID mismatch, unregistered физический каталог `.worktrees/T-NNN` и ignored .vs. Любой непроверенный путь блокирует commit/publish; данные не удаляются.
10. pre-commit разрешает только staged изменения текущего worktree и проверяет все соседние worktree; pre-push требует clean status и повторяет глобальную проверку.
11. После архивации T-013 production registry quarantine пуст; ни одно dirty worktree не получает исключение. Regression fixtures отдельно подтверждают точную проверку Format 1 и блокировку изменённого fingerprint.
12. Quality gate запускает synthetic regressions для bare admin, staged/unstaged/untracked, ignored .vs, точного synthetic quarantine, hook environment isolation и hooks. Audit subprocesses удаляют и восстанавливают унаследованные `GIT_*`, отключают system/global config, используют tracked empty global config, запрещают pager и optional locks и явно отключают repo-local `core.fsmonitor`, чтобы read-only audit не запускал произвольный watcher из проекта.
13. Документация задаёт обязательный audit перед ручным созданием task worktree и handoff для interruption; ограничение local hooks указано явно.
14. Семь raw-файлов T-013 архивированы и повторно проверены: Development-Folder-V2_T-013-source-snapshot-2026-11-18_91bb56d5.zip, archive SHA-256 734f27b8027e4a0aaa2f1aeca5868ba242249766fca26e975fcb718c60602d99, Format 1 manifest SHA-256 91bb56d5de1822cfb64a9fad0270c83d41d5b00c110e6740d2804c9e96c2d4f3. Backup ref backup/2026-11-18-T013-source-base сохраняет исходный HEAD; T-013 worktree чист на том же HEAD, история не переписана.
15. 24 worktree-regression cases покрывают отсутствие/prunable worktree, mismatch task ID/branch, orphan task directory, запуск audit из unrelated cwd без RepositoryRoot, точный quarantine с Unicode-путём при включённом Git path quoting, изоляцию system/global Git config, подавление repo-local fsmonitor, отказ для absolute/traversal quarantine paths и блокировку Publish на read-only ветке T-013; source assertions требуют reparse-guard для корней репозитория, admin/common dirs, config и зарегистрированных worktrees. Проверяется, что audit ничего не удаляет.
16. Regression suite блокирует непустой production quarantine registry; неизвестные каталоги не добавляются в quarantine автоматически.
17. Git errors из Windows Codex sandbox не трактуются как повреждение репозитория: если `rev-parse` работает, а `status`/`diff` выдают ошибку worktree, повторить только read-only проверку в разрешённом execution context, которому доступен exact checkout. По одной sandbox-ошибке запрещено менять Git metadata или выполнять reset/repair.
18. Если настройка worktree config завершается посреди нескольких `git config`-записей, она может оставить частичный набор параметров; verifier обязан отказать, commit/push не продолжаются. После проверки authenticated identity безопасный recovery — повторно выполнить идемпотентную настройку `scripts/github/configure-local.ps1 -IdentityOnly` и verifier. Автоматический rollback не выполняется: он может затереть параллельное изменение конфигурации. Это остаточный риск, а не транзакционная гарантия.

## Ограничения

Git metadata — атрибуция, а не доказательство физического автора. Pre-commit/pre-push hooks можно обойти вне политики; они не являются серверным security boundary. Независимое ревью и hosted CI остаются отдельными gates. Неверную публичную историю не переписывать.

Настройка нескольких Git config keys не атомарна как единая транзакция. При сбое часть worktree-scoped параметров может уже быть записана; verifier и hooks блокируют дальнейшую работу до полного совпадения. Повторный `configure-local.ps1 -IdentityOnly` предназначен для сведения значений к policy, но конкурентная запись во время настройки отдельно не синхронизируется. Runtime-тестирование reparse-point/junction ancestors в production filesystem не покрыто; их отказ закреплён source regression и synthetic проверки остаются ограниченными политикой хоста.

## Критерий завершения

Не закрывать T-015 до публикации scoped commit и независимого read-only review именно live PR head от другого производителя. Для этой же текущей пары head/base hosted `quality-gate` должен завершиться успешно, а reviewer report обязан назвать проверенный head. Любое изменение head, base, diff или критериев приёмки аннулирует прежний review; изменение head/base требует нового hosted gate. Замечания воспроизводятся и закрываются отдельным commit в этой ветке; merge запрещён до повторного успешного review и CI.
