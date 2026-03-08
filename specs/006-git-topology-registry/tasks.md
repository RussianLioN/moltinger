# Tasks: Auto-Maintained Git Topology Registry

**Input**: Design documents from `/specs/006-git-topology-registry/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Shell-based validation is required for this feature because the registry must remain deterministic and reliable under topology mutations.

**Organization**: Tasks are grouped by user story so each story can be implemented and validated independently.

## Phase 0: Planning (Executor Assignment)

- [x] P001 Review `docs/reports/consilium/2026-03-08-git-topology-registry-automation.md` and freeze v1 scope in `specs/006-git-topology-registry/plan.md`
- [x] P002 Analyze all implementation tasks and assign executors across `scripts/`, `.githooks/`, `.claude/commands/`, `docs/`, and `tests/`
- [x] P003 Decide the final sidecar filename/schema and record it in `specs/006-git-topology-registry/contracts/registry-document.md`
- [x] P004 Prepare shell fixture strategy for topology discovery and hook validation in `tests/`

---

## Phase 1: Setup (Shared Infrastructure)

- [x] T001 Create sidecar intent file in `docs/GIT-TOPOLOGY-INTENT.yaml`
- [x] T002 Create owner script skeleton in `scripts/git-topology-registry.sh`
- [x] T003 [P] Create tracked hook placeholders in `.githooks/post-checkout`, `.githooks/post-merge`, and `.githooks/post-rewrite`
- [x] T004 Update `scripts/setup-git-hooks.sh` to install tracked hook files instead of regenerating hook bodies inline
- [x] T005 [P] Add script metadata entry for the new topology tool in `scripts/manifest.json`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Build the shared generator/check/recovery foundation before wiring any user story workflow.

- [x] T006 Implement live topology discovery in `scripts/git-topology-registry.sh` using `git worktree list --porcelain` and `git for-each-ref`
- [x] T007 Implement repo-shared lock and health-state handling under `$(git rev-parse --git-common-dir)` in `scripts/git-topology-registry.sh`
- [x] T008 Implement deterministic markdown rendering for `docs/GIT-TOPOLOGY-REGISTRY.md` in `scripts/git-topology-registry.sh`
- [x] T009 Implement sidecar merge/default-intent logic in `scripts/git-topology-registry.sh`
- [x] T010 Implement `refresh`, `check`, `status`, and `doctor` command paths in `scripts/git-topology-registry.sh`

**Checkpoint**: The repo can now compute normalized topology, render a deterministic registry, and detect/recover stale state.

---

## Phase 3: User Story 1 - Trust Current Git Topology (Priority: P1) 🎯 MVP

**Goal**: Operators and LLM sessions can rely on one committed, sanitized registry instead of rediscovering topology manually.

**Independent Test**: Run `scripts/git-topology-registry.sh refresh --write-doc` after a topology change and verify the committed registry updates correctly without absolute paths or volatile churn.

- [ ] T011 [US1] Convert `docs/GIT-TOPOLOGY-REGISTRY.md` into the generated, sanitized registry format produced by `scripts/git-topology-registry.sh`
- [ ] T012 [US1] Render current worktrees, active local branches, and unmerged remote branches into `docs/GIT-TOPOLOGY-REGISTRY.md`
- [ ] T013 [P] [US1] Update `docs/QUICK-REFERENCE.md`, `CLAUDE.md`, `.ai/instructions/shared-core.md`, and `AGENTS.md` to describe the registry as generated and point to the refresh/check path
- [ ] T014 [P] [US1] Add shell validation coverage for discovery/render determinism in `tests/unit/test_git_topology_registry.sh`
- [ ] T015 [US1] Add integration validation for sanitized output and no-op refresh behavior in `tests/integration/test_git_topology_registry.sh`

**Checkpoint**: A refreshed registry provides a trustworthy, sanitized shared topology snapshot.

---

## Phase 4: User Story 2 - Keep Registry Current Through Managed Workflows (Priority: P2)

**Goal**: Managed topology-changing workflows refresh or validate the registry in the same flow.

**Independent Test**: Run `/worktree start`, `/worktree cleanup`, and `/session-summary` paths in a temp repo/worktree setup and verify the registry is refreshed or the user receives actionable stale-state guidance.

- [ ] T020 [US2] Integrate registry refresh/check into `.claude/commands/worktree.md` for `start`, `finish`, and `cleanup`
- [ ] T021 [US2] Integrate registry check/refresh into `.claude/commands/session-summary.md`
- [ ] T022 [US2] Wire validation/backstop logic into `.githooks/pre-push`, `.githooks/post-checkout`, `.githooks/post-merge`, and `.githooks/post-rewrite`
- [ ] T023 [P] [US2] Create a thin command wrapper in `.claude/commands/git-topology.md` for `refresh`, `check`, `status`, and `doctor`
- [ ] T024 [P] [US2] Add workflow integration coverage for managed topology mutations in `tests/e2e/test_git_topology_registry_workflow.sh`

**Checkpoint**: Managed repo workflows keep registry freshness aligned with topology changes.

---

## Phase 5: User Story 3 - Preserve Human Intent and Recover From Drift (Priority: P3)

**Goal**: Reviewed intent survives regeneration, and manual raw git changes can be reconciled safely.

**Independent Test**: Add reviewed intent for a branch/worktree, make an out-of-band topology change, run `doctor`, and verify the registry and intent are reconciled without losing approved notes.

- [ ] T030 [US3] Implement the reviewed intent schema in `docs/GIT-TOPOLOGY-INTENT.yaml`
- [ ] T031 [US3] Implement orphan-intent handling and default `needs-decision` behavior in `scripts/git-topology-registry.sh`
- [ ] T032 [US3] Implement stale-state recovery draft/backup behavior in `scripts/git-topology-registry.sh`
- [ ] T033 [P] [US3] Document manual reconciliation and recovery flows in `specs/006-git-topology-registry/quickstart.md`
- [ ] T034 [P] [US3] Add annotation-preservation and doctor-flow coverage in `tests/integration/test_git_topology_registry.sh` and `tests/e2e/test_git_topology_registry_workflow.sh`

**Checkpoint**: The system preserves human intent and recovers cleanly from out-of-band topology drift.

---

## Final Phase: Polish & Cross-Cutting Concerns

- [ ] T040 [P] Reconcile `docs/reports/consilium/2026-03-08-git-topology-registry-automation.md` with final implementation decisions and add feature cross-links where needed
- [ ] T041 Run quality gates for the feature using `tests/unit/test_git_topology_registry.sh`, `tests/integration/test_git_topology_registry.sh`, and `tests/e2e/test_git_topology_registry_workflow.sh`
- [ ] T042 Refresh `docs/GIT-TOPOLOGY-REGISTRY.md` from the final generator and verify it contains no absolute paths
- [ ] T043 Verify `scripts/setup-git-hooks.sh` installs hook behavior identical to tracked `.githooks/*`
- [ ] T044 Prepare merge-ready handoff notes in `specs/006-git-topology-registry/quickstart.md` and `SESSION_SUMMARY.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1**: starts immediately
- **Phase 2**: depends on Phase 1
- **Phase 3**: depends on Phase 2
- **Phase 4**: depends on Phase 2 and should build on the MVP from Phase 3
- **Phase 5**: depends on Phase 2 and should build on the workflow wiring from Phase 4
- **Final Phase**: depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: no dependency on later stories; delivers the first useful registry snapshot
- **User Story 2 (P2)**: depends on the generator and registry format from US1
- **User Story 3 (P3)**: depends on the generator plus workflow/recovery surfaces established earlier

### Parallel Opportunities

- Sidecar file, hook placeholders, and manifest metadata can start in parallel
- Deterministic render tests and sanitized-output tests can run in parallel once the generator exists
- Workflow wrapper and e2e workflow tests can run in parallel within US2
- Recovery docs and annotation-preservation tests can run in parallel within US3

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Setup
2. Complete Foundational generator/check/recovery base
3. Deliver generated, sanitized registry snapshot
4. Validate deterministic refresh and no-op behavior

### Incremental Delivery

1. Add managed workflow integration after MVP registry exists
2. Add reviewed intent preservation and doctor/recovery after workflow integration
3. Finish with hook parity, quality gates, and handoff docs
