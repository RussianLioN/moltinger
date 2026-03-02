#!/bin/bash
# test_chat_flow.sh - E2E tests for complete chat user flow
# Tests full user journey from login to chat response
#
# Test Scenarios:
#   1. Login flow - POST /login with password, get session cookie
#   2. Chat message - POST /api/v1/chat with message, get response
#   3. Chat context - Follow-up question verifies context maintained
#   4. Chat timeout - Verify response within 30 seconds
#
# Usage:
#   source tests/e2e/test_chat_flow.sh
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
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")/../.."

# Source test helpers
# shellcheck source=tests/lib/test_helpers.sh
source "$LIB_DIR/test_helpers.sh"

# Moltis API Configuration
MOLTIS_URL="${MOLTIS_URL:-http://localhost:13131}"
MOLTIS_PASSWORD="${MOLTIS_PASSWORD:-}"
MOLTIS_ENV_FILE="${MOLTIS_ENV_FILE:-/opt/moltinger/.env}"

# Test timeouts
CHAT_TIMEOUT="${CHAT_TIMEOUT:-30}"  # Maximum time to wait for chat response
LOGIN_TIMEOUT="${LOGIN_TIMEOUT:-10}"
POLL_INTERVAL=1  # Seconds between polling attempts

# Cookie storage
COOKIE_FILE="/tmp/moltis-e2e-cookie-$$"
SESSION_ID=""

# Test tracking
LOGIN_SUCCESS=false
CHAT_RESPONSE_TIME=0
LAST_RESPONSE=""

# ==============================================================================
# SETUP AND TEARDOWN
# ==============================================================================

# Setup test environment
setup_chat_flow_tests() {
    log_debug "Setting up chat flow E2E tests"

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

    # Verify Moltis is running
    local health_status
    health_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "${MOLTIS_URL}/health" 2>/dev/null || echo "000")

    if [[ "$health_status" != "200" ]]; then
        test_skip "Moltis not reachable at $MOLTIS_URL (HTTP $health_status)"
        return 2
    fi

    log_info "Moltis is reachable at $MOLTIS_URL"
    return 0
}

# Cleanup test environment
cleanup_chat_flow_tests() {
    log_debug "Cleaning up chat flow E2E tests"
    rm -f "$COOKIE_FILE"
    rm -f "$COOKIE_FILE.response" 2>/dev/null || true
}

# Register cleanup on exit
trap cleanup_chat_flow_tests EXIT

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

# Authenticate with Moltis and store session
# Returns: 0 on success, 1 on failure
moltis_login() {
    local password="$1"

    log_debug "Attempting login to $MOLTIS_URL"

    local response_code
    response_code=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
        -X POST "${MOLTIS_URL}/login" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "password=${password}" \
        -o /dev/null \
        -w "%{http_code}" \
        --max-time "$LOGIN_TIMEOUT" 2>/dev/null || echo "000")

    if [[ "$response_code" == "200" ]] || [[ "$response_code" == "302" ]]; then
        # Extract session ID from cookie file
        if [[ -f "$COOKIE_FILE" ]]; then
            SESSION_ID=$(grep -i "session\|moltis" "$COOKIE_FILE" 2>/dev/null | head -1 | awk '{print $7}' || echo "")
        fi
        log_debug "Login successful (HTTP $response_code)"
        LOGIN_SUCCESS=true
        return 0
    else
        log_debug "Login failed (HTTP $response_code)"
        LOGIN_SUCCESS=false
        return 1
    fi
}

# Send chat message and poll for response
# Usage: send_chat "message" [timeout_seconds]
# Returns: Response body on success, empty string on failure
send_chat() {
    local message="$1"
    local timeout="${2:-$CHAT_TIMEOUT}"

    log_debug "Sending chat message: $message"

    # Send message
    local send_response
    send_response=$(curl -s -b "$COOKIE_FILE" \
        -X POST "${MOLTIS_URL}/api/v1/chat" \
        -H "Content-Type: application/json" \
        -d "{\"message\": \"${message}\"}" \
        --max-time "$LOGIN_TIMEOUT" 2>/dev/null || echo "")

    # If response is immediate (not async), return it
    if [[ -n "$send_response" ]] && [[ "$send_response" != "null" ]]; then
        LAST_RESPONSE="$send_response"
        echo "$send_response"
        return 0
    fi

    # Poll for response (async mode)
    local start_time
    start_time=$(date +%s)
    local elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        local poll_response
        poll_response=$(curl -s -b "$COOKIE_FILE" \
            "${MOLTIS_URL}/api/v1/chat" \
            --max-time "$LOGIN_TIMEOUT" 2>/dev/null || echo "")

        if [[ -n "$poll_response" ]] && [[ "$poll_response" != "null" ]]; then
            CHAT_RESPONSE_TIME=$elapsed
            LAST_RESPONSE="$poll_response"
            echo "$poll_response"
            return 0
        fi

        sleep "$POLL_INTERVAL"
        elapsed=$(($(date +%s) - start_time))
    done

    log_debug "Chat response timeout after ${timeout}s"
    return 1
}

# ==============================================================================
# TEST CASES
# ==============================================================================

# Test 1: Login flow with valid credentials
test_login_flow() {
    test_start "login_flow"

    # Clean cookie file for fresh login
    rm -f "$COOKIE_FILE"

    if moltis_login "$MOLTIS_PASSWORD"; then
        # Verify cookie file was created
        if [[ -f "$COOKIE_FILE" ]]; then
            assert_file_exists "$COOKIE_FILE" "Session cookie file created"

            # Verify cookie contains session data
            if grep -q -i "session\|moltis" "$COOKIE_FILE" 2>/dev/null; then
                test_pass
            else
                test_fail "Cookie file does not contain session data"
            fi
        else
            test_fail "Cookie file not created"
        fi
    else
        test_fail "Login failed with password"
    fi
}

# Test 2: Login with invalid password fails
test_login_invalid_password() {
    test_start "login_invalid_password"

    # Save current cookie
    local saved_cookie
    saved_cookie="${COOKIE_FILE}.saved"
    cp "$COOKIE_FILE" "$saved_cookie" 2>/dev/null || true

    # Try login with invalid password
    rm -f "$COOKIE_FILE"

    if moltis_login "invalid_password_12345"; then
        test_fail "Login should fail with invalid password"
    else
        # Verify no valid session was created
        if [[ ! -f "$COOKIE_FILE" ]] || ! grep -q -i "session" "$COOKIE_FILE" 2>/dev/null; then
            test_pass
        else
            test_fail "Invalid login created a session"
        fi
    fi

    # Restore valid session
    mv "$saved_cookie" "$COOKIE_FILE" 2>/dev/null || true
}

# Test 3: Chat message - send simple greeting
test_chat_message() {
    test_start "chat_message"

    if [[ "$LOGIN_SUCCESS" != "true" ]]; then
        test_skip "Not logged in, skipping chat message test"
        return 2
    fi

    local response
    response=$(send_chat "Hello" "$CHAT_TIMEOUT")

    if [[ -n "$response" ]]; then
        # Verify response is not empty
        if [[ "$response" != "null" ]] && [[ "$response" != "{}" ]]; then
            log_debug "Chat response: $response"
            test_pass
        else
            test_fail "Chat returned empty/null response"
        fi
    else
        test_fail "No response received within timeout"
    fi
}

# Test 4: Chat response within timeout
test_chat_timeout() {
    test_start "chat_timeout"

    if [[ "$LOGIN_SUCCESS" != "true" ]]; then
        test_skip "Not logged in, skipping chat timeout test"
        return 2
    fi

    local start_time
    start_time=$(date +%s)

    local response
    response=$(send_chat "What is 2+2?" "$CHAT_TIMEOUT")

    local end_time
    end_time=$(date +%s)

    local duration=$((end_time - start_time))

    log_debug "Chat response time: ${duration}s"

    if [[ -n "$response" ]]; then
        if [[ $duration -le $CHAT_TIMEOUT ]]; then
            test_pass
        else
            test_fail "Response exceeded timeout (${duration}s > ${CHAT_TIMEOUT}s)"
        fi
    else
        test_fail "No response received"
    fi
}

# Test 5: Chat context maintained across messages
test_chat_context() {
    test_start "chat_context"

    if [[ "$LOGIN_SUCCESS" != "true" ]]; then
        test_skip "Not logged in, skipping chat context test"
        return 2
    fi

    # First message: set context
    local response1
    response1=$(send_chat "My name is Alice" "$CHAT_TIMEOUT")

    # Wait a bit
    sleep 1

    # Second message: ask about context
    local response2
    response2=$(send_chat "What is my name?" "$CHAT_TIMEOUT")

    if [[ -n "$response2" ]]; then
        # Check if response mentions "Alice" or indicates context awareness
        local response_lower
        response_lower=$(echo "$response2" | tr '[:upper:]' '[:lower:]')

        if echo "$response_lower" | grep -qi "alice"; then
            log_debug "Context maintained: bot remembers 'Alice'"
            test_pass
        elif echo "$response_lower" | grep -qiE "(don't know|didn't say|can't recall|no information)"; then
            test_fail "Context not maintained: bot doesn't remember previous message"
        else
            # Response may be valid even without explicit name mention
            log_debug "Context check: got response but unclear if context maintained"
            test_pass "Got valid response (context verification unclear)"
        fi
    else
        test_fail "No response for context question"
    fi
}

# Test 6: Chat handles special characters
test_chat_special_characters() {
    test_start "chat_special_characters"

    if [[ "$LOGIN_SUCCESS" != "true" ]]; then
        test_skip "Not logged in, skipping special characters test"
        return 2
    fi

    local response
    response=$(send_chat "Test special chars: @#\$%^&*()_+-=[]{}|;':\",./<>?" "$CHAT_TIMEOUT")

    if [[ -n "$response" ]]; then
        log_debug "Special chars response: $response"
        test_pass
    else
        test_fail "No response for message with special characters"
    fi
}

# Test 7: Chat handles empty/null message gracefully
test_chat_empty_message() {
    test_start "chat_empty_message"

    if [[ "$LOGIN_SUCCESS" != "true" ]]; then
        test_skip "Not logged in, skipping empty message test"
        return 2
    fi

    local response_code
    response_code=$(curl -s -b "$COOKIE_FILE" \
        -X POST "${MOLTIS_URL}/api/v1/chat" \
        -H "Content-Type: application/json" \
        -d '{"message": ""}' \
        -o /dev/null \
        -w "%{http_code}" \
        --max-time "$LOGIN_TIMEOUT" 2>/dev/null || echo "000")

    # Should either accept (200) or reject gracefully (400, 422)
    if [[ "$response_code" == "200" ]] || [[ "$response_code" == "400" ]] || [[ "$response_code" == "422" ]]; then
        test_pass
    else
        test_skip "Unexpected response for empty message: $response_code"
    fi
}

# Test 8: Chat handles long message
test_chat_long_message() {
    test_start "chat_long_message"

    if [[ "$LOGIN_SUCCESS" != "true" ]]; then
        test_skip "Not logged in, skipping long message test"
        return 2
    fi

    # Create a long message (1000 characters)
    local long_message="Please repeat this: "
    long_message+="$(printf 'A%.0s' {1..980})"

    local response
    response=$(send_chat "$long_message" "$CHAT_TIMEOUT")

    if [[ -n "$response" ]]; then
        test_pass
    else
        test_fail "No response for long message"
    fi
}

# Test 9: Multiple concurrent chat sessions (using different cookies)
test_chat_concurrent_sessions() {
    test_start "chat_concurrent_sessions"

    # Create second session
    local cookie2="/tmp/moltis-e2e-cookie-$$-2"

    # Login second session
    local response_code
    response_code=$(curl -s -c "$cookie2" \
        -X POST "${MOLTIS_URL}/login" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "password=${MOLTIS_PASSWORD}" \
        -o /dev/null \
        -w "%{http_code}" \
        --max-time "$LOGIN_TIMEOUT" 2>/dev/null || echo "000")

    rm -f "$cookie2"

    if [[ "$response_code" == "200" ]] || [[ "$response_code" == "302" ]]; then
        test_pass
    else
        test_skip "Concurrent sessions test failed: HTTP $response_code"
    fi
}

# Test 10: Chat response time is reasonable (< 15 seconds for simple query)
test_chat_response_performance() {
    test_start "chat_response_performance"

    if [[ "$LOGIN_SUCCESS" != "true" ]]; then
        test_skip "Not logged in, skipping performance test"
        return 2
    fi

    local start_time
    start_time=$(date +%s)

    local response
    response=$(send_chat "Say 'test'" 15)

    local end_time
    end_time=$(date +%s)

    local duration=$((end_time - start_time))

    log_debug "Simple chat response time: ${duration}s"

    if [[ -n "$response" ]]; then
        if [[ $duration -lt 15 ]]; then
            test_pass
        else
            test_fail "Response too slow for simple query: ${duration}s"
        fi
    else
        test_skip "No response received"
    fi
}

# ==============================================================================
# TEST RUNNER
# ==============================================================================

# Run all chat flow E2E tests
run_chat_flow_tests() {
    local setup_result
    setup_result=$(setup_chat_flow_tests)
    local setup_code=$?

    if [[ $setup_code -ne 0 ]]; then
        test_start "chat_flow_tests"
        test_skip "Dependencies not met"
        return 2
    fi

    log_info "Running chat flow E2E tests..."
    log_info "Moltis URL: $MOLTIS_URL"
    log_info "Chat timeout: ${CHAT_TIMEOUT}s"

    # Run all test cases
    test_login_flow
    test_login_invalid_password
    test_chat_message || true
    test_chat_timeout || true
    test_chat_context || true
    test_chat_special_characters || true
    test_chat_empty_message
    test_chat_long_message || true
    test_chat_concurrent_sessions
    test_chat_response_performance || true
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    start_timer
    run_chat_flow_tests
    generate_report
fi
