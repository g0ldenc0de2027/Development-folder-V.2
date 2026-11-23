# T-027 — Условный откат core.bare

Статус: merged. Источник: воспроизведение в PR #24.

Интеграция: [PR #26](https://github.com/g0ldenc0de2027/Development-folder-V.2/pull/26), squash `c136a87ef91d07d6c4169e72f9d99bba33963dfe`.
CI после слияния: [run #44575489137](https://github.com/g0ldenc0de2027/Development-folder-V.2/actions/runs/44575489137), success на указанном squash-коммите.

## Зона файлов

- `scripts/lib/GitIdentity.psm1`
- `tests/git-identity-regressions.ps1`
- `tasks/T-027-core-bare-conditional-rollback.md`

## Приёмка

Откат удаляет одиночное временное значение true только при точном совпадении под блокировкой Git. Значение false, записанное другим процессом, сохраняется и возвращается диагностика отказа отката. Повторная запись того же true неразличима для сравнения по значению. Сценарии штатного отката, отказа блокировки и повторной миграции сохраняются.
