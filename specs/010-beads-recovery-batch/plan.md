# Implementation Plan: Safe Batch Recovery of Leaked Beads Issues

**Branch**: `010-beads-recovery-batch` | **Date**: 2026-03-09 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/010-beads-recovery-batch/spec.md`

## Summary

Add a script-first batch recovery workflow that audits leaked issues in the canonical root tracker, produces a deterministic plan, and applies only high-confidence recoveries into localized owner worktrees. Reuse the existing single-issue recovery and localization helpers, add explicit ownership overrides for ambiguous cases, and leave canonical root cleanup out of scope for the same command.

## Technical Context

**Language/Version**: Bash 3.2+ and repository-standard JSON/Markdown  
**Primary Dependencies**: `git`, `bd`, `jq`, existing repo shell helpers and tests  
**Storage**: canonical root `.beads/issues.jsonl`, worktree-local `.beads/issues.jsonl` and `.beads/beads.db`, committed ownership override file, generated plan and journal JSON  
**Testing**: shell unit/static tests plus `make codex-check` for governance-sensitive docs  
**Target Platform**: macOS/Linux developer machines with multiple git worktrees
**Project Type**: Repository workflow automation + Beads state repair  
**Performance Goals**: audit in under 10 seconds and safe apply in under 15 seconds on the current repo topology  
**Constraints**: fail closed on ambiguous ownership, do not rewrite canonical root in the same command, tolerate current `molt` vs `moltinger-*` prefix mismatch, produce deterministic machine-readable artifacts  
**Scale/Scope**: single repository, dozens of worktrees at most, hundreds of tracker records, small batches of leaked issues per run

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- Context-First Development: PASS (existing recovery, localization, worktree, topology, and test contracts reviewed first)
- Single Source of Truth: PASS (one batch owner script, one ownership override file, one plan artifact per run)
- Library-First Development: PASS (reuse existing repo scripts and `jq`; no new external library is justified)
- Code Reuse & DRY: PASS (batch flow wraps existing `beads-recover-issue.sh` and `beads-worktree-localize.sh` rather than replacing them)
- Strict Type Safety: N/A (Bash/JSON scope)
- Atomic Task Execution: PASS (audit, apply, docs, and validation can be implemented as narrow slices)
- Quality Gates: PASS (shell tests plus governance check will gate the change)
- Progressive Specification: PASS (spec -> plan -> tasks -> implement flow is being followed)

No constitution violations require exception handling.

## Project Structure

### Documentation (this feature)

```text
specs/010-beads-recovery-batch/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── recovery-batch-cli.md
└── tasks.md
```

### Source Code (repository root)

```text
scripts/
docs/
tests/unit/
tests/static/
```

**Structure Decision**: Keep the implementation in the existing repo workflow layers: one owner batch script in `scripts/`, one committed ownership override file in `docs/`, targeted shell tests in `tests/unit/` and `tests/static/`, and operating-model updates in `docs/`.

## Phase 0: Research Decisions (to `research.md`)

1. Reuse existing single-issue recovery and worktree localization helpers instead of building a second recovery engine.
2. Drive batch automation from deterministic JSON plan and journal artifacts rather than ad hoc stdout parsing.
3. Treat explicit ownership overrides as the only safe path for ambiguous issue-to-worktree mappings.
4. Keep canonical root cleanup out of scope for the same command that performs automatic recovery apply.
5. Preserve JSONL-level recovery even when the local Beads database cannot import safely due to prefix mismatch.

## Phase 1: Design Artifacts

- Define entities for ownership overrides, audit candidates, plan actions, backups, and run journals.
- Define the CLI contract for `audit` and `apply` modes, including exit codes and fail-closed blockers.
- Define deterministic JSON artifact formats for plan and journal outputs.
- Define quickstart flows for audit-only, safe apply, and operator review.

## Phase 2: Execution Readiness

- Generate atomic tasks grouped by user story.
- Keep implementation centered on one owner batch script that delegates single-item work to existing helpers.
- Ensure final validation covers ambiguous ownership, redirected worktrees, duplicate detection, stale-plan blocking, and journal creation.

## V1 Scope Freeze

### In Scope

- One owner script at `scripts/beads-recovery-batch.sh` with `audit` and `apply` modes.
- One committed ownership override artifact under `docs/`.
- Deterministic JSON plan and journal artifacts generated under a repo-local temp or output path.
- Reuse of `scripts/beads-worktree-localize.sh` and `scripts/beads-recover-issue.sh` for actual worktree repair.
- Unit/static coverage for audit/apply safety boundaries.
- Documentation updates for the new recovery workflow.

### Out of Scope

- Automatic canonical root cleanup in the same command.
- Automatic owner inference from weak heuristics alone.
- Global Beads prefix migration from `molt` to `moltinger-*`.
- Background daemons or always-on watchers for tracker recovery.
- Rewriting unrelated worktrees or tracker files not referenced by the approved plan.

## Executor Lanes

| Lane | Scope | Primary owner |
|---|---|---|
| `shell-core` | `scripts/beads-recovery-batch.sh`, existing recovery/localize integration, `scripts/manifest.json` | main implementer |
| `docs-contract` | `docs/`, `specs/010-beads-recovery-batch/`, operating model updates | main implementer |
| `tests` | `tests/unit/`, `tests/static/` | main implementer, reviewable independently |

## Test Fixture Strategy

- Build batch-recovery tests around temporary repositories and throwaway worktrees under `mktemp -d`.
- Seed fixture repos with tracked `.beads/config.yaml` and `.beads/issues.jsonl` so localization and recovery operate on realistic inputs.
- Use synthetic ownership override files and canonical root JSONL snapshots to cover safe, duplicate, ambiguous, and stale-plan scenarios.
- Keep destructive root cleanup out of fixtures for this feature; tests should prove it never happens.

## Agent Context Update

- No new language or framework is introduced.
- Agent context files do not need semantic updates for this feature beyond the spec artifacts themselves.
