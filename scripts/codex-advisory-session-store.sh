#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_STORE_DIR="${PROJECT_ROOT}/.tmp/current/codex-advisory-session-store"
DEFAULT_AUDIT_DIR="${PROJECT_ROOT}/.tmp/current/codex-advisory-intake-audit"

STORE_DIR="${MOLTIS_CODEX_ADVISORY_SESSION_STORE_DIR:-${DEFAULT_STORE_DIR}}"
AUDIT_DIR="${MOLTIS_CODEX_ADVISORY_AUDIT_DIR:-${DEFAULT_AUDIT_DIR}}"
COMMAND="${1:-}"
SESSION_ID=""
CALLBACK_TOKEN=""
RECORD_FILE=""
MESSAGE_ID=""
DECISION=""
RESOLVED_VIA=""
TELEGRAM_ACTOR_ID=""
RAW_INPUT=""
NOTE=""
FOLLOWUP_STATUS=""
FOLLOWUP_ERROR=""
JSON_OUTPUT=true

usage() {
    cat <<'EOF'
Usage:
  codex-advisory-session-store.sh <command> [options]

Commands:
  open              Save or replace one advisory session record from JSON
  get               Print one record by session id
  bind-message      Attach Telegram alert message id to an existing session
  resolve           Persist one advisory decision for an existing session
  mark-followup     Persist follow-up delivery status for an existing session

Common options:
  --store-dir PATH            Advisory session store directory
  --audit-dir PATH            Advisory audit mirror directory
  --session-id ID             Advisory session id
  --callback-token TOKEN      Advisory callback token
  --record-file PATH          JSON file to read for open
  --message-id N              Telegram message id for bind-message/mark-followup
  --decision VALUE            accept|decline|expired|duplicate
  --resolved-via VALUE        callback_query|tokenized_recovery|operator_override
  --telegram-actor-id ID      Telegram actor id for resolve
  --raw-input TEXT            Raw callback payload or recovery command
  --note TEXT                 Optional audit note
  --followup-status VALUE     not_requested|awaiting_user|sent|suppressed|retry|failed
  --followup-error TEXT       Optional follow-up delivery error text
  --json                      Print resulting JSON (default)
  -h, --help                  Show help
EOF
}

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing required dependency: $1"
}

sanitize_session_id() {
    local value="$1"
    [[ -n "$value" ]] || fail "session id is required"
    [[ "$value" =~ ^[A-Za-z0-9._:-]+$ ]] || fail "invalid session id: $value"
    printf '%s\n' "$value"
}

sanitize_callback_token() {
    local value="$1"
    [[ -n "$value" ]] || fail "callback token is required"
    [[ "$value" =~ ^[A-Za-z0-9._:-]+$ ]] || fail "invalid callback token"
    printf '%s\n' "$value"
}

record_path_for() {
    local session_id
    session_id="$(sanitize_session_id "$1")"
    printf '%s/%s.json\n' "$STORE_DIR" "$session_id"
}

audit_path_for() {
    local session_id
    session_id="$(sanitize_session_id "$1")"
    printf '%s/%s.json\n' "$AUDIT_DIR" "$session_id"
}

ensure_store_dir() {
    mkdir -p "$STORE_DIR"
}

ensure_audit_dir() {
    mkdir -p "$AUDIT_DIR"
}

render_json() {
    local path="$1"
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        cat "$path"
    fi
}

validate_record_file() {
    local path="$1"
    jq -e '
        .schema_version == "codex-advisory-session/v1" and
        (.event.event_id | type == "string" and length > 0) and
        (.event.upstream_fingerprint | type == "string" and length > 0) and
        (.alert.alert_id | type == "string" and length > 0) and
        (.alert.chat_id | type == "string" and length > 0) and
        (.alert.interactive_mode | IN("inline_callbacks", "one_way_only")) and
        (.session.session_id | type == "string" and length > 0) and
        (.session.callback_token | type == "string" and length > 0) and
        (.session.chat_id | type == "string" and length > 0) and
        (.session.expires_at | type == "string" and length > 0) and
        (.session.status | IN("pending", "accepted", "declined", "expired", "duplicate")) and
        (.recommendation_envelope.headline_ru | type == "string" and length > 0) and
        (.recommendation_envelope.summary_ru | type == "string") and
        (.interaction_record.schema_version == "codex-advisory-interaction/v1") and
        (.interaction_record.event_id == .event.event_id) and
        (.interaction_record.alert_id == .alert.alert_id) and
        (.interaction_record.chat_id == .alert.chat_id) and
        (.interaction_record.followup_status | IN("not_requested", "awaiting_user", "sent", "suppressed", "retry", "failed")) and
        (.audit_notes | type == "array")
    ' "$path" >/dev/null || fail "record does not match the required advisory-session shape"
}

parse_args() {
    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --store-dir)
                STORE_DIR="${2:?missing value for --store-dir}"
                shift 2
                ;;
            --audit-dir)
                AUDIT_DIR="${2:?missing value for --audit-dir}"
                shift 2
                ;;
            --session-id)
                SESSION_ID="${2:?missing value for --session-id}"
                shift 2
                ;;
            --callback-token)
                CALLBACK_TOKEN="${2:?missing value for --callback-token}"
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
            --followup-status)
                FOLLOWUP_STATUS="${2:?missing value for --followup-status}"
                shift 2
                ;;
            --followup-error)
                FOLLOWUP_ERROR="${2:?missing value for --followup-error}"
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
    ensure_audit_dir
    validate_record_file "$RECORD_FILE"

    local session_id path tmp
    session_id="$(jq -r '.session.session_id' "$RECORD_FILE")"
    sanitize_session_id "$session_id" >/dev/null
    sanitize_callback_token "$(jq -r '.session.callback_token' "$RECORD_FILE")" >/dev/null

    path="$(record_path_for "$session_id")"
    tmp="${path}.tmp"
    jq '.' "$RECORD_FILE" > "$tmp"
    mv "$tmp" "$path"
    cp "$path" "$(audit_path_for "$session_id")"
    render_json "$path"
}

get_record() {
    [[ -n "$SESSION_ID" ]] || fail "--session-id is required for get"
    local path
    path="$(record_path_for "$SESSION_ID")"
    [[ -f "$path" ]] || fail "advisory session not found: $SESSION_ID"
    render_json "$path"
}

bind_message() {
    [[ -n "$SESSION_ID" ]] || fail "--session-id is required for bind-message"
    [[ "$MESSAGE_ID" =~ ^[1-9][0-9]*$ ]] || fail "--message-id must be a positive integer"

    local path tmp
    path="$(record_path_for "$SESSION_ID")"
    [[ -f "$path" ]] || fail "advisory session not found: $SESSION_ID"
    tmp="${path}.tmp"

    jq --argjson message_id "$MESSAGE_ID" '
        .alert.message_id = $message_id |
        .alert.status = "sent" |
        .interaction_record.message_id = $message_id |
        .audit_notes = ((.audit_notes // []) + ["alert_message_id attached"])
    ' "$path" > "$tmp"
    mv "$tmp" "$path"
    ensure_audit_dir
    cp "$path" "$(audit_path_for "$SESSION_ID")"
    render_json "$path"
}

resolve_record() {
    [[ -n "$SESSION_ID" ]] || fail "--session-id is required for resolve"
    [[ -n "$DECISION" ]] || fail "--decision is required for resolve"
    [[ -n "$RESOLVED_VIA" ]] || fail "--resolved-via is required for resolve"
    [[ -n "$TELEGRAM_ACTOR_ID" ]] || fail "--telegram-actor-id is required for resolve"
    [[ -n "$RAW_INPUT" ]] || fail "--raw-input is required for resolve"

    case "$DECISION" in
        accept|decline|expired|duplicate) ;;
        *) fail "invalid decision: $DECISION" ;;
    esac
    case "$RESOLVED_VIA" in
        callback_query|tokenized_recovery|operator_override) ;;
        *) fail "invalid resolved-via value: $RESOLVED_VIA" ;;
    esac

    local path tmp resolved_at
    path="$(record_path_for "$SESSION_ID")"
    [[ -f "$path" ]] || fail "advisory session not found: $SESSION_ID"
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
            session_id: .session.session_id,
            decision: $decision,
            resolved_at: $resolved_at,
            resolved_via: $resolved_via,
            telegram_actor_id: $telegram_actor_id,
            raw_input: $raw_input
        }
        | (if $note != "" then .decision.note = $note else . end)
        | .session.status = (
            if $decision == "accept" then "accepted"
            elif $decision == "decline" then "declined"
            elif $decision == "expired" then "expired"
            else .session.status
            end
          )
        | .session.resolved_at = (
            if $decision == "duplicate" then (.session.resolved_at // $resolved_at) else $resolved_at end
          )
        | .interaction_record.decision = $decision
        | .interaction_record.decision_source = $resolved_via
        | .interaction_record.resolved_at = $resolved_at
        | .audit_notes = ((.audit_notes // []) + ["decision:" + $decision + " via " + $resolved_via])
        | (if $note != "" then .audit_notes = (.audit_notes + [$note]) else . end)
    ' "$path" > "$tmp"
    mv "$tmp" "$path"
    ensure_audit_dir
    cp "$path" "$(audit_path_for "$SESSION_ID")"
    render_json "$path"
}

mark_followup() {
    [[ -n "$SESSION_ID" ]] || fail "--session-id is required for mark-followup"
    [[ -n "$FOLLOWUP_STATUS" ]] || fail "--followup-status is required for mark-followup"

    case "$FOLLOWUP_STATUS" in
        not_requested|awaiting_user|sent|suppressed|retry|failed) ;;
        *) fail "invalid followup status: $FOLLOWUP_STATUS" ;;
    esac

    if [[ -n "$MESSAGE_ID" ]] && [[ ! "$MESSAGE_ID" =~ ^[1-9][0-9]*$ ]]; then
        fail "--message-id must be a positive integer"
    fi

    local path tmp recorded_at
    path="$(record_path_for "$SESSION_ID")"
    [[ -f "$path" ]] || fail "advisory session not found: $SESSION_ID"
    recorded_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    tmp="${path}.tmp"

    jq \
        --arg followup_status "$FOLLOWUP_STATUS" \
        --arg message_id "$MESSAGE_ID" \
        --arg followup_error "$FOLLOWUP_ERROR" \
        --arg recorded_at "$recorded_at" \
        --arg note "$NOTE" \
        '
        .interaction_record.followup_status = $followup_status
        | .interaction_record.resolved_at = (.interaction_record.resolved_at // $recorded_at)
        | (
            if $followup_status == "sent" then
                .followup = {
                    message_id: (if $message_id == "" then null else ($message_id | tonumber) end),
                    sent_at: $recorded_at
                }
            elif $followup_status == "suppressed" then
                .followup = {
                    message_id: null,
                    suppressed_at: $recorded_at
                }
            else
                .followup = {
                    message_id: (if $message_id == "" then null else ($message_id | tonumber) end),
                    updated_at: $recorded_at
                }
            end
          )
        | (
            if $followup_error == "" then
                del(.followup.error)
            else
                .followup.error = $followup_error
            end
          )
        | .audit_notes = ((.audit_notes // []) + ["followup:" + $followup_status])
        | (if $note != "" then .audit_notes = (.audit_notes + [$note]) else . end)
    ' "$path" > "$tmp"
    mv "$tmp" "$path"
    ensure_audit_dir
    cp "$path" "$(audit_path_for "$SESSION_ID")"
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
        bind-message)
            bind_message
            ;;
        resolve)
            resolve_record
            ;;
        mark-followup)
            mark_followup
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
