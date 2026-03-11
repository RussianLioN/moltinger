# Tasks: Codex Telegram Consent Routing

**Input**: Design documents from `/specs/017-codex-telegram-consent-routing/`  
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/consent-store-record.schema.json, quickstart.md

## Phase 0: Planning (Executor Assignment)

- [x] P001 Confirm the feature scope: authoritative Telegram consent routing, not another watcher-side polling workaround
- [x] P002 Validate current runtime constraints across `config/moltis.toml`, watcher consent flow, Telegram docs, and E2E harnesses
- [x] P003 Prepare a Speckit package that turns consilium findings into executable implementation slices

---

## Phase 1: Setup

- [x] T001 Create the consent router runtime skeleton in `scripts/moltis-codex-consent-router.sh`
- [x] T002 [P] Create the shared consent-store helper skeleton in `scripts/codex-telegram-consent-store.sh`
- [x] T003 [P] Create fixture inputs under `tests/fixtures/codex-telegram-consent-routing/`
- [x] T004 Create the component test skeleton in `tests/component/test_moltis_codex_consent_router.sh`
- [x] T005 Register new scripts and env contracts in `scripts/manifest.json`
- [x] T006 Add operator documentation skeleton updates in `docs/codex-cli-upstream-watcher.md` and `docs/telegram-e2e-on-demand.md`

---

## Phase 2: Foundational

- [x] T007 Extend `scripts/telegram-bot-send.sh` and `scripts/telegram-bot-send-remote.sh` to support explicit inline reply markup payloads
- [x] T008 Implement the authoritative consent-store contract matching `specs/017-codex-telegram-consent-routing/contracts/consent-store-record.schema.json`
- [x] T009 Wire the main Moltis Telegram ingress surface in `config/moltis.toml` and related runtime glue so consent actions reach the authoritative router instead of only the generic chat path
- [x] T010 Add baseline component validation for store parsing, action-token validation, expiry handling, and duplicate suppression

---

## Phase 3: User Story 1 - Main Telegram Ingress Owns Consent Replies (Priority: P1) MVP

**Goal**: A Codex consent reply is handled authoritatively by the main Moltis Telegram ingress and does not fall through to the generic bot dialog.

**Independent Test**: Open a pending consent request, submit a valid callback or structured fallback command, and confirm the authoritative router records the decision while generic bot handling is suppressed or replaced contextually.

- [x] T011 [US1] Update `scripts/codex-cli-upstream-watcher.sh` so consent-capable alerts emit a request id, action token, and explicit action affordances instead of only free-text `да/нет`
- [x] T012 [US1] Implement callback/fallback-command matching and validation in `scripts/moltis-codex-consent-router.sh`
- [x] T013 [US1] Persist authoritative decision state in `scripts/codex-telegram-consent-store.sh`
- [x] T014 [P] [US1] Add fixture-backed component tests for callback routing, command fallback, expired tokens, and invalid chat/context handling
- [x] T015 [US1] Document the authoritative routing behavior and fallback semantics in `docs/codex-cli-upstream-watcher.md`

---

## Phase 4: User Story 2 - Recommendations Arrive Immediately After Consent (Priority: P1)

**Goal**: After acceptance, the user receives practical recommendations promptly in the same chat, without waiting for a later watcher scheduler pass.

**Independent Test**: Accept a valid consent request through the authoritative router and confirm the second recommendation message is sent once, while decline closes the state without sending it.

- [x] T020 [US2] Implement immediate follow-up recommendation delivery from the authoritative runtime path
- [x] T021 [US2] Make acceptance and decline idempotent in the shared consent store
- [x] T022 [P] [US2] Add component coverage for accept, decline, duplicate accept, and follow-up send failure/retry behavior
- [x] T023 [US2] Update watcher output so it advertises consent only when the authoritative router is available
- [x] T024 [US2] Document the immediate follow-up behavior and operator expectations

---

## Phase 5: User Story 3 - Live Acceptance And Safe Fallback (Priority: P2)

**Goal**: Operators can validate the real Telegram path end-to-end, and unhealthy consent routing cleanly degrades to a one-way alert.

**Independent Test**: Run a live or hermetic end-to-end scenario `alert -> consent action -> recommendations` plus a degraded scenario where the router is unavailable and the alert becomes one-way only.

- [ ] T030 [US3] Extend `scripts/telegram-e2e-on-demand.sh` and/or related helpers with a Codex-specific acceptance path
- [ ] T031 [US3] Add a live-acceptance or hermetic-equivalent contract for the scenario `alert -> consent -> recommendations`
- [ ] T032 [P] [US3] Add degraded-mode coverage proving the watcher falls back to one-way alerts without a misleading question
- [ ] T033 [US3] Document rollout, rollback, and observability steps in `docs/codex-cli-upstream-watcher.md` and `docs/telegram-e2e-on-demand.md`

---

## Phase 6: Polish & Cross-Cutting Concerns

- [ ] T040 [P] Add make targets or helper entrypoints for consent-router validation
- [ ] T041 [P] Validate Bash syntax for the new scripts and updated Telegram sender helpers
- [ ] T042 Run targeted component validation for consent router and Codex watcher regressions
- [ ] T043 Run the chosen E2E acceptance path and capture operator-facing evidence
- [ ] T044 Verify docs, runtime config, and contract schema stay aligned
- [ ] T045 Update `docs/GIT-TOPOLOGY-REGISTRY.md` if a dedicated branch/worktree is created for this feature

## Dependencies & Execution Order

- Phase 1 -> Phase 2 -> Phase 3 -> Phase 4 -> Phase 5 -> Phase 6
- User Story 1 is the MVP because it fixes the ownership bug.
- User Story 2 depends on authoritative routing and shared consent state from User Story 1.
- User Story 3 depends on both routing and immediate follow-up delivery existing first.

## Implementation Strategy

- First make inbound ownership correct.
- Then make the second message immediate and idempotent.
- Only after that declare the live UX fixed via end-to-end acceptance.
