# Handoff — T-004, 2026-11-15

- Изолированная task/T-004 от c98a1922dee2dedeaed6eeb528d72098beb3a128; T-003 не изменяется.
- Повторная сверка: RULES 0.2.0, семь модулей, COVERAGE и schema 2 lock всего пакета; восстановлен утверждённый список языков.
- Общая БЗ — редактируемый канон, здесь точная закреплённая копия; путь подключения произвольный и локальный.
- Реализован файловый CLI; новые проверки охватывают весь пакет и optional/null marker. Актуальные test/CI evidence и точные SHA — PR #4.
- Перед merge нужны свежие independent review/CI и последовательная интеграция после T-003. Swarm, прикладная матрица, security-watch и валидатор переводов ещё не готовы; детали в rules/COVERAGE.md.

## Исторический bootstrap-снимок (не текущие статусы задач)

# Handoff

- V2 создан с чистого листа; root commit `0641901e825fdede9e1fdabf3fa83078ce5ab8ad` опубликован в public repository по решению владельца.
- На `main` SHA `65b5ab35d46b81e5af1963c351d05ac5da0291dc` hosted `quality-gate` завершился success; ruleset `27253655` требует этот exact context от GitHub Actions App `15368`, strict=true, без bypass actors.
- Live verifier с `-RequireStatusCheck` завершился `PASS_WITH_RECORDED_LIMITS`. Dependency graph подтверждён прямым GitHub SBOM API, SPDX-2.3; generic patterns и validity checks не покрыты текущим планом.
- T-001 слита PR #1. Карточка закрыта с прозрачной отметкой: независимое review на точный PR head SHA в доступных доказательствах не найдено; историческую процедуру нельзя считать подтверждённой.
- T-002 находится в `task/T-002` и draft PR #2. До merge сверить в PR description текущие head/base/test merge-result SHA, успешный обязательный `quality-gate` и независимое review на текущий head; проверки повторяются после изменения SHA. Следующие этапы — доверие к изменяемому PR quality workflow, Git identity и входящие task refs/push.
- P0 task-scope/worktree guard остаётся ручным. `spec/СОСТОЯНИЕ.md` — DRAFT / NOT READY; перед автоматизацией lifecycle нужно завершить спецификацию. Прикладную реализацию не начинать.
