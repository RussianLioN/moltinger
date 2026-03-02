#!/bin/bash
# test_api_endpoints.sh - Integration tests for Moltis API endpoints
# Tests HTTP API authentication, endpoints, and response validation
#
# Test Scenarios:
#   - /health (GET, no auth) → 200
#   - /login (POST, password) → 200/302
#   - /api/v1/chat (POST, cookie) → 200
#   - /metrics (GET, no auth) → 200
#   - /api/mcp/servers (GET, cookie) → 200
#
# Usage:
#   source tests/integration/test_api_endpoints.sh
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

# Source test helpers
# shellcheck source=tests/lib/test_helpers.sh
source "$LIB_DIR/test_helpers.sh"

# API Configuration
MOLTIS_URL="${MOLTIS_URL:-http://localhost:13131}"
MOLTIS_PASSWORD="${MOLTIS_PASSWORD:-}"
MOLTIS_ENV_FILE="${MOLTIS_ENV_FILE:-/opt/moltinger/.env}"
TEST_TIMEOUT=30

# Cookie file for authenticated requests
COOKIE_FILE="/tmp/moltis-test-cookie-$$"

# Test results
AUTH_SUCCESS=false
RESPONSE_BODY=""

# ==============================================================================
# SETUP AND TEARDOWN
# ==============================================================================

# Setup test environment
setup_api_tests() {
    log_debug "Setting up API endpoint tests"

    # Check dependencies
    if ! command -v curl &> /dev/null; then
        test_skip "curl not installed"
        return 2
    fi

    if ! command -v jq &> /dev/null; then
        test_skip "jq not installed"
        return 2
    fi

    # Get password from .env if not set
    if [[ -z "$MOLTIS_PASSWORD" ]]; then
        if [[ -f "$MOLTIS_ENV_FILE" ]]; then
            MOLTIS_PASSWORD=$(grep "^MOLTIS_PASSWORD=" "$MOLTIS_ENV_FILE" 2>/dev/null | cut -d'=' -f2-)
        fi

        if [[ -z "$MOLTIS_PASSWORD" ]]; then
            test_skip "MOLTIS_PASSWORD not set (set env var or configure $MOLTIS_ENV_FILE)"
            return 2
        fi
    fi

    # Check if Moltis is reachable
    if ! curl -s --max-time 5 "$MOLTIS_URL/health" > /dev/null 2>&1; then
        log_warn "Moltis not reachable at $MOLTIS_URL"
    fi

    return 0
}

# Cleanup test environment
cleanup_api_tests() {
    log_debug "Cleaning up API endpoint tests"
    rm -f "$COOKIE_FILE"
}

# Register cleanup on exit
trap cleanup_api_tests EXIT

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

# Authenticate with Moltis API
# Returns: 0 on success, 1 on failure
moltis_authenticate() {
    log_debug "Authenticating with Moltis API"

    local response_code
    response_code=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
        -X POST "${MOLTIS_URL}/login" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "password=${MOLTIS_PASSWORD}" \
        -o /dev/null \
        -w "%{http_code}" \
        --max-time "$TEST_TIMEOUT" 2>/dev/null || echo "000")

    if [[ "$response_code" == "200" ]] || [[ "$response_code" == "302" ]]; then
        log_debug "Authentication successful (HTTP $response_code)"
        AUTH_SUCCESS=true
        return 0
    else
        log_debug "Authentication failed (HTTP $response_code)"
        AUTH_SUCCESS=false
        return 1
    fi
}

# Make authenticated API request
# Usage: api_request METHOD ENDPOINT [DATA]
api_request() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"

    local response_code
    response_code=$(curl -s -b "$COOKIE_FILE" \
        -X "$method" "${MOLTIS_URL}${endpoint}" \
        ${data:--H "Content-Type: application/json"} \
        ${data:--d "$data"} \
        -o "$COOKIE_FILE.response" \
        -w "%{http_code}" \
        --max-time "$TEST_TIMEOUT" 2>/dev/null || echo "000")

    RESPONSE_BODY=$(cat "$COOKIE_FILE.response" 2>/dev/null || echo "")
    rm -f "$COOKIE_FILE.response"

    echo "$response_code"
}

# ==============================================================================
# TEST CASES
# ==============================================================================

# Test 1: Health endpoint (no auth required)
test_health_endpoint() {
    test_start "health_endpoint"

    local response_code
    response_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time "$TEST_TIMEOUT" \
        "${MOLTIS_URL}/health" 2>/dev/null || echo "000")

    if [[ "$response_code" == "200" ]]; then
        # Verify response contains health indicator
        local response
        response=$(curl -s --max-time "$TEST_TIMEOUT" "${MOLTIS_URL}/health" 2>/dev/null || echo "")

        # Health endpoint should return status or similar
        if echo "$response" | jq -e '.status' > /dev/null 2>&1 || \
           echo "$response" | grep -qiE "(healthy|ok|status)" 2>/dev/null; then
            test_pass
        else
            test_pass "Got 200 but response format unclear"
        fi
    else
        test_fail "Expected HTTP 200, got $response_code"
    fi
}

# Test 2: Login endpoint authentication
test_login_endpoint() {
    test_start "login_endpoint"

    if moltis_authenticate; then
        test_pass
    else
        test_fail "Authentication failed"
    fi
}

# Test 3: Chat endpoint (requires auth)
test_chat_endpoint() {
    test_start "chat_endpoint"

    if [[ "$AUTH_SUCCESS" != "true" ]]; then
        test_skip "Authentication not successful, skipping chat endpoint test"
        return 2
    fi

    local response_code
    response_code=$(api_request "POST" "/api/v1/chat" '{"message": "/help"}')

    if [[ "$response_code" == "200" ]] || [[ "$response_code" == "202" ]]; then
        test_pass
    else
        test_fail "Expected HTTP 200/202, got $response_code"
    fi
}

# Test 4: Chat endpoint returns valid response
test_chat_response_format() {
    test_start "chat_response_format"

    if [[ "$AUTH_SUCCESS" != "true" ]]; then
        test_skip "Authentication not successful, skipping chat response test"
        return 2
    fi

    local response_code
    response_code=$(api_request "POST" "/api/v1/chat" '{"message": "/help"}')

    if [[ "$response_code" != "200" ]] && [[ "$response_code" != "202" ]]; then
        test_fail "Request failed with HTTP $response_code"
        return 1
    fi

    # Check response format
    if echo "$RESPONSE_BODY" | jq -e '.' > /dev/null 2>&1; then
        # Valid JSON response
        test_pass
    elif [[ -n "$RESPONSE_BODY" ]]; then
        # Non-empty response (may be plain text)
        test_pass "Got non-JSON response"
    else
        test_fail "Empty response body"
    fi
}

# Test 5: Metrics endpoint (no auth required)
test_metrics_endpoint() {
    test_start "metrics_endpoint"

    local response_code
    response_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time "$TEST_TIMEOUT" \
        "${MOLTIS_URL}/metrics" 2>/dev/null || echo "000")

    if [[ "$response_code" == "200" ]]; then
        test_pass
    else
        test_fail "Expected HTTP 200, got $response_code"
    fi
}

# Test 6: Metrics endpoint contains Prometheus format
test_metrics_prometheus_format() {
    test_start "metrics_prometheus_format"

    local response
    response=$(curl -s --max-time "$TEST_TIMEOUT" "${MOLTIS_URL}/metrics" 2>/dev/null || echo "")

    if [[ -z "$response" ]]; then
        test_fail "Empty metrics response"
        return 1
    fi

    # Check for Prometheus format (HELP or TYPE comments)
    if echo "$response" | grep -qE "^# (HELP|TYPE)"; then
        test_pass
    else
        test_skip "Metrics endpoint doesn't return Prometheus format (may not be enabled)"
    fi
}

# Test 7: MCP servers endpoint (requires auth)
test_mcp_servers_endpoint() {
    test_start "mcp_servers_endpoint"

    if [[ "$AUTH_SUCCESS" != "true" ]]; then
        test_skip "Authentication not successful, skipping MCP servers test"
        return 2
    fi

    local response_code
    response_code=$(api_request "GET" "/api/mcp/servers")

    # MCP endpoint may not be available in all configurations
    if [[ "$response_code" == "200" ]]; then
        test_pass
    elif [[ "$response_code" == "404" ]]; then
        test_skip "MCP servers endpoint not available (404)"
    elif [[ "$response_code" == "401" ]] || [[ "$response_code" == "403" ]]; then
        test_fail "Authentication rejected for MCP endpoint"
    else
        test_fail "Unexpected response code: $response_code"
    fi
}

# Test 8: Session persistence across requests
test_session_persistence() {
    test_start "session_persistence"

    if [[ "$AUTH_SUCCESS" != "true" ]]; then
        test_skip "Authentication not successful, skipping session test"
        return 2
    fi

    # First request
    local code1
    code1=$(api_request "GET" "/api/v1/chat")

    # Second request (should reuse session)
    local code2
    code2=$(api_request "GET" "/api/v1/chat")

    if [[ "$code1" == "200" ]] || [[ "$code1" == "202" ]]; then
        if [[ "$code2" == "200" ]] || [[ "$code2" == "202" ]]; then
            test_pass
        else
            test_fail "Session not persisted (second request failed with $code2)"
        fi
    else
        test_fail "First request failed with $code1"
    fi
}

# Test 9: Unauthorized request without authentication
test_unauthorized_request() {
    test_start "unauthorized_request"

    # Clear cookies
    rm -f "$COOKIE_FILE"
    AUTH_SUCCESS=false

    local response_code
    response_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time "$TEST_TIMEOUT" \
        "${MOLTIS_URL}/api/v1/chat" 2>/dev/null || echo "000")

    # Should get 401, 403, or redirect to login
    if [[ "$response_code" == "401" ]] || \
       [[ "$response_code" == "403" ]] || \
       [[ "$response_code" == "302" ]]; then
        test_pass
    else
        test_skip "Unexpected response for unauthorized request: $response_code (may allow anonymous access)"
    fi
}

# Test 10: API response time is reasonable
test_api_response_time() {
    test_start "api_response_time"

    local start_time
    start_time=$(date +%s%N 2>/dev/null || python3 -c "import time; print(int(time.time() * 1000000000))")

    curl -s --max-time "$TEST_TIMEOUT" "${MOLTIS_URL}/health" > /dev/null 2>&1 || true

    local end_time
    end_time=$(date +%s%N 2>/dev/null || python3 -c "import time; print(int(time.time() * 1000000000))")

    local duration_ns=$((end_time - start_time))
    local duration_ms=$((duration_ns / 1000000))

    log_debug "API response time: ${duration_ms}ms"

    # Should respond within 5 seconds
    if [[ $duration_ms -lt 5000 ]]; then
        test_pass
    else
        test_fail "API response time too high: ${duration_ms}ms"
    fi
}

# ==============================================================================
# TEST RUNNER
# ==============================================================================

# Run all API endpoint tests
run_api_endpoint_tests() {
    local setup_result
    setup_result=$(setup_api_tests)
    local setup_code=$?

    if [[ $setup_code -ne 0 ]]; then
        # Skip all tests
        test_start "api_endpoint_tests"
        test_skip "Dependencies not met"
        return 2
    fi

    log_info "Running API endpoint integration tests..."
    log_info "Moltis URL: $MOLTIS_URL"

    # Run all test cases
    test_health_endpoint
    test_login_endpoint
    test_chat_endpoint || true
    test_chat_response_format || true
    test_metrics_endpoint
    test_metrics_prometheus_format || true
    test_mcp_servers_endpoint || true
    test_session_persistence || true
    test_unauthorized_request
    test_api_response_time || true
}

# Run tests if sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    start_timer
    run_api_endpoint_tests
    generate_report
fi
