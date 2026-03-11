# Tasks: Production-Aware Remote UAT Hardening

**Input**: Design documents from `/specs/011-remote-uat-hardening/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/, quickstart.md

**Tests**: Acceptance proof for this feature is based on comparable before/after artifacts, deterministic component coverage for Telegram Web failure classes, and verification that production guardrails remain intact.

**Organization**: Tasks are grouped by operator value. The critical path is: review current baseline, lock security and operational guardrails, establish the authoritative verdict contract, harden Telegram Web diagnostics, then keep MTProto only as an explicit secondary cross-check.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (`US1`, `US2`, `US3`, `US4`)
- Include exact file paths in descriptions

## Phase 0: Review / Re-baseline

**Purpose**: Freeze what is already shipped in `main`, capture the current production-aware gap, and convert the package from generic planning into a precise delta backlog.

- [X] T001 Compare the shipped baseline for `synthetic`, `real_user`, and standalone Telegram Web paths in `specs/011-remote-uat-hardening/quickstart.md`
- [X] T002 Capture the current failing production-aware Telegram Web artifact and execution notes in `tests/fixtures/telegram-web/`
- [X] T003 Document the schema delta between the current `telegram-e2e-result.json` output and the target contract in `specs/011-remote-uat-hardening/contracts/remote-uat-contract.md`
- [X] T004 Rewrite the implementation delta summary and acceptance proof section in `specs/011-remote-uat-hardening/plan.md`

---

## Phase 1: Security & Operational Guardrails

**Purpose**: Block unsafe operational defaults before any authoritative production-aware path is promoted.

**CRITICAL**: No user story work should begin until these guardrails are defined and enforced.

- [X] T005 Add operator-safe artifact and restricted debug-bundle separation in `scripts/telegram-e2e-on-demand.sh`
- [X] T006 [P] Narrow `TELEGRAM_TEST_*` secret exposure and step scope in `.github/workflows/telegram-e2e-on-demand.yml`
- [X] T007 [P] Add concurrency and manual-use serialization guards for the shared production target in `.github/workflows/telegram-e2e-on-demand.yml`
- [X] T008 Add Telegram Web state handling, storage, and break-glass guidance in `docs/TELEGRAM-WEB-USER-MONITOR.md`
- [X] T009 [P] Add secret/state redaction and no-leak coverage in `tests/component/`
- [X] T010 Verify scheduler-disable and polling-preservation guardrails in `.github/workflows/deploy.yml`

**Checkpoint**: Production guardrails are enforceable, not just documented.

---

## Phase 2: User Story 1 - Decision-Grade Post-Deploy Verdict (Priority: P1) MVP

**Goal**: Give operators one manual post-deploy run that produces a trustworthy verdict for the real Telegram user path.

**Independent Test**: Run the authoritative production-aware check after deploy and receive one comparable artifact with a clear verdict, run context, and next-step guidance.

- [X] T011 [US1] Promote the authoritative Telegram Web run path in `scripts/telegram-e2e-on-demand.sh`
- [X] T012 [US1] Convert `.github/workflows/telegram-e2e-on-demand.yml` into a single authoritative operator entrypoint in `.github/workflows/telegram-e2e-on-demand.yml`
- [X] T013 [US1] Implement the canonical verdict artifact structure in `scripts/telegram-e2e-on-demand.sh`
- [X] T014 [US1] Add operator-facing `recommended_action` output in `scripts/telegram-e2e-on-demand.sh`
- [X] T015 [US1] Capture comparable before/after authoritative run artifacts in `tests/fixtures/telegram-web/`

**Checkpoint**: The operator gets one authoritative post-deploy verdict rather than multiple loosely related run modes.

---

## Phase 3: User Story 2 - Deterministic Diagnostics and Attribution (Priority: P1)

**Goal**: Make failing runs actionable by normalizing failure classes, stage reporting, and fail-closed attribution.

**Independent Test**: Reproduce the Telegram Web failure classes and verify that each failed artifact identifies the stage, failure code, attribution state, and review-safe context.

- [X] T016 [P] [US2] Normalize failure taxonomy and attribution output in `scripts/telegram-web-user-probe.mjs`
- [X] T017 [P] [US2] Extend component coverage for `missing_session_state`, `ui_drift`, `chat_open_failure`, `stale_chat_noise`, `send_failure`, and `bot_no_response` in `tests/component/test_telegram_web_probe_correlation.sh`
- [X] T018 [US2] Wire normalized Telegram Web execution signals into the canonical wrapper in `scripts/telegram-e2e-on-demand.sh`
- [X] T019 [US2] Separate operator-safe artifact fields from debug-only diagnostics in `scripts/telegram-e2e-on-demand.sh`

**Checkpoint**: Any red run is deterministic, review-safe, and usable for RCA without guesswork.

---

## Phase 4: User Story 4 - Manual Operator Workflow and Proof of Value (Priority: P2)

**Goal**: Align the actual workflow, documentation, and acceptance evidence with the final authoritative verdict path.

**Independent Test**: An operator can follow one documented post-deploy flow from deploy completion to verdict review to rerun, without undocumented steps or CI confusion.

- [X] T020 [US4] Update the final operator workflow and rerun guidance in `docs/telegram-e2e-on-demand.md`
- [X] T021 [P] [US4] Align clean-deploy verification guidance with the authoritative Telegram Web path in `docs/CLEAN-DEPLOY-TELEGRAM-WEB-USER-MONITOR.md`
- [X] T022 [P] [US4] Align quick reference wording with the final manual-only workflow in `docs/QUICK-REFERENCE.md`
- [X] T023 [US4] Record the acceptance-proof checklist and before/after evidence model in `specs/011-remote-uat-hardening/quickstart.md`

**Checkpoint**: The user-facing value is documented as one reliable operator workflow, not a set of scripts.

---

## Phase 5: User Story 3 - Secondary MTProto Cross-Check (Priority: P2)

**Goal**: Keep MTProto available only as an explicit secondary diagnostic path after the primary verdict is known.

**Independent Test**: After the authoritative Telegram Web verdict, an operator can opt into MTProto cross-checking without replacing the primary verdict or widening the default production surface.

- [X] T024 [US3] Reframe MTProto as explicit secondary diagnostics in `.github/workflows/telegram-e2e-on-demand.yml`
- [X] T025 [P] [US3] Tighten MTProto prerequisite and secret handling in `scripts/telegram-real-user-e2e.py`
- [X] T026 [US3] Add `fallback_assessment` and secondary-diagnostic decision support to `scripts/telegram-e2e-on-demand.sh`

**Checkpoint**: MTProto remains available as a controlled cross-check, not as a competing primary path.

---

## Phase 6: Polish & Verification

**Purpose**: Close the loop with proof that the change improved operator outcomes and preserved production boundaries.

- [X] T027 [P] Run final component regression for `tests/component/test_telegram_web_probe_correlation.sh`
- [X] T028 [P] Verify no-regression for scheduler-disable and polling-preservation behavior in `.github/workflows/deploy.yml`
- [X] T029 Run the final manual authoritative rerun and store the acceptance evidence in `tests/fixtures/telegram-web/`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 0: Review / Re-baseline** has no prerequisites and must complete first.
- **Phase 1: Security & Operational Guardrails** depends on Phase 0 and blocks all feature delivery.
- **Phase 2: US1** depends on Phase 1 and defines the MVP.
- **Phase 3: US2** depends on US1 because deterministic diagnostics harden the authoritative verdict path.
- **Phase 4: US4** depends on US1 and US2 because docs and acceptance proof must reflect the final workflow and artifact contract.
- **Phase 5: US3** depends on US1 and US2 because MTProto is only a secondary diagnostic after the primary verdict exists.
- **Phase 6: Polish** depends on all desired user stories being complete.

### User Story Dependencies

- **US1**: First delivery target after guardrails.
- **US2**: Depends on authoritative artifact ownership and Telegram Web execution wiring from US1.
- **US4**: Depends on the final verdict and diagnostics behavior from US1 and US2.
- **US3**: Depends on the final primary verdict semantics from US1 and US2.

### Parallel Opportunities

- `T006`, `T007`, `T008`, and `T009` can run in parallel after the guardrail phase starts.
- `T016` and `T017` can run in parallel during deterministic-diagnostics work.
- `T021` and `T022` can run in parallel during workflow/doc alignment.
- `T024` and `T025` can run in parallel during secondary-diagnostics work.
- `T027` and `T028` can run in parallel during final verification.

---

## Parallel Example: Guardrails

```bash
Task: "Narrow TELEGRAM_TEST_* secret exposure and step scope in .github/workflows/telegram-e2e-on-demand.yml"
Task: "Add concurrency and manual-use serialization guards for the shared production target in .github/workflows/telegram-e2e-on-demand.yml"
Task: "Add secret/state redaction and no-leak coverage in tests/component/"
```

## Parallel Example: Diagnostics

```bash
Task: "Normalize failure taxonomy and attribution output in scripts/telegram-web-user-probe.mjs"
Task: "Extend component coverage for missing_session_state, ui_drift, chat_open_failure, stale_chat_noise, send_failure, and bot_no_response in tests/component/test_telegram_web_probe_correlation.sh"
```

## Implementation Strategy

### MVP First

1. Complete Review / Re-baseline.
2. Complete Security & Operational Guardrails.
3. Complete User Story 1.
4. Complete User Story 2.
5. Validate the authoritative Telegram Web path with comparable before/after artifacts.

### Incremental Delivery

1. Establish one decision-grade operator verdict.
2. Make every red run deterministic and review-safe.
3. Align the operator workflow and proof of value.
4. Add MTProto only as a controlled secondary diagnostic path.
