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
4. pre-commit проверяет effective default identity и безопасно исправляет обычный drift после проверки account. Так как Git захватывает identity до запуска pre-commit, успешное исправление drift обязано завершить текущую попытку отказом; повторный commit допускается только отдельным запуском после повторной проверки. Не утверждай, что `git commit --author` всегда блокируется до создания commit: pre-push проверяет фактические author/committer metadata всех outgoing commits до отправки. Неверную историю он не исправляет автоматически.
5. Pre-push передаёт несколько обновляемых ref ranges одним однозначным параметром; verifier и quality gate разбирают каждую строку отдельно.
6. 31 identity-regression cases покрывают common placeholder, изоляцию, account mismatch, author/committer environment/config injection, разрешённые identity, неверные author/committer name/email, multi-ref hook execution, автокоррекцию с обязательным безопасным повтором commit, safe bare-admin migration без per-worktree override и при заранее настроенном core.bare=false; bootstrap будущих worktrees, неоднозначный common core.worktree, нормализацию регистра login, поиск shell root при вложенном `git.exe`, доступность неинтерактивных проверок при `GIT_EDITOR=false`, восстановление partial worktree identity, блокировку T-013 как исходного и целевого ref, допустимые Git temporary indexes и отказ для произвольных index paths. Регрессия quality gate требует отключения pager во всех его прямых Git-вызовах и diff-проверках.
7. Полный `quality-gate.ps1 -BaseRef origin/main`, регрессии и `git diff --check` проходят. Успехи привязаны к точному HEAD/содержимому.
8. Правила документируют безопасное автолечение только до commit при подтверждённой identity; после commit — только отдельная recovery-задача и новая история, без amend/rebase/filter/rewrite. Опубликованные T-010/T-011/T-013 refs не изменяются.

9. Перед началом задачи глобальный audit обнаруживает dirty tracked/untracked worktree, missing/prunable worktree, task ID mismatch, unregistered физический каталог `.worktrees/T-NNN` и ignored .vs. Любой непроверенный путь блокирует commit/publish; данные не удаляются.
10. pre-commit разрешает только staged изменения текущего worktree и проверяет все соседние worktree; pre-push требует clean status и повторяет глобальную проверку.
11. После архивации T-013 production registry quarantine пуст; ни одно dirty worktree не получает исключение. Regression fixtures отдельно подтверждают точную проверку Format 1 и блокировку изменённого fingerprint.
12. Quality gate запускает synthetic regressions для bare admin, staged/unstaged/untracked, ignored .vs, точного synthetic quarantine, hook environment isolation и hooks. Audit subprocesses удаляют и восстанавливают унаследованные `GIT_*`, отключают system/global config, используют tracked empty global config, запрещают pager и optional locks и явно отключают repo-local `core.fsmonitor`, чтобы read-only audit не запускал произвольный watcher из проекта.
13. Документация задаёт обязательный audit перед ручным созданием task worktree и handoff для interruption; ограничение local hooks указано явно.
14. Семь raw-файлов T-013 архивированы и повторно проверены: Development-Folder-V2_T-013-source-snapshot-2026-11-18_91bb56d5.zip, archive SHA-256 734f27b8027e4a0aaa2f1aeca5868ba242249766fca26e975fcb718c60602d99, Format 1 manifest SHA-256 91bb56d5de1822cfb64a9fad0270c83d41d5b00c110e6740d2804c9e96c2d4f3. Backup ref backup/2026-11-18-T013-source-base сохраняет исходный HEAD; T-013 worktree чист на том же HEAD, история не переписана.
15. 25 сценариев worktree-регрессий покрывают отсутствие/prunable worktree, несовпадение ID задачи/ветки, orphan-каталог, запуск audit из постороннего cwd без RepositoryRoot, точный Unicode-quarantine при Git path quoting, изоляцию system/global Git config, отключение repo-local fsmonitor, запрет rooted/traversal-путей и блокировку Publish для read-only T-013 и реальный pre-commit E2E для commit -a, pathspec, Git temporary index и проверенной identity auto-repair через локальный synthetic gh на bare admin. Чистый .worktrees/main допускается только при точном совпадении полного пути с Git-регистрацией; одноимённый незарегистрированный каталог блокируется и сохраняется. Source assertions проверяют reparse guards корней, admin/common dirs, config и зарегистрированных worktrees. Audit ничего не удаляет.
16. Regression suite блокирует непустой production quarantine registry; неизвестные каталоги не добавляются в quarantine автоматически.
17. Git errors из Windows Codex sandbox не трактуются как повреждение репозитория: если `rev-parse` работает, а `status`/`diff` выдают ошибку worktree, повторить только read-only проверку в разрешённом execution context, которому доступен exact checkout. По одной sandbox-ошибке запрещено менять Git metadata или выполнять reset/repair.
18. Если настройка worktree config завершается посреди нескольких `git config`-записей, она может оставить частичный набор параметров; verifier обязан отказать, commit/push не продолжаются. Synthetic regression удаляет часть identity keys, подтверждает отказ verifier и проверяет convergence после повторной настройки. Recovery — после проверки authenticated identity повторно выполнить `scripts/github/configure-local.ps1 -IdentityOnly` и verifier. Автоматический rollback не выполняется: он может затереть параллельное изменение конфигурации. Это остаточный риск, а не транзакционная гарантия.
19. Pre-push блокирует обе формы публикации ветки-источника `refs/heads/task/T-013*`: отправку защищённой локальной ветки под другим remote-именем и создание защищённого remote ref из другой локальной ветки. Synthetic test подтверждает, что оба отказа происходят до изменения fixture remote.

## Candidate checks — 2026-11-19

- Candidate base: branch task/T-015-git-attribution, HEAD dd371f482d9c9502c0b50ba9834ab297c6594639; origin/main is f577dc70e58d75ab5fd61d0c2e712c27b590713a.
- Full local quality-gate command pwsh -NoLogo -NoProfile -File scripts/quality-gate.ps1 -BaseRef origin/main: PASS on the candidate before this evidence update. Identity regressions 31/31, task-worktree regressions 25/25, KB regressions 44/44, privacy covered 41 Markdown files plus regression source, hygiene checked 69 text files, actionlint PASS, Gitleaks PASS (97 reachable commits); stack build/dependency audit is NOT COVERED because the template selects no application stack.
- The passing run does not yet validate this final documentation update; rerun the gate and git diff --check before commit. No T-015 commit or push has been made for the candidate.
- Live PR #11 remains OPEN/Draft at published head dd371f482d9c9502c0b50ba9834ab297c6594639, base f577dc70e58d75ab5fd61d0c2e712c27b590713a. Hosted run #44363546723 succeeded on that old head only; fresh CI and independent review are required after publishing the final candidate.

## Ограничения

Git metadata — атрибуция, а не доказательство физического автора. Локальные hooks можно обойти вне политики; это не серверный security boundary. Текущая блокировка T-013 относится к именам branch refs; она не реализует общую проверку ancestry/tag/ref policy, которой управляет отдельный Git workflow task. Независимое ревью и hosted CI остаются отдельными gates. Неверную публичную историю не переписывать.

Настройка нескольких Git config keys не атомарна как единая транзакция. При сбое часть worktree-scoped параметров может уже быть записана; verifier и hooks блокируют дальнейшую работу до полного совпадения. Повторный `configure-local.ps1 -IdentityOnly` предназначен для сведения значений к policy, но конкурентная запись во время настройки отдельно не синхронизируется. Runtime-тестирование reparse-point/junction ancestors в production filesystem не покрыто; их отказ закреплён source regression и synthetic проверки остаются ограниченными политикой хоста.

## Критерий завершения

Не закрывать T-015 до публикации scoped commit и независимого read-only review именно live PR head от другого производителя. Для этой же текущей пары head/base hosted `quality-gate` должен завершиться успешно, а reviewer report обязан назвать проверенный head. Любое изменение head, base, diff или критериев приёмки аннулирует прежний review; изменение head/base требует нового hosted gate. Замечания воспроизводятся и закрываются отдельным commit в этой ветке; merge запрещён до повторного успешного review и CI.
