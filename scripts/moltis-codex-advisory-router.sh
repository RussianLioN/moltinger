#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_STORE_SCRIPT="${PROJECT_ROOT}/scripts/codex-advisory-session-store.sh"
DEFAULT_TELEGRAM_SEND_SCRIPT="${PROJECT_ROOT}/scripts/telegram-bot-send.sh"

STORE_SCRIPT="${MOLTIS_CODEX_ADVISORY_SESSION_STORE_SCRIPT:-${DEFAULT_STORE_SCRIPT}}"
STORE_DIR="${MOLTIS_CODEX_ADVISORY_SESSION_STORE_DIR:-${PROJECT_ROOT}/.tmp/current/codex-advisory-session-store}"
TELEGRAM_SEND_SCRIPT="${MOLTIS_CODEX_ADVISORY_ROUTER_SEND_SCRIPT:-${DEFAULT_TELEGRAM_SEND_SCRIPT}}"
TELEGRAM_ENV_FILE="${MOLTIS_CODEX_ADVISORY_ROUTER_ENV_FILE:-${MOLTIS_ENV_FILE:-}}"
SEND_REPLY="${MOLTIS_CODEX_ADVISORY_ROUTER_SEND_REPLY:-true}"
CALLBACK_PREFIX="${MOLTIS_CODEX_ADVISORY_CALLBACK_PREFIX:-codex-advisory}"
FALLBACK_COMMAND="${MOLTIS_CODEX_ADVISORY_RECOVERY_COMMAND:-/codex-advisory-followup}"

EVENT_FILE=""
COMMAND_TEXT=""
CALLBACK_DATA=""
CHAT_ID=""
ACTOR_ID=""
REPLY_TO_MESSAGE_ID=""
JSON_OUT=""
STDOUT_FORMAT="json"

usage() {
    cat <<'EOF'
Usage:
  moltis-codex-advisory-router.sh [options]

Route one Moltis-native Codex advisory action from the authoritative Telegram ingress.

Options:
  --event-file PATH            Read one inbound event JSON from PATH
  --command-text TEXT          Recovery command text
  --callback-data TEXT         Telegram callback data
  --chat-id ID                 Telegram chat id
  --actor-id ID                Telegram actor id
  --reply-to MESSAGE_ID        Reply to this Telegram message id
  --store-script PATH          Advisory session store helper path
  --store-dir PATH             Advisory session store directory
  --telegram-send-script PATH  Telegram sender script for follow-up replies
  --telegram-env-file PATH     Env file for Telegram sender token loading
  --send-reply true|false      Whether to send a contextual reply (default: true)
  --json-out PATH              Write JSON result to PATH
  --stdout MODE                json|none (default: json)
  -h, --help                   Show help
EOF
}

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

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --event-file)
                EVENT_FILE="${2:?missing value for --event-file}"
                shift 2
                ;;
            --command-text)
                COMMAND_TEXT="${2:?missing value for --command-text}"
                shift 2
                ;;
            --callback-data)
                CALLBACK_DATA="${2:?missing value for --callback-data}"
                shift 2
                ;;
            --chat-id)
                CHAT_ID="${2:?missing value for --chat-id}"
                shift 2
                ;;
            --actor-id)
                ACTOR_ID="${2:?missing value for --actor-id}"
                shift 2
                ;;
            --reply-to)
                REPLY_TO_MESSAGE_ID="${2:?missing value for --reply-to}"
                shift 2
                ;;
            --store-script)
                STORE_SCRIPT="${2:?missing value for --store-script}"
                shift 2
                ;;
            --store-dir)
                STORE_DIR="${2:?missing value for --store-dir}"
                shift 2
                ;;
            --telegram-send-script)
                TELEGRAM_SEND_SCRIPT="${2:?missing value for --telegram-send-script}"
                shift 2
                ;;
            --telegram-env-file)
                TELEGRAM_ENV_FILE="${2:?missing value for --telegram-env-file}"
                shift 2
                ;;
            --send-reply)
                SEND_REPLY="$(normalize_bool "${2:?missing value for --send-reply}")"
                shift 2
                ;;
            --json-out)
                JSON_OUT="${2:?missing value for --json-out}"
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

    case "$STDOUT_FORMAT" in
        json|none) ;;
        *) fail "Invalid --stdout mode: $STDOUT_FORMAT" ;;
    esac
}

read_event_json() {
    if [[ -n "$EVENT_FILE" ]]; then
        [[ -f "$EVENT_FILE" ]] || fail "Event file not found: $EVENT_FILE"
        cat "$EVENT_FILE"
        return 0
    fi

    if [[ -z "$COMMAND_TEXT" && -z "$CALLBACK_DATA" && -z "$CHAT_ID" && -z "$ACTOR_ID" && -z "$REPLY_TO_MESSAGE_ID" && ! -t 0 ]]; then
        cat
        return 0
    fi

    printf '{}\n'
}

extract_if_missing() {
    local field="$1"
    local event_json="$2"
    case "$field" in
        callback)
            if [[ -z "$CALLBACK_DATA" ]]; then
                CALLBACK_DATA="$(jq -r '
                    .callback_query.data //
                    .callback.data //
                    .telegram.callback_query.data //
                    ""
                ' <<<"$event_json")"
            fi
            ;;
        command)
            if [[ -z "$COMMAND_TEXT" ]]; then
                COMMAND_TEXT="$(jq -r '
                    .command.text //
                    .message.text //
                    .telegram.message.text //
                    .text //
                    ""
                ' <<<"$event_json")"
            fi
            ;;
        chat)
            if [[ -z "$CHAT_ID" ]]; then
                CHAT_ID="$(jq -r '
                    (.callback_query.message.chat.id // .message.chat.id // .chat.id // .chat_id // "") | tostring
                ' <<<"$event_json")"
            fi
            ;;
        actor)
            if [[ -z "$ACTOR_ID" ]]; then
                ACTOR_ID="$(jq -r '
                    (.callback_query.from.id // .message.from.id // .from.id // .actor_id // "") | tostring
                ' <<<"$event_json")"
            fi
            ;;
        reply_to)
            if [[ -z "$REPLY_TO_MESSAGE_ID" ]]; then
                REPLY_TO_MESSAGE_ID="$(jq -r '
                    (.callback_query.message.message_id // .message.message_id // .reply_to_message_id // 0) | tostring
                ' <<<"$event_json")"
                if [[ "$REPLY_TO_MESSAGE_ID" == "0" ]]; then
                    REPLY_TO_MESSAGE_ID=""
                fi
            fi
            ;;
    esac
}

run_sender() {
    local chat_id="$1"
    local text="$2"
    local reply_to="$3"
    local -a cmd=("$TELEGRAM_SEND_SCRIPT" --chat-id "$chat_id" --text "$text" --json)

    if [[ -n "$reply_to" ]]; then
        cmd+=(--reply-to "$reply_to")
    fi

    if [[ -n "$TELEGRAM_ENV_FILE" ]]; then
        MOLTIS_ENV_FILE="$TELEGRAM_ENV_FILE" "${cmd[@]}"
    else
        "${cmd[@]}"
    fi
}

resolve_store_record() {
    local session_id="$1"
    "$STORE_SCRIPT" get --store-dir "$STORE_DIR" --session-id "$session_id" --json
}

store_mark_followup() {
    local session_id="$1"
    local followup_status="$2"
    local message_id="${3:-}"
    local followup_error="${4:-}"
    local note="${5:-}"
    local -a cmd=(
        "$STORE_SCRIPT"
        mark-followup
        --store-dir "$STORE_DIR"
        --session-id "$session_id"
        --followup-status "$followup_status"
        --json
    )

    if [[ -n "$message_id" ]]; then
        cmd+=(--message-id "$message_id")
    fi
    if [[ -n "$followup_error" ]]; then
        cmd+=(--followup-error "$followup_error")
    fi
    if [[ -n "$note" ]]; then
        cmd+=(--note "$note")
    fi

    "${cmd[@]}" >/dev/null
}

build_recommendations_reply() {
    local record_json="$1"
    python3 - <<'PY' "$record_json"
import json
import sys

record = json.loads(sys.argv[1])
envelope = record.get("recommendation_envelope", {}) or {}
headline = str(envelope.get("headline_ru", "")).strip() or "Практические рекомендации по обновлению Codex CLI"
summary = str(envelope.get("summary_ru", "")).strip()
priority_checks = [str(v).strip() for v in (envelope.get("priority_checks") or []) if str(v).strip()]
impacted = [str(v).strip() for v in (envelope.get("impacted_surfaces") or []) if str(v).strip()]
items = envelope.get("items") or []
raw_reference_path = str(envelope.get("raw_reference_path", "")).strip()

lines = [headline, ""]

if summary:
    lines.append(summary)
    lines.append("")

if priority_checks:
    lines.append("Что проверить в первую очередь:")
    for value in priority_checks[:4]:
        lines.append(f"- {value}")
    lines.append("")

if impacted:
    lines.append("Какие поверхности затронуты:")
    for value in impacted[:5]:
        lines.append(f"- {value}")
    lines.append("")

if items:
    lines.append("Практические шаги:")
    for item in items[:3]:
        title = str(item.get("title", "")).strip()
        rationale = str(item.get("rationale", "")).strip()
        next_steps = [str(v).strip() for v in (item.get("next_steps") or []) if str(v).strip()]
        impacted_paths = [str(v).strip() for v in (item.get("impacted_paths") or []) if str(v).strip()]
        if title:
            lines.append(f"- {title}")
        if rationale:
            lines.append(f"  Почему: {rationale}")
        if impacted_paths:
            lines.append(f"  Пути: {', '.join(impacted_paths[:4])}")
        for step in next_steps[:3]:
            lines.append(f"  Дальше: {step}")
    if len(items) > 3:
        lines.append(f"- И ещё {len(items) - 3} рекомендаций в payload.")
    lines.append("")

if raw_reference_path:
    lines.append(f"Сырые рекомендации сохранены в: {raw_reference_path}")

print("\n".join([line for line in lines if line is not None]).strip())
PY
}

result_json() {
    local handled="$1"
    local suppress_generic="$2"
    local decision="$3"
    local session_id="$4"
    local resolved_via="$5"
    local reply_text="$6"
    local reply_status="$7"
    local reply_error="$8"

    jq -cn \
        --argjson handled "$handled" \
        --argjson suppress_generic "$suppress_generic" \
        --arg decision "$decision" \
        --arg session_id "$session_id" \
        --arg resolved_via "$resolved_via" \
        --arg reply_text "$reply_text" \
        --arg reply_status "$reply_status" \
        --arg reply_error "$reply_error" \
        '{
            handled: $handled,
            suppress_generic: $suppress_generic,
            decision: $decision,
            session_id: (if $session_id == "" then null else $session_id end),
            resolved_via: (if $resolved_via == "" then null else $resolved_via end),
            reply_text: (if $reply_text == "" then null else $reply_text end),
            delivery: {
                status: $reply_status,
                error: (if $reply_error == "" then null else $reply_error end)
            }
        }'
}

main() {
    require_command jq
    require_command python3
    [[ -x "$STORE_SCRIPT" ]] || fail "Advisory session store helper is not executable: $STORE_SCRIPT"

    parse_args "$@"

    local event_json action session_id callback_token raw_input resolved_via
    local record_json stored_chat_id stored_token stored_status expires_at now_epoch expiry_epoch
    local outbound_reply_to recommendations_text sender_output reply_status reply_error result
    local followup_success_status followup_failure_status followup_note followup_message_id decision

    event_json="$(read_event_json)"
    extract_if_missing callback "$event_json"
    extract_if_missing command "$event_json"
    extract_if_missing chat "$event_json"
    extract_if_missing actor "$event_json"
    extract_if_missing reply_to "$event_json"

    action=""
    session_id=""
    callback_token=""
    raw_input=""
    resolved_via=""

    if [[ -n "$CALLBACK_DATA" && "$CALLBACK_DATA" =~ ^${CALLBACK_PREFIX}:(accept|decline):([A-Za-z0-9._:-]+):([A-Za-z0-9._:-]+)$ ]]; then
        action="${BASH_REMATCH[1]}"
        session_id="${BASH_REMATCH[2]}"
        callback_token="${BASH_REMATCH[3]}"
        raw_input="$CALLBACK_DATA"
        resolved_via="callback_query"
    elif [[ -n "$COMMAND_TEXT" && "$COMMAND_TEXT" =~ ^/?codex-advisory-followup(@[A-Za-z0-9_]+)?[[:space:]]+(accept|decline)[[:space:]]+([A-Za-z0-9._:-]+)[[:space:]]+([A-Za-z0-9._:-]+)$ ]]; then
        action="${BASH_REMATCH[2]}"
        session_id="${BASH_REMATCH[3]}"
        callback_token="${BASH_REMATCH[4]}"
        raw_input="$COMMAND_TEXT"
        resolved_via="tokenized_recovery"
    fi

    if [[ -z "$action" || -z "$session_id" || -z "$callback_token" ]]; then
        result="$(result_json false false "no_match" "" "" "" "skipped" "")"
        if [[ -n "$JSON_OUT" ]]; then
            ensure_parent_dir "$JSON_OUT"
            printf '%s\n' "$result" > "$JSON_OUT"
        fi
        [[ "$STDOUT_FORMAT" == "json" ]] && printf '%s\n' "$result"
        return 0
    fi

    record_json="$(resolve_store_record "$session_id" 2>/dev/null || true)"
    if [[ -z "$record_json" ]]; then
        result="$(result_json true true "invalid" "$session_id" "$resolved_via" "Не удалось найти активную advisory-сессию. Дождитесь нового уведомления." "skipped" "")"
    else
        stored_chat_id="$(jq -r '.session.chat_id' <<<"$record_json")"
        stored_token="$(jq -r '.session.callback_token' <<<"$record_json")"
        stored_status="$(jq -r '.session.status' <<<"$record_json")"
        expires_at="$(jq -r '.session.expires_at' <<<"$record_json")"
        outbound_reply_to="$(jq -r '(.alert.message_id // 0) | tostring' <<<"$record_json")"
        if [[ "$outbound_reply_to" == "0" ]]; then
            outbound_reply_to="${REPLY_TO_MESSAGE_ID}"
        fi

        now_epoch="$(date -u +%s)"
        expiry_epoch="$(python3 - <<'PY' "$expires_at"
import datetime as dt
import sys
value = sys.argv[1]
try:
    print(int(dt.datetime.fromisoformat(value.replace('Z', '+00:00')).timestamp()))
except Exception:
    print(0)
PY
)"

        if [[ -n "$CHAT_ID" && "$stored_chat_id" != "$CHAT_ID" ]]; then
            result="$(result_json true true "invalid" "$session_id" "$resolved_via" "Этот advisory-запрос относится к другому чату и не может быть подтверждён отсюда." "skipped" "")"
        elif [[ "$stored_token" != "$callback_token" ]]; then
            result="$(result_json true true "invalid" "$session_id" "$resolved_via" "Не удалось подтвердить токен действия. Дождитесь нового уведомления." "skipped" "")"
        elif [[ "$expiry_epoch" -gt 0 && "$now_epoch" -gt "$expiry_epoch" ]]; then
            "$STORE_SCRIPT" resolve \
                --store-dir "$STORE_DIR" \
                --session-id "$session_id" \
                --decision expired \
                --resolved-via "$resolved_via" \
                --telegram-actor-id "${ACTOR_ID:-$CHAT_ID}" \
                --raw-input "$raw_input" \
                --note "expired before advisory follow-up delivery" \
                --json >/dev/null
            result="$(result_json true true "expired" "$session_id" "$resolved_via" "Окно подтверждения уже истекло. Дождитесь нового advisory-уведомления." "skipped" "")"
        elif [[ "$stored_status" != "pending" ]]; then
            "$STORE_SCRIPT" resolve \
                --store-dir "$STORE_DIR" \
                --session-id "$session_id" \
                --decision duplicate \
                --resolved-via "$resolved_via" \
                --telegram-actor-id "${ACTOR_ID:-$CHAT_ID}" \
                --raw-input "$raw_input" \
                --note "duplicate advisory action after resolved state" \
                --json >/dev/null
            result="$(result_json true true "duplicate" "$session_id" "$resolved_via" "Этот advisory-ответ уже был обработан раньше. Повторно ничего делать не нужно." "skipped" "")"
        else
            if [[ "$action" == "accept" ]]; then
                "$STORE_SCRIPT" resolve \
                    --store-dir "$STORE_DIR" \
                    --session-id "$session_id" \
                    --decision accept \
                    --resolved-via "$resolved_via" \
                    --telegram-actor-id "${ACTOR_ID:-$CHAT_ID}" \
                    --raw-input "$raw_input" \
                    --json >/dev/null
                recommendations_text="$(build_recommendations_reply "$record_json")"
                result="$(result_json true true "accept" "$session_id" "$resolved_via" "$recommendations_text" "skipped" "")"
                followup_success_status="sent"
                followup_failure_status="retry"
                followup_note="recommendations delivered from Moltis-native advisory router"
            else
                "$STORE_SCRIPT" resolve \
                    --store-dir "$STORE_DIR" \
                    --session-id "$session_id" \
                    --decision decline \
                    --resolved-via "$resolved_via" \
                    --telegram-actor-id "${ACTOR_ID:-$CHAT_ID}" \
                    --raw-input "$raw_input" \
                    --json >/dev/null
                store_mark_followup "$session_id" "suppressed" "" "" "user declined advisory recommendations" || true
                result="$(result_json true true "decline" "$session_id" "$resolved_via" "Понял. Практические рекомендации по этому обновлению отправляться не будут." "skipped" "")"
            fi
        fi
    fi

    reply_status="$(jq -r '.delivery.status' <<<"$result")"
    reply_error=""
    if [[ "$SEND_REPLY" == "true" ]]; then
        if [[ -z "$CHAT_ID" ]]; then
            if [[ -n "${followup_failure_status:-}" ]]; then
                reply_status="failed"
                reply_error="chat id is required for immediate follow-up delivery"
                store_mark_followup "$session_id" "$followup_failure_status" "" "$reply_error" "follow-up delivery skipped because chat id was missing" || true
            fi
        elif [[ ! -x "$TELEGRAM_SEND_SCRIPT" ]]; then
            if [[ -n "${followup_failure_status:-}" ]]; then
                reply_status="failed"
                reply_error="telegram sender script is not executable: $TELEGRAM_SEND_SCRIPT"
                store_mark_followup "$session_id" "$followup_failure_status" "" "$reply_error" "follow-up delivery skipped because sender script was unavailable" || true
            fi
        else
            set +e
            sender_output="$(run_sender "$CHAT_ID" "$(jq -r '.reply_text' <<<"$result")" "$outbound_reply_to" 2>&1)"
            if [[ $? -eq 0 ]]; then
                reply_status="sent"
                followup_message_id="$(jq -r '.result.message_id // ""' <<<"$sender_output" 2>/dev/null || true)"
                if [[ -n "${followup_success_status:-}" ]]; then
                    store_mark_followup "$session_id" "$followup_success_status" "$followup_message_id" "" "$followup_note" || true
                fi
            else
                reply_status="failed"
                reply_error="${sender_output:-telegram sender exited with a non-zero status}"
                if [[ -n "${followup_failure_status:-}" ]]; then
                    store_mark_followup "$session_id" "$followup_failure_status" "" "$reply_error" "follow-up delivery failed in router" || true
                fi
            fi
            set -e
        fi

        result="$(jq \
            --arg reply_status "$reply_status" \
            --arg reply_error "$reply_error" \
            '.delivery.status = $reply_status | .delivery.error = (if $reply_error == "" then null else $reply_error end)' <<<"$result")"
    fi

    if [[ -n "$JSON_OUT" ]]; then
        ensure_parent_dir "$JSON_OUT"
        printf '%s\n' "$result" > "$JSON_OUT"
    fi
    [[ "$STDOUT_FORMAT" == "json" ]] && printf '%s\n' "$result"
}

main "$@"
