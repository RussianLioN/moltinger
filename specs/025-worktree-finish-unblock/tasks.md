# Tasks: Safely Unblock `command-worktree finish`

**Input**: Design documents from `/specs/025-worktree-finish-unblock/`
**Prerequisites**: `spec.md`, `plan.md`

**Tests**: Required. This follow-up explicitly adds and expands targeted shell tests before final delivery.

**Organization**: Tasks are grouped by user story so ordinary helper behavior and command-contract behavior can be verified independently.

## Phase 1: Specification

- [x] T001 Create branch-scoped specification in `specs/025-worktree-finish-unblock/spec.md`
- [x] T002 Create constrained implementation plan in `specs/025-worktree-finish-unblock/plan.md`
- [x] T003 Generate and keep this execution task list current in `specs/025-worktree-finish-unblock/tasks.md`

---

## Phase 2: User Story 1 - Safe Issue Resolution for Ordinary Flows (Priority: P1) 🎯 MVP

**Goal**: Make ordinary helper issue resolution conservative and keep local/stale readiness behavior honest.

**Independent Test**: `bash tests/unit/test_worktree_ready.sh`

- [x] T004 [US1] Harden ambiguous branch-to-issue resolution in `scripts/worktree-ready.sh`
- [x] T005 [US1] Add ambiguous branch-mapping coverage with `Issue: n/a` assertions in `tests/unit/test_worktree_ready.sh`
- [x] T006 [US1] Add regression coverage proving `beads_state=local` does not route to `./scripts/beads-worktree-localize.sh --path .` in `tests/unit/test_worktree_ready.sh`
- [x] T007 [US1] Add regression coverage proving stale topology in ordinary doctor remains a warning/deferred publish path in `tests/unit/test_worktree_ready.sh`
- [x] T007a [US1] Add executable ordinary `finish` mode in `scripts/worktree-ready.sh` with conservative `Issue: n/a` and deferred topology publication
- [x] T007b [US1] Add ordinary `finish` coverage for ambiguous issue mapping and stale topology in `tests/unit/test_worktree_ready.sh`

---

## Phase 3: User Story 2 - Honest Finish Contract for `command-worktree` (Priority: P2)

**Goal**: Align the documented ordinary worktree finish/doctor contract with plain `bd`, `Issue: n/a`, and dedicated topology publication only.

**Independent Test**: `bash tests/static/test_beads_worktree_ownership.sh` and `make codex-check`

- [x] T008 [US2] Replace ordinary `bd-local.sh` references with plain `bd` contract language in `.claude/commands/worktree.md`
- [x] T009 [US2] Document `Issue: n/a` skip-close behavior and deferred dedicated topology publication in `.claude/commands/worktree.md`
- [x] T010 [US2] Add static guards preventing `bd-local.sh` and auto topology publication drift in `tests/static/test_beads_worktree_ownership.sh`

---

## Phase 4: Verification, PR, and CI

- [x] T011 Run `bash tests/unit/test_worktree_ready.sh`
- [x] T012 Run `bash tests/static/test_beads_worktree_ownership.sh`
- [x] T013 Run `make codex-check`
- [x] T014 Commit and push branch `025-worktree-finish-unblock`
- [x] T015 Open a PR for `025-worktree-finish-unblock`
- [x] T016 Review GitHub Actions logs for the PR and fix failures until all checks are green

---

## Dependencies & Execution Order

- Specification tasks complete first.
- User Story 1 helper/test work precedes User Story 2 contract/static-guard work.
- Verification depends on both user stories being complete.
- PR opening and GitHub Actions triage happen only after local gates pass.

## Implementation Strategy

1. Finish the constrained Speckit package for the current branch.
2. Patch the helper and targeted tests for safe issue resolution, executable ordinary `finish`, and stale-topology handling.
3. Patch the command contract and static guards for plain `bd` and no auto publish.
4. Run local quality gates, then open the PR and drive Actions to green.
