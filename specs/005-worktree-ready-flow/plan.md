# Implementation Plan: Worktree Ready UX

**Branch**: `005-worktree-ready-flow` | **Date**: 2026-03-08 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/005-worktree-ready-flow/spec.md`

## Summary

Улучшение навыка `worktree` должно довести пользователя до состояния `developer ready`, а не останавливаться на факте создания git worktree. Технический подход: расширить [`worktree.md`](/Users/rl/coding/moltinger/.claude/commands/worktree.md) новым first-class flow для существующей ветки и one-shot slug-only start, ввести явный readiness contract и вынести повторяемую shell-логику в один детерминированный helper-скрипт для path normalization, live topology conflict detection, readiness/doctor статусов и next-step handoff.

Дополнительный design slice для текущего UAT-дефекта: `command-worktree` должен стать двухфазным. Phase A подготавливает dedicated worktree (`plan -> mutate -> reconcile -> classify -> emit handoff`), после чего workflow обязан остановиться. Phase B выполняется только уже из созданного worktree или в новой handoff-сессии. Для этого helper получает machine-readable handoff contract (`key=value`) и явные terminal handoff states, а `worktree.md` закрепляет hard stop-and-handoff boundary.

Ключевой design choice: не автоматизировать доверительные действия вроде одобрения `.envrc` по умолчанию. Вместо этого команда должна заранее выявлять, что для текущего worktree потребуется дополнительный шаг, и возвращать точные инструкции или opt-in handoff. Для one-shot start authoritative проверкой конфликтов считается live `git`, а committed topology registry используется как shared snapshot и должен refresh-иться сразу после mutation.

## Technical Context

**Language/Version**: Markdown command artifacts + Bash/Zsh shell helpers
**Primary Dependencies**: `bd` CLI, `git worktree`, `git for-each-ref`, [`scripts/git-session-guard.sh`](/Users/rl/coding/moltinger/scripts/git-session-guard.sh), [`scripts/git-topology-registry.sh`](/Users/rl/coding/moltinger/scripts/git-topology-registry.sh), `direnv`, Codex CLI, optional `osascript` / terminal integrations
**Storage**: File-based command/spec documents + git worktree metadata
**Testing**: Shell smoke checks, manual workflow validation for blocked/approved environment states, output-contract verification against quickstart scenarios, unit coverage for machine-readable handoff contract and stop-boundary states
**Target Platform**: macOS-first terminal workflows with graceful fallback on non-macOS systems
**Project Type**: Single (CLI/skill workflow enhancement)
**Performance Goals**: Readiness classification and next-step generation complete in under 2 seconds after worktree creation; zero follow-up explanation needed for primary flows
**Constraints**: Preserve trust boundary for environment approval, stay additive over existing low-level `bd worktree` usage, avoid destructive cleanup behavior changes, degrade gracefully when terminal automation is unavailable
**Scale/Scope**: 6 user stories, 39 functional requirements, one command artifact update plus one helper script and supporting docs/contracts

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Evidence |
|-----------|--------|----------|
| I. Context-First Development | ✅ PASS | Existing [`worktree.md`](/Users/rl/coding/moltinger/.claude/commands/worktree.md), [`scripts/git-session-guard.sh`](/Users/rl/coding/moltinger/scripts/git-session-guard.sh), `.envrc`, `bd worktree` behavior, and real user flow were analyzed before planning |
| II. Single Source of Truth | ✅ PASS | New readiness logic is centralized in a single helper script rather than duplicated across prompt branches |
| III. Library-First Development | ✅ PASS | No new third-party library selected; existing shell tooling and `bd`/`git` primitives cover the feature without added dependency overhead |
| IV. Code Reuse & DRY | ✅ PASS | Plan reuses `bd worktree create/list` and `git-session-guard.sh --refresh/--status` rather than reimplementing worktree or guard logic |
| V. Strict Type Safety | ✅ N/A | Planned implementation is Markdown and shell, no TypeScript surface in MVP |
| VI. Atomic Task Execution | ✅ PASS | Tasks will separate contract, helper script, command artifact, and validation flows into independently reviewable slices |
| VII. Quality Gates | ✅ PASS | Manual workflow verification and shell-level output validation are part of the plan before merge |
| VIII. Progressive Specification | ✅ PASS | Spec, plan, and task artifacts are being generated in order before implementation |

**Gate Status**: ✅ ALL PASS - Proceed to Phase 0 and Phase 1 artifacts

## Project Structure

### Documentation (this feature)

```text
specs/005-worktree-ready-flow/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── worktree-command-interface.md
│   ├── worktree-planning-schema.md
│   └── worktree-readiness-schema.md
└── tasks.md
```

### Source Code (repository root)

```text
.claude/commands/
└── worktree.md                 # Command workflow to upgrade

scripts/
├── git-session-guard.sh        # Existing guard reused for readiness/doctor
└── worktree-ready.sh           # New helper for path, readiness, next steps, doctor, handoff

specs/
└── 005-worktree-ready-flow/    # Speckit artifacts for this feature
```

**Structure Decision**: Keep the human-facing workflow definition in `.claude/commands/worktree.md`, but move deterministic state inspection and formatting into a new helper script so readiness behavior is testable and reusable across create, doctor, and optional handoff flows.

## Phase 0: Research Decisions

Research findings are documented in [research.md](./research.md). The main outcomes:

1. Continue using `bd worktree create/list` as the authoritative worktree integration point.
2. Reuse `scripts/git-session-guard.sh --refresh` and `--status` for session integrity instead of inventing another guard mechanism.
3. Treat `.envrc` readiness as a surfaced user action, not an implicit side effect.
4. Prefer a single helper script over embedding all readiness logic directly in the command artifact.
5. For start/create collision checks, prefer live `git` (`git worktree list`, local refs, remote refs) over committed registry snapshots when they disagree.

## Phase 1: Design Outcomes

Phase 1 artifacts define:

- the data entities and status model in [data-model.md](./data-model.md)
- the command, planning, readiness, and handoff contracts in [contracts/worktree-command-interface.md](./contracts/worktree-command-interface.md), [contracts/worktree-planning-schema.md](./contracts/worktree-planning-schema.md), [contracts/worktree-readiness-schema.md](./contracts/worktree-readiness-schema.md), and `contracts/worktree-handoff-schema.md`
- the end-to-end validation scenarios in [quickstart.md](./quickstart.md)

## Complexity Tracking

> No constitution violations currently require justification.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| N/A | N/A | N/A |
