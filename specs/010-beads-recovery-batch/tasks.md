# Tasks: Safe Batch Recovery of Leaked Beads Issues

**Input**: Design documents from `/specs/010-beads-recovery-batch/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅, quickstart.md ✅

**Tests**: Shell-based validation is required for this feature because ownership recovery must remain deterministic and fail closed.

**Organization**: Tasks are grouped by user story so audit, apply, and evidence/reporting can be implemented and validated independently.

## Phase 0: Planning (Executor Assignment) ✅ COMPLETE

- [x] P001 [EXECUTOR: MAIN] [SEQUENTIAL] Freeze v1 scope around `audit` plus safe `apply` in `specs/010-beads-recovery-batch/spec.md` and `plan.md`
- [x] P002 [EXECUTOR: MAIN] [SEQUENTIAL] Reuse existing recovery/localization primitives and record that decision in `specs/010-beads-recovery-batch/research.md`
- [x] P003 [EXECUTOR: MAIN] [SEQUENTIAL] Define plan, journal, and ownership override contracts in `specs/010-beads-recovery-batch/data-model.md` and `contracts/recovery-batch-cli.md`
- [x] P004 [EXECUTOR: MAIN] [SEQUENTIAL] Break implementation into atomic phases in `specs/010-beads-recovery-batch/tasks.md`

**Executor Summary**:

- Existing repo tooling is sufficient; no new agent definitions are required.
- Use `worker` semantics for non-trivial shell/test implementation and `MAIN` for spec/docs reconciliation and final verification.
- Same-file ownership wins over nominal parallelism; tasks touching the same shell script remain sequential.

---

## Phase 1: Setup (Shared Infrastructure)

- [x] T001 [EXECUTOR: worker] [SEQUENTIAL] Create committed ownership override seed file in `docs/beads-recovery-ownership.json`
- [x] T002 [EXECUTOR: worker] [SEQUENTIAL] Create owner batch script skeleton with CLI parsing and shell safety in `scripts/beads-recovery-batch.sh`
- [x] T003 [P] [EXECUTOR: worker] [PARALLEL-GROUP-SETUP] Add script inventory metadata for the batch recovery tool in `scripts/manifest.json`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Build the shared audit/apply plumbing before any user story can be completed.

- [x] T004 [EXECUTOR: worker] [SEQUENTIAL] Implement live topology fingerprinting, canonical root discovery, and ownership override loading in `scripts/beads-recovery-batch.sh`
- [x] T005 [EXECUTOR: worker] [SEQUENTIAL] Implement deterministic JSON plan rendering in `scripts/beads-recovery-batch.sh`
- [x] T006 [EXECUTOR: worker] [SEQUENTIAL] Implement stale-plan validation, journal path creation, and per-worktree backup helpers in `scripts/beads-recovery-batch.sh`
- [x] T007 [P] [EXECUTOR: worker] [PARALLEL-GROUP-FOUNDATION] Add unit fixture support for batch recovery scenarios in `tests/unit/test_beads_recovery_batch.sh`

**Checkpoint**: The feature can discover topology, render a plan, and prepare safe apply scaffolding without mutating canonical root state.

---

## Phase 3: User Story 1 - Audit Recovery Candidates Before Any Write (Priority: P1) 🎯 MVP

**Goal**: Operators can generate a deterministic recovery plan that separates safe candidates from blocked ones.

**Independent Test**: Run `scripts/beads-recovery-batch.sh audit` against fixture repos with mixed topology and confirm it emits one plan file, marks ambiguous ownership as blocked, and performs no tracker writes.

- [x] T008 [US1] [EXECUTOR: worker] [SEQUENTIAL] Implement audit candidate discovery from canonical root JSONL in `scripts/beads-recovery-batch.sh`
- [x] T009 [US1] [EXECUTOR: worker] [SEQUENTIAL] Implement owner resolution using live worktree topology plus `docs/beads-recovery-ownership.json` overrides in `scripts/beads-recovery-batch.sh`
- [x] T010 [US1] [EXECUTOR: worker] [SEQUENTIAL] Mark redirected, duplicate, ambiguous, and missing-worktree cases as blocked or localized-needed in `scripts/beads-recovery-batch.sh`
- [x] T011 [US1] [EXECUTOR: worker] [SEQUENTIAL] Add audit-mode unit coverage in `tests/unit/test_beads_recovery_batch.sh`

**Checkpoint**: Audit mode can produce a trustworthy plan without changing tracker state.

---

## Phase 4: User Story 2 - Apply Only High-Confidence Recoveries Safely (Priority: P2)

**Goal**: Operators can apply only the safe items from a previously generated plan.

**Independent Test**: Run `scripts/beads-recovery-batch.sh apply --plan ...` and confirm it localizes safe redirected worktrees, recovers only high-confidence items, and leaves blocked cases untouched.

- [x] T012 [US2] [EXECUTOR: worker] [SEQUENTIAL] Implement apply-mode plan loading and stale-topology refusal in `scripts/beads-recovery-batch.sh`
- [x] T013 [US2] [EXECUTOR: worker] [SEQUENTIAL] Integrate `scripts/beads-worktree-localize.sh` and `scripts/beads-recover-issue.sh` into safe apply execution in `scripts/beads-recovery-batch.sh`
- [x] T014 [US2] [EXECUTOR: worker] [SEQUENTIAL] Implement per-worktree backup capture and per-issue result recording in `scripts/beads-recovery-batch.sh`
- [x] T015 [US2] [EXECUTOR: worker] [SEQUENTIAL] Add apply-mode unit coverage for safe, duplicate, redirected, and stale-plan cases in `tests/unit/test_beads_recovery_batch.sh`

**Checkpoint**: Apply mode recovers only explicitly safe issues from an approved plan and never rewrites canonical root state.

---

## Phase 5: User Story 3 - Leave Reviewable Evidence and Cleanup Guidance (Priority: P3)

**Goal**: Every run leaves a clear journal, backups, and explicit “cleanup still blocked” guidance when unresolved items remain.

**Independent Test**: Inspect the emitted journal and backups after audit and apply runs and verify a maintainer can reconstruct the exact actions and blockers without reading raw tracker diffs first.

- [x] T016 [US3] [EXECUTOR: worker] [SEQUENTIAL] Implement JSON journal output and human summary rendering in `scripts/beads-recovery-batch.sh`
- [x] T017 [US3] [EXECUTOR: worker] [SEQUENTIAL] Document the new ownership override and batch recovery workflow in `docs/CODEX-OPERATING-MODEL.md` and `specs/010-beads-recovery-batch/quickstart.md`
- [x] T018 [US3] [EXECUTOR: worker] [SEQUENTIAL] Add guardrail coverage for ownership override presence and fail-closed behavior in `tests/static/test_beads_worktree_ownership.sh` and `tests/unit/test_beads_recovery_batch.sh`

**Checkpoint**: Operators get durable evidence and explicit cleanup boundaries after every run.

---

## Final Phase: Polish & Cross-Cutting Concerns

- [x] T019 [EXECUTOR: MAIN] [SEQUENTIAL] Reconcile checkbox state and artifact links in `specs/010-beads-recovery-batch/tasks.md`
- [x] T020 [EXECUTOR: MAIN] [SEQUENTIAL] Run quality gates for the feature using `bash -n scripts/beads-recovery-batch.sh`, `tests/unit/test_beads_recover_issue.sh`, `tests/unit/test_beads_recovery_batch.sh`, `tests/static/test_beads_worktree_ownership.sh`, `scripts/scripts-verify.sh`, and `make codex-check`
- [x] T021 [EXECUTOR: MAIN] [SEQUENTIAL] Refresh topology documentation after the new feature branch mutation via `scripts/git-topology-registry.sh refresh --write-doc`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1**: starts immediately
- **Phase 2**: depends on Phase 1
- **Phase 3**: depends on Phase 2 and delivers the MVP
- **Phase 4**: depends on Phase 3
- **Phase 5**: depends on Phase 4
- **Final Phase**: depends on all desired user stories

### User Story Dependencies

- **US1 (P1)**: no dependency on later stories; it delivers the first useful review boundary
- **US2 (P2)**: depends on the audit plan from US1
- **US3 (P3)**: depends on audit/apply outcomes from earlier stories

### Parallel Opportunities

- T003 can run in parallel with T002 after the script name is fixed
- T007 can start once the script contract is stable enough for fixture design
- Static guardrail updates can be prepared while final journal/docs work lands, but same-file edits remain sequential

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Setup
2. Complete Foundational plan and topology helpers
3. Deliver audit mode and audit tests
4. Validate that no tracker files are mutated

### Incremental Delivery

1. Add safe apply on top of audited plans
2. Add journals, docs, and explicit cleanup guidance
3. Finish with full validation and topology/doc refresh
