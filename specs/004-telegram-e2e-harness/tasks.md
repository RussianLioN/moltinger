# Tasks: On-Demand Telegram E2E Harness

**Input**: Design documents from `/specs/004-telegram-e2e-harness/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

## Phase 0: Planning (Executor Assignment)

- [x] P001 Analyze tasks and assign executors for all phases
- [x] P002 Resolve remaining research/contract ambiguities
- [x] P003 Prepare Beads import structure and dependency map
- [x] P004 Start first implementation scope (US1)

---

## Phase 1: Setup

- [x] T001 Create CLI skeleton in `scripts/telegram-e2e-on-demand.sh`
- [x] T002 Create workflow skeleton in `.github/workflows/telegram-e2e-on-demand.yml`
- [x] T003 Create runbook in `docs/telegram-e2e-on-demand.md`

---

## Phase 2: Foundational

- [x] T004 Implement shared Moltis auth flow in `scripts/telegram-e2e-on-demand.sh`
- [x] T005 Implement response polling/capture flow in `scripts/telegram-e2e-on-demand.sh`
- [x] T006 Implement structured JSON report writer in `scripts/telegram-e2e-on-demand.sh`
- [x] T007 Implement redaction/safe logging behavior in `scripts/telegram-e2e-on-demand.sh`

---

## Phase 3: User Story 1 - On-Demand Synthetic E2E (P1)

- [x] T010 [US1] Implement full synthetic execution path in `scripts/telegram-e2e-on-demand.sh`
- [x] T011 [US1] Implement CLI argument contract and exit codes in `scripts/telegram-e2e-on-demand.sh`
- [x] T012 [US1] Add synthetic quickstart commands to `docs/telegram-e2e-on-demand.md`
- [x] T013 [US1] Add workflow artifact upload and script invocation in `.github/workflows/telegram-e2e-on-demand.yml`
- [x] T014 [US1] Validate synthetic smoke flow and capture sample artifact schema

---

## Phase 4: User Story 2 - Dual Trigger Interface (P2)

- [x] T020 [US2] Align CLI/workflow parameter names and defaults
- [x] T021 [US2] Ensure workflow and CLI emit identical schema fields
- [x] T022 [US2] Add trigger_source parity handling (`cli`/`workflow_dispatch`)
- [x] T023 [US2] Add workflow usage examples to runbook
- [x] T024 [US2] Validate parity with one local and one workflow dispatch run

---

## Phase 5: User Story 3 - Real User MTProto Execution (P3)

- [x] T030 [US3] Add `real_user` mode execution path via MTProto
- [x] T031 [US3] Add prerequisite validation for `TELEGRAM_TEST_*` secrets
- [x] T032 [US3] Return structured runtime/precondition diagnostics
- [x] T033 [US3] Document real_user setup and execution path

---

## Phase 6: User Story 4 - Live Operability Regression Pack (P2)

- [x] T034 [US4] Reconcile deferred-vs-live `real_user` history in `specs/004-telegram-e2e-harness/spec.md` and `specs/004-telegram-e2e-harness/tasks.md`
- [x] T035 [US4] Extend `tests/live_external/test_telegram_external_smoke.sh` to execute the synthetic Moltis harness against the authoritative live target
- [x] T036 [US4] Extend `tests/live_external/test_telegram_external_smoke.sh` to execute `real_user` MTProto verification and assert redaction boundaries
- [x] T037 [US4] Document the full Moltis operability verification set in `docs/telegram-e2e-on-demand.md`
- [x] T038 [US4] Run targeted validation for the updated docs, helper diagnostics, and live-suite skip wiring

---

## Final Phase: Polish & Cross-Cutting

- [x] T040 Add script metadata to `scripts/manifest.json`
- [x] T041 Update secrets/docs references for on-demand e2e
- [x] T042 Run unit/integration quality gates for non-regression
- [x] T043 Update Beads issue notes with implementation progress
- [x] T044 Prepare merge-ready summary and operational handoff

---

## Dependencies & Execution Order

- Phase 1 -> Phase 2 -> Phase 3 -> Phase 4 -> Phase 5 -> Phase 6 -> Final Phase
- US2 depends on US1 artifact schema and invocation path
- US3 depends on established report/error framework from US1/US2
- US4 depends on working US3 execution plus the existing live-only lane boundary
