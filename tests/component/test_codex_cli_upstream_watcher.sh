#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

WATCHER_SCRIPT="$PROJECT_ROOT/scripts/codex-cli-upstream-watcher.sh"
CONSENT_STORE_SCRIPT="$PROJECT_ROOT/scripts/codex-telegram-consent-store.sh"
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
    : > "$FAKE_TELEGRAM_STATE_DIR/calls.log"

    cat > "$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh" <<'SEND'
#!/usr/bin/env bash
set -euo pipefail
state_dir="${FAKE_TELEGRAM_STATE_DIR:?}"
mkdir -p "$state_dir"
count_file="$state_dir/count.txt"
count=0
if [[ -f "$count_file" ]]; then
  count="$(cat "$count_file")"
fi
count=$((count + 1))
printf '%s\n' "$count" > "$count_file"
printf 'call\n' >> "$state_dir/calls.log"
printf '%s\n' "$*" >> "$state_dir/last-args.txt"
printf '%s\n' "$*" > "$state_dir/call-${count}.txt"
if [[ "${FAKE_TELEGRAM_FAIL:-0}" == "1" ]]; then
  echo "fake telegram failure" >&2
  exit 1
fi
printf '{"ok":true,"result":{"message_id":%s}}\n' "$count"
SEND
    chmod +x "$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh"

    cat > "$FAKE_TELEGRAM_ENV_FILE" <<'ENV'
TELEGRAM_ALLOWED_USERS=123456
TELEGRAM_BOT_TOKEN=fake-token
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

    local work_dir state_file report summary summary_text call_text consent_store_dir request_id store_record

    test_start "component_codex_cli_upstream_watcher_emits_extended_schema_shape"
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
        has("severity") and
        has("advisor_bridge") and
        has("followup") and
        has("automation") and
        (.snapshot.latest_version == "0.113.0") and
        (.snapshot.primary_source.status == "ok") and
        (.snapshot.highlight_explanations | length >= 1) and
        (.severity.level == "important") and
        (.advisor_bridge.status == "ready")
    ' "$report" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Watcher report should match the extended schema shape"
    fi

    test_start "component_codex_cli_upstream_watcher_manual_summary_is_russian_and_explains_new_modes"
    summary_text="$(cat "$summary")"
    assert_contains "$summary_text" "Важность: высокая" "Summary should expose severity in Russian"
    assert_contains "$summary_text" "Что умеет этот режим" "Summary should explain the new capabilities"
    assert_contains "$summary_text" "Практические рекомендации для проекта" "Summary should mention project applicability guidance"
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

    test_start "component_codex_cli_upstream_watcher_digest_queues_then_sends_combined_message"
    setup_fake_telegram_sender
    export FAKE_TELEGRAM_STATE_DIR
    work_dir="$(secure_temp_dir codex-upstream-watcher-digest)"
    state_file="$work_dir/state.json"
    run_watcher scheduler "$work_dir" "$state_file" \
        --release-file "$FIXTURE_DIR/releases-0.113.0.html" \
        --delivery-mode digest \
        --digest-max-items 2 \
        --telegram-enabled \
        --telegram-env-file "$FAKE_TELEGRAM_ENV_FILE" \
        --telegram-send-script "$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh"
    report="$work_dir/report.json"
    assert_eq "queued" "$(jq -r '.decision.status' "$report")" "First digest run should queue a pending digest item"
    assert_eq "0" "$(wc -l < "$FAKE_TELEGRAM_STATE_DIR/calls.log" | tr -d ' ')" "Digest queue should not send on the first item"

    run_watcher scheduler "$work_dir" "$state_file" \
        --release-file "$FIXTURE_DIR/releases-0.114.0.html" \
        --delivery-mode digest \
        --digest-max-items 2 \
        --telegram-enabled \
        --telegram-env-file "$FAKE_TELEGRAM_ENV_FILE" \
        --telegram-send-script "$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh"
    report="$work_dir/report.json"
    call_text="$(cat "$FAKE_TELEGRAM_STATE_DIR/call-1.txt")"
    assert_eq "deliver" "$(jq -r '.decision.status' "$report")" "Second digest item should flush the combined digest"
    assert_contains "$call_text" "Дайджест обновлений Codex CLI" "Telegram digest should use the digest headline"
    assert_contains "$call_text" "0.113.0" "Digest should mention the first queued version"
    assert_contains "$call_text" "0.114.0" "Digest should mention the second queued version"
    test_pass

    test_start "component_codex_cli_upstream_watcher_scheduler_emits_authoritative_consent_request"
    setup_fake_telegram_sender
    export FAKE_TELEGRAM_STATE_DIR
    work_dir="$(secure_temp_dir codex-upstream-watcher-telegram)"
    state_file="$work_dir/state.json"
    consent_store_dir="$work_dir/consent-store"
    run_watcher scheduler "$work_dir" "$state_file" \
        --release-file "$FIXTURE_DIR/releases-0.113.0.html" \
        --include-issue-signals \
        --issue-signals-file "$FIXTURE_DIR/issue-signals.json" \
        --telegram-enabled \
        --telegram-env-file "$FAKE_TELEGRAM_ENV_FILE" \
        --telegram-send-script "$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh" \
        --telegram-consent-store-script "$CONSENT_STORE_SCRIPT" \
        --telegram-consent-store-dir "$consent_store_dir"
    report="$work_dir/report.json"
    call_text="$(cat "$FAKE_TELEGRAM_STATE_DIR/call-1.txt")"
    request_id="$(jq -r '.followup.consent.pending_state.request_id' "$report")"
    store_record="$consent_store_dir/${request_id}.json"
    assert_eq "deliver" "$(jq -r '.decision.status' "$report")" "Fresh scheduler run should deliver the upstream alert"
    assert_eq "pending" "$(jq -r '.followup.consent.status' "$report")" "Scheduler alert should open a pending consent flow"
    assert_eq "authoritative" "$(jq -r '.followup.consent.router_mode' "$report")" "Watcher should advertise authoritative consent routing"
    assert_eq "true" "$(jq -r '.telegram_target.consent_router_enabled' "$report")" "Router flag should be exposed in the report"
    assert_file_exists "$store_record" "Watcher should persist a shared consent record for the authoritative router"
    assert_contains "$call_text" "Хотите получить практические рекомендации" "Alert message should ask whether recommendations are needed"
    assert_contains "$call_text" "/codex-followup accept" "Alert message should include explicit fallback command"
    assert_contains "$(cat "$FAKE_TELEGRAM_STATE_DIR/last-args.txt")" "--reply-markup-json" "Watcher should pass reply_markup for explicit actions"
    assert_eq "1" "$(jq -r '.request.question_message_id' "$store_record")" "Shared consent record should be bound to the Telegram alert message id"
    test_pass

    test_start "component_codex_cli_upstream_watcher_repeat_scheduler_run_is_suppressed_without_legacy_getupdates"
    run_watcher scheduler "$work_dir" "$state_file" \
        --release-file "$FIXTURE_DIR/releases-0.113.0.html" \
        --include-issue-signals \
        --issue-signals-file "$FIXTURE_DIR/issue-signals.json" \
        --telegram-enabled \
        --telegram-env-file "$FAKE_TELEGRAM_ENV_FILE" \
        --telegram-send-script "$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh" \
        --telegram-consent-store-script "$CONSENT_STORE_SCRIPT" \
        --telegram-consent-store-dir "$consent_store_dir"
    report="$work_dir/report.json"
    assert_eq "suppress" "$(jq -r '.decision.status' "$report")" "Repeated scheduler run should not resend the same upstream event"
    assert_eq "1" "$(wc -l < "$FAKE_TELEGRAM_STATE_DIR/calls.log" | tr -d ' ')" "Repeated scheduler run should not trigger a second Telegram message"
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

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_codex_cli_upstream_watcher_tests
fi
