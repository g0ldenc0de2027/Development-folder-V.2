# Урок: безопасная Git identity в linked worktrees

Наблюдение: локальные задачи в linked worktrees получили неправильную общую identity, а bare admin repository с общим `core.bare=true` мешал обычным операциям вроде `git status` в связанных рабочих копиях.

Причина: `git config --local` меняет общий конфиг worktree-семейства. Идентичность должна быть worktree-scoped через `extensions.worktreeConfig`; `core.bare` тоже нельзя без разбора наследовать из общего конфига. Явный `git commit --author` может изменить metadata уже создаваемого commit, поэтому один pre-commit не гарантирует перехват.

Закрепление: до commit проверять authenticated GitHub account и effective identity, сохранять имя/email только в config.worktree, проверять реальный Git hook и каждый outgoing commit до отправки. Bare-admin `core.bare=true` переносить в config.worktree самого bare-root только после проверки структуры и регистрации worktree; текущей linked worktree задавать `core.bare=false`. Неоднозначный common `core.worktree` блокировать. После некорректного commit не переписывать историю: сохранить refs и решать отдельной recovery-задачей.

Источники и точные ревизии: владелец, задача T-015 (2026-11-17); независимые замечания Xiaomi MiMo и Antigravity по PR #11; официальная документация Git `git-worktree` и `git-config`.

Область применимости и ограничения: Git linked worktrees на Windows в поддерживаемой среде проекта. Синтетические regression cases проверяют механизм, но сами по себе не подтверждают физическое авторство и не защищают от отключения локальных hooks.

Как проверить: запустить `pwsh -NoLogo -NoProfile -File tests/git-identity-regressions.ps1`; затем выполнить проектный quality gate в точной task worktree и проверить `git status` в затронутых worktrees.
