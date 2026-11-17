# T-015 — Изоляция и проверка Git-атрибуции

- **Статус:** in_progress
- **Основание:** владелец поручил устранить повторяемые ошибки Git attribution и добавить безопасную автокоррекцию.
- **База:** `f577dc70e58d75ab5fd61d0c2e712c27b590713a` — live `origin/main` при создании worktree.
- **Ветка/worktree:** `task/T-015-git-attribution` / `.worktrees/T-015`.
- **Исходные факты:** common .git/config задаёт user.name=Scope Fixture; worktree-specific identity отсутствует; extensions.worktreeConfig=true. Старый configure-local.ps1 использовал git config --local, изменяя общий конфиг. PR #9/T-010 содержит опубликованные commits с fixture attribution; T-013 имеет два локальных fixture-attributed commits без обнаруженного remote branch. Два последних опубликованных T-011 commits имеют ID-based noreply association, но некорректный display name.

## Цель

Перестать создавать commits с placeholder, чужой или некорректно интерполированной личностью; настраивать identity только в целевом linked worktree после подтверждения GitHub account. Не переписывать существующую историю и не выдавать автоматическую настройку за исправление уже созданных commits.

## Зона файлов

- `AGENTS.md`
- `config/github/repository.json`
- `scripts/github/configure-local.ps1`
- `scripts/verify-git-identity.ps1`
- `scripts/lib/GitIdentity.psm1`
- .githooks/pre-commit
- .githooks/pre-push
- `scripts/quality-gate.ps1`
- `tests/git-identity-regressions.ps1`
- `docs/git-identity.md`
- `tasks/T-015-git-attribution-hardening.md`

## Приёмка

1. GitHub author profile фиксируется открытыми полями `login` и `userId`; секреты и email не записываются в tracked files.
2. Настройка сверяет live gh api user с repo policy, пишет user.name, ID-based noreply email и user.useConfigOnly только через git config --worktree. Common user.name/email сохраняются; стандартные hooks/fetch/pull/push параметры настраиваются отдельно.
3. pre-commit сначала проверяет локальную identity; при отсутствии или несоответствии сверяет live gh api user и автоматически записывает identity только в этот worktree, затем повторяет проверку. Стандартные repository-wide settings настраиваются отдельно; сетевой сбой, другой аккаунт, environment overrides, не совпадающие с policy, и любые GIT_CONFIG overrides блокируют commit; точные author/committer совпадения проходят дополнительную проверку effective identity. Email не печатается.
4. Push-range verifier отклоняет новые commits с неверными author/committer name/email, включая явный `--author` override и fixture identity.
5. 14 synthetic regressions покрывают placeholder в common config, worktree repair, account mismatch, author/committer environment/config injection, точные разрешённые значения identity, неверные author/committer name/email, outgoing ranges и порядок hooks. Fixture удаляется из собственного temp-каталога.
6. Полный `quality-gate.ps1 -BaseRef origin/main`, регрессии и `git diff --check` проходят. Успехи привязаны к точному HEAD/содержимому.
7. Правила документируют безопасное автолечение только до commit при подтверждённой identity; после commit — только отдельная recovery-задача и новая история, без amend/rebase/filter/rewrite. Опубликованные T-010/T-011/T-013 refs не изменяются.

## Ограничения

Git metadata — атрибуция, а не доказательство физического автора. Pre-commit/pre-push hooks можно обойти вне политики; они не являются серверным security boundary. Независимое ревью и hosted CI остаются отдельными gates. Неверную публичную историю не переписывать.

## Следующий шаг

Получить независимое read-only review текущего live head PR #11 от другого производителя. Исправления выполнять в этой task-ветке; после каждого нового head повторно запускать локальный gate и сверять hosted CI с точной парой head/base. Не сливать PR до успешного независимого review и зелёного CI.
