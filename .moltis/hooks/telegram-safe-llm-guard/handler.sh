#!/usr/bin/env bash
set -euo pipefail

SAFE_AFTER_LLM_TEXT="${TELEGRAM_SAFE_AFTER_LLM_TEXT:-Сейчас не буду запускать внутренние инструменты прямо в Telegram. Могу ответить кратко в чате или оформить это как отдельный фоновый навык с уведомлением по завершении.}"
SAFE_MESSAGE_TEXT="${TELEGRAM_SAFE_MESSAGE_TEXT:-Во внутреннем рантайме произошла ошибка, и технический лог не должен попадать в чат. Повторите запрос короче или разбейте его на шаги.}"
SAFE_TOOL_BLOCK_REASON="${TELEGRAM_SAFE_TOOL_BLOCK_REASON:-В Telegram-режиме я не запускаю внутренние инструменты. Сузьте запрос до конкретного вопроса или попросите вынести задачу в отдельный навык или фоновый процесс.}"

payload="$(cat)"
[[ -n "$payload" ]] || exit 0

printf '%s' "$payload" | awk \
  -v safe_after="$SAFE_AFTER_LLM_TEXT" \
  -v safe_message="$SAFE_MESSAGE_TEXT" \
  -v safe_block="$SAFE_TOOL_BLOCK_REASON" '
function minify_json(input,    i,c,out,in_string,escaped) {
  out = ""
  in_string = 0
  escaped = 0
  for (i = 1; i <= length(input); i++) {
    c = substr(input, i, 1)
    if (in_string) {
      out = out c
      if (escaped) {
        escaped = 0
      } else if (c == "\\") {
        escaped = 1
      } else if (c == "\"") {
        in_string = 0
      }
      continue
    }
    if (c == "\"") {
      in_string = 1
      out = out c
      continue
    }
    if (c ~ /[[:space:]]/) {
      continue
    }
    out = out c
  }
  return out
}

function json_escape(input,    i,c,out) {
  out = ""
  for (i = 1; i <= length(input); i++) {
    c = substr(input, i, 1)
    if (c == "\\") {
      out = out "\\\\"
    } else if (c == "\"") {
      out = out "\\\""
    } else if (c == "\b") {
      out = out "\\b"
    } else if (c == "\f") {
      out = out "\\f"
    } else if (c == "\n") {
      out = out "\\n"
    } else if (c == "\r") {
      out = out "\\r"
    } else if (c == "\t") {
      out = out "\\t"
    } else {
      out = out c
    }
  }
  return out
}

function value_span(json, start,    c,depth,in_string,escaped,i) {
  c = substr(json, start, 1)
  if (c == "\"") {
    in_string = 1
    escaped = 0
    for (i = start + 1; i <= length(json); i++) {
      c = substr(json, i, 1)
      if (escaped) {
        escaped = 0
      } else if (c == "\\") {
        escaped = 1
      } else if (c == "\"") {
        return start SUBSEP i
      }
    }
    return ""
  }

  if (c == "{" || c == "[") {
    depth = 0
    in_string = 0
    escaped = 0
    for (i = start; i <= length(json); i++) {
      c = substr(json, i, 1)
      if (in_string) {
        if (escaped) {
          escaped = 0
        } else if (c == "\\") {
          escaped = 1
        } else if (c == "\"") {
          in_string = 0
        }
        continue
      }
      if (c == "\"") {
        in_string = 1
        continue
      }
      if (c == "{" || c == "[") {
        depth++
      } else if (c == "}" || c == "]") {
        depth--
        if (depth == 0) {
          return start SUBSEP i
        }
      }
    }
    return ""
  }

  for (i = start; i <= length(json); i++) {
    c = substr(json, i, 1)
    if (c == "," || c == "}") {
      return start SUBSEP (i - 1)
    }
  }
  return start SUBSEP length(json)
}

function key_value_span(json, key,    token,depth,in_string,escaped,i,c,span_start) {
  token = "\"" key "\":"
  depth = 0
  in_string = 0
  escaped = 0
  for (i = 1; i <= length(json); i++) {
    c = substr(json, i, 1)
    if (in_string) {
      if (escaped) {
        escaped = 0
      } else if (c == "\\") {
        escaped = 1
      } else if (c == "\"") {
        in_string = 0
      }
      continue
    }
    if (depth == 1 && substr(json, i, length(token)) == token) {
      span_start = i + length(token)
      return value_span(json, span_start)
    }
    if (c == "\"") {
      in_string = 1
      continue
    }
    if (c == "{") {
      depth++
      continue
    }
    if (c == "}") {
      depth--
      continue
    }
  }
  return ""
}

function extract_top_level_object(json, key,    span,parts,start_idx,end_idx) {
  span = key_value_span(json, key)
  if (span == "") {
    return ""
  }
  split(span, parts, SUBSEP)
  start_idx = parts[1]
  end_idx = parts[2]
  return substr(json, start_idx, end_idx - start_idx + 1)
}

function replace_or_add_raw(obj, key, raw,    span,parts,start_idx,end_idx,body) {
  span = key_value_span(obj, key)
  if (span != "") {
    split(span, parts, SUBSEP)
    start_idx = parts[1]
    end_idx = parts[2]
    return substr(obj, 1, start_idx - 1) raw substr(obj, end_idx + 1)
  }

  body = substr(obj, 1, length(obj) - 1)
  if (length(body) > 1) {
    body = body ","
  }
  return body "\"" key "\":" raw "}"
}

function has_nonempty_tool_calls(data_obj,    span,parts,start_idx,end_idx,raw_value) {
  span = key_value_span(data_obj, "tool_calls")
  if (span == "") {
    return 0
  }
  split(span, parts, SUBSEP)
  start_idx = parts[1]
  end_idx = parts[2]
  raw_value = substr(data_obj, start_idx, end_idx - start_idx + 1)
  return raw_value != "[]"
}

function contains_internal_telemetry(value, lower_value) {
  lower_value = tolower(value)
  if (lower_value ~ /activity log/) return 1
  if (lower_value ~ /running:/) return 1
  if (lower_value ~ /searching memory/) return 1
  if (lower_value ~ /thinking/) return 1
  if (lower_value ~ /timed out:agentruntimedout/) return 1
  if (lower_value ~ /timed out: agent run timed out/) return 1
  if (lower_value ~ /mcp__/) return 1
  if (lower_value ~ /sessions_list/) return 1
  if (lower_value ~ /nodes_list/) return 1
  if (lower_value ~ /memory_search/) return 1
  if (lower_value ~ /tool_call/) return 1
  if (lower_value ~ /<tool/) return 1
  if (lower_value ~ /<\/tool>/) return 1
  if (lower_value ~ /"name":"process"/) return 1
  if (lower_value ~ /"name":"cron"/) return 1
  if (lower_value ~ /"tool":"process"/) return 1
  if (lower_value ~ /"tool":"cron"/) return 1
  if (lower_value ~ /`process`/) return 1
  if (lower_value ~ /`cron`/) return 1
  if (lower_value ~ /`sessions_list`/) return 1
  if (lower_value ~ /`nodes_list`/) return 1
  return 0
}

function print_modified(data_obj, replacement_text, clear_tool_calls,    patched) {
  patched = data_obj
  if (clear_tool_calls) {
    patched = replace_or_add_raw(patched, "tool_calls", "[]")
  }
  patched = replace_or_add_raw(patched, "text", "\"" json_escape(replacement_text) "\"")
  print "{\"action\":\"modify\",\"data\":" patched "}"
}

BEGIN {
  raw = ""
}

{
  raw = raw $0 "\n"
}

END {
  payload = minify_json(raw)
  if (payload == "") {
    exit 0
  }

  if (payload ~ /"event":"AfterLLMCall"/) {
    if (payload !~ /custom-zai-telegram-safe/ && payload !~ /zai-telegram-safe::glm-5/) {
      exit 0
    }

    data_obj = extract_top_level_object(payload, "data")
    if (data_obj == "") {
      exit 0
    }

    if (has_nonempty_tool_calls(data_obj) || contains_internal_telemetry(data_obj)) {
      print_modified(data_obj, safe_after, 1)
    }
    exit 0
  }

  if (payload ~ /"event":"BeforeToolCall"/) {
    if (payload ~ /custom-zai-telegram-safe/ || payload ~ /zai-telegram-safe::glm-5/) {
      print safe_block > "/dev/stderr"
      exit 1
    }
    exit 0
  }

  if (payload ~ /"event":"MessageSending"/) {
    data_obj = extract_top_level_object(payload, "data")
    if (data_obj == "") {
        exit 0
    }

    if (contains_internal_telemetry(data_obj)) {
      print_modified(data_obj, safe_message, 0)
    }
    exit 0
  }

  exit 0
}
'
