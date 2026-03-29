#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

HOOK_SCRIPT="$PROJECT_ROOT/.moltis/hooks/telegram-safe-llm-guard/handler.sh"

run_component_telegram_safe_llm_guard_tests() {
    start_timer

    test_start "component_telegram_safe_llm_guard_ignores_non_safe_provider_after_llm_payloads"
    if output="$(cat <<'JSON' | bash "$HOOK_SCRIPT"
{
  "event": "AfterLLMCall",
  "data": {
    "provider": "openai-codex",
    "text": "normal reply",
    "tool_calls": [{"name": "process"}]
  }
}
JSON
    )" && [[ -z "$output" ]]; then
        test_pass
    else
        test_fail "Hook must stay inert for non-Telegram-safe providers"
    fi

    test_start "component_telegram_safe_llm_guard_rewrites_safe_provider_tool_calls_before_execution"
    if output="$(cat <<'JSON' | bash "$HOOK_SCRIPT"
{
  "event": "AfterLLMCall",
  "data": {
    "provider": "custom-zai-telegram-safe",
    "model": "glm-5",
    "text": "```json {\"name\":\"process\",\"arguments\":{\"action\":\"list\"}} ```",
    "tool_calls": [
      {
        "name": "process",
        "arguments": {
          "action": "list"
        }
      }
    ],
    "meta": {
      "finish_reason": "tool_calls"
    }
  },
  "session_id": "abc123"
}
JSON
    )" && jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$output" \
         && jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$output" \
         && jq -e '.data.model == "glm-5"' >/dev/null 2>&1 <<<"$output" \
         && jq -e '.data.meta.finish_reason == "tool_calls"' >/dev/null 2>&1 <<<"$output" \
         && jq -e '.data.text | contains("не буду запускать внутренние инструменты прямо в Telegram")' >/dev/null 2>&1 <<<"$output"; then
        test_pass
    else
        test_fail "Hook must replace Telegram-safe tool-call payloads with a direct user-facing answer"
    fi

    test_start "component_telegram_safe_llm_guard_rewrites_textual_internal_telemetry_even_without_tool_array"
    if output="$(cat <<'JSON' | bash "$HOOK_SCRIPT"
{
  "event": "AfterLLMCall",
  "provider": "custom-zai-telegram-safe",
  "data": {
    "text": "📋 Activity log • 💻 Running: `find /home/moltis/.moltis/skills -maxdepth 2 -type...` • 🧠 Searching memory...",
    "tool_calls": []
  }
}
JSON
    )" && jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$output" \
         && jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$output" \
         && jq -e '.data.text | contains("не буду запускать внутренние инструменты прямо в Telegram")' >/dev/null 2>&1 <<<"$output"; then
        test_pass
    else
        test_fail "Hook must rewrite Telegram-safe telemetry dumps before textual tool fallback can run"
    fi

    test_start "component_telegram_safe_llm_guard_blocks_before_tool_call_for_safe_provider"
    if stderr_file="$(mktemp)" && cat <<'JSON' | bash "$HOOK_SCRIPT" > /dev/null 2>"$stderr_file"
{
  "event": "BeforeToolCall",
  "data": {
    "provider": "custom-zai-telegram-safe",
    "tool": "process",
    "arguments": {
      "action": "list"
    }
  }
}
JSON
    then
        rm -f "$stderr_file"
        test_fail "Hook must block BeforeToolCall for the Telegram-safe provider"
    else
        if grep -Fq 'В Telegram-режиме я не запускаю внутренние инструменты.' "$stderr_file"; then
            rm -f "$stderr_file"
            test_pass
        else
            rm -f "$stderr_file"
            test_fail "Blocked BeforeToolCall must surface a human-readable reason"
        fi
    fi

    test_start "component_telegram_safe_llm_guard_sanitizes_message_sending_telemetry"
    if output="$(cat <<'JSON' | bash "$HOOK_SCRIPT"
{
  "event": "MessageSending",
  "data": {
    "account_id": "moltis-bot",
    "to": "262872984",
    "text": "Activity log • nodes_list • sessions_list • cron"
  }
}
JSON
    )" && jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$output" \
         && jq -e '.data.account_id == "moltis-bot"' >/dev/null 2>&1 <<<"$output" \
         && jq -e '.data.to == "262872984"' >/dev/null 2>&1 <<<"$output" \
         && jq -e '.data.text | contains("технический лог не должен попадать в чат")' >/dev/null 2>&1 <<<"$output"; then
        test_pass
    else
        test_fail "MessageSending guard must sanitize leaked telemetry while preserving routing fields"
    fi

    test_start "component_telegram_safe_llm_guard_leaves_clean_message_sending_payloads_untouched"
    if output="$(cat <<'JSON' | bash "$HOOK_SCRIPT"
{
  "event": "MessageSending",
  "data": {
    "account_id": "moltis-bot",
    "to": "262872984",
    "text": "Короткий человеческий ответ без внутренней телеметрии."
  }
}
JSON
    )" && [[ -z "$output" ]]; then
        test_pass
    else
        test_fail "Clean outbound replies must pass through without modification"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_telegram_safe_llm_guard_tests
fi
