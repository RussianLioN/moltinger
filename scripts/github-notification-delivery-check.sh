#!/usr/bin/env bash
set -euo pipefail

NOTIFICATION_SCOPE="${NOTIFICATION_SCOPE:-notification}"
EMAIL_ENABLED="${EMAIL_ENABLED:-false}"
TELEGRAM_ENABLED="${TELEGRAM_ENABLED:-false}"
EMAIL_OUTCOME="${EMAIL_OUTCOME:-skipped}"
TELEGRAM_OUTCOME="${TELEGRAM_OUTCOME:-skipped}"

configured_channels=0
successful_channels=0

if [[ "$EMAIL_ENABLED" == "true" ]]; then
    configured_channels=$((configured_channels + 1))
    [[ "$EMAIL_OUTCOME" == "success" ]] && successful_channels=$((successful_channels + 1))
fi

if [[ "$TELEGRAM_ENABLED" == "true" ]]; then
    configured_channels=$((configured_channels + 1))
    [[ "$TELEGRAM_OUTCOME" == "success" ]] && successful_channels=$((successful_channels + 1))
fi

if (( configured_channels > 0 && successful_channels == 0 )); then
    printf '::error::All configured %s notification channels failed\n' "$NOTIFICATION_SCOPE"
    exit 1
fi
