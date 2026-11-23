# Исследование: безопасный доступ AI-агентов к credentials

- **Проект:** Development Folder V2
- **Автор:** OpenAI Codex (GPT-6); read-only GitHub research, synthesis and source attribution
- **Дата:** 2026-11-16
- **Версия материала:** v1.0.0
- **Тип:** research
- **Статус:** draft — кандидаты и требования для обсуждения, не утверждённая архитектура
- **Связь:** T-009; дополняет agent-workflow-research.md и agent-coordination-research.md

Решения и ссылки ниже являются синтезом для будущего ТЗ. Донорский код, prompts и сервисы не используются.
## 1. Сравнение GitHub-решений

### 1.1. Метод и refs

Read-only просмотр GitHub-материалов; refs получены через git ls-remote 2026-11-16 и закреплены полными commit SHA. Просмотрены выбранные README, security/specification docs, advisory и открытый issue; код, сборки, тесты и запущенные сервисы не проверялись. Это анализ паттернов, не аудит продуктов и не выбор поставщика.

- [OpenSandbox](https://github.com/opensandbox-group/OpenSandbox/tree/4ca105e813240d663cfa9a0c9ccb50b70624246a), commit 4ca105e813240d663cfa9a0c9ccb50b70624246a: [OSEP-0012](https://github.com/opensandbox-group/OpenSandbox/blob/4ca105e813240d663cfa9a0c9ccb50b70624246a/oseps/0012-credential-vault.md), [Credential Vault guide](https://github.com/opensandbox-group/OpenSandbox/blob/4ca105e813240d663cfa9a0c9ccb50b70624246a/docs/guides/credential-vault.md), [privacy issue #1713](https://github.com/opensandbox-group/OpenSandbox/issues/1713).
- [AgentCordon](https://github.com/agentcordon/agentcordon/tree/85048420592b4b269373154f6a60754b75fd49c0), commit 85048420592b4b269373154f6a60754b75fd49c0: [README](https://github.com/agentcordon/agentcordon/blob/85048420592b4b269373154f6a60754b75fd49c0/README.md), [architecture](https://github.com/agentcordon/agentcordon/blob/85048420592b4b269373154f6a60754b75fd49c0/docs/system-architecture.md), [Cedar authorization](https://github.com/agentcordon/agentcordon/blob/85048420592b4b269373154f6a60754b75fd49c0/docs/authorization-and-cedar-policy.md), [SECURITY.md](https://github.com/agentcordon/agentcordon/blob/85048420592b4b269373154f6a60754b75fd49c0/SECURITY.md), [license](https://github.com/agentcordon/agentcordon/blob/85048420592b4b269373154f6a60754b75fd49c0/LICENSE).
- [Octo STS](https://github.com/octo-sts/app/tree/2354277b95554f40b34950cd130a64050ff12da1), main commit 2354277b95554f40b34950cd130a64050ff12da1; v0.5.3 resolves to 0f177fde54f9318e33f0bba6abaea9463a7c3afd: [README/trust policies](https://github.com/octo-sts/app/blob/2354277b95554f40b34950cd130a64050ff12da1/README.md), [GHSA-h3qp-hwvr-9xcq / CVE-2025-52477](https://github.com/advisories/GHSA-h3qp-hwvr-9xcq).
- Official [MCP authorization security considerations](https://github.com/modelcontextprotocol/modelcontextprotocol/blob/ac00313ff7f5e9f47b0e0d1ebdf9c0ad6411380b/docs/specification/2026-07-28/basic/authorization/security-considerations.mdx), commit ac00313ff7f5e9f47b0e0d1ebdf9c0ad6411380b.

### 1.2. Что взять и чего не считать доказанным

| Источник | Идея | Граница |
|---|---|---|
| OpenSandbox Credential Vault | Секрет не передаётся sandbox в env, file, argv или read API. Proxy связывает credential с sandbox, scheme, host, port, HTTP method/path; credential scope сверяется с egress policy; неоднозначность закрывается отказом; изменение политики подтверждается revision ACK. OSEP помечен авторами как implemented. | Это Docker/Kubernetes и прозрачный HTTP(S) proxy, не переносимый Windows vault; non-HTTP и per-process policy исключены. Issue #1713 отмечает, что TLS на настроенных портах расшифровывается до проверки credential binding, даже для запросов без credential. Значит, proxy может затрагивать приватность всего HTTPS-трафика; TLS inspection требует отдельного согласия и точного охвата. |
| AgentCordon | Документы описывают CLI + broker + control plane: workspace signing key, запрос с operation/method/target, Cedar policy и URL fence, секрет остаётся у broker, есть audit и response leak scan. Полезен принцип вызова разрешённой операции без выдачи секрета модели. | Сам проект помечен pre-1.0, форматы меняются, SECURITY.md поддерживает только последнюю minor, лицензия AGPL-3.0-only. Отдельный сервер не подходит local-only режиму без трансформации. Мы просмотрели документы, не реализацию и тесты; claims security независимым аудитом не подтверждены. |
| Octo STS | OIDC identity обменивается на короткоживущий GitHub App token, trust policy ограничивает репозиторий и permissions. Хороший образец для CI workload с проверяемым issuer. | GitHub Actions OIDC не удостоверяет произвольный desktop-процесс Codex/Antigravity. GHSA фиксирует unauthenticated SSRF через поля OIDC token и возможную утечку чувствительных данных в логах до 0.5.3; v0.5.3 добавил sanitization/redaction. Короткий TTL не заменяет проверку issuer/audience/subject, egress controls и отзыв. |
| MCP Authorization | Для HTTP MCP token привязывается к resource URI, сервер проверяет intended audience и не пересылает client token upstream; применяются безопасное хранение и короткий TTL. | Документ относится к HTTP transport; для stdio он указывает credentials из environment, что не скрывает секрет от agent process. OAuth сам по себе не создаёт sandbox. |

### 1.3. Clean-room требования-кандидаты

Не утверждённое решение, а вход в будущее ТЗ:

1. Агент запрашивает структурированную операцию; broker проверяет grant и выполняет её с credential. Значение секрета не возвращается в модельный контекст.
2. Grant ограничен owner-approved task/payload, сессией, операцией, resource/audience, точным host + method + path, сроком/лимитом и policy revision. Имя агента или роль в prompt не доказывают identity.
3. Обе БЗ, Git, task board, transcripts, event/outbox, logs, backups и sync export хранят только credential/grant IDs и receipts, никогда значения ключей или refresh tokens.
4. Неизвестный target, неоднозначное правило, неподдерживаемый протокол, expiry/revocation, неожиданный redirect, DNS rebinding, private/loopback/link-local IPv4/IPv6, proxy bypass или ошибка policy закрываются отказом. Credential scope и network egress проверяются независимо.
5. Если все desktop agents работают под одним Windows пользователем, имя процесса в конфиге не создаёт отдельную security identity. Пока OS boundary не доказана, владелец остаётся корнем доверия; автоматический доступ к новым credentials не выдаётся.
6. Не читать конфигурации, environment, browser profiles, databases, secret stores или процессы других AI-клиентов. Интеграция использует только явную поддерживаемую auth/capability surface либо действие владельца.
7. Подпись request связывает её с ключом, но не заменяет authorization. Receipt фиксирует результат и correlation IDs без секрета/заголовков; операция идемпотентна, grant можно отозвать.

### 1.4. Adversarial checks для будущей реализации

- Synthetic secret markers не должны появляться в prompt, stdout/stderr, argv/env, agent-visible files, Git diff, HTTP errors, transcripts, operational DB, backups и sync exports.
- Проверить host/path/method/audience mismatch, wildcard apex/Unicode, alternate port, redirect на другой host, DNS rebinding, private IPv4/IPv6, proxy bypass, malformed OIDC issuer/aud/sub, replay и подмену task/session/policy revision.
- Проверить отзыв во время сессии, expiry, несколько совпавших правил, restart во время обмена и unknown outcome; старый worker не может продолжить по устаревшему grant.
- Проверить ответы upstream, отражающие credential в header/body, пределы redaction и содержимое ошибок. Не обещать «секрет не утечёт» только потому, что он не выдавался напрямую.
- Для TLS inspection определить фактически расшифровываемый трафик, проверить bypass/pinning/CA removal и требовать явное согласие. Отдельно проверять Windows agent surfaces и CI OIDC identity.

### 1.5. Вывод этапа

**ADAPT:** OpenSandbox — узкие host/method/path bindings, согласование с egress, fail-closed ambiguity, redaction и revision ACK; MCP — resource/audience separation и запрет token passthrough; Octo STS — TTL и точные trust claims; AgentCordon — operation broker, отзыв grant и audit receipts.

**TRANSFORM_SECURITY:** продукты OpenSandbox и AgentCordon требуют иной модели под portable Windows/local-first и разнообразные GUI/CLI/SDK. Компоненты и код не выбраны. Credential broker не входит в первый срез переносимой БЗ; исследование не разрешает автоматизировать auth.

Upstream implementation/tests не запускались, внешнее review/security assessment не проводились. Код и prompts доноров не копировались. Требования и архитектура остаются DRAFT/NOT READY.
