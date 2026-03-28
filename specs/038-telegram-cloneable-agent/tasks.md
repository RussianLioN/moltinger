# Tasks: Telegram Cloneable Agent

**Input**: Design documents from `/specs/038-telegram-cloneable-agent/`  
**Prerequisites**: `spec.md`, `plan.md`

## Phase 0: Research And Package Baseline

- [x] T001 Confirm current lane/worktree reuse and package id `038` in `specs/038-telegram-cloneable-agent/`
- [x] T002 Review the provided research source and supplement it with additional official/community evidence in `specs/038-telegram-cloneable-agent/spec.md` and `specs/038-telegram-cloneable-agent/plan.md`
- [x] T003 Create the Speckit artifacts and checklist in `specs/038-telegram-cloneable-agent/spec.md`, `specs/038-telegram-cloneable-agent/plan.md`, `specs/038-telegram-cloneable-agent/tasks.md`, and `specs/038-telegram-cloneable-agent/checklists/requirements.md`

## Phase 1: Setup

- [ ] T010 Create the cloneable-agent runbook skeleton in `docs/runbooks/moltis-telegram-cloneable-agent.md`
- [ ] T011 [P] Create the reusable worker-lane skill template skeleton in `skills/telegram-cloneable-agent/SKILL.md`
- [ ] T012 [P] Create the reusable version-watch skill template skeleton in `skills/telegram-version-watch/SKILL.md`
- [ ] T013 [P] Create fixture inputs for long-running Telegram scenarios in `tests/fixtures/telegram-cloneable-agent/`

## Phase 2: Foundational Contracts

- [ ] T020 Define lane separation, durable-state pointers, and base delivery settings in `config/moltis.toml`
- [ ] T021 Define the durable job/monitor state contract and route-context schema in `docs/runbooks/moltis-telegram-cloneable-agent.md`
- [ ] T022 Create the explicit completion-delivery rule in `docs/rules/moltis-telegram-cloneable-agents-must-use-explicit-completion-delivery.md`
- [ ] T023 Create the base component harness for cloneable-agent contracts in `tests/component/test_telegram_cloneable_agent_contract.sh`

## Phase 3: User Story 1 - Telegram Safely Hands Off Heavy Work (Priority: P1) 🎯 MVP

**Goal**: Make the Telegram entry lane fast, safe, and incapable of leaking `Activity log` while heavy work moves to a background worker.

**Independent Test**: Send heavy-task fixtures through the contract harness and confirm quick ack, background handoff, and no raw tool/progress leakage in the user-facing reply.

- [ ] T030 [US1] Implement quick-ack and safe user-facing lane guidance in `config/moltis.toml`
- [ ] T031 [US1] Document Telegram user-lane behavior, allowed surfaces, and failure semantics in `docs/runbooks/moltis-telegram-cloneable-agent.md`
- [ ] T032 [P] [US1] Add fixture-backed tests for quick ack and no-`Activity log` leakage in `tests/component/test_telegram_cloneable_agent_contract.sh`

## Phase 4: User Story 2 - Completion Delivery Is Explicit And Reliable (Priority: P1)

**Goal**: Deliver final completion or failure as an explicit outbound operation that survives the end of the original Telegram turn.

**Independent Test**: Simulate delayed completion and broken primary reply routing, then confirm one explicit completion or failure message still reaches the saved Telegram route.

- [ ] T040 [US2] Wire explicit completion-delivery guidance and direct-send fallback into `config/moltis.toml`
- [ ] T041 [US2] Reuse `scripts/telegram-bot-send.sh` in the runbook and define persisted route/account/thread context in `docs/runbooks/moltis-telegram-cloneable-agent.md`
- [ ] T042 [P] [US2] Add delivery-loss and fallback regression coverage in `tests/component/test_telegram_cloneable_agent_contract.sh`

## Phase 5: User Story 3 - Version Watch Template Uses Durable State Instead Of Chat History (Priority: P1)

**Goal**: Provide a practical, cloneable template for “watch for a new version and notify the user” with duplicate-safe durable state.

**Independent Test**: Run the template against “new version”, “same version”, and “source failure” fixtures and confirm state survives session changes while notifications remain duplicate-safe.

- [ ] T050 [US3] Implement the version-watch template in `skills/telegram-version-watch/SKILL.md`
- [ ] T051 [US3] Document scheduler choice, durable-state layout, and duplicate-suppression logic in `docs/runbooks/moltis-telegram-cloneable-agent.md`
- [ ] T052 [P] [US3] Add fixture-backed version-watch contract tests in `tests/component/test_telegram_version_watch_contract.sh`

## Phase 6: User Story 4 - User Can Interrupt, Queue, Replace, Or Inspect A Running Job (Priority: P2)

**Goal**: Make concurrent heavy requests safe through one authoritative interrupt/queue policy.

**Independent Test**: Exercise status, cancel, replace, and new-task-during-active-run scenarios and confirm deterministic queue decisions are exposed back to the user.

- [ ] T060 [US4] Add interrupt/queue/replace/steer policy to `config/moltis.toml`
- [ ] T061 [US4] Document status/cancel/replace semantics and operator expectations in `docs/runbooks/moltis-telegram-cloneable-agent.md`
- [ ] T062 [P] [US4] Add queue and interrupt contract coverage in `tests/component/test_telegram_cloneable_agent_contract.sh`

## Phase 7: User Story 5 - Watchdog Detects Stalls, Looping, And Delivery Degradation (Priority: P2)

**Goal**: Turn silence and hidden drift into explicit health signals with retryable diagnostics.

**Independent Test**: Reproduce stalled-worker, no-progress loop, and delivery-failure fixtures and confirm watchdog outcomes classify the right failure mode.

- [ ] T070 [US5] Add watchdog and loop-detection guardrails in `config/moltis.toml`
- [ ] T071 [US5] Create the watchdog rule in `docs/rules/moltis-telegram-long-running-workers-must-expose-watchdog-signals.md`
- [ ] T072 [P] [US5] Add stalled/no-progress/delivery-drift tests in `tests/component/test_telegram_cloneable_agent_contract.sh`

## Phase 8: User Story 6 - Authoritative UAT Fails Closed On Telegram Long-Running Regressions (Priority: P2)

**Goal**: Prove both branch correctness and live Telegram behavior without confusing one kind of proof for the other.

**Independent Test**: Run hermetic contract tests and a separate remote smoke/UAT path; confirm both catch the target regressions and report them with the correct proof boundary.

- [ ] T080 [US6] Extend `tests/component/test_telegram_remote_uat_contract.sh` for long-running signatures: `Activity log`, >90s sync wait, lost completion, duplicate notify, and route contamination
- [ ] T081 [US6] Add a live external smoke/UAT path in `tests/live_external/test_telegram_long_running_cloneable_agent_smoke.sh`
- [ ] T082 [US6] Document authoritative UAT boundaries and operator workflow in `docs/runbooks/moltis-telegram-cloneable-agent.md` and `docs/knowledge/LLM-REMOTE-MOLTIS-DOCKER-RUNBOOK.md`

## Phase 9: Polish & Cross-Cutting Concerns

- [ ] T090 [P] Reconcile skill, rule, config, and runbook references across `skills/`, `docs/`, and `config/moltis.toml`
- [ ] T091 [P] Run targeted component validation for `tests/component/test_telegram_cloneable_agent_contract.sh`, `tests/component/test_telegram_version_watch_contract.sh`, and `tests/component/test_telegram_remote_uat_contract.sh`
- [ ] T092 Run live-safe validation for `tests/live_external/test_telegram_long_running_cloneable_agent_smoke.sh`
- [ ] T093 Reconcile completed checkboxes and final scope notes in `specs/038-telegram-cloneable-agent/tasks.md`

## Dependencies & Execution Order

- Phase 0 is complete and establishes the planning baseline.
- Phase 1 must finish before foundational contracts, because the runbook/skill/fixture surfaces define the carrier paths.
- Phase 2 blocks every user story; no runtime implementation should start before lane, state, and delivery contracts exist.
- User Story 1 is the MVP and should land before any completion/delivery or monitor work.
- User Story 2 depends on the lane split from User Story 1 and the foundational durable-state contract.
- User Story 3 depends on explicit durable-state and delivery behavior from earlier phases.
- User Story 4 depends on the existence of active worker lifecycle and status storage.
- User Story 5 depends on active worker and delivery flows so the watchdog can classify real failure modes.
- User Story 6 depends on the earlier stories because UAT needs the full contract surface to verify.

## Implementation Strategy

### MVP First

1. Complete Phase 1 and Phase 2.
2. Land User Story 1 so Telegram becomes a thin, safe front door.
3. Land User Story 2 so completion delivery stops depending on the original sync turn.
4. Validate the MVP with fixture-backed contract tests before adding monitors or queueing behavior.

### Incremental Delivery

1. Add the version-watch template after the base handoff and completion model are stable.
2. Add interrupt/queue policy after worker lifecycle and durable state already exist.
3. Add watchdog semantics after core delivery behavior is observable.
4. Finish by strengthening authoritative UAT and live smoke boundaries.
