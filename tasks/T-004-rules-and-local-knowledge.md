# T-004 — RULES и локальная база знаний V2

Статус: ready_for_review. Главный ИИ/исполнитель: Codex, gpt-6.1-sol.
Дата: 2026-11-15. База: c98a1922dee2dedeaed6eeb528d72098beb3a128.
Ветка: task/T-004; отдельный worktree .worktrees/T-004.
Зависимость: T-003 не изменяется; интеграция пересечений docs/handoff выполняется последовательно.

## Поручение

Написать RULES и сразу создать локальную БЗ в V2 с чистого листа.
Точный допуск и ограничения: spec/local-knowledge.md, LKB-001…008.

## Зона файлов

- rules/RULES.md
- rules/policy-lock.json
- knowledge/**
- scripts/kb.ps1
- tests/kb-regressions.ps1
- spec/local-knowledge.md
- spec/СОСТОЯНИЕ.md
- specification-system/tz_state.md
- tasks/T-004-rules-and-local-knowledge.md
- docs/local-knowledge.md
- docs/development.md
- docs/handoff.md
- README.md
- AGENTS.md
- scripts/quality-gate.ps1

Локальная настройка вне Git: .etalon.json в worktree T-004.
Дополнительный разрешённый корень: новая общая БЗ, явно указанная владельцем;
только собственные starter files, knowledge, rules и локальный Git без remote.
Фиксированный путь этого корня в публикуемые файлы не включать.

## Приёмка

Отрицательные LKB-регрессии, полный gate, полный scope diff, отсутствие донорского кода,
публичных приватных данных и ложных утверждений о готовом swarm.
Независимое review и hosted CI на точных SHA — перед merge.

## Проверки и остаток

- Локальный полный quality-gate -BaseRef origin/main: exit 0; KB regressions 31 passed / 0 failed / 0 skipped, PowerShell AST, actionlint, Gitleaks и whitespace прошли.
- Проверены общий corpus (2 draft) и проектный corpus (4 draft), SHA-256 RULES совпадает; doctor использует локальный marker.
- Проверки включают Unicode/пробелы, перенос corpus, invalid explicit env без fallback, junction refusal, review content binding и byte budget.
- При первой проверке исправлены JSON timestamp parsing и LF сериализация; итоговые отрицательные сценарии включены в suite.
- Перед merge: независимое review другого производителя, hosted CI для точных SHA, последовательная интеграция после T-003 и повторная проверка при смене base.
- Полный swarm, federated search, authenticated publisher, remote freshness и OS sandbox остаются вне среза.
