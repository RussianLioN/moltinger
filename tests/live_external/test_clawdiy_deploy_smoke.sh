#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

LIVE_CLAWDIY_URL="${LIVE_CLAWDIY_URL:-${CLAWDIY_URL:-}}"
LIVE_MOLTIS_URL="${LIVE_MOLTIS_URL:-${MOLTIS_URL:-}}"
TEST_TIMEOUT="${TEST_TIMEOUT:-10}"

metrics_status_code() {
    local base_url="$1"
    local timeout="${2:-5}"
    curl_with_test_client_ip -s -o /dev/null -w '%{http_code}' --max-time "$timeout" "${base_url%/}/metrics" 2>/dev/null || echo "000"
}

normalize_base_url() {
    local value="$1"
    printf '%s' "${value%/}" | tr '[:upper:]' '[:lower:]'
}

run_clawdiy_deploy_smoke_tests() {
    start_timer

    if ! is_live_mode; then
        test_start "clawdiy_deploy_requires_live_mode"
        test_skip "Suite requires --live"
        generate_report
        return
    fi

    require_commands_or_skip curl jq || {
        test_start "clawdiy_deploy_setup"
        test_skip "Dependencies unavailable"
        generate_report
        return
    }

    test_start "clawdiy_deploy_target_configured"
    if [[ -z "$LIVE_CLAWDIY_URL" ]]; then
        test_skip "Set LIVE_CLAWDIY_URL or CLAWDIY_URL for Clawdiy deploy smoke"
        generate_report
        return
    fi
    test_pass

    test_start "clawdiy_deploy_urls_are_distinct"
    if [[ -z "$LIVE_MOLTIS_URL" ]]; then
        test_skip "Set LIVE_MOLTIS_URL or MOLTIS_URL for runtime-isolation check"
    else
        local clawdiy_url moltis_url
        clawdiy_url="$(normalize_base_url "$LIVE_CLAWDIY_URL")"
        moltis_url="$(normalize_base_url "$LIVE_MOLTIS_URL")"
        if [[ "$clawdiy_url" != "$moltis_url" ]]; then
            test_pass
        else
            test_fail "Clawdiy and Moltis live URLs must remain distinct"
        fi
    fi

    test_start "clawdiy_deploy_health_endpoint"
    local clawdiy_health_code
    clawdiy_health_code="$(health_status_code "$LIVE_CLAWDIY_URL" "$TEST_TIMEOUT")"
    if [[ "$clawdiy_health_code" == "200" ]]; then
        test_pass
    else
        test_fail "Clawdiy health endpoint should return 200 (got $clawdiy_health_code)"
    fi

    test_start "clawdiy_deploy_metrics_endpoint"
    local clawdiy_metrics_code
    clawdiy_metrics_code="$(metrics_status_code "$LIVE_CLAWDIY_URL" "$TEST_TIMEOUT")"
    if [[ "$clawdiy_metrics_code" == "200" ]]; then
        test_pass
    else
        test_fail "Clawdiy metrics endpoint should return 200 (got $clawdiy_metrics_code)"
    fi

    test_start "clawdiy_deploy_moltis_health_unchanged"
    if [[ -z "$LIVE_MOLTIS_URL" ]]; then
        test_skip "Set LIVE_MOLTIS_URL or MOLTIS_URL for Moltis isolation check"
    else
        local moltis_health_code
        moltis_health_code="$(health_status_code "$LIVE_MOLTIS_URL" "$TEST_TIMEOUT")"
        if [[ "$moltis_health_code" == "200" ]]; then
            test_pass
        else
            test_fail "Moltis health endpoint should remain 200 during Clawdiy rollout (got $moltis_health_code)"
        fi
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_clawdiy_deploy_smoke_tests
fi
