#!/usr/bin/env bash
# Run a tracked browser navigation canary and verify that the live runtime
# actually used the browser tool instead of only producing a plausible answer.

set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

MOLTIS_URL="${MOLTIS_URL:-http://localhost:13131}"
MOLTIS_CONTAINER="${MOLTIS_CONTAINER:-moltis}"
SMOKE_SCRIPT="${MOLTIS_BROWSER_CANARY_SMOKE_SCRIPT:-$PROJECT_ROOT/scripts/test-moltis-api.sh}"
DOCKER_BIN="${DOCKER_BIN:-docker}"
CANARY_PROMPT="${MOLTIS_BROWSER_CANARY_PROMPT:-Используй browser, а не web_fetch. Открой https://docs.moltis.org/ и ответь только точным заголовком страницы без пояснений.}"
EXPECTED_REPLY="${MOLTIS_BROWSER_CANARY_EXPECTED_REPLY:-Introduction - Moltis Documentation}"
CHAT_WAIT_MS="${MOLTIS_BROWSER_CANARY_CHAT_WAIT_MS:-120000}"
TEST_TIMEOUT="${MOLTIS_BROWSER_CANARY_TEST_TIMEOUT:-90}"
REQUIRED_LOG="${MOLTIS_BROWSER_CANARY_REQUIRED_LOG:-tool execution succeeded tool=browser}"
REJECT_LOG_RE="${MOLTIS_BROWSER_CANARY_REJECT_LOG_RE:-browser container failed readiness check|tool execution failed tool=browser|browser launch failed}"

timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

require_file() {
    local path="$1"
    if [[ ! -f "$path" ]]; then
        echo "moltis-browser-canary.sh: missing required file: $path" >&2
        exit 1
    fi
}

main() {
    local started_at smoke_log recent_logs

    require_file "$SMOKE_SCRIPT"
    started_at="$(timestamp)"
    smoke_log="$(mktemp "${TMPDIR:-/tmp}/moltis-browser-canary.XXXXXX")"
    trap 'rm -f "${smoke_log:-}"' EXIT

    if ! CHAT_WAIT_MS="$CHAT_WAIT_MS" \
        TEST_TIMEOUT="$TEST_TIMEOUT" \
        EXPECTED_REPLY_TEXT="$EXPECTED_REPLY" \
        bash "$SMOKE_SCRIPT" "$CANARY_PROMPT" >"$smoke_log" 2>&1; then
        cat "$smoke_log" >&2 || true
        echo "moltis-browser-canary.sh: browser smoke failed before browser-tool proof" >&2
        exit 1
    fi

    recent_logs="$("$DOCKER_BIN" logs --since "$started_at" "$MOLTIS_CONTAINER" 2>&1 || true)"
    if [[ -z "$recent_logs" ]]; then
        cat "$smoke_log" >&2 || true
        echo "moltis-browser-canary.sh: no recent Moltis logs were captured after the canary start time" >&2
        exit 1
    fi

    if ! grep -Fq "$REQUIRED_LOG" <<<"$recent_logs"; then
        cat "$smoke_log" >&2 || true
        printf '%s\n' "$recent_logs" >&2
        echo "moltis-browser-canary.sh: browser canary did not produce '$REQUIRED_LOG' in live logs" >&2
        exit 1
    fi

    if grep -Eq "$REJECT_LOG_RE" <<<"$recent_logs"; then
        cat "$smoke_log" >&2 || true
        printf '%s\n' "$recent_logs" >&2
        echo "moltis-browser-canary.sh: browser canary matched a browser failure signature in live logs" >&2
        exit 1
    fi

    cat <<EOF
[OK] Moltis browser canary passed
container=$MOLTIS_CONTAINER
base_url=$MOLTIS_URL
started_at=$started_at
expected_reply=$EXPECTED_REPLY
required_log=$REQUIRED_LOG
EOF
}

main "$@"
