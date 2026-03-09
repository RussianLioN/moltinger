# Tasks: Codex Upstream Watcher

**Input**: Design documents from `/specs/012-codex-upstream-watcher/`  
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/watcher-report.schema.json, quickstart.md

## Phase 0: Planning (Executor Assignment)

- [x] P001 Confirm implementation branch/spec pairing and upstream watcher scope boundaries in `specs/012-codex-upstream-watcher/tasks.md`
- [x] P002 Validate local prerequisites for official-source polling, cron installation, and Moltinger Telegram reuse in `specs/012-codex-upstream-watcher/research.md`
- [x] P003 Start MVP implementation with manual upstream watching before scheduler automation

---

## Phase 1: Setup

- [ ] T001 Create the watcher script skeleton in `scripts/codex-cli-upstream-watcher.sh`
- [ ] T002 [P] Create the operator runbook in `docs/codex-cli-upstream-watcher.md`
- [ ] T003 [P] Create fixed watcher fixtures in `tests/fixtures/codex-upstream-watcher/`
- [ ] T004 Create the component test skeleton in `tests/component/test_codex_cli_upstream_watcher.sh`
- [ ] T005 Register the watcher script and cron artifact in `scripts/manifest.json`
- [ ] T006 Create the scheduler cron file skeleton in `scripts/cron.d/moltis-codex-upstream-watcher`

---

## Phase 2: Foundational

- [ ] T007 Implement official-source intake and shared watcher-state handling in `scripts/codex-cli-upstream-watcher.sh`
- [ ] T008 Implement deterministic JSON generation matching `specs/012-codex-upstream-watcher/contracts/watcher-report.schema.json` in `scripts/codex-cli-upstream-watcher.sh`
- [ ] T009 Reuse `scripts/telegram-bot-send.sh` for scheduler Telegram transport in `scripts/codex-cli-upstream-watcher.sh`
- [ ] T010 Create baseline component validation coverage in `tests/component/test_codex_cli_upstream_watcher.sh`

---

## Phase 3: User Story 1 - Operator Can Run An Official-Source Watch Check Manually (Priority: P1) MVP

**Goal**: Let an operator run one watcher command and learn whether the official Codex upstream state is fresh or already known, without needing a local Codex binary.

**Independent Test**: Run the watcher against fixture-backed official sources and confirm it emits a deterministic summary and JSON report with latest version, highlights, fingerprint, and freshness decision.

- [ ] T011 [US1] Implement manual watcher mode and primary-source polling in `scripts/codex-cli-upstream-watcher.sh`
- [ ] T012 [US1] Add advisory issue-signal intake and source-status reporting in `scripts/codex-cli-upstream-watcher.sh`
- [ ] T013 [P] [US1] Add fixture-backed manual-run tests in `tests/component/test_codex_cli_upstream_watcher.sh`
- [ ] T014 [US1] Document manual watcher usage and output semantics in `docs/codex-cli-upstream-watcher.md`

---

## Phase 4: User Gets Telegram Alert From Scheduled Upstream Watcher (Priority: P1)

**Goal**: Run the watcher on the Moltinger host schedule and send one Telegram alert for each fresh upstream fingerprint.

**Independent Test**: Run scheduler mode with a fresh actionable fixture and mocked Telegram sender, then confirm one alert is sent and duplicates are suppressed on repeat runs.

- [ ] T020 [US2] Implement scheduler-safe Telegram delivery decisions in `scripts/codex-cli-upstream-watcher.sh`
- [ ] T021 [US2] Add the repository-managed cron job in `scripts/cron.d/moltis-codex-upstream-watcher`
- [ ] T022 [US2] Wire cron installation and script inventory metadata in `scripts/manifest.json`
- [ ] T023 [P] [US2] Add Telegram scheduler and duplicate-suppression tests in `tests/component/test_codex_cli_upstream_watcher.sh`
- [ ] T024 [US2] Document scheduled Moltinger installation and Telegram requirements in `docs/codex-cli-upstream-watcher.md`

---

## Phase 5: Scheduled Runs Stay Safe During Source Failures And Recovery (Priority: P2)

**Goal**: Keep scheduled upstream alerts coherent and low-noise when source reads fail, recover, or partially disagree.

**Independent Test**: Exercise source failure, recovery, and changed-source fixtures and confirm watcher state, report, and Telegram behavior stay retry-safe and duplicate-safe.

- [ ] T030 [US3] Implement failure and recovery state transitions in `scripts/codex-cli-upstream-watcher.sh`
- [ ] T031 [US3] Implement explicit investigate and retry reporting for malformed or unavailable sources in `scripts/codex-cli-upstream-watcher.sh`
- [ ] T032 [P] [US3] Add failure-and-recovery component tests in `tests/component/test_codex_cli_upstream_watcher.sh`
- [ ] T033 [US3] Document safety boundaries and future bridge points to local advisor flows in `docs/codex-cli-upstream-watcher.md`

---

## Phase 6: Polish & Cross-Cutting Concerns

- [ ] T040 [P] Add a convenient make target in `Makefile`
- [ ] T041 [P] Add a manual workflow entrypoint in `.github/workflows/codex-cli-upstream-watcher.yml`
- [ ] T042 Validate Bash syntax for `scripts/codex-cli-upstream-watcher.sh` and referenced tests
- [ ] T043 Run targeted component validation for `tests/component/test_codex_cli_upstream_watcher.sh`
- [ ] T044 Verify watcher docs, cron automation, and deployment wiring stay aligned
- [ ] T045 Update `docs/GIT-TOPOLOGY-REGISTRY.md` for the new `012-codex-upstream-watcher` worktree

## Dependencies & Execution Order

- Phase 1 -> Phase 2 -> Phase 3 -> Phase 4 -> Phase 5 -> Phase 6
- User Story 1 is the MVP and must land before scheduler or Telegram automation work.
- User Story 2 depends on stable fingerprint/state logic from Phases 2 and 3.
- User Story 3 depends on earlier scheduler delivery behavior existing so recovery and retry semantics are meaningful.

## Implementation Strategy

- Deliver the smallest useful slice first: manual upstream watcher run.
- Add scheduled Telegram delivery second.
- Add failure/recovery hardening after the baseline watcher and scheduler behavior are stable.
