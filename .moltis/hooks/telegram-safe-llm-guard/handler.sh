#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${MOLTIS_TELEGRAM_SAFE_LLM_GUARD_SCRIPT:-/server/scripts/telegram-safe-llm-guard.sh}"
export MOLTIS_TELEGRAM_SAFE_LLM_GUARD_AUDIT_FILE="${MOLTIS_TELEGRAM_SAFE_LLM_GUARD_AUDIT_FILE:-/tmp/moltis-telegram-safe-llm-guard.audit.log}"

if [[ ! -x "$SCRIPT_PATH" ]]; then
    printf 'telegram-safe-llm-guard bundle handler error: missing executable script at %s\n' "$SCRIPT_PATH" >&2
    exit 1
fi

exec "$SCRIPT_PATH" "$@"
