#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"
source "$SCRIPT_DIR/../lib/http.sh"

LIVE_WEB_DEMO_URL="${LIVE_WEB_DEMO_URL:-${ASC_DEMO_URL:-}}"
LIVE_MOLTIS_URL="${LIVE_MOLTIS_URL:-${MOLTIS_URL:-}}"
TEST_TIMEOUT="${TEST_TIMEOUT:-10}"

normalize_base_url() {
    local value="$1"
    printf '%s' "${value%/}" | tr '[:upper:]' '[:lower:]'
}

run_web_factory_demo_smoke_tests() {
    start_timer

    if ! is_live_mode; then
        test_start "web_factory_demo_requires_live_mode"
        test_skip "Suite requires --live"
        generate_report
        return
    fi

    require_commands_or_skip curl jq || {
        test_start "web_factory_demo_smoke_prereqs"
        test_skip "Dependencies unavailable"
        generate_report
        return
    }

    test_start "web_factory_demo_target_configured"
    if [[ -z "$LIVE_WEB_DEMO_URL" ]]; then
        test_skip "Set LIVE_WEB_DEMO_URL or ASC_DEMO_URL for web demo smoke"
        generate_report
        return
    fi
    test_pass

    test_start "web_factory_demo_urls_are_distinct"
    if [[ -z "$LIVE_MOLTIS_URL" ]]; then
        test_skip "Set LIVE_MOLTIS_URL or MOLTIS_URL for runtime-isolation check"
    else
        local web_demo_url moltis_url
        web_demo_url="$(normalize_base_url "$LIVE_WEB_DEMO_URL")"
        moltis_url="$(normalize_base_url "$LIVE_MOLTIS_URL")"
        if [[ "$web_demo_url" != "$moltis_url" ]]; then
            test_pass
        else
            test_fail "ASC demo and Moltis live URLs must remain distinct"
        fi
    fi

    test_start "web_factory_demo_health_endpoint"
    local health_code
    health_code="$(health_status_code "$LIVE_WEB_DEMO_URL" "$TEST_TIMEOUT")"
    if [[ "$health_code" == "200" ]]; then
        test_pass
    else
        test_fail "Web demo health endpoint should return 200 (got $health_code)"
    fi

    test_start "web_factory_demo_operator_health_projection"
    local operator_health_file
    operator_health_file="$(mktemp)"
    if curl_with_test_client_ip -fsS --max-time "$TEST_TIMEOUT" "${LIVE_WEB_DEMO_URL%/}/api/health" -o "$operator_health_file"; then
        assert_eq "agent-factory-web-adapter" "$(jq -r '.service' "$operator_health_file")" "Operator health endpoint should identify the web adapter service"
        assert_eq "shared_token_hash" "$(jq -r '.access_gate_mode' "$operator_health_file")" "Operator health endpoint should expose the configured shared-token access gate"
        assert_contains "$(jq -r '.operator_status.public_base_url' "$operator_health_file")" "asc." "Operator health endpoint should expose the public demo base URL"
        test_pass
    else
        test_fail "Operator health endpoint should be reachable on the live web demo"
    fi
    rm -f "$operator_health_file"

    test_start "web_factory_demo_root_shell"
    local shell_file
    shell_file="$(mktemp)"
    if curl_with_test_client_ip -fsS --max-time "$TEST_TIMEOUT" "${LIVE_WEB_DEMO_URL%/}/" -o "$shell_file"; then
        assert_contains "$(cat "$shell_file")" "ASC AI Fabrique Demo" "Live web demo root should render the browser shell"
        assert_contains "$(cat "$shell_file")" "Фабричный агент-бизнес-аналитик" "Live web demo root should expose the business-facing shell content"
        test_pass
    else
        test_fail "Live web demo root should serve the browser shell"
    fi
    rm -f "$shell_file"

    test_start "web_factory_demo_gate_prompt_without_token"
    local gate_response_file
    gate_response_file="$(mktemp)"
    if curl_with_test_client_ip -fsS --max-time "$TEST_TIMEOUT" \
        -X POST "${LIVE_WEB_DEMO_URL%/}/api/turn" \
        -H 'Content-Type: application/json' \
        -d '{"web_conversation_envelope":{"request_id":"live-web-demo-smoke","ui_action":"start_project","user_text":"Проверка controlled demo access"}}' \
        -o "$gate_response_file"; then
        assert_eq "gate_pending" "$(jq -r '.status' "$gate_response_file")" "Live web demo should fail closed when no access token is provided"
        assert_eq "request_demo_access" "$(jq -r '.next_action' "$gate_response_file")" "Live web demo should ask for a demo token when access is missing"
        test_pass
    else
        test_fail "Live web demo should return a controlled gate prompt when access token is absent"
    fi
    rm -f "$gate_response_file"

    test_start "web_factory_demo_metrics_endpoint"
    local metrics_code
    metrics_code="$(curl_with_test_client_ip -s -o /dev/null -w '%{http_code}' --max-time "$TEST_TIMEOUT" "${LIVE_WEB_DEMO_URL%/}/metrics" 2>/dev/null || echo "000")"
    if [[ "$metrics_code" == "200" ]]; then
        test_pass
    else
        test_fail "Web demo metrics endpoint should return 200 (got $metrics_code)"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_web_factory_demo_smoke_tests
fi
