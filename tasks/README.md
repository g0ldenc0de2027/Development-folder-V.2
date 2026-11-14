# Task workflow

Текущий этап еще не содержит task lifecycle automation. До ее готовности используйте Git worktree вручную и не совмещайте задачи:

1. Обновить origin/main и подтвердить, что локальный main равен origin/main.
2. Создать task/T-NNN от origin/main и отдельный worktree в .worktrees/T-NNN.
3. До изменений записать scope файлов и критерии приемки.
4. Проверять tracked, staged, unstaged и untracked пути против scope.
5. Не размещать параллельные задачи в одном worktree.
6. Перед публикацией убедиться, что нет незакоммиченных файлов и SHA соответствует проверенному diff.
7. Открыть PR; пока live ruleset не требует quality-gate, merge запрещен. После включения check провести CI на merge-result текущих head/base SHA и независимое review на текущем head SHA.
8. После завершения убрать только свой чистый worktree.

Автоматизация этих шагов предусмотрена roadmap.
