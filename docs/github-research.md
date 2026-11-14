# GitHub setup research — 2026-11-14

## Решение и проверенные ограничения
- Development-folder-V.2 намеренно public по выбору владельца для бесплатного плана.
- Активен repository ruleset для main: PR required; deletion и non-fast-forward блокируются; linear history; review threads должны быть resolved; squash-only; bypass actors отсутствуют.
- Required approval count равен 0: владелец работает один и не может сам дать независимое GitHub approval. Независимое AI review остается отдельным доказательством, привязанным к PR head SHA. Пока required status context не включен, quality gate еще не GitHub-enforced.
- Actions включены с read-only default token, обязательным pinning по SHA и allowlist только для checkout action. Workflow не использует стороннюю security action.
- Локальная настройка repo устанавливает pre-push quality gate, GitHub CLI credential helper, noreply identity, fast-forward-only pulls и fetch pruning. AI provenance сохраняется trailer Assisted-by и полями PR; GitHub commit author остается владельцем для связки noreply и не идентифицирует агента сам по себе.
- Secret scanning, push protection, Dependabot alerts/security updates и private vulnerability reporting подтверждены live API. Dependency graph не имеет status-поля в ответе repository REST API; его состояние явно помечается как inferred, поскольку официальный GitHub Docs указывает, что Dependabot alerts требуют включенного графа.
- Live read-back показывает generic non-provider patterns и validity checks как disabled. GitHub документирует включение generic patterns для organization-owned repos on GitHub Team with Secret Protection; для этого personal Free репозитория считаем их недоступным покрытием. Gitleaks запускается локально и в CI, но не заменяет provider validation.
- Live ruleset пока не содержит required status check; это подтверждено API. Слияние запрещено до первого успешного run, установки exact quality-gate context от GitHub Actions и повторного live read-back.
- Актуальный read-only verifier прошёл все проверяемые repository, Actions, ruleset, Dependabot и secret-scanning настройки; завершился ожидаемым `INCOMPLETE` (exit 2), поскольку quality-gate status ещё не установлен до первого hosted run.

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
