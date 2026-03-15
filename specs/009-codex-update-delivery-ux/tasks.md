# Tasks: Codex Update Delivery UX

**Input**: Design documents from `/specs/009-codex-update-delivery-ux/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/delivery-report.schema.json, quickstart.md

## Phase 0: Planning (Executor Assignment)

- [x] P001 Confirm implementation branch/spec pairing and delivery UX scope boundaries in `specs/009-codex-update-delivery-ux/tasks.md`
- [x] P002 Validate local prerequisites for advisor reuse, launcher integration, and optional Telegram delivery in `specs/009-codex-update-delivery-ux/research.md`
- [x] P003 Start MVP delivery with User Story 1 only after executor assignment and prerequisite validation

---

## Phase 1: Setup

- [x] T001 Create the delivery script skeleton in `scripts/codex-cli-update-delivery.sh`
- [x] T002 [P] Create the operator runbook in `docs/codex-update-delivery.md`
- [x] T003 [P] Create fixed delivery fixtures in `tests/fixtures/codex-update-delivery/`
- [x] T004 Create the component test skeleton in `tests/component/test_codex_cli_update_delivery.sh`
- [x] T005 Register the delivery script in `scripts/manifest.json`

---

## Phase 2: Foundational

- [x] T006 Implement advisor-report intake and shared delivery-state handling in `scripts/codex-cli-update-delivery.sh`
- [x] T007 Implement deterministic JSON generation matching `specs/009-codex-update-delivery-ux/contracts/delivery-report.schema.json` in `scripts/codex-cli-update-delivery.sh`
- [x] T008 Implement per-surface delivery decision logic in `scripts/codex-cli-update-delivery.sh`
- [x] T009 Create baseline component validation coverage in `tests/component/test_codex_cli_update_delivery.sh`

---

## Phase 3: User Story 1 - User Asks In Plain Language And Gets The Report (Priority: P1) MVP

**Goal**: Let a user request the current Codex update status in plain language instead of composing script flags.

**Independent Test**: Trigger the Codex-facing wrapper and confirm it returns a short readable result driven by the delivery script.

- [x] T010 [US1] Implement plain-language on-demand summary mode in `scripts/codex-cli-update-delivery.sh`
- [x] T011 [US1] Add a Codex-facing command or skill wrapper in `.claude/commands/codex-update.md` and/or `.claude/skills/codex-update-delivery/`
- [x] T012 [P] [US1] Add fixture-backed wrapper tests in `tests/component/test_codex_cli_update_delivery.sh`
- [x] T013 [US1] Document the user-facing request flow in `docs/codex-update-delivery.md`

---

## Phase 4: User Sees An Alert When Launching Codex (Priority: P1)

**Goal**: Surface a short fresh-update alert at Codex startup without blocking launch.

**Independent Test**: Launch through the repo launcher with a fresh actionable fixture and confirm the alert prints before Codex starts. Confirm launch still proceeds when the check fails.

- [x] T020 [US2] Implement launcher-alert mode in `scripts/codex-cli-update-delivery.sh`
- [x] T021 [US2] Integrate non-blocking pre-session delivery checks into `scripts/codex-profile-launch.sh`
- [x] T022 [P] [US2] Add launcher alert and fail-open coverage in `tests/component/test_codex_cli_update_delivery.sh`
- [x] T023 [US2] Document launch-time alert behavior in `docs/codex-update-delivery.md`
- [x] T024 [US2] Add optional background Telegram delivery at launch in `scripts/codex-profile-launch.sh` and `tests/component/test_codex_profile_launch.sh`

---

## Phase 5: User Gets Telegram Notification Through Moltinger (Priority: P2)

**Goal**: Deliver one concise Telegram message for fresh actionable updates using the existing bot send path.

**Independent Test**: Run Telegram delivery with a mocked sender and confirm one message is sent for a fresh actionable update and duplicates are suppressed.

- [x] T030 [US3] Implement Telegram delivery mode and target configuration in `scripts/codex-cli-update-delivery.sh`
- [x] T031 [US3] Reuse `scripts/telegram-bot-send.sh` for Telegram transport from the delivery flow
- [x] T032 [P] [US3] Add Telegram delivery and duplicate-suppression tests in `tests/component/test_codex_cli_update_delivery.sh`
- [x] T033 [US3] Document Telegram setup and safety boundaries in `docs/codex-update-delivery.md`
- [x] T034 [US3] Add the remote transport bridge in `scripts/telegram-bot-send-remote.sh` and `tests/component/test_telegram_bot_send_remote.sh`

---

## Phase 6: Delivery State Stays Coherent Across Surfaces (Priority: P3)

**Goal**: Keep on-demand, launcher, and Telegram surfaces coordinated through one delivery state model.

**Independent Test**: Exercise multiple surfaces against one fingerprint and confirm each surface records delivered, suppressed, or retryable state correctly.

- [x] T040 [US4] Implement per-surface state persistence and retry-safe updates in `scripts/codex-cli-update-delivery.sh`
- [x] T041 [US4] Add cross-surface state coherence tests in `tests/component/test_codex_cli_update_delivery.sh`
- [x] T042 [US4] Document shared-state semantics and future scheduler compatibility in `docs/codex-update-delivery.md`

---

## Phase 7: Polish & Cross-Cutting Concerns

- [x] T050 [P] Add a convenient make target in `Makefile`
- [x] T051 [P] Validate Bash syntax for `scripts/codex-cli-update-delivery.sh` and referenced tests
- [x] T052 Run targeted component validation for `tests/component/test_codex_cli_update_delivery.sh`
- [x] T053 Verify delivery docs, command or skill wrappers, and launcher integration stay aligned
- [x] T054 Update `docs/GIT-TOPOLOGY-REGISTRY.md` for the new `009-codex-update-delivery-ux` worktree
- [x] T055 Validate launcher-triggered Telegram automation and script inventory alignment
## Dependencies & Execution Order

- Phase 1 -> Phase 2 -> Phase 3 -> Phase 4 -> Phase 5 -> Phase 6 -> Phase 7
- User Story 1 is the MVP and must land before launcher or Telegram delivery work.
- User Story 2 depends on the stable delivery report and shared state logic from Phases 2 and 3.
- User Story 3 depends on stable delivery state so Telegram does not duplicate alerts.
- User Story 4 depends on earlier surfaces existing so cross-surface coherence can be validated.
