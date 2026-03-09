# Tasks: Codex CLI Update Advisor

**Input**: Design documents from `/specs/008-codex-update-advisor/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/advisor-report.schema.json, quickstart.md

## Phase 0: Planning (Executor Assignment)

- [x] P001 Confirm implementation branch/spec pairing and advisor scope boundaries in `specs/008-codex-update-advisor/tasks.md`
- [x] P002 Validate local prerequisites for the base monitor, advisor state path, and optional Beads sync in `specs/008-codex-update-advisor/research.md`
- [x] P003 Start MVP delivery with User Story 1 only after executor assignment and prerequisite validation

---

## Phase 1: Setup

- [x] T001 Create the advisor script skeleton in `scripts/codex-cli-update-advisor.sh`
- [x] T002 [P] Create the operator runbook in `docs/codex-cli-update-advisor.md`
- [x] T003 [P] Register the advisor script in `scripts/manifest.json`
- [x] T004 Create fixed advisor fixtures in `tests/fixtures/codex-update-advisor/`
- [x] T005 Create the component test skeleton in `tests/component/test_codex_cli_update_advisor.sh`

---

## Phase 2: Foundational

- [x] T006 Implement monitor-report intake and monitor invocation handoff in `scripts/codex-cli-update-advisor.sh`
- [x] T007 Implement advisor state load/save plus fingerprint comparison in `scripts/codex-cli-update-advisor.sh`
- [x] T008 Implement deterministic advisor JSON generation matching `specs/008-codex-update-advisor/contracts/advisor-report.schema.json` in `scripts/codex-cli-update-advisor.sh`
- [x] T009 Implement summary rendering and wrapper-safe stdout behavior in `scripts/codex-cli-update-advisor.sh`
- [x] T010 Create baseline component validation coverage in `tests/component/test_codex_cli_update_advisor.sh`

---

## Phase 3: User Story 1 - Operator Gets A Low-Noise Alert (Priority: P1) MVP

**Goal**: Deliver one advisor command that tells an operator whether this result is new, already seen, ignorable, or investigatory, while preserving a stable report.

**Independent Test**: Run the advisor twice against the same upgrade-worthy input and state file, then confirm the first run notifies and the second run suppresses the duplicate.

- [x] T011 [US1] Implement CLI argument parsing for state, monitor input, and safe defaults in `scripts/codex-cli-update-advisor.sh`
- [x] T012 [US1] Implement notification threshold logic and duplicate suppression flow in `scripts/codex-cli-update-advisor.sh`
- [x] T013 [P] [US1] Add first-run and repeat-run fixture tests in `tests/component/test_codex_cli_update_advisor.sh`
- [x] T014 [US1] Document low-noise notification behavior in `docs/codex-cli-update-advisor.md`

---

## Phase 4: User Story 2 - Maintainer Gets Concrete Project Change Suggestions (Priority: P2)

**Goal**: Translate monitor evidence into repository-specific follow-up suggestions with impacted paths and rationale.

**Independent Test**: Run the advisor on fixture-backed monitor reports with workflow-relevant changes and verify it emits prioritized suggestions tied to impacted repository surfaces.

- [x] T020 [US2] Map monitor relevance categories to repository suggestion rules in `scripts/codex-cli-update-advisor.sh`
- [x] T021 [US2] Implement suggestion prioritization, impacted paths, and implementation brief generation in `scripts/codex-cli-update-advisor.sh`
- [x] T022 [P] [US2] Add suggestion fixtures in `tests/fixtures/codex-update-advisor/`
- [x] T023 [US2] Validate suggestion coverage in `tests/component/test_codex_cli_update_advisor.sh`
- [x] T024 [US2] Document how maintainers should interpret project change suggestions in `docs/codex-cli-update-advisor.md`

---

## Phase 5: User Story 3 - Backlog Owner Gets A Ready-To-Track Implementation Brief (Priority: P3)

**Goal**: Allow explicit Beads follow-up creation or update using the richer advisor brief while keeping default runs read-only.

**Independent Test**: Run the advisor once without issue flags and once with explicit Beads sync flags, then confirm the advisor records the correct issue action behavior in both cases.

- [x] T030 [US3] Add explicit issue-sync flags and advisor brief rendering in `scripts/codex-cli-update-advisor.sh`
- [x] T031 [US3] Implement Beads create/update flow for advisor follow-up briefs in `scripts/codex-cli-update-advisor.sh`
- [x] T032 [P] [US3] Add tracker-action fixture coverage in `tests/component/test_codex_cli_update_advisor.sh`
- [x] T033 [US3] Document Beads handoff usage and safety boundaries in `docs/codex-cli-update-advisor.md`

---

## Phase 6: User Story 4 - Wrapper Or Scheduler Can Consume The Advisor Safely (Priority: P4)

**Goal**: Keep the advisor reusable from thin wrappers or scheduled executions without prose scraping or ambiguous state behavior.

**Independent Test**: Invoke the advisor with `--stdout json` and with `--monitor-report`, then confirm a caller can rely on stable machine-readable fields.

- [x] T040 [US4] Refine wrapper-safe stdout, exit behavior, and monitor passthrough handling in `scripts/codex-cli-update-advisor.sh`
- [x] T041 [US4] Add contract validation for `--stdout json` and `--monitor-report` in `tests/component/test_codex_cli_update_advisor.sh`
- [x] T042 [US4] Document wrapper and scheduler usage expectations in `docs/codex-cli-update-advisor.md`

---

## Phase 7: Polish & Cross-Cutting Concerns

- [x] T050 [P] Add a convenient make target in `Makefile`
- [x] T051 [P] Validate Bash syntax for `scripts/codex-cli-update-advisor.sh` and referenced tests
- [x] T052 Run targeted component validation for `tests/component/test_codex_cli_update_advisor.sh`
- [x] T053 Verify the monitor and advisor docs or contracts stay aligned
- [x] T054 Update `docs/GIT-TOPOLOGY-REGISTRY.md` for the new `008-codex-update-advisor` worktree
- [x] T055 Update Beads status and package notes after the implementation slice lands

---

## Dependencies & Execution Order

- Phase 1 -> Phase 2 -> Phase 3 -> Phase 4 -> Phase 5 -> Phase 6 -> Phase 7
- User Story 1 is the MVP and must land before suggestion or tracker automation work.
- User Story 2 depends on the stable monitor input and notification report established by Phases 2 and 3.
- User Story 3 depends on the stable implementation brief from User Story 2.
- User Story 4 depends on the stable report contract established by earlier phases.
