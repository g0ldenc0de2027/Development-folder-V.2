# T-002 — Сверить GitHub settings и закрыть bootstrap T-001

**Статус:** merged
**PR:** #2 — https://github.com/g0ldenc0de2027/Development-folder-V.2/pull/2
**Merge SHA:** c98a1922dee2dedeaed6eeb528d72098beb3a128
**Проверенные ревизии:** head e9db06ad083d007d15e0674d195f16999fbfc93b; base 65b5ab35d46b81e5af1963c351d05ac5da0291dc; CI merge-result 04bf30fd6879f4d18abf3c270cd05e5428e55079.
**Review:** Gemini 4 Argon (Antigravity) вынес APPROVE для точной указанной тройки SHA. Отчёт не является GitHub-native approval; GitHub API не содержит review submission.

### Результат приёмки
Все шесть критериев выполнены. Local quality gate и live settings verifier прошли на head. Hosted quality-gate прошёл на CI merge-result. После merge PR #2 и локальная main синхронизированы до merge SHA. Для author email GitHub-generated squash-коммита выявлен отдельный privacy follow-up; адрес намеренно не копируется в репозиторий.
**Тип:** maintenance / GitHub configuration and closeout
**База:** `65b5ab35d46b81e5af1963c351d05ac5da0291dc` (`origin/main`)

## Цель

Убрать обнаруженные расхождения live GitHub settings, versioned manifests и handoff. Зафиксировать фактический статус T-001 и не приписывать ему независимое review, если отчёт на точный SHA не найден.

## Зона файлов

- `config/github/repository.json`
- `config/github/main-ruleset.json`
- `scripts/github/verify-settings.ps1`
- `tests/quality-gate-regressions.ps1`
- `tasks/T-001-sync-required-status-check.md`
- `tasks/T-002-reconcile-github-settings-and-closeout.md`
- `docs/handoff.md`
- `docs/github-research.md`
- `docs/roadmap.md`

## Критерии приёмки

1. Dependency graph проверяется прямым GitHub SBOM endpoint, а не выводится из Dependabot alerts; результат fail-closed при отсутствующем или некорректном SBOM.
2. Manifest и live verifier описывают и сверяют все параметры live pull-request rule, включая dismissal stale reviews, extra approval для unattributed changes, reviewer list, code-owner review и approval последнего push.
3. Regression tests закрепляют прямую проверку SBOM и сравнение полного набора PR-параметров.
4. T-001 отражает, что PR #1 был слит; отсутствие найденного независимого отчёта на точный head SHA записано как исторический пробел доказательств, без заявления, что review был выполнен.
5. Handoff и roadmap соответствуют актуальному SHA и перечисляют незакрытые следующие задачи.
6. Локальный quality gate и live verifier проходят на этом checkout. До merge фиксируются PR head/base/merge-result SHA и независимое review на head SHA; отсутствие доказательства блокирует закрытие.

## Принятые ограничения

- Нулевой approval count остаётся документированным режимом solo-владельца; независимый AI review не называется GitHub approval.
- Live ruleset не меняется в этой задаче.
- Поведение создаваемых приложений и проектное ТЗ не меняются.
