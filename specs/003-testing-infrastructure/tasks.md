# Tasks: Testing Infrastructure

**Input**: Design documents from `/specs/003-testing-infrastructure/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, quickstart.md ✅

**Tests**: This feature IS the testing system - tests are self-referential.

**Organization**: Tasks grouped by user story for independent implementation.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story (US1-US4)
- Include exact file paths

---

## Phase 0: Planning (Executor Assignment)

**Purpose**: Prepare for implementation by analyzing requirements and assigning executors.

- [ ] P001 Analyze all tasks and identify required agent types and capabilities
- [ ] P002 Create missing agents using meta-agent-v3 (if needed), then ask user restart
- [ ] P003 Assign executors: MAIN (trivial only), existing (100% match), or specific agent
- [ ] P004 Resolve research: simple (solve now), complex (create prompts in research/)

**Artifacts**:
- tasks.md with [EXECUTOR: name] annotations
- .claude/agents/ (if new agents created)

---

## Phase 1: Setup (Project Initialization)

**Purpose**: Create test infrastructure foundation

- [ ] T001 Create tests/ directory structure per plan.md (tests/, tests/unit/, tests/integration/, tests/uat/, tests/fixtures/, tests/reports/)
- [ ] T002 [P] Install bats-core, bats-support, bats-assert on development machine
- [ ] T003 [P] Create requirements-test.txt with pytest, pytest-testinfra, pytest-docker-compose, playwright, pytest-playwright, pytest-cov
- [ ] T004 [P] Create tests/conftest.py with global pytest fixtures
- [ ] T005 [P] Create tests/fixtures/mock_responses/ directory with placeholder .gitkeep
- [ ] T006 Add test targets to Makefile (test, test-unit, test-integration, test-uat, coverage)
- [ ] T007 [P] Create tests/unit/lib/mock.bash with common mock functions (docker, ssh, curl)

**Checkpoint**: Test infrastructure scaffold ready

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core test utilities that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [ ] T008 Implement mock_docker() function in tests/unit/lib/mock.bash
- [ ] T009 [P] Implement mock_ssh() function in tests/unit/lib/mock.bash
- [ ] T010 [P] Implement mock_curl() function in tests/unit/lib/mock.bash
- [ ] T011 Create tests/integration/conftest.py with Docker Compose fixtures
- [ ] T012 [P] Create tests/uat/conftest.py with Playwright fixtures
- [ ] T013 Create tests/fixtures/sample_configs/moltis.toml with test configuration

**Checkpoint**: Foundation ready - user story implementation can begin

---

## Phase 3: User Story 1 - Developer Runs Tests (Priority: P1) 🎯 MVP

**Goal**: Developers can run unit tests for Bash scripts with clear pass/fail output

**Independent Test**: Run `make test-unit` and verify tests execute, report results in < 60s

### Implementation for User Story 1

- [ ] T014 [P] [US1] Create tests/unit/scripts/deploy.bats with tests for deploy.sh functions
- [ ] T015 [P] [US1] Create tests/unit/scripts/backup.bats with tests for backup-moltis-enhanced.sh functions
- [ ] T016 [P] [US1] Create tests/unit/scripts/health-monitor.bats with tests for health-monitor.sh functions
- [ ] T017 [US1] Add assertions for critical paths in deploy.bats (backup before deploy, rollback)
- [ ] T018 [US1] Add assertions for error handling in backup.bats (encryption failure, disk full)
- [ ] T019 [US1] Verify unit tests complete in < 60 seconds per SC-004
- [ ] T020 [US1] Create .github/workflows/test.yml with unit test job

**Checkpoint**: Unit tests working - developers can test scripts locally and in CI

---

## Phase 4: User Story 2 - Infrastructure Validation (Priority: P2)

**Goal**: Docker Compose configuration automatically validated before deployment

**Independent Test**: Run `make test-integration` and verify all 5 services start, health checks pass

### Implementation for User Story 2

- [ ] T021 [P] [US2] Create tests/integration/test_services.py with service health tests
- [ ] T022 [P] [US2] Create tests/integration/test_networking.py with network isolation tests
- [ ] T023 [US2] Implement test_moltis_healthy() in test_services.py (HTTP 200 on /health)
- [ ] T024 [US2] Implement test_prometheus_healthy() in test_services.py
- [ ] T025 [US2] Implement test_all_services_running() in test_services.py (5 services)
- [ ] T026 [US2] Implement test_network_isolation() in test_networking.py
- [ ] T027 [US2] Add integration test job to .github/workflows/test.yml with matrix strategy
- [ ] T028 [US2] Configure test job to block deploy.yml on failure (FR-012)

**Checkpoint**: Integration tests validate Docker Compose - bad configs caught in CI

---

## Phase 5: User Story 3 - UAT Test Automation (Priority: P3)

**Goal**: Top 20 critical UAT scenarios automated, reducing testing time from 9 days to 2 hours

**Independent Test**: Run `make test-uat` and verify Web UI and Telegram tests pass

### Implementation for User Story 3

- [ ] T029 [P] [US3] Install Playwright browsers (chromium, firefox, webkit)
- [ ] T030 [P] [US3] Create tests/uat/pages/chat.py with Page Object for chat interface
- [ ] T031 [US3] Create tests/uat/test_web_ui.py with Web UI test scenarios
- [ ] T032 [US3] Implement test_send_message() in test_web_ui.py (send message, get response)
- [ ] T033 [US3] Implement test_model_selection() in test_web_ui.py (select GLM-5, verify response)
- [ ] T034 [US3] Implement test_response_time() in test_web_ui.py (response < 5 seconds)
- [ ] T035 [US3] Create tests/uat/test_telegram.py with Telegram bot tests
- [ ] T036 [US3] Implement test_start_command() in test_telegram.py (/start returns greeting)
- [ ] T037 [US3] Add screenshot capture on failure in conftest.py (FR-017)
- [ ] T038 [US3] Configure headless mode for CI in test.yml (FR-016)
- [ ] T039 [US3] Create mock GLM API responses in tests/fixtures/mock_responses/glm.json

**Checkpoint**: UAT automation ready - critical user journeys tested automatically

---

## Phase 6: User Story 4 - Test Coverage Tracking (Priority: P3)

**Goal**: Coverage metrics visible, tracking progress toward 50% target

**Independent Test**: Run `make coverage` and verify HTML report generated with percentages

### Implementation for User Story 4

- [ ] T040 [P] [US4] Create scripts/coverage.sh for Bash script coverage tracking
- [ ] T041 [P] [US4] Configure pytest-cov in tests/conftest.py for Python coverage
- [ ] T042 [US4] Create tests/reports/coverage/ directory for HTML reports
- [ ] T043 [US4] Implement coverage calculation in scripts/coverage.sh (files touched / total files)
- [ ] T044 [US4] Add combined coverage report generation to Makefile
- [ ] T045 [US4] Add coverage job to .github/workflows/test.yml
- [ ] T046 [US4] Create coverage badge configuration for README.md

**Checkpoint**: Coverage tracking working - progress toward 50% visible

---

## Phase 7: Polish & Documentation

**Purpose**: Documentation and final improvements

- [ ] T047 [P] Create tests/README.md with how to run tests
- [ ] T048 [P] Add CI/CD badge to project README.md
- [ ] T049 Document how to add new tests in tests/README.md
- [ ] T050 Validate quickstart.md instructions work end-to-end
- [ ] T051 Add Makefile help target showing available test commands
- [ ] T052 Verify all success criteria from spec.md are met

---

## Dependencies & Execution Order

### Phase Dependencies

```
Phase 0 (Planning)
    ↓
Phase 1 (Setup) → Phase 2 (Foundational)
                        ↓
        ┌───────────────┼───────────────┐
        ↓               ↓               ↓
   Phase 3 (US1)   Phase 4 (US2)   Phase 5 (US3)
   [P1 - MVP]      [P2]            [P3]
                        ↓
                   Phase 6 (US4)
                   [P3]
                        ↓
                   Phase 7 (Polish)
```

### User Story Dependencies

| Story | Depends On | Can Run In Parallel With |
|-------|------------|--------------------------|
| US1 (Unit Tests) | Foundational | US2, US3, US4 |
| US2 (Integration) | Foundational | US1, US3, US4 |
| US3 (UAT) | Foundational | US1, US2, US4 |
| US4 (Coverage) | US1, US2 | - |

### Parallel Opportunities

**Within Phase 1 (Setup)**:
```bash
# Can run in parallel (different files):
T002: Install bats-core
T003: Create requirements-test.txt
T004: Create tests/conftest.py
T005: Create fixtures directory
T007: Create mock.bash
```

**Within Phase 3 (US1)**:
```bash
# Can run in parallel (different .bats files):
T014: Create deploy.bats
T015: Create backup.bats
T016: Create health-monitor.bats
```

**Cross-Story Parallel**:
```bash
# After Foundational phase, can work in parallel:
Developer A: US1 (Unit tests)
Developer B: US2 (Integration tests)
Developer C: US3 (UAT automation)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. ✅ Complete Phase 1: Setup
2. ✅ Complete Phase 2: Foundational
3. ✅ Complete Phase 3: User Story 1 (Unit Tests)
4. **STOP and VALIDATE**: Run `make test-unit`, verify < 60s
5. Deploy - developers can now test Bash scripts

### Incremental Delivery

| Increment | Stories | Value Delivered |
|-----------|---------|-----------------|
| MVP | US1 | Unit tests for scripts |
| v1.1 | +US2 | Integration tests for Docker |
| v1.2 | +US3 | UAT automation |
| v1.3 | +US4 | Coverage tracking |

---

## Task Summary

| Phase | Tasks | Parallelizable |
|-------|-------|----------------|
| Phase 0: Planning | 4 | - |
| Phase 1: Setup | 7 | 5 |
| Phase 2: Foundational | 6 | 4 |
| Phase 3: US1 (MVP) | 7 | 3 |
| Phase 4: US2 | 8 | 2 |
| Phase 5: US3 | 11 | 2 |
| Phase 6: US4 | 7 | 2 |
| Phase 7: Polish | 6 | 2 |
| **Total** | **56** | **20** |

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to user story
- Each user story independently testable
- Tests ARE the feature being built
- Commit after each task
- Verify success criteria at each checkpoint
