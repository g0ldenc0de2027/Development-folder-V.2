# Исследование: связка проектной и общей БЗ, поиск и мультимодальный ввод

- **Проекты:** Development Folder V2 и общая Knowledge_Base
- **Автор:** OpenAI Codex (GPT-6.1-sol); внутренние read-only роли по retrieval, памяти/межпроектной модели и надёжности; применены профили инженерии данных, ТЗ, поиска и модели угроз. Все внутренние роли принадлежат одному производителю; внешнего межпроизводительского review не было.
- **Дата:** 2026-11-16
- **Версия:** v1.2.0
- **Тип / статус:** research / draft; требования и архитектурные предложения для обсуждения, не реализация и не выбор стека
- **Связь:** T-009; уточнение владельца от 2026-11-16; T-004 LKB-001…008

## 1. Решения владельца и границы

Владелец уточнил назначение и поток знаний (2026-11-16):

1. **Проектная локальная БЗ содержит знания только одного проекта**, соответствующего одной папке разработки. Она хранит детальные требования, решения, уроки, материалы, источники, доказательства и рабочие черновики в пределах этого проекта.
2. **Общая БЗ — портфельная и тематически широкая.** Она получает отобранные ценные знания из локальных БЗ всех проектов и принимает прямые записи владельца на любые темы, в том числе не связанные с проектами. Она не ограничивается общими правилами или обобщённым опытом.
3. **Рабочий поиск начинается в общей БЗ.** Локальная БЗ текущего проекта запрашивает общую БЗ в начале задачи; агент затем использует проектные источники и уточняет факты. Если нужного знания нет, оно недостаточно или могло устареть, следует провести исследование. Для сложных, неясных и высокорисковых случаев нужны OSINT/Deep Research и профильные экспертные роли; выбранный вариант должен быть обоснован доказательствами и пригодностью для задачи.
4. Результаты исследования сначала сохраняются в локальную БЗ проекта. В общую передаётся только полезная другим информация после проверки происхождения, прав, секретов/PII, актуальности, классификации и аудитории. Прямая запись владельца может иметь любой тематический scope, но её происхождение и статус доказательности должны быть явными.
5. Внешняя общая БЗ может располагаться в любой выбранной папке и на любом доступном диске. Абсолютный путь — локальный locator, а не идентификатор коллекции.
6. Для обеих БЗ требуется хранение и обработка основных типов файлов. Обработка внешними провайдерами по умолчанию не разрешена; наружу передаются только явно разрешённые данные.

**Проектная трактовка для будущей спецификации:** общая БЗ охватывает все проекты и самостоятельные материалы владельца, но не становится автоматической копией всех локальных файлов, секретов, истории чатов или необработанных данных. Для проектных записей требуются namespace/origin, ссылки на доказательства, scope, classification, ACL/audience и admission. Прямая запись владельца также проходит учёт происхождения и статуса: факт личного внесения не равен независимой проверке истинности. Неизвестный scope не публикуется и не выдаётся агенту. Конкретные schema, ACL, admission, sync и правила выдачи необходимо определить в READY-спецификации; эта запись их не реализует.

## 2. Снимок текущих двух БЗ

Это статическая проверка конкретного локального снимка от 2026-11-16, а не заявление о live GitHub состоянии.

- Project T-009 базируется на `f577dc70e58d75ab5fd61d0c2e712c27b590713a`; рабочее дерево имеет незакоммиченные исследовательские файлы.
- Локальный clone общей Knowledge_Base: `283ec02c47b7a1228ebaf878f75d400dd734e406`, `main` совпадал с `origin/main` во время проверки.
- `pwsh -NoProfile -File scripts/kb.ps1 check` в общей БЗ: PASS; в каталоге 2 записи, `integrity=pass`, `truth=not_assessed`, `reviewIdentity=not_authenticated`.
- T-004 `doctor` обнаружил общую папку как `available_not_validated`; `compatibility=not_verified`, `federatedSearch=not_implemented`. Это подтверждает обнаружение пути, но не подключение корпуса и не готовность поиска. В worktree T-009 локального указателя нет, поэтому его `doctor=not_configured` не выдаётся за результат рабочей копии T-004.
- В обеих поставках совпадают SHA-256 файлов `scripts/kb.ps1`, `tests/kb-regressions.ps1`, `rules/RULES.md`, `rules/COVERAGE.md`, `rules/policy-lock.json`. Это совпадение байтов, не аутентификация издателя, freshness или доказательство истинности.
- Обе схемы используют catalog schema 1: у коллекции есть один `projectId`, а у записи — `id/kind/title/status/path/contentSha256/sources/review`. В записи нет `originProjectId`, classification, ACL/audience, parser lineage или task/run ID. Этой схемы недостаточно для безопасного общего каталога знаний по множеству проектов.
- T-004 ограничен Markdown/JSON, локальными `check/search/get/context/doctor` и черновиком в inbox. Обработка PDF, Office, изображений, аудио/видео, таблиц и архивов не реализована в этом срезе; это не дефект LKB-001…008, а новое требование, требующее отдельной спецификации.
- Адресная проверка `context -Id agent-workflow-research -MaxBytes 262144` в T-009 завершилась `KB_CONTEXT_LIMIT` (exit 1). Тело записи 256 752 байта; весь набор rules в этой поставке 51 961 байт, ещё до JSON-обрамления. Это конкретный случай, когда крупную запись нельзя передать через максимальный поддерживаемый context-бюджет. Сам файл ниже лимита тела 262 144 байта; прежнее наблюдение о превышении body-limit было временным и не является текущим дефектом.
- Текущий `search` сначала загружает/хэширует/проверяет весь catalog, затем выполняет literal substring matching; до 100 результатов могут содержать полные тела. Производительность и предел размера ответа не измерялись.

## 3. Целевая модель: пять раздельных слоёв

1. **Общая каноническая база.** Общие правила, принятые межпроектные решения и нужные проверенные записи по всем проектам. Для каждой записи — project namespace, статус, классификация и разрешённая аудитория. Правила остаются в общей БЗ каноном; проекты держат полную hash-pinned копию и явно показывают, если она устарела.
2. **Проектная база.** Детальная память только своего проекта. Она авторитетна для проектных фактов и доказательств. Проектная копия, опубликованная в общей БЗ, получает отдельный shared record ID и обратную ссылку на исходный ID/hash/revision; публикация не меняет локальный оригинал.
3. **Оригиналы файлов и артефактов.** Неизменённый источник хранится отдельно от каталога и поискового индекса. Используются логические `collection_id/project_id/artifact_id`, content hash и относительная структура; не вшивать машинный абсолютный путь в переносимый corpus. Крупные бинарные оригиналы не следует автоматически класть в Git.
4. **Производные материалы.** Извлечённый текст, OCR/ASR, нормализованные таблицы, previews, embeddings и индексы помечаются как производные с hash оригинала, версией parser/model/config, временем, покрытием и ошибками. Их можно перестроить; ими нельзя заменять оригинал.
5. **Оперативное состояние агентов.** Задания, lease/heartbeat, сообщения, подтверждения, run-статусы и события хранятся в отдельном authoritative ledger. Чаты, scratchpad агентов и БЗ — разные потоки. БЗ хранит отобранные долговременные факты и ссылки на доказательства, а не служит доской живого статуса.

### Направление обновлений

- Общая БЗ → проект: обновление норм/общих знаний через проверяемый пакет с точной ревизией, schema version, manifest и hashes; проект применяет его как reviewable change. Автообновление без видимого diff не рекомендуется.
- Проект → общая БЗ: local draft → проверка источника/прав/секретов/PII/классификации → проверка дубля и конфликта → owner/reviewer approval → новая общая ревизия. Перенос остаётся явным и аудируемым.
- Одинаковый ID + hash — идемпотентный импорт. Одинаковый ID с разным содержимым создаёт конфликт и сохраняет обе версии; правила и канонические знания не разрешаются автоматически по last-write-wins.
- Если общая БЗ недоступна, проект продолжает локальную работу только в ясно помеченном `local-only` режиме. Нельзя выдавать результат как объединённый или актуальный, незаметно переключившись на локальную копию.

## 4. Поиск, контекст и скорость

### Контракт результата

`search` должен возвращать ограниченный DTO: record ID, project/scope, статус, источник, exact revision/hash, короткий фрагмент и оценку/тип совпадения. Полный текст читается отдельным адресным запросом. Одновременно ограничиваются число результатов, размер snippet, суммарные байты и время. При частичной выдаче возвращаются `partial=true` и причина; частичный ответ не маркируется как полный.

Для каждого результата нужен provenance receipt: источник (project/common), collection generation или commit, record ID/hash/revision, anchor внутри файла (раздел/страница/лист/ячейка/timecode/line), время актуальности и решение доступа. Смешение источников не должно скрывать происхождение.

### Индекс

Сначала измерить существующий small-corpus путь, затем выбирать механизм. Лексический exact/identifier поиск должен оставаться доступен офлайн; BM25/FTS и семантический слой — последующие кандидаты. Derived index хранится вне канонической коллекции и привязывается к `collection_id + generation/content manifest + schema + parser/tokenizer/model versions`. При смене модели/парсера или несовпадении hash индекс становится `stale/rebuild_required`, пока не пройдет проверку; повреждённый индекс перестраивается из оригиналов.

Построение: ограниченная очередь → staging generation → parse/index → integrity check → атомарная активация pointer. Один контролируемый writer; повторные filesystem events объединяются; periodic scan сверяет удалённые/переименованные файлы. На removable/UNC/cloud folders watcher не является единственным источником изменений. SQLite/WAL — только кандидат для локального same-host индекса: официальный SQLite guide указывает, что WAL не работает на network filesystem. Не помещать живую WAL-БД в общую папку синхронизации.

### Отклик и отсутствие зависаний

Обещать «никогда не ломается» нельзя; можно гарантировать ограниченную стоимость операции, видимое состояние и восстановление. Нужны budgets для чтения, парсинга и очередей, отмена/таймаут оболочки там, где ОС позволяет прервать операцию, ограниченное число retry и понятные статусы `ready/degraded/local_only/stale/indexing/timeout/unavailable/quarantined/restore_required`. Тяжёлый парсер не должен блокировать поиск/UI. Численные P95/P99 SLO выбираются после baseline на целевом ПК для разных размеров корпуса и типов носителя; сейчас такие измерения отсутствуют.

## 5. Форматы: полная матрица возможностей

«Поддерживает формат» необходимо разделить на обнаружение, безопасное хранение оригинала, извлечение текста/структуры, OCR/ASR, индексирование, цитирование якоря и ограничения. Не обещать одинаковую точность для всех типов.

| Группа | Базовые типы | Ожидаемая обработка |
|---|---|---|
| Текст и код | MD/TXT/RST/AsciiDoc, исходники распространённых языков, shell/PowerShell, SQL, конфиги INI/TOML/JSON/JSONL/YAML/XML, логи | Текстовый поиск; язык/кодировка/путь/hash; секреты и локальные пути фильтровать до выдачи |
| Документы | PDF (текст и скан), DOC/DOCX, XLS/XLSX, PPT/PPTX, ODT/ODS/ODP, RTF, EPUB, HTML/MHTML | Текст, заголовки, таблицы и layout; точная страница/slide/sheet/cell; показать нераспознанные страницы |
| Данные | CSV/TSV, JSON/NDJSON/XML, Parquet/Arrow, SQL schema/dump | Schema, поля, типы, профили и ограниченные выборки; не выполнять произвольный SQL/макросы при ingest |
| Изображения и схемы | PNG/JPEG/TIFF/WebP/HEIC, SVG, Draw.io, Mermaid/PlantUML и экспортированные диаграммы | Метаданные и локальный OCR; сохранение original; координаты/страница и OCR confidence; SVG не рендерить без sandbox |
| Почта/календарь | EML/MSG, ICS | Body, заголовки/даты, вложения как отдельные связанные артефакты, календарная семантика |
| Аудио/видео | WAV/MP3/M4A/OGG/FLAC, MP4/MKV/MOV/WebM, VTT/SRT | Метаданные; ASR локально как отдельная опция; транскрипт с timecodes и confidence; дорогие задачи — фоновые/отменяемые |
| Архивы и неизвестные | ZIP/TAR/7z/RAR и прочие неизвестные/бинарные файлы | По умолчанию сохранять как opaque original + hash/MIME/размер; рекурсивное извлечение только в карантине с лимитом глубины/распаковки и path containment; неизвестный формат — `stored_only`, не «проиндексирован» |

Требуется версионируемая support matrix: `detected`, `stored_only`, `extracted`, `OCR/ASR`, `partial`, `unsupported`, `quarantined`, `failed`; версия parser и тестовый корпус для каждого формата. Ни один список не означает поддержку абсолютно всех форматов: новые parser adapters добавляются по мере спроса и проверки безопасности.

### Очерёдность поддержки (предложение; не статус реализации)

| Уровень | Набор | Режим и ограничение |
|---|---|---|
| A — базовая обработка | TXT/MD/RST/AsciiDoc, популярные исходники и скрипты, SQL, конфигурации JSON/JSONL/YAML/TOML/XML/INI, CSV/TSV, логи, HTML, Jupyter `.ipynb` | Локальная текстовая/структурная обработка; код, SQL и notebook cells никогда не исполняются при индексации; якоря строки/ячейки/раздела |
| B — офис и документы | цифровые PDF, DOC/DOCX, XLS/XLSX, PPT/PPTX, ODT/ODS/ODP, RTF, EPUB, EML/MSG, ICS | Извлечение layout и таблиц с page/slide/sheet/cell anchors; повреждённые, защищённые паролем и частично читаемые файлы получают явный status |
| C — мультимедиа и сканы | сканированные PDF, PNG/JPEG/TIFF/WebP/HEIC, схемы Draw.io/Mermaid/PlantUML, аудио/видео, VTT/SRT | OCR/ASR — локальные и отдельно включаемые операции с CPU/RAM/time limits, confidence и page/box/timecode anchors; сетевой egress запрещён по умолчанию |
| D — opaque или опасные форматы | ZIP/TAR/7z/RAR, EXE/DLL и другие бинарные сборки, модельные веса, live/database backups, proprietary/неизвестные форматы | Хранить оригинал/метаданные/hash как `stored_only`; извлекать содержимое только после отдельного allowlist/security review в карантине с лимитами; не запускать, не монтировать как рабочую БД и не выполнять SQL/макросы |

Порядок внедрения — сначала A, затем B; C включается по реальной потребности и замерам, D остаётся opaque, пока конкретный адаптер не прошёл допуск. Это приоритет разработки, а не разрешение урезать будущую цель: обе базы используют одну версионируемую capability matrix и должны давать одинаковые processing states. Локальная политика ограничивает данные одним проектом; общая применяет portfolio namespace/ACL к нужным материалам всех проектов. Перед выдачей общий поиск проверяет project/audience/classification.

Для каждого формата матрица обязана фиксировать extensions, MIME/signature, операции и anchors, parser/версию и лицензию, поддержку платформы/toolchain, offline-возможность, ресурсные лимиты, test corpus, security review, статус/ограничения и дату проверки. «В установленном коде», «протестировано на фикстуре» и «целевая поддержка» — разные поля. Parser upgrade требует повторить форматные/security regression cases. Полнота и свежесть должны быть измеряемыми, а неизвестные версии не считаются поддержанными.

**Текущее состояние:** обе БЗ пока не реализуют эту матрицу и мультимодальный ingest; текущий T-004 ограничен Markdown/JSON/PowerShell, а эта таблица — target design. Ни OCR/ASR, ни Office/PDF parser ещё не установлен и не проверен.
## 6. Безопасный конвейер файлов

1. До чтения — авторизация и destination project, classification/retention, размер, quota, extension **и** signature/MIME; имя файла нормализуется и не используется как доверенный путь.
2. Оригинал сначала попадает в карантин вне Git/веб-корня. Сканирование и проверка прав/PII/секретов до shared promotion. Не запускать загруженные файлы, макросы, scripts и embedded links.
3. Parser запускается с минимальными правами, read-only входом, отдельным процессом/изоляцией, без сети по умолчанию и с CPU/RAM/time/page/pixel/decompression limits. Защита от ZIP/XML bombs, traversal, polyglots, SSRF при ссылках, parser CVE и отказа диска.
4. Извлечение пишет отдельный bounded artifact с source hash, parser/model/config, coverage, anchor map, language и confidence. При partial/failure виден статус и причина; молча индексировать неполный текст как полный нельзя.
5. Prompt-like текст в извлечённых документах считается недоверенным quoted data. ACL/classification наследуются extracted chunks, snippets, thumbnails, embeddings, caches и logs. Access filter выполняется до retrieval, rerank и контекстной выдачи; отсутствие проекта/класса/ACL означает deny.
6. Cloud OCR/ASR/embedding/reranker вызывается только после явного egress decision по выбранному файлу/фрагменту/провайдеру; журнал хранит идентификаторы и решение, не секретный body.

## 7. Переносимость, конфликт и восстановление

- Стабильная identity коллекции и артефакта не зависит от буквы диска или папки. Local marker хранит локальный путь, не попадающий в Git; move/USB offline даёт ясный status и возможность переуказать root. В реальном T-004 `doctor` пока проверяет только существование папки.
- Между ПК распространяются проверенные версии через Git/PR или явные versioned export/import bundles с manifest (`collection/project ID`, schema version, package revision, source commit, object hashes, provenance, status/tombstones). Resume/checkpoints и dedupe обязательны; не делить живую БД копированием отдельных файлов.
- Backup ≠ sync. Backup содержит согласованный snapshot канона, разрешённых оригиналов и manifest; project inbox/черновики отдельно, derived index можно перестроить. Restore идет в staging, проверяет подписи/формат/hashes/schema/ACL и количество записей, затем переключает активное поколение; исходник и откат сохраняются. Не восстанавливать активные agent sessions/leases.
- Определить и измерить RPO/RTO. Выполнять restore drill на другом пути/томе. В README общей БЗ manual backup описан отдельно от Git и inbox, но это не доказывает автоматизированную процедуру или пройденную проверку восстановления.

## 8. Сравнение GitHub-аналогов: идеи, не донорский код

| Аналог и закреплённый источник | Полезная идея | Ограничение для нас |
|---|---|---|
| [Joplin search, `fc8cab6107e7328b2501943db2ec6e9c590bfc20`](https://github.com/laurent22/joplin/blob/fc8cab6107e7328b2501943db2ec6e9c590bfc20/readme/apps/search.md) | FTS и BM25 для быстрого поиска; документ прямо описывает fallback для языков без обычных границ слов | Токенизатор надо оценивать на русском, английском, CJK, арабском и идентификаторах; один индекс не гарантирует качество |
| [SilverBullet search config, `4101f3d4a29f48cf25042987459b301b9ec2de8e`](https://github.com/silverbulletmd/silverbullet/blob/4101f3d4a29f48cf25042987459b301b9ec2de8e/docs/Install/Configuration.md) | Rebuildable search index отдельно от пространства знаний; журнал/индекс не загрязняет исходные markdown | Указан polling для внешних папок; частые полные проходы надо измерять |
| [Khoj search, `ae229ca894c0b80ad84664afcfdde523b5e87057`](https://github.com/khoj-ai/khoj/blob/ae229ca894c0b80ad84664afcfdde523b5e87057/documentation/docs/features/search.md) | Семантический retrieval по chunk embeddings, затем reranking; изменение bi-encoder требует переиндексации | Это опциональный этап; модель/данные/egress и качество требуют отдельного решения и русского eval-набора |
| [SQLite FTS5](https://www.sqlite.org/fts5.html), [WAL](https://sqlite.org/wal.html), [interrupt](https://www.sqlite.org/c3ref/interrupt.html) | BM25, rebuild/integrity-check, explicit cancellation interfaces; отделённый index | FTS external-content consistency лежит на приложении; WAL не подходит для сетевой общей папки, индекс должен быть производным и same-host |
| [Syncthing syncing docs, `f02059067d50cc30e29fc83f1c0e3636da29ed3b`](https://github.com/syncthing/docs/blob/f02059067d50cc30e29fc83f1c0e3636da29ed3b/users/syncing.rst) | Временный файл/hash/atomic replace, scanner плюс watcher, видимые конфликтные копии | Folder sync не даёт атомарной транзакции всего multi-file поколения БЗ и не решает ACL |
| [CouchDB replication protocol, `5a15ed69b49c8dab30a4276ebd633dba77b9490c`](https://github.com/apache/couchdb/blob/5a15ed69b49c8dab30a4276ebd633dba77b9490c/src/docs/src/replication/protocol.rst), [PouchDB conflicts, `0ec5a68736e306814f491081eaf31692211af007`](https://github.com/apache/pouchdb/blob/0ec5a68736e306814f491081eaf31692211af007/docs/guides/conflicts.md) | Revision history, resumable change feed/checkpoints, conflict branches | Не принимать автоматическое разрешение конфликта за истину для общих норм и знаний |
| [Trilium sync, `ef70aa157e1101ddb12472955a7803f83ec006ba`](https://github.com/TriliumNext/Trilium/blob/ef70aa157e1101ddb12472955a7803f83ec006ba/docs/Developer%20Guide/Developer%20Guide/Concepts/Synchronisation.md) | Hash-based integrity, revisions/tombstones и видимые sync states | Документ описывает LWW для ряда конфликтов; нам для канонических фактов нужно сохранять обе версии и ждать решения |
| [Apache Tika, `eedcbd14a72f536f8bc1ef3d669037540a2cc196`](https://github.com/apache/tika/blob/eedcbd14a72f536f8bc1ef3d669037540a2cc196/README.md) | Широкое распознавание/извлечение текста/метаданных, структурированный вывод и process isolation парсеров | Это parser toolkit, не база знаний; версия в снимке требует Java 17, поддержка и Windows/RAM должны проверяться |
| [Docling format matrix, `440492ac0d0e14952b32dda28fede7495611c899`](https://github.com/docling-project/docling/blob/440492ac0d0e14952b32dda28fede7495611c899/docs/usage/supported_formats.md) | Unified структурированный output, таблицы, Office/PDF, изображения, email, audio/video | Большой набор optional extras/моделей; не выбирать до оценки локальной производительности и licenses |
| [Unstructured, `ac932052e6e0ba3feab8a6e96b6d4480218e009f`](https://github.com/Unstructured-IO/unstructured/blob/ac932052e6e0ba3feab8a6e96b6d4480218e009f/README.md) | Определение типа и маршрутизация к file-specific partitioner | Отдельные зависимости и качество отличаются по типам; benchmark автора не является нашей проверкой |
| [OWASP File Upload Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/File_Upload_Cheat_Sheet.html) | Defense-in-depth: limits, signature check, sandbox/AV, safe names/paths, decompressed size | Руководство общего характера, не сертификация конкретного parser или конфигурации |

Источники просмотрены по pinned commit, если указан SHA. Не скачивал и не запускал upstream-код, не копировал фрагменты. Для GitHub-репозиториев это выборочный анализ README/docs; отдельные source-level/security/license audits не выполнялись.

## 9. Риски и необходимые решения

| Риск | Уровень | Требование / mitigation |
|---|---|---|
| Общая запись проекта показана не тому агенту/провайдеру | P1 | Project namespace + classification + allowlist ACL до retrieval; default deny; отрицательные cross-project tests |
| Общая база ошибочно становится полным зеркалом проектов | P1 | Admission allowlist, purpose/rights/retention, approval; не импортировать автоматически чаты, secrets, `.env`, сырые логи/репозитории |
| Parser/file causes code execution, RCE, DoS или prompt injection | P1 | Quarantine, parser isolation, no network/macros, quotas, content sniff, archive expansion caps, prompt isolation, updates/advisories |
| Устаревшая common revision выглядит актуальной при offline работе | P1 | Manifest/generation/source commit, explicit `stale/as-of`, stale import blocked from promotion, tombstone/revocation tracking |
| Публикация/restore оставляет смешанные catalog, body, rules или index | P1 | Stage → verify hashes/schema/ACL → atomic generation pointer; crash-injection and rollback evidence |
| Поиск блокирует работу на медленном/отключённом диске | P2 | Measured I/O budget, process-level timeout, cancel/progress, bounded retry, visible `timeout/offline` state, no silent fallback |
| Большой результат съедает контекст или скрывает неполную выдачу | P2 | Search DTO/snippets, hard byte cap before materialization, exact IDs and explicit partial indicator; split long source records |
| Derived index exposes removed/private text after revocation | P1 | Inherit ACL/tombstones, purge/rebuild cache/embeddings/logs; verify deletion and access regression |

Владелец уже принял роли двух баз и локальное расположение общей БЗ. Требуют утверждения в отдельном ТЗ: допустимые классы проектных данных в общей БЗ, кто утверждает публикацию, какие file types должны реально парситься в первой версии, разрешены ли внешние OCR/ASR/embeddings для отдельных классов данных.

## 10. План разработки по зависимостям

1. **Foundation/spec:** внести решение владельца в scope; определить collection/project/record/file identity, classification, audiences, lifecycle, compatibility, support matrix; заполнить FR/NFR/SEC/DATA/OPS IDs и readiness. Код не начинать до READY.
2. **Стабильное ядро двух БЗ:** migration/schema compatibility, local/common source status, safe generation manifest, explicit local-only mode, exact provenance. Не менять file paths в исходниках ради установки на другом диске.
3. **Надёжная локальная БЗ и поиск:** bounded/portable read path; context/search size caps; retrieval eval по языкам и типам; rebuildable local index только после benchmark; long-record modularization; UI показывает источник/freshness/cancel.
4. **Ingest MVP:** allowlist common text/code + Office/PDF/CSV/JSON formats, quarantine, isolated parsers, extraction provenance/anchors, storage-only fallback. OCR/ASR и archive recursion — отдельный opt-in после threat/performance review.
5. **Shared multi-project corpus:** namespace and ACL; promotion workflow; conflict/tombstones; read-only federated search; packages/manifests and versioned pinned snapshots. Никакой автоматической полной синхронизации.
6. **Multi-PC/agent operations:** resumable import/export; backup/restore drills; health dashboard, audit receipts, task/run ledger API. Live task ledger stays separate from durable curated knowledge.

## 11. Критерии приёмки будущего ТЗ

- Перемещение shared/project root между разными буквами диска и доступными каталогами не меняет logical ID; Unicode/пробелы проверяются. Отключённый носитель возвращает bounded timeout/unavailable без ложного `queryable`.
- У проекта А есть private test record. Агент проекта B не может узнать ни содержимое, ни title, ни совпадение, ни snippet, ни vector/cache/log side-channel; общий агент получает только разрешённую аудиторию.
- Search result всегда показывает source collection, project namespace, exact generation/revision/hash, anchor, status and access decision. Неподтверждённая freshness маркируется `unknown/as-of`, не `current`.
- Для каждого поддерживаемого формата тестируются корректное распознавание, spoofed extension/signature, нормальный parse, повреждённый/частичный документ, limit, cancellation, provenance anchor, unsupported fallback и пересоздание derivatives.
- ZIP/XML bomb, path traversal, macro/active content, malicious prompt text, malformed PDF/image, parser crash и disk full завершаются контролируемым `quarantined/failed`, не выходом за квоты и не запуском содержимого.
- Контекст выдаёт полный ограниченный пакет либо явный отказ до сборки ответа; результаты не молча обрезаются. Большие материалы адресуются секциями/фрагментами с устойчивыми ID.
- Повреждение/смена версии индекса приводит к явно отмеченному rebuild из исходника; индекс не единственный экземпляр знаний и может быть удалён/пересоздан.
- Два offline ПК редактируют одну logical record; импорт сохраняет две конфликтующие версии, повторная доставка идемпотентна, stale client не удаляет/не перезаписывает accepted/revoked version.
- Backup/restore на другой путь проверяет manifest/hash/count/ACL до активации, не теряет inbox/originals, умеет rollback; измеряются RPO/RTO.
- На эталонном ПК публикуются p50/p95/p99, memory, indexing progress and cancel latency для согласованных corpus/file profiles. Порог не назначается без baseline.

## 12. Ограничения исследования и следующий шаг

**Глубина:** R2 — targeted OSINT/Deep Research плюс внутренние роль-проверки. GitHub shortlist не исчерпывающий; views закреплены SHA, но полнота issues/advisories и runtime production behavior не проверялась. Внешние модели, сервисы и GitHub не получили проектные файлы/секреты. Архитектура и стек не утверждены; это не аудит безопасности выбранной реализации.

**Вывод о готовности:** T-004 — ограниченный текстовый MVP с integrity checks и безопасным capture в draft inbox. Обе локальные поставки согласованы по базовым файлам правил и CLI. Общая БЗ пока не подключена к запросам проектов; общего проекта каталога, namespace/ACL, мультимодального ingestion, publisher, conflict protocol, index lifecycle и автоматизированного restore нет. Поэтому текущую систему нельзя считать готовым вторым мозгом для нескольких проектов и агентов.

**Следующий шаг:** открыть отдельный READY-спек на multi-project knowledge data model + file-ingestion MVP, включив решения владельца и перечисленные открытые политики; затем оценить безопасный первый форматный набор. До него не выбирать parser stack, embeddings, database engine или transport.

## Источники по security файлов

- [OWASP File Upload Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/File_Upload_Cheat_Sheet.html): content/type/signature checks, quarantine/sandbox/AV when available, limits after decompression, unsafe archive/parser threats.
- [SQLite FTS5](https://www.sqlite.org/fts5.html): external index consistency, rebuild and integrity-check.
- [SQLite WAL](https://sqlite.org/wal.html): same-host requirement; WAL is not for network filesystems.
- [SQLite interrupt](https://www.sqlite.org/c3ref/interrupt.html) and [progress handler](https://www.sqlite.org/c3ref/progress_handler.html): cancellation/progress primitives for future DB query/index work.
