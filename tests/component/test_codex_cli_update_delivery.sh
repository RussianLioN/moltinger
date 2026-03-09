#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

DELIVERY_SCRIPT="$PROJECT_ROOT/scripts/codex-cli-update-delivery.sh"
FIXTURE_DIR="$PROJECT_ROOT/tests/fixtures/codex-update-delivery"
FAKE_TELEGRAM_BIN_DIR=""
FAKE_TELEGRAM_STATE_DIR=""

setup_component_codex_cli_update_delivery() {
    require_commands_or_skip jq python3 || return 2
    return 0
}

setup_fake_telegram_sender() {
    FAKE_TELEGRAM_BIN_DIR="$(secure_temp_dir fake-telegram-bin)"
    FAKE_TELEGRAM_STATE_DIR="$(secure_temp_dir fake-telegram-state)"

    cat > "$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh" <<'SEND'
#!/usr/bin/env bash
set -euo pipefail
state_dir="${FAKE_TELEGRAM_STATE_DIR:?}"
mkdir -p "$state_dir"
printf 'call\n' >> "$state_dir/calls.log"
printf '%s\n' "$*" >> "$state_dir/last-args.txt"
if [[ "${FAKE_TELEGRAM_FAIL:-0}" == "1" ]]; then
  echo '{"ok":false,"error":"fake telegram failure"}' >&2
  exit 1
fi
echo '{"ok":true,"result":{"message_id":1}}'
SEND
    chmod +x "$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh"
}

run_delivery() {
    local fixture="$1"
    local output_dir="$2"
    local state_file="$3"
    local surface="$4"
    shift 4

    bash "$DELIVERY_SCRIPT" \
        --surface "$surface" \
        --advisor-report "$fixture" \
        --state-file "$state_file" \
        --json-out "$output_dir/report.json" \
        --summary-out "$output_dir/summary.md" \
        --stdout none \
        "$@"
}

run_component_codex_cli_update_delivery_tests() {
    start_timer

    local setup_code=0
    set +e
    setup_component_codex_cli_update_delivery
    setup_code=$?
    set -e
    if [[ $setup_code -ne 0 ]]; then
        generate_report
        return
    fi

    local work_dir state_file report summary output original_path

    test_start "component_codex_cli_update_delivery_emits_schema_shape"
    work_dir="$(secure_temp_dir codex-update-delivery)"
    state_file="$work_dir/state.json"
    run_delivery "$FIXTURE_DIR/advisor-notify.json" "$work_dir" "$state_file" on-demand
    report="$work_dir/report.json"
    summary="$work_dir/summary.md"
    assert_file_exists "$report" "Delivery report JSON should be written"
    assert_file_exists "$summary" "Delivery summary should be written"
    if jq -e '
        has("checked_at") and
        has("advisor_snapshot") and
        has("fingerprint") and
        has("surface_decisions") and
        has("surface_state") and
        has("notes") and
        (.surface_decisions | length == 3)
    ' "$report" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Delivery report should match the required schema shape"
    fi

    test_start "component_codex_cli_update_delivery_on_demand_first_run_delivers"
    assert_eq "deliver" "$(jq -r '.surface_decisions[] | select(.surface == "on-demand") | .status' "$report")" "First on-demand run should deliver"
    assert_contains "$(cat "$summary")" "Suggested Project Changes" "On-demand summary should explain concrete follow-up ideas"
    test_pass

    test_start "component_codex_cli_update_delivery_on_demand_duplicate_is_suppressed_but_still_summarized"
    run_delivery "$FIXTURE_DIR/advisor-notify.json" "$work_dir" "$state_file" on-demand
    report="$work_dir/report.json"
    summary="$work_dir/summary.md"
    assert_eq "suppress" "$(jq -r '.surface_decisions[] | select(.surface == "on-demand") | .status' "$report")" "Repeated on-demand run should be marked as suppressed"
    assert_contains "$(cat "$summary")" "Delivery: suppress" "On-demand summary should remain available even when the state is already known"
    test_pass

    test_start "component_codex_cli_update_delivery_launcher_alert_is_short_and_duplicate_safe"
    work_dir="$(secure_temp_dir codex-update-delivery-launcher)"
    state_file="$work_dir/state.json"
    output="$(bash "$DELIVERY_SCRIPT" \
        --surface launcher \
        --advisor-report "$FIXTURE_DIR/advisor-notify.json" \
        --state-file "$state_file" \
        --stdout summary)"
    assert_contains "$output" "[Codex Update Alert]" "Launcher mode should emit a short alert banner"
    output="$(bash "$DELIVERY_SCRIPT" \
        --surface launcher \
        --advisor-report "$FIXTURE_DIR/advisor-notify.json" \
        --state-file "$state_file" \
        --stdout summary)"
    assert_eq "" "$output" "Repeated launcher run should suppress duplicate banner output"
    test_pass

    test_start "component_codex_cli_update_delivery_surfaces_investigate_state"
    work_dir="$(secure_temp_dir codex-update-delivery-investigate)"
    state_file="$work_dir/state.json"
    run_delivery "$FIXTURE_DIR/advisor-investigate.json" "$work_dir" "$state_file" on-demand
    report="$work_dir/report.json"
    assert_eq "investigate" "$(jq -r '.surface_decisions[] | select(.surface == "on-demand") | .status' "$report")" "Investigate fixture should remain investigate for the active surface"
    test_pass

    test_start "component_codex_cli_update_delivery_keeps_surface_state_separate"
    work_dir="$(secure_temp_dir codex-update-delivery-surfaces)"
    state_file="$work_dir/state.json"
    run_delivery "$FIXTURE_DIR/advisor-notify.json" "$work_dir" "$state_file" on-demand
    run_delivery "$FIXTURE_DIR/advisor-notify.json" "$work_dir" "$state_file" launcher
    report="$work_dir/report.json"
    assert_eq "deliver" "$(jq -r '.surface_decisions[] | select(.surface == "launcher") | .status' "$report")" "Launcher should still deliver even if on-demand already saw the same fingerprint"
    test_pass

    test_start "component_codex_cli_update_delivery_telegram_sends_once_and_suppresses_duplicates"
    setup_fake_telegram_sender
    original_path="$PATH"
    export PATH="$FAKE_TELEGRAM_BIN_DIR:$PATH"
    export FAKE_TELEGRAM_STATE_DIR
    work_dir="$(secure_temp_dir codex-update-delivery-telegram)"
    state_file="$work_dir/state.json"
    run_delivery "$FIXTURE_DIR/advisor-notify.json" "$work_dir" "$state_file" telegram \
        --telegram-enabled \
        --telegram-chat-id 123456 \
        --telegram-send-script "$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh"
    report="$work_dir/report.json"
    assert_eq "deliver" "$(jq -r '.surface_decisions[] | select(.surface == "telegram") | .status' "$report")" "Fresh telegram run should send"
    run_delivery "$FIXTURE_DIR/advisor-notify.json" "$work_dir" "$state_file" telegram \
        --telegram-enabled \
        --telegram-chat-id 123456 \
        --telegram-send-script "$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh"
    report="$work_dir/report.json"
    assert_eq "suppress" "$(jq -r '.surface_decisions[] | select(.surface == "telegram") | .status' "$report")" "Duplicate telegram run should suppress resend"
    assert_eq "1" "$(wc -l < "$FAKE_TELEGRAM_STATE_DIR/calls.log" | tr -d ' ')" "Telegram sender should be invoked only once"
    test_pass

    test_start "component_codex_cli_update_delivery_marks_telegram_failures_retryable"
    setup_fake_telegram_sender
    export PATH="$FAKE_TELEGRAM_BIN_DIR:$original_path"
    export FAKE_TELEGRAM_STATE_DIR
    export FAKE_TELEGRAM_FAIL=1
    work_dir="$(secure_temp_dir codex-update-delivery-telegram-fail)"
    state_file="$work_dir/state.json"
    run_delivery "$FIXTURE_DIR/advisor-notify.json" "$work_dir" "$state_file" telegram \
        --telegram-enabled \
        --telegram-chat-id 123456 \
        --telegram-send-script "$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh"
    report="$work_dir/report.json"
    assert_eq "retry" "$(jq -r '.surface_decisions[] | select(.surface == "telegram") | .status' "$report")" "Telegram failure should remain retryable"
    unset FAKE_TELEGRAM_FAIL
    export PATH="$original_path"
    test_pass

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_codex_cli_update_delivery_tests
fi
