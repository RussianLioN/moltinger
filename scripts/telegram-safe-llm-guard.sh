#!/usr/bin/env bash
set -euo pipefail

payload="$(cat)"
if [[ -z "${payload:-}" ]]; then
    exit 0
fi

AUDIT_FILE="${MOLTIS_TELEGRAM_SAFE_LLM_GUARD_AUDIT_FILE:-}"

write_audit_line() {
    local message="$1"
    if [[ -z "${AUDIT_FILE:-}" ]]; then
        return 0
    fi

    mkdir -p "$(dirname "$AUDIT_FILE")" 2>/dev/null || true
    printf '%s pid=%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$$" "$message" >>"$AUDIT_FILE" 2>/dev/null || true
}

payload_flat="$(
    printf '%s' "$payload" \
        | tr '\r\n' '  ' \
        | sed 's/[[:space:]][[:space:]]*/ /g'
)"

extract_first_string() {
    local key="$1"

    printf '%s' "$payload" | awk -v key="$key" '
        BEGIN {
            RS = ""
            ORS = ""
            needle = "\"" key "\""
            state = "seek"
            value = ""
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
                    if (substr(text, j, 1) != "\"") {
                        continue
                    }
                    state = "capture"
                    value = ""
                    escape = 0
                    i = j
                    continue
                }

                if (escape) {
                    if (c == "n") {
                        value = value "\n"
                    } else if (c == "r") {
                        value = value "\r"
                    } else if (c == "t") {
                        value = value "\t"
                    } else {
                        value = value c
                    }
                    escape = 0
                    continue
                }

                if (c == "\\") {
                    escape = 1
                    continue
                }

                if (c == "\"") {
                    print value
                    exit 0
                }

                value = value c
            }
        }
        END {
            exit 1
        }
    '
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

extract_json_object() {
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
                    if (substr(text, j, 1) != "{") {
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
                if (c == "{") {
                    depth++
                    continue
                }
                if (c == "}") {
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

append_field_to_object() {
    local object_json="$1"
    local field_fragment="$2"

    if [[ -z "$field_fragment" ]]; then
        printf '%s' "$object_json"
        return
    fi

    if [[ -z "$object_json" || "$object_json" == "{}" ]]; then
        printf '{%s}' "$field_fragment"
        return
    fi

    printf '%s,%s}' "${object_json%\}}" "$field_fragment"
}

filter_top_level_object_fields() {
    local object_json="$1"
    shift
    local remove_csv=""
    local field_name

    for field_name in "$@"; do
        if [[ -n "$remove_csv" ]]; then
            remove_csv="${remove_csv},${field_name}"
        else
            remove_csv="$field_name"
        fi
    done

    printf '%s' "$object_json" | awk -v remove_csv="$remove_csv" '
        BEGIN {
            RS = ""
            ORS = ""
            split(remove_csv, remove_keys, ",")
            for (i in remove_keys) {
                if (remove_keys[i] != "") {
                    remove[remove_keys[i]] = 1
                }
            }
            out = ""
            member = ""
            started = 0
            in_string = 0
            escape = 0
            depth = 0
        }

        function trim(value) {
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            return value
        }

        function flush_member(    item, key) {
            item = trim(member)
            member = ""
            if (item == "") {
                return
            }

            key = ""
            if (match(item, /^"[^"]*"/)) {
                key = substr(item, 2, RLENGTH - 2)
                if (key in remove) {
                    return
                }
            }

            if (out != "") {
                out = out "," item
            } else {
                out = item
            }
        }

        {
            text = $0
            n = length(text)
            for (i = 1; i <= n; i++) {
                c = substr(text, i, 1)

                if (!started) {
                    if (c == "{") {
                        started = 1
                    }
                    continue
                }

                if (escape) {
                    member = member c
                    escape = 0
                    continue
                }
                if (c == "\\") {
                    member = member c
                    escape = 1
                    continue
                }
                if (c == "\"") {
                    member = member c
                    in_string = !in_string
                    continue
                }
                if (in_string) {
                    member = member c
                    continue
                }

                if (c == "}" && depth == 0) {
                    flush_member()
                    print "{" out "}"
                    exit 0
                }
                if (c == "," && depth == 0) {
                    flush_member()
                    continue
                }
                if (c == "{" || c == "[") {
                    depth++
                } else if (c == "}" || c == "]") {
                    depth--
                }

                member = member c
            }
        }

        END {
            if (!started) {
                print "{}"
            }
        }
    '
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

prepend_message_to_array() {
    local messages_json="$1"
    local role="$2"
    local content="$3"
    local message_json

    message_json="$(build_message_json "$role" "$content")"
    if [[ "$messages_json" == "[]" ]]; then
        printf '[%s]' "$message_json"
        return
    fi

    printf '[%s,%s' "$message_json" "${messages_json#\[}"
}

discover_runtime_skill_names_csv() {
    local csv_override="${MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES:-}"
    local runtime_root="${MOLTIS_RUNTIME_SKILLS_ROOT:-/home/moltis/.moltis/skills}"
    local names=""
    local path=""
    local skill_name=""

    if [[ -n "$csv_override" ]]; then
        printf '%s' "$csv_override"
        return 0
    fi

    [[ -d "$runtime_root" ]] || return 1

    for path in "$runtime_root"/*/SKILL.md; do
        [[ -f "$path" ]] || continue
        skill_name="${path%/SKILL.md}"
        skill_name="${skill_name##*/}"
        [[ -n "$skill_name" ]] || continue
        case ",$names," in
            *,"$skill_name",*)
                continue
                ;;
        esac
        names="${names:+$names,}$skill_name"
    done

    [[ -n "$names" ]] || return 1
    printf '%s' "$names"
}

format_skill_names_bullets() {
    local csv="$1"
    local bullet_text=""
    local skill_name=""

    if [[ -z "$csv" ]]; then
        printf '%s' '- runtime snapshot unavailable in hook context'
        return
    fi

    local old_ifs="$IFS"
    IFS=','
    read -r -a skill_items <<<"$csv"
    IFS="$old_ifs"

    for skill_name in "${skill_items[@]}"; do
        [[ -n "$skill_name" ]] || continue
        bullet_text="${bullet_text}${bullet_text:+$'\n'}- ${skill_name}"
    done

    if [[ -z "$bullet_text" ]]; then
        bullet_text='- runtime snapshot unavailable in hook context'
    fi

    printf '%s' "$bullet_text"
}

build_skill_runtime_snapshot_message() {
    local csv="${1:-}"
    local bullets=""

    bullets="$(format_skill_names_bullets "$csv")"

    cat <<EOF
Telegram-safe skill runtime note:
- Для текущего хода не доказывай отсутствие навыков через exec/find/cat по ~/.moltis/skills, /home/moltis/.moltis/skills, /server/skills, mounted workspace или repo paths.
- Если нужен ответ про навыки, опирайся на runtime-discovered skills и на best-effort snapshot ниже. Если snapshot недоступен, честно скажи, что hook не подтверждает список, но это не означает отсутствия навыков.
- Для create/update/delete навыков предпочитай dedicated tools create_skill, update_skill, delete_skill.
- Канонический scaffold: skills/<name>/SKILL.md.
- Best-effort runtime snapshot:
${bullets}
EOF
}

build_skill_authoring_guard_message() {
    cat <<'EOF'
Telegram-safe skill-authoring contract:
- Для skill visibility/create/update/delete не используй browser, web-search, Tavily, exec и filesystem-пробы как primary path.
- Допустимые tool paths для такого хода: create_skill, update_skill, delete_skill, session_state, send_message, send_image.
- Если runtime snapshot недоступен, не делай вывод "навыков нет"; скажи, что sandbox filesystem не является доказательством отсутствия навыка.
- Если create_skill или update_skill вернул validation/frontmatter error, кратко объясни ошибку и повтори попытку с валидным SKILL.md.
EOF
}

build_skill_probe_result_text() {
    local csv="${1:-}"
    local bullets=""

    bullets="$(format_skill_names_bullets "$csv")"

    cat <<EOF
Telegram-safe runtime note for skills:
${bullets}

Filesystem-пробы по ~/.moltis/skills, /home/moltis/.moltis/skills, /server/skills и mounted workspace не считаются доказательством наличия или отсутствия навыка.
Для skill visibility отвечай осторожно по runtime context, а для create/update/delete используй dedicated tools create_skill, update_skill, delete_skill.
Канонический scaffold: skills/<name>/SKILL.md.
EOF
}

build_exec_heredoc_command() {
    local text="$1"

    printf "cat <<'__MOLTIS_TELEGRAM_SAFE__'\n%s\n__MOLTIS_TELEGRAM_SAFE__" "$text"
}

emit_before_tool_modified_payload() {
    local tool_name_fragment="$1"
    local arguments_json="$2"
    local data_object_json modified_data_json

    data_object_json="$(extract_json_object data || true)"
    if [[ -z "$data_object_json" ]]; then
        return 1
    fi

    modified_data_json="$(filter_top_level_object_fields "$data_object_json" tool arguments)"
    if [[ -n "$tool_name_fragment" ]]; then
        modified_data_json="$(append_field_to_object "$modified_data_json" "$tool_name_fragment")"
    fi
    modified_data_json="$(append_field_to_object "$modified_data_json" "\"arguments\":$arguments_json")"
    printf '{"action":"modify","data":%s}\n' "$modified_data_json"
}

emit_modified_payload_preserve_tool_calls() {
    local text="$1"
    local session_key provider model finish_reason input_tokens output_tokens reasoning_tokens data_object_json modified_data_json tool_calls_json

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
    data_object_json="$(extract_json_object data || true)"
    tool_calls_json="$(extract_json_array tool_calls || true)"

    if [[ -n "$data_object_json" ]]; then
        modified_data_json="$(filter_top_level_object_fields "$data_object_json" text)"
        modified_data_json="$(append_field_to_object "$modified_data_json" "$(json_string_field text "$text")")"
        printf '{"action":"modify","data":%s}\n' "$modified_data_json"
        return
    fi

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
            if [[ -n "$tool_calls_json" && "$tool_calls_json" != "[]" ]]; then
                printf ',\"tool_calls\":%s' "$tool_calls_json"
            fi
        )"
}

extract_tool_call_names() {
    local tool_calls_json="${1:-}"

    [[ -n "$tool_calls_json" && "$tool_calls_json" != "[]" ]] || return 1

    printf '%s' "$tool_calls_json" \
        | grep -oE '(^|[\[,])[[:space:]]*\{[[:space:]]*"name"[[:space:]]*:[[:space:]]*"[^"]+"' \
        | sed -E 's/^.*"name"[[:space:]]*:[[:space:]]*"//; s/"$//'
}

tool_name_is_allowlisted() {
    local tool_name="${1:-}"
    case "$tool_name" in
        create_skill|update_skill|delete_skill|session_state|send_message|send_image)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

tool_calls_only_allowlisted() {
    local tool_calls_json="${1:-}"
    local saw_name=false
    local tool_name=""

    while IFS= read -r tool_name; do
        [[ -n "$tool_name" ]] || continue
        saw_name=true
        if ! tool_name_is_allowlisted "$tool_name"; then
            return 1
        fi
    done < <(extract_tool_call_names "$tool_calls_json" || true)

    $saw_name
}

tool_calls_include_disallowed() {
    local tool_calls_json="${1:-}"
    local tool_name=""

    while IFS= read -r tool_name; do
        [[ -n "$tool_name" ]] || continue
        if ! tool_name_is_allowlisted "$tool_name"; then
            return 0
        fi
    done < <(extract_tool_call_names "$tool_calls_json" || true)

    return 1
}

emit_modified_payload() {
    local text="$1"
    local include_tool_calls="${2:-false}"
    local session_key provider model finish_reason input_tokens output_tokens reasoning_tokens data_object_json modified_data_json

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
    data_object_json="$(extract_json_object data || true)"

    if [[ -n "$data_object_json" ]]; then
        modified_data_json="$(filter_top_level_object_fields "$data_object_json" text tool_calls)"
        if [[ "$include_tool_calls" == "true" ]]; then
            modified_data_json="$(append_field_to_object "$modified_data_json" '"tool_calls":[]')"
        fi
        modified_data_json="$(append_field_to_object "$modified_data_json" "$(json_string_field text "$text")")"
        printf '{"action":"modify","data":%s}\n' "$modified_data_json"
        return
    fi

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
    local tool_count="${2:-}"
    local session_key provider model iteration data_object_json modified_data_json

    session_key="$(extract_first_string session_key || true)"
    provider="$(extract_first_string provider || true)"
    model="$(extract_first_string model || true)"
    iteration="$(extract_first_number iteration || true)"

    data_object_json="$(extract_json_object data || true)"
    if [[ -n "$data_object_json" ]]; then
        modified_data_json="$(filter_top_level_object_fields "$data_object_json" messages tool_count)"
        if [[ -n "$tool_count" ]]; then
            modified_data_json="$(append_field_to_object "$modified_data_json" "$(json_number_field tool_count "$tool_count")")"
        fi
        modified_data_json="$(append_field_to_object "$modified_data_json" "\"messages\":$messages_json")"
        printf '{"action":"modify","data":%s}\n' "$modified_data_json"
        return
    fi

    printf '{"action":"modify","data":{%s%s%s%s%s%s}}\n' \
        "$(json_string_field session_key "${session_key:-current-session}")" \
        "$(append_optional_string_field provider "$provider")" \
        "$(append_optional_string_field model "$model")" \
        "$(append_optional_number_field iteration "$iteration")" \
        "$(append_optional_number_field tool_count "$tool_count")" \
        "$(printf ',\"messages\":%s' "$messages_json")"
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

    write_audit_line "diag event=$event_name source=$preview_source text_len=$text_length safe_lane=$is_safe_lane delivery_telemetry=$delivery_telemetry after_llm_intent=$after_llm_intent planning=$planning_leak status=$status_like preview=$(printf '%s' "$preview_value" | tr '\r\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g' | cut -c1-220)"
}

event="$(extract_first_string event || true)"
model="$(extract_first_string model || true)"
provider="$(extract_first_string provider || true)"
response_text="$(extract_first_string text || true)"
tool_name="$(extract_first_string tool || true)"
command_arg="$(extract_first_string command || true)"
tool_calls_json="$(extract_json_array tool_calls || true)"
response_text_flat="$(
    printf '%s' "${response_text:-}" \
        | tr '\r\n' '  ' \
        | sed 's/[[:space:]][[:space:]]*/ /g'
)"

write_audit_line "invoke event=${event:-<none>} provider=${provider:-<none>} model=${model:-<none>} payload_len=${#payload_flat} text_len=${#response_text_flat}"

is_telegram_safe_lane=false
case "${model:-}" in
    custom-zai-telegram-safe::*)
        is_telegram_safe_lane=true
        ;;
esac
if [[ "${provider:-}" == "custom-zai-telegram-safe" || "${provider:-}" == "zai-telegram-safe" ]]; then
    is_telegram_safe_lane=true
fi

if [[ "$event" != "BeforeLLMCall" && "$event" != "AfterLLMCall" && "$event" != "BeforeToolCall" && "$event" != "MessageSending" ]]; then
    exit 0
fi

tool_count="$(extract_first_number tool_count || true)"
tool_calls_present=false
if [[ -n "${tool_calls_json:-}" && "$tool_calls_json" != "[]" ]]; then
    tool_calls_present=true
fi
tool_calls_allowlisted_only=false
tool_calls_have_disallowed=false
if [[ "$tool_calls_present" == true ]]; then
    if tool_calls_only_allowlisted "$tool_calls_json"; then
        tool_calls_allowlisted_only=true
    fi
    if tool_calls_include_disallowed "$tool_calls_json"; then
        tool_calls_have_disallowed=true
    fi
fi

# Keep delivery-time stripping strict, but allow broader AfterLLM fail-closed
# interception before text-fallback parsing can promote intent text into tools.
has_delivery_internal_telemetry=false
if printf '%s' "${response_text_flat:-$payload_flat}" | grep -Eiq "activity log|running:|searching memory|thinking|nodes_list|sessions_list|missing 'action' parameter|list failed:|mcp__|tool-progress|tool call"; then
    has_delivery_internal_telemetry=true
fi

has_after_llm_tool_intent=false
if [[ "$event" == "AfterLLMCall" ]] && \
   printf '%s' "${response_text_flat:-$payload_flat}" | grep -Eiq "no remote nodes available|let me (check|search|inspect|look|study|read|try|get)|i( ?|')ll (check|search|inspect|look|study|read|try|get)|сейчас (проверю|поищу|изучу|посмотрю)|проверю через|посмотрю через|открою (документац|docs|сайт)|перейду на |наш[её]л.{0,120}(официальн.{0,60})?(документац|docs|documentation|manual|guide|инструкц)|наш[её]л.{0,120}(репозитор|github)|((отлично|супер|окей|ладно)[!,.[:space:]]{0,12})?давай(те)? (изучу|разберу|посмотрю|проверю|почитаю|получу|найду|открою|проанализирую|сделаю)|хорошо,? (изучу|проверю|посмотрю|почитаю).{0,120}(документац|docs|documentation|manual|guide|инструкц)|[Хх]орошо[^[:cntrl:]]{0,80}[Дд]авай(те)?[[:space:]]+изучу|[Оо]тлично[^[:cntrl:]]{0,80}[Дд]авай(те)?[[:space:]]+изучу|[Дд]авай(те)?[[:space:]]+изучу.{0,160}(официальн.{0,60})?(документац|docs|documentation|manual|guide|инструкц)|начну с (поиска|анализа|изучения|просмотра)|[Нн]ачина(ю|ем)[:[:space:]]|получ(у|им|ить).{0,120}(документац|docs|documentation|manual|guide|инструкц)|изучу.{0,80}(полностью|целиком|всю|весь|дальше)|попробую.{0,120}(найти|посмотреть|прочитать|изучить).{0,120}(workspace|документац|файл|темплейт|template)|([Нн]айду|найду).{0,80}(темплейт|template|шаблон)|([Сс]мотрю|[Пп]роверяю).{0,80}(директори(ю|и)[[:space:]]+skills|skills[[:space:]]+directory)|mounted workspace|workspace that's mounted|read the skill files|look at the existing skills|find the skills|create_skill tool|documentation search tool"; then
    has_after_llm_tool_intent=true
fi

has_user_visible_internal_planning=false
if [[ "$event" == "AfterLLMCall" || "$event" == "MessageSending" ]] && \
   printf '%s' "${response_text_flat:-$payload_flat}" | grep -Eiq "пользователь просит|the user (is )?asking|у меня есть доступ к|i have access to|мне доступны|сначала найду|для начала найду|((отлично|супер|окей|ладно)[!,.[:space:]]{0,12})?давай(те)? (получу|найду|изучу|посмотрю|открою|проверю|проанализирую|сделаю)|хорошо,? (изучу|проверю|посмотрю|почитаю).{0,120}(документац|docs|documentation|manual|guide|инструкц)|[Хх]орошо[^[:cntrl:]]{0,80}[Дд]авай(те)?[[:space:]]+изучу|[Оо]тлично[^[:cntrl:]]{0,80}[Дд]авай(те)?[[:space:]]+изучу|[Дд]авай(те)?[[:space:]]+изучу.{0,160}(официальн.{0,60})?(документац|docs|documentation|manual|guide|инструкц)|начну с (поиска|анализа|изучения|просмотра)|[Нн]ачина(ю|ем)[:[:space:]]|наш[её]л.{0,120}(репозитор|github|документац|docs|documentation|manual|guide|инструкц)|получ(у|им|ить).{0,120}(документац|docs|documentation|manual|guide|инструкц)|([Нн]айду|найду).{0,80}(темплейт|template|шаблон)|([Сс]мотрю|[Пп]роверяю).{0,80}(директори(ю|и)[[:space:]]+skills|skills[[:space:]]+directory)|как пример|как реальн(ый|ого) пример|mcp__|mounted workspace|skill files|existing skills"; then
    has_user_visible_internal_planning=true
fi
if [[ "$event" == "AfterLLMCall" || "$event" == "MessageSending" ]] && \
   printf '%s' "${response_text_flat:-$payload_flat}" | grep -Eiq "(у меня есть доступ к|i have access to|мне доступны).{0,160}((^|[^[:alnum:]_])(create_skill|update_skill|delete_skill|browser|exec|process|cron)([^[:alnum:]_]|$)|tavily|mcp__)"; then
    has_user_visible_internal_planning=true
fi

looks_like_status=false
if printf '%s' "$payload_flat" | grep -Eiq '(^|[^[:alnum:]_])/?status([^[:alnum:]_]|$)|статус( системы)?|параметр[[:space:]]*\||канал: telegram|провайдер:|режим: safe-text|модель: custom-zai-telegram-safe::glm-5'; then
    looks_like_status=true
fi

looks_like_broad_research_request=false
if printf '%s' "$payload_flat" | grep -Eiq '((изучи|изучить|исследуй|исследовать|прочитай|прочитать|study|research|analy[sz]e|read).{0,120}(документац|инструкц|курс|официальн|docs|documentation|manual|guide|гайд|сайт|site))|((документац|инструкц|курс|официальн|docs|documentation|manual|guide|гайд|сайт|site).{0,120}(полностью|целиком|всю|весь|глубоко|thoroughly|fully|end[ -]?to[ -]?end))'; then
    looks_like_broad_research_request=true
fi

looks_like_skill_turn=false
if printf '%s' "$payload_flat" | grep -Eiq '((созда(й|дим|ть)|добав(ь|им|ить)|обнов(и|им|ить)|измени(ть|м)|удали(ть|м)?).{0,120}(навык|skills?|skill))|((какие|что).{0,80}(навык(и|ов)?|skills?))|((темплейт|template|шаблон).{0,120}(навык|skills?|skill))|((create|update|delete)[ _-]?skill)'; then
    looks_like_skill_turn=true
fi

has_skill_path_false_negative=false
if [[ "$event" == "AfterLLMCall" || "$event" == "MessageSending" ]] && \
   printf '%s' "${response_text_flat:-$payload_flat}" | grep -Eiq '(/home/moltis/\.moltis/skills|~/.moltis/skills).{0,120}(не существует|отсутствует|doesn.?t exist|not found)|либо были удалены, либо( ещё| еще)? не созданы'; then
    has_skill_path_false_negative=true
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
    if [[ -z "$response_text_flat" || "$has_delivery_internal_telemetry" == true || "$has_after_llm_tool_intent" == true || "$has_user_visible_internal_planning" == true || "$looks_like_broad_research_request" == true || "$has_skill_path_false_negative" == true ]]; then
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

if [[ "$event" == "BeforeLLMCall" ]]; then
    messages_json="$(extract_json_array messages || true)"
    if [[ -n "${messages_json:-}" ]]; then
        if [[ "$looks_like_broad_research_request" == true ]]; then
            # Hard override broad doc-study turns so the provider never sees the
            # original research request and cannot improvise a user-visible plan.
            long_research_guard=$'Telegram-safe hard override:\n- Ignore the prior conversation content for this turn.\n- This user-facing Telegram lane must remain text-only and must not expose internal planning.\n- Do not browse, search, inspect local files, inspect skills, or call any tools.\n- Do not say that you are going to check, search, open docs, inspect the environment, inspect the mounted workspace, read skill files, or look at existing skills right now.\n- Return exactly this single Russian sentence and nothing else: "В Telegram-safe режиме я не запускаю инструменты и не провожу глубокий поиск. Могу дать краткий ответ без поиска или продолжить в web UI/операторской сессии для полного разбора."'
            long_research_user=$'Верни в ответ ровно указанную в системном сообщении фразу. Не добавляй ничего.'
            messages_json="[$(build_message_json system "$long_research_guard"),$(build_message_json user "$long_research_user")]"
            write_audit_line "before_modify reason=long_research_hard_override tool_count=0 guard_reapplied=true previously_present=$already_guarded_long_research"
            emit_before_llm_modified_payload "$messages_json" 0
            exit 0
        fi
        if [[ "$looks_like_skill_turn" == true ]]; then
            skill_snapshot_csv="$(discover_runtime_skill_names_csv || true)"
            messages_json="$(prepend_message_to_array "$messages_json" system "$(build_skill_authoring_guard_message)")"
            messages_json="$(prepend_message_to_array "$messages_json" system "$(build_skill_runtime_snapshot_message "$skill_snapshot_csv")")"
            write_audit_line "before_modify reason=skill_turn tool_count=${tool_count:-preserve}"
            emit_before_llm_modified_payload "$messages_json" "${tool_count:-4}"
            exit 0
        fi
        write_audit_line "before_modify reason=safe_lane tool_count=0"
        emit_before_llm_modified_payload "$messages_json" 0
        exit 0
    fi
fi

if [[ "$event" == "BeforeToolCall" && "$is_telegram_safe_lane" == true ]]; then
    if tool_name_is_allowlisted "$tool_name"; then
        exit 0
    fi

    if [[ "$tool_name" == "exec" ]] && \
       printf '%s' "$command_arg" | grep -Eiq '(/home/moltis/\.moltis/skills|~/.moltis/skills|/server/skills|skills[[:space:]]+directory|SKILL\.md|find[^[:cntrl:]]{0,120}skills|ls[^[:cntrl:]]{0,80}skills|cat[^[:cntrl:]]{0,120}SKILL\.md|head[^[:cntrl:]]{0,120}SKILL\.md)'; then
        skill_snapshot_csv="$(discover_runtime_skill_names_csv || true)"
        synthetic_command="$(build_exec_heredoc_command "$(build_skill_probe_result_text "$skill_snapshot_csv")")"
        write_audit_line "emit_modify event=$event reason=skill_exec_probe tool=$tool_name"
        emit_before_tool_modified_payload '"tool":"exec"' "{\"command\":\"$(json_escape "$synthetic_command")\"}"
        exit 0
    fi
fi

if [[ "$event" == "MessageSending" && "$looks_like_status" != true && "$has_delivery_internal_telemetry" != true && "$has_after_llm_tool_intent" != true && "$has_user_visible_internal_planning" != true ]]; then
    exit 0
fi

canonical_status=$'Статус: Online\nКанал: Telegram (@moltinger_bot)\nМодель: custom-zai-telegram-safe::glm-5\nПровайдер: custom-zai-telegram-safe\nРежим: safe-text'

if [[ "$looks_like_status" == true ]]; then
    write_audit_line "emit_modify event=$event reason=status"
    if [[ "$event" == "AfterLLMCall" ]]; then
        emit_modified_payload "$canonical_status" true
    else
        emit_modified_payload "$canonical_status" false
    fi
    exit 0
fi

if [[ "$event" == "AfterLLMCall" && "$tool_calls_allowlisted_only" == true && ( "$has_delivery_internal_telemetry" == true || "$has_after_llm_tool_intent" == true || "$has_user_visible_internal_planning" == true || "$has_skill_path_false_negative" == true ) ]]; then
    fallback_text='Выполняю запрос по навыкам через встроенные инструменты без filesystem-проб. После завершения вернусь с итогом.'
    write_audit_line "emit_modify event=$event reason=allowlisted_skill_tool_progress tool_calls_present=$tool_calls_present"
    emit_modified_payload_preserve_tool_calls "$fallback_text"
    exit 0
fi

if [[ "$tool_calls_have_disallowed" == true || "$has_delivery_internal_telemetry" == true || "$has_after_llm_tool_intent" == true || "$has_user_visible_internal_planning" == true || "$has_skill_path_false_negative" == true ]]; then
    fallback_text='В Telegram-safe режиме я не запускаю инструменты и не показываю внутренние логи. Для browser/search/process workflow продолжим в web UI или операторской сессии.'
    if [[ "$has_skill_path_false_negative" == true ]]; then
        fallback_text='Я не использую sandbox filesystem как доказательство отсутствия навыков. Для работы с навыками продолжу через runtime skill-tools без проверки директорий.'
    fi
    write_audit_line "emit_modify event=$event reason=fallback tool_calls_present=$tool_calls_present disallowed_tools=$tool_calls_have_disallowed delivery_telemetry=$has_delivery_internal_telemetry after_llm_intent=$has_after_llm_tool_intent planning=$has_user_visible_internal_planning false_negative=$has_skill_path_false_negative"
    if [[ "$event" == "AfterLLMCall" ]]; then
        emit_modified_payload "$fallback_text" true
    else
        emit_modified_payload "$fallback_text" false
    fi
    exit 0
fi

exit 0
