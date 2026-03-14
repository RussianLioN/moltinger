#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

DISCOVERY_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-discovery.py"
SESSION_FIXTURE="$PROJECT_ROOT/tests/fixtures/agent-factory/discovery/session-new.json"
CLARIFICATION_FIXTURE="$PROJECT_ROOT/tests/fixtures/agent-factory/discovery/session-awaiting-clarification.json"
CONFIRMED_FIXTURE="$PROJECT_ROOT/tests/fixtures/agent-factory/discovery/brief-confirmed-handoff.json"

run_integration_local_agent_factory_resume_tests() {
    start_timer
    require_commands_or_skip python3 jq || {
        test_start "integration_local_agent_factory_resume_prereqs"
        test_skip "python3 and jq are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    test_start "integration_local_agent_factory_resume_preserves_pending_question"
    if python3 "$DISCOVERY_SCRIPT" run --source "$SESSION_FIXTURE" --output "$tmpdir/resumed-session.json" >/dev/null; then
        assert_eq "awaiting_user_reply" "$(jq -r '.status' "$tmpdir/resumed-session.json")" "Interrupted discovery should resume in user-reply mode"
        assert_eq "target_users" "$(jq -r '.next_topic' "$tmpdir/resumed-session.json")" "The next topic should stay on the original pending question"
        assert_eq "2" "$(jq -r '.conversation_turns | length' "$tmpdir/resumed-session.json")" "Resume should not duplicate the pending agent question"
        assert_eq "in_progress" "$(jq -r '.resume_context.resumed_from_status' "$tmpdir/resumed-session.json")" "Resume context should keep the previous session status"
        assert_eq "awaiting_user_reply" "$(jq -r '.resume_context.restored_status' "$tmpdir/resumed-session.json")" "Resume context should show the restored interaction state"
        assert_contains "$(jq -r '.resume_context.summary_text' "$tmpdir/resumed-session.json")" "Возобновляю discovery-сессию" "Resume context should explain that the session was restored"
        test_pass
    else
        test_fail "Interrupted discovery should resume without losing the pending agent question"
    fi

    test_start "integration_local_agent_factory_resume_restores_open_clarification_context"
    if python3 "$DISCOVERY_SCRIPT" run --source "$CLARIFICATION_FIXTURE" --output "$tmpdir/resumed-clarification.json" >/dev/null; then
        assert_eq "awaiting_clarification" "$(jq -r '.status' "$tmpdir/resumed-clarification.json")" "Interrupted clarification should resume in clarification state"
        assert_eq "awaiting_clarification" "$(jq -r '.resume_context.resumed_from_status' "$tmpdir/resumed-clarification.json")" "Resume context should preserve the prior clarification status"
        assert_eq "input_examples" "$(jq -r '.resume_context.current_topic' "$tmpdir/resumed-clarification.json")" "Resume context should point to the blocked clarification topic"
        assert_contains "$(jq -r '.resume_context.open_clarification_ids[0]' "$tmpdir/resumed-clarification.json")" "clarification-unsafe-" "Resume context should expose the active clarification id"
        assert_contains "$(jq -r '.next_question' "$tmpdir/resumed-clarification.json")" "без реальных реквизитов" "Interrupted clarification should restore the exact safe-example request"
        test_pass
    else
        test_fail "Interrupted clarification should resume with the blocking clarification intact"
    fi

    test_start "integration_local_agent_factory_resume_reopens_confirmed_brief_with_history"
    if jq '. + {
      "brief_feedback_text": "Добавь, что срочные платежи CFO идут по отдельному сценарию и требуют нового согласования.",
      "brief_section_updates": {
        "exceptions": [
          "Срочные платежи CFO идут по отдельному сценарию и требуют нового согласования"
        ],
        "open_risks": [
          "Нужно отдельно описать сценарий срочных платежей CFO"
        ]
      }
    }' "$CONFIRMED_FIXTURE" >"$tmpdir/reopen-source.json" &&
        python3 "$DISCOVERY_SCRIPT" run --source "$tmpdir/reopen-source.json" --output "$tmpdir/reopened-brief.json" >/dev/null &&
        python3 "$DISCOVERY_SCRIPT" run --source "$tmpdir/reopened-brief.json" --output "$tmpdir/resumed-reopened.json" >/dev/null &&
        jq '. + {
          "confirmation_reply": {
            "confirmed": true,
            "confirmation_text": "Да, обновленная версия brief подтверждена.",
            "confirmed_by": "demo-business-user"
          }
        }' "$tmpdir/reopened-brief.json" >"$tmpdir/reconfirm-source.json" &&
        python3 "$DISCOVERY_SCRIPT" run --source "$tmpdir/reconfirm-source.json" --output "$tmpdir/reconfirmed-brief.json" >/dev/null &&
        python3 "$DISCOVERY_SCRIPT" run --source "$tmpdir/reconfirmed-brief.json" --output "$tmpdir/reconfirmed-handoff.json" >/dev/null; then
        assert_eq "reopened" "$(jq -r '.status' "$tmpdir/reopened-brief.json")" "Confirmed brief should move into reopened state after a meaningful correction"
        assert_eq "reopened" "$(jq -r '.requirement_brief.status' "$tmpdir/reopened-brief.json")" "The active brief should explicitly show reopened status"
        assert_eq "1.2" "$(jq -r '.requirement_brief.version' "$tmpdir/reopened-brief.json")" "Reopen should create a new brief version instead of overwriting the confirmed one"
        assert_eq "1" "$(jq -r '.confirmation_history | length' "$tmpdir/reopened-brief.json")" "Reopen should archive the previous confirmation snapshot"
        assert_eq "superseded" "$(jq -r '.confirmation_history[0].status' "$tmpdir/reopened-brief.json")" "Archived confirmation snapshot should be marked superseded"
        assert_eq "1.1" "$(jq -r '.confirmation_history[0].brief_snapshot.version' "$tmpdir/reopened-brief.json")" "Archived confirmation history should keep the original confirmed brief snapshot"
        assert_eq "1.2" "$(jq -r '.confirmation_history[0].superseded_by_brief_version' "$tmpdir/reopened-brief.json")" "Archived confirmation history should point to the new brief version"
        assert_eq "1" "$(jq -r '.handoff_history | length' "$tmpdir/reopened-brief.json")" "Reopen should archive the previous handoff record"
        assert_eq "superseded" "$(jq -r '.handoff_history[0].handoff_status' "$tmpdir/reopened-brief.json")" "Archived handoff should be marked superseded"
        assert_eq "false" "$(jq -r 'if has("factory_handoff_record") then "true" else "false" end' "$tmpdir/reopened-brief.json")" "Reopened brief should not expose an active downstream handoff"
        assert_eq "reopened" "$(jq -r '.resume_context.restored_status' "$tmpdir/resumed-reopened.json")" "Resuming a reopened brief should keep the reopened state"
        assert_eq "request_explicit_confirmation" "$(jq -r '.next_action' "$tmpdir/resumed-reopened.json")" "Reopened brief should still require explicit confirmation after resume"
        assert_eq "1.1" "$(jq -r '.resume_context.latest_confirmed_brief_version' "$tmpdir/resumed-reopened.json")" "Resume context should preserve the last confirmed brief version"
        assert_eq "confirmed" "$(jq -r '.status' "$tmpdir/reconfirmed-brief.json")" "The reopened brief should be confirmable in a later step"
        assert_eq "confirmation-snapshot-002" "$(jq -r '.confirmation_snapshot.confirmation_snapshot_id' "$tmpdir/reconfirmed-brief.json")" "Reconfirmation should create a new confirmation snapshot id"
        assert_eq "1.2" "$(jq -r '.confirmation_snapshot.brief_version' "$tmpdir/reconfirmed-brief.json")" "The new confirmation snapshot should bind to the reopened brief version"
        assert_eq "ready" "$(jq -r '.factory_handoff_record.handoff_status' "$tmpdir/reconfirmed-handoff.json")" "Reconfirmed brief should publish a fresh ready handoff on replay"
        assert_eq "1.2" "$(jq -r '.factory_handoff_record.brief_version' "$tmpdir/reconfirmed-handoff.json")" "The new handoff should reference the reopened brief version"
        test_pass
    else
        test_fail "Reopened discovery should preserve confirmation and handoff history across resume and reconfirmation"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_integration_local_agent_factory_resume_tests
fi
