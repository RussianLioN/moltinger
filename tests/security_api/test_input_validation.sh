#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

MOLTIS_URL="${TEST_BASE_URL:-${MOLTIS_URL:-http://127.0.0.1:13131}}"
MOLTIS_PASSWORD="${MOLTIS_PASSWORD:-}"
TEST_TIMEOUT="${TEST_TIMEOUT:-20}"
COOKIE_FILE="$(secure_temp_file security-input-cookie)"
RPC_OUTPUT_FILE="$(secure_temp_file security-input-rpc)"
MAX_MESSAGE_BYTES=12000

setup_security_input() {
    require_commands_or_skip curl jq node python3 || return 2
    if [[ -z "$MOLTIS_PASSWORD" ]] && ! is_live_mode; then
        MOLTIS_PASSWORD="test_password"
    fi
    require_secret_or_skip MOLTIS_PASSWORD "MOLTIS_PASSWORD" || return 2
    [[ "$(health_status_code "$MOLTIS_URL" 5)" == "200" ]]
}

login_fixture_user() {
    local code
    code=$(moltis_login_code "$MOLTIS_URL" "$MOLTIS_PASSWORD" "$COOKIE_FILE" "$TEST_TIMEOUT")
    if [[ "$code" == "200" || "$code" == "302" || "$code" == "303" ]]; then
        TEST_COOKIE_HEADER="$(cookie_file_to_header "$COOKIE_FILE")"
        export TEST_COOKIE_HEADER
        return 0
    fi
    return 1
}

assert_chat_rpc_completed() {
    local file="$1"
    jq -e '
      .ok == true
      and .result.ok == true
      and .result.payload.ok == true
      and ([.events[]? | select(.event == "chat" and (.payload.state == "final" or .payload.state == "error"))] | length) >= 1
    ' "$file" >/dev/null 2>&1
}

run_security_input_validation_tests() {
    start_timer

    local setup_code=0
    set +e
    setup_security_input
    setup_code=$?
    set -e
    if [[ $setup_code -ne 0 ]]; then
        test_start "security_api_input_setup"
        if [[ $setup_code -eq 2 ]]; then
            test_skip "Dependencies or secrets unavailable"
        else
            test_fail "Moltis fixture stack is not reachable"
        fi
        generate_report
        return
    fi

    if ! login_fixture_user; then
        test_start "security_api_input_login"
        test_fail "Fixture login should succeed before input validation tests"
        generate_report
        return
    fi

    test_start "security_api_empty_message_handled"
    ws_rpc_request chat.send '{"text":""}' "$RPC_OUTPUT_FILE" 1500 'chat'
    if assert_chat_rpc_completed "$RPC_OUTPUT_FILE"; then
        test_pass
    else
        test_fail "Empty message should be handled without transport failure"
    fi

    test_start "security_api_malformed_frame_handled"
    ws_rpc_invalid_frame '{"type":"req","id":"broken"' "$RPC_OUTPUT_FILE" 500
    if jq -e '.ok == true and .result.ok == true and .result.payload.status == "ok" and ([.events[]? | select(.event == "error" and (.payload.message | test("invalid frame"; "i")))] | length) >= 1' "$RPC_OUTPUT_FILE" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Malformed frame should not crash the WS gateway"
    fi

    test_start "security_api_oversized_message_no_server_error"
    local long_message
    long_message=$(python3 - <<'PY'
print('A' * 12000)
PY
)
    ws_rpc_request chat.send "$(jq -nc --arg text "$long_message" '{text: $text}')" "$RPC_OUTPUT_FILE" 1500 'chat'
    if assert_chat_rpc_completed "$RPC_OUTPUT_FILE"; then
        test_pass
    else
        test_fail "Oversized message should not crash the chat transport"
    fi

    test_start "security_api_xss_payload_no_server_error"
    local xss_payload
    xss_payload='<script>alert("xss")</script>'
    ws_rpc_request chat.send "$(jq -nc --arg text "$xss_payload" '{text: $text}')" "$RPC_OUTPUT_FILE" 1500 'chat'
    if assert_chat_rpc_completed "$RPC_OUTPUT_FILE"; then
        test_pass
    else
        test_fail "XSS payload should not crash the chat transport"
    fi

    test_start "security_api_sql_injection_payload_no_server_error"
    ws_rpc_request chat.send "$(jq -nc --arg text "' OR '1'='1" '{text: $text}')" "$RPC_OUTPUT_FILE" 1500 'chat'
    if assert_chat_rpc_completed "$RPC_OUTPUT_FILE"; then
        test_pass
    else
        test_fail "SQL injection payload should not crash the chat transport"
    fi

    test_start "security_api_path_traversal_payload_no_server_error"
    ws_rpc_request chat.send "$(jq -nc --arg text "../../../etc/passwd" '{text: $text}')" "$RPC_OUTPUT_FILE" 1500 'chat'
    if assert_chat_rpc_completed "$RPC_OUTPUT_FILE"; then
        test_pass
    else
        test_fail "Path traversal payload should not crash the chat transport"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_security_input_validation_tests
fi
