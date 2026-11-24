# T-049 — Проверять путь policy-lock целиком

Статус: merged (PR #48, squash 3e59f63db5bf9c38d74b90ccb4e5e7c727f9c46d). Неблокирующее замечание ревью T-048, требование LKB-001.

## Зона файлов

- `scripts/kb.ps1`
- `tests/kb-regressions.ps1`
- `tasks/T-049-kb-policy-path.md`

## Приёмка

Путь policy-lock с завершающим LF отклоняется при проверке записи lock с кодом KB_POLICY_LOCK и пустым stdout. Канонический пакет и его хеши сохраняются.
