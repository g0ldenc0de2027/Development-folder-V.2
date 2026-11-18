# Локальная и общая база знаний / Local and shared knowledge

## Быстрый старт

Из корня task worktree, PowerShell 7.4+:

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
предназначен для исторического чтения, а не текущей рекомендации.
Context включает index, все закреплённые модули, карту охвата и выбранные записи; при превышении -MaxBytes отказ
KB_CONTEXT_LIMIT. По умолчанию бюджет 128 KiB, диапазон 512–262144 bytes. Он не означает автоматическую загрузку в конкретный AI client.

Полные ответы `search` и `get` ограничены отдельно через `-MaxOutputBytes`: по умолчанию
131072 байта, допустимый диапазон 512–2097152. Считаются UTF-8 байты точного JSON
вместе с завершающим LF. Если ответ больше бюджета, CLI возвращает `KB_OUTPUT_LIMIT`
и exit 1, пишет пустой stdout и не обрезает JSON. Лимит относится только к выдаче:
он не ограничивает объём чтения и внутреннюю память до сериализации.
Значение команды принимается PowerShell без учёта регистра; `SEARCH` и `GET` подчиняются
тому же лимиту.

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
Пакет правил содержит ровно девять обязательных путей: `rules/RULES.md`, семь
канонических файлов `rules/modules/01-knowledge-and-calibration.md`,
`02-spec-and-quality.md`, `03-agents-and-workspace.md`, `04-git-and-release.md`,
`05-security.md`, `06-ui-i18n-help.md`, `07-research-and-decisions.md` и
`rules/COVERAGE.md`. У каждой нормы один модуль; индекс задаёт общие ограничения и маршрут чтения.
Policy-lock schemaVersion=2 фиксирует path/sha256 каждого файла. CLI требует точное
множество этих девяти путей и возвращает `KB_POLICY_LOCK` при пропуске, подмене, лишнем
или повторном пути; локальная ссылка на незакреплённый файл возвращает `KB_POLICY_LINK`.
Изменённые байты возвращают `KB_POLICY_CHANGED`. Старый lock schema 1 не конвертируется
молча: сохраните снимок, перенесите полную согласованную поставку и проверьте check/context.
Каталог знаний сохраняет schemaVersion=1. Карта COVERAGE различает норму и реальную автоматику.

Hash pin не удостоверяет publisher, не сообщает о новых remote отзывах и не защищает
от произвольного shell той же учётной записи. Автоматического sync/publisher пока нет.

## Ограничения и ошибки

KB_CONTENT_CHANGED — bytes расходятся с catalog; выясните изменение, не повышайте trust.
KB_POLICY_CHANGED — файл пакета правил расходится с lock; восстановите согласованную поставку.
KB_POLICY_LINK — локальная ссылка ведёт к файлу вне закреплённого пакета.
KB_POLICY_LOCK — неподдерживаемая схема, повтор пути или некорректный lock.
KB_HARDLINK — файл записи имеет несколько hard links; используйте отдельную обычную копию внутри базы.
KB_LINK_ENUMERATION_UNAVAILABLE — сетевой/неизвестный том или неподдерживаемая ФС; hard-link enumeration недоступно, завершилось ошибкой или вернуло неполные данные; чтение завершается отказом.
KB_JSON_DUPLICATE_KEY — неоднозначный JSON, исправьте повтор ключа.
KB_SHARED_UNAVAILABLE — проверьте явно выбранный путь; fallback не выполняется.
KB_POSSIBLE_SECRET — не сохраняйте секрет в знания; scanner не гарантирует очистку.

Нет внешних запросов моделей/телеметрии. Общая БЗ не публикуется автоматически в GitHub.
Reparse checks не являются полной OS isolation и не устраняют все filesystem races.
Корень проекта и все существующие компоненты его пути от корня тома проверяются на reparse point до определения типа volume; родительская junction блокируется. Для `knowledge/catalog.json`, записей `knowledge/records/*` и `.etalon.json` на NTFS/ReFS/UDF каталог до 24 записей проверяется через `fsutil hardlink list`; при большем числе записей используется `GetFileInformationByHandle` по открытому handle, чтобы не запускать отдельный процесс на каждую запись. В обоих режимах принимается ровно один link; несколько дают `KB_HARDLINK`, ошибка/неполные данные — `KB_LINK_ENUMERATION_UNAVAILABLE`. FAT/FAT32/exFAT не поддерживают hard links и допускаются без перечисления. Сетевые и неизвестные типы/форматы томов отклоняются. Правила проекта защищены своим SHA-256 lock. Между проверкой пути и чтением остаётся ограниченный TOCTOU-риск; это не OS isolation.
Backup содержит канон и нужный inbox. Restore не активирует старые sessions/права.

## English quick reference

Run the commands above from the worktree root using PowerShell 7.4 or newer.
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
The package has exactly nine required paths: `rules/RULES.md`, the seven canonical files
under `rules/modules/` (`01-knowledge-and-calibration.md` through
`07-research-and-decisions.md`), and `rules/COVERAGE.md`. Policy-lock schema 2 pins every
path and SHA-256. `check` rejects missing, substituted, extra, or duplicate lock paths as
`KB_POLICY_LOCK`; an unpinned local Markdown link is `KB_POLICY_LINK`, and changed bytes
are `KB_POLICY_CHANGED`. Update the entire approved package in one task; schema 1 is refused
rather than silently migrated. Check validates every pinned file and local Markdown link; context returns all pinned texts.
The default context budget is 128 KiB (512–262144 bytes); an insufficient budget fails explicitly.
Full `search` and `get` JSON output uses a separate `-MaxOutputBytes` budget (131072 default,
512–2097152 range), counted as UTF-8 bytes including the final LF. Oversized output returns
`KB_OUTPUT_LIMIT`, exit 1, and empty stdout without truncation; processing memory is not bounded.
PowerShell accepts command values case-insensitively, so uppercase `SEARCH` and `GET` use
the same output limit.
KB_POLICY_CHANGED means bytes differ; KB_POLICY_LINK means an unpinned local link;
KB_POLICY_LOCK means a malformed/unsupported package. Restore a reviewed package, do not bypass checks.
Missing or null knowledge_base is not configured; a non-string location is invalid.
The coverage map openly lists missing application-stack, translation-validation and security-watch capabilities.

Capture schema 2 требует заявленные source, scope, author, runtime; автор не аутентифицирован. Старые конверты schema 1 не переписываются. Check проверяет записи и правила на ограниченные признаки секретов и отклоняет неучтённые Markdown-файлы верхнего уровня knowledge/records; это не проверка PII и не гарантия отсутствия всех секретов. Draft возвращается со своим статусом и не является проверенным знанием.
