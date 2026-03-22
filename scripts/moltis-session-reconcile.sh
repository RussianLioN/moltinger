#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
MOLTIS_URL="${MOLTIS_URL:-http://localhost:13131}"
ENV_FILE="${MOLTIS_ENV_FILE:-$PROJECT_ROOT/.env}"
WS_RPC_CLI="${MOLTIS_WS_RPC_CLI:-$PROJECT_ROOT/tests/lib/ws_rpc_cli.mjs}"
EXPECTED_MODEL="${EXPECTED_MODEL:-openai-codex::gpt-5.4}"
TEST_TIMEOUT="${TEST_TIMEOUT:-20}"
RPC_WAIT_MS="${RPC_WAIT_MS:-1000}"
SESSION_KEY=""
TELEGRAM_CHAT_ID=""
CHANNEL_TYPE=""
CHANNEL_ACCOUNT_ID=""
APPLY_CHANGES=false
RESET_SESSION=true

# shellcheck source=../tests/lib/http.sh
source "$PROJECT_ROOT/tests/lib/http.sh"
# shellcheck source=../tests/lib/rpc.sh
source "$PROJECT_ROOT/tests/lib/rpc.sh"

usage() {
    cat <<'EOF'
Usage: moltis-session-reconcile.sh [--session-key <key> | --telegram-chat-id <id>] [options]

Resolve a target Moltis session, report the planned reconcile action as JSON, and
optionally apply the canonical model patch plus a session reset.

Target options:
  --session-key <key>           Reconcile an explicit session key (for example: main)
  --telegram-chat-id <id>       Resolve the active Telegram-bound session for a chat id
  --channel-account-id <id>     Optional channel account id filter when resolving by chat id
  --channel-type <type>         Optional channel type override (default: telegram when chat id is set)

Behavior:
  --apply                       Apply sessions.patch and sessions.reset
  --skip-reset                  Patch the session model but do not reset context
  --base-url <url>              Moltis base URL (default: http://localhost:13131)
  --expected-model <model>      Canonical model to enforce (default: openai-codex::gpt-5.4)

Default mode is dry-run and emits a JSON summary.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --session-key)
            SESSION_KEY="${2:-}"
            shift 2
            ;;
        --telegram-chat-id)
            TELEGRAM_CHAT_ID="${2:-}"
            shift 2
            ;;
        --channel-account-id)
            CHANNEL_ACCOUNT_ID="${2:-}"
            shift 2
            ;;
        --channel-type)
            CHANNEL_TYPE="${2:-}"
            shift 2
            ;;
        --apply)
            APPLY_CHANGES=true
            shift
            ;;
        --skip-reset)
            RESET_SESSION=false
            shift
            ;;
        --base-url)
            MOLTIS_URL="${2:-}"
            shift 2
            ;;
        --expected-model)
            EXPECTED_MODEL="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "moltis-session-reconcile.sh: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

require_command() {
    local command="$1"
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "moltis-session-reconcile.sh: required command not found: $command" >&2
        exit 2
    fi
}

read_password() {
    grep '^MOLTIS_PASSWORD=' "$ENV_FILE" 2>/dev/null | tail -1 | cut -d'=' -f2-
}

emit_json_error() {
    local message="$1"
    local candidates_json="${2:-[]}"
    local resolved_json="${3:-null}"
    jq -n \
        --arg status "error" \
        --arg message "$message" \
        --arg target_session_key "$SESSION_KEY" \
        --arg telegram_chat_id "$TELEGRAM_CHAT_ID" \
        --arg channel_type "$CHANNEL_TYPE" \
        --arg channel_account_id "$CHANNEL_ACCOUNT_ID" \
        --arg expected_model "$EXPECTED_MODEL" \
        --argjson candidates "$candidates_json" \
        --argjson resolved_session "$resolved_json" \
        '{
            status: $status,
            message: $message,
            target: {
                session_key: (if $target_session_key == "" then null else $target_session_key end),
                telegram_chat_id: (if $telegram_chat_id == "" then null else $telegram_chat_id end),
                channel_type: (if $channel_type == "" then null else $channel_type end),
                channel_account_id: (if $channel_account_id == "" then null else $channel_account_id end)
            },
            expected_model: $expected_model,
            candidates: $candidates,
            candidate_count: ($candidates | length),
            resolved_session: $resolved_session
        }'
}

rpc_request() {
    local method="$1"
    local params_json="$2"
    local output_file="$3"

    TEST_BASE_URL="$MOLTIS_URL" \
    TEST_TIMEOUT="$TEST_TIMEOUT" \
    MOLTIS_PASSWORD="$MOLTIS_PASSWORD" \
    TEST_COOKIE_HEADER="$TEST_COOKIE_HEADER" \
        node "$WS_RPC_CLI" request --method "$method" --params "$params_json" --wait-ms "$RPC_WAIT_MS" > "$output_file"

    if ! jq -e '.ok == true and .result.ok == true' "$output_file" >/dev/null 2>&1; then
        echo "moltis-session-reconcile.sh: RPC failed for method $method" >&2
        jq . "$output_file" >&2 || true
        exit 1
    fi
}

resolve_candidates() {
    local sessions_file="$1"

    if [[ -n "$SESSION_KEY" ]]; then
        jq --arg key "$SESSION_KEY" '
            [.result.payload[]
             | . + {
                 channelBindingParsed: (
                   if (.channelBinding // "") == "" then null
                   else try (.channelBinding | fromjson) catch null
                   end
                 )
               }
             | select(.key == $key)]
        ' "$sessions_file"
        return
    fi

    jq \
        --arg chat_id "$TELEGRAM_CHAT_ID" \
        --arg channel_type "$CHANNEL_TYPE" \
        --arg account_id "$CHANNEL_ACCOUNT_ID" '
        [.result.payload[]
         | . + {
             channelBindingParsed: (
               if (.channelBinding // "") == "" then null
               else try (.channelBinding | fromjson) catch null
               end
             )
           }
         | select((.channelBindingParsed.chat_id // "") == $chat_id)
         | select(($channel_type == "") or ((.channelBindingParsed.channel_type // "") == $channel_type))
         | select(($account_id == "") or ((.channelBindingParsed.account_id // "") == $account_id))]
    ' "$sessions_file"
}

resolve_session() {
    local candidates_json="$1"

    jq '
        if length == 1 then
            .[0]
        elif ([.[] | select(.activeChannel == true)] | length) == 1 then
            ([.[] | select(.activeChannel == true)] | sort_by(.updatedAt // 0) | reverse | .[0])
        else
            empty
        end
    ' <<<"$candidates_json"
}

TMP_DIR="$(mktemp -d /tmp/moltis-session-reconcile.XXXXXX)"
COOKIE_FILE="$TMP_DIR/cookies.txt"
SESSIONS_FILE="$TMP_DIR/sessions-list.json"
PATCH_FILE="$TMP_DIR/sessions-patch.json"
RESET_FILE="$TMP_DIR/sessions-reset.json"
VERIFY_FILE="$TMP_DIR/sessions-verify.json"
trap 'rm -rf "$TMP_DIR"' EXIT

main() {
    local auth_code candidates_json resolved_json verify_candidates_json verify_resolved_json
    local patch_payload reset_payload patch_result_json reset_result_json

    require_command curl
    require_command jq
    require_command node

    if [[ -z "$SESSION_KEY" && -z "$TELEGRAM_CHAT_ID" ]]; then
        emit_json_error "Either --session-key or --telegram-chat-id is required."
        exit 2
    fi

    if [[ -n "$SESSION_KEY" && -n "$TELEGRAM_CHAT_ID" ]]; then
        emit_json_error "Use either --session-key or --telegram-chat-id, not both."
        exit 2
    fi

    if [[ -n "$TELEGRAM_CHAT_ID" && -z "$CHANNEL_TYPE" ]]; then
        CHANNEL_TYPE="telegram"
    fi

    MOLTIS_PASSWORD="${MOLTIS_PASSWORD:-$(read_password)}"
    if [[ -z "${MOLTIS_PASSWORD:-}" ]]; then
        emit_json_error "MOLTIS_PASSWORD not found in $ENV_FILE"
        exit 2
    fi

    auth_code="$(moltis_login_code "$MOLTIS_URL" "$MOLTIS_PASSWORD" "$COOKIE_FILE" "$TEST_TIMEOUT")"
    if [[ "$auth_code" != "200" && "$auth_code" != "302" && "$auth_code" != "303" ]]; then
        emit_json_error "Authentication failed with HTTP $auth_code"
        exit 1
    fi

    TEST_COOKIE_HEADER="$(cookie_file_to_header "$COOKIE_FILE")"
    export TEST_COOKIE_HEADER

    rpc_request "sessions.list" '{}' "$SESSIONS_FILE"
    candidates_json="$(resolve_candidates "$SESSIONS_FILE")"
    resolved_json="$(resolve_session "$candidates_json")"

    if [[ -z "$resolved_json" || "$resolved_json" == "null" ]]; then
        emit_json_error "Could not resolve a unique target session from the provided selector." "$candidates_json"
        exit 1
    fi

    if [[ "$APPLY_CHANGES" != "true" ]]; then
        jq -n \
            --arg status "dry-run" \
            --arg expected_model "$EXPECTED_MODEL" \
            --argjson candidates "$candidates_json" \
            --argjson resolved_session "$resolved_json" \
            --argjson apply_reset "$( [[ "$RESET_SESSION" == "true" ]] && echo true || echo false )" \
            '{
                status: $status,
                expected_model: $expected_model,
                candidate_count: ($candidates | length),
                candidates: $candidates,
                resolved_session: $resolved_session,
                planned_actions: {
                    patch_model: $expected_model,
                    reset_session: $apply_reset
                }
            }'
        return 0
    fi

    patch_payload="$(jq -nc --arg key "$(jq -r '.key' <<<"$resolved_json")" --arg model "$EXPECTED_MODEL" '{key: $key, model: $model}')"
    rpc_request "sessions.patch" "$patch_payload" "$PATCH_FILE"
    patch_result_json="$(jq '.result.payload' "$PATCH_FILE")"

    reset_result_json='null'
    if [[ "$RESET_SESSION" == "true" ]]; then
        reset_payload="$(jq -nc --arg key "$(jq -r '.key' <<<"$resolved_json")" '{key: $key}')"
        rpc_request "sessions.reset" "$reset_payload" "$RESET_FILE"
        reset_result_json="$(jq '.result.payload' "$RESET_FILE")"
    fi

    rpc_request "sessions.list" '{}' "$VERIFY_FILE"
    verify_candidates_json="$(resolve_candidates "$VERIFY_FILE")"
    verify_resolved_json="$(resolve_session "$verify_candidates_json")"

    if [[ -z "$verify_resolved_json" || "$verify_resolved_json" == "null" ]]; then
        emit_json_error "Reconcile applied, but the target session could not be re-resolved for verification." "$verify_candidates_json"
        exit 1
    fi

    if [[ "$(jq -r '.model // empty' <<<"$verify_resolved_json")" != "$EXPECTED_MODEL" ]]; then
        emit_json_error "Reconcile applied, but the verified session model does not match the expected model." "$verify_candidates_json" "$verify_resolved_json"
        exit 1
    fi

    jq -n \
        --arg status "applied" \
        --arg expected_model "$EXPECTED_MODEL" \
        --argjson candidates "$candidates_json" \
        --argjson resolved_session "$resolved_json" \
        --argjson patch_result "$patch_result_json" \
        --argjson reset_result "$reset_result_json" \
        --argjson verified_session "$verify_resolved_json" \
        --argjson apply_reset "$( [[ "$RESET_SESSION" == "true" ]] && echo true || echo false )" \
        '{
            status: $status,
            expected_model: $expected_model,
            candidate_count: ($candidates | length),
            candidates: $candidates,
            resolved_session: $resolved_session,
            patch_result: $patch_result,
            reset_applied: $apply_reset,
            reset_result: $reset_result,
            verified_session: $verified_session
        }'
}

main
