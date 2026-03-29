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

extract_json_array() {
    local key="$1"

    printf '%s' "$payload" | awk -v key="$key" '
        BEGIN {
            RS = ""
            ORS = ""
            needle = "\"" key "\""
            state = "seek"
            value = ""
            depth = 0
            in_string = 0
            escape = 0
        }
        {
            text = $0
            n = length(text)
            for (i = 1; i <= n; i++) {
                c = substr(text, i, 1)
                if (state == "seek") {
                    if (substr(text, i, length(needle)) != needle) {
                        continue
                    }
                    j = i + length(needle)
                    while (j <= n && substr(text, j, 1) ~ /[ \t\r\n]/) {
                        j++
                    }
                    if (substr(text, j, 1) != ":") {
                        continue
                    }
                    j++
                    while (j <= n && substr(text, j, 1) ~ /[ \t\r\n]/) {
                        j++
                    }
                    if (substr(text, j, 1) != "[") {
                        continue
                    }
                    state = "capture"
                    depth = 0
                    in_string = 0
                    escape = 0
                    i = j - 1
                    continue
                }

                value = value c

                if (escape) {
                    escape = 0
                    continue
                }
                if (c == "\\") {
                    escape = 1
                    continue
                }
                if (c == "\"") {
                    in_string = !in_string
                    continue
                }
                if (in_string) {
                    continue
                }
                if (c == "[") {
                    depth++
                    continue
                }
                if (c == "]") {
                    depth--
                    if (depth == 0) {
                        print value
                        exit 0
                    }
                }
            }
        }
        END {
            if (value == "") {
                exit 1
            }
        }
    '
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

build_message_json() {
    local role="$1"
    local content="$2"

    printf '{"role":"%s","content":"%s"}' "$(json_escape "$role")" "$(json_escape "$content")"
}

append_message_to_array() {
    local messages_json="$1"
    local role="$2"
    local content="$3"
    local message_json

    message_json="$(build_message_json "$role" "$content")"
    if [[ "$messages_json" == "[]" ]]; then
        printf '[%s]' "$message_json"
        return
    fi

    printf '%s,%s]' "${messages_json%]}" "$message_json"
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

emit_before_llm_modified_payload() {
    local messages_json="$1"
    local tool_count="$2"
    local session_key provider model iteration

    session_key="$(extract_first_string session_key || true)"
    provider="$(extract_first_string provider || true)"
    model="$(extract_first_string model || true)"
    iteration="$(extract_first_number iteration || true)"

    printf '{"action":"modify","data":{%s%s%s%s%s,"messages":%s}}\n' \
        "$(json_string_field session_key "${session_key:-current-session}")" \
        "$(append_optional_string_field provider "$provider")" \
        "$(append_optional_string_field model "$model")" \
        "$(append_optional_number_field tool_count "$tool_count")" \
        "$(append_optional_number_field iteration "$iteration")" \
        "$messages_json"
}

log_guard_diagnostic() {
    local event_name="$1"
    local preview_source="$2"
    local preview_value="$3"
    local text_length="$4"
    local is_safe_lane="$5"
    local delivery_telemetry="$6"
    local after_llm_intent="$7"
    local planning_leak="$8"
    local status_like="$9"

    printf 'telegram-safe-llm-guard diag event=%s source=%s text_len=%s safe_lane=%s delivery_telemetry=%s after_llm_intent=%s planning=%s status=%s preview=%s\n' \
        "$event_name" \
        "$preview_source" \
        "$text_length" \
        "$is_safe_lane" \
        "$delivery_telemetry" \
        "$after_llm_intent" \
        "$planning_leak" \
        "$status_like" \
        "$preview_value" >&2
}

event="$(extract_first_string event || true)"
model="$(extract_first_string model || true)"
provider="$(extract_first_string provider || true)"
response_text="$(extract_first_string text || true)"
response_text_flat="$(
    printf '%s' "${response_text:-}" \
        | tr '\r\n' '  ' \
        | sed 's/[[:space:]][[:space:]]*/ /g'
)"

is_telegram_safe_lane=false
case "${model:-}" in
    custom-zai-telegram-safe::*)
        is_telegram_safe_lane=true
        ;;
esac
if [[ "${provider:-}" == "custom-zai-telegram-safe" || "${provider:-}" == "zai-telegram-safe" ]]; then
    is_telegram_safe_lane=true
fi

if [[ "$event" != "BeforeLLMCall" && "$event" != "AfterLLMCall" && "$event" != "MessageSending" ]]; then
    exit 0
fi

tool_count="$(extract_first_number tool_count || true)"
tool_calls_present=false
if printf '%s' "$payload_flat" | grep -Eq '"tool_calls"[[:space:]]*:[[:space:]]*\[[[:space:]]*\{'; then
    tool_calls_present=true
fi

# Keep delivery-time stripping strict, but allow broader AfterLLM fail-closed
# interception before text-fallback parsing can promote intent text into tools.
has_delivery_internal_telemetry=false
if printf '%s' "${response_text_flat:-$payload_flat}" | grep -Eiq "activity log|running:|searching memory|thinking|nodes_list|sessions_list|missing 'action' parameter|list failed:|mcp__|tool-progress|tool call"; then
    has_delivery_internal_telemetry=true
fi

has_after_llm_tool_intent=false
if [[ "$event" == "AfterLLMCall" ]] && \
   printf '%s' "${response_text_flat:-$payload_flat}" | grep -Eiq "no remote nodes available|let me (check|search|inspect|look|study|read|try|get)|i( ?|')ll (check|search|inspect|look|study|read|try|get)|сейчас (проверю|поищу|изучу|посмотрю)|проверю через|посмотрю через|открою (документац|docs|сайт)|перейду на |наш[её]л.{0,120}(официальн.{0,60})?(документац|docs|documentation|manual|guide|инструкц)|наш[её]л.{0,120}(репозитор|github)|((отлично|супер|окей|ладно)[!,.[:space:]]{0,12})?давай(те)? (изучу|разберу|посмотрю|проверю|почитаю|получу|найду|открою|проанализирую)|хорошо,? (изучу|проверю|посмотрю|почитаю).{0,120}(документац|docs|documentation|manual|guide|инструкц)|начну с (поиска|анализа|изучения|просмотра)|получ(у|им|ить).{0,120}(документац|docs|documentation|manual|guide|инструкц)|изучу.{0,80}(полностью|целиком|всю|весь|дальше)|попробую.{0,120}(найти|посмотреть|прочитать|изучить).{0,120}(навык|skills?|workspace|документац|файл)|mounted workspace|workspace that's mounted|read the skill files|look at the existing skills|find the skills|create_skill tool|documentation search tool|существующ(ие|его) навык|имеющ(егося|ийся) навы"; then
    has_after_llm_tool_intent=true
fi

has_user_visible_internal_planning=false
if [[ "$event" == "AfterLLMCall" || "$event" == "MessageSending" ]] && \
   printf '%s' "${response_text_flat:-$payload_flat}" | grep -Eiq "пользователь просит|the user (is )?asking|у меня есть доступ к|i have access to|мне доступны|сначала найду|для начала найду|((отлично|супер|окей|ладно)[!,.[:space:]]{0,12})?давай(те)? (получу|найду|изучу|посмотрю|открою|проверю|проанализирую)|хорошо,? (изучу|проверю|посмотрю|почитаю).{0,120}(документац|docs|documentation|manual|guide|инструкц)|начну с (поиска|анализа|изучения|просмотра)|наш[её]л.{0,120}(репозитор|github|документац|docs|documentation|manual|guide|инструкц)|получ(у|им|ить).{0,120}(документац|docs|documentation|manual|guide|инструкц)|mcp__|mounted workspace|skill files|existing skills|существующ(ие|его) навык|имеющ(егося|ийся) навы"; then
    has_user_visible_internal_planning=true
fi
if [[ "$event" == "AfterLLMCall" || "$event" == "MessageSending" ]] && \
   printf '%s' "${response_text_flat:-$payload_flat}" | grep -Eiq "(у меня есть доступ к|i have access to|мне доступны).{0,160}((^|[^[:alnum:]_])create_skill([^[:alnum:]_]|$)|skills?|tavily|mcp__)"; then
    has_user_visible_internal_planning=true
fi

looks_like_status=false
if printf '%s' "$payload_flat" | grep -Eiq '(^|[^[:alnum:]_])/?status([^[:alnum:]_]|$)|статус( системы)?|параметр[[:space:]]*\||канал: telegram|провайдер:|режим: safe-text|модель: custom-zai-telegram-safe::glm-5|доступные навыки|готов к работе'; then
    looks_like_status=true
fi

looks_like_broad_research_request=false
if printf '%s' "$payload_flat" | grep -Eiq '((изучи|изучить|исследуй|исследовать|прочитай|прочитать|study|research|analy[sz]e|read).{0,120}(документац|инструкц|курс|официальн|docs|documentation|manual|guide|гайд|сайт|site))|((документац|инструкц|курс|официальн|docs|documentation|manual|guide|гайд|сайт|site).{0,120}(полностью|целиком|всю|весь|глубоко|thoroughly|fully|end[ -]?to[ -]?end))'; then
    looks_like_broad_research_request=true
fi

if [[ "$event" == "AfterLLMCall" || "$event" == "MessageSending" ]]; then
    diagnostic_preview_source="text"
    diagnostic_preview_value="$response_text_flat"
    if [[ -z "$diagnostic_preview_value" ]]; then
        diagnostic_preview_source="payload"
        diagnostic_preview_value="$payload_flat"
    fi
    diagnostic_preview_value="$(
        printf '%s' "$diagnostic_preview_value" \
            | tr '\r\n' '  ' \
            | sed 's/[[:space:]][[:space:]]*/ /g' \
            | cut -c1-220
    )"
    if [[ -z "$response_text_flat" || "$has_delivery_internal_telemetry" == true || "$has_after_llm_tool_intent" == true || "$has_user_visible_internal_planning" == true || "$looks_like_broad_research_request" == true || "$(printf '%s' "$payload_flat" | grep -Eic 'документац|docs|codex-update|навык|skill')" -gt 0 ]]; then
        log_guard_diagnostic \
            "$event" \
            "$diagnostic_preview_source" \
            "$diagnostic_preview_value" \
            "${#response_text_flat}" \
            "$is_telegram_safe_lane" \
            "$has_delivery_internal_telemetry" \
            "$has_after_llm_tool_intent" \
            "$has_user_visible_internal_planning" \
            "$looks_like_status"
    fi
fi

already_guarded_long_research=false
if printf '%s' "$payload_flat" | grep -Fq 'Telegram-safe long-research guard'; then
    already_guarded_long_research=true
fi

if [[ "$event" == "MessageSending" ]]; then
    if [[ "$is_telegram_safe_lane" != true && "$looks_like_status" != true && "$has_delivery_internal_telemetry" != true && "$has_after_llm_tool_intent" != true && "$has_user_visible_internal_planning" != true ]]; then
        exit 0
    fi
elif [[ "$is_telegram_safe_lane" != true ]]; then
    exit 0
fi

if [[ "$event" == "BeforeLLMCall" && "$looks_like_broad_research_request" == true && "$already_guarded_long_research" != true ]]; then
    messages_json="$(extract_json_array messages || true)"
    if [[ -n "${messages_json:-}" ]]; then
        long_research_guard=$'Telegram-safe long-research guard:\n- This user-facing Telegram lane must remain text-only.\n- Do not browse, search, inspect local files, inspect skills, or call any tools.\n- Do not say that you are going to check, search, open docs, inspect the environment, inspect the mounted workspace, read skill files, or look at existing skills right now.\n- Avoid self-action phrasing such as: "попробую", "найду", "посмотрю", "изучу", "let me", "I will".\n- If the request requires deep research or full doc/course study, do not provide a plan of action and do not promise to start searching.\n- For this turn, answer in Russian with exactly this single sentence and nothing else: "В Telegram-safe режиме я не запускаю инструменты и не провожу глубокий поиск. Могу дать краткий ответ без поиска или продолжить в web UI/операторской сессии для полного разбора."'
        emit_before_llm_modified_payload "$(append_message_to_array "$messages_json" system "$long_research_guard")" 0
        exit 0
    fi
fi

if [[ "$event" == "MessageSending" && "$looks_like_status" != true && "$has_delivery_internal_telemetry" != true && "$has_after_llm_tool_intent" != true && "$has_user_visible_internal_planning" != true ]]; then
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

if [[ "$tool_calls_present" == true || "$has_delivery_internal_telemetry" == true || "$has_after_llm_tool_intent" == true || "$has_user_visible_internal_planning" == true ]]; then
    fallback_text='В Telegram-safe режиме я не запускаю инструменты и не показываю внутренние логи. Для browser/search/process workflow продолжим в web UI или операторской сессии.'
    if [[ "$event" == "AfterLLMCall" ]]; then
        emit_modified_payload "$fallback_text" true
    else
        emit_modified_payload "$fallback_text" false
    fi
    exit 0
fi

exit 0
