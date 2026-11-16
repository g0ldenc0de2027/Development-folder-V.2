# T-010 — Согласовать правило проектной и портфельной БЗ

- **Статус:** in_progress; владелец расширил уточнение на цикл поиска, исследования и переноса знаний; код инфраструктуры не включён
- **Версия задачи:** v1.4.0 · 2026-11-16
- **База:** f577dc70e58d75ab5fd61d0c2e712c27b590713a (`origin/main`)
- **Ветка/worktree:** `task/T-010-kb-portfolio-scope`
- **Автор:** OpenAI Codex (GPT-6)
- **Зависимость:** каноническая редакция общей БЗ `codex/portfolio-kb-scope`; V2 mirror сохраняет exact bytes и policy-lock

## Решение владельца

Одна папка разработки — один проект; локальная БЗ хранит ценное только по этому проекту.
Общая БЗ собирает важные сведения из локальных БЗ всех проектов и принимает прямые
записи владельца на любую тему, включая не связанную с разработкой. Она предназначена
как общий источник для всех допущенных агентов и будущих проектов, с обязательными
scope, classification, audience и provenance.

На старте содержательной задачи проверяются обе БЗ. Если в них нет актуального ответа
или тяжёлый случай остаётся непонятным, правила требуют OSINT, Deep Research, профильных
экспертов и сравнения выполнимых вариантов. После работы полезный проверенный результат
сохраняется в локальную БЗ; значимое для портфеля или указанные владельцем сведения
предлагаются общей через контроль provenance, свежести, безопасности, лицензии и доступа.

## Цель

Согласовать правила 1, 17 и 20 общей БЗ и зеркала V2 с уточнённой моделью владельца.
Добавить архитектурную спецификацию будущего lifecycle со статусом DRAFT / NOT READY.
Не заявлять, что федеративный поиск, ACL, publisher, парсеры или рой агентов уже реализованы.

## Зона файлов V2

- README.md
- `tasks/T-010-align-project-and-portfolio-kb-scope.md`
- `rules/RULES.md`
- `rules/COVERAGE.md`
- `rules/modules/01-knowledge-and-calibration.md`
- `rules/modules/07-research-and-decisions.md`
- `rules/policy-lock.json`
- `knowledge/README.md`
- `spec/local-knowledge.md`
- `spec/СОСТОЯНИЕ.md`
- `spec/portfolio-kb-agent-workflow.md`
- `specification-system/tz_state.md`
- `docs/local-knowledge.md`
- `docs/handoff.md`

Каноническая общая БЗ изменяется отдельно в ветке codex/portfolio-kb-scope:
README.md и соответствующие rules/ файлы с policy-lock. V2 получает точную копию
нормативных файлов после проверки байтов и lock.

## Критерии приёмки

1. Локальная БЗ однозначно ограничена одним проектом; общая БЗ включает отобранные
   проектные сведения всех проектов и прямые записи владельца любой тематики.
2. Нормы требуют на старте содержательной задачи проверять обе базы и сохранять
   проверенные результаты сначала локально.
3. Для тяжёлого случая с недостатком данных/ясности обязательны OSINT, Deep Research,
   профильные экспертные роли и обоснованный выбор лучшего целесообразного решения.
4. Promotion в общую БЗ сохраняет исходный локальный источник и проходит provenance,
   freshness, conflict, duplication, privacy, license, scope и audience checks.
5. Доступ фильтруется до поиска и производных представлений; при отсутствии ACL закрытая
   проектная запись не выдаётся в общую. Не объявлять автора/agent из метаданных identity.
6. spec/portfolio-kb-agent-workflow.md содержит роли, lifecycle, file matrix, security,
   reliability, acceptance и open decisions; статус DRAFT / NOT READY не допускает реализацию.
7. Текущее состояние CLI и пробелы федерации, ACL, promotion и file ingestion изложены
   согласованно; V2 rule package соответствует канону общей БЗ и lock.
8. Не вносить код парсеров, embeddings, OCR/ASR, publisher, ACL или coordinator в T-010.
9. Каждый изменённый V2-путь перечислен в зоне задачи; полный diff не содержит изменений вне неё.
10. DRAFT-спецификация отделяет предложенный baseline форматов от утверждённого scope, задаёт блокирующие решения по форматам и конкурентной записи, определяет изоляцию парсеров и раздельный lifecycle quarantined → isolated-processing → derived-quarantined → review/release; содержит проверяемые критерии без заявления о работающей реализации.
11. Для parser-run, review и release заданы раздельные права; ошибки, истёкший receipt, смена hash/политики, частичный вывод и egress без отдельного допуска остаются закрытыми; при WSB-конкуренции задания сериализованы, гость закрывается/удаляется после задания и запускается заново; данные между заданиями не смешиваются.
12. Исследовательские выводы ссылаются на первичные источники; источники не трактуются как доказательство безопасности конкретной реализации.

## Проверки и статус

- Общая БЗ: pwsh -NoProfile -File scripts/kb.ps1 check — PASS (integrity=pass, 2 records, 9 rules files); tests/kb-regressions.ps1 — 44 passed, 0 failed.
- V2: pwsh -NoProfile -File scripts/quality-gate.ps1 -BaseRef origin/main — PASS, exit 0 на текущем worktree после всех изменений T-010.
- Gate покрыл 39 Markdown-документов и regression source, hygiene — 57 текстовых файлов, actionlint — PASS, Gitleaks — PASS для worktree/reachable history/push ranges (46 commits). Stack build/dependency audit — NOT COVERED: стек приложения не выбран.
- git diff --check прошёл в обоих репозиториях. RULES, COVERAGE, Rule 1/20 modules и policy-lock побайтно совпадают; package 0.4.0, lock hashes проходят.
- Внутренние read-only роли Codex (policy/reliability/privacy) — APPROVE на Rule 20 и DRAFT lifecycle, включая карантин и WSB; это не внешний cross-vendor review. Перед merge получить внешний independent review на точных опубликованных heads.
- Hosted CI и review — изменяемые данные: перед слиянием сверить текущие head/base/test SHA и результат по live PR #2 общей БЗ и PR #9 V2. Предыдущая CI-ревизия не подтверждает новый head; merge не выполнялся.
## Ограничения

Эта задача меняет назначение и границу текстового правила. Она не реализует схему многопроектного каталога, классификатор, ACL, синхронизацию, ingestion, OCR/ASR или новый parser stack. Подтверждённое владельцем требование поддержки основных типов файлов остаётся целевым требованием для обеих БЗ и требует отдельного READY-спека до реализации.
