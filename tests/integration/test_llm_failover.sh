#!/bin/bash
# test_llm_failover.sh - Integration tests for LLM provider failover
# Tests circuit breaker state transitions and provider health checks
#
# Test Scenarios:
#   - GLM healthy → circuit: CLOSED, active_provider: glm
#   - GLM down, Ollama up → circuit: OPEN, active_provider: ollama
#   - Both down → Alert triggered, circuit: OPEN
#   - Recovery → circuit transitions through HALF-OPEN to CLOSED
#
# Usage:
#   source tests/integration/test_llm_failover.sh
#
# Exit Codes:
#   0 - All tests passed
#   1 - One or more tests failed
#   2 - Dependencies missing (skip)
#
# Part of: 001-docker-deploy-improvements
# Contract: specs/001-docker-deploy-improvements/contracts/test-integration.md

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source test helpers
# shellcheck source=tests/lib/test_helpers.sh
source "$LIB_DIR/test_helpers.sh"

# Source health monitor for circuit breaker functions
# shellcheck source=scripts/health-monitor.sh
source "$PROJECT_ROOT/scripts/health-monitor.sh"

# Test configuration
TEST_TIMEOUT=60
CIRCUIT_STATE_FILE="/tmp/moltis-llm-state-test-$$.json"

# Override state file for testing
export CIRCUIT_BREAKER_STATE_FILE="$CIRCUIT_STATE_FILE"
export CIRCUIT_BREAKER_FAILURE_THRESHOLD=2  # Lower for faster tests
export CIRCUIT_BREAKER_RECOVERY_TIMEOUT=10   # 10 seconds for testing
export CIRCUIT_BREAKER_SUCCESS_THRESHOLD=1   # 1 success for recovery

# ==============================================================================
# SETUP AND TEARDOWN
# ==============================================================================

# Setup test environment
setup_llm_failover_tests() {
    log_debug "Setting up LLM failover tests"

    # Clean up any existing test state file
    rm -f "$CIRCUIT_STATE_FILE"

    # Initialize circuit breaker in test state
    init_circuit_breaker

    # Check dependencies
    local -a missing_deps=()

    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi

    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi

    if ! command -v flock &> /dev/null; then
        missing_deps+=("flock")
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        test_skip "Missing dependencies: ${missing_deps[*]}"
        return 2
    fi

    # Check if at least one provider is configured
    if [[ -z "${GLM_API_KEY:-}" ]] && [[ -z "${OLLAMA_HOST:-}" ]]; then
        test_skip "No LLM providers configured (set GLM_API_KEY or OLLAMA_HOST)"
        return 2
    fi

    return 0
}

# Cleanup test environment
cleanup_llm_failover_tests() {
    log_debug "Cleaning up LLM failover tests"

    # Remove test state file
    rm -f "$CIRCUIT_STATE_FILE"
    rm -f "${CIRCUIT_STATE_FILE}.lock"

    # Restore any mocked endpoints
    restore_glm 2>/dev/null || true
    restore_ollama 2>/dev/null || true
}

# Register cleanup on exit
trap cleanup_llm_failover_tests EXIT

# ==============================================================================
# TEST CASES
# ==============================================================================

# Test 1: Circuit breaker initialization
test_circuit_breaker_initialization() {
    test_start "circuit_breaker_initialization"

    # Reinitialize for clean state
    rm -f "$CIRCUIT_STATE_FILE"
    init_circuit_breaker

    local state
    state=$(get_circuit_breaker_state)

    # Verify initial state
    local current_state
    current_state=$(echo "$state" | jq -r '.state')
    local active_provider
    active_provider=$(echo "$state" | jq -r '.active_provider')
    local failure_count
    failure_count=$(echo "$state" | jq -r '.failure_count')

    assert_eq "$CB_STATE_CLOSED" "$current_state" "Initial state should be CLOSED"
    assert_eq "glm" "$active_provider" "Initial provider should be glm"
    assert_eq "0" "$failure_count" "Initial failure count should be 0"

    test_pass
}

# Test 2: GLM health check when configured
test_glm_health_check() {
    test_start "glm_health_check"

    if [[ -z "${GLM_API_KEY:-}" ]]; then
        test_skip "GLM_API_KEY not configured"
        return 2
    fi

    # Check GLM health
    if check_glm_health > /dev/null 2>&1; then
        log_debug "GLM API is healthy"
        test_pass
    else
        test_fail "GLM health check failed"
    fi
}

# Test 3: Ollama health check
test_ollama_health_check() {
    test_start "ollama_health_check"

    # Check Ollama health (may fail if not running)
    if check_ollama_health > /dev/null 2>&1; then
        log_debug "Ollama API is healthy"
        test_pass
    else
        log_debug "Ollama health check failed (may not be running)"
        test_skip "Ollama not available"
    fi
}

# Test 4: Circuit breaker records failure correctly
test_circuit_breaker_failure() {
    test_start "circuit_breaker_failure"

    # Reset state
    rm -f "$CIRCUIT_STATE_FILE"
    init_circuit_breaker

    local initial_state
    initial_state=$(get_circuit_breaker_state)
    local initial_failures
    initial_failures=$(echo "$initial_state" | jq -r '.failure_count')

    # Record a failure
    record_failure

    local new_state
    new_state=$(get_circuit_breaker_state)
    local new_failures
    new_failures=$(echo "$new_state" | jq -r '.failure_count')

    assert_eq "$((initial_failures + 1))" "$new_failures" "Failure count should increment"

    test_pass
}

# Test 5: Circuit breaker opens after threshold
test_circuit_breaker_opens() {
    test_start "circuit_breaker_opens"

    # Reset state
    rm -f "$CIRCUIT_STATE_FILE"
    init_circuit_breaker

    # Record failures until threshold
    record_failure  # 1
    record_failure  # 2 (threshold)

    local state
    state=$(get_circuit_breaker_state)
    local current_state
    current_state=$(echo "$state" | jq -r '.state')
    local active_provider
    active_provider=$(echo "$state" | jq -r '.active_provider')

    assert_eq "$CB_STATE_OPEN" "$current_state" "State should be OPEN after threshold"
    assert_eq "ollama" "$active_provider" "Active provider should switch to ollama"

    test_pass
}

# Test 6: Circuit breaker transitions to HALF-OPEN after timeout
test_circuit_breaker_half_open() {
    test_start "circuit_breaker_half_open"

    # Reset state and create OPEN state with old failure time
    rm -f "$CIRCUIT_STATE_FILE"
    init_circuit_breaker

    # Force OPEN state with old failure time
    local old_timestamp
    old_timestamp=$(date -u -d '20 seconds ago' +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
                    date -u -v-20S +"%Y-%m-%dT%H:%M:%SZ")

    local open_state
    open_state=$(cat "$CIRCUIT_STATE_FILE" | jq \
        --arg state "$CB_STATE_OPEN" \
        --arg provider "ollama" \
        --arg timestamp "$old_timestamp" \
        '{
            state: $state,
            failure_count: 2,
            success_count: 0,
            last_failure_time: $timestamp,
            last_state_change: $timestamp,
            active_provider: $provider,
            fallback_provider: "ollama"
        }')
    echo "$open_state" > "$CIRCUIT_STATE_FILE"

    # Trigger recovery timeout check
    check_recovery_timeout

    local state
    state=$(get_circuit_breaker_state)
    local current_state
    current_state=$(echo "$state" | jq -r '.state')

    assert_eq "$CB_STATE_HALF_OPEN" "$current_state" "State should transition to HALF-OPEN after timeout"

    test_pass
}

# Test 7: Circuit breaker closes on success
test_circuit_breaker_closes() {
    test_start "circuit_breaker_closes"

    # Reset state and create HALF-OPEN state
    rm -f "$CIRCUIT_STATE_FILE"
    init_circuit_breaker

    local half_open_state
    half_open_state=$(cat "$CIRCUIT_STATE_FILE" | jq \
        --arg state "$CB_STATE_HALF_OPEN" \
        '{
            state: $state,
            failure_count: 0,
            success_count: 0,
            last_failure_time: null,
            last_state_change: "'"$(get_timestamp)"'",
            active_provider: "glm",
            fallback_provider: "ollama"
        }')
    echo "$half_open_state" > "$CIRCUIT_STATE_FILE"

    # Record success
    record_success

    local state
    state=$(get_circuit_breaker_state)
    local current_state
    current_state=$(echo "$state" | jq -r '.state')
    local active_provider
    active_provider=$(echo "$state" | jq -r '.active_provider')

    assert_eq "$CB_STATE_CLOSED" "$current_state" "State should close after success"
    assert_eq "glm" "$active_provider" "Active provider should return to glm"

    test_pass
}

# Test 8: Get LLM provider status
test_get_llm_provider_status() {
    test_start "get_llm_provider_status"

    local status
    status=$(get_llm_provider_status)

    # Verify JSON structure
    if ! echo "$status" | jq -e '.glm' > /dev/null 2>&1; then
        test_fail "Invalid JSON structure for glm status"
        return 1
    fi

    if ! echo "$status" | jq -e '.ollama' > /dev/null 2>&1; then
        test_fail "Invalid JSON structure for ollama status"
        return 1
    fi

    # Verify status values are valid
    local glm_status
    glm_status=$(echo "$status" | jq -r '.glm')
    local ollama_status
    ollama_status=$(echo "$status" | jq -r '.ollama')

    case "$glm_status" in
        healthy|unhealthy|not_configured)
            log_debug "GLM status: $glm_status"
            ;;
        *)
            test_fail "Invalid GLM status: $glm_status"
            return 1
            ;;
    esac

    case "$ollama_status" in
        healthy|unhealthy|not_configured)
            log_debug "Ollama status: $ollama_status"
            ;;
        *)
            test_fail "Invalid Ollama status: $ollama_status"
            return 1
            ;;
    esac

    test_pass
}

# Test 9: Circuit breaker state file locking
test_circuit_breaker_locking() {
    test_start "circuit_breaker_locking"

    # Reset state
    rm -f "$CIRCUIT_STATE_FILE"
    init_circuit_breaker

    # Test that update_circuit_breaker uses locking
    # This is a basic test - proper locking tests require parallel execution
    update_circuit_breaker "$CB_STATE_CLOSED" "glm" 0 0

    if [[ ! -f "$CIRCUIT_STATE_FILE" ]]; then
        test_fail "State file not created"
        return 1
    fi

    test_pass
}

# Test 10: Evaluate LLM health (end-to-end)
test_evaluate_llm_health() {
    test_start "evaluate_llm_health"

    # Reset state
    rm -f "$CIRCUIT_STATE_FILE"
    init_circuit_breaker

    local initial_state
    initial_state=$(get_circuit_breaker_state)
    local initial_state_name
    initial_state_name=$(echo "$initial_state" | jq -r '.state')

    # Evaluate health (should not crash)
    evaluate_llm_health > /dev/null 2>&1 || true

    local final_state
    final_state=$(get_circuit_breaker_state)

    # State should remain valid JSON
    if ! echo "$final_state" | jq -e '.state' > /dev/null 2>&1; then
        test_fail "State file corrupted after evaluate_llm_health"
        return 1
    fi

    test_pass
}

# ==============================================================================
# TEST RUNNER
# ==============================================================================

# Run all LLM failover tests
run_llm_failover_tests() {
    local setup_code=0
    set +e
    setup_llm_failover_tests
    setup_code=$?
    set -e

    if [[ $setup_code -eq 2 ]]; then
        # Skip all tests
        test_start "llm_failover_tests"
        test_skip "Dependencies not met"
        return 2
    fi

    log_info "Running LLM failover integration tests..."

    # Run all test cases
    test_circuit_breaker_initialization
    test_glm_health_check || true
    test_ollama_health_check || true
    test_circuit_breaker_failure
    test_circuit_breaker_opens
    test_circuit_breaker_half_open
    test_circuit_breaker_closes
    test_get_llm_provider_status
    test_circuit_breaker_locking
    test_evaluate_llm_health
}

# Run tests if sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    start_timer
    run_llm_failover_tests
    generate_report
fi
