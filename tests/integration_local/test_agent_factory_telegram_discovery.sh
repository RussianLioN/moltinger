#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

ADAPTER_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-telegram-adapter.py"
NEW_PROJECT_FIXTURE="$PROJECT_ROOT/tests/fixtures/agent-factory/telegram/update-new-project.json"
DISCOVERY_ANSWER_FIXTURE="$PROJECT_ROOT/tests/fixtures/agent-factory/telegram/update-discovery-answer.json"

run_integration_local_agent_factory_telegram_discovery_tests() {
    start_timer
    require_commands_or_skip python3 jq || {
        test_start "integration_local_agent_factory_telegram_discovery_prereqs"
        test_skip "python3 and jq are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    test_start "integration_local_agent_factory_telegram_discovery_new_project_to_follow_up"
    if python3 "$ADAPTER_SCRIPT" handle-update \
        --source "$NEW_PROJECT_FIXTURE" \
        --state-root "$tmpdir/state" \
        --output "$tmpdir/out-1.json" >/dev/null \
      && python3 "$ADAPTER_SCRIPT" handle-update \
        --source "$DISCOVERY_ANSWER_FIXTURE" \
        --state-root "$tmpdir/state" \
        --output "$tmpdir/out-2.json" >/dev/null; then
        local session_id
        session_id="$(jq -r '.telegram_adapter_session.telegram_adapter_session_id' "$tmpdir/out-1.json")"
        assert_eq "$session_id" "$(jq -r '.telegram_adapter_session.telegram_adapter_session_id' "$tmpdir/out-2.json")" \
            "Discovery follow-up must stay in the same Telegram adapter session"
        assert_eq "answer_discovery_question" "$(jq -r '.telegram_intent.intent_type' "$tmpdir/out-2.json")" \
            "Discovery answer fixture should resolve as answer_discovery_question"
        assert_eq "current_workflow" "$(jq -r '.runtime_response.next_topic' "$tmpdir/out-2.json")" \
            "After target_users answer adapter should ask current_workflow topic"
        assert_contains "$(jq -r '.reply_payloads | map(.reply_kind) | join(",")' "$tmpdir/out-2.json")" "discovery_question" \
            "Adapter should return the next discovery question payload"
        assert_contains "$(jq -r '.reply_payloads[0].rendered_text' "$tmpdir/out-2.json")" "Сбор требований продолжается" \
            "Status payload should stay user-readable in Telegram format"
        assert_file_exists "$tmpdir/state/history/${session_id}.jsonl" \
            "Adapter should persist Telegram history events for discovery routing"
        assert_eq "2" "$(wc -l < "$tmpdir/state/history/${session_id}.jsonl" | tr -d ' ')" \
            "Two Telegram turns should create two history records"
        test_pass
    else
        test_fail "Adapter should progress from new project to first follow-up discovery question"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_integration_local_agent_factory_telegram_discovery_tests
fi
