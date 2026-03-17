#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

WEB_ADAPTER_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-web-adapter.py"
SESSION_NEW_FIXTURE="$PROJECT_ROOT/tests/fixtures/agent-factory/web-demo/session-new.json"

run_integration_local_agent_factory_web_flow_tests() {
    start_timer
    require_commands_or_skip python3 jq || {
        test_start "integration_local_agent_factory_web_flow_prereqs"
        test_skip "python3 and jq are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    test_start "integration_local_agent_factory_web_flow_starts_browser_discovery_from_raw_idea"
    if python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$SESSION_NEW_FIXTURE" --state-root "$tmpdir/state" --output "$tmpdir/start-out.json" >/dev/null; then
        assert_eq "awaiting_user_reply" "$(jq -r '.status' "$tmpdir/start-out.json")" "New browser project should immediately enter guided discovery"
        assert_eq "ask_next_question" "$(jq -r '.next_action' "$tmpdir/start-out.json")" "First browser turn should route into the next useful discovery question"
        assert_eq "target_users" "$(jq -r '.next_topic' "$tmpdir/start-out.json")" "The first uncovered topic after the raw idea should be target users"
        assert_contains "$(jq -r '.next_question' "$tmpdir/start-out.json")" "Кто" "Browser reply should keep the business-readable discovery question"
        assert_eq "web" "$(jq -r '.web_conversation_envelope.normalized_payload.request_channel' "$tmpdir/start-out.json")" "Normalized browser payload should keep the web request channel"
        assert_eq "discovery_in_progress" "$(jq -r '.status_snapshot.user_visible_status' "$tmpdir/start-out.json")" "User-visible status should remain safe and browser-friendly"
        assert_file_exists "$tmpdir/state/sessions/web-demo-session-invoice-approval.json" "Browser turn should persist the session snapshot under the web-demo state root"
        if compgen -G "$tmpdir/state/history/web-demo-session-invoice-approval-*.json" >/dev/null; then
            test_pass
        else
            test_fail "Browser turn should persist at least one audit/history snapshot"
        fi
    else
        test_fail "Browser adapter should start discovery directly from the session-new fixture"
    fi

    test_start "integration_local_agent_factory_web_flow_reprompts_on_low_signal_start_idea"
    if jq '.web_conversation_envelope.user_text = "test"' "$SESSION_NEW_FIXTURE" >"$tmpdir/start-low-signal.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/start-low-signal.json" --state-root "$tmpdir/state-low-signal" --output "$tmpdir/start-low-signal-out.json" >/dev/null; then
        assert_eq "awaiting_user_reply" "$(jq -r '.status' "$tmpdir/start-low-signal-out.json")" "Low-signal start should keep discovery waiting for a valid idea"
        assert_eq "problem" "$(jq -r '.next_topic' "$tmpdir/start-low-signal-out.json")" "Low-signal start should keep focus on business problem topic"
        assert_contains "$(jq -r '.next_question' "$tmpdir/start-low-signal-out.json")" "слишком общий" "Low-signal start should trigger an explicit reprompt"
        assert_eq "" "$(jq -r '.discovery_runtime_state.requirement_topics[] | select(.topic_name == "problem") | .summary' "$tmpdir/start-low-signal-out.json")" "Low-signal start must not be accepted as problem statement"
        assert_eq "low_signal_guard" "$(jq -r '.ui_projection.question_source' "$tmpdir/start-low-signal-out.json")" "UI projection should expose low-signal guard mode for start turn"
        test_pass
    else
        test_fail "Browser adapter should reject low-signal start messages as automation subject"
    fi

    test_start "integration_local_agent_factory_web_flow_advances_after_submit_turn"
    if jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-claims-routing-002",
          "request_id": "web-request-claims-routing-002",
          "transport_mode": "synthetic_fixture",
          "ui_action": "submit_turn",
          "user_text": "Оператор первой линии и руководитель смены."
        } | del(.demo_access_grant)' "$tmpdir/start-out.json" >"$tmpdir/turn-two.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/turn-two.json" --state-root "$tmpdir/state" --output "$tmpdir/turn-two-out.json" >/dev/null; then
        assert_eq "awaiting_user_reply" "$(jq -r '.status' "$tmpdir/turn-two-out.json")" "Second browser turn should keep the conversational loop active"
        assert_eq "current_workflow" "$(jq -r '.next_topic' "$tmpdir/turn-two-out.json")" "After target users are answered the flow should move to current workflow"
        assert_contains "$(jq -r '.next_question' "$tmpdir/turn-two-out.json")" "Как этот процесс работает" "The next browser question should advance to the current workflow topic"
        assert_eq "Оператор первой линии и руководитель смены." "$(jq -r '.discovery_runtime_state.requirement_topics[] | select(.topic_name == "target_users") | .summary' "$tmpdir/turn-two-out.json")" "Browser turn should persist the answer into the canonical discovery topics"
        assert_eq "current_workflow" "$(jq -r '.web_conversation_envelope.normalized_payload.current_topic' "$tmpdir/turn-two-out.json")" "Normalized browser payload should point to the next pending discovery topic"
        test_pass
    else
        test_fail "Browser adapter should resume the saved session and advance discovery after a follow-up answer"
    fi

    test_start "integration_local_agent_factory_web_flow_keeps_topic_on_low_signal_reply"
    if jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-claims-routing-004",
          "request_id": "web-request-claims-routing-004",
          "transport_mode": "synthetic_fixture",
          "ui_action": "submit_turn",
          "user_text": "ping"
        } | del(.demo_access_grant)' "$tmpdir/start-out.json" >"$tmpdir/turn-low-signal.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/turn-low-signal.json" --state-root "$tmpdir/state" --output "$tmpdir/turn-low-signal-out.json" >/dev/null; then
        assert_eq "awaiting_user_reply" "$(jq -r '.status' "$tmpdir/turn-low-signal-out.json")" "Low-signal browser reply should keep the dialog active"
        assert_eq "target_users" "$(jq -r '.next_topic' "$tmpdir/turn-low-signal-out.json")" "Low-signal reply should not advance discovery to the next topic"
        assert_contains "$(jq -r '.next_question' "$tmpdir/turn-low-signal-out.json")" "слишком общий" "Low-signal reply should trigger an architect reprompt"
        assert_eq "" "$(jq -r '.discovery_runtime_state.requirement_topics[] | select(.topic_name == "target_users") | .summary' "$tmpdir/turn-low-signal-out.json")" "Low-signal reply must not overwrite canonical topic summary"
        assert_eq "low_signal_guard" "$(jq -r '.ui_projection.question_source' "$tmpdir/turn-low-signal-out.json")" "UI projection should expose low-signal guard mode"
        test_pass
    else
        test_fail "Browser adapter should keep the same discovery topic when the user sends low-signal input"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_integration_local_agent_factory_web_flow_tests
fi
