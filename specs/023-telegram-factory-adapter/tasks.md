# Tasks: Telegram Factory Adapter

**Input**: Design documents from `/specs/023-telegram-factory-adapter/`  
**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories), `research.md`, `data-model.md`, `contracts/`

**Tests**: Validation tasks are included because this slice preserves the Telegram adapter backlog for real user-facing brief confirmation, automatic downstream handoff, in-chat artifact delivery, and Telegram session recovery.

**Organization**: Tasks are grouped by user story so the Telegram adapter can be delivered as independent slices while preserving the existing ownership boundary: `022` remains the discovery core, `020` remains the downstream factory core, and `023` owns the live Telegram transport/routing/delivery layer only.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (e.g. `US1`, `US2`)
- Include exact file paths in descriptions

## Phase 0: Planning (Executor Assignment)

**Purpose**: Lock the Telegram-adapter scope and complete the planning package before runtime changes begin.

- [x] P001 Analyze the existing Telegram transport, discovery runtime, and downstream factory boundaries for `specs/023-telegram-factory-adapter/`
- [x] P002 Create and reconcile the active Speckit package in `specs/023-telegram-factory-adapter/`
- [x] P003 Record Telegram adapter decisions and source-backed constraints in `specs/023-telegram-factory-adapter/research.md`
- [x] P004 Resolve planning blockers without leaving unresolved clarification markers in `specs/023-telegram-factory-adapter/`

---

## Phase 1: Setup

**Purpose**: Establish Telegram-adapter-specific config, manifest, fixtures, and test wiring before foundational implementation starts.

- [ ] T001 Update active Telegram adapter anchors and storage paths in `config/moltis.toml`
- [ ] T002 [P] Reconcile script descriptions and new adapter entrypoints in `scripts/manifest.json`
- [ ] T003 [P] Create the Telegram adapter fixture tree in `tests/fixtures/agent-factory/telegram/README.md`
- [ ] T004 [P] Register Telegram adapter suites in `tests/run.sh`

**Checkpoint**: The repo knows where the adapter lives, how it is described, where its fixtures go, and how its tests will run.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Add the shared adapter plumbing that all Telegram user stories depend on.

**⚠️ CRITICAL**: No Telegram user story should be treated as complete until this phase is done.

- [ ] T005 [P] Create reusable Telegram adapter fixtures in `tests/fixtures/agent-factory/telegram/update-new-project.json`
- [ ] T006 [P] Create component routing and sanitization coverage in `tests/component/test_agent_factory_telegram_routing.sh`
- [ ] T007 [P] Create local adapter flow coverage in `tests/integration_local/test_agent_factory_telegram_flow.sh`
- [ ] T008 [P] Implement the adapter entrypoint and normalized envelope handling in `scripts/agent-factory-telegram-adapter.py`
- [ ] T009 [P] Extend shared Telegram render and state helpers in `scripts/agent_factory_common.py`
- [ ] T010 Document operator flow and adapter storage layout in `docs/runbooks/agent-factory-telegram-adapter.md`

**Checkpoint**: One Telegram update can be normalized, routed, and rendered through shared adapter plumbing.

---

## Phase 3: User Story 1 - Live Telegram Discovery Interview (Priority: P1) 🎯 MVP

**Goal**: Let a business user start a new project in Telegram and continue the guided discovery interview there without touching JSON, CLI, or repo files.

**Independent Test**: A raw Telegram message opens a project, the adapter routes it into `scripts/agent-factory-discovery.py`, and the user receives the next business-analyst follow-up question back in the same chat.

### Validation for User Story 1

- [ ] T011 [P] [US1] Create component coverage for Telegram intent parsing in `tests/component/test_agent_factory_telegram_intents.sh`
- [ ] T012 [P] [US1] Create integration coverage for `new project -> first follow-up question` in `tests/integration_local/test_agent_factory_telegram_discovery.sh`

### Implementation for User Story 1

- [ ] T013 [P] [US1] Extend `scripts/agent-factory-telegram-adapter.py` to open projects and route free-form Telegram replies into `scripts/agent-factory-discovery.py`
- [ ] T014 [P] [US1] Implement Telegram-readable discovery prompts and status text in `scripts/agent_factory_common.py`
- [ ] T015 [US1] Add discovery conversation fixtures in `tests/fixtures/agent-factory/telegram/update-discovery-answer.json`
- [ ] T016 [US1] Document live discovery commands and UX in `docs/runbooks/agent-factory-telegram-adapter.md`

**Checkpoint**: The factory business-analyst agent is reachable by a real user through Telegram for discovery.

---

## Phase 4: User Story 2 - Telegram Brief Review And Confirmation (Priority: P1)

**Goal**: Let the user review, correct, confirm, and reopen the requirements brief from inside Telegram.

**Independent Test**: The user reaches `awaiting_confirmation`, sees a Telegram-readable brief summary, asks for corrections conversationally, and explicitly confirms one exact brief version in the same chat.

### Validation for User Story 2

- [ ] T017 [P] [US2] Create component coverage for Telegram brief rendering and chunking in `tests/component/test_agent_factory_telegram_brief.sh`
- [ ] T018 [P] [US2] Create integration coverage for Telegram correction and confirmation intents in `tests/integration_local/test_agent_factory_telegram_confirmation.sh`

### Implementation for User Story 2

- [ ] T019 [P] [US2] Extend `scripts/agent-factory-telegram-adapter.py` to support brief review, correction, confirm, and reopen intents
- [ ] T020 [P] [US2] Implement chunked brief rendering and confirmation prompts in `scripts/agent_factory_common.py`
- [ ] T021 [US2] Add awaiting-confirmation fixtures in `tests/fixtures/agent-factory/telegram/update-brief-confirm.json`
- [ ] T022 [US2] Document Telegram brief confirmation and reopen behavior in `docs/runbooks/agent-factory-telegram-adapter.md`

**Checkpoint**: The user can complete `discovery -> confirmed brief` fully inside Telegram.

---

## Phase 5: User Story 3 - Automatic Factory Handoff From Telegram (Priority: P2)

**Goal**: Turn Telegram confirmation into automatic downstream handoff, concept-pack generation, and in-chat artifact delivery.

**Independent Test**: A confirmed Telegram brief launches the downstream handoff chain automatically, and the user receives the 3 concept-pack artifacts back in Telegram without manual operator file handling.

### Validation for User Story 3

- [ ] T023 [P] [US3] Create component coverage for downstream orchestration and delivery sanitization in `tests/component/test_agent_factory_telegram_delivery.sh`
- [ ] T024 [P] [US3] Create integration coverage for `confirmed brief -> artifacts returned to Telegram` in `tests/integration_local/test_agent_factory_telegram_handoff.sh`

### Implementation for User Story 3

- [ ] T025 [P] [US3] Extend `scripts/agent-factory-telegram-adapter.py` to invoke `scripts/agent-factory-intake.py` and `scripts/agent-factory-artifacts.py` automatically after confirmation
- [ ] T026 [P] [US3] Add Bot API document delivery helper in `scripts/telegram-bot-send-document.sh`
- [ ] T027 [US3] Reconcile delivery and provenance fields in `scripts/agent-factory-intake.py` and `scripts/agent-factory-artifacts.py`
- [ ] T028 [US3] Document concept-pack delivery and failure messaging in `docs/runbooks/agent-factory-telegram-adapter.md` and `docs/runbooks/agent-factory-prototype.md`

**Checkpoint**: Telegram is no longer just an input channel; it becomes the full user-facing path from confirmation to concept-pack delivery.

---

## Phase 6: User Story 4 - Resume And Reopen In Telegram (Priority: P3)

**Goal**: Let the user resume an interrupted Telegram conversation, inspect current status, and reopen a confirmed brief without losing provenance.

**Independent Test**: After pausing mid-discovery or after a confirmed brief already exists, the user can come back in Telegram, continue the same project, inspect status, or reopen the brief while history remains intact.

### Validation for User Story 4

- [ ] T029 [P] [US4] Create integration coverage for resume, status, and project selection in `tests/integration_local/test_agent_factory_telegram_resume.sh`

### Implementation for User Story 4

- [ ] T030 [P] [US4] Extend `scripts/agent-factory-telegram-adapter.py` to persist active project pointers and resume context under `data/agent-factory/telegram/`
- [ ] T031 [P] [US4] Extend `scripts/agent_factory_common.py` with Telegram session projection and reopened-brief status text
- [ ] T032 [P] [US4] Add live pilot validation for adapter delivery boundaries in `tests/live_external/test_telegram_external_smoke.sh`
- [ ] T033 [US4] Document resume, reopen, and `/status` behavior in `docs/runbooks/agent-factory-telegram-adapter.md`

**Checkpoint**: Telegram behaves like a real working user channel rather than a one-shot demo.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Reconcile planning, docs, topology, and validation once the Telegram adapter is implemented.

- [ ] T034 [P] Run final planning artifact validation in `.specify/scripts/bash/check-prerequisites.sh` and reconcile `specs/023-telegram-factory-adapter/checklists/requirements.md`
- [ ] T035 [P] Refresh topology documentation in `docs/GIT-TOPOLOGY-REGISTRY.md`
- [ ] T036 Reconcile session handoff and current status in `SESSION_SUMMARY.md`
- [ ] T037 Run target Telegram adapter validation slices from `specs/023-telegram-factory-adapter/quickstart.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1: Setup** starts immediately after planning.
- **Phase 2: Foundational** depends on Phase 1 and blocks all Telegram user stories.
- **Phase 3: US1** is the MVP slice and depends on Phase 2.
- **Phase 4: US2** depends on US1 because brief review requires live Telegram discovery output.
- **Phase 5: US3** depends on US2 because downstream launch requires a confirmed brief.
- **Phase 6: US4** depends on US1 and US2 because resume and reopen operate on real session and brief state.
- **Phase 7: Polish** depends on all desired user stories.

### User Story Dependencies

- **US1 (P1)**: can start after the foundational phase.
- **US2 (P1)**: requires live adapter-driven discovery state from US1.
- **US3 (P2)**: requires confirmed brief behavior from US2.
- **US4 (P3)**: builds on the session and brief history created in US1 and US2.

### Parallel Opportunities

- `T002`, `T003`, and `T004` can run in parallel in Phase 1.
- `T005`, `T006`, and `T007` can run in parallel in Phase 2.
- `T011` and `T012` can run in parallel for US1 validation.
- `T017` and `T018` can run in parallel for US2 validation.
- `T023` and `T024` can run in parallel for US3 validation.
- `T030`, `T031`, and `T032` can run in parallel once the underlying adapter state exists.

## Implementation Strategy

### MVP First (User Story 1 + User Story 2)

1. Build the adapter foundations and normalized routing path.
2. Make Telegram a real discovery surface.
3. Add brief review and explicit confirmation inside Telegram.
4. Validate the user-facing experience before expanding downstream delivery.

### Incremental Delivery

1. Add adapter config, fixtures, and test wiring.
2. Add normalized Telegram routing and discovery delegation.
3. Add brief rendering, correction, confirmation, and reopen behavior.
4. Add automatic downstream launch and artifact delivery.
5. Add resume/status/live pilot coverage and final polish.

### Parallel Team Strategy

With multiple implementers:

- one stream owns `config/` plus `scripts/manifest.json`
- one stream owns `scripts/agent-factory-telegram-adapter.py`
- one stream owns `scripts/agent_factory_common.py` plus Telegram rendering rules
- one stream owns Telegram fixtures and tests
- one stream owns runbooks, quickstart reconciliation, and final topology/session handoff
