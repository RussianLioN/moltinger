#!/usr/bin/env bash
set -euo pipefail

payload="$(cat)"
if [[ -z "${payload:-}" ]]; then
    exit 0
fi

compact_payload="$(printf '%s' "$payload" | tr -d '\r\n')"

extract_json_string() {
    local key="$1"
    local match=""
    match="$(
        printf '%s' "$compact_payload" |
            grep -oE "\"$key\"[[:space:]]*:[[:space:]]*\"([^\"\\\\]|\\\\.)*\"" |
            head -n 1 || true
    )"
    if [[ -z "$match" ]]; then
        return 0
    fi

    printf '%s' "$match" |
        sed -E 's/^"[^"]+"[[:space:]]*:[[:space:]]*"//; s/"$//'
}

extract_last_json_string() {
    local key="$1"
    local match=""
    match="$(
        printf '%s' "$compact_payload" |
            grep -oE "\"$key\"[[:space:]]*:[[:space:]]*\"([^\"\\\\]|\\\\.)*\"" |
            tail -n 1 || true
    )"
    if [[ -z "$match" ]]; then
        return 0
    fi

    printf '%s' "$match" |
        sed -E 's/^"[^"]+"[[:space:]]*:[[:space:]]*"//; s/"$//'
}

extract_json_number() {
    local key="$1"
    local match=""
    match="$(
        printf '%s' "$compact_payload" |
            grep -oE "\"$key\"[[:space:]]*:[[:space:]]*[0-9]+" |
            head -n 1 || true
    )"
    if [[ -z "$match" ]]; then
        return 0
    fi

    printf '%s' "$match" | sed -E 's/^"[^"]+"[[:space:]]*:[[:space:]]*//'
}

json_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    printf '%s' "$value"
}

emit_after_llm_modify() {
    local replacement_text="$1"
    local canonical_provider="${provider:-custom-zai-telegram-safe}"
    local canonical_model="${model:-custom-zai-telegram-safe::glm-5}"
    local session_fragment=""
    local iteration_fragment=""
    local input_tokens_fragment=""
    local output_tokens_fragment=""

    if [[ -n "$session_key" ]]; then
        session_fragment=",\"session_key\":\"$(json_escape "$session_key")\""
    fi
    if [[ -n "$iteration" ]]; then
        iteration_fragment=",\"iteration\":$iteration"
    fi
    if [[ -n "$input_tokens" ]]; then
        input_tokens_fragment=",\"input_tokens\":$input_tokens"
    fi
    if [[ -n "$output_tokens" ]]; then
        output_tokens_fragment=",\"output_tokens\":$output_tokens"
    fi

    printf '{"action":"modify","data":{"provider":"%s","model":"%s","text":"%s","tool_calls":[]%s%s%s%s}}\n' \
        "$(json_escape "$canonical_provider")" \
        "$(json_escape "$canonical_model")" \
        "$(json_escape "$replacement_text")" \
        "$session_fragment" \
        "$iteration_fragment" \
        "$input_tokens_fragment" \
        "$output_tokens_fragment"
}

event="$(extract_json_string "event")"
model="$(extract_json_string "model")"
provider="$(extract_json_string "provider")"
session_key="$(extract_json_string "session_key")"
if [[ -z "$session_key" ]]; then
    session_key="$(extract_json_string "session_id")"
fi
iteration="$(extract_json_number "iteration")"
input_tokens="$(extract_json_number "input_tokens")"
output_tokens="$(extract_json_number "output_tokens")"

is_telegram_safe_lane=false
case "$model" in
    custom-zai-telegram-safe::*)
        is_telegram_safe_lane=true
        ;;
esac

if [[ "$provider" == "custom-zai-telegram-safe" || "$provider" == "zai-telegram-safe" ]]; then
    is_telegram_safe_lane=true
fi

if [[ "$is_telegram_safe_lane" != true ]]; then
    exit 0
fi

emit_after_llm_guard() {
    local text has_nonempty_tool_calls=false
    local has_strong_telemetry=false looks_like_status=false mentions_wrong_model=false

    text="$(extract_last_json_string "text")"

    if grep -Eq '"tool_calls"[[:space:]]*:[[:space:]]*\[[[:space:]]*\{' <<<"$compact_payload"; then
        has_nonempty_tool_calls=true
    fi

    if grep -Eiq 'activity log|running:|searching memory|mcp__[[:alnum:]_:.:-]+|nodes_list|sessions_list|missing '\''action'\'' parameter' <<<"$text"; then
        has_strong_telemetry=true
    fi

    if grep -Eiq 'статус|канал:|модель:|провайдер:|режим:|safe-text|система' <<<"$text"; then
        looks_like_status=true
    fi

    if grep -Fq 'zai::glm-5' <<<"$text"; then
        mentions_wrong_model=true
    fi

    if [[ "$looks_like_status" == true && ( "$has_nonempty_tool_calls" == true || "$has_strong_telemetry" == true || "$mentions_wrong_model" == true ) ]]; then
        emit_after_llm_modify $'Статус: Online\nКанал: Telegram (@moltis-bot)\nМодель: custom-zai-telegram-safe::glm-5\nПровайдер: custom-zai-telegram-safe\nРежим: safe-text'
        exit 0
    fi

    if [[ "$has_nonempty_tool_calls" == true || "$has_strong_telemetry" == true ]]; then
        emit_after_llm_modify 'В Telegram-safe режиме я отвечаю без инструментов и внутренних логов. Если нужен browser/search/cron/process workflow, продолжим в web UI или операторской сессии.'
        exit 0
    fi
}

case "$event" in
    AfterLLMCall)
        emit_after_llm_guard
        ;;
esac

exit 0
