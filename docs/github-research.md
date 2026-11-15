# GitHub setup research — 2026-11-14

## Решение и проверенные ограничения
- Development-folder-V.2 намеренно public по выбору владельца для бесплатного плана.
- Активен repository ruleset для main: PR required; deletion и non-fast-forward блокируются; linear history; review threads должны быть resolved; squash-only; bypass actors отсутствуют.
- Required approval count равен 0: владелец работает один и не может сам дать независимое GitHub approval. Независимое AI review остается отдельным доказательством, привязанным к PR head SHA. Exact status context `quality-gate` включен в live ruleset, strict=true, expected source — GitHub Actions App `15368`.
- Actions включены с read-only default token, обязательным pinning по SHA и allowlist только для checkout action. Workflow не использует стороннюю security action.
- Локальная настройка repo устанавливает pre-push quality gate, GitHub CLI credential helper, noreply identity, fast-forward-only pulls и fetch pruning. AI provenance сохраняется trailer Assisted-by и полями PR; GitHub commit author остается владельцем для связки noreply и не идентифицирует агента сам по себе.
- Secret scanning, push protection, Dependabot alerts/security updates и private vulnerability reporting подтверждены live API. Dependency graph подтверждается прямым `GET /repos/{owner}/{repo}/dependency-graph/sbom`: валидный SPDX-2.3 SBOM содержит пакет самого репозитория; текущая выдача также включает `actions/checkout`. Это прямое подтверждение, не вывод из Dependabot.
- Live read-back показывает generic non-provider patterns и validity checks как disabled. GitHub документирует включение generic patterns для organization-owned repos on GitHub Team with Secret Protection; для этого personal Free репозитория считаем их недоступным покрытием. Gitleaks запускается локально и в CI, но не заменяет provider validation.
- Bootstrap root SHA `0641901e825fdede9e1fdabf3fa83078ce5ab8ad` прошел hosted `quality-gate`; после этого status check включен в live ruleset и подтвержден API read-back. Следующие PR обязаны пройти этот check на актуальном merge-result SHA.
- Read-only verifier `-RequireStatusCheck` завершился `PASS_WITH_RECORDED_LIMITS`: repository, Actions, ruleset, Dependabot, secret-scanning и SBOM endpoint подтверждены; generic secret patterns и validity checks явно не покрыты.

## Архитектурные выводы
- Required workflow не должен иметь path filters: при фильтрации job может оказаться skipped.
- Review относится к PR head SHA; CI проверяет merge-result SHA для точной пары head/base. Изменение любой стороны требует повторной проверки; merge принимается только при совпадении этой пары.
- Автоматический token ограничен read; actions закреплены полными commit SHA. Другие actions и permissions добавляются только с обоснованием.
- Pre-push использует SHA из протокола Git hook: Gitleaks сканирует историю всех локальных refs и точные входящие диапазоны, включая новые refs; удаление ref блокируется локальным hook.
- GitHub protections не решают происхождение файлов. Изоляция задач через отдельные worktrees обязательна; автоматический scope guard остается следующим P0 этапом.

## Источники
Проверены официальные страницы GitHub Docs и release pages на 2026-11-14:
- [Protected branches and plan availability](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches)
- [Repository rulesets and bypass actors](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets)
- [Rulesets REST API](https://docs.github.com/en/rest/repos/rules)
- [Required status checks and skipped workflows](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks)
- [Pull request merge-result SHA semantics](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)
- [Actions permissions REST API](https://docs.github.com/en/rest/actions/permissions)
- [Secure use of GitHub Actions](https://docs.github.com/en/actions/reference/security/secure-use)
- [Secret scanning settings](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-security-and-analysis-settings-for-your-repository)
- [Generic secret scanning eligibility](https://docs.github.com/en/code-security/how-tos/secure-your-secrets/detect-secret-leaks/enabling-secret-scanning-for-generic-patterns)
- [Dependency graph and Dependabot alerts requirements](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-security-and-analysis-settings-for-your-repository)
- [Secret scanning coverage](https://docs.github.com/en/code-security/reference/secret-security/secret-scanning-scope)
- [Private vulnerability reporting](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/configure-for-a-repository)
- [actions/checkout v7.0.1](https://github.com/actions/checkout/releases/tag/v7.0.1)
- [Gitleaks v8.30.1](https://github.com/gitleaks/gitleaks/releases/tag/v8.30.1)
- [Git pre-push hook protocol](https://git-scm.com/docs/githooks#_pre_push)
- [Gitleaks Git-history ranges](https://github.com/gitleaks/gitleaks#git)
- [actionlint v1.7.12](https://github.com/rhysd/actionlint/releases/tag/v1.7.12)

Recheck plan eligibility and API values when changing repository owner type or policy.

## Исторический срез до merge PR #2 — R2, 2026-11-14

Этот раздел сохраняет live-состояние и рекомендации на момент подготовки исследования, до слияния PR #2. Упоминания открытой draft PR и её закрытия — исторические; они не описывают текущее состояние. Актуальные сведения находятся в разделе Post-merge T-002.

### Подтверждено live
- Публичный репозиторий использует активный ruleset только для `main`: PR обязателен, `quality-gate` обязателен от GitHub Actions App `15368`, строгая актуальность включена, bypass actors отсутствуют. Review approvals — 0 по выбранному режиму одиночного владельца.
- T-002 остаётся отдельной draft PR; перед merge точные head/base/test merge-result и CI сверяются повторно. AI-review — организационный контроль, не GitHub approval.
- Локальный pre-push gate сканирует Gitleaks по pushed history range, но не содержит byte-size порога; удаление ref отклоняется локально, non-fast-forward для task refs не проверяется.
- GitHub provider secret scanning и push protection включены; generic/non-provider patterns и validity checks live verifier отмечает как `NOT COVERED`.
- Репозиторию не назначен LICENSE-файл. Решение о лицензии оставлено владельцу.

### Ограничения платформы и последствия
- GitHub rulesets доступны публичным репозиториям на Free, но GitHub документирует push rulesets только для Team в internal/private репозиториях. Следовательно, на public Free нельзя полагаться на серверное правило размера push.
- Push protection пропускает проверку public-repository push свыше 50 MB. До определения отдельной лимитирующей политики такой push нельзя считать защищённым от утечки секретов.
- Вывод по текущему workflow: `quality-gate` на `pull_request` выполняет gate из PR merge checkout. Required check от того же Actions App не является независимым доверенным корнем для изменений workflow или самого gate: такие изменения могут менять код, который формирует требуемый результат. Это риск будущих PR, не дефект T-002: T-002 не меняет workflow и `scripts/quality-gate.ps1`.
- Сохранить `pull_request` с read-only token, SHA-pinned checkout и `persist-credentials: false`. Если появится trusted-base policy workflow, он должен читать PR-файлы как данные через API и не checkout/build/execute untrusted PR content. GitHub отдельно предупреждает, что `pull_request_target` нельзя использовать для запуска кода из PR.
- Текущий main ruleset защищает только `main`. Для task refs возможен отдельный branch ruleset `task/*`, блокирующий non-fast-forward и оставляющий удаление разрешённым для настроенного удаления ветки после merge.
- Для public Free нужен локальный fail-closed push-size gate и PR-проверка как компенсирующий контроль. Они не равны серверной блокировке; порог и метрика размера требуют отдельного определения и тестов.
- Отсутствие LICENSE означает действие default copyright; GitHub ToS разрешает пользователям просматривать и fork публичный репозиторий. До решения владельца не подразумевать открытое разрешение на переиспользование.

### Рекомендации на момент исторического снимка
1. Завершить T-002 после независимого review на текущем PR head и зелёного CI на текущей паре head/base.
2. Отдельной sequential task добавить trust policy для изменений workflow/gate, remote non-fast-forward protection для `task/*`, author identity guard и ограничение размера push с негативными regression cases.
3. До первого release установить tag policy; сейчас опубликованные tags отсутствуют.
4. До существенного роста публичного репозитория зафиксировать решение владельца о лицензии и приватности email в уже опубликованной истории. Не переписывать published history без отдельного решения владельца.

### Официальные источники
- [GitHub repository rulesets and plan availability](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/managing-rulesets-for-a-repository)
- [GitHub rules available to rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets)
- [GitHub push protection detection scope and limitations](https://docs.github.com/en/code-security/reference/secret-security/secret-scanning-scope)
- [GitHub secure use of `pull_request_target`](https://docs.github.com/en/actions/reference/security/securely-using-pull_request_target)
- [GitHub licensing a repository](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)

## Post-merge T-002 closeout and email privacy evidence — 2026-11-14

- PR #2 merged as c98a1922dee2dedeaed6eeb528d72098beb3a128 after local gate, live verifier, successful hosted run #43592810050, and Gemini 4 Argon APPROVE for the exact recorded head/base/test tuple.
- Run #43592810050 reports/attaches the Actions check to PR head `e9db06ad083d007d15e0674d195f16999fbfc93b`; this is the check association SHA. The workflow checks out `github.sha`; for `pull_request`, GitHub defines `GITHUB_SHA` as the synthetic merge-branch commit. The tested event SHA was `04bf30fd6879f4d18abf3c270cd05e5428e55079`, with parents base `65b5ab35d46b81e5af1963c351d05ac5da0291dc` and head `e9db06ad083d007d15e0674d195f16999fbfc93b`. No separate check-run on the synthetic commit is expected; that does not mean the gate skipped it. [GitHub pull_request SHA semantics](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows).
- Read-only API classification found the author field of the new squash commit uses an external domain; the raw address was deliberately excluded from public project docs. The committer field and the author field are separate and must be checked separately.
- The default-branch history contains a prior squash commit with the same redacted classification. Bootstrap and task-branch commits were classified as GitHub noreply. PR synthetic merge-result commits are PR refs, not commits on main.
- GET /user вернул email = null. Это подтверждает только, что публичное поле профиля не раскрыто; это не подтверждает приватный commit email или account option, блокирующую CLI pushes. GET /user/emails не читался из-за отсутствия широкого scope user.
- Before any future GitHub-generated merge, manually verify Keep my email addresses private and Block command-line pushes that expose my personal email in Settings > Emails. On squash, select/confirm the GitHub noreply author where the UI offers the selector; then verify the resulting commit author and committer via API without printing email values.
- The owner chose to preserve public history. No rewrite, force-push, ref deletion, or Support request was performed. A separate redacted plan is stored outside this public repository in the owner's local audit folder.
- The PR review artifact is external AI review, not GitHub-native approval. T-002 is closed; its task card and handoff now record the actual merge state.
- Owner decision for the next CI-trust stage: do not add an external GitHub App now. The repository owner remains the trust root; document residual risk and do not describe the Actions check as an independent trust anchor.
