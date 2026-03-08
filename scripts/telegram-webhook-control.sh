#!/usr/bin/env bash
# telegram-webhook-control.sh - Manage Telegram bot webhook directly via Bot API.

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
MOLTIS_ENV_FILE="${MOLTIS_ENV_FILE:-.env}"
TELEGRAM_TIMEOUT_SECONDS="${TELEGRAM_TIMEOUT_SECONDS:-20}"

show_help() {
    cat <<'EOF'
Usage:
  telegram-webhook-control.sh <command> [options]

Commands:
  webhook-info
      Show current webhook status.

  webhook-set --url URL [--secret SECRET] [--drop-pending true|false] [--allowed-updates list]
      Configure webhook URL.
      --allowed-updates: comma-separated, e.g. "message,edited_message,callback_query"

  webhook-delete [--drop-pending true|false]
      Remove webhook and return to getUpdates mode.

  get-me
      Validate bot token and show bot identity.

Environment:
  TELEGRAM_BOT_TOKEN           Required if --token is not passed.
  MOLTIS_ENV_FILE              Optional env file path (default: .env)
  TELEGRAM_TIMEOUT_SECONDS     API timeout in seconds (default: 20)

Global options:
  --token TOKEN                Override TELEGRAM_BOT_TOKEN
  --json                       Force JSON-only output (default behavior)
  -h, --help                   Show help
EOF
}

require_bin() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "{\"ok\":false,\"error\":\"Missing dependency: $1\"}"
        exit 1
    }
}

bool_to_json() {
    case "${1:-}" in
        true|TRUE|1|yes|YES|on|ON) echo "true" ;;
        false|FALSE|0|no|NO|off|OFF) echo "false" ;;
        *)
            echo "{\"ok\":false,\"error\":\"Invalid boolean value: ${1}. Use true|false\"}"
            exit 2
            ;;
    esac
}

telegram_api_get() {
    local method="$1"
    curl -sS --max-time "$TELEGRAM_TIMEOUT_SECONDS" \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/${method}"
}

telegram_api_post_json() {
    local method="$1"
    local payload="$2"
    curl -sS --max-time "$TELEGRAM_TIMEOUT_SECONDS" \
        -X POST \
        -H "content-type: application/json" \
        -d "$payload" \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/${method}"
}

require_bin curl
require_bin jq

if [[ -f "$MOLTIS_ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$MOLTIS_ENV_FILE"
    set +a
fi

if [[ $# -lt 1 ]]; then
    show_help
    exit 2
fi

TOKEN_OVERRIDE=""
COMMAND=""
declare -a ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
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
        webhook-info|webhook-set|webhook-delete|get-me)
            COMMAND="$1"
            shift
            ARGS=("$@")
            break
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

case "$COMMAND" in
    get-me)
        telegram_api_get "getMe"
        ;;

    webhook-info)
        telegram_api_get "getWebhookInfo"
        ;;

    webhook-delete)
        DROP_PENDING="false"
        while [[ ${#ARGS[@]} -gt 0 ]]; do
            case "${ARGS[0]}" in
                --drop-pending)
                    DROP_PENDING="${ARGS[1]:-}"
                    ARGS=("${ARGS[@]:2}")
                    ;;
                *)
                    echo "{\"ok\":false,\"error\":\"Unknown option for webhook-delete: ${ARGS[0]}\"}"
                    exit 2
                    ;;
            esac
        done
        DROP_PENDING_JSON="$(bool_to_json "$DROP_PENDING")"
        payload="$(jq -cn --argjson drop_pending_updates "$DROP_PENDING_JSON" '{drop_pending_updates: $drop_pending_updates}')"
        telegram_api_post_json "deleteWebhook" "$payload"
        ;;

    webhook-set)
        URL=""
        SECRET=""
        DROP_PENDING="false"
        ALLOWED_UPDATES=""

        while [[ ${#ARGS[@]} -gt 0 ]]; do
            case "${ARGS[0]}" in
                --url)
                    URL="${ARGS[1]:-}"
                    ARGS=("${ARGS[@]:2}")
                    ;;
                --secret)
                    SECRET="${ARGS[1]:-}"
                    ARGS=("${ARGS[@]:2}")
                    ;;
                --drop-pending)
                    DROP_PENDING="${ARGS[1]:-}"
                    ARGS=("${ARGS[@]:2}")
                    ;;
                --allowed-updates)
                    ALLOWED_UPDATES="${ARGS[1]:-}"
                    ARGS=("${ARGS[@]:2}")
                    ;;
                *)
                    echo "{\"ok\":false,\"error\":\"Unknown option for webhook-set: ${ARGS[0]}\"}"
                    exit 2
                    ;;
            esac
        done

        if [[ -z "$URL" ]]; then
            echo "{\"ok\":false,\"error\":\"--url is required for webhook-set\"}"
            exit 2
        fi

        DROP_PENDING_JSON="$(bool_to_json "$DROP_PENDING")"

        payload="$(jq -cn \
            --arg url "$URL" \
            --arg secret_token "$SECRET" \
            --argjson drop_pending_updates "$DROP_PENDING_JSON" \
            '{
                url: $url,
                drop_pending_updates: $drop_pending_updates
            } + (if ($secret_token | length) > 0 then {secret_token: $secret_token} else {} end)
            ')"

        if [[ -n "$ALLOWED_UPDATES" ]]; then
            updates_json="$(printf '%s' "$ALLOWED_UPDATES" | awk -F',' '
                BEGIN { printf("["); }
                {
                    for (i = 1; i <= NF; i++) {
                        gsub(/^ +| +$/, "", $i);
                        if ($i != "") {
                            if (count > 0) printf(",");
                            printf("\"%s\"", $i);
                            count++;
                        }
                    }
                }
                END { printf("]"); }
            ')"
            payload="$(jq -cn --argjson base "$payload" --argjson allowed_updates "$updates_json" '$base + {allowed_updates: $allowed_updates}')"
        fi

        telegram_api_post_json "setWebhook" "$payload"
        ;;

    *)
        echo "{\"ok\":false,\"error\":\"Unknown command: ${COMMAND}\",\"script\":\"$SCRIPT_NAME\"}"
        exit 2
        ;;
esac
