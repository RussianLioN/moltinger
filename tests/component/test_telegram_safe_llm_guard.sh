#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

HOOK_SCRIPT="$PROJECT_ROOT/scripts/telegram-safe-llm-guard.sh"
MINIMAL_PATH="/usr/bin:/bin"

setup_component_telegram_safe_llm_guard() {
    require_commands_or_skip bash jq tr sed grep || return 2
    if [[ ! -x "$HOOK_SCRIPT" ]]; then
        test_skip "Hook script is missing or not executable: $HOOK_SCRIPT"
        return 2
    fi
    return 0
}

run_hook_with_minimal_path() {
    local input_json="$1"
    printf '%s\n' "$input_json" | env PATH="$MINIMAL_PATH" bash "$HOOK_SCRIPT"
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

    test_start "component_before_llm_guard_strips_tool_surface_for_broad_telegram_research_requests"
    local before_llm_output
    before_llm_output="$(
        run_hook_with_minimal_path \
            '{"event":"BeforeLLMCall","data":{"session_key":"session:abc","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","messages":[{"role":"system","content":"base system"},{"role":"user","content":"Ты можешь сейчас изучить полностью официальную инструкцию на Moltis и пошагово научить меня создавать новый навык на примере?"}],"tool_count":37,"iteration":1}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_llm_output" && \
       jq -e '.data.tool_count == 0' >/dev/null 2>&1 <<<"$before_llm_output" && \
       jq -e '.data.messages[-1].role == "system"' >/dev/null 2>&1 <<<"$before_llm_output" && \
       jq -e '.data.messages[-1].content | contains("Telegram-safe long-research guard")' >/dev/null 2>&1 <<<"$before_llm_output" && \
       jq -e '.data.messages[-1].content | contains("must remain text-only")' >/dev/null 2>&1 <<<"$before_llm_output"; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must strip tool surface and append a deterministic Telegram-safe long-research policy before the provider sees a broad doc-study request"
    fi

    test_start "component_before_llm_guard_does_not_depend_on_tool_count_field_to_append_long_research_policy"
    local before_llm_no_tool_count_output
    before_llm_no_tool_count_output="$(
        run_hook_with_minimal_path \
            '{"event":"BeforeLLMCall","data":{"session_key":"session:abd","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","messages":[{"role":"system","content":"base system"},{"role":"user","content":"Изучи полностью официальную документацию Moltis и научи меня делать новый навык"}],"iteration":1}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_llm_no_tool_count_output" && \
       jq -e '.data.tool_count == 0' >/dev/null 2>&1 <<<"$before_llm_no_tool_count_output" && \
       jq -e '.data.messages[-1].content | contains("Telegram-safe long-research guard")' >/dev/null 2>&1 <<<"$before_llm_no_tool_count_output"; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must still append the long-research policy and force tool_count=0 even if the runtime payload omits tool_count"
    fi

    test_start "component_after_llm_guard_rewrites_status_like_tool_fallback_to_canonical_safe_status_without_jq_runtime_dependency"
    local after_status_output
    after_status_output="$(
        run_hook_with_minimal_path \
            '{"event":"AfterLLMCall","data":{"session_key":"session:ghi","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","text":"**Статус системы**\nПроцессы в tmux: нет\nМодель: zai::glm-5","tool_calls":[{"name":"process","arguments":{"action":"list"}},{"name":"cron","arguments":{"action":"list"}}]}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$after_status_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$after_status_output" && \
       jq -e '.data.text == "Статус: Online\nКанал: Telegram (@moltinger_bot)\nМодель: custom-zai-telegram-safe::glm-5\nПровайдер: custom-zai-telegram-safe\nРежим: safe-text"' >/dev/null 2>&1 <<<"$after_status_output" && \
       jq -e '.data.provider == "custom-zai-telegram-safe"' >/dev/null 2>&1 <<<"$after_status_output" && \
       jq -e '.data.model == "custom-zai-telegram-safe::glm-5"' >/dev/null 2>&1 <<<"$after_status_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must replace Telegram-safe status tool fallbacks with a canonical safe-text status reply without depending on jq in the runtime container"
    fi

    test_start "component_after_llm_guard_blocks_general_tool_fallbacks_for_telegram_safe_lane"
    local after_general_output
    after_general_output="$(
        run_hook_with_minimal_path \
            '{"event":"AfterLLMCall","data":{"session_key":"session:jkl","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","text":"Сейчас проверю через browser и cron.","tool_calls":[{"name":"browser","arguments":{"action":"navigate"}}]}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$after_general_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$after_general_output" && \
       jq -e '.data.text | contains("не запускаю инструменты")' >/dev/null 2>&1 <<<"$after_general_output" && \
       jq -e '.data.text | contains("web UI")' >/dev/null 2>&1 <<<"$after_general_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must suppress general Telegram-safe tool fallbacks and replace them with a clean user-facing fallback"
    fi

    test_start "component_after_llm_guard_blocks_internal_telemetry_even_without_tool_calls"
    local telemetry_only_output
    telemetry_only_output="$(
        run_hook_with_minimal_path \
            '{"event":"AfterLLMCall","data":{"session_key":"session:pqr","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","text":"📋 Activity log • 💻 Running: `find /home/moltis/.moltis/skills` • 🧠 Searching memory...","tool_calls":[]}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$telemetry_only_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$telemetry_only_output" && \
       jq -e '.data.text | contains("не показываю внутренние логи")' >/dev/null 2>&1 <<<"$telemetry_only_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must replace raw internal telemetry even when the tool_calls array is empty"
    fi

    test_start "component_after_llm_guard_blocks_tool_intent_text_before_text_fallback_parser_can_promote_it"
    local tool_intent_output
    tool_intent_output="$(
        run_hook_with_minimal_path \
            '{"event":"AfterLLMCall","data":{"session_key":"session:qrs","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","text":"No remote nodes available. Let me check the available skills and search the Moltis documentation for you.","tool_calls":[]}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$tool_intent_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$tool_intent_output" && \
       jq -e '.data.text | contains("не запускаю инструменты")' >/dev/null 2>&1 <<<"$tool_intent_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must treat latent tool-intent text as internal telemetry so text-fallback parsing never turns it into real Telegram-safe tool execution"
    fi

    test_start "component_after_llm_guard_blocks_observed_russian_long_research_commitment_before_text_fallback_parser_can_promote_it"
    local observed_long_research_output
    observed_long_research_output="$(
        run_hook_with_minimal_path \
            '{"event":"AfterLLMCall","data":{"session_key":"session:qst","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","text":"Нашёл официальную документацию Moltis. Давай изучу её полностью:","tool_calls":[]}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$observed_long_research_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$observed_long_research_output" && \
       jq -e '.data.text | contains("не запускаю инструменты")' >/dev/null 2>&1 <<<"$observed_long_research_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must fail closed on the observed Russian long-research commitment wording before text fallback turns it into real tool execution"
    fi

    test_start "component_after_llm_guard_blocks_observed_mounted_workspace_skill_probe_wording_before_text_fallback_parser_can_promote_it"
    local mounted_workspace_output
    mounted_workspace_output="$(
        run_hook_with_minimal_path \
            '{"event":"AfterLLMCall","data":{"session_key":"session:qsu","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","text":"Попробую найти навыки через mounted workspace:","tool_calls":[]}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$mounted_workspace_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$mounted_workspace_output" && \
       jq -e '.data.text | contains("не запускаю инструменты")' >/dev/null 2>&1 <<<"$mounted_workspace_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must fail closed on mounted-workspace skill-probe wording before text fallback turns it into exec or tavily skill calls"
    fi

    test_start "component_after_llm_guard_blocks_observed_github_repo_doc_fetch_wording_before_text_fallback_parser_can_promote_it"
    local github_repo_fetch_output
    github_repo_fetch_output="$(
        run_hook_with_minimal_path \
            '{"event":"AfterLLMCall","data":{"session_key":"session:qsv","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","text":"Нашёл официальный репозиторий Moltis на GitHub. Давайте получу полную документацию:","tool_calls":[]}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$github_repo_fetch_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$github_repo_fetch_output" && \
       jq -e '.data.text | contains("не запускаю инструменты")' >/dev/null 2>&1 <<<"$github_repo_fetch_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must fail closed on GitHub-repository doc-fetch wording before text fallback turns it into tavily research"
    fi

    test_start "component_after_llm_guard_blocks_user_visible_internal_tool_monologue_without_activity_log_markers"
    local internal_monologue_output
    internal_monologue_output="$(
        run_hook_with_minimal_path \
            '{"event":"AfterLLMCall","data":{"session_key":"session:qsw","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","text":"Пользователь просит изучить официальную документацию Moltis. У меня есть доступ к mcp__tavily__tavily_search, mcp__tavily__tavily_skill и create_skill. Сначала найду официальную документацию Moltis.","tool_calls":[]}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$internal_monologue_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$internal_monologue_output" && \
       jq -e '.data.text | contains("не запускаю инструменты")' >/dev/null 2>&1 <<<"$internal_monologue_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must suppress user-visible internal tool inventory and planning even when Activity log markers are absent"
    fi

    test_start "component_message_sending_guard_rewrites_final_status_delivery_even_when_after_llm_missed"
    local message_sending_status_output
    message_sending_status_output="$(
        run_hook_with_minimal_path \
            '{"event":"MessageSending","session_id":"session:stu","data":{"user_message":"/status","text":"**Статус системы**\nАктивность:\n- Tmux: нет сессий\n- Cron: нет задач\nНавыки: codex-update\nГотов к работе. Что делаем?\nActivity log • process • Running: `uptime`"}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$message_sending_status_output" && \
       jq -e '.data.text == "Статус: Online\nКанал: Telegram (@moltinger_bot)\nМодель: custom-zai-telegram-safe::glm-5\nПровайдер: custom-zai-telegram-safe\nРежим: safe-text"' >/dev/null 2>&1 <<<"$message_sending_status_output" && \
       jq -e 'has("data") and (.data | has("tool_calls") | not)' >/dev/null 2>&1 <<<"$message_sending_status_output"; then
        test_pass
    else
        test_fail "MessageSending guard must canonicalize final /status delivery so Telegram never sees status drift or appended Activity log traces"
    fi

    test_start "component_message_sending_guard_rewrites_final_internal_telemetry_for_safe_lane"
    local message_sending_general_output
    message_sending_general_output="$(
        run_hook_with_minimal_path \
            '{"event":"MessageSending","session_id":"session:vwx","data":{"text":"📋 Activity log • mcp__tavily__tavily_map • Running: `curl https://docs.moltis.org`"}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$message_sending_general_output" && \
       jq -e '.data.text | contains("не запускаю инструменты")' >/dev/null 2>&1 <<<"$message_sending_general_output" && \
       jq -e 'has("data") and (.data | has("tool_calls") | not)' >/dev/null 2>&1 <<<"$message_sending_general_output"; then
        test_pass
    else
        test_fail "MessageSending guard must strip leaked internal telemetry from the final Telegram-safe reply even when it appears only at delivery time"
    fi

    test_start "component_message_sending_guard_rewrites_final_internal_tool_monologue_without_activity_log_markers"
    local message_sending_internal_monologue_output
    message_sending_internal_monologue_output="$(
        run_hook_with_minimal_path \
            '{"event":"MessageSending","session_id":"session:vwy","data":{"text":"Пользователь просит изучить официальную документацию Moltis. У меня есть доступ к mcp__tavily__tavily_search, mcp__tavily__tavily_skill и create_skill. Сначала найду официальную документацию Moltis."}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$message_sending_internal_monologue_output" && \
       jq -e '.data.text | contains("не запускаю инструменты")' >/dev/null 2>&1 <<<"$message_sending_internal_monologue_output" && \
       jq -e 'has("data") and (.data | has("tool_calls") | not)' >/dev/null 2>&1 <<<"$message_sending_internal_monologue_output"; then
        test_pass
    else
        test_fail "MessageSending guard must strip final internal tool inventory/planning leakage even when Activity log markers are absent"
    fi

    test_start "component_message_sending_guard_is_noop_for_plain_text_without_strict_delivery_log_markers"
    local message_sending_plain_output
    message_sending_plain_output="$(
        run_hook_with_minimal_path \
            '{"event":"MessageSending","session_id":"session:vwz","data":{"text":"Сейчас проверю формулировку ответа и вернусь с кратким планом."}}'
    )"
    if [[ -z "$message_sending_plain_output" ]]; then
        test_pass
    else
        test_fail "MessageSending guard must stay inert for plain text that lacks strict delivery-log markers so it does not rewrite ordinary replies outside the real Activity log path"
    fi

    test_start "component_telegram_safe_llm_guard_is_noop_for_non_telegram_safe_models"
    local non_safe_output
    non_safe_output="$(
        run_hook_with_minimal_path \
            '{"event":"AfterLLMCall","data":{"session_key":"session:mno","provider":"zai","model":"zai::glm-5","text":"plain response","tool_calls":[]}}'
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
