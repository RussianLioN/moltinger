#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

SEND_SCRIPT="$PROJECT_ROOT/scripts/moltis-codex-advisory-send.sh"
INTAKE_SCRIPT="$PROJECT_ROOT/scripts/moltis-codex-advisory-intake.sh"
STORE_SCRIPT="$PROJECT_ROOT/scripts/codex-advisory-session-store.sh"
EVENT_FIXTURE="$PROJECT_ROOT/tests/fixtures/codex-advisory-events/advisory-event-interactive-ready.json"

FAKE_TELEGRAM_BIN_DIR=""
FAKE_TELEGRAM_STATE_DIR=""
FAKE_TELEGRAM_ENV_FILE=""

setup_component_moltis_codex_advisory_send() {
    require_commands_or_skip jq python3 || return 2
    return 0
}

setup_fake_telegram_sender() {
    FAKE_TELEGRAM_BIN_DIR="$(secure_temp_dir fake-advisory-send-bin)"
    FAKE_TELEGRAM_STATE_DIR="$(secure_temp_dir fake-advisory-send-state)"
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
printf '{"ok":true,"result":{"message_id":%s}}\n' "$count"
SEND
    chmod +x "$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh"

    cat > "$FAKE_TELEGRAM_ENV_FILE" <<'ENV'
TELEGRAM_BOT_TOKEN=fake-token
ENV
}

run_component_moltis_codex_advisory_send_tests() {
    start_timer

    local setup_code=0
    set +e
    setup_component_moltis_codex_advisory_send
    setup_code=$?
    set -e
    if [[ $setup_code -ne 0 ]]; then
        generate_report
        return
    fi

    local work_dir output_json audit_file

    test_start "component_moltis_codex_advisory_send_routes_watcher_delivery_into_intake"
    setup_fake_telegram_sender
    export FAKE_TELEGRAM_STATE_DIR
    work_dir="$(secure_temp_dir codex-advisory-send)"
    output_json="$work_dir/send.json"
    CODEX_UPSTREAM_WATCHER_ADVISORY_EVENT_OUT="$EVENT_FIXTURE" \
    MOLTIS_ENV_FILE="$FAKE_TELEGRAM_ENV_FILE" \
    MOLTIS_CODEX_ADVISORY_INTAKE_SCRIPT="$INTAKE_SCRIPT" \
    MOLTIS_CODEX_ADVISORY_TELEGRAM_SEND_SCRIPT="$FAKE_TELEGRAM_BIN_DIR/telegram-bot-send.sh" \
    MOLTIS_CODEX_ADVISORY_SESSION_STORE_SCRIPT="$STORE_SCRIPT" \
    MOLTIS_CODEX_ADVISORY_SESSION_STORE_DIR="$work_dir/session-store" \
    MOLTIS_CODEX_ADVISORY_AUDIT_DIR="$work_dir/audit" \
    MOLTIS_CODEX_ADVISORY_INTERACTIVE_MODE="inline_callbacks" \
    bash "$SEND_SCRIPT" \
        --chat-id 123456 \
        --text "ignored legacy watcher text" \
        --json > "$output_json"

    audit_file="$work_dir/audit/codex-advisory-f171d17b575745a0.json"
    assert_eq "true" "$(jq -r '.ok' "$output_json")" "Sender adapter should report Bot API compatible success"
    assert_eq "1" "$(jq -r '.result.message_id' "$output_json")" "Sender adapter should expose the Telegram message id"
    assert_eq "moltis-codex-advisory-send" "$(jq -r '.transport' "$output_json")" "Sender adapter should identify its transport"
    assert_eq "inline_callbacks" "$(jq -r '.interactive_mode' "$output_json")" "Interactive mode should come from the advisory config/env"
    assert_file_exists "$audit_file" "Sender adapter should persist advisory audit through intake"
    assert_contains "$(cat "$FAKE_TELEGRAM_STATE_DIR/last-args.txt")" "--reply-markup-json" "Adapter should preserve inline actions by routing through intake"
    test_pass

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_moltis_codex_advisory_send_tests
fi
