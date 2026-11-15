# T-004 — RULES и локальная база знаний V2

Статус: in_progress. Главный ИИ/исполнитель: Codex, gpt-6.1-sol.
Дата: 2026-11-15. База: c98a1922dee2dedeaed6eeb528d72098beb3a128.
Ветка: task/T-004; отдельный worktree .worktrees/T-004.
Зависимость: T-003 слита в 9f98b28046ca605577e5a829e02818335f66174c; статус её карточки и roadmap уточняются при интеграции.

## Поручение

Написать RULES и сразу создать локальную БЗ в V2 с чистого листа.
Точный допуск и ограничения: spec/local-knowledge.md, LKB-001…008.

## Зона файлов

- rules/RULES.md
- rules/policy-lock.json
- rules/COVERAGE.md
- rules/modules/**
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
- docs/roadmap.md
- tasks/T-003-closeout-and-email-privacy-plan.md
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

## Повторная сверка 2026-11-15

Поручение: исправить расхождения правил и честно отделить рекомендации аудита от реализации.
Пакет 0.2.0, policy-lock schema 2: index + семь модулей + COVERAGE; context включает весь пакет.
Восстановлен утверждённый набор десяти языков (hi/bn вместо ошибочно подставленных it/ja).
Отдельно проверяются tampered/missing module, unpinned link и optional/null shared marker.

## Проверки и остаток

- Предыдущий head 1007ab6 имел успешный hosted gate; это историческое свидетельство, не проверка новых правок.
- Текущие проверки и точные head/base/test merge-result публикуются в PR #4; после правок требуется новое independent review.
- До merge: независимое review итогового head после интеграции T-003, успешный CI и повторная проверка при смене base.
- Полный swarm, federated search, authenticated publisher, remote freshness и OS sandbox вне среза.
- Прикладные стековые профили, валидатор переводов/справки и security-watch onboarding ещё не реализованы; карта rules/COVERAGE.md фиксирует охват.
