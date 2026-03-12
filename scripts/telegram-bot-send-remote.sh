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

strip_wrapping_quotes() {
  local value="${1:-}"
  if [[ "$value" == \"*\" && "$value" == *\" ]]; then
    value="${value#\"}"
    value="${value%\"}"
  fi
  if [[ "$value" == \'*\' && "$value" == *\' ]]; then
    value="${value#\'}"
    value="${value%\'}"
  fi
  printf '%s\n' "$value"
}

read_env_value() {
  local env_file="$1"
  local key="$2"
  local value=""

  [[ -f "$env_file" ]] || return 1
  value="$(sed -n "s/^${key}=//p" "$env_file" | head -n 1)"
  [[ -n "$value" ]] || return 1
  strip_wrapping_quotes "$value"
}

resolve_telegram_token() {
  local configured=""

  if [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]]; then
    printf '%s\n' "${TELEGRAM_BOT_TOKEN}"
    return 0
  fi

  configured="$(read_env_value "$remote_env_file" "TELEGRAM_BOT_TOKEN" || true)"
  if [[ -n "$configured" ]]; then
    printf '%s\n' "$configured"
    return 0
  fi

  return 1
}

send_via_remote_script() {
  local sender="$remote_root/scripts/telegram-bot-send.sh"
  local help_output=""
  local cmd=()

  [[ -x "$sender" ]] || return 11

  if [[ -n "$reply_markup_json" ]]; then
    help_output="$("$sender" --help 2>&1 || true)"
    if [[ "$help_output" != *"--reply-markup-json"* ]]; then
      return 10
    fi
  fi

  cmd=(
    "$sender"
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
}

send_via_direct_api() {
  local token payload

  token="$(resolve_telegram_token)" || {
    echo '{"ok":false,"error":"TELEGRAM_BOT_TOKEN is not set on remote host","script":"telegram-bot-send-remote.sh"}'
    return 1
  }

  if [[ -n "$reply_markup_json" ]] && ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$reply_markup_json"; then
    echo '{"ok":false,"error":"--reply-markup-json must be a JSON object","script":"telegram-bot-send-remote.sh"}'
    return 2
  fi

  payload="$(
    jq -cn \
      --arg chat_id "$chat_id" \
      --arg text "$text" \
      --arg parse_mode "$parse_mode" \
      --argjson disable_notification "$disable_notification" \
      --arg reply_to_message_id "$reply_to" \
      --arg reply_markup_json "$reply_markup_json" \
      '{
          chat_id: $chat_id,
          text: $text,
          disable_notification: $disable_notification
      }
      + (if ($parse_mode|length) > 0 then {parse_mode: $parse_mode} else {} end)
      + (if ($reply_to_message_id|length) > 0 then {reply_to_message_id: ($reply_to_message_id|tonumber)} else {} end)
      + (if ($reply_markup_json|length) > 0 then {reply_markup: ($reply_markup_json|fromjson)} else {} end)'
  )"

  curl -sS --max-time "${TELEGRAM_TIMEOUT_SECONDS:-20}" \
    -X POST \
    -H "content-type: application/json" \
    -d "$payload" \
    "https://api.telegram.org/bot${token}/sendMessage"
}

cd "$remote_root"

set +e
remote_output="$(send_via_remote_script 2>&1)"
remote_status=$?
set -e

if [[ $remote_status -eq 0 ]]; then
  printf '%s\n' "$remote_output"
  exit 0
fi

if [[ $remote_status -ne 10 && $remote_status -ne 11 ]]; then
  printf '%s\n' "$remote_output"
  exit "$remote_status"
fi

send_via_direct_api
EOF
