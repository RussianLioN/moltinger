#!/usr/bin/env bash
set -euo pipefail

payload="$(cat)"
if [[ -z "${payload:-}" ]]; then
    exit 0
fi

payload_flat="$(
    printf '%s' "$payload" \
        | tr '\r\n' '  ' \
        | sed 's/[[:space:]][[:space:]]*/ /g'
)"

extract_first_string() {
    local key="$1"
    local match

    match="$(printf '%s' "$payload_flat" | grep -oE "\"${key}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -n1 || true)"
    if [[ -z "$match" ]]; then
        return 1
    fi

    printf '%s' "$match" \
        | sed -E 's/^"[^"]*"[[:space:]]*:[[:space:]]*"//; s/"$//'
}

extract_first_number() {
    local key="$1"
    local match

    match="$(printf '%s' "$payload_flat" | grep -oE "\"${key}\"[[:space:]]*:[[:space:]]*[0-9]+" | head -n1 || true)"
    if [[ -z "$match" ]]; then
        return 1
    fi

    printf '%s' "$match" \
        | sed -E 's/^"[^"]*"[[:space:]]*:[[:space:]]*//'
}

json_escape() {
    printf '%s' "$1" | awk '
        BEGIN {
            ORS = ""
        }
        {
            gsub(/\\/, "\\\\")
            gsub(/"/, "\\\"")
            gsub(/\t/, "\\t")
            gsub(/\r/, "\\r")
            if (NR > 1) {
                printf "\\n"
            }
            printf "%s", $0
        }
    '
}

json_string_field() {
    local key="$1"
    local value="$2"
    printf '"%s":"%s"' "$key" "$(json_escape "$value")"
}

json_number_field() {
    local key="$1"
    local value="$2"
    printf '"%s":%s' "$key" "$value"
}

append_optional_string_field() {
    local key="$1"
    local value="${2:-}"
    if [[ -n "$value" ]]; then
        printf ',%s' "$(json_string_field "$key" "$value")"
    fi
}

append_optional_number_field() {
    local key="$1"
    local value="${2:-}"
    if [[ -n "$value" ]]; then
        printf ',%s' "$(json_number_field "$key" "$value")"
    fi
}

emit_modified_payload() {
    local text="$1"
    local include_tool_calls="${2:-false}"
    local session_key provider model finish_reason input_tokens output_tokens reasoning_tokens

    session_key="$(extract_first_string session_key || true)"
    if [[ -z "$session_key" ]]; then
        session_key="$(extract_first_string session_id || true)"
    fi
    provider="$(extract_first_string provider || true)"
    model="$(extract_first_string model || true)"
    finish_reason="$(extract_first_string finish_reason || true)"
    input_tokens="$(extract_first_number input_tokens || true)"
    output_tokens="$(extract_first_number output_tokens || true)"
    reasoning_tokens="$(extract_first_number reasoning_tokens || true)"

    printf '{"action":"modify","data":{%s%s%s%s%s%s%s,"text":"%s"%s}}\n' \
        "$(json_string_field session_key "${session_key:-current-session}")" \
        "$(append_optional_string_field provider "$provider")" \
        "$(append_optional_string_field model "$model")" \
        "$(append_optional_string_field finish_reason "$finish_reason")" \
        "$(append_optional_number_field input_tokens "$input_tokens")" \
        "$(append_optional_number_field output_tokens "$output_tokens")" \
        "$(append_optional_number_field reasoning_tokens "$reasoning_tokens")" \
        "$(json_escape "$text")" \
        "$(
            if [[ "$include_tool_calls" == "true" ]]; then
                printf ',\"tool_calls\":[]'
            fi
        )"
}

event="$(extract_first_string event || true)"
model="$(extract_first_string model || true)"
provider="$(extract_first_string provider || true)"

is_telegram_safe_lane=false
case "${model:-}" in
    custom-zai-telegram-safe::*)
        is_telegram_safe_lane=true
        ;;
esac
if [[ "${provider:-}" == "custom-zai-telegram-safe" || "${provider:-}" == "zai-telegram-safe" ]]; then
    is_telegram_safe_lane=true
fi

if [[ "$event" != "AfterLLMCall" && "$event" != "MessageSending" ]]; then
    exit 0
fi

tool_calls_present=false
if printf '%s' "$payload_flat" | grep -Eq '"tool_calls"[[:space:]]*:[[:space:]]*\[[[:space:]]*\{'; then
    tool_calls_present=true
fi

has_internal_telemetry=false
if printf '%s' "$payload_flat" | grep -Eiq "activity log|running:|searching memory|thinking|nodes_list|sessions_list|missing 'action' parameter|list failed:|mcp__|tool-progress|tool call"; then
    has_internal_telemetry=true
fi

looks_like_status=false
if printf '%s' "$payload_flat" | grep -Eiq '(^|[^[:alnum:]_])/?status([^[:alnum:]_]|$)|статус( системы)?|параметр[[:space:]]*\||канал: telegram|провайдер:|режим: safe-text|модель: custom-zai-telegram-safe::glm-5|доступные навыки|готов к работе'; then
    looks_like_status=true
fi

mentions_wrong_model=false
if printf '%s' "$payload_flat" | grep -Fq 'zai::glm-5'; then
    mentions_wrong_model=true
fi

if [[ "$event" == "AfterLLMCall" && "$is_telegram_safe_lane" != true ]]; then
    exit 0
fi

if [[ "$event" == "MessageSending" && "$looks_like_status" != true && "$has_internal_telemetry" != true ]]; then
    exit 0
fi

canonical_status=$'Статус: Online\nКанал: Telegram (@moltinger_bot)\nМодель: custom-zai-telegram-safe::glm-5\nПровайдер: custom-zai-telegram-safe\nРежим: safe-text'

if [[ "$looks_like_status" == true ]]; then
    if [[ "$event" == "AfterLLMCall" ]]; then
        emit_modified_payload "$canonical_status" true
    else
        emit_modified_payload "$canonical_status" false
    fi
    exit 0
fi

if [[ "$tool_calls_present" == true || "$has_internal_telemetry" == true ]]; then
    fallback_text='В Telegram-safe режиме я не запускаю инструменты и не показываю внутренние логи. Для browser/search/process workflow продолжим в web UI или операторской сессии.'
    if [[ "$event" == "AfterLLMCall" ]]; then
        emit_modified_payload "$fallback_text" true
    else
        emit_modified_payload "$fallback_text" false
    fi
    exit 0
fi

exit 0
