# Development Folder V2

**Назначение:** безопасный, воспроизводимый эталон для создания отдельных проектов на современных языках и стеках.
**Версия продукта:** 2.0.0-development
**Статус:** GitHub foundation активен: hosted CI прошёл на bootstrap SHA, а `quality-gate` обязателен в live ruleset. Прикладная реализация остаётся закрыта до READY. Проверки worktree и файловой зоны задачи действуют в локальном pre-push после слияния [PR #8](https://github.com/g0ldenc0de2027/Development-folder-V.2/pull/8). Создание worktree и координация выполнения задач описаны в [task workflow](tasks/README.md).

## Принципы

- Один создаваемый продукт — один репозиторий; эталон не превращается в монорепозиторий приложений.
- Новый функционал начинается с проверяемых требований и критериев приемки.
- Языки и инструменты подключаются профилями проекта по необходимости; все SDK не устанавливаются в эталон одновременно.
- Зависимости фиксируются lock-файлами, проверяются на поддержку, совместимость и известные уязвимости.
- Рабочая ветка и worktree изолированы для каждой задачи; в PR попадают только ее файлы.
- Обычные изменения в main проходят через PR и проверки точных SHA. Единственное исключение — чистый initial root commit в подтверждённо пустой remote; детали и условия остановки — в docs/github-workflow.md.

## Быстрый старт

Для разработки эталона требуется проверенная Windows 11 x64 GA 26H2 (build 26300) на ветке `ge_release`, указанная в allowlist `config/runtime-support.json`; PowerShell 7.6 LTS не ниже 7.6.10, Git и GitHub CLI. CI отдельно работает на `windows-2025` (Windows Server 2025 x64, build 26100). Windows 10, Windows 11 25H2 и другие неподтверждённые выпуски, ARM64, Windows Server как хост разработчика, Windows PowerShell 5.1, Linux и macOS не поддерживаются. Подробности и источники: docs/development.md. Локальная проверка:

    pwsh -NoProfile -File scripts/quality-gate.ps1

Перед первым push настройте локальный Git hook: pwsh -NoProfile -File scripts/github/configure-local.ps1. Порядок веток, PR и проверок: docs/github-workflow.md. Цель и границы V2: spec/ТЗ.md и spec/СОСТОЯНИЕ.md.

## Правила и знания

Рабочие нормы: [rules/RULES.md](rules/RULES.md). Карта памяти проекта:
[knowledge/README.md](knowledge/README.md). Команды чтения, поиска и предложений:
[docs/local-knowledge.md](docs/local-knowledge.md).

Первый файловый срез БЗ имеет отдельный допуск spec/local-knowledge.md.
Он не включает автоматический рой, общий publisher или прикладные профили стеков.
Целевой портфельный lifecycle и агентский контур описаны отдельно как DRAFT / NOT READY: spec/portfolio-kb-agent-workflow.md.

Текущие исправления по аудиту и точка передачи следующему агенту: [tasks/T-008-audit-remediation.md](tasks/T-008-audit-remediation.md).
