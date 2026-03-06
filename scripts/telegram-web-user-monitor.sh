#!/usr/bin/env bash
# telegram-web-user-monitor.sh - Wrapper for Telegram Web user probe (no API_HASH).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${MOLTIS_ENV_FILE:-.env}"

TELEGRAM_WEB_STATE="${TELEGRAM_WEB_STATE:-/opt/moltinger/data/.telegram-web-state.json}"
TELEGRAM_WEB_TARGET="${TELEGRAM_WEB_TARGET:-@moltinger_bot}"
TELEGRAM_WEB_MESSAGE="${TELEGRAM_WEB_MESSAGE:-/status}"
TELEGRAM_WEB_TIMEOUT_SECONDS="${TELEGRAM_WEB_TIMEOUT_SECONDS:-45}"
TELEGRAM_WEB_MIN_REPLY_LEN="${TELEGRAM_WEB_MIN_REPLY_LEN:-2}"

if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
fi

exec node "${SCRIPT_DIR}/telegram-web-user-probe.mjs" \
    --state "${TELEGRAM_WEB_STATE}" \
    --target "${TELEGRAM_WEB_TARGET}" \
    --text "${TELEGRAM_WEB_MESSAGE}" \
    --timeout "${TELEGRAM_WEB_TIMEOUT_SECONDS}" \
    --min-reply-len "${TELEGRAM_WEB_MIN_REPLY_LEN}"
