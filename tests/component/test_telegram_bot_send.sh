#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

SEND_SCRIPT="$PROJECT_ROOT/scripts/telegram-bot-send.sh"

setup_component_telegram_bot_send() {
    require_commands_or_skip bash awk sed grep cat || return 2
    if [[ ! -x "$SEND_SCRIPT" ]]; then
        test_skip "Send script is missing or not executable: $SEND_SCRIPT"
        return 2
    fi
    return 0
}

make_fake_curl_bin() {
    local bin_dir="$1"
    cat >"$bin_dir/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"${FAKE_CURL_ARGS_FILE:?}"
payload=""
args=("$@")
for i in "${!args[@]}"; do
  if [[ "${args[$i]}" == "-d" ]]; then
    next_index=$((i + 1))
    payload="${args[$next_index]:-}"
    break
  fi
done
printf '%s' "$payload" >"${FAKE_CURL_PAYLOAD_FILE:?}"
printf '%s\n' "${FAKE_CURL_RESPONSE:?}"
EOF
    chmod +x "$bin_dir/curl"
}

make_broken_jq_bin() {
    local bin_dir="$1"
    cat >"$bin_dir/jq" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
    chmod +x "$bin_dir/jq"
}

run_component_telegram_bot_send_tests() {
    start_timer

    local setup_code=0
    set +e
    setup_component_telegram_bot_send
    setup_code=$?
    set -e
    if [[ $setup_code -ne 0 ]]; then
        generate_report
        return
    fi

    test_start "component_telegram_bot_send_basic_send_works_without_jq"
    local basic_tmp basic_bin basic_args basic_payload basic_output
    basic_tmp="$(secure_temp_dir telegram-bot-send-basic)"
    basic_bin="$basic_tmp/bin"
    mkdir -p "$basic_bin"
    make_fake_curl_bin "$basic_bin"
    make_broken_jq_bin "$basic_bin"
    basic_args="$basic_tmp/curl-args.txt"
    basic_payload="$basic_tmp/curl-payload.json"
    basic_output="$(
        PATH="$basic_bin:/usr/bin:/bin" \
        FAKE_CURL_ARGS_FILE="$basic_args" \
        FAKE_CURL_PAYLOAD_FILE="$basic_payload" \
        FAKE_CURL_RESPONSE='{"ok":true,"result":{"message_id":101}}' \
        TELEGRAM_BOT_TOKEN='test-token' \
        /bin/bash "$SEND_SCRIPT" \
            --chat-id 262872984 \
            --text $'Строка 1\nСтрока 2'
    )"
    if [[ "$basic_output" == *'"ok":true'* ]] && \
       grep -Fq 'https://api.telegram.org/bottest-token/sendMessage' "$basic_args" && \
       grep -Fq '"chat_id":"262872984"' "$basic_payload" && \
       grep -Fq '"text":"Строка 1\nСтрока 2"' "$basic_payload" && \
       grep -Fq '"disable_notification":false' "$basic_payload"; then
        test_pass
    else
        test_fail "telegram-bot-send.sh must build a valid payload and succeed without jq for basic sends"
    fi

    test_start "component_telegram_bot_send_reply_markup_works_without_jq"
    local markup_tmp markup_bin markup_payload markup_output
    markup_tmp="$(secure_temp_dir telegram-bot-send-markup)"
    markup_bin="$markup_tmp/bin"
    mkdir -p "$markup_bin"
    make_fake_curl_bin "$markup_bin"
    make_broken_jq_bin "$markup_bin"
    markup_payload="$markup_tmp/curl-payload.json"
    markup_output="$(
        PATH="$markup_bin:/usr/bin:/bin" \
        FAKE_CURL_ARGS_FILE="$markup_tmp/curl-args.txt" \
        FAKE_CURL_PAYLOAD_FILE="$markup_payload" \
        FAKE_CURL_RESPONSE='{"ok":true,"result":{"message_id":102}}' \
        TELEGRAM_BOT_TOKEN='test-token' \
        /bin/bash "$SEND_SCRIPT" \
            --chat-id 262872984 \
            --text 'markup' \
            --reply-markup-json '{"inline_keyboard":[[{"text":"Да","callback_data":"x"}]]}'
    )"
    if [[ "$markup_output" == *'"ok":true'* ]] && \
       grep -Fq '"reply_markup":{"inline_keyboard":[[{"text":"Да","callback_data":"x"}]]}' "$markup_payload"; then
        test_pass
    else
        test_fail "telegram-bot-send.sh must preserve reply_markup JSON even when jq is unavailable"
    fi

    test_start "component_telegram_bot_send_fails_when_telegram_returns_ok_false"
    local fail_tmp fail_bin fail_output fail_status
    fail_tmp="$(secure_temp_dir telegram-bot-send-fail)"
    fail_bin="$fail_tmp/bin"
    mkdir -p "$fail_bin"
    make_fake_curl_bin "$fail_bin"
    make_broken_jq_bin "$fail_bin"
    set +e
    fail_output="$(
        PATH="$fail_bin:/usr/bin:/bin" \
        FAKE_CURL_ARGS_FILE="$fail_tmp/curl-args.txt" \
        FAKE_CURL_PAYLOAD_FILE="$fail_tmp/curl-payload.json" \
        FAKE_CURL_RESPONSE='{"ok":false,"description":"Forbidden"}' \
        TELEGRAM_BOT_TOKEN='test-token' \
        /bin/bash "$SEND_SCRIPT" \
            --chat-id 262872984 \
            --text 'forbidden'
    )"
    fail_status=$?
    set -e
    if [[ "$fail_status" -eq 1 ]] && [[ "$fail_output" == *'"ok":false'* ]]; then
        test_pass
    else
        test_fail "telegram-bot-send.sh must return non-zero when Telegram Bot API replies with ok=false"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_telegram_bot_send_tests
fi
