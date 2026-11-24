# T-044 — Проверять жёсткие ссылки в пакете правил

Статус: merged (PR #43, squash 2d7c146a764b1ee5fecb80e21307a7c7862bc392). Аудит Antigravity F-05.

## Зона файлов

- `scripts/kb.ps1`
- `tests/kb-regressions.ps1`
- `docs/local-knowledge.md`
- `knowledge/records/git-attribution-worktrees.md`
- `knowledge/catalog.json`
- `tasks/T-044-policy-file-integrity.md`

## Приёмка

Чтение policy-lock и каждого закреплённого файла пакета использует ту же проверку жёстких ссылок, что и записи БЗ. Состав пакета, хэши и контракт CLI сохраняются. Регрессия проверяет отказ KB_HARDLINK и пустой stdout для catalog, policy-lock и RULES. Штатный check и регрессии БЗ проходят.

Дополнение аудита A19 и A21: справка описывает границу `sourceCollectionId` и охват проверки жёстких ссылок. В локальном уроке об авторстве отделены исторические свидетельства от более поздней проверки main, добавлены условия повторной проверки. Статус урока сохраняется draft. Принятие первого независимо проверенного урока отслеживается в T-068.
