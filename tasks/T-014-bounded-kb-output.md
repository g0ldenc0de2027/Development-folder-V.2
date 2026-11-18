# T-014 — Ограничение объёма выдачи локальной БЗ

- **Статус:** in_progress
- **Ветка/worktree:** `task/T-014-bounded-kb-output` / `.worktrees/T-014`
- **База:** `f577dc70e58d75ab5fd61d0c2e712c27b590713a` (`origin/main`; сверена с live `origin/main` 2026-11-17)
- **Автор:** Codex, GPT-6
- **Основание:** прямое поручение владельца от 2026-11-17 провести полный аудит и улучшать локальную БЗ.

## Проблема

Воспроизведено на T-009: `search -Query local-first -Limit 1 -MaxBytes 512` завершился успешно и выдал 75 629 UTF-8 байт, включая тело записи 71 854 байта. `MaxBytes` документирован только для `context`; у `search/get` нет явного ограничения ответа. Это не нарушение прежнего контракта, а подтверждённый риск неконтролируемого размера ответа.

Дополнительно в ходе аудита локальной БЗ воспроизведён разрыв LKB-001: schema 2 lock только с `rules/RULES.md` и индекс без локальных ссылок проходил `check` с exit 0, хотя READY-контракт требует полный пакет из индекса, семи модулей и карты охвата. Тест `LKB-001 index-only policy package is refused` зафиксировал прохождение такого fixture до исправления.

## Решение

Добавить отдельный параметр `-MaxOutputBytes` для полных JSON-ответов `search` и `get`: default 131072 байта, диапазон 512–2097152. При превышении возвращать `KB_OUTPUT_LIMIT`, exit 1 и пустой stdout. Не урезать JSON/записи. Существующий `-MaxBytes` и код отказа `KB_CONTEXT_LIMIT` для `context` оставить без изменений. Текущие поля и полные тела записей при успешном ответе сохранить.

PowerShell принимает значения `Command` из `ValidateSet` без учёта регистра. Поэтому проверка бюджета обязана одинаково охватывать все принятые варианты написания команды; верхний регистр нельзя трактовать как обход.

Для уже принятого LKB-001 проверять в schema 2 lock точное множество девяти канонических путей RULES: индекс, модули 01–07 с фиксированными именами и `rules/COVERAGE.md`. Отсутствующие, заменённые, лишние и повторные пути отклонять как `KB_POLICY_LOCK`, даже если индекс перестал ссылаться на пакет; ссылку на незакреплённый файл — как `KB_POLICY_LINK`.

## Зона файлов

- `scripts/kb.ps1`
- `tests/kb-regressions.ps1`
- `spec/local-knowledge.md`
- `spec/СОСТОЯНИЕ.md`
- `specification-system/tz_state.md`
- `docs/local-knowledge.md`
- `docs/handoff.md`
- `tasks/T-014-bounded-kb-output.md`

## Приёмка

1. Спецификация определяет параметр, default/range, подсчёт UTF-8 байтов сериализованного JSON вместе с завершающей новой строкой, fail-closed поведение и отсутствие обрезания.
2. `search` и `get` не пишут частичный/полный JSON в stdout при превышении бюджета; stderr содержит только короткий стабильный код. Любые написания команд, принимаемые `ValidateSet` (включая `SEARCH` и `GET`), имеют тот же предел.
3. Regression cases покрывают Unicode byte-count (многобайтный текст), превышение бюджета обеими командами в нижнем и верхнем регистре, пустой stdout при отказе и успешную полную выдачу при достаточном бюджете.
4. Контракт `context -MaxBytes` и существующие проверки остаются прежними.
5. Локальные KB-регрессии и quality gate проходят на точном HEAD/рабочем diff; scope, handoff и `git diff --check` согласованы.
6. Fixtures моделируют полный девятифайловый пакет; сокращение lock до одного индекса, пропуск канонического модуля, изменение его байтов, отсутствие файла, незакреплённая ссылка и дубликат отклоняются ожидаемыми кодами.
7. LKB-003 permits only supported local fixed/removable volumes. Project-root ancestors are checked for reparse points before volume detection, preventing a parent junction from redirecting volume checks. For NTFS/ReFS/UDF, `fsutil hardlink list` checks the catalog, record bodies and `.etalon.json` when there are at most 24 records; larger catalogs use link count from `GetFileInformationByHandle` on the open handle. Exactly one link is required. FAT/FAT32/exFAT are accepted because they do not support hard links; network/unknown volume, unsupported filesystem, or unavailable/ambiguous enumeration fails closed. Pinned rule files remain protected by SHA-256 lock.

## Audit follow-up: hard-link alias in LKB-003 (2026-11-18)

Во время полного аудита локальной БЗ synthetic NTFS fixture показал, что hard link из файла вне корня проекта в `knowledge/records` проходит reparse-проверку и `get` возвращает его тело. Это обход логической границы каталога; он не означает, что CLI является OS sandbox. Малый каталог проверяется штатной `fsutil hardlink list`; при числе записей больше 24 применяется `GetFileInformationByHandle` по открытому handle, чтобы избежать процесса на каждую запись. Microsoft описывает hard link как несколько путей к одному файлу, а справка fsutil документирует команду `list`: [Hard links and junctions](https://learn.microsoft.com/en-us/windows/win32/fileio/hard-links-and-junctions), [fsutil hardlink](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/fsutil-hardlink). [Сравнение поддерживаемых функций файловых систем](https://learn.microsoft.com/en-us/windows/win32/fileio/filesystem-functionality-comparison/) подтверждает отсутствие hard links в FAT32/exFAT.

Scope расширен только для устранения этого LKB-003 дефекта: `scripts/kb.ps1`, `tests/kb-regressions.ps1`, `spec/local-knowledge.md`, `docs/local-knowledge.md`, `docs/handoff.md` и эта карточка.


## Ограничения

Лимит ограничивает stdout-ответ, но не обещает ограничить объём чтения/внутреннюю память до сериализации. Не менять схему каталога, статус admission знаний, поиск по shared KB или transport к AI-провайдерам.

## Проверка исходного среза (до case-variant follow-up)

- Полный gate выполнен на рабочем содержимом поверх committed HEAD `3f75090c6e236aca7ffb5533a83e7f7302e71f18` и базы `origin/main` `f577dc70e58d75ab5fd61d0c2e712c27b590713a`: KB-regressions — 52/52 PASS; PowerShell AST и `git diff --check` — PASS. Scoped commit содержит ровно это проверенное содержимое.
- `quality-gate.ps1 -BaseRef origin/main` — PASS: 6 PowerShell files parsed; privacy — 38 Markdown plus regression source; hygiene — 56 text files; Actionlint PASS; Gitleaks PASS (64 reachable commits, рабочее дерево и supplied push range).
- Application stack build/dependency audit — NOT COVERED, стек не выбран. Hosted CI и независимое review требуются на опубликованном SHA этой правки; результаты старого PR head не переносятся.

## Follow-up проверка регистра (2026-11-18)

- Внутренний read-only review точного PR head `7715450d0664eb9c64a3f0e5e42eb814f187ac37` обнаружил обход: `ValidateSet` принимает команды без учёта регистра, а `-cin` пропускал `SEARCH/GET` мимо лимита. Новые фикстуры воспроизвели дефект до исправления; после замены на `-in` регрессии прошли 52/52 (exit 0).
- Полный `pwsh -NoProfile -File scripts/quality-gate.ps1 -BaseRef origin/main` на текущем working diff поверх HEAD `7715450d0664eb9c64a3f0e5e42eb814f187ac37` и base `f577dc70e58d75ab5fd61d0c2e712c27b590713a`: **PASS, exit 0**; KB regressions 52/52, PowerShell/JSON parse PASS, privacy 38 Markdown + regression source, hygiene 56 text files, Actionlint PASS, Gitleaks PASS (65 commits, working tree и push range). `git diff --check`: **PASS, exit 0**.
- Hosted run `#44192782023` относится к прежнему head и fix не подтверждает. Перед merge нужны свежие CI и независимое review точного live head; стековая сборка/dependency audit не применяются к docs-only template без выбранного стека.

## Поведенчески нейтральная оптимизация чтения (2026-11-18)

- Read-Bytes проверяет длину открытого файла под FileShare.Read, затем выделяет буфер фактического размера плюс один байт, а не максимального лимита для каждого файла. Контракт Maximum, hash/UTF-8/secret validation и отказ для payload выше лимита не меняются.
- Добавлена регрессия на точный верхний размер записи (262144 байта); существующая проверка размера на один байт выше сохранена.
- Синтетический benchmark: 1000 записей × 1024 байта, каталог 354103 байта. Старый вариант: 9.60 с, working set 145.4 МиБ, private peak 82.9 МиБ; временный вариант: 8.05 с, 142.3 МиБ, 75.1 МиБ. Распознанные JSON-значения совпали. Расчётные суммарные read-buffer allocations: 250 МиБ → 0.98 МиБ. Однократный benchmark, не универсальная гарантия.
- Ограничение T-014 сохраняется: CLI не обещает верхнюю границу совокупной внутренней памяти или сериализации для всего корпуса.

## Проверка после оптимизации (2026-11-18)

- База перед изменением: HEAD fc0d391bf1ccbeae4ddb359a348c11a25eeb26ba; origin/main f577dc70e58d75ab5fd61d0c2e712c27b590713a.
- Полный quality gate на рабочем diff: PASS, exit 0; 53 KB regressions; шесть PowerShell files parsed; privacy 38 Markdown плюс regression source; hygiene 56 text files; Actionlint PASS; Gitleaks PASS (68 commits). git diff --check PASS.
- Изменение кода зафиксировано как 440a792 и прошло полный local quality gate на точном committed HEAD: 53 regressions, parse/privacy/hygiene/Actionlint/Gitleaks PASS. Hosted run #44192782023 относится к более раннему head; актуальные CI и независимое review проверяйте на live PR #12.

## Проверка после hard-link follow-up (2026-11-18)

- Quality gate был выполнен на рабочем diff поверх parent HEAD `4860a453b241a1c7dd135e03bcadc401a5253484` и base `origin/main` `f577dc70e58d75ab5fd61d0c2e712c27b590713a`; после фиксации у ветки будет новый commit SHA.
- Полный `quality-gate.ps1 -BaseRef origin/main`: PASS, exit 0; 57/57 KB-регрессий; PowerShell/JSON parsing PASS; privacy — 38 Markdown и regression source; hygiene — 56 text files; Actionlint PASS; Gitleaks PASS (70 commits, рабочее дерево и push range).
- Обе hard-link регрессии прошли: hard-linked catalog и внешний alias записи возвращают `KB_HARDLINK`, stdout пуст. До исправления regression для записи возвращала тело внешнего synthetic-файла. `git diff --check`: PASS, exit 0 на финальном documented diff.
- Всегда-компилируемый P/Invoke вариант дал около 46% замедления на малом каталоге, поэтому выбран адаптивный режим: `fsutil` до 24 записей, same-handle API выше порога. Для малого текущего KB: 6 запусков после 2 прогревов, медиана 861.5 мс на parent HEAD и 965.4 мс на рабочем diff (примерно +12%); это локальная оценка, не гарантия для других дисков и систем. Отдельная 25-record регрессия покрывает native path.
- Hosted CI и независимое review нужны на новом опубликованном SHA; старый run PR #12 относится к предшествующему head. Application stack build/dependency audit остаётся NOT COVERED, поскольку стек эталона не выбран.

### CI follow-up

- Hosted run [#44228007156](https://github.com/g0ldenc0de2027/Development-folder-V.2/actions/runs/44228007156) checked PR head `e19ef86865f86036cad94a48e5b6de25b3ac0ff0` against base `f577dc70e58d75ab5fd61d0c2e712c27b590713a`; event/test merge-result `d117b12cd806889cd33c217ca91f98bbeb12aaf0` has those exact parents. It failed in the external hard-link regression. The old assertion required only `KB_HARDLINK`, and the failure log did not include the actual error code or stdout length; the cause is therefore not inferred.
- The regression now accepts either `KB_HARDLINK` or the specified `KB_LINK_ENUMERATION_UNAVAILABLE`, but only when exit is 1 and stdout is empty. The full local quality gate passed afterward; a fresh hosted run on the follow-up commit is required before merge.
