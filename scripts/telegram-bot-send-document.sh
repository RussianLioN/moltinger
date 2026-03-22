#!/usr/bin/env bash
# telegram-bot-send-document.sh - Send Telegram document via Bot API from CLI.

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
MOLTIS_ENV_FILE="${MOLTIS_ENV_FILE:-.env}"
TELEGRAM_TIMEOUT_SECONDS="${TELEGRAM_TIMEOUT_SECONDS:-30}"

show_help() {
    cat <<'EOF'
Usage:
  telegram-bot-send-document.sh --chat-id CHAT --file PATH [options]

Required:
  --chat-id CHAT_ID            Target chat/user/channel ID
  --file PATH                  Absolute or relative path to file

Optional:
  --caption TEXT               Caption for the document
  --disable-notification       Send silently
  --token TOKEN                Override TELEGRAM_BOT_TOKEN
  --dry-run                    Do not call Telegram API, only validate inputs
  --retry N                    Retry attempts for API call (default: 0)
  --json                       JSON output (default)
  -h, --help                   Show help

Environment:
  TELEGRAM_BOT_TOKEN           Required if --token not provided and --dry-run is not set
  MOLTIS_ENV_FILE              Optional env file path (default: .env)
  TELEGRAM_TIMEOUT_SECONDS     API timeout in seconds (default: 30)
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
FILE_PATH=""
CAPTION=""
DISABLE_NOTIFICATION="false"
TOKEN_OVERRIDE=""
DRY_RUN="false"
RETRY_COUNT="0"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --chat-id)
            CHAT_ID="${2:-}"
            shift 2
            ;;
        --file)
            FILE_PATH="${2:-}"
            shift 2
            ;;
        --caption)
            CAPTION="${2:-}"
            shift 2
            ;;
        --disable-notification)
            DISABLE_NOTIFICATION="true"
            shift
            ;;
        --token)
            TOKEN_OVERRIDE="${2:-}"
            shift 2
            ;;
        --retry)
            RETRY_COUNT="${2:-0}"
            shift 2
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
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

if [[ -z "$CHAT_ID" || -z "$FILE_PATH" ]]; then
    echo "{\"ok\":false,\"error\":\"--chat-id and --file are required\",\"script\":\"$SCRIPT_NAME\"}"
    exit 2
fi

if [[ ! -f "$FILE_PATH" ]]; then
    echo "{\"ok\":false,\"error\":\"File not found: $FILE_PATH\",\"script\":\"$SCRIPT_NAME\"}"
    exit 2
fi

if [[ "$DRY_RUN" == "true" ]]; then
    jq -cn \
      --arg script "$SCRIPT_NAME" \
      --arg chat_id "$CHAT_ID" \
      --arg file_path "$FILE_PATH" \
      --arg caption "$CAPTION" \
      --argjson disable_notification "$DISABLE_NOTIFICATION" \
      '{ok:true,dry_run:true,script:$script,chat_id:$chat_id,file_path:$file_path,caption:$caption,disable_notification:$disable_notification}'
    exit 0
fi

TELEGRAM_BOT_TOKEN="${TOKEN_OVERRIDE:-${TELEGRAM_BOT_TOKEN:-}}"
if [[ -z "${TELEGRAM_BOT_TOKEN}" ]]; then
    echo "{\"ok\":false,\"error\":\"TELEGRAM_BOT_TOKEN is not set\",\"script\":\"$SCRIPT_NAME\"}"
    exit 1
fi

if ! [[ "$RETRY_COUNT" =~ ^[0-9]+$ ]]; then
    echo "{\"ok\":false,\"error\":\"--retry must be a non-negative integer\",\"script\":\"$SCRIPT_NAME\"}"
    exit 2
fi

api_url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument"
attempt=0
max_attempts=$((RETRY_COUNT + 1))

while [[ "$attempt" -lt "$max_attempts" ]]; do
    attempt=$((attempt + 1))
    response="$(curl -sS --max-time "$TELEGRAM_TIMEOUT_SECONDS" \
        -X POST \
        -F "chat_id=$CHAT_ID" \
        -F "document=@${FILE_PATH}" \
        -F "caption=${CAPTION}" \
        -F "disable_notification=${DISABLE_NOTIFICATION}" \
        "$api_url" || true)"

    ok="$(printf '%s' "$response" | jq -r '.ok // false' 2>/dev/null || echo "false")"
    if [[ "$ok" == "true" ]]; then
        printf '%s\n' "$response"
        exit 0
    fi

    if [[ "$attempt" -lt "$max_attempts" ]]; then
        sleep 1
    fi
done

jq -cn \
  --arg script "$SCRIPT_NAME" \
  --arg chat_id "$CHAT_ID" \
  --arg file_path "$FILE_PATH" \
  --arg response "${response:-}" \
  --argjson attempts "$attempt" \
  '{ok:false,script:$script,chat_id:$chat_id,file_path:$file_path,attempts:$attempts,error:"sendDocument failed",response:$response}'
exit 1
