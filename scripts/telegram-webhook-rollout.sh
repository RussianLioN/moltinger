#!/bin/bash
# Controlled Telegram webhook rollout helper.
# Usage:
#   ./scripts/telegram-webhook-rollout.sh status
#   ./scripts/telegram-webhook-rollout.sh enable
#   ./scripts/telegram-webhook-rollout.sh verify
#   ./scripts/telegram-webhook-rollout.sh disable

set -euo pipefail

TELEGRAM_API_BASE="${TELEGRAM_API_BASE:-https://api.telegram.org/bot}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_WEBHOOK_URL="${TELEGRAM_WEBHOOK_URL:-}"
TELEGRAM_WEBHOOK_SECRET="${TELEGRAM_WEBHOOK_SECRET:-}"
TELEGRAM_PENDING_MAX="${TELEGRAM_PENDING_MAX:-10}"
TELEGRAM_PROBE_TIMEOUT="${TELEGRAM_PROBE_TIMEOUT:-10}"
TELEGRAM_DROP_PENDING_UPDATES="${TELEGRAM_DROP_PENDING_UPDATES:-true}"
TELEGRAM_EXPECT_EMPTY_LAST_ERROR="${TELEGRAM_EXPECT_EMPTY_LAST_ERROR:-true}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

usage() {
    cat <<'EOF'
Controlled Telegram webhook rollout helper

Commands:
  status   - Show bot identity + webhook state
  enable   - Configure Telegram webhook to TELEGRAM_WEBHOOK_URL
  verify   - Verify webhook contract and probe endpoint for redirect regressions
  disable  - Delete webhook and verify polling baseline

Environment variables:
  TELEGRAM_BOT_TOKEN                 (required for all commands)
  TELEGRAM_WEBHOOK_URL               (required for enable/verify)
  TELEGRAM_WEBHOOK_SECRET            (optional, recommended)
  TELEGRAM_PENDING_MAX               (optional, default: 10)
  TELEGRAM_PROBE_TIMEOUT             (optional, default: 10)
  TELEGRAM_DROP_PENDING_UPDATES      (optional, default: true)
  TELEGRAM_EXPECT_EMPTY_LAST_ERROR   (optional, default: true)

Example:
  TELEGRAM_BOT_TOKEN=... \
  TELEGRAM_WEBHOOK_URL=https://moltis.ainetic.tech/telegram/webhook \
  TELEGRAM_WEBHOOK_SECRET=... \
  ./scripts/telegram-webhook-rollout.sh enable
EOF
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        log_error "Missing required command: $1"
        exit 1
    fi
}

require_token() {
    if [[ -z "$TELEGRAM_BOT_TOKEN" ]]; then
        log_error "TELEGRAM_BOT_TOKEN is empty"
        exit 1
    fi
}

require_webhook_url() {
    if [[ -z "$TELEGRAM_WEBHOOK_URL" ]]; then
        log_error "TELEGRAM_WEBHOOK_URL is empty"
        exit 1
    fi
    if [[ ! "$TELEGRAM_WEBHOOK_URL" =~ ^https:// ]]; then
        log_error "TELEGRAM_WEBHOOK_URL must use https://"
        exit 1
    fi
}

telegram_api() {
    local method="$1"
    local data="${2:-}"
    local url="${TELEGRAM_API_BASE}${TELEGRAM_BOT_TOKEN}/${method}"

    if [[ -n "$data" ]]; then
        curl -sS --fail-with-body -X POST "$url" \
            -H "Content-Type: application/json" \
            -d "$data"
    else
        curl -sS --fail-with-body "$url"
    fi
}

get_me() {
    telegram_api "getMe"
}

get_webhook_info() {
    telegram_api "getWebhookInfo"
}

check_api_ok() {
    local response="$1"
    local ok
    ok="$(echo "$response" | jq -r '.ok // false')"
    if [[ "$ok" != "true" ]]; then
        echo "$response" | jq .
        return 1
    fi
    return 0
}

status() {
    local me_response
    local webhook_response
    me_response="$(get_me)"
    webhook_response="$(get_webhook_info)"

    if ! check_api_ok "$me_response"; then
        log_error "Telegram getMe failed"
        exit 1
    fi
    if ! check_api_ok "$webhook_response"; then
        log_error "Telegram getWebhookInfo failed"
        exit 1
    fi

    local username
    local bot_id
    username="$(echo "$me_response" | jq -r '.result.username // ""')"
    bot_id="$(echo "$me_response" | jq -r '.result.id // ""')"

    local url
    local pending
    local last_error
    local last_error_date
    url="$(echo "$webhook_response" | jq -r '.result.url // ""')"
    pending="$(echo "$webhook_response" | jq -r '.result.pending_update_count // 0')"
    last_error="$(echo "$webhook_response" | jq -r '.result.last_error_message // ""')"
    last_error_date="$(echo "$webhook_response" | jq -r '.result.last_error_date // 0')"

    log_info "Bot: @$username (id=$bot_id)"
    if [[ -n "$url" ]]; then
        log_info "Mode: webhook"
        log_info "Webhook URL: $url"
    else
        log_info "Mode: polling (no webhook URL configured)"
    fi
    log_info "Pending updates: $pending"

    if [[ -n "$last_error" ]]; then
        log_warn "Last webhook error: $last_error (date epoch: $last_error_date)"
    else
        log_success "Last webhook error: none"
    fi
}

enable() {
    require_webhook_url

    local payload
    if [[ -n "$TELEGRAM_WEBHOOK_SECRET" ]]; then
        payload="$(jq -cn \
          --arg url "$TELEGRAM_WEBHOOK_URL" \
          --arg secret "$TELEGRAM_WEBHOOK_SECRET" \
          --argjson drop "$TELEGRAM_DROP_PENDING_UPDATES" \
          '{url:$url, secret_token:$secret, drop_pending_updates:$drop}')"
    else
        payload="$(jq -cn \
          --arg url "$TELEGRAM_WEBHOOK_URL" \
          --argjson drop "$TELEGRAM_DROP_PENDING_UPDATES" \
          '{url:$url, drop_pending_updates:$drop}')"
    fi

    local response
    response="$(telegram_api "setWebhook" "$payload")"
    if ! check_api_ok "$response"; then
        log_error "setWebhook failed"
        exit 1
    fi

    log_success "Webhook configured"
    verify
}

disable() {
    local payload
    payload="$(jq -cn --argjson drop "$TELEGRAM_DROP_PENDING_UPDATES" '{drop_pending_updates:$drop}')"

    local response
    response="$(telegram_api "deleteWebhook" "$payload")"
    if ! check_api_ok "$response"; then
        log_error "deleteWebhook failed"
        exit 1
    fi

    local webhook_response
    webhook_response="$(get_webhook_info)"
    if ! check_api_ok "$webhook_response"; then
        log_error "getWebhookInfo failed after deleteWebhook"
        exit 1
    fi

    local url
    url="$(echo "$webhook_response" | jq -r '.result.url // ""')"
    if [[ -n "$url" ]]; then
        log_error "Webhook URL still present after disable: $url"
        exit 1
    fi

    log_success "Webhook disabled; polling baseline restored"
}

probe_webhook_endpoint() {
    require_webhook_url

    local probe_body
    local epoch
    local http_code
    local response_file
    response_file="$(mktemp)"
    epoch="$(date +%s)"
    probe_body="$(jq -cn \
      --argjson now "$epoch" \
      '{update_id:999999999,message:{message_id:1,date:$now,chat:{id:123456789,type:"private"},from:{id:123456789,is_bot:false,first_name:"Webhook",username:"webhook_probe"},text:"/status"}}')"

    local curl_args=(
        -sS
        --max-time "$TELEGRAM_PROBE_TIMEOUT"
        -o "$response_file"
        -w "%{http_code}"
        -X POST
        "$TELEGRAM_WEBHOOK_URL"
        -H "Content-Type: application/json"
        --data "$probe_body"
    )

    if [[ -n "$TELEGRAM_WEBHOOK_SECRET" ]]; then
        curl_args+=(-H "X-Telegram-Bot-Api-Secret-Token: $TELEGRAM_WEBHOOK_SECRET")
    fi

    http_code="$(curl "${curl_args[@]}")"

    local response_preview
    response_preview="$(head -c 300 "$response_file" | tr '\n' ' ')"
    rm -f "$response_file"

    if [[ "$http_code" =~ ^3 ]]; then
        log_error "Webhook endpoint returns redirect ($http_code). This usually breaks Telegram delivery."
        exit 1
    fi
    if [[ "$http_code" =~ ^5 ]]; then
        log_error "Webhook endpoint returned server error ($http_code)"
        exit 1
    fi

    case "$http_code" in
        200|202|204|400|401|403|405)
            log_success "Webhook probe HTTP status: $http_code"
            ;;
        *)
            log_error "Unexpected webhook probe status: $http_code"
            log_info "Response preview: ${response_preview:-<empty>}"
            exit 1
            ;;
    esac
}

verify() {
    require_webhook_url

    local webhook_response
    webhook_response="$(get_webhook_info)"

    if ! check_api_ok "$webhook_response"; then
        log_error "getWebhookInfo failed"
        exit 1
    fi

    local configured_url
    local pending
    local last_error
    configured_url="$(echo "$webhook_response" | jq -r '.result.url // ""')"
    pending="$(echo "$webhook_response" | jq -r '.result.pending_update_count // 0')"
    last_error="$(echo "$webhook_response" | jq -r '.result.last_error_message // ""')"

    if [[ "$configured_url" != "$TELEGRAM_WEBHOOK_URL" ]]; then
        log_error "Configured webhook URL mismatch"
        log_info "Expected: $TELEGRAM_WEBHOOK_URL"
        log_info "Actual:   $configured_url"
        exit 1
    fi

    if [[ "$pending" -gt "$TELEGRAM_PENDING_MAX" ]]; then
        log_error "Pending updates too high: $pending > $TELEGRAM_PENDING_MAX"
        exit 1
    fi

    if [[ "$TELEGRAM_EXPECT_EMPTY_LAST_ERROR" == "true" ]] && [[ -n "$last_error" ]]; then
        log_error "Telegram reports last webhook error: $last_error"
        exit 1
    fi

    probe_webhook_endpoint
    log_success "Webhook verification passed"
}

main() {
    require_command curl
    require_command jq

    local command="${1:-}"
    case "$command" in
        -h|--help|help|"")
            usage
            ;;
        status)
            require_token
            status
            ;;
        enable)
            require_token
            enable
            ;;
        verify)
            require_token
            verify
            ;;
        disable)
            require_token
            disable
            ;;
        *)
            log_error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

main "$@"
