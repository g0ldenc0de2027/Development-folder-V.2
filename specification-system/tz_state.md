# Specification state

Canonical source: spec/ТЗ.md
Version: 0.1.0-draft
Status: DRAFT / NOT READY
Implementation admission: blocked for product features
Infrastructure bootstrap: allowed and underway
Open decisions: supported operating systems; stack-profile inventory; portfolio knowledge workflow and agent identity/ACL; project progress/ETA model; release and backup policy.

## Допуск T-004 от 2026-11-15

По прямому поручению владельца READY только срез RULES и файловой локальной БЗ, описанный в spec/local-knowledge.md (LKB-001…008). Остальной продукт остаётся DRAFT / NOT READY. Автоматический рой, общий publisher, миграция V1 и внешние adapters в допуск не входят. Реализация среза прошла локальный gate и 44 KB-регрессии; точные CI/review свидетельства ведутся в PR #4; состояние задачи — tasks/T-004-rules-and-local-knowledge.md.

## Целевой контур локальной и портфельной памяти

Спецификация: spec/portfolio-kb-agent-workflow.md, версия 0.5.0.
Статус: DRAFT / NOT READY; архитектурный дизайн, не допуск к реализации.
Решено владельцем: local KB — только один проект; common KB — накопительная память всех проектов плюс прямые записи на любые темы; обе проверяются в начале содержательной работы; значимые findings сохраняются локально и рассматриваются для promotion.
Не решено: identity/ACL; отдельные права parser-run/review/release; допуск проектных сведений в remote Git/облако; storage/network matrix; file capabilities/performance; parser concurrency/backend; promotion approvals и backup RPO/RTO.
Следующий шаг: закрыть open decisions и пройти review READY перед кодом федерации, publisher, parsers или agent broker.
