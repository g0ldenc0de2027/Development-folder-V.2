# Handoff — Development Folder V2

- Контракт точного чтения записи локальной БЗ и оставшаяся работа с параметрами описаны в [T-060](../tasks/T-060-kb-get-query.md).
- Текущие ревизии, обсуждения и статусы проверяйте в [списке PR V2](https://github.com/g0ldenc0de2027/Development-folder-V.2/pulls).
- Состояние проверок сверяйте в [GitHub Actions V2](https://github.com/g0ldenc0de2027/Development-folder-V.2/actions) по точной ревизии.
- Перед интеграцией применяйте [штатный GitHub workflow](github-workflow.md).
- Подключение сценарного прогноза к локальной панели описано в [T-120](../tasks/T-120-viewer-forecast-display.md).
- Динамика подтверждённого остатка по датам и условия воспроизведения описаны в [T-121](../tasks/T-121-viewer-remaining-work.md).

- Исправления по аудиту V2 начаты с жизненного цикла временного каталога gate. Зона, приёмка и оставшиеся части замечания описаны в [T-058](../tasks/T-058-gate-temp-ownership.md).

## Панель проекта — сверка на 2026-11-28

Снимок проверен по main 57cab22e4e6f275feb5fa406b054ab6d4654e59e. Для продолжения откройте [руководство панели](project-viewer.md), затем карточку нужного среза.

| Задачи | Результат в проверенной main | PR |
|---|---|---|
| T-120–T-122 | Отображение сценарного прогноза и динамики подтверждённого остатка | [#108](https://github.com/g0ldenc0de2027/Development-folder-V.2/pull/108), [#109](https://github.com/g0ldenc0de2027/Development-folder-V.2/pull/109), [#110](https://github.com/g0ldenc0de2027/Development-folder-V.2/pull/110) |
| T-123–T-124 | Сверка истории слияний и объяснение изменения объёма | [#111](https://github.com/g0ldenc0de2027/Development-folder-V.2/pull/111), [#112](https://github.com/g0ldenc0de2027/Development-folder-V.2/pull/112) |
| T-125–T-128 | Журнал решений, отдельный учёт результатов задачи, подключение журнала и обновление курса в смете | [#113](https://github.com/g0ldenc0de2027/Development-folder-V.2/pull/113), [#114](https://github.com/g0ldenc0de2027/Development-folder-V.2/pull/114), [#115](https://github.com/g0ldenc0de2027/Development-folder-V.2/pull/115), [#116](https://github.com/g0ldenc0de2027/Development-folder-V.2/pull/116) |

T-129 добавляет регрессию смешанных расходов. На дату сверки [PR #117](https://github.com/g0ldenc0de2027/Development-folder-V.2/pull/117) открыт как черновик. Hosted quality-gate успешен на head ff6264a6df85d4093ba51615a794590a59baa69e. Следующий шаг — независимое ревью этой ревизии. Перед интеграцией сверяйте текущие ревизии и проверки по PR.


## Исторический Handoff — T-014

- T-014 обновляется на актуальной main. Зона, результаты прошлых проверок и критерии приёмки сохранены в карточке задачи.
- Актуальные SHA, CI и независимое ревью отслеживаются в PR #12.

## Исторический Handoff — T-011, 2026-11-16

- Общая БЗ: [PR #2](https://github.com/g0ldenc0de2027/Knowledge_Base/pull/2) — источник истины для статуса, ревизий, CI и review. Карточка задачи хранит только подписанные исторические снимки.
- V2 replacement [PR #10](https://github.com/g0ldenc0de2027/Development-folder-V.2/pull/10) — источник истины для актуальных статуса, head/base и checks. Merge разрешается только после проверки неизменившейся пары SHA, успешного CI и независимого review на соответствующем head.
- T-011 уточняет границы текущей и целевой БЗ, ограничения внешней передачи и спецификацию 0.5.0. Канонические правила и V2 mirror совпадают по пяти закреплённым файлам.
- Исторические отчёты Copilot/DeepSeek и разбор их замечаний находятся в карточке T-011. Перед использованием review сверяйте его SHA с head live PR.
- ACL, федеративный поиск, publisher, ingestion/OCR/ASR и coordinator не реализованы; portfolio workflow остаётся `DRAFT / NOT READY`; app stack audit — `NOT COVERED`.
- Перед merge перепроверьте live PR, unresolved review threads и неизменность SHA после CI/review. Автоматическая проверка parent tuple выделена в T-012.

## Исторический Handoff — T-008, 2026-11-19

## Historical snapshot — GitHub reliability and T-015, 2026-11-19

## Evidence snapshot before the documentation follow-up

- T-015 implementation commit `1c675cc61ba47b7280e3b05083ce66539bfbf4d2` was pushed to PR #11. At this snapshot PR #11 was OPEN/Draft, head `1c675cc61ba47b7280e3b05083ce66539bfbf4d2`, base `f577dc70e58d75ab5fd61d0c2e712c27b590713a`.
- Hosted `quality-gate` run [#44471405219](https://github.com/g0ldenc0de2027/Development-folder-V.2/actions/runs/44471405219) succeeded on event `pull_request`; checkout/test merge-result `a28d75c53172ac1bde86ed33de43ded53582d671` has exactly the stated base and head as parents.
- Local full gate and pre-push gate passed on the implementation: identity 31/31, worktree 25/25, KB 44/44, privacy 41 Markdown files plus regression source, hygiene 69 text files, actionlint and Gitleaks PASS. Stack build/dependency audit does not apply because no application stack is selected.
- Read-only `scripts/github/verify-settings.ps1 -RequireStatusCheck` returned `GITHUB_SETTINGS_AUDIT=PASS_WITH_RECORDED_LIMITS`; expected repository, main ruleset, Actions, Dependabot and secret-scanning settings matched. Generic GitHub secret patterns and validity checks remain disabled and are recorded limitations.
- The repo-wide inventory found 12 open Draft PRs (#5–#16), all based on `main@f577dc70…`; green checks do not mean these tasks were reviewed, accepted, or integrated. Process task PRs sequentially against the current base.

### Acceptance rule at that snapshot

- PR #11 remains unmerged. No GitHub-native review was present at this snapshot. After this documentation/policy update, read the live PR for the final head/base and hosted check; obtain an independent read-only review naming that exact head. Do not merge until current-head review, hosted CI, scope acceptance and integration checks all pass.
- AGENTS.md now requires agent-owned per-run temp paths, `try/finally` cleanup and post-cleanup verification; it explicitly protects user data, inbox, backups and unowned artifacts from broad deletion.
- Evidence for commit 55970f4d7db0429a2c5d9c64c7f617965d0d5815: pre-push passed with 69 local text files; hosted quality-gate #44484559621 passed on merge-result 40dccdbe36672be9c7638a745ea846396e309f2c with 65 hosted text files. These counts describe separate runs. The earlier unpublished recovery checkpoint is preserved locally and is outside this evidence.
- For every action, confirm the target repository, branch, full SHA and current live remote state from the linked worktree. The bare admin repository is not a working tree. Never infer success from a stale run, an empty review decision, or a command wrapper that hides a nonzero child exit.

---

## Historical snapshot — T-015, 2026-11-17

- База task/T-015 — `ff48a0fd7a412a5112477d86dfe5ff3122709fb0`; существующий draft PR #11 до новых исправлений указывал на эту ревизию. Основной scoped-набор сохранён локальным commit `7a5ce92`; исправление regression harness ожидает отдельного commit.
- Инициализация linked-worktree Git config безопасно разделила bare admin и T-015; все 14 linked worktrees читают `git status`. Пять worktrees сохраняют прежние правки без потерь: T-009, T-012, T-013, T-014 и T-015.
- T-015: 22/22 регрессии, полный quality gate, Git identity verifier и `git diff --check` прошли на текущем рабочем содержимом. Первая попытка pre-push корректно заблокировала публикацию из-за бага обнаружения Git shell в regression harness; поиск исправлен, добавлена проверка вложенного `git.exe`.
- Полный gate повторён после обновления handoff и исправления harness; следующий шаг — зафиксировать только тест, карточку и handoff, затем выполнить обычный push в task/T-015. Первая публикация осталась заблокирована штатным hook, история не переписывалась и проверки не обходились.
- После публикации проверить hosted CI на точной ревизии и запросить свежее независимое read-only review нового head. PR не сливать до нового review и зелёного CI.
- Historical T-004/bootstrap notes below are preserved as historical records.
## Historical snapshot — T-004, 2026-11-15

- Recovery checkpoint: code commit `7483dc749dc5d35453c4532010ccec458f0dfe3e` is on `task/T-008`; the unpublished fixture-identity commit `ff6499005837312f8832b484d8fc51e52c08d628` remains preserved by backup ref `backup/2026-11-19-T-008-before-identity-repair`. The remote branch was not rewritten.
- Local scope and pre-push checks passed on the code commit: 29/29 paths in scope, PowerShell 7.6.10, KB 44/44, task-scope 8/8, privacy/hygiene, actionlint, Gitleaks, and diff checks.
- Hosted checkpoint: run [#44460186961](https://github.com/g0ldenc0de2027/Development-folder-V.2/actions/runs/44460186961) SUCCESS for PR head `7483dc749dc5d35453c4532010ccec458f0dfe3e`, base `f577dc70e58d75ab5fd61d0c2e712c27b590713a`; event/test merge-result `8e2e3956f9c16a216b31609120c7e5f106e27814` has exactly those parents. This is a dated checkpoint; query live PR #8 before relying on current head/checks.
- At that checkpoint PR #8 was OPEN/Draft, unmerged, with no GitHub-native review. A fresh independent review of the live head is required before merge.
- Read-only audit after T-008 publication: 16 registered worktrees CLEAN; T-015 alone has 9 candidate paths. Its full local gate now passes (identity 31/31, worktree 25/25, KB 44/44, privacy/hygiene, actionlint, Gitleaks); commit/publish remains pending while the handoff provenance is preserved and reconciled.

## Исторический bootstrap-снимок до слияния T-003 (не текущие статусы задач)

# Handoff

- V2 остаётся публичным по решению владельца; PR #2 / T-002 слита, локальная main чистая на c98a1922dee2dedeaed6eeb528d72098beb3a128. Полный PR/review/CI revision tuple находится в карточке tasks/T-002-reconcile-github-settings-and-closeout.md.
- Владелец выбрал no-App: владелец — корень доверия. У ruleset нет обязательных approvals и CODEOWNERS, поэтому review владельцем — организационный контроль, а не GitHub-enforced gate. PR может изменить собственный workflow/gate и пройти изменённую проверку; это остаточный риск, описанный в docs/github-workflow.md.
- PR #3 / T-003 остаётся draft. Copilot CHANGES REQUIRED на head bbd8abc: P2/P3 закрыты в code-fix commit 5c3eaf06dd5ee9a518659db015e4ffbc54b8a982. Его проверенная пара: base c98a1922dee2dedeaed6eeb528d72098beb3a128, hosted run 43622066954 SUCCESS, checkout/test merge-result 5fb052c8094ceb3f530b306d8ba164416411d63f с точными родителями base/head. GitHub Actions проверяет каждую последующую ревизию отдельно; актуальный статус смотреть в PR #3. GitHub-native review отсутствует; свежий независимый review последнего head требуется.
- В публичных документах нельзя публиковать email или local-part. email=null в публичном профиле не подтверждает приватность commit email. История не переписывается; адрес учётной записи перед следующим merge владелец проверяет отдельно. Claim detector — ограниченная эвристика, её покрытие определяется fixtures, а не произвольным смысловым анализом.
- T-003: локальная regression suite, полный quality gate и pre-push gate прошли на code-fix commit 5c3eaf0; hosted CI прошёл на его точной паре SHA. Каждая последующая PR-ревизия получает отдельный hosted gate. Независимый review последнего head остаётся открытым.
- После T-003 продолжить отдельные задачи no-App merge controls, Git identity/push-size controls и P0 scope/worktree guard; прикладную реализацию не начинать до READY в спецификации.

## Просмотрщик проектов

- T-051 добавляет независимый локальный просмотр карточек в режиме чтения.
- Запуск и реестр описаны в [руководстве](project-viewer.md).
- Пользовательский пилот сравнивает скорость поиска с ручным просмотром.

## Пилот трекера T-101

Локальный просмотрщик принимает одну необязательную очередь и явные привязки заданий через реестр. Синтетическая матрица доступности копий, конфликт, изоляция проектов и сохранение снимка проверяются через HTTP в `tests/project-viewer-regressions.ps1`. Реальную пару задачи и задания подтверждает владелец перед пользовательским прогоном. См. [руководство](project-viewer.md) и [карточку T-101](../tasks/T-101-project-tracker-readonly.md).
