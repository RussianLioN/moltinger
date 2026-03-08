#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

MOLTIS_URL="${TEST_BASE_URL:-${MOLTIS_URL:-http://127.0.0.1:13131}}"
MOLTIS_PASSWORD="${MOLTIS_PASSWORD:-}"
TEST_TIMEOUT="${TEST_TIMEOUT:-30}"
COOKIE_FILE="$(secure_temp_file integration-api-cookie)"
HEADER_FILE="$(secure_temp_file integration-api-headers)"
RESPONSE_FILE="$(secure_temp_file integration-api-response)"
RPC_OUTPUT_FILE="$(secure_temp_file integration-api-rpc)"
AUTH_SUCCESS=false

setup_integration_local() {
    require_commands_or_skip curl jq node || return 2
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
        TEST_COOKIE_HEADER="$(cookie_file_to_header "$COOKIE_FILE")"
        export TEST_COOKIE_HEADER
        AUTH_SUCCESS=true
        return 0
    fi
    AUTH_SUCCESS=false
    return 1
}

read_auth_status() {
    curl_with_test_client_ip -s -b "$COOKIE_FILE" \
        -H 'Accept: application/json' \
        "${MOLTIS_URL}/api/auth/status" \
        --max-time "$TEST_TIMEOUT" >"$RESPONSE_FILE"
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
    if ws_rpc_request_noauth health '{}' "$RPC_OUTPUT_FILE"; then
        test_fail "Protected WS transport should not accept unauthenticated clients"
    elif jq -e '.ok == false and (.message | test("ws open timeout|connect"; "i"))' "$RPC_OUTPUT_FILE" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Unauthenticated WS connect should fail"
    fi

    test_start "integration_local_chat_endpoint"
    ws_rpc_request chat.send '{"text":"Hello from integration_local"}' "$RPC_OUTPUT_FILE" 2000 'chat'
    if jq -e '.ok == true and .result.ok == true and .result.payload.ok == true and ([.events[]? | select(.event == "chat" and .payload.state == "final")] | length) >= 1' "$RPC_OUTPUT_FILE" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Authenticated chat RPC should stream a final chat event"
    fi

    test_start "integration_local_runtime_status_rpc"
    ws_rpc_request status '{}' "$RPC_OUTPUT_FILE"
    if jq -e '.ok == true and .result.ok == true and (.result.payload.version | length > 0) and (.result.payload.connections >= 0)' "$RPC_OUTPUT_FILE" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Status RPC should expose runtime state for the authenticated fixture"
    fi

    test_start "integration_local_session_persistence"
    local before_count after_count first_message second_message
    first_message="first session message $(date +%s)"
    second_message="second session message $(date +%s)"

    ws_rpc_request chat.context '{}' "$RPC_OUTPUT_FILE"
    before_count=$(jq -r '.result.payload.session.messageCount // 0' "$RPC_OUTPUT_FILE")

    ws_rpc_request chat.send "$(jq -nc --arg text "$first_message" '{text: $text}')" "$RPC_OUTPUT_FILE" 1500 'chat'
    ws_rpc_request chat.send "$(jq -nc --arg text "$second_message" '{text: $text}')" "$RPC_OUTPUT_FILE" 1500 'chat'
    ws_rpc_request chat.context '{}' "$RPC_OUTPUT_FILE"
    after_count=$(jq -r '.result.payload.session.messageCount // 0' "$RPC_OUTPUT_FILE")
    ws_rpc_request chat.history '{}' "$RESPONSE_FILE"

    if (( after_count >= before_count + 2 )) \
        && jq -e --arg first "$first_message" --arg second "$second_message" '.result.payload | any(.content == $first) and any(.content == $second)' "$RESPONSE_FILE" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Session context/history should retain sequential chat messages"
    fi

    test_start "integration_local_logout_invalidates_session"
    local logout_code
    logout_code=$(moltis_logout_code "$MOLTIS_URL" "$COOKIE_FILE" "$TEST_TIMEOUT")
    unset TEST_COOKIE_HEADER || true
    read_auth_status
    if [[ "$logout_code" =~ ^(200|204|302|303)$ ]] && jq -e '.authenticated == false' "$RESPONSE_FILE" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Logout should invalidate the current authenticated session"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_integration_local_api_tests
fi
