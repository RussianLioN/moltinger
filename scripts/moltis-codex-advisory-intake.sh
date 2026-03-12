#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_SCHEMA_PATH="${PROJECT_ROOT}/specs/021-moltis-native-codex-update-advisory/contracts/advisory-event.schema.json"
DEFAULT_TELEGRAM_SEND_SCRIPT="${PROJECT_ROOT}/scripts/telegram-bot-send.sh"
DEFAULT_AUDIT_DIR="${PROJECT_ROOT}/.tmp/current/codex-advisory-intake-audit"

EVENT_FILE=""
JSON_OUT=""
SUMMARY_OUT=""
STDOUT_FORMAT="summary"
SEND_ALERT="${MOLTIS_CODEX_ADVISORY_SEND_ALERT:-false}"
FORCE_ONE_WAY=false
TELEGRAM_CHAT_ID="${MOLTIS_CODEX_ADVISORY_TELEGRAM_CHAT_ID:-}"
TELEGRAM_ENV_FILE="${MOLTIS_CODEX_ADVISORY_TELEGRAM_ENV_FILE:-${MOLTIS_ENV_FILE:-}}"
TELEGRAM_SEND_SCRIPT="${MOLTIS_CODEX_ADVISORY_TELEGRAM_SEND_SCRIPT:-${DEFAULT_TELEGRAM_SEND_SCRIPT}}"
AUDIT_DIR="${MOLTIS_CODEX_ADVISORY_AUDIT_DIR:-${DEFAULT_AUDIT_DIR}}"
SCHEMA_PATH="${MOLTIS_CODEX_ADVISORY_EVENT_SCHEMA:-${DEFAULT_SCHEMA_PATH}}"
CALLBACK_PREFIX="${MOLTIS_CODEX_ADVISORY_CALLBACK_PREFIX:-codex-advisory}"
DEGRADED_REASON="${MOLTIS_CODEX_ADVISORY_DEGRADED_REASON:-Interactive callback path пока не подтверждён; отправляем только one-way alert.}"

TEMP_DIR=""
RENDER_PATH=""
SUMMARY_PATH=""

usage() {
    cat <<'EOF'
Usage:
  moltis-codex-advisory-intake.sh [options]

Render or deliver one Moltis-native Codex advisory alert from a normalized event.

Options:
  --event-file PATH            Read one Codex advisory event JSON from PATH
  --chat-id ID                 Telegram chat id for delivery
  --telegram-env-file PATH     Env file for Telegram sender
  --telegram-send-script PATH  Telegram sender script
  --audit-dir PATH             Directory for machine-readable audit records
  --schema-path PATH           Advisory event schema path for operator reference
  --send true|false            Deliver the alert via Telegram (default: false)
  --force-one-way              Force degraded one-way rendering even if the event is interactive-ready
  --callback-prefix PREFIX     Prefix for inline callback payloads
  --degraded-reason TEXT       Human-readable degraded reason for one-way mode
  --json-out PATH              Write machine-readable result to PATH
  --summary-out PATH           Write summary to PATH
  --stdout MODE                summary|json|none (default: summary)
  -h, --help                   Show help
EOF
}

cleanup() {
    if [[ -n "${TEMP_DIR}" && -d "${TEMP_DIR}" ]]; then
        rm -rf "${TEMP_DIR}"
    fi
}
trap cleanup EXIT

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing required dependency: $1"
}

ensure_parent_dir() {
    mkdir -p "$(dirname "$1")"
}

normalize_bool() {
    case "${1:-}" in
        true|1|yes|on) printf 'true\n' ;;
        false|0|no|off|'') printf 'false\n' ;;
        *) fail "Invalid boolean value: $1" ;;
    esac
}

validate_event_file() {
    local path="$1"
    jq -e '
        .schema_version == "codex-advisory-event/v1" and
        (.event_id | type == "string" and length > 0) and
        (.created_at | type == "string" and length > 0) and
        (.source == "codex-cli-upstream-watcher") and
        (.upstream_fingerprint | type == "string" and length >= 8) and
        (.latest_version | type == "string" and length > 0) and
        (.severity | IN("normal", "important", "critical", "investigate")) and
        (.summary_ru | type == "string" and length > 0) and
        (.why_it_matters_ru | type == "string" and length > 0) and
        (.highlights_ru | type == "array" and length >= 1) and
        (.recommendation_status | IN("ready", "deferred", "unavailable")) and
        (.interactive_followup_eligible | type == "boolean")
    ' "$path" >/dev/null 2>&1 || fail "Advisory event does not match the expected shape"
}

run_sender() {
    local chat_id="$1"
    local text="$2"
    local reply_markup_json="${3:-}"
    local -a cmd=(
        "$TELEGRAM_SEND_SCRIPT"
        --chat-id "$chat_id"
        --text "$text"
        --json
    )

    if [[ -n "$reply_markup_json" ]]; then
        cmd+=(--reply-markup-json "$reply_markup_json")
    fi

    if [[ -n "$TELEGRAM_ENV_FILE" ]]; then
        MOLTIS_ENV_FILE="$TELEGRAM_ENV_FILE" "${cmd[@]}"
    else
        "${cmd[@]}"
    fi
}

render_result() {
    local interactive_mode="$1"
    local degraded_reason="$2"
    local chat_id="$3"

    jq \
        --arg interactive_mode "$interactive_mode" \
        --arg degraded_reason "$degraded_reason" \
        --arg chat_id "$chat_id" \
        --arg schema_path "$SCHEMA_PATH" \
        --arg callback_prefix "$CALLBACK_PREFIX" '
        def severity_label(value):
          if value == "normal" then "обычная"
          elif value == "important" then "высокая"
          elif value == "critical" then "критическая"
          elif value == "investigate" then "нужно проверить"
          else value
          end;
        def alert_lines:
          [
            "Обновление Codex CLI",
            "Последняя версия из официального источника: \(.latest_version)",
            "Важность: \(severity_label(.severity))",
            "Почему это важно: \(.why_it_matters_ru)",
            "Простыми словами:"
          ]
          + (.highlights_ru | map("- " + .))
          + (
            if (.recommendation_payload.summary_ru // "") != ""
            then [
              "Что это может дать проекту:",
              "- \(.recommendation_payload.summary_ru)"
            ]
            else []
            end
          )
          + (
            if $interactive_mode == "inline_callbacks"
            then [
              "",
              "Если нужны практические рекомендации для проекта, используйте inline-кнопки ниже."
            ]
            else [
              "",
              "Сейчас это one-way alert: интерактивный follow-up временно выключен.",
              "Причина: \($degraded_reason)"
            ]
            end
          );
        {
          schema_version: "codex-advisory-intake/v1",
          status: "rendered",
          source_schema_path: $schema_path,
          event: .,
          alert: {
            alert_id: ("alert-" + .event_id),
            event_id: .event_id,
            chat_id: (if $chat_id == "" then null else $chat_id end),
            message_id: null,
            interactive_mode: $interactive_mode,
            message_text: (alert_lines | join("\n")),
            reply_markup: (
              if $interactive_mode == "inline_callbacks"
              then {
                inline_keyboard: [[
                  {
                    text: "Получить рекомендации",
                    callback_data: ($callback_prefix + ":accept:" + .event_id)
                  },
                  {
                    text: "Не сейчас",
                    callback_data: ($callback_prefix + ":decline:" + .event_id)
                  }
                ]]
              }
              else null
              end
            )
          },
          interaction_record: {
            schema_version: "codex-advisory-interaction/v1",
            event_id: .event_id,
            alert_id: ("alert-" + .event_id),
            chat_id: (if $chat_id == "" then null else $chat_id end),
            message_id: null,
            interactive_mode: $interactive_mode,
            decision: "none",
            decision_source: "none",
            followup_status: (if $interactive_mode == "inline_callbacks" then "awaiting_user" else "not_requested" end),
            degraded_reason: (if $interactive_mode == "inline_callbacks" then "" else $degraded_reason end),
            created_at: .created_at,
            resolved_at: null
          }
        }
    ' "$EVENT_FILE" > "$RENDER_PATH"
}

write_audit_record() {
    local event_id
    event_id="$(jq -r '.event.event_id' "$RENDER_PATH")"
    [[ "$event_id" =~ ^[A-Za-z0-9._:-]+$ ]] || fail "Invalid event id for audit record: $event_id"
    mkdir -p "$AUDIT_DIR"
    jq '.interaction_record' "$RENDER_PATH" > "${AUDIT_DIR}/${event_id}.json"
}

patch_delivery_success() {
    local chat_id="$1"
    local message_id="$2"
    jq \
        --arg chat_id "$chat_id" \
        --argjson message_id "$message_id" '
        .status = "sent" |
        .alert.chat_id = $chat_id |
        .alert.message_id = $message_id |
        .interaction_record.chat_id = $chat_id |
        .interaction_record.message_id = $message_id
    ' "$RENDER_PATH" > "${RENDER_PATH}.tmp"
    mv "${RENDER_PATH}.tmp" "$RENDER_PATH"
}

patch_delivery_failure() {
    local error_text="$1"
    jq \
        --arg error_text "$error_text" '
        .status = "failed" |
        .delivery_error = $error_text
    ' "$RENDER_PATH" > "${RENDER_PATH}.tmp"
    mv "${RENDER_PATH}.tmp" "$RENDER_PATH"
}

render_summary() {
    jq -r '
      def mode_label(value):
        if value == "inline_callbacks" then "interactive-ready"
        elif value == "one_way_only" then "one-way"
        else value
        end;
      [
        "# Moltis-native Codex advisory",
        "",
        "- Статус: \(.status)",
        "- Event id: \(.event.event_id)",
        "- Последняя версия: \(.event.latest_version)",
        "- Важность: \(.event.severity)",
        "- Режим интерактивности: \(mode_label(.alert.interactive_mode))",
        (if (.alert.chat_id // "") != "" then "- Telegram chat id: \(.alert.chat_id)" else empty end),
        (if (.alert.message_id // null) != null then "- Telegram message id: \(.alert.message_id)" else empty end),
        (if (.interaction_record.degraded_reason // "") != "" then "- Причина деградации: \(.interaction_record.degraded_reason)" else empty end),
        "",
        "## Текст уведомления",
        .alert.message_text
      ] | join("\n")
    ' "$RENDER_PATH"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --event-file)
                EVENT_FILE="${2:?missing value for --event-file}"
                shift 2
                ;;
            --chat-id)
                TELEGRAM_CHAT_ID="${2:?missing value for --chat-id}"
                shift 2
                ;;
            --telegram-env-file)
                TELEGRAM_ENV_FILE="${2:?missing value for --telegram-env-file}"
                shift 2
                ;;
            --telegram-send-script)
                TELEGRAM_SEND_SCRIPT="${2:?missing value for --telegram-send-script}"
                shift 2
                ;;
            --audit-dir)
                AUDIT_DIR="${2:?missing value for --audit-dir}"
                shift 2
                ;;
            --schema-path)
                SCHEMA_PATH="${2:?missing value for --schema-path}"
                shift 2
                ;;
            --send)
                SEND_ALERT="$(normalize_bool "${2:?missing value for --send}")"
                shift 2
                ;;
            --force-one-way)
                FORCE_ONE_WAY=true
                shift
                ;;
            --callback-prefix)
                CALLBACK_PREFIX="${2:?missing value for --callback-prefix}"
                shift 2
                ;;
            --degraded-reason)
                DEGRADED_REASON="${2:?missing value for --degraded-reason}"
                shift 2
                ;;
            --json-out)
                JSON_OUT="${2:?missing value for --json-out}"
                shift 2
                ;;
            --summary-out)
                SUMMARY_OUT="${2:?missing value for --summary-out}"
                shift 2
                ;;
            --stdout)
                STDOUT_FORMAT="${2:?missing value for --stdout}"
                shift 2
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

    [[ -n "$EVENT_FILE" ]] || fail "--event-file is required"
    [[ -f "$EVENT_FILE" ]] || fail "Event file not found: $EVENT_FILE"
    case "$STDOUT_FORMAT" in
        summary|json|none) ;;
        *) fail "Invalid --stdout mode: $STDOUT_FORMAT" ;;
    esac
}

main() {
    require_command jq

    parse_args "$@"
    validate_event_file "$EVENT_FILE"

    TEMP_DIR="$(mktemp -d)"
    RENDER_PATH="${TEMP_DIR}/render.json"
    SUMMARY_PATH="${TEMP_DIR}/summary.md"

    local event_interactive_ready interactive_mode reply_markup_json send_output send_code message_id
    event_interactive_ready="$(jq -r '.interactive_followup_eligible' "$EVENT_FILE")"
    interactive_mode="one_way_only"
    if [[ "$FORCE_ONE_WAY" != "true" && "$event_interactive_ready" == "true" ]]; then
        interactive_mode="inline_callbacks"
    fi

    render_result "$interactive_mode" "$DEGRADED_REASON" "$TELEGRAM_CHAT_ID"

    if [[ "$SEND_ALERT" == "true" ]]; then
        [[ -n "$TELEGRAM_CHAT_ID" ]] || fail "--chat-id is required when --send true"
        [[ -x "$TELEGRAM_SEND_SCRIPT" ]] || fail "Telegram sender script is not executable: $TELEGRAM_SEND_SCRIPT"
        reply_markup_json="$(jq -c '.alert.reply_markup // empty' "$RENDER_PATH")"
        set +e
        send_output="$(run_sender "$TELEGRAM_CHAT_ID" "$(jq -r '.alert.message_text' "$RENDER_PATH")" "$reply_markup_json" 2>&1)"
        send_code=$?
        set -e
        if [[ $send_code -eq 0 ]]; then
            message_id="$(printf '%s' "$send_output" | jq -r '.result.message_id // 0' 2>/dev/null || true)"
            if [[ "$message_id" =~ ^[1-9][0-9]*$ ]]; then
                patch_delivery_success "$TELEGRAM_CHAT_ID" "$message_id"
            else
                patch_delivery_failure "Telegram sender returned success without message_id"
                write_audit_record
                exit 1
            fi
        else
            patch_delivery_failure "${send_output:-telegram sender exited with status ${send_code}}"
            write_audit_record
            exit 1
        fi
    fi

    write_audit_record
    render_summary > "$SUMMARY_PATH"

    if [[ -n "$JSON_OUT" ]]; then
        ensure_parent_dir "$JSON_OUT"
        cp "$RENDER_PATH" "$JSON_OUT"
    fi

    if [[ -n "$SUMMARY_OUT" ]]; then
        ensure_parent_dir "$SUMMARY_OUT"
        cp "$SUMMARY_PATH" "$SUMMARY_OUT"
    fi

    case "$STDOUT_FORMAT" in
        summary)
            cat "$SUMMARY_PATH"
            ;;
        json)
            cat "$RENDER_PATH"
            ;;
        none)
            ;;
    esac
}

main "$@"
