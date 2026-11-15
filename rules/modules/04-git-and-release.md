# Git и выпуск

Редакция 0.2.0 · 2026-11-15 · Codex, gpt-6.1-sol.
Область и приоритет — [RULES](../RULES.md). Это нормативный текст, не отчёт о реализации.

## Правило 12. Git, review и выпуск

Следовать docs/github-workflow.md и реальной конфигурации репозитория.
main — интеграционная ветка, изменения через PR; задача — task/T-NNN и отдельный worktree.
Перед commit проверить всю зону изменений, включая committed/staged/unstaged/untracked,
rename/delete. Прежние чужие правки не присваивать.

Локальные commits и обычный push завершённой task-ветки в проверенный origin разрешены
в рамках поручения после применимых checks. Commit получает Conventional Commits,
Refs и Assisted-by. Для merge обязательны независимое review текущего head,
CI на соответствующей head/base revision tuple и принятый scope.

Не путать PR head, base, synthetic merge-result и squash commit main.
Изменившаяся ревизия требует актуальных доказательств.
Force push, переписывание опубликованной истории, удаление remote refs, перенос тегов
и обход hooks агентом запрещены. Отклонение gate исправляется, не обходится.
Reset/clean/rebase/amend/revert/cherry-pick и удаление локальных веток требуют
отдельного явного запроса; перед потерей работы нужен backup.

Tag/release — отдельный workflow с применимыми gates и проверенным rollback.
Выпуск не равен приёмке владельцем; зелёный CI сам по себе не принимает продукт.
Не публиковать в существующую main напрямую.

Локальная проверка и server enforcement — разные границы. Владелец остаётся корнем
доверия выбранной no-App модели; residual risk изменяемого workflow сохраняется.
Tag/release разрешаются автоматически только по отдельно утверждённому и реализованному
release workflow с полным gate. Отсутствующий workflow нельзя заменить ручным обходом.
Локальный hook обязан строго отказать, когда надёжно подтвердить разрешённый выпуск нельзя.
Privacy email защищается настройкой verified noreply identity; GET /user email=null
не подтверждает приватность email опубликованных commits.
