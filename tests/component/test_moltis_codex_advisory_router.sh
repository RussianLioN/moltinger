#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

INTAKE_SCRIPT="$PROJECT_ROOT/scripts/moltis-codex-advisory-intake.sh"
ROUTER_SCRIPT="$PROJECT_ROOT/scripts/moltis-codex-advisory-router.sh"
STORE_SCRIPT="$PROJECT_ROOT/scripts/codex-advisory-session-store.sh"
EVENT_FIXTURE_DIR="$PROJECT_ROOT/tests/fixtures/codex-advisory-events"
ROUTING_FIXTURE_DIR="$PROJECT_ROOT/tests/fixtures/codex-advisory-routing"
REPORT_FINALIZED=false
FAKE_TELEGRAM_BIN_DIR=""
FAKE_TELEGRAM_STATE_DIR=""
FAKE_TELEGRAM_ENV_FILE=""

finalize_component_moltis_codex_advisory_router_report() {
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

on_component_moltis_codex_advisory_router_exit() {
    local exit_code="$?"
    trap - EXIT
    finalize_component_moltis_codex_advisory_router_report "$exit_code"
    exit "$exit_code"
}

setup_component_moltis_codex_advisory_router() {
    require_commands_or_skip bash jq python3 || return 2
    return 0
}

setup_fake_telegram_sender() {
    FAKE_TELEGRAM_BIN_DIR="$(secure_temp_dir fake-advisory-router-telegram-bin)"
    FAKE_TELEGRAM_STATE_DIR="$(secure_temp_dir fake-advisory-router-telegram-state)"
    FAKE_TELEGRAM_ENV_FILE="$FAKE_TELEGRAM_STATE_DIR/fake.env"
    : > "$FAKE_TELEGRAM_STATE_DIR/calls.log"

    cat > "$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh" <<'SEND'
#!/usr/bin/env bash
set -euo pipefail
state_dir="${FAKE_TELEGRAM_STATE_DIR:?}"
count_file="$state_dir/count.txt"
count=0
if [[ -f "$count_file" ]]; then
  count="$(cat "$count_file")"
fi
count=$((count + 1))
printf '%s\n' "$count" > "$count_file"
printf 'call\n' >> "$state_dir/calls.log"
printf '%s\n' "$*" > "$state_dir/call-${count}.txt"
if [[ "${FAKE_TELEGRAM_FAIL:-0}" == "1" ]]; then
  echo "fake telegram failure" >&2
  exit 1
fi
printf '{"ok":true,"result":{"message_id":%s}}\n' "$count"
SEND
    chmod +x "$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh"

    cat > "$FAKE_TELEGRAM_ENV_FILE" <<'ENV'
TELEGRAM_BOT_TOKEN=fake-token
ENV
}

copy_fixture_record() {
    local store_dir="$1"
    local fixture_name="$2"
    mkdir -p "$store_dir"
    cp "$ROUTING_FIXTURE_DIR/$fixture_name" "$store_dir/$(jq -r '.session.session_id' "$ROUTING_FIXTURE_DIR/$fixture_name").json"
}

run_component_moltis_codex_advisory_router_tests() {
    start_timer
    trap on_component_moltis_codex_advisory_router_exit EXIT

    local setup_code=0
    set +e
    setup_component_moltis_codex_advisory_router
    setup_code=$?
    set -e
    if [[ $setup_code -ne 0 ]]; then
        generate_report
        return
    fi

    local work_dir store_dir output render_json event_file session_file session_id callback_token

    test_start "component_codex_advisory_session_store_open_get_and_bind_message"
    work_dir="$(secure_temp_dir codex-advisory-store-open)"
    store_dir="$work_dir/store"
    output="$(
        bash "$STORE_SCRIPT" open \
            --store-dir "$store_dir" \
            --record-file "$ROUTING_FIXTURE_DIR/session-record-pending.json" \
            --json
    )"
    assert_contains "$output" '"session_id": "advsess-abc12345"' "Open should print the stored advisory session"
    output="$(bash "$STORE_SCRIPT" bind-message --store-dir "$store_dir" --session-id advsess-abc12345 --message-id 301 --json)"
    assert_json_value "$output" '.alert.message_id' "301" "bind-message should persist the Telegram alert id"
    output="$(bash "$STORE_SCRIPT" get --store-dir "$store_dir" --session-id advsess-abc12345 --json)"
    assert_json_value "$output" '.session.callback_token' "tok-xyz789" "get should return the authoritative advisory session"
    test_pass

    test_start "component_moltis_codex_advisory_intake_opens_pending_session_for_interactive_alert"
    setup_fake_telegram_sender
    export FAKE_TELEGRAM_STATE_DIR
    work_dir="$(secure_temp_dir codex-advisory-intake-open-session)"
    store_dir="$work_dir/store"
    render_json="$work_dir/render.json"
    bash "$INTAKE_SCRIPT" \
        --event-file "$EVENT_FIXTURE_DIR/advisory-event-interactive-ready.json" \
        --send true \
        --chat-id 262872984 \
        --interactive-mode inline_callbacks \
        --session-store-script "$STORE_SCRIPT" \
        --session-store-dir "$store_dir" \
        --telegram-send-script "$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh" \
        --telegram-env-file "$FAKE_TELEGRAM_ENV_FILE" \
        --json-out "$render_json" \
        --stdout none
    session_id="$(jq -r '.session.session_id' "$render_json")"
    callback_token="$(jq -r '.session.callback_token' "$render_json")"
    session_file="$store_dir/${session_id}.json"
    assert_file_exists "$session_file" "Interactive advisory delivery should open one pending session"
    assert_json_value "$(cat "$session_file")" '.session.status' "pending" "Fresh advisory session should start as pending"
    assert_json_value "$(cat "$session_file")" '.alert.message_id' "1" "Stored session should bind the alert message id"
    assert_contains "$(cat "$FAKE_TELEGRAM_STATE_DIR/call-1.txt")" "--reply-markup-json" "Interactive advisory alert should send inline callback markup"
    assert_contains "$(cat "$FAKE_TELEGRAM_STATE_DIR/call-1.txt")" "$callback_token" "Callback token should be encoded into Telegram reply markup"
    test_pass

    test_start "component_moltis_codex_advisory_router_accept_callback_sends_followup_immediately"
    output="$(
        bash "$ROUTER_SCRIPT" \
            --store-script "$STORE_SCRIPT" \
            --store-dir "$store_dir" \
            --callback-data "codex-advisory:accept:${session_id}:${callback_token}" \
            --chat-id 262872984 \
            --actor-id 262872984 \
            --reply-to 1 \
            --telegram-send-script "$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh" \
            --telegram-env-file "$FAKE_TELEGRAM_ENV_FILE" \
            --send-reply true \
            --stdout json
    )"
    assert_json_value "$output" '.handled' "true" "Router should handle a valid advisory callback"
    assert_json_value "$output" '.decision' "accept" "Accept callback should resolve as accept"
    assert_json_value "$output" '.delivery.status' "sent" "Accept callback should send recommendations immediately"
    assert_json_value "$(cat "$session_file")" '.session.status' "accepted" "Session should be accepted after a valid callback"
    assert_json_value "$(cat "$session_file")" '.interaction_record.followup_status' "sent" "Follow-up status should be marked as sent"
    assert_contains "$(cat "$FAKE_TELEGRAM_STATE_DIR/call-2.txt")" "Практические рекомендации" "Follow-up message should contain the recommendations headline"
    assert_contains "$(cat "$FAKE_TELEGRAM_STATE_DIR/call-2.txt")" "Что проверить в первую очередь" "Follow-up message should contain practical checks"
    test_pass

    test_start "component_moltis_codex_advisory_router_duplicate_accept_is_idempotent"
    output="$(
        bash "$ROUTER_SCRIPT" \
            --store-script "$STORE_SCRIPT" \
            --store-dir "$store_dir" \
            --callback-data "codex-advisory:accept:${session_id}:${callback_token}" \
            --chat-id 262872984 \
            --actor-id 262872984 \
            --reply-to 1 \
            --telegram-send-script "$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh" \
            --telegram-env-file "$FAKE_TELEGRAM_ENV_FILE" \
            --send-reply true \
            --stdout json
    )"
    assert_json_value "$output" '.decision' "duplicate" "Second identical callback should resolve as duplicate"
    assert_contains "$(cat "$FAKE_TELEGRAM_STATE_DIR/call-3.txt")" "уже был обработан" "Duplicate callback should only acknowledge duplicate handling"
    if grep -q "Практические рекомендации" "$FAKE_TELEGRAM_STATE_DIR/call-3.txt"; then
        test_fail "Duplicate callback must not send the recommendations headline a second time"
    else
        test_pass
    fi

    test_start "component_moltis_codex_advisory_router_decline_via_recovery_suppresses_followup"
    setup_fake_telegram_sender
    export FAKE_TELEGRAM_STATE_DIR
    work_dir="$(secure_temp_dir codex-advisory-router-decline)"
    store_dir="$work_dir/store"
    copy_fixture_record "$store_dir" "session-record-pending.json"
    output="$(
        bash "$ROUTER_SCRIPT" \
            --store-script "$STORE_SCRIPT" \
            --store-dir "$store_dir" \
            --event-file "$ROUTING_FIXTURE_DIR/event-recovery-decline.json" \
            --telegram-send-script "$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh" \
            --telegram-env-file "$FAKE_TELEGRAM_ENV_FILE" \
            --send-reply true \
            --stdout json
    )"
    assert_json_value "$output" '.decision' "decline" "Recovery decline should resolve explicitly"
    assert_json_value "$(cat "$store_dir/advsess-abc12345.json")" '.session.status' "declined" "Decline should close the session as declined"
    assert_json_value "$(cat "$store_dir/advsess-abc12345.json")" '.interaction_record.followup_status' "suppressed" "Decline should suppress follow-up delivery"
    assert_contains "$(cat "$FAKE_TELEGRAM_STATE_DIR/call-1.txt")" "не будут" "Decline should send only the acknowledgement"
    test_pass

    test_start "component_moltis_codex_advisory_router_rejects_wrong_chat_binding"
    work_dir="$(secure_temp_dir codex-advisory-router-invalid-chat)"
    store_dir="$work_dir/store"
    copy_fixture_record "$store_dir" "session-record-pending.json"
    output="$(
        bash "$ROUTER_SCRIPT" \
            --store-script "$STORE_SCRIPT" \
            --store-dir "$store_dir" \
            --event-file "$ROUTING_FIXTURE_DIR/event-invalid-chat.json" \
            --send-reply false \
            --stdout json
    )"
    assert_json_value "$output" '.decision' "invalid" "Router should reject recovery commands from another chat"
    assert_json_value "$(cat "$store_dir/advsess-abc12345.json")" '.session.status' "pending" "Wrong chat must not mutate the pending session"
    test_pass

    test_start "component_moltis_codex_advisory_router_marks_expired_session"
    work_dir="$(secure_temp_dir codex-advisory-router-expired)"
    store_dir="$work_dir/store"
    copy_fixture_record "$store_dir" "session-record-expired.json"
    output="$(
        bash "$ROUTER_SCRIPT" \
            --store-script "$STORE_SCRIPT" \
            --store-dir "$store_dir" \
            --callback-data "codex-advisory:accept:advsess-expired01:tok-expired" \
            --chat-id 262872984 \
            --actor-id 262872984 \
            --send-reply false \
            --stdout json
    )"
    assert_json_value "$output" '.decision' "expired" "Expired callback should resolve as expired"
    assert_json_value "$(cat "$store_dir/advsess-expired01.json")" '.session.status' "expired" "Expired session should be persisted as expired"
    test_pass

    finalize_component_moltis_codex_advisory_router_report 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_moltis_codex_advisory_router_tests
fi
