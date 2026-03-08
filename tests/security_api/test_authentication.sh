#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

MOLTIS_URL="${TEST_BASE_URL:-${MOLTIS_URL:-http://127.0.0.1:13131}}"
MOLTIS_PASSWORD="${MOLTIS_PASSWORD:-}"
TEST_TIMEOUT="${TEST_TIMEOUT:-20}"
COOKIE_FILE="$(secure_temp_file security-auth-cookie)"
HEADER_FILE="$(secure_temp_file security-auth-headers)"
RESPONSE_FILE="$(secure_temp_file security-auth-response)"

setup_security_auth() {
    require_commands_or_skip curl jq || return 2
    if [[ -z "$MOLTIS_PASSWORD" ]] && ! is_live_mode; then
        MOLTIS_PASSWORD="test_password"
    fi
    require_secret_or_skip MOLTIS_PASSWORD "MOLTIS_PASSWORD" || return 2
    [[ "$(health_status_code "$MOLTIS_URL" 5)" == "200" ]]
}

login_with_password() {
    local password="$1"
    curl -s -D "$HEADER_FILE" -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
        -X POST "${MOLTIS_URL}/api/auth/login" \
        -H 'Content-Type: application/json' \
        -d "$(jq -nc --arg password "$password" '{password: $password}')" \
        -o "$RESPONSE_FILE" \
        -w '%{http_code}' \
        --max-time "$TEST_TIMEOUT" 2>/dev/null || echo "000"
}

run_security_authentication_tests() {
    start_timer

    local setup_code=0
    set +e
    setup_security_auth
    setup_code=$?
    set -e
    if [[ $setup_code -ne 0 ]]; then
        test_start "security_api_auth_setup"
        if [[ $setup_code -eq 2 ]]; then
            test_skip "Dependencies or secrets unavailable"
        else
            test_fail "Moltis fixture stack is not reachable"
        fi
        generate_report
        return
    fi

    test_start "security_api_invalid_password_rejected"
    local invalid_code
    invalid_code=$(login_with_password "wrong-password")
    if [[ "$invalid_code" == "401" || "$invalid_code" == "403" ]]; then
        test_pass
    else
        test_fail "Invalid password should return 401/403 (got $invalid_code)"
    fi

    test_start "security_api_empty_password_rejected"
    local empty_code
    empty_code=$(login_with_password "")
    if [[ "$empty_code" == "400" || "$empty_code" == "401" || "$empty_code" == "403" ]]; then
        test_pass
    else
        test_fail "Empty password should be rejected (got $empty_code)"
    fi

    test_start "security_api_valid_password_accepted"
    local valid_code
    valid_code=$(login_with_password "$MOLTIS_PASSWORD")
    if [[ "$valid_code" == "200" || "$valid_code" == "302" || "$valid_code" == "303" ]]; then
        test_pass
    else
        test_fail "Valid password should authenticate (got $valid_code)"
    fi

    test_start "security_api_protected_chat_requires_auth"
    rm -f "$COOKIE_FILE"
    local unauth_chat_code
    unauth_chat_code=$(moltis_request POST "$MOLTIS_URL" "/api/v1/chat" "$COOKIE_FILE" "$RESPONSE_FILE" "$TEST_TIMEOUT" '{"message":"unauthenticated"}')
    if [[ "$unauth_chat_code" == "401" || "$unauth_chat_code" == "403" || "$unauth_chat_code" == "302" ]]; then
        test_pass
    else
        test_fail "Protected chat endpoint should require auth (got $unauth_chat_code)"
    fi

    test_start "security_api_session_cookie_is_httponly"
    login_with_password "$MOLTIS_PASSWORD" >/dev/null
    if rg -qi '^set-cookie:.*httponly' "$HEADER_FILE"; then
        test_pass
    else
        test_fail "Session cookie should include HttpOnly"
    fi

    test_start "security_api_logout_invalidates_session"
    login_with_password "$MOLTIS_PASSWORD" >/dev/null
    local logout_code post_logout_code
    logout_code=$(moltis_logout_code "$MOLTIS_URL" "$COOKIE_FILE" "$TEST_TIMEOUT")
    post_logout_code=$(moltis_request POST "$MOLTIS_URL" "/api/v1/chat" "$COOKIE_FILE" "$RESPONSE_FILE" "$TEST_TIMEOUT" '{"message":"after logout"}')
    if [[ "$logout_code" =~ ^(200|204|302|303)$ && "$post_logout_code" =~ ^(401|403|302)$ ]]; then
        test_pass
    else
        test_fail "Logout should invalidate session (logout=$logout_code, post=$post_logout_code)"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_security_authentication_tests
fi
