#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${MOLTIS_TELEGRAM_SAFE_LLM_GUARD_SCRIPT:-/server/scripts/telegram-safe-llm-guard.sh}"
export MOLTIS_TELEGRAM_SAFE_LLM_GUARD_AUDIT_FILE="${MOLTIS_TELEGRAM_SAFE_LLM_GUARD_AUDIT_FILE:-/tmp/moltis-telegram-safe-llm-guard.audit.log}"
CAPTURE_DIR="${MOLTIS_TELEGRAM_SAFE_LLM_GUARD_CAPTURE_DIR:-/tmp/moltis-telegram-safe-llm-guard-capture}"

if [[ ! -x "$SCRIPT_PATH" ]]; then
    printf 'telegram-safe-llm-guard bundle handler error: missing executable script at %s\n' "$SCRIPT_PATH" >&2
    exit 1
fi

payload="$(cat)"

capture_stub=""
if [[ -n "$CAPTURE_DIR" ]]; then
    mkdir -p "$CAPTURE_DIR" 2>/dev/null || true
    capture_stub="${CAPTURE_DIR}/$(date -u +%Y%m%dT%H%M%SZ)-$$"
    printf '%s' "$payload" > "${capture_stub}.payload.json" 2>/dev/null || true
fi

output="$(printf '%s' "$payload" | "$SCRIPT_PATH" "$@")"

if [[ -n "$capture_stub" ]]; then
    printf '%s' "$output" > "${capture_stub}.output.json" 2>/dev/null || true
fi

printf '%s' "$output"
