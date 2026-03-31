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

    test_start "component_before_llm_guard_hard_overrides_broad_telegram_research_requests"
    local before_llm_output
    before_llm_output="$(
        run_hook_with_minimal_path \
            '{"event":"BeforeLLMCall","data":{"session_key":"session:abc","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","messages":[{"role":"system","content":"base system"},{"role":"user","content":"Ты можешь сейчас изучить полностью официальную инструкцию на Moltis и пошагово научить меня создавать новый навык на примере?"}],"tool_count":37,"iteration":1}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_llm_output" && \
       jq -e '.data.tool_count == 0' >/dev/null 2>&1 <<<"$before_llm_output" && \
       jq -e '.data.messages | length == 2' >/dev/null 2>&1 <<<"$before_llm_output" && \
       jq -e '.data.messages[0].role == "system"' >/dev/null 2>&1 <<<"$before_llm_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe hard override")' >/dev/null 2>&1 <<<"$before_llm_output" && \
       jq -e '.data.messages[0].content | contains("must remain text-only")' >/dev/null 2>&1 <<<"$before_llm_output" && \
       jq -e '.data.messages[0].content | contains("В Telegram-safe режиме я не запускаю инструменты")' >/dev/null 2>&1 <<<"$before_llm_output" && \
       jq -e '.data.messages[1].role == "user"' >/dev/null 2>&1 <<<"$before_llm_output" && \
       jq -e '.data.messages[1].content == "Верни в ответ ровно указанную в системном сообщении фразу. Не добавляй ничего."' >/dev/null 2>&1 <<<"$before_llm_output"; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must hard-override broad doc-study turns so the provider sees only a deterministic Telegram-safe reply contract"
    fi

    test_start "component_before_llm_guard_does_not_depend_on_tool_count_field_to_apply_hard_override"
    local before_llm_no_tool_count_output
    before_llm_no_tool_count_output="$(
        run_hook_with_minimal_path \
            '{"event":"BeforeLLMCall","data":{"session_key":"session:abd","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","messages":[{"role":"system","content":"base system"},{"role":"user","content":"Изучи полностью официальную документацию Moltis и научи меня делать новый навык"}],"iteration":1}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_llm_no_tool_count_output" && \
       jq -e '.data.tool_count == 0' >/dev/null 2>&1 <<<"$before_llm_no_tool_count_output" && \
       jq -e '.data.messages | length == 2' >/dev/null 2>&1 <<<"$before_llm_no_tool_count_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe hard override")' >/dev/null 2>&1 <<<"$before_llm_no_tool_count_output" && \
       jq -e '.data.messages[1].content == "Верни в ответ ровно указанную в системном сообщении фразу. Не добавляй ничего."' >/dev/null 2>&1 <<<"$before_llm_no_tool_count_output"; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must still apply the hard override and force tool_count=0 even if the runtime payload omits tool_count"
    fi

    test_start "component_before_llm_guard_hard_overrides_skill_template_requests"
    local before_llm_template_output
    before_llm_template_output="$(
        run_hook_with_minimal_path \
            '{"event":"BeforeLLMCall","data":{"session_key":"session:abg","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","messages":[{"role":"system","content":"base system"},{"role":"user","content":"Давай создадим навык. У тебя должен быть темплейт."}],"tool_count":37,"iteration":1}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_llm_template_output" && \
       jq -e '.data.tool_count == 0' >/dev/null 2>&1 <<<"$before_llm_template_output" && \
       jq -e '.data.messages | length == 2' >/dev/null 2>&1 <<<"$before_llm_template_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe skill-template override")' >/dev/null 2>&1 <<<"$before_llm_template_output" && \
       jq -e '.data.messages[0].content | contains("docs/moltis-skill-agent-authoring.md")' >/dev/null 2>&1 <<<"$before_llm_template_output" && \
       jq -e '.data.messages[1].content == "Верни в ответ ровно указанную в системном сообщении фразу. Не добавляй ничего."' >/dev/null 2>&1 <<<"$before_llm_template_output"; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must hard-override Telegram-safe skill-template requests so the provider cannot improvise a local template search plan"
    fi

    test_start "component_before_llm_guard_replaces_history_when_session_already_contains_stale_guard"
    local before_llm_existing_guard_output
    before_llm_existing_guard_output="$(
        run_hook_with_minimal_path \
            '{"event":"BeforeLLMCall","data":{"session_key":"session:abf","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","messages":[{"role":"system","content":"base system"},{"role":"system","content":"Telegram-safe long-research guard: stale copy"},{"role":"user","content":"Изучи полностью официальную документацию Moltis и научи меня делать новый навык"}],"tool_count":37,"iteration":2}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_llm_existing_guard_output" && \
       jq -e '.data.tool_count == 0' >/dev/null 2>&1 <<<"$before_llm_existing_guard_output" && \
       jq -e '.data.messages | length == 2' >/dev/null 2>&1 <<<"$before_llm_existing_guard_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe hard override")' >/dev/null 2>&1 <<<"$before_llm_existing_guard_output" && \
       jq -e '.data.messages[1].content == "Верни в ответ ровно указанную в системном сообщении фразу. Не добавляй ничего."' >/dev/null 2>&1 <<<"$before_llm_existing_guard_output"; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must replace stale session history with the hard override when an older guard copy already exists"
    fi

    test_start "component_before_llm_guard_forces_safe_lane_text_only_even_for_non_research_request"
    local before_llm_general_output
    before_llm_general_output="$(
        run_hook_with_minimal_path \
            '{"event":"BeforeLLMCall","data":{"session_key":"session:abe","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","messages":[{"role":"system","content":"base system"},{"role":"user","content":"Ответь кратко, что умеет этот бот."}],"tool_count":37,"iteration":1}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_llm_general_output" && \
       jq -e '.data.tool_count == 0' >/dev/null 2>&1 <<<"$before_llm_general_output" && \
       jq -e '.data.messages | length == 2' >/dev/null 2>&1 <<<"$before_llm_general_output" && \
       jq -e '.data.messages[-1].role == "user"' >/dev/null 2>&1 <<<"$before_llm_general_output" && \
       jq -e '.data.messages[-1].content == "Ответь кратко, что умеет этот бот."' >/dev/null 2>&1 <<<"$before_llm_general_output"; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must force tool_count=0 for the Telegram-safe lane even when the request is not broad research"
    fi

    test_start "component_before_llm_guard_emits_modify_payload_without_duplicate_messages_or_tool_count_fields"
    local before_tool_count_field_count before_messages_field_count
    before_tool_count_field_count="$(printf '%s' "$before_llm_output" | grep -o '"tool_count":' | wc -l | tr -d ' ')"
    before_messages_field_count="$(printf '%s' "$before_llm_output" | grep -o '"messages":' | wc -l | tr -d ' ')"
    if [[ "$before_tool_count_field_count" == "1" && "$before_messages_field_count" == "1" ]]; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must emit a clean modify payload without duplicate top-level tool_count/messages keys that the runtime can reject silently"
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

    test_start "component_after_llm_guard_emits_modify_payload_without_duplicate_text_or_tool_calls_fields"
    local after_text_field_count after_tool_calls_field_count
    after_text_field_count="$(printf '%s' "$after_general_output" | grep -o '"text":' | wc -l | tr -d ' ')"
    after_tool_calls_field_count="$(printf '%s' "$after_general_output" | grep -o '"tool_calls":' | wc -l | tr -d ' ')"
    if [[ "$after_text_field_count" == "1" && "$after_tool_calls_field_count" == "1" ]]; then
        test_pass
    else
        test_fail "AfterLLMCall guard must emit a clean modify payload without duplicate top-level text/tool_calls keys that the runtime can reject silently"
    fi

    test_start "component_after_llm_guard_keeps_stderr_empty_on_successful_modify"
    local after_general_stdout_file after_general_stderr_file after_general_output_clean after_general_stderr
    after_general_stdout_file="$(mktemp)"
    after_general_stderr_file="$(mktemp)"
    printf '%s\n' \
        '{"event":"AfterLLMCall","data":{"session_key":"session:jkm","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","text":"Хорошо, Сергей! Начинаю прямо сейчас. Сначала найду официальную документацию Moltis и изучу существующий навык `codex-update`:","tool_calls":[]}}' \
        | env PATH="$MINIMAL_PATH" bash "$HOOK_SCRIPT" >"$after_general_stdout_file" 2>"$after_general_stderr_file"
    after_general_output_clean="$(cat "$after_general_stdout_file")"
    after_general_stderr="$(cat "$after_general_stderr_file")"
    rm -f "$after_general_stdout_file" "$after_general_stderr_file"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$after_general_output_clean" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$after_general_output_clean" && \
       [[ -z "$after_general_stderr" ]]; then
        test_pass
    else
        test_fail "AfterLLMCall modify path must keep stderr empty so the runtime sees a clean hook protocol response"
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

    test_start "component_after_llm_guard_blocks_observed_template_probe_wording_before_text_fallback_parser_can_promote_it"
    local template_probe_output
    template_probe_output="$(
        run_hook_with_minimal_path \
            '{"event":"AfterLLMCall","data":{"session_key":"session:qsz","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","text":"Хорошо! Давай найду темплейт навыка и структуру. Смотрю в директории skills:","tool_calls":[]}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$template_probe_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$template_probe_output" && \
       jq -e '.data.text | contains("docs/moltis-skill-agent-authoring.md")' >/dev/null 2>&1 <<<"$template_probe_output" && \
       jq -e '.data.text | contains("skills/<name>/SKILL.md")' >/dev/null 2>&1 <<<"$template_probe_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must fail closed on observed template-and-skills-directory planning before text fallback turns it into queued Telegram-safe churn"
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

    test_start "component_after_llm_guard_blocks_live_post_deploy_doc_search_plan_without_tool_names"
    local live_doc_search_plan_output
    live_doc_search_plan_output="$(
        run_hook_with_minimal_path \
            '{"event":"AfterLLMCall","data":{"session_key":"session:qsx","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","text":"Хорошо, изучу документацию Moltis и существующие навыки как примеры. Начну с поиска официальной документации и анализа имеющегося навыка codex-update, который как раз занимается проверкой версий.","tool_calls":[]}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$live_doc_search_plan_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$live_doc_search_plan_output" && \
       jq -e '.data.text | contains("не запускаю инструменты")' >/dev/null 2>&1 <<<"$live_doc_search_plan_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must suppress live post-deploy doc-search planning text even when no raw tool names are present"
    fi

    test_start "component_after_llm_guard_blocks_live_skill_template_search_plan_from_audit"
    local live_template_search_plan_output
    live_template_search_plan_output="$(
        run_hook_with_minimal_path \
            '{"event":"AfterLLMCall","data":{"session_key":"session:qsz2","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","text":"Хорошо! Давай найду темплейт навыка и структуру:","tool_calls":[]}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$live_template_search_plan_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$live_template_search_plan_output" && \
       jq -e '.data.text | contains("docs/moltis-skill-agent-authoring.md")' >/dev/null 2>&1 <<<"$live_template_search_plan_output" && \
       jq -e '.data.text | contains("skills/<name>/SKILL.md")' >/dev/null 2>&1 <<<"$live_template_search_plan_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must rewrite live skill-template search planning into a deterministic template answer"
    fi

    test_start "component_after_llm_guard_blocks_exact_live_template_directory_probe_phrase_from_audit"
    local live_template_directory_probe_output
    live_template_directory_probe_output="$(
        run_hook_with_minimal_path \
            '{"event":"AfterLLMCall","data":{"session_key":"session:qsz3","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","text":"Давай найду темплейт. Смотрю в директории skills:","tool_calls":[]}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$live_template_directory_probe_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$live_template_directory_probe_output" && \
       jq -e '.data.text | contains("docs/moltis-skill-agent-authoring.md")' >/dev/null 2>&1 <<<"$live_template_directory_probe_output" && \
       jq -e '.data.text | contains("skills/<name>/SKILL.md")' >/dev/null 2>&1 <<<"$live_template_directory_probe_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must rewrite the exact live template-directory probe phrase from the runtime audit"
    fi

    test_start "component_after_llm_guard_blocks_exact_live_friendly_doc_search_plan_wording"
    local live_friendly_doc_search_plan_output
    live_friendly_doc_search_plan_output="$(
        run_hook_with_minimal_path \
            '{"event":"AfterLLMCall","data":{"session_key":"session:qsy","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","text":"Отлично! Давай изучу официальную документацию и существующие навыки как примеры. Начну с поиска документации Moltis и анализа навыка codex-update (он как раз проверяет версии):","tool_calls":[]}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$live_friendly_doc_search_plan_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$live_friendly_doc_search_plan_output" && \
       jq -e '.data.text | contains("не запускаю инструменты")' >/dev/null 2>&1 <<<"$live_friendly_doc_search_plan_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must suppress the exact live friendly doc-search wording that still leaks internal planning without raw tool names"
    fi

    test_start "component_after_llm_guard_blocks_exact_live_named_doc_study_phrase_from_probe"
    local live_named_doc_study_output
    live_named_doc_study_output="$(
        run_hook_with_minimal_path \
            '{"event":"AfterLLMCall","data":{"session_key":"session:qsy2","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","text":"Хорошо, Сергей! Давай изучу официальную документацию Moltis и существующий навык `codex-update` как реальный пример. Начинаю:","tool_calls":[]}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$live_named_doc_study_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$live_named_doc_study_output" && \
       jq -e '.data.text | contains("не запускаю инструменты")' >/dev/null 2>&1 <<<"$live_named_doc_study_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must suppress the exact live named doc-study wording captured by the authoritative Telegram probe"
    fi

    test_start "component_after_llm_guard_blocks_exact_live_codex_update_reading_phrase_from_audit"
    local live_codex_update_reading_output
    live_codex_update_reading_output="$(
        run_hook_with_minimal_path \
            '{"event":"AfterLLMCall","data":{"session_key":"session:qsz","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","text":"Давай наконец сделаю это! Читаю существующий навык `codex-update` как пример и найду документацию:","tool_calls":[]}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$live_codex_update_reading_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$live_codex_update_reading_output" && \
       jq -e '.data.text | contains("не запускаю инструменты")' >/dev/null 2>&1 <<<"$live_codex_update_reading_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must suppress the exact live codex-update reading phrase captured by the runtime audit"
    fi

    test_start "component_after_llm_guard_blocks_exact_live_named_doc_search_plan_wording_from_runtime_audit"
    local live_named_doc_search_plan_output
    live_named_doc_search_plan_output="$(
        run_hook_with_minimal_path \
            '{"event":"AfterLLMCall","data":{"session_key":"session:qt0","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","text":"Хорошо, Сергей! Давай изучу официальную документацию Moltis и существующий навык `codex-update` как реальный пример. Начинаю:","tool_calls":[]}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$live_named_doc_search_plan_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$live_named_doc_search_plan_output" && \
       jq -e '.data.text | contains("не запускаю инструменты")' >/dev/null 2>&1 <<<"$live_named_doc_search_plan_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must suppress the exact live named doc-search wording captured from the runtime audit"
    fi

    test_start "component_message_sending_guard_rewrites_final_status_delivery_even_when_after_llm_missed"
    local message_sending_status_output
    message_sending_status_output="$(
        run_hook_with_minimal_path \
            '{"event":"MessageSending","session_id":"session:stu","data":{"account_id":"moltis-bot","to":"123456","reply_to_message_id":777,"user_message":"/status","text":"**Статус системы**\nАктивность:\n- Tmux: нет сессий\n- Cron: нет задач\nНавыки: codex-update\nГотов к работе. Что делаем?\nActivity log • process • Running: `uptime`"}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$message_sending_status_output" && \
       jq -e '.data.text == "Статус: Online\nКанал: Telegram (@moltinger_bot)\nМодель: custom-zai-telegram-safe::glm-5\nПровайдер: custom-zai-telegram-safe\nРежим: safe-text"' >/dev/null 2>&1 <<<"$message_sending_status_output" && \
       jq -e '.data.account_id == "moltis-bot"' >/dev/null 2>&1 <<<"$message_sending_status_output" && \
       jq -e '.data.to == "123456"' >/dev/null 2>&1 <<<"$message_sending_status_output" && \
       jq -e '.data.reply_to_message_id == 777' >/dev/null 2>&1 <<<"$message_sending_status_output" && \
       jq -e '.data.user_message == "/status"' >/dev/null 2>&1 <<<"$message_sending_status_output" && \
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

    test_start "component_message_sending_guard_keeps_stderr_empty_on_successful_modify"
    local message_sending_stdout_file message_sending_stderr_file message_sending_output_clean message_sending_stderr
    message_sending_stdout_file="$(mktemp)"
    message_sending_stderr_file="$(mktemp)"
    printf '%s\n' \
        '{"event":"MessageSending","session_id":"session:vwy2","data":{"account_id":"moltis-bot","to":"777000","reply_to_message_id":780,"text":"Хорошо, Сергей! Давай изучу официальную документацию Moltis и существующий навык `codex-update` как реальный пример. Начинаю:"}}' \
        | env PATH="$MINIMAL_PATH" bash "$HOOK_SCRIPT" >"$message_sending_stdout_file" 2>"$message_sending_stderr_file"
    message_sending_output_clean="$(cat "$message_sending_stdout_file")"
    message_sending_stderr="$(cat "$message_sending_stderr_file")"
    rm -f "$message_sending_stdout_file" "$message_sending_stderr_file"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$message_sending_output_clean" && \
       jq -e '.data.text | contains("не запускаю инструменты")' >/dev/null 2>&1 <<<"$message_sending_output_clean" && \
       [[ -z "$message_sending_stderr" ]]; then
        test_pass
    else
        test_fail "MessageSending modify path must keep stderr empty so the runtime sees a clean hook protocol response"
    fi

    test_start "component_message_sending_guard_rewrites_final_doc_search_plan_without_tool_names"
    local message_sending_doc_search_plan_output
    message_sending_doc_search_plan_output="$(
        run_hook_with_minimal_path \
            '{"event":"MessageSending","session_id":"session:vwx2","data":{"text":"Хорошо, изучу документацию Moltis и существующие навыки как примеры. Начну с поиска официальной документации и анализа имеющегося навыка codex-update, который как раз занимается проверкой версий."}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$message_sending_doc_search_plan_output" && \
       jq -e '.data.text | contains("не запускаю инструменты")' >/dev/null 2>&1 <<<"$message_sending_doc_search_plan_output" && \
       jq -e 'has("data") and (.data | has("tool_calls") | not)' >/dev/null 2>&1 <<<"$message_sending_doc_search_plan_output"; then
        test_pass
    else
        test_fail "MessageSending guard must strip final doc-search planning leakage even when no raw tool names are present"
    fi

    test_start "component_message_sending_guard_rewrites_exact_live_friendly_doc_search_plan_wording"
    local message_sending_friendly_doc_search_plan_output
    message_sending_friendly_doc_search_plan_output="$(
        run_hook_with_minimal_path \
            '{"event":"MessageSending","session_id":"session:vwx3","data":{"account_id":"moltis-bot","to":"987654","reply_to_message_id":778,"text":"Отлично! Давай изучу официальную документацию и существующие навыки как примеры. Начну с поиска документации Moltis и анализа навыка codex-update (он как раз проверяет версии):"}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$message_sending_friendly_doc_search_plan_output" && \
       jq -e '.data.text | contains("не запускаю инструменты")' >/dev/null 2>&1 <<<"$message_sending_friendly_doc_search_plan_output" && \
       jq -e '.data.account_id == "moltis-bot"' >/dev/null 2>&1 <<<"$message_sending_friendly_doc_search_plan_output" && \
       jq -e '.data.to == "987654"' >/dev/null 2>&1 <<<"$message_sending_friendly_doc_search_plan_output" && \
       jq -e '.data.reply_to_message_id == 778' >/dev/null 2>&1 <<<"$message_sending_friendly_doc_search_plan_output" && \
       jq -e 'has("data") and (.data | has("tool_calls") | not)' >/dev/null 2>&1 <<<"$message_sending_friendly_doc_search_plan_output"; then
        test_pass
    else
        test_fail "MessageSending guard must strip the exact live friendly doc-search wording and preserve routing fields required for Telegram delivery"
    fi

    test_start "component_message_sending_guard_rewrites_exact_live_named_doc_search_plan_wording"
    local message_sending_named_doc_search_plan_output
    message_sending_named_doc_search_plan_output="$(
        run_hook_with_minimal_path \
            '{"event":"MessageSending","session_id":"session:vwx4","data":{"account_id":"moltis-bot","to":"555000","reply_to_message_id":779,"text":"Хорошо, Сергей! Давай изучу официальную документацию Moltis и существующий навык `codex-update` как реальный пример. Начинаю:"}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$message_sending_named_doc_search_plan_output" && \
       jq -e '.data.text | contains("не запускаю инструменты")' >/dev/null 2>&1 <<<"$message_sending_named_doc_search_plan_output" && \
       jq -e '.data.account_id == "moltis-bot"' >/dev/null 2>&1 <<<"$message_sending_named_doc_search_plan_output" && \
       jq -e '.data.to == "555000"' >/dev/null 2>&1 <<<"$message_sending_named_doc_search_plan_output" && \
       jq -e '.data.reply_to_message_id == 779' >/dev/null 2>&1 <<<"$message_sending_named_doc_search_plan_output"; then
        test_pass
    else
        test_fail "MessageSending guard must rewrite the exact live named doc-search wording and preserve Telegram routing fields"
    fi

    test_start "component_message_sending_guard_rewrites_exact_live_named_doc_study_phrase_from_probe"
    local message_sending_named_doc_study_output
    message_sending_named_doc_study_output="$(
        run_hook_with_minimal_path \
            '{"event":"MessageSending","session_id":"session:vwx4","data":{"account_id":"moltis-bot","to":"987655","reply_to_message_id":779,"text":"Хорошо, Сергей! Давай изучу официальную документацию Moltis и существующий навык `codex-update` как реальный пример. Начинаю:"}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$message_sending_named_doc_study_output" && \
       jq -e '.data.text | contains("не запускаю инструменты")' >/dev/null 2>&1 <<<"$message_sending_named_doc_study_output" && \
       jq -e '.data.account_id == "moltis-bot"' >/dev/null 2>&1 <<<"$message_sending_named_doc_study_output" && \
       jq -e '.data.to == "987655"' >/dev/null 2>&1 <<<"$message_sending_named_doc_study_output" && \
       jq -e '.data.reply_to_message_id == 779' >/dev/null 2>&1 <<<"$message_sending_named_doc_study_output" && \
       jq -e 'has("data") and (.data | has("tool_calls") | not)' >/dev/null 2>&1 <<<"$message_sending_named_doc_study_output"; then
        test_pass
    else
        test_fail "MessageSending guard must strip the exact live named doc-study wording captured by the authoritative Telegram probe"
    fi

    test_start "component_message_sending_guard_rewrites_live_skill_template_search_plan"
    local message_sending_template_search_output
    message_sending_template_search_output="$(
        run_hook_with_minimal_path \
            '{"event":"MessageSending","session_id":"session:vwx5","data":{"account_id":"moltis-bot","to":"555111","reply_to_message_id":780,"text":"Отлично! Давай найду темплейт и структуру навыков:"}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$message_sending_template_search_output" && \
       jq -e '.data.text | contains("docs/moltis-skill-agent-authoring.md")' >/dev/null 2>&1 <<<"$message_sending_template_search_output" && \
       jq -e '.data.text | contains("skills/<name>/SKILL.md")' >/dev/null 2>&1 <<<"$message_sending_template_search_output" && \
       jq -e '.data.account_id == "moltis-bot"' >/dev/null 2>&1 <<<"$message_sending_template_search_output" && \
       jq -e '.data.to == "555111"' >/dev/null 2>&1 <<<"$message_sending_template_search_output" && \
       jq -e '.data.reply_to_message_id == 780' >/dev/null 2>&1 <<<"$message_sending_template_search_output"; then
        test_pass
    else
        test_fail "MessageSending guard must rewrite live skill-template search planning and preserve Telegram routing fields"
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
