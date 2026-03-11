# Implementation Plan: Worktree Handoff Hardening

**Branch**: `011-worktree-handoff-hardening` | **Date**: 2026-03-09 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/011-worktree-handoff-hardening/spec.md`

## Summary

Harden the `command-worktree` boundary so create and attach flows remain strictly Phase A-only in the originating session, while manual handoff preserves enough downstream intent for complex requests such as Speckit startup. The design stays additive over the existing workflow: keep manual handoff as default, keep automatic Codex or terminal launch opt-in, separate the concise pending summary from any richer Phase B seed payload, and align helper output, command instructions, and regression coverage around one stop-after-handoff contract.

## Technical Context

**Language/Version**: Markdown command artifacts + Bash shell helpers and shell-based unit tests  
**Primary Dependencies**: `bd` CLI, `git worktree`, `.claude/commands/worktree.md`, `scripts/worktree-ready.sh`, `tests/unit/test_worktree_ready.sh`, optional launch integrations already supported by the current workflow  
**Storage**: Repository files, helper output contracts, and Speckit artifacts in `specs/011-worktree-handoff-hardening/`  
**Testing**: Shell unit tests and command/workflow regression scenarios for create and attach handoff behavior  
**Target Platform**: Codex/terminal worktree workflows in the existing repository development environment  
**Project Type**: Single repository workflow hardening  
**Performance Goals**: Preserve current create and attach responsiveness while adding no extra operator steps for simple manual handoff flows  
**Constraints**: Stop after Phase A; manual handoff remains default; automatic Codex or terminal handoff remains opt-in; preserve existing worktree creation behavior unless boundary correctness requires change; do not redesign unrelated Beads or topology workflows; do not modify production behavior; regression coverage required  
**Scale/Scope**: 4 user stories, 23 functional requirements, one worktree workflow area spanning command guidance, helper contract, and test coverage

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Evidence |
|-----------|--------|----------|
| I. Context-First Development | ✅ PASS | Existing `command-worktree` command instructions, helper contract, current tests, and prior worktree spec artifacts were reviewed before planning |
| II. Single Source of Truth | ✅ PASS | The plan keeps one authoritative boundary and handoff contract shared by helper output, instructions, and tests |
| III. Library-First Development | ✅ PASS | No new third-party library is needed; the change extends existing repository workflows and helper/test surfaces |
| IV. Code Reuse & DRY | ✅ PASS | The plan reuses the current `command-worktree` guidance, helper surfaces, and shell test infrastructure rather than introducing parallel workflows |
| V. Strict Type Safety | ✅ N/A | Planned scope is Markdown and shell, not a TypeScript runtime surface |
| VI. Atomic Task Execution | ✅ PASS | Tasks can be split into contract/spec alignment, helper behavior, and regression coverage slices |
| VII. Quality Gates | ✅ PASS | Regression coverage is part of feature scope and is required before implementation is considered complete |
| VIII. Progressive Specification | ✅ PASS | This session is limited to spec, plan, tasks, and Beads import before any runtime implementation |

**Gate Status**: ✅ ALL PASS - proceed to research and design artifacts

## Project Structure

### Documentation (this feature)

```text
specs/011-worktree-handoff-hardening/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── worktree-boundary-contract.md
│   ├── manual-handoff-contract.md
│   └── regression-coverage-contract.md
└── tasks.md
```

### Source Code (repository root)

```text
.claude/commands/
└── worktree.md

scripts/
└── worktree-ready.sh

tests/unit/
└── test_worktree_ready.sh
```

**Structure Decision**: Keep the feature focused on the existing worktree workflow surfaces that define or prove the boundary: the user-facing command instructions, the helper that emits the handoff contract, and the unit/regression coverage that protects the behavior.

## Phase 0: Research Decisions

Research findings are documented in [research.md](./research.md). The main outcomes:

1. Preserve the current two-phase conceptual model and make the stop-after-Phase-A rule more explicit instead of redesigning the workflow.
2. Keep `pending_summary` as a concise human-readable field, but add or formalize a separate richer Phase B seed carrier for complex downstream intent.
3. Reuse the existing helper and shell test surfaces instead of inventing a new orchestration layer.
4. Treat create and attach as equal boundary commands for regression purposes.
5. Keep manual handoff as the safe default and automatic launch as opt-in only.

## Phase 1: Design Outcomes

Phase 1 artifacts define:

- the boundary, handoff, and regression entities in [data-model.md](./data-model.md)
- the authoritative behavior for stop-after-Phase-A, manual handoff payload roles, and regression coverage in [contracts/worktree-boundary-contract.md](./contracts/worktree-boundary-contract.md), [contracts/manual-handoff-contract.md](./contracts/manual-handoff-contract.md), and [contracts/regression-coverage-contract.md](./contracts/regression-coverage-contract.md)
- the validation scenarios for create, attach, structured downstream requests, and opt-in launch fallback in [quickstart.md](./quickstart.md)

## Complexity Tracking

> No constitution violations currently require justification.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| N/A | N/A | N/A |
