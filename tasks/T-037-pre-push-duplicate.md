# T-037 — Убрать повторную проверку ref в pre-push

Статус: merged. Аудиты Kimi M-1 и Qoder B-019/S-013/C-010.

Интеграция: [PR #36](https://github.com/g0ldenc0de2027/Development-folder-V.2/pull/36), squash `ee38460643bca7f7cf600f372c33e84e3ea5eeec`.
CI после слияния: [run #44753694661](https://github.com/g0ldenc0de2027/Development-folder-V.2/actions/runs/44753694661), success на указанном squash-коммите.

## Зона файлов

- `.githooks/pre-push`
- `tasks/T-037-pre-push-duplicate.md`

## Приёмка

Удалить второй одинаковый блок проверки текущей одноимённой ветки. Первый блок, его порядок относительно проверок SHA и вся политика push сохраняются. Полный quality gate и обычный pre-push проходят.
