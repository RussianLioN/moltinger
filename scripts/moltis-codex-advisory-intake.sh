#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_SCHEMA_PATH="${PROJECT_ROOT}/specs/021-moltis-native-codex-update-advisory/contracts/advisory-event.schema.json"
DEFAULT_TELEGRAM_SEND_SCRIPT="${PROJECT_ROOT}/scripts/telegram-bot-send.sh"
DEFAULT_AUDIT_DIR="${PROJECT_ROOT}/.tmp/current/codex-advisory-intake-audit"
DEFAULT_SESSION_STORE_SCRIPT="${PROJECT_ROOT}/scripts/codex-advisory-session-store.sh"

EVENT_FILE=""
JSON_OUT=""
SUMMARY_OUT=""
STDOUT_FORMAT="summary"
SEND_ALERT="${MOLTIS_CODEX_ADVISORY_SEND_ALERT:-false}"
FORCE_ONE_WAY=false
INTERACTIVE_MODE="${MOLTIS_CODEX_ADVISORY_INTERACTIVE_MODE:-one_way_only}"
TELEGRAM_CHAT_ID="${MOLTIS_CODEX_ADVISORY_TELEGRAM_CHAT_ID:-}"
TELEGRAM_ENV_FILE="${MOLTIS_CODEX_ADVISORY_TELEGRAM_ENV_FILE:-${MOLTIS_ENV_FILE:-}}"
TELEGRAM_SEND_SCRIPT="${MOLTIS_CODEX_ADVISORY_TELEGRAM_SEND_SCRIPT:-${DEFAULT_TELEGRAM_SEND_SCRIPT}}"
AUDIT_DIR="${MOLTIS_CODEX_ADVISORY_AUDIT_DIR:-${DEFAULT_AUDIT_DIR}}"
SCHEMA_PATH="${MOLTIS_CODEX_ADVISORY_EVENT_SCHEMA:-${DEFAULT_SCHEMA_PATH}}"
CALLBACK_PREFIX="${MOLTIS_CODEX_ADVISORY_CALLBACK_PREFIX:-codex-advisory}"
DEGRADED_REASON="${MOLTIS_CODEX_ADVISORY_DEGRADED_REASON:-Interactive callback path пока не подтверждён; отправляем только one-way alert.}"
SESSION_STORE_SCRIPT="${MOLTIS_CODEX_ADVISORY_SESSION_STORE_SCRIPT:-${DEFAULT_SESSION_STORE_SCRIPT}}"
SESSION_STORE_DIR="${MOLTIS_CODEX_ADVISORY_SESSION_STORE_DIR:-${PROJECT_ROOT}/.tmp/current/codex-advisory-session-store}"
CALLBACK_WINDOW_HOURS="${MOLTIS_CODEX_ADVISORY_CALLBACK_WINDOW_HOURS:-24}"
RECOVERY_COMMAND="${MOLTIS_CODEX_ADVISORY_RECOVERY_COMMAND:-/codex-advisory-followup}"

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
  --interactive-mode MODE      one_way_only|inline_callbacks (default from env)
  --callback-prefix PREFIX     Prefix for inline callback payloads
  --degraded-reason TEXT       Human-readable degraded reason for one-way mode
  --session-store-script PATH  Advisory session store helper path
  --session-store-dir PATH     Directory for advisory sessions
  --callback-window-hours N    Expiry window for interactive follow-up
  --recovery-command TEXT      Recovery-only tokenized fallback command
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

normalize_interactive_mode() {
    case "${1:-}" in
        one_way_only|inline_callbacks) printf '%s\n' "$1" ;;
        *) fail "Invalid interactive mode: $1" ;;
    esac
}

validate_positive_int() {
    [[ "${1:-}" =~ ^[1-9][0-9]*$ ]] || fail "Expected a positive integer, got: ${1:-}"
}

build_session_metadata() {
    python3 - <<'PY' "$EVENT_FILE" "$TELEGRAM_CHAT_ID" "$CALLBACK_WINDOW_HOURS"
import datetime as dt
import hashlib
import json
import secrets
import sys

event_path, chat_id, window_hours = sys.argv[1], sys.argv[2], int(sys.argv[3])
with open(event_path, "r", encoding="utf-8") as fh:
    event = json.load(fh)

seed = f"{event['event_id']}:{chat_id}:{event['created_at']}:{secrets.token_hex(4)}"
session_id = "advsess-" + hashlib.sha256(seed.encode()).hexdigest()[:16]
callback_token = "tok-" + secrets.token_hex(8)
created_at = dt.datetime.now(dt.timezone.utc)
expires_at = created_at + dt.timedelta(hours=window_hours)

print(json.dumps({
    "session_id": session_id,
    "callback_token": callback_token,
    "expires_at": expires_at.strftime("%Y-%m-%dT%H:%M:%SZ"),
}))
PY
}

build_session_record() {
    local session_id="$1"
    local callback_token="$2"
    local expires_at="$3"
    local message_id="$4"

    jq \
        --arg session_id "$session_id" \
        --arg callback_token "$callback_token" \
        --arg expires_at "$expires_at" \
        --arg chat_id "$TELEGRAM_CHAT_ID" \
        --arg interactive_mode "$INTERACTIVE_MODE" \
        --arg recovery_command "$RECOVERY_COMMAND" \
        --arg callback_prefix "$CALLBACK_PREFIX" \
        --argjson message_id "$message_id" \
        '
        {
          schema_version: "codex-advisory-session/v1",
          event: {
            event_id: .event_id,
            created_at: .created_at,
            source: .source,
            upstream_fingerprint: .upstream_fingerprint,
            latest_version: .latest_version,
            severity: .severity,
            summary_ru: .summary_ru,
            why_it_matters_ru: .why_it_matters_ru,
            highlights_ru: (.highlights_ru // []),
            recommendation_status: .recommendation_status,
            interactive_followup_eligible: .interactive_followup_eligible
          },
          alert: {
            alert_id: ("alert-" + .event_id),
            event_id: .event_id,
            chat_id: $chat_id,
            message_id: $message_id,
            delivery_mode: "telegram",
            interactive_mode: $interactive_mode,
            created_at: .created_at,
            status: "sent"
          },
          session: {
            session_id: $session_id,
            alert_id: ("alert-" + .event_id),
            chat_id: $chat_id,
            callback_token: $callback_token,
            expires_at: $expires_at,
            status: "pending",
            resolved_at: null
          },
          recommendation_envelope: {
            event_id: .event_id,
            chat_id: $chat_id,
            headline_ru: (.recommendation_payload.headline_ru // "Практические рекомендации по обновлению Codex CLI"),
            summary_ru: (.recommendation_payload.summary_ru // ""),
            priority_checks: (.recommendation_payload.priority_checks // []),
            impacted_surfaces: (.recommendation_payload.impacted_surfaces // []),
            raw_reference_path: (.recommendation_payload.raw_reference_path // ""),
            items: (
              (.recommendation_payload.items // []) |
              map({
                title: (.title_ru // .title // ""),
                rationale: (.rationale_ru // .rationale // ""),
                impacted_paths: (.impacted_surfaces // .impacted_paths // []),
                next_steps: (.next_steps_ru // .next_steps // [])
              })
            )
          },
          interaction_record: {
            schema_version: "codex-advisory-interaction/v1",
            event_id: .event_id,
            upstream_fingerprint: .upstream_fingerprint,
            alert_id: ("alert-" + .event_id),
            chat_id: $chat_id,
            message_id: $message_id,
            interactive_mode: $interactive_mode,
            decision: "none",
            decision_source: "none",
            followup_status: "awaiting_user",
            degraded_reason: "",
            created_at: .created_at,
            resolved_at: null
          },
          recovery: {
            mode: "tokenized_command",
            accept_command_text: ($recovery_command + " accept " + $session_id + " " + $callback_token),
            decline_command_text: ($recovery_command + " decline " + $session_id + " " + $callback_token)
          },
          audit_notes: [
            "session opened by advisory intake",
            ("callback prefix: " + $callback_prefix)
          ]
        }
    ' "$EVENT_FILE"
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
    local session_id="$4"
    local callback_token="$5"
    local expires_at="$6"

    jq \
        --arg interactive_mode "$interactive_mode" \
        --arg degraded_reason "$degraded_reason" \
        --arg chat_id "$chat_id" \
        --arg schema_path "$SCHEMA_PATH" \
        --arg callback_prefix "$CALLBACK_PREFIX" \
        --arg session_id "$session_id" \
        --arg callback_token "$callback_token" \
        --arg expires_at "$expires_at" \
        --arg recovery_command "$RECOVERY_COMMAND" '
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
                    callback_data: ($callback_prefix + ":accept:" + $session_id + ":" + $callback_token)
                  },
                  {
                    text: "Не сейчас",
                    callback_data: ($callback_prefix + ":decline:" + $session_id + ":" + $callback_token)
                  }
                ]]
              }
              else null
              end
            )
          },
          session: (
            if $interactive_mode == "inline_callbacks"
            then {
              session_id: $session_id,
              callback_token: $callback_token,
              expires_at: $expires_at,
              status: "pending"
            }
            else null
            end
          ),
          recovery: (
            if $interactive_mode == "inline_callbacks"
            then {
              mode: "tokenized_command",
              accept_command_text: ($recovery_command + " accept " + $session_id + " " + $callback_token),
              decline_command_text: ($recovery_command + " decline " + $session_id + " " + $callback_token)
            }
            else null
            end
          ),
          interaction_record: {
            schema_version: "codex-advisory-interaction/v1",
            event_id: .event_id,
            upstream_fingerprint: .upstream_fingerprint,
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
        (if (.session.session_id // "") != "" then "- Session id: \(.session.session_id)" else empty end),
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
            --interactive-mode)
                INTERACTIVE_MODE="$(normalize_interactive_mode "${2:?missing value for --interactive-mode}")"
                shift 2
                ;;
            --callback-prefix)
                CALLBACK_PREFIX="${2:?missing value for --callback-prefix}"
                shift 2
                ;;
            --degraded-reason)
                DEGRADED_REASON="${2:?missing value for --degraded-reason}"
                shift 2
                ;;
            --session-store-script)
                SESSION_STORE_SCRIPT="${2:?missing value for --session-store-script}"
                shift 2
                ;;
            --session-store-dir)
                SESSION_STORE_DIR="${2:?missing value for --session-store-dir}"
                shift 2
                ;;
            --callback-window-hours)
                CALLBACK_WINDOW_HOURS="${2:?missing value for --callback-window-hours}"
                shift 2
                ;;
            --recovery-command)
                RECOVERY_COMMAND="${2:?missing value for --recovery-command}"
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
    INTERACTIVE_MODE="$(normalize_interactive_mode "$INTERACTIVE_MODE")"
    validate_positive_int "$CALLBACK_WINDOW_HOURS"
    case "$STDOUT_FORMAT" in
        summary|json|none) ;;
        *) fail "Invalid --stdout mode: $STDOUT_FORMAT" ;;
    esac
}

main() {
    require_command jq
    require_command python3

    parse_args "$@"
    validate_event_file "$EVENT_FILE"

    TEMP_DIR="$(mktemp -d)"
    RENDER_PATH="${TEMP_DIR}/render.json"
    SUMMARY_PATH="${TEMP_DIR}/summary.md"

    local event_interactive_ready interactive_mode degraded_reason reply_markup_json send_output send_code message_id
    local session_metadata session_id callback_token expires_at session_record_path
    event_interactive_ready="$(jq -r '.interactive_followup_eligible' "$EVENT_FILE")"
    interactive_mode="one_way_only"
    degraded_reason="$DEGRADED_REASON"
    session_id=""
    callback_token=""
    expires_at=""

    if [[ "$FORCE_ONE_WAY" == "true" ]]; then
        degraded_reason="Interactive path принудительно отключён оператором."
    elif [[ "$INTERACTIVE_MODE" != "inline_callbacks" ]]; then
        degraded_reason="Interactive advisory mode ещё не включён в Moltis runtime; отправляем one-way alert."
    elif [[ "$event_interactive_ready" != "true" ]]; then
        degraded_reason="Producer event пометил follow-up как недоступный; отправляем one-way alert."
    elif [[ -z "$TELEGRAM_CHAT_ID" ]]; then
        degraded_reason="Нельзя открыть advisory-session без Telegram chat id."
    elif [[ ! -x "$SESSION_STORE_SCRIPT" ]]; then
        degraded_reason="Advisory session store недоступен; отправляем one-way alert."
    else
        interactive_mode="inline_callbacks"
        session_metadata="$(build_session_metadata)"
        session_id="$(jq -r '.session_id' <<<"$session_metadata")"
        callback_token="$(jq -r '.callback_token' <<<"$session_metadata")"
        expires_at="$(jq -r '.expires_at' <<<"$session_metadata")"
    fi

    render_result "$interactive_mode" "$degraded_reason" "$TELEGRAM_CHAT_ID" "$session_id" "$callback_token" "$expires_at"

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
                if [[ "$interactive_mode" == "inline_callbacks" ]]; then
                    session_record_path="${TEMP_DIR}/session-record.json"
                    build_session_record "$session_id" "$callback_token" "$expires_at" "$message_id" > "$session_record_path"
                    "$SESSION_STORE_SCRIPT" open \
                        --store-dir "$SESSION_STORE_DIR" \
                        --record-file "$session_record_path" \
                        --json >/dev/null
                fi
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
