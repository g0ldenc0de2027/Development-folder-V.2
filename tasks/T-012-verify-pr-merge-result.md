# T-012 — Проверять точный merge-result PR в hosted gate

**Статус:** merged

Интеграция: [PR #13](https://github.com/g0ldenc0de2027/Development-folder-V.2/pull/13), squash `436aa6f8570ab82f7d425a1859221862a8b328cb`.
CI после слияния: [run #44496675294](https://github.com/g0ldenc0de2027/Development-folder-V.2/actions/runs/44496675294), success на указанном squash-коммите.
**Тип:** maintenance / GitHub Actions quality gate
**Главный ИИ / исполнитель:** Codex (OpenAI), GPT-6
**Дата:** 2026-11-16
**База:** `f577dc70e58d75ab5fd61d0c2e712c27b590713a` (`origin/main`)
**Ветка / worktree:** `task/T-012-verify-pr-merge-result` / `.worktrees/T-012`

## Основание

В PR CI checkout выполняется по `github.sha`, а базу и head берут из payload PR. Сейчас workflow записывает эти три значения в summary, но не утверждает, что checked-out commit — именно merge-result с ровно двумя родителями в порядке `[base, head]`. Для текущих проверок родители сверялись отдельно через GitHub API. Handoff T-011 уже выделяет автоматическую проверку как отдельный этап.

Согласно официальной документации GitHub, для `pull_request` `github.sha` — последний merge commit ветки PR, а head SHA берётся из `github.event.pull_request.head.sha`. Поэтому hosted gate должен сравнить фактический checkout и родительский tuple с этими конкретными значениями.

## Цель

До запуска основного quality gate автоматически проверить, что PR workflow тестирует ожидаемый merge-result текущей пары base/head. Любое отсутствие, неверный формат или расхождение SHA/родителей должно приводить к отказу. Локальный quality gate вне PR должен продолжать работать и явно обозначать, что PR-only assertion к нему неприменим.

## Зона файлов

- `.github/workflows/quality-gate.yml`
- `scripts/quality-gate.ps1`
- `scripts/verify-pr-merge-result.ps1`
- `tests/pr-merge-result-regressions.ps1`
- `docs/github-workflow.md`
- `docs/handoff.md` — обновить после интеграции T-011, чтобы не конфликтовать с его текущей правкой handoff
- `tasks/T-012-verify-pr-merge-result.md`

Не менять правила GitHub, branch protection, права токенов, PR #10 или настройки аккаунта.

## Приёмка

1. Для события `pull_request` workflow перед quality gate вызывает проверку с `github.event.pull_request.base.sha`, `github.event.pull_request.head.sha` и `github.sha`.
2. Проверка подтверждает, что checked-out `HEAD` равен `github.sha`, этот объект является commit и имеет ровно двух родителей в точном порядке `[base, head]`.
3. Отсутствующий/невалидный SHA, недоступный commit, другой `HEAD`, переставленные родители, один или три родителя блокируют шаг ненулевым кодом.
4. Для локального запуска и событий без PR assertion явно `NOT APPLICABLE`; отсутствие PR-полей не должно ошибочно блокировать обычный локальный gate.
5. Регрессии создают только синтетическую локальную Git fixture; покрывают успешный tuple и каждый отрицательный случай, не обращаются к сети и не используют пользовательский Git config.
6. Workflow остаётся least-privilege, pinned actions, без `pull_request_target`; `actionlint` и структурные проверки подтверждают точный источник всех трёх SHA.
7. Документация объясняет различие PR head, base и tested merge-result, а handoff обновляется после интеграции T-011.
8. Пройти локальные regression suite, полный `scripts/quality-gate.ps1 -BaseRef origin/main`, `git diff --check`, push preflight и hosted CI; зафиксировать точные head/base/test SHA отдельно.
9. Не заявлять, что эта проверка делает workflow неизменяемым при PR: владелец остаётся корнем доверия, и ручная проверка diff workflow/gate сохраняется.

## Ограничения

Проверка подтверждает целостность tuple в checkout данного run. Она не защищает от изменения PR самого workflow или проверяющего скрипта; этот residual risk no-App модели остаётся описанным в `docs/github-workflow.md`. Независимое review точного head требуется перед merge.
