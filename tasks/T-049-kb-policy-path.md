# T-049 — Проверять путь policy-lock целиком

Статус: in_progress. Неблокирующее замечание ревью T-048, требование LKB-001.

## Зона файлов

- `scripts/kb.ps1`
- `tests/kb-regressions.ps1`
- `tasks/T-049-kb-policy-path.md`

## Приёмка

Путь policy-lock с завершающим LF отклоняется при проверке записи lock с кодом KB_POLICY_LOCK и пустым stdout. Канонический пакет и его хеши сохраняются.
