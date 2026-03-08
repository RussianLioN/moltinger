#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

MOLTIS_URL="${TEST_BASE_URL:-${MOLTIS_URL:-http://127.0.0.1:13131}}"
TEST_TIMEOUT="${TEST_TIMEOUT:-20}"
ATTEMPTS=6
HEADER_FILE="$(secure_temp_file auth-rate-limit-headers)"
RESPONSE_FILE="$(secure_temp_file auth-rate-limit-response)"

setup_auth_rate_limit() {
    require_commands_or_skip curl jq || return 2
    [[ "$(health_status_code "$MOLTIS_URL" 5)" == "200" ]]
}

attempt_invalid_login() {
    curl -s -D "$HEADER_FILE" \
        -X POST "${MOLTIS_URL}/api/auth/login" \
        -H 'Content-Type: application/json' \
        -d '{"password":"definitely-wrong-password"}' \
        -o "$RESPONSE_FILE" \
        -w '%{http_code}' \
        --max-time "$TEST_TIMEOUT" 2>/dev/null || echo "000"
}

run_security_auth_rate_limit_tests() {
    start_timer

    local setup_code=0
    set +e
    setup_auth_rate_limit
    setup_code=$?
    set -e
    if [[ $setup_code -ne 0 ]]; then
        test_start "security_api_rate_limit_setup"
        if [[ $setup_code -eq 2 ]]; then
            test_skip "Dependencies unavailable"
        else
            test_fail "Moltis fixture stack is not reachable"
        fi
        generate_report
        return
    fi

    test_start "security_api_login_rate_limit_triggers_429"
    local triggered=false
    local i code
    for ((i=1; i<=ATTEMPTS; i++)); do
        code=$(attempt_invalid_login)
        if [[ "$code" == "429" ]]; then
            triggered=true
            break
        fi
        sleep 1
    done
    if [[ "$triggered" == "true" ]]; then
        test_pass
    else
        test_fail "Expected login throttling to return 429 within ${ATTEMPTS} attempts"
    fi

    test_start "security_api_login_rate_limit_sets_retry_after"
    if rg -qi '^retry-after:' "$HEADER_FILE"; then
        test_pass
    else
        test_fail "429 response should include Retry-After header"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_security_auth_rate_limit_tests
fi
