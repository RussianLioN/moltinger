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
JSON_OUTPUT=true

usage() {
    cat <<'EOF'
Usage:
  moltis-codex-update-state.sh <command> [options]

Commands:
  get             Print the current Moltis-native Codex update state
  update          Update last seen/run fields after a skill run
  mark-delivered  Persist the last alert fingerprint and delivery time

Options:
  --state-file PATH        Path to the state file
  --run-mode MODE          manual|scheduler
  --fingerprint VALUE      Latest upstream fingerprint
  --latest-version VALUE   Latest upstream version
  --decision VALUE         ignore|upgrade-later|upgrade-now|investigate
  --delivery-status VALUE  not-attempted|suppressed|sent|failed
  --degraded-reason TEXT   Optional degraded-mode explanation
  --alert-fingerprint VAL  Fingerprint that was delivered
  --alert-at ISO8601       Delivery timestamp override
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
            --arg degraded_reason "$DEGRADED_REASON" \
            '
            .schema_version = "moltis-codex-update-state/v1" |
            .last_seen_fingerprint = $fingerprint |
            .last_seen_version = $latest_version |
            .last_run_at = $ts |
            .last_run_mode = $run_mode |
            .last_result = $decision |
            .last_delivery_status = $delivery_status |
            .degraded_reason = $degraded_reason
            ' <<<"$current_json"
    )"
    write_state_json "$next_json"
    print_result
}

command_mark_delivered() {
    [[ -n "$ALERT_FINGERPRINT" ]] || fail "--alert-fingerprint is required for mark-delivered"
    local ts current_json next_json
    ts="${ALERT_AT:-$(current_timestamp)}"
    current_json="$(read_state_json "$STATE_FILE")"
    next_json="$(
        jq \
            --arg ts "$ts" \
            --arg alert_fingerprint "$ALERT_FINGERPRINT" \
            '
            .schema_version = "moltis-codex-update-state/v1" |
            .last_alert_fingerprint = $alert_fingerprint |
            .last_alert_at = $ts
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
        mark-delivered)
            command_mark_delivered
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
