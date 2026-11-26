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

## Одна локальная очередь

Добавьте `queue` к тому же реестру. Укажите стабильное имя очереди и локальный каталог с подпапками `tasks`, `reports`, `accepted`. Относительный путь разрешается от файла реестра. Например:

```json
{
  "queue": {"id":"pilot","path":"./exchange"},
  "projects":[{
    "id":"v2","name":"Development Folder V2","roots":["./checkout"],
    "bindings":[{"taskId":"T-001","assignmentId":"PILOT-001"}],
    "ownerActions":[{"taskId":"T-001","text":"Проверить итог","requires":["PILOT-001"]}]
  }]
}
```

Привязки и указания необязательны. `requires` перечисляет ID привязанных к этой задаче заданий, по которым обе копии должны читаться и совпадать. Пустой список снимает условие сверки. Один ID задания может быть привязан только к одной задаче в реестре. Задания без привязки показаны отдельно. При недоступной очереди отображается последний снимок в пределах текущего сеанса. Отчёты до 1 МиБ отображаются как текст. Панель читает отчёты локально и не отправляет их во внешние сервисы.

## Панель хода разработки

Для календаря добавьте необязательный объект `timeline` к записи проекта в реестре:

~~~json
{
  "id": "v2",
  "name": "Development Folder V2",
  "roots": ["./checkout"],
  "timeline": {
    "timeZone": "UTC",
    "startDate": "2026-11-20",
    "stages": [
      {
        "id": "pilot",
        "name": "Пилот",
        "plannedDate": "2026-11-26",
        "taskIds": ["T-001"]
      }
    ]
  }
}
~~~

Используйте даты в формате `YYYY-MM-DD`. Дата старта, плановая и фактическая даты этапа необязательны. Для факта используйте поле `actualDate`. Часовой пояс определяет отметку «Сегодня». Нажмите название этапа, чтобы отфильтровать задачи. Доска и список используют общий поиск и фильтры.

Общий экран показывает задачи с полем «Решение владельца: ожидается». Из списка открывается карточка с действием и доступными доказательствами. Если источник отключён, отображается время последнего полного чтения. История переходов за период пока недоступна.

### Development overview

Add optional `timeline` metadata to a project as shown above. The time zone controls the Today marker. Dates use `YYYY-MM-DD` and may be omitted. Select a stage to filter tasks. The board and list share filters. The portfolio shows tasks waiting for an owner decision and the project view shows source freshness.
