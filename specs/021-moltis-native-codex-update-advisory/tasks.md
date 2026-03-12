# Tasks: Moltis-Native Codex Update Advisory Flow

**Input**: Design documents from `/specs/021-moltis-native-codex-update-advisory/`  
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/advisory-event.schema.json, quickstart.md

## Phase 0: Planning (Executor Assignment)

- [x] P001 Confirm scope boundaries: repo-side producer only, Moltis-native Telegram owner in `specs/021-moltis-native-codex-update-advisory/tasks.md`
- [x] P002 Link the new feature package to tracker issue `moltinger-apm` and capture the architectural reason in `specs/021-moltis-native-codex-update-advisory/research.md`
- [x] P003 Retire the old Codex bridge entrypoint and document the temporary `one-way alert` production mode in `docs/codex-update-delivery.md` and `docs/codex-cli-upstream-watcher.md`

---

## Phase 1: Setup

- [x] T001 Validate and, if needed, extend the producer-to-Moltis advisory contract in `specs/021-moltis-native-codex-update-advisory/contracts/advisory-event.schema.json`
- [x] T002 [P] Create or update the migration/runbook documentation for the new ownership model in repository docs and Moltis-facing handoff notes
- [x] T003 [P] Add fixture samples for normalized advisory events in `tests/fixtures/`
- [x] T004 Create validation coverage for producer-side advisory event generation in `tests/component/`

---

## Phase 2: Foundational

- [x] T005 Implement producer-only advisory event emission in `scripts/codex-cli-upstream-watcher.sh`
- [x] T006 Implement or wire the Moltis-native advisory intake surface through repository-managed config/contracts in `config/moltis.toml` and related docs
- [x] T007 Add deterministic machine-readable interaction/audit record expectations for Moltis-native handling
- [x] T008 Create baseline verification coverage for one-way degraded behavior and event-contract validity

---

## Phase 3: User Story 1 - Moltis Owns The Telegram Alert (Priority: P1) MVP

**Goal**: A fresh Codex advisory reaches Telegram through Moltis as the sole Telegram owner.

**Independent Test**: Inject a normalized advisory event and confirm Moltis sends one Russian Telegram alert without asking the user to type `/codex_*`.

- [x] T010 [US1] Remove any remaining user-facing references to repo-side reply-command UX from runtime docs and prompts
- [x] T011 [US1] Implement Moltis-native alert rendering from the normalized advisory event
- [x] T012 [P] [US1] Add verification coverage for one-way and interactive-ready alert rendering
- [x] T013 [US1] Document the new ownership boundary for operators and future maintainers

---

## Phase 4: User Story 2 - Acceptance Sends Immediate Recommendations (Priority: P1)

**Goal**: A user accepts the Moltis alert and immediately gets practical recommendations in the same chat.

**Independent Test**: Press the inline accept action and confirm a second message with recommendations is sent promptly.

- [x] T020 [US2] Implement Moltis-native callback ownership for Codex advisory acceptance and decline
- [x] T021 [US2] Implement immediate follow-up recommendation delivery from Moltis
- [x] T022 [US2] Add idempotency and expiry handling for duplicate or stale callback actions
- [x] T023 [P] [US2] Add E2E coverage for `alert -> accept -> follow-up` and `alert -> decline`
- [x] T024 [US2] Add deep-link or tokenized fallback only as recovery, not as the primary UX

---

## Phase 5: User Story 3 - Degrade Safely And Audit End-To-End (Priority: P2)

**Goal**: Production stays honest when the interactive path is unavailable, and operators can audit one full interaction.

**Independent Test**: Disable callback routing and confirm Moltis sends a one-way alert with a recorded degraded reason.

- [ ] T030 [US3] Implement degraded one-way advisory mode inside Moltis-native flow
- [ ] T031 [US3] Implement audit records for alert, callback, and follow-up delivery
- [ ] T032 [P] [US3] Add live or hermetic acceptance coverage for degraded mode and full audit trail
- [ ] T033 [US3] Document rollback and safe-disable steps for the interactive advisory feature

---

## Phase 6: Polish & Cross-Cutting Concerns

- [ ] T040 [P] Sync bridge/runtime docs so Codex no longer advertises the retired repo-side skill
- [ ] T041 [P] Validate skill sync and discovery state after retiring the old bridge and adding the new plan artifacts
- [ ] T042 Validate contract/schema and targeted docs/config consistency
- [ ] T043 Run targeted validation and live-proof checklist
- [ ] T044 Update tracker status, related follow-up issues, and any topology or rollout docs if a dedicated branch/worktree is later created

## Dependencies & Execution Order

- Phase 1 -> Phase 2 -> Phase 3 -> Phase 4 -> Phase 5 -> Phase 6
- Phase 0 is already complete for package opening and bridge retirement.
- User Story 1 is the MVP because it fixes the ownership boundary first.
- User Story 2 depends on Moltis owning alert state and callbacks.
- User Story 3 depends on the interactive path existing so degraded mode and audit behavior are meaningful.

## Implementation Strategy

- First retire the broken repo-side bridge and keep production honest.
- Then formalize the producer contract from repo tooling to Moltis.
- Move Telegram alert ownership into Moltis before reintroducing any interactive follow-up.
- Add immediate recommendations only after callback ownership is proven.
- Keep `one-way alert` as the safe fallback at every stage.
