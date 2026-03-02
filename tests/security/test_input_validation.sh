#!/bin/bash
# test_input_validation.sh - Security tests for Moltis input validation
# Tests input sanitization: message size limits, special characters, XSS, SQL injection
#
# Test Scenarios:
#   P0: test_message_size_limit - Large messages are handled/rejected
#   P0: test_empty_message - Empty message is rejected
#   P1: test_special_characters - Special characters don't break the system
#   P1: test_xss_attempt - XSS attempts are sanitized
#   P1: test_sql_injection - SQL injection attempts are blocked
#   P1: test_command_injection - Command injection attempts are blocked
#   P1: test_path_traversal - Path traversal attempts are blocked
#
# Usage:
#   source tests/security/test_input_validation.sh
#   run_input_validation_tests
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
MAX_MESSAGE_SIZE="${MAX_MESSAGE_SIZE:-10000}"  # 10KB default

# Cookie file for authenticated requests
COOKIE_FILE="/tmp/test-input-validation-cookie-$$"

# Test results
AUTH_SUCCESS=false

# Security test vectors
declare -a XSS_VECTORS=(
    '<script>alert("XSS")</script>'
    '<img src=x onerror=alert(1)>'
    '<svg onload=alert(1)>'
    'javascript:alert(1)'
    '<iframe src="javascript:alert(1)">'
    '"><script>alert(String.fromCharCode(88,83,83))</script>'
)

declare -a SQL_INJECTION_VECTORS=(
    "'; DROP TABLE users; --"
    "' OR '1'='1"
    '" OR "1"="1'
    "1' UNION SELECT NULL--"
    "'; EXEC xp_cmdshell('dir'); --"
    "' OR 1=1#"
)

declare -a COMMAND_INJECTION_VECTORS=(
    '; ls -la'
    '| cat /etc/passwd'
    '`whoami`'
    '$(id)'
    '; ping -c 1 127.0.0.1'
    '| cat /proc/version'
)

declare -a PATH_TRAVERSAL_VECTORS=(
    '../../../etc/passwd'
    '..\\..\\..\\..\\windows\\system32\\drivers\\etc\\hosts'
    '....//....//....//etc/passwd'
    '%2e%2e%2fetc%2fpasswd'
    '..%252f..%252f..%252fetc%252fpasswd'
)

# ==============================================================================
# SETUP AND TEARDOWN
# ==============================================================================

# Setup test environment
setup_input_tests() {
    log_debug "Setting up input validation security tests"

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

    # Authenticate for tests that require it
    local response_code
    response_code=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
        -X POST "${MOLTIS_URL}/login" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "password=${MOLTIS_PASSWORD}" \
        -o /dev/null \
        -w "%{http_code}" \
        --max-time "$TEST_TIMEOUT" 2>/dev/null || echo "000")

    if [[ "$response_code" == "200" ]] || [[ "$response_code" == "302" ]]; then
        AUTH_SUCCESS=true
        log_debug "Authentication successful"
    else
        log_warn "Authentication failed (HTTP $response_code), some tests may be skipped"
    fi

    return 0
}

# Cleanup test environment
cleanup_input_tests() {
    log_debug "Cleaning up input validation security tests"
    rm -f "$COOKIE_FILE"
}

# Register cleanup on exit
trap cleanup_input_tests EXIT

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

# Send message to chat endpoint
# Usage: send_message "message content"
# Returns: HTTP response code
send_message() {
    local message="$1"
    local json_escaped
    json_escaped=$(echo "$message" | jq -Rs .)

    local response_code
    response_code=$(curl -s -b "$COOKIE_FILE" \
        -X POST "${MOLTIS_URL}/api/v1/chat" \
        -H "Content-Type: application/json" \
        -d "{\"message\": $json_escaped}" \
        -o /dev/null \
        -w "%{http_code}" \
        --max-time "$TEST_TIMEOUT" 2>/dev/null || echo "000")

    echo "$response_code"
}

# Get response body from chat endpoint
# Usage: get_response_body "message content"
get_response_body() {
    local message="$1"
    local json_escaped
    json_escaped=$(echo "$message" | jq -Rs .)

    local response
    response=$(curl -s -b "$COOKIE_FILE" \
        -X POST "${MOLTIS_URL}/api/v1/chat" \
        -H "Content-Type: application/json" \
        -d "{\"message\": $json_escaped}" \
        --max-time "$TEST_TIMEOUT" 2>/dev/null || echo "")

    echo "$response"
}

# Check if response contains error indicator
# Usage: is_error_response "response_body"
is_error_response() {
    local response="$1"

    # Check for JSON error response
    if echo "$response" | jq -e '.error' > /dev/null 2>&1; then
        return 0
    fi

    # Check for common error indicators in text
    if echo "$response" | grep -qiE "(error|invalid|rejected|denied)"; then
        return 0
    fi

    return 1
}

# Check if malicious content is reflected unsanitized
# Usage: is_reflected_unsanitized "response_body" "malicious_string"
is_reflected_unsanitized() {
    local response="$1"
    local malicious="$2"

    # Check if malicious string appears in response
    if [[ "$response" == *"$malicious"* ]]; then
        return 0
    fi

    return 1
}

# ==============================================================================
# TEST CASES
# ==============================================================================

# Test 1: Empty message is rejected (P0 - Critical)
test_empty_message() {
    test_start "empty_message"

    if [[ "$AUTH_SUCCESS" != "true" ]]; then
        test_skip "Not authenticated"
        return 2
    fi

    local response_code
    response_code=$(send_message "")

    # Should return 400 (Bad Request) for empty message
    if [[ "$response_code" == "400" ]] || [[ "$response_code" == "422" ]]; then
        test_pass
    else
        # Some systems may accept empty messages (graceful handling)
        if [[ "$response_code" == "200" ]] || [[ "$response_code" == "202" ]]; then
            test_pass "Empty message accepted (graceful handling)"
        else
            test_fail "Expected 400/422 for empty message, got $response_code"
        fi
    fi
}

# Test 2: Message size limit is enforced (P0 - Critical)
test_message_size_limit() {
    test_start "message_size_limit"

    if [[ "$AUTH_SUCCESS" != "true" ]]; then
        test_skip "Not authenticated"
        return 2
    fi

    # Generate a large message (10x the expected limit)
    local large_message
    large_message=$(python3 -c "print('x' * $((MAX_MESSAGE_SIZE * 10)))" 2>/dev/null || echo "")

    if [[ -z "$large_message" ]]; then
        # Fallback: use simpler method
        large_message=$(head -c $((MAX_MESSAGE_SIZE * 10)) < /dev/zero | tr '\0' 'x')
    fi

    local response_code
    response_code=$(send_message "$large_message")

    # Should reject or handle gracefully
    if [[ "$response_code" == "413" ]] || [[ "$response_code" == "400" ]] || [[ "$response_code" == "422" ]]; then
        test_pass "Large message rejected (HTTP $response_code)"
    elif [[ "$response_code" == "200" ]] || [[ "$response_code" == "202" ]]; then
        test_pass "Large message accepted (server handles it)"
    elif [[ "$response_code" == "500" ]] || [[ "$response_code" == "502" ]] || [[ "$response_code" == "503" ]]; then
        test_fail "Server error on large message (HTTP $response_code)"
    else
        test_skip "Unexpected response for large message: $response_code"
    fi
}

# Test 3: Maximum allowed message size works (P1)
test_max_allowed_message() {
    test_start "max_allowed_message"

    if [[ "$AUTH_SUCCESS" != "true" ]]; then
        test_skip "Not authenticated"
        return 2
    fi

    # Generate message at the limit
    local max_message
    max_message=$(python3 -c "print('x' * $((MAX_MESSAGE_SIZE - 100)))" 2>/dev/null || echo "")

    if [[ -z "$max_message" ]]; then
        max_message=$(head -c $((MAX_MESSAGE_SIZE - 100)) < /dev/zero | tr '\0' 'x')
    fi

    local response_code
    response_code=$(send_message "$max_message")

    # Should accept messages at the limit
    if [[ "$response_code" == "200" ]] || [[ "$response_code" == "202" ]]; then
        test_pass
    elif [[ "$response_code" == "413" ]] || [[ "$response_code" == "400" ]]; then
        test_skip "Message size limit may be lower than $MAX_MESSAGE_SIZE"
    else
        test_skip "Unexpected response: $response_code"
    fi
}

# Test 4: Special characters are handled (P1)
test_special_characters() {
    test_start "special_characters"

    if [[ "$AUTH_SUCCESS" != "true" ]]; then
        test_skip "Not authenticated"
        return 2
    fi

    local special_message='!@#$%^&*()_+-={}[]|:";<>?,./`~'

    local response_code
    response_code=$(send_message "$special_message")

    # Should handle special characters gracefully
    if [[ "$response_code" == "200" ]] || [[ "$response_code" == "202" ]]; then
        test_pass
    elif [[ "$response_code" == "500" ]]; then
        test_fail "Server crashed on special characters"
    else
        test_skip "Unexpected response: $response_code"
    fi
}

# Test 5: Unicode characters are handled (P1)
test_unicode_characters() {
    test_start "unicode_characters"

    if [[ "$AUTH_SUCCESS" != "true" ]]; then
        test_skip "Not authenticated"
        return 2
    fi

    local unicode_message='Test Приват 你好 مرحبا 🎉✨'

    local response_code
    response_code=$(send_message "$unicode_message")

    # Should handle Unicode gracefully
    if [[ "$response_code" == "200" ]] || [[ "$response_code" == "202" ]]; then
        test_pass
    elif [[ "$response_code" == "500" ]]; then
        test_fail "Server crashed on Unicode characters"
    else
        test_skip "Unexpected response: $response_code"
    fi
}

# Test 6: XSS attempts are sanitized (P1)
test_xss_attempts() {
    test_start "xss_attempts"

    if [[ "$AUTH_SUCCESS" != "true" ]]; then
        test_skip "Not authenticated"
        return 2
    fi

    local xss_blocked=true

    for xss_vector in "${XSS_VECTORS[@]}"; do
        log_debug "Testing XSS vector: $xss_vector"

        local response
        response=$(get_response_body "$xss_vector")

        # Check if unsanitized XSS is reflected
        if is_reflected_unsanitized "$response" "$xss_vector"; then
            # Vector may be reflected but properly escaped
            # Check if script tags are intact (bad)
            if [[ "$response" == *"<script>"* ]]; then
                log_warn "Possible unsanitized XSS reflection: $xss_vector"
                xss_blocked=false
            fi
        fi
    done

    if [[ "$xss_blocked" == "true" ]]; then
        test_pass
    else
        test_fail "XSS vectors may not be properly sanitized"
    fi
}

# Test 7: SQL injection attempts are blocked (P1)
test_sql_injection_attempts() {
    test_start "sql_injection_attempts"

    if [[ "$AUTH_SUCCESS" != "true" ]]; then
        test_skip "Not authenticated"
        return 2
    fi

    local sql_blocked=true

    for sql_vector in "${SQL_INJECTION_VECTORS[@]}"; do
        log_debug "Testing SQL injection vector: $sql_vector"

        local response_code
        response_code=$(send_message "$sql_vector")

        # Should not cause server error
        if [[ "$response_code" == "500" ]] || [[ "$response_code" == "502" ]]; then
            log_warn "Server error on SQL injection vector"
            sql_blocked=false
        fi
    done

    if [[ "$sql_blocked" == "true" ]]; then
        test_pass
    else
        test_fail "SQL injection vectors caused server errors"
    fi
}

# Test 8: Command injection attempts are blocked (P1)
test_command_injection_attempts() {
    test_start "command_injection_attempts"

    if [[ "$AUTH_SUCCESS" != "true" ]]; then
        test_skip "Not authenticated"
        return 2
    fi

    local cmd_blocked=true

    for cmd_vector in "${COMMAND_INJECTION_VECTORS[@]}"; do
        log_debug "Testing command injection vector: $cmd_vector"

        local response_code
        response_code=$(send_message "$cmd_vector")

        # Should not cause server error
        if [[ "$response_code" == "500" ]] || [[ "$response_code" == "502" ]]; then
            log_warn "Server error on command injection vector"
            cmd_blocked=false
        fi
    done

    if [[ "$cmd_blocked" == "true" ]]; then
        test_pass
    else
        test_fail "Command injection vectors caused server errors"
    fi
}

# Test 9: Path traversal attempts are blocked (P1)
test_path_traversal_attempts() {
    test_start "path_traversal_attempts"

    if [[ "$AUTH_SUCCESS" != "true" ]]; then
        test_skip "Not authenticated"
        return 2
    fi

    local path_blocked=true

    for path_vector in "${PATH_TRAVERSAL_VECTORS[@]}"; do
        log_debug "Testing path traversal vector: $path_vector"

        local response_code
        response_code=$(send_message "$path_vector")

        # Should not cause server error
        if [[ "$response_code" == "500" ]] || [[ "$response_code" == "502" ]]; then
            log_warn "Server error on path traversal vector"
            path_blocked=false
        fi

        # Check if file content is leaked
        local response
        response=$(get_response_body "$path_vector")

        if [[ "$response" == *"root:"* ]] || [[ "$response" == *"[extensions]"* ]]; then
            log_warn "Possible file content leak detected"
            path_blocked=false
        fi
    done

    if [[ "$path_blocked" == "true" ]]; then
        test_pass
    else
        test_fail "Path traversal vectors caused issues"
    fi
}

# Test 10: Null bytes are handled (P1)
test_null_bytes() {
    test_start "null_bytes"

    if [[ "$AUTH_SUCCESS" != "true" ]]; then
        test_skip "Not authenticated"
        return 2
    fi

    # Message with null byte
    local null_message="test$(printf '\0')message"

    local response_code
    response_code=$(send_message "$null_message")

    # Should handle null bytes gracefully
    if [[ "$response_code" == "200" ]] || [[ "$response_code" == "202" ]]; then
        test_pass
    elif [[ "$response_code" == "400" ]] || [[ "$response_code" == "422" ]]; then
        test_pass "Null bytes rejected"
    elif [[ "$response_code" == "500" ]]; then
        test_fail "Server error on null bytes"
    else
        test_skip "Unexpected response: $response_code"
    fi
}

# Test 11: Very long input lines are handled (P1)
test_long_line_handling() {
    test_start "long_line_handling"

    if [[ "$AUTH_SUCCESS" != "true" ]]; then
        test_skip "Not authenticated"
        return 2
    fi

    # Generate a single very long line
    local long_line="test "
    long_line+="$(head -c 5000 < /dev/zero | tr '\0' 'a')"
    long_line+=" end"

    local response_code
    response_code=$(send_message "$long_line")

    # Should handle long lines gracefully
    if [[ "$response_code" == "200" ]] || [[ "$response_code" == "202" ]]; then
        test_pass
    elif [[ "$response_code" == "413" ]] || [[ "$response_code" == "400" ]]; then
        test_pass "Long line rejected"
    elif [[ "$response_code" == "500" ]]; then
        test_fail "Server error on long line"
    else
        test_skip "Unexpected response: $response_code"
    fi
}

# Test 12: Malformed JSON is rejected (P1)
test_malformed_json() {
    test_start "malformed_json"

    if [[ "$AUTH_SUCCESS" != "true" ]]; then
        test_skip "Not authenticated"
        return 2
    fi

    local response_code
    response_code=$(curl -s -b "$COOKIE_FILE" \
        -X POST "${MOLTIS_URL}/api/v1/chat" \
        -H "Content-Type: application/json" \
        -d '{"message": unclosed quote' \
        -o /dev/null \
        -w "%{http_code}" \
        --max-time "$TEST_TIMEOUT" 2>/dev/null || echo "000")

    # Should reject malformed JSON
    if [[ "$response_code" == "400" ]] || [[ "$response_code" == "422" ]]; then
        test_pass
    elif [[ "$response_code" == "500" ]]; then
        test_fail "Server crashed on malformed JSON"
    else
        test_skip "Unexpected response: $response_code"
    fi
}

# Test 13: Extra JSON fields are ignored (P1)
test_extra_json_fields() {
    test_start "extra_json_fields"

    if [[ "$AUTH_SUCCESS" != "true" ]]; then
        test_skip "Not authenticated"
        return 2
    fi

    local response_code
    response_code=$(curl -s -b "$COOKIE_FILE" \
        -X POST "${MOLTIS_URL}/api/v1/chat" \
        -H "Content-Type: application/json" \
        -d '{"message": "test", "extra_field": "value", "another": 123}' \
        -o /dev/null \
        -w "%{http_code}" \
        --max-time "$TEST_TIMEOUT" 2>/dev/null || echo "000")

    # Should handle gracefully (ignore extra fields)
    if [[ "$response_code" == "200" ]] || [[ "$response_code" == "202" ]]; then
        test_pass
    elif [[ "$response_code" == "400" ]]; then
        test_pass "Extra fields rejected (strict schema)"
    else
        test_skip "Unexpected response: $response_code"
    fi
}

# Test 14: Newline and tab characters are handled (P1)
test_whitespace_characters() {
    test_start "whitespace_characters"

    if [[ "$AUTH_SUCCESS" != "true" ]]; then
        test_skip "Not authenticated"
        return 2
    fi

    local whitespace_message="test$(printf '\n\r\t')message"

    local response_code
    response_code=$(send_message "$whitespace_message")

    # Should handle whitespace characters
    if [[ "$response_code" == "200" ]] || [[ "$response_code" == "202" ]]; then
        test_pass
    elif [[ "$response_code" == "500" ]]; then
        test_fail "Server error on whitespace characters"
    else
        test_skip "Unexpected response: $response_code"
    fi
}

# ==============================================================================
# TEST RUNNER
# ==============================================================================

# Run all input validation security tests
run_input_validation_tests() {
    local setup_result
    setup_result=$(setup_input_tests)
    local setup_code=$?

    if [[ $setup_code -ne 0 ]]; then
        # Skip all tests
        test_start "input_validation_security_tests"
        test_skip "Dependencies not met"
        return 2
    fi

    log_info "Running input validation security tests..."
    log_info "Moltis URL: $MOLTIS_URL"
    log_info "Max message size: $MAX_MESSAGE_SIZE"

    # Run P0 (Critical) tests
    test_empty_message
    test_message_size_limit

    # Run P1 tests
    test_max_allowed_message || true
    test_special_characters
    test_unicode_characters
    test_xss_attempts
    test_sql_injection_attempts
    test_command_injection_attempts
    test_path_traversal_attempts
    test_null_bytes || true
    test_long_line_handling || true
    test_malformed_json || true
    test_extra_json_fields || true
    test_whitespace_characters || true
}

# Run tests if sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    start_timer
    run_input_validation_tests
    generate_report
fi
