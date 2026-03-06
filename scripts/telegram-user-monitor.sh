#!/usr/bin/env bash
# telegram-user-monitor.sh - One-shot monitor: send probe as user and validate bot reply.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOLTIS_ENV_FILE="${MOLTIS_ENV_FILE:-.env}"

TELEGRAM_MONITOR_TARGET="${TELEGRAM_MONITOR_TARGET:-@moltinger_bot}"
TELEGRAM_MONITOR_MESSAGE="${TELEGRAM_MONITOR_MESSAGE:-/status}"
TELEGRAM_MONITOR_TIMEOUT_SECONDS="${TELEGRAM_MONITOR_TIMEOUT_SECONDS:-45}"
TELEGRAM_MONITOR_POLL_INTERVAL="${TELEGRAM_MONITOR_POLL_INTERVAL:-2}"
TELEGRAM_MONITOR_MIN_REPLY_LEN="${TELEGRAM_MONITOR_MIN_REPLY_LEN:-2}"
TELEGRAM_SESSION="${TELEGRAM_SESSION:-.telegram-user}"

show_help() {
    cat <<'EOF'
Usage:
  telegram-user-monitor.sh [options]

Options:
  --target @bot_or_chat         Target chat/bot (default: @moltinger_bot)
  --message "/status"           Probe message text (default: /status)
  --timeout 45                  Wait timeout seconds (default: 45)
  --poll-interval 2             Poll interval seconds (default: 2)
  --min-reply-len 2             Minimum reply length (default: 2)
  --session .telegram-user      Telethon session prefix
  --env-file .env               Env file with TELEGRAM_API_ID/HASH
  -h, --help                    Show help

Environment:
  TELEGRAM_API_ID, TELEGRAM_API_HASH
  TELEGRAM_MONITOR_TARGET, TELEGRAM_MONITOR_MESSAGE
  TELEGRAM_MONITOR_TIMEOUT_SECONDS, TELEGRAM_MONITOR_POLL_INTERVAL
  TELEGRAM_MONITOR_MIN_REPLY_LEN, TELEGRAM_SESSION
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) TELEGRAM_MONITOR_TARGET="${2:-}"; shift 2 ;;
        --message) TELEGRAM_MONITOR_MESSAGE="${2:-}"; shift 2 ;;
        --timeout) TELEGRAM_MONITOR_TIMEOUT_SECONDS="${2:-}"; shift 2 ;;
        --poll-interval) TELEGRAM_MONITOR_POLL_INTERVAL="${2:-}"; shift 2 ;;
        --min-reply-len) TELEGRAM_MONITOR_MIN_REPLY_LEN="${2:-}"; shift 2 ;;
        --session) TELEGRAM_SESSION="${2:-}"; shift 2 ;;
        --env-file) MOLTIS_ENV_FILE="${2:-}"; shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *)
            echo "{\"ok\":false,\"status\":\"fail\",\"error\":\"Unknown argument: $1\"}"
            exit 2
            ;;
    esac
done

if [[ -f "$MOLTIS_ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$MOLTIS_ENV_FILE"
    set +a
fi

exec "${SCRIPT_DIR}/telegram-user-probe.py" \
    --to "${TELEGRAM_MONITOR_TARGET}" \
    --text "${TELEGRAM_MONITOR_MESSAGE}" \
    --timeout-seconds "${TELEGRAM_MONITOR_TIMEOUT_SECONDS}" \
    --poll-interval "${TELEGRAM_MONITOR_POLL_INTERVAL}" \
    --min-reply-len "${TELEGRAM_MONITOR_MIN_REPLY_LEN}" \
    --session "${TELEGRAM_SESSION}" \
    --env-file "${MOLTIS_ENV_FILE}"
