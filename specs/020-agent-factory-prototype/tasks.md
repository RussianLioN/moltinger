# Tasks: Agent Factory Prototype

**Input**: Design documents from `/specs/020-agent-factory-prototype/`  
**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories), `research.md`, `data-model.md`, `contracts/`

**Tests**: Validation tasks are included because the feature contract requires synchronized artifacts, explicit approval gates, traceable swarm stages, and admin-visible failure handling.

**Organization**: Tasks are grouped by user story so each delivery slice can be implemented and demonstrated independently.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (e.g. `US1`, `US2`, `US3`)
- Include exact file paths in descriptions

## Phase 0: Planning (Executor Assignment)

**Purpose**: Lock the planning baseline and assign future implementation slices.

- [x] P001 Analyze all tasks and identify the required executor domains for mirror/context, intake, review, swarm, playground, and evidence work
- [x] P002 Create the active Speckit package and planning artifacts in `specs/020-agent-factory-prototype/`
- [x] P003 Assign future work to existing repo domains (`config/`, `scripts/`, `tests/`, `docs/`, `.github/workflows/`) instead of inventing a parallel project tree
- [x] P004 Resolve planning blockers through local project context and upstream ASC mirror without leaving unresolved clarification markers

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Prepare the local context mirror and planning anchors that all later runtime work depends on.

- [x] T001 Mirror upstream ASC roadmap and concept docs into `docs/asc-roadmap/` and `docs/concept/`
- [x] T002 Add provenance and navigation for the local ASC mirror in `docs/ASC-AI-FABRIQUE-MIRROR.md`
- [x] T003 Reconcile local factory planning references to use in-repo ASC paths in `docs/plans/parallel-doodling-coral.md` and `docs/research/openclaw-moltis-research.md`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish factory identity, artifact templates, fleet role contracts, and reusable fixtures before user stories are implemented.

**⚠️ CRITICAL**: No user story work should be treated as complete until this phase is done.

- [ ] T004 Update the factory-facing identity and local ASC context references in `config/moltis.toml`
- [ ] T005 [P] Create source-first artifact templates in `docs/templates/agent-factory/project-doc.md`, `docs/templates/agent-factory/agent-spec.md`, and `docs/templates/agent-factory/presentation.md`
- [ ] T006 [P] Extend fleet role defaults for tester, validator, auditor, and assembler in `config/fleet/agents-registry.json` and `config/fleet/policy.json`
- [ ] T007 [P] Create reusable fixtures for concept intake, defense feedback, and swarm evidence in `tests/fixtures/agent-factory/`
- [ ] T008 Wire future agent-factory test files into the umbrella runner in `tests/run.sh`

**Checkpoint**: Factory context, reusable templates, future-role contracts, and fixtures are ready.

---

## Phase 3: User Story 1 - Idea Intake To Concept Pack (Priority: P1) 🎯 MVP

**Goal**: Turn a Telegram conversation into a versioned concept record and three synchronized downloadable artifacts.

**Independent Test**: A user provides one automation idea through a guided flow and receives aligned project-doc/spec/presentation outputs without manual file assembly.

### Validation for User Story 1

- [ ] T009 [P] [US1] Create artifact-alignment checks in `tests/component/test_agent_factory_artifacts.sh`
- [ ] T010 [P] [US1] Create intake-flow integration coverage in `tests/integration_local/test_agent_factory_intake.sh`

### Implementation for User Story 1

- [ ] T011 [P] [US1] Implement concept intake orchestration in `scripts/agent-factory-intake.py`
- [ ] T012 [P] [US1] Implement concept-pack generation and artifact version sync in `scripts/agent-factory-artifacts.py`
- [ ] T013 [US1] Wire Moltinger factory routing and concept-pack behavior in `config/moltis.toml`
- [ ] T014 [US1] Document concept-pack output and download semantics in `docs/runbooks/agent-factory-prototype.md`

**Checkpoint**: One idea can become a synchronized three-artifact concept pack.

---

## Phase 4: User Story 2 - Defense Outcome And Rework Loop (Priority: P1)

**Goal**: Record defense outcomes, preserve feedback, and gate production until explicit approval exists.

**Independent Test**: The same concept can move through `approved`, `rework_requested`, `rejected`, or `pending_decision` with preserved version history.

### Validation for User Story 2

- [ ] T015 [P] [US2] Create defense-state integration coverage in `tests/integration_local/test_agent_factory_review.sh`

### Implementation for User Story 2

- [ ] T016 [P] [US2] Implement defense review and feedback capture in `scripts/agent-factory-review.py`
- [ ] T017 [US2] Extend artifact revision handling for feedback-driven updates in `scripts/agent-factory-artifacts.py`
- [ ] T018 [US2] Document approval, rejection, and rework rules in `docs/runbooks/agent-factory-prototype.md`

**Checkpoint**: Concept approval is explicit and version-safe before production.

---

## Phase 5: User Story 3 - Autonomous Production Swarm To Playground (Priority: P1)

**Goal**: Launch a specialized internal swarm that produces a runnable playground package from an approved concept.

**Independent Test**: An approved concept triggers coder/tester/validator/auditor/assembler stages and produces a reviewable playground bundle without end-user orchestration.

### Validation for User Story 3

- [ ] T019 [P] [US3] Create swarm orchestration coverage in `tests/integration_local/test_agent_factory_swarm.sh`
- [ ] T020 [P] [US3] Create playground packaging coverage in `tests/component/test_agent_factory_playground.sh`

### Implementation for User Story 3

- [ ] T021 [P] [US3] Implement swarm coordination and stage lifecycle in `scripts/agent-factory-swarm.py`
- [ ] T022 [P] [US3] Implement container and playground packaging in `scripts/agent-factory-playground.py`
- [ ] T023 [US3] Wire production-stage role contracts into `config/fleet/agents-registry.json` and `config/fleet/policy.json`
- [ ] T024 [US3] Document swarm evidence and playground publication flow in `docs/runbooks/agent-factory-prototype.md`

**Checkpoint**: Approved concepts can reach a runnable playground package with evidence.

---

## Phase 6: User Story 4 - Operator Escalation And Evidence (Priority: P2)

**Goal**: Produce structured escalation packets, auditable state transitions, and operator-visible status during defense and swarm execution.

**Independent Test**: A blocker failure creates a reviewable escalation packet with concept id, stage, evidence, and recommended action, while happy-path runs stay silent.

### Validation for User Story 4

- [ ] T025 [P] [US4] Create escalation and audit coverage in `tests/component/test_agent_factory_escalation.sh`

### Implementation for User Story 4

- [ ] T026 [P] [US4] Implement escalation packet and audit emission in `scripts/agent-factory-swarm.py`
- [ ] T027 [US4] Extend concept-pack and swarm status publication in `scripts/agent-factory-artifacts.py`
- [ ] T028 [US4] Document admin intervention flow and evidence expectations in `docs/runbooks/agent-factory-prototype.md`

**Checkpoint**: Operators can understand failures without tracing raw server state.

---

## Phase 7: User Story 5 - Local Context Continuity For Factory Knowledge (Priority: P2)

**Goal**: Keep the ASC mirror and local factory references reviewable, versioned, and discoverable for future sessions.

**Independent Test**: A new session can locate upstream concept context, local plans, active specs, and platform contracts from repo paths only.

### Validation for User Story 5

- [ ] T029 [P] [US5] Create mirror-integrity coverage in `tests/component/test_agent_factory_context_mirror.sh`

### Implementation for User Story 5

- [ ] T030 [US5] Reconcile mirror navigation and active spec references in `docs/ASC-AI-FABRIQUE-MIRROR.md` and `specs/020-agent-factory-prototype/quickstart.md`

**Checkpoint**: The repository itself carries the planning context required for future sessions.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Reconcile documentation, tests, and landing checks across the full prototype path.

- [ ] T031 [P] Run final planning artifact validation in `.specify/scripts/bash/check-prerequisites.sh` and reconcile `specs/020-agent-factory-prototype/checklists/requirements.md`
- [ ] T032 [P] Refresh topology documentation after the feature-branch mutation in `docs/GIT-TOPOLOGY-REGISTRY.md`
- [ ] T033 Reconcile session handoff and operator summary in `SESSION_SUMMARY.md`
- [ ] T034 Run quickstart verification from `specs/020-agent-factory-prototype/quickstart.md` and record any remaining blockers

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1: Setup** is already complete and establishes the context mirror.
- **Phase 2: Foundational** blocks all user-story implementation.
- **Phase 3: US1** depends on Phase 2 and is the MVP slice.
- **Phase 4: US2** depends on US1 because defense operates on concept-pack outputs.
- **Phase 5: US3** depends on US2 because production requires explicit approval.
- **Phase 6: US4** depends on US3 because escalation/evidence must cover the real swarm flow.
- **Phase 7: US5** can validate context continuity in parallel with late implementation, but final reconciliation should happen after other stories land.
- **Phase 8: Polish** depends on all desired user stories.

### User Story Dependencies

- **US1 (P1)**: starts after foundational work; no dependency on later stories.
- **US2 (P1)**: requires a concept-pack output from US1.
- **US3 (P1)**: requires an explicit defense approval state from US2.
- **US4 (P2)**: requires the real swarm flow from US3.
- **US5 (P2)**: benefits from all prior work but its validation can begin earlier.

### Within Each User Story

- Validation tasks should be added before the story is declared complete.
- Templates and fixtures should exist before orchestration code.
- Documentation changes should land alongside the behavior they describe.
- Story completion requires both behavior and evidence, not just code presence.

### Parallel Opportunities

- `T005`, `T006`, and `T007` can run in parallel inside Phase 2.
- `T009` and `T010` can run in parallel for US1 validation.
- `T011` and `T012` can run in parallel after templates/fixtures exist.
- `T019` and `T020` can run in parallel for US3 validation.
- `T021` and `T022` can run in parallel if stage boundaries stay explicit.

---

## Parallel Example: User Story 1

```bash
Task: "Create artifact-alignment checks in tests/component/test_agent_factory_artifacts.sh"
Task: "Create intake-flow integration coverage in tests/integration_local/test_agent_factory_intake.sh"

Task: "Implement concept intake orchestration in scripts/agent-factory-intake.py"
Task: "Implement concept-pack generation and artifact version sync in scripts/agent-factory-artifacts.py"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete foundational factory identity, templates, fixtures, and role contracts.
2. Implement intake plus synchronized concept-pack generation.
3. Validate that three downloadable artifacts stay aligned.
4. Stop and review before expanding into approval and swarm execution.

### Incremental Delivery

1. Context mirror and planning are already landed.
2. Add concept-pack intake.
3. Add defense gate and rework.
4. Add autonomous swarm to playground.
5. Add operator escalation and final context hardening.

### Parallel Team Strategy

With multiple implementers:

- one stream owns `config/` and `docs/templates/`
- one stream owns `scripts/agent-factory-*`
- one stream owns `tests/fixtures/agent-factory/` and validation scripts
- one stream owns `docs/runbooks/agent-factory-prototype.md` and planning reconciliation
