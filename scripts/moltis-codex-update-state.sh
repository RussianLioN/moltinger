#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_STATE_FILE="${PROJECT_ROOT}/.tmp/current/moltis-codex-update-state.json"

STATE_FILE="${MOLTIS_CODEX_UPDATE_STATE_FILE:-${DEFAULT_STATE_FILE}}"
COMMAND="${1:-}"
RUN_MODE=""
FINGERPRINT=""
LATEST_VERSION=""
DECISION=""
DELIVERY_STATUS=""
DEGRADED_REASON=""
ALERT_FINGERPRINT=""
ALERT_AT=""
DELIVERY_ERROR=""
MESSAGE_ID=""
JSON_OUTPUT=true

usage() {
    cat <<'EOF'
Usage:
  moltis-codex-update-state.sh <command> [options]

Commands:
  get             Print the current Moltis-native Codex update state
  update          Update last seen/run fields after a skill run
  mark-delivery   Persist scheduler delivery status and alert checkpoint
  mark-delivered  Backward-compatible alias for mark-delivery

Options:
  --state-file PATH        Path to the state file
  --run-mode MODE          manual|scheduler
  --fingerprint VALUE      Latest upstream fingerprint
  --latest-version VALUE   Latest upstream version
  --decision VALUE         ignore|upgrade-later|upgrade-now|investigate
  --delivery-status VALUE  not-attempted|deferred|not-configured|suppressed|sent|failed
  --degraded-reason TEXT   Optional degraded-mode explanation
  --alert-fingerprint VAL  Fingerprint that was delivered
  --alert-at ISO8601       Delivery timestamp override
  --delivery-error TEXT    Optional delivery error details
  --message-id N           Optional Telegram message id for sent delivery
  --json                   Print JSON output (default)
  -h, --help               Show help
EOF
}

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

ensure_parent_dir() {
    mkdir -p "$(dirname "$1")"
}

current_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

parse_args() {
    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --state-file)
                STATE_FILE="${2:?missing value for --state-file}"
                shift 2
                ;;
            --run-mode)
                RUN_MODE="${2:?missing value for --run-mode}"
                shift 2
                ;;
            --fingerprint)
                FINGERPRINT="${2:?missing value for --fingerprint}"
                shift 2
                ;;
            --latest-version)
                LATEST_VERSION="${2:?missing value for --latest-version}"
                shift 2
                ;;
            --decision)
                DECISION="${2:?missing value for --decision}"
                shift 2
                ;;
            --delivery-status)
                DELIVERY_STATUS="${2:?missing value for --delivery-status}"
                shift 2
                ;;
            --degraded-reason)
                DEGRADED_REASON="${2:?missing value for --degraded-reason}"
                shift 2
                ;;
            --alert-fingerprint)
                ALERT_FINGERPRINT="${2:?missing value for --alert-fingerprint}"
                shift 2
                ;;
            --alert-at)
                ALERT_AT="${2:?missing value for --alert-at}"
                shift 2
                ;;
            --delivery-error)
                [[ $# -ge 2 ]] || fail "missing value for --delivery-error"
                DELIVERY_ERROR="${2-}"
                shift 2
                ;;
            --message-id)
                MESSAGE_ID="${2:?missing value for --message-id}"
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

default_state_json() {
    cat <<'EOF'
{
  "schema_version": "moltis-codex-update-state/v1",
  "last_seen_fingerprint": "",
  "last_seen_version": "",
  "last_alert_fingerprint": "",
  "last_alert_at": "",
  "last_run_at": "",
  "last_run_mode": "",
  "last_result": "",
  "last_delivery_status": "",
  "last_delivery_error": "",
  "last_delivery_attempt_at": "",
  "last_alert_message_id": 0,
  "degraded_reason": ""
}
EOF
}

read_state_json() {
    local path="$1"
    if [[ -f "$path" ]]; then
        cat "$path"
    else
        default_state_json
    fi
}

write_state_json() {
    local json_payload="$1"
    ensure_parent_dir "$STATE_FILE"
    printf '%s\n' "$json_payload" > "$STATE_FILE"
}

print_result() {
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        cat "$STATE_FILE"
    fi
}

command_get() {
    local current_json
    current_json="$(read_state_json "$STATE_FILE")"
    ensure_parent_dir "$STATE_FILE"
    if [[ ! -f "$STATE_FILE" ]]; then
        printf '%s\n' "$current_json" > "$STATE_FILE"
    fi
    print_result
}

command_update() {
    [[ -n "$RUN_MODE" ]] || fail "--run-mode is required for update"
    [[ -n "$FINGERPRINT" ]] || fail "--fingerprint is required for update"
    [[ -n "$LATEST_VERSION" ]] || fail "--latest-version is required for update"
    [[ -n "$DECISION" ]] || fail "--decision is required for update"

    case "$RUN_MODE" in
        manual|scheduler) ;;
        *) fail "Invalid --run-mode: $RUN_MODE" ;;
    esac

    case "$DECISION" in
        ignore|upgrade-later|upgrade-now|investigate) ;;
        *) fail "Invalid --decision: $DECISION" ;;
    esac

    case "${DELIVERY_STATUS:-}" in
        ""|not-attempted|deferred|not-configured|suppressed|sent|failed) ;;
        *) fail "Invalid --delivery-status: $DELIVERY_STATUS" ;;
    esac

    local ts current_json next_json
    ts="$(current_timestamp)"
    current_json="$(read_state_json "$STATE_FILE")"
    next_json="$(
        jq \
            --arg ts "$ts" \
            --arg run_mode "$RUN_MODE" \
            --arg fingerprint "$FINGERPRINT" \
            --arg latest_version "$LATEST_VERSION" \
            --arg decision "$DECISION" \
            --arg delivery_status "$DELIVERY_STATUS" \
            --arg delivery_error "$DELIVERY_ERROR" \
            --arg degraded_reason "$DEGRADED_REASON" \
            '
            .schema_version = "moltis-codex-update-state/v1" |
            .last_seen_fingerprint = $fingerprint |
            .last_seen_version = $latest_version |
            .last_run_at = $ts |
            .last_run_mode = $run_mode |
            .last_result = $decision |
            .last_delivery_status = $delivery_status |
            .last_delivery_error = $delivery_error |
            .last_delivery_attempt_at = (if $delivery_status == "" then .last_delivery_attempt_at else $ts end) |
            .degraded_reason = $degraded_reason
            ' <<<"$current_json"
    )"
    write_state_json "$next_json"
    print_result
}

command_mark_delivery() {
    [[ -n "$DELIVERY_STATUS" ]] || fail "--delivery-status is required for mark-delivery"
    case "$DELIVERY_STATUS" in
        deferred|not-configured|suppressed|sent|failed|not-attempted) ;;
        *) fail "Invalid --delivery-status: $DELIVERY_STATUS" ;;
    esac
    if [[ -n "$MESSAGE_ID" && ! "$MESSAGE_ID" =~ ^[0-9]+$ ]]; then
        fail "--message-id must be numeric"
    fi

    local ts current_json next_json
    ts="${ALERT_AT:-$(current_timestamp)}"
    current_json="$(read_state_json "$STATE_FILE")"
    next_json="$(
        jq \
            --arg ts "$ts" \
            --arg alert_fingerprint "$ALERT_FINGERPRINT" \
            --arg delivery_status "$DELIVERY_STATUS" \
            --arg delivery_error "$DELIVERY_ERROR" \
            --argjson message_id "${MESSAGE_ID:-0}" \
            '
            .schema_version = "moltis-codex-update-state/v1" |
            .last_delivery_status = $delivery_status |
            .last_delivery_error = $delivery_error |
            .last_delivery_attempt_at = $ts |
            .last_alert_message_id = (if $message_id > 0 then $message_id else .last_alert_message_id end) |
            .last_alert_fingerprint = (if $alert_fingerprint == "" then .last_alert_fingerprint else $alert_fingerprint end) |
            .last_alert_at = (if $alert_fingerprint == "" then .last_alert_at else $ts end)
            ' <<<"$current_json"
    )"
    write_state_json "$next_json"
    print_result
}

main() {
    parse_args "$@"

    case "$COMMAND" in
        get)
            command_get
            ;;
        update)
            command_update
            ;;
        mark-delivery)
            command_mark_delivery
            ;;
        mark-delivered)
            command_mark_delivery
            ;;
        ""|-h|--help)
            usage
            ;;
        *)
            fail "Unknown command: $COMMAND"
            ;;
    esac
}

main "$@"
