# Исследование: закреплённые источники, лицензии и shortlist

- **Проект:** Development Folder V2
- **Автор:** OpenAI Codex (GPT-6); текст перенесён из исходного исследования без изменения содержания соответствующего диапазона
- **Дата:** 2026-11-16
- **Версия:** v1.0.0
- **Диапазон:** §§14–15
- **Статус:** draft; исследовательский материал, не утверждённая архитектура
- **Происхождение:** $derivedSource; конкретные ссылки и pinned refs сохранены в тексте разделов

---
## 14. Закреплённые refs и идентификаторы источников (наблюдение 2026-11-16)

- PurpleFlow main: 8a27a33d62d3b90d97917a6d4b88e2b89075f3af.
- MCP Agent Mail Rust: только LICENSE-проверка, pinned revision `2fee578fc8ce92b06c88eb5dc3a4340032a5835b`; технический разбор прекращён из-за rider (см. §15).
- Google Lightflow main: 2940cc4b4ad702d20b16c1a76a5716b223a9bf98.
- OKF Agent Memory develop: 4cbbf831224ec76bc450522faac9249905fdc51a; main: 1a6303d9f3582c6d238ace4d8643337baf06fc60 (предыдущий snapshot, не current default branch).
- Agent Workflow Kit main: dc5e68d48c6753a95fe3f6c9f06c9f771801491f.
- AWS CLI Agent Orchestrator main: 4aa07ddf5fe5a5a183283910abc3c70c078f1152.
- OpenWOP main: fe3f892a08355ab89f91090052d535b05ee9d107 (новая ревизия после первоначального snapshot 6d0888d759d327bc702a71f619390a82ac8b23d1).
- Agent-Loom main: c19bc63f2da3e7c563118949893ec98367c9465f.
- A2A main: 4d7cda4b1754ed410e41bf3be7ad9ebc62afe3d3.
- Prefect main: 8decde08a77cebcf5932a87a48efa9bc8ce39d54.
- Microsoft Agent Framework main: e2f52bc5a0c4b5e26901f63102fe509e51b48a92.
- Cognee main: 4053f6cc5536757f26a3665eed95c50088e6dc0b.
- Letta Code main: eadef1c6c3594d1bf81517efd4b68fce54644ad4.
- Khoj master: ae229ca894c0b80ad84664afcfdde523b5e87057.
- Graphiti HEAD: 869c1b279e01a2767a464581e1cb657ce0e39271.
- Open WebUI HEAD: b0e6098e940942281d9c83f3529ea117287a3a22.
- AnythingLLM HEAD: 4d09fa5f730698d39f1d783e47316744b260a700.
- AnythingLLM advisory GHSA-3f4c-xj8r-h4cr: published 2026-09-21; patched commit listed as 27cf88c6d1a52cff0f67a8a9ee8ba2548d1f117f; accessed 2026-11-16.

- Syncthing docs main: f02059067d50cc30e29fc83f1c0e3636da29ed3b.
- Automerge main: 09b19d5080a86548c72721a82747bebe272c6c31.
- Automerge Repo Keyhive.
  Pinned revision (main): 0f5ae05732713d54af2124c66d4020ca16aebec8.
- Apache CouchDB main: 5a15ed69b49c8dab30a4276ebd633dba77b9490c.
- Electric canonical repository neondatabase/electric main: 3f9809fb0bd894cb74470d434749673492ad7acf; прежний URL electric-sql/electric перенаправляется на canonical repository.
- PowerSync JavaScript SDKs main: repository ID 699908722 / node R_kgDOKbfCcg, Apache-2.0, commit 770a4f652361ec59a6a155bd002b67eed07c4728, tree 5703d4d970452b7b54125a55e07d9a1fef55c925.
- PowerSync documentation main: repository ID 870546457 / node R_kgDOM-N8GQ, Apache-2.0, commit 8741345c70af31f40c4ed587728ef15998713647, tree 162c6e5e83c0a8432d594ba0ea942c1e7d9425d0.
- RxDB master: repository ID 75425073 / node MDEwOlJlcG9zaXRvcnk3NTQyNTA3Mw==, Apache-2.0, commit 177d00f160b00275ed77ab5b4a54c3e0e22288c2, tree 1fe86e5fd17e46b8ce64152068ccfa46746673f8.
- Apache PouchDB master: repository ID 714074 / node MDEwOlJlcG9zaXRvcnk3MTQwNzQ=, Apache-2.0, commit 0ec5a68736e306814f491081eaf31692211af007, tree d6eabb64ca7d2d92f16687a7dc8a454110061a42.
- Rocicorp Zero docs main: repository ID 894087912 / node R_kgDONUqy6A, Apache-2.0, commit b8e0d5c15b4f5a9e571a36633af672cb2b313346, tree 15b3b7240684974a3ed0f8a855fee0bf800e7093.
- durable-sync main: repository ID 1302271261 / node R_kgDOTZ8VHQ, MIT, commit f1f69ad0bc6e9af91df8075f18825ca71b81ad83, tree 2af0ae348b89b9cd7f0216f2c1183ff3518ab24d.
- SQLite network filesystem и WAL docs: официальные страницы, доступны 2026-11-16; Git commit pin неприменим.

**Запись фиксирует идеи и выводы с ограничениями. Это не утверждённая спецификация, security approval, лицензия на код или разрешение на реализацию/подключение зависимостей.**

## 15. Delta shortlist и IP-проверка (наблюдение 2026-11-16)

### 15.1. Исключение по лицензионному риску

`Dicklesworthstone/mcp_agent_mail_rust` проверен только на уровне LICENSE по pinned commit `2fee578fc8ce92b06c88eb5dc3a4340032a5835b`. Файл помечает лицензию как `MIT License (with OpenAI/Anthropic Rider)` и содержит специальные ограничения, прямо относящиеся к OpenAI и Anthropic. Метаданные GitHub при этом показывали `NOASSERTION`, поэтому одного SPDX-поля недостаточно. Из-за потенциального конфликта с используемыми AI-средами источник исключён из shortlist; техническое изучение остановлено. В этой версии удалены ранее сохранённые технические описания механики данного проекта. Возврат к нему возможен только после отдельной правовой оценки и письменного разрешения правообладателя. Это риск-флаг, не юридическое заключение.

### 15.2. Кандидаты, прошедшие первичную проверку соответствия

| Источник и наблюдение | Что можно взять как чисто-проектную идею | Статус и недостающие доказательства |
|---|---|---|
| [agent-lore README](https://github.com/osteele/agent-lore/blob/ccc27ea1ca9b80c0e14679094df91df3f5da9945/README.md) и [MIT LICENSE](https://github.com/osteele/agent-lore/blob/ccc27ea1ca9b80c0e14679094df91df3f5da9945/LICENSE), HEAD `ccc27ea1ca9b80c0e14679094df91df3f5da9945`; дерево через API не получено из-за rate limit | Разделить проверенный канон и агентские полевые заметки с более низким уровнем доверия; записывать автора/сессию/проект; хранить разногласия отдельно; превращать пустые поиски в backlog; держать файлы читаемыми как Markdown в обычном Git. README указывает на локальный корень с пользовательским override `AGENT_LORE_KB`. | `ADAPT` как модель отдельного unreviewed-tier. Текущая документация называет Node 22+ и MCP; структура записи и права на свободные agent writes, egress, импорт, миграции, восстановление и безопасность реализации не проверялись. Не использовать в качестве канона и не подключать как зависимость без READY и отдельного пилота. |
| [agent-loom architecture](https://github.com/osteele/agent-loom/blob/c19bc63f2da3e7c563118949893ec98367c9465f/docs/architecture.md) и [MIT LICENSE](https://github.com/osteele/agent-loom/blob/c19bc63f2da3e7c563118949893ec98367c9465f/LICENSE), HEAD совпадает с предыдущим pinned ref | Видимые статусы owner-unverifiable/expired, durable transfer request, audit trail восстановления, claims и leases отдельно от presentation. | `ADAPT` для контракта состояния. Источник сам указывает, что логические leases не запрещают запись в файлы, forced recovery authority/reason записываются, но не проверяются. Не считать lease авторизацией или sandbox. |
| [A2A task lifecycle](https://github.com/a2aproject/A2A/blob/4d7cda4b1754ed410e41bf3be7ad9ebc62afe3d3/docs/topics/life-of-a-task.md), [Apache-2.0 LICENSE](https://github.com/a2aproject/A2A/blob/4d7cda4b1754ed410e41bf3be7ad9ebc62afe3d3/LICENSE), HEAD совпадает с предыдущим pinned ref | Разделять короткий Message для согласования и Task с taskId/contextId для длительной, наблюдаемой работы. | `DEFER` как возможный межпровайдерный адаптер. Сам протокол не является нашей авторитетной очередью, локальным хранилищем, гарантией доставки или policy engine; нужно отдельно проверять поддержку конкретными поверхностями AI. |
| [Beads release history](https://github.com/gastownhall/beads/releases), current HEAD `8cdfa796a8f571266f2687f8b80365cbe26a943d`, tree `5a63278a009433753357db1b035e8dd0e562cd91`; MIT | Идеи dependency graph, ready-work projection, task IDs и явных отношений блокировки/замещения. | Последний проверенный stable release — `v1.3.4`; `v1.4.0-rc.2` — prerelease. `LAB` для собственного task model; версия RC и сложность хранения/синхронизации не допускают немедленный выбор зависимости. Полная Windows-совместимость и restore не проверялись. |
| [LangGraph current security advisories](https://github.com/langchain-ai/langgraph/security/advisories), current HEAD `41fb001df9313d5edb5aaac32851d894b1750a1b`, tree `4768635434f53f7fff9c3ca7ece64a7b84eefbaf`, MIT, stable `1.2.22` | Checkpoint/interrupt/replay как ориентир устойчивого workflow и human gate. | `DEFER` как framework dependency до package-level audit. Первый успешный публичный API ответ `per_page=100` вернул 13 advisory objects; полный pagination/header replay прервал анонимный rate limit. Примеры: GHSA-3fx2-cqw9-xr3c фиксировал affected `langgraph` `<1.2.14` и `langgraph-sdk` `<0.4.6`; GHSA-fvww-7h3r-vfhp фиксировал `langgraph-sdk` `<=0.4.3` (patched `0.4.4`); GHSA-4hm6-w6qq-w73v указывал cross-user Store access в `langgraph-api` `<0.15.0`. Эти package-specific advisory ranges не доказывают, что current stable release уязвим; нужна проверка фактического lockfile, транзитивных пакетов и auth-конфигурации при возможном пилоте. |
| [Letta Code stable release](https://github.com/letta-ai/letta-code/releases/tag/v0.34.63), current main совпадает с pinned commit, Apache-2.0 | Agent-scoped memory UX и разделение локальной памяти от проектной/общей. | `LAB` как источник UX-идей. Частые релизы повышают churn; auto-reflection и sync требуют проверки прав/egress. Текущий продукт и Windows-переносимость не тестировались. |

### 15.3. Решение по подборке

- Лучшее совпадение по «второй памяти» — не автозапись в проверенный канон, а два явно разделённых уровня: курируемые правила/решения и временные агентские наблюдения с происхождением, статусом доверия и очередью human review. `agent-lore` показывает эту продуктовую идею; собственные папки и формат остаются нашим решением.
- Для агентского взаимодействия сочетать внутренний task/run/event store с A2A-подобным переносимым envelope; Beads полезен как источник dependency semantics, agent-loom — как источник статусов lease/transfer/recovery. Доставка, ACK, назначения и права должны быть реализованы и проверены в собственном coordinator.
- Публичный межпровайдерный протокол не заменяет API/adapters конкретных клиентов. Для офлайн первого этапа сохраняется один активный host. SQLite WAL не открывать нескольким компьютерам через файловый sync.
- Никакая библиотека, база данных, протокол или workflow engine не выбрана; код и бинарники не скачивались, не запускались и не переносились.

### 15.4. Текущая глубина и ограничения

Проверены read-only current refs через `git ls-remote` и выборочные GitHub страницы/публичная REST metadata. Публичные REST-запросы к API были ограничены анонимным rate limit после начального успешного чтения; последующие metadata, release и advisory страницы не удалось систематически выгрузить с пагинацией и Link headers. Глубина по таблице различается: точечные license/docs/code locators для Agent-Loom/A2A, README+LICENSE для agent-lore, метаданные и публичные advisories для LangGraph, release/metadata snapshot для Beads/Letta. Ни один репозиторий не клонировался и не запускался; полный исходный код, CI, транзитивные зависимости, Windows smoke/restore, egress и непрерывность поддержки не аудированы. GitHub discovery totals/incomplete_results по поисковому индексу не получены; результат остаётся `CONTINUE_TARGETED_RESEARCH` и не является полным рынком или рекомендацией к подключению.
