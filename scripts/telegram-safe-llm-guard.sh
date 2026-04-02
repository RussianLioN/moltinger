#!/usr/bin/env bash
set -euo pipefail

payload="$(cat)"
if [[ -z "${payload:-}" ]]; then
    exit 0
fi

AUDIT_FILE="${MOLTIS_TELEGRAM_SAFE_LLM_GUARD_AUDIT_FILE:-}"
INTENT_DIR="${MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR:-/tmp/moltis-telegram-safe-llm-guard-intent}"
INTENT_TTL_SEC="${MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_TTL_SEC:-900}"
SUPPRESS_TTL_SEC="${MOLTIS_TELEGRAM_SAFE_LLM_GUARD_SUPPRESS_TTL_SEC:-300}"
DIRECT_FASTPATH_ENABLED="${MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH:-true}"
DIRECT_SEND_SCRIPT="${MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT:-/server/scripts/telegram-bot-send.sh}"

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

flatten_text_for_match() {
    local text="${1:-}"

    printf '%s' "$text" \
        | tr '\r\n' '  ' \
        | sed 's/[[:space:]][[:space:]]*/ /g'
}

extract_last_message_content_by_role() {
    local messages_json="${1:-}"
    local target_role="${2:-user}"

    [[ -n "$messages_json" ]] || return 1

    printf '%s' "$messages_json" | awk -v target_role="$target_role" '
        function extract_string_value(obj, key,    needle, state, value, escape, n, i, j, c) {
            needle = "\"" key "\""
            state = "seek"
            value = ""
            escape = 0
            n = length(obj)

            for (i = 1; i <= n; i++) {
                c = substr(obj, i, 1)
                if (state == "seek") {
                    if (substr(obj, i, length(needle)) != needle) {
                        continue
                    }
                    j = i + length(needle)
                    while (j <= n && substr(obj, j, 1) ~ /[ \t\r\n]/) {
                        j++
                    }
                    if (substr(obj, j, 1) != ":") {
                        continue
                    }
                    j++
                    while (j <= n && substr(obj, j, 1) ~ /[ \t\r\n]/) {
                        j++
                    }
                    if (substr(obj, j, 1) != "\"") {
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
                    return value
                }

                value = value c
            }

            return ""
        }

        function flush_object(obj,    role, content) {
            role = extract_string_value(obj, "role")
            if (role != target_role) {
                return
            }
            content = extract_string_value(obj, "content")
            if (content != "") {
                last_content = content
            }
        }

        BEGIN {
            RS = ""
            ORS = ""
            in_string = 0
            escape = 0
            depth = 0
            capturing = 0
            obj = ""
            last_content = ""
        }

        {
            text = $0
            n = length(text)
            for (i = 1; i <= n; i++) {
                c = substr(text, i, 1)

                if (!capturing) {
                    if (c == "{") {
                        capturing = 1
                        obj = "{"
                        depth = 1
                        in_string = 0
                        escape = 0
                    }
                    continue
                }

                if (i > 1 || obj != "{") {
                    obj = obj c
                }

                if (escape) {
                    escape = 0
                    continue
                }

                if (c == "\\") {
                    if (in_string) {
                        escape = 1
                    }
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
                        flush_object(obj)
                        capturing = 0
                        obj = ""
                    }
                }
            }
        }

        END {
            if (last_content == "") {
                exit 1
            }
            print last_content
        }
    '
}

sanitize_intent_key() {
    local raw_key="${1:-}"

    [[ -n "$raw_key" ]] || return 1

    printf '%s' "$raw_key" \
        | tr -cs 'A-Za-z0-9._-' '_' \
        | sed -E 's/^_+//; s/_+$//' \
        | cut -c1-120
}

lane_file_path() {
    local raw_key="${1:-}"
    local safe_key=""

    safe_key="$(sanitize_intent_key "$raw_key" || true)"
    [[ -n "$safe_key" ]] || return 1

    printf '%s/%s.lane' "$INTENT_DIR" "$safe_key"
}

intent_file_path() {
    local raw_key="${1:-}"
    local safe_key=""

    safe_key="$(sanitize_intent_key "$raw_key" || true)"
    [[ -n "$safe_key" ]] || return 1

    printf '%s/%s.intent' "$INTENT_DIR" "$safe_key"
}

suppress_file_path() {
    local raw_key="${1:-}"
    local safe_key=""

    safe_key="$(sanitize_intent_key "$raw_key" || true)"
    [[ -n "$safe_key" ]] || return 1

    printf '%s/%s.suppress' "$INTENT_DIR" "$safe_key"
}

persist_safe_lane_marker() {
    local raw_key="${1:-}"
    local lane_file=""

    [[ -n "$raw_key" ]] || return 0

    lane_file="$(lane_file_path "$raw_key" || true)"
    [[ -n "$lane_file" ]] || return 0

    mkdir -p "$INTENT_DIR" 2>/dev/null || true
    printf '%s\n' "$(date +%s)" >"$lane_file" 2>/dev/null || true
}

safe_lane_marker_is_fresh() {
    local raw_key="${1:-}"
    local lane_file=""
    local stored_epoch=""
    local now_epoch=0
    local age_sec=0

    [[ -n "$raw_key" ]] || return 1

    lane_file="$(lane_file_path "$raw_key" || true)"
    [[ -n "$lane_file" && -f "$lane_file" ]] || return 1

    IFS= read -r stored_epoch <"$lane_file" || return 1
    [[ "$stored_epoch" =~ ^[0-9]+$ ]] || return 1

    now_epoch="$(date +%s)"
    age_sec=$((now_epoch - stored_epoch))
    if (( age_sec < 0 || age_sec > INTENT_TTL_SEC )); then
        rm -f "$lane_file" 2>/dev/null || true
        return 1
    fi

    return 0
}

clear_safe_lane_marker() {
    local raw_key="${1:-}"
    local lane_file=""

    [[ -n "$raw_key" ]] || return 0

    lane_file="$(lane_file_path "$raw_key" || true)"
    [[ -n "$lane_file" ]] || return 0

    rm -f "$lane_file" 2>/dev/null || true
}

persist_delivery_suppression() {
    local raw_key="${1:-}"
    local token="${2:-}"
    local suppress_file=""

    [[ -n "$raw_key" && -n "$token" ]] || return 0

    suppress_file="$(suppress_file_path "$raw_key" || true)"
    [[ -n "$suppress_file" ]] || return 0

    mkdir -p "$INTENT_DIR" 2>/dev/null || true
    printf '%s\t%s\n' "$(date +%s)" "$token" >"$suppress_file" 2>/dev/null || true
    write_audit_line "suppress_set key=$(basename "$suppress_file") token=$token"
}

load_delivery_suppression() {
    local raw_key="${1:-}"
    local suppress_file=""
    local stored_epoch=""
    local stored_token=""
    local now_epoch=0
    local age_sec=0

    [[ -n "$raw_key" ]] || return 1

    suppress_file="$(suppress_file_path "$raw_key" || true)"
    [[ -n "$suppress_file" && -f "$suppress_file" ]] || return 1

    IFS=$'\t' read -r stored_epoch stored_token <"$suppress_file" || return 1
    [[ "$stored_epoch" =~ ^[0-9]+$ && -n "$stored_token" ]] || return 1

    now_epoch="$(date +%s)"
    age_sec=$((now_epoch - stored_epoch))
    if (( age_sec < 0 || age_sec > SUPPRESS_TTL_SEC )); then
        rm -f "$suppress_file" 2>/dev/null || true
        return 1
    fi

    printf '%s' "$stored_token"
}

clear_delivery_suppression() {
    local raw_key="${1:-}"
    local suppress_file=""

    [[ -n "$raw_key" ]] || return 0

    suppress_file="$(suppress_file_path "$raw_key" || true)"
    [[ -n "$suppress_file" ]] || return 0

    rm -f "$suppress_file" 2>/dev/null || true
}

persist_turn_intent() {
    local raw_key="${1:-}"
    local intent_name="${2:-}"
    local intent_file=""

    [[ -n "$raw_key" && -n "$intent_name" ]] || return 0

    intent_file="$(intent_file_path "$raw_key" || true)"
    [[ -n "$intent_file" ]] || return 0

    mkdir -p "$INTENT_DIR" 2>/dev/null || true
    printf '%s\t%s\n' "$(date +%s)" "$intent_name" >"$intent_file" 2>/dev/null || true
    write_audit_line "intent_set key=$(basename "$intent_file") intent=$intent_name"
}

load_turn_intent() {
    local raw_key="${1:-}"
    local intent_file=""
    local stored_epoch=""
    local stored_intent=""
    local now_epoch=0
    local age_sec=0

    [[ -n "$raw_key" ]] || return 1

    intent_file="$(intent_file_path "$raw_key" || true)"
    [[ -n "$intent_file" && -f "$intent_file" ]] || return 1

    IFS=$'\t' read -r stored_epoch stored_intent <"$intent_file" || return 1
    [[ "$stored_epoch" =~ ^[0-9]+$ && -n "$stored_intent" ]] || return 1

    now_epoch="$(date +%s)"
    age_sec=$((now_epoch - stored_epoch))
    if (( age_sec < 0 || age_sec > INTENT_TTL_SEC )); then
        rm -f "$intent_file" 2>/dev/null || true
        return 1
    fi

    printf '%s' "$stored_intent"
}

clear_turn_intent() {
    local raw_key="${1:-}"
    local intent_file=""

    [[ -n "$raw_key" ]] || return 0

    intent_file="$(intent_file_path "$raw_key" || true)"
    [[ -n "$intent_file" ]] || return 0

    rm -f "$intent_file" 2>/dev/null || true
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

format_skill_names_inline() {
    local csv="$1"
    local inline_text=""
    local skill_name=""

    [[ -n "$csv" ]] || return 1

    local old_ifs="$IFS"
    IFS=','
    read -r -a skill_items <<<"$csv"
    IFS="$old_ifs"

    for skill_name in "${skill_items[@]}"; do
        [[ -n "$skill_name" ]] || continue
        inline_text="${inline_text}${inline_text:+, }${skill_name}"
    done

    [[ -n "$inline_text" ]] || return 1
    printf '%s' "$inline_text"
}

count_skill_names_csv() {
    local csv="$1"
    local count=0
    local skill_name=""

    [[ -n "$csv" ]] || {
        printf '0'
        return 0
    }

    local old_ifs="$IFS"
    IFS=','
    read -r -a skill_items <<<"$csv"
    IFS="$old_ifs"

    for skill_name in "${skill_items[@]}"; do
        [[ -n "$skill_name" ]] || continue
        count=$((count + 1))
    done

    printf '%s' "$count"
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
- Если пользователь спрашивает именно про template/шаблон навыка, покажи канонический минимальный scaffold из project docs, а не ищи его через workspace, skills directory или existing skills.
EOF
}

build_text_only_hard_override_message() {
    local label="$1"
    local reply_text="$2"

    cat <<EOF
${label}:
- Ignore the prior conversation content for this turn.
- This turn is text-only and must not call any tools.
- Do not mention sandbox/filesystem limitations, repeated-turn counters, or ask a follow-up question before the list.
- Return exactly this single Russian sentence and nothing else: "${reply_text}"
EOF
}

build_skill_visibility_hard_override_message() {
    local visibility_reply_text="$1"
    build_text_only_hard_override_message "Telegram-safe skill-visibility hard override" "$visibility_reply_text"
}

build_sparse_skill_create_guard_message() {
    cat <<'EOF'
Telegram-safe sparse create-skill override:
- Игнорируй старые незавершённые вопросы про описание, тело, template и прошлые pending create-turns; ориентируйся только на последний явный запрос пользователя создать skill.
- Если пользователь уже дал имя/slug навыка, считай это достаточным для первой попытки.
- Первый содержательный ход обязан быть create_skill.
- Не задавай уточняющих вопросов до первой попытки create_skill.
- Не ищи template, не смотри existing skills, не проверяй filesystem/directories и не используй exec/browser/web-search.
- Для create_skill сам сгенерируй description и content.
- Content должен быть валидным минимальным SKILL.md со структурой:
  ---
  name: <skill-name>
  description: Базовый навык <skill-name>. Использовать когда пользователь явно просит сценарий <skill-name>.
  ---
  # <skill-name>

  ## Активация
  Когда пользователь явно просит сценарий <skill-name> или доработку этого навыка, используй его.

  ## Workflow
  1. Уточни цель, если для точного выполнения не хватает контекста.
  2. Выполни основной сценарий навыка.
  3. Верни краткий итог и предложи, как доработать навык дальше.

  ## Templates
  - TODO: добавить конкретные шаблоны под сценарий навыка.
- Если create_skill вернул validation/frontmatter error, сразу повтори попытку с этим каноническим scaffold.
- Если create_skill сообщил, что имя уже занято, кратко скажи об этом и предлагай update/overwrite только по явной команде пользователя.
- После успешного create_skill ответь коротко, что создан базовый шаблон навыка и его можно доработать следующим сообщением.
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

build_disallowed_tool_runtime_note() {
    local tool_name="${1:-unknown-tool}"

    cat <<EOF
Telegram-safe runtime note:
- Tool \`${tool_name}\` blocked for the user-facing Telegram lane.
- Allow only dedicated skill tools and allowlisted Tavily research MCP tools here.
- Do not call browser, arbitrary MCP/web-search, process, cron, or filesystem probes here.
- Continue text-only, or use only safe tools: create_skill, update_skill, delete_skill, session_state, send_message, send_image, mcp__tavily__tavily_search, mcp__tavily__tavily_extract, mcp__tavily__tavily_map, mcp__tavily__tavily_crawl, mcp__tavily__tavily_research.
EOF
}

build_skill_visibility_reply_text() {
    local csv="${1:-}"
    local inline_names=""
    local count="0"

    inline_names="$(format_skill_names_inline "$csv" || true)"
    count="$(count_skill_names_csv "$csv")"

    if [[ -z "$inline_names" || "$count" == "0" ]]; then
        printf '%s' 'Сейчас hook не подтвердил имена навыков. Это не означает, что навыков нет, но без live runtime snapshot я не буду выдумывать список.'
        return 0
    fi

    printf 'Навыки (%s): %s.' "$count" "$inline_names"
}

build_skill_create_reply_text() {
    local skill_name="${1:-}"
    local create_state="${2:-}"

    [[ -n "$skill_name" ]] || return 1

    case "$create_state" in
        exists)
            printf 'Навык `%s` уже существует. Могу следующим сообщением обновить его или показать текущий шаблон.' "$skill_name"
            ;;
        created)
            printf 'Создал базовый шаблон навыка `%s`. Могу следующим сообщением доработать описание, workflow и templates.' "$skill_name"
            ;;
        failed)
            printf 'Не смог создать базовый шаблон навыка `%s` в runtime skills. Могу показать канонический шаблон SKILL.md текстом и подготовить содержимое для ручного создания.' "$skill_name"
            ;;
        *)
            return 1
            ;;
    esac
}

build_skill_create_hard_override_message() {
    local reply_text="$1"
    build_text_only_hard_override_message "Telegram-safe skill-create hard override" "$reply_text"
}

build_skill_apply_reply_text() {
    local skill_name="${1:-}"

    if [[ -n "$skill_name" ]]; then
        printf 'В Telegram-safe режиме я не запускаю навык `%s` через инструменты. Могу кратко объяснить, что делает этот навык, или продолжить в web UI/операторской сессии.' "$skill_name"
        return 0
    fi

    printf '%s' 'В Telegram-safe режиме я не запускаю навыки через инструменты. Могу кратко объяснить, что делает нужный навык, или продолжить в web UI/операторской сессии.'
}

build_skill_apply_hard_override_message() {
    local reply_text="$1"
    build_text_only_hard_override_message "Telegram-safe skill-apply hard override" "$reply_text"
}

build_skill_template_hard_override_message() {
    local reply_text="$1"
    build_text_only_hard_override_message "Telegram-safe skill-template hard override" "$reply_text"
}

build_minimal_skill_scaffold() {
    local skill_name="$1"

    cat <<EOF
---
name: ${skill_name}
description: Базовый навык ${skill_name}. Использовать, когда пользователь явно просит сценарий ${skill_name}.
---
# ${skill_name}

## Активация
Когда пользователь явно просит сценарий ${skill_name} или доработку этого навыка, используй его.

## Workflow
1. Уточни цель, если для точного выполнения не хватает контекста.
2. Выполни основной сценарий навыка.
3. Верни краткий итог и предложи, как доработать навык дальше.

## Templates
- TODO: добавить конкретные шаблоны под сценарий навыка.
EOF
}

build_skill_template_reply_text() {
    cat <<'EOF'
Канонический минимальный шаблон навыка:

```md
---
name: <skill-name>
description: Базовый навык <skill-name>. Использовать, когда пользователь явно просит сценарий <skill-name>.
---
# <skill-name>

## Активация
Когда пользователь явно просит сценарий <skill-name> или доработку этого навыка, используй его.

## Workflow
1. Уточни цель, если для точного выполнения не хватает контекста.
2. Выполни основной сценарий навыка.
3. Верни краткий итог и предложи, как доработать навык дальше.

## Templates
- TODO: добавить конкретные шаблоны под сценарий навыка.
```

Если хочешь, следующим сообщением я создам такой базовый навык по имени/slug.
EOF
}

flag_enabled() {
    case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
        1|true|yes|on)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

extract_runtime_field_from_text() {
    local source_text="${1:-}"
    local field_name="${2:-}"

    [[ -n "$source_text" && -n "$field_name" ]] || return 1

    printf '%s' "$source_text" \
        | grep -oE "${field_name}=[^ |]+" \
        | head -n 1 \
        | sed -E "s/^${field_name}=//"
}

extract_requested_skill_name() {
    local source_text="${1:-}"
    local normalized_text=""

    [[ -n "$source_text" ]] || return 1

    normalized_text="$(
        printf '%s' "$source_text" \
            | tr '\r\n' '  ' \
            | sed 's/[[:space:]][[:space:]]*/ /g'
    )"

    if [[ "$normalized_text" =~ [Сс]озда(й|ть|дим)[[:space:]]+(нов(ый|ую)[[:space:]]+)?(навык|skill)[[:space:]]+([A-Za-z0-9][A-Za-z0-9._-]*) ]]; then
        printf '%s' "${BASH_REMATCH[5]}"
        return 0
    fi

    if [[ "$normalized_text" =~ [Cc]reate[[:space:]]+(new[[:space:]]+)?skill[[:space:]]+([A-Za-z0-9][A-Za-z0-9._-]*) ]]; then
        printf '%s' "${BASH_REMATCH[2]}"
        return 0
    fi

    if [[ "$normalized_text" =~ [Cc]reate[[:space:]]+([A-Za-z0-9][A-Za-z0-9._-]*)[[:space:]]+skill ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

create_runtime_skill_scaffold() {
    local skill_name="${1:-}"
    local runtime_root="${MOLTIS_RUNTIME_SKILLS_ROOT:-/home/moltis/.moltis/skills}"
    local skill_dir=""

    [[ -n "$skill_name" ]] || return 1
    [[ "$skill_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || return 1

    skill_dir="${runtime_root}/${skill_name}"
    mkdir -p "$skill_dir" || return 1
    build_minimal_skill_scaffold "$skill_name" > "${skill_dir}/SKILL.md" || return 1

    [[ -f "${skill_dir}/SKILL.md" ]] || return 1
    grep -Fq "name: ${skill_name}" "${skill_dir}/SKILL.md"
}

runtime_skill_dir_path() {
    local skill_name="${1:-}"
    local runtime_root="${MOLTIS_RUNTIME_SKILLS_ROOT:-/home/moltis/.moltis/skills}"

    [[ -n "$skill_name" ]] || return 1
    printf '%s/%s' "$runtime_root" "$skill_name"
}

send_telegram_direct_message() {
    local chat_id="${1:-}"
    local text="${2:-}"
    local reply_to="${3:-}"

    [[ -n "$chat_id" && -n "$text" ]] || return 1
    [[ -x "$DIRECT_SEND_SCRIPT" ]] || return 1

    if [[ -n "$reply_to" ]]; then
        "$DIRECT_SEND_SCRIPT" --chat-id "$chat_id" --text "$text" --reply-to "$reply_to" >/dev/null 2>&1
        return $?
    fi

    "$DIRECT_SEND_SCRIPT" --chat-id "$chat_id" --text "$text" >/dev/null 2>&1
}

response_has_delivery_internal_trace() {
    local text="${1:-}"
    local flat=""

    flat="$(
        printf '%s' "$text" \
            | tr '\r\n' ' ' \
            | sed 's/[[:space:]][[:space:]]*/ /g'
    )"

    if printf '%s' "$flat" | grep -Eiq "activity log([[:space:]]|$).*(•|running:|searching memory|fetching (github\\.com|https?://)|mcp tool error|validation errors for call\\[|tool-progress|mcp__|nodes_list|sessions_list|missing 'action' parameter|list failed:)"; then
        return 0
    fi
    if printf '%s' "$flat" | grep -Eiq "running:|searching memory|nodes_list|sessions_list|missing 'action' parameter|list failed:|mcp tool error|validation errors for call\\[|fetching (github\\.com|https?://)|tool-progress"; then
        return 0
    fi
    if printf '%s' "$flat" | grep -Eiq '(^|[[:space:]])(•|🔧|🗺️|💻|🔗|🌐|🧠|❌)[[:space:]]*mcp__'; then
        return 0
    fi

    return 1
}

delivery_internal_suffix_is_appended() {
    local text="${1:-}"
    local flat=""

    flat="$(
        printf '%s' "$text" \
            | tr '\r\n' ' ' \
            | sed 's/[[:space:]][[:space:]]*/ /g'
    )"

    if printf '%s' "$flat" | grep -Eiq '^.+[^[:space:]][[:space:]]+Activity log[[:space:]]+(•|running:|searching memory|fetching (github\.com|https?://)|mcp tool error|validation errors for call\[|tool-progress|mcp__|nodes_list|sessions_list|missing '\''action'\'' parameter|list failed:)'; then
        return 0
    fi
    if printf '%s' "$flat" | grep -Eiq '^.+[^[:space:]][[:space:]]+•[[:space:]]+mcp__[A-Za-z0-9_:.:-]+'; then
        return 0
    fi

    return 1
}

strip_delivery_internal_suffix() {
    local text="${1:-}"
    local cleaned="$text"

    cleaned="$(
        printf '%s' "$cleaned" \
            | tr '\r\n' ' ' \
            | sed 's/[[:space:]][[:space:]]*/ /g'
    )"

    if ! delivery_internal_suffix_is_appended "$cleaned"; then
        printf '%s' "$text"
        return 0
    fi

    if [[ "$cleaned" == *" Activity log "* ]]; then
        cleaned="${cleaned%% Activity log*}"
    elif [[ "$cleaned" == *"Activity log "* ]]; then
        cleaned="${cleaned%%Activity log*}"
    fi
    if [[ "$cleaned" == *" • mcp__"* ]]; then
        cleaned="${cleaned%% • mcp__*}"
    elif [[ "$cleaned" == *"• mcp__"* ]]; then
        cleaned="${cleaned%%• mcp__*}"
    fi

    cleaned="$(
        printf '%s' "$cleaned" \
            | sed 's/[[:space:]]*$//'
    )"

    printf '%s' "$cleaned"
}

reply_mentions_any_skill_from_csv() {
    local reply_text="${1:-}"
    local csv="${2:-}"
    local normalized_reply=""
    local skill_name=""

    normalized_reply="$(printf '%s' "$reply_text" | tr '[:upper:]' '[:lower:]')"
    [[ -n "$normalized_reply" && -n "$csv" ]] || return 1

    local old_ifs="$IFS"
    IFS=','
    read -r -a skill_items <<<"$csv"
    IFS="$old_ifs"

    for skill_name in "${skill_items[@]}"; do
        [[ -n "$skill_name" ]] || continue
        if [[ "$normalized_reply" == *"$(printf '%s' "$skill_name" | tr '[:upper:]' '[:lower:]')"* ]]; then
            return 0
        fi
    done

    return 1
}

build_exec_heredoc_command() {
    local text="$1"

    printf "cat <<'__MOLTIS_TELEGRAM_SAFE__'\n%s\n__MOLTIS_TELEGRAM_SAFE__" "$text"
}

emit_before_tool_modified_payload() {
    local tool_name="$1"
    local arguments_json="$2"
    local data_object_json modified_data_json
    local tool_field_fragment=""
    local tool_name_field_fragment=""

    if [[ -n "$tool_name" ]]; then
        tool_field_fragment="$(json_string_field tool "$tool_name")"
        tool_name_field_fragment="$(json_string_field tool_name "$tool_name")"
    fi

    data_object_json="$(extract_json_object data || true)"
    if [[ -n "$data_object_json" ]]; then
        modified_data_json="$(filter_top_level_object_fields "$data_object_json" tool tool_name arguments)"
        if [[ -n "$tool_field_fragment" ]]; then
            modified_data_json="$(append_field_to_object "$modified_data_json" "$tool_field_fragment")"
        fi
        if [[ -n "$tool_name_field_fragment" ]]; then
            modified_data_json="$(append_field_to_object "$modified_data_json" "$tool_name_field_fragment")"
        fi
        modified_data_json="$(append_field_to_object "$modified_data_json" "\"arguments\":$arguments_json")"
        printf '{"action":"modify","data":%s}\n' "$modified_data_json"
        return
    fi

    modified_data_json="$(filter_top_level_object_fields "$payload" event tool tool_name arguments)"
    if [[ -n "$tool_field_fragment" ]]; then
        modified_data_json="$(append_field_to_object "$modified_data_json" "$tool_field_fragment")"
    fi
    if [[ -n "$tool_name_field_fragment" ]]; then
        modified_data_json="$(append_field_to_object "$modified_data_json" "$tool_name_field_fragment")"
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
    if tool_name_is_skill_allowlisted "$tool_name" || tool_name_is_tavily_allowlisted "$tool_name"; then
        return 0
    fi
    return 1
}

tool_name_is_skill_allowlisted() {
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

tool_name_is_tavily_allowlisted() {
    local tool_name="${1:-}"
    case "$tool_name" in
        mcp__tavily__tavily_search|mcp__tavily__tavily_extract|mcp__tavily__tavily_map|mcp__tavily__tavily_crawl|mcp__tavily__tavily_research)
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

tool_calls_only_skill_allowlisted() {
    local tool_calls_json="${1:-}"
    local saw_name=false
    local tool_name=""

    while IFS= read -r tool_name; do
        [[ -n "$tool_name" ]] || continue
        saw_name=true
        if ! tool_name_is_skill_allowlisted "$tool_name"; then
            return 1
        fi
    done < <(extract_tool_call_names "$tool_calls_json" || true)

    $saw_name
}

tool_calls_include_tavily_allowlisted() {
    local tool_calls_json="${1:-}"
    local tool_name=""

    while IFS= read -r tool_name; do
        [[ -n "$tool_name" ]] || continue
        if tool_name_is_tavily_allowlisted "$tool_name"; then
            return 0
        fi
    done < <(extract_tool_call_names "$tool_calls_json" || true)

    return 1
}

tool_calls_only_tavily_allowlisted() {
    local tool_calls_json="${1:-}"
    local saw_name=false
    local tool_name=""

    while IFS= read -r tool_name; do
        [[ -n "$tool_name" ]] || continue
        saw_name=true
        if ! tool_name_is_tavily_allowlisted "$tool_name"; then
            return 1
        fi
    done < <(extract_tool_call_names "$tool_calls_json" || true)

    $saw_name
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
user_message="$(extract_first_string user_message || true)"
account_id="$(extract_first_string account_id || true)"
turn_session_key="$(extract_first_string session_key || true)"
if [[ -z "$turn_session_key" ]]; then
    turn_session_key="$(extract_first_string session_id || true)"
fi
tool_name="$(extract_first_string tool || true)"
if [[ -z "$tool_name" ]]; then
    tool_name="$(extract_first_string tool_name || true)"
fi
command_arg="$(extract_first_string command || true)"
messages_json="$(extract_json_array messages || true)"
latest_user_message="$(extract_last_message_content_by_role "${messages_json:-}" user || true)"
latest_assistant_message="$(extract_last_message_content_by_role "${messages_json:-}" assistant || true)"
latest_system_message="$(extract_last_message_content_by_role "${messages_json:-}" system || true)"
tool_calls_json="$(extract_json_array tool_calls || true)"
response_text_flat="$(flatten_text_for_match "${response_text:-}")"
user_message_flat="$(flatten_text_for_match "${user_message:-}")"
latest_user_message_flat="$(flatten_text_for_match "${latest_user_message:-}")"
latest_assistant_message_flat="$(flatten_text_for_match "${latest_assistant_message:-}")"
latest_system_message_flat="$(flatten_text_for_match "${latest_system_message:-}")"
intent_text_flat="${latest_user_message_flat:-$user_message_flat}"
status_query_text_flat="${intent_text_flat:-$user_message_flat}"
persisted_turn_intent="$(load_turn_intent "${turn_session_key:-}" || true)"
persisted_delivery_suppression="$(load_delivery_suppression "${turn_session_key:-}" || true)"
channel_account="$(extract_runtime_field_from_text "${latest_system_message:-}" "channel_account" || true)"
has_current_user_turn=false
if [[ -n "$intent_text_flat" ]]; then
    has_current_user_turn=true
fi

write_audit_line "invoke event=${event:-<none>} provider=${provider:-<none>} model=${model:-<none>} payload_len=${#payload_flat} text_len=${#response_text_flat}"

is_telegram_safe_lane=false
case "${model:-}" in
    custom-zai-telegram-safe::*|openai-codex::*)
        is_telegram_safe_lane=true
        ;;
esac
if [[ "${provider:-}" == "custom-zai-telegram-safe" || "${provider:-}" == "zai-telegram-safe" || "${provider:-}" == "openai-codex" ]]; then
    is_telegram_safe_lane=true
fi
if [[ "${account_id:-}" == "moltis-bot" || "${channel_account:-}" == "moltis-bot" ]]; then
    is_telegram_safe_lane=true
fi
if [[ "$is_telegram_safe_lane" != true ]] && safe_lane_marker_is_fresh "${turn_session_key:-}"; then
    is_telegram_safe_lane=true
    write_audit_line "safe_lane_restored source=marker session=${turn_session_key:-missing}"
fi
if [[ "$is_telegram_safe_lane" == true ]]; then
    persist_safe_lane_marker "${turn_session_key:-}"
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
if [[ "$event" == "AfterLLMCall" || "$event" == "MessageSending" ]] && \
   response_has_delivery_internal_trace "${response_text:-$payload_flat}"; then
    has_delivery_internal_telemetry=true
fi

has_appended_delivery_internal_suffix=false
if [[ "$event" == "MessageSending" ]] && delivery_internal_suffix_is_appended "${response_text:-}"; then
    has_appended_delivery_internal_suffix=true
fi

has_after_llm_tool_intent=false
if [[ "$event" == "AfterLLMCall" ]] && \
   printf '%s' "${response_text_flat:-$payload_flat}" | grep -Eiq "no remote nodes available|let me (check|search|inspect|look|study|read|try|get)|i( ?|')ll (check|search|inspect|look|study|read|try|get)|сейчас (проверю|поищу|изучу|посмотрю)|проверю через|посмотрю через|открою (документац|docs|сайт)|перейду на |наш[её]л.{0,120}(официальн.{0,60})?(документац|docs|documentation|manual|guide|инструкц)|наш[её]л.{0,120}(репозитор|github)|((отлично|супер|окей|ладно)[!,.[:space:]]{0,12})?давай(те)? (изучу|разберу|посмотрю|проверю|почитаю|получу|найду|открою|проанализирую|сделаю)|хорошо,? (изучу|проверю|посмотрю|почитаю).{0,120}(документац|docs|documentation|manual|guide|инструкц)|[Хх]орошо[^[:cntrl:]]{0,80}[Дд]авай(те)?[[:space:]]+изучу|[Оо]тлично[^[:cntrl:]]{0,80}[Дд]авай(те)?[[:space:]]+изучу|[Дд]авай(те)?[[:space:]]+изучу.{0,160}(официальн.{0,60})?(документац|docs|documentation|manual|guide|инструкц)|начну с (поиска|анализа|изучения|просмотра)|[Нн]ачина(ю|ем)[:[:space:]]|получ(у|им|ить).{0,120}(документац|docs|documentation|manual|guide|инструкц)|изучу.{0,80}(полностью|целиком|всю|весь|дальше)|попробую.{0,120}(найти|посмотреть|прочитать|изучить).{0,120}(workspace|документац|файл|темплейт|template)|(поищу|ищу).{0,80}(темплейт|template|шаблон)|([Нн]айду|найду).{0,80}(темплейт|template|шаблон)|([Сс]мотрю|[Пп]роверяю).{0,80}(директори(ю|и)[[:space:]]+skills|skills[[:space:]]+directory)|mounted workspace|workspace that's mounted|read the skill files|look at the existing skills|find the skills|create_skill tool|documentation search tool"; then
    has_after_llm_tool_intent=true
fi

has_user_visible_internal_planning=false
if [[ "$event" == "AfterLLMCall" || "$event" == "MessageSending" ]] && \
   printf '%s' "${response_text_flat:-$payload_flat}" | grep -Eiq "пользователь просит|the user (is )?asking|у меня есть доступ к|i have access to|мне доступны|сначала найду|для начала найду|((отлично|супер|окей|ладно)[!,.[:space:]]{0,12})?давай(те)? (получу|найду|изучу|посмотрю|открою|проверю|проанализирую|сделаю)|хорошо,? (изучу|проверю|посмотрю|почитаю).{0,120}(документац|docs|documentation|manual|guide|инструкц)|[Хх]орошо[^[:cntrl:]]{0,80}[Дд]авай(те)?[[:space:]]+изучу|[Оо]тлично[^[:cntrl:]]{0,80}[Дд]авай(те)?[[:space:]]+изучу|[Дд]авай(те)?[[:space:]]+изучу.{0,160}(официальн.{0,60})?(документац|docs|documentation|manual|guide|инструкц)|начну с (поиска|анализа|изучения|просмотра)|[Нн]ачина(ю|ем)[:[:space:]]|наш[её]л.{0,120}(репозитор|github|документац|docs|documentation|manual|guide|инструкц)|получ(у|им|ить).{0,120}(документац|docs|documentation|manual|guide|инструкц)|(поищу|ищу).{0,80}(темплейт|template|шаблон)|([Нн]айду|найду).{0,80}(темплейт|template|шаблон)|([Сс]мотрю|[Пп]роверяю).{0,80}(директори(ю|и)[[:space:]]+skills|skills[[:space:]]+directory)|как пример|как реальн(ый|ого) пример|mcp__|mounted workspace|skill files|existing skills"; then
    has_user_visible_internal_planning=true
fi
if [[ "$event" == "AfterLLMCall" || "$event" == "MessageSending" ]] && \
   printf '%s' "${response_text_flat:-$payload_flat}" | grep -Eiq "(у меня есть доступ к|i have access to|мне доступны).{0,160}((^|[^[:alnum:]_])(create_skill|update_skill|delete_skill|browser|exec|process|cron)([^[:alnum:]_]|$)|tavily|mcp__)"; then
    has_user_visible_internal_planning=true
fi

current_turn_status_request=false
if printf '%s' "$status_query_text_flat" | grep -Eiq '(^|[^[:alnum:]_])/?status([^[:alnum:]_]|$)|статус( системы)?'; then
    current_turn_status_request=true
fi

looks_like_observed_status_reply=false
if [[ ( "$event" == "AfterLLMCall" || "$event" == "MessageSending" ) && -z "$status_query_text_flat" ]] && \
   printf '%s' "${response_text_flat:-$payload_flat}" | grep -Eiq '(^|[^[:alnum:]_])/?status([^[:alnum:]_]|$)|статус( системы)?|активность:|канал: telegram|провайдер:|режим: safe-text|модель: (custom-zai-telegram-safe::glm-5|openai-codex::gpt-5\.4)'; then
    looks_like_observed_status_reply=true
fi

looks_like_status=false
if [[ "$current_turn_status_request" == true ]]; then
    looks_like_status=true
elif [[ "$looks_like_observed_status_reply" == true ]]; then
    looks_like_status=true
elif [[ "$persisted_turn_intent" == "status" && -z "$status_query_text_flat" ]]; then
    # Carry the status intent only within the same turn when the runtime omits
    # the current user message in later hook events. Do not let an old /status
    # reply contaminate unrelated follow-up turns such as template/skills/create.
    looks_like_status=true
fi

looks_like_broad_research_request=false
if printf '%s' "$intent_text_flat" | grep -Eiq '((изучи|изучить|исследуй|исследовать|прочитай|прочитать|study|research|analy[sz]e|read).{0,120}(документац|инструкц|курс|официальн|docs|documentation|manual|guide|гайд|сайт|site))|((документац|инструкц|курс|официальн|docs|documentation|manual|guide|гайд|сайт|site).{0,120}(полностью|целиком|всю|весь|глубоко|thoroughly|fully|end[ -]?to[ -]?end))'; then
    looks_like_broad_research_request=true
fi

looks_like_skill_turn=false
if printf '%s' "$intent_text_flat" | grep -Eiq '((созда(й|дим|ть)|добав(ь|им|ить)|обнов(и|им|ить)|измени(ть|м)|удали(ть|м)?).{0,120}(навык|skills?|skill))|((какие|что).{0,80}(навык(и|ов)?|skills?))|((темплейт|template|шаблон).{0,120}(навык|skills?|skill))|((create|update|delete)[ _-]?skill)'; then
    looks_like_skill_turn=true
fi

current_turn_skill_template_request=false
if printf '%s' "$intent_text_flat" | grep -Eiq '(темплейт|template|шаблон)'; then
    if [[ "$looks_like_skill_turn" == true ]] || \
       printf '%s' "$latest_assistant_message_flat" | grep -Eiq '(навык|skills?|skill|темплейт|template|шаблон|create_skill|update_skill|delete_skill)' || \
       printf '%s' "$latest_system_message_flat" | grep -Eiq '<available_skills>|канонический минимальный scaffold'; then
        current_turn_skill_template_request=true
    fi
fi
looks_like_skill_template_request="$current_turn_skill_template_request"
if [[ "$persisted_turn_intent" == "skill_template" && "$has_current_user_turn" != true ]]; then
    looks_like_skill_template_request=true
fi

looks_like_skill_followup_turn=false
if [[ -n "$latest_user_message_flat" ]] && \
   printf '%s' "$latest_assistant_message_flat" | grep -Eiq '(созда(е|ё)м[^[:cntrl:]]{0,160}навык|опиши[^[:cntrl:]]{0,120}навык|описание[^[:cntrl:]]{0,120}навык|мне нужны детали|дай мне инструкц|жду от тебя инструкц|тело[[:space:]]*\(инструкц|разреш[её]нные инструменты|что должен делать этот навык|это обновл[её]нная версия|skill description|skill body|allowed tools|what should (this|the) skill do|waiting for your instructions)'; then
    looks_like_skill_followup_turn=true
fi

if [[ "$looks_like_skill_followup_turn" == true ]]; then
    looks_like_skill_turn=true
fi

current_turn_skill_visibility_request=false
if printf '%s' "$intent_text_flat" | grep -Eiq '((какие|что|что у тебя с|покажи|перечисли|list|show|which|what).{0,80}(навык(и|ов)?|skills?))|((навык(и|ов)?|skills?).{0,80}(какие|что|list|show|which|what))'; then
    if ! printf '%s' "$intent_text_flat" | grep -Eiq '((созда(й|дим|ть)|добав(ь|им|ить)|обнов(и|им|ить)|измени(ть|м)|удали(ть|м)?|create|update|delete|build|make).{0,120}(навык|skills?|skill))|((темплейт|template|шаблон).{0,120}(навык|skills?|skill))'; then
        current_turn_skill_visibility_request=true
    fi
fi
looks_like_skill_visibility_request="$current_turn_skill_visibility_request"
if [[ "$persisted_turn_intent" == "skill_visibility" && "$has_current_user_turn" != true ]]; then
    looks_like_skill_visibility_request=true
fi

current_turn_sparse_skill_create_request=false
if printf '%s' "$intent_text_flat" | grep -Eiq '((созда(й|дим|ть)|добав(ь|им|ить)|сдела(й|ем|ть)|create|build|make).{0,120}(навык|skills?|skill))|((create|build|make)[[:space:]]+[A-Za-z0-9._-]+[[:space:]]+(skill|навык))'; then
    if ! printf '%s' "$intent_text_flat" | grep -Eiq '(SKILL\.md|frontmatter|markdown|описан|тело|body|workflow|templates?|шаблон|template)'; then
        current_turn_sparse_skill_create_request=true
    fi
fi
looks_like_sparse_skill_create_request="$current_turn_sparse_skill_create_request"

current_turn_skill_apply_request=false
if printf '%s' "$intent_text_flat" | grep -Eiq '((примен(и|ить|им)|используй|использовать|запуст(и|ить|им)|активир(уй|овать)|apply|use|run).{0,120}(навык|skills?|skill))|((навык|skills?|skill).{0,120}(примен(и|ить|им)|используй|запуст(и|ить|им)|активир(уй|овать)|apply|use|run))'; then
    current_turn_skill_apply_request=true
    looks_like_skill_turn=true
fi

if [[ "$event" == "BeforeLLMCall" && "$has_current_user_turn" == true && -n "$persisted_delivery_suppression" ]]; then
    write_audit_line "suppress_clear reason=new_user_turn token=$persisted_delivery_suppression"
    clear_delivery_suppression "${turn_session_key:-}"
    persisted_delivery_suppression=""
fi

requested_skill_name="$(extract_requested_skill_name "${latest_user_message:-${user_message:-}}" || true)"
requested_skill_name_re=""
if [[ -n "$requested_skill_name" ]]; then
    requested_skill_name_re="$(printf '%s' "$requested_skill_name" | sed 's/[][(){}.^$?+*|\\/]/\\&/g')"
fi
persisted_skill_create_state=""
persisted_skill_create_name=""
if [[ "$persisted_turn_intent" =~ ^skill_create_([a-z]+):([A-Za-z0-9._-]+)$ ]]; then
    persisted_skill_create_state="${BASH_REMATCH[1]}"
    persisted_skill_create_name="${BASH_REMATCH[2]}"
fi
if [[ -z "$requested_skill_name" && -n "$persisted_skill_create_name" ]]; then
    requested_skill_name="$persisted_skill_create_name"
fi
if [[ "$has_current_user_turn" != true && -n "$persisted_skill_create_state" && -n "$requested_skill_name" && -n "$requested_skill_name_re" ]] && \
   printf '%s' "${intent_text_flat} ${latest_user_message_flat} ${latest_assistant_message_flat} ${response_text_flat} ${payload_flat}" \
      | grep -Eiq "((созда(й|дим|ть)|добав(ь|им|ить)|сдела(й|ем|ть)|create|build|make).{0,120}(навык|skills?|skill))|((темплейт|template|шаблон).{0,120}(навык|skills?|skill))|((create|update|delete)[ _-]?skill)|${requested_skill_name_re}"; then
    looks_like_sparse_skill_create_request=true
fi

has_skill_path_false_negative=false
if [[ "$event" == "AfterLLMCall" || "$event" == "MessageSending" ]] && \
   printf '%s' "${response_text_flat:-$payload_flat}" | grep -Eiq '(/home/moltis/\.moltis/skills|~/.moltis/skills).{0,120}(не существует|отсутствует|doesn.?t exist|not found)|либо были удалены, либо( ещё| еще)? не созданы|[0-9]+[[:space:]]+навык(а|ов)?[^[:cntrl:]]{0,120}в[[:space:]]+конфиге[^[:cntrl:]]{0,160}файлов[^[:cntrl:]]{0,80}(нет|no)|файлов[^[:cntrl:]]{0,80}(нет|no)[^[:cntrl:]]{0,40}sandbox'; then
    has_skill_path_false_negative=true
fi

has_skill_visibility_generic_mismatch=false
if [[ ( "$event" == "AfterLLMCall" || "$event" == "MessageSending" ) && "$tool_calls_present" != true ]] && \
   printf '%s' "${response_text_flat:-$payload_flat}" | grep -Eiq '([0-9]+[[:space:]]+навык(а|ов)?[[:space:]]+в[[:space:]]+конфиге[^[:cntrl:]]{0,160}файлов[^[:cntrl:]]{0,80}(нет|no)[^[:cntrl:]]{0,80}(sandbox|хочешь создать|stop|стоп))|(skills?[^[:cntrl:]]{0,120}(config|sandbox)[^[:cntrl:]]{0,120}(stop))'; then
    has_skill_visibility_generic_mismatch=true
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
    if [[ -z "$response_text_flat" || "$has_delivery_internal_telemetry" == true || "$has_after_llm_tool_intent" == true || "$has_user_visible_internal_planning" == true || "$looks_like_broad_research_request" == true || "$has_skill_path_false_negative" == true || "$has_skill_visibility_generic_mismatch" == true ]]; then
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
    if [[ "$is_telegram_safe_lane" != true && "$looks_like_status" != true && "$looks_like_skill_visibility_request" != true && "$looks_like_skill_template_request" != true && -z "$persisted_skill_create_state" && "$has_delivery_internal_telemetry" != true && "$has_after_llm_tool_intent" != true && "$has_user_visible_internal_planning" != true && "$has_skill_path_false_negative" != true && "$has_skill_visibility_generic_mismatch" != true ]]; then
        exit 0
    fi
elif [[ "$is_telegram_safe_lane" != true ]]; then
    exit 0
fi

canonical_status=$'Статус: Online\nКанал: Telegram (@moltinger_bot)\nМодель: openai-codex::gpt-5.4\nПровайдер: openai-codex\nРежим: safe-text'

if [[ "$event" == "BeforeLLMCall" ]]; then
    telegram_chat_id="$(extract_runtime_field_from_text "${latest_system_message:-}" "channel_chat_id" || true)"
    next_turn_intent=""
    next_turn_skill_create_state=""
    if [[ "$looks_like_status" == true ]]; then
        next_turn_intent="status"
    elif [[ "$looks_like_skill_visibility_request" == true ]]; then
        next_turn_intent="skill_visibility"
    elif [[ "$looks_like_skill_template_request" == true ]]; then
        next_turn_intent="skill_template"
    elif [[ "$looks_like_sparse_skill_create_request" == true && -n "${requested_skill_name:-}" ]]; then
        skill_snapshot_csv="$(discover_runtime_skill_names_csv || true)"
        case ",${skill_snapshot_csv}," in
            *,"${requested_skill_name}",*)
                next_turn_intent="skill_create_exists:${requested_skill_name}"
                next_turn_skill_create_state="exists"
                ;;
            *)
                if [[ "$is_telegram_safe_lane" == true ]]; then
                    if create_runtime_skill_scaffold "$requested_skill_name"; then
                        next_turn_intent="skill_create_created:${requested_skill_name}"
                        next_turn_skill_create_state="created"
                    else
                        next_turn_intent="skill_create_failed:${requested_skill_name}"
                        next_turn_skill_create_state="failed"
                    fi
                else
                    next_turn_intent="skill_create_failed:${requested_skill_name}"
                    next_turn_skill_create_state="failed"
                fi
                ;;
        esac
    fi

    if [[ -n "$next_turn_intent" ]]; then
        persist_turn_intent "${turn_session_key:-}" "$next_turn_intent"
    else
        clear_turn_intent "${turn_session_key:-}"
    fi

    if [[ "$is_telegram_safe_lane" == true ]] && flag_enabled "$DIRECT_FASTPATH_ENABLED" && [[ -n "${telegram_chat_id:-}" ]]; then
        if [[ "$current_turn_status_request" == true ]]; then
            if send_telegram_direct_message "$telegram_chat_id" "$canonical_status"; then
                write_audit_line "direct_fastpath kind=status chat_id=$telegram_chat_id"
                persist_delivery_suppression "${turn_session_key:-}" "status"
                clear_turn_intent "${turn_session_key:-}"
                exit 0
            fi
            write_audit_line "direct_fastpath_failed kind=status chat_id=${telegram_chat_id:-missing}"
        fi
        if [[ "$current_turn_skill_visibility_request" == true ]]; then
            skill_snapshot_csv="$(discover_runtime_skill_names_csv || true)"
            visibility_reply_text="$(build_skill_visibility_reply_text "$skill_snapshot_csv")"
            if send_telegram_direct_message "$telegram_chat_id" "$visibility_reply_text"; then
                write_audit_line "direct_fastpath kind=skill_visibility chat_id=$telegram_chat_id snapshot_count=$(count_skill_names_csv "$skill_snapshot_csv")"
                persist_delivery_suppression "${turn_session_key:-}" "skill_visibility"
                clear_turn_intent "${turn_session_key:-}"
                exit 0
            fi
            write_audit_line "direct_fastpath_failed kind=skill_visibility chat_id=${telegram_chat_id:-missing}"
        fi
        if [[ "$current_turn_skill_template_request" == true ]]; then
            template_reply_text="$(build_skill_template_reply_text)"
            if send_telegram_direct_message "$telegram_chat_id" "$template_reply_text"; then
                write_audit_line "direct_fastpath kind=skill_template chat_id=$telegram_chat_id"
                persist_delivery_suppression "${turn_session_key:-}" "skill_template"
                clear_turn_intent "${turn_session_key:-}"
                exit 0
            fi
            write_audit_line "direct_fastpath_failed kind=skill_template chat_id=${telegram_chat_id:-missing}"
        fi
        if [[ "$current_turn_sparse_skill_create_request" == true && -n "${requested_skill_name:-}" && -n "${next_turn_skill_create_state:-}" ]]; then
            create_reply_text="$(build_skill_create_reply_text "$requested_skill_name" "$next_turn_skill_create_state" || true)"
            if [[ -n "$create_reply_text" ]] && send_telegram_direct_message "$telegram_chat_id" "$create_reply_text"; then
                write_audit_line "direct_fastpath kind=skill_create chat_id=$telegram_chat_id skill=$requested_skill_name state=$next_turn_skill_create_state"
                persist_delivery_suppression "${turn_session_key:-}" "skill_create:${next_turn_skill_create_state}:${requested_skill_name}"
                clear_turn_intent "${turn_session_key:-}"
                exit 0
            fi
            write_audit_line "direct_fastpath_failed kind=skill_create chat_id=${telegram_chat_id:-missing} skill=${requested_skill_name:-missing} state=${next_turn_skill_create_state:-missing}"
        fi
        if [[ "$current_turn_skill_apply_request" == true ]]; then
            apply_reply_text="$(build_skill_apply_reply_text "${requested_skill_name:-}" || true)"
            if [[ -n "$apply_reply_text" ]] && send_telegram_direct_message "$telegram_chat_id" "$apply_reply_text"; then
                write_audit_line "direct_fastpath kind=skill_apply chat_id=$telegram_chat_id skill=${requested_skill_name:-missing}"
                persist_delivery_suppression "${turn_session_key:-}" "skill_apply:${requested_skill_name:-generic}"
                clear_turn_intent "${turn_session_key:-}"
                exit 0
            fi
            write_audit_line "direct_fastpath_failed kind=skill_apply chat_id=${telegram_chat_id:-missing} skill=${requested_skill_name:-missing}"
        fi
    fi

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
        if [[ "$looks_like_skill_visibility_request" == true ]]; then
            skill_snapshot_csv="$(discover_runtime_skill_names_csv || true)"
            visibility_reply_text="$(build_skill_visibility_reply_text "$skill_snapshot_csv")"
            visibility_guard="$(build_skill_visibility_hard_override_message "$visibility_reply_text")"
            visibility_user=$'Верни в ответ ровно указанную в системном сообщении фразу. Не добавляй ничего.'
            messages_json="[$(build_message_json system "$visibility_guard"),$(build_message_json user "$visibility_user")]"
            write_audit_line "before_modify reason=skill_visibility_hard_override tool_count=0 snapshot_count=$(count_skill_names_csv "$skill_snapshot_csv")"
            emit_before_llm_modified_payload "$messages_json" 0
            exit 0
        fi
        if [[ "$looks_like_skill_template_request" == true ]]; then
            template_reply_text="$(build_skill_template_reply_text)"
            template_guard="$(build_skill_template_hard_override_message "$template_reply_text")"
            template_user=$'Верни в ответ ровно указанную в системном сообщении фразу. Не добавляй ничего.'
            messages_json="[$(build_message_json system "$template_guard"),$(build_message_json user "$template_user")]"
            write_audit_line "before_modify reason=skill_template_hard_override tool_count=0"
            emit_before_llm_modified_payload "$messages_json" 0
            exit 0
        fi
        if [[ -n "$requested_skill_name" && -n "$next_turn_skill_create_state" ]]; then
            create_reply_text="$(build_skill_create_reply_text "$requested_skill_name" "$next_turn_skill_create_state")"
            create_guard="$(build_skill_create_hard_override_message "$create_reply_text")"
            create_user=$'Верни в ответ ровно указанную в системном сообщении фразу. Не добавляй ничего.'
            messages_json="[$(build_message_json system "$create_guard"),$(build_message_json user "$create_user")]"
            write_audit_line "before_modify reason=skill_create_hard_override tool_count=0 skill=$requested_skill_name state=$next_turn_skill_create_state"
            emit_before_llm_modified_payload "$messages_json" 0
            exit 0
        fi
        if [[ "$current_turn_skill_apply_request" == true ]]; then
            apply_reply_text="$(build_skill_apply_reply_text "${requested_skill_name:-}" || true)"
            if [[ -n "$apply_reply_text" ]]; then
                apply_guard="$(build_skill_apply_hard_override_message "$apply_reply_text")"
                apply_user=$'Верни в ответ ровно указанную в системном сообщении фразу. Не добавляй ничего.'
                messages_json="[$(build_message_json system "$apply_guard"),$(build_message_json user "$apply_user")]"
                write_audit_line "before_modify reason=skill_apply_hard_override tool_count=0 skill=${requested_skill_name:-missing}"
                emit_before_llm_modified_payload "$messages_json" 0
                exit 0
            fi
        fi
        if [[ "$looks_like_skill_turn" == true ]]; then
            skill_snapshot_csv="$(discover_runtime_skill_names_csv || true)"
            if [[ "$looks_like_sparse_skill_create_request" == true ]]; then
                messages_json="$(prepend_message_to_array "$messages_json" system "$(build_sparse_skill_create_guard_message)")"
            fi
            messages_json="$(prepend_message_to_array "$messages_json" system "$(build_skill_authoring_guard_message)")"
            messages_json="$(prepend_message_to_array "$messages_json" system "$(build_skill_runtime_snapshot_message "$skill_snapshot_csv")")"
            write_audit_line "before_modify reason=skill_turn visibility=$looks_like_skill_visibility_request sparse_create=$looks_like_sparse_skill_create_request tool_count=${tool_count:-preserve}"
            emit_before_llm_modified_payload "$messages_json" "${tool_count:-4}"
            exit 0
        fi
        write_audit_line "before_modify reason=safe_lane tool_count=0"
        emit_before_llm_modified_payload "$messages_json" 0
        exit 0
    fi
fi

if [[ "$event" == "BeforeToolCall" && "$is_telegram_safe_lane" == true ]]; then
    if [[ -n "$persisted_delivery_suppression" ]]; then
        synthetic_command="$(build_exec_heredoc_command "Telegram-safe direct fastpath already handled this reply.")"
        write_audit_line "emit_modify event=$event reason=direct_fastpath_tool_suppress token=$persisted_delivery_suppression tool=${tool_name:-missing}"
        emit_before_tool_modified_payload "exec" "{\"command\":\"$(json_escape "$synthetic_command")\"}"
        exit 0
    fi

    if tool_name_is_allowlisted "$tool_name"; then
        exit 0
    fi

    if [[ "$looks_like_status" == true ]] && [[ "$tool_name" =~ ^(sessions_list|nodes_list|process|cron)$ ]]; then
        synthetic_command="$(build_exec_heredoc_command "$canonical_status")"
        write_audit_line "emit_modify event=$event reason=status_tool_rewrite tool=$tool_name"
        emit_before_tool_modified_payload "exec" "{\"command\":\"$(json_escape "$synthetic_command")\"}"
        exit 0
    fi

    if [[ "$tool_name" == "exec" ]] && \
       printf '%s' "$command_arg" | grep -Eiq '(/home/moltis/\.moltis/skills|~/.moltis/skills|/server/skills|skills[[:space:]]+directory|SKILL\.md|find[^[:cntrl:]]{0,120}skills|ls[^[:cntrl:]]{0,80}skills|cat[^[:cntrl:]]{0,120}SKILL\.md|head[^[:cntrl:]]{0,120}SKILL\.md)'; then
        skill_snapshot_csv="$(discover_runtime_skill_names_csv || true)"
        synthetic_command="$(build_exec_heredoc_command "$(build_skill_probe_result_text "$skill_snapshot_csv")")"
        write_audit_line "emit_modify event=$event reason=skill_exec_probe tool=$tool_name"
        emit_before_tool_modified_payload "exec" "{\"command\":\"$(json_escape "$synthetic_command")\"}"
        exit 0
    fi

    disallowed_tool_note="$(build_disallowed_tool_runtime_note "${tool_name:-unknown-tool}")"
    synthetic_command="$(build_exec_heredoc_command "$disallowed_tool_note")"
    write_audit_line "emit_modify event=$event reason=disallowed_tool_block tool=${tool_name:-missing}"
    emit_before_tool_modified_payload "exec" "{\"command\":\"$(json_escape "$synthetic_command")\"}"
    exit 0
fi

if [[ "$event" == "MessageSending" && -n "$persisted_delivery_suppression" && "$is_telegram_safe_lane" == true ]]; then
    write_audit_line "emit_modify event=$event reason=direct_fastpath_delivery_suppress token=$persisted_delivery_suppression"
    clear_delivery_suppression "${turn_session_key:-}"
    clear_turn_intent "${turn_session_key:-}"
    emit_modified_payload "NO_REPLY" false
    exit 0
fi

if [[ "$event" == "MessageSending" && "$is_telegram_safe_lane" == true && "$DIRECT_FASTPATH_ENABLED" == true && "$looks_like_status" != true && "$looks_like_skill_visibility_request" != true && "$looks_like_skill_template_request" != true && -z "$persisted_skill_create_state" && "$has_delivery_internal_telemetry" == true ]]; then
    delivery_chat_id="$(extract_first_string to || true)"
    if [[ -z "$delivery_chat_id" ]]; then
        delivery_chat_id="$(extract_first_number to || true)"
    fi
    delivery_reply_to="$(extract_first_number reply_to_message_id || true)"
    clean_delivery_text="$(strip_delivery_internal_suffix "${response_text:-}")"

    if [[ "$has_appended_delivery_internal_suffix" == true && -n "$delivery_chat_id" && -n "$clean_delivery_text" && "$clean_delivery_text" != "${response_text:-}" ]]; then
        if send_telegram_direct_message "$delivery_chat_id" "$clean_delivery_text" "${delivery_reply_to:-}"; then
            write_audit_line "direct_fastpath kind=clean_delivery chat_id=$delivery_chat_id reply_to=${delivery_reply_to:-none}"
            persist_delivery_suppression "${turn_session_key:-}" "clean_delivery"
            emit_modified_payload "NO_REPLY" false
            exit 0
        fi
        write_audit_line "direct_fastpath_failed kind=clean_delivery chat_id=${delivery_chat_id:-missing} reply_to=${delivery_reply_to:-none}"
    fi
fi

if [[ "$event" == "MessageSending" && "$looks_like_status" != true && "$looks_like_skill_visibility_request" != true && "$looks_like_skill_template_request" != true && -z "$persisted_skill_create_state" && "$has_delivery_internal_telemetry" != true && "$has_after_llm_tool_intent" != true && "$has_user_visible_internal_planning" != true && "$has_skill_path_false_negative" != true && "$has_skill_visibility_generic_mismatch" != true ]]; then
    exit 0
fi

if [[ "$looks_like_status" == true ]]; then
    write_audit_line "emit_modify event=$event reason=status"
    if [[ "$event" == "AfterLLMCall" ]]; then
        emit_modified_payload "$canonical_status" true
    else
        clear_turn_intent "${turn_session_key:-}"
        emit_modified_payload "$canonical_status" false
    fi
    exit 0
fi

if [[ "$event" == "AfterLLMCall" || "$event" == "MessageSending" ]]; then
    if [[ "$looks_like_skill_visibility_request" == true || "$has_skill_visibility_generic_mismatch" == true ]]; then
        skill_snapshot_csv="$(discover_runtime_skill_names_csv || true)"
        if [[ -n "$skill_snapshot_csv" || "$has_skill_visibility_generic_mismatch" == true || "$looks_like_skill_visibility_request" == true ]]; then
            if [[ "$has_skill_path_false_negative" == true || "$has_skill_visibility_generic_mismatch" == true ]] || \
               ! reply_mentions_any_skill_from_csv "$response_text_flat" "$skill_snapshot_csv"; then
                visibility_reply_text="$(build_skill_visibility_reply_text "$skill_snapshot_csv")"
                write_audit_line "emit_modify event=$event reason=skill_visibility_reply_override snapshot_count=$(count_skill_names_csv "$skill_snapshot_csv") false_negative=$has_skill_path_false_negative generic_mismatch=$has_skill_visibility_generic_mismatch"
                if [[ "$event" == "AfterLLMCall" ]]; then
                    emit_modified_payload "$visibility_reply_text" true
                else
                    emit_modified_payload "$visibility_reply_text" false
                fi
                exit 0
            fi
            if [[ "$looks_like_skill_visibility_request" == true && -n "$persisted_skill_create_state" ]]; then
                write_audit_line "intent_clear reason=skill_visibility_followup_consumed_create_intent skill=$requested_skill_name state=$persisted_skill_create_state"
                clear_turn_intent "${turn_session_key:-}"
            fi
        fi
    fi
    if [[ "$looks_like_skill_template_request" == true ]]; then
        template_reply_text="$(build_skill_template_reply_text)"
        write_audit_line "emit_modify event=$event reason=skill_template_reply_override"
        if [[ "$event" == "AfterLLMCall" ]]; then
            emit_modified_payload "$template_reply_text" true
        else
            emit_modified_payload "$template_reply_text" false
        fi
        exit 0
    fi
    if [[ -n "$persisted_skill_create_state" && -n "$requested_skill_name" && "$looks_like_skill_visibility_request" != true && "$looks_like_skill_template_request" != true && "$looks_like_status" != true ]] && \
       [[ "$has_after_llm_tool_intent" == true || "$has_user_visible_internal_planning" == true || "$has_skill_path_false_negative" == true || "$tool_calls_present" == true || "$response_text_flat" == *"$requested_skill_name"* || "$payload_flat" == *"$requested_skill_name"* || "$event" == "MessageSending" ]]; then
        create_reply_text="$(build_skill_create_reply_text "$requested_skill_name" "$persisted_skill_create_state" || true)"
        if [[ -n "$create_reply_text" ]]; then
            write_audit_line "emit_modify event=$event reason=skill_create_reply_override skill=$requested_skill_name state=$persisted_skill_create_state"
            if [[ "$event" == "AfterLLMCall" ]]; then
                emit_modified_payload "$create_reply_text" true
            else
                clear_turn_intent "${turn_session_key:-}"
                emit_modified_payload "$create_reply_text" false
            fi
            exit 0
        fi
    fi
fi

if [[ "$event" == "AfterLLMCall" && "$tool_calls_allowlisted_only" == true && ( "$tool_calls_present" == true || "$has_delivery_internal_telemetry" == true || "$has_after_llm_tool_intent" == true || "$has_user_visible_internal_planning" == true || "$has_skill_path_false_negative" == true ) ]]; then
    fallback_text='Выполняю запрос через встроенные инструменты без показа внутренних логов. После завершения вернусь с итогом.'
    if tool_calls_only_skill_allowlisted "$tool_calls_json"; then
        fallback_text='Выполняю запрос по навыкам через встроенные инструменты без filesystem-проб. После завершения вернусь с итогом.'
    elif tool_calls_only_tavily_allowlisted "$tool_calls_json"; then
        fallback_text='Собираю подтверждение по источникам без показа внутренних логов. После завершения вернусь с кратким итогом.'
    fi
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
