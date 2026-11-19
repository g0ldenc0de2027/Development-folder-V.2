# Локальная и общая база знаний / Local and shared knowledge

## Быстрый старт

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
Пакет редакции 0.5.0: index rules/RULES.md, семь rules/modules/*.md и rules/COVERAGE.md.
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

Run the commands above from the worktree root on the verified Windows 11 x64 GA 26H2 (build 26300, `ge_release` branch), using PowerShell 7.6 LTS version 7.6.10 or newer. GitHub Actions separately validates on the Windows Server 2025 x64 `windows-2025` runner (build 26100).
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
