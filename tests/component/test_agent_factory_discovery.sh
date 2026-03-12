#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

DISCOVERY_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-discovery.py"
SESSION_NEW_FIXTURE="$PROJECT_ROOT/tests/fixtures/agent-factory/discovery/session-new.json"
SESSION_CLARIFICATION_FIXTURE="$PROJECT_ROOT/tests/fixtures/agent-factory/discovery/session-awaiting-clarification.json"

run_component_agent_factory_discovery_tests() {
    start_timer
    require_commands_or_skip python3 jq || {
        test_start "component_agent_factory_discovery_prereqs"
        test_skip "python3 and jq are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    test_start "component_agent_factory_discovery_calculates_topic_progress_for_new_session"
    if python3 "$DISCOVERY_SCRIPT" run --source "$SESSION_NEW_FIXTURE" --output "$tmpdir/session-new.json" >/dev/null; then
        assert_eq "awaiting_user_reply" "$(jq -r '.status' "$tmpdir/session-new.json")" "New discovery session should wait for the next user reply"
        assert_eq "ask_next_question" "$(jq -r '.next_action' "$tmpdir/session-new.json")" "New discovery session should ask the next useful question"
        assert_eq "target_users" "$(jq -r '.next_topic' "$tmpdir/session-new.json")" "Target users should be the first uncovered topic after the raw idea"
        assert_contains "$(jq -r '.next_question' "$tmpdir/session-new.json")" "Кто" "Target users question should stay business-readable"
        assert_eq "9" "$(jq -r '.topic_progress.total_topics' "$tmpdir/session-new.json")" "Discovery flow should track all required topics"
        assert_eq "1" "$(jq -r '.topic_progress.partial_topics' "$tmpdir/session-new.json")" "Raw idea should seed one partial topic"
        assert_eq "8" "$(jq -r '.topic_progress.unasked_topics' "$tmpdir/session-new.json")" "Remaining topics should stay unasked until covered"
        assert_eq "false" "$(jq -r '.topic_progress.ready_for_brief' "$tmpdir/session-new.json")" "A fresh session cannot be ready for brief generation"
        assert_eq "2" "$(jq -r '.conversation_turns | length' "$tmpdir/session-new.json")" "Session should preserve the user idea turn and one agent question"
        test_pass
    else
        test_fail "Discovery session should render structured progress from the new-session fixture"
    fi

    test_start "component_agent_factory_discovery_prioritizes_open_clarification_items"
    if python3 "$DISCOVERY_SCRIPT" run --source "$SESSION_CLARIFICATION_FIXTURE" --output "$tmpdir/session-clarification.json" >/dev/null; then
        assert_eq "awaiting_clarification" "$(jq -r '.status' "$tmpdir/session-clarification.json")" "Open clarification should keep the session in clarification state"
        assert_eq "resolve_clarification" "$(jq -r '.next_action' "$tmpdir/session-clarification.json")" "Clarification flow should be explicit"
        assert_eq "input_examples" "$(jq -r '.next_topic' "$tmpdir/session-clarification.json")" "Clarification should point to the affected topic"
        assert_contains "$(jq -r '.next_question' "$tmpdir/session-clarification.json")" "без реальных реквизитов" "Clarification question should preserve the operator-safe wording"
        assert_eq "1" "$(jq -r '.topic_progress.clarification_count' "$tmpdir/session-clarification.json")" "One open clarification should be counted"
        assert_contains "$(jq -r '.open_questions | join(" | ")' "$tmpdir/session-clarification.json")" "без реальных реквизитов" "Open questions should surface the active clarification"
        assert_eq "true" "$(jq -r '[.requirement_topics[] | select(.topic_name == "input_examples" and .status == "unresolved")] | length == 1' "$tmpdir/session-clarification.json")" "Affected topic should remain unresolved until clarified"
        test_pass
    else
        test_fail "Discovery session should keep clarification issues explicit"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_agent_factory_discovery_tests
fi
