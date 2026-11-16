# Связь правил с исполнением

Редакция 0.4.0, 2026-11-16. Область: текущий текстовый срез и явные пробелы покрытия.
Это карта текущего охвата; обязательства нормы определяются соответствующим модулем.

| Правило | Механизм/свидетельство | Охват и пробел |
|---|---|---|
| 1 | kb.ps1 check/search/get/context/capture/doctor | Поиск в обеих БЗ обязателен, но сейчас выполняется вручную по одной коллекции за вызов. Пространства проектов, ACL на записи, объединённый поиск и безопасное продвижение не реализованы. Приём и обработка основных форматов, а также изоляция парсеров остаются будущим scope |
| 2 | Карточка задачи и bounded scope review | Организационный контроль; общего enforcement процесса нет |
| 3 | quality-gate.ps1, actionlint, Gitleaks, KB regressions | Host scope; application coverage/performance/SBOM/DAST NOT COVERED |
| 4 | Regression failing-before/passing-after, draft capture | Автоматического продвижения урока в accepted нет |
| 5 | Task worktree, scope diff, task card | Scope guard пока ручной; swarm dispatch/inbox/leases не реализованы |
| 6 | AGENTS и назначение владельца | Procedural role, не OS auth |
| 7 | ТЗ и будущий UI acceptance | UI/tokens/screenshots/contrast NOT COVERED: UI пока отсутствует |
| 8 | Effective toolchain inventory, repo requirements | Полного freshness радара всех стеков нет |
| 9 | AGENTS/README/skill provenance review | Payload генератора V2 ещё нет; synchronization claims не заявляются |
| 10 | Ignored temp/data, scoped cleanup | Retention/backup требуют отдельной настройки; age-delete не разрешён |
| 11 | Документированные JSON/CLI и отрицательные KB-тесты | Прикладные API/БД/worker профили NOT COVERED |
| 12 | pre-push, live ruleset, PR/CI tuple | Local controls обходятся владельцем; no-App residual risk; release workflow не готов |
| 13 | Требования и карточки | Полный denominator/progress/ETA ledger V2 не реализован |
| 14 | Gitleaks/history, actionlint, KB path checks | Не общий security audit; security-watch/onboarding не реализованы |
| 15 | Regression утверждённых locale IDs в policy | Это проверка нормы; UI keys/plural/layout всех 10 языков NOT COVERED |
| 16 | docs/local-knowledge.md, RU/EN и command scenarios | Полный валидатор полноты справки/переводов не реализован |
| 17 | Доказательства, альтернативы и решение владельца | Сравнение вариантов — процессная норма; автоматического decision record gate нет |
| 18 | Scoped READY в spec/local-knowledge.md, tz_state | Весь продукт остаётся DRAFT; universal spec gate V2 не реализован |
| 19 | Source ID/commit/coverage donor report | Донорский код не импортирован; exhaustive audit не заявлен |
| 20 | Исследование R0–R3, источники, экспертные роли | Во всех тяжёлых случаях обязательны OSINT, Deep Research и профильные специалисты; для R2/R3 — 2–4 независимые экспертные роли, для R3 — отдельная итоговая проверка. Автоматическое назначение экспертов, учёт участия и проверка независимости пока не реализованы |

Полнота пакета: policy-lock schema 2 фиксирует index, все модули и эту карту;
check/context сверяют каждый файл. Изменённый/непоставленный файл блокирует чтение пакета.
Никакая строка карты не подтверждает будущую capability до её реализации и испытания.
