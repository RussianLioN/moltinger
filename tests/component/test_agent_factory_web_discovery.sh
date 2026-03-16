#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

WEB_ADAPTER_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-web-adapter.py"
SESSION_NEW_FIXTURE="$PROJECT_ROOT/tests/fixtures/agent-factory/web-demo/session-new.json"
SESSION_DISCOVERY_ANSWER_FIXTURE="$PROJECT_ROOT/tests/fixtures/agent-factory/web-demo/session-discovery-answer.json"

assert_safe_browser_copy() {
    local text="$1"
    local message="$2"
    if [[ "$text" == *"/Users/"* ]] || [[ "$text" == *"ask_next_question"* ]] || [[ "$text" == *"discovery_in_progress"* ]] || [[ "$text" == *"discovery_runtime_state"* ]]; then
        test_fail "$message"
        return 1
    fi
    return 0
}

run_component_agent_factory_web_discovery_tests() {
    start_timer
    require_commands_or_skip python3 jq || {
        test_start "component_agent_factory_web_discovery_prereqs"
        test_skip "python3 and jq are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    test_start "component_agent_factory_web_discovery_renders_safe_first_followup_question"
    if python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$SESSION_NEW_FIXTURE" --state-root "$tmpdir/state" --output "$tmpdir/session-new.json" >/dev/null; then
        local card_kinds label_text card_text
        card_kinds="$(jq -r '[.reply_cards[].card_kind] | join(",")' "$tmpdir/session-new.json")"
        label_text="$(jq -r '.status_snapshot.user_visible_status_label + " | " + .status_snapshot.next_recommended_action_label' "$tmpdir/session-new.json")"
        card_text="$(jq -r '[.reply_cards[].body_text] | join("\n---\n")' "$tmpdir/session-new.json")"

        assert_eq "status_update,discovery_question" "$card_kinds" "US1 should render a status card plus the next discovery question"
        assert_eq "Сбор требований продолжается | Ответить на следующий вопрос" "$label_text" "Status snapshot should project browser-readable discovery labels"
        assert_eq "Агент-архитектор Moltis" "$(jq -r '.ui_projection.agent_display_name' "$tmpdir/session-new.json")" "UI projection should expose the architect agent identity"
        assert_eq "adaptive_architect" "$(jq -r '.ui_projection.question_source' "$tmpdir/session-new.json")" "First follow-up question should come from adaptive architect composer"
        assert_contains "$card_text" "Кто будет основным пользователем" "The first browser follow-up must stay business-readable"
        assert_contains "$card_text" "Сбор требований продолжается" "Status copy should explain the live discovery state in plain language"
        if assert_safe_browser_copy "$card_text" "Browser-visible reply cards must not leak internal machine codes or repo paths"; then
            test_pass
        fi
    else
        test_fail "Browser adapter should render the first follow-up question from the new-session fixture"
    fi

    test_start "component_agent_factory_web_discovery_routes_followup_answer_without_internal_leakage"
    if python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$SESSION_DISCOVERY_ANSWER_FIXTURE" --state-root "$tmpdir/state" --output "$tmpdir/session-answer.json" >/dev/null; then
        local card_kinds label_text card_text
        card_kinds="$(jq -r '[.reply_cards[].card_kind] | join(",")' "$tmpdir/session-answer.json")"
        label_text="$(jq -r '.status_snapshot.user_visible_status_label + " | " + .status_snapshot.next_recommended_action_label' "$tmpdir/session-answer.json")"
        card_text="$(jq -r '[.reply_cards[].body_text] | join("\n---\n")' "$tmpdir/session-answer.json")"

        assert_eq "current_workflow" "$(jq -r '.next_topic' "$tmpdir/session-answer.json")" "Second browser turn should advance the interview to current workflow"
        assert_eq "adaptive_architect" "$(jq -r '.ui_projection.question_source' "$tmpdir/session-answer.json")" "Follow-up question should stay in adaptive architect mode"
        assert_eq "status_update,discovery_question" "$card_kinds" "Follow-up browser turn should keep the status card plus the next discovery question"
        assert_eq "Сбор требований продолжается | Ответить на следующий вопрос" "$label_text" "Follow-up browser turn should preserve the same browser-readable status projection"
        assert_contains "$card_text" "Как этот процесс работает сейчас" "The next browser question should move to the current workflow topic"
        assert_contains "$card_text" "Следующий шаг: ответить на следующий вопрос." "Status card should stay readable after follow-up routing"
        if assert_safe_browser_copy "$card_text" "Follow-up browser reply cards must stay free from internal action IDs and repo paths"; then
            test_pass
        fi
    else
        test_fail "Browser adapter should route the second discovery answer into the next live question"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_agent_factory_web_discovery_tests
fi
