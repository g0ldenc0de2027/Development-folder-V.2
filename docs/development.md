# Разработка эталона

## Поддерживаемая основа
- Windows 10/11
- PowerShell 7.4+
- Git for Windows
- GitHub CLI для проверки remote и PR
- Интернет для получения pinned actionlint и Gitleaks во временную папку gate

Linux/macOS и Windows PowerShell 5.1 пока не поддерживаются. Не меняйте target будущего проекта только ради локально установленных инструментов.

## Проверки
Настройте локальные безопасные Git defaults и pre-push quality gate один раз после clone:

    pwsh -NoProfile -File scripts/github/configure-local.ps1

Локальный gate:

    pwsh -NoProfile -File scripts/quality-gate.ps1

Read-only сверка live GitHub settings с versioned config (repository, ruleset, Actions, Dependabot и security):

    pwsh -NoProfile -File scripts/github/verify-settings.ps1

Пока required status check не появился после первого CI, скрипт выведет INCOMPLETE и завершится с кодом 2. Для проверки merge-readiness используйте -RequireStatusCheck; режим завершится ошибкой при отсутствии check или при неверном его источнике.

Проверка точного диапазона PR:

    pwsh -NoProfile -File scripts/quality-gate.ps1 -BaseRef origin/main

Версии аудит-инструментов и SHA-256 находятся в config/security/tools.json. Gate проверяет hash перед запуском и удаляет только свой временный каталог. Перед push hook передает локальные и удаленные SHA обновляемых refs; Gitleaks проверяет их диапазоны и сканирует доступную локальную историю.

## Обновления
Обновление toolchain требует старой версии, официального источника, проверки совместимости, rollback plan и post-update gate. Не меняйте dependency manifests будущего проекта как часть обновления среды.
