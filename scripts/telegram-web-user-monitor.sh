#!/usr/bin/env bash
# telegram-web-user-monitor.sh - Wrapper for Telegram Web user probe (no API_HASH).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${MOLTIS_ENV_FILE:-.env}"

TELEGRAM_WEB_STATE="${TELEGRAM_WEB_STATE:-/opt/moltinger/data/.telegram-web-state.json}"
TELEGRAM_WEB_TARGET="${TELEGRAM_WEB_TARGET:-@moltinger_bot}"
TELEGRAM_WEB_PROBE_PROFILE="${TELEGRAM_WEB_PROBE_PROFILE:-strict_status}"
TELEGRAM_WEB_MESSAGE="${TELEGRAM_WEB_MESSAGE:-}"
TELEGRAM_WEB_TIMEOUT_SECONDS="${TELEGRAM_WEB_TIMEOUT_SECONDS:-45}"
TELEGRAM_WEB_MIN_REPLY_LEN="${TELEGRAM_WEB_MIN_REPLY_LEN:-2}"
TELEGRAM_WEB_COMPOSER_RETRIES="${TELEGRAM_WEB_COMPOSER_RETRIES:-2}"

if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
fi

PROBE_TEXT=""
case "${TELEGRAM_WEB_PROBE_PROFILE}" in
    strict_status)
        PROBE_TEXT="${TELEGRAM_WEB_MESSAGE:-/status}"
        ;;
    echo_ping)
        PROBE_TEXT="${TELEGRAM_WEB_MESSAGE:-test2}"
        ;;
    *)
        echo "{\"ok\":false,\"status\":\"fail\",\"error\":\"Unknown TELEGRAM_WEB_PROBE_PROFILE\",\"profile\":\"${TELEGRAM_WEB_PROBE_PROFILE}\"}"
        exit 2
        ;;
esac

exec node "${SCRIPT_DIR}/telegram-web-user-probe.mjs" \
    --state "${TELEGRAM_WEB_STATE}" \
    --target "${TELEGRAM_WEB_TARGET}" \
    --text "${PROBE_TEXT}" \
    --timeout "${TELEGRAM_WEB_TIMEOUT_SECONDS}" \
    --min-reply-len "${TELEGRAM_WEB_MIN_REPLY_LEN}" \
    --composer-retries "${TELEGRAM_WEB_COMPOSER_RETRIES}"
