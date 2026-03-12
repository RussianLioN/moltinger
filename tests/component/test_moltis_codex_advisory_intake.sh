#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

WATCHER_SCRIPT="$PROJECT_ROOT/scripts/codex-cli-upstream-watcher.sh"
INTAKE_SCRIPT="$PROJECT_ROOT/scripts/moltis-codex-advisory-intake.sh"
WATCHER_FIXTURE_DIR="$PROJECT_ROOT/tests/fixtures/codex-upstream-watcher"
EVENT_FIXTURE_DIR="$PROJECT_ROOT/tests/fixtures/codex-advisory-events"
FAKE_TELEGRAM_BIN_DIR=""
FAKE_TELEGRAM_STATE_DIR=""
FAKE_TELEGRAM_ENV_FILE=""

setup_component_moltis_codex_advisory_intake() {
    require_commands_or_skip jq python3 || return 2
    return 0
}

setup_fake_telegram_sender() {
    FAKE_TELEGRAM_BIN_DIR="$(secure_temp_dir fake-advisory-telegram-bin)"
    FAKE_TELEGRAM_STATE_DIR="$(secure_temp_dir fake-advisory-telegram-state)"
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

run_component_moltis_codex_advisory_intake_tests() {
    start_timer

    local setup_code=0
    set +e
    setup_component_moltis_codex_advisory_intake
    setup_code=$?
    set -e
    if [[ $setup_code -ne 0 ]]; then
        generate_report
        return
    fi

    local work_dir event_file render_json audit_file output_text exit_code

    test_start "component_codex_upstream_watcher_emits_moltis_advisory_event"
    work_dir="$(secure_temp_dir codex-advisory-event)"
    event_file="$work_dir/advisory-event.json"
    bash "$WATCHER_SCRIPT" \
        --mode manual \
        --release-file "$WATCHER_FIXTURE_DIR/releases-0.114.0.html" \
        --include-issue-signals \
        --issue-signals-file "$WATCHER_FIXTURE_DIR/issue-signals.json" \
        --json-out "$work_dir/report.json" \
        --summary-out "$work_dir/summary.md" \
        --advisory-event-out "$event_file" \
        --stdout none
    assert_file_exists "$event_file" "Watcher should export a normalized advisory event"
    if jq -e '
        .schema_version == "codex-advisory-event/v1" and
        .source == "codex-cli-upstream-watcher" and
        .latest_version == "0.114.0" and
        .why_it_matters_ru != "" and
        (.highlights_ru | length >= 2) and
        (.interactive_followup_eligible | type == "boolean")
    ' "$event_file" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Watcher should emit the expected Moltis advisory event shape"
    fi

    test_start "component_moltis_codex_advisory_intake_renders_interactive_ready_alert_without_repo_commands"
    work_dir="$(secure_temp_dir codex-advisory-intake-render)"
    render_json="$work_dir/render.json"
    bash "$INTAKE_SCRIPT" \
        --event-file "$EVENT_FIXTURE_DIR/advisory-event-interactive-ready.json" \
        --json-out "$render_json" \
        --stdout none
    assert_file_exists "$render_json" "Intake should emit a machine-readable render report"
    assert_eq "inline_callbacks" "$(jq -r '.alert.interactive_mode' "$render_json")" "Interactive-ready event should render inline callback mode"
    assert_contains "$(jq -r '.alert.message_text' "$render_json")" "Если нужны практические рекомендации" "Interactive-ready alert should mention inline actions"
    assert_contains "$(jq -c '.alert.reply_markup' "$render_json")" "\"inline_keyboard\"" "Interactive-ready alert should render inline keyboard markup"
    if grep -q "/codex_" <<<"$(jq -r '.alert.message_text' "$render_json")"; then
        test_fail "Interactive-ready alert must not mention retired repo-side command UX"
    else
        test_pass
    fi

    test_start "component_moltis_codex_advisory_intake_keeps_one_way_mode_honest"
    work_dir="$(secure_temp_dir codex-advisory-intake-one-way)"
    render_json="$work_dir/render.json"
    bash "$INTAKE_SCRIPT" \
        --event-file "$EVENT_FIXTURE_DIR/advisory-event-one-way.json" \
        --json-out "$render_json" \
        --stdout none
    assert_eq "one_way_only" "$(jq -r '.alert.interactive_mode' "$render_json")" "One-way fixture should stay one-way"
    assert_eq "not_requested" "$(jq -r '.interaction_record.followup_status' "$render_json")" "One-way alert must not open a pending follow-up"
    assert_contains "$(jq -r '.alert.message_text' "$render_json")" "one-way alert" "One-way alert should explain degraded delivery"
    assert_eq "null" "$(jq -r '.alert.reply_markup' "$render_json")" "One-way alert must not expose reply markup"
    test_pass

    test_start "component_moltis_codex_advisory_intake_sends_alert_and_persists_audit_record"
    setup_fake_telegram_sender
    export FAKE_TELEGRAM_STATE_DIR
    work_dir="$(secure_temp_dir codex-advisory-intake-send)"
    render_json="$work_dir/render.json"
    bash "$INTAKE_SCRIPT" \
        --event-file "$EVENT_FIXTURE_DIR/advisory-event-interactive-ready.json" \
        --send true \
        --chat-id 123456 \
        --telegram-send-script "$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh" \
        --telegram-env-file "$FAKE_TELEGRAM_ENV_FILE" \
        --audit-dir "$work_dir/audit" \
        --json-out "$render_json" \
        --stdout none
    audit_file="$work_dir/audit/codex-advisory-f171d17b575745a0.json"
    assert_eq "sent" "$(jq -r '.status' "$render_json")" "Intake should mark successful Telegram delivery"
    assert_eq "1" "$(jq -r '.alert.message_id' "$render_json")" "Telegram sender response should be reflected in the render report"
    assert_file_exists "$audit_file" "Intake should persist an audit record"
    assert_eq "inline_callbacks" "$(jq -r '.interactive_mode' "$audit_file")" "Audit record should preserve interactive mode"
    assert_contains "$(cat "$FAKE_TELEGRAM_STATE_DIR/last-args.txt")" "--reply-markup-json" "Interactive-ready delivery should send inline markup to Telegram"
    test_pass

    test_start "component_moltis_codex_advisory_intake_rejects_invalid_event_shape"
    work_dir="$(secure_temp_dir codex-advisory-intake-invalid)"
    set +e
    output_text="$(bash "$INTAKE_SCRIPT" --event-file "$EVENT_FIXTURE_DIR/advisory-event-invalid.json" --stdout none 2>&1)"
    exit_code=$?
    set -e
    if [[ $exit_code -eq 0 ]]; then
        test_fail "Invalid event shape should fail validation"
    else
        assert_contains "$output_text" "expected shape" "Failure should explain the advisory contract mismatch"
        test_pass
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_moltis_codex_advisory_intake_tests
fi
