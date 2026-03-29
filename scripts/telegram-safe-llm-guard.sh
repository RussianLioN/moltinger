#!/usr/bin/env bash
set -euo pipefail

payload="$(cat)"
if [[ -z "${payload:-}" ]]; then
    exit 0
fi

if ! jq -e '.' >/dev/null 2>&1 <<<"$payload"; then
    exit 0
fi

event="$(jq -r '.event // empty' <<<"$payload")"
model="$(jq -r '.data.model // .model // empty' <<<"$payload")"
provider="$(jq -r '.data.provider // .provider // empty' <<<"$payload")"
session_key="$(jq -r '.data.session_key // .session_key // .session_id // "current-session"' <<<"$payload")"

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

extract_last_user_text() {
    jq -r '
        def content_to_text:
            if . == null then ""
            elif type == "string" then .
            elif type == "array" then
                [ .[]?
                  | if type == "string" then .
                    elif type == "object" then (.text // .input_text // .content // "")
                    else ""
                    end
                ] | join("\n")
            elif type == "object" then (.text // .input_text // .content // "")
            else ""
            end;
        (.data.messages // .messages // []) as $messages
        | [ $messages[]? | select(.role == "user") | (.content | content_to_text) ]
        | last // ""
    ' <<<"$payload"
}

emit_before_llm_guard() {
    local last_user_text normalized guard
    last_user_text="$(extract_last_user_text)"
    normalized="$(printf '%s' "$last_user_text" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    if [[ "$normalized" == "/status" ]]; then
        guard=$'Telegram-safe status contract:\n- Never call or simulate tools.\n- Never output Activity log, tool names, raw commands, or internal steps.\n- For the literal command /status reply with exactly these plain-text lines and nothing else:\nСтатус: online\nСессия: `'"$session_key"$'`\nМодель: '"$model"$'\nРежим: telegram-safe\n- Do not inspect processes, cron, tmux, skills, nodes, filesystem, or environment.'
    else
        guard=$'Telegram-safe response contract:\n- Never call or simulate tools, even if tool schemas are visible.\n- Never output Activity log, tool names, raw commands, or internal steps.\n- Answer directly from current conversation context only.\n- If the request would require browser/search/exec/cron/process or other multi-step tools, say that Telegram-safe mode cannot run that workflow and suggest continuing in the web UI or operator session.'
    fi

    jq -c --arg guard "$guard" '
        (.data // {}) as $data
        | ($data.messages // []) as $messages
        | {action:"modify", data:($data + {messages:($messages + [{role:"system", content:$guard}])})}
    ' <<<"$payload"
}

emit_after_llm_guard() {
    local text tool_calls_count
    text="$(jq -r '.data.text // .text // ""' <<<"$payload")"
    tool_calls_count="$(jq -r '((.data.tool_calls // .tool_calls // []) | length)' <<<"$payload")"

    local has_activity_log=false
    if grep -Eiq 'activity log|using glm-5|tool call|process|cron|tmux|list failed:' <<<"$text"; then
        has_activity_log=true
    fi

    local looks_like_status=false
    if grep -Eiq 'статус|сессия|параметр|всё работает|режим: telegram|песочниц|активност' <<<"$text"; then
        looks_like_status=true
    fi

    local mentions_wrong_model=false
    if grep -Fq 'zai::glm-5' <<<"$text"; then
        mentions_wrong_model=true
    fi

    if [[ "$looks_like_status" == true && ( "$tool_calls_count" != "0" || "$has_activity_log" == true || "$mentions_wrong_model" == true ) ]]; then
        local status_text
        status_text=$'Статус: online\nСессия: `'"$session_key"$'`\nМодель: '"$model"$'\nРежим: telegram-safe'
        jq -c --arg text "$status_text" '
            (.data // {}) as $data
            | {action:"modify", data:($data + {text:$text, tool_calls:[]})}
        ' <<<"$payload"
        exit 0
    fi

    if [[ "$tool_calls_count" != "0" || "$has_activity_log" == true ]]; then
        local fallback_text
        fallback_text='В Telegram-safe режиме я не выполняю многошаговые инструменты и не показываю внутренние логи. Если нужен browser/search/cron/process workflow, продолжим в web UI или операторской сессии.'
        jq -c --arg text "$fallback_text" '
            (.data // {}) as $data
            | {action:"modify", data:($data + {text:$text, tool_calls:[]})}
        ' <<<"$payload"
        exit 0
    fi
}

case "$event" in
    BeforeLLMCall)
        emit_before_llm_guard
        ;;
    AfterLLMCall)
        emit_after_llm_guard
        ;;
esac

exit 0
