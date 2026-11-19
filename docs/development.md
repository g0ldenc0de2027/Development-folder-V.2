# Разработка эталона

## Поддерживаемая основа
- Windows 10/11
- PowerShell 7.4+
- Git for Windows
- GitHub CLI для проверки remote и PR
- Интернет для получения pinned actionlint и Gitleaks во временную папку gate

Linux/macOS и Windows PowerShell 5.1 пока не поддерживаются. Не меняйте target будущего проекта только ради локально установленных инструментов.

## Проверки
После clone настройте репозиторий и каждую новую linked worktree отдельной командой. Команда сверяет origin и текущий GitHub account, включает безопасную worktree-конфигурацию и записывает identity только в выбранную worktree:

    pwsh -NoProfile -File scripts/github/configure-local.ps1

Повторите её из каждой новой `.worktrees/T-NNN` до первого commit. Не запускайте её из bare admin root: эта папка намеренно не является рабочим деревом, поэтому обычный `git status` там неприменим. Список linked worktrees получите через `git worktree list`; status проверяйте из каждой рабочей папки. Если диагностика сообщает о неоднозначном `core.worktree`, конфликтующем `core.bare` или невозможности `git status` внутри linked worktree, остановитесь: не редактируйте общий `.git/config` вручную.

Локальный gate:

    pwsh -NoProfile -File scripts/quality-gate.ps1

Read-only сверка live GitHub settings с versioned config (repository, ruleset, Actions, Dependabot и security):

    pwsh -NoProfile -File scripts/github/verify-settings.ps1 -RequireStatusCheck

Эта команда подтверждает, что live ruleset и manifest требуют точный `quality-gate` от GitHub Actions, strict policy включена, а check отсутствует на устаревшем или постороннем источнике.

Проверка точного диапазона PR:

    pwsh -NoProfile -File scripts/quality-gate.ps1 -BaseRef origin/main

Версии аудит-инструментов и SHA-256 находятся в config/security/tools.json. Gate проверяет hash перед запуском и удаляет только свой временный каталог. Перед push hook передает локальные и удаленные SHA обновляемых refs; Gitleaks проверяет их диапазоны и сканирует доступную локальную историю.

## Обновления
Обновление toolchain требует старой версии, официального источника, проверки совместимости, rollback plan и post-update gate. Не меняйте dependency manifests будущего проекта как часть обновления среды.

## RULES и файловая база знаний

Новые зависимости не устанавливаются: используется поддерживаемый PowerShell 7.4+.
В проверенной среде T-004 effective PowerShell — 7.6.9, Git — 2.56.0.windows.4.
Python не нужен этому срезу. Это inventory, а не pin target будущих продуктов.

    pwsh -NoProfile -File scripts/kb.ps1 check
    pwsh -NoProfile -File tests/kb-regressions.ps1

Сценарии пользователя и подключения общей БЗ: local-knowledge.md.
Gate запускает integrity check текущего корпуса и KB-регрессии.
Каталог, Markdown и rules lock проверяются вместе. Inbox data/knowledge/inbox игнорируется Git.
