# Implementation Plan: Beads Dolt-Native Migration

**Branch**: `029-beads-dolt-native-migration` | **Date**: 2026-03-20 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/029-beads-dolt-native-migration/spec.md`

## Summary

Официальный upstream `beads` уже живет в Dolt-native модели, но текущий репозиторий все еще завязан на legacy JSONL-first workflow: tracked `.beads/issues.jsonl`, repo-local `bin/bd`, resolver, hook normalization, operator docs и тестовый harness. При этом локально установленный `bd 0.49.6` уже показывает переходное состояние: `bd --help` знает `backend`, `branch`, `vc`, `migrate dolt`, `export` и `sync`, а `bd info` работает в `Mode: direct` с `Reason: worktree_safety`.

Это означает, что проекту нужен не моментальный cutover, а staged migration contract. План переводит репозиторий на новый Beads в два шага: сначала inventory/report-only compatibility layer, затем pilot worktree и controlled rollout. Legacy JSONL path перестает быть целевой архитектурой, но удаляется только после того, как новый operator/review surface, rollback package и readiness matrix доказаны на практике.

## Observed Local Integration

- В этом новом `029` worktree `bd backend show` и `bd info` сейчас указывают на `/Users/rl/coding/moltinger/moltinger-main/.beads`, то есть текущая topology все еще демонстрирует shared/canonical-root coupling even before migration starts.
- Локальный `bd 0.49.6` уже exposes migration-related commands: `bd backend`, `bd branch`, `bd vc`, `bd export`, `bd migrate`, `bd migrate dolt`.
- Repo-local `.envrc`, `bin/bd`, `scripts/beads-resolve-db.sh`, `.githooks/pre-commit`, `scripts/beads-normalize-issues-jsonl.sh`, `.beads/config.yaml`, `.beads/AGENTS.md`, `.claude/docs/beads-quickstart*.md` и `.claude/skills/beads/resources/*` продолжают описывать или enforce legacy `bd sync` + tracked JSONL flow.
- Existing tests and helpers are also JSONL-aware: `tests/static/test_beads_worktree_ownership.sh`, `tests/unit/test_bd_dispatch.sh`, `tests/unit/test_beads_normalize_issues_jsonl.sh`, `tests/unit/test_beads_worktree_audit.sh`, `scripts/worktree-ready.sh`, `scripts/beads-recovery-batch.sh`, `scripts/beads-recover-issue.sh`.
- Следовательно, migration должна охватывать не только CLI backend change, но и repo-local operator contract, docs, hooks, bootstrap flows и validation matrix.

## Technical Context

**Language/Version**: Bash/Zsh shell scripts, Markdown artifacts, existing shell test harness
**Primary Dependencies**: `git`, installed `bd 0.49.6`, existing repo-local `bin/bd`, `scripts/beads-resolve-db.sh`, tracked git hooks, official upstream Beads docs/issues, existing `.specify` workflow
**Storage**: Current state uses SQLite backend plus tracked `.beads/issues.jsonl`; target state is Dolt-native Beads contract with JSONL treated only as explicitly bounded export/backup artifact if retained at all
**Testing**: Shell unit/static tests, migration dry-run verification, pilot worktree validation, focused quickstart execution
**Target Platform**: macOS/Linux developer environments and Codex/App multi-worktree flows
**Project Type**: Repository workflow and issue-state contract migration for multi-worktree Beads usage
**Performance Goals**: Inventory/readiness reports must complete fast enough for routine operator use; pilot/cutover checks should add no surprising latency to normal issue lifecycle; repeated readiness reports must be deterministic
**Constraints**: No long-lived mixed mode, no issue loss, no hidden fallback to legacy JSONL-first workflow, no blind canonical-root cleanup inside migration, docs/AGENTS/skills must align with the active contract, rollback must be separate and evidence-preserving
**Scale/Scope**: 3 user stories, 24 functional requirements, one target Beads contract, one legacy-surface inventory, one pilot cutover path, and one staged rollout/rollback contract
**Upstream Version Scope**: The target direction follows current official Dolt-native upstream guidance, but implementation must remain compatible with the locally observed `bd 0.49.6` command surface until an explicit version-upgrade step is proven and adopted

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Evidence |
|-----------|--------|----------|
| I. Context-First Development | ✅ PASS | Official Beads docs/issues, local CLI behavior, repo-local wrappers/hooks/docs, and current worktree/backend observations were reviewed before design |
| II. Single Source of Truth | ✅ PASS | Plan converges target contract, legacy inventory, rollout gates, and rollback evidence into one migration model |
| III. Library-First Development | ✅ PASS | No new third-party library is required; migration reuses existing `bd` CLI, shell tooling, and spec workflow |
| IV. Code Reuse & DRY | ✅ PASS | Plan reuses current repo-local bootstrap, docs, tests, and Beads scripts where safe, rather than adding a parallel long-lived migration framework |
| V. Strict Type Safety | ✅ N/A | Scope is shell/Markdown workflow migration, not TypeScript |
| VI. Atomic Task Execution | ✅ PASS | Inventory, pilot, docs alignment, rollout, rollback, and tests can be landed in small independently reviewable slices |
| VII. Quality Gates | ✅ PASS | Migration dry-runs, readiness checks, pilot validation, docs alignment, and rollback verification are required deliverables |
| VIII. Progressive Specification | ✅ PASS | Spec, plan, tasks, and read-only analyze are being produced before any migration implementation |

**Gate Status**: ✅ ALL PASS - proceed to design artifacts and task generation.

## Project Structure

### Documentation (this feature)

```text
specs/029-beads-dolt-native-migration/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── inventory-readiness-contract.md
│   ├── pilot-cutover-contract.md
│   ├── review-surface-contract.md
│   ├── rollout-rollback-contract.md
│   └── target-contract.md
└── tasks.md
```

### Source Code (repository root)

```text
bin/
└── bd                                      # Existing repo-local entrypoint to inventory, bridge, then retire or shrink

scripts/
├── beads-resolve-db.sh                     # Existing legacy ownership resolver to inventory and adapt
├── beads-normalize-issues-jsonl.sh         # Existing JSONL normalizer to demote or retire
├── beads-worktree-localize.sh              # Existing localizer that may need compatibility-mode behavior
├── worktree-ready.sh                       # Existing bootstrap/handoff flow to align with the new Beads contract
├── beads-dolt-migration-inventory.sh       # Planned inventory/report-only readiness runner
├── beads-dolt-pilot.sh                     # Planned isolated pilot cutover workflow
└── beads-dolt-rollout.sh                   # Planned staged cutover/rollback orchestrator

docs/
├── beads-dolt-native-migration.md
├── CODEX-OPERATING-MODEL.md
├── WORKTREE-HOTFIX-PLAYBOOK.md
├── rules/
│   └── beads-dolt-native-contract.md
└── migration/
    └── beads-dolt-native-cutover.md

.beads/
├── AGENTS.md
└── config.yaml

.githooks/
└── pre-commit

.claude/docs/
├── beads-quickstart.md
└── beads-quickstart.en.md

.claude/skills/beads/resources/
├── COMMANDS_QUICKREF.md
└── WORKFLOWS.md

tests/
├── static/
│   └── test_beads_dolt_docs_alignment.sh
└── unit/
    ├── test_beads_dolt_inventory.sh
    ├── test_beads_dolt_pilot.sh
    └── test_beads_dolt_rollout.sh
```

**Structure Decision**: Keep migration implementation script-first and repo-local. Add three dedicated migration flows: inventory/report-only, pilot cutover, and staged rollout/rollback. Legacy resolver/normalizer/bootstrap surfaces remain in scope only long enough to inventory, bridge, and retire or adapt them under one target Beads contract.

## Phase 0: Research Decisions

Research outcomes are recorded in [research.md](./research.md). The design direction is:

1. Treat current official upstream Dolt-native Beads as the target architecture, not the current repo behavior.
2. Keep current repo-local JSONL-first workflow only as a migration source, not as the long-term design target.
3. Require a full deterministic inventory of legacy surfaces before any cutover attempt.
4. Introduce a report-only compatibility layer before pilot or rollout so mixed mode is observable and blocked.
5. Prove the new contract on one isolated pilot worktree before touching remaining worktrees.
6. Define a new operator/review surface before removing reliance on tracked `.beads/issues.jsonl`.
7. Keep rollout and rollback as separate procedures with separate evidence.
8. Scope migration against the locally observed `bd 0.49.6` command surface and topology behavior, even while targeting newer upstream semantics.
9. Do not mix migration with canonical-root cleanup or with the current RCA fix for legacy `.beads/issues.jsonl` drift.

## Phase 1: Design Outcomes

Phase 1 artifacts define:

- the target Beads contract in [contracts/target-contract.md](./contracts/target-contract.md)
- readiness inventory and gating rules in [contracts/inventory-readiness-contract.md](./contracts/inventory-readiness-contract.md)
- pilot expectations in [contracts/pilot-cutover-contract.md](./contracts/pilot-cutover-contract.md)
- the replacement operator/review surface in [contracts/review-surface-contract.md](./contracts/review-surface-contract.md)
- staged rollout and rollback boundaries in [contracts/rollout-rollback-contract.md](./contracts/rollout-rollback-contract.md)
- migration entities and worktree statuses in [data-model.md](./data-model.md)
- operator validation scenarios in [quickstart.md](./quickstart.md)

## Phase 2: Execution Readiness

- No implementation task should start until official upstream findings, local CLI capability checks, and repo-local inventory scope are all reflected in tasks.
- Inventory/report-only detection lands before any mutating pilot or cutover flow.
- Pilot success criteria must be explicit and must prove that legacy JSONL-first reasoning is no longer part of the everyday workflow for the pilot worktree.
- Docs, AGENTS, skills, hooks, and bootstrap surfaces must converge on one active Beads contract before full cutover.
- Rollback must restore operator usability and issue-state consistency, not only revert command wrappers.

## V1 Scope Freeze

### In Scope

- One explicit target Dolt-native-compatible Beads contract for this repo
- One deterministic inventory of legacy repo-local Beads surfaces
- One report-only compatibility layer
- One isolated pilot cutover path
- One staged rollout and one separate rollback contract
- Docs, AGENTS, skills, hooks, and tests alignment with the active contract

### Out of Scope

- Solving the current legacy JSONL drift RCA inside this feature
- Bulk canonical-root cleanup bundled into the migration
- Silent or best-effort mixed-mode support as a long-lived operating model
- Replacing Beads with another tracker
- Non-Beads worktree topology publication or unrelated deployment fixes

## Executor Lanes

| Lane | Scope | Primary owner |
|---|---|---|
| `inventory` | repo-local surface inventory, readiness report, blockers | main implementer |
| `pilot` | isolated worktree cutover and compatibility interception | main implementer |
| `rollout` | staged cutover, rollback, docs/AGENTS/skills alignment | main implementer |
| `tests` | static/unit/pilot validation matrix | main implementer |

## Test Fixture Strategy

- Reuse temporary repo/worktree fixtures from the existing shell harness.
- Model at least one legacy JSONL-first worktree, one pilot-ready worktree, one blocked sibling worktree, and one bootstrap-variance case.
- Validate inventory determinism with repeated report-only runs.
- Validate pilot behavior against both allowed and forbidden legacy surfaces.
- Validate rollback after partial rollout without requiring destructive cleanup of unrelated worktrees.

## Agent Context Update

- No new programming language or external runtime is introduced.
- Agent context should reflect that Beads migration is now a first-class repo workflow, but current legacy JSONL RCA remains a separate feature stream.
