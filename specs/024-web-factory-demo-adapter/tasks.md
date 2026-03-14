# Tasks: Web Factory Demo Adapter

**Input**: Design documents from `/specs/024-web-factory-demo-adapter/`  
**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories), `research.md`, `data-model.md`, `contracts/`

**Tests**: Validation tasks are included because this slice introduces a new browser-facing demo surface, subdomain deploy path, browser session semantics, brief confirmation in UI, automatic downstream handoff, and downloadable concept-pack artifacts.

**Organization**: Tasks are grouped by user story so the browser demo can be delivered as independent slices while preserving the existing ownership boundary: `022` remains the discovery core, `020` remains the downstream factory core, `023` remains the follow-up Telegram transport scope, and `024` owns the primary web-first adapter plus demo deployment surface.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (e.g. `US1`, `US2`)
- Include exact file paths in descriptions

## Phase 0: Planning (Executor Assignment)

**Purpose**: Lock the web-first pivot and complete the planning package before runtime changes begin.

- [x] P001 Analyze the existing browser-test baseline, discovery runtime, and same-host subdomain deployment pattern for `specs/024-web-factory-demo-adapter/`
- [x] P002 Create and reconcile the active Speckit package in `specs/024-web-factory-demo-adapter/`
- [x] P003 Record the web-first pivot, deployment constraints, and Telegram follow-up positioning in `specs/024-web-factory-demo-adapter/research.md`
- [x] P004 Apply clarification updates so `024` is the primary demo path and `023` remains preserved follow-up scope

---

## Phase 1: Setup

**Purpose**: Establish web-demo-specific config, deployment, fixtures, and test wiring before foundational implementation starts.

- [x] T001 Update active web-demo adapter anchors and storage paths in `config/moltis.toml`
- [x] T002 [P] Create the same-host demo compose surface in `docker-compose.asc.yml`
- [x] T003 [P] Reconcile script descriptions and new browser-adapter entrypoints in `scripts/manifest.json`
- [x] T004 [P] Create the web-demo fixture tree in `tests/fixtures/agent-factory/web-demo/README.md`
- [x] T005 [P] Register web-demo suites in `tests/run.sh`

**Checkpoint**: The repo knows where the browser adapter lives, how it is deployed, where its fixtures go, and how its tests will run.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Add the shared web-demo plumbing that all browser user stories depend on.

**⚠️ CRITICAL**: No browser user story should be treated as complete until this phase is done.

- [ ] T006 [P] Create reusable web-demo session fixtures in `tests/fixtures/agent-factory/web-demo/session-new.json`
- [ ] T007 [P] Create component coverage for access gate and session routing in `tests/component/test_agent_factory_web_access.sh`
- [ ] T008 [P] Create local adapter flow coverage in `tests/integration_local/test_agent_factory_web_flow.sh`
- [ ] T009 [P] Implement the web adapter entrypoint and normalized browser envelope handling in `scripts/agent-factory-web-adapter.py`
- [ ] T010 [P] Extend shared browser render and status helpers in `scripts/agent_factory_common.py`
- [ ] T011 [P] Add the initial browser shell assets in `web/agent-factory-demo/index.html`, `web/agent-factory-demo/app.css`, and `web/agent-factory-demo/app.js`
- [ ] T012 Document operator flow and adapter storage layout in `docs/runbooks/agent-factory-web-demo.md`

**Checkpoint**: One browser turn can be gated, normalized, routed, and rendered through shared web-demo plumbing.

---

## Phase 3: User Story 1 - Live Web Discovery Interview (Priority: P1) 🎯 MVP

**Goal**: Let a business user open one browser URL and start the guided discovery interview there without Telegram, JSON, or CLI tools.

**Independent Test**: A raw browser turn opens a project, the adapter routes it into `scripts/agent-factory-discovery.py`, and the user receives the next business-analyst follow-up question in the same UI.

### Validation for User Story 1

- [ ] T013 [P] [US1] Create component coverage for browser discovery routing and user-safe rendering in `tests/component/test_agent_factory_web_discovery.sh`
- [ ] T014 [P] [US1] Create browser-flow coverage for `new project -> first follow-up question` in `tests/e2e_browser/agent_factory_web_demo.mjs`

### Implementation for User Story 1

- [ ] T015 [P] [US1] Extend `scripts/agent-factory-web-adapter.py` to open projects and route free-form browser turns into `scripts/agent-factory-discovery.py`
- [ ] T016 [P] [US1] Implement browser-readable discovery cards and status text in `scripts/agent_factory_common.py`
- [ ] T017 [US1] Add discovery conversation fixtures in `tests/fixtures/agent-factory/web-demo/session-discovery-answer.json`
- [ ] T018 [US1] Document live discovery UX and browser entry flow in `docs/runbooks/agent-factory-web-demo.md`

**Checkpoint**: The factory business-analyst agent is reachable by a real user through the browser for discovery.

---

## Phase 4: User Story 2 - Web Brief Review And Confirmation (Priority: P1)

**Goal**: Let the user review, correct, confirm, and reopen the requirements brief from inside the browser.

**Independent Test**: The user reaches `awaiting_confirmation`, sees a readable brief summary in the browser, asks for corrections conversationally, and explicitly confirms one exact brief version in the same UI.

### Validation for User Story 2

- [ ] T019 [P] [US2] Create component coverage for browser brief rendering and section chunking in `tests/component/test_agent_factory_web_brief.sh`
- [ ] T020 [P] [US2] Create integration coverage for browser correction and confirmation intents in `tests/integration_local/test_agent_factory_web_confirmation.sh`

### Implementation for User Story 2

- [ ] T021 [P] [US2] Extend `scripts/agent-factory-web-adapter.py` to support brief review, correction, confirm, and reopen actions
- [ ] T022 [P] [US2] Implement brief section rendering and confirmation prompts in `web/agent-factory-demo/app.js` and `scripts/agent_factory_common.py`
- [ ] T023 [US2] Add awaiting-confirmation fixtures in `tests/fixtures/agent-factory/web-demo/session-awaiting-confirmation.json`
- [ ] T024 [US2] Document browser brief confirmation and reopen behavior in `docs/runbooks/agent-factory-web-demo.md`

**Checkpoint**: The user can complete `discovery -> confirmed brief` fully inside the browser.

---

## Phase 5: User Story 3 - Automatic Handoff And Artifact Downloads (Priority: P2)

**Goal**: Turn browser confirmation into automatic downstream handoff, concept-pack generation, and browser downloads.

**Independent Test**: A confirmed browser brief launches the downstream handoff chain automatically, and the user downloads the 3 concept-pack artifacts from the same browser session without operator file handling.

### Validation for User Story 3

- [ ] T025 [P] [US3] Create component coverage for downstream orchestration and download sanitization in `tests/component/test_agent_factory_web_delivery.sh`
- [ ] T026 [P] [US3] Create integration coverage for `confirmed brief -> downloadable artifacts` in `tests/integration_local/test_agent_factory_web_handoff.sh`

### Implementation for User Story 3

- [ ] T027 [P] [US3] Extend `scripts/agent-factory-web-adapter.py` to invoke `scripts/agent-factory-intake.py` and `scripts/agent-factory-artifacts.py` automatically after confirmation
- [ ] T028 [P] [US3] Add browser download endpoints and safe delivery metadata in `scripts/agent-factory-web-adapter.py` and `web/agent-factory-demo/app.js`
- [ ] T029 [US3] Reconcile delivery and provenance fields in `scripts/agent-factory-intake.py` and `scripts/agent-factory-artifacts.py`
- [ ] T030 [US3] Document concept-pack browser delivery and failure messaging in `docs/runbooks/agent-factory-web-demo.md` and `docs/runbooks/agent-factory-prototype.md`

**Checkpoint**: The browser demo becomes the full user-facing path from confirmation to concept-pack download.

---

## Phase 6: User Story 4 - Controlled Subdomain Demo Access (Priority: P2)

**Goal**: Let the operator publish a reliable browser demo surface on a dedicated subdomain with minimal controlled access.

**Independent Test**: The operator deploys the web-demo stack on the target subdomain, sees a healthy demo surface, and business users can open the entry URL without Telegram/VPN friction.

### Validation for User Story 4

- [ ] T031 [P] [US4] Create component coverage for access-gate and health projection behavior in `tests/component/test_agent_factory_web_access.sh`
- [ ] T032 [P] [US4] Create remote demo smoke coverage in `tests/live_external/test_web_factory_demo_smoke.sh`

### Implementation for User Story 4

- [ ] T033 [P] [US4] Extend `scripts/deploy.sh` and `docker-compose.asc.yml` to support the dedicated web-demo target
- [ ] T034 [P] [US4] Add demo-access and health/status publication behavior in `scripts/agent-factory-web-adapter.py`
- [ ] T035 [US4] Document subdomain rollout, access gate, and smoke procedure in `docs/runbooks/agent-factory-web-demo.md`

**Checkpoint**: The web-first adapter is a publishable demo surface rather than only a local browser fixture.

---

## Phase 7: User Story 5 - Resume And Reopen In Browser (Priority: P3)

**Goal**: Let the user resume an interrupted browser conversation, inspect current status, and reopen a confirmed brief without losing provenance.

**Independent Test**: After pausing mid-discovery or after a confirmed brief already exists, the user can refresh or return later, continue the same project, inspect status, or reopen the brief while history remains intact.

### Validation for User Story 5

- [ ] T036 [P] [US5] Create integration coverage for resume and reopen in `tests/integration_local/test_agent_factory_web_resume.sh`
- [ ] T037 [P] [US5] Extend browser-flow coverage for refresh continuity in `tests/e2e_browser/agent_factory_web_demo.mjs`

### Implementation for User Story 5

- [ ] T038 [P] [US5] Extend `scripts/agent-factory-web-adapter.py` to persist active project pointers and resume context under `data/agent-factory/web-demo/`
- [ ] T039 [P] [US5] Extend `web/agent-factory-demo/app.js` and `scripts/agent_factory_common.py` with resume/status and reopened-brief projections
- [ ] T040 [US5] Document resume, status, and reopen behavior in `docs/runbooks/agent-factory-web-demo.md`

**Checkpoint**: The browser demo behaves like a real working user channel rather than a one-shot presentation.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Reconcile planning, docs, topology, and validation once the web demo is implemented.

- [ ] T041 [P] Run final planning artifact validation in `.specify/scripts/bash/check-prerequisites.sh` and reconcile `specs/024-web-factory-demo-adapter/checklists/requirements.md`
- [ ] T042 [P] Refresh topology documentation in `docs/GIT-TOPOLOGY-REGISTRY.md`
- [ ] T043 Reconcile session handoff and current status in `SESSION_SUMMARY.md`
- [ ] T044 Run target web-demo validation slices from `specs/024-web-factory-demo-adapter/quickstart.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1: Setup** starts immediately after planning.
- **Phase 2: Foundational** depends on Phase 1 and blocks all browser user stories.
- **Phase 3: US1** is the MVP slice and depends on Phase 2.
- **Phase 4: US2** depends on US1 because brief review requires live browser discovery output.
- **Phase 5: US3** depends on US2 because downstream launch requires a confirmed brief.
- **Phase 6: US4** depends on Phase 2 and should be complete before remote demo rollout.
- **Phase 7: US5** depends on US1 and US2 because resume and reopen operate on real session and brief state.
- **Phase 8: Polish** depends on all desired user stories.

### User Story Dependencies

- **US1 (P1)**: can start after the foundational phase.
- **US2 (P1)**: requires live adapter-driven discovery state from US1.
- **US3 (P2)**: requires confirmed brief behavior from US2.
- **US4 (P2)**: requires the foundational adapter surface and deployment wiring.
- **US5 (P3)**: builds on the session and brief history created in US1 and US2.

### Parallel Opportunities

- `T002`, `T003`, `T004`, and `T005` can run in parallel in Phase 1.
- `T006`, `T007`, and `T008` can run in parallel in Phase 2.
- `T013` and `T014` can run in parallel for US1 validation.
- `T019` and `T020` can run in parallel for US2 validation.
- `T025` and `T026` can run in parallel for US3 validation.
- `T031` and `T032` can run in parallel for US4 validation.
- `T036` and `T037` can run in parallel for US5 validation.

## Implementation Strategy

### MVP First (User Story 1 + User Story 2)

1. Build the access, session, and browser-shell foundations.
2. Make the browser a real discovery surface.
3. Add brief review and explicit confirmation in-browser.
4. Validate the user-facing experience before expanding download and remote demo rollout.

### Incremental Delivery

1. Add adapter config, compose surface, fixtures, and test wiring.
2. Add browser session access and discovery delegation.
3. Add brief rendering, correction, confirmation, and reopen behavior.
4. Add automatic downstream launch and browser downloads.
5. Add subdomain rollout, resume coverage, and final polish.

### Parallel Team Strategy

With multiple implementers:

- one stream owns `docker-compose.asc.yml`, `scripts/deploy.sh`, and rollout/runbook work
- one stream owns `scripts/agent-factory-web-adapter.py`
- one stream owns browser assets under `web/agent-factory-demo/`
- one stream owns `scripts/agent_factory_common.py` plus UI rendering projections
- one stream owns fixtures and tests across component/integration/browser/live smoke
