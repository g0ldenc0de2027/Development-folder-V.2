# T-067 — Привязать проверку зоны к фактической отправке

Статус — в работе. Источник — аудит V2, A06.

## Зона файлов

- `.githooks/pre-push`
- `scripts/verify-git-identity.ps1`
- `scripts/verify-task-scope.ps1`
- `tests/git-identity-regressions.ps1`
- `tests/task-scope-regressions.ps1`
- `docs/github-workflow.md`
- `tasks/T-067-pin-push-scope.md`

## Приёмка

- Hook сверяет фактический OID отправки с HEAD. Проверка зоны читает карточку из этого коммита.
- Для зоны и gate используется один подтверждённый SHA main. Нет объекта или ревизия изменилась — push блокируется.
- Синтетические Git-сценарии покрывают неверную и устаревшую базу, смену HEAD и существующую политику pre-push. Точные результаты фиксируются в PR.
