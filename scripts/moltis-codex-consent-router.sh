#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_STORE_SCRIPT="${PROJECT_ROOT}/scripts/codex-telegram-consent-store.sh"
DEFAULT_TELEGRAM_SEND_SCRIPT="${PROJECT_ROOT}/scripts/telegram-bot-send.sh"

STORE_SCRIPT="${CODEX_TELEGRAM_CONSENT_STORE_SCRIPT:-${DEFAULT_STORE_SCRIPT}}"
STORE_DIR="${CODEX_TELEGRAM_CONSENT_STORE_DIR:-${PROJECT_ROOT}/.tmp/current/codex-telegram-consent-store}"
TELEGRAM_SEND_SCRIPT="${CODEX_TELEGRAM_CONSENT_ROUTER_SEND_SCRIPT:-${DEFAULT_TELEGRAM_SEND_SCRIPT}}"
TELEGRAM_ENV_FILE="${CODEX_TELEGRAM_CONSENT_ROUTER_ENV_FILE:-${MOLTIS_ENV_FILE:-}}"
SEND_REPLY="${CODEX_TELEGRAM_CONSENT_ROUTER_SEND_REPLY:-true}"

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
  moltis-codex-consent-router.sh [options]

Route one Codex consent action from the authoritative Telegram ingress.

Options:
  --event-file PATH            Read one inbound event JSON from PATH
  --command-text TEXT          Structured fallback command text
  --callback-data TEXT         Telegram callback data
  --chat-id ID                 Telegram chat id
  --actor-id ID                Telegram actor id
  --reply-to MESSAGE_ID        Reply to this Telegram message id
  --store-script PATH          Consent store helper path
  --store-dir PATH             Consent store directory
  --telegram-send-script PATH  Telegram sender script for contextual replies
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
    local request_id="$1"
    "$STORE_SCRIPT" get --store-dir "$STORE_DIR" --request-id "$request_id" --json
}

find_single_pending_record_for_chat() {
    local chat_id="$1"
    [[ -n "$chat_id" ]] || return 2

    local path matched_path="" match_count=0
    shopt -s nullglob
    for path in "$STORE_DIR"/*.json; do
        if jq -e --arg chat_id "$chat_id" '
            (.request.chat_id == $chat_id) and
            (.request.status == "pending") and
            ((try (.request.expires_at | fromdateiso8601) catch 0) > now)
        ' "$path" >/dev/null 2>&1; then
            matched_path="$path"
            match_count=$((match_count + 1))
        fi
    done
    shopt -u nullglob

    if [[ $match_count -eq 1 ]]; then
        cat "$matched_path"
        return 0
    fi
    if [[ $match_count -eq 0 ]]; then
        return 3
    fi
    return 4
}

store_mark_delivery() {
    local request_id="$1"
    local delivery_status="$2"
    local message_id="${3:-}"
    local delivery_error="${4:-}"
    local note="${5:-}"
    local -a cmd=(
        "$STORE_SCRIPT"
        mark-delivery
        --store-dir "$STORE_DIR"
        --request-id "$request_id"
        --delivery-status "$delivery_status"
        --json
    )

    if [[ -n "$message_id" ]]; then
        cmd+=(--message-id "$message_id")
    fi
    if [[ -n "$delivery_error" ]]; then
        cmd+=(--delivery-error "$delivery_error")
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
summary = str(record.get("recommendations", {}).get("summary", "")).strip()
items = record.get("recommendations", {}).get("items", []) or []

lines = [
    "Практические рекомендации по обновлению Codex CLI",
    "",
]

if summary:
    lines.append(summary)
    lines.append("")

if items:
    lines.append("Что можно сделать в проекте:")
    for item in items[:3]:
        title = str(item.get("title", "")).strip()
        rationale = str(item.get("rationale", "")).strip()
        impacted = [str(value).strip() for value in item.get("impacted_paths", []) if str(value).strip()]
        next_steps = [str(value).strip() for value in item.get("next_steps", []) if str(value).strip()]

        if title:
            lines.append(f"- {title}")
        if rationale:
            lines.append(f"  Почему: {rationale}")
        if impacted:
            lines.append(f"  Затронутые пути: {', '.join(impacted[:4])}")
        for step in next_steps[:3]:
            lines.append(f"  Дальше: {step}")
    if len(items) > 3:
        lines.append(f"- И ещё {len(items) - 3} рекомендаций в подготовленном payload.")
else:
    lines.append("Подробный список не был подготовлен, но стоит проверить связанные инструкции и workflow проекта вручную.")

print("\n".join(lines).strip())
PY
}

result_json() {
    local handled="$1"
    local suppress_generic="$2"
    local decision="$3"
    local request_id="$4"
    local resolved_via="$5"
    local reply_text="$6"
    local reply_status="$7"
    local reply_error="$8"

    jq -cn \
        --argjson handled "$handled" \
        --argjson suppress_generic "$suppress_generic" \
        --arg decision "$decision" \
        --arg request_id "$request_id" \
        --arg resolved_via "$resolved_via" \
        --arg reply_text "$reply_text" \
        --arg reply_status "$reply_status" \
        --arg reply_error "$reply_error" \
        '{
            handled: $handled,
            suppress_generic: $suppress_generic,
            decision: $decision,
            request_id: $request_id,
            resolved_via: $resolved_via,
            reply_text: $reply_text,
            delivery: {
                status: $reply_status,
                error: (if $reply_error == "" then null else $reply_error end)
            }
        }'
}

main() {
    require_command jq
    require_command python3
    [[ -x "$STORE_SCRIPT" ]] || fail "Consent store helper is not executable: $STORE_SCRIPT"

    parse_args "$@"

    local event_json parse_mode action request_id action_token raw_input resolved_via alias_lookup_code
    local record_json record_path stored_chat_id stored_token stored_status expires_at now_epoch expiry_epoch
    local stored_delivery_status stored_question_message_id
    local decision reply_text reply_status reply_error result actor_id
    local outbound_reply_to followup_delivery_on_success followup_delivery_on_failure
    local followup_note followup_delivery_message_id sender_output recommendations_text

    event_json="$(read_event_json)"
    extract_if_missing callback "$event_json"
    extract_if_missing command "$event_json"
    extract_if_missing chat "$event_json"
    extract_if_missing actor "$event_json"
    extract_if_missing reply_to "$event_json"

    action=""
    request_id=""
    action_token=""
    raw_input=""
    resolved_via=""
    outbound_reply_to=""
    followup_delivery_on_success=""
    followup_delivery_on_failure=""
    followup_note=""
    followup_delivery_message_id=""

    if [[ -n "$CALLBACK_DATA" && "$CALLBACK_DATA" =~ ^codex-consent:(accept|decline):([A-Za-z0-9._-]+):([A-Za-z0-9._-]+)$ ]]; then
        action="${BASH_REMATCH[1]}"
        request_id="${BASH_REMATCH[2]}"
        action_token="${BASH_REMATCH[3]}"
        raw_input="$CALLBACK_DATA"
        resolved_via="callback_query"
    elif [[ -n "$COMMAND_TEXT" && "$COMMAND_TEXT" =~ ^/?codex-followup(@[A-Za-z0-9_]+)?[[:space:]]+(accept|decline)[[:space:]]+([A-Za-z0-9._-]+)[[:space:]]+([A-Za-z0-9._-]+)$ ]]; then
        action="${BASH_REMATCH[2]}"
        request_id="${BASH_REMATCH[3]}"
        action_token="${BASH_REMATCH[4]}"
        raw_input="$COMMAND_TEXT"
        resolved_via="command_fallback"
    elif [[ -n "$COMMAND_TEXT" && "$COMMAND_TEXT" =~ ^/?codex_da(@[A-Za-z0-9_]+)?$ ]]; then
        action="accept"
        raw_input="$COMMAND_TEXT"
        resolved_via="command_alias"
    elif [[ -n "$COMMAND_TEXT" && "$COMMAND_TEXT" =~ ^/?codex_net(@[A-Za-z0-9_]+)?$ ]]; then
        action="decline"
        raw_input="$COMMAND_TEXT"
        resolved_via="command_alias"
    fi

    if [[ "$resolved_via" == "command_alias" ]]; then
        if [[ -z "$CHAT_ID" ]]; then
            reply_text="Не удалось определить чат для короткой команды. Откройте последнее уведомление и попробуйте ещё раз."
            result="$(result_json true true invalid "" "$resolved_via" "$reply_text" skipped "")"
            if [[ -n "$JSON_OUT" ]]; then
                ensure_parent_dir "$JSON_OUT"
                printf '%s\n' "$result" > "$JSON_OUT"
            fi
            [[ "$STDOUT_FORMAT" == "json" ]] && printf '%s\n' "$result"
            return 0
        fi

        set +e
        record_json="$(find_single_pending_record_for_chat "$CHAT_ID" 2>/dev/null)"
        alias_lookup_code=$?
        set -e

        case "$alias_lookup_code" in
            0)
                request_id="$(jq -r '.request.request_id' <<<"$record_json")"
                action_token="$(jq -r '.request.action_token' <<<"$record_json")"
                ;;
            3)
                reply_text="Сейчас нет активного запроса на рекомендации. Дождитесь нового уведомления."
                result="$(result_json true true invalid "" "$resolved_via" "$reply_text" skipped "")"
                if [[ "$SEND_REPLY" == "true" && -n "$CHAT_ID" && -x "$TELEGRAM_SEND_SCRIPT" ]]; then
                    set +e
                    run_sender "$CHAT_ID" "$reply_text" "$REPLY_TO_MESSAGE_ID" >/dev/null 2>&1
                    set -e
                fi
                if [[ -n "$JSON_OUT" ]]; then
                    ensure_parent_dir "$JSON_OUT"
                    printf '%s\n' "$result" > "$JSON_OUT"
                fi
                [[ "$STDOUT_FORMAT" == "json" ]] && printf '%s\n' "$result"
                return 0
                ;;
            4)
                reply_text="В этом чате сейчас несколько активных запросов. Используйте резервную длинную команду из нужного уведомления."
                result="$(result_json true true invalid "" "$resolved_via" "$reply_text" skipped "")"
                if [[ "$SEND_REPLY" == "true" && -n "$CHAT_ID" && -x "$TELEGRAM_SEND_SCRIPT" ]]; then
                    set +e
                    run_sender "$CHAT_ID" "$reply_text" "$REPLY_TO_MESSAGE_ID" >/dev/null 2>&1
                    set -e
                fi
                if [[ -n "$JSON_OUT" ]]; then
                    ensure_parent_dir "$JSON_OUT"
                    printf '%s\n' "$result" > "$JSON_OUT"
                fi
                [[ "$STDOUT_FORMAT" == "json" ]] && printf '%s\n' "$result"
                return 0
                ;;
            *)
                reply_text="Не удалось сопоставить короткую команду с активным запросом. Попробуйте ещё раз из последнего уведомления."
                result="$(result_json true true invalid "" "$resolved_via" "$reply_text" skipped "")"
                if [[ "$SEND_REPLY" == "true" && -n "$CHAT_ID" && -x "$TELEGRAM_SEND_SCRIPT" ]]; then
                    set +e
                    run_sender "$CHAT_ID" "$reply_text" "$REPLY_TO_MESSAGE_ID" >/dev/null 2>&1
                    set -e
                fi
                if [[ -n "$JSON_OUT" ]]; then
                    ensure_parent_dir "$JSON_OUT"
                    printf '%s\n' "$result" > "$JSON_OUT"
                fi
                [[ "$STDOUT_FORMAT" == "json" ]] && printf '%s\n' "$result"
                return 0
                ;;
        esac
    fi

    if [[ -z "$action" || -z "$request_id" || -z "$action_token" ]]; then
        result="$(result_json false false no_match \"\" \"\" \"\" skipped \"\")"
        if [[ -n "$JSON_OUT" ]]; then
            ensure_parent_dir "$JSON_OUT"
            printf '%s\n' "$result" > "$JSON_OUT"
        fi
        [[ "$STDOUT_FORMAT" == "json" ]] && printf '%s\n' "$result"
        return 0
    fi

    record_json="$(resolve_store_record "$request_id" 2>/dev/null || true)"
    if [[ -z "$record_json" ]]; then
        reply_text="Не удалось найти активный запрос на рекомендации. Дождитесь нового уведомления."
        result="$(result_json true true invalid "$request_id" "$resolved_via" "$reply_text" skipped \"\")"
        if [[ "$SEND_REPLY" == "true" && -n "$CHAT_ID" && -x "$TELEGRAM_SEND_SCRIPT" ]]; then
            set +e
            run_sender "$CHAT_ID" "$reply_text" "$REPLY_TO_MESSAGE_ID" >/dev/null 2>&1
            set -e
        fi
    else
        stored_chat_id="$(jq -r '.request.chat_id' <<<"$record_json")"
        stored_token="$(jq -r '.request.action_token' <<<"$record_json")"
        stored_status="$(jq -r '.request.status' <<<"$record_json")"
        stored_delivery_status="$(jq -r '.delivery.status // "not_sent"' <<<"$record_json")"
        stored_question_message_id="$(jq -r '(.request.question_message_id // 0) | tostring' <<<"$record_json")"
        expires_at="$(jq -r '.request.expires_at' <<<"$record_json")"
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
            decision="invalid"
            reply_text="Этот запрос на рекомендации относится к другому чату и не может быть подтверждён отсюда."
            result="$(result_json true true "$decision" "$request_id" "$resolved_via" "$reply_text" skipped \"\")"
        elif [[ "$stored_token" != "$action_token" ]]; then
            decision="invalid"
            reply_text="Не удалось подтвердить токен действия. Дождитесь нового уведомления."
            result="$(result_json true true "$decision" "$request_id" "$resolved_via" "$reply_text" skipped \"\")"
        elif [[ "$expiry_epoch" -gt 0 && "$now_epoch" -gt "$expiry_epoch" ]]; then
            "$STORE_SCRIPT" resolve \
                --store-dir "$STORE_DIR" \
                --request-id "$request_id" \
                --decision expired \
                --resolved-via "$resolved_via" \
                --telegram-actor-id "${ACTOR_ID:-$CHAT_ID}" \
                --raw-input "$raw_input" \
                --note "expired before authoritative routing" \
                --json >/dev/null
            decision="expired"
            reply_text="Окно подтверждения уже истекло. Дождитесь нового уведомления, если рекомендации всё ещё нужны."
            result="$(result_json true true "$decision" "$request_id" "$resolved_via" "$reply_text" skipped \"\")"
        elif [[ "$stored_status" != "pending" ]]; then
            "$STORE_SCRIPT" resolve \
                --store-dir "$STORE_DIR" \
                --request-id "$request_id" \
                --decision duplicate \
                --resolved-via "$resolved_via" \
                --telegram-actor-id "${ACTOR_ID:-$CHAT_ID}" \
                --raw-input "$raw_input" \
                --note "duplicate action after resolved state" \
                --json >/dev/null
            decision="duplicate"
            if [[ "$stored_status" == "failed" || "$stored_delivery_status" == "retry" || "$stored_delivery_status" == "failed" ]]; then
                reply_text="Этот ответ уже был обработан. Предыдущая отправка рекомендаций не завершилась успешно; нужен повтор со стороны оператора."
            else
                reply_text="Этот ответ уже был обработан раньше. Повторно ничего делать не нужно."
            fi
            result="$(result_json true true "$decision" "$request_id" "$resolved_via" "$reply_text" skipped \"\")"
        else
            if [[ "$stored_question_message_id" != "0" ]]; then
                outbound_reply_to="$stored_question_message_id"
            elif [[ -n "$REPLY_TO_MESSAGE_ID" ]]; then
                outbound_reply_to="$REPLY_TO_MESSAGE_ID"
            fi

            if [[ "$action" == "accept" ]]; then
                decision="accept"
                recommendations_text="$(build_recommendations_reply "$record_json")"
                reply_text="$recommendations_text"
                if [[ "$SEND_REPLY" == "true" ]]; then
                    followup_delivery_on_success="sent"
                    followup_delivery_on_failure="retry"
                    followup_note="recommendations delivered from authoritative router"
                fi
            else
                decision="decline"
                reply_text="Понял. Практические рекомендации по этому обновлению отправляться не будут."
                store_mark_delivery "$request_id" "suppressed" "" "" "user declined recommendations" || true
            fi
            "$STORE_SCRIPT" resolve \
                --store-dir "$STORE_DIR" \
                --request-id "$request_id" \
                --decision "$decision" \
                --resolved-via "$resolved_via" \
                --telegram-actor-id "${ACTOR_ID:-$CHAT_ID}" \
                --raw-input "$raw_input" \
                --json >/dev/null
            result="$(result_json true true "$decision" "$request_id" "$resolved_via" "$reply_text" skipped \"\")"
        fi
    fi

    reply_status="$(jq -r '.delivery.status' <<<"$result")"
    reply_error=""
    if [[ "$SEND_REPLY" == "true" ]]; then
        if [[ -z "$CHAT_ID" ]]; then
            if [[ -n "$followup_delivery_on_failure" ]]; then
                reply_status="failed"
                reply_error="chat id is required for immediate follow-up delivery"
                store_mark_delivery "$request_id" "$followup_delivery_on_failure" "" "$reply_error" "follow-up delivery skipped because chat id was missing" || true
            fi
        elif [[ ! -x "$TELEGRAM_SEND_SCRIPT" ]]; then
            if [[ -n "$followup_delivery_on_failure" ]]; then
                reply_status="failed"
                reply_error="telegram sender script is not executable: $TELEGRAM_SEND_SCRIPT"
                store_mark_delivery "$request_id" "$followup_delivery_on_failure" "" "$reply_error" "follow-up delivery skipped because sender script was unavailable" || true
            fi
        else
            set +e
            sender_output="$(run_sender "$CHAT_ID" "$(jq -r '.reply_text' <<<"$result")" "$outbound_reply_to" 2>&1)"
            if [[ $? -eq 0 ]]; then
                reply_status="sent"
                followup_delivery_message_id="$(jq -r '.result.message_id // ""' <<<"$sender_output" 2>/dev/null || true)"
                if [[ -n "$followup_delivery_on_success" ]]; then
                    store_mark_delivery "$request_id" "$followup_delivery_on_success" "$followup_delivery_message_id" "" "$followup_note" || true
                fi
            else
                reply_status="failed"
                reply_error="${sender_output:-failed to send contextual Telegram reply}"
                if [[ -n "$followup_delivery_on_failure" ]]; then
                    store_mark_delivery "$request_id" "$followup_delivery_on_failure" "" "$reply_error" "follow-up delivery failed in authoritative router" || true
                fi
            fi
            set -e
        fi

        result="$(jq \
            --arg reply_status "$reply_status" \
            --arg reply_error "$reply_error" \
            --arg reply_message_id "$followup_delivery_message_id" \
            '.delivery.status = $reply_status | .delivery.error = (if $reply_error == "" then null else $reply_error end)' \
            <<<"$result")"
        if [[ -n "$followup_delivery_message_id" ]]; then
            result="$(jq --arg reply_message_id "$followup_delivery_message_id" '.delivery.message_id = ($reply_message_id | tonumber)' <<<"$result")"
        fi
    fi

    if [[ -n "$JSON_OUT" ]]; then
        ensure_parent_dir "$JSON_OUT"
        printf '%s\n' "$result" > "$JSON_OUT"
    fi
    if [[ "$STDOUT_FORMAT" == "json" ]]; then
        printf '%s\n' "$result"
    fi
}

main "$@"
