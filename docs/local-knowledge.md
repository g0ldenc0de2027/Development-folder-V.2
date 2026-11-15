# Локальная и общая база знаний / Local and shared knowledge

## Быстрый старт

Из корня task worktree на Windows 11 x64 build 26200+ с PowerShell 7.6 LTS не ниже 7.6.6 и с актуальным servicing patch:

~~~powershell
pwsh -NoProfile -File scripts/kb.ps1 check
pwsh -NoProfile -File scripts/kb.ps1 search -Query 'переносимость'
pwsh -NoProfile -File scripts/kb.ps1 get -Id local-first
pwsh -NoProfile -File scripts/kb.ps1 context -Id local-first
pwsh -NoProfile -File scripts/kb.ps1 doctor
pwsh -NoProfile -File scripts/kb.ps1 capture -Title 'Наблюдение' -Text 'Проверить новый сценарий' -Source 'test:example' -Scope 'example' -Author 'operator' -Runtime 'local'
~~~

CLI возвращает JSON в stdout, короткий код ошибки в stderr и exit 1 при отказе.
Check проверяет catalog, hashes и локальную поставку RULES, а не истинность записей.
Search — буквальный case-insensitive поиск, без русской морфологии/векторов.
Get/search исключают withdrawn и superseded по умолчанию; явный -IncludeWithdrawn
предназначен для исторического чтения, а не текущей рекомендации. Search сообщает
общее число совпадений, число выданных записей и `truncated`; результат сверх `-Limit`
не следует принимать за полный список.
Context возвращает весь выбранный набор записей или завершается с `KB_CONTEXT_RECORD_LIMIT`;
частичный контекст не выдаётся как полный. По умолчанию `-Limit` равен 100, максимум — 1000.
Context включает index, все закреплённые модули, карту охвата и выбранные записи; при превышении -MaxBytes отказ
KB_CONTEXT_LIMIT. По умолчанию бюджет 128 KiB, диапазон 512–262144 bytes. Он не означает автоматическую загрузку в конкретный AI client.

## Произвольное местоположение общей БЗ

Путь задаётся через ETALON_KNOWLEDGE_BASE, иначе knowledge_base локального .etalon.json.
Ни имя диска, ни имя папки не закреплены в коде. В локальной настройке используйте
полный путь, в том числе пробелы и кириллицу. В Git эта настройка не включается.
Null или отсутствие knowledge_base означает not_configured; другое нестроковое значение отклоняется.
Environment имеет приоритет; явно недоступный environment не заменяется marker.
После переноса БЗ обновите только настройку, затем повторите doctor и check.

Чтобы проверить или искать в общей базе, передайте её выбранный путь явно:

~~~powershell
pwsh -NoProfile -File scripts/kb.ps1 check -ProjectRoot $env:ETALON_KNOWLEDGE_BASE
pwsh -NoProfile -File scripts/kb.ps1 search -ProjectRoot $env:ETALON_KNOWLEDGE_BASE -Query 'правила'
~~~

Doctor показывает только обнаружение каталога, не совместимость/достоверность.
Объединённый поиск двух баз в одном запросе пока не реализован.
Если environment не используется, для -ProjectRoot передайте путь из локальной настройки.

## Записи и обновление

Catalog: schemaVersion=1, постоянный projectId коллекции, records.
У записи: id, kind, title, status, path, contentSha256, sources, review.
Допустимые kinds: lesson/decision/reference/research.
Статусы: draft/reviewed/accepted/superseded/withdrawn.
Тела — knowledge/records/*.md, до 256 KiB; catalog до 1 MiB и 1000 записей.
Пути относительно выбранного root; traversal, reparse points и unknown schema отклоняются.

После редактирования тела главный ИИ обновляет его hash в catalog. Предыдущее review
сохранять за изменённым текстом нельзя. Для reviewed/accepted нужны sources и review:
by, at (UTC timestamp), contentSha256, evidence. Metadata by — заявление об авторе,
не аутентификация. Проверку содержания и admission делает действующий workflow.

Capture создаёт уникальный draft envelope в ignored data/knowledge/inbox; catalog
не меняется. Файлы .part после сбоя не являются опубликованными предложениями.
Автоматический admission/recovery stage не реализован; такие файлы сохраняются
для отдельного разбора. Inbox резервируется отдельно от Git.

## Канон правил

Редактировать RULES следует в общей БЗ. V2 хранит точную копию; policy-lock фиксирует
версию, sourceCollectionId и SHA-256 каждого файла. После обновления канона главный ИИ проверяет diff,
переносит полную копию и обновляет lock одной задачей, затем запускает check.
Пакет редакции 0.2.0: index rules/RULES.md, семь rules/modules/*.md и rules/COVERAGE.md.
У каждой нормы один модуль; индекс задаёт общие ограничения и маршрут чтения.
Policy-lock имеет schemaVersion=2 и files с path/sha256, максимум 12 файлов.
Неизвестная схема, отсутствующий файл, изменённые байты, повтор пути или локальная
ссылка за пределы поставки приводят к отказу. Старый lock schema 1 не конвертируется
молча: сохраните снимок, перенесите полную согласованную поставку и проверьте check/context.
Каталог знаний сохраняет schemaVersion=1. Карта COVERAGE различает норму и реальную автоматику.

Hash pin не удостоверяет publisher, не сообщает о новых remote отзывах и не защищает
от произвольного shell той же учётной записи. Автоматического sync/publisher пока нет.

## Ограничения и ошибки

KB_CONTENT_CHANGED — bytes расходятся с catalog; выясните изменение, не повышайте trust.
KB_CONTEXT_LIMIT — указанный byte budget недостаточен; полный контекст не выдан.
KB_CONTEXT_RECORD_LIMIT — набор больше `-Limit`; уменьшите выборку или явно повысьте лимит.
KB_POLICY_CHANGED — файл пакета правил расходится с lock; восстановите согласованную поставку.
KB_POLICY_INCOMPLETE — каноническая поставка RULES 0.2.0 не содержит всех девяти закреплённых файлов.
KB_POLICY_LINK — локальная ссылка ведёт к файлу вне закреплённого пакета.
KB_POLICY_LOCK — неподдерживаемая схема, повтор пути или некорректный lock.
KB_JSON_DUPLICATE_KEY — неоднозначный JSON, исправьте повтор ключа.
KB_SHARED_UNAVAILABLE — проверьте явно выбранный путь; fallback не выполняется.
KB_POSSIBLE_SECRET — не сохраняйте секрет в знания; scanner не гарантирует очистку.

Нет внешних запросов моделей/телеметрии. Общая БЗ не публикуется автоматически в GitHub.
Reparse checks не являются полной OS isolation и не устраняют все filesystem races.
Backup содержит канон и нужный inbox. Restore не активирует старые sessions/права.

## English quick reference

Run the commands above from the worktree root on Windows 11 x64 build 26200 or newer, using PowerShell 7.6 LTS, version 7.6.6 or newer, with the current servicing update. GitHub Actions separately validates on the Windows Server 2025 x64 `windows-2025` runner.
The CLI emits JSON; failures use stderr and exit code 1. Search is literal.
Use -ProjectRoot to select any local/shared collection directory explicitly.
Set ETALON_KNOWLEDGE_BASE or an ignored .etalon.json knowledge_base for discovery.
An unavailable explicit location never falls back to another collection.

Markdown bodies and catalog metadata are versioned together. New notes are drafts.
Capture writes an ignored proposal only. Context includes complete pinned rules and
refuses an insufficient byte budget. Hash integrity does not establish truth or reviewer identity.
Do not store credentials or personal data. Back up ignored inbox separately.


### English policy-package update and recovery

The editable rules canon is in the shared collection; projects keep a byte-identical snapshot.
Policy-lock schema 2 pins the index, seven thematic modules and the coverage map.
Update the entire approved package in one task; schema 1 is refused rather than silently migrated.
Check validates every pinned file and local Markdown link; context returns all pinned texts.
The default context budget is 128 KiB (512–262144 bytes); an insufficient budget fails explicitly.
KB_POLICY_CHANGED means bytes differ; KB_POLICY_LINK means an unpinned local link;
KB_POLICY_LOCK means a malformed/unsupported package. Restore a reviewed package, do not bypass checks.
Missing or null knowledge_base is not configured; a non-string location is invalid.
The coverage map openly lists missing application-stack, translation-validation and security-watch capabilities.

Capture schema 2 требует заявленные source, scope, author, runtime; автор не аутентифицирован. Старые конверты schema 1 не переписываются. Check проверяет записи и правила на ограниченные признаки секретов и отклоняет неучтённые Markdown-файлы верхнего уровня knowledge/records; это не проверка PII и не гарантия отсутствия всех секретов. Draft возвращается со своим статусом и не является проверенным знанием.
