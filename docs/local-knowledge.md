# Локальная и общая база знаний / Local and shared knowledge

## Быстрый старт

Встроенная справка: `Get-Help ./scripts/kb.ps1 -Full`.

Из корня task worktree на проверенной Windows 11 x64 GA 26H2/build 26300, ветка `ge_release`, с PowerShell 7.6 LTS не ниже 7.6.10:

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
Search — буквальный поиск без учёта регистра и морфологии. Пустой результат содержит records: [] и totalMatches: 0. Если get не нашёл запрошенный ID, он возвращает KB_NOT_FOUND. Doctor проверяет обнаружение и доступность пути общей БЗ, а совместимость оставляет непроверенной.
Get/search исключают withdrawn и superseded по умолчанию; явный -IncludeWithdrawn
предназначен для исторического чтения, а не текущей рекомендации. Search сообщает
общее число совпадений, число выданных записей и `truncated`; результат сверх `-Limit`
не следует принимать за полный список.
Агенты могут передать `search -Compact` и получить карточки с ID, типом, заголовком,
статусом и SHA-256. Тело выбранной записи читается через `get -Id`. Если хеш изменился,
повторите поиск. Полный поиск используется по умолчанию. Для других команд
`-Compact` возвращает `KB_COMPACT_SEARCH_ONLY`.
Context возвращает весь выбранный набор записей или завершается с `KB_CONTEXT_RECORD_LIMIT`;
частичный контекст не выдаётся как полный. По умолчанию `-Limit` равен 100, максимум — 1000.
Context включает index, все закреплённые модули, карту охвата и выбранные записи; при превышении -MaxBytes (UTF-8 байты JSON, включая завершающий LF) отказ
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

### Назначение общей базы и обязательный preflight

Локальная БЗ принадлежит одному проекту и сохраняет его подробный контекст. Общая БЗ
собирает выбранные важные сведения из локальных БЗ всех проектов и любые прямые записи
владельца, в том числе на темы вне разработки. Она — общий источник знаний для
допущенных агентов и проектов. Целевая архитектура должна ограничивать выдачу по аутентифицированной роли, scope, classification и audience до поиска и формирования производных данных. Сейчас schema 1 не содержит этих per-record полей, CLI не аутентифицирует агента и не фильтрует выдачу; `search/get/context` возвращают подходящие записи выбранного каталога. Не размещайте в общей базе закрытые/project-confidential данные, рассчитывая на такую фильтрацию. Локальный проектный источник остаётся главным источником текущих требований
и решений. В общей базе сохраняются происхождение и точная ревизия; она не является
полным зеркалом.

В начале каждой содержательной задачи вручную выполните поиск в обеих коллекциях:

~~~powershell
pwsh -NoProfile -File scripts/kb.ps1 search -Query 'текст запроса'
pwsh -NoProfile -File scripts/kb.ps1 search -ProjectRoot $env:ETALON_KNOWLEDGE_BASE -Query 'текст запроса'
~~~

Если общая база настроена через локальный .etalon.json, передайте в -ProjectRoot путь из
этой настройки. Сейчас CLI проверяет или ищет одну коллекцию за вызов; doctor только
обнаруживает shared root, не выполняет федерацию и не подтверждает совместимость или ACL.
Сохраните в handoff или записи, какие базы проверены, какие применимые IDs/revisions найдены
и какие источники оказались недоступны. Не считайте пустой ответ доказательством отсутствия
знаний, пока не проверены статус записей и доступность/полнота источника.

Если для существенного вопроса не хватает свежих и применимых данных, действуйте по
правилу 20: исследуйте первоисточники; в тяжёлых случаях обязательны OSINT, Deep Research,
экспертные роли и сравнение выполнимых решений. Если общая БЗ явно настроена, но не
доступна, сообщите об этом и не подменяйте её другой коллекцией.

После работы новые проверенные факты и решения сохраняются сначала в локальную БЗ.
Ценные для портфеля, важные для общей картины или указанные владельцем знания предлагаются
в общую через проверку provenance, свежести, scope, audience, классификации, лицензии,
секретов/PII, противоречий и дубликатов. Автоматическое копирование локальных файлов,
принятие предложений и publisher не реализованы.

Полный целевой дизайн, роли агентов, цикл research/promotion и файловая capability matrix:
[spec/portfolio-kb-agent-workflow.md](../spec/portfolio-kb-agent-workflow.md).
Статус этого дизайна — DRAFT / NOT READY; он не меняет ограниченный объём текущего CLI.

Цель владельца для обеих БЗ — хранить и обрабатывать основные типы файлов. Сейчас
поддерживаются только Markdown-записи с JSON-каталогом. Office/PDF, изображения, аудио
и видео, OCR/ASR, архивы и другие исходники пока не извлекаются и не индексируются.
Каждый будущий адаптер должен отдельно показывать stored, extracted и indexed; исходник,
который только сохранён, не считается доступным для поиска.

Чтобы проверить или искать в общей базе, передайте её выбранный путь явно:

~~~powershell
pwsh -NoProfile -File scripts/kb.ps1 check -ProjectRoot $env:ETALON_KNOWLEDGE_BASE
pwsh -NoProfile -File scripts/kb.ps1 search -ProjectRoot $env:ETALON_KNOWLEDGE_BASE -Query 'правила'
~~~

Doctor показывает только обнаружение каталога, не совместимость/достоверность.
Объединённый поиск двух баз в одном запросе пока не реализован.
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
KB_CONTEXT_LIMIT — указанный byte budget недостаточен; полный контекст не выдан.
KB_CONTEXT_RECORD_LIMIT — набор больше `-Limit`; уменьшите выборку или явно повысьте лимит.
KB_POLICY_CHANGED — файл пакета правил расходится с lock; восстановите согласованную поставку.
KB_OUTPUT_LIMIT — ответ search/get превышает бюджет; уменьшите выборку или увеличьте лимит.
KB_POLICY_LINK — локальная ссылка ведёт к файлу вне закреплённого пакета.
KB_POLICY_LOCK — неподдерживаемая схема, повтор пути или некорректный lock.
KB_HARDLINK — файл записи имеет несколько hard links; используйте отдельную обычную копию внутри базы.
KB_LINK_ENUMERATION_UNAVAILABLE — сетевой/неизвестный том или неподдерживаемая ФС; hard-link enumeration недоступно, завершилось ошибкой или вернуло неполные данные; чтение завершается отказом.
KB_JSON_DUPLICATE_KEY — неоднозначный JSON, исправьте повтор ключа.
KB_SHARED_UNAVAILABLE — проверьте явно выбранный путь; fallback не выполняется.
KB_POSSIBLE_SECRET — не сохраняйте секрет в знания; scanner не гарантирует очистку.

Нет внешних запросов моделей/телеметрии. Общая БЗ не публикуется автоматически в GitHub.
Reparse checks не являются полной OS isolation и не устраняют все filesystem races.
Корень проекта и все существующие компоненты его пути от корня тома проверяются на reparse point до определения типа volume; родительская junction блокируется. Для `knowledge/catalog.json`, записей `knowledge/records/*` и `.etalon.json` на NTFS/ReFS/UDF каталог до 24 записей сначала проверяется через `fsutil hardlink list`; при большем числе записей сначала используется `GetFileInformationByHandle` по открытому handle. Если выбранный способ не может получить полный достоверный результат, CLI однократно пробует альтернативный способ; native-проверка принимает только link count 1, а `fsutil` — ровно один путь, совпадающий с проверяемым. Несколько links дают `KB_HARDLINK`; если оба способа недоступны или неоднозначны — `KB_LINK_ENUMERATION_UNAVAILABLE`. FAT/FAT32/exFAT не поддерживают hard links и допускаются без перечисления. Сетевые и неизвестные типы/форматы томов отклоняются. Правила проекта защищены своим SHA-256 lock. Fallback может быть медленнее на больших каталогах; между проверкой пути и чтением остаётся ограниченный TOCTOU-риск, это не OS isolation.
Backup содержит канон и нужный inbox. Restore не активирует старые sessions/права.

## English quick reference

Run the commands above from the worktree root on the verified Windows 11 x64 GA 26H2 (build 26300, `ge_release` branch), using PowerShell 7.6 LTS version 7.6.10 or newer. GitHub Actions separately validates on the Windows Server 2025 x64 `windows-2025` runner (build 26100).
The CLI emits JSON; failures use stderr and exit code 1. Search is literal.
Use -ProjectRoot to select any local/shared collection directory explicitly.
Set ETALON_KNOWLEDGE_BASE or an ignored .etalon.json knowledge_base for discovery.
An unavailable explicit location never falls back to another collection.

Markdown bodies and catalog metadata are versioned together. New notes are drafts.
Capture writes an ignored proposal only. Context includes complete pinned rules and
refuses an insufficient byte budget. Hash integrity does not establish truth or reviewer identity.
Do not store credentials or personal data. Back up ignored inbox separately.


See command syntax and examples with `Get-Help ./scripts/kb.ps1 -Full`. Use `check` for
catalogue and policy integrity and `doctor` to inspect shared collection discovery and availability.
Doctor reports compatibility as unverified. An empty search returns `records: []` and
`totalMatches: 0`; a missing record ID in `get` returns `KB_NOT_FOUND`.
Use `-Limit` to bound record selection (default 100, maximum 1000) and inspect `truncated`.
Context rejects an incomplete record selection with `KB_CONTEXT_RECORD_LIMIT`.
`search -Compact` returns metadata including `contentSha256`. Use `get -Id` for the body.

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

## Сверка выбранной коллекции

Для check, search, get и context передайте `-ExpectedCollectionId <UUID>`, полученный из доверенной конфигурации. При несовпадении CLI возвращает `KB_COLLECTION_ID_MISMATCH` с пустым stdout. При отсутствующем корне возвращается KB_ROOT_UNAVAILABLE. Перенос коллекции сохраняет её ID. Используйте параметр в каждом вызове чтения.

Capture schema 2 requires declared source, scope, author and runtime. The author identity is unauthenticated and schema 1 proposals are preserved as written. Check rejects uncatalogued top-level Markdown records and scans records and rules for common secret patterns. The scan does not establish absence of secrets or personal data. Treat draft records as unreviewed.
