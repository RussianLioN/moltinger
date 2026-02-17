# Data Model: Testing Infrastructure

**Feature**: 003-testing-infrastructure
**Date**: 2026-02-17

---

## Entities

### TestSuite

Collection of related tests with execution configuration.

| Field | Type | Description |
|-------|------|-------------|
| name | string | Suite identifier (unit/integration/uat) |
| path | string | Directory path to test files |
| runner | string | Test runner command (bats/pytest) |
| timeout | integer | Max execution time in seconds |
| parallel | boolean | Can run in parallel |

**State Transitions**:
```
pending → running → passed
                  → failed
                  → skipped
```

### TestCase

Individual test with structure and assertions.

| Field | Type | Description |
|-------|------|-------------|
| id | string | Unique test identifier |
| name | string | Human-readable test name |
| file | string | Source file path |
| line | integer | Line number in source |
| suite | string | Parent suite name |
| tags | array | Categories (smoke, critical, etc.) |
| mock_required | array | External dependencies to mock |

**Example**:
```yaml
id: "deploy.bats:backup_before_deploy"
name: "Backup runs before deployment"
file: "tests/unit/scripts/deploy.bats"
suite: "unit"
tags: ["critical", "deploy"]
mock_required: ["docker", "ssh"]
```

### TestReport

Execution results for a test run.

| Field | Type | Description |
|-------|------|-------------|
| run_id | string | Unique execution identifier |
| timestamp | datetime | When tests ran |
| suite | string | Which suite was run |
| total | integer | Total tests |
| passed | integer | Passed count |
| failed | integer | Failed count |
| skipped | integer | Skipped count |
| duration_ms | integer | Total execution time |
| status | string | Overall result (pass/fail) |
| failures | array | List of failure details |

**Example**:
```json
{
  "run_id": "run-20260217-143052",
  "timestamp": "2026-02-17T14:30:52Z",
  "suite": "unit",
  "total": 15,
  "passed": 14,
  "failed": 1,
  "skipped": 0,
  "duration_ms": 1234,
  "status": "fail",
  "failures": [
    {
      "test": "deploy.bats:rollback",
      "message": "Expected 'success', got 'error'",
      "file": "tests/unit/scripts/deploy.bats",
      "line": 45
    }
  ]
}
```

### CoverageReport

Test coverage metrics.

| Field | Type | Description |
|-------|------|-------------|
| timestamp | datetime | When coverage was measured |
| total_files | integer | Files in scope |
| covered_files | integer | Files with tests |
| total_lines | integer | Total lines of code |
| covered_lines | integer | Lines executed by tests |
| percentage | float | Coverage percentage |
| by_suite | object | Breakdown by test suite |
| uncovered | array | Files without coverage |

**Example**:
```json
{
  "timestamp": "2026-02-17T14:30:52Z",
  "total_files": 12,
  "covered_files": 6,
  "total_lines": 2500,
  "covered_lines": 1250,
  "percentage": 50.0,
  "by_suite": {
    "unit": 30,
    "integration": 15,
    "uat": 5
  },
  "uncovered": [
    "scripts/health-monitor.sh"
  ]
}
```

---

## Relationships

```
TestSuite 1──* TestCase
TestRun 1──* TestReport
TestReport *──* TestCase (results)
CoverageReport 1──1 TestRun
```

---

## Validation Rules

### TestCase
- `id` must be unique across all suites
- `name` must not be empty
- `file` must exist on disk
- `mock_required` items must have corresponding mock implementations

### TestReport
- `total` must equal `passed + failed + skipped`
- `status` must be "pass" if `failed` = 0, else "fail"
- `duration_ms` must be positive

### CoverageReport
- `percentage` must equal `covered_lines / total_lines * 100`
- `percentage` must be between 0 and 100
