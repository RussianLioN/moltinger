#!/bin/bash
# Smoke-check Moltis auth and chat/status via the current auth + RPC surfaces.

set -euo pipefail

if [[ -n "${MOLTIS_ACTIVE_ROOT:-}" ]]; then
    PROJECT_ROOT="$MOLTIS_ACTIVE_ROOT"
else
    SCRIPT_PATH="${BASH_SOURCE[0]-$0}"
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
    PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
fi
MOLTIS_URL="${MOLTIS_URL:-http://localhost:13131}"
ENV_FILE="${MOLTIS_ENV_FILE:-$PROJECT_ROOT/.env}"
TEST_TIMEOUT="${TEST_TIMEOUT:-20}"
CHAT_WAIT_MS="${CHAT_WAIT_MS:-15000}"
RESET_CHAT_CONTEXT_BEFORE_SEND="${RESET_CHAT_CONTEXT_BEFORE_SEND:-true}"
TEST_SESSION_KEY="${TEST_SESSION_KEY:-}"
DELETE_TEST_SESSION_ON_EXIT="${DELETE_TEST_SESSION_ON_EXIT:-false}"
EXPECTED_PROVIDER="${EXPECTED_PROVIDER:-}"
EXPECTED_MODEL="${EXPECTED_MODEL:-}"
EXPECTED_REPLY_TEXT="${EXPECTED_REPLY_TEXT:-}"
COOKIE_FILE="/tmp/moltis-session-$$"
STATUS_FILE="/tmp/moltis-status-$$.json"
RPC_OUTPUT_FILE="/tmp/moltis-chat-$$.json"
AUTH_STATUS_FILE="/tmp/moltis-auth-$$.json"
CHAT_CLEAR_FILE="/tmp/moltis-chat-clear-$$.json"
SESSION_DELETE_FILE="/tmp/moltis-session-delete-$$.json"
SESSION_DELETE_ATTEMPTED="false"

# shellcheck source=../tests/lib/http.sh
source "$PROJECT_ROOT/tests/lib/http.sh"
# shellcheck source=../tests/lib/rpc.sh
source "$PROJECT_ROOT/tests/lib/rpc.sh"

cleanup() {
    if [[ "$DELETE_TEST_SESSION_ON_EXIT" == "true" && -n "$TEST_SESSION_KEY" && "$SESSION_DELETE_ATTEMPTED" != "true" && -n "${TEST_COOKIE_HEADER:-}" ]]; then
        delete_test_session_best_effort || true
    fi
    rm -f "$COOKIE_FILE" "$STATUS_FILE" "$RPC_OUTPUT_FILE" "$AUTH_STATUS_FILE" "$CHAT_CLEAR_FILE"
    rm -f "$SESSION_DELETE_FILE"
    unset TEST_COOKIE_HEADER || true
}

trap cleanup EXIT

require_command() {
    local command="$1"
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "ERROR: required command not found: $command" >&2
        exit 1
    fi
}

read_password() {
    grep '^MOLTIS_PASSWORD=' "$ENV_FILE" 2>/dev/null | tail -1 | cut -d'=' -f2-
}

print_json_summary() {
    local file_path="$1"
    local jq_expr="$2"

    if ! jq -r "$jq_expr" "$file_path"; then
        echo "ERROR: failed to parse JSON output from $file_path" >&2
        exit 1
    fi
}

delete_test_session_best_effort() {
    [[ -n "$TEST_SESSION_KEY" ]] || return 0

    TEST_BASE_URL="$MOLTIS_URL" TEST_TIMEOUT="$TEST_TIMEOUT" MOLTIS_PASSWORD="$MOLTIS_PASSWORD" TEST_COOKIE_HEADER="$TEST_COOKIE_HEADER" \
        node "$PROJECT_ROOT/tests/lib/ws_rpc_cli.mjs" request \
            --method sessions.delete \
            --params "$(jq -nc --arg key "$TEST_SESSION_KEY" '{key: $key}')" >"$SESSION_DELETE_FILE" 2>/dev/null || return 1

    jq -e '.ok == true and .result.ok == true and .result.payload.ok == true' "$SESSION_DELETE_FILE" >/dev/null 2>&1
}

run_chat_workflow_sequence() {
    local command_text="$1"
    local steps_json

    steps_json="$(
        jq -nc \
            --arg session_key "$TEST_SESSION_KEY" \
            --argjson reset_chat "$([[ "$RESET_CHAT_CONTEXT_BEFORE_SEND" == "true" ]] && echo true || echo false)" \
            --argjson delete_session "$([[ "$DELETE_TEST_SESSION_ON_EXIT" == "true" && -n "$TEST_SESSION_KEY" ]] && echo true || echo false)" \
            --arg text "$command_text" \
            --argjson wait_ms "$CHAT_WAIT_MS" \
            '
            [
              (if $session_key != "" then {method: "sessions.switch", params: {key: $session_key}} else empty end),
              (if $reset_chat then {method: "chat.clear", params: {}} else empty end),
              {method: "chat.send", params: {text: $text}, waitMs: $wait_ms},
              (if $delete_session then {method: "sessions.delete", params: {key: $session_key}} else empty end)
            ]
            '
    )"

    TEST_BASE_URL="$MOLTIS_URL" TEST_TIMEOUT="$TEST_TIMEOUT" MOLTIS_PASSWORD="$MOLTIS_PASSWORD" TEST_COOKIE_HEADER="$TEST_COOKIE_HEADER" \
        node "$PROJECT_ROOT/tests/lib/ws_rpc_cli.mjs" sequence --steps "$steps_json" --subscribe chat >"$RPC_OUTPUT_FILE"
}

main() {
    local command="${1:-/status}"
    local health_code auth_code logout_code
    local final_event_count final_provider final_model final_reply_text
    local chat_run_started

    require_command curl
    require_command jq
    require_command node

    MOLTIS_PASSWORD="${MOLTIS_PASSWORD:-$(read_password)}"
    if [[ -z "${MOLTIS_PASSWORD:-}" ]]; then
        echo "ERROR: MOLTIS_PASSWORD not found in $ENV_FILE" >&2
        exit 1
    fi

    echo "=== Testing Moltis API/RPC ==="
    echo "URL: $MOLTIS_URL"
    echo "Command: $command"
    echo

    echo "1. Health check..."
    health_code="$(health_status_code "$MOLTIS_URL" "$TEST_TIMEOUT")"
    if [[ "$health_code" != "200" ]]; then
        echo "ERROR: Health endpoint returned HTTP $health_code" >&2
        exit 1
    fi
    echo "   OK (HTTP $health_code)"

    echo
    echo "2. Authenticating via /api/auth/login..."
    auth_code="$(moltis_login_code "$MOLTIS_URL" "$MOLTIS_PASSWORD" "$COOKIE_FILE" "$TEST_TIMEOUT")"
    if [[ "$auth_code" != "200" && "$auth_code" != "302" && "$auth_code" != "303" ]]; then
        echo "ERROR: Authentication failed (HTTP $auth_code)" >&2
        exit 1
    fi
    TEST_COOKIE_HEADER="$(cookie_file_to_header "$COOKIE_FILE")"
    export TEST_COOKIE_HEADER
    echo "   OK (HTTP $auth_code)"

    echo
    echo "3. Reading auth status..."
    moltis_request "GET" "$MOLTIS_URL" "/api/auth/status" "$COOKIE_FILE" "$AUTH_STATUS_FILE" "$TEST_TIMEOUT" >/dev/null
    if ! jq -e '.authenticated == true' "$AUTH_STATUS_FILE" >/dev/null 2>&1; then
        echo "ERROR: Authenticated status check failed" >&2
        jq . "$AUTH_STATUS_FILE" >&2 || true
        exit 1
    fi
    print_json_summary "$AUTH_STATUS_FILE" '.'

    echo
    echo "4. Fetching runtime status via RPC..."
    TEST_BASE_URL="$MOLTIS_URL" TEST_TIMEOUT="$TEST_TIMEOUT" \
        node "$PROJECT_ROOT/tests/lib/ws_rpc_cli.mjs" request --method status --params '{}' >"$STATUS_FILE"
    if ! jq -e '.ok == true and .result.ok == true' "$STATUS_FILE" >/dev/null 2>&1; then
        echo "ERROR: Status RPC failed" >&2
        jq . "$STATUS_FILE" >&2 || true
        exit 1
    fi
    print_json_summary "$STATUS_FILE" '{version: .result.payload.version, connections: .result.payload.connections}'

    echo
    echo "5. Running chat workflow via a single RPC connection..."
    if ! run_chat_workflow_sequence "$command"; then
        echo "ERROR: chat workflow RPC sequence failed" >&2
        jq . "$RPC_OUTPUT_FILE" >&2 || true
        exit 1
    fi

    if [[ -n "$TEST_SESSION_KEY" ]]; then
        if ! jq -e --arg key "$TEST_SESSION_KEY" '
            .ok == true and
            ([.result.payload[]? | select(.step.method == "sessions.switch")][0].response.ok == true) and
            (([.result.payload[]? | select(.step.method == "sessions.switch")][0].response.payload.entry.key // "") == $key)
        ' "$RPC_OUTPUT_FILE" >/dev/null 2>&1; then
            echo "ERROR: sessions.switch step failed for TEST_SESSION_KEY='$TEST_SESSION_KEY'" >&2
            jq . "$RPC_OUTPUT_FILE" >&2 || true
            exit 1
        fi
        echo "   Switched to dedicated session: $TEST_SESSION_KEY"
    fi

    if [[ "$RESET_CHAT_CONTEXT_BEFORE_SEND" == "true" ]]; then
        if ! jq -e '
            .ok == true and
            ([.result.payload[]? | select(.step.method == "chat.clear")][0].response.ok == true) and
            ([.result.payload[]? | select(.step.method == "chat.clear")][0].response.payload.ok == true)
        ' "$RPC_OUTPUT_FILE" >/dev/null 2>&1; then
            echo "ERROR: chat.clear step failed" >&2
            jq . "$RPC_OUTPUT_FILE" >&2 || true
            exit 1
        fi
        echo "   Cleared chat context"
    fi

    final_event_count="$(jq -r '[.events[]? | select(.event == "chat" and .payload.state == "final")] | length' "$RPC_OUTPUT_FILE")"
    chat_run_started="$(jq -r '([.result.payload[]? | select(.step.method == "chat.send")][0].response.ok == true and [.result.payload[]? | select(.step.method == "chat.send")][0].response.payload.ok == true)' "$RPC_OUTPUT_FILE" 2>/dev/null || echo "false")"
    if [[ "$final_event_count" == "0" ]]; then
        if [[ "$chat_run_started" == "true" ]]; then
            echo "ERROR: Chat RPC started successfully but did not reach a final event within CHAT_WAIT_MS=$CHAT_WAIT_MS" >&2
        else
            echo "ERROR: Chat RPC did not start successfully" >&2
        fi
        jq . "$RPC_OUTPUT_FILE" >&2 || true
        exit 1
    fi

    final_provider="$(jq -r '[.events[]? | select(.event == "chat" and .payload.state == "final")][-1].payload.provider // empty' "$RPC_OUTPUT_FILE")"
    final_model="$(jq -r '[.events[]? | select(.event == "chat" and .payload.state == "final")][-1].payload.model // empty' "$RPC_OUTPUT_FILE")"
    final_reply_text="$(jq -r '[.events[]? | select(.event == "chat" and .payload.state == "final")][-1].payload.text // empty' "$RPC_OUTPUT_FILE")"

    if [[ -n "$EXPECTED_PROVIDER" && "$final_provider" != "$EXPECTED_PROVIDER" ]]; then
        echo "ERROR: Final provider mismatch: expected '$EXPECTED_PROVIDER', got '$final_provider'" >&2
        jq . "$RPC_OUTPUT_FILE" >&2 || true
        exit 1
    fi

    if [[ -n "$EXPECTED_MODEL" && "$final_model" != "$EXPECTED_MODEL" ]]; then
        echo "ERROR: Final model mismatch: expected '$EXPECTED_MODEL', got '$final_model'" >&2
        jq . "$RPC_OUTPUT_FILE" >&2 || true
        exit 1
    fi

    if [[ -n "$EXPECTED_REPLY_TEXT" && "$final_reply_text" != "$EXPECTED_REPLY_TEXT" ]]; then
        echo "ERROR: Final reply text mismatch: expected '$EXPECTED_REPLY_TEXT', got '$final_reply_text'" >&2
        jq . "$RPC_OUTPUT_FILE" >&2 || true
        exit 1
    fi

    print_json_summary "$RPC_OUTPUT_FILE" '[.events[]? | select(.event == "chat" and .payload.state == "final")][-1]'

    if [[ "$DELETE_TEST_SESSION_ON_EXIT" == "true" && -n "$TEST_SESSION_KEY" ]]; then
        if ! jq -e '
            .ok == true and
            ([.result.payload[]? | select(.step.method == "sessions.delete")][0].response.ok == true) and
            ([.result.payload[]? | select(.step.method == "sessions.delete")][0].response.payload.ok == true)
        ' "$RPC_OUTPUT_FILE" >/dev/null 2>&1; then
            echo "ERROR: sessions.delete RPC failed for TEST_SESSION_KEY='$TEST_SESSION_KEY'" >&2
            jq . "$RPC_OUTPUT_FILE" >&2 || true
            exit 1
        fi
        SESSION_DELETE_ATTEMPTED="true"
        echo "   Deleted dedicated session"
    fi

    echo
    echo "6. Logging out..."
    logout_code="$(moltis_logout_code "$MOLTIS_URL" "$COOKIE_FILE" "$TEST_TIMEOUT")"
    if [[ ! "$logout_code" =~ ^(200|204|302|303)$ ]]; then
        echo "ERROR: Logout failed (HTTP $logout_code)" >&2
        exit 1
    fi
    echo "   OK (HTTP $logout_code)"

    echo
    echo "=== Done ==="
}

main "$@"
