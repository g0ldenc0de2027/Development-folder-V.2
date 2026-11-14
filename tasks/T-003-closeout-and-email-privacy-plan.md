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
- `docs/github-workflow.md`

Полный privacy-cleanup plan хранится отдельным локальным audit-артефактом, не в публичном репозитории; абсолютный локальный путь в Git не записывать.

## Критерии приёмки

1. T-002 отражает `merged`, PR #2, merge SHA `c98a1922dee2dedeaed6eeb528d72098beb3a128`, точные head/base/test merge-result SHA и внешний verdict `APPROVE`; отдельно сказано, что GitHub-native review в API отсутствовал.
2. `docs/handoff.md` отражает текущую чистую `main` на `c98a1922dee2dedeaed6eeb528d72098beb3a128`, merge T-002 и реальные незакрытые пункты. Не оставлять PR #2 как draft/open.
3. В публичных docs записана только минимальная redacted информация об авторском email для предотвращения повторения; адрес и его локальная часть не публикуются.
4. Документация отличает main-историю от синтетических merge-result refs PR и не называет все найденные объекты частью `main`.
5. Зафиксировано решение владельца: опубликованную историю не переписывать; никаких force-push, filter-repo или Support-запросов в этой задаче.
6. Regression checks выявляют устаревший T-002/handoff state, отклоняют положительные выводы о приватности commit email на основании null-поля профиля, включая смешанные claims и copular privacy assertions, и сохраняют безопасные отрицательные формулировки.
7. Полный local `quality-gate` проходит на проверенном HEAD. Перед merge PR публикуется с независимым review, точными SHA и зелёным CI.
8. Privacy scanner охватывает все публичные Markdown-документы репозитория и сам исходник regression suite, без исключения path findings для .ps1. Он разрешает только точный системный GitHub web-committer адрес и обнаруживает пользовательские users.noreply.github.com, внешние адреса, lookalike-домены, Unicode/punycode и obfuscated email.
9. Regression cases покрывают внешние и lookalike email, точную allowlist boundary, Unicode/punycode, [at]/%40/at-dot/[dot]/(dot)/fullwidth-@ obfuscation, Windows/macOS/POSIX/MSYS и оба вида UNC путей. HTTP routes и URL (включая маршруты с дефисом перед /users или /home) не считаются локальными файлами. Claim fixtures проверяют quoted/backticked email=null, nil, английские/русские словоформы, and/while/although/because/тире/скобки/slash/soft line break, смешанные положительные и отрицательные утверждения, согласованные отрицательные списки, разные конструкции neither/nor, double negatives, safe not-yet/on-its-own/cannot-be-used-to/insufficient-to/neither-nor и отдельный API evidence. Совпадения не выводят содержимое; отдельный local-part не сохраняется. Detector is a bounded heuristic and does not guarantee recognition of arbitrary paraphrases.
10. Полный T-002 SHA tuple находится только в карточке T-002; handoff ссылается на карточку и показывает текущий статус без дублирования старых SHA. Ревью и CI имеют provenance по SHA и считаются устаревшими после изменения head или base.
11. Зафиксирован no-App выбор владельца: владелец остаётся корнем доверия, ручное owner review не enforced GitHub, PR может изменить собственный gate, а отсутствие технически независимого контроля записано как residual risk.

## Учёт внешнего ревью

- GitHub Copilot проверил head 363cfdbc52343a66ea17fc34c66737b3c0d0f33d и подтвердил P2: положительный вывод после отрицания и em dash маскировался общей проверкой отрицания. Исправление этой конкретной формы вошло в 9c486a3a653f423add97ee93b376ffde8a42154e; этот отчёт не покрывает более поздние изменения.
- Antigravity (Gemini 4 Argon) выполнил READ-ONLY review exact head 9c486a3a653f423add97ee93b376ffde8a42154e, вердикт APPROVE с замечаниями P2-1..P2-3 и P3-1. Он воспроизвёл смешанные утверждения через and/while/although/и при этом/тире/скобки/slash/перенос строки, двойное отрицание, варианты null-сигнала и false positives not-yet, on-its-own, cannot-be-used-to, insufficient-to, neither-nor; отметил неполный path scan и подавление path результатов в test source.
- На head b272622eb93d1881960a164671fcb30836e99b6f GitHub Copilot вынес APPROVE: сверил revision tuple, публичные документы и hosted run #43614751907 (тестовый merge-result a4067f9fd3001fe4dbb843e5d387374f19037ed0); локальные регрессии сканера не запускал. Это подтверждает просмотренный diff и CI evidence, но не опровергает отдельные целевые пробы.
- На том же head Antigravity вынес CHANGES REQUIRED и воспроизвёл три группы проблем: ложные срабатывания на согласованные отрицательные списки; пропуски смешанных/разделённых утверждений и конструкций neither/nor; пропуск [dot]/(dot) и ложное срабатывание на URL-маршрутах с дефисом перед /users или /home.
- GitHub Copilot checked exact PR #3 head bbd8abc223099b368407cd7082f6cec409d5c6e6 against base c98a1922dee2dedeaed6eeb528d72098beb3a128; verdict CHANGES REQUIRED. P2: the heuristic missed an affirmative copular privacy predicate following the profile null signal. P3: handoff/roadmap still described hosted CI as pending. Run 43618469816 succeeded on test merge-result 4592797ecefdf767903ae37d37522f52fa1a3146, whose parents are the exact base and head. The report and run cover bbd8abc only and are stale after later local changes.
- Codex reproduced P2 with a red-first regression, fixed the predicate, and added direct positive and negative copular fixtures. The targeted regression suite and full quality gate pass on the current diff against origin/main (QUALITY-GATE=PASS); the pre-push hook must repeat the gate for the commit. After publishing the fix, fresh independent reviews and hosted CI are required for the exact final head/base pair.

## Границы

- Не менять GitHub settings в этой задаче.
- Не переписывать историю, не удалять refs и не обращаться в GitHub Support.
- Не менять продуктовую спецификацию и прикладное поведение.
- Следующую отдельную задачу по CI вести по решению владельца: без внешнего GitHub App; владелец — корень доверия, residual risk зафиксировать, независимую изоляцию не заявлять.
