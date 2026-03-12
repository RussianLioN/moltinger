# Tasks: Codex Upstream Watcher

**Input**: Design documents from `/specs/012-codex-upstream-watcher/`  
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/watcher-report.schema.json, quickstart.md

## Phase 0: Planning (Executor Assignment)

- [x] P001 Confirm implementation branch/spec pairing and upstream watcher scope boundaries in `specs/012-codex-upstream-watcher/tasks.md`
- [x] P002 Validate local prerequisites for official-source polling, cron installation, and Moltinger Telegram reuse in `specs/012-codex-upstream-watcher/research.md`
- [x] P003 Start MVP implementation with manual upstream watching before scheduler automation

---

## Phase 1: Setup

- [x] T001 Create the watcher script skeleton in `scripts/codex-cli-upstream-watcher.sh`
- [x] T002 [P] Create the operator runbook in `docs/codex-cli-upstream-watcher.md`
- [x] T003 [P] Create fixed watcher fixtures in `tests/fixtures/codex-upstream-watcher/`
- [x] T004 Create the component test skeleton in `tests/component/test_codex_cli_upstream_watcher.sh`
- [x] T005 Register the watcher script and cron artifact in `scripts/manifest.json`
- [x] T006 Create the scheduler cron file skeleton in `scripts/cron.d/moltis-codex-upstream-watcher`

---

## Phase 2: Foundational

- [x] T007 Implement official-source intake and shared watcher-state handling in `scripts/codex-cli-upstream-watcher.sh`
- [x] T008 Implement deterministic JSON generation matching `specs/012-codex-upstream-watcher/contracts/watcher-report.schema.json` in `scripts/codex-cli-upstream-watcher.sh`
- [x] T009 Reuse `scripts/telegram-bot-send.sh` for scheduler Telegram transport in `scripts/codex-cli-upstream-watcher.sh`
- [x] T010 Create baseline component validation coverage in `tests/component/test_codex_cli_upstream_watcher.sh`

---

## Phase 3: User Story 1 - Operator Can Run An Official-Source Watch Check Manually (Priority: P1) MVP

**Goal**: Let an operator run one watcher command and learn whether the official Codex upstream state is fresh or already known, without needing a local Codex binary.

**Independent Test**: Run the watcher against fixture-backed official sources and confirm it emits a deterministic summary and JSON report with latest version, highlights, fingerprint, and freshness decision.

- [x] T011 [US1] Implement manual watcher mode and primary-source polling in `scripts/codex-cli-upstream-watcher.sh`
- [x] T012 [US1] Add advisory issue-signal intake and source-status reporting in `scripts/codex-cli-upstream-watcher.sh`
- [x] T013 [P] [US1] Add fixture-backed manual-run tests in `tests/component/test_codex_cli_upstream_watcher.sh`
- [x] T014 [US1] Document manual watcher usage and output semantics in `docs/codex-cli-upstream-watcher.md`

---

## Phase 4: User Gets Telegram Alert From Scheduled Upstream Watcher (Priority: P1)

**Goal**: Run the watcher on the Moltinger host schedule and send one Telegram alert for each fresh upstream fingerprint.

**Independent Test**: Run scheduler mode with a fresh actionable fixture and mocked Telegram sender, then confirm one alert is sent and duplicates are suppressed on repeat runs.

- [x] T020 [US2] Implement scheduler-safe Telegram delivery decisions in `scripts/codex-cli-upstream-watcher.sh`
- [x] T021 [US2] Add the repository-managed cron job in `scripts/cron.d/moltis-codex-upstream-watcher`
- [x] T022 [US2] Wire cron installation and script inventory metadata in `scripts/manifest.json`
- [x] T023 [P] [US2] Add Telegram scheduler and duplicate-suppression tests in `tests/component/test_codex_cli_upstream_watcher.sh`
- [x] T024 [US2] Document scheduled Moltinger installation and Telegram requirements in `docs/codex-cli-upstream-watcher.md`

---

## Phase 5: Scheduled Runs Stay Safe During Source Failures And Recovery (Priority: P2)

**Goal**: Keep scheduled upstream alerts coherent and low-noise when source reads fail, recover, or partially disagree.

**Independent Test**: Exercise source failure, recovery, and changed-source fixtures and confirm watcher state, report, and Telegram behavior stay retry-safe and duplicate-safe.

- [x] T030 [US3] Implement failure and recovery state transitions in `scripts/codex-cli-upstream-watcher.sh`
- [x] T031 [US3] Implement explicit investigate and retry reporting for malformed or unavailable sources in `scripts/codex-cli-upstream-watcher.sh`
- [x] T032 [P] [US3] Add failure-and-recovery component tests in `tests/component/test_codex_cli_upstream_watcher.sh`
- [x] T033 [US3] Document safety boundaries and future bridge points to local advisor flows in `docs/codex-cli-upstream-watcher.md`

---

## Phase 6: Polish & Cross-Cutting Concerns

- [x] T040 [P] Add a convenient make target in `Makefile`
- [x] T041 [P] Add a manual workflow entrypoint in `.github/workflows/codex-cli-upstream-watcher.yml`
- [x] T042 Validate Bash syntax for `scripts/codex-cli-upstream-watcher.sh` and referenced tests
- [x] T043 Run targeted component validation for `tests/component/test_codex_cli_upstream_watcher.sh`
- [x] T044 Verify watcher docs, cron automation, and deployment wiring stay aligned
- [x] T045 Update `docs/GIT-TOPOLOGY-REGISTRY.md` for the new `012-codex-upstream-watcher` worktree

---

## Phase 7: Severity, Digest, And Opt-In Practical Guidance

**Goal**: Make upstream alerts more useful and less noisy by adding severity levels, digest batching, and a consent-based bridge to project-facing recommendations.

**Independent Test**: Confirm manual reports expose Russian severity and plain-language explanations, digest mode batches non-critical events, and a Telegram `да` reply triggers a second practical-recommendation message while `нет` suppresses it.

- [x] T050 [US4] Add Russian plain-language highlight explanations and severity classification in `scripts/codex-cli-upstream-watcher.sh`
- [x] T051 [US4] Add digest-mode state handling and combined Telegram delivery in `scripts/codex-cli-upstream-watcher.sh`
- [x] T052 [US3] Build an advisor bridge for project-facing practical recommendations in `scripts/codex-cli-upstream-watcher.sh`
- [x] T053 [US3] Add Telegram consent follow-up and reply processing in `scripts/codex-cli-upstream-watcher.sh`
- [x] T054 [P] Extend fixtures and component coverage for severity, digest, and consent flow in `tests/component/test_codex_cli_upstream_watcher.sh`
- [x] T055 [US3] Update the watcher contract and documentation for severity, digest, and practical-recommendation UX in `specs/012-codex-upstream-watcher/contracts/watcher-report.schema.json` and `docs/codex-cli-upstream-watcher.md`
- [x] T056 [P] Update manual workflow and script inventory metadata for the expanded watcher surface in `.github/workflows/codex-cli-upstream-watcher.yml` and `scripts/manifest.json`

## Dependencies & Execution Order

- Phase 1 -> Phase 2 -> Phase 3 -> Phase 4 -> Phase 5 -> Phase 6 -> Phase 7
- User Story 1 is the MVP and must land before scheduler or Telegram automation work.
- User Story 2 depends on stable fingerprint/state logic from Phases 2 and 3.
- User Story 3 depends on earlier scheduler delivery behavior existing so recovery and retry semantics are meaningful.
- User Stories 3 and 4 in the extended scope depend on the baseline watcher and Telegram alert path already existing.

## Implementation Strategy

- Deliver the smallest useful slice first: manual upstream watcher run.
- Add scheduled Telegram delivery second.
- Add failure/recovery hardening after the baseline watcher and scheduler behavior are stable.
- Add severity, digest batching, and consent-based project guidance only after the base upstream watcher semantics are stable.
