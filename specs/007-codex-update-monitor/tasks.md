# Tasks: Codex CLI Update Monitor

**Input**: Design documents from `/specs/007-codex-update-monitor/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/monitor-report.schema.json, quickstart.md

## Phase 0: Planning (Executor Assignment)

- [x] P001 Confirm implementation branch/spec pairing and executor ownership in `specs/007-codex-update-monitor/tasks.md`
- [x] P002 Link the feature package to the active Beads issue via `bd` and capture dependency notes in `specs/007-codex-update-monitor/tasks.md`
- [x] P003 Validate local prerequisites for Codex CLI, upstream source access, and optional Beads sync in `specs/007-codex-update-monitor/research.md`
- [x] P004 Start MVP delivery with User Story 1 only after executor assignment and prerequisite validation

---

## Phase 1: Setup

- [x] T001 Create the monitor script skeleton in `scripts/codex-cli-update-monitor.sh`
- [x] T002 [P] Create the operator runbook in `docs/codex-cli-update-monitor.md`
- [x] T003 [P] Register the new script in `scripts/manifest.json`
- [x] T004 Create fixed input/output fixtures in `tests/fixtures/codex-update-monitor/`
- [x] T005 Create a manual workflow skeleton in `.github/workflows/codex-cli-update-monitor.yml`

---

## Phase 2: Foundational

- [x] T006 Implement local Codex state detection in `scripts/codex-cli-update-monitor.sh`
- [x] T007 Implement upstream release collection plus optional issue-signal intake with graceful source-failure handling in `scripts/codex-cli-update-monitor.sh`
- [x] T008 [P] Implement repository workflow trait detection in `scripts/codex-cli-update-monitor.sh`
- [x] T009 Implement deterministic JSON report generation matching `specs/007-codex-update-monitor/contracts/monitor-report.schema.json` in `scripts/codex-cli-update-monitor.sh`
- [x] T010 Implement recommendation rubric and human summary rendering in `scripts/codex-cli-update-monitor.sh`
- [x] T011 Create component validation coverage in `tests/component/test_codex_cli_update_monitor.sh`

---

## Phase 3: User Story 1 - Operator Gets An Update Decision Fast (Priority: P1) MVP

**Goal**: Deliver one command that tells an operator whether action is needed now and produces stable JSON plus Markdown outputs.

**Independent Test**: Run the monitor with fixture-backed upstream data and verify the command emits valid JSON, a readable summary, and one of the four allowed recommendation values.

- [x] T012 [US1] Implement CLI argument parsing for output paths, source selection, and safe defaults in `scripts/codex-cli-update-monitor.sh`
- [x] T013 [US1] Implement version comparison and baseline decision flow in `scripts/codex-cli-update-monitor.sh`
- [x] T014 [P] [US1] Add contract and recommendation fixture tests in `tests/component/test_codex_cli_update_monitor.sh`
- [x] T015 [US1] Document local operator usage in `docs/codex-cli-update-monitor.md`
- [x] T016 [US1] Wire the manual workflow entrypoint to the script in `.github/workflows/codex-cli-update-monitor.yml`

---

## Phase 4: User Story 2 - Maintainer Gets Repository-Relevant Analysis (Priority: P2)

**Goal**: Explain why upstream Codex changes do or do not matter to this repository's actual workflow.

**Independent Test**: Run the monitor against fixtures that include both relevant and non-relevant upstream changes and confirm the report classifies them with repository-specific rationale.

- [x] T020 [US2] Map upstream release and optional issue-signal changes to repository workflow traits in `scripts/codex-cli-update-monitor.sh`
- [x] T021 [US2] Implement `relevant_changes`, `non_relevant_changes`, and evidence sections while keeping issue signals advisory in `scripts/codex-cli-update-monitor.sh`
- [x] T022 [P] [US2] Add relevance-classification fixtures in `tests/fixtures/codex-update-monitor/`
- [x] T023 [US2] Validate repository-specific rationale coverage in `tests/component/test_codex_cli_update_monitor.sh`
- [x] T024 [US2] Document how relevance is interpreted for operators in `docs/codex-cli-update-monitor.md`

---

## Phase 5: User Story 3 - Backlog Follow-Up Is Optional But Actionable (Priority: P3)

**Goal**: Allow explicit Beads follow-up creation or update without making tracker mutation the default.

**Independent Test**: Run the monitor once without issue flags and once with explicit Beads sync flags, then confirm the report records the correct issue action behavior in both cases.

- [ ] T030 [US3] Add explicit issue-sync flags and dry-run-safe defaults in `scripts/codex-cli-update-monitor.sh`
- [ ] T031 [US3] Implement Beads issue payload creation/update flow in `scripts/codex-cli-update-monitor.sh`
- [ ] T032 [P] [US3] Add tracker-action fixture coverage in `tests/component/test_codex_cli_update_monitor.sh`
- [ ] T033 [US3] Document Beads sync usage and safety boundaries in `docs/codex-cli-update-monitor.md`

---

## Phase 6: User Story 4 - The Contract Stays Reusable (Priority: P4)

**Goal**: Keep the script usable from a thin future wrapper without rewriting collector logic or scraping prose.

**Independent Test**: Invoke the monitor in a wrapper-style way and confirm a caller can rely on stable machine-readable outputs and explicit failure modes.

- [x] T040 [US4] Refine stdout, stderr, and exit semantics for wrapper-safe consumption in `scripts/codex-cli-update-monitor.sh`
- [x] T041 [US4] Add wrapper-consumption contract validation in `tests/component/test_codex_cli_update_monitor.sh`
- [x] T042 [US4] Document wrapper-ready invocation expectations in `docs/codex-cli-update-monitor.md`

---

## Phase 7: Polish & Cross-Cutting Concerns

- [x] T050 [P] Add a convenient make target in `Makefile`
- [x] T051 [P] Validate Bash syntax for `scripts/codex-cli-update-monitor.sh` and referenced helpers
- [x] T052 Run targeted component validation for `tests/component/test_codex_cli_update_monitor.sh`
- [x] T053 Verify the manual workflow and runbook stay aligned with the script contract
- [ ] T054 Update Beads status and package notes after the first implementation slice lands

---

## Dependencies & Execution Order

- Phase 1 -> Phase 2 -> Phase 3 -> Phase 4 -> Phase 5 -> Phase 6 -> Phase 7
- User Story 1 is the MVP and must land before any follow-up automation work.
- User Story 2 depends on foundational collection/reporting logic from Phase 2.
- User Story 3 depends on the stable recommendation report from User Stories 1 and 2.
- User Story 4 depends on the stable output contract established by earlier phases.
