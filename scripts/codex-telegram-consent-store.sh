#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_STORE_DIR="${PROJECT_ROOT}/.tmp/current/codex-telegram-consent-store"

STORE_DIR="${CODEX_TELEGRAM_CONSENT_STORE_DIR:-${DEFAULT_STORE_DIR}}"
COMMAND="${1:-}"
REQUEST_ID=""
ACTION_TOKEN=""
RECORD_FILE=""
MESSAGE_ID=""
DECISION=""
RESOLVED_VIA=""
TELEGRAM_ACTOR_ID=""
RAW_INPUT=""
NOTE=""
DELIVERY_STATUS=""
DELIVERY_ERROR=""
JSON_OUTPUT=true

usage() {
    cat <<'EOF'
Usage:
  codex-telegram-consent-store.sh <command> [options]

Commands:
  open            Save or replace one authoritative consent record from JSON
  get             Print one record by request id
  find-by-token   Print one record by action token
  bind-message    Attach Telegram question_message_id to an existing record
  resolve         Persist a consent decision for an existing record
  mark-delivery   Persist follow-up delivery status for an existing record

Common options:
  --store-dir PATH          Consent store directory
  --request-id ID           Consent request id
  --action-token TOKEN      Consent action token
  --record-file PATH        JSON file to read for open
  --message-id N            Telegram message id for bind-message
  --decision VALUE          accept|decline|expired|invalid|duplicate
  --resolved-via VALUE      callback_query|command_fallback|command_alias|operator_override
  --telegram-actor-id ID    Telegram actor id for resolve
  --raw-input TEXT          Raw callback data or command text for resolve
  --note TEXT               Optional audit note for resolve
  --delivery-status VALUE   not_sent|sent|suppressed|retry|failed
  --delivery-error TEXT     Optional delivery error text
  --json                    Print resulting JSON (default)
  -h, --help                Show help
EOF
}

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing required dependency: $1"
}

sanitize_request_id() {
    local value="$1"
    [[ -n "$value" ]] || fail "request id is required"
    [[ "$value" =~ ^[A-Za-z0-9._-]+$ ]] || fail "invalid request id: $value"
    printf '%s\n' "$value"
}

sanitize_action_token() {
    local value="$1"
    [[ -n "$value" ]] || fail "action token is required"
    [[ "$value" =~ ^[A-Za-z0-9._-]+$ ]] || fail "invalid action token"
    printf '%s\n' "$value"
}

record_path_for() {
    local request_id
    request_id="$(sanitize_request_id "$1")"
    printf '%s/%s.json\n' "$STORE_DIR" "$request_id"
}

ensure_store_dir() {
    mkdir -p "$STORE_DIR"
}

validate_record_file() {
    local path="$1"
    jq -e '
        .request.request_id? and
        .request.source? == "codex_upstream_watcher" and
        .request.fingerprint? and
        .request.chat_id? and
        .request.created_at? and
        .request.expires_at? and
        .request.status? and
        .request.action_token? and
        .request.question_text? and
        .request.delivery_mode? and
        (.recommendations.summary? | type == "string") and
        (.recommendations.items? | type == "array") and
        (.delivery.status? | type == "string") and
        (.audit_notes? | type == "array")
    ' "$path" >/dev/null || fail "record does not match the required consent-store shape"
}

render_json() {
    local path="$1"
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        cat "$path"
    fi
}

parse_args() {
    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --store-dir)
                STORE_DIR="${2:?missing value for --store-dir}"
                shift 2
                ;;
            --request-id)
                REQUEST_ID="${2:?missing value for --request-id}"
                shift 2
                ;;
            --action-token)
                ACTION_TOKEN="${2:?missing value for --action-token}"
                shift 2
                ;;
            --record-file)
                RECORD_FILE="${2:?missing value for --record-file}"
                shift 2
                ;;
            --message-id)
                MESSAGE_ID="${2:?missing value for --message-id}"
                shift 2
                ;;
            --decision)
                DECISION="${2:?missing value for --decision}"
                shift 2
                ;;
            --resolved-via)
                RESOLVED_VIA="${2:?missing value for --resolved-via}"
                shift 2
                ;;
            --telegram-actor-id)
                TELEGRAM_ACTOR_ID="${2:?missing value for --telegram-actor-id}"
                shift 2
                ;;
            --raw-input)
                RAW_INPUT="${2:?missing value for --raw-input}"
                shift 2
                ;;
            --note)
                NOTE="${2:?missing value for --note}"
                shift 2
                ;;
            --delivery-status)
                DELIVERY_STATUS="${2:?missing value for --delivery-status}"
                shift 2
                ;;
            --delivery-error)
                DELIVERY_ERROR="${2:?missing value for --delivery-error}"
                shift 2
                ;;
            --json)
                JSON_OUTPUT=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                fail "Unknown argument: $1"
                ;;
        esac
    done
}

open_record() {
    [[ -n "$RECORD_FILE" ]] || fail "--record-file is required for open"
    [[ -f "$RECORD_FILE" ]] || fail "record file not found: $RECORD_FILE"
    ensure_store_dir
    validate_record_file "$RECORD_FILE"

    local request_id path tmp
    request_id="$(jq -r '.request.request_id' "$RECORD_FILE")"
    sanitize_request_id "$request_id" >/dev/null
    sanitize_action_token "$(jq -r '.request.action_token' "$RECORD_FILE")" >/dev/null

    path="$(record_path_for "$request_id")"
    tmp="${path}.tmp"
    jq '.' "$RECORD_FILE" > "$tmp"
    mv "$tmp" "$path"
    render_json "$path"
}

get_record() {
    [[ -n "$REQUEST_ID" ]] || fail "--request-id is required for get"
    local path
    path="$(record_path_for "$REQUEST_ID")"
    [[ -f "$path" ]] || fail "consent record not found: $REQUEST_ID"
    render_json "$path"
}

find_by_token() {
    [[ -n "$ACTION_TOKEN" ]] || fail "--action-token is required for find-by-token"
    sanitize_action_token "$ACTION_TOKEN" >/dev/null
    ensure_store_dir

    local path
    shopt -s nullglob
    for path in "$STORE_DIR"/*.json; do
        if jq -e --arg token "$ACTION_TOKEN" '.request.action_token == $token' "$path" >/dev/null 2>&1; then
            render_json "$path"
            return 0
        fi
    done
    shopt -u nullglob
    fail "consent record not found for token"
}

bind_message() {
    [[ -n "$REQUEST_ID" ]] || fail "--request-id is required for bind-message"
    [[ "$MESSAGE_ID" =~ ^[1-9][0-9]*$ ]] || fail "--message-id must be a positive integer"
    local path tmp
    path="$(record_path_for "$REQUEST_ID")"
    [[ -f "$path" ]] || fail "consent record not found: $REQUEST_ID"
    tmp="${path}.tmp"
    jq --argjson message_id "$MESSAGE_ID" '
        .request.question_message_id = $message_id |
        .audit_notes = ((.audit_notes // []) + ["question_message_id attached"])
    ' "$path" > "$tmp"
    mv "$tmp" "$path"
    render_json "$path"
}

resolve_record() {
    [[ -n "$REQUEST_ID" ]] || fail "--request-id is required for resolve"
    [[ -n "$DECISION" ]] || fail "--decision is required for resolve"
    [[ -n "$RESOLVED_VIA" ]] || fail "--resolved-via is required for resolve"
    [[ -n "$TELEGRAM_ACTOR_ID" ]] || fail "--telegram-actor-id is required for resolve"
    [[ -n "$RAW_INPUT" ]] || fail "--raw-input is required for resolve"

    case "$DECISION" in
        accept|decline|expired|invalid|duplicate) ;;
        *) fail "invalid decision: $DECISION" ;;
    esac
    case "$RESOLVED_VIA" in
        callback_query|command_fallback|command_alias|operator_override) ;;
        *) fail "invalid resolved-via value: $RESOLVED_VIA" ;;
    esac

    local path tmp resolved_at
    path="$(record_path_for "$REQUEST_ID")"
    [[ -f "$path" ]] || fail "consent record not found: $REQUEST_ID"
    resolved_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    tmp="${path}.tmp"

    jq \
        --arg decision "$DECISION" \
        --arg resolved_via "$RESOLVED_VIA" \
        --arg telegram_actor_id "$TELEGRAM_ACTOR_ID" \
        --arg raw_input "$RAW_INPUT" \
        --arg resolved_at "$resolved_at" \
        --arg note "$NOTE" \
        '
        .decision = {
            request_id: .request.request_id,
            decision: $decision,
            resolved_at: $resolved_at,
            resolved_via: $resolved_via,
            telegram_actor_id: $telegram_actor_id,
            raw_input: $raw_input
        }
        | (if $note != "" then .decision.note = $note else . end)
        | .request.status = (
            if $decision == "accept" then "accepted"
            elif $decision == "decline" then "declined"
            elif $decision == "expired" then "expired"
            else .request.status
            end
        )
        | .audit_notes = ((.audit_notes // []) + ["decision:" + $decision + " via " + $resolved_via])
        ' "$path" > "$tmp"
    mv "$tmp" "$path"
    render_json "$path"
}

mark_delivery() {
    [[ -n "$REQUEST_ID" ]] || fail "--request-id is required for mark-delivery"
    [[ -n "$DELIVERY_STATUS" ]] || fail "--delivery-status is required for mark-delivery"

    case "$DELIVERY_STATUS" in
        not_sent|sent|suppressed|retry|failed) ;;
        *) fail "invalid delivery status: $DELIVERY_STATUS" ;;
    esac

    if [[ -n "$MESSAGE_ID" ]] && [[ ! "$MESSAGE_ID" =~ ^[1-9][0-9]*$ ]]; then
        fail "--message-id must be a positive integer"
    fi

    local path tmp recorded_at
    path="$(record_path_for "$REQUEST_ID")"
    [[ -f "$path" ]] || fail "consent record not found: $REQUEST_ID"
    recorded_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    tmp="${path}.tmp"

    jq \
        --arg delivery_status "$DELIVERY_STATUS" \
        --arg message_id "$MESSAGE_ID" \
        --arg delivery_error "$DELIVERY_ERROR" \
        --arg recorded_at "$recorded_at" \
        --arg note "$NOTE" \
        '
        .delivery.status = $delivery_status
        | .delivery.message_id = (if $message_id == "" then null else ($message_id | tonumber) end)
        | (
            if $delivery_status == "sent" then
                .delivery.sent_at = $recorded_at
            else
                del(.delivery.sent_at)
            end
          )
        | (
            if $delivery_error == "" then
                del(.delivery.error)
            else
                .delivery.error = $delivery_error
            end
          )
        | .request.status = (
            if $delivery_status == "sent" then "delivered"
            elif ($delivery_status == "retry" or $delivery_status == "failed") then "failed"
            else .request.status
            end
          )
        | .audit_notes = ((.audit_notes // []) + ["delivery:" + $delivery_status])
        | (if $note != "" then .audit_notes = (.audit_notes + [$note]) else . end)
        ' "$path" > "$tmp"
    mv "$tmp" "$path"
    render_json "$path"
}

main() {
    require_command jq
    [[ -n "$COMMAND" ]] || {
        usage >&2
        exit 2
    }
    parse_args "$@"

    case "$COMMAND" in
        open)
            open_record
            ;;
        get)
            get_record
            ;;
        find-by-token)
            find_by_token
            ;;
        bind-message)
            bind_message
            ;;
        resolve)
            resolve_record
            ;;
        mark-delivery)
            mark_delivery
            ;;
        -h|--help)
            usage
            ;;
        *)
            fail "Unknown command: $COMMAND"
            ;;
    esac
}

main "$@"
