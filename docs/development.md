# Разработка эталона

## Поддерживаемая основа

Эталонные инструменты разработки запускаются только на проверенной **Windows 11 x64 GA 26H2 (build 26300)** из allowlist [`config/runtime-support.json`](../config/runtime-support.json), на ветке `ge_release`. Проверка требует точного совпадения display version/build, client installation и Windows client ProductType. Новые выпуски не добавляются автоматически.

Требуется **PowerShell 7.6 LTS, не ниже 7.6.10**. 7.6.10 — последний опубликованный LTS patch на 2026-11-15. Проверяйте версию именно того `pwsh.exe`, который запускает gate: при нескольких установках выберите stable binary 7.6.10+ явно. Локальные runtime-проверки T-008 прошли под PowerShell 7.6.10. Официальный lifecycle указывает, что поддерживается только последняя update-версия ветки. Порог и дата проверки хранятся в `config/runtime-support.json`; gate не делает сетевой запрос за последним релизом при каждом запуске, поэтому недельный аудит toolchain должен сверять официальный источник и обновлять baseline.

Проверено 2026-11-15 по официальным источникам:

- [Windows 11 release information](https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information): подтверждает General Availability для 26H2/build 26300. Microsoft также поддерживает 25H2, но он не входит в allowlist эталона, поскольку его совместимость с проектным gate отдельно не проверялась.
- [Поддерживаемые версии Windows client](https://learn.microsoft.com/en-us/windows/release-health/supported-versions-windows-client): подтверждает lifecycle поддерживаемых выпусков и даты окончания обслуживания по редакциям.
- [PowerShell 7.6.10 release](https://github.com/PowerShell/PowerShell/releases/tag/v7.6.10): последний проверенный LTS patch.
- [Жизненный цикл PowerShell](https://learn.microsoft.com/en-us/powershell/scripting/install/powershell-support-lifecycle?view=powershell-7.6): определяет LTS-ветку и правило поддержки latest update конкретной ветки.

Не входят в матрицу разработчика: Windows 10 (включая LTSC/ESU, которые отдельно не квалифицировались), Windows 11 25H2, 24H2, 26H1 и preview/prerelease builds, прочие неподтверждённые Windows client releases, Windows 11 ARM64, Windows Server, Windows PowerShell 5.1, Linux и macOS. ОС/архитектура будущего создаваемого приложения выбирается отдельно в его ТЗ и не ограничивается этой матрицей эталона.

**CI:** GitHub Actions использует `windows-2025` — Windows Server 2025 x64 (base build 26100). Runner может содержать устаревший встроенный pwsh; workflow скачивает официальный PowerShell 7.6.10 win-x64 ZIP, сверяет SHA-256 из config/runtime-support.json, затем проверяет точный runtime и запускает gate этим бинарником. На 2026-11-15 runner фактически запускал 7.6.9, поэтому встроенной версии образа доверять как удовлетворяющей минимуму нельзя. Образ ОС остаётся плавающим, проверяется точный base build; архив PowerShell загружается по сети при каждом CI run с timeout/retry. Это изолированная среда CI, не поддержка Windows Server как пользовательского хоста. [Состав runner image](https://github.com/actions/runner-images/blob/main/images/windows/Windows2025-Readme.md) проверен 2026-11-15.

Git for Windows и GitHub CLI нужны для GitHub workflow. Интернет нужен для загрузки SHA-256-проверенного PowerShell в CI и pinned actionlint/Gitleaks во временную папку локального gate.
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
Если `-BaseRef` не передан, но задан `$env:PR_BASE_BRANCH`, скрипт использует `origin/<PR_BASE_BRANCH>`.

Версии аудит-инструментов и SHA-256 находятся в config/security/tools.json. Gate проверяет hash перед запуском. Для `-TemporaryRoot` нужен существующий каталог вне Git-репозиториев, без reparse points на пути. Gate создаёт в нём отдельный каталог запуска `gate-<runId>` с маркером владения `.gate-owner`. Перед push hook передаёт `-RemoteName`, `-RemoteUrl` и `-PushRange`; сравнение `-RemoteName`/`-RemoteUrl` с ожидаемым origin выполняется только если задан `-RemoteName`. `-PushRange` принимает один SHA (40 или 64 hex) либо диапазон `base..head`. Gitleaks всегда сканирует рабочее дерево и доступную историю, а переданные push-диапазоны проверяет дополнительно.

При отдельном запуске тестов с синтетическими Git-фикстурами параметр `-TempRoot` задаёт существующий родительский каталог вне рабочих деревьев и bare-репозиториев. Выберите путь без reparse points. При запуске без параметра используется системный временный каталог. О порядке работы с фикстурами см. [Task workflow](../tasks/README.md).

Финальный результат `scripts/quality-gate.ps1` печатается в stdout только при нулевом внутреннем коде `$gateExit` и после успешного завершения блока очистки: это точная строка `QUALITY-GATE=PASS`, после чего сценарий завершается с кодом выхода 0. Если исключение возникает в основном теле проверок, перехватчик пишет в stderr `QUALITY-GATE=FAIL: <сообщение>`, устанавливает `$gateExit = 1`, и маркер успеха не выводится. Ошибки очистки временного каталога (проверка владельца и reparse points, удаление, отсутствие остатка каталога) дают отдельный stderr-маркер `QUALITY-GATE=FAIL: cleanup of '<TemporaryRoot>/gate-<runId>': <сообщение>` и тоже код 1, даже когда сами проверки прошли. Отказы, произошедшие до входа в основной блок (parameter binding, разбор скрипта, инициализация путей), не имеют собственного маркера quality gate и диагностируются стандартными сообщениями PowerShell. Для автоматической проверки используйте пару: stdout-строка `QUALITY-GATE=PASS` плюс exit code 0; любое `QUALITY-GATE=FAIL:` в stderr или ненулевой код означают отказ проверки. Если отказ ещё не подтверждён и процесс продолжает работать, итог ожидается. Если оператор подтвердил отмену, фиксируйте её отдельно. Код выхода 0 без точного маркера успеха означает неполное подтверждение результата. Если наблюдение прервалось или процесс завершился, а итоговый маркер и код выхода недоступны, результат неизвестен до повторной сверки.

## Обновления
Обновление toolchain требует старой версии, официального источника, проверки совместимости, rollback plan и post-update gate. Не меняйте dependency manifests будущего проекта как часть обновления среды.

## RULES и файловая база знаний

Новые зависимости не устанавливаются: для CLI используется PowerShell 7.6 LTS с текущим security/servicing patch; матрица ОС и CI описана выше.
В проверке T-008 использованы PowerShell 7.6.10 и Git 2.56.0.windows.4.
Python не нужен этому срезу. Это inventory, а не pin target будущих продуктов.

    pwsh -NoProfile -File scripts/kb.ps1 check
    pwsh -NoProfile -File tests/kb-regressions.ps1

Сценарии пользователя и подключения общей БЗ: local-knowledge.md.
Gate запускает integrity check текущего корпуса и KB-регрессии.
Каталог, Markdown и rules lock проверяются вместе. Inbox data/knowledge/inbox игнорируется Git.

Локальный кэш Visual Studio .vs игнорируется Git и исключается из обхода исходников.
Если файл из .vs принудительно добавлен в индекс, gate завершается отказом. Это не
проверка содержимого игнорируемых локальных кэшей; не храните в них исходники проекта.
