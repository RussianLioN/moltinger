#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_INTAKE_SCRIPT="${PROJECT_ROOT}/scripts/moltis-codex-advisory-intake.sh"
DEFAULT_TELEGRAM_SEND_SCRIPT="${PROJECT_ROOT}/scripts/telegram-bot-send.sh"
DEFAULT_CONFIG_FILE="${PROJECT_ROOT}/config/moltis.toml"
DEFAULT_AUDIT_DIR="${PROJECT_ROOT}/.tmp/current/codex-advisory-intake-audit"
DEFAULT_SESSION_STORE_SCRIPT="${PROJECT_ROOT}/scripts/codex-advisory-session-store.sh"
DEFAULT_SESSION_STORE_DIR="${PROJECT_ROOT}/.tmp/current/codex-advisory-session-store"

CHAT_ID=""
TEXT=""
MOLTIS_ENV_FILE="${MOLTIS_ENV_FILE:-.env}"
CONFIG_FILE="${MOLTIS_CONFIG_FILE:-${DEFAULT_CONFIG_FILE}}"
ADVISORY_EVENT_FILE="${MOLTIS_CODEX_ADVISORY_EVENT_FILE:-${CODEX_UPSTREAM_WATCHER_ADVISORY_EVENT_OUT:-}}"

show_help() {
    cat <<'EOF'
Usage:
  moltis-codex-advisory-send.sh --chat-id CHAT --text "ignored watcher text" [options]

Adapter that preserves the telegram-bot-send.sh CLI contract for the upstream
watcher but routes the actual Telegram delivery through Moltis-native advisory
intake, using the normalized advisory event file as the source of truth.

Required:
  --chat-id CHAT_ID           Telegram chat id
  --text MESSAGE              Compatibility argument; advisory intake renders the real message

Optional:
  --reply-to MESSAGE_ID       Ignored for alert delivery (kept for CLI compatibility)
  --reply-markup-json JSON    Ignored for alert delivery (kept for CLI compatibility)
  --disable-notification      Ignored for alert delivery unless the underlying sender uses it
  --parse-mode MODE           Ignored
  --json                      JSON output (default)
  -h, --help                  Show help

Environment:
  CODEX_UPSTREAM_WATCHER_ADVISORY_EVENT_OUT / MOLTIS_CODEX_ADVISORY_EVENT_FILE
                              Path to the normalized advisory event JSON
  MOLTIS_CODEX_ADVISORY_INTAKE_SCRIPT
                              Override advisory intake helper path
  MOLTIS_CODEX_ADVISORY_TELEGRAM_SEND_SCRIPT
                              Underlying real Telegram sender for intake
  MOLTIS_CODEX_ADVISORY_INTERACTIVE_MODE
                              one_way_only|inline_callbacks (fallbacks to config/moltis.toml env section)
  MOLTIS_CONFIG_FILE          Moltis config path for env fallbacks
  MOLTIS_ENV_FILE             Env file passed to the real Telegram sender
EOF
}

fail_json() {
    local message="$1"
    printf '{"ok":false,"error":%s,"script":"%s"}\n' "$(jq -Rn --arg v "$message" '$v')" "$SCRIPT_NAME"
    exit 1
}

require_bin() {
    command -v "$1" >/dev/null 2>&1 || fail_json "Missing dependency: $1"
}

resolve_env_value() {
    local key="$1"
    local default_value="${2:-}"
    local direct_value="${!key:-}"
    if [[ -n "$direct_value" ]]; then
        printf '%s\n' "$direct_value"
        return 0
    fi

    if [[ -f "$CONFIG_FILE" ]]; then
        local config_value=""
        config_value="$(python3 - <<'PY' "$CONFIG_FILE" "$key" 2>/dev/null || true
import sys
try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib
path, key = sys.argv[1], sys.argv[2]
with open(path, "rb") as fh:
    data = tomllib.load(fh)
env = data.get("env", {})
value = env.get(key, "")
if isinstance(value, bool):
    print("true" if value else "false")
elif value is None:
    print("")
else:
    print(str(value))
PY
)"
        if [[ -n "$config_value" ]]; then
            printf '%s\n' "$config_value"
            return 0
        fi
    fi

    printf '%s\n' "$default_value"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --chat-id)
                CHAT_ID="${2:-}"
                shift 2
                ;;
            --text)
                TEXT="${2:-}"
                shift 2
                ;;
            --reply-to|--reply-markup-json|--parse-mode)
                shift 2
                ;;
            --disable-notification|--json)
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                fail_json "Unknown argument: $1"
                ;;
        esac
    done

    [[ -n "$CHAT_ID" ]] || fail_json "--chat-id is required"
    [[ -n "$TEXT" ]] || fail_json "--text is required"
    [[ -n "$ADVISORY_EVENT_FILE" ]] || fail_json "Normalized advisory event path is not configured"
    [[ -f "$ADVISORY_EVENT_FILE" ]] || fail_json "Normalized advisory event file not found: $ADVISORY_EVENT_FILE"
}

main() {
    require_bin jq
    require_bin python3

    parse_args "$@"

    local intake_script actual_sender interactive_mode audit_dir session_store_script session_store_dir callback_window_hours recovery_command callback_prefix intake_output intake_message_id
    intake_script="$(resolve_env_value "MOLTIS_CODEX_ADVISORY_INTAKE_SCRIPT" "$DEFAULT_INTAKE_SCRIPT")"
    actual_sender="$(resolve_env_value "MOLTIS_CODEX_ADVISORY_TELEGRAM_SEND_SCRIPT" "$DEFAULT_TELEGRAM_SEND_SCRIPT")"
    interactive_mode="$(resolve_env_value "MOLTIS_CODEX_ADVISORY_INTERACTIVE_MODE" "one_way_only")"
    audit_dir="$(resolve_env_value "MOLTIS_CODEX_ADVISORY_AUDIT_DIR" "$DEFAULT_AUDIT_DIR")"
    session_store_script="$(resolve_env_value "MOLTIS_CODEX_ADVISORY_SESSION_STORE_SCRIPT" "$DEFAULT_SESSION_STORE_SCRIPT")"
    session_store_dir="$(resolve_env_value "MOLTIS_CODEX_ADVISORY_SESSION_STORE_DIR" "$DEFAULT_SESSION_STORE_DIR")"
    callback_window_hours="$(resolve_env_value "MOLTIS_CODEX_ADVISORY_CALLBACK_WINDOW_HOURS" "24")"
    recovery_command="$(resolve_env_value "MOLTIS_CODEX_ADVISORY_RECOVERY_COMMAND" "/codex-advisory-followup")"
    callback_prefix="$(resolve_env_value "MOLTIS_CODEX_ADVISORY_CALLBACK_PREFIX" "codex-advisory")"

    [[ -x "$intake_script" ]] || fail_json "Advisory intake script is not executable: $intake_script"
    [[ -x "$actual_sender" ]] || fail_json "Underlying Telegram sender is not executable: $actual_sender"
    [[ -x "$session_store_script" ]] || fail_json "Advisory session store helper is not executable: $session_store_script"

    set +e
    intake_output="$(
        "$intake_script" \
            --event-file "$ADVISORY_EVENT_FILE" \
            --chat-id "$CHAT_ID" \
            --telegram-send-script "$actual_sender" \
            --telegram-env-file "$MOLTIS_ENV_FILE" \
            --interactive-mode "$interactive_mode" \
            --audit-dir "$audit_dir" \
            --session-store-script "$session_store_script" \
            --session-store-dir "$session_store_dir" \
            --callback-window-hours "$callback_window_hours" \
            --recovery-command "$recovery_command" \
            --callback-prefix "$callback_prefix" \
            --send true \
            --stdout json \
            2>&1
    )"
    if [[ $? -ne 0 ]]; then
        set -e
        fail_json "${intake_output:-advisory intake delivery failed}"
    fi
    set -e

    intake_message_id="$(printf '%s' "$intake_output" | jq -r '.alert.message_id // ""' 2>/dev/null || true)"
    [[ "$intake_message_id" =~ ^[1-9][0-9]*$ ]] || fail_json "Advisory intake did not return a Telegram message id"

    jq -cn \
        --argjson message_id "$intake_message_id" \
        --arg mode "$interactive_mode" \
        --arg event_file "$ADVISORY_EVENT_FILE" \
        '{
            ok: true,
            result: {
                message_id: $message_id
            },
            transport: "moltis-codex-advisory-send",
            interactive_mode: $mode,
            advisory_event_file: $event_file
        }'
}

main "$@"
