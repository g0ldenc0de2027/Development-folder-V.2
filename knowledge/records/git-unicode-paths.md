# Урок: не зависеть от кодовой страницы консоли при чтении Git-путей

**Последняя проверка сценария:** 2026-11-21.

**Область применимости:** Development Folder V2, `scripts/verify-task-scope.ps1`, Git for Windows в связанном рабочем дереве, PowerShell 7.6.10. Локальная проверка выполнена на Windows 11 x64 26H2, build 26300.9974, ветка `ge_release`.

## Наблюдение

Scope guard ошибочно отклонял допустимый Unicode-путь `spec/ТЗ.md`, когда PowerShell запускал Git с кодовой страницей CP866. Та же фикстура проходила в UTF-8. Причиной ложного отказа было декодирование вывода Git по текущей кодовой странице консоли.

## Закрепление

На время вызова Git scope guard задаёт UTF-8 для декодирования вывода, затем восстанавливает прежнюю кодировку в `finally`. Регрессия запускает проверку Unicode-пути с CP866 и реальным контекстом связанного рабочего дерева Git. Набор также проверяет полный scope, чистоту дерева и неизменность HEAD, refs, index и status исходного репозитория.

## Источники и точная ревизия

- 2026-11-21, `main@7da6c0f4f4367ec9465eafd16acf249dc9a0e277`: случай CP866 есть в [tests/task-scope-regressions.ps1](../../tests/task-scope-regressions.ps1), а настройка и восстановление кодировки реализованы в [scripts/verify-task-scope.ps1](../../scripts/verify-task-scope.ps1). Штатный quality gate прошёл на указанной Windows baseline и в [GitHub Actions #44901331572](https://github.com/g0ldenc0de2027/Development-folder-V.2/actions/runs/44901331572).
- Исходное наблюдение от 2026-11-19: локальные quality gate и pre-push прошли на содержимом PR head `e8653345c5a62382be02bf8957e459a4def28e6a`. [Исторический запуск #44402452200](https://github.com/g0ldenc0de2027/Development-folder-V.2/actions/runs/44402452200) проверил merge-result `66c80a08d0f4f8569efd0c6e944a9b0dc8ba3cc0`.

## Когда повторить проверку

Повторите регрессию на новой точной ревизии при изменении чтения вывода Git, scope guard, PowerShell, Git for Windows или матрицы Windows. Из чистого рабочего дерева запустите `pwsh -NoLogo -NoProfile -File scripts/quality-gate.ps1` и удостоверьтесь, что сводка `TASK-SCOPE-REGRESSIONS` сообщает ноль отказов. Для разбора конкретно CP866 выполните `tests/task-scope-regressions.ps1` с уникальным `-TempRoot` вне рабочих деревьев и bare-репозиториев. Подтверждённый охват ограничен зафиксированной Windows и данным сценарием; для иных ОС, рантаймов и сценариев нужны отдельные свидетельства.
