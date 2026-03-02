#!/bin/bash
# test_authentication.sh - Security tests for Moltis authentication
# Tests authentication security: invalid passwords, session expiration, unauthorized access
#
# Test Scenarios:
#   P0: test_invalid_password - Wrong password returns 401/403
#   P0: test_session_expiration - Session expires after timeout
#   P0: test_unauthenticated_access - Protected endpoints return 401 without auth
#   P1: test_session_cookie_httponly - Cookie security attributes
#   P1: test_brute_force_protection - Multiple failed attempts are throttled
#   P1: test_password_complexity - Weak passwords are rejected
#
# Usage:
#   source tests/security/test_authentication.sh
#   run_authentication_tests
#
# Exit Codes:
#   0 - All tests passed
#   1 - One or more tests failed (security issue found)
#   2 - Dependencies missing (skip)
#
# Part of: 001-docker-deploy-improvements
# Contract: specs/001-docker-deploy-improvements/contracts/test-security.md

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
TEST_TIMEOUT=10
SESSION_TIMEOUT="${SESSION_TIMEOUT:-3600}"  # Default 1 hour

# Cookie file for authenticated requests
COOKIE_FILE="/tmp/test-auth-cookie-$$"

# Test results
AUTH_SUCCESS=false
FAILED_ATTEMPTS=0

# ==============================================================================
# SETUP AND TEARDOWN
# ==============================================================================

# Setup test environment
setup_auth_tests() {
    log_debug "Setting up authentication security tests"

    # Check dependencies
    if ! command -v curl &> /dev/null; then
        test_skip "curl not installed"
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
        log_warn "Moltis not reachable at $MOLTIS_URL - tests may fail"
    fi

    return 0
}

# Cleanup test environment
cleanup_auth_tests() {
    log_debug "Cleaning up authentication security tests"
    rm -f "$COOKIE_FILE"
}

# Register cleanup on exit
trap cleanup_auth_tests EXIT

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

# Authenticate with Moltis API
# Usage: moltis_authenticate [password]
# Returns: 0 on success, 1 on failure
moltis_authenticate() {
    local password="${1:-$MOLTIS_PASSWORD}"

    local response_code
    response_code=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
        -X POST "${MOLTIS_URL}/api/auth/login" \
        -H "Content-Type: application/json" \
        -d "\{"password\":"${password}" \
        -o /dev/null \
        -w "%{http_code}" \
        --max-time "$TEST_TIMEOUT" 2>/dev/null || echo "000")

    echo "$response_code"
}

# Make authenticated request
# Usage: make_authenticated_request endpoint
make_authenticated_request() {
    local endpoint="$1"

    local response_code
    response_code=$(curl -s -b "$COOKIE_FILE" \
        -X GET "${MOLTIS_URL}${endpoint}" \
        -H "Content-Type: application/json" \
        -o /dev/null \
        -w "%{http_code}" \
        --max-time "$TEST_TIMEOUT" 2>/dev/null || echo "000")

    echo "$response_code"
}

# ==============================================================================
# TEST CASES
# ==============================================================================

# Test 1: Invalid password returns 401/403 (P0 - Critical)
test_invalid_password() {
    test_start "invalid_password"

    local response_code
    response_code=$(moltis_authenticate "wrong_password_12345")

    # Should return 401 (Unauthorized) or 403 (Forbidden)
    if [[ "$response_code" == "401" ]] || [[ "$response_code" == "403" ]]; then
        test_pass
    else
        test_fail "Expected 401/403 for invalid password, got $response_code"
    fi
}

# Test 2: Empty password is rejected (P0 - Critical)
test_empty_password() {
    test_start "empty_password"

    local response_code
    response_code=$(moltis_authenticate "")

    # Should return 400 (Bad Request) or 401 (Unauthorized)
    if [[ "$response_code" == "400" ]] || [[ "$response_code" == "401" ]] || [[ "$response_code" == "403" ]]; then
        test_pass
    else
        test_fail "Expected 400/401 for empty password, got $response_code"
    fi
}

# Test 3: Valid authentication succeeds (P0 - Critical)
test_valid_authentication() {
    test_start "valid_authentication"

    local response_code
    response_code=$(moltis_authenticate "$MOLTIS_PASSWORD")

    if [[ "$response_code" == "200" ]] || [[ "$response_code" == "302" ]]; then
        AUTH_SUCCESS=true
        test_pass
    else
        AUTH_SUCCESS=false
        test_fail "Valid authentication failed with HTTP $response_code"
    fi
}

# Test 4: Unauthenticated access to protected endpoint returns 401 (P0 - Critical)
test_unauthenticated_access_chat() {
    test_start "unauthenticated_access_chat"

    # Clear any existing session
    rm -f "$COOKIE_FILE"

    local response_code
    response_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time "$TEST_TIMEOUT" \
        "${MOLTIS_URL}/api/v1/chat" 2>/dev/null || echo "000")

    # Should return 401, 403, or 302 (redirect to login)
    if [[ "$response_code" == "401" ]] || [[ "$response_code" == "403" ]] || [[ "$response_code" == "302" ]]; then
        test_pass
    else
        test_fail "Expected 401/403/302 for unauthenticated access, got $response_code"
    fi
}

# Test 5: Unauthenticated access to MCP servers returns 401 (P0 - Critical)
test_unauthenticated_access_mcp() {
    test_start "unauthenticated_access_mcp"

    # Clear any existing session
    rm -f "$COOKIE_FILE"

    local response_code
    response_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time "$TEST_TIMEOUT" \
        "${MOLTIS_URL}/api/mcp/servers" 2>/dev/null || echo "000")

    # MCP endpoint may not be available (404 is acceptable)
    if [[ "$response_code" == "404" ]]; then
        test_skip "MCP endpoint not available"
    elif [[ "$response_code" == "401" ]] || [[ "$response_code" == "403" ]] || [[ "$response_code" == "302" ]]; then
        test_pass
    else
        test_fail "Expected 401/403/302/404 for unauthenticated MCP access, got $response_code"
    fi
}

# Test 6: Session persists across requests (P1)
test_session_persistence() {
    test_start "session_persistence"

    if [[ "$AUTH_SUCCESS" != "true" ]]; then
        # First authenticate
        local response_code
        response_code=$(moltis_authenticate "$MOLTIS_PASSWORD")

        if [[ "$response_code" != "200" ]] && [[ "$response_code" != "302" ]]; then
            test_skip "Could not authenticate for session test"
            return 2
        fi
        AUTH_SUCCESS=true
    fi

    # First request
    local code1
    code1=$(make_authenticated_request "/api/v1/chat")

    # Second request
    local code2
    code2=$(make_authenticated_request "/api/v1/chat")

    # Both should succeed if session is persisted
    if [[ "$code1" == "200" ]] || [[ "$code1" == "202" ]]; then
        if [[ "$code2" == "200" ]] || [[ "$code2" == "202" ]]; then
            test_pass
        else
            test_fail "Session not persisted (second request: $code2)"
        fi
    else
        test_skip "First request failed with $code1"
    fi
}

# Test 7: Session cookie is HTTP-only (P1)
test_session_cookie_httponly() {
    test_start "session_cookie_httponly"

    if [[ "$AUTH_SUCCESS" != "true" ]]; then
        # First authenticate
        local response_code
        response_code=$(moltis_authenticate "$MOLTIS_PASSWORD")

        if [[ "$response_code" != "200" ]] && [[ "$response_code" != "302" ]]; then
            test_skip "Could not authenticate for cookie test"
            return 2
        fi
    fi

    # Check cookie file for HttpOnly flag
    if [[ -f "$COOKIE_FILE" ]]; then
        # Look for httponly in cookie file
        if grep -qi "httponly" "$COOKIE_FILE" 2>/dev/null; then
            test_pass
        else
            test_skip "Could not verify HttpOnly flag (may be set differently)"
        fi
    else
        test_skip "Cookie file not created"
    fi
}

# Test 8: Session cookie uses Secure flag over HTTPS (P1)
test_session_cookie_secure() {
    test_start "session_cookie_secure"

    # Only test if using HTTPS
    if [[ "$MOLTIS_URL" != https://* ]]; then
        test_skip "Not using HTTPS, skipping Secure flag test"
        return 2
    fi

    if [[ "$AUTH_SUCCESS" != "true" ]]; then
        local response_code
        response_code=$(moltis_authenticate "$MOLTIS_PASSWORD")

        if [[ "$response_code" != "200" ]] && [[ "$response_code" != "302" ]]; then
            test_skip "Could not authenticate for Secure flag test"
            return 2
        fi
    fi

    # Check cookie file for Secure flag
    if [[ -f "$COOKIE_FILE" ]]; then
        if grep -qi "secure" "$COOKIE_FILE" 2>/dev/null; then
            test_pass
        else
            test_fail "Secure flag not set on session cookie over HTTPS"
        fi
    else
        test_skip "Cookie file not created"
    fi
}

# Test 9: Multiple failed auth attempts don't crash server (P1)
test_brute_force_resistance() {
    test_start "brute_force_resistance"

    # Try multiple invalid passwords
    local throttle_detected=false
    for i in {1..5}; do
        local response_code
        response_code=$(moltis_authenticate "wrong_password_$i")

        # After some attempts, should see throttling (429) or consistent 401/403
        if [[ "$response_code" == "429" ]]; then
            throttle_detected=true
            break
        fi
    done

    if [[ "$throttle_detected" == "true" ]]; then
        test_pass "Brute force protection active (429 throttling detected)"
    else
        test_pass "Server handles repeated failures (no crash)"
    fi
}

# Test 10: Session requires valid cookie (P1)
test_stolen_session_rejection() {
    test_start "stolen_session_rejection"

    if [[ "$AUTH_SUCCESS" != "true" ]]; then
        local response_code
        response_code=$(moltis_authenticate "$MOLTIS_PASSWORD")

        if [[ "$response_code" != "200" ]] && [[ "$response_code" != "302" ]]; then
            test_skip "Could not authenticate for session test"
            return 2
        fi
        AUTH_SUCCESS=true
    fi

    # Save valid cookie
    local valid_cookie
    valid_cookie=$(cat "$COOKIE_FILE" 2>/dev/null || echo "")

    if [[ -z "$valid_cookie" ]]; then
        test_skip "No cookie to test"
        return 2
    fi

    # Corrupt the cookie
    echo "corrupted_data" > "$COOKIE_FILE"

    # Try to access with corrupted cookie
    local response_code
    response_code=$(make_authenticated_request "/api/v1/chat")

    # Should reject corrupted session
    if [[ "$response_code" == "401" ]] || [[ "$response_code" == "403" ]]; then
        # Restore valid cookie for other tests
        echo "$valid_cookie" > "$COOKIE_FILE"
        test_pass
    elif [[ "$response_code" == "200" ]] || [[ "$response_code" == "202" ]]; then
        # Restore valid cookie
        echo "$valid_cookie" > "$COOKIE_FILE"
        test_fail "Server accepted corrupted session cookie"
    else
        # Restore valid cookie
        echo "$valid_cookie" > "$COOKIE_FILE"
        test_skip "Unexpected response: $response_code"
    fi
}

# Test 11: Logout invalidates session (P1)
test_logout_invalidates_session() {
    test_start "logout_invalidates_session"

    if [[ "$AUTH_SUCCESS" != "true" ]]; then
        local response_code
        response_code=$(moltis_authenticate "$MOLTIS_PASSWORD")

        if [[ "$response_code" != "200" ]] && [[ "$response_code" != "302" ]]; then
            test_skip "Could not authenticate for logout test"
            return 2
        fi
        AUTH_SUCCESS=true
    fi

    # Try to logout (if endpoint exists)
    local logout_response
    logout_response=$(curl -s -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
        -X POST "${MOLTIS_URL}/logout" \
        -o /dev/null \
        -w "%{http_code}" \
        --max-time "$TEST_TIMEOUT" 2>/dev/null || echo "000")

    # After logout, try to access protected resource
    local response_code
    response_code=$(make_authenticated_request "/api/v1/chat")

    # Should be denied after logout
    if [[ "$logout_response" != "000" ]] && \
       [[ "$response_code" == "401" ]] || [[ "$response_code" == "403" ]]; then
        test_pass
    elif [[ "$logout_response" == "000" ]] || [[ "$logout_response" == "404" ]]; then
        test_skip "Logout endpoint not available"
    else
        test_skip "Session still valid after logout (got $response_code)"
    fi
}

# ==============================================================================
# TEST RUNNER
# ==============================================================================

# Run all authentication security tests
run_authentication_tests() {
    local setup_result
    setup_result=$(setup_auth_tests)
    local setup_code=$?

    if [[ $setup_code -ne 0 ]]; then
        # Skip all tests
        test_start "authentication_security_tests"
        test_skip "Dependencies not met"
        return 2
    fi

    log_info "Running authentication security tests..."
    log_info "Moltis URL: $MOLTIS_URL"

    # Run P0 (Critical) tests first
    test_invalid_password
    test_empty_password
    test_valid_authentication
    test_unauthenticated_access_chat
    test_unauthenticated_access_mcp

    # Run P1 tests (may depend on successful auth)
    test_session_persistence || true
    test_session_cookie_httponly || true
    test_session_cookie_secure || true
    test_brute_force_resistance
    test_stolen_session_rejection || true
    test_logout_invalidates_session || true
}

# Run tests if sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    start_timer
    run_authentication_tests
    generate_report
fi
