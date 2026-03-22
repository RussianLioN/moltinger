#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

ADAPTER_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-telegram-adapter.py"
NEW_PROJECT_FIXTURE="$PROJECT_ROOT/tests/fixtures/agent-factory/telegram/update-new-project.json"

run_integration_local_agent_factory_telegram_flow_tests() {
    start_timer
    require_commands_or_skip python3 jq || {
        test_start "integration_local_agent_factory_telegram_flow_prereqs"
        test_skip "python3 and jq are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    test_start "integration_local_agent_factory_telegram_flow_reuses_session_and_advances_topic"
    if python3 "$ADAPTER_SCRIPT" handle-update \
        --source "$NEW_PROJECT_FIXTURE" \
        --state-root "$tmpdir/state" \
        --output "$tmpdir/out-1.json" >/dev/null; then
        local session_id
        session_id="$(jq -r '.telegram_adapter_session.telegram_adapter_session_id' "$tmpdir/out-1.json")"
        local next_topic_1
        next_topic_1="$(jq -r '.runtime_response.next_topic' "$tmpdir/out-1.json")"

        cat > "$tmpdir/follow-up.json" <<'JSON'
{
  "update_id": 880010002,
  "message": {
    "message_id": 4502,
    "date": 1774000020,
    "chat": {
      "id": 262872984,
      "type": "private"
    },
    "from": {
      "id": 262872984,
      "first_name": "Сергей",
      "language_code": "ru"
    },
    "text": "Основной пользователь — клиентский менеджер, выгодоприобретатели — члены кредитного комитета."
  }
}
JSON
        if python3 "$ADAPTER_SCRIPT" handle-update \
            --source "$tmpdir/follow-up.json" \
            --state-root "$tmpdir/state" \
            --output "$tmpdir/out-2.json" >/dev/null; then
            assert_eq "$session_id" "$(jq -r '.telegram_adapter_session.telegram_adapter_session_id' "$tmpdir/out-2.json")" \
                "Follow-up turn must stay in the same Telegram adapter session"
            assert_eq "answer_discovery_question" "$(jq -r '.telegram_intent.intent_type' "$tmpdir/out-2.json")" \
                "Follow-up turn should be routed as discovery answer"
            assert_ne "$next_topic_1" "$(jq -r '.runtime_response.next_topic' "$tmpdir/out-2.json")" \
                "Next topic should advance after a meaningful answer"
            assert_file_exists "$tmpdir/state/sessions/${session_id}.json" "Adapter should persist session snapshot on disk"
            assert_contains "$(jq -r '.reply_payloads | map(.reply_kind) | join(",")' "$tmpdir/out-2.json")" "discovery_question" \
                "Adapter should ask the next discovery question"
            test_pass
        else
            test_fail "Follow-up update should be routed through persisted Telegram session"
        fi
    else
        test_fail "First Telegram update should create session and route to discovery"
    fi

    test_start "integration_local_agent_factory_telegram_flow_status_command_returns_snapshot_without_mutation"
    cat > "$tmpdir/status.json" <<'JSON'
{
  "update_id": 880010003,
  "message": {
    "message_id": 4503,
    "date": 1774000040,
    "chat": {
      "id": 262872984,
      "type": "private"
    },
    "from": {
      "id": 262872984,
      "first_name": "Сергей",
      "language_code": "ru"
    },
    "text": "/status"
  }
}
JSON
    if python3 "$ADAPTER_SCRIPT" handle-update \
        --source "$tmpdir/status.json" \
        --state-root "$tmpdir/state" \
        --output "$tmpdir/status-out.json" >/dev/null; then
        assert_eq "true" "$(jq -r '.ok' "$tmpdir/status-out.json")" "Status intent should be handled successfully"
        assert_eq "request_status" "$(jq -r '.telegram_intent.intent_type' "$tmpdir/status-out.json")" \
            "Status command should resolve into request_status intent"
        assert_eq "status_update" "$(jq -r '.reply_payloads[0].reply_kind' "$tmpdir/status-out.json")" \
            "Status command should return status update payload"
        test_pass
    else
        test_fail "Status command should return current Telegram session snapshot"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_integration_local_agent_factory_telegram_flow_tests
fi
