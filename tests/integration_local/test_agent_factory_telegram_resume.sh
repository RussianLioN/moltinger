#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

ADAPTER_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-telegram-adapter.py"

send_turn() {
    local tmpdir="$1"
    local state_root="$2"
    local turn_id="$3"
    local message_id="$4"
    local message_text="$5"
    cat > "$tmpdir/input-${turn_id}.json" <<JSON
{
  "update_id": $((880520000 + turn_id)),
  "message": {
    "message_id": $message_id,
    "date": $((1782000000 + turn_id)),
    "chat": {
      "id": 262872984,
      "type": "private"
    },
    "from": {
      "id": 262872984,
      "first_name": "Сергей",
      "language_code": "ru"
    },
    "text": "$message_text"
  }
}
JSON
    python3 "$ADAPTER_SCRIPT" handle-update \
        --source "$tmpdir/input-${turn_id}.json" \
        --state-root "$state_root" \
        --output "$tmpdir/output-${turn_id}.json" >/dev/null
}

run_integration_local_agent_factory_telegram_resume_tests() {
    start_timer
    require_commands_or_skip python3 jq || {
        test_start "integration_local_agent_factory_telegram_resume_prereqs"
        test_skip "python3 and jq are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    test_start "integration_local_agent_factory_telegram_resume_status_and_project_selection"
    if send_turn "$tmpdir" "$tmpdir/state" 1 9201 "Автоматизировать подготовку one-page summary по клиенту для кредитного комитета." \
      && send_turn "$tmpdir" "$tmpdir/state" 2 9202 "Пользователь первого проекта — клиентский менеджер, выгодоприобретатели — кредитный комитет." \
      && send_turn "$tmpdir" "$tmpdir/state" 3 9203 "/new Автоматизировать проверку комплектности кредитного досье перед комитетом." \
      && send_turn "$tmpdir" "$tmpdir/state" 4 9204 "Пользователь второго проекта — кредитный аналитик, выгодоприобретатели — риск-служба." \
      && send_turn "$tmpdir" "$tmpdir/state" 5 9205 "/projects"; then
        local key_a key_b ds_a ds_b
        key_a="$(jq -r '.active_project_pointer.project_key' "$tmpdir/output-1.json")"
        key_b="$(jq -r '.active_project_pointer.project_key' "$tmpdir/output-3.json")"
        ds_a="$(jq -r '.runtime_response.discovery_session_id' "$tmpdir/output-2.json")"
        ds_b="$(jq -r '.runtime_response.discovery_session_id' "$tmpdir/output-4.json")"

        assert_eq "list_projects" "$(jq -r '.telegram_intent.intent_type' "$tmpdir/output-5.json")" \
            "Projects command should resolve to list_projects intent"
        assert_contains "$(jq -r '.reply_payloads[0].rendered_text' "$tmpdir/output-5.json")" "$key_a" \
            "Projects list should include first project key"
        assert_contains "$(jq -r '.reply_payloads[0].rendered_text' "$tmpdir/output-5.json")" "$key_b" \
            "Projects list should include second project key"
        assert_eq "$key_b" "$(jq -r '.project_registry.active_project_key' "$tmpdir/output-5.json")" \
            "After opening second project it should remain active by default"
        assert_ne "$key_a" "$key_b" "Two started projects should have different keys"
        assert_ne "$ds_a" "$ds_b" "Different projects should have different discovery session ids"

        send_turn "$tmpdir" "$tmpdir/state" 6 9206 "/project $key_a"
        assert_eq "select_project" "$(jq -r '.telegram_intent.intent_type' "$tmpdir/output-6.json")" \
            "Project switch command should resolve to select_project intent"
        assert_eq "$key_a" "$(jq -r '.active_project_pointer.project_key' "$tmpdir/output-6.json")" \
            "Adapter should switch active project pointer"
        assert_contains "$(jq -r '.reply_payloads[0].rendered_text' "$tmpdir/output-6.json")" "Переключил на проект" \
            "Project selection response should acknowledge active project switch"

        send_turn "$tmpdir" "$tmpdir/state" 7 9207 "Для первого проекта потери в текущем процессе: ручная сверка и повторный перенос данных."
        assert_eq "$ds_a" "$(jq -r '.runtime_response.discovery_session_id' "$tmpdir/output-7.json")" \
            "After project switch the follow-up answer should continue first discovery session"
        assert_ne "$ds_b" "$(jq -r '.runtime_response.discovery_session_id' "$tmpdir/output-7.json")" \
            "After project switch adapter must not continue second discovery session"

        send_turn "$tmpdir" "$tmpdir/state" 8 9208 "/status"
        assert_eq "request_status" "$(jq -r '.telegram_intent.intent_type' "$tmpdir/output-8.json")" \
            "Status intent should still work after project switch"
        assert_eq "$key_a" "$(jq -r '.status_snapshot.project_key' "$tmpdir/output-8.json")" \
            "Status snapshot should reflect currently selected project"
        assert_eq "$key_a" "$(jq -r '.project_registry.active_project_key' "$tmpdir/output-8.json")" \
            "Project registry should persist active key after resume flow"
        test_pass
    else
        test_fail "Telegram adapter should support project listing, switch, and resumed continuation"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_integration_local_agent_factory_telegram_resume_tests
fi
