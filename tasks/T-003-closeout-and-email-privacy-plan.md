# T-003 — Закрыть merge T-002 и закрепить план приватности email

**Статус:** ready for review
**Тип:** maintenance / GitHub closeout and privacy documentation
**База:** `c98a1922dee2dedeaed6eeb528d72098beb3a128` (`origin/main` после merge PR #2)

## Основание

PR #2 слита после локального `QUALITY-GATE=PASS`, live verifier `PASS_WITH_RECORDED_LIMITS`, зелёного hosted `quality-gate` и независимого отчёта Gemini 4 Argon на точную тройку SHA. После merge проверка публичной истории обнаружила, что author email squash-коммита имеет внешний домен. Сам адрес не включать в Git, выводы тестов или отчёты. Владелец ранее выбрал не переписывать опубликованную историю и разрешил подготовить privacy-cleanup plan.

## Зона файлов

- `tasks/T-003-closeout-and-email-privacy-plan.md`
- `tasks/T-002-reconcile-github-settings-and-closeout.md`
- `docs/handoff.md`
- `docs/github-research.md`
- `docs/roadmap.md`
- `tests/quality-gate-regressions.ps1`

Полный privacy-cleanup plan хранится отдельным локальным audit-артефактом, не в публичном репозитории; абсолютный локальный путь в Git не записывать.

## Критерии приёмки

1. T-002 отражает `merged`, PR #2, merge SHA `c98a1922dee2dedeaed6eeb528d72098beb3a128`, точные head/base/test merge-result SHA и внешний verdict `APPROVE`; отдельно сказано, что GitHub-native review в API отсутствовал.
2. `docs/handoff.md` отражает текущую чистую `main` на `c98a1922dee2dedeaed6eeb528d72098beb3a128`, merge T-002 и реальные незакрытые пункты. Не оставлять PR #2 как draft/open.
3. В публичных docs записана только минимальная redacted информация об авторском email для предотвращения повторения; адрес и его локальная часть не публикуются.
4. Документация отличает main-историю от синтетических merge-result refs PR и не называет все найденные объекты частью `main`.
5. Зафиксировано решение владельца: опубликованную историю не переписывать; никаких force-push, filter-repo или Support-запросов в этой задаче.
6. Regression checks обнаруживают stale T-002/handoff state и запрещают заявлять, что merge email privacy подтверждена только по `.email == null` в публичном профиле.
7. Полный local `quality-gate` проходит на проверенном HEAD. Перед merge PR публикуется с независимым review, точными SHA и зелёным CI.
8. Privacy scanner охватывает все публичные Markdown-документы репозитория и исходник regression suite. Он разрешает только точный неперсональный GitHub web-committer адрес и блокирует пользовательские `users.noreply.github.com`, внешние адреса и домены-двойники.
9. Regression cases покрывают внешние и lookalike email, common `[at]` / `%40` encodings, common Windows/POSIX/UNC absolute path patterns, false privacy claims на `.email == null` в любом Markdown и безопасные отрицательные формулировки. Совпадения не выводят содержимое. Отдельный local-part не сохраняется и не считается проверяемым без безопасного reference.
10. T-002 SHA tuple закреплён одной строкой ревизий в карточке и проверяется точечно в handoff; PR #2/review attribution/native-review distinction закреплены. Документация явно отделяет `main` history от synthetic PR refs; поля метаданных T-002 отделены пустой строкой от результата приёмки.

## Учёт внешнего ревью

- Отчёт Gemini 4 Argon (Antigravity) привязан к устаревшему head `65e7e382a1d0cd958c52661b811ac84aeba5f52c`; он не является review текущего head. P2-1..P2-3 и P3-1 приняты к исправлению в текущей задаче, после нового commit нужны обновлённые независимые отзывы и CI на итоговой паре SHA.
- Для проверки допустимой системной личности GitHub web-committer используется точное исключение. Документация GitHub требует учитывать системный committer для web-based merges: https://docs.github.com/en/enterprise-cloud@latest/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets.
- Само значение персонального email и его local-part не записывать в эту карточку или регрессионные выводы.

## Границы

- Не менять GitHub settings в этой задаче.
- Не переписывать историю, не удалять refs и не обращаться в GitHub Support.
- Не менять продуктовую спецификацию и прикладное поведение.
- Следующую отдельную задачу по CI вести по решению владельца: без внешнего GitHub App; владелец — корень доверия, residual risk зафиксировать, независимую изоляцию не заявлять.
