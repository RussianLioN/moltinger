# Tasks: Beads Dolt-Native Migration

**Input**: Design documents from `/specs/029-beads-dolt-native-migration/`  
**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`

**Tests**: Tests are required for this feature because migration safety depends on deterministic readiness reports, pilot verification, and rollback validation.

**Organization**: Tasks are grouped by user story so each increment can be implemented and validated independently.

## Phase 0: Planning (Executor Assignment)

**Purpose**: Freeze migration boundaries, evidence sources, and stage gates before any implementation.

- [x] P001 Reconcile `specs/029-beads-dolt-native-migration/spec.md`, `plan.md`, and `tasks.md` against the current repo-local Beads surfaces and local `bd 0.49.6` command surface
- [x] P002 Re-review official upstream Beads docs and issue threads recorded in `specs/029-beads-dolt-native-migration/research.md`
- [x] P003 Confirm affected files and execution order from `specs/029-beads-dolt-native-migration/plan.md`
- [x] P004 Freeze migration boundaries for inventory, pilot, rollout, rollback, legacy RCA separation, and canonical-root cleanup in `specs/029-beads-dolt-native-migration/plan.md`
- [x] P005 Capture the initial legacy-surface inventory scope across wrappers, hooks, docs, skills, configs, tests, and bootstrap flows in `specs/029-beads-dolt-native-migration/research.md`
- [x] P006 Record readiness gate, pilot gate, and rollback package expectations from `specs/029-beads-dolt-native-migration/contracts/`

**Gate**: Do not start `T001+` until the target contract, legacy inventory scope, pilot gate, and rollback contract are all reflected in task ordering.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Prepare shared fixtures, docs surface, and script registration for migration work.

- [x] T001 Create migration fixture support for legacy JSONL-first, pilot-ready, blocked sibling, and bootstrap-variance states in `tests/lib/git_topology_fixture.sh`
- [x] T002 [P] Create migration operator doc scaffold in `docs/beads-dolt-native-migration.md`
- [x] T003 [P] Register planned migration scripts in `scripts/manifest.json`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared primitives that every migration stage depends on

**⚠️ CRITICAL**: No user story work should begin before these tasks are complete.

- [x] T004 [P] Implement reusable legacy-surface discovery helpers in `scripts/beads-dolt-migration-inventory.sh`
- [x] T005 [P] Implement deterministic readiness classification helpers and machine-readable report output in `scripts/beads-dolt-migration-inventory.sh`
- [x] T006 [P] Add reusable migration assertion helpers in `tests/lib/test_helpers.sh`
- [x] T007 Extend static expectations for docs/AGENTS/skills alignment under the target contract in `tests/static/test_beads_dolt_docs_alignment.sh`
- [x] T008 Add foundational unit coverage for backend/runtime detection, canonical-root coupling, and legacy-surface classification in `tests/unit/test_beads_dolt_inventory.sh`

**Checkpoint**: Inventory and readiness primitives exist and can support report-only, pilot, and rollout stages without hidden mixed mode.

---

## Phase 3: User Story 1 - Legacy Surfaces Are Inventoried Before Cutover (Priority: P1) 🎯 MVP

**Goal**: Produce a deterministic report of all repo-local legacy Beads surfaces and block cutover until critical blockers are resolved.

**Independent Test**: On an unchanged repository and on fixture repos, repeated inventory runs produce the same readiness verdict and classify wrappers, hooks, docs, configs, skills, tests, and tracked artifacts consistently.

### Tests for User Story 1

- [x] T009 [P] [US1] Add repeated-run determinism coverage for inventory/readiness reports in `tests/unit/test_beads_dolt_inventory.sh`
- [x] T010 [P] [US1] Add blocker classification coverage for wrappers, hooks, docs, configs, and bootstrap variance in `tests/unit/test_beads_dolt_inventory.sh`

### Implementation for User Story 1

- [x] T011 [US1] Implement the repo-local legacy-surface inventory runner in `scripts/beads-dolt-migration-inventory.sh`
- [x] T012 [US1] Emit deterministic readiness reports and blocker summaries from `scripts/beads-dolt-migration-inventory.sh`
- [x] T013 [US1] Document the inventory model and target contract summary in `docs/beads-dolt-native-migration.md` and `docs/rules/beads-dolt-native-contract.md`
- [x] T014 [US1] Capture the initial repository inventory baseline in `docs/migration/beads-dolt-native-cutover.md`

**Checkpoint**: The project can enumerate and classify migration blockers before any mutating cutover.

---

## Phase 4: User Story 2 - One Pilot Worktree Uses The New Beads Contract Safely (Priority: P2)

**Goal**: Prove the new Beads contract on one isolated worktree without silent fallback to legacy JSONL-first behavior.

**Independent Test**: A pilot worktree passes readiness checks, executes a representative issue lifecycle, blocks legacy-only surfaces explicitly, and exposes a usable replacement review surface.

### Tests for User Story 2

- [x] T015 [P] [US2] Add pilot pass/fail/blocked coverage in `tests/unit/test_beads_dolt_pilot.sh`
- [x] T016 [P] [US2] Add legacy-surface interception coverage for pilot mode in `tests/unit/test_beads_dolt_pilot.sh`

### Implementation for User Story 2

- [x] T017 [US2] Implement the isolated pilot workflow in `scripts/beads-dolt-pilot.sh`
- [x] T018 [US2] Adapt `bin/bd`, `scripts/beads-resolve-db.sh`, and `.githooks/pre-commit` so pilot mode can detect and block legacy-only surfaces explicitly
- [x] T019 [US2] Define and document the replacement operator/review surface in `docs/beads-dolt-native-migration.md`, `docs/CODEX-OPERATING-MODEL.md`, and `specs/029-beads-dolt-native-migration/contracts/review-surface-contract.md`
- [x] T020 [US2] Update pilot-facing operator guidance in `.beads/AGENTS.md`, `.claude/docs/beads-quickstart.md`, and `.claude/docs/beads-quickstart.en.md`

**Checkpoint**: One isolated worktree can demonstrate the target contract without silent return to the legacy model.

---

## Phase 5: User Story 3 - Remaining Worktrees Cut Over With Rollout And Rollback (Priority: P3)

**Goal**: Transition the remaining repo-local surfaces and worktrees to one Beads contract with a separate rollback package.

**Independent Test**: Starting from a successful pilot, rollout transitions only ready worktrees, blocked worktrees remain blocked, docs and skills converge on one workflow, and rollback restores operator usability without losing evidence.

### Tests for User Story 3

- [x] T021 [P] [US3] Add staged rollout and rollback coverage in `tests/unit/test_beads_dolt_rollout.sh`
- [x] T022 [P] [US3] Add blocked-worktree and no-mixed-mode coverage in `tests/unit/test_beads_dolt_rollout.sh`

### Implementation for User Story 3

- [x] T023 [US3] Implement staged report-only, cutover, verification, and rollback orchestration in `scripts/beads-dolt-rollout.sh`
- [x] T024 [US3] Align bootstrap and handoff flows with the active contract in `.envrc` and `scripts/worktree-ready.sh`
- [x] T025 [US3] Retire or demote legacy JSONL-first surfaces in `scripts/beads-normalize-issues-jsonl.sh`, `scripts/beads-worktree-localize.sh`, and related compatibility paths where the new contract requires it
- [x] T026 [US3] Update repo-local docs, skills, and rules to the final operator workflow in `AGENTS.md`, `.claude/skills/beads/resources/COMMANDS_QUICKREF.md`, `.claude/skills/beads/resources/WORKFLOWS.md`, `docs/WORKTREE-HOTFIX-PLAYBOOK.md`, and `docs/migration/beads-dolt-native-cutover.md`

**Checkpoint**: The repo can transition from pilot to full cutover without hidden mixed mode and with a separate rollback package.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final consistency, docs alignment, and focused validation.

- [x] T027 [P] Refresh migration references in `docs/beads-dolt-native-migration.md` and `specs/029-beads-dolt-native-migration/quickstart.md`
- [x] T028 Run focused validation and capture final inventory/pilot/rollout results in `specs/029-beads-dolt-native-migration/quickstart.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Can start after the Phase 0 planning gate closes
- **Foundational (Phase 2)**: Depends on Setup completion and blocks all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational completion
- **User Story 2 (Phase 4)**: Depends on Foundational completion and uses the readiness outputs from US1
- **User Story 3 (Phase 5)**: Depends on Foundational completion and should consume pilot results from US2
- **Polish (Phase 6)**: Depends on all desired user stories being complete

### User Story Dependencies

- **US1**: First deliverable and MVP
- **US2**: Can start after Foundational, but should use the inventory/readiness contract from US1
- **US3**: Should use inventory and pilot outputs from US1 and US2 before rollout

### Parallel Opportunities

- `T002` and `T003` can run in parallel once setup starts
- `T004`, `T005`, and `T006` can run in parallel in the foundational phase
- `T009` and `T010` can run in parallel for US1
- `T015` and `T016` can run in parallel for US2
- `T021` and `T022` can run in parallel for US3
- `T027` can run in parallel with `T028` during final polish

---

## Parallel Example: User Story 1

```bash
Task: "Add repeated-run determinism coverage for inventory/readiness reports in tests/unit/test_beads_dolt_inventory.sh"
Task: "Add blocker classification coverage for wrappers, hooks, docs, configs, and bootstrap variance in tests/unit/test_beads_dolt_inventory.sh"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 0 planning gate
2. Complete Phase 1: Setup
3. Complete Phase 2: Foundational
4. Complete Phase 3: User Story 1
5. Validate deterministic inventory/readiness before pilot

### Incremental Delivery

1. Ship report-only inventory and readiness first
2. Add isolated pilot cutover next
3. Add staged rollout and rollback last

### Rollout Discipline

1. Do not cut over remaining worktrees before the pilot passes
2. Do not leave legacy and target contracts both active as steady state
3. Keep rollback separate, explicit, and evidence-preserving
