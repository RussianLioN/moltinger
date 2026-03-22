#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_TEST_CHAT_ID="${TELEGRAM_TEST_CHAT_ID:-}"
TELEGRAM_API_BASE="https://api.telegram.org/bot"
TEST_TIMEOUT="${TEST_TIMEOUT:-30}"
MOLTIS_URL="${MOLTIS_URL:-${TEST_BASE_URL:-https://moltis.ainetic.tech}}"
HARNESS_SCRIPT="$PROJECT_ROOT/scripts/telegram-e2e-on-demand.sh"

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

telethon_available() {
    if ! command -v python3 >/dev/null 2>&1; then
        return 1
    fi
    python3 -c 'import telethon' >/dev/null 2>&1
}

run_harness_probe() {
    local mode="$1"
    local message="$2"
    local timeout_sec="$3"
    local output_file="$4"
    local log_file="$5"
    local rc

    set +e
    bash "$HARNESS_SCRIPT" \
        --mode "$mode" \
        --message "$message" \
        --timeout-sec "$timeout_sec" \
        --output "$output_file" \
        --moltis-url "$MOLTIS_URL" \
        --verbose >"$log_file" 2>&1
    rc=$?
    set -e

    printf '%s\n' "$rc"
}

harness_report_completed() {
    local output_file="$1"
    local expected_transport="$2"

    jq -e --arg expected_transport "$expected_transport" '
        .status == "completed" and
        (.observed_response // "" | length > 0) and
        .transport == $expected_transport and
        .trigger_source == "cli"
    ' "$output_file" >/dev/null 2>&1
}

artifact_or_log_leaks_secret() {
    local secret_value="$1"
    shift

    [[ -n "$secret_value" ]] || return 1

    local path
    for path in "$@"; do
        if [[ -f "$path" ]] && grep -Fq -- "$secret_value" "$path"; then
            return 0
        fi
    done

    return 1
}

run_live_telegram_tests() {
    start_timer
    local suite_tmp_dir synthetic_report synthetic_log real_user_report real_user_log
    suite_tmp_dir="$(secure_temp_dir "telegram-live")"
    synthetic_report="$suite_tmp_dir/moltis-synthetic.json"
    synthetic_log="$suite_tmp_dir/moltis-synthetic.log"
    real_user_report="$suite_tmp_dir/moltis-real-user.json"
    real_user_log="$suite_tmp_dir/moltis-real-user.log"

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
    if require_secret_or_skip TELEGRAM_BOT_TOKEN "TELEGRAM_BOT_TOKEN"; then
        test_pass
    fi

    test_start "live_telegram_get_me"
    if [[ -z "$TELEGRAM_BOT_TOKEN" ]]; then
        test_skip "TELEGRAM_BOT_TOKEN not set"
    else
        local get_me
        get_me=$(telegram_api getMe)
        if echo "$get_me" | jq -e '.ok == true and (.result.id != null)' >/dev/null 2>&1; then
            test_pass
        else
            test_fail "Telegram getMe should return ok=true"
        fi
    fi

    test_start "live_telegram_webhook_info"
    if [[ -z "$TELEGRAM_BOT_TOKEN" ]]; then
        test_skip "TELEGRAM_BOT_TOKEN not set"
    else
        local webhook_info
        webhook_info=$(telegram_api getWebhookInfo)
        if echo "$webhook_info" | jq -e '.ok == true and (.result | type == "object")' >/dev/null 2>&1; then
            test_pass
        else
            test_fail "Telegram getWebhookInfo should return ok=true"
        fi
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

    test_start "live_moltis_synthetic_harness"
    if ! [[ -f "$HARNESS_SCRIPT" ]]; then
        test_fail "Harness script is missing: $HARNESS_SCRIPT"
    elif require_secret_or_skip MOLTIS_PASSWORD "MOLTIS_PASSWORD"; then
        local synthetic_exit synthetic_status
        synthetic_exit="$(run_harness_probe synthetic "/status" "$TEST_TIMEOUT" "$synthetic_report" "$synthetic_log")"
        synthetic_status="$(jq -r '.status // "missing"' "$synthetic_report" 2>/dev/null || echo "missing")"
        if [[ "$synthetic_exit" == "0" ]] && harness_report_completed "$synthetic_report" "moltis_api_chat"; then
            test_pass
        else
            test_fail "Synthetic harness should complete (exit=$synthetic_exit, status=$synthetic_status)"
        fi
    fi

    test_start "live_moltis_synthetic_projects_harness"
    if ! [[ -f "$HARNESS_SCRIPT" ]]; then
        test_fail "Harness script is missing: $HARNESS_SCRIPT"
    elif require_secret_or_skip MOLTIS_PASSWORD "MOLTIS_PASSWORD"; then
        local synthetic_projects_exit synthetic_projects_status
        synthetic_projects_exit="$(run_harness_probe synthetic "/projects" "$TEST_TIMEOUT" "$suite_tmp_dir/moltis-synthetic-projects.json" "$suite_tmp_dir/moltis-synthetic-projects.log")"
        synthetic_projects_status="$(jq -r '.status // "missing"' "$suite_tmp_dir/moltis-synthetic-projects.json" 2>/dev/null || echo "missing")"
        if [[ "$synthetic_projects_exit" == "0" ]] && harness_report_completed "$suite_tmp_dir/moltis-synthetic-projects.json" "moltis_api_chat"; then
            test_pass
        else
            test_fail "Synthetic /projects harness should complete (exit=$synthetic_projects_exit, status=$synthetic_projects_status)"
        fi
    fi

    test_start "live_moltis_real_user_harness"
    if ! [[ -f "$HARNESS_SCRIPT" ]]; then
        test_fail "Harness script is missing: $HARNESS_SCRIPT"
    elif ! telethon_available; then
        test_skip "telethon is not installed on the live runner"
    elif ! require_secret_or_skip TELEGRAM_TEST_API_ID "TELEGRAM_TEST_API_ID"; then
        :
    elif ! require_secret_or_skip TELEGRAM_TEST_API_HASH "TELEGRAM_TEST_API_HASH"; then
        :
    elif ! require_secret_or_skip TELEGRAM_TEST_SESSION "TELEGRAM_TEST_SESSION"; then
        :
    else
        local real_user_timeout real_user_exit real_user_status
        real_user_timeout="$TEST_TIMEOUT"
        if [[ "$real_user_timeout" -lt 45 ]]; then
            real_user_timeout=45
        fi
        real_user_exit="$(run_harness_probe real_user "/status" "$real_user_timeout" "$real_user_report" "$real_user_log")"
        real_user_status="$(jq -r '.status // "missing"' "$real_user_report" 2>/dev/null || echo "missing")"
        if [[ "$real_user_exit" == "0" ]] && harness_report_completed "$real_user_report" "telegram_mtproto_real_user"; then
            test_pass
        else
            test_fail "real_user harness should complete (exit=$real_user_exit, status=$real_user_status)"
        fi
    fi

    test_start "live_moltis_harness_redaction"
    if [[ ! -f "$synthetic_report" && ! -f "$real_user_report" ]]; then
        test_skip "No harness artifacts were produced in this run"
    elif artifact_or_log_leaks_secret "${MOLTIS_PASSWORD:-}" \
        "$synthetic_report" "$synthetic_log" "$real_user_report" "$real_user_log"; then
        test_fail "Harness artifacts or logs leaked MOLTIS_PASSWORD"
    elif artifact_or_log_leaks_secret "${TELEGRAM_TEST_SESSION:-}" \
        "$synthetic_report" "$synthetic_log" "$real_user_report" "$real_user_log"; then
        test_fail "Harness artifacts or logs leaked TELEGRAM_TEST_SESSION"
    else
        test_pass
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_live_telegram_tests
fi
