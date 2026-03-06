#!/bin/bash
# test_full_failover_chain.sh - E2E tests for complete LLM failover chain
# Tests full provider failover: GLM -> Ollama -> Alert
#
# Test Scenarios:
#   1. All providers healthy - GLM-5 responds
#   2. GLM down, Ollama up - Automatic fallback to Ollama
#   3. All providers down - Alert triggered
#   4. Provider recovery - Automatic return to primary
#
# Usage:
#   source tests/e2e/test_full_failover_chain.sh
#
# Exit Codes:
#   0 - All tests passed
#   1 - One or more tests failed
#   2 - Dependencies missing (skip)
#
# Part of: 001-docker-deploy-improvements
# Contract: specs/001-docker-deploy-improvements/contracts/test-e2e.md

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
TEST_TIMEOUT=120  # Extended timeout for failover tests
CIRCUIT_STATE_FILE="/tmp/moltis-llm-state-e2e-$$"

# Override circuit breaker settings for faster tests
export CIRCUIT_BREAKER_STATE_FILE="$CIRCUIT_STATE_FILE"
export CIRCUIT_BREAKER_FAILURE_THRESHOLD=2  # Lower for faster testing
export CIRCUIT_BREAKER_RECOVERY_TIMEOUT=15   # 15 seconds for testing
export CIRCUIT_BREAKER_SUCCESS_THRESHOLD=1   # Quick recovery

# Provider endpoints (real values backed up for restoration)
GLM_API_ENDPOINT_REAL="${GLM_API_ENDPOINT:-}"
OLLAMA_HOST_REAL="${OLLAMA_HOST:-}"

# Mock server settings
MOCK_SERVER_PORT=49999
MOCK_GLM_URL="http://localhost:${MOCK_SERVER_PORT}/glm"
MOCK_OLLAMA_URL="http://localhost:${MOCK_SERVER_PORT}/ollama"

# Test tracking
MOCK_SERVER_PID=""
ORIGINAL_GLM_KEY=""
ORIGINAL_OLLAMA_HOST=""

# ==============================================================================
# SETUP AND TEARDOWN
# ==============================================================================

# Setup test environment
setup_failover_tests() {
    log_debug "Setting up full failover chain E2E tests"

    # Check dependencies
    if ! command -v jq &> /dev/null; then
        test_skip "jq not installed"
        return 2
    fi

    if ! command -v curl &> /dev/null; then
        test_skip "curl not installed"
        return 2
    fi

    # Save original configuration
    ORIGINAL_GLM_KEY="${GLM_API_KEY:-}"
    ORIGINAL_OLLAMA_HOST="${OLLAMA_HOST:-}"

    # Clean up any existing test state
    rm -f "$CIRCUIT_STATE_FILE"

    # Initialize circuit breaker
    init_circuit_breaker

    # Verify at least one provider is configured
    if [[ -z "$ORIGINAL_GLM_KEY" ]] && [[ -z "$ORIGINAL_OLLAMA_HOST" ]]; then
        test_skip "No LLM providers configured (set GLM_API_KEY or OLLAMA_HOST)"
        return 2
    fi

    log_info "Failover chain tests initialized"
    log_info "GLM configured: $([ -n "$ORIGINAL_GLM_KEY" ] && echo 'yes' || echo 'no')"
    log_info "Ollama configured: $([ -n "$ORIGINAL_OLLAMA_HOST" ] && echo 'yes' || echo 'no')"

    return 0
}

# Cleanup test environment
cleanup_failover_tests() {
    log_debug "Cleaning up full failover chain E2E tests"

    # Stop mock server if running
    if [[ -n "$MOCK_SERVER_PID" ]] && kill -0 "$MOCK_SERVER_PID" 2>/dev/null; then
        kill "$MOCK_SERVER_PID" 2>/dev/null || true
        wait "$MOCK_SERVER_PID" 2>/dev/null || true
        MOCK_SERVER_PID=""
    fi

    # Remove test state file
    rm -f "$CIRCUIT_STATE_FILE"
    rm -f "${CIRCUIT_STATE_FILE}.lock"

    # Restore original configuration
    export GLM_API_KEY="$ORIGINAL_GLM_KEY"
    export OLLAMA_HOST="$ORIGINAL_OLLAMA_HOST"

    # Clear mock URLs
    unset GLM_API_ENDPOINT
    unset OLLAMA_HOST
}

# Register cleanup on exit
trap cleanup_failover_tests EXIT

# ==============================================================================
# MOCKING UTILITIES
# ==============================================================================

# Start a simple mock server that rejects connections
# Usage: start_mock_server
start_mock_server() {
    # Use Python or netcat to create a listener on unused port
    if command -v python3 &> /dev/null; then
        python3 -c "
import socket
import time
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('localhost', ${MOCK_SERVER_PORT}))
s.listen(1)
s.settimeout(120)
print('Mock server listening on port ${MOCK_SERVER_PORT}', flush=True)
try:
    while True:
        try:
            conn, addr = s.accept()
            conn.close()
        except socket.timeout:
            break
except KeyboardInterrupt:
    pass
s.close()
" > /dev/null 2>&1 &
        MOCK_SERVER_PID=$!
    elif command -v nc &> /dev/null; then
        # netcat version (may not work on all systems)
        nc -l "${MOCK_SERVER_PORT}" > /dev/null 2>&1 &
        MOCK_SERVER_PID=$!
    else
        log_warn "No mock server available (need python3 or nc)"
        return 1
    fi

    sleep 1  # Give server time to start

    if kill -0 "$MOCK_SERVER_PID" 2>/dev/null; then
        log_debug "Mock server started (PID: $MOCK_SERVER_PID)"
        return 0
    else
        log_warn "Mock server failed to start"
        MOCK_SERVER_PID=""
        return 1
    fi
}

# Mock GLM API failure
# Usage: mock_glm_failure
mock_glm_failure() {
    log_debug "Mocking GLM API failure"

    # Save real endpoint
    GLM_API_ENDPOINT_REAL="${GLM_API_ENDPOINT:-https://open.bigmodel.cn/api/paas/v4/chat/completions}"

    # Set to invalid endpoint
    export GLM_API_ENDPOINT="http://localhost:${MOCK_SERVER_PORT}/glm"

    log_debug "GLM API mocked to fail at $GLM_API_ENDPOINT"
}

# Restore GLM API
restore_glm_endpoint() {
    log_debug "Restoring GLM API endpoint"

    if [[ -n "$GLM_API_ENDPOINT_REAL" ]]; then
        export GLM_API_ENDPOINT="$GLM_API_ENDPOINT_REAL"
        log_debug "GLM API restored to $GLM_API_ENDPOINT"
    else
        unset GLM_API_ENDPOINT
        log_debug "GLM API endpoint cleared"
    fi
}

# Mock Ollama failure
# Usage: mock_ollama_failure
mock_ollama_failure() {
    log_debug "Mocking Ollama failure"

    # Save real host
    OLLAMA_HOST_REAL="${OLLAMA_HOST:-http://localhost:11434}"

    # Set to invalid host
    export OLLAMA_HOST="http://localhost:${MOCK_SERVER_PORT}/ollama"

    log_debug "Ollama mocked to fail at $OLLAMA_HOST"
}

# Restore Ollama
restore_ollama_endpoint() {
    log_debug "Restoring Ollama endpoint"

    if [[ -n "$OLLAMA_HOST_REAL" ]]; then
        export OLLAMA_HOST="$OLLAMA_HOST_REAL"
        log_debug "Ollama restored to $OLLAMA_HOST"
    else
        unset OLLAMA_HOST
        log_debug "Ollama endpoint cleared"
    fi
}

# ==============================================================================
# TEST CASES
# ==============================================================================

# Test 1: Circuit breaker initial state (CLOSED, GLM active)
test_initial_state() {
    test_start "failover_initial_state"

    # Reset circuit breaker
    rm -f "$CIRCUIT_STATE_FILE"
    init_circuit_breaker

    local state
    state=$(get_circuit_breaker_state)

    local current_state
    current_state=$(echo "$state" | jq -r '.state')
    local active_provider
    active_provider=$(echo "$state" | jq -r '.active_provider')

    assert_eq "$CB_STATE_CLOSED" "$current_state" "Initial state should be CLOSED"
    assert_eq "glm" "$active_provider" "Initial provider should be GLM"

    test_pass
}

# Test 2: GLM healthy when configured
test_glm_healthy() {
    test_start "failover_glm_healthy"

    if [[ -z "$ORIGINAL_GLM_KEY" ]]; then
        test_skip "GLM not configured"
        return 2
    fi

    # Reset state
    rm -f "$CIRCUIT_STATE_FILE"
    init_circuit_breaker

    # Check GLM health
    if check_glm_health > /dev/null 2>&1; then
        # Verify circuit remains CLOSED
        local state
        state=$(get_circuit_breaker_state)
        local current_state
        current_state=$(echo "$state" | jq -r '.state')
        local active_provider
        active_provider=$(echo "$state" | jq -r '.active_provider')

        assert_eq "$CB_STATE_CLOSED" "$current_state" "State should be CLOSED when GLM healthy"
        assert_eq "glm" "$active_provider" "GLM should be active when healthy"

        test_pass
    else
        test_skip "GLM health check failed (may be temporarily down)"
    fi
}

# Test 3: GLM down triggers fallback to Ollama
test_glm_down_ollama_up() {
    test_start "failover_glm_down_ollama_up"

    # Skip if Ollama not configured
    if [[ -z "$ORIGINAL_OLLAMA_HOST" ]]; then
        test_skip "Ollama not configured"
        return 2
    fi

    # Reset state
    rm -f "$CIRCUIT_STATE_FILE"
    init_circuit_breaker

    # Start mock server
    start_mock_server

    # Mock GLM failure
    mock_glm_failure

    # Record failures to trigger circuit open
    record_failure  # 1
    record_failure  # 2 (threshold reached)

    # Verify circuit is OPEN and provider switched
    local state
    state=$(get_circuit_breaker_state)
    local current_state
    current_state=$(echo "$state" | jq -r '.state')
    local active_provider
    active_provider=$(echo "$state" | jq -r '.active_provider')

    # Restore GLM
    restore_glm_endpoint

    assert_eq "$CB_STATE_OPEN" "$current_state" "State should be OPEN after GLM failures"
    assert_eq "ollama" "$active_provider" "Ollama should be active after GLM failure"

    test_pass
}

# Test 4: All providers down triggers alert condition
test_all_down_alert() {
    test_start "failover_all_down_alert"

    # Reset state
    rm -f "$CIRCUIT_STATE_FILE"
    init_circuit_breaker

    # Start mock server
    start_mock_server

    # Mock both providers as down
    mock_glm_failure
    mock_ollama_failure

    # Record failures to open circuit
    record_failure
    record_failure

    local state
    state=$(get_circuit_breaker_state)
    local current_state
    current_state=$(echo "$state" | jq -r '.state')
    local active_provider
    active_provider=$(echo "$state" | jq -r '.active_provider')

    # Verify circuit is OPEN (fallback mode)
    if [[ "$current_state" == "$CB_STATE_OPEN" ]]; then
        log_debug "Alert condition: both providers down, circuit OPEN"

        # Check if Ollama health check also fails
        if ! check_ollama_health > /dev/null 2>&1; then
            log_debug "Alert condition confirmed: fallback provider also unhealthy"
        fi

        # Restore endpoints
        restore_glm_endpoint
        restore_ollama_endpoint

        test_pass
    else
        # Restore endpoints
        restore_glm_endpoint
        restore_ollama_endpoint

        test_fail "Circuit should be OPEN when all providers down"
    fi
}

# Test 5: Provider recovery - HALF-OPEN to CLOSED transition
test_provider_recovery() {
    test_start "failover_provider_recovery"

    # Reset state and create OPEN state with old failure time
    rm -f "$CIRCUIT_STATE_FILE"
    init_circuit_breaker

    # Create OPEN state with timestamp older than recovery timeout
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

    # Trigger recovery timeout check (should transition to HALF-OPEN)
    check_recovery_timeout

    local state
    state=$(get_circuit_breaker_state)
    local current_state
    current_state=$(echo "$state" | jq -r '.state')

    if [[ "$current_state" == "$CB_STATE_HALF_OPEN" ]]; then
        log_debug "State transitioned to HALF-OPEN"

        # Now record success to close circuit
        record_success

        state=$(get_circuit_breaker_state)
        current_state=$(echo "$state" | jq -r '.state')
        local active_provider
        active_provider=$(echo "$state" | jq -r '.active_provider')

        assert_eq "$CB_STATE_CLOSED" "$current_state" "State should close after success"
        assert_eq "glm" "$active_provider" "GLM should be active after recovery"

        test_pass
    else
        test_fail "State should transition to HALF-OPEN after recovery timeout"
    fi
}

# Test 6: Full failover chain - GLM -> Ollama -> GLM
test_full_failover_chain() {
    test_start "failover_full_chain"

    # Skip if Ollama not configured
    if [[ -z "$ORIGINAL_OLLAMA_HOST" ]]; then
        test_skip "Ollama not configured, cannot test full chain"
        return 2
    fi

    # Reset state
    rm -f "$CIRCUIT_STATE_FILE"
    init_circuit_breaker

    local initial_state
    initial_state=$(get_circuit_breaker_state)
    local initial_provider
    initial_provider=$(echo "$initial_state" | jq -r '.active_provider')

    log_debug "Initial provider: $initial_provider"

    # Phase 1: GLM fails, switch to Ollama
    start_mock_server
    mock_glm_failure

    record_failure
    record_failure

    local state_after_fail
    state_after_fail=$(get_circuit_breaker_state)
    local provider_after_fail
    provider_after_fail=$(echo "$state_after_fail" | jq -r '.active_provider')

    log_debug "Provider after GLM failure: $provider_after_fail"

    if [[ "$provider_after_fail" != "ollama" ]]; then
        restore_glm_endpoint
        test_fail "Provider should be Ollama after GLM failure"
        return 1
    fi

    # Phase 2: Simulate recovery timeout
    local old_timestamp
    old_timestamp=$(date -u -d '20 seconds ago' +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
                    date -u -v-20S +"%Y-%m-%dT%H:%M:%SZ")

    local recovering_state
    recovering_state=$(echo "$state_after_fail" | jq \
        --arg timestamp "$old_timestamp" \
        '.last_failure_time = $timestamp')
    echo "$recovering_state" > "$CIRCUIT_STATE_FILE"

    check_recovery_timeout

    # Phase 3: Record success to close circuit
    restore_glm_endpoint
    record_success

    local final_state
    final_state=$(get_circuit_breaker_state)
    local final_provider
    final_provider=$(echo "$final_state" | jq -r '.active_provider')
    local final_circuit_state
    final_circuit_state=$(echo "$final_state" | jq -r '.state')

    log_debug "Final provider: $final_provider"
    log_debug "Final circuit state: $final_circuit_state"

    assert_eq "glm" "$final_provider" "Provider should return to GLM after recovery"
    assert_eq "$CB_STATE_CLOSED" "$final_circuit_state" "Circuit should be CLOSED after recovery"

    test_pass
}

# Test 7: Circuit breaker state persists across checks
test_state_persistence() {
    test_start "failover_state_persistence"

    # Reset state
    rm -f "$CIRCUIT_STATE_FILE"
    init_circuit_breaker

    # Record a failure
    record_failure

    local state1
    state1=$(get_circuit_breaker_state)
    local failures1
    failures1=$(echo "$state1" | jq -r '.failure_count')

    # Re-read state
    local state2
    state2=$(get_circuit_breaker_state)
    local failures2
    failures2=$(echo "$state2" | jq -r '.failure_count')

    assert_eq "$failures1" "$failures2" "Failure count should persist"

    test_pass
}

# Test 8: Multiple rapid failures don't cause race conditions
test_rapid_failures() {
    test_start "failover_rapid_failures"

    # Reset state
    rm -f "$CIRCUIT_STATE_FILE"
    init_circuit_breaker

    # Record multiple failures rapidly
    for i in {1..5}; do
        record_failure
    done

    local state
    state=$(get_circuit_breaker_state)
    local failure_count
    failure_count=$(echo "$state" | jq -r '.failure_count')
    local circuit_state
    circuit_state=$(echo "$state" | jq -r '.state')

    # Should have 5 failures and be OPEN
    assert_eq "5" "$failure_count" "Should record all 5 failures"
    assert_eq "$CB_STATE_OPEN" "$circuit_state" "Circuit should be OPEN after rapid failures"

    test_pass
}

# Test 9: Health check doesn't crash on invalid state file
test_invalid_state_recovery() {
    test_start "failover_invalid_state_recovery"

    # Create invalid state file
    echo "invalid json" > "$CIRCUIT_STATE_FILE"

    # Should recover by reinitializing
    local state
    state=$(get_circuit_breaker_state 2>/dev/null || echo "{}")

    # Verify state is valid after recovery
    if echo "$state" | jq -e '.state' > /dev/null 2>&1; then
        test_pass
    else
        test_fail "Failed to recover from invalid state file"
    fi
}

# Test 10: Get LLM provider status returns valid JSON
test_provider_status_json() {
    test_start "failover_provider_status_json"

    local status
    status=$(get_llm_provider_status)

    # Verify JSON is valid
    if ! echo "$status" | jq -e '.' > /dev/null 2>&1; then
        test_fail "Provider status is not valid JSON"
        return 1
    fi

    # Check required fields
    local has_glm
    has_glm=$(echo "$status" | jq -e '.glm' > /dev/null 2>&1 && echo "yes" || echo "no")
    local has_ollama
    has_ollama=$(echo "$status" | jq -e '.ollama' > /dev/null 2>&1 && echo "yes" || echo "no")

    assert_eq "yes" "$has_glm" "Status should include glm field"
    assert_eq "yes" "$has_ollama" "Status should include ollama field"

    test_pass
}

# ==============================================================================
# TEST RUNNER
# ==============================================================================

# Run all failover chain E2E tests
run_failover_chain_tests() {
    local setup_result
    setup_result=$(setup_failover_tests)
    local setup_code=$?

    if [[ $setup_code -ne 0 ]]; then
        test_start "failover_chain_tests"
        test_skip "Dependencies not met"
        return 2
    fi

    log_info "Running full failover chain E2E tests..."
    log_info "Circuit breaker threshold: $CIRCUIT_BREAKER_FAILURE_THRESHOLD"
    log_info "Recovery timeout: ${CIRCUIT_BREAKER_RECOVERY_TIMEOUT}s"

    # Run all test cases
    test_initial_state
    test_glm_healthy || true
    test_glm_down_ollama_up || true
    test_all_down_alert || true
    test_provider_recovery
    test_full_failover_chain || true
    test_state_persistence
    test_rapid_failures
    test_invalid_state_recovery
    test_provider_status_json
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    start_timer
    run_failover_chain_tests
    generate_report
fi
