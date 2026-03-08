#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_TEST_CHAT_ID="${TELEGRAM_TEST_CHAT_ID:-}"
TELEGRAM_API_BASE="https://api.telegram.org/bot"
TEST_TIMEOUT="${TEST_TIMEOUT:-30}"

telegram_api() {
    local method="$1"
    local data="${2:-}"
    local url="${TELEGRAM_API_BASE}${TELEGRAM_BOT_TOKEN}/${method}"

    if [[ -n "$data" ]]; then
        curl -s --max-time "$TEST_TIMEOUT" -X POST "$url" -H 'Content-Type: application/json' -d "$data" 2>/dev/null
    else
        curl -s --max-time "$TEST_TIMEOUT" "$url" 2>/dev/null
    fi
}

run_live_telegram_tests() {
    start_timer

    if ! is_live_mode; then
        test_start "live_telegram_requires_live_mode"
        test_skip "Suite requires --live"
        generate_report
        return
    fi

    require_commands_or_skip curl jq || {
        test_start "live_telegram_setup"
        test_skip "Dependencies unavailable"
        generate_report
        return
    }

    test_start "live_telegram_token_available"
    require_secret_or_skip TELEGRAM_BOT_TOKEN "TELEGRAM_BOT_TOKEN" || {
        generate_report
        return
    }
    test_pass

    test_start "live_telegram_get_me"
    local get_me
    get_me=$(telegram_api getMe)
    if echo "$get_me" | jq -e '.ok == true and (.result.id != null)' >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Telegram getMe should return ok=true"
    fi

    test_start "live_telegram_webhook_info"
    local webhook_info
    webhook_info=$(telegram_api getWebhookInfo)
    if echo "$webhook_info" | jq -e '.ok == true and (.result | type == "object")' >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Telegram getWebhookInfo should return ok=true"
    fi

    test_start "live_telegram_send_message_smoke"
    if [[ -z "$TELEGRAM_TEST_CHAT_ID" ]]; then
        test_skip "Set TELEGRAM_TEST_CHAT_ID for outbound Telegram smoke"
    else
        local send_payload send_result
        send_payload=$(jq -nc --arg chat_id "$TELEGRAM_TEST_CHAT_ID" --arg text "moltinger live telegram smoke $(date +%s)" '{chat_id: $chat_id, text: $text}')
        send_result=$(telegram_api sendMessage "$send_payload")
        if echo "$send_result" | jq -e '.ok == true' >/dev/null 2>&1; then
            test_pass
        else
            test_fail "Telegram sendMessage should return ok=true"
        fi
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_live_telegram_tests
fi
