#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

WATCHER_SCRIPT="$PROJECT_ROOT/scripts/codex-cli-upstream-watcher.sh"
FIXTURE_DIR="$PROJECT_ROOT/tests/fixtures/codex-upstream-watcher"
FAKE_TELEGRAM_BIN_DIR=""
FAKE_TELEGRAM_STATE_DIR=""
FAKE_TELEGRAM_ENV_FILE=""

setup_component_codex_cli_upstream_watcher() {
    require_commands_or_skip jq python3 || return 2
    return 0
}

setup_fake_telegram_sender() {
    FAKE_TELEGRAM_BIN_DIR="$(secure_temp_dir fake-telegram-bin)"
    FAKE_TELEGRAM_STATE_DIR="$(secure_temp_dir fake-telegram-state)"
    FAKE_TELEGRAM_ENV_FILE="$FAKE_TELEGRAM_STATE_DIR/fake.env"

    cat > "$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh" <<'SEND'
#!/usr/bin/env bash
set -euo pipefail
state_dir="${FAKE_TELEGRAM_STATE_DIR:?}"
mkdir -p "$state_dir"
printf 'call\n' >> "$state_dir/calls.log"
printf '%s\n' "$*" >> "$state_dir/last-args.txt"
if [[ "${FAKE_TELEGRAM_FAIL:-0}" == "1" ]]; then
  echo "fake telegram failure" >&2
  exit 1
fi
echo '{"ok":true,"result":{"message_id":1}}'
SEND
    chmod +x "$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh"

    cat > "$FAKE_TELEGRAM_ENV_FILE" <<'ENV'
TELEGRAM_ALLOWED_USERS=123456
ENV
}

run_watcher() {
    local mode="$1"
    local output_dir="$2"
    local state_file="$3"
    shift 3

    bash "$WATCHER_SCRIPT" \
        --mode "$mode" \
        --state-file "$state_file" \
        --json-out "$output_dir/report.json" \
        --summary-out "$output_dir/summary.md" \
        --stdout none \
        "$@"
}

run_component_codex_cli_upstream_watcher_tests() {
    start_timer

    local setup_code=0
    set +e
    setup_component_codex_cli_upstream_watcher
    setup_code=$?
    set -e
    if [[ $setup_code -ne 0 ]]; then
        generate_report
        return
    fi

    local work_dir state_file report summary output

    test_start "component_codex_cli_upstream_watcher_emits_schema_shape"
    work_dir="$(secure_temp_dir codex-upstream-watcher-schema)"
    state_file="$work_dir/state.json"
    run_watcher manual "$work_dir" "$state_file" \
        --release-file "$FIXTURE_DIR/releases-0.113.0.html" \
        --include-issue-signals \
        --issue-signals-file "$FIXTURE_DIR/issue-signals.json"
    report="$work_dir/report.json"
    summary="$work_dir/summary.md"
    assert_file_exists "$report" "Watcher report JSON should be written"
    assert_file_exists "$summary" "Watcher summary should be written"
    if jq -e '
        has("checked_at") and
        has("snapshot") and
        has("fingerprint") and
        has("decision") and
        has("state") and
        has("notes") and
        (.snapshot.latest_version == "0.113.0") and
        (.snapshot.primary_source.status == "ok") and
        (.snapshot.advisory_sources[0].status == "ok")
    ' "$report" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Watcher report should match the schema shape"
    fi

    test_start "component_codex_cli_upstream_watcher_manual_first_run_is_fresh"
    assert_eq "deliver" "$(jq -r '.decision.status' "$report")" "First manual run should mark the upstream fingerprint as fresh"
    assert_eq "new" "$(jq -r '.snapshot.release_status' "$report")" "First manual run should report a new release status"
    assert_contains "$(cat "$summary")" "Последняя версия из официального источника: 0.113.0" "Summary should mention the latest version in Russian"
    test_pass

    test_start "component_codex_cli_upstream_watcher_manual_repeat_is_suppressed"
    run_watcher manual "$work_dir" "$state_file" \
        --release-file "$FIXTURE_DIR/releases-0.113.0.html" \
        --include-issue-signals \
        --issue-signals-file "$FIXTURE_DIR/issue-signals.json"
    report="$work_dir/report.json"
    assert_eq "suppress" "$(jq -r '.decision.status' "$report")" "Repeated manual run should be suppressed"
    assert_eq "known" "$(jq -r '.snapshot.release_status' "$report")" "Repeated manual run should be known"
    test_pass

    test_start "component_codex_cli_upstream_watcher_marks_advisory_source_unavailable"
    work_dir="$(secure_temp_dir codex-upstream-watcher-advisory)"
    state_file="$work_dir/state.json"
    run_watcher manual "$work_dir" "$state_file" \
        --release-file "$FIXTURE_DIR/releases-0.113.0.html" \
        --include-issue-signals \
        --issue-signals-file "$FIXTURE_DIR/missing-issues.json"
    report="$work_dir/report.json"
    assert_eq "unavailable" "$(jq -r '.snapshot.advisory_sources[0].status' "$report")" "Missing advisory source should be marked unavailable"
    test_pass

    test_start "component_codex_cli_upstream_watcher_surfaces_primary_parse_investigate"
    work_dir="$(secure_temp_dir codex-upstream-watcher-investigate)"
    state_file="$work_dir/state.json"
    run_watcher manual "$work_dir" "$state_file" \
        --release-file "$FIXTURE_DIR/releases-malformed.html"
    report="$work_dir/report.json"
    assert_eq "investigate" "$(jq -r '.decision.status' "$report")" "Malformed primary source should trigger investigate"
    assert_eq "investigate" "$(jq -r '.snapshot.primary_source.status' "$report")" "Primary source status should be investigate"
    test_pass

    test_start "component_codex_cli_upstream_watcher_scheduler_sends_once_and_suppresses_duplicates"
    setup_fake_telegram_sender
    export FAKE_TELEGRAM_STATE_DIR
    work_dir="$(secure_temp_dir codex-upstream-watcher-telegram)"
    state_file="$work_dir/state.json"
    run_watcher scheduler "$work_dir" "$state_file" \
        --release-file "$FIXTURE_DIR/releases-0.113.0.html" \
        --include-issue-signals \
        --issue-signals-file "$FIXTURE_DIR/issue-signals.json" \
        --telegram-enabled \
        --telegram-env-file "$FAKE_TELEGRAM_ENV_FILE" \
        --telegram-send-script "$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh"
    report="$work_dir/report.json"
    assert_eq "deliver" "$(jq -r '.decision.status' "$report")" "Fresh scheduler run should deliver"
    run_watcher scheduler "$work_dir" "$state_file" \
        --release-file "$FIXTURE_DIR/releases-0.113.0.html" \
        --include-issue-signals \
        --issue-signals-file "$FIXTURE_DIR/issue-signals.json" \
        --telegram-enabled \
        --telegram-env-file "$FAKE_TELEGRAM_ENV_FILE" \
        --telegram-send-script "$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh"
    report="$work_dir/report.json"
    assert_eq "suppress" "$(jq -r '.decision.status' "$report")" "Repeated scheduler run should suppress duplicate Telegram delivery"
    assert_eq "1" "$(wc -l < "$FAKE_TELEGRAM_STATE_DIR/calls.log" | tr -d ' ')" "Telegram sender should be called only once"
    test_pass

    test_start "component_codex_cli_upstream_watcher_retries_failed_telegram_delivery"
    setup_fake_telegram_sender
    export FAKE_TELEGRAM_STATE_DIR
    export FAKE_TELEGRAM_FAIL=1
    work_dir="$(secure_temp_dir codex-upstream-watcher-retry)"
    state_file="$work_dir/state.json"
    run_watcher scheduler "$work_dir" "$state_file" \
        --release-file "$FIXTURE_DIR/releases-0.113.0.html" \
        --telegram-enabled \
        --telegram-env-file "$FAKE_TELEGRAM_ENV_FILE" \
        --telegram-send-script "$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh"
    report="$work_dir/report.json"
    assert_eq "retry" "$(jq -r '.decision.status' "$report")" "Telegram failure should be retryable"
    unset FAKE_TELEGRAM_FAIL
    run_watcher scheduler "$work_dir" "$state_file" \
        --release-file "$FIXTURE_DIR/releases-0.113.0.html" \
        --telegram-enabled \
        --telegram-env-file "$FAKE_TELEGRAM_ENV_FILE" \
        --telegram-send-script "$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh"
    report="$work_dir/report.json"
    assert_eq "deliver" "$(jq -r '.decision.status' "$report")" "Retrying the same fingerprint should deliver once Telegram recovers"
    assert_eq "2" "$(wc -l < "$FAKE_TELEGRAM_STATE_DIR/calls.log" | tr -d ' ')" "Telegram sender should be retried exactly once more"
    test_pass

    test_start "component_codex_cli_upstream_watcher_recovery_to_same_fingerprint_does_not_resend"
    setup_fake_telegram_sender
    export FAKE_TELEGRAM_STATE_DIR
    work_dir="$(secure_temp_dir codex-upstream-watcher-recovery)"
    state_file="$work_dir/state.json"
    run_watcher scheduler "$work_dir" "$state_file" \
        --release-file "$FIXTURE_DIR/releases-0.113.0.html" \
        --telegram-enabled \
        --telegram-env-file "$FAKE_TELEGRAM_ENV_FILE" \
        --telegram-send-script "$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh"
    run_watcher scheduler "$work_dir" "$state_file" \
        --release-file "$FIXTURE_DIR/releases-malformed.html" \
        --telegram-enabled \
        --telegram-env-file "$FAKE_TELEGRAM_ENV_FILE" \
        --telegram-send-script "$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh"
    run_watcher scheduler "$work_dir" "$state_file" \
        --release-file "$FIXTURE_DIR/releases-0.113.0.html" \
        --telegram-enabled \
        --telegram-env-file "$FAKE_TELEGRAM_ENV_FILE" \
        --telegram-send-script "$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh"
    report="$work_dir/report.json"
    assert_eq "suppress" "$(jq -r '.decision.status' "$report")" "Recovery to the already-delivered fingerprint should suppress duplicates"
    assert_eq "1" "$(wc -l < "$FAKE_TELEGRAM_STATE_DIR/calls.log" | tr -d ' ')" "Recovery should not resend an already-delivered fingerprint"
    test_pass

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_codex_cli_upstream_watcher_tests
fi
