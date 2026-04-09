#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

ROUTER_SCRIPT="$PROJECT_ROOT/scripts/moltis-codex-consent-router.sh"
STORE_SCRIPT="$PROJECT_ROOT/scripts/codex-telegram-consent-store.sh"
FIXTURE_DIR="$PROJECT_ROOT/tests/fixtures/codex-telegram-consent-routing"
REPORT_FINALIZED=false
FAKE_TELEGRAM_BIN_DIR=""
FAKE_TELEGRAM_STATE_DIR=""
FAKE_TELEGRAM_ENV_FILE=""

finalize_component_codex_consent_router_report() {
    local exit_code="${1:-0}"

    if [[ "$REPORT_FINALIZED" != "true" ]]; then
        REPORT_FINALIZED=true

        if [[ "$exit_code" -ne 0 && -n "${TEST_CURRENT:-}" ]]; then
            test_fail "Unexpected command failure (exit ${exit_code})"
        fi

        set +e
        generate_report
        set -e
    fi

    cleanup_registered_paths || true
}

on_component_codex_consent_router_exit() {
    local exit_code="$?"
    trap - EXIT
    finalize_component_codex_consent_router_report "$exit_code"
    exit "$exit_code"
}

setup_component_codex_consent_router() {
    require_commands_or_skip bash jq python3 || return 2
    return 0
}

setup_fake_telegram_sender() {
    FAKE_TELEGRAM_BIN_DIR="$(secure_temp_dir fake-consent-telegram-bin)"
    FAKE_TELEGRAM_STATE_DIR="$(secure_temp_dir fake-consent-telegram-state)"
    FAKE_TELEGRAM_ENV_FILE="$FAKE_TELEGRAM_STATE_DIR/fake.env"
    : > "$FAKE_TELEGRAM_STATE_DIR/calls.log"

    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -euo pipefail' \
        'state_dir="${FAKE_TELEGRAM_STATE_DIR:?}"' \
        'count_file="$state_dir/count.txt"' \
        'count=0' \
        'if [[ -f "$count_file" ]]; then' \
        '  count="$(cat "$count_file")"' \
        'fi' \
        'count=$((count + 1))' \
        'printf '"'"'%s\n'"'"' "$count" > "$count_file"' \
        'printf '"'"'call\n'"'"' >> "$state_dir/calls.log"' \
        'printf '"'"'%s\n'"'"' "$*" > "$state_dir/call-${count}.txt"' \
        'if [[ "${FAKE_TELEGRAM_FAIL:-0}" == "1" ]]; then' \
        '  echo "fake telegram failure" >&2' \
        '  exit 1' \
        'fi' \
        "printf '{\"ok\":true,\"result\":{\"message_id\":%s}}\\n' \"\$count\"" \
        > "$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh"
    chmod +x "$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh"

    printf '%s\n' \
        'TELEGRAM_BOT_TOKEN=fake-token' \
        > "$FAKE_TELEGRAM_ENV_FILE"
}

copy_fixture_record() {
    local store_dir="$1"
    local fixture_name="$2"
    mkdir -p "$store_dir"
    cp "$FIXTURE_DIR/$fixture_name" "$store_dir/$(jq -r '.request.request_id' "$FIXTURE_DIR/$fixture_name").json"
}

run_component_codex_consent_router_tests() {
    start_timer

    local setup_code=0
    set +e
    setup_component_codex_consent_router
    setup_code=$?
    set -e
    if [[ $setup_code -ne 0 ]]; then
        generate_report
        return
    fi

    local work_dir store_dir output record_path

    test_start "component_codex_consent_store_open_get_and_bind_message"
    work_dir="$(secure_temp_dir codex-consent-store-open)"
    store_dir="$work_dir/store"
    output="$(
        bash "$STORE_SCRIPT" open \
            --store-dir "$store_dir" \
            --record-file "$FIXTURE_DIR/consent-record-pending.json" \
            --json
    )"
    assert_contains "$output" '"request_id": "req-abc12345"' "Open should print the stored record"
    output="$(bash "$STORE_SCRIPT" bind-message --store-dir "$store_dir" --request-id req-abc12345 --message-id 301 --json)"
    assert_json_value "$output" '.request.question_message_id' "301" "bind-message should persist the Telegram question id"
    output="$(bash "$STORE_SCRIPT" get --store-dir "$store_dir" --request-id req-abc12345 --json)"
    assert_json_value "$output" '.request.action_token' "tok-xyz789" "get should return the authoritative record"
    test_pass

    test_start "component_codex_consent_router_accepts_valid_command_fallback"
    work_dir="$(secure_temp_dir codex-consent-router-accept)"
    store_dir="$work_dir/store"
    copy_fixture_record "$store_dir" "consent-record-pending.json"
    output="$(
        bash "$ROUTER_SCRIPT" \
            --store-script "$STORE_SCRIPT" \
            --store-dir "$store_dir" \
            --event-file "$FIXTURE_DIR/event-command-accept.json" \
            --send-reply false \
            --stdout json
    )"
    assert_json_value "$output" '.handled' "true" "Router should handle a valid structured fallback command"
    assert_json_value "$output" '.decision' "accept" "Router should classify accept correctly"
    assert_json_value "$(cat "$store_dir/req-abc12345.json")" '.request.status' "accepted" "Store should persist accepted status"
    assert_json_value "$(cat "$store_dir/req-abc12345.json")" '.decision.resolved_via' "command_fallback" "Store should record command routing path"
    test_pass

    test_start "component_codex_consent_router_accepts_short_command_alias"
    work_dir="$(secure_temp_dir codex-consent-router-short-alias)"
    store_dir="$work_dir/store"
    copy_fixture_record "$store_dir" "consent-record-pending.json"
    output="$(
        bash "$ROUTER_SCRIPT" \
            --store-script "$STORE_SCRIPT" \
            --store-dir "$store_dir" \
            --command-text "/codex_da" \
            --chat-id 262872984 \
            --actor-id 262872984 \
            --send-reply false \
            --stdout json
    )"
    assert_json_value "$output" '.handled' "true" "Router should handle the short accept command"
    assert_json_value "$output" '.decision' "accept" "Short accept command should resolve as accept"
    assert_json_value "$(cat "$store_dir/req-abc12345.json")" '.request.status' "accepted" "Short accept command should resolve the pending request"
    assert_json_value "$(cat "$store_dir/req-abc12345.json")" '.decision.resolved_via' "command_alias" "Store should record the short command alias path"
    test_pass

    test_start "component_codex_consent_router_marks_duplicate_after_already_resolved_action"
    output="$(
        bash "$ROUTER_SCRIPT" \
            --store-script "$STORE_SCRIPT" \
            --store-dir "$store_dir" \
            --event-file "$FIXTURE_DIR/event-command-accept.json" \
            --send-reply false \
            --stdout json
    )"
    assert_json_value "$output" '.decision' "duplicate" "Second identical action should be duplicate-safe"
    assert_json_value "$(cat "$store_dir/req-abc12345.json")" '.decision.decision' "duplicate" "Latest recorded decision should reflect duplicate handling"
    test_pass

    test_start "component_codex_consent_router_accepts_callback_payload"
    work_dir="$(secure_temp_dir codex-consent-router-callback)"
    store_dir="$work_dir/store"
    copy_fixture_record "$store_dir" "consent-record-pending.json"
    output="$(
        bash "$ROUTER_SCRIPT" \
            --store-script "$STORE_SCRIPT" \
            --store-dir "$store_dir" \
            --event-file "$FIXTURE_DIR/event-callback-accept.json" \
            --send-reply false \
            --stdout json
    )"
    assert_json_value "$output" '.decision' "accept" "Callback query should be routed as accept"
    assert_json_value "$(cat "$store_dir/req-abc12345.json")" '.decision.resolved_via' "callback_query" "Store should record callback_query origin"
    test_pass

    test_start "component_codex_consent_router_accept_sends_recommendations_immediately"
    setup_fake_telegram_sender
    export FAKE_TELEGRAM_STATE_DIR
    work_dir="$(secure_temp_dir codex-consent-router-followup)"
    store_dir="$work_dir/store"
    copy_fixture_record "$store_dir" "consent-record-pending.json"
    output="$(
        bash "$ROUTER_SCRIPT" \
            --store-script "$STORE_SCRIPT" \
            --store-dir "$store_dir" \
            --event-file "$FIXTURE_DIR/event-command-accept.json" \
            --telegram-send-script "$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh" \
            --telegram-env-file "$FAKE_TELEGRAM_ENV_FILE" \
            --send-reply true \
            --stdout json
    )"
    assert_json_value "$output" '.decision' "accept" "Accept should still resolve as accept when follow-up delivery is enabled"
    assert_json_value "$output" '.delivery.status' "sent" "Accept should send recommendations immediately"
    assert_json_value "$(cat "$store_dir/req-abc12345.json")" '.request.status' "delivered" "Successful recommendation delivery should promote the request to delivered"
    assert_json_value "$(cat "$store_dir/req-abc12345.json")" '.delivery.status' "sent" "Store should persist sent delivery state"
    assert_json_value "$(cat "$store_dir/req-abc12345.json")" '.delivery.message_id' "1" "Store should persist the Telegram message id of the follow-up"
    assert_contains "$(cat "$FAKE_TELEGRAM_STATE_DIR/call-1.txt")" "Практические рекомендации по обновлению Codex CLI" "Follow-up message should contain the recommendations headline"
    assert_contains "$(cat "$FAKE_TELEGRAM_STATE_DIR/call-1.txt")" "Что можно сделать в проекте" "Follow-up message should contain project actions"
    test_pass

    test_start "component_codex_consent_router_decline_suppresses_recommendation_followup"
    work_dir="$(secure_temp_dir codex-consent-router-decline)"
    store_dir="$work_dir/store"
    copy_fixture_record "$store_dir" "consent-record-pending.json"
    output="$(
        bash "$ROUTER_SCRIPT" \
            --store-script "$STORE_SCRIPT" \
            --store-dir "$store_dir" \
            --event-file "$FIXTURE_DIR/event-command-decline.json" \
            --telegram-send-script "$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh" \
            --telegram-env-file "$FAKE_TELEGRAM_ENV_FILE" \
            --send-reply false \
            --stdout json
    )"
    assert_json_value "$output" '.decision' "decline" "Decline should resolve explicitly"
    assert_json_value "$(cat "$store_dir/req-abc12345.json")" '.request.status' "declined" "Decline should close the request as declined"
    assert_json_value "$(cat "$store_dir/req-abc12345.json")" '.delivery.status' "suppressed" "Decline should suppress recommendation follow-up delivery"
    test_pass

    test_start "component_codex_consent_router_duplicate_accept_does_not_send_recommendations_twice"
    setup_fake_telegram_sender
    export FAKE_TELEGRAM_STATE_DIR
    work_dir="$(secure_temp_dir codex-consent-router-duplicate-followup)"
    store_dir="$work_dir/store"
    copy_fixture_record "$store_dir" "consent-record-pending.json"
    output="$(
        bash "$ROUTER_SCRIPT" \
            --store-script "$STORE_SCRIPT" \
            --store-dir "$store_dir" \
            --event-file "$FIXTURE_DIR/event-command-accept.json" \
            --telegram-send-script "$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh" \
            --telegram-env-file "$FAKE_TELEGRAM_ENV_FILE" \
            --send-reply true \
            --stdout json
    )"
    assert_json_value "$output" '.delivery.status' "sent" "First accept should send the recommendation follow-up"
    output="$(
        bash "$ROUTER_SCRIPT" \
            --store-script "$STORE_SCRIPT" \
            --store-dir "$store_dir" \
            --event-file "$FIXTURE_DIR/event-command-accept.json" \
            --telegram-send-script "$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh" \
            --telegram-env-file "$FAKE_TELEGRAM_ENV_FILE" \
            --send-reply true \
            --stdout json
    )"
    assert_json_value "$output" '.decision' "duplicate" "Second identical accept should resolve as duplicate"
    assert_contains "$(cat "$FAKE_TELEGRAM_STATE_DIR/call-2.txt")" "уже был обработан" "Duplicate accept should produce only a duplicate acknowledgement"
    if grep -q "Практические рекомендации по обновлению Codex CLI" "$FAKE_TELEGRAM_STATE_DIR/call-2.txt"; then
        test_fail "Duplicate accept should not send the recommendation headline a second time"
    else
        test_pass
    fi

    test_start "component_codex_consent_router_accept_marks_retry_when_followup_send_fails"
    setup_fake_telegram_sender
    export FAKE_TELEGRAM_STATE_DIR
    work_dir="$(secure_temp_dir codex-consent-router-followup-fail)"
    store_dir="$work_dir/store"
    copy_fixture_record "$store_dir" "consent-record-pending.json"
    output="$(
        FAKE_TELEGRAM_FAIL=1 \
        bash "$ROUTER_SCRIPT" \
            --store-script "$STORE_SCRIPT" \
            --store-dir "$store_dir" \
            --event-file "$FIXTURE_DIR/event-command-accept.json" \
            --telegram-send-script "$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh" \
            --telegram-env-file "$FAKE_TELEGRAM_ENV_FILE" \
            --send-reply true \
            --stdout json
    )"
    assert_json_value "$output" '.decision' "accept" "Delivery failure should not erase the original consent decision"
    assert_json_value "$output" '.delivery.status' "failed" "Router should report failed follow-up delivery when sender exits non-zero"
    assert_json_value "$(cat "$store_dir/req-abc12345.json")" '.request.status' "failed" "Failed follow-up delivery should move the request into failed state"
    assert_json_value "$(cat "$store_dir/req-abc12345.json")" '.delivery.status' "retry" "Store should remember that the recommendation follow-up needs retry"
    test_pass

    test_start "component_codex_consent_router_rejects_invalid_chat_context"
    work_dir="$(secure_temp_dir codex-consent-router-invalid-chat)"
    store_dir="$work_dir/store"
    copy_fixture_record "$store_dir" "consent-record-pending.json"
    output="$(
        bash "$ROUTER_SCRIPT" \
            --store-script "$STORE_SCRIPT" \
            --store-dir "$store_dir" \
            --event-file "$FIXTURE_DIR/event-invalid-chat.json" \
            --send-reply false \
            --stdout json
    )"
    assert_json_value "$output" '.decision' "invalid" "Chat mismatch should be rejected explicitly"
    assert_json_value "$(cat "$store_dir/req-abc12345.json")" '.request.status' "pending" "Invalid chat should not resolve the stored request"
    test_pass

    test_start "component_codex_consent_router_ignores_non_json_stdin_when_explicit_flags_are_present"
    work_dir="$(secure_temp_dir codex-consent-router-stdin-override)"
    store_dir="$work_dir/store"
    copy_fixture_record "$store_dir" "consent-record-expired.json"
    output="$(
        printf 'stdin should be ignored by explicit consent flags\n' \
        | bash "$ROUTER_SCRIPT" \
            --store-script "$STORE_SCRIPT" \
            --store-dir "$store_dir" \
            --callback-data "codex-consent:accept:req-expired01:tok-expired" \
            --chat-id 262872984 \
            --actor-id 262872984 \
            --send-reply false \
            --stdout json
    )"
    assert_json_value "$output" '.decision' "expired" "Explicit callback args should win over unrelated stdin payloads"
    assert_json_value "$(cat "$store_dir/req-expired01.json")" '.request.status' "expired" "Explicit callback args should still resolve the authoritative record"
    test_pass

    test_start "component_codex_consent_router_marks_expired_request"
    work_dir="$(secure_temp_dir codex-consent-router-expired)"
    store_dir="$work_dir/store"
    copy_fixture_record "$store_dir" "consent-record-expired.json"
    output="$(
        bash "$ROUTER_SCRIPT" \
            --store-script "$STORE_SCRIPT" \
            --store-dir "$store_dir" \
            --callback-data "codex-consent:accept:req-expired01:tok-expired" \
            --chat-id 262872984 \
            --actor-id 262872984 \
            --send-reply false \
            --stdout json
    )"
    assert_json_value "$output" '.decision' "expired" "Expired request should close as expired"
    assert_json_value "$(cat "$store_dir/req-expired01.json")" '.request.status' "expired" "Store should persist the expired state"
    test_pass
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    trap on_component_codex_consent_router_exit EXIT
    run_component_codex_consent_router_tests
fi
