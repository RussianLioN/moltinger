#!/bin/bash
# Prometheus Metrics Unit Tests
# Tests Prometheus metrics format and content
#
# Test Cases:
#   - Metric naming conventions
#   - Required metrics exist
#   - Metric labels and values
#   - HELP and TYPE annotations
#
# Part of: 001-docker-deploy-improvements
# Contract: specs/001-fallback-llm-ollama/contracts/prometheus-metrics.md

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

# Circuit breaker states (from health-monitor.sh)
CB_STATE_CLOSED="closed"
CB_STATE_OPEN="open"
CB_STATE_HALF_OPEN="half_open"

# Test state file
TEST_STATE_FILE="${TMPDIR:-/tmp}/test-metrics-cb-state-$$"
export CIRCUIT_BREAKER_STATE_FILE="$TEST_STATE_FILE"

# Counter file for fallback metrics
TEST_COUNTER_FILE="${TMPDIR:-/tmp}/test-metrics-fallback-counter-$$"
export FALLBACK_COUNTER_FILE="$TEST_COUNTER_FILE"

# ==============================================================================
# HELPER FUNCTIONS (from health-monitor.sh)
# ==============================================================================

# Get ISO8601 timestamp
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Map circuit breaker state to numeric value
state_to_numeric() {
    local state="$1"
    case "$state" in
        "$CB_STATE_CLOSED")    echo "0" ;;
        "$CB_STATE_OPEN")      echo "1" ;;
        "$CB_STATE_HALF_OPEN") echo "2" ;;
        *)                     echo "-1" ;;
    esac
}

# Initialize circuit breaker state file
init_test_state() {
    cat > "$CIRCUIT_BREAKER_STATE_FILE" << EOF
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
    echo "0" > "$FALLBACK_COUNTER_FILE"
}

# Get circuit breaker state
get_circuit_breaker_state() {
    cat "$CIRCUIT_BREAKER_STATE_FILE" 2>/dev/null || echo "{}"
}

# Get fallback counter
get_fallback_counter() {
    cat "$FALLBACK_COUNTER_FILE" 2>/dev/null || echo "0"
}

# Increment fallback counter
increment_fallback_counter() {
    local counter
    counter=$(get_fallback_counter)
    counter=$((counter + 1))
    echo "$counter" > "$FALLBACK_COUNTER_FILE"
    echo "$counter"
}

# Generate mock Prometheus metrics
generate_mock_metrics() {
    local cb_state
    cb_state=$(get_circuit_breaker_state)
    local state
    state=$(echo "$cb_state" | jq -r '.state')
    local failure_count
    failure_count=$(echo "$cb_state" | jq -r '.failure_count')
    local success_count
    success_count=$(echo "$cb_state" | jq -r '.success_count')
    local active_provider
    active_provider=$(echo "$cb_state" | jq -r '.active_provider')
    local fallback_total
    fallback_total=$(get_fallback_counter)

    local state_numeric
    state_numeric=$(state_to_numeric "$state")

    cat << EOF
# HELP llm_provider_available Whether the LLM provider is available (1=available, 0=unavailable)
# TYPE llm_provider_available gauge
llm_provider_available{provider="glm"} 1
llm_provider_available{provider="ollama"} 1

# HELP llm_fallback_triggered_total Total number of times fallback was triggered
# TYPE llm_fallback_triggered_total counter
llm_fallback_triggered_total $fallback_total

# HELP moltis_circuit_state Circuit breaker state (0=closed, 1=open, 2=half-open)
# TYPE moltis_circuit_state gauge
moltis_circuit_state $state_numeric

# HELP moltis_circuit_failures Current failure count in circuit breaker
# TYPE moltis_circuit_failures gauge
moltis_circuit_failures $failure_count

# HELP moltis_circuit_successes Current success count in circuit breaker
# TYPE moltis_circuit_successes gauge
moltis_circuit_successes $success_count

# HELP moltis_active_provider Currently active LLM provider (1=glm, 0=ollama)
# TYPE moltis_active_provider gauge
moltis_active_provider{provider="$active_provider"} 1
EOF
}

# ==============================================================================
# SETUP / TEARDOWN
# ==============================================================================

setup_test() {
    rm -f "$TEST_STATE_FILE"
    rm -f "$TEST_COUNTER_FILE"
    init_test_state
}

teardown_test() {
    rm -f "$TEST_STATE_FILE"
    rm -f "$TEST_COUNTER_FILE"
}

# ==============================================================================
# VALIDATION FUNCTIONS
# ==============================================================================

# Check if metric name follows Prometheus conventions
validate_metric_name() {
    local metric_line="$1"

    # Extract metric name (everything before { or space)
    local metric_name
    metric_name=$(echo "$metric_line" | sed 's/{.*//' | sed 's/ .*//')

    # Prometheus metric names should match: [a-zA-Z_:][a-zA-Z0-9_:]*
    if echo "$metric_name" | grep -qE '^[a-zA-Z_:][a-zA-Z0-9_:]*$'; then
        return 0
    else
        return 1
    fi
}

# Check if metric has proper HELP annotation
validate_metric_help() {
    local metrics_output="$1"
    local metric_name="$2"

    # Extract base metric name (without labels)
    local base_name
    base_name=$(echo "$metric_name" | sed 's/{.*//')

    if echo "$metrics_output" | grep -q "^# HELP $base_name "; then
        return 0
    else
        return 1
    fi
}

# Check if metric has proper TYPE annotation
validate_metric_type() {
    local metrics_output="$1"
    local metric_name="$2"

    # Extract base metric name (without labels)
    local base_name
    base_name=$(echo "$metric_name" | sed 's/{.*//')

    if echo "$metrics_output" | grep -q "^# TYPE $base_name "; then
        return 0
    else
        return 1
    fi
}

# Check if metric line has correct format
validate_metric_line() {
    local line="$1"

    # Format: metric_name{labels} value or metric_name value
    if echo "$line" | grep -qE '^[a-zA-Z_:][a-zA-Z0-9_:]*(\{[^}]*\})?\s+[0-9.e+-]+$'; then
        return 0
    else
        return 1
    fi
}

# ==============================================================================
# TEST CASES
# ==============================================================================

# Test 1: Metric naming conventions
test_metric_naming_conventions() {
    test_start "Metrics should follow Prometheus naming conventions"

    setup_test
    local metrics
    metrics=$(generate_mock_metrics)

    local failed=0

    # Extract metric names and validate
    while IFS= read -r line; do
        if [[ "$line" =~ ^# ]] || [[ -z "$line" ]]; then
            continue
        fi

        local metric_name
        metric_name=$(echo "$line" | awk '{print $1}')

        if ! validate_metric_name "$metric_name"; then
            log_warn "Invalid metric name: $metric_name"
            failed=1
        fi
    done <<< "$metrics"

    teardown_test

    if [[ $failed -eq 0 ]]; then
        test_pass
    else
        test_fail "Some metric names don't follow Prometheus conventions"
    fi
}

# Test 2: llm_provider_available metric exists
test_metric_llm_provider_available() {
    test_start "llm_provider_available metric should exist with correct format"

    setup_test
    local metrics
    metrics=$(generate_mock_metrics)

    # Check HELP annotation
    if ! validate_metric_help "$metrics" "llm_provider_available"; then
        test_fail "Missing HELP annotation for llm_provider_available"
        teardown_test
        return
    fi

    # Check TYPE annotation
    if ! validate_metric_type "$metrics" "llm_provider_available"; then
        test_fail "Missing TYPE annotation for llm_provider_available"
        teardown_test
        return
    fi

    # Check metric exists for glm provider
    if ! echo "$metrics" | grep -q 'llm_provider_available{provider="glm"}'; then
        test_fail "Missing llm_provider_available for glm provider"
        teardown_test
        return
    fi

    # Check metric exists for ollama provider
    if ! echo "$metrics" | grep -q 'llm_provider_available{provider="ollama"}'; then
        test_fail "Missing llm_provider_available for ollama provider"
        teardown_test
        return
    fi

    # Check value is 0 or 1
    local glm_value
    glm_value=$(echo "$metrics" | grep 'llm_provider_available{provider="glm"}' | awk '{print $2}')
    if [[ "$glm_value" != "0" ]] && [[ "$glm_value" != "1" ]]; then
        test_fail "llm_provider_available value should be 0 or 1, got: $glm_value"
        teardown_test
        return
    fi

    teardown_test
    test_pass
}

# Test 3: moltis_circuit_state metric exists with correct values
test_metric_circuit_state() {
    test_start "moltis_circuit_state metric should exist with valid values (0, 1, 2)"

    setup_test
    local metrics
    metrics=$(generate_mock_metrics)

    # Check HELP annotation
    if ! validate_metric_help "$metrics" "moltis_circuit_state"; then
        test_fail "Missing HELP annotation for moltis_circuit_state"
        teardown_test
        return
    fi

    # Check TYPE annotation (should be gauge)
    if ! echo "$metrics" | grep -q '^# TYPE moltis_circuit_state gauge'; then
        test_fail "moltis_circuit_state should be type 'gauge'"
        teardown_test
        return
    fi

    # Check metric line format
    local state_line
    state_line=$(echo "$metrics" | grep '^moltis_circuit_state ')
    if [[ -z "$state_line" ]]; then
        test_fail "moltis_circuit_state metric line not found"
        teardown_test
        return
    fi

    # Check value is valid (0, 1, or 2)
    local state_value
    state_value=$(echo "$state_line" | awk '{print $2}')
    if [[ "$state_value" != "0" ]] && [[ "$state_value" != "1" ]] && [[ "$state_value" != "2" ]]; then
        test_fail "moltis_circuit_state value should be 0, 1, or 2, got: $state_value"
        teardown_test
        return
    fi

    teardown_test
    test_pass
}

# Test 4: llm_fallback_triggered_total counter exists
test_metric_fallback_total() {
    test_start "llm_fallback_triggered_total counter metric should exist"

    setup_test
    local metrics
    metrics=$(generate_mock_metrics)

    # Check HELP annotation
    if ! validate_metric_help "$metrics" "llm_fallback_triggered_total"; then
        test_fail "Missing HELP annotation for llm_fallback_triggered_total"
        teardown_test
        return
    fi

    # Check TYPE annotation (should be counter)
    if ! echo "$metrics" | grep -q '^# TYPE llm_fallback_triggered_total counter'; then
        test_fail "llm_fallback_triggered_total should be type 'counter'"
        teardown_test
        return
    fi

    # Check metric exists
    if ! echo "$metrics" | grep -q '^llm_fallback_triggered_total '; then
        test_fail "llm_fallback_triggered_total metric line not found"
        teardown_test
        return
    fi

    # Check value is non-negative integer
    local counter_value
    counter_value=$(echo "$metrics" | grep '^llm_fallback_triggered_total ' | awk '{print $2}')
    if ! [[ "$counter_value" =~ ^[0-9]+$ ]]; then
        test_fail "llm_fallback_triggered_total value should be non-negative integer, got: $counter_value"
        teardown_test
        return
    fi

    teardown_test
    test_pass
}

# Test 5: All metrics have HELP and TYPE annotations
test_metric_help_text() {
    test_start "All metrics should have HELP and TYPE annotations"

    setup_test
    local metrics
    metrics=$(generate_mock_metrics)

    # Extract all metric base names (non-comment lines, without labels)
    local metric_names=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^# ]] || [[ -z "$line" ]]; then
            continue
        fi
        # Extract metric name without labels
        local metric_name
        metric_name=$(echo "$line" | awk '{print $1}' | sed 's/{.*//')
        # Add unique names only
        if [[ ! " ${metric_names[*]} " =~ " ${metric_name} " ]]; then
            metric_names+=("$metric_name")
        fi
    done <<< "$metrics"

    local failed=0

    for metric_name in "${metric_names[@]}"; do
        if ! validate_metric_help "$metrics" "$metric_name"; then
            log_warn "Missing HELP for: $metric_name"
            failed=1
        fi
        if ! validate_metric_type "$metrics" "$metric_name"; then
            log_warn "Missing TYPE for: $metric_name"
            failed=1
        fi
    done

    teardown_test

    if [[ $failed -eq 0 ]]; then
        test_pass
    else
        test_fail "Some metrics missing HELP or TYPE annotations"
    fi
}

# Test 6: Circuit state mapping is correct
test_metric_state_mapping() {
    test_start "Circuit breaker state should map to correct numeric values"

    setup_test

    # Test CLOSED → 0
    cat > "$CIRCUIT_BREAKER_STATE_FILE" << EOF
{"state": "closed", "failure_count": 0, "success_count": 0, "last_failure_time": null, "last_state_change": "$(get_timestamp)", "active_provider": "glm", "fallback_provider": "ollama"}
EOF
    assert_eq "0" "$(state_to_numeric "closed")" "CLOSED state should map to 0"

    # Test OPEN → 1
    cat > "$CIRCUIT_BREAKER_STATE_FILE" << EOF
{"state": "open", "failure_count": 3, "success_count": 0, "last_failure_time": "$(get_timestamp)", "last_state_change": "$(get_timestamp)", "active_provider": "ollama", "fallback_provider": "ollama"}
EOF
    assert_eq "1" "$(state_to_numeric "open")" "OPEN state should map to 1"

    # Test HALF_OPEN → 2
    cat > "$CIRCUIT_BREAKER_STATE_FILE" << EOF
{"state": "half_open", "failure_count": 0, "success_count": 1, "last_failure_time": null, "last_state_change": "$(get_timestamp)", "active_provider": "glm", "fallback_provider": "ollama"}
EOF
    assert_eq "2" "$(state_to_numeric "half_open")" "HALF_OPEN state should map to 2"

    teardown_test
    test_pass
}

# Test 7: Fallback counter increments correctly
test_metric_fallback_counter() {
    test_start "Fallback counter should increment correctly"

    setup_test

    # Initial value should be 0
    assert_eq "0" "$(get_fallback_counter)" "Initial fallback counter should be 0"

    # Increment and check
    assert_eq "1" "$(increment_fallback_counter)" "First increment should return 1"
    assert_eq "1" "$(get_fallback_counter)" "Counter should be 1 after first increment"

    assert_eq "2" "$(increment_fallback_counter)" "Second increment should return 2"
    assert_eq "2" "$(get_fallback_counter)" "Counter should be 2 after second increment"

    # Verify in metrics output
    local metrics
    metrics=$(generate_mock_metrics)
    local counter_value
    counter_value=$(echo "$metrics" | grep '^llm_fallback_triggered_total ' | awk '{print $2}')
    assert_eq "2" "$counter_value" "Metrics output should reflect counter value"

    teardown_test
    test_pass
}

# Test 8: Metric values update with state changes
test_metric_state_changes() {
    test_start "Metric values should reflect state changes"

    setup_test

    # Initial state: CLOSED
    local metrics
    metrics=$(generate_mock_metrics)
    local state_value
    state_value=$(echo "$metrics" | grep '^moltis_circuit_state ' | awk '{print $2}')
    assert_eq "0" "$state_value" "Initial state should be 0 (CLOSED)"

    # Change to OPEN
    cat > "$CIRCUIT_BREAKER_STATE_FILE" << EOF
{"state": "open", "failure_count": 3, "success_count": 0, "last_failure_time": "$(get_timestamp)", "last_state_change": "$(get_timestamp)", "active_provider": "ollama", "fallback_provider": "ollama"}
EOF
    metrics=$(generate_mock_metrics)
    state_value=$(echo "$metrics" | grep '^moltis_circuit_state ' | awk '{print $2}')
    assert_eq "1" "$state_value" "State should be 1 (OPEN)"

    local failure_count
    failure_count=$(echo "$metrics" | grep '^moltis_circuit_failures ' | awk '{print $2}')
    assert_eq "3" "$failure_count" "Failure count should be 3"

    teardown_test
    test_pass
}

# Test 9: Active provider metric reflects actual provider
test_metric_active_provider() {
    test_start "moltis_active_provider metric should reflect active provider"

    setup_test

    # Test with glm as active
    local metrics
    metrics=$(generate_mock_metrics)
    if ! echo "$metrics" | grep -q 'moltis_active_provider{provider="glm"} 1'; then
        test_fail "Active provider metric should show glm as active"
        teardown_test
        return
    fi

    # Test with ollama as active
    cat > "$CIRCUIT_BREAKER_STATE_FILE" << EOF
{"state": "open", "failure_count": 3, "success_count": 0, "last_failure_time": "$(get_timestamp)", "last_state_change": "$(get_timestamp)", "active_provider": "ollama", "fallback_provider": "ollama"}
EOF
    metrics=$(generate_mock_metrics)
    if ! echo "$metrics" | grep -q 'moltis_active_provider{provider="ollama"} 1'; then
        test_fail "Active provider metric should show ollama as active"
        teardown_test
        return
    fi

    teardown_test
    test_pass
}

# Test 10: Metrics output is parseable by Prometheus
test_metric_parseable_format() {
    test_start "Metrics output should be in parseable Prometheus format"

    setup_test
    local metrics
    metrics=$(generate_mock_metrics)

    local failed=0

    # Check each non-comment line
    while IFS= read -r line; do
        # Skip comments and empty lines
        if [[ "$line" =~ ^# ]] || [[ -z "$line" ]]; then
            continue
        fi

        # Validate metric line format
        if ! validate_metric_line "$line"; then
            log_warn "Invalid metric line format: $line"
            failed=1
        fi
    done <<< "$metrics"

    teardown_test

    if [[ $failed -eq 0 ]]; then
        test_pass
    else
        test_fail "Some metric lines have invalid format"
    fi
}

# ==============================================================================
# TEST RUNNER
# ==============================================================================

run_all_tests() {
    start_timer

    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo ""
        echo "========================================="
        echo "  Prometheus Metrics Unit Tests"
        echo "========================================="
        echo ""
    fi

    # Check for jq dependency
    if ! command -v jq &> /dev/null; then
        test_skip "jq is required for metrics tests"
        generate_report
        return 2
    fi

    # Run all tests
    test_metric_naming_conventions
    test_metric_llm_provider_available
    test_metric_circuit_state
    test_metric_fallback_total
    test_metric_help_text
    test_metric_state_mapping
    test_metric_fallback_counter
    test_metric_state_changes
    test_metric_active_provider
    test_metric_parseable_format

    # Generate report
    generate_report
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
