#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

WEB_ADAPTER_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-web-adapter.py"
SESSION_NEW_FIXTURE="$PROJECT_ROOT/tests/fixtures/agent-factory/web-demo/session-new.json"

run_component_agent_factory_web_access_tests() {
    start_timer
    require_commands_or_skip python3 jq || {
        test_start "component_agent_factory_web_access_prereqs"
        test_skip "python3 and jq are required"
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

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_agent_factory_web_access_tests
fi
