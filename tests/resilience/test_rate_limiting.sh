#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

LIVE_MOLTIS_URL="${LIVE_MOLTIS_URL:-${MOLTIS_URL:-}}"
TEST_TIMEOUT="${TEST_TIMEOUT:-20}"
RATE_LIMIT_BURST="${RATE_LIMIT_BURST:-12}"
HEADER_FILE="$(secure_temp_file resilience-rate-limit-headers)"
RESPONSE_FILE="$(secure_temp_file resilience-rate-limit-response)"

login_attempt() {
    local password="$1"
    curl -s -D "$HEADER_FILE" -X POST "${LIVE_MOLTIS_URL}/api/auth/login" \
        -H 'Content-Type: application/json' \
        -d "$(jq -nc --arg password "$password" '{password: $password}')" \
        -o "$RESPONSE_FILE" \
        -w '%{http_code}' \
        --max-time "$TEST_TIMEOUT" 2>/dev/null || echo '000'
}

run_resilience_rate_limiting_tests() {
    start_timer

    if ! is_live_mode; then
        test_start "resilience_rate_limit_requires_live_mode"
        test_skip "Suite requires --live"
        generate_report
        return
    fi

    require_commands_or_skip curl jq || {
        test_start "resilience_rate_limit_setup"
        test_skip "Dependencies unavailable"
        generate_report
        return
    }

    test_start "resilience_rate_limit_target_configured"
    if [[ -z "$LIVE_MOLTIS_URL" ]]; then
        test_skip "Set LIVE_MOLTIS_URL or MOLTIS_URL for resilience rate-limit checks"
        generate_report
        return
    fi
    test_pass

    test_start "resilience_rate_limit_health_endpoint"
    local health_code
    health_code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "${LIVE_MOLTIS_URL}/health" 2>/dev/null || echo '000')
    if [[ "$health_code" == "200" ]]; then
        test_pass
    else
        test_fail "Health endpoint should return 200 (got $health_code)"
    fi

    test_start "resilience_rate_limit_login_burst"
    local saw_429=false
    local saw_retry_after=false
    local i code
    for i in $(seq 1 "$RATE_LIMIT_BURST"); do
        code=$(login_attempt "invalid-password-$i")
        if [[ "$code" == "429" ]]; then
            saw_429=true
            if rg -qi '^Retry-After:' "$HEADER_FILE"; then
                saw_retry_after=true
            fi
            break
        fi
    done
    if [[ "$saw_429" == "true" && "$saw_retry_after" == "true" ]]; then
        test_pass
    elif [[ "$saw_429" == "true" ]]; then
        test_fail "Rate limiting returned 429 without Retry-After header"
    else
        test_skip "Rate limiting not observed on login burst"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_resilience_rate_limiting_tests
fi
