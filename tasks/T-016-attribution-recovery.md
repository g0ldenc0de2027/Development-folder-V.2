# T-016 — Восстановление T-013 с неизвестным историческим происхождением

- **Статус:** in_progress; T-016 опубликована в draft PR #15; первый hosted quality-gate успешен, свежее независимое review актуального PR head ожидается. Текущие head и CI проверяются по PR #15.
- **Тип:** attribution recovery и scoped documentation/spec maintenance; без продуктовой реализации.
- **Главный ИИ:** Codex (OpenAI), GPT-6.
- **База:** f577dc70e58d75ab5fd61d0c2e712c27b590713a; live origin/main совпадал с этим SHA перед созданием worktree.
- **Recovery-ветка/worktree:** task/T-016-attribution-recovery / .worktrees/T-016.
- **Источник:** task/T-013-agent-orchestration-research, committed HEAD 88342060af7c6c18a163d3b6fa6727ab5c17fd7e, seven modified paths; два локальных commits имеют fixture author Scope Fixture.
- **Историческое происхождение:** UNKNOWN. Source branch/worktree и старые commits сохраняются; reset, amend, rebase, force push и переписывание истории запрещены.
- **Recovery editor:** Codex GPT-6 в T-016. Это атрибутирует только новую recovery-сборку и её commit, не исходные исторические фрагменты.
- **PR:** #15 открыт, Draft; merge не выполнялся. Первый recovery commit `a6e458e6972aeda409a9520c6bc0fd2d47d4f7d5` прошёл hosted run `#44173816019` на merge-result `571d79398c150fd8d46dafd257f56fbe571f7ca4`; родители merge-result — base `f577dc70e58d75ab5fd61d0c2e712c27b590713a` и этот head. Это свидетельство первой PR-редакции; актуальные после статусного обновления head и CI смотреть в PR #15. Независимое cross-vendor review актуального head не проводилось.

## Цель

Перенести точный объём T-013 из смешанного дерева в новую branch от live origin/main, явно отделить происхождение источника от автора recovery, учесть подтверждённые замечания и вернуть T-013 в обычный review workflow без утраты данных или исправления истории старой ветки.

## Зона файлов

- tasks/T-016-attribution-recovery.md
- tasks/T-013-agent-orchestration-research-and-spec.md
- docs/handoff.md
- docs/agent-orchestration-roadmap.md
- specification-system/tz_state.md
- spec/agent-orchestration.md
- knowledge/records/agent-orchestration-research-2026-11-16.md
- knowledge/catalog.json

## Recovery input manifest

Формат: Canonical Bundle Manifest Format 1; raw SHA-256 файлов, ordinal UTF-8 path order, один LF между записями и без LF после последней строки.

| Source path | SHA-256 raw bytes |
|---|---|
| docs/agent-orchestration-roadmap.md | 19612a2eaa70fa4d087cd9fcb82fec9b01dd50d29a065d6c258ffd93f5571420 |
| docs/handoff.md | 240327a43600032b111866ad0bed46c0e5b7c19c5be52d4e584f761fb1bf2bde |
| knowledge/catalog.json | a0581b9adf5cbb8cee5f05a022bcd112e3cb58b56f5653bb15c13217418afdc6 |
| knowledge/records/agent-orchestration-research-2026-11-16.md | 05e0e65a2a65c30ca605e7df149beb2310236d2aa06ca1cfa6104a57172ed62d |
| spec/agent-orchestration.md | 47d7c9b0291f80d97d293197d427f86870dc2d0983b6d5ac0a5f4d864de525aa |
| specification-system/tz_state.md | 0144c4eee302abaf47b25df365918c53fa38281fe62d9d509d35f0b931b362d5 |
| tasks/T-013-agent-orchestration-research-and-spec.md | cd1e106747fc758a96f71889691b1764adcf9a8d214d6151de2457386802be6e |

- Manifest size: 704 bytes.
- Manifest SHA-256: 39fc2f2f042d15e546b778cff626ab8e60d1eaf0adf3383b80868fb64e9cc37f.
- Seven files were copied byte-for-byte into the clean worktree before edits. The source T-013 worktree remains intact.

## Review disposition carried into this recovery

- Lifecycle/assignment, account-memory digest, COM superscript device names, and conditional M5 review-policy requirements already exist in the copied T-013 text. The old findings used earlier fingerprints and are not treated as fresh approvals or as current unaddressed defects.
- The missing normative Unicode display policy was accepted and corrected in FR-AOR-006; its full source basis and limits are recorded in the R7 research section.
- Earlier reports with fingerprints 5fea239… and 64d069… apply only to their respective earlier snapshots. Fresh review must verify the exact T-016 head and current CI.

## Acceptance

1. Recovery base is exact live origin/main; the recovery commit ancestry contains no copied Scope Fixture commit objects.
2. Changed paths equal exactly the eight paths in this task scope; no unrelated staged, unstaged, or untracked path is included.
3. Source provenance is labeled UNKNOWN wherever the file-level origin is asserted; current recovery edits/commit author are stated separately.
4. T-013 requirements remain DRAFT / NOT READY; no implementation, provider invocation, automatic dispatch, or integration claim is added.
5. UCD 18.0.0 policy uses the official Default_Ignorable_Code_Point and Bidi_Control data files; U+00AD, U+034F, bidi, zero-width, reserved/unassigned, and a negative control vector are explicit. Raw bytes/hash and escaped projection digest are distinct and bound to permit/approval.
6. Prior review findings are dispositioned with exact in-tree requirement evidence; no old report is claimed as approval of the recovery head.
7. Full quality gate, KB integrity, privacy/hygiene, actionlint, Gitleaks and git diff checks pass on the exact final commit before push. Hosted CI and fresh independent review are tied to the eventual exact PR head; no merge before current review and gates.

## Limits and prohibited actions

- This is documentation/specification recovery only. It does not implement Unicode escaping, agent coordination, ACL, adapters, or runtime checks.
- Do not reset, clean, rebase, amend, delete, or rewrite the original T-013 branch/worktree. Do not push directly to main or merge this recovery PR.
