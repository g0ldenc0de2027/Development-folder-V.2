# Исследование: многоформатная локальная и портфельная БЗ

- Версия: 1.1.0-draft
- Дата: 2026-11-18
- Глубина: R2 — архитектурное сравнение и targeted source review
- Область: Development Folder V2, локальная проектная БЗ и общая портфельная БЗ
- Статус: рекомендация, не решение о внедрении

## Краткий вывод

Текущий файловый контракт полезен для текстовых записей и правил, но не покрывает требование владельца об основных типах файлов. Нужен отдельный, версионируемый конвейер источников и производных материалов с проверяемой матрицей по каждому формату и режиму обработки. Формат нельзя объявлять поддержанным до тестов, лимитов и проверки безопасности.

Рекомендация: слоистая архитектура с заменяемыми локальными адаптерами; неизменяемый оригинал; производные текст/структура/OCR/ASR связываются с SHA исходника и параметрами обработчика. Тяжёлую обработку вынести из CLI/UI в ограниченный worker; результат публиковать атомарно после проверок.

## Текущий срез, проверенный через CLI и документы

- V2 local KB CLI check на ветке T-014: PASS по структурной целостности, 4 записи, правила 9/9; truth=not_assessed, reviewIdentity=not_authenticated. Это не подтверждает истинность или личность reviewer.
- V2 doctor: sharedStatus=not_configured, federatedSearch=not_implemented, compatibility=not_verified. Общая БЗ не обнаруживается автоматически, federated search нет.
- Каталог V2 использует Markdown bodies и JSON metadata; поиск literal. Запросы по импорту не нашли существующей записи, но это не доказывает отсутствие знания во всех материалах.
- Общая БЗ прошла CLI check по integrity. Её CLI не принимает MaxOutputBytes, присутствующий в текущем T-014 V2 snapshot; это расхождение контрактов/версий для отдельного решения.
- Прочитаны local records local-first и swarm-boundaries, shared record common-rules. Все draft, поэтому использованы как подсказки, не как принятая истина.
- Сверены spec/local-knowledge.md, docs/local-knowledge.md и README общей БЗ. Сквозной импорт Office/PDF, OCR/ASR, архивов и мультимедиа не заявлен реализованным.

## Требования владельца и границы памяти

1. Одна папка разработки — один проект; local KB используется только им.
2. Общая БЗ — память портфеля всех проектов и прямых owner entries на любые темы.
3. Обе коллекции в перспективе работают с основными типами материалов.
4. Перед содержательной работой ищутся local и доступная shared БЗ; новая находка сначала сохраняется локально.
5. Promotion в shared требует проверки происхождения, свежести, конфликтов, приватности, безопасности, лицензии, scope и аудитории.
6. Локальная обработка и отсутствие egress — default; внешнему сервису передаются только явно разрешённые данные.
7. В shared KB не проверены record-level ACL и authenticated access filtering. Закрытые материалы туда не переносятся до внедрения и валидации enforcement.
8. Внешняя БЗ может лежать на любом выбранном диске/пути; личный абсолютный путь не закрепляется в коде или portable metadata.

## Идеи из аналогов

| Решение | Полезная идея | Граница |
|---|---|---|
| Paperless-ngx | Lifecycle документов, версии и видимые сбои; оригинал отдельно от производных | Не переносить серверную архитектуру целиком |
| Khoj | Различать разовую загрузку и длительную синхронизацию источника | Синхронизация требует отдельной модели изменений и прав |
| Onyx | ACL применяются в retrieval до передачи chunks агенту | Пока ACL shared KB не подтверждён, это целевое требование, не функция |
| Docling | Широкий extraction interface и структурированный результат | Модели могут загружаться при первом использовании; лицензии моделей отдельны |
| MarkItDown | Лёгкая конвертация документов в Markdown | Работает с правами вызывающего процесса; это не sandbox |
| SQLite FTS5 | Возможная локальная лексическая индексация | Добавлять только после benchmark текущего literal search |

## Сравнение вариантов

| Подход | Преимущества | Ограничения | Оценка |
|---|---|---|---|
| Парсер внутри PowerShell CLI | Простая поставка без runtime | Hostile input и долгие операции могут подвесить или скомпрометировать host | Не подходит для произвольных файлов |
| Один универсальный parser | Быстро широкий охват | Привязка к runtime, моделям, формату вывода, лицензиям и advisories | Кандидат только после пилота |
| Набор разрозненных конвертеров | Можно взять инструмент для каждого формата | Разные поставки/lifecycle/error contracts | Не как исходная архитектура |
| Adapter pipeline и отдельные workers | Изоляция, управляемые лимиты, замена адаптера без смены KB-контракта | Требуется durable job state и сопровождение workers | Рекомендуется |

## Рекомендуемый pipeline

1. Пользователь выбирает файлы или утверждённый корень импорта; автоматическое сканирование диска не включается.
2. Intake делает неизменяемый quarantine snapshot и считает raw SHA-256/размер; парсер работает с ним, не переоткрывая исходный путь.
3. Проверяются выбранный root, reparse points, сигнатура, extension mismatch, capability и лимиты. Неизвестный формат — UNSUPPORTED/REJECTED.
4. Адаптер работает в least-privilege worker без tool access и сети. ОС-изоляция ограничивает filesystem/network; Windows Job Object даёт процессные и ресурсные лимиты, но не является sandbox.
5. Оригинал не меняется. Text/structure/OCR/ASR/preview/chunks — производные с own hash, parser/version/config/language и parent source SHA.
6. Import имеет durable job ID, progress, cancel/retry и crash recovery. Ошибка одного файла не останавливает пакет; повтор идемпотентен.
7. Только проверенный итог публикуется атомарно. Извлечённый текст остаётся недоверенными данными, не командами и не полномочиями.
8. Поиск сохраняет exact locator: страница PDF, лист/диапазон, слайд, раздел или media timestamp.
9. Импорт не равен admission знаний. Reviewed/accepted — отдельная проверка; local-to-shared — отдельное предложение.

## Предлагаемые фазы поддержки

| Фаза | Кандидаты | Gate перед объявлением поддержки |
|---|---|---|
| 0. Intake foundation | Источники/hash/catalog, portable storage, очередь и статусы, no egress | Threat model, storage, limits, restore |
| 1. Digital docs | MD/TXT/HTML/CSV/JSON; text-layer PDF; DOCX/XLSX/PPTX | Parser fixtures, structure/fidelity, citations, sandbox, limits, offline install |
| 2. Scans/images | Image-only PDF, PNG/JPEG/TIFF + OCR | Local model/license, offline prefetch, confidence/resource tests |
| 3. Containers | Выбранные ZIP и EML/MSG | Expanded bytes/count/depth caps; traversal/link/duplicate/cancel tests |
| 4. Audio/video | Выбранные WAV/MP3/MP4 + ASR | Model/license/size, local speed/quality, timestamp citations |

Это план проверки, не обещание поддержки. Матрица должна показывать supported/partial/metadata-only/unsupported/failed по конкретным форматам.

## Обязательные риски и controls

- Hostile input: изолированный worker + memory/CPU/time/process caps; если enforceable isolation нет — NOT COVERED, обработка запрещена.
- Prompt injection/document poisoning: документ не может выдавать инструменты, доступ, задачи или egress.
- Egress: network deny для workers; удалённые OCR/embedding/reranker выключены; отдельное approval перечисляет источник, поля, получателя и цель.
- ZIP/path/reparse risks: лимиты распаковки/элементов/глубины; не распаковывать в произвольные пользовательские пути.
- PDF/Office active behavior: не запускать COM/Office, macros, formulas, PDF JS, внешние связи/URL; XML external entities отключить.
- Shared confidentiality: ACL применяется до retrieval; без него закрытые originals/derivatives остаются local.
- Надёжность: durable jobs, idempotency, atomic publish, retries, явные failure codes, crash recovery.
- Portability: хранить managed originals/metadata в выбранном root; absolute личные пути не в каталоге; restore сверяет hashes.
- Supply chain: exact parser/model pins, лицензии кода и каждой модели, advisories, malicious-file regressions.

## Открытые решения и пределы

- Утвердить первый набор форматов, сохранив конечную цель охвата основных категорий.
- Утвердить managed import (оригинал копируется в root БЗ) или reference (только внешняя ссылка).
- Решить at-rest encryption и переносимое восстановление до импорта sensitive data.
- Задать размер установки/model cache и правило offline prefetch без auto-download.
- Подготовить synthetic/разрешённый корпус; не класть личные документы в public fixtures.
- Утвердить лимиты размера/страниц/вложений/времени/параллелизма после оценки реальных workload.

Файлы владельца не обрабатывались. Не измерялись скорость, размер пакетов, качество OCR/ASR, Windows runtime compatibility, лицензии для выпуска или реальное OS isolation. Код доноров не скачивался и не запускался.

## Дополнение: память и задержка локального CLI (2026-11-18)

- **Ранее измеренный benchmark T-014:** карточка T-014 фиксирует однократный синтетический прогон 1 000 записей по 1 024 байта (каталог 354 103 байта): 9,60 → 8,05 с; working set 145,4 → 142,3 МиБ; private peak 82,9 → 75,1 МиБ. Он сравнивал варианты `Read-Bytes`, а не максимальный корпус из 1 000 тел по 262 144 байта; цифры не доказывают поведение на расчётной верхней границе. В T-017 прогон не повторялся.

- **Автор и основание:** Codex (OpenAI), GPT-6; read-only разбор T-014 HEAD 1abcd6edcd7c039d13399c6b8433890e99c1c7d5. Вывод дополнительно проверили два внутренних Codex subagents по архитектуре и QA/надёжности; это не внешний vendor review.
- **Наблюдение:** `scripts/kb.ps1:152` ограничивает отдельное тело 262 144 байтами; `:239` разрешает до 1 000 записей. `Load-Catalog` читает и декодирует каждое тело, а затем удерживает все тела в `$entries` (`:257–279`); `Select-Entries` применяет `-Limit` позднее (`:286–294`). `-MaxOutputBytes` проверяется после `ConvertTo-Json` (`:416–420`). Поэтому `search -Limit 1` и `get` всё равно проверяют и временно удерживают весь корпус.
- **Расчёт верхней границы:** 1 000 × 262 144 = 262 144 000 байт, то есть 250 MiB сырых тел. Для ASCII-heavy текста .NET-строки могут занимать примерно вдвое больше; это около 500 MiB только строк тел, без объектов, каталогов, правил и сериализации. Это расчёт по текущим ограничениям, не измеренный peak working set.
- **Оценка:** это известный предел рабочей памяти/задержки и риск роста корпуса, явно исключённый из acceptance T-014; он не опровергает выполненные критерии T-014. Полная проверка всех хэшей, секретных паттернов и orphan-файлов сохраняет целостность корпуса, но требует читать весь набор на каждом поиске.
- **Варианты:** (A) потоково проверять записи по одной и удерживать только тела выбранных результатов, продолжая проверку всех последующих записей; (B) ввести общий лимит байтов корпуса, что ограничит рост допустимого хранилища; (C) внедрить FTS/index для задержки поиска, добавив жизненный цикл индекса и риск расхождения с источниками.
- **Рекомендация:** следующим отдельным scoped change после review/merge T-014 выбрать (A), сохранить порядок каталога, literal case-insensitive поиск, статусы, полные тела результатов и fail-closed проверку записей за пределами -Limit. Опцию (C) рассматривать лишь после benchmark, сравнивая её с текущим literal Contains; FTS5 токенизирует запрос и поддерживает собственный операторный синтаксис, поэтому это не эквивалентная замена без отдельного контракта.
- **Проверки перед реализацией:** регрессия, где повреждённая или запрещённая запись расположена после первого совпадения при -Limit 1 и всё равно даёт отказ с пустым stdout; сохранение порядка/статусных фильтров, полного тела, get и context budget; синтетический benchmark representative/max corpus с runtime и peak working set. Не вводить жёсткий CI-порог по памяти без стабильной методики/инструментации.
- **Источники:** исходный T-014 код и task/spec ограничения зафиксированы в источниках этого дополнения; официальные FileStream.Read и .NET file-reading guide описывают блочное чтение и ReadToEnd; официальный SQLite FTS5 reference задаёт токенизацию и синтаксис запросов. Ни benchmark, ни изменение кода в этом дополнении не выполнялись.
## Источники и закреплённые наблюдения

Проверено 2026-11-18. GitHub SHA — default branch snapshot, полученный в эту дату.

- [Docling README @ ce69639a](https://github.com/docling-project/docling/blob/ce69639a64683598b915e003ee5e65b5c03454bd/README.md) — форматы, runtime и отдельные model licenses.
- [Docling offline/model prefetch docs](https://docling-project.github.io/docling/usage/advanced_options/) — first-use download по умолчанию и offline prefetch.
- [MarkItDown README @ ed178952](https://github.com/microsoft/markitdown/blob/ed178952a6672abdfd35b5f9e76a80b6cefc086e/README.md) — I/O с правами вызывающего процесса и ограничения untrusted input.
- [Paperless-ngx docs @ 7977093e](https://github.com/paperless-ngx/paperless-ngx/tree/7977093e83dd215be54273ccf77d2ab98be577b3/docs) — document versions/lifecycle/error handling.
- [Khoj upload/sync docs](https://docs.khoj.dev/data-sources/share_your_data/) — upload и continuous sync — разные workflows.
- [Onyx filter semantics @ 0ac4c33c](https://github.com/onyx-dot-app/onyx/blob/0ac4c33cd2f52b3536b239ce65d20c32954dee9a/backend/onyx/document_index/FILTER_SEMANTICS.md) — ACL и knowledge scope как retrieval filters.
- [SQLite FTS5](https://www.sqlite.org/fts5.html) — возможная lexical search ступень, технология не выбрана.
- [Microsoft AppContainer](https://learn.microsoft.com/en-us/windows/win32/secauthz/appcontainer-isolation) и [Job Objects](https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects) — complementary isolation/resource controls.
- [OWASP prompt-injection guidance](https://cheatsheetseries.owasp.org/cheatsheets/LLM_Prompt_Injection_Prevention_Cheat_Sheet.html) и [RAG Security](https://cheatsheetseries.owasp.org/cheatsheets/RAG_Security_Cheat_Sheet.html) — ingestion/retrieval/provenance/access/egress risks.

## Кто проводил анализ

Первичный R2 синтез провели три Codex subagents (архитектура; поиск/эксплуатация; безопасность). Дополнение о рабочей памяти T-014 проверили два Codex subagents (архитектура; QA/надёжность). Это внутренние потоки одной AI-поставки, не независимое vendor review и не внешние специалисты. Источники каждого слоя указаны отдельно.
