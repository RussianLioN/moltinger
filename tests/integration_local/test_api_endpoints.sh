#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

MOLTIS_URL="${TEST_BASE_URL:-${MOLTIS_URL:-http://127.0.0.1:13131}}"
MOLTIS_PASSWORD="${MOLTIS_PASSWORD:-}"
TEST_TIMEOUT="${TEST_TIMEOUT:-30}"
COOKIE_FILE="$(secure_temp_file integration-api-cookie)"
RESPONSE_FILE="$(secure_temp_file integration-api-response)"
AUTH_SUCCESS=false

setup_integration_local() {
    require_commands_or_skip curl jq || return 2
    if [[ -z "$MOLTIS_PASSWORD" ]] && ! is_live_mode; then
        MOLTIS_PASSWORD="test_password"
    fi
    require_secret_or_skip MOLTIS_PASSWORD "MOLTIS_PASSWORD" || return 2
    local health_code
    health_code=$(health_status_code "$MOLTIS_URL" 5)
    if [[ "$health_code" != "200" ]]; then
        return 1
    fi
    return 0
}

login_or_fail() {
    local code
    code=$(moltis_login_code "$MOLTIS_URL" "$MOLTIS_PASSWORD" "$COOKIE_FILE" "$TEST_TIMEOUT")
    if [[ "$code" == "200" || "$code" == "302" || "$code" == "303" ]]; then
        AUTH_SUCCESS=true
        return 0
    fi
    AUTH_SUCCESS=false
    return 1
}

chat_request() {
    local payload
    payload=$(jq -nc --arg message "$1" '{message: $message}')
    moltis_request POST "$MOLTIS_URL" "/api/v1/chat" "$COOKIE_FILE" "$RESPONSE_FILE" "$TEST_TIMEOUT" "$payload"
}

run_integration_local_api_tests() {
    start_timer

    local setup_code=0
    set +e
    setup_integration_local
    setup_code=$?
    set -e
    if [[ $setup_code -ne 0 ]]; then
        test_start "integration_local_setup"
        if [[ $setup_code -eq 2 ]]; then
            test_skip "Dependencies or fixture secrets not available"
        else
            test_fail "Moltis fixture stack is not reachable"
        fi
        generate_report
        return
    fi

    test_start "integration_local_health_endpoint"
    assert_eq "200" "$(health_status_code "$MOLTIS_URL" 5)" "Health endpoint should return 200"
    test_pass

    test_start "integration_local_login_success"
    if login_or_fail; then
        test_pass
    else
        test_fail "Fixture login should succeed"
    fi

    test_start "integration_local_chat_requires_auth"
    rm -f "$COOKIE_FILE"
    local unauth_code
    unauth_code=$(moltis_request POST "$MOLTIS_URL" "/api/v1/chat" "$COOKIE_FILE" "$RESPONSE_FILE" "$TEST_TIMEOUT" '{"message":"auth required?"}')
    if [[ "$unauth_code" == "401" || "$unauth_code" == "403" || "$unauth_code" == "302" ]]; then
        test_pass
    else
        test_fail "Chat endpoint should reject unauthenticated requests (got $unauth_code)"
    fi

    test_start "integration_local_chat_endpoint"
    login_or_fail || true
    local chat_code
    chat_code=$(chat_request "Hello from integration_local")
    if [[ "$chat_code" == "200" || "$chat_code" == "202" ]]; then
        test_pass
    else
        test_fail "Authenticated chat request should succeed (got $chat_code)"
    fi

    test_start "integration_local_metrics_endpoint"
    local metrics_code
    metrics_code=$(curl -s -o "$RESPONSE_FILE" -w '%{http_code}' --max-time "$TEST_TIMEOUT" "$MOLTIS_URL/metrics" 2>/dev/null || echo "000")
    if [[ "$metrics_code" == "200" ]] && rg -q 'moltis_circuit_state|llm_provider_available' "$RESPONSE_FILE"; then
        test_pass
    else
        test_fail "Metrics endpoint should expose Prometheus series"
    fi

    test_start "integration_local_session_persistence"
    login_or_fail || true
    local first_code second_code
    first_code=$(chat_request "first session message")
    second_code=$(chat_request "second session message")
    if [[ "$first_code" =~ ^(200|202)$ && "$second_code" =~ ^(200|202)$ ]]; then
        test_pass
    else
        test_fail "Session cookie should persist across sequential chat requests"
    fi

    test_start "integration_local_logout_invalidates_session"
    login_or_fail || true
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
    run_integration_local_api_tests
fi
