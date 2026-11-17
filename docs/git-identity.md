# Безопасная Git-атрибуция в linked worktrees

## Причина

В многопоточном checkout у всех linked worktrees общий admin repository и общий конфиг .git/config. Параметр git config --local пишет туда, поэтому настройка имени автора из одной рабочей копии может распространиться на остальные. Конфигурация extensions.worktreeConfig=true позволяет хранить настройки отдельно в config.worktree конкретной рабочей копии.

## Настройка и автоматическая коррекция до commit

1. Проверь, что gh auth status показывает нужный аккаунт, а gh api user возвращает login и numeric ID, совпадающие с commitIdentity в tracked config/github/repository.json.
2. Из целевого linked worktree запусти pwsh -NoLogo -NoProfile -File scripts/github/configure-local.ps1.
3. Скрипт записывает identity только через git config --worktree; затем проверяет effective author/committer, user.useConfigOnly и сохранность common user.name/email. Отдельно он задаёт стандартные repository-wide hooks, fetch, pull, push и credential settings.
4. pre-commit сначала проверяет identity без сети. При отсутствующей или неверной конфигурации он один раз запускает configure-local.ps1: тот сверяет активный gh api user и исправляет identity только в этом worktree, повторно устанавливая фиксированные repository-wide settings. Затем проверка выполняется снова. Сетевой сбой, другой аккаунт, несовпадающие с policy GIT_AUTHOR_*/GIT_COMMITTER_* overrides и любые GIT_CONFIG_* overrides блокируют commit; точные совпадения author/committer разрешены, а effective identity дополнительно сверяется с policy. pre-push сверяет metadata каждого отправляемого commit.

Не копируй identity вручную между worktrees и не используй git config --local user.name/email. Если проверка не проходит, остановись и исправь конфигурацию после проверки аккаунта.

## После создания неверного commit

Hook не исправляет уже созданные commits. Сначала зафиксируй точные refs, status, diff и SHA-256 резервной копии изменений. Не используй amend, rebase, reset или фильтрацию истории. Для неопубликованного ошибочного объёма подготовь отдельную recovery-задачу и чистую ветку с теми же проверенными содержимым и тестами; исходную ветку и резервный patch сохраняй до проверки новой копии. Для опубликованной истории не меняй refs: исправление делается новым PR/commit либо отдельной чистой replacement-веткой с явным решением владельца.

Git metadata показывает заявленную identity, но не доказывает физическое авторство. Hooks усиливают дисциплину, но могут быть отключены вручную; CI и ревью остаются независимыми gates.

## Проверка

tests/git-identity-regressions.ps1 создаёт только синтетические admin и linked worktrees в указанном temp-каталоге. Он проверяет, что неверная общая identity не протекает в commit, что локальная настройка не меняет common config, что несовпадающие overrides блокируются, точная identity проходит и outgoing history проверяется до push.
