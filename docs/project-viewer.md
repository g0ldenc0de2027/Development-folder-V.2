# Локальный просмотрщик проектов

Сохраните реестр вне Git. Относительные пути в нём разрешаются от папки реестра.

```json
{"projects":[{"id":"v2","name":"Development Folder V2","roots":["./checkout"]}]}
```

Указывайте рабочие checkout, например V2/.worktrees/main, и выбранные task worktree. При переносе меняйте путь, сохраняя ID.

```powershell
pwsh -NoProfile -File scripts/project-viewer.ps1 -RegistryPath <путь-к-реестру>
```

Откройте выведенный URL. «Обновить» перечитывает источники. Ctrl+C останавливает панель. URL содержит ключ сеанса, храните его локально.

Карточка может содержать строки «Блокер:», «Следующее действие:», «Решение владельца: ожидается», а также явно подписанные PR_HEAD_SHA, PR_BASE_SHA, CI_HEAD_SHA и CI_BASE_SHA. Полный исходный текст всегда доступен для прочитанных версий.

## English quick start

Create a local JSON registry, run the command above, and open the printed session URL. Refresh rereads source cards. Ctrl+C stops the viewer. Keep the session URL private.
