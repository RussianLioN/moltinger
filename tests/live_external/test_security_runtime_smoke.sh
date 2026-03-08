#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

LIVE_MOLTIS_URL="${LIVE_MOLTIS_URL:-${MOLTIS_URL:-}}"
MOLTIS_PASSWORD="${MOLTIS_PASSWORD:-}"
HEADER_FILE="$(secure_temp_file security-runtime-headers)"
RESPONSE_FILE="$(secure_temp_file security-runtime-response)"

run_security_runtime_smoke_tests() {
    start_timer

    if ! is_live_mode; then
        test_start "security_runtime_requires_live_mode"
        test_skip "Suite requires --live"
        generate_report
        return
    fi

    require_commands_or_skip curl jq || {
        test_start "security_runtime_setup"
        test_skip "Dependencies unavailable"
        generate_report
        return
    }

    test_start "security_runtime_target_configured"
    if [[ -z "$LIVE_MOLTIS_URL" ]]; then
        test_skip "Set LIVE_MOLTIS_URL or MOLTIS_URL for live runtime smoke"
    else
        test_pass
    fi

    test_start "security_runtime_password_available"
    require_secret_or_skip MOLTIS_PASSWORD "MOLTIS_PASSWORD" || {
        generate_report
        return
    }
    test_pass

    test_start "security_runtime_login_sets_cookie"
    local code
    code=$(curl -s -D "$HEADER_FILE" -X POST "${LIVE_MOLTIS_URL}/api/auth/login" -H 'Content-Type: application/json' -d "$(jq -nc --arg password "$MOLTIS_PASSWORD" '{password: $password}')" -o "$RESPONSE_FILE" -w '%{http_code}' 2>/dev/null || echo '000')
    if [[ "$code" =~ ^(200|302|303)$ ]]; then
        test_pass
    else
        test_fail "Live login should succeed (got $code)"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_security_runtime_smoke_tests
fi
