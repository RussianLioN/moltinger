# Tasks: Worktree Ready UX

**Input**: Design documents from `/specs/005-worktree-ready-flow/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅, quickstart.md ✅

**Tests**: Manual workflow validation from `specs/005-worktree-ready-flow/quickstart.md` (no automated tests explicitly requested in the specification)

**Organization**: Tasks are grouped by user story to preserve independent implementation and validation.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no unmet dependencies)
- **[Story]**: Which user story the task belongs to (`[US1]`-`[US4]`)
- Every task includes an exact file path

---

## Phase 0: Planning (Executor Assignment) ✅ COMPLETE

**Purpose**: Lock the implementation surface and ensure the feature package is ready for execution.

- [x] P001 [EXECUTOR: MAIN] [SEQUENTIAL] Analyze the implementation surface across `.claude/commands/worktree.md`, `scripts/git-session-guard.sh`, and `specs/005-worktree-ready-flow/plan.md`
- [x] P002 [EXECUTOR: MAIN] [SEQUENTIAL] Record library and workflow decisions in `specs/005-worktree-ready-flow/research.md`
- [x] P003 [EXECUTOR: MAIN] [SEQUENTIAL] Define the UX and readiness contracts in `specs/005-worktree-ready-flow/contracts/worktree-command-interface.md` and `specs/005-worktree-ready-flow/contracts/worktree-readiness-schema.md`
- [x] P004 [EXECUTOR: MAIN] [SEQUENTIAL] Break the feature into implementation phases in `specs/005-worktree-ready-flow/tasks.md`

**Executor Summary**:

- Existing agent inventory is sufficient; no new agent definitions are required for this feature.
- Use `worker` for non-trivial implementation and command-artifact edits.
- Use `MAIN` only for trivial documentation/validation bookkeeping and final verification.
- Override earlier `[P]` assumptions whenever tasks target the same file; file ownership wins over nominal parallelism.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the helper entrypoint and validation artifacts used by all stories.

- [x] T001 [EXECUTOR: worker] [SEQUENTIAL] Create `scripts/worktree-ready.sh` with CLI usage, mode dispatch, and shell safety guards → Artifacts: [worktree-ready.sh](../../scripts/worktree-ready.sh)
- [x] T002 [EXECUTOR: MAIN] [PARALLEL-GROUP-SETUP] Create `specs/005-worktree-ready-flow/validation.md` as the implementation validation log for quickstart scenarios → Artifacts: [validation.md](./validation.md)
- [x] T003 [P] [EXECUTOR: worker] [PARALLEL-GROUP-SETUP] Add a helper invocation placeholder and updated quick-usage skeleton to `.claude/commands/worktree.md` → Artifacts: [worktree.md](../../.claude/commands/worktree.md)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Build the shared readiness/reporting infrastructure required by every user story.

**⚠️ CRITICAL**: No user story work should begin until this phase is complete.

- [x] T004 [EXECUTOR: worker] [SEQUENTIAL] Implement path normalization, branch/path formatting, and reusable output rendering in `scripts/worktree-ready.sh` → Artifacts: [worktree-ready.sh](../../scripts/worktree-ready.sh)
- [x] T005 [EXECUTOR: worker] [SEQUENTIAL] Implement worktree/beads discovery using `bd worktree list` and `git worktree list` in `scripts/worktree-ready.sh` → Artifacts: [worktree-ready.sh](../../scripts/worktree-ready.sh)
- [x] T006 [EXECUTOR: worker] [SEQUENTIAL] Implement `scripts/git-session-guard.sh --status` integration and status parsing in `scripts/worktree-ready.sh` → Artifacts: [worktree-ready.sh](../../scripts/worktree-ready.sh)
- [x] T007 [EXECUTOR: worker] [SEQUENTIAL] Implement readiness report generation matching `specs/005-worktree-ready-flow/contracts/worktree-readiness-schema.md` in `scripts/worktree-ready.sh` → Artifacts: [worktree-ready.sh](../../scripts/worktree-ready.sh)
- [x] T008 [EXECUTOR: worker] [SEQUENTIAL] Wire foundational helper usage, readiness vocabulary, and fallback rules into `.claude/commands/worktree.md` → Artifacts: [worktree.md](../../.claude/commands/worktree.md)

**Checkpoint**: The helper can classify a worktree and render a consistent readiness block.

---

## Phase 3: User Story 1 - Existing Branch Without Guesswork (Priority: P1) 🎯 MVP

**Goal**: Existing branches can become worktrees through a first-class flow without forcing the user to remember low-level commands.

**Independent Test**: Request a worktree for an existing branch and receive a sanitized path, a correct branch mapping, and an actionable `Next` block without follow-up explanation.

### Implementation for User Story 1

- [x] T009 [US1] [EXECUTOR: worker] [SEQUENTIAL] Implement existing-branch resolution and target-path derivation in `scripts/worktree-ready.sh` → Artifacts: [worktree-ready.sh](../../scripts/worktree-ready.sh)
- [x] T010 [US1] [EXECUTOR: worker] [SEQUENTIAL] Implement already-attached-branch detection with existing-path reporting in `scripts/worktree-ready.sh` → Artifacts: [worktree-ready.sh](../../scripts/worktree-ready.sh)
- [x] T011 [US1] [EXECUTOR: worker] [SEQUENTIAL] Add `attach` and `start --existing` routing rules to `.claude/commands/worktree.md` → Artifacts: [worktree.md](../../.claude/commands/worktree.md)
- [x] T012 [US1] [EXECUTOR: worker] [SEQUENTIAL] Add sanitized path preview and existing-branch output examples to `.claude/commands/worktree.md` → Artifacts: [worktree.md](../../.claude/commands/worktree.md)

**Checkpoint**: A user with an existing branch can get the right worktree without low-level command knowledge.

---

## Phase 4: User Story 2 - Honest Ready-to-Work Handoff (Priority: P1)

**Goal**: The workflow reports actual session readiness and the exact next action instead of stopping at "created".

**Independent Test**: Run the flow once in a context that needs environment approval and once in a context that does not; each time the final status and next steps must match reality.

### Implementation for User Story 2

- [x] T013 [US2] [EXECUTOR: worker] [SEQUENTIAL] Implement environment-readiness probes and next-step generation in `scripts/worktree-ready.sh` → Artifacts: [worktree-ready.sh](../../scripts/worktree-ready.sh)
- [x] T014 [US2] [EXECUTOR: worker] [SEQUENTIAL] Map helper outcomes to `created`, `needs_env_approval`, `ready_for_codex`, and `action_required` in `scripts/worktree-ready.sh` → Artifacts: [worktree-ready.sh](../../scripts/worktree-ready.sh)
- [x] T015 [US2] [EXECUTOR: worker] [SEQUENTIAL] Update the final status block and completion rules in `.claude/commands/worktree.md` → Artifacts: [worktree.md](../../.claude/commands/worktree.md)
- [x] T016 [US2] [EXECUTOR: worker] [SEQUENTIAL] Add manual copy-paste handoff examples for blocked and ready environments to `.claude/commands/worktree.md` → Artifacts: [worktree.md](../../.claude/commands/worktree.md)

**Checkpoint**: The command no longer overstates readiness and always tells the user the exact next step.

---

## Phase 5: User Story 3 - Optional Terminal and Codex Launch (Priority: P2)

**Goal**: Frequent users can opt into a one-step handoff to a terminal or Codex session, with safe fallback when unsupported.

**Independent Test**: Request `--handoff terminal` and `--handoff codex`; on supported systems automation runs, and on unsupported systems the user gets a correct manual fallback.

### Implementation for User Story 3

- [x] T017 [US3] [EXECUTOR: worker] [SEQUENTIAL] Implement `--handoff manual|terminal|codex` parsing and fallback selection in `scripts/worktree-ready.sh` → Artifacts: [worktree-ready.sh](../../scripts/worktree-ready.sh)
- [x] T018 [US3] [EXECUTOR: worker] [SEQUENTIAL] Implement macOS terminal/Codex launch commands plus manual fallback output in `scripts/worktree-ready.sh` → Artifacts: [worktree-ready.sh](../../scripts/worktree-ready.sh)
- [x] T019 [US3] [EXECUTOR: worker] [SEQUENTIAL] Document opt-in handoff behavior, platform limits, and safety boundaries in `.claude/commands/worktree.md` → Artifacts: [worktree.md](../../.claude/commands/worktree.md)

**Checkpoint**: Handoff automation is useful when requested and harmless when unavailable.

---

## Phase 6: User Story 4 - Readiness Diagnosis for Worktrees (Priority: P2)

**Goal**: A developer can run doctor mode and immediately understand why a worktree is or is not ready.

**Independent Test**: Run doctor against a healthy worktree and a degraded worktree; both must return concise status plus one exact recommended action for any failing probe.

### Implementation for User Story 4

- [x] T020 [US4] [EXECUTOR: worker] [SEQUENTIAL] Implement `doctor` mode with branch, beads, guard, environment, and topology checks in `scripts/worktree-ready.sh` → Artifacts: [worktree-ready.sh](../../scripts/worktree-ready.sh)
- [x] T021 [US4] [EXECUTOR: worker] [SEQUENTIAL] Route `/worktree doctor` and related diagnostics in `.claude/commands/worktree.md` → Artifacts: [worktree.md](../../.claude/commands/worktree.md)
- [x] T022 [US4] [EXECUTOR: worker] [SEQUENTIAL] Add occupied-branch and recovery-guidance examples to `.claude/commands/worktree.md` → Artifacts: [worktree.md](../../.claude/commands/worktree.md)

**Checkpoint**: Doctor mode provides a compact readiness diagnosis and concrete recovery steps.

---

## Phase 6B: User Story 5 - One-Shot Start Without Workflow Knowledge (Priority: P1)

**Goal**: A user can request a new worktree with only a short slug, and the workflow will either create the clean default automatically, reuse exact matches, or ask one short clarification when ambiguity is real.

**Independent Test**: Run the helper and command flow with slug-only input in three states: no collision, exact existing target, and similar-name collision. Each scenario must end in either an automatic safe decision or one concise clarification that includes the clean-new option.

### Implementation for User Story 5

- [x] T026 [US5] [EXECUTOR: worker] [SEQUENTIAL] Extend the feature package for slug-only start, ambiguity handling, and live-topology authority in `specs/005-worktree-ready-flow/spec.md`, `plan.md`, `data-model.md`, and `contracts/` → Artifacts: [spec.md](./spec.md), [plan.md](./plan.md), [data-model.md](./data-model.md), [worktree-command-interface.md](./contracts/worktree-command-interface.md), [worktree-planning-schema.md](./contracts/worktree-planning-schema.md)
- [x] T027 [US5] [EXECUTOR: worker] [SEQUENTIAL] Implement `plan` mode with branch/path derivation, live git conflict detection, and planning decisions in `scripts/worktree-ready.sh` → Artifacts: [worktree-ready.sh](../../scripts/worktree-ready.sh)
- [x] T028 [US5] [EXECUTOR: worker] [SEQUENTIAL] Merge planner-first slug-only routing, clarification rules, and topology-aware start behavior into `.claude/commands/worktree.md` → Artifacts: [worktree.md](../../.claude/commands/worktree.md)
- [x] T029 [US5] [EXECUTOR: worker] [SEQUENTIAL] Update Codex-facing usage guidance for plain-language "worktree skill" invocations in `.ai/instructions/codex-adapter.md`, `AGENTS.md`, and `docs/QUICK-REFERENCE.md` → Artifacts: [codex-adapter.md](../../.ai/instructions/codex-adapter.md), [AGENTS.md](../../AGENTS.md), [QUICK-REFERENCE.md](../../docs/QUICK-REFERENCE.md)
- [x] T030 [US5] [EXECUTOR: worker] [SEQUENTIAL] Add unit coverage for helper planning decisions and fixture support in `tests/unit/test_worktree_ready.sh` and `tests/lib/git_topology_fixture.sh` → Artifacts: [test_worktree_ready.sh](../../tests/unit/test_worktree_ready.sh), [git_topology_fixture.sh](../../tests/lib/git_topology_fixture.sh)
- [x] T031 [US5] [EXECUTOR: MAIN] [SEQUENTIAL] Record pre-UAT helper validation for slug-only and ambiguity scenarios in `specs/005-worktree-ready-flow/validation.md` and `quickstart.md` → Artifacts: [validation.md](./validation.md), [quickstart.md](./quickstart.md)

**Checkpoint**: Slug-only start no longer depends on the user remembering issue ids, naming templates, or the difference between clean-create and attach flows.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Finalize docs, validate scenarios, and reconcile the feature package.

- [x] T023 [EXECUTOR: worker] [SEQUENTIAL] Update quick usage, output format, and safety notes comprehensively in `.claude/commands/worktree.md` → Artifacts: [worktree.md](../../.claude/commands/worktree.md)
- [ ] T024 [P] [EXECUTOR: MAIN] [PARALLEL-GROUP-VALIDATION] Validate the scenarios from `specs/005-worktree-ready-flow/quickstart.md` and record results in `specs/005-worktree-ready-flow/validation.md`
- [x] T025 [EXECUTOR: MAIN] [SEQUENTIAL] Reconcile implementation notes and checkbox state in `specs/005-worktree-ready-flow/tasks.md` → Artifacts: [tasks.md](./tasks.md)

---

## Phase 7B: UAT Hardening Follow-Up

**Purpose**: Close the stop-and-handoff gap found in manual UAT so `command-worktree` does not continue downstream work from the originating session.

- [x] T032 [EXECUTOR: MAIN] [SEQUENTIAL] Extend `specs/005-worktree-ready-flow/spec.md`, `plan.md`, `data-model.md`, and `contracts/` with stop-and-handoff boundary semantics and a machine-readable handoff contract
- [x] T033 [EXECUTOR: worker] [SEQUENTIAL] Add machine-readable `key=value` handoff output, terminal final states, and stable exit-code mapping to `scripts/worktree-ready.sh`
- [x] T034 [EXECUTOR: worker] [SEQUENTIAL] Rewrite `.claude/commands/worktree.md` so create/attach flows are explicitly Phase A only (`prepare -> handoff -> stop`) and may not continue downstream task execution in the originating session
- [x] T035 [EXECUTOR: worker] [SEQUENTIAL] Add unit regression coverage for boundary-aware handoff output and blocked/clarification exit codes in `tests/unit/test_worktree_ready.sh`
- [x] T036 [EXECUTOR: MAIN] [SEQUENTIAL] Update `specs/005-worktree-ready-flow/quickstart.md` and `validation.md` with the new UAT stop-boundary scenarios and expected handoff block
- [x] T037 [EXECUTOR: MAIN] [SEQUENTIAL] Run targeted validation (`make codex-check`, relevant worktree tests, manual/UAT notes) and mark the follow-up tasks complete in `specs/005-worktree-ready-flow/tasks.md`

---

## Phase 7C: Invoking-Branch Landing and Copy-Paste UX

**Purpose**: Ensure topology registry mutations are landed in the invoking branch before handoff and that manual next steps are rendered in copy-paste-friendly code blocks.

- [x] T038 [EXECUTOR: MAIN] [SEQUENTIAL] Extend `specs/005-worktree-ready-flow/spec.md`, `plan.md`, `quickstart.md`, and `validation.md` with invoking-branch landing semantics and fenced-command UX
- [x] T039 [EXECUTOR: worker] [SEQUENTIAL] Update `.claude/commands/worktree.md` so managed create/attach flows land topology registry mutations in the invoking branch before handoff and render manual next steps inside fenced `bash` blocks
- [x] T040 [EXECUTOR: MAIN] [SEQUENTIAL] Validate the new guidance against the latest UAT findings and mark the follow-up tasks complete in `specs/005-worktree-ready-flow/tasks.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: no dependencies
- **Phase 2 (Foundational)**: depends on Phase 1 and blocks all user stories
- **Phase 3 (US1)**, **Phase 4 (US2)**, and **Phase 6B (US5)**: depend on Phase 2 and form the modern MVP path
- **Phase 5 (US3)** and **Phase 6 (US4)**: depend on Phase 2 and can proceed after the MVP path
- **Phase 7 (Polish)**: depends on all desired story work being complete

### User Story Dependencies

- **US1** depends on the foundational helper/reporting layer
- **US2** depends on the foundational helper/reporting layer
- **US5** depends on the foundational helper/reporting layer and extends the same helper with live topology planning
- **US3** depends on US2 readiness output being present
- **US4** depends on the foundational helper/reporting layer and reuses US2 status vocabulary

### Parallel Opportunities

- T002 and T003 can proceed in parallel after T001
- T005 through T007 stay sequential because they all modify `scripts/worktree-ready.sh`
- US1 and US2 can proceed in parallel after Phase 2 if separate owners avoid editing the same command artifact simultaneously
- T024 can run in parallel with final documentation cleanup once the implementation stabilizes

---

## Parallel Example: Foundational Phase

```bash
Task: "Implement worktree/beads discovery using bd worktree list and git worktree list in scripts/worktree-ready.sh"
Task: "Implement scripts/git-session-guard.sh --status integration and status parsing in scripts/worktree-ready.sh"
```

---

## Implementation Strategy

### MVP First

1. Complete Phase 1 (Setup)
2. Complete Phase 2 (Foundational)
3. Complete Phase 3 (US1)
4. Complete Phase 4 (US2)
5. Validate the blocked-env, ready-env, and slug-only one-shot scenarios from `specs/005-worktree-ready-flow/quickstart.md`

### Incremental Delivery

1. Deliver MVP with existing-branch flow, honest readiness handoff, and one-shot slug-only start
2. Add opt-in terminal/Codex handoff
3. Add doctor mode and final polish

### Notes

- `[P]` means parallelizable only when file ownership is respected
- Manual validation is required because the feature spans shell environment behavior and user-facing command UX
- The implementation must remain additive over the current low-level workflow
