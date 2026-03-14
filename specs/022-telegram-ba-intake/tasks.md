# Tasks: Factory Business Analyst Intake

**Input**: Design documents from `/specs/022-telegram-ba-intake/`  
**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories), `research.md`, `data-model.md`, `contracts/`

**Tests**: Validation tasks are included because this slice introduces conversational discovery, confirmation gating, example-driven clarification, handoff into the existing concept-pack pipeline, and interrupted-session recovery.

**Organization**: Tasks are grouped by user story so the discovery layer can be delivered as independent slices without mixing it into the already completed `020-agent-factory-prototype` scope. `022-telegram-ba-intake` remains the legacy feature id; the actual scope is the factory business-analyst agent on `Moltis` with pluggable interface adapters.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (e.g. `US1`, `US2`)
- Include exact file paths in descriptions

## Phase 0: Planning (Executor Assignment)

**Purpose**: Lock the discovery-first scope and assign implementation ownership before runtime changes begin.

- [x] P001 Analyze all tasks and identify executor domains for discovery state, brief generation, handoff, config, tests, and runbooks
- [x] P002 Create and reconcile the active Speckit package in `specs/022-telegram-ba-intake/`
- [x] P003 Confirm the downstream boundary to `specs/020-agent-factory-prototype/` so handoff changes do not drift into defense/swarm concerns
- [x] P004 Resolve planning blockers using local repo context without leaving unresolved clarification markers

---

## Phase 1: Foundational (Blocking Prerequisites)

**Purpose**: Establish discovery-specific templates, fixtures, config anchors, and test wiring before user-story implementation.

**⚠️ CRITICAL**: No user story work should be treated as complete until this phase is done.

- [x] T001 Update discovery-first factory identity and state-path anchors in `config/moltis.toml`
- [x] T002 [P] Create a source-first requirements brief template in `docs/templates/agent-factory/requirements-brief.md`
- [x] T003 [P] Create reusable discovery fixtures in `tests/fixtures/agent-factory/discovery/`
- [x] T004 Wire future discovery tests into `tests/run.sh`

**Checkpoint**: Discovery config, brief template, fixtures, and test harness are ready.

---

## Phase 2: User Story 1 - Guided Discovery Interview (Priority: P1) 🎯 MVP

**Goal**: Let a non-technical business user start a factory conversation through a supported interface and be guided through the collection of structured business requirements.

**Independent Test**: A user starts with a raw automation idea, answers adaptive questions in free-form business language, and the system tracks discovery progress without requiring an external template.

### Validation for User Story 1

- [x] T005 [P] [US1] Create component coverage for topic progress and next-question behavior in `tests/component/test_agent_factory_discovery.sh`
- [x] T006 [P] [US1] Create local discovery-flow integration coverage in `tests/integration_local/test_agent_factory_discovery_flow.sh`

### Implementation for User Story 1

- [x] T007 [P] [US1] Implement discovery-session orchestration in `scripts/agent-factory-discovery.py`
- [x] T008 [P] [US1] Extend shared normalization/state helpers in `scripts/agent_factory_common.py`
- [x] T009 [US1] Wire discovery entrypoint and runtime anchors in `config/moltis.toml`
- [x] T010 [US1] Document discovery-session behavior in `docs/runbooks/agent-factory-discovery.md`

**Checkpoint**: The factory can guide a business user through a structured interview through the current interface adapter.

---

## Phase 3: User Story 2 - Confirmed Requirements Brief (Priority: P1)

**Goal**: Turn discovery output into a reviewable brief that the user can correct and explicitly confirm before downstream generation begins.

**Independent Test**: The user reviews a brief draft, requests corrections in conversation, and confirms a final version without editing files manually.

### Validation for User Story 2

- [x] T011 [P] [US2] Create component coverage for brief drafting and confirmation state in `tests/component/test_agent_factory_brief.sh`
- [x] T012 [P] [US2] Create local confirmation-loop integration coverage in `tests/integration_local/test_agent_factory_confirmation.sh`

### Implementation for User Story 2

- [x] T013 [P] [US2] Implement draft brief generation and versioning in `scripts/agent-factory-discovery.py`
- [x] T014 [P] [US2] Implement brief rendering from `docs/templates/agent-factory/requirements-brief.md`
- [x] T015 [US2] Document correction, confirmation, and reopen rules in `docs/runbooks/agent-factory-discovery.md`

**Checkpoint**: One confirmed requirements brief can be produced from the discovery dialogue.

---

## Phase 4: User Story 3 - Example-Driven Requirement Clarification (Priority: P2)

**Goal**: Preserve examples, rules, and exceptions as first-class discovery artifacts and resolve contradictions before confirmation.

**Independent Test**: The user provides multiple input/output cases and the system captures them structurally, detects contradictions, and forces clarification before confirmation.

### Validation for User Story 3

- [x] T016 [P] [US3] Create component coverage for example extraction and contradiction handling in `tests/component/test_agent_factory_examples.sh`

### Implementation for User Story 3

- [x] T017 [P] [US3] Extend `scripts/agent-factory-discovery.py` to capture example cases, business rules, and exceptions
- [x] T018 [US3] Implement safe-example and contradiction handling in `scripts/agent_factory_common.py`
- [x] T019 [US3] Document example and clarification policy in `docs/runbooks/agent-factory-discovery.md`

**Checkpoint**: Discovery captures grounded business cases instead of abstract prose only.

---

## Phase 5: User Story 4 - Handoff Into Existing Factory Pipeline (Priority: P2)

**Goal**: Convert a confirmed brief into a canonical handoff record consumable by the existing concept-pack pipeline.

**Independent Test**: A confirmed brief triggers one handoff record and the downstream concept-pack path can start without manual copy-paste, while unconfirmed or reopened briefs remain blocked.

### Validation for User Story 4

- [x] T020 [P] [US4] Create handoff compatibility coverage in `tests/component/test_agent_factory_handoff.sh`
- [x] T021 [P] [US4] Create local discovery-to-concept integration coverage in `tests/integration_local/test_agent_factory_handoff.sh`

### Implementation for User Story 4

- [x] T022 [P] [US4] Implement canonical handoff record generation in `scripts/agent-factory-discovery.py`
- [x] T023 [US4] Adapt `scripts/agent-factory-intake.py` to consume confirmed discovery handoff records
- [x] T024 [US4] Reconcile downstream concept-pack entry semantics in `scripts/agent-factory-artifacts.py`
- [x] T025 [US4] Document discovery-to-concept handoff in `docs/runbooks/agent-factory-discovery.md` and `docs/runbooks/agent-factory-prototype.md`

**Checkpoint**: Confirmed discovery becomes the real upstream input for the existing factory.

---

## Phase 6: User Story 5 - Interrupted Session Recovery (Priority: P3)

**Goal**: Let a user resume discovery or reopen a confirmed brief without losing context or overwriting prior confirmed state.

**Independent Test**: A user leaves mid-session or reopens a confirmed brief later, and the system continues from the correct state with preserved history.

### Validation for User Story 5

- [ ] T026 [P] [US5] Create local resume/reopen coverage in `tests/integration_local/test_agent_factory_resume.sh`

### Implementation for User Story 5

- [ ] T027 [P] [US5] Implement discovery session persistence and recovery in `scripts/agent-factory-discovery.py`
- [ ] T028 [P] [US5] Extend revision and confirmation history support in `scripts/agent_factory_common.py`
- [ ] T029 [US5] Document resume and reopen expectations in `docs/runbooks/agent-factory-discovery.md`

**Checkpoint**: Discovery survives real business pauses and revision loops.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Reconcile spec artifacts, docs, tests, and handoff boundaries before landing.

- [ ] T030 [P] Run final planning artifact validation in `.specify/scripts/bash/check-prerequisites.sh` and reconcile `specs/022-telegram-ba-intake/checklists/requirements.md`
- [ ] T031 [P] Refresh topology documentation after feature-branch mutation in `docs/GIT-TOPOLOGY-REGISTRY.md`
- [ ] T032 Reconcile session handoff and current status in `SESSION_SUMMARY.md`
- [ ] T033 Run quickstart verification from `specs/022-telegram-ba-intake/quickstart.md` and record any remaining blockers

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1: Foundational** blocks all user-story implementation.
- **Phase 2: US1** is the MVP slice and depends on Phase 1.
- **Phase 3: US2** depends on US1 because confirmation requires discovery output.
- **Phase 4: US3** depends on US1 and should land before brief confirmation is treated as robust.
- **Phase 5: US4** depends on US2 because only a confirmed brief can be handed off downstream.
- **Phase 6: US5** depends on US1/US2 because recovery operates on real session and brief state.
- **Phase 7: Polish** depends on all desired user stories.

### User Story Dependencies

- **US1 (P1)**: can start after foundational work.
- **US2 (P1)**: requires discovery-session output from US1.
- **US3 (P2)**: builds on the discovery session and should precede final confirmation hardening.
- **US4 (P2)**: requires a confirmed brief from US2.
- **US5 (P3)**: builds on session and brief versioning from US1 and US2.

### Parallel Opportunities

- `T002`, `T003`, and `T004` can run in parallel in Phase 1.
- `T005` and `T006` can run in parallel for US1 validation.
- `T007` and `T008` can run in parallel once the foundational phase is complete.
- `T011` and `T012` can run in parallel for US2 validation.
- `T020` and `T021` can run in parallel for handoff validation.

## Implementation Strategy

### MVP First (User Story 1 + User Story 2)

1. Finish discovery foundations.
2. Implement guided discovery interview.
3. Generate a draft brief and explicit confirmation loop.
4. Review the resulting discovery UX before expanding into example logic and downstream handoff.

### Incremental Delivery

1. Add discovery session state and next-question logic.
2. Add draft brief, confirmation, and versioning.
3. Add example grounding and contradiction handling.
4. Add handoff into the existing concept-pack pipeline.
5. Add recovery/reopen semantics and final polish.

### Parallel Team Strategy

With multiple implementers:

- one stream owns `config/` and runtime anchors
- one stream owns `scripts/agent-factory-discovery.py` and shared helpers
- one stream owns `tests/fixtures/agent-factory/discovery/` plus validation scripts
- one stream owns runbooks and planning reconciliation
