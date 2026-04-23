#!/usr/bin/env bash
# telegram-bot-send.sh - Send Telegram message via Bot API from CLI.

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
MOLTIS_ENV_FILE="${MOLTIS_ENV_FILE:-}"
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
  MOLTIS_ENV_FILE             Optional explicit env file path
  TELEGRAM_TIMEOUT_SECONDS    API timeout in seconds (default: 20)
EOF
}

require_bin() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "{\"ok\":false,\"error\":\"Missing dependency: $1\",\"script\":\"$SCRIPT_NAME\"}"
        exit 1
    }
}

json_escape() {
    printf '%s' "$1" | awk '
        BEGIN { ORS = "" }
        {
            gsub(/\\/, "\\\\")
            gsub(/"/, "\\\"")
            gsub(/\t/, "\\t")
            gsub(/\r/, "\\r")
            if (NR > 1) {
                printf "\\n"
            }
            printf "%s", $0
        }
    '
}

has_working_jq() {
    command -v jq >/dev/null 2>&1 || return 1
    jq -nc '{}' >/dev/null 2>&1
}

validate_reply_markup_json() {
    local value="${1:-}"
    local compact=""

    if [[ -z "$value" ]]; then
        return 0
    fi

    if has_working_jq; then
        jq -e 'type == "object"' >/dev/null 2>&1 <<<"$value"
        return $?
    fi

    compact="$(
        printf '%s' "$value" \
            | tr '\r\n' '  ' \
            | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
    )"
    [[ "$compact" == \{*\} ]]
}

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

require_bin curl

if [[ -z "${TOKEN_OVERRIDE:-}" && -z "${TELEGRAM_BOT_TOKEN:-}" && -n "${MOLTIS_ENV_FILE:-}" && -f "$MOLTIS_ENV_FILE" ]]; then
    if [[ -r "$MOLTIS_ENV_FILE" ]]; then
        set -a
        # shellcheck disable=SC1090
        source "$MOLTIS_ENV_FILE"
        set +a
    else
        echo "{\"ok\":false,\"error\":\"Environment file is not readable: $MOLTIS_ENV_FILE\",\"script\":\"$SCRIPT_NAME\"}"
        exit 1
    fi
fi

TELEGRAM_BOT_TOKEN="${TOKEN_OVERRIDE:-${TELEGRAM_BOT_TOKEN:-}}"
if [[ -z "${TELEGRAM_BOT_TOKEN}" ]]; then
    echo "{\"ok\":false,\"error\":\"TELEGRAM_BOT_TOKEN is not set\",\"script\":\"$SCRIPT_NAME\"}"
    exit 1
fi

if [[ -z "$CHAT_ID" || -z "$TEXT" ]]; then
    echo "{\"ok\":false,\"error\":\"--chat-id and --text are required\",\"script\":\"$SCRIPT_NAME\"}"
    exit 2
fi

if [[ -n "$REPLY_MARKUP_JSON" ]] && ! validate_reply_markup_json "$REPLY_MARKUP_JSON"; then
    echo "{\"ok\":false,\"error\":\"--reply-markup-json must be a JSON object\",\"script\":\"$SCRIPT_NAME\"}"
    exit 2
fi

if [[ -n "$REPLY_TO" && ! "$REPLY_TO" =~ ^-?[0-9]+$ ]]; then
    echo "{\"ok\":false,\"error\":\"--reply-to must be numeric\",\"script\":\"$SCRIPT_NAME\"}"
    exit 2
fi

payload="{"
payload+="\"chat_id\":\"$(json_escape "$CHAT_ID")\""
payload+=",\"text\":\"$(json_escape "$TEXT")\""
payload+=",\"disable_notification\":$DISABLE_NOTIFICATION"
if [[ -n "$PARSE_MODE" ]]; then
    payload+=",\"parse_mode\":\"$(json_escape "$PARSE_MODE")\""
fi
if [[ -n "$REPLY_TO" ]]; then
    payload+=",\"reply_to_message_id\":$REPLY_TO"
fi
if [[ -n "$REPLY_MARKUP_JSON" ]]; then
    payload+=",\"reply_markup\":$REPLY_MARKUP_JSON"
fi
payload+="}"

api_url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
response="$(
    printf 'url = "%s"\n' "$api_url" \
        | curl -sS --max-time "$TELEGRAM_TIMEOUT_SECONDS" \
            -X POST \
            -H "content-type: application/json" \
            -d "$payload" \
            --config -
)"

printf '%s\n' "$response"
if printf '%s' "$response" | grep -Eq '"ok"[[:space:]]*:[[:space:]]*true'; then
    exit 0
fi

exit 1
