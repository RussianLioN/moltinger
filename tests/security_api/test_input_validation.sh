#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

MOLTIS_URL="${TEST_BASE_URL:-${MOLTIS_URL:-http://127.0.0.1:13131}}"
MOLTIS_PASSWORD="${MOLTIS_PASSWORD:-}"
TEST_TIMEOUT="${TEST_TIMEOUT:-20}"
COOKIE_FILE="$(secure_temp_file security-input-cookie)"
HEADER_FILE="$(secure_temp_file security-input-headers)"
RESPONSE_FILE="$(secure_temp_file security-input-response)"
MAX_MESSAGE_BYTES=12000

setup_security_input() {
    require_commands_or_skip curl jq || return 2
    if [[ -z "$MOLTIS_PASSWORD" ]] && ! is_live_mode; then
        MOLTIS_PASSWORD="test_password"
    fi
    require_secret_or_skip MOLTIS_PASSWORD "MOLTIS_PASSWORD" || return 2
    [[ "$(health_status_code "$MOLTIS_URL" 5)" == "200" ]]
}

login_fixture_user() {
    local code
    code=$(moltis_login_code "$MOLTIS_URL" "$MOLTIS_PASSWORD" "$COOKIE_FILE" "$TEST_TIMEOUT")
    [[ "$code" == "200" || "$code" == "302" || "$code" == "303" ]]
}

chat_with_payload() {
    local payload="$1"
    curl -s -D "$HEADER_FILE" -b "$COOKIE_FILE" \
        -X POST "${MOLTIS_URL}/api/v1/chat" \
        -H 'Content-Type: application/json' \
        -d "$payload" \
        -o "$RESPONSE_FILE" \
        -w '%{http_code}' \
        --max-time "$TEST_TIMEOUT" 2>/dev/null || echo "000"
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

    test_start "security_api_empty_message_rejected"
    local empty_code
    empty_code=$(chat_with_payload '{"message":""}')
    if [[ "$empty_code" == "400" || "$empty_code" == "422" ]]; then
        test_pass
    else
        test_fail "Empty messages should be rejected (got $empty_code)"
    fi

    test_start "security_api_malformed_json_rejected"
    local malformed_code
    malformed_code=$(curl -s -b "$COOKIE_FILE" -X POST "${MOLTIS_URL}/api/v1/chat" -H 'Content-Type: application/json' -d '{"message":' -o "$RESPONSE_FILE" -w '%{http_code}' --max-time "$TEST_TIMEOUT" 2>/dev/null || echo "000")
    if [[ "$malformed_code" == "400" || "$malformed_code" == "422" ]]; then
        test_pass
    else
        test_fail "Malformed JSON should be rejected (got $malformed_code)"
    fi

    test_start "security_api_oversized_message_no_server_error"
    local long_message oversized_code
    long_message=$(python3 - <<'PY'
print('A' * 12000)
PY
)
    oversized_code=$(chat_with_payload "$(jq -nc --arg message "$long_message" '{message: $message}')")
    if [[ "$oversized_code" == "400" || "$oversized_code" == "413" || "$oversized_code" == "422" || "$oversized_code" == "200" || "$oversized_code" == "202" ]]; then
        test_pass
    else
        test_fail "Oversized message should not crash server (got $oversized_code)"
    fi

    test_start "security_api_xss_payload_no_server_error"
    local xss_payload xss_code
    xss_payload='<script>alert("xss")</script>'
    xss_code=$(chat_with_payload "$(jq -nc --arg message "$xss_payload" '{message: $message}')")
    if [[ "$xss_code" =~ ^(200|202|400|422)$ ]]; then
        if [[ "$xss_code" =~ ^(200|202)$ ]] && rg -Fq "$xss_payload" "$RESPONSE_FILE"; then
            test_fail "Response reflected raw XSS payload"
        else
            test_pass
        fi
    else
        test_fail "XSS payload should not cause 5xx behavior (got $xss_code)"
    fi

    test_start "security_api_sql_injection_payload_no_server_error"
    local sql_code
    sql_code=$(chat_with_payload "$(jq -nc --arg message "' OR '1'='1" '{message: $message}')")
    if [[ "$sql_code" =~ ^(200|202|400|422)$ ]]; then
        test_pass
    else
        test_fail "SQL injection payload should not cause 5xx behavior (got $sql_code)"
    fi

    test_start "security_api_path_traversal_payload_no_server_error"
    local traversal_code
    traversal_code=$(chat_with_payload "$(jq -nc --arg message "../../../etc/passwd" '{message: $message}')")
    if [[ "$traversal_code" =~ ^(200|202|400|422)$ ]]; then
        test_pass
    else
        test_fail "Path traversal payload should not cause 5xx behavior (got $traversal_code)"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_security_input_validation_tests
fi
