# Research: Testing Infrastructure

**Feature**: 003-testing-infrastructure
**Date**: 2026-02-17
**Status**: Complete

---

## Technology Decisions

### 1. Unit Testing Framework for Bash Scripts

**Decision**: bats-core

**Rationale**:
- Industry standard for Bash testing
- TAP-compliant output (works with CI/CD)
- Active community, well-maintained fork
- Supports mocking via helper libraries

**Alternatives Considered**:
| Framework | Pros | Cons | Decision |
|-----------|------|------|----------|
| **bats-core** | Standard, TAP-compliant, extensible | Requires installation | ✅ Selected |
| shunit2 | Pure Bash, no dependencies | Less active, limited features | Rejected |
| assert.sh | Simple, lightweight | No TAP output, limited | Rejected |
| Manual tests | No framework needed | No automation, no reports | Rejected |

**Installation**:
```bash
# macOS
brew install bats-core bats-support bats-assert

# Linux (in Docker)
apt-get install bats
# or from source
git clone https://github.com/bats-core/bats-core.git
```

**Library**: bats-core v1.11+ | bats-support | bats-assert

---

### 2. Integration Testing for Docker Compose

**Decision**: pytest + testinfra + pytest-docker-compose

**Rationale**:
- testinfra integrates with pytest (familiar to most developers)
- pytest-docker-compose handles container lifecycle
- Can test container state, networking, health checks
- Works in CI/CD environments

**Alternatives Considered**:
| Framework | Pros | Cons | Decision |
|-----------|------|------|----------|
| **testinfra** | Python-based, pytest integration | Requires Python | ✅ Selected |
| container-structure-test | Google tool, YAML-based | Limited to image testing | Rejected |
| dgoss | Shell-based, simple | Limited assertions | Rejected |
| manual docker commands | No dependencies | Not automated | Rejected |

**Installation**:
```bash
pip install pytest pytest-testinfra pytest-docker-compose
```

**Library**: pytest-testinfra, pytest-docker-compose

---

### 3. UAT Browser Automation

**Decision**: Playwright (Python)

**Rationale**:
- Cross-browser support (Chromium, Firefox, WebKit)
- Built-in auto-wait, no flaky sleeps
- Screenshot on failure (FR-017)
- Headless and visible modes (FR-016)
- Active development, Microsoft-backed

**Alternatives Considered**:
| Framework | Pros | Cons | Decision |
|-----------|------|------|----------|
| **Playwright** | Modern, fast, reliable | Python async learning curve | ✅ Selected |
| Selenium | Industry standard, huge ecosystem | Slower, requires WebDriver | Rejected |
| Cypress | Great DX, time-travel debug | JavaScript-only, no Safari | Rejected |
| Puppeteer | Chrome team, fast | Chromium only | Rejected |

**Installation**:
```bash
pip install playwright pytest-playwright
playwright install
```

**Library**: playwright + pytest-playwright

---

### 4. Coverage Reporting

**Decision**: Custom Bash coverage script + pytest-cov

**Rationale**:
- Bash has no native coverage tool
- Custom script tracks which scripts/functions are tested
- pytest-cov for Python integration tests
- Combined HTML report

**Implementation**:
```bash
# Custom coverage tracking
# Track: files touched by tests vs total files
coverage_dir="tests/coverage"
```

---

### 5. CI/CD Integration

**Decision**: GitHub Actions matrix strategy

**Rationale**:
- Already using GitHub Actions (existing workflow)
- Matrix for parallel execution (FR-014)
- Built-in test result visualization
- PR status checks (FR-013)

**Pattern**:
```yaml
test:
  strategy:
    matrix:
      suite: [unit, integration, uat]
  steps:
    - run: make test-${{ matrix.suite }}
```

---

## Summary

| Component | Library | Version | Purpose |
|-----------|---------|---------|---------|
| Bash Unit Tests | bats-core | 1.11+ | Script testing |
| Bash Assertions | bats-assert | latest | Assertion helpers |
| Integration Tests | pytest-testinfra | 10+ | Docker/container testing |
| Docker Integration | pytest-docker-compose | 3+ | Compose lifecycle |
| UAT Automation | playwright | 1.40+ | Browser testing |
| Coverage (Python) | pytest-cov | 5+ | Coverage reports |
| Coverage (Bash) | Custom | - | Script coverage |

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| bats-core installation on CI | Use Docker image with bats pre-installed |
| Playwright browser download | Cache browsers in CI, use `playwright install` |
| Docker daemon access in CI | Use `docker:dind` or GitHub Actions container |
| Flaky tests | Retry logic, proper waits, mock external APIs |
