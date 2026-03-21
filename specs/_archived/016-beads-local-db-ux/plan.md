# Implementation Plan: UX-Safe Beads Local Ownership

**Branch**: `016-beads-local-db-ux` | **Date**: 2026-03-12 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/016-beads-local-db-ux/spec.md`

## Summary

Текущее unsafe поведение подтверждено фактами в этой worktree: plain `bd info` сейчас резолвит database path в canonical root (`/Users/rl/coding/moltinger/.beads/beads.db`), а явный `bd --db .beads/beads.db info` корректно работает с локальной worktree DB. Значит auto-discovery самого `bd` нельзя считать надежным ownership mechanism для git worktree, и решение должно убрать зависимость от того, загрузился ли `BEADS_DB` через `direnv`.

Технический подход: сделать repo-local plain-`bd` dispatch явным и детерминированным. Для этого план вводит worktree-aware shim под обычным именем `bd`, который валидирует local `.beads` ownership contract и запускает системный `bd` через явный `--db <worktree-local-db>` только в безопасных состояниях. Если local ownership не подтвержден, shim fail-closed останавливает mutating commands с понятной ошибкой и recovery path.

Чтобы пользователь не выбирал между `bd` и `bd-local`, plain `bd` станет repo-local default через два канала bootstrap:
- `direnv`/`.envrc`, когда он доступен и одобрен
- managed launch/handoff paths (`worktree-ready`, Codex launcher и смежные session entrypoints), когда `direnv` недоступен или не одобрен

Отдельный compatibility slice покроет уже открытые worktree: локальный ownership contract считается валидным, если текущая worktree содержит локальные `.beads/config.yaml`, `.beads/issues.jsonl`, `.beads/beads.db` и не содержит legacy redirect residue. Для legacy/partial states будет спроектирован отдельный managed localization flow, который восстанавливает local ownership in place там, где это безопасно, и никогда не возвращается к shared redirect path.

Root cleanup intentionally остается вне scope steady-state ownership fix. План допускает только явное обнаружение и маркировку residual root cleanup как отдельного follow-up потока. Ни plain `bd`, ни compatibility migration не должны чинить canonical root `main` вручную или маскировать старый residue как завершенную cleanup-работу.

## Technical Context

**Language/Version**: Bash/Zsh shell scripts plus Markdown command/docs artifacts
**Primary Dependencies**: `bd` CLI with explicit `--db` flag support, `git rev-parse`, `direnv`, `scripts/worktree-ready.sh`, `scripts/codex-profile-launch.sh`, repo-local docs and instruction surfaces
**Storage**: Worktree-local `.beads/` files (`config.yaml`, `issues.jsonl`, `beads.db`) plus repo-tracked shell/docs/test artifacts
**Testing**: Shell unit tests, static guardrail tests, quickstart/manual validation for worktree migration and bootstrap scenarios
**Target Platform**: macOS-first local developer and Codex/App sessions with POSIX-shell-compatible behavior
**Project Type**: Single repository CLI/workflow hardening
**Performance Goals**: Ownership resolution and dispatch decision complete before command handoff with no noticeable extra latency in daily `bd` usage; blocking errors are immediate and actionable on first failure
**Constraints**: No silent fallback to canonical root, no return to shared redirect ownership, no manual root `main` repair, no blind stash/reset/pull hacks, no breakage of existing worktrees or branches, `direnv` cannot be the sole safety mechanism, docs/tests/guardrails are mandatory
**Scale/Scope**: 3 user stories, 26 functional requirements, one repo-local command-dispatch layer, one compatibility localization path, bootstrap changes in session entrypoints, and repo-wide docs/test guardrail alignment

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Evidence |
|-----------|--------|----------|
| I. Context-First Development | ✅ PASS | Current repo state, historical `bd-local.sh`, current `bd info`/`bd --db` behavior, `.envrc`, worktree helpers, and existing tests/docs were inspected before planning |
| II. Single Source of Truth | ✅ PASS | Plan uses worktree-local `.beads/` foundation as the ownership contract instead of duplicating ownership state across wrapper lore and ad hoc env assumptions |
| III. Library-First Development | ✅ PASS | No new library is needed; the design reuses native `bd --db` dispatch, existing shell scripts, and current test infrastructure |
| IV. Code Reuse & DRY | ✅ PASS | Plan reuses `bd` itself for command execution, existing worktree/Codex launch surfaces for bootstrap, and current shell test framework for guardrails |
| V. Strict Type Safety | ✅ N/A | Planned MVP is shell and Markdown, not TypeScript |
| VI. Atomic Task Execution | ✅ PASS | Tasks will separate dispatch, bootstrap, migration, docs, and validation into small independently reviewable slices |
| VII. Quality Gates | ✅ PASS | Unit/static validation plus quickstart scenario checks are part of the design, and docs/guardrails are required deliverables |
| VIII. Progressive Specification | ✅ PASS | Spec, plan, and tasks are being produced before implementation |

**Gate Status**: ✅ ALL PASS - Proceed to Phase 0 and Phase 1 artifacts

## Project Structure

### Documentation (this feature)

```text
specs/016-beads-local-db-ux/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── bd-dispatch-contract.md
│   ├── ownership-migration-boundary.md
│   └── session-bootstrap-contract.md
└── tasks.md
```

### Source Code (repository root)

```text
bin/
└── bd                          # Planned repo-local shim for plain `bd`

scripts/
├── codex-profile-launch.sh     # Existing launcher to bootstrap plain `bd`
├── worktree-ready.sh           # Existing handoff/readiness flow to bootstrap plain `bd`
├── beads-resolve-db.sh         # Planned ownership resolver and fail-closed decision helper
└── beads-worktree-localize.sh  # Planned compatibility/migration helper

.envrc                          # Optional direnv bootstrap path

.claude/commands/
├── worktree.md                 # Managed launch/handoff guidance
├── beads-init.md               # Beads setup guidance
└── speckit.tobeads.md          # Beads import workflow guidance

.claude/docs/
├── beads-quickstart.md
└── beads-quickstart.en.md

tests/
├── unit/
│   ├── test_bd_dispatch.sh
│   └── test_worktree_ready.sh
└── static/
    └── test_beads_worktree_ownership.sh
```

**Structure Decision**: Keep ownership resolution in one shell helper and expose the user-facing plain `bd` contract through a repo-local shim plus session bootstrap surfaces. This preserves a single default command for users while keeping fail-closed logic testable and centralized.

## Phase 0: Research Decisions

Research findings are documented in [research.md](./research.md). The main outcomes:

1. Use `bd --db <worktree-local-db>` as the execution primitive for safe local ownership instead of relying on implicit auto-discovery or `BEADS_DB` alone.
2. Treat the current worktree’s `.beads/` foundation files as the ownership contract and validate them before any mutating dispatch.
3. Deliver plain-`bd` UX through a repo-local shim plus multi-channel bootstrap (`.envrc` when available, managed launch/handoff when not).
4. Keep compatibility migration for legacy worktrees as a separate managed path and never return to shared redirect ownership.
5. Preserve explicit troubleshooting-only fallbacks such as manual `--db` or `--no-db` usage as non-default flows.
6. Keep residual root cleanup as a separate follow-up stream rather than mixing it into ownership repair.

## Phase 1: Design Outcomes

Phase 1 artifacts define:

- the ownership, dispatch, bootstrap, migration, and cleanup-boundary entities in [data-model.md](./data-model.md)
- the plain-`bd` runtime guarantees in [contracts/bd-dispatch-contract.md](./contracts/bd-dispatch-contract.md)
- the session bootstrap responsibilities in [contracts/session-bootstrap-contract.md](./contracts/session-bootstrap-contract.md)
- the separation between compatibility migration and root cleanup in [contracts/ownership-migration-boundary.md](./contracts/ownership-migration-boundary.md)
- the end-to-end operator and agent validation scenarios in [quickstart.md](./quickstart.md)

## Complexity Tracking

> No constitution violations currently require justification.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| N/A | N/A | N/A |
