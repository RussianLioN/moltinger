# Tasks: Deterministic Beads Issues JSONL Ownership

**Input**: Design documents from `/specs/028-beads-issues-jsonl-rca/`  
**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`

**Tests**: Tests are required for this feature because the specification explicitly demands reproducible RCA, guardrails against nondeterministic rewrites, and rollout/rollback verification.

**Organization**: Tasks are grouped by user story so each increment can be implemented and validated independently.

## Phase 0: Planning (Executor Assignment)

**Purpose**: Prepare the implementation order, execution lanes, and research boundaries before code changes.

- [ ] P001 Reconcile `specs/028-beads-issues-jsonl-rca/spec.md`, `specs/028-beads-issues-jsonl-rca/plan.md`, and `specs/028-beads-issues-jsonl-rca/tasks.md` against current Beads ownership code paths
- [ ] P002 Review baseline incident evidence in `SESSION_SUMMARY.md` and planned RCA output in `specs/028-beads-issues-jsonl-rca/contracts/rca-evidence-contract.md`
- [ ] P003 Confirm affected implementation surfaces from `specs/028-beads-issues-jsonl-rca/plan.md` and annotate final execution order in `specs/028-beads-issues-jsonl-rca/tasks.md`
- [ ] P004 Freeze scope boundaries for routine sync, migration, rollout, rollback, and canonical-root cleanup in `specs/028-beads-issues-jsonl-rca/plan.md`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Prepare shared fixtures, docs surface, and manifest plumbing for the implementation.

- [ ] T001 Create multi-worktree JSONL drift fixture support in `tests/lib/git_topology_fixture.sh`
- [ ] T002 [P] Create deterministic sync-model operator doc scaffold in `docs/beads-issues-jsonl-sync-model.md`
- [ ] T003 [P] Register planned RCA and migration scripts in `scripts/manifest.json`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared primitives that all user stories depend on

**⚠️ CRITICAL**: No user story work should begin before these tasks are complete.

- [ ] T004 [P] Implement shared sync-authority decision primitives for tracked JSONL rewrites in `scripts/beads-resolve-db.sh`
- [ ] T005 [P] Implement shared semantic-vs-noise hashing and canonicalization helpers in `scripts/beads-normalize-issues-jsonl.sh`
- [ ] T006 [P] Add reusable JSONL rewrite assertion helpers in `tests/lib/test_helpers.sh`
- [ ] T007 Extend static ownership guard expectations for JSONL sync invariants in `tests/static/test_beads_worktree_ownership.sh`
- [ ] T008 Add foundational unit coverage for new authority decision codes in `tests/unit/test_bd_dispatch.sh`

**Checkpoint**: Shared ownership/sync primitives exist and can support guarded daily sync, RCA evidence, and migration logic.

---

## Phase 3: User Story 1 - Daily Sync Uses One Deterministic Owner (Priority: P1) 🎯 MVP

**Goal**: Ensure mutating Beads sync either rewrites only the owned worktree JSONL or blocks before any ambiguous/cross-worktree mutation.

**Independent Test**: On a fixture with canonical root and sibling worktrees, mutating sync from one dedicated worktree only touches its owned `.beads/issues.jsonl`; safe reruns are byte-stable; ambiguous/root-leak attempts are blocked before write.

### Tests for User Story 1

- [ ] T009 [P] [US1] Add safe semantic sync and byte-stable rerun coverage in `tests/unit/test_beads_issues_jsonl_sync.sh`
- [ ] T010 [P] [US1] Add root-leak and sibling-rewrite block coverage in `tests/unit/test_beads_issues_jsonl_sync.sh`

### Implementation for User Story 1

- [ ] T011 [US1] Wire mutating Beads sync authority checks into `bin/bd` and `scripts/beads-resolve-db.sh`
- [ ] T012 [US1] Implement deterministic canonical rewrite and noise-only no-op handling in `scripts/beads-normalize-issues-jsonl.sh`
- [ ] T013 [US1] Route tracked git-hook mutation surfaces through the new authority/noise checks in `.githooks/pre-commit` and `.githooks/pre-push`
- [ ] T014 [US1] Update the daily sync operator contract in `docs/CODEX-OPERATING-MODEL.md`, `.claude/docs/beads-quickstart.md`, and `.claude/docs/beads-quickstart.en.md`

**Checkpoint**: Daily sync is deterministic for covered safe cases and fail-closed for covered unsafe cases.

---

## Phase 4: User Story 2 - RCA Reproduces Drift With Reviewable Evidence (Priority: P2)

**Goal**: Provide a reproducible RCA flow with machine-readable logs and stable verdicts for leakage, noise-only rewrites, and ambiguity.

**Independent Test**: Running the same RCA fixture twice produces the same decision codes and verdict class while leaving non-approved tracked state untouched.

### Tests for User Story 2

- [ ] T015 [P] [US2] Add RCA regression scenarios for leakage, noise-only rewrite, and ambiguous ownership in `tests/unit/test_beads_issues_jsonl_rca.sh`

### Implementation for User Story 2

- [ ] T016 [US2] Implement the reproducible RCA and evidence runner in `scripts/beads-issues-jsonl-rca.sh`
- [ ] T017 [US2] Emit stable machine-readable evidence fields from `scripts/beads-issues-jsonl-rca.sh` and `scripts/beads-resolve-db.sh`
- [ ] T018 [US2] Write the durable RCA incident record in `docs/rca/2026-03-xx-beads-issues-jsonl-drift-ownership-gap.md`
- [ ] T019 [US2] Publish the deterministic sync-authority rule and RCA usage guidance in `docs/rules/beads-issues-jsonl-deterministic-sync-authority.md`, `docs/WORKTREE-HOTFIX-PLAYBOOK.md`, and `docs/beads-issues-jsonl-sync-model.md`

**Checkpoint**: RCA output is reproducible, reviewable, and clearly distinguishes leakage, noise, and ambiguity.

---

## Phase 5: User Story 3 - Existing Worktrees Migrate Safely With Rollout And Rollback (Priority: P3)

**Goal**: Provide audit-first migration, staged rollout, and explicit rollback for existing worktrees without losing issues or silently folding in canonical-root cleanup.

**Independent Test**: On fixtures covering current, legacy, duplicate, and ambiguous worktrees, audit builds a deterministic plan, apply snapshots before safe changes, verify reports unresolved blockers, and rollback preserves evidence.

### Tests for User Story 3

- [ ] T020 [P] [US3] Add audit/apply/verify/rollback coverage for current, legacy, duplicate, and ambiguous cases in `tests/unit/test_beads_sync_migration.sh`

### Implementation for User Story 3

- [ ] T021 [US3] Implement audit/apply/verify/rollback workflow with staged rollout modes, snapshots, and candidate classification in `scripts/beads-sync-migration.sh`
- [ ] T022 [US3] Integrate migration boundaries with existing ownership audit and recovery flows in `scripts/beads-worktree-audit.sh` and `scripts/beads-recovery-batch.sh`
- [ ] T023 [US3] Document staged rollout and explicit rollback in `docs/beads-issues-jsonl-sync-model.md` and `docs/CODEX-OPERATING-MODEL.md`
- [ ] T024 [US3] Update operator validation and rollback steps in `specs/028-beads-issues-jsonl-rca/quickstart.md`

**Checkpoint**: Existing worktrees can be classified and upgraded safely, and rollback remains explicit and evidence-preserving.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final consistency, docs alignment, and focused validation.

- [ ] T025 [P] Refresh Beads workflow references in `.claude/skills/beads/resources/WORKFLOWS.md` and `.claude/skills/beads/resources/COMMANDS_QUICKREF.md`
- [ ] T026 Run focused validation and capture final results in `specs/028-beads-issues-jsonl-rca/quickstart.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion and blocks all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational completion
- **User Story 2 (Phase 4)**: Depends on Foundational completion and benefits from User Story 1 decision codes
- **User Story 3 (Phase 5)**: Depends on Foundational completion and should consume the guardrails/evidence established in User Stories 1 and 2
- **Polish (Phase 6)**: Depends on all desired user stories being complete

### User Story Dependencies

- **US1**: First deliverable and MVP
- **US2**: Can start after Foundational, but its evidence format should reuse US1 authority codes
- **US3**: Should reuse authority and evidence outputs from US1 and US2 for safe migration and rollback

### Parallel Opportunities

- `T002` and `T003` can run in parallel after setup starts
- `T004`, `T005`, and `T006` can run in parallel in the foundational phase
- `T009` and `T010` can run in parallel for US1
- `T015` can run while US1 implementation is landing, once foundational decision codes are stable
- `T020` can start after RCA and migration contracts are fixed, in parallel with US3 docs work
- `T025` can run in parallel with `T026` during final polish

---

## Parallel Example: User Story 1

```bash
Task: "Add safe semantic sync and byte-stable rerun coverage in tests/unit/test_beads_issues_jsonl_sync.sh"
Task: "Add root-leak and sibling-rewrite block coverage in tests/unit/test_beads_issues_jsonl_sync.sh"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational
3. Complete Phase 3: User Story 1
4. Validate deterministic daily sync before expanding scope

### Incremental Delivery

1. Ship deterministic daily sync guardrails first
2. Add reproducible RCA/evidence next
3. Add migration, rollout, and rollback last

### Rollout Discipline

1. Do not mix migration apply with canonical-root cleanup
2. Do not enable hard enforcement before report-only evidence is reviewable
3. Keep rollback evidence-preserving and operator-readable
