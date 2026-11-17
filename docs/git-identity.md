# Безопасная Git-атрибуция в linked worktrees

## Причина

В многопоточном checkout у всех linked worktrees общий admin repository и общий конфиг `.git/config`. Параметр `git config --local` пишет туда, поэтому identity из одной рабочей копии может распространиться на остальные. `extensions.worktreeConfig=true` включает отдельный `config.worktree` для каждой рабочей копии. Параметры `core.bare` и `core.worktree` нельзя бездумно задавать общими для нескольких worktrees: common `core.worktree` блокируется, а bare admin `core.bare=true` должен оставаться только в `config.worktree` bare-root.

## Настройка и автоматическая коррекция до commit

1. Проверь, что gh auth status показывает нужный аккаунт, а gh api user возвращает login и numeric ID, совпадающие с commitIdentity в tracked config/github/repository.json.
2. После clone и после создания каждой новой linked worktree запусти из её корня `pwsh -NoLogo -NoProfile -File scripts/github/configure-local.ps1`. Не запускай команду из bare admin root: он намеренно не является working tree, и `git status` для него неприменим; проверяй status в конкретной linked worktree.
3. Скрипт записывает identity только через git config --worktree; затем проверяет effective author/committer, user.useConfigOnly и сохранность common user.name/email. Отдельно он задаёт стандартные repository-wide hooks, fetch, pull, push и credential settings.
4. Инициализация безопасно включает `extensions.worktreeConfig`, проверяет регистрацию worktree и исправляет известную bare-admin конфигурацию: переносит `core.bare=true` из общего конфига в `config.worktree` bare-root и задаёт `core.bare=false` текущей worktree. Затем pre-commit проверяет effective default identity без сети; при обычном drift он один раз запускает `configure-local.ps1`, которая подтверждает account через `gh api user`, исправляет только текущую worktree и повторяет проверку. Сетевой сбой, другой аккаунт, несовпадающие с policy `GIT_AUTHOR_*`/`GIT_COMMITTER_*` overrides и любые `GIT_CONFIG_*` overrides блокируют commit. Email не печатается.

Не копируй identity вручную между worktrees и не используй git config --local user.name/email. Если проверка не проходит, остановись и исправь конфигурацию после проверки аккаунта.

## После создания неверного commit

Hook не исправляет уже созданные commits. Сначала зафиксируй точные refs, status, diff и SHA-256 резервной копии изменений. Не используй amend, rebase, reset или фильтрацию истории. Для неопубликованного ошибочного объёма подготовь отдельную recovery-задачу и чистую ветку с теми же проверенными содержимым и тестами; исходную ветку и резервный patch сохраняй до проверки новой копии. Для опубликованной истории не меняй refs: исправление делается новым PR/commit либо отдельной чистой replacement-веткой с явным решением владельца.

Явный `git commit --author` меняет author создаваемого commit и не во всех версиях/путях виден pre-commit как environment override. Поэтому pre-push независимо проверяет author/committer metadata каждого outgoing commit и блокирует передачу неподходящей истории на remote. Локальный commit с ошибочной attribution может существовать; не исправляй его amend/rebase или переписыванием опубликованной истории — зафиксируй refs и оформи recovery-задачу.

Git metadata показывает заявленную identity, но не доказывает физическое авторство. Hooks усиливают дисциплину, но могут быть отключены вручную; CI и ревью остаются независимыми gates.

## Проверка

`tests/git-identity-regressions.ps1` создаёт только синтетические admin и linked worktrees в своём temp-каталоге. Он динамически запускает hooks, проверяет передачу нескольких ref ranges, изоляцию identity, автокоррекцию, fail-closed обработку неоднозначной конфигурации и миграцию `core.bare`; также проверяет, что outgoing metadata валидируется до push.
