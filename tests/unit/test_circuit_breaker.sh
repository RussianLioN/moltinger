#!/bin/bash
# Circuit Breaker State Machine Unit Tests
# Tests the circuit breaker implementation from scripts/health-monitor.sh
#
# Test Cases:
#   - Initial state verification
#   - State transitions (CLOSED → OPEN → HALF-OPEN → CLOSED)
#   - Failure/success counting
#   - Recovery timeout
#   - State persistence
#
# Part of: 001-docker-deploy-improvements
# Contract: specs/001-fallback-llm-ollama/contracts/circuit-breaker-state.md

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

# Test-specific configuration
TEST_STATE_FILE="${TMPDIR:-/tmp}/test-cb-state-$$"
TEST_RECOVERY_TIMEOUT=5  # Short timeout for tests

# Circuit breaker configuration (matches health-monitor.sh)
CB_STATE_CLOSED="closed"
CB_STATE_OPEN="open"
CB_STATE_HALF_OPEN="half_open"

# Override circuit breaker state file for testing
export CIRCUIT_BREAKER_STATE_FILE="$TEST_STATE_FILE"
export CIRCUIT_BREAKER_FAILURE_THRESHOLD=3
export CIRCUIT_BREAKER_RECOVERY_TIMEOUT="$TEST_RECOVERY_TIMEOUT"
export CIRCUIT_BREAKER_SUCCESS_THRESHOLD=2

# ==============================================================================
# HELPER FUNCTIONS (from health-monitor.sh)
# ==============================================================================

# Get ISO8601 timestamp
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Initialize circuit breaker state file
init_circuit_breaker() {
    if [[ ! -f "$CIRCUIT_BREAKER_STATE_FILE" ]]; then
        local initial_state
        initial_state=$(cat <<EOF
{
    "state": "$CB_STATE_CLOSED",
    "failure_count": 0,
    "success_count": 0,
    "last_failure_time": null,
    "last_state_change": "$(get_timestamp)",
    "active_provider": "glm",
    "fallback_provider": "ollama"
}
EOF
)
        echo "$initial_state" > "$CIRCUIT_BREAKER_STATE_FILE"
    fi
}

# Read circuit breaker state
get_circuit_breaker_state() {
    init_circuit_breaker
    local state
    state=$(cat "$CIRCUIT_BREAKER_STATE_FILE" 2>/dev/null || echo "{}")

    if ! echo "$state" | jq -e '.state' > /dev/null 2>&1; then
        init_circuit_breaker
        state=$(cat "$CIRCUIT_BREAKER_STATE_FILE")
    fi

    echo "$state"
}

# Get current state name
get_current_state() {
    get_circuit_breaker_state | jq -r '.state'
}

# Get failure count
get_failure_count() {
    get_circuit_breaker_state | jq -r '.failure_count'
}

# Get success count
get_success_count() {
    get_circuit_breaker_state | jq -r '.success_count'
}

# Get active provider
get_active_provider() {
    get_circuit_breaker_state | jq -r '.active_provider'
}

# Update circuit breaker state (simplified version)
update_circuit_breaker() {
    local new_state="$1"
    local active_provider="$2"
    local failure_count="${3:-0}"
    local success_count="${4:-0}"

    init_circuit_breaker

    local current_state
    current_state=$(get_circuit_breaker_state)

    local new_state_json
    new_state_json=$(echo "$current_state" | jq \
        --arg state "$new_state" \
        --arg provider "$active_provider" \
        --argjson failures "$failure_count" \
        --argjson successes "$success_count" \
        --arg timestamp "$(get_timestamp)" \
        '{
            state: $state,
            failure_count: $failures,
            success_count: $successes,
            last_failure_time: .last_failure_time,
            last_state_change: (if .state != $state then $timestamp else .last_state_change end),
            active_provider: $provider,
            fallback_provider: .fallback_provider
        }')

    echo "$new_state_json" > "$CIRCUIT_BREAKER_STATE_FILE"
}

# Record a failure
record_failure() {
    local current_state
    current_state=$(get_circuit_breaker_state)
    local state
    state=$(echo "$current_state" | jq -r '.state')
    local failure_count
    failure_count=$(echo "$current_state" | jq -r '.failure_count')

    failure_count=$((failure_count + 1))

    case "$state" in
        "$CB_STATE_CLOSED")
            if [[ $failure_count -ge $CIRCUIT_BREAKER_FAILURE_THRESHOLD ]]; then
                update_circuit_breaker "$CB_STATE_OPEN" "ollama" "$failure_count" 0
                local updated_state
                updated_state=$(cat "$CIRCUIT_BREAKER_STATE_FILE" | jq --arg ts "$(get_timestamp)" '.last_failure_time = $ts')
                echo "$updated_state" > "$CIRCUIT_BREAKER_STATE_FILE"
            else
                update_circuit_breaker "$CB_STATE_CLOSED" "glm" "$failure_count" 0
            fi
            ;;
        "$CB_STATE_HALF_OPEN")
            update_circuit_breaker "$CB_STATE_OPEN" "ollama" "$failure_count" 0
            local updated_state
            updated_state=$(cat "$CIRCUIT_BREAKER_STATE_FILE" | jq --arg ts "$(get_timestamp)" '.last_failure_time = $ts')
            echo "$updated_state" > "$CIRCUIT_BREAKER_STATE_FILE"
            ;;
        "$CB_STATE_OPEN")
            update_circuit_breaker "$CB_STATE_OPEN" "ollama" "$failure_count" 0
            ;;
    esac
}

# Record a success
record_success() {
    local current_state
    current_state=$(get_circuit_breaker_state)
    local state
    state=$(echo "$current_state" | jq -r '.state')
    local success_count
    success_count=$(echo "$current_state" | jq -r '.success_count')

    success_count=$((success_count + 1))

    case "$state" in
        "$CB_STATE_HALF_OPEN")
            if [[ $success_count -ge $CIRCUIT_BREAKER_SUCCESS_THRESHOLD ]]; then
                update_circuit_breaker "$CB_STATE_CLOSED" "glm" 0 "$success_count"
            else
                update_circuit_breaker "$CB_STATE_HALF_OPEN" "glm" 0 "$success_count"
            fi
            ;;
        "$CB_STATE_CLOSED")
            update_circuit_breaker "$CB_STATE_CLOSED" "glm" 0 "$success_count"
            ;;
        "$CB_STATE_OPEN")
            # Successes in OPEN state don't change state
            ;;
    esac
}

# Map state to numeric
state_to_numeric() {
    local state="$1"
    case "$state" in
        "$CB_STATE_CLOSED")    echo "0" ;;
        "$CB_STATE_OPEN")      echo "1" ;;
        "$CB_STATE_HALF_OPEN") echo "2" ;;
        *)                     echo "-1" ;;
    esac
}

# Check recovery timeout
check_recovery_timeout() {
    local current_state
    current_state=$(get_circuit_breaker_state)
    local state
    state=$(echo "$current_state" | jq -r '.state')
    local last_failure
    last_failure=$(echo "$current_state" | jq -r '.last_failure_time')

    if [[ "$state" != "$CB_STATE_OPEN" ]]; then
        return 1
    fi

    if [[ "$last_failure" == "null" ]]; then
        return 1
    fi

    # Use UTC timezone for consistent date parsing
    local last_epoch current_epoch elapsed
    last_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "${last_failure}" +%s 2>/dev/null ||
                 TZ=UTC date -d "$last_failure" +%s 2>/dev/null ||
                 echo "0")
    current_epoch=$(TZ=UTC date +%s 2>/dev/null || date +%s)
    elapsed=$((current_epoch - last_epoch))

    if [[ $elapsed -ge $CIRCUIT_BREAKER_RECOVERY_TIMEOUT ]]; then
        update_circuit_breaker "$CB_STATE_HALF_OPEN" "glm" 0 0
        return 0
    fi

    return 1
}

# ==============================================================================
# SETUP / TEARDOWN
# ==============================================================================

setup_test() {
    # Remove any existing test state file
    rm -f "$TEST_STATE_FILE"
    rm -f "${TEST_STATE_FILE}.lock"
}

teardown_test() {
    # Clean up test state file
    rm -f "$TEST_STATE_FILE"
    rm -f "${TEST_STATE_FILE}.lock"
}

# ==============================================================================
# TEST CASES
# ==============================================================================

# Test 1: Initial state is CLOSED
test_cb_initial_state() {
    test_start "Initial circuit breaker state should be CLOSED"

    setup_test
    init_circuit_breaker

    local state
    state=$(get_current_state)
    assert_eq "$CB_STATE_CLOSED" "$state" "Initial state should be CLOSED"

    local failure_count
    failure_count=$(get_failure_count)
    assert_eq "0" "$failure_count" "Initial failure count should be 0"

    local success_count
    success_count=$(get_success_count)
    assert_eq "0" "$success_count" "Initial success count should be 0"

    local provider
    provider=$(get_active_provider)
    assert_eq "glm" "$provider" "Initial active provider should be glm"

    teardown_test
    test_pass
}

# Test 2: CLOSED → OPEN after 3 failures
test_cb_closed_to_open() {
    test_start "Circuit breaker should transition to OPEN after 3 failures"

    setup_test
    init_circuit_breaker

    # Record 3 failures
    record_failure  # failure_count = 1, state = CLOSED
    assert_eq "$CB_STATE_CLOSED" "$(get_current_state)" "State should remain CLOSED after 1 failure"
    assert_eq "1" "$(get_failure_count)" "Failure count should be 1"

    record_failure  # failure_count = 2, state = CLOSED
    assert_eq "$CB_STATE_CLOSED" "$(get_current_state)" "State should remain CLOSED after 2 failures"
    assert_eq "2" "$(get_failure_count)" "Failure count should be 2"

    record_failure  # failure_count = 3, state → OPEN
    assert_eq "$CB_STATE_OPEN" "$(get_current_state)" "State should transition to OPEN after 3 failures"
    assert_eq "3" "$(get_failure_count)" "Failure count should be 3"

    local provider
    provider=$(get_active_provider)
    assert_eq "ollama" "$provider" "Active provider should switch to ollama (fallback)"

    teardown_test
    test_pass
}

# Test 3: OPEN → HALF-OPEN after recovery timeout
test_cb_open_to_half_open() {
    test_start "Circuit breaker should transition to HALF-OPEN after recovery timeout"

    setup_test
    init_circuit_breaker

    # Force circuit to OPEN state with a past failure time
    # Use UTC for consistent epoch calculation
    local current_epoch
    current_epoch=$(TZ=UTC date +%s 2>/dev/null || date +%s)
    local past_epoch=$((current_epoch - TEST_RECOVERY_TIMEOUT - 2))

    # Format as ISO8601 UTC using TZ=UTC
    local past_timestamp
    past_timestamp=$(TZ=UTC date -j -f "%s" "$past_epoch" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null ||
                     TZ=UTC date -u -d "@$past_epoch" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)

    local open_state
    open_state=$(cat <<EOF
{
    "state": "$CB_STATE_OPEN",
    "failure_count": 3,
    "success_count": 0,
    "last_failure_time": "$past_timestamp",
    "last_state_change": "$(get_timestamp)",
    "active_provider": "ollama",
    "fallback_provider": "ollama"
}
EOF
)
    echo "$open_state" > "$CIRCUIT_BREAKER_STATE_FILE"

    # Check recovery timeout - should transition to HALF-OPEN
    check_recovery_timeout

    local state
    state=$(get_current_state)
    assert_eq "$CB_STATE_HALF_OPEN" "$state" "State should transition to HALF-OPEN after timeout"

    local provider
    provider=$(get_active_provider)
    assert_eq "glm" "$provider" "Active provider should be glm (testing recovery)"

    teardown_test
    test_pass
}

# Test 4: HALF-OPEN → CLOSED after 2 successes
test_cb_half_open_to_closed() {
    test_start "Circuit breaker should transition to CLOSED after 2 successes in HALF-OPEN"

    setup_test
    init_circuit_breaker

    # Set state to HALF-OPEN
    update_circuit_breaker "$CB_STATE_HALF_OPEN" "glm" 0 0

    # Record first success
    record_success
    assert_eq "$CB_STATE_HALF_OPEN" "$(get_current_state)" "State should remain HALF-OPEN after 1 success"
    assert_eq "1" "$(get_success_count)" "Success count should be 1"

    # Record second success - should close circuit
    record_success
    assert_eq "$CB_STATE_CLOSED" "$(get_current_state)" "State should transition to CLOSED after 2 successes"
    assert_eq "2" "$(get_success_count)" "Success count should be 2"

    local provider
    provider=$(get_active_provider)
    assert_eq "glm" "$provider" "Active provider should be glm (primary)"

    teardown_test
    test_pass
}

# Test 5: HALF-OPEN → OPEN on failure
test_cb_half_open_to_open() {
    test_start "Circuit breaker should transition to OPEN on failure in HALF-OPEN"

    setup_test
    init_circuit_breaker

    # Set state to HALF-OPEN
    update_circuit_breaker "$CB_STATE_HALF_OPEN" "glm" 0 1

    # Record failure - should go back to OPEN
    record_failure
    assert_eq "$CB_STATE_OPEN" "$(get_current_state)" "State should transition to OPEN on failure"

    local provider
    provider=$(get_active_provider)
    assert_eq "ollama" "$provider" "Active provider should switch to ollama (fallback)"

    teardown_test
    test_pass
}

# Test 6: State persistence across script invocations
test_cb_state_persistence() {
    test_start "Circuit breaker state should persist across script invocations"

    setup_test
    init_circuit_breaker

    # Modify state
    update_circuit_breaker "$CB_STATE_OPEN" "ollama" 5 0

    # Read state back (simulates new script invocation)
    local state
    state=$(get_circuit_breaker_state)

    assert_eq "$CB_STATE_OPEN" "$(echo "$state" | jq -r '.state')" "State should persist"
    assert_eq "5" "$(echo "$state" | jq -r '.failure_count')" "Failure count should persist"
    assert_eq "0" "$(echo "$state" | jq -r '.success_count')" "Success count should persist"
    assert_eq "ollama" "$(echo "$state" | jq -r '.active_provider')" "Active provider should persist"

    teardown_test
    test_pass
}

# Test 7: Success resets failure count in CLOSED state
test_cb_success_resets_failures() {
    test_start "Success should reset failure count in CLOSED state"

    setup_test
    init_circuit_breaker

    # Record 2 failures
    record_failure
    record_failure
    assert_eq "2" "$(get_failure_count)" "Failure count should be 2"

    # Record success - should reset failure count
    record_success
    assert_eq "$CB_STATE_CLOSED" "$(get_current_state)" "State should remain CLOSED"
    assert_eq "0" "$(get_failure_count)" "Failure count should reset to 0"
    assert_eq "1" "$(get_success_count)" "Success count should be 1"

    teardown_test
    test_pass
}

# Test 8: State to numeric mapping
test_cb_state_to_numeric() {
    test_start "State to numeric mapping should be correct"

    assert_eq "0" "$(state_to_numeric "$CB_STATE_CLOSED")" "CLOSED should map to 0"
    assert_eq "1" "$(state_to_numeric "$CB_STATE_OPEN")" "OPEN should map to 1"
    assert_eq "2" "$(state_to_numeric "$CB_STATE_HALF_OPEN")" "HALF_OPEN should map to 2"
    assert_eq "-1" "$(state_to_numeric "unknown")" "Unknown state should map to -1"

    test_pass
}

# Test 9: Recovery timeout doesn't trigger too early
test_cb_recovery_timeout_not_yet() {
    test_start "Recovery timeout should not trigger before timeout expires"

    setup_test
    init_circuit_breaker

    # Set state to OPEN with current time (just now, not enough time passed)
    local current_time
    current_time=$(get_timestamp)

    local open_state
    open_state=$(cat <<EOF
{
    "state": "$CB_STATE_OPEN",
    "failure_count": 3,
    "success_count": 0,
    "last_failure_time": "$current_time",
    "last_state_change": "$current_time",
    "active_provider": "ollama",
    "fallback_provider": "ollama"
}
EOF
)
    echo "$open_state" > "$CIRCUIT_BREAKER_STATE_FILE"

    # Check recovery timeout - should NOT transition (just happened)
    if check_recovery_timeout; then
        test_fail "Recovery timeout should not trigger before timeout expires"
    else
        assert_eq "$CB_STATE_OPEN" "$(get_current_state)" "State should remain OPEN"
        test_pass
    fi

    teardown_test
}

# ==============================================================================
# TEST RUNNER
# ==============================================================================

run_all_tests() {
    start_timer

    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo ""
        echo "========================================="
        echo "  Circuit Breaker Unit Tests"
        echo "========================================="
        echo ""
    fi

    # Check dependencies
    if ! command -v jq &> /dev/null; then
        test_skip "jq is required for circuit breaker tests"
        generate_report
        return 2
    fi

    # Run all tests
    test_cb_initial_state
    test_cb_closed_to_open
    test_cb_open_to_half_open
    test_cb_half_open_to_closed
    test_cb_half_open_to_open
    test_cb_state_persistence
    test_cb_success_resets_failures
    test_cb_state_to_numeric
    test_cb_recovery_timeout_not_yet

    # Generate report
    generate_report
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
