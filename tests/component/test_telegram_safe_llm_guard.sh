#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

HOOK_SCRIPT="$PROJECT_ROOT/scripts/telegram-safe-llm-guard.sh"

setup_component_telegram_safe_llm_guard() {
    require_commands_or_skip bash jq tr sed grep || return 2
    return 0
}

run_component_telegram_safe_llm_guard_tests() {
    start_timer

    local setup_code=0
    set +e
    setup_component_telegram_safe_llm_guard
    setup_code=$?
    set -e
    if [[ $setup_code -ne 0 ]]; then
        generate_report
        return
    fi

    test_start "component_before_llm_guard_injects_strict_status_contract_for_telegram_safe_lane"
    local before_status_output
    before_status_output="$(
        cat <<'EOF' | bash "$HOOK_SCRIPT"
{"event":"BeforeLLMCall","data":{"session_key":"session:abc","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","messages":[{"role":"user","content":"/status"}]}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_status_output" && \
       jq -e '.data.messages[-1].role == "system"' >/dev/null 2>&1 <<<"$before_status_output" && \
       jq -e '.data.messages[-1].content | contains("For the literal command /status")' >/dev/null 2>&1 <<<"$before_status_output" && \
       jq -e '.data.messages[-1].content | contains("Модель: custom-zai-telegram-safe::glm-5")' >/dev/null 2>&1 <<<"$before_status_output"; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must inject an exact `/status` contract for the Telegram-safe lane"
    fi

    test_start "component_before_llm_guard_injects_no_tool_policy_for_general_telegram_safe_requests"
    local before_general_output
    before_general_output="$(
        cat <<'EOF' | bash "$HOOK_SCRIPT"
{"event":"BeforeLLMCall","data":{"session_key":"session:def","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","messages":[{"role":"user","content":"Изучи документацию и настрой workflow"}]}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_general_output" && \
       jq -e '.data.messages[-1].content | contains("Never call or simulate tools")' >/dev/null 2>&1 <<<"$before_general_output" && \
       jq -e '.data.messages[-1].content | contains("web UI or operator session")' >/dev/null 2>&1 <<<"$before_general_output"; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must inject a no-tool Telegram-safe policy for general requests"
    fi

    test_start "component_after_llm_guard_rewrites_status_like_tool_fallback_to_canonical_safe_status"
    local after_status_output
    after_status_output="$(
        cat <<'EOF' | bash "$HOOK_SCRIPT"
{"event":"AfterLLMCall","data":{"session_key":"session:ghi","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","text":"**Статус системы**\nПроцессы в tmux: нет\nМодель: zai::glm-5","tool_calls":[{"name":"process","arguments":{"action":"list"}},{"name":"cron","arguments":{"action":"list"}}]}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$after_status_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$after_status_output" && \
       jq -e '.data.text | contains("Модель: custom-zai-telegram-safe::glm-5")' >/dev/null 2>&1 <<<"$after_status_output" && \
       jq -e '.data.text | contains("Режим: telegram-safe")' >/dev/null 2>&1 <<<"$after_status_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must replace Telegram-safe status tool fallbacks with a canonical status reply"
    fi

    test_start "component_after_llm_guard_blocks_general_tool_fallbacks_for_telegram_safe_lane"
    local after_general_output
    after_general_output="$(
        cat <<'EOF' | bash "$HOOK_SCRIPT"
{"event":"AfterLLMCall","data":{"session_key":"session:jkl","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","text":"Сейчас проверю через browser и cron.","tool_calls":[{"name":"browser","arguments":{"action":"navigate"}}]}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$after_general_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$after_general_output" && \
       jq -e '.data.text | contains("не выполняю многошаговые инструменты")' >/dev/null 2>&1 <<<"$after_general_output" && \
       jq -e '.data.text | contains("web UI")' >/dev/null 2>&1 <<<"$after_general_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must suppress general Telegram-safe tool fallbacks and replace them with a clean user-facing fallback"
    fi

    test_start "component_telegram_safe_llm_guard_is_noop_for_non_telegram_safe_models"
    local non_safe_output
    non_safe_output="$(
        cat <<'EOF' | bash "$HOOK_SCRIPT"
{"event":"AfterLLMCall","data":{"session_key":"session:mno","provider":"zai","model":"zai::glm-5","text":"plain response","tool_calls":[]}}
EOF
    )"
    if [[ -z "$non_safe_output" ]]; then
        test_pass
    else
        test_fail "Guard must stay inert outside the Telegram-safe provider/model lane"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_telegram_safe_llm_guard_tests
fi
