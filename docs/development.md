# Разработка эталона

## Поддерживаемая основа

Эталонные инструменты разработки запускаются на **Windows 11 x64 build 26200 или новее** и
**PowerShell 7.6 LTS, версия не ниже 7.6.6**. 7.6.6 — последний LTS patch, указанный Microsoft 2026-11-15, и support floor; этот worktree проверен на 7.6.9. Устанавливайте последний security/servicing update ветки 7.6. Gate проверяет именно этот минимальный patch, а недельный аудит toolchain сверяет, что он не устарел.
Build-порог исключает Windows 10 и старые ветки Windows 11; перед работой отдельно
убедитесь, что точная редакция и выпуск Windows остаются на обслуживании Microsoft.

Проверено 2026-11-15 по официальным источникам:

- [Поддерживаемые версии Windows client](https://learn.microsoft.com/en-us/windows/release-health/supported-versions-windows-client): 25H2 (build 26200) и более новые поддерживаемые выпуски входят в текущую базовую матрицу; статус зависит от редакции.
- [Жизненный цикл PowerShell](https://learn.microsoft.com/en-us/powershell/scripting/install/powershell-support-lifecycle?view=powershell-7.6): PowerShell 7.4 LTS завершил поддержку 2026-11-10; текущая LTS — 7.6.6 (на дату проверки). Microsoft обслуживает только последний update конкретной ветки.

Не входят в матрицу разработчика: Windows 10 (обычная поддержка завершена; исключения LTSC/ESU отдельно не квалифицировались), Windows 11 ARM64, Windows Server, Windows PowerShell 5.1, Linux и macOS. ОС/архитектура будущего создаваемого приложения выбирается отдельно в его ТЗ и не ограничивается этой матрицей эталона.

**CI:** GitHub Actions использует `windows-2025` — Windows Server 2025 x64 (build 26100); образ проверяет runtime gate и на 2026-11-15 содержит PowerShell 7.6.10. Workflow печатает фактическую patch-версию каждого запуска. Это изолированная среда CI, она не означает поддержку Windows Server как пользовательского хоста. [Состав runner image](https://github.com/actions/runner-images/blob/main/images/windows/Windows2025-Readme.md) проверен 2026-11-15; версия PowerShell меняется вместе с образом.

Git for Windows и GitHub CLI нужны для GitHub workflow. Интернет нужен для получения pinned actionlint и Gitleaks во временную папку gate.
## Проверки
Настройте локальные безопасные Git defaults и pre-push quality gate один раз после clone:

    pwsh -NoProfile -File scripts/github/configure-local.ps1

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

Новые зависимости не устанавливаются: для CLI используется PowerShell 7.6 LTS с текущим security/servicing patch; матрица ОС и CI описана выше.
В проверенной среде T-004 effective PowerShell — 7.6.9, Git — 2.56.0.windows.4.
Python не нужен этому срезу. Это inventory, а не pin target будущих продуктов.

    pwsh -NoProfile -File scripts/kb.ps1 check
    pwsh -NoProfile -File tests/kb-regressions.ps1

Сценарии пользователя и подключения общей БЗ: local-knowledge.md.
Gate запускает integrity check текущего корпуса и KB-регрессии.
Каталог, Markdown и rules lock проверяются вместе. Inbox data/knowledge/inbox игнорируется Git.
