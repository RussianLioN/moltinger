#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${MOLTIS_TELEGRAM_SAFE_LLM_GUARD_SCRIPT:-/server/scripts/telegram-safe-llm-guard.sh}"

if [[ ! -x "$SCRIPT_PATH" ]]; then
    printf 'telegram-safe-llm-guard bundle handler error: missing executable script at %s\n' "$SCRIPT_PATH" >&2
    exit 1
fi

exec "$SCRIPT_PATH" "$@"
