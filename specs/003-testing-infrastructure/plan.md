# Implementation Plan: Testing Infrastructure

**Branch**: `003-testing-infrastructure` | **Date**: 2026-02-17 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/003-testing-infrastructure/spec.md`

---

## Summary

Создание комплексной testing infrastructure для проекта Moltinger, включающую:
- Unit тесты для Bash скриптов (bats-core)
- Integration тесты для Docker Compose (testinfra)
- UAT автоматизацию (Playwright)
- Coverage tracking (0% → 50%)
- CI/CD интеграцию с GitHub Actions

---

## Technical Context

**Language/Version**: Bash 4.0+, Python 3.11+
**Primary Dependencies**: bats-core, pytest, testinfra, playwright
**Storage**: N/A (tests generate reports to files)
**Testing**: Self-referential - building the testing system
**Target Platform**: Linux (Docker containers), macOS (local dev)
**Project Type**: Infrastructure/DevOps project
**Performance Goals**: Unit < 60s, Full suite < 5 min
**Constraints**: No external API calls in tests (mock required)
**Scale/Scope**: 4 scripts, 5 services, 68 UAT cases (20 automated)

---

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Design Check ✅

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Context-First | ✅ Pass | Read existing scripts, CI/CD config |
| II. Single Source of Truth | ✅ Pass | Tests in single `tests/` directory |
| III. Library-First | ✅ Pass | Using bats-core, testinfra, playwright |
| IV. Code Reuse | ✅ Pass | Shared test utilities in `tests/lib/` |
| V. Type Safety | ⚠️ Partial | Bash has no types, Python uses hints |
| VI. Atomic Task Execution | ✅ Pass | Each test file = atomic unit |
| VII. Quality Gates | ✅ Pass | Tests ARE the quality gate |
| VIII. Progressive Specification | ✅ Pass | Following spec → plan → tasks |

### Violations Justified

| Violation | Why Needed | Mitigation |
|-----------|------------|------------|
| Bash no type safety | Testing Bash scripts requires Bash | Use bats-assert for type assertions |

---

## Project Structure

### Documentation (this feature)

```text
specs/003-testing-infrastructure/
├── spec.md              # Feature specification ✅
├── plan.md              # This file ✅
├── research.md          # Technology decisions ✅
├── research/            # (not needed - simple research)
├── data-model.md        # Test entities
├── quickstart.md        # How to run tests
├── contracts/           # (not needed - no API)
└── tasks.md             # Implementation tasks (via /speckit.tasks)
```

### Source Code (repository root)

```text
tests/
├── unit/                    # Bash unit tests
│   ├── scripts/             # Tests for scripts/
│   │   ├── deploy.bats
│   │   ├── backup.bats
│   │   └── health-monitor.bats
│   └── lib/                 # Shared test helpers
│       └── mock.bash
│
├── integration/             # Docker Compose tests
│   ├── test_services.py     # Service health tests
│   ├── test_networking.py   # Network tests
│   └── conftest.py          # pytest fixtures
│
├── uat/                     # Browser automation
│   ├── test_web_ui.py       # Web UI tests
│   ├── test_telegram.py     # Telegram bot tests
│   └── pages/               # Page objects
│       └── chat.py
│
├── fixtures/                # Test data
│   ├── mock_responses/
│   └── sample_configs/
│
├── reports/                 # Generated reports
│   ├── coverage/
│   └── screenshots/
│
└── conftest.py              # Global pytest config

.github/
└── workflows/
    └── test.yml             # New: Test workflow

Makefile                      # Add test targets
```

**Structure Decision**: Single project structure with `tests/` directory containing unit/, integration/, uat/ subdirectories. Follows pytest conventions for Python tests, bats conventions for Bash tests.

---

## Complexity Tracking

> No constitution violations requiring justification beyond noted above.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Bash type safety | Testing Bash requires Bash | Would need to rewrite all scripts in Python |

---

## Implementation Phases

### Phase 1: Foundation (Day 1-2)

1. **Setup test infrastructure**
   - Install bats-core, pytest, testinfra, playwright
   - Create `tests/` directory structure
   - Add test targets to Makefile

2. **Unit tests for critical scripts**
   - `tests/unit/scripts/deploy.bats`
   - `tests/unit/scripts/backup.bats`
   - Mock external commands (docker, ssh)

### Phase 2: Integration Tests (Day 3-4)

3. **Docker Compose validation**
   - `tests/integration/test_services.py`
   - Health check tests
   - Network isolation tests

4. **CI/CD integration**
   - `.github/workflows/test.yml`
   - Matrix strategy for parallel execution
   - PR status checks

### Phase 3: UAT Automation (Day 5-7)

5. **Playwright setup**
   - Browser installation
   - Page objects for Web UI
   - Mock GLM/Telegram APIs

6. **Critical UAT scenarios**
   - Web UI basic chat
   - Telegram bot response
   - Model selection

### Phase 4: Coverage & Reporting (Day 8-10)

7. **Coverage tracking**
   - Custom Bash coverage script
   - pytest-cov for Python
   - Combined HTML report

8. **Documentation**
   - `tests/README.md`
   - How to add new tests
   - CI/CD badge

---

## Dependencies

| Dependency | Version | Purpose | Install |
|------------|---------|---------|---------|
| bats-core | 1.11+ | Bash testing | `brew install bats-core` |
| bats-support | latest | Assertion helpers | `brew install bats-support` |
| bats-assert | latest | Assertions | `brew install bats-assert` |
| pytest | 8+ | Python test framework | `pip install pytest` |
| pytest-testinfra | 10+ | Infrastructure tests | `pip install pytest-testinfra` |
| pytest-docker-compose | 3+ | Docker lifecycle | `pip install pytest-docker-compose` |
| playwright | 1.40+ | Browser automation | `pip install playwright` |
| pytest-playwright | latest | Playwright pytest plugin | `pip install pytest-playwright` |
| pytest-cov | 5+ | Coverage reports | `pip install pytest-cov` |

---

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Unit test execution | < 60s | `time make test-unit` |
| Full suite execution | < 5 min | `time make test` |
| Coverage (month 1) | 20% | Coverage report |
| Coverage (month 3) | 50% | Coverage report |
| Flaky test rate | < 1% | Test run analysis |
| CI test feedback | < 10 min | GitHub Actions timing |
