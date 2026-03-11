# Tasks: Worktree Handoff Hardening

**Input**: Design documents from `/specs/011-worktree-handoff-hardening/`
**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories), `research.md`, `data-model.md`, `contracts/`

**Tests**: Regression coverage is required for this feature because the defect affects boundary safety and structured downstream handoff behavior.

**Organization**: Tasks are grouped by user story so each story can be implemented and validated independently.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no blocking dependency on incomplete work)
- **[Story]**: Which user story this task belongs to (`US1`, `US2`, `US3`, `US4`)
- Include exact file paths in descriptions

## Phase 0: Planning (Executor Assignment)

**Purpose**: Prepare the implementation pass without starting runtime work in this planning session.

- [x] P001 Analyze the implementation scope in `specs/011-worktree-handoff-hardening/spec.md` and `specs/011-worktree-handoff-hardening/plan.md`
- [x] P002 Identify whether implementation can stay within `.claude/commands/worktree.md`, `scripts/worktree-ready.sh`, `tests/unit/test_worktree_ready.sh`, and existing contract docs
- [x] P003 Assign execution order for contract, helper, and regression tasks in `specs/011-worktree-handoff-hardening/tasks.md`
- [x] P004 Confirm the required regression scenarios from `specs/011-worktree-handoff-hardening/quickstart.md` before editing runtime files

## Phase 1: Setup (Shared Preparation)

**Purpose**: Prepare fixtures and shared context for the implementation slice.

- [x] T001 Review current boundary and handoff touchpoints in `.claude/commands/worktree.md`, `scripts/worktree-ready.sh`, and `tests/unit/test_worktree_ready.sh`
- [x] T002 [P] Add representative mixed-request fixtures for create, attach, and structured Speckit startup prompts in `tests/unit/test_worktree_ready.sh`
- [x] T003 [P] Identify the current short-pending and rich-handoff output points in `scripts/worktree-ready.sh`

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Define the shared contract and failing regression signals before story-specific implementation.

**Critical**: No user story work should be considered complete until these tasks are done.

- [x] T004 Add failing create and attach boundary-regression expectations in `tests/unit/test_worktree_ready.sh`
- [x] T005 [P] Add failing structured-handoff preservation expectations for long Speckit startup prompts in `tests/unit/test_worktree_ready.sh`
- [x] T006 [P] Update `.claude/commands/worktree.md` to define one authoritative stop-after-Phase-A contract for create and attach flows
- [x] T007 Update `scripts/worktree-ready.sh` shared handoff rendering so manual helper output remains canonical, `pending_summary` stays concise, and `phase_b_seed_payload` is emitted as a separate richer deferred carrier

## Phase 3: User Story 1 - Enforce Stop After Phase A (Priority: P1)

**Goal**: Successful create and attach flows stop at handoff and do not continue downstream work in the originating session.

**Independent Test**: Submit mixed create and attach requests with downstream work and verify that the reply ends at handoff with no local Phase B continuation.

### Tests for User Story 1

- [x] T008 [P] [US1] Add create-flow stop-after-handoff regression assertions in `tests/unit/test_worktree_ready.sh`
- [x] T009 [P] [US1] Add attach-flow stop-after-handoff regression assertions in `tests/unit/test_worktree_ready.sh`

### Implementation for User Story 1

- [x] T010 [US1] Harden create-flow boundary instructions in `.claude/commands/worktree.md`
- [x] T011 [US1] Harden attach-flow boundary instructions in `.claude/commands/worktree.md` so attach stops at the same Phase A boundary as create
- [x] T012 [US1] Update create and attach handoff-state output in `scripts/worktree-ready.sh`
- [x] T013 [US1] Reconcile boundary-oriented helper assertions in `tests/unit/test_worktree_ready.sh`

## Phase 4: User Story 2 - Preserve Rich Manual Handoff Intent (Priority: P1)

**Goal**: Manual handoff keeps a concise pending summary while preserving rich downstream intent for complex requests.

**Independent Test**: Submit a structured Speckit startup request and verify that the handoff preserves exact downstream constraints without collapsing everything into one sentence.

### Tests for User Story 2

- [x] T014 [P] [US2] Add structured downstream-request fixtures with feature descriptions, defaults, boundaries, and stop conditions in `tests/unit/test_worktree_ready.sh`
- [x] T015 [P] [US2] Add rich-handoff preservation assertions in `tests/unit/test_worktree_ready.sh`

### Implementation for User Story 2

- [x] T016 [US2] Update `scripts/worktree-ready.sh` to preserve concise `pending_summary` plus a separate `phase_b_seed_payload` for complex requests without weakening the stop-after-handoff boundary
- [x] T017 [US2] Update `.claude/commands/worktree.md` so the richer downstream payload is relayed only as deferred Phase B context
- [x] T018 [US2] Reconcile structured-intent expectations in `tests/unit/test_worktree_ready.sh`

## Phase 5: User Story 3 - Align Helper Output And Workflow Contract (Priority: P2)

**Goal**: Helper output, command instructions, and documented contracts describe the same boundary and handoff semantics.

**Independent Test**: Compare the helper output and the command guidance for the same successful flow and verify that boundary, handoff mode, and payload roles match.

### Tests for User Story 3

- [x] T019 [P] [US3] Add helper-versus-instruction alignment assertions in `tests/unit/test_worktree_ready.sh`

### Implementation for User Story 3

- [x] T020 [US3] Align `pending_summary` and `phase_b_seed_payload` terminology in `.claude/commands/worktree.md` and `scripts/worktree-ready.sh`
- [x] T021 [US3] Update `specs/005-worktree-ready-flow/contracts/worktree-command-interface.md` with the hardened create/attach boundary, canonical manual helper output, and dual-payload semantics
- [x] T022 [US3] Update `specs/005-worktree-ready-flow/contracts/worktree-handoff-schema.md` to document the relationship between `pending`, `phase_b_seed_payload`, and the human-facing deferred payload block

## Phase 6: User Story 4 - Guard Against Regression For Complex Prompts (Priority: P2)

**Goal**: Regression coverage detects future boundary leakage or downstream-intent loss for realistic mixed requests.

**Independent Test**: Run the regression suite against create and attach flows with long structured downstream prompts and confirm that the suite fails on boundary or payload drift.

### Tests for User Story 4

- [x] T023 [P] [US4] Add long-prompt create-flow regression scenarios in `tests/unit/test_worktree_ready.sh`
- [x] T024 [P] [US4] Add long-prompt attach-flow regression scenarios in `tests/unit/test_worktree_ready.sh`
- [x] T025 [P] [US4] Add automatic-launch success and fallback boundary scenarios in `tests/unit/test_worktree_ready.sh`

### Implementation for User Story 4

- [x] T026 [US4] Update `specs/005-worktree-ready-flow/quickstart.md` with structured-handoff, attach-boundary, and launch-fallback expectations
- [x] T027 [US4] Record implementation validation results in `specs/005-worktree-ready-flow/validation.md`, including concise `pending` plus richer `phase_b_seed_payload` coverage

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Final reconciliation across operator guidance and validation artifacts.

- [x] T028 [P] Refresh manual operator guidance in `docs/WORKTREE-HOTFIX-PLAYBOOK.md` if the handoff contract or troubleshooting steps changed
- [x] T029 Run `tests/unit/test_worktree_ready.sh` and reconcile final validation evidence in `specs/011-worktree-handoff-hardening/quickstart.md`

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1: Setup** has no prerequisites.
- **Phase 2: Foundational** depends on Phase 1 and blocks all story work.
- **Phase 3: User Story 1** and **Phase 4: User Story 2** depend on Phase 2.
- **Phase 5: User Story 3** depends on the boundary and payload behavior established in Phases 3 and 4.
- **Phase 6: User Story 4** depends on the implemented boundary and payload contract from Phases 3 through 5.
- **Phase 7: Polish** depends on the desired user stories being complete.

### User Story Dependencies

- **User Story 1 (P1)** can begin as soon as Foundational work is complete.
- **User Story 2 (P1)** can begin as soon as Foundational work is complete.
- **User Story 3 (P2)** depends on the implemented concepts from User Stories 1 and 2.
- **User Story 4 (P2)** depends on the implemented contract from User Stories 1 through 3.

### Parallel Opportunities

- `T002` and `T003` can run in parallel once setup starts.
- `T004`, `T005`, and `T006` can run in parallel during the foundational phase.
- `T008` and `T009` can run in parallel for create and attach boundary tests.
- `T014` and `T015` can run in parallel for structured handoff fixtures and assertions.
- `T023`, `T024`, and `T025` can run in parallel when expanding regression coverage.

## Parallel Example: User Story 2

```bash
Task: "Add structured downstream-request fixtures with feature descriptions, defaults, boundaries, and stop conditions in tests/unit/test_worktree_ready.sh"
Task: "Add rich-handoff preservation assertions in tests/unit/test_worktree_ready.sh"
```

## Implementation Strategy

### MVP First

1. Complete Phase 1: Setup.
2. Complete Phase 2: Foundational.
3. Complete Phase 3: User Story 1.
4. Complete Phase 4: User Story 2.
5. Stop and validate the hardened boundary plus rich handoff contract before alignment and polish work.

### Incremental Delivery

1. Land the strict boundary first.
2. Add rich manual handoff preservation.
3. Align helper output and documented contracts.
4. Expand regression coverage for long structured prompts and launch fallback behavior.
