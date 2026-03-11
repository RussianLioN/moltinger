# Tasks: UX-Safe Beads Local Ownership

**Input**: Design documents from `/specs/016-beads-local-db-ux/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅, quickstart.md ✅

**Tests**: Mandatory. This feature requires unit coverage, static guardrails, and quickstart validation because the spec explicitly makes docs, tests, and guardrails part of the acceptance contract.

**Organization**: Tasks are grouped by user story so local ownership safety, compatibility migration, and root-cleanup separation can be implemented and validated independently.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel when file ownership does not overlap
- **[Story]**: Which user story this task belongs to (`[US1]`, `[US2]`, `[US3]`)
- Every task includes an exact file path

---

## Phase 0: Planning (Executor Assignment) ✅ COMPLETE

**Purpose**: Lock the implementation surface before any runtime edits.

- [x] P001 Analyze current plain-`bd`, `direnv`, worktree, and Beads ownership behavior for `specs/016-beads-local-db-ux/spec.md`
- [x] P002 Record design decisions in `specs/016-beads-local-db-ux/research.md`
- [x] P003 Define dispatch, bootstrap, and migration boundaries in `specs/016-beads-local-db-ux/contracts/bd-dispatch-contract.md`, `specs/016-beads-local-db-ux/contracts/session-bootstrap-contract.md`, and `specs/016-beads-local-db-ux/contracts/ownership-migration-boundary.md`
- [x] P004 Break implementation into ordered phases in `specs/016-beads-local-db-ux/tasks.md`

**Executor Summary**:

- Existing repo tooling is sufficient; no new agent definitions are required for planning.
- Runtime shell changes should stay concentrated in `bin/`, `scripts/`, `.envrc`, and the high-traffic Beads/worktree docs.
- Validation must cover both dispatch behavior and documentation drift.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the implementation surfaces and validation artifacts used by every story.

- [x] T001 Create repo-local plain-`bd` shim entrypoint in `bin/bd`
- [x] T002 Create ownership-resolution helper in `scripts/beads-resolve-db.sh`
- [x] T003 [P] Create compatibility/localization helper in `scripts/beads-worktree-localize.sh`
- [x] T004 [P] Create validation log for implementation evidence in `specs/016-beads-local-db-ux/validation.md`
- [x] T005 [P] Create test scaffolding for dispatch and static ownership guardrails in `tests/unit/test_bd_dispatch.sh` and `tests/static/test_beads_worktree_ownership.sh`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Build the shared ownership-resolution and session-bootstrap layer required by all stories.

**⚠️ CRITICAL**: No user story work should begin until this phase is complete.

- [x] T006 Implement worktree-local ownership contract validation in `scripts/beads-resolve-db.sh`
- [x] T007 Implement explicit local DB dispatch via `bd --db <worktree-local-db>` in `bin/bd`
- [x] T008 Implement fail-closed blocked states and actionable error messages in `scripts/beads-resolve-db.sh` and `bin/bd`
- [x] T009 Wire repo-local plain-`bd` bootstrap into `.envrc`
- [x] T010 Wire repo-local plain-`bd` bootstrap into `scripts/codex-profile-launch.sh` and `scripts/worktree-ready.sh`
- [x] T011 Register new script surfaces and integrity metadata in `scripts/manifest.json` and `scripts/codex-check.sh`

**Checkpoint**: Plain `bd` can be safely routed to the current worktree’s local DB or blocked before mutation, and managed sessions know how to bootstrap that path.

---

## Phase 3: User Story 1 - Plain `bd` Works Safely In A Dedicated Worktree (Priority: P1) 🎯 MVP

**Goal**: Users and agents in a dedicated worktree can run ordinary `bd` without choosing a wrapper, while unsafe sessions fail closed instead of writing to the canonical root tracker.

**Independent Test**: Validate that plain `bd` in a bootstrapped dedicated worktree uses `.beads/beads.db`, and that an unbootstrapped or root-fallback path blocks before any mutating command writes.

### Tests for User Story 1

- [x] T012 [P] [US1] Add unit coverage for local execution, blocked root fallback, blocked missing foundation, and blocked unbootstrapped sessions in `tests/unit/test_bd_dispatch.sh`
- [x] T013 [P] [US1] Add static guardrails for repo-local plain-`bd` bootstrap in `.envrc`, `scripts/codex-profile-launch.sh`, and `scripts/worktree-ready.sh` via `tests/static/test_beads_worktree_ownership.sh`

### Implementation for User Story 1

- [x] T014 [US1] Implement bootstrap-aware plain-`bd` session detection in `scripts/beads-resolve-db.sh` and `bin/bd`
- [x] T015 [US1] Update Beads quickstart guidance to document plain `bd` as the only default repo-local command in `.claude/docs/beads-quickstart.md` and `.claude/docs/beads-quickstart.en.md`
- [x] T016 [US1] Update Beads workflow guidance so agent-facing entrypoints assume safe plain `bd` instead of wrapper choice in `.claude/skills/beads/SKILL.md`, `.claude/skills/beads/resources/COMMANDS_QUICKREF.md`, and `.claude/skills/beads/resources/WORKFLOWS.md`

**Checkpoint**: Daily repo-local Beads usage is documented and enforced as plain `bd`, with fail-closed behavior when the session is unsafe.

---

## Phase 4: User Story 2 - Existing Worktrees Migrate Without Wrapper Lore (Priority: P1)

**Goal**: Existing worktrees with legacy or partial ownership state can be localized through one managed path instead of requiring manual wrapper knowledge or redirect archaeology.

**Independent Test**: Validate migratable legacy, partial-foundation, and damaged-blocked worktrees; safe states localize in place, unsafe states block with one exact recovery path, and no flow revives shared redirect ownership.

### Tests for User Story 2

- [x] T017 [P] [US2] Add unit coverage for legacy redirect, partial foundation, in-place localization, and blocked damaged states in `tests/unit/test_bd_dispatch.sh`
- [x] T018 [P] [US2] Extend worktree regression coverage for compatibility handoff and no raw `bd worktree create` fallback in `tests/unit/test_worktree_ready.sh`

### Implementation for User Story 2

- [x] T019 [US2] Implement managed localization behavior for legacy and partial worktrees in `scripts/beads-worktree-localize.sh`
- [x] T020 [US2] Integrate compatibility-state detection and migration routing into `scripts/beads-resolve-db.sh` and `bin/bd`
- [x] T021 [US2] Update managed worktree and Beads command guidance to route compatibility recovery through the new localization flow in `.claude/commands/worktree.md`, `.claude/commands/beads-init.md`, and `.claude/commands/speckit.tobeads.md`

**Checkpoint**: Existing worktrees can be localized in place or blocked safely, and users no longer need wrapper lore to recover them.

---

## Phase 5: User Story 3 - Root Cleanup Stays Separate From Ownership Safety (Priority: P2)

**Goal**: The fix preserves clear boundaries between dedicated-worktree ownership safety and any residual cleanup still needed in the canonical root.

**Independent Test**: Validate that local ownership works even when root cleanup residue exists, that root residue is reported separately, and that docs/tests never imply the feature repaired root `main`.

### Tests for User Story 3

- [x] T022 [P] [US3] Add static guardrails that forbid wrapper-choice UX drift, raw `bd worktree create` advice, and root-cleanup conflation in `tests/static/test_beads_worktree_ownership.sh`
- [x] T023 [P] [US3] Add quickstart validation scenarios for root-cleanup separation in `specs/016-beads-local-db-ux/quickstart.md` and `specs/016-beads-local-db-ux/validation.md`

### Implementation for User Story 3

- [x] T024 [US3] Implement separate root-cleanup notices without auto-repair in `scripts/beads-resolve-db.sh` and `scripts/worktree-ready.sh`
- [x] T025 [US3] Update repo-wide operator guidance to distinguish ownership migration from residual root cleanup in `AGENTS.md`, `docs/CODEX-OPERATING-MODEL.md`, and `docs/WORKTREE-HOTFIX-PLAYBOOK.md`

**Checkpoint**: Ownership-safe daily work and compatibility migration no longer imply or depend on manual root cleanup.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Reconcile high-traffic docs, complete validation, and ensure the feature package tells one coherent story.

- [x] T026 [P] Update remaining Beads references to the safe plain-`bd` contract in `.claude/commands/speckit.tobeads.md`, `.claude/commands/beads-init.md`, and `.claude/skills/beads/resources/SPECKIT_BRIDGE.md`
- [x] T027 [P] Run targeted validation from `specs/016-beads-local-db-ux/quickstart.md` and record results in `specs/016-beads-local-db-ux/validation.md`
- [x] T028 Reconcile checkbox state and artifact references in `specs/016-beads-local-db-ux/tasks.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies
- **Phase 2 (Foundational)**: Depends on Phase 1 and blocks all user stories
- **Phase 3 (US1)**: Depends on Phase 2 and is the MVP
- **Phase 4 (US2)**: Depends on Phase 2 and can begin after or alongside late US1 doc work if file ownership stays separate
- **Phase 5 (US3)**: Depends on Phase 2 and on the migration vocabulary introduced by US2
- **Phase 6 (Polish)**: Depends on all desired story work being complete

### User Story Dependencies

- **US1** depends on the foundational dispatch and bootstrap layer
- **US2** depends on the same foundational dispatch layer plus migration helper creation
- **US3** depends on the ownership and migration vocabulary already being in place so the cleanup boundary can be enforced consistently

### Parallel Opportunities

- T003, T004, and T005 can proceed in parallel after the feature package is locked
- T009 and T010 can proceed in parallel once the dispatch contract is stable
- Test tasks marked `[P]` can run in parallel when they do not claim the same file
- Documentation tasks may run in parallel only when file ownership does not overlap

---

## Parallel Example: Foundational Phase

```bash
Task: "Wire repo-local plain-bd bootstrap into .envrc"
Task: "Wire repo-local plain-bd bootstrap into scripts/codex-profile-launch.sh and scripts/worktree-ready.sh"
```

---

## Implementation Strategy

### MVP First

1. Complete Phase 1 (Setup)
2. Complete Phase 2 (Foundational)
3. Complete Phase 3 (US1)
4. Validate the bootstrapped, unbootstrapped, and blocked-root-fallback quickstart scenarios

### Incremental Delivery

1. Land the safe plain-`bd` dispatch contract first
2. Add compatibility migration for existing worktrees
3. Add cleanup-boundary reporting and finish doc alignment
4. Re-run targeted validation after each increment
