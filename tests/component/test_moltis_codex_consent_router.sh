#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

ROUTER_SCRIPT="$PROJECT_ROOT/scripts/moltis-codex-consent-router.sh"
STORE_SCRIPT="$PROJECT_ROOT/scripts/codex-telegram-consent-store.sh"
FIXTURE_DIR="$PROJECT_ROOT/tests/fixtures/codex-telegram-consent-routing"
REPORT_FINALIZED=false

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
