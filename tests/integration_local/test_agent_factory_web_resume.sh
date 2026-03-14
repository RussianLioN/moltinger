#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

WEB_ADAPTER_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-web-adapter.py"
SESSION_NEW_FIXTURE="$PROJECT_ROOT/tests/fixtures/agent-factory/web-demo/session-new.json"
REVIEW_FIXTURE="$PROJECT_ROOT/tests/fixtures/agent-factory/web-demo/session-awaiting-confirmation.json"

run_integration_local_agent_factory_web_resume_tests() {
    start_timer
    require_commands_or_skip python3 jq || {
        test_start "integration_local_agent_factory_web_resume_prereqs"
        test_skip "python3 and jq are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    test_start "integration_local_agent_factory_web_resume_restores_saved_discovery_session"
    if python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$SESSION_NEW_FIXTURE" --state-root "$tmpdir/state" --output "$tmpdir/start-out.json" >/dev/null &&
        jq 'del(.discovery_runtime_state)
          | .web_conversation_envelope = {
              "web_conversation_envelope_id": "web-envelope-resume-001",
              "request_id": "web-request-resume-001",
              "transport_mode": "synthetic_fixture",
              "ui_action": "request_status",
              "user_text": ""
            }' "$tmpdir/start-out.json" >"$tmpdir/resume-source.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/resume-source.json" --state-root "$tmpdir/state" --output "$tmpdir/resume-out.json" >/dev/null; then
        assert_eq "awaiting_user_reply" "$(jq -r '.status' "$tmpdir/resume-out.json")" "Resume status request should keep the discovery loop active"
        assert_eq "true" "$(jq -r '.resume_context.resume_available' "$tmpdir/resume-out.json")" "Resume context should declare the browser session resumable"
        assert_eq "true" "$(jq -r '.resume_context.resumed_from_saved_session' "$tmpdir/resume-out.json")" "Resume context should acknowledge that the adapter restored saved state"
        assert_contains "$(jq -r '.resume_context.summary_text' "$tmpdir/resume-out.json")" "Возобновляю browser-сессию" "Resume summary should be browser-readable"
        assert_eq "$(jq -r '.browser_project_pointer.project_key' "$tmpdir/start-out.json")" "$(jq -r '.resume_context.active_project_key' "$tmpdir/resume-out.json")" "Resume context should point to the same active project"
        assert_eq "$(jq -r '.next_question' "$tmpdir/start-out.json")" "$(jq -r '.resume_context.pending_question' "$tmpdir/resume-out.json")" "Resume context should keep the pending discovery question"
        assert_file_exists "$tmpdir/state/pointers/web-demo-session-invoice-approval.json" "Active browser pointer should be persisted under the web-demo state root"
        assert_file_exists "$tmpdir/state/resume/web-demo-session-invoice-approval.json" "Resume context should be persisted under the web-demo state root"
        test_pass
    else
        test_fail "Browser status request should restore the saved discovery session and persist resume metadata"
    fi

    test_start "integration_local_agent_factory_web_resume_reopens_confirmed_brief_without_losing_history"
    if python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$REVIEW_FIXTURE" --state-root "$tmpdir/reopen-state" --output "$tmpdir/review-out.json" >/dev/null &&
        jq '.web_conversation_envelope = {
              "web_conversation_envelope_id": "web-envelope-resume-010",
              "request_id": "web-request-resume-010",
              "transport_mode": "synthetic_fixture",
              "ui_action": "confirm_brief",
              "user_text": ""
            } | del(.demo_access_grant)' "$tmpdir/review-out.json" >"$tmpdir/confirm-source.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/confirm-source.json" --state-root "$tmpdir/reopen-state" --output "$tmpdir/confirmed-out.json" >/dev/null &&
        jq '.web_conversation_envelope = {
              "web_conversation_envelope_id": "web-envelope-resume-011",
              "request_id": "web-request-resume-011",
              "transport_mode": "synthetic_fixture",
              "ui_action": "request_status",
              "user_text": ""
            } | del(.demo_access_grant)' "$tmpdir/confirmed-out.json" >"$tmpdir/downloads-source.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/downloads-source.json" --state-root "$tmpdir/reopen-state" --output "$tmpdir/downloads-out.json" >/dev/null &&
        jq '.web_conversation_envelope = {
              "web_conversation_envelope_id": "web-envelope-resume-012",
              "request_id": "web-request-resume-012",
              "transport_mode": "synthetic_fixture",
              "ui_action": "reopen_brief",
              "user_text": "Нужно уточнить правила для срочных платежей CFO."
            } | .brief_section_updates = {
              "open_risks": [
                "Нужно отдельно согласовать handoff для сценария срочных платежей CFO"
              ]
            } | del(.demo_access_grant)' "$tmpdir/downloads-out.json" >"$tmpdir/reopen-source.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/reopen-source.json" --state-root "$tmpdir/reopen-state" --output "$tmpdir/reopen-out.json" >/dev/null; then
        assert_eq "reopened" "$(jq -r '.status' "$tmpdir/reopen-out.json")" "Reopen action should return the browser flow to a reopened brief state"
        assert_eq "awaiting_confirmation" "$(jq -r '.status_snapshot.user_visible_status' "$tmpdir/reopen-out.json")" "Browser-safe status should keep the reopened brief inside confirmation UX"
        assert_eq "Brief переоткрыт" "$(jq -r '.status_snapshot.brief_status_label' "$tmpdir/reopen-out.json")" "Status snapshot should expose a reopened-brief label"
        assert_contains "$(jq -r '.resume_context.summary_text' "$tmpdir/reopen-out.json")" "переоткрыт" "Resume summary should explain that the brief was reopened"
        assert_eq "1.0" "$(jq -r '.resume_context.latest_confirmed_brief_version' "$tmpdir/reopen-out.json")" "Resume context should preserve the last confirmed brief version"
        assert_eq "1" "$(jq -r '.resume_context.confirmation_history_count' "$tmpdir/reopen-out.json")" "Resume context should keep confirmation history count after reopen"
        assert_eq "1" "$(jq -r '.resume_context.handoff_history_count' "$tmpdir/reopen-out.json")" "Resume context should keep handoff history count after reopen"
        assert_eq "false" "$(jq -r '.resume_context.linked_brief_version == .resume_context.latest_confirmed_brief_version' "$tmpdir/reopen-out.json")" "Reopened browser brief should move to a new version while preserving the previous confirmed one"
        assert_contains "$(jq -r '[.reply_cards[] | select(.card_kind == "brief_summary_section")][0].body_text' "$tmpdir/reopen-out.json")" "Переоткрыта версия" "Browser summary should clearly mark the reopened brief version"
        test_pass
    else
        test_fail "Browser reopen flow should preserve confirmation/handoff history while issuing a new reviewable version"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_integration_local_agent_factory_web_resume_tests
fi
