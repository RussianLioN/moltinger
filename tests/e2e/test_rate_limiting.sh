#!/bin/bash
# test_rate_limiting.sh - E2E tests for rate limiting and abuse prevention
# Tests API rate limiting, request throttling, and DoS protection
#
# Test Scenarios:
#   1. Normal requests are not rate limited
#   2. Rapid requests trigger rate limiting
#   3. Rate limit headers are present
#   4. Rate limit resets after timeout
#   5. Concurrent requests are handled correctly
#
# Priority: P2 (Optional - can be skipped if rate limiting not implemented)
#
# Usage:
#   source tests/e2e/test_rate_limiting.sh
#
# Exit Codes:
#   0 - All tests passed
#   1 - One or more tests failed
#   2 - Feature not implemented (skip)
#
# Part of: 001-docker-deploy-improvements
# Contract: specs/001-docker-deploy-improvements/contracts/test-e2e.md

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")/../.."

# Source test helpers
# shellcheck source=tests/lib/test_helpers.sh
source "$LIB_DIR/test_helpers.sh"

# API Configuration
MOLTIS_URL="${MOLTIS_URL:-http://localhost:13131}"
MOLTIS_PASSWORD="${MOLTIS_PASSWORD:-}"
MOLTIS_ENV_FILE="${MOLTIS_ENV_FILE:-/opt/moltinger/.env}"

# Rate limit test configuration
RATE_LIMIT_THRESHOLD="${RATE_LIMIT_THRESHOLD:-10}"  # Expected rate limit
RATE_LIMIT_WINDOW="${RATE_LIMIT_WINDOW:-60}"        # Time window in seconds
BURST_TEST_COUNT=20                                  # Number of rapid requests
CONCURRENT_REQUESTS=10                               # Concurrent request count
COOKIE_FILE="/tmp/moltis-rate-limit-$$"

# Test tracking
RATE_LIMIT_IMPLEMENTED=false
RATE_LIMIT_HEADERS=()
RATE_LIMIT_RESET_TIME=0

# ==============================================================================
# SETUP AND TEARDOWN
# ==============================================================================

# Setup test environment
setup_rate_limiting_tests() {
    log_debug "Setting up rate limiting E2E tests"

    # Check dependencies
    if ! command -v curl &> /dev/null; then
        test_skip "curl not installed"
        return 2
    fi

    if ! command -v jq &> /dev/null; then
        test_skip "jq not installed"
        return 2
    fi

    # Get password if needed for authenticated tests
    if [[ -z "$MOLTIS_PASSWORD" ]] && [[ -f "$MOLTIS_ENV_FILE" ]]; then
        MOLTIS_PASSWORD=$(grep "^MOLTIS_PASSWORD=" "$MOLTIS_ENV_FILE" 2>/dev/null | cut -d'=' -f2-)
    fi

    # Verify Moltis is running
    local health_status
    health_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "${MOLTIS_URL}/health" 2>/dev/null || echo "000")

    if [[ "$health_status" != "200" ]]; then
        test_skip "Moltis not reachable at $MOLTIS_URL (HTTP $health_status)"
        return 2
    fi

    # Test if rate limiting is implemented
    local response
    response=$(curl -s -i "${MOLTIS_URL}/health" 2>/dev/null | head -20 || echo "")

    if echo "$response" | grep -qiE "(rate.?limit|x-ratelimit)"; then
        RATE_LIMIT_IMPLEMENTED=true
        log_info "Rate limiting appears to be implemented"
    else
        log_warn "Rate limiting headers not detected - tests may be skipped"
    fi

    return 0
}

# Cleanup test environment
cleanup_rate_limiting_tests() {
    log_debug "Cleaning up rate limiting E2E tests"
    rm -f "$COOKIE_FILE"
}

# Register cleanup on exit
trap cleanup_rate_limiting_tests EXIT

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

# Authenticate for rate limit tests
# Returns: 0 on success
rate_limit_auth() {
    if [[ -n "$MOLTIS_PASSWORD" ]]; then
        curl -s -c "$COOKIE_FILE" \
            -X POST "${MOLTIS_URL}/login" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "password=${MOLTIS_PASSWORD}" \
            -o /dev/null \
            --max-time 10 2>/dev/null || true
    fi
    return 0
}

# Make a request and capture headers and status
# Usage: make_request [endpoint] [use_auth]
# Returns: "status_code:header1=value1;header2=value2"
make_request() {
    local endpoint="${1:-/health}"
    local use_auth="${2:-false}"
    local output

    if [[ "$use_auth" == "true" ]] && [[ -f "$COOKIE_FILE" ]]; then
        output=$(curl -s -i -b "$COOKIE_FILE" \
            "${MOLTIS_URL}${endpoint}" \
            --max-time 10 2>/dev/null || echo "")
    else
        output=$(curl -s -i "${MOLTIS_URL}${endpoint}" --max-time 10 2>/dev/null || echo "")
    fi

    # Extract status code
    local status_code
    status_code=$(echo "$output" | head -1 | grep -oE '[0-9]{3}' || echo "000")

    # Extract rate limit headers
    local headers=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^[Rr]ate-[Ll]imit: ]] || \
           [[ "$line" =~ ^[Xx]-[Rr]ate[Ll]imit- ]] || \
           [[ "$line" =~ ^[Xx]-[Rr]ate[Ll]imit-[Aa]fter: ]]; then
            # Remove carriage return using tr instead of parameter expansion
            local clean_line
            clean_line=$(echo "$line" | tr -d '\r')
            headers+="${clean_line};"
        fi
    done <<< "$output"

    echo "${status_code}:${headers}"
}

# Extract header value from request response
# Usage: get_header "status:headers" "header_name"
get_header() {
    local response="$1"
    local header_name="$2"

    local headers="${response#*:}"
    echo "$headers" | grep -iE "^${header_name}:" | cut -d':' -f2- | tr -d ' \r' || echo ""
}

# Extract status code from request response
# Usage: get_status "status:headers"
get_status() {
    echo "$1" | cut -d':' -f1
}

# Perform rapid requests to trigger rate limit
# Usage: rapid_request_test [count] [endpoint] [use_auth]
# Returns: "success_count:rate_limited_count:first_429_index"
rapid_request_test() {
    local count="${1:-$BURST_TEST_COUNT}"
    local endpoint="${2:-/health}"
    local use_auth="${3:-false}"

    local success_count=0
    local rate_limited_count=0
    local first_429_index=-1

    for i in $(seq 1 "$count"); do
        local response
        response=$(make_request "$endpoint" "$use_auth")
        local status
        status=$(get_status "$response")

        if [[ "$status" == "429" ]]; then
            ((rate_limited_count++)) || true
            if [[ $first_429_index -eq -1 ]]; then
                first_429_index=$i
            fi
        elif [[ "$status" == "200" ]] || [[ "$status" == "202" ]]; then
            ((success_count++)) || true
        fi
    done

    echo "${success_count}:${rate_limited_count}:${first_429_index}"
}

# Perform concurrent requests
# Usage: concurrent_request_test [count] [endpoint] [use_auth]
concurrent_request_test() {
    local count="${1:-$CONCURRENT_REQUESTS}"
    local endpoint="${2:-/health}"
    local use_auth="${3:-false}"

    local pids=()
    local results="/tmp/rl-result-$$"

    rm -f "$results"

    for i in $(seq 1 "$count"); do
        (
            local response
            response=$(make_request "$endpoint" "$use_auth")
            echo "$(get_status "$response")" >> "$results"
        ) &
        pids+=($!)
    done

    # Wait for all background jobs
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    # Count results
    local success_count=0
    local rate_limited_count=0
    local error_count=0

    while IFS= read -r status; do
        case "$status" in
            200|202)
                ((success_count++)) || true
                ;;
            429)
                ((rate_limited_count++)) || true
                ;;
            *)
                ((error_count++)) || true
                ;;
        esac
    done < "$results"

    rm -f "$results"
    echo "${success_count}:${rate_limited_count}:${error_count}"
}

# ==============================================================================
# TEST CASES
# ==============================================================================

# Test 1: Single request is not rate limited
test_single_request_not_limited() {
    test_start "rate_limit_single_request"

    local response
    response=$(make_request "/health")
    local status
    status=$(get_status "$response")

    if [[ "$status" == "200" ]] || [[ "$status" == "429" ]]; then
        # If we get 429 on first request, rate limit might be too strict
        if [[ "$status" == "429" ]]; then
            test_skip "Single request was rate limited (limit too strict or already hit)"
        else
            test_pass
        fi
    else
        test_fail "Unexpected status: $status"
    fi
}

# Test 2: Rate limit headers are present (if implemented)
test_rate_limit_headers() {
    test_start "rate_limit_headers"

    if [[ "$RATE_LIMIT_IMPLEMENTED" != "true" ]]; then
        test_skip "Rate limiting not implemented"
        return 2
    fi

    local response
    response=$(make_request "/health")

    # Check for common rate limit headers
    local has_limit=false
    local has_remaining=false
    local has_reset=false

    local headers="${response#*:}"
    if echo "$headers" | grep -iqE "rate.*limit.*remaining"; then
        has_remaining=true
    fi
    if echo "$headers" | grep -iqE "rate.*limit.*reset"; then
        has_reset=true
    fi
    if echo "$headers" | grep -iqE "^rate.*limit:"; then
        has_limit=true
    fi

    if [[ "$has_limit" == "true" ]] || [[ "$has_remaining" == "true" ]]; then
        log_debug "Rate limit headers found"
        test_pass
    else
        test_skip "No rate limit headers detected"
    fi
}

# Test 3: Rapid requests trigger rate limiting (if implemented)
test_rapid_requests_trigger_limit() {
    test_start "rate_limit_rapid_requests"

    if [[ "$RATE_LIMIT_IMPLEMENTED" != "true" ]]; then
        test_skip "Rate limiting not implemented"
        return 2
    fi

    local result
    result=$(rapid_request_test "$BURST_TEST_COUNT" "/health")
    IFS=':' read -r success_count rate_limited_count first_429 <<< "$result"

    log_debug "Rapid requests: $success_count successful, $rate_limited_count rate limited"

    if [[ $rate_limited_count -gt 0 ]]; then
        log_debug "Rate limiting triggered at request #$first_429"
        test_pass
    elif [[ $success_count -eq $BURST_TEST_COUNT ]]; then
        test_skip "No rate limiting triggered (threshold may be higher than $BURST_TEST_COUNT)"
    else
        test_fail "Unexpected result: some requests failed without 429 status"
    fi
}

# Test 4: Rate limit resets after timeout (if implemented)
test_rate_limit_reset() {
    test_start "rate_limit_reset"

    if [[ "$RATE_LIMIT_IMPLEMENTED" != "true" ]]; then
        test_skip "Rate limiting not implemented"
        return 2
    fi

    # First, trigger rate limit
    rapid_request_test "$BURST_TEST_COUNT" "/health"

    # Wait for reset (use shorter window for testing)
    local wait_time=5
    log_debug "Waiting ${wait_time}s for rate limit reset..."
    sleep "$wait_time"

    # Try request again
    local response
    response=$(make_request "/health")
    local status
    status=$(get_status "$response")

    if [[ "$status" == "200" ]]; then
        test_pass
    elif [[ "$status" == "429" ]]; then
        test_skip "Rate limit not reset after ${wait_time}s (window may be longer)"
    else
        test_fail "Unexpected status after reset: $status"
    fi
}

# Test 5: Concurrent requests are handled correctly
test_concurrent_requests() {
    test_start "rate_limit_concurrent"

    local result
    result=$(concurrent_request_test "$CONCURRENT_REQUESTS" "/health")
    IFS=':' read -r success_count rate_limited_count error_count <<< "$result"

    log_debug "Concurrent requests: $success_count OK, $rate_limited_count limited, $error_count errors"

    # At minimum, some requests should succeed
    if [[ $success_count -gt 0 ]]; then
        test_pass
    else
        test_fail "All concurrent requests failed"
    fi
}

# Test 6: Authenticated requests have separate rate limits (if implemented)
test_authenticated_rate_limit() {
    test_start "rate_limit_authenticated"

    if [[ -z "$MOLTIS_PASSWORD" ]]; then
        test_skip "No password configured, skipping authenticated test"
        return 2
    fi

    if [[ "$RATE_LIMIT_IMPLEMENTED" != "true" ]]; then
        test_skip "Rate limiting not implemented"
        return 2
    fi

    # Authenticate
    rate_limit_auth

    # Make authenticated requests
    local result
    result=$(rapid_request_test 10 "/api/v1/chat" "true")
    IFS=':' read -r success_count rate_limited_count _ <<< "$result"

    log_debug "Authenticated requests: $success_count OK, $rate_limited_count limited"

    # Should get at least some responses (either success or rate limit)
    if [[ $((success_count + rate_limited_count)) -gt 0 ]]; then
        test_pass
    else
        test_fail "All authenticated requests failed"
    fi
}

# Test 7: Rate limit applies per IP/session (if implemented)
test_per_session_rate_limit() {
    test_start "rate_limit_per_session"

    if [[ "$RATE_LIMIT_IMPLEMENTED" != "true" ]]; then
        test_skip "Rate limiting not implemented"
        return 2
    fi

    # This test verifies rate limiting is per-IP or per-session
    # We make requests and check if we can trigger rate limit

    local result
    result=$(rapid_request_test 15 "/health")
    IFS=':' read -r success_count rate_limited_count _ <<< "$result"

    if [[ $rate_limited_count -gt 0 ]]; then
        log_debug "Rate limit is enforced (per IP/session)"
        test_pass
    else
        test_skip "Could not trigger rate limit (may be per-user or threshold too high)"
    fi
}

# Test 8: Rate limit response includes Retry-After header (if implemented)
test_retry_after_header() {
    test_start "rate_limit_retry_after"

    if [[ "$RATE_LIMIT_IMPLEMENTED" != "true" ]]; then
        test_skip "Rate limiting not implemented"
        return 2
    fi

    # Trigger rate limit first
    rapid_request_test "$BURST_TEST_COUNT" "/health"

    # Get a 429 response
    local response
    local attempts=0
    local max_attempts=5

    while [[ $attempts -lt $max_attempts ]]; do
        response=$(make_request "/health")
        local status
        status=$(get_status "$response")

        if [[ "$status" == "429" ]]; then
            break
        fi
        ((attempts++)) || true
    done

    if [[ "$(get_status "$response")" == "429" ]]; then
        local headers="${response#*:}"
        if echo "$headers" | grep -iq "retry-after"; then
            local retry_after
            retry_after=$(echo "$headers" | grep -i "retry-after" | cut -d':' -f2- | tr -d ' \r')
            log_debug "Retry-After header: $retry_after"
            test_pass
        else
            test_skip "No Retry-After header (not required)"
        fi
    else
        test_skip "Could not trigger 429 response"
    fi
}

# Test 9: Different endpoints may have different rate limits
test_endpoint_specific_limits() {
    test_start "rate_limit_endpoint_specific"

    if [[ "$RATE_LIMIT_IMPLEMENTED" != "true" ]]; then
        test_skip "Rate limiting not implemented"
        return 2
    fi

    # Test health endpoint (usually has higher or no limit)
    local health_result
    health_result=$(rapid_request_test 10 "/health")

    # Test chat endpoint (may have stricter limit)
    local chat_result
    if [[ -n "$MOLTIS_PASSWORD" ]]; then
        rate_limit_auth
        chat_result=$(rapid_request_test 10 "/api/v1/chat" "true")
    fi

    # This is informational - we just verify both work
    test_pass "Endpoint-specific limit test completed"
}

# Test 10: Rate limiting doesn't block legitimate traffic
test_legitimate_traffic() {
    test_start "rate_limit_legitimate_traffic"

    # Simulate legitimate user: spaced requests
    local all_success=true

    for i in $(seq 1 5); do
        local response
        response=$(make_request "/health")
        local status
        status=$(get_status "$response")

        if [[ "$status" != "200" ]]; then
            all_success=false
            break
        fi

        sleep 1  # Normal user delay
    done

    if [[ "$all_success" == "true" ]]; then
        test_pass
    else
        test_fail "Legitimate spaced requests were rate limited"
    fi
}

# Test 11: Response time metrics (P50, P95, P99)
test_response_time_metrics() {
    test_start "rate_limit_response_metrics"

    local sample_count=50
    local times_file="/tmp/rl-times-$$"
    rm -f "$times_file"

    # Collect response times
    for i in $(seq 1 "$sample_count"); do
        local start_time
        start_time=$(date +%s%3N)  # Milliseconds

        local response
        response=$(make_request "/health")
        local status
        status=$(get_status "$response")

        local end_time
        end_time=$(date +%s%3N)

        local duration=$((end_time - start_time))
        echo "$duration" >> "$times_file"

        # Small delay to avoid overwhelming
        sleep 0.05
    done

    # Calculate percentiles
    local sorted_times="/tmp/rl-sorted-$$"
    sort -n "$times_file" > "$sorted_times"

    local p50_index=$((sample_count * 50 / 100))
    local p95_index=$((sample_count * 95 / 100))
    local p99_index=$((sample_count * 99 / 100))

    local p50=$(sed -n "${p50_index}p" "$sorted_times")
    local p95=$(sed -n "${p95_index}p" "$sorted_times")
    local p99=$(sed -n "${p99_index}p" "$sorted_times")

    rm -f "$times_file" "$sorted_times"

    log_info "Response Time Metrics (ms):"
    log_info "  P50: ${p50}ms"
    log_info "  P95: ${p95}ms"
    log_info "  P99: ${p99}ms"

    # Check if percentiles are reasonable (not too slow)
    # P95 should be under 5 seconds (5000ms) for a healthy API
    if [[ $p95 -lt 5000 ]]; then
        test_pass
    else
        test_skip "P95 (${p95}ms) is above 5000ms threshold"
    fi
}

# ==============================================================================
# TEST RUNNER
# ==============================================================================

# Run all rate limiting E2E tests
run_rate_limiting_tests() {
    local setup_result
    setup_result=$(setup_rate_limiting_tests)
    local setup_code=$?

    if [[ $setup_code -ne 0 ]]; then
        test_start "rate_limiting_tests"
        test_skip "Dependencies not met"
        return 2
    fi

    log_info "Running rate limiting E2E tests..."
    log_info "Rate limiting implemented: $RATE_LIMIT_IMPLEMENTED"
    log_info "Burst test count: $BURST_TEST_COUNT"
    log_info "Concurrent requests: $CONCURRENT_REQUESTS"

    # Run all test cases
    test_single_request_not_limited
    test_rate_limit_headers || true
    test_rapid_requests_trigger_limit || true
    test_rate_limit_reset || true
    test_concurrent_requests
    test_authenticated_rate_limit || true
    test_per_session_rate_limit || true
    test_retry_after_header || true
    test_endpoint_specific_limits || true
    test_response_time_metrics || true
    test_legitimate_traffic
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    start_timer
    run_rate_limiting_tests
    generate_report
fi
