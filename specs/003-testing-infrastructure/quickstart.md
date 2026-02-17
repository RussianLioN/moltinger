# Quickstart: Testing Infrastructure

**Feature**: 003-testing-infrastructure
**Date**: 2026-02-17

---

## Prerequisites

- Bash 4.0+
- Python 3.11+
- Docker and Docker Compose
- Make

---

## Installation

```bash
# macOS
brew install bats-core bats-support bats-assert

# Python dependencies
pip install pytest pytest-testinfra pytest-docker-compose
pip install playwright pytest-playwright pytest-cov
playwright install

# Verify installation
bats --version
pytest --version
playwright --version
```

---

## Running Tests

### All Tests

```bash
make test
```

### By Suite

```bash
# Unit tests only (fast)
make test-unit

# Integration tests (requires Docker)
make test-integration

# UAT tests (requires running services)
make test-uat
```

### Specific Test

```bash
# Single bats test file
bats tests/unit/scripts/deploy.bats

# Single pytest test
pytest tests/integration/test_services.py -v

# Specific test case
pytest tests/integration/test_services.py::test_moltis_healthy -v
```

---

## Test Structure

```
tests/
├── unit/              # Bash script tests (bats)
│   └── scripts/
│       ├── deploy.bats
│       └── backup.bats
├── integration/       # Docker Compose tests (pytest)
│   ├── test_services.py
│   └── test_networking.py
└── uat/               # Browser tests (playwright)
    ├── test_web_ui.py
    └── test_telegram.py
```

---

## Writing Tests

### Bash Unit Test (bats)

```bash
#!/usr/bin/env bats
# tests/unit/scripts/example.bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

setup() {
  # Runs before each test
  source scripts/example.sh
}

@test "function returns expected value" {
  run my_function "input"
  assert_success
  assert_output "expected output"
}

@test "function handles error" {
  run my_function "invalid"
  assert_failure
}
```

### Integration Test (pytest + testinfra)

```python
# tests/integration/test_example.py

def test_container_running(host):
    """Test that container is running."""
    container = host.docker("moltis")
    assert container.is_running

def test_health_endpoint(host):
    """Test health check endpoint."""
    result = host.run("curl -s http://localhost:13131/health")
    assert result.rc == 0
    assert "ok" in result.stdout
```

### UAT Test (playwright)

```python
# tests/uat/test_example.py
from playwright.sync_api import Page, expect

def test_chat_sends_message(page: Page):
    """Test sending a chat message."""
    page.goto("https://moltis.ainetic.tech")
    page.fill("#message-input", "Hello!")
    page.click("#send-button")
    expect(page.locator(".response")).to_be_visible()
```

---

## CI/CD Integration

Tests run automatically on:
- Every push to `main`
- Every pull request

View results in GitHub Actions: `.github/workflows/test.yml`

---

## Coverage Reports

```bash
# Generate coverage report
make coverage

# View HTML report
open tests/reports/coverage/index.html
```

Target: 50% coverage within 3 months.

---

## Troubleshooting

### Tests fail with "command not found"
Install missing dependencies (see Installation section).

### Docker tests fail
Ensure Docker daemon is running:
```bash
docker info
```

### Playwright tests timeout
Increase timeout or check network:
```bash
pytest tests/uat/ --timeout=60
```

### Flaky tests
Check for:
- Race conditions (add proper waits)
- External dependencies (mock them)
- Resource cleanup (use fixtures)
