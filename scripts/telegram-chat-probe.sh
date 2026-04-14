#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE_SCRIPT="$SCRIPT_DIR/telegram-user-probe.py"

message=""
target="${TELEGRAM_TEST_BOT_USERNAME:-@moltinger_bot}"
timeout_sec=45
json_out=""
verbose=false

usage() {
    cat <<'EOF'
Usage: telegram-chat-probe.sh --message <text> [--target <chat>] [--timeout-sec <seconds>] [--json-out <path>] [--verbose]

Thin compatibility wrapper around scripts/telegram-user-probe.py for skill-driven Telegram real_user probes.
EOF
}

log() {
    if [[ "$verbose" == "true" ]]; then
        printf '[telegram-chat-probe] %s\n' "$*" >&2
    fi
}

next_action_for_status() {
    local status="${1:-}"

    case "$status" in
        completed)
            printf 'none'
            ;;
        timeout)
            printf 'Увеличить timeout или проверить, отвечает ли бот на этот prompt вручную.'
            ;;
        precondition_failed)
            printf 'Проверить TELEGRAM_TEST_API_ID, TELEGRAM_TEST_API_HASH и TELEGRAM_TEST_SESSION.'
            ;;
        upstream_failed)
            printf 'Проверить Telegram session validity, target и stderr probe helper-а.'
            ;;
        *)
            printf 'Проверить raw JSON ответа helper-а и stderr обёртки.'
            ;;
    esac
}

emit_result() {
    local status="$1"
    local observed_reply="$2"
    local result_json=""

    result_json="$(jq -cn \
        --arg target "$target" \
        --arg message "$message" \
        --arg status "$status" \
        --arg observed_reply "$observed_reply" \
        --arg next_action "$(next_action_for_status "$status")" \
        '{
          target: $target,
          message: $message,
          status: $status,
          observed_reply: $observed_reply,
          next_action: $next_action
        }')"

    if [[ -n "$json_out" ]]; then
        printf '%s\n' "$result_json" > "$json_out"
    fi

    printf '%s\n' "$result_json"
}

cleanup() {
    if [[ -n "${probe_stdout_file:-}" ]]; then
        rm -f "$probe_stdout_file"
    fi
    if [[ -n "${probe_stderr_file:-}" ]]; then
        rm -f "$probe_stderr_file"
    fi
}

trap cleanup EXIT

while [[ $# -gt 0 ]]; do
    case "$1" in
        --message)
            message="${2:-}"
            shift 2
            ;;
        --target)
            target="${2:-}"
            shift 2
            ;;
        --timeout-sec)
            timeout_sec="${2:-}"
            shift 2
            ;;
        --json-out)
            json_out="${2:-}"
            shift 2
            ;;
        --verbose)
            verbose=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "telegram-chat-probe.sh: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -z "$message" ]]; then
    echo "telegram-chat-probe.sh: --message is required" >&2
    usage >&2
    exit 2
fi

if [[ ! -f "$PROBE_SCRIPT" ]]; then
    echo "telegram-chat-probe.sh: missing probe script: $PROBE_SCRIPT" >&2
    exit 1
fi

probe_api_id="${TELEGRAM_TEST_API_ID:-}"
probe_api_hash="${TELEGRAM_TEST_API_HASH:-}"
probe_session="${TELEGRAM_TEST_SESSION:-}"

if [[ -z "$probe_api_id" || -z "$probe_api_hash" || -z "$probe_session" ]]; then
    emit_result "precondition_failed" ""
    exit 0
fi

probe_stdout_file="$(mktemp)"
probe_stderr_file="$(mktemp)"

set +e
TELEGRAM_API_ID="$probe_api_id" \
TELEGRAM_API_HASH="$probe_api_hash" \
TELEGRAM_SESSION="$probe_session" \
python3 "$PROBE_SCRIPT" \
    --to "$target" \
    --text "$message" \
    --timeout-seconds "$timeout_sec" \
    >"$probe_stdout_file" \
    2>"$probe_stderr_file"
probe_rc=$?
set -e

probe_output="$(cat "$probe_stdout_file")"
probe_stderr="$(cat "$probe_stderr_file")"

log "raw probe stdout: $probe_output"
log "raw probe stderr: $probe_stderr"
log "probe exit code: $probe_rc"

status="upstream_failed"
observed_reply=""

if ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$probe_output"; then
    observed_reply="${probe_output:-$probe_stderr}"
elif jq -e '.error == "Timeout waiting for reply"' >/dev/null 2>&1 <<<"$probe_output" || [[ $probe_rc -eq 3 ]]; then
    status="timeout"
    observed_reply="$(jq -r '.reply_text // ""' <<<"$probe_output")"
elif jq -e '.status == "pass"' >/dev/null 2>&1 <<<"$probe_output"; then
    status="completed"
    observed_reply="$(jq -r '.reply_text // ""' <<<"$probe_output")"
elif [[ $probe_rc -ne 0 ]]; then
    observed_reply="$(jq -r '.error // .reply_text // ""' <<<"$probe_output")"
    if [[ -z "$observed_reply" ]]; then
        observed_reply="${probe_stderr:-$probe_output}"
    fi
else
    observed_reply="$(jq -r '.error // .reply_text // ""' <<<"$probe_output")"
fi

emit_result "$status" "$observed_reply"
