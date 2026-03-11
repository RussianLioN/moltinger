#!/usr/bin/env bash
# telegram-bot-send-remote.sh - Send Telegram message by delegating to the Moltinger server runtime.

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SSH_BIN="${MOLTINGER_TELEGRAM_SSH_BIN:-ssh}"
SSH_TARGET="${MOLTINGER_TELEGRAM_SSH_TARGET:-root@ainetic.tech}"
SSH_CONNECT_TIMEOUT="${MOLTINGER_TELEGRAM_SSH_CONNECT_TIMEOUT:-20}"
REMOTE_ROOT="${MOLTINGER_TELEGRAM_REMOTE_ROOT:-/opt/moltinger}"
REMOTE_ENV_FILE="${MOLTINGER_TELEGRAM_REMOTE_ENV_FILE:-/opt/moltinger/.env}"

show_help() {
    cat <<'EOF'
Usage:
  telegram-bot-send-remote.sh --chat-id CHAT --text "message" [options]

Required:
  --chat-id CHAT_ID           Target Telegram chat id
  --text MESSAGE              Message text

Optional:
  --parse-mode MODE           MarkdownV2 | HTML
  --disable-notification      Send silently
  --reply-to MESSAGE_ID       Reply to a specific message
  --reply-markup-json JSON    Raw Telegram reply_markup JSON object
  --json                      JSON output (default)
  -h, --help                  Show help

Environment:
  MOLTINGER_TELEGRAM_SSH_BIN              SSH client binary (default: ssh)
  MOLTINGER_TELEGRAM_SSH_TARGET           SSH target (default: root@ainetic.tech)
  MOLTINGER_TELEGRAM_SSH_CONNECT_TIMEOUT  SSH connect timeout seconds (default: 20)
  MOLTINGER_TELEGRAM_REMOTE_ROOT          Remote repo root (default: /opt/moltinger)
  MOLTINGER_TELEGRAM_REMOTE_ENV_FILE      Remote env file with TELEGRAM_BOT_TOKEN
EOF
}

CHAT_ID=""
TEXT=""
PARSE_MODE=""
DISABLE_NOTIFICATION=false
REPLY_TO=""
REPLY_MARKUP_JSON=""

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
            DISABLE_NOTIFICATION=true
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

if [[ -z "$CHAT_ID" || -z "$TEXT" ]]; then
    echo "{\"ok\":false,\"error\":\"--chat-id and --text are required\",\"script\":\"$SCRIPT_NAME\"}"
    exit 2
fi

payload_b64="$(
    jq -cn \
        --arg remote_root "$REMOTE_ROOT" \
        --arg remote_env_file "$REMOTE_ENV_FILE" \
        --arg chat_id "$CHAT_ID" \
        --arg text "$TEXT" \
        --arg parse_mode "$PARSE_MODE" \
        --argjson disable_notification "$DISABLE_NOTIFICATION" \
        --arg reply_to "$REPLY_TO" \
        --arg reply_markup_json "$REPLY_MARKUP_JSON" \
        '{
            remote_root: $remote_root,
            remote_env_file: $remote_env_file,
            chat_id: $chat_id,
            text: $text,
            parse_mode: $parse_mode,
            disable_notification: $disable_notification,
            reply_to: $reply_to,
            reply_markup_json: $reply_markup_json
        }' | base64 | tr -d '\n'
)"

"$SSH_BIN" -o BatchMode=yes -o ConnectTimeout="$SSH_CONNECT_TIMEOUT" "$SSH_TARGET" /bin/bash -s -- \
    "$payload_b64" <<'EOF'
set -euo pipefail

payload_json="$(printf '%s' "$1" | base64 --decode)"
remote_root="$(jq -r '.remote_root' <<<"$payload_json")"
remote_env_file="$(jq -r '.remote_env_file' <<<"$payload_json")"
chat_id="$(jq -r '.chat_id' <<<"$payload_json")"
text="$(jq -r '.text' <<<"$payload_json")"
parse_mode="$(jq -r '.parse_mode' <<<"$payload_json")"
disable_notification="$(jq -r '.disable_notification' <<<"$payload_json")"
reply_to="$(jq -r '.reply_to' <<<"$payload_json")"
reply_markup_json="$(jq -r '.reply_markup_json' <<<"$payload_json")"

cd "$remote_root"

cmd=(
  ./scripts/telegram-bot-send.sh
  --chat-id "$chat_id"
  --text "$text"
  --json
)

if [[ -n "$parse_mode" ]]; then
  cmd+=(--parse-mode "$parse_mode")
fi

if [[ "$disable_notification" == "true" ]]; then
  cmd+=(--disable-notification)
fi

if [[ -n "$reply_to" ]]; then
  cmd+=(--reply-to "$reply_to")
fi

if [[ -n "$reply_markup_json" ]]; then
  cmd+=(--reply-markup-json "$reply_markup_json")
fi

MOLTIS_ENV_FILE="$remote_env_file" "${cmd[@]}"
EOF
