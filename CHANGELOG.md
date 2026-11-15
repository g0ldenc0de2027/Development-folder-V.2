# Changelog

Все заметные изменения Development Folder V2 фиксируются здесь.

## Unreleased
- Матрица runtime вынесена в `config/runtime-support.json`: проверенная Windows 11 x64 GA 26H2/build 26300 на `ge_release`; PowerShell 7.6 LTS 7.6.10+; CI — Windows Server 2025 build 26100.
- Gate, scope guard и KB CLI fail-closed проверяют поддерживаемую платформу и линию PowerShell через общий runtime verifier; scope guard корректно обрабатывает Unicode-пути.
- Усилен pre-push: только одноимённая task/T-NNN ветка, без тегов/удалений/non-fast-forward; зоны файлов сверяются с карточкой задачи.
- Исправлена передача диапазонов Git hook в PowerShell и добавлена fail-closed проверка scope.
- KB CLI проверяет секретоподобные значения в метаданных, комплектность канонического RULES 0.2.0 и не выдаёт неполный context молча.
- Аудит-реестр и инструкции передачи: tasks/T-008-audit-remediation.md.

## 2.0.0-development — 2026-11-14
- Создан чистый каркас V2 без переноса файлов и Git-истории прежнего эталона.
- Добавлены GitHub rules, read-only settings verifier, CI quality gate, pre-push hook и документация рабочего процесса.
- Спецификация продукта оставлена в статусе DRAFT до детализации и проверки критериев.
