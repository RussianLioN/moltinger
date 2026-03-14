#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

WEB_ADAPTER_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-web-adapter.py"
SESSION_NEW_FIXTURE="$PROJECT_ROOT/tests/fixtures/agent-factory/web-demo/session-new.json"

run_component_agent_factory_web_access_tests() {
    start_timer
    require_commands_or_skip python3 jq curl || {
        test_start "component_agent_factory_web_access_prereqs"
        test_skip "python3, jq and curl are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    test_start "component_agent_factory_web_access_blocks_without_active_access_grant"
    if jq 'del(.demo_access_grant)' "$SESSION_NEW_FIXTURE" >"$tmpdir/no-access.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/no-access.json" --state-root "$tmpdir/state" --output "$tmpdir/no-access-out.json" >/dev/null; then
        assert_eq "gate_pending" "$(jq -r '.status' "$tmpdir/no-access-out.json")" "Adapter should fail closed when no access grant is present"
        assert_eq "request_demo_access" "$(jq -r '.next_action' "$tmpdir/no-access-out.json")" "Access gate should request a demo token"
        assert_eq "gate_pending" "$(jq -r '.web_demo_session.status' "$tmpdir/no-access-out.json")" "Session should remain gate-pending until access is granted"
        assert_eq "needs_attention" "$(jq -r '.status_snapshot.user_visible_status' "$tmpdir/no-access-out.json")" "User-visible status should stay safe when access is blocked"
        assert_eq "status_update,error_message" "$(jq -r '[.reply_cards[].card_kind] | join(",")' "$tmpdir/no-access-out.json")" "Blocked response should render a status card and one controlled error card"
        if [[ -f "$tmpdir/state/sessions/web-demo-session-claims-routing.json" ]]; then
            test_fail "Blocked access should not persist an active browser session"
        else
            test_pass
        fi
    else
        test_fail "Adapter should return a controlled blocked response without an access grant"
    fi

    test_start "component_agent_factory_web_access_rejects_mismatched_configured_token"
    if ASC_DEMO_ACCESS_MODE=shared_token_hash \
        ASC_DEMO_SHARED_TOKEN_HASH="0000000000000000000000000000000000000000000000000000000000000000" \
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$SESSION_NEW_FIXTURE" --state-root "$tmpdir/state" --output "$tmpdir/mismatch-out.json" >/dev/null; then
        assert_eq "gate_pending" "$(jq -r '.status' "$tmpdir/mismatch-out.json")" "Configured shared-token mode should block mismatched demo access grants"
        assert_eq "shared_token_hash" "$(jq -r '.access_gate.mode' "$tmpdir/mismatch-out.json")" "Access gate should report the configured shared-token validation mode"
        assert_eq "true" "$(jq -r '.access_gate.configured' "$tmpdir/mismatch-out.json")" "Configured shared-token mode should report a ready access policy"
        assert_contains "$(jq -r '.access_gate.reason' "$tmpdir/mismatch-out.json")" "не подходит" "Blocked response should explain that the provided token is not valid for the demo"
        test_pass
    else
        test_fail "Configured shared-token mode should fail closed on a mismatched grant"
    fi

    test_start "component_agent_factory_web_access_restores_saved_session_for_status_request"
    if python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$SESSION_NEW_FIXTURE" --state-root "$tmpdir/state" --output "$tmpdir/start-out.json" >/dev/null &&
        jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-claims-routing-003",
          "request_id": "web-request-claims-routing-003",
          "transport_mode": "synthetic_fixture",
          "ui_action": "request_status",
          "user_text": ""
        } | del(.demo_access_grant)' "$tmpdir/start-out.json" >"$tmpdir/status-request.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/status-request.json" --state-root "$tmpdir/state" --output "$tmpdir/status-out.json" >/dev/null; then
        assert_file_exists "$tmpdir/state/sessions/web-demo-session-invoice-approval.json" "Successful browser turn should persist the active web-demo session"
        assert_eq "awaiting_user_reply" "$(jq -r '.status' "$tmpdir/status-out.json")" "Restored session should keep the prior runtime status"
        assert_eq "awaiting_user_reply" "$(jq -r '.web_demo_session.status' "$tmpdir/status-out.json")" "Restored session should stay ready for the next business answer"
        assert_eq "invoice-approval-web-demo" "$(jq -r '.browser_project_pointer.project_key' "$tmpdir/status-out.json")" "Status request should restore the same active project pointer"
        assert_eq "target_users" "$(jq -r '.web_conversation_envelope.normalized_payload.current_topic' "$tmpdir/status-out.json")" "Restored status should point to the pending discovery topic"
        assert_eq "discovery_in_progress" "$(jq -r '.status_snapshot.user_visible_status' "$tmpdir/status-out.json")" "Status request should keep a safe user-facing discovery state"
        test_pass
    else
        test_fail "Adapter should restore the saved browser session for a follow-up status request"
    fi

    test_start "component_agent_factory_web_access_projects_operator_safe_health_status"
    local server_pid=""
    local health_ready="false"
    local fixture_hash
    fixture_hash="$(python3 -c 'import hashlib, sys; print(hashlib.sha256(sys.argv[1].encode()).hexdigest())' "$(jq -r '.demo_access_grant.grant_value' "$SESSION_NEW_FIXTURE")")"
    if ASC_DEMO_ACCESS_MODE="shared_token_hash" \
        ASC_DEMO_SHARED_TOKEN_HASH="$fixture_hash" \
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$SESSION_NEW_FIXTURE" --state-root "$tmpdir/health-state" --output "$tmpdir/health-state-out.json" >/dev/null; then
        ASC_DEMO_DOMAIN="asc.ainetic.tech" \
            ASC_DEMO_PUBLIC_BASE_URL="https://asc.ainetic.tech" \
            ASC_DEMO_ACCESS_MODE="shared_token_hash" \
            ASC_DEMO_SHARED_TOKEN_HASH="$fixture_hash" \
            python3 "$WEB_ADAPTER_SCRIPT" serve --host 127.0.0.1 --port 18796 --state-root "$tmpdir/health-state" --assets-root "$PROJECT_ROOT/web/agent-factory-demo" >/dev/null 2>"$tmpdir/health-server.log" &
    else
        test_fail "Configured shared-token mode should create one persisted browser session for operator health checks"
    fi
    server_pid=$!
    if [[ -n "$server_pid" ]]; then
        for _ in $(seq 1 40); do
            if curl -fsS "http://127.0.0.1:18796/api/health" >/dev/null 2>&1; then
                health_ready="true"
                break
            fi
            sleep 0.25
        done
        if [[ "$health_ready" == "true" ]] &&
            curl -fsS "http://127.0.0.1:18796/api/health" -o "$tmpdir/health.json" &&
            curl -fsS "http://127.0.0.1:18796/metrics" -o "$tmpdir/metrics.txt"; then
            assert_eq "ok" "$(jq -r '.status' "$tmpdir/health.json")" "Health endpoint should stay reachable for operator checks"
            assert_eq "agent-factory-web-adapter" "$(jq -r '.service' "$tmpdir/health.json")" "Health endpoint should identify the published adapter service"
            assert_eq "shared_token_hash" "$(jq -r '.access_gate_mode' "$tmpdir/health.json")" "Health endpoint should expose the configured access-gate mode"
            assert_eq "true" "$(jq -r '.access_gate_configured' "$tmpdir/health.json")" "Health endpoint should report when the shared token policy is configured"
            assert_eq "ready" "$(jq -r '.operator_status.publication_status' "$tmpdir/health.json")" "Configured demo surface should publish a ready operator status"
            assert_eq "https://asc.ainetic.tech" "$(jq -r '.public_base_url' "$tmpdir/health.json")" "Health endpoint should echo the public demo base URL"
            assert_eq "1" "$(jq -r '.operator_status.active_session_count' "$tmpdir/health.json")" "Health endpoint should count persisted browser sessions"
            assert_eq "1" "$(jq -r '.operator_status.awaiting_user_reply_count' "$tmpdir/health.json")" "Health endpoint should project the pending browser reply state"
            assert_contains "$(cat "$tmpdir/metrics.txt")" "agent_factory_web_demo_publication_ready 1" "Metrics endpoint should expose publication readiness"
            assert_contains "$(cat "$tmpdir/metrics.txt")" "agent_factory_web_demo_access_gate_ready 1" "Metrics endpoint should expose access-gate readiness"
            assert_contains "$(cat "$tmpdir/metrics.txt")" "agent_factory_web_demo_awaiting_user_reply_sessions 1" "Metrics endpoint should expose session-state gauges"
            test_pass
        else
            test_fail "Operator-safe health and metrics endpoints should be reachable for the web demo"
        fi
    else
        test_fail "Adapter server should start with a configured health publication surface"
    fi
    if [[ -n "$server_pid" ]]; then
        kill "$server_pid" >/dev/null 2>&1 || true
        wait "$server_pid" 2>/dev/null || true
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_agent_factory_web_access_tests
fi
