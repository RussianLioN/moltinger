#!/usr/bin/env bash
# telegram-webhook-monitor.sh - Continuous Telegram webhook/response quality monitor
# Safe for cron/CI: does not print secrets, emits structured JSON report.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="${MOLTIS_ACTIVE_ROOT:-$DEFAULT_PROJECT_ROOT}"

MODE="text"

show_help() {
    cat <<'EOF'
Usage: telegram-webhook-monitor.sh [--json] [--text]

Monitors Telegram channel health for Moltis:
  - Telegram token validity (getMe)
  - Webhook configuration/HTTPS/pending queue (getWebhookInfo)
  - Optional test message delivery (sendMessage)
  - Moltis telegram inbound mode + latest telegram session preview cleanliness

Environment:
  MOLTIS_ENV_FILE                  Path to .env file (default: <project-root>/.env)
  MOLTIS_BASE_URL                  Moltis base URL (default: http://localhost:13131)
  MOLTIS_PASSWORD                  Auth password for Moltis UI/API (optional for preview checks)
  TELEGRAM_BOT_TOKEN               Telegram bot token (required)
  TELEGRAM_TEST_USER               Telegram user ID for probe message (optional; no auto-fallback)
  TELEGRAM_REQUIRE_WEBHOOK         true|false (default: true)
  TELEGRAM_REQUIRE_HTTPS_WEBHOOK   true|false (default: true)
  TELEGRAM_REQUIRE_TEST_USER       true|false (default: false)
  TELEGRAM_PROBE_DISABLE_NOTIFICATION true|false (default: true)
  TELEGRAM_MAX_PENDING_UPDATES     Non-negative integer (default: 3)
  TELEGRAM_TIMEOUT_SECONDS         HTTP timeout in seconds (default: 20)
  MONITOR_VALIDATE_PREVIEW         true|false (default: true)
EOF
}

for arg in "$@"; do
    case "$arg" in
        --json)
            MODE="json"
            ;;
        --text)
            MODE="text"
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            exit 2
            ;;
    esac
done

is_true() {
    case "${1:-}" in
        1|true|TRUE|yes|YES|on|ON)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

timestamp_utc() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

declare -a FAILURES=()
declare -a WARNINGS=()

add_failure() {
    FAILURES+=("$1")
}

add_warning() {
    WARNINGS+=("$1")
}

require_bin() {
    local name="$1"
    if ! command -v "$name" >/dev/null 2>&1; then
        add_failure "Missing dependency: ${name}"
    fi
}

require_bin curl
require_bin jq

MOLTIS_ENV_FILE="${MOLTIS_ENV_FILE:-$PROJECT_ROOT/.env}"
MOLTIS_BASE_URL="${MOLTIS_BASE_URL:-http://localhost:13131}"
TELEGRAM_REQUIRE_WEBHOOK="${TELEGRAM_REQUIRE_WEBHOOK:-true}"
TELEGRAM_REQUIRE_HTTPS_WEBHOOK="${TELEGRAM_REQUIRE_HTTPS_WEBHOOK:-true}"
TELEGRAM_REQUIRE_TEST_USER="${TELEGRAM_REQUIRE_TEST_USER:-false}"
TELEGRAM_PROBE_DISABLE_NOTIFICATION="${TELEGRAM_PROBE_DISABLE_NOTIFICATION:-true}"
TELEGRAM_MAX_PENDING_UPDATES="${TELEGRAM_MAX_PENDING_UPDATES:-3}"
TELEGRAM_TIMEOUT_SECONDS="${TELEGRAM_TIMEOUT_SECONDS:-20}"
MONITOR_VALIDATE_PREVIEW="${MONITOR_VALIDATE_PREVIEW:-true}"

if [[ -f "$MOLTIS_ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$MOLTIS_ENV_FILE"
    set +a
else
    add_warning "Environment file not found: ${MOLTIS_ENV_FILE}"
fi

TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
MOLTIS_PASSWORD="${MOLTIS_PASSWORD:-}"
TELEGRAM_TEST_USER="${TELEGRAM_TEST_USER:-}"

if ! [[ "$TELEGRAM_MAX_PENDING_UPDATES" =~ ^[0-9]+$ ]]; then
    add_failure "TELEGRAM_MAX_PENDING_UPDATES must be a non-negative integer"
fi

telegram_api() {
    local method="$1"
    local payload="${2:-}"
    local url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/${method}"

    if [[ -n "$payload" ]]; then
        curl -sS --max-time "$TELEGRAM_TIMEOUT_SECONDS" \
            -X POST "$url" \
            -H "content-type: application/json" \
            -d "$payload"
    else
        curl -sS --max-time "$TELEGRAM_TIMEOUT_SECONDS" "$url"
    fi
}

telegram_ok=false
webhook_configured=false
webhook_https=false
send_probe_ok=false
send_probe_attempted=false
preview_clean=true
probe_skipped_reason=""

bot_username=""
bot_id=""
webhook_url=""
pending_updates=0
last_error_message=""
inbound_mode=""
telegram_preview=""
probe_message_id=""

if [[ -z "$TELEGRAM_BOT_TOKEN" ]]; then
    add_failure "TELEGRAM_BOT_TOKEN is not set"
else
    tg_me_raw="$(telegram_api "getMe" || true)"
    if ! echo "$tg_me_raw" | jq -e '.' >/dev/null 2>&1; then
        add_failure "getMe returned invalid JSON"
    else
        if [[ "$(echo "$tg_me_raw" | jq -r '.ok // false')" == "true" ]]; then
            telegram_ok=true
            bot_username="$(echo "$tg_me_raw" | jq -r '.result.username // ""')"
            bot_id="$(echo "$tg_me_raw" | jq -r '.result.id // ""')"
        else
            err_code="$(echo "$tg_me_raw" | jq -r '.error_code // "unknown"')"
            err_desc="$(echo "$tg_me_raw" | jq -r '.description // "unknown error"')"
            add_failure "getMe failed [${err_code}] ${err_desc}"
        fi
    fi

    tg_hook_raw="$(telegram_api "getWebhookInfo" || true)"
    if ! echo "$tg_hook_raw" | jq -e '.' >/dev/null 2>&1; then
        add_failure "getWebhookInfo returned invalid JSON"
    else
        if [[ "$(echo "$tg_hook_raw" | jq -r '.ok // false')" != "true" ]]; then
            add_failure "getWebhookInfo failed"
        else
            webhook_url="$(echo "$tg_hook_raw" | jq -r '.result.url // ""')"
            pending_updates="$(echo "$tg_hook_raw" | jq -r '.result.pending_update_count // 0')"
            last_error_message="$(echo "$tg_hook_raw" | jq -r '.result.last_error_message // ""')"

            if [[ -n "$webhook_url" && "$webhook_url" != "null" ]]; then
                webhook_configured=true
                if [[ "$webhook_url" =~ ^https:// ]]; then
                    webhook_https=true
                fi
            fi

            if is_true "$TELEGRAM_REQUIRE_WEBHOOK" && [[ "$webhook_configured" != "true" ]]; then
                add_failure "Telegram webhook is not configured (polling mode)"
            fi

            if is_true "$TELEGRAM_REQUIRE_HTTPS_WEBHOOK" && [[ "$webhook_configured" == "true" ]] && [[ "$webhook_https" != "true" ]]; then
                add_failure "Webhook URL is not HTTPS"
            fi

            if [[ "$pending_updates" -gt "$TELEGRAM_MAX_PENDING_UPDATES" ]]; then
                add_failure "Pending updates too high: ${pending_updates} > ${TELEGRAM_MAX_PENDING_UPDATES}"
            fi

            if [[ -n "$last_error_message" && "$last_error_message" != "null" ]]; then
                add_failure "Telegram webhook last_error_message is non-empty"
            fi
        fi
    fi
fi

if [[ -z "$TELEGRAM_TEST_USER" ]]; then
    if is_true "$TELEGRAM_REQUIRE_TEST_USER"; then
        add_failure "TELEGRAM_TEST_USER not set"
    else
        probe_skipped_reason="test_user_not_configured"
    fi
else
    if ! [[ "$TELEGRAM_TEST_USER" =~ ^[0-9]+$ ]]; then
        add_failure "TELEGRAM_TEST_USER must be numeric"
    elif [[ "$telegram_ok" == "true" ]]; then
        send_probe_attempted=true
        probe_disable_notification=false
        if is_true "$TELEGRAM_PROBE_DISABLE_NOTIFICATION"; then
            probe_disable_notification=true
        fi
        probe_text="[monitor] telegram/webhook probe $(timestamp_utc)"
        probe_payload="$(
            jq -cn \
                --arg chat_id "$TELEGRAM_TEST_USER" \
                --arg text "$probe_text" \
                --argjson disable_notification "$probe_disable_notification" \
                '{chat_id:$chat_id,text:$text,disable_notification:$disable_notification}'
        )"
        probe_resp="$(telegram_api "sendMessage" "$probe_payload" || true)"

        if ! echo "$probe_resp" | jq -e '.' >/dev/null 2>&1; then
            add_failure "sendMessage returned invalid JSON"
        elif [[ "$(echo "$probe_resp" | jq -r '.ok // false')" == "true" ]]; then
            send_probe_ok=true
            probe_message_id="$(echo "$probe_resp" | jq -r '.result.message_id // ""')"
        else
            err_code="$(echo "$probe_resp" | jq -r '.error_code // "unknown"')"
            err_desc="$(echo "$probe_resp" | jq -r '.description // "unknown error"')"
            add_failure "sendMessage failed [${err_code}] ${err_desc}"
        fi
    fi
fi

if is_true "$MONITOR_VALIDATE_PREVIEW"; then
    if [[ -z "$MOLTIS_PASSWORD" ]]; then
        add_warning "MOLTIS_PASSWORD not set: preview cleanliness check skipped"
    else
        cookie_file="$(mktemp)"
        trap 'rm -f "$cookie_file"' EXIT

        login_payload="$(jq -cn --arg password "$MOLTIS_PASSWORD" '{password:$password}')"
        login_code="$(
            curl -sS -o /dev/null -w "%{http_code}" \
                -c "$cookie_file" -b "$cookie_file" \
                -X POST "${MOLTIS_BASE_URL}/api/auth/login" \
                -H "content-type: application/json" \
                -d "$login_payload" || true
        )"

        if [[ "$login_code" != "200" ]]; then
            add_warning "Moltis login failed (HTTP ${login_code}), preview check skipped"
        else
            state_html="$(curl -sS -b "$cookie_file" "${MOLTIS_BASE_URL}/" || true)"
            state_json="$(
                printf '%s' "$state_html" | \
                    sed -n 's/.*window.__MOLTIS__=\(.*\);<\/script>.*/\1/p' | \
                    head -1
            )"

            if [[ -z "$state_json" ]]; then
                add_warning "Cannot extract window.__MOLTIS__ from UI page"
            elif ! echo "$state_json" | jq -e '.' >/dev/null 2>&1; then
                add_warning "window.__MOLTIS__ payload is not valid JSON"
            else
                inbound_mode="$(echo "$state_json" | jq -r '[.channel_descriptors[]? | select(.channel_type=="telegram")][0].capabilities.inbound_mode // ""')"
                telegram_preview="$(echo "$state_json" | jq -r '[.sessions_recent[]? | select((.key // "") | startswith("telegram:"))][0].preview // ""')"

                if is_true "$TELEGRAM_REQUIRE_WEBHOOK" && [[ "$inbound_mode" != "webhook" ]]; then
                    add_failure "Moltis telegram inbound_mode is '${inbound_mode:-unknown}', expected 'webhook'"
                fi

                if [[ -z "$telegram_preview" ]]; then
                    add_warning "No recent telegram session preview found"
                else
                    if echo "$telegram_preview" | grep -Eiq 'traceback|panic|exception|stack trace|internal server error'; then
                        preview_clean=false
                        add_failure "Telegram preview includes error signature"
                    fi
                    if echo "$telegram_preview" | grep -Eiq '<script|</|token|api[_-]?key|password'; then
                        preview_clean=false
                        add_failure "Telegram preview includes unsafe/sensitive pattern"
                    fi
                    if [[ "${#telegram_preview}" -lt 2 ]]; then
                        preview_clean=false
                        add_failure "Telegram preview is too short to validate quality"
                    fi
                fi
            fi
        fi
    fi
fi

failures_json='[]'
warnings_json='[]'

if [[ ${#FAILURES[@]} -gt 0 ]]; then
    failures_json="$(printf '%s\n' "${FAILURES[@]}" | jq -R . | jq -s .)"
fi
if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    warnings_json="$(printf '%s\n' "${WARNINGS[@]}" | jq -R . | jq -s .)"
fi

status="pass"
if [[ ${#FAILURES[@]} -gt 0 ]]; then
    status="fail"
elif [[ ${#WARNINGS[@]} -gt 0 ]]; then
    status="warn"
fi

report_json="$(
    jq -n \
        --arg status "$status" \
        --arg timestamp "$(timestamp_utc)" \
        --arg bot_username "$bot_username" \
        --arg bot_id "$bot_id" \
        --arg webhook_url "$webhook_url" \
        --arg inbound_mode "$inbound_mode" \
        --arg telegram_preview "$telegram_preview" \
        --arg probe_message_id "$probe_message_id" \
        --arg probe_skipped_reason "$probe_skipped_reason" \
        --argjson pending_updates "${pending_updates:-0}" \
        --argjson telegram_ok "$telegram_ok" \
        --argjson webhook_configured "$webhook_configured" \
        --argjson webhook_https "$webhook_https" \
        --argjson send_probe_ok "$send_probe_ok" \
        --argjson send_probe_attempted "$send_probe_attempted" \
        --argjson preview_clean "$preview_clean" \
        --argjson failures "$failures_json" \
        --argjson warnings "$warnings_json" \
        '{
            status: $status,
            timestamp: $timestamp,
            checks: {
                telegram_ok: $telegram_ok,
                webhook_configured: $webhook_configured,
                webhook_https: $webhook_https,
                pending_updates: $pending_updates,
                send_probe_attempted: $send_probe_attempted,
                send_probe_ok: $send_probe_ok,
                preview_clean: $preview_clean
            },
            telemetry: {
                bot_username: $bot_username,
                bot_id: $bot_id,
                webhook_url: $webhook_url,
                inbound_mode: $inbound_mode,
                probe_message_id: $probe_message_id,
                probe_skipped_reason: $probe_skipped_reason,
                telegram_preview: $telegram_preview
            },
            failures: $failures,
            warnings: $warnings
        }'
)"

if [[ "$MODE" == "json" ]]; then
    echo "$report_json"
else
    echo "Telegram webhook monitor: ${status}"
    echo "$report_json" | jq '.'
fi

if [[ "$status" == "fail" ]]; then
    exit 1
fi

exit 0
