#!/bin/bash
# Moltis Test Framework - Shared Test Utilities
# Provides assertion functions, test runners, and output formatting
#
# Usage:
#   source tests/lib/test_helpers.sh
#   test_start "my_test_case"
#   assert_eq "expected" "actual" "values should match"
#   test_pass
#
# Part of: 001-docker-deploy-improvements
# Contract: specs/001-docker-deploy-improvements/contracts/scripts.md

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# Test state
declare -g TEST_CURRENT=""
declare -g TESTS_PASSED=0
declare -g TESTS_FAILED=0
declare -g TESTS_SKIPPED=0
declare -g TESTS_TOTAL=0
declare -g TEST_START_TIME=""
declare -ga TEST_FAILURES=()
declare -ga TEST_SKIP_REASONS=()

# Output configuration
declare -g OUTPUT_JSON=false
declare -g VERBOSE=false
declare -g COLOR_ENABLED=true

# ==============================================================================
# COLORS
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Disable colors if output is not a terminal or JSON mode
init_colors() {
    if [[ "$OUTPUT_JSON" == "true" || ! -t 1 ]]; then
        COLOR_ENABLED=false
        RED=''
        GREEN=''
        YELLOW=''
        BLUE=''
        MAGENTA=''
        CYAN=''
        NC=''
    fi
}

# ==============================================================================
# LOGGING FUNCTIONS
# ==============================================================================

# Log informational message
log_info() {
    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo -e "${BLUE}[INFO]${NC} $*" >&2
    fi
}

# Log warning message
log_warn() {
    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo -e "${YELLOW}[WARN]${NC} $*" >&2
    fi
}

# Log error message
log_error() {
    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo -e "${RED}[ERROR]${NC} $*" >&2
    fi
}

# Log debug message (only in verbose mode)
log_debug() {
    if [[ "$VERBOSE" == "true" && "$OUTPUT_JSON" != "true" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $*" >&2
    fi
}

# ==============================================================================
# TEST CASE MANAGEMENT
# ==============================================================================

# Start a new test case
# Usage: test_start "test_name"
test_start() {
    local test_name="$1"
    TEST_CURRENT="$test_name"
    ((TESTS_TOTAL++)) || true

    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo ""
        echo -e "${MAGENTA}▶ Test: ${test_name}${NC}"
    fi
}

# Mark current test as passed
# Usage: test_pass
test_pass() {
    ((TESTS_PASSED++)) || true

    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo -e "${GREEN}  ✓ PASS${NC} ${TEST_CURRENT}"
    fi

    TEST_CURRENT=""
}

# Mark current test as failed
# Usage: test_fail "reason"
test_fail() {
    local reason="$1"
    ((TESTS_FAILED++)) || true
    TEST_FAILURES+=("${TEST_CURRENT}: ${reason}")

    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo -e "${RED}  ✗ FAIL${NC} ${TEST_CURRENT}"
        echo -e "${RED}    Reason: ${reason}${NC}"
    fi

    TEST_CURRENT=""
}

# Skip current test
# Usage: test_skip "reason"
test_skip() {
    local reason="$1"
    ((TESTS_SKIPPED++)) || true
    TEST_SKIP_REASONS+=("${TEST_CURRENT}: ${reason}")

    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo -e "${YELLOW}  ⊘ SKIP${NC} ${TEST_CURRENT} - ${reason}"
    fi

    TEST_CURRENT=""
}

# ==============================================================================
# ASSERTION FUNCTIONS
# ==============================================================================

# Assert two values are equal
# Usage: assert_eq "expected" "actual" "message"
assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="${3:-values should be equal}"

    if [[ "$expected" == "$actual" ]]; then
        log_debug "assert_eq: '$expected' == '$actual'"
        return 0
    else
        log_debug "assert_eq: '$expected' != '$actual'"
        test_fail "$message (expected: '$expected', got: '$actual')"
        return 1
    fi
}

# Assert two values are not equal
# Usage: assert_ne "unexpected" "actual" "message"
assert_ne() {
    local unexpected="$1"
    local actual="$2"
    local message="${3:-values should not be equal}"

    if [[ "$unexpected" != "$actual" ]]; then
        log_debug "assert_ne: '$unexpected' != '$actual'"
        return 0
    else
        log_debug "assert_ne: '$unexpected' == '$actual'"
        test_fail "$message (both values: '$unexpected')"
        return 1
    fi
}

# Assert value is true/success
# Usage: assert_true $exit_code "message"
assert_true() {
    local actual="$1"
    local message="${2:-expected true/success}"

    if [[ "$actual" == "0" || "$actual" == "true" || "$actual" == "yes" ]]; then
        log_debug "assert_true: '$actual' is true"
        return 0
    else
        log_debug "assert_true: '$actual' is not true"
        test_fail "$message (got: '$actual')"
        return 1
    fi
}

# Assert value is false/failure
# Usage: assert_false $exit_code "message"
assert_false() {
    local actual="$1"
    local message="${2:-expected false/failure}"

    if [[ "$actual" != "0" && "$actual" != "true" && "$actual" != "yes" ]]; then
        log_debug "assert_false: '$actual' is false"
        return 0
    else
        log_debug "assert_false: '$actual' is not false"
        test_fail "$message (got: '$actual')"
        return 1
    fi
}

# Assert string contains substring
# Usage: assert_contains "haystack" "needle" "message"
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-string should contain substring}"

    if [[ "$haystack" == *"$needle"* ]]; then
        log_debug "assert_contains: '$haystack' contains '$needle'"
        return 0
    else
        log_debug "assert_contains: '$haystack' does not contain '$needle'"
        test_fail "$message (haystack: '$haystack', needle: '$needle')"
        return 1
    fi
}

# Assert string matches regex pattern
# Usage: assert_matches "string" "pattern" "message"
assert_matches() {
    local string="$1"
    local pattern="$2"
    local message="${3:-string should match pattern}"

    if [[ "$string" =~ $pattern ]]; then
        log_debug "assert_matches: '$string' matches '$pattern'"
        return 0
    else
        log_debug "assert_matches: '$string' does not match '$pattern'"
        test_fail "$message (string: '$string', pattern: '$pattern')"
        return 1
    fi
}

# Assert file exists
# Usage: assert_file_exists "/path/to/file" "message"
assert_file_exists() {
    local filepath="$1"
    local message="${2:-file should exist}"

    if [[ -f "$filepath" ]]; then
        log_debug "assert_file_exists: '$filepath' exists"
        return 0
    else
        log_debug "assert_file_exists: '$filepath' does not exist"
        test_fail "$message (file: '$filepath')"
        return 1
    fi
}

# Assert directory exists
# Usage: assert_dir_exists "/path/to/dir" "message"
assert_dir_exists() {
    local dirpath="$1"
    local message="${2:-directory should exist}"

    if [[ -d "$dirpath" ]]; then
        log_debug "assert_dir_exists: '$dirpath' exists"
        return 0
    else
        log_debug "assert_dir_exists: '$dirpath' does not exist"
        test_fail "$message (directory: '$dirpath')"
        return 1
    fi
}

# Assert file contains string
# Usage: assert_file_contains "/path/to/file" "needle" "message"
assert_file_contains() {
    local filepath="$1"
    local needle="$2"
    local message="${3:-file should contain string}"

    if [[ -f "$filepath" ]] && grep -q "$needle" "$filepath"; then
        log_debug "assert_file_contains: '$filepath' contains '$needle'"
        return 0
    else
        log_debug "assert_file_contains: '$filepath' does not contain '$needle'"
        test_fail "$message (file: '$filepath', needle: '$needle')"
        return 1
    fi
}

# Assert HTTP status code
# Usage: assert_http_code 200 "https://example.com" "message"
assert_http_code() {
    local expected="$1"
    local url="$2"
    local message="${3:-HTTP status code mismatch}"
    local timeout="${4:-10}"

    local actual
    actual=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$timeout" "$url" 2>/dev/null || echo "000")

    if [[ "$actual" == "$expected" ]]; then
        log_debug "assert_http_code: '$url' returned $expected"
        return 0
    else
        log_debug "assert_http_code: '$url' returned $actual (expected $expected)"
        test_fail "$message (url: '$url', expected: $expected, got: $actual)"
        return 1
    fi
}

# Assert HTTP response contains string
# Usage: assert_http_contains "https://example.com" "needle" "message"
assert_http_contains() {
    local url="$1"
    local needle="$2"
    local message="${3:-HTTP response should contain string}"
    local timeout="${4:-10}"

    local response
    response=$(curl -s --max-time "$timeout" "$url" 2>/dev/null || echo "")

    if [[ "$response" == *"$needle"* ]]; then
        log_debug "assert_http_contains: '$url' response contains '$needle'"
        return 0
    else
        log_debug "assert_http_contains: '$url' response does not contain '$needle'"
        test_fail "$message (url: '$url', needle: '$needle')"
        return 1
    fi
}

# Assert JSON value at path
# Usage: assert_json_value '{"key":"value"}' ".key" "value" "message"
assert_json_value() {
    local json="$1"
    local path="$2"
    local expected="$3"
    local message="${4:-JSON value mismatch}"

    if ! command -v jq &> /dev/null; then
        test_fail "$message (jq not installed)"
        return 1
    fi

    local actual
    actual=$(echo "$json" | jq -r "$path" 2>/dev/null || echo "")

    if [[ "$actual" == "$expected" ]]; then
        log_debug "assert_json_value: JSON path '$path' is '$expected'"
        return 0
    else
        log_debug "assert_json_value: JSON path '$path' is '$actual' (expected '$expected')"
        test_fail "$message (path: '$path', expected: '$expected', got: '$actual')"
        return 1
    fi
}

# Assert array contains element
# Usage: assert_array_contains "element" "elem1 elem2 elem3" "message"
assert_array_contains() {
    local element="$1"
    shift
    local array=("$@")
    local message="${4:-array should contain element}"

    for item in "${array[@]}"; do
        if [[ "$item" == "$element" ]]; then
            log_debug "assert_array_contains: array contains '$element'"
            return 0
        fi
    done

    log_debug "assert_array_contains: array does not contain '$element'"
    test_fail "$message (element: '$element')"
    return 1
}

# Assert command succeeds
# Usage: assert_command_success "ls -la" "message"
assert_command_success() {
    local command="$1"
    local message="${2:-command should succeed}"

    if eval "$command" &> /dev/null; then
        log_debug "assert_command_success: command '$command' succeeded"
        return 0
    else
        log_debug "assert_command_success: command '$command' failed"
        test_fail "$message (command: '$command')"
        return 1
    fi
}

# Assert command fails
# Usage: assert_command_fails "false" "message"
assert_command_fails() {
    local command="$1"
    local message="${2:-command should fail}"

    if ! eval "$command" &> /dev/null; then
        log_debug "assert_command_fails: command '$command' failed as expected"
        return 0
    else
        log_debug "assert_command_fails: command '$command' succeeded unexpectedly"
        test_fail "$message (command: '$command')"
        return 1
    fi
}

# Assert greater than
# Usage: assert_gt 5 3 "5 should be greater than 3"
assert_gt() {
    local left="$1"
    local right="$2"
    local message="${3:-$left should be greater than $right}"

    if [[ "$left" -gt "$right" ]]; then
        log_debug "assert_gt: $left > $right"
        return 0
    else
        log_debug "assert_gt: $left is not > $right"
        test_fail "$message"
        return 1
    fi
}

# Assert less than
# Usage: assert_lt 3 5 "3 should be less than 5"
assert_lt() {
    local left="$1"
    local right="$2"
    local message="${3:-$left should be less than $right}"

    if [[ "$left" -lt "$right" ]]; then
        log_debug "assert_lt: $left < $right"
        return 0
    else
        log_debug "assert_lt: $left is not < $right"
        test_fail "$message"
        return 1
    fi
}

# ==============================================================================
# MOCKING UTILITIES
# ==============================================================================

# Mock GLM API failure
# Usage: mock_glm_failure
mock_glm_failure() {
    log_debug "Mocking GLM API failure"

    # Backup real GLM endpoint
    export GLM_API_ENDPOINT_REAL="${GLM_API_ENDPOINT:-https://open.bigmodel.cn/api/paas/v4/chat/completions}"

    # Set mock endpoint to fail
    export GLM_API_ENDPOINT="http://localhost:49999"  # Non-existent endpoint

    log_debug "GLM API endpoint mocked to fail at $GLM_API_ENDPOINT"
}

# Restore GLM API endpoint
# Usage: restore_glm
restore_glm() {
    log_debug "Restoring GLM API endpoint"

    if [[ -n "${GLM_API_ENDPOINT_REAL:-}" ]]; then
        export GLM_API_ENDPOINT="$GLM_API_ENDPOINT_REAL"
        unset GLM_API_ENDPOINT_REAL
        log_debug "GLM API endpoint restored to $GLM_API_ENDPOINT"
    else
        unset GLM_API_ENDPOINT
        log_debug "GLM API endpoint cleared"
    fi
}

# Mock Ollama failure
# Usage: mock_ollama_failure
mock_ollama_failure() {
    log_debug "Mocking Ollama failure"

    # Backup real Ollama endpoint
    export OLLAMA_HOST_REAL="${OLLAMA_HOST:-http://localhost:11434}"

    # Set mock endpoint to fail
    export OLLAMA_HOST="http://localhost:49999"  # Non-existent endpoint

    log_debug "Ollama host mocked to fail at $OLLAMA_HOST"
}

# Restore Ollama endpoint
# Usage: restore_ollama
restore_ollama() {
    log_debug "Restoring Ollama host"

    if [[ -n "${OLLAMA_HOST_REAL:-}" ]]; then
        export OLLAMA_HOST="$OLLAMA_HOST_REAL"
        unset OLLAMA_HOST_REAL
        log_debug "Ollama host restored to $OLLAMA_HOST"
    else
        unset OLLAMA_HOST
        log_debug "Ollama host cleared"
    fi
}

# Mock Docker container state
# Usage: mock_container_state "container_name" "healthy|unhealthy|running|exited"
mock_container_state() {
    local container_name="$1"
    local state="$2"

    log_debug "Mocking container '$container_name' state as '$state'"

    # Store mock state in environment variable
    export "MOCK_CONTAINER_${container_name^^}=$state"
}

# Get mocked container state
# Usage: get_mocked_container_state "container_name"
get_mocked_container_state() {
    local container_name="$1"
    local var_name="MOCK_CONTAINER_${container_name^^}"
    echo "${!var_name:-}"
}

# ==============================================================================
# OUTPUT FUNCTIONS
# ==============================================================================

# Get ISO8601 timestamp
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Generate test report in text format
generate_report() {
    local exit_code=0

    if [[ "$OUTPUT_JSON" == "true" ]]; then
        generate_report_json
        return $?
    fi

    echo ""
    echo "========================================="
    echo "  Test Results Summary"
    echo "========================================="
    echo ""

    # Overall status
    if [[ $TESTS_FAILED -eq 0 ]]; then
        if [[ $TESTS_TOTAL -gt 0 ]]; then
            echo -e "${GREEN}✓ All tests passed${NC}"
        else
            echo -e "${YELLOW}⚠ No tests were run${NC}"
        fi
    else
        echo -e "${RED}✗ $TESTS_FAILED test(s) failed${NC}"
        exit_code=1
    fi

    echo ""
    echo "Total:   $TESTS_TOTAL"
    echo -e "Passed:  ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed:  ${RED}$TESTS_FAILED${NC}"
    echo -e "Skipped: ${YELLOW}$TESTS_SKIPPED${NC}"

    # Timing
    if [[ -n "$TEST_START_TIME" ]]; then
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - TEST_START_TIME))
        echo ""
        echo "Duration: ${duration}s"
    fi

    # Failures
    if [[ ${#TEST_FAILURES[@]} -gt 0 ]]; then
        echo ""
        echo -e "${RED}Failed tests:${NC}"
        for failure in "${TEST_FAILURES[@]}"; do
            echo "  - $failure"
        done
    fi

    # Skipped tests
    if [[ ${#TEST_SKIP_REASONS[@]} -gt 0 ]]; then
        echo ""
        echo -e "${YELLOW}Skipped tests:${NC}"
        for skip in "${TEST_SKIP_REASONS[@]}"; do
            echo "  - $skip"
        done
    fi

    echo ""
    echo "========================================="

    return $exit_code
}

# Generate test report in JSON format
generate_report_json() {
    local status="pass"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        status="fail"
    elif [[ $TESTS_TOTAL -eq 0 ]]; then
        status="skip"
    fi

    # Calculate duration
    local duration=0
    if [[ -n "$TEST_START_TIME" ]]; then
        local end_time
        end_time=$(date +%s)
        duration=$((end_time - TEST_START_TIME))
    fi

    # Build JSON arrays
    local failures_json="[]"
    local skips_json="[]"

    if [[ ${#TEST_FAILURES[@]} -gt 0 ]]; then
        failures_json=$(printf '%s\n' "${TEST_FAILURES[@]}" | jq -R . | jq -s .)
    fi

    if [[ ${#TEST_SKIP_REASONS[@]} -gt 0 ]]; then
        skips_json=$(printf '%s\n' "${TEST_SKIP_REASONS[@]}" | jq -R . | jq -s .)
    fi

    # Output JSON
    jq -n \
        --arg status "$status" \
        --arg timestamp "$(get_timestamp)" \
        --argjson total "$TESTS_TOTAL" \
        --argjson passed "$TESTS_PASSED" \
        --argjson failed "$TESTS_FAILED" \
        --argjson skipped "$TESTS_SKIPPED" \
        --argjson duration "$duration" \
        --argjson failures "$failures_json" \
        --argjson skipped_tests "$skips_json" \
        '{
            status: $status,
            timestamp: $timestamp,
            summary: {
                total: $total,
                passed: $passed,
                failed: $failed,
                skipped: $skipped,
                duration_seconds: $duration
            },
            failures: $failures,
            skipped_tests: $skipped_tests
        }'

    # Return exit code based on status
    if [[ "$status" == "fail" ]]; then
        return 1
    fi
    return 0
}

# ==============================================================================
# OUTPUT MODE CONTROL
# ==============================================================================

# Enable/disable JSON output
# Usage: set_json_output true|false
set_json_output() {
    OUTPUT_JSON="$1"
    init_colors
}

# Enable/disable verbose mode
# Usage: set_verbose true|false
set_verbose() {
    VERBOSE="$1"
}

# Initialize colors (should be called after sourcing)
init_colors

# ==============================================================================
# TIMER FUNCTIONS
# ==============================================================================

# Start test suite timer
# Usage: start_timer
start_timer() {
    TEST_START_TIME=$(date +%s)
}

# Get elapsed time in seconds
# Usage: get_elapsed_time
get_elapsed_time() {
    if [[ -n "$TEST_START_TIME" ]]; then
        local current_time
        current_time=$(date +%s)
        echo $((current_time - TEST_START_TIME))
    else
        echo "0"
    fi
}
