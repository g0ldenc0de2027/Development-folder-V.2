# Specification state

Canonical source: spec/ТЗ.md
Version: 0.1.0-draft
Status: DRAFT / NOT READY
Implementation admission: blocked for product features
Infrastructure bootstrap: allowed and underway
Open decisions: supported operating systems; stack-profile inventory; local knowledge integration; project progress/ETA model; release and backup policy.

## Допуск T-004 от 2026-11-15

По прямому поручению владельца READY только срез RULES и файловой локальной БЗ, описанный в spec/local-knowledge.md (LKB-001…008). Остальной продукт остаётся DRAFT / NOT READY. Автоматический рой, общий publisher, миграция V1 и внешние adapters в допуск не входят. Реализация среза прошла локальный gate и 44 KB-регрессии; точные CI/review свидетельства ведутся в PR #4; состояние задачи — tasks/T-004-rules-and-local-knowledge.md.
