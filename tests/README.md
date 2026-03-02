# Moltis Test Framework

Тестовая инфраструктура для Moltis Agent, поддерживающая unit, integration, E2E и security тесты.

## Структура

```
tests/
├── lib/
│   └── test_helpers.sh      # Shared test utilities and assertions
├── unit/                    # Unit tests (no external dependencies)
├── integration/             # Integration tests (Docker, services)
├── e2e/                     # End-to-end tests (full stack)
├── security/                # Security tests (auth, input validation, XSS)
├── run_unit.sh              # Unit test runner
├── run_integration.sh       # Integration test runner
├── run_e2e.sh               # E2E test runner
└── run_security.sh          # Security test runner
```

## Использование

### Через Makefile

```bash
# Запуск unit тестов (по умолчанию)
make test

# Все типы тестов
make test-unit           # Unit тесты
make test-integration    # Integration тесты
make test-e2e            # E2E тесты
make test-security       # Security тесты
make test-all            # Все тесты
```

### Непосредственно через скрипты

```bash
# Unit тесты
./tests/run_unit.sh

# С JSON выводом для CI/CD
./tests/run_unit.sh --json

# С фильтрацией
./tests/run_unit.sh --filter "circuit_breaker"

# Verbose режим
./tests/run_unit.sh --verbose

# Integration тесты
./tests/run_integration.sh [--json] [--verbose] [--filter PATTERN] [--parallel]

# E2E тесты
./tests/run_e2e.sh [--json] [--verbose] [--timeout N] [--filter PATTERN] [--keep-containers]

# Security тесты
./tests/run_security.sh [--json] [--verbose] [--filter PATTERN] [--severity LEVEL]
```

## Написание тестов

### Базовый шаблон

```bash
#!/bin/bash
# My Test Description

set -euo pipefail

# Source test helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

# Test case 1
test_start "my_first_test"
assert_eq "expected" "actual" "values should match"
test_pass

# Test case 2
test_start "my_second_test"
assert_file_exists "/path/to/file" "file should exist"
test_pass

# Generate report
generate_report
```

### Доступные утверждения (assertions)

```bash
# Equality
assert_eq "expected" "actual" "message"
assert_ne "unexpected" "actual" "message"

# Boolean
assert_true $exit_code "message"
assert_false $exit_code "message"

# String
assert_contains "haystack" "needle" "message"
assert_matches "string" "pattern" "message"

# Files
assert_file_exists "/path/to/file" "message"
assert_dir_exists "/path/to/dir" "message"
assert_file_contains "/path/to/file" "needle" "message"

# HTTP
assert_http_code 200 "https://example.com" "message"
assert_http_contains "https://example.com" "needle" "message"

# JSON
assert_json_value '{"key":"value"}' ".key" "value" "message"

# Arrays
assert_array_contains "element" "elem1" "elem2" "elem3"

# Commands
assert_command_success "ls -la" "message"
assert_command_fails "false" "message"

# Numeric
assert_gt 5 3 "message"
assert_lt 3 5 "message"
```

### Mocking утилиты

```bash
# Mock GLM API failure
mock_glm_failure
# ... test failure handling ...
restore_glm

# Mock Ollama failure
mock_ollama_failure
# ... test failure handling ...
restore_ollama

# Mock container state
mock_container_state "moltis" "unhealthy"
```

### Управление выводом

```bash
# Включить JSON вывод
set_json_output true

# Включить verbose режим
set_verbose true
```

## JSON формат вывода

### Успешный запуск

```json
{
  "status": "pass",
  "timestamp": "2026-03-02T21:00:00Z",
  "summary": {
    "total": 10,
    "passed": 10,
    "failed": 0,
    "skipped": 0,
    "duration_seconds": 5
  },
  "failures": [],
  "skipped_tests": []
}
```

### С ошибками

```json
{
  "status": "fail",
  "timestamp": "2026-03-02T21:00:00Z",
  "summary": {
    "total": 10,
    "passed": 8,
    "failed": 2,
    "skipped": 0,
    "duration_seconds": 5
  },
  "failures": [
    "test_circuit_breaker: Circuit did not open after threshold",
    "test_config_validation: Invalid config accepted"
  ],
  "skipped_tests": []
}
```

### Security тесты

```json
{
  "status": "warning",
  "timestamp": "2026-03-02T21:00:00Z",
  "summary": {
    "total": 5,
    "passed": 5,
    "failed": 0,
    "skipped": 0
  },
  "vulnerabilities": {
    "total": 2,
    "by_severity": {
      "critical": 0,
      "high": 0,
      "medium": 2,
      "low": 0
    }
  },
  "findings": [
    {
      "description": "Insecure HTTP endpoint detected",
      "severity": "medium",
      "location": "config/moltis.toml"
    }
  ]
}
```

## Конвенции

1. **Имена файлов**: `test_<имя>.sh` в соответствующей директории
2. **Исполняемость**: Все тестовые файлы должны быть `chmod +x`
3. **Shebang**: `#!/bin/bash` в начале каждого файла
4. **Safety**: `set -euo pipefail` для обработки ошибок
5. **Source helpers**: Всегда sourcing `test_helpers.sh` в начале

## CI/CD интеграция

```yaml
- name: Run unit tests
  run: make test-unit

- name: Run integration tests
  run: make test-integration

- name: Run security tests
  run: make test-security --json

- name: Upload test results
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: test-results
    path: test-results.json
```

## Справка

Паттерны взяты из существующих скриптов проекта:
- `scripts/health-monitor.sh` — цвета, JSON вывод, timestamps
- `scripts/preflight-check.sh` — структура проверок, агрегация результатов

Дополнительная информация в контрактах:
- `specs/001-docker-deploy-improvements/contracts/scripts.md`
