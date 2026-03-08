#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

ALLOW_DESTRUCTIVE_TESTS="${ALLOW_DESTRUCTIVE_TESTS:-0}"
TARGET_MOLTIS_CONTAINER="${TARGET_MOLTIS_CONTAINER:-}"
LIVE_MOLTIS_URL="${LIVE_MOLTIS_URL:-${MOLTIS_URL:-}}"
TEST_TIMEOUT="${TEST_TIMEOUT:-15}"

run_resilience_deployment_recovery_tests() {
    start_timer

    if ! is_live_mode; then
        test_start "resilience_deploy_requires_live_mode"
        test_skip "Suite requires --live"
        generate_report
        return
    fi

    require_commands_or_skip docker curl || {
        test_start "resilience_deploy_setup"
        test_skip "Dependencies unavailable"
        generate_report
        return
    }

    test_start "resilience_deploy_opt_in_required"
    if [[ "$ALLOW_DESTRUCTIVE_TESTS" != "1" ]]; then
        test_skip "Set ALLOW_DESTRUCTIVE_TESTS=1 to run deployment recovery checks"
        generate_report
        return
    fi
    test_pass

    test_start "resilience_deploy_container_target_configured"
    if [[ -z "$TARGET_MOLTIS_CONTAINER" ]]; then
        test_skip "Set TARGET_MOLTIS_CONTAINER for deployment recovery checks"
        generate_report
        return
    fi
    test_pass

    test_start "resilience_deploy_container_exists"
    if docker inspect "$TARGET_MOLTIS_CONTAINER" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Target container $TARGET_MOLTIS_CONTAINER does not exist"
    fi

    test_start "resilience_deploy_health_endpoint"
    if [[ -z "$LIVE_MOLTIS_URL" ]]; then
        test_skip "Set LIVE_MOLTIS_URL or MOLTIS_URL for deployment health verification"
    else
        local code
        code=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$TEST_TIMEOUT" "${LIVE_MOLTIS_URL}/health" 2>/dev/null || echo '000')
        if [[ "$code" == "200" ]]; then
            test_pass
        else
            test_fail "Deployment health endpoint should return 200 (got $code)"
        fi
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_resilience_deployment_recovery_tests
fi
