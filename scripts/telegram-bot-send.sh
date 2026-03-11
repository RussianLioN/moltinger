#!/usr/bin/env bash
# telegram-bot-send.sh - Send Telegram message via Bot API from CLI.

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
MOLTIS_ENV_FILE="${MOLTIS_ENV_FILE:-.env}"
TELEGRAM_TIMEOUT_SECONDS="${TELEGRAM_TIMEOUT_SECONDS:-20}"

show_help() {
    cat <<'EOF'
Usage:
  telegram-bot-send.sh --chat-id CHAT --text "message" [options]

Required:
  --chat-id CHAT_ID           Target chat/user/channel ID (numeric or @username where Telegram allows)
  --text MESSAGE              Message text

Optional:
  --parse-mode MODE           MarkdownV2 | HTML
  --disable-notification      Send silently
  --reply-to MESSAGE_ID       Reply to a specific message
  --reply-markup-json JSON    Raw Telegram reply_markup JSON object
  --token TOKEN               Override TELEGRAM_BOT_TOKEN
  --json                      JSON output (default)
  -h, --help                  Show help

Environment:
  TELEGRAM_BOT_TOKEN          Required if --token not provided
  MOLTIS_ENV_FILE             Optional env file path (default: .env)
  TELEGRAM_TIMEOUT_SECONDS    API timeout in seconds (default: 20)
EOF
}

require_bin() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "{\"ok\":false,\"error\":\"Missing dependency: $1\",\"script\":\"$SCRIPT_NAME\"}"
        exit 1
    }
}

require_bin curl
require_bin jq

if [[ -f "$MOLTIS_ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$MOLTIS_ENV_FILE"
    set +a
fi

CHAT_ID=""
TEXT=""
PARSE_MODE=""
DISABLE_NOTIFICATION="false"
REPLY_TO=""
REPLY_MARKUP_JSON=""
TOKEN_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --chat-id)
            CHAT_ID="${2:-}"
            shift 2
            ;;
        --text)
            TEXT="${2:-}"
            shift 2
            ;;
        --parse-mode)
            PARSE_MODE="${2:-}"
            shift 2
            ;;
        --disable-notification)
            DISABLE_NOTIFICATION="true"
            shift
            ;;
        --reply-to)
            REPLY_TO="${2:-}"
            shift 2
            ;;
        --reply-markup-json)
            REPLY_MARKUP_JSON="${2:-}"
            shift 2
            ;;
        --token)
            TOKEN_OVERRIDE="${2:-}"
            shift 2
            ;;
        --json)
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "{\"ok\":false,\"error\":\"Unknown argument: $1\",\"script\":\"$SCRIPT_NAME\"}"
            exit 2
            ;;
    esac
done

TELEGRAM_BOT_TOKEN="${TOKEN_OVERRIDE:-${TELEGRAM_BOT_TOKEN:-}}"
if [[ -z "${TELEGRAM_BOT_TOKEN}" ]]; then
    echo "{\"ok\":false,\"error\":\"TELEGRAM_BOT_TOKEN is not set\",\"script\":\"$SCRIPT_NAME\"}"
    exit 1
fi

if [[ -z "$CHAT_ID" || -z "$TEXT" ]]; then
    echo "{\"ok\":false,\"error\":\"--chat-id and --text are required\",\"script\":\"$SCRIPT_NAME\"}"
    exit 2
fi

if [[ -n "$REPLY_MARKUP_JSON" ]] && ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$REPLY_MARKUP_JSON"; then
    echo "{\"ok\":false,\"error\":\"--reply-markup-json must be a JSON object\",\"script\":\"$SCRIPT_NAME\"}"
    exit 2
fi

payload="$(jq -cn \
    --arg chat_id "$CHAT_ID" \
    --arg text "$TEXT" \
    --arg parse_mode "$PARSE_MODE" \
    --argjson disable_notification "$DISABLE_NOTIFICATION" \
    --arg reply_to_message_id "$REPLY_TO" \
    --arg reply_markup_json "$REPLY_MARKUP_JSON" \
    '{
        chat_id: $chat_id,
        text: $text,
        disable_notification: $disable_notification
    }
    + (if ($parse_mode|length) > 0 then {parse_mode: $parse_mode} else {} end)
    + (if ($reply_to_message_id|length) > 0 then {reply_to_message_id: ($reply_to_message_id|tonumber)} else {} end)
    + (if ($reply_markup_json|length) > 0 then {reply_markup: ($reply_markup_json|fromjson)} else {} end)
    '
)"

curl -sS --max-time "$TELEGRAM_TIMEOUT_SECONDS" \
    -X POST \
    -H "content-type: application/json" \
    -d "$payload" \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
