#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

REMOTE_SEND_SCRIPT="$PROJECT_ROOT/scripts/telegram-bot-send-remote.sh"
FAKE_SSH_BIN_DIR=""
FAKE_SSH_STATE_DIR=""
FAKE_CURL_BIN_DIR=""

setup_component_telegram_bot_send_remote() {
    require_commands_or_skip bash jq python3 || return 2
    return 0
}

setup_fake_ssh() {
    FAKE_SSH_BIN_DIR="$(secure_temp_dir fake-ssh-bin)"
    FAKE_SSH_STATE_DIR="$(secure_temp_dir fake-ssh-state)"

    cat > "$FAKE_SSH_BIN_DIR/ssh" <<'SSH'
#!/usr/bin/env bash
set -euo pipefail

state_dir="${FAKE_SSH_STATE_DIR:?}"
printf '%s\n' "$@" > "$state_dir/ssh-args.txt"

remote_script="$state_dir/remote-script.sh"
cat > "$remote_script"
chmod +x "$remote_script"

args=("$@")
dashdash_index=-1
for i in "${!args[@]}"; do
  if [[ "${args[$i]}" == "--" ]]; then
    dashdash_index="$i"
    break
  fi
done

if (( dashdash_index < 0 )); then
  echo "missing -- marker" >&2
  exit 1
fi

remote_args=("${args[@]:$((dashdash_index + 1))}")
/bin/bash "$remote_script" "${remote_args[@]}"
SSH
    chmod +x "$FAKE_SSH_BIN_DIR/ssh"
}

setup_fake_curl() {
    FAKE_CURL_BIN_DIR="$(secure_temp_dir fake-curl-bin)"

cat > "$FAKE_CURL_BIN_DIR/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail

state_dir="${FAKE_SSH_STATE_DIR:?}"
printf '%s\n' "$@" > "$state_dir/curl-args.txt"
stdin_config="$(cat)"
printf '%s' "$stdin_config" > "$state_dir/curl-stdin.txt"

payload=""
args=("$@")
for i in "${!args[@]}"; do
  if [[ "${args[$i]}" == "-d" ]]; then
    next_index=$((i + 1))
    payload="${args[$next_index]:-}"
    break
  fi
done

printf '%s\n' "$payload" > "$state_dir/curl-payload.json"
echo '{"ok":true,"result":{"message_id":101}}'
CURL
    chmod +x "$FAKE_CURL_BIN_DIR/curl"
}

run_component_telegram_bot_send_remote_tests() {
    start_timer

    local setup_code=0
    set +e
    setup_component_telegram_bot_send_remote
    setup_code=$?
    set -e
    if [[ $setup_code -ne 0 ]]; then
        generate_report
        return
    fi

    local work_dir remote_root remote_env fake_sender output

    test_start "component_telegram_bot_send_remote_forwards_message_to_remote_sender"
    setup_fake_ssh
    work_dir="$(secure_temp_dir telegram-remote-send)"
    remote_root="$work_dir/remote-root"
    remote_env="$remote_root/.env"
    fake_sender="$remote_root/scripts/telegram-bot-send.sh"

    mkdir -p "$remote_root/scripts"
    cat > "$fake_sender" <<'SENDER'
#!/usr/bin/env bash
set -euo pipefail
state_dir="${FAKE_SSH_STATE_DIR:?}"
if [[ "${1:-}" == "--help" ]]; then
cat <<'EOF'
Usage:
  telegram-bot-send.sh --chat-id CHAT --text "message" [options]

Optional:
  --parse-mode MODE
  --disable-notification
  --reply-to MESSAGE_ID
  --reply-markup-json JSON
  --token TOKEN
  --json
EOF
exit 0
fi
printf '%s\n' "${MOLTIS_ENV_FILE:-missing}" > "$state_dir/remote-env.txt"
printf '%s\n' "$@" > "$state_dir/remote-args.txt"
echo '{"ok":true,"result":{"message_id":99}}'
SENDER
    chmod +x "$fake_sender"
    printf 'TELEGRAM_BOT_TOKEN=fake-token\n' > "$remote_env"

    output="$(
        PATH="$FAKE_SSH_BIN_DIR:$PATH" \
        FAKE_SSH_STATE_DIR="$FAKE_SSH_STATE_DIR" \
        MOLTINGER_TELEGRAM_SSH_BIN="$FAKE_SSH_BIN_DIR/ssh" \
        MOLTINGER_TELEGRAM_SSH_TARGET="fake-target" \
        MOLTINGER_TELEGRAM_REMOTE_ROOT="$remote_root" \
        MOLTINGER_TELEGRAM_REMOTE_ENV_FILE="$remote_env" \
        bash "$REMOTE_SEND_SCRIPT" \
            --chat-id 262872984 \
            --text "codex launch telegram probe" \
            --disable-notification \
            --json
    )"

    assert_contains "$output" '"ok":true' "Remote wrapper should return the remote sender JSON"
    assert_contains "$(cat "$FAKE_SSH_STATE_DIR/ssh-args.txt")" "fake-target" "SSH wrapper should target the configured host"
    assert_contains "$(cat "$FAKE_SSH_STATE_DIR/remote-args.txt")" "--chat-id" "Remote sender should receive chat-id flag"
    assert_contains "$(cat "$FAKE_SSH_STATE_DIR/remote-args.txt")" "262872984" "Remote sender should receive the configured chat id"
    assert_contains "$(cat "$FAKE_SSH_STATE_DIR/remote-args.txt")" "--disable-notification" "Remote sender should preserve silence flag"
    assert_eq "$remote_env" "$(cat "$FAKE_SSH_STATE_DIR/remote-env.txt")" "Remote sender should load TELEGRAM_BOT_TOKEN from the configured remote env file"
    test_pass

    test_start "component_telegram_bot_send_remote_preserves_multiline_text"
    output="$(
        PATH="$FAKE_SSH_BIN_DIR:$PATH" \
        FAKE_SSH_STATE_DIR="$FAKE_SSH_STATE_DIR" \
        MOLTINGER_TELEGRAM_SSH_BIN="$FAKE_SSH_BIN_DIR/ssh" \
        MOLTINGER_TELEGRAM_SSH_TARGET="fake-target" \
        MOLTINGER_TELEGRAM_REMOTE_ROOT="$remote_root" \
        MOLTINGER_TELEGRAM_REMOTE_ENV_FILE="$remote_env" \
        bash "$REMOTE_SEND_SCRIPT" \
            --chat-id 262872984 \
            --text $'Строка 1\nСтрока 2\nСтрока 3' \
            --json
    )"

    assert_contains "$output" '"ok":true' "Remote wrapper should keep returning remote sender JSON for multiline text"
    assert_contains "$(cat "$FAKE_SSH_STATE_DIR/remote-args.txt")" "Строка 1" "Remote sender should receive the first line of the multiline text"
    assert_contains "$(cat "$FAKE_SSH_STATE_DIR/remote-args.txt")" "Строка 2" "Remote sender should receive the second line of the multiline text"
    assert_contains "$(cat "$FAKE_SSH_STATE_DIR/remote-args.txt")" "Строка 3" "Remote sender should receive the third line of the multiline text"
    test_pass

    test_start "component_telegram_bot_send_remote_forwards_reply_markup_json"
    output="$(
        PATH="$FAKE_SSH_BIN_DIR:$PATH" \
        FAKE_SSH_STATE_DIR="$FAKE_SSH_STATE_DIR" \
        MOLTINGER_TELEGRAM_SSH_BIN="$FAKE_SSH_BIN_DIR/ssh" \
        MOLTINGER_TELEGRAM_SSH_TARGET="fake-target" \
        MOLTINGER_TELEGRAM_REMOTE_ROOT="$remote_root" \
        MOLTINGER_TELEGRAM_REMOTE_ENV_FILE="$remote_env" \
        bash "$REMOTE_SEND_SCRIPT" \
            --chat-id 262872984 \
            --text "codex consent prompt" \
            --reply-markup-json '{"inline_keyboard":[[{"text":"Да","callback_data":"codex-consent:accept:req-1:tok-1"}]]}' \
            --json
    )"

    assert_contains "$output" '"ok":true' "Remote wrapper should still return successful JSON with reply_markup"
    assert_contains "$(cat "$FAKE_SSH_STATE_DIR/remote-args.txt")" "--reply-markup-json" "Remote sender should preserve reply_markup flag"
    assert_contains "$(cat "$FAKE_SSH_STATE_DIR/remote-args.txt")" "inline_keyboard" "Remote sender should pass inline keyboard JSON through unchanged"
    test_pass

    test_start "component_telegram_bot_send_remote_falls_back_for_legacy_remote_sender"
    setup_fake_curl
    cat > "$fake_sender" <<'SENDER'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
cat <<'EOF'
Usage:
  telegram-bot-send.sh --chat-id CHAT --text "message" [options]

Optional:
  --parse-mode MODE
  --disable-notification
  --reply-to MESSAGE_ID
  --token TOKEN
  --json
EOF
exit 0
fi

echo '{"ok":false,"error":"Unknown argument: --reply-markup-json","script":"telegram-bot-send.sh"}'
exit 2
SENDER
    chmod +x "$fake_sender"

    output="$(
        PATH="$FAKE_CURL_BIN_DIR:$FAKE_SSH_BIN_DIR:$PATH" \
        FAKE_SSH_STATE_DIR="$FAKE_SSH_STATE_DIR" \
        MOLTINGER_TELEGRAM_SSH_BIN="$FAKE_SSH_BIN_DIR/ssh" \
        MOLTINGER_TELEGRAM_SSH_TARGET="fake-target" \
        MOLTINGER_TELEGRAM_REMOTE_ROOT="$remote_root" \
        MOLTINGER_TELEGRAM_REMOTE_ENV_FILE="$remote_env" \
        bash "$REMOTE_SEND_SCRIPT" \
            --chat-id 262872984 \
            --text "codex consent prompt" \
            --reply-markup-json '{"inline_keyboard":[[{"text":"Да","callback_data":"codex-consent:accept:req-1:tok-1"}]]}' \
            --json
    )"

    assert_contains "$output" '"ok":true' "Remote wrapper should fall back to direct Bot API call for legacy remote sender"
    assert_contains "$(cat "$FAKE_SSH_STATE_DIR/curl-args.txt")" "--config" "Fallback should configure curl via stdin instead of argv URL"
    if grep -Fq 'fake-token' "$FAKE_SSH_STATE_DIR/curl-args.txt"; then
        test_fail "Fallback should not expose the Telegram token in curl argv"
    fi
    assert_contains "$(cat "$FAKE_SSH_STATE_DIR/curl-stdin.txt")" "https://api.telegram.org/botfake-token/sendMessage" "Fallback should still target the remote Bot API URL through curl config stdin"
    assert_contains "$(cat "$FAKE_SSH_STATE_DIR/curl-payload.json")" "\"reply_markup\"" "Fallback payload should preserve reply_markup"
    assert_contains "$(cat "$FAKE_SSH_STATE_DIR/curl-payload.json")" "inline_keyboard" "Fallback payload should preserve inline keyboard JSON"
    test_pass

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_telegram_bot_send_remote_tests
fi
