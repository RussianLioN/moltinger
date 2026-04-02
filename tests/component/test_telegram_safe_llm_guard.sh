#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

HOOK_SCRIPT="$PROJECT_ROOT/scripts/telegram-safe-llm-guard.sh"
HOOK_HANDLER="$PROJECT_ROOT/.moltis/hooks/telegram-safe-llm-guard/handler.sh"
MINIMAL_PATH="/usr/bin:/bin"
export MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=false
export MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=false

setup_component_telegram_safe_llm_guard() {
    require_commands_or_skip bash jq tr sed grep || return 2
    if [[ ! -x "$HOOK_SCRIPT" || ! -x "$HOOK_HANDLER" ]]; then
        test_skip "Hook script or handler is missing/executable: $HOOK_SCRIPT | $HOOK_HANDLER"
        return 2
    fi
    return 0
}

run_hook_with_minimal_path() {
    local input_json="$1"
    printf '%s\n' "$input_json" | env PATH="$MINIMAL_PATH" bash "$HOOK_SCRIPT"
}

run_hook_bundle_with_minimal_path() {
    local input_json="$1"
    printf '%s\n' "$input_json" | env PATH="$MINIMAL_PATH" MOLTIS_TELEGRAM_SAFE_LLM_GUARD_SCRIPT="$HOOK_SCRIPT" bash "$HOOK_HANDLER"
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

    test_start "component_before_llm_guard_creates_sparse_skill_immediately_and_hard_overrides_reply"
    local before_llm_skill_turn_output before_llm_skill_turn_root before_llm_skill_turn_file
    before_llm_skill_turn_root="$(secure_temp_dir telegram-safe-create-direct)"
    before_llm_skill_turn_file="$before_llm_skill_turn_root/codex-update-new/SKILL.md"
    before_llm_skill_turn_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_RUNTIME_SKILLS_ROOT="$before_llm_skill_turn_root" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,telegram-learner' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:abg","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","messages":[{"role":"system","content":"base system"},{"role":"user","content":"Давай создадим навык codex-update-new"}],"tool_count":37,"iteration":1}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_llm_skill_turn_output" && \
       jq -e '.data.tool_count == 0' >/dev/null 2>&1 <<<"$before_llm_skill_turn_output" && \
       jq -e '.data.messages | length == 2' >/dev/null 2>&1 <<<"$before_llm_skill_turn_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe skill-create hard override")' >/dev/null 2>&1 <<<"$before_llm_skill_turn_output" && \
       jq -e '.data.messages[0].content | contains("Создал базовый шаблон навыка `codex-update-new`")' >/dev/null 2>&1 <<<"$before_llm_skill_turn_output" && \
       [[ -f "$before_llm_skill_turn_file" ]] && \
       grep -Fq 'name: codex-update-new' "$before_llm_skill_turn_file"; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must immediately create a minimal scaffold for sparse Telegram skill-create requests and hard-override the reply instead of letting the model churn"
    fi

    test_start "component_before_llm_guard_hard_overrides_skill_visibility_queries_to_deterministic_runtime_list"
    local before_llm_skill_visibility_output
    before_llm_skill_visibility_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,post-close-task-classifier,telegram-learner' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:abv","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","messages":[{"role":"system","content":"base system"},{"role":"user","content":"А что у тебя с навыками/skills?"}],"tool_count":37,"iteration":1}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_llm_skill_visibility_output" && \
       jq -e '.data.tool_count == 0' >/dev/null 2>&1 <<<"$before_llm_skill_visibility_output" && \
       jq -e '.data.messages | length == 2' >/dev/null 2>&1 <<<"$before_llm_skill_visibility_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe skill-visibility hard override")' >/dev/null 2>&1 <<<"$before_llm_skill_visibility_output" && \
       jq -e '.data.messages[0].content | contains("Навыки (3): codex-update, post-close-task-classifier, telegram-learner.")' >/dev/null 2>&1 <<<"$before_llm_skill_visibility_output" && \
       jq -e '.data.messages[1].content == "Верни в ответ ровно указанную в системном сообщении фразу. Не добавляй ничего."' >/dev/null 2>&1 <<<"$before_llm_skill_visibility_output"; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must hard-override Telegram skill-visibility turns into a deterministic text-only runtime skill list"
    fi

    test_start "component_before_llm_guard_classifies_skill_visibility_from_latest_user_turn_even_when_history_contains_create_skill_turns"
    local before_llm_skill_visibility_history_output
    before_llm_skill_visibility_history_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,post-close-task-classifier,telegram-learner' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:abvh","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","messages":[{"role":"system","content":"base system"},{"role":"user","content":"Давай создадим навык codex-update-new"},{"role":"assistant","content":"Опиши навык подробнее."},{"role":"user","content":"А что у тебя с навыками/skills?"}],"tool_count":37,"iteration":1}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_llm_skill_visibility_history_output" && \
       jq -e '.data.tool_count == 0' >/dev/null 2>&1 <<<"$before_llm_skill_visibility_history_output" && \
       jq -e '.data.messages | length == 2' >/dev/null 2>&1 <<<"$before_llm_skill_visibility_history_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe skill-visibility hard override")' >/dev/null 2>&1 <<<"$before_llm_skill_visibility_history_output" && \
       jq -e '.data.messages[0].content | contains("Навыки (3): codex-update, post-close-task-classifier, telegram-learner.")' >/dev/null 2>&1 <<<"$before_llm_skill_visibility_history_output"; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must classify skill visibility from the latest user turn instead of being contaminated by older create-skill history"
    fi

    test_start "component_before_llm_guard_classifies_sparse_create_from_latest_user_turn_even_when_history_contains_visibility_turns"
    local before_llm_skill_create_history_output before_llm_skill_create_history_root before_llm_skill_create_history_file
    before_llm_skill_create_history_root="$(secure_temp_dir telegram-safe-create-history)"
    before_llm_skill_create_history_file="$before_llm_skill_create_history_root/codex-update-new/SKILL.md"
    before_llm_skill_create_history_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_RUNTIME_SKILLS_ROOT="$before_llm_skill_create_history_root" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,telegram-learner' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:abgi","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","messages":[{"role":"system","content":"base system"},{"role":"user","content":"А что у тебя с навыками/skills?"},{"role":"assistant","content":"Навыки (2): codex-update, telegram-learner."},{"role":"user","content":"Создай навык codex-update-new"}],"tool_count":37,"iteration":1}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_llm_skill_create_history_output" && \
       jq -e '.data.tool_count == 0' >/dev/null 2>&1 <<<"$before_llm_skill_create_history_output" && \
       jq -e '.data.messages | length == 2' >/dev/null 2>&1 <<<"$before_llm_skill_create_history_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe skill-create hard override")' >/dev/null 2>&1 <<<"$before_llm_skill_create_history_output" && \
       jq -e '.data.messages[0].content | contains("Создал базовый шаблон навыка `codex-update-new`")' >/dev/null 2>&1 <<<"$before_llm_skill_create_history_output" && \
       jq -e '.data.messages[1].content == "Верни в ответ ровно указанную в системном сообщении фразу. Не добавляй ничего."' >/dev/null 2>&1 <<<"$before_llm_skill_create_history_output" && \
       [[ -f "$before_llm_skill_create_history_file" ]] && \
       grep -Fq 'name: codex-update-new' "$before_llm_skill_create_history_file"; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must classify sparse create from the latest user turn, create the runtime scaffold, and hard-override the final reply instead of reusing stale visibility history"
    fi

    test_start "component_before_llm_guard_treats_moltis_bot_channel_as_safe_lane_even_after_manual_model_switch"
    local before_llm_channel_safe_output
    before_llm_channel_safe_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,post-close-task-classifier,telegram-learner' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:channel-safe","provider":"openai-codex","model":"gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"А что у тебя с навыками/skills?"}],"tool_count":37,"iteration":1}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_llm_channel_safe_output" && \
       jq -e '.data.tool_count == 0' >/dev/null 2>&1 <<<"$before_llm_channel_safe_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe skill-visibility hard override")' >/dev/null 2>&1 <<<"$before_llm_channel_safe_output" && \
       jq -e '.data.messages[0].content | contains("Навыки (3): codex-update, post-close-task-classifier, telegram-learner.")' >/dev/null 2>&1 <<<"$before_llm_channel_safe_output"; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must keep @moltinger_bot on the Telegram-safe lane even if the session model/provider were manually switched away from the pinned safe model"
    fi

    test_start "component_before_llm_guard_hard_overrides_skill_template_requests_without_direct_block"
    local before_llm_skill_template_output
    before_llm_skill_template_output="$(
        env PATH="$MINIMAL_PATH" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:template-hard","provider":"openai-codex","model":"gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"assistant","content":"Могу создать новый навык. Если хочешь, сначала покажу шаблон."},{"role":"user","content":"У тебя должен быть темплейт"}],"tool_count":37,"iteration":1}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_llm_skill_template_output" && \
       jq -e '.data.tool_count == 0' >/dev/null 2>&1 <<<"$before_llm_skill_template_output" && \
       jq -e '.data.messages | length == 2' >/dev/null 2>&1 <<<"$before_llm_skill_template_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe skill-template hard override")' >/dev/null 2>&1 <<<"$before_llm_skill_template_output" && \
       jq -e '.data.messages[0].content | contains("Канонический минимальный шаблон навыка:")' >/dev/null 2>&1 <<<"$before_llm_skill_template_output"; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must force template requests into a deterministic text-only reply instead of using the broken direct-send block path"
    fi

    test_start "component_before_llm_guard_hard_overrides_skill_apply_requests"
    local before_llm_skill_apply_output
    before_llm_skill_apply_output="$(
        env PATH="$MINIMAL_PATH" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:skill-apply-hard","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Давай применим навык codex-update"}],"tool_count":37,"iteration":1}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_llm_skill_apply_output" && \
       jq -e '.data.tool_count == 0' >/dev/null 2>&1 <<<"$before_llm_skill_apply_output" && \
       jq -e '.data.messages | length == 2' >/dev/null 2>&1 <<<"$before_llm_skill_apply_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe skill-apply hard override")' >/dev/null 2>&1 <<<"$before_llm_skill_apply_output" && \
       jq -e '.data.messages[0].content | contains("В Telegram-safe режиме я не запускаю навыки через инструменты.")' >/dev/null 2>&1 <<<"$before_llm_skill_apply_output" && \
       jq -e '.data.messages[1].content == "Верни в ответ ровно указанную в системном сообщении фразу. Не добавляй ничего."' >/dev/null 2>&1 <<<"$before_llm_skill_apply_output"; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must hard-override skill-apply requests so Telegram-safe turns do not spin in execution/tool loops"
    fi

    test_start "component_before_llm_guard_direct_fastpaths_status_via_bot_send_when_enabled"
    local fastpath_status_tmp fastpath_status_send_script fastpath_status_log fastpath_status_stdout fastpath_status_stderr fastpath_status_status fastpath_status_intent_dir fastpath_status_suppress_file
    fastpath_status_tmp="$(secure_temp_dir telegram-safe-fastpath-status)"
    fastpath_status_send_script="$fastpath_status_tmp/send.sh"
    fastpath_status_log="$fastpath_status_tmp/send.log"
    fastpath_status_intent_dir="$fastpath_status_tmp/intent"
    fastpath_status_suppress_file="$fastpath_status_intent_dir/session_faststatus.suppress"
    cat >"$fastpath_status_send_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'chat_id=%s\ntext=%s\n' "$2" "$4" >"$FASTPATH_LOG"
printf '{"ok":true}\n'
EOF
    chmod +x "$fastpath_status_send_script"
    fastpath_status_stdout="$fastpath_status_tmp/stdout.log"
    fastpath_status_stderr="$fastpath_status_tmp/stderr.log"
    set +e
    env PATH="$MINIMAL_PATH" \
        FASTPATH_LOG="$fastpath_status_log" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$fastpath_status_intent_dir" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$fastpath_status_send_script" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_SCRIPT="$HOOK_SCRIPT" \
        bash "$HOOK_HANDLER" >"$fastpath_status_stdout" 2>"$fastpath_status_stderr" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:faststatus","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"/status"}],"tool_count":37,"iteration":1}}
EOF
    fastpath_status_status=$?
    set -e
    if [[ "$fastpath_status_status" -eq 0 ]] && \
       [[ ! -s "$fastpath_status_stdout" ]] && \
       [[ ! -s "$fastpath_status_stderr" ]] && \
       [[ -f "$fastpath_status_suppress_file" ]] && \
       grep -Fq $'\tstatus' "$fastpath_status_suppress_file" && \
       grep -Fq 'chat_id=262872984' "$fastpath_status_log" && \
       grep -Fq 'text=Статус: Online' "$fastpath_status_log" && \
       grep -Fq 'openai-codex::gpt-5.4' "$fastpath_status_log"; then
        test_pass
    else
        test_fail "Direct /status fastpath must stay handler-safe: send canonical text, return rc=0, and leave only a delivery-suppression marker instead of triggering hook-block"
    fi

    test_start "component_before_llm_guard_direct_fastpaths_skill_visibility_via_bot_send_when_enabled"
    local fastpath_visibility_tmp fastpath_visibility_send_script fastpath_visibility_log fastpath_visibility_stdout fastpath_visibility_stderr fastpath_visibility_status fastpath_visibility_intent_dir fastpath_visibility_suppress_file
    fastpath_visibility_tmp="$(secure_temp_dir telegram-safe-fastpath-visibility)"
    fastpath_visibility_send_script="$fastpath_visibility_tmp/send.sh"
    fastpath_visibility_log="$fastpath_visibility_tmp/send.log"
    fastpath_visibility_intent_dir="$fastpath_visibility_tmp/intent"
    fastpath_visibility_suppress_file="$fastpath_visibility_intent_dir/session_fastvis.suppress"
    cat >"$fastpath_visibility_send_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'chat_id=%s\ntext=%s\n' "$2" "$4" >"$FASTPATH_LOG"
printf '{"ok":true}\n'
EOF
    chmod +x "$fastpath_visibility_send_script"
    fastpath_visibility_stdout="$fastpath_visibility_tmp/stdout.log"
    fastpath_visibility_stderr="$fastpath_visibility_tmp/stderr.log"
    set +e
    env PATH="$MINIMAL_PATH" \
        FASTPATH_LOG="$fastpath_visibility_log" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$fastpath_visibility_intent_dir" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$fastpath_visibility_send_script" \
        MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,post-close-task-classifier,telegram-learner' \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_SCRIPT="$HOOK_SCRIPT" \
        bash "$HOOK_HANDLER" >"$fastpath_visibility_stdout" 2>"$fastpath_visibility_stderr" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:fastvis","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"А что у тебя с навыками/skills?"}],"tool_count":37,"iteration":1}}
EOF
    fastpath_visibility_status=$?
    set -e
    if [[ "$fastpath_visibility_status" -eq 0 ]] && \
       [[ ! -s "$fastpath_visibility_stdout" ]] && \
       [[ ! -s "$fastpath_visibility_stderr" ]] && \
       [[ -f "$fastpath_visibility_suppress_file" ]] && \
       grep -Fq $'\tskill_visibility' "$fastpath_visibility_suppress_file" && \
       grep -Fq 'chat_id=262872984' "$fastpath_visibility_log" && \
       grep -Fq 'text=Навыки (3): codex-update, post-close-task-classifier, telegram-learner.' "$fastpath_visibility_log"; then
        test_pass
    else
        test_fail "Direct skill-visibility fastpath must stay handler-safe: send the deterministic runtime list, return rc=0, and store only a delivery-suppression marker"
    fi

    test_start "component_before_llm_guard_direct_fastpaths_skill_template_via_bot_send_when_enabled"
    local fastpath_template_tmp fastpath_template_send_script fastpath_template_log fastpath_template_stdout fastpath_template_stderr fastpath_template_status fastpath_template_intent_dir fastpath_template_suppress_file
    fastpath_template_tmp="$(secure_temp_dir telegram-safe-fastpath-template)"
    fastpath_template_send_script="$fastpath_template_tmp/send.sh"
    fastpath_template_log="$fastpath_template_tmp/send.log"
    fastpath_template_intent_dir="$fastpath_template_tmp/intent"
    fastpath_template_suppress_file="$fastpath_template_intent_dir/session_fasttemplate.suppress"
    cat >"$fastpath_template_send_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'chat_id=%s\ntext=%s\n' "$2" "$4" >"$FASTPATH_LOG"
printf '{"ok":true}\n'
EOF
    chmod +x "$fastpath_template_send_script"
    fastpath_template_stdout="$fastpath_template_tmp/stdout.log"
    fastpath_template_stderr="$fastpath_template_tmp/stderr.log"
    set +e
    env PATH="$MINIMAL_PATH" \
        FASTPATH_LOG="$fastpath_template_log" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$fastpath_template_intent_dir" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$fastpath_template_send_script" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_SCRIPT="$HOOK_SCRIPT" \
        bash "$HOOK_HANDLER" >"$fastpath_template_stdout" 2>"$fastpath_template_stderr" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:fasttemplate","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"assistant","content":"Сначала покажу шаблон навыка."},{"role":"user","content":"У тебя должен быть темплейт"}],"tool_count":37,"iteration":1}}
EOF
    fastpath_template_status=$?
    set -e
    if [[ "$fastpath_template_status" -eq 0 ]] && \
       [[ ! -s "$fastpath_template_stdout" ]] && \
       [[ ! -s "$fastpath_template_stderr" ]] && \
       [[ -f "$fastpath_template_suppress_file" ]] && \
       grep -Fq $'\tskill_template' "$fastpath_template_suppress_file" && \
       grep -Fq 'chat_id=262872984' "$fastpath_template_log" && \
       grep -Fq 'text=Канонический минимальный шаблон навыка:' "$fastpath_template_log"; then
        test_pass
    else
        test_fail "Direct skill-template fastpath must stay handler-safe: send the canonical scaffold, return rc=0, and leave only a delivery-suppression marker"
    fi

    test_start "component_before_llm_guard_direct_fastpaths_sparse_skill_create_into_runtime_scaffold_when_enabled"
    local fastpath_create_tmp fastpath_create_send_script fastpath_create_log fastpath_create_stdout fastpath_create_stderr fastpath_create_status fastpath_runtime_skills_root fastpath_created_skill fastpath_create_intent_dir fastpath_create_suppress_file
    fastpath_create_tmp="$(secure_temp_dir telegram-safe-fastpath-create)"
    fastpath_create_send_script="$fastpath_create_tmp/send.sh"
    fastpath_create_log="$fastpath_create_tmp/send.log"
    fastpath_runtime_skills_root="$fastpath_create_tmp/skills"
    fastpath_created_skill="$fastpath_runtime_skills_root/codex-update-new-fastpath/SKILL.md"
    fastpath_create_intent_dir="$fastpath_create_tmp/intent"
    fastpath_create_suppress_file="$fastpath_create_intent_dir/session_fastcreate.suppress"
    cat >"$fastpath_create_send_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'chat_id=%s\ntext=%s\n' "$2" "$4" >"$FASTPATH_LOG"
printf '{"ok":true}\n'
EOF
    chmod +x "$fastpath_create_send_script"
    fastpath_create_stdout="$fastpath_create_tmp/stdout.log"
    fastpath_create_stderr="$fastpath_create_tmp/stderr.log"
    set +e
    env PATH="$MINIMAL_PATH" \
        FASTPATH_LOG="$fastpath_create_log" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$fastpath_create_intent_dir" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$fastpath_create_send_script" \
        MOLTIS_RUNTIME_SKILLS_ROOT="$fastpath_runtime_skills_root" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_SCRIPT="$HOOK_SCRIPT" \
        bash "$HOOK_HANDLER" >"$fastpath_create_stdout" 2>"$fastpath_create_stderr" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:fastcreate","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Создай навык codex-update-new-fastpath"}],"tool_count":37,"iteration":1}}
EOF
    fastpath_create_status=$?
    set -e
    if [[ "$fastpath_create_status" -eq 0 ]] && \
       [[ ! -s "$fastpath_create_stdout" ]] && \
       [[ ! -s "$fastpath_create_stderr" ]] && \
       [[ -f "$fastpath_create_suppress_file" ]] && \
       grep -Fq $'\tskill_create:created:codex-update-new-fastpath' "$fastpath_create_suppress_file" && \
       [[ -f "$fastpath_created_skill" ]] && \
       grep -Fq 'name: codex-update-new-fastpath' "$fastpath_created_skill" && \
       grep -Fq 'chat_id=262872984' "$fastpath_create_log" && \
       grep -Fq 'text=Создал базовый шаблон навыка `codex-update-new-fastpath`.' "$fastpath_create_log"; then
        test_pass
    else
        test_fail "Direct sparse-create fastpath must stay handler-safe: create the scaffold, send the deterministic confirmation, return rc=0, and store only a delivery-suppression marker"
    fi

    test_start "component_before_tool_guard_suppresses_followup_tools_after_direct_fastpath_marker"
    local direct_fastpath_tool_dir direct_fastpath_tool_output direct_fastpath_tool_marker
    direct_fastpath_tool_dir="$(secure_temp_dir telegram-safe-direct-fastpath-tool)"
    direct_fastpath_tool_marker="$direct_fastpath_tool_dir/session_fastcreate.suppress"
    mkdir -p "$direct_fastpath_tool_dir"
    printf '%s\tskill_create:created:codex-update-new-fastpath\n' "$(date +%s)" >"$direct_fastpath_tool_marker"
    direct_fastpath_tool_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$direct_fastpath_tool_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeToolCall","session_key":"session:fastcreate","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","tool":"create_skill","arguments":{"name":"codex-update-new-fastpath"}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$direct_fastpath_tool_output" && \
       jq -e '.data.tool == "exec"' >/dev/null 2>&1 <<<"$direct_fastpath_tool_output" && \
       jq -e '.data.arguments.command | contains("direct fastpath already handled this reply")' >/dev/null 2>&1 <<<"$direct_fastpath_tool_output"; then
        test_pass
    else
        test_fail "BeforeToolCall guard must turn follow-up tool attempts into a no-op exec when the direct fastpath already handled the Telegram-visible reply"
    fi

    test_start "component_message_sending_guard_suppresses_runtime_delivery_after_direct_fastpath"
    local direct_fastpath_delivery_dir direct_fastpath_delivery_output direct_fastpath_delivery_marker
    direct_fastpath_delivery_dir="$(secure_temp_dir telegram-safe-direct-fastpath-delivery)"
    direct_fastpath_delivery_marker="$direct_fastpath_delivery_dir/session_faststatus.suppress"
    mkdir -p "$direct_fastpath_delivery_dir"
    printf '%s\tstatus\n' "$(date +%s)" >"$direct_fastpath_delivery_marker"
    direct_fastpath_delivery_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$direct_fastpath_delivery_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageSending","session_id":"session:faststatus","data":{"account_id":"moltis-bot","to":"262872984","reply_to_message_id":999,"text":"Error: blocked by BeforeLLMCall hook: hook 'telegram-safe-llm-guard' blocked the action"}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$direct_fastpath_delivery_output" && \
       jq -e '.data.text == "NO_REPLY"' >/dev/null 2>&1 <<<"$direct_fastpath_delivery_output" && \
       [[ ! -f "$direct_fastpath_delivery_marker" ]]; then
        test_pass
    else
        test_fail "MessageSending guard must suppress the runtime's trailing reply after a successful direct fastpath instead of surfacing a second Telegram message"
    fi

    test_start "component_message_sending_guard_direct_sends_clean_reply_when_final_delivery_has_activity_log_suffix"
    local direct_clean_delivery_tmp direct_clean_delivery_send_script direct_clean_delivery_log direct_clean_delivery_stdout direct_clean_delivery_stderr direct_clean_delivery_status
    direct_clean_delivery_tmp="$(secure_temp_dir telegram-safe-direct-clean-delivery)"
    direct_clean_delivery_send_script="$direct_clean_delivery_tmp/send.sh"
    direct_clean_delivery_log="$direct_clean_delivery_tmp/send.log"
    cat >"$direct_clean_delivery_send_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
chat_id=""
text=""
reply_to=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --chat-id)
            chat_id="${2:-}"
            shift 2
            ;;
        --text)
            text="${2:-}"
            shift 2
            ;;
        --reply-to)
            reply_to="${2:-}"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done
printf 'chat_id=%s\ntext=%s\nreply_to=%s\n' "$chat_id" "$text" "$reply_to" >"$FASTPATH_LOG"
printf '{"ok":true}\n'
EOF
    chmod +x "$direct_clean_delivery_send_script"
    direct_clean_delivery_stdout="$direct_clean_delivery_tmp/stdout.log"
    direct_clean_delivery_stderr="$direct_clean_delivery_tmp/stderr.log"
    set +e
    env PATH="$MINIMAL_PATH" \
        FASTPATH_LOG="$direct_clean_delivery_log" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
        MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$direct_clean_delivery_send_script" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$direct_clean_delivery_tmp/intent" \
        bash "$HOOK_SCRIPT" >"$direct_clean_delivery_stdout" 2>"$direct_clean_delivery_stderr" <<'EOF'
{"event":"MessageSending","session_id":"session:clean-delivery","data":{"account_id":"moltis-bot","to":"262872984","reply_to_message_id":1200,"text":"Да — новая стабильная версия есть: 0.118.0. Activity log • mcp__tavily__tavily_search • mcp__tavily__tavily_search"}}
EOF
    direct_clean_delivery_status=$?
    set -e
    if [[ "$direct_clean_delivery_status" -eq 0 ]] && \
       [[ ! -s "$direct_clean_delivery_stderr" ]] && \
       jq -e '.action == "modify"' >/dev/null 2>&1 <"$direct_clean_delivery_stdout" && \
       jq -e '.data.text == "NO_REPLY"' >/dev/null 2>&1 <"$direct_clean_delivery_stdout" && \
       grep -Fq 'chat_id=262872984' "$direct_clean_delivery_log" && \
       grep -Fq 'text=Да — новая стабильная версия есть: 0.118.0.' "$direct_clean_delivery_log" && \
       grep -Fq 'reply_to=1200' "$direct_clean_delivery_log"; then
        test_pass
    else
        test_fail "MessageSending guard must direct-send the cleaned final reply and suppress the dirty runtime delivery when Activity log is appended to an otherwise valid answer"
    fi

    test_start "component_message_sending_guard_does_not_direct_send_legitimate_activity_log_explanation"
    local legit_activity_log_tmp legit_activity_log_send_script legit_activity_log_log legit_activity_log_stdout legit_activity_log_stderr legit_activity_log_status
    legit_activity_log_tmp="$(secure_temp_dir telegram-safe-legit-activity-log)"
    legit_activity_log_send_script="$legit_activity_log_tmp/send.sh"
    legit_activity_log_log="$legit_activity_log_tmp/send.log"
    cat >"$legit_activity_log_send_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'unexpected-direct-send\n' >"$FASTPATH_LOG"
printf '{"ok":true}\n'
EOF
    chmod +x "$legit_activity_log_send_script"
    legit_activity_log_stdout="$legit_activity_log_tmp/stdout.log"
    legit_activity_log_stderr="$legit_activity_log_tmp/stderr.log"
    set +e
    env PATH="$MINIMAL_PATH" \
        FASTPATH_LOG="$legit_activity_log_log" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
        MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$legit_activity_log_send_script" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$legit_activity_log_tmp/intent" \
        bash "$HOOK_SCRIPT" >"$legit_activity_log_stdout" 2>"$legit_activity_log_stderr" <<'EOF'
{"event":"MessageSending","session_id":"session:legit-activity-log","data":{"account_id":"moltis-bot","to":"262872985","reply_to_message_id":1201,"text":"Что такое Activity log в Moltis? Это внутренний журнал выполнения, который обычному пользователю обычно не показывают."}}
EOF
    legit_activity_log_status=$?
    set -e
    if [[ "$legit_activity_log_status" -eq 0 ]] && \
       [[ ! -s "$legit_activity_log_stderr" ]] && \
       [[ ! -s "$legit_activity_log_stdout" ]] && \
       [[ ! -e "$legit_activity_log_log" ]]; then
        test_pass
    else
        test_fail "MessageSending clean-delivery fastpath must stay inert for a legitimate explanatory reply that merely mentions Activity log and does not append a runtime telemetry suffix"
    fi

    test_start "component_before_llm_guard_clears_stale_direct_fastpath_suppression_on_new_user_turn"
    local stale_direct_fastpath_dir stale_direct_fastpath_marker stale_direct_fastpath_output
    stale_direct_fastpath_dir="$(secure_temp_dir telegram-safe-stale-direct-fastpath)"
    stale_direct_fastpath_marker="$stale_direct_fastpath_dir/session_plain-followup.suppress"
    mkdir -p "$stale_direct_fastpath_dir"
    printf '%s\tstatus\n' "$(date +%s)" >"$stale_direct_fastpath_marker"
    stale_direct_fastpath_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$stale_direct_fastpath_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:plain-followup","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Привет"}],"tool_count":37,"iteration":1}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$stale_direct_fastpath_output" && \
       [[ ! -f "$stale_direct_fastpath_marker" ]]; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must clear stale direct-fastpath suppression at the start of a new user turn so the next normal reply is not silenced"
    fi

    test_start "component_before_llm_guard_does_not_persist_stale_status_intent_for_template_followup"
    local stale_status_template_dir stale_status_template_output stale_status_template_intent
    stale_status_template_dir="$(secure_temp_dir telegram-safe-stale-status-template)"
    printf '%s\tstatus\n' "$(date +%s)" >"$stale_status_template_dir/session_template-followup.intent"
    stale_status_template_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$stale_status_template_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:template-followup","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","messages":[{"role":"system","content":"<available_skills>\n- codex-update\n</available_skills>"},{"role":"assistant","content":"Статус: Online\nКанал: Telegram (@moltinger_bot)\nМодель: custom-zai-telegram-safe::glm-5\nПровайдер: custom-zai-telegram-safe\nРежим: safe-text"},{"role":"user","content":"У тебя должен быть темплейт"}],"tool_count":37,"iteration":1}}
EOF
    )"
    stale_status_template_intent="$(cat "$stale_status_template_dir/session_template-followup.intent" 2>/dev/null || true)"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$stale_status_template_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe skill-template hard override")' >/dev/null 2>&1 <<<"$stale_status_template_output" && \
       [[ "$stale_status_template_intent" == *$'\tskill_template' ]]; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must not persist a stale /status intent when the latest user turn is a template follow-up"
    fi

    test_start "component_before_llm_guard_does_not_persist_stale_skill_visibility_intent_for_template_followup"
    local stale_visibility_template_dir stale_visibility_template_output stale_visibility_template_intent
    stale_visibility_template_dir="$(secure_temp_dir telegram-safe-stale-visibility-template)"
    printf '%s\tskill_visibility\n' "$(date +%s)" >"$stale_visibility_template_dir/session_template-after-visibility.intent"
    stale_visibility_template_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$stale_visibility_template_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:template-after-visibility","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis\n<available_skills>\n- codex-update\n</available_skills>"},{"role":"assistant","content":"Навыки (3): codex-update, post-close-task-classifier, telegram-learner."},{"role":"user","content":"У тебя должен быть темплейт"}],"tool_count":37,"iteration":1}}
EOF
    )"
    stale_visibility_template_intent="$(cat "$stale_visibility_template_dir/session_template-after-visibility.intent" 2>/dev/null || true)"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$stale_visibility_template_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe skill-template hard override")' >/dev/null 2>&1 <<<"$stale_visibility_template_output" && \
       [[ "$stale_visibility_template_intent" == *$'\tskill_template' ]]; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must let a template follow-up replace stale persisted skill-visibility intent instead of reusing the previous skills turn"
    fi

    test_start "component_before_llm_guard_does_not_persist_stale_skill_visibility_intent_for_create_followup"
    local stale_visibility_create_dir stale_visibility_create_output stale_visibility_create_intent stale_visibility_create_file
    stale_visibility_create_dir="$(secure_temp_dir telegram-safe-stale-visibility-create)"
    stale_visibility_create_file="$stale_visibility_create_dir/runtime/codex-update-new-from-stale/SKILL.md"
    printf '%s\tskill_visibility\n' "$(date +%s)" >"$stale_visibility_create_dir/session_create-after-visibility.intent"
    stale_visibility_create_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_RUNTIME_SKILLS_ROOT="$stale_visibility_create_dir/runtime" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$stale_visibility_create_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:create-after-visibility","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"assistant","content":"Навыки (3): codex-update, post-close-task-classifier, telegram-learner."},{"role":"user","content":"Создай навык codex-update-new-from-stale"}],"tool_count":37,"iteration":1}}
EOF
    )"
    stale_visibility_create_intent="$(cat "$stale_visibility_create_dir/session_create-after-visibility.intent" 2>/dev/null || true)"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$stale_visibility_create_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe skill-create hard override")' >/dev/null 2>&1 <<<"$stale_visibility_create_output" && \
       [[ -f "$stale_visibility_create_file" ]] && \
       grep -Fq 'name: codex-update-new-from-stale' "$stale_visibility_create_file" && \
       [[ "$stale_visibility_create_intent" == *$'\tskill_create_created:codex-update-new-from-stale' ]]; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must let a sparse create follow-up replace stale persisted skill-visibility intent instead of reusing the previous skills turn"
    fi

    test_start "component_message_sending_guard_reuses_persisted_skill_create_intent_for_final_confirmation"
    local skill_create_intent_dir skill_create_intent_output
    skill_create_intent_dir="$(secure_temp_dir telegram-safe-skill-create-intent)"
    printf '%s\tskill_create_created:codex-update-new\n' "$(date +%s)" >"$skill_create_intent_dir/session_skill_create.intent"
    skill_create_intent_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$skill_create_intent_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageSending","session_id":"session_skill_create","data":{"account_id":"moltis-bot","to":"262872984","reply_to_message_id":959,"text":"Ищу template и существующие навыки перед созданием."}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$skill_create_intent_output" && \
       jq -e '.data.text == "Создал базовый шаблон навыка `codex-update-new`. Могу следующим сообщением доработать описание, workflow и templates."' >/dev/null 2>&1 <<<"$skill_create_intent_output" && \
       jq -e '.data.account_id == "moltis-bot"' >/dev/null 2>&1 <<<"$skill_create_intent_output"; then
        test_pass
    else
        test_fail "MessageSending guard must reuse the persisted sparse-create intent and replace final planning chatter with a deterministic create confirmation"
    fi

    test_start "component_message_sending_guard_consumes_persisted_skill_create_intent_after_first_final_rewrite"
    local skill_create_intent_first_output skill_create_intent_second_output
    skill_create_intent_dir="$(secure_temp_dir telegram-safe-skill-create-consume)"
    printf '%s\tskill_create_created:codex-update-new\n' "$(date +%s)" >"$skill_create_intent_dir/session_skill_create.intent"
    skill_create_intent_first_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$skill_create_intent_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageSending","session_id":"session_skill_create","data":{"account_id":"moltis-bot","to":"262872984","reply_to_message_id":959,"text":"Ищу template и существующие навыки перед созданием."}}
EOF
    )"
    skill_create_intent_second_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$skill_create_intent_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageSending","session_id":"session_skill_create","data":{"account_id":"moltis-bot","to":"262872984","reply_to_message_id":960,"text":"Создам навык позже, сначала уточню детали."}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$skill_create_intent_first_output" && \
       [[ -z "$skill_create_intent_second_output" ]] && \
       [[ ! -f "$skill_create_intent_dir/session_skill_create.intent" ]]; then
        test_pass
    else
        test_fail "MessageSending guard must consume persisted skill-create intent after the first final rewrite so later unrelated deliveries are not rewritten to a false create-success reply"
    fi

    test_start "component_message_sending_guard_does_not_override_immediate_skill_visibility_followup_with_stale_create_confirmation"
    local skill_create_visibility_dir skill_create_visibility_output
    skill_create_visibility_dir="$(secure_temp_dir telegram-safe-skill-create-visibility)"
    printf '%s\tskill_create_created:codex-update-new\n' "$(date +%s)" >"$skill_create_visibility_dir/session_skill_create.intent"
    skill_create_visibility_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$skill_create_visibility_dir" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,codex-update-new,telegram-learner' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageSending","session_id":"session_skill_create","data":{"account_id":"moltis-bot","to":"262872984","reply_to_message_id":961,"user_message":"А что у тебя с навыками/skills?","text":"Навыки (3): codex-update, codex-update-new, telegram-learner."}}
EOF
    )"
    if [[ -z "$skill_create_visibility_output" ]] && \
       [[ ! -f "$skill_create_visibility_dir/session_skill_create.intent" ]]; then
        test_pass
    else
        test_fail "MessageSending guard must not overwrite an immediate skill-visibility follow-up with stale create confirmation and must clear the old create intent once visibility is proven"
    fi

    test_start "component_message_sending_guard_reuses_persisted_skill_template_intent_for_final_delivery"
    local skill_template_intent_dir skill_template_output
    skill_template_intent_dir="$(secure_temp_dir telegram-safe-skill-template-intent)"
    printf '%s\tskill_template\n' "$(date +%s)" >"$skill_template_intent_dir/session_skill_template.intent"
    skill_template_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$skill_template_intent_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageSending","session_id":"session_skill_template","data":{"account_id":"moltis-bot","to":"262872984","reply_to_message_id":960,"text":"Поищу template в системе и вернусь."}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$skill_template_output" && \
       jq -e '.data.text | contains("Канонический минимальный шаблон навыка:")' >/dev/null 2>&1 <<<"$skill_template_output" && \
       jq -e '.data.text | contains("## Workflow")' >/dev/null 2>&1 <<<"$skill_template_output"; then
        test_pass
    else
        test_fail "MessageSending guard must reuse the persisted template intent and rewrite the final Telegram delivery to the canonical scaffold text"
    fi

    test_start "component_before_llm_guard_keeps_skill_authoring_flow_on_followup_details_turn_without_repeating_create_keywords"
    local before_llm_skill_followup_output
    before_llm_skill_followup_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,telegram-learner' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:abgj","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","messages":[{"role":"system","content":"base system"},{"role":"user","content":"Создай навык codex-update-new"},{"role":"assistant","content":"Окей, создаём `codex-update-new`. Мне нужны детали: описание, тело инструкций и разрешённые инструменты. Что должен делать этот навык?"},{"role":"user","content":"Следить за версиями Codex CLI и уведомлять пользователя о новых релизах."}],"tool_count":37,"iteration":1}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_llm_skill_followup_output" && \
       jq -e '.data.tool_count == 37' >/dev/null 2>&1 <<<"$before_llm_skill_followup_output" && \
       jq -e '.data.messages | length == 6' >/dev/null 2>&1 <<<"$before_llm_skill_followup_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe skill runtime note")' >/dev/null 2>&1 <<<"$before_llm_skill_followup_output" && \
       jq -e '.data.messages[1].content | contains("Telegram-safe skill-authoring contract")' >/dev/null 2>&1 <<<"$before_llm_skill_followup_output" && \
       jq -e '.data.messages[-1].content == "Следить за версиями Codex CLI и уведомлять пользователя о новых релизах."' >/dev/null 2>&1 <<<"$before_llm_skill_followup_output"; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must keep the skill-authoring flow active when the latest user turn is a follow-up description for a previously requested create-skill flow"
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

    test_start "component_before_tool_guard_rewrites_skill_exec_probe_to_runtime_note"
    local before_tool_exec_output
    before_tool_exec_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,telegram-learner' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeToolCall","data":{"session_key":"session:tool","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","tool":"exec","arguments":{"command":"ls -la ~/.moltis/skills/"}}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_tool_exec_output" && \
       jq -e '.data.tool == "exec"' >/dev/null 2>&1 <<<"$before_tool_exec_output" && \
       jq -e '.data.arguments.command | contains("Telegram-safe runtime note for skills")' >/dev/null 2>&1 <<<"$before_tool_exec_output" && \
       jq -e '.data.arguments.command | contains("create_skill, update_skill, delete_skill")' >/dev/null 2>&1 <<<"$before_tool_exec_output" && \
       jq -e '.data.arguments.command | contains("skills/<name>/SKILL.md")' >/dev/null 2>&1 <<<"$before_tool_exec_output"; then
        test_pass
    else
        test_fail "BeforeToolCall guard must rewrite skill-path exec probes into a runtime note instead of letting Telegram turns inspect filesystem paths"
    fi

    test_start "component_before_tool_guard_rewrites_quoted_skill_exec_probe_to_runtime_note"
    local before_tool_quoted_exec_output
    before_tool_quoted_exec_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,telegram-learner' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeToolCall","data":{"session_key":"session:toolq","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","tool":"exec","arguments":{"command":"bash -lc \"ls -la ~/.moltis/skills/\""}}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_tool_quoted_exec_output" && \
       jq -e '.data.tool == "exec"' >/dev/null 2>&1 <<<"$before_tool_quoted_exec_output" && \
       jq -e '.data.arguments.command | contains("Telegram-safe runtime note for skills")' >/dev/null 2>&1 <<<"$before_tool_quoted_exec_output" && \
       jq -e '.data.arguments.command | contains("codex-update")' >/dev/null 2>&1 <<<"$before_tool_quoted_exec_output"; then
        test_pass
    else
        test_fail "BeforeToolCall guard must also rewrite quoted exec skill probes whose command strings contain escaped quotes"
    fi

    test_start "component_before_tool_guard_restores_safe_lane_for_top_level_tool_name_payload"
    local top_level_tool_intent_dir before_tool_top_level_output
    top_level_tool_intent_dir="$(secure_temp_dir telegram-safe-before-tool-top-level)"
    env PATH="$MINIMAL_PATH" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$top_level_tool_intent_dir" \
        MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,telegram-learner' \
        bash "$HOOK_SCRIPT" <<'EOF' >/dev/null
{"event":"BeforeLLMCall","data":{"session_key":"session:tooltop","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","messages":[{"role":"system","content":"Host: host=test | channel_account=moltis-bot | channel_chat_id=262872984"},{"role":"user","content":"А что у тебя с навыками/skills?"}],"tool_count":37,"iteration":1}}
EOF
    before_tool_top_level_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$top_level_tool_intent_dir" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,telegram-learner' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeToolCall","session_key":"session:tooltop","tool_name":"exec","arguments":{"command":"ls -la /home/moltis/.moltis/skills/"}}
EOF
    )"
    rm -rf "$top_level_tool_intent_dir"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_tool_top_level_output" && \
       jq -e '.data.session_key == "session:tooltop"' >/dev/null 2>&1 <<<"$before_tool_top_level_output" && \
       jq -e '.data.tool == "exec"' >/dev/null 2>&1 <<<"$before_tool_top_level_output" && \
       jq -e '.data.tool_name == "exec"' >/dev/null 2>&1 <<<"$before_tool_top_level_output" && \
       jq -e '.data.arguments.command | contains("Telegram-safe runtime note for skills")' >/dev/null 2>&1 <<<"$before_tool_top_level_output"; then
        test_pass
    else
        test_fail "BeforeToolCall guard must restore Telegram-safe lane from the persisted marker and rewrite live top-level tool_name payloads"
    fi

    test_start "component_before_tool_guard_rewrites_status_tool_from_top_level_tool_name_payload"
    local top_level_status_intent_dir before_tool_status_output
    top_level_status_intent_dir="$(secure_temp_dir telegram-safe-before-tool-status)"
    env PATH="$MINIMAL_PATH" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$top_level_status_intent_dir" \
        bash "$HOOK_SCRIPT" <<'EOF' >/dev/null
{"event":"BeforeLLMCall","data":{"session_key":"session:toolstatus","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","messages":[{"role":"system","content":"Host: host=test | channel_account=moltis-bot | channel_chat_id=262872984"},{"role":"user","content":"/status"}],"tool_count":37,"iteration":1}}
EOF
    before_tool_status_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$top_level_status_intent_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeToolCall","session_key":"session:toolstatus","tool_name":"sessions_list","arguments":{"limit":10}}
EOF
    )"
    rm -rf "$top_level_status_intent_dir"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_tool_status_output" && \
       jq -e '.data.session_key == "session:toolstatus"' >/dev/null 2>&1 <<<"$before_tool_status_output" && \
       jq -e '.data.tool == "exec"' >/dev/null 2>&1 <<<"$before_tool_status_output" && \
       jq -e '.data.tool_name == "exec"' >/dev/null 2>&1 <<<"$before_tool_status_output" && \
       jq -e '.data.arguments.command | contains("Статус: Online")' >/dev/null 2>&1 <<<"$before_tool_status_output" && \
       jq -e '.data.arguments.command | contains("Режим: safe-text")' >/dev/null 2>&1 <<<"$before_tool_status_output"; then
        test_pass
    else
        test_fail "BeforeToolCall guard must rewrite top-level status tools like sessions_list after restoring the persisted Telegram-safe status intent"
    fi

    test_start "component_before_tool_guard_allows_create_skill_passthrough"
    local before_tool_create_output
    before_tool_create_output="$(
        run_hook_with_minimal_path \
            '{"event":"BeforeToolCall","data":{"session_key":"session:tool2","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","tool":"create_skill","arguments":{"name":"codex-update-new"}}}'
    )"
    if [[ -z "$before_tool_create_output" ]]; then
        test_pass
    else
        test_fail "BeforeToolCall guard must not block dedicated skill tools such as create_skill"
    fi

    test_start "component_before_tool_guard_blocks_disallowed_browser_tool_in_safe_lane"
    local before_tool_browser_output
    before_tool_browser_output="$(
        run_hook_with_minimal_path \
            '{"event":"BeforeToolCall","session_key":"session:browser","provider":"openai-codex","model":"gpt-5.4","tool_name":"browser","arguments":{"action":"open","url":"https://example.com"}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_tool_browser_output" && \
       jq -e '.data.session_key == "session:browser"' >/dev/null 2>&1 <<<"$before_tool_browser_output" && \
       jq -e '.data.tool == "exec"' >/dev/null 2>&1 <<<"$before_tool_browser_output" && \
       jq -e '.data.tool_name == "exec"' >/dev/null 2>&1 <<<"$before_tool_browser_output" && \
       jq -e '.data.arguments.command | contains("Tool `browser` blocked")' >/dev/null 2>&1 <<<"$before_tool_browser_output" && \
       jq -e '.data.arguments.command | contains("allowlisted Tavily research MCP tools")' >/dev/null 2>&1 <<<"$before_tool_browser_output"; then
        test_pass
    else
        test_fail "BeforeToolCall guard must fail closed on disallowed browser-style tools while keeping the safe-lane note aligned with the Tavily passthrough contract"
    fi

    test_start "component_before_tool_guard_allows_tavily_passthrough_in_safe_lane"
    local before_tool_tavily_output
    before_tool_tavily_output="$(
        run_hook_with_minimal_path \
            '{"event":"BeforeToolCall","session_key":"session:tavily","provider":"openai-codex","model":"gpt-5.4","tool_name":"mcp__tavily__tavily_search","arguments":{"query":"openai codex releases"}}'
    )"
    if [[ -z "$before_tool_tavily_output" ]]; then
        test_pass
    else
        test_fail "BeforeToolCall guard must keep allowlisted Tavily research MCP tools intact instead of rewriting them into synthetic exec payloads"
    fi

    test_start "component_before_tool_guard_blocks_non_allowlisted_tavily_tool_names"
    local before_tool_tavily_skill_output
    before_tool_tavily_skill_output="$(
        run_hook_with_minimal_path \
            '{"event":"BeforeToolCall","session_key":"session:tavily-skill","provider":"openai-codex","model":"gpt-5.4","tool_name":"mcp__tavily__tavily_skill","arguments":{"query":"openai codex releases"}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_tool_tavily_skill_output" && \
       jq -e '.data.session_key == "session:tavily-skill"' >/dev/null 2>&1 <<<"$before_tool_tavily_skill_output" && \
       jq -e '.data.tool == "exec"' >/dev/null 2>&1 <<<"$before_tool_tavily_skill_output" && \
       jq -e '.data.arguments.command | contains("Tool `mcp__tavily__tavily_skill` blocked")' >/dev/null 2>&1 <<<"$before_tool_tavily_skill_output" && \
       jq -e '.data.arguments.command | contains("mcp__tavily__tavily_search")' >/dev/null 2>&1 <<<"$before_tool_tavily_skill_output"; then
        test_pass
    else
        test_fail "BeforeToolCall guard must restrict Tavily passthrough to the explicit research-tool allowlist instead of passing arbitrary tavily_* names"
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
       jq -e '.data.text == "Статус: Online\nКанал: Telegram (@moltinger_bot)\nМодель: openai-codex::gpt-5.4\nПровайдер: openai-codex\nРежим: safe-text"' >/dev/null 2>&1 <<<"$after_status_output" && \
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

    test_start "component_after_llm_guard_rewrites_generic_skill_count_reply_to_deterministic_runtime_skill_list"
    local after_skill_visibility_output
    after_skill_visibility_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,post-close-task-classifier,telegram-learner' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"AfterLLMCall","data":{"session_key":"session:skillvis","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","text":"У меня 3 навыка. Ты спрашиваешь третий раз. Что ты хочешь сделать?","tool_calls":[],"messages":[{"role":"system","content":"base system"},{"role":"user","content":"А что у тебя с навыками/skills?"}]}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$after_skill_visibility_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$after_skill_visibility_output" && \
       jq -e '.data.text == "Навыки (3): codex-update, post-close-task-classifier, telegram-learner."' >/dev/null 2>&1 <<<"$after_skill_visibility_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must replace generic repeated-turn skill-count replies with a deterministic runtime skill list"
    fi

    test_start "component_after_llm_guard_rewrites_skill_visibility_reply_from_latest_user_turn_even_when_history_contains_create_skill_turns"
    local after_skill_visibility_history_output
    after_skill_visibility_history_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,post-close-task-classifier,telegram-learner' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"AfterLLMCall","data":{"session_key":"session:skillvish","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","text":"У меня 3 навыка. Что ты хочешь сделать?","tool_calls":[],"messages":[{"role":"system","content":"base system"},{"role":"user","content":"Создай навык codex-update-new"},{"role":"assistant","content":"Опиши его подробнее."},{"role":"user","content":"А что у тебя с навыками/skills?"}]}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$after_skill_visibility_history_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$after_skill_visibility_history_output" && \
       jq -e '.data.text == "Навыки (3): codex-update, post-close-task-classifier, telegram-learner."' >/dev/null 2>&1 <<<"$after_skill_visibility_history_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must classify visibility from the latest user turn instead of older create-skill history"
    fi

    test_start "component_after_llm_guard_rewrites_observed_skill_visibility_stop_phrase_even_without_turn_context"
    local after_skill_visibility_stop_output
    after_skill_visibility_stop_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,post-close-task-classifier,telegram-learner' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"AfterLLMCall","data":{"session_key":"session:skillstop","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","text":"3 навыка в конфиге, файлов нет в sandbox. Стоп.","tool_calls":[]}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$after_skill_visibility_stop_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$after_skill_visibility_stop_output" && \
       jq -e '.data.text == "Навыки (3): codex-update, post-close-task-classifier, telegram-learner."' >/dev/null 2>&1 <<<"$after_skill_visibility_stop_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must rewrite the observed config-and-sandbox stop phrase to the canonical runtime skill list even when the runtime omits current-turn context"
    fi

    test_start "component_after_llm_guard_rewrites_observed_config_no_files_create_prompt_without_turn_context"
    local after_skill_visibility_no_files_output
    after_skill_visibility_no_files_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,post-close-task-classifier,telegram-learner' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"AfterLLMCall","data":{"session_key":"session:skillnofiles","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","text":"3 навыка в конфиге. Файлов нет. Хочешь создать — дай инструкцию.","tool_calls":[]}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$after_skill_visibility_no_files_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$after_skill_visibility_no_files_output" && \
       jq -e '.data.text == "Навыки (3): codex-update, post-close-task-classifier, telegram-learner."' >/dev/null 2>&1 <<<"$after_skill_visibility_no_files_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must rewrite the observed config-without-files create-prompt phrase to the canonical runtime skill list even when the runtime omits current-turn context"
    fi

    test_start "component_after_llm_guard_reuses_persisted_skill_visibility_intent_when_runtime_omits_turn_context"
    local persisted_intent_dir after_skill_visibility_persisted_output
    persisted_intent_dir="$(mktemp -d)"
    env PATH="$MINIMAL_PATH" \
        MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,post-close-task-classifier,telegram-learner' \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$persisted_intent_dir" \
        bash "$HOOK_SCRIPT" <<'EOF' >/dev/null
{"event":"BeforeLLMCall","data":{"session_key":"session:skillpersist-after","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","messages":[{"role":"system","content":"base system"},{"role":"user","content":"А что у тебя с навыками/skills?"}],"tool_count":37,"iteration":1}}
EOF
    after_skill_visibility_persisted_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,post-close-task-classifier,telegram-learner' \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$persisted_intent_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"AfterLLMCall","data":{"session_key":"session:skillpersist-after","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","text":"3 навыка. Создать новый?","tool_calls":[]}}
EOF
    )"
    rm -rf "$persisted_intent_dir"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$after_skill_visibility_persisted_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$after_skill_visibility_persisted_output" && \
       jq -e '.data.text == "Навыки (3): codex-update, post-close-task-classifier, telegram-learner."' >/dev/null 2>&1 <<<"$after_skill_visibility_persisted_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must reuse the persisted skill-visibility intent when the runtime drops turn context and leaves only a short generic prompt"
    fi

    test_start "component_after_llm_guard_does_not_let_stale_status_intent_override_skill_visibility_followup"
    local stale_status_visibility_dir after_skill_visibility_from_status_output
    stale_status_visibility_dir="$(secure_temp_dir telegram-safe-stale-status-visibility)"
    printf '%s\tstatus\n' "$(date +%s)" >"$stale_status_visibility_dir/session_status-visibility.intent"
    after_skill_visibility_from_status_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$stale_status_visibility_dir" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,post-close-task-classifier,telegram-learner' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"AfterLLMCall","data":{"session_key":"session:status-visibility","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","messages":[{"role":"system","content":"base system"},{"role":"assistant","content":"Статус: Online\nКанал: Telegram (@moltinger_bot)\nМодель: custom-zai-telegram-safe::glm-5\nПровайдер: custom-zai-telegram-safe\nРежим: safe-text"},{"role":"user","content":"А что у тебя с навыками/skills?"}],"text":"**Навыки: 4 в конфиге, файлов нет в sandbox.** Ты 12-й раз спрашиваешь.","tool_calls":[]}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$after_skill_visibility_from_status_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$after_skill_visibility_from_status_output" && \
       jq -e '.data.text == "Навыки (3): codex-update, post-close-task-classifier, telegram-learner."' >/dev/null 2>&1 <<<"$after_skill_visibility_from_status_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must let the latest skill-visibility turn win over stale /status history and persisted status intent"
    fi

    test_start "component_after_llm_guard_preserves_allowlisted_skill_tool_calls_while_rewriting_progress_text"
    local after_skill_tool_output
    after_skill_tool_output="$(
        run_hook_with_minimal_path \
            '{"event":"AfterLLMCall","data":{"session_key":"session:skilltool","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","text":"Пользователь просит создать навык. У меня есть доступ к create_skill. Сначала найду шаблон.","tool_calls":[{"name":"create_skill","arguments":{"name":"codex-update-new"}}]}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$after_skill_tool_output" && \
       jq -e '.data.tool_calls[0].name == "create_skill"' >/dev/null 2>&1 <<<"$after_skill_tool_output" && \
       jq -e '.data.text | contains("через встроенные инструменты")' >/dev/null 2>&1 <<<"$after_skill_tool_output" && \
       jq -e '.data.text | contains("filesystem-проб")' >/dev/null 2>&1 <<<"$after_skill_tool_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must keep allowlisted create_skill tool calls reachable while replacing leaked internal planning with a safe progress line"
    fi

    test_start "component_after_llm_guard_preserves_allowlisted_tavily_tool_calls_while_rewriting_progress_text"
    local after_tavily_tool_output
    after_tavily_tool_output="$(
        run_hook_with_minimal_path \
            '{"event":"AfterLLMCall","data":{"session_key":"session:tavilytool","provider":"openai-codex","model":"gpt-5.4","text":"Сейчас проверю последние релизы Codex через GitHub и Tavily.","tool_calls":[{"name":"mcp__tavily__tavily_search","arguments":{"query":"Codex CLI latest stable release"}}]}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$after_tavily_tool_output" && \
       jq -e '.data.tool_calls[0].name == "mcp__tavily__tavily_search"' >/dev/null 2>&1 <<<"$after_tavily_tool_output" && \
       jq -e '.data.text | contains("Собираю подтверждение по источникам")' >/dev/null 2>&1 <<<"$after_tavily_tool_output" && \
       jq -e '.data.text | contains("без показа внутренних логов")' >/dev/null 2>&1 <<<"$after_tavily_tool_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must preserve allowlisted Tavily tool calls and replace leaked planning only with a generic safe progress line"
    fi

    test_start "component_after_llm_guard_uses_generic_progress_text_for_mixed_skill_and_tavily_tool_calls"
    local after_mixed_tool_output
    after_mixed_tool_output="$(
        run_hook_with_minimal_path \
            '{"event":"AfterLLMCall","data":{"session_key":"session:mixedtool","provider":"openai-codex","model":"gpt-5.4","text":"Сейчас создам навык и параллельно проверю релизы Codex через Tavily.","tool_calls":[{"name":"create_skill","arguments":{"name":"codex-update-new"}},{"name":"mcp__tavily__tavily_search","arguments":{"query":"Codex CLI latest stable release"}}]}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$after_mixed_tool_output" && \
       jq -e '.data.tool_calls[0].name == "create_skill"' >/dev/null 2>&1 <<<"$after_mixed_tool_output" && \
       jq -e '.data.tool_calls[1].name == "mcp__tavily__tavily_search"' >/dev/null 2>&1 <<<"$after_mixed_tool_output" && \
       jq -e '.data.text | contains("Выполняю запрос через встроенные инструменты")' >/dev/null 2>&1 <<<"$after_mixed_tool_output" && \
       jq -e '.data.text | contains("без показа внутренних логов")' >/dev/null 2>&1 <<<"$after_mixed_tool_output" && \
       jq -e '.data.text | contains("filesystem-проб") | not' >/dev/null 2>&1 <<<"$after_mixed_tool_output" && \
       jq -e '.data.text | contains("Собираю подтверждение по источникам") | not' >/dev/null 2>&1 <<<"$after_mixed_tool_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must fall back to a generic progress line for mixed allowlisted skill and Tavily tool calls instead of misclassifying the turn"
    fi

    test_start "component_after_llm_guard_does_not_replace_allowlisted_create_skill_flow_with_visibility_list"
    local after_skill_tool_stop_output
    after_skill_tool_stop_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,post-close-task-classifier,telegram-learner' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"AfterLLMCall","data":{"session_key":"session:skilltoolstop","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","text":"3 навыка в конфиге, файлов нет в sandbox. Стоп.","tool_calls":[{"name":"create_skill","arguments":{"name":"codex-update-new"}}]}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$after_skill_tool_stop_output" && \
       jq -e '.data.tool_calls[0].name == "create_skill"' >/dev/null 2>&1 <<<"$after_skill_tool_stop_output" && \
       jq -e '.data.text | contains("через встроенные инструменты")' >/dev/null 2>&1 <<<"$after_skill_tool_stop_output" && \
       jq -e '.data.text != "Навыки (3): codex-update, post-close-task-classifier, telegram-learner."' >/dev/null 2>&1 <<<"$after_skill_tool_stop_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must not convert an allowlisted create_skill execution into a visibility-list rewrite just because the leaked text resembles the observed stop phrase"
    fi

    test_start "component_after_llm_guard_rewrites_skill_path_false_negative_without_claiming_no_skills"
    local after_skill_false_negative_output
    after_skill_false_negative_output="$(
        run_hook_with_minimal_path \
            '{"event":"AfterLLMCall","data":{"session_key":"session:false","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","text":"По факту: папки /home/moltis/.moltis/skills/ не существует. Навыки либо были удалены, либо ещё не созданы.","tool_calls":[]}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$after_skill_false_negative_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$after_skill_false_negative_output" && \
       jq -e '.data.text | contains("не использую sandbox filesystem как доказательство отсутствия навыков")' >/dev/null 2>&1 <<<"$after_skill_false_negative_output" && \
       jq -e '.data.text | contains("runtime skill-tools")' >/dev/null 2>&1 <<<"$after_skill_false_negative_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must rewrite skill-path false negatives so Telegram never claims that missing sandbox directories prove skills are absent"
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
       jq -e '.data.text | contains("не запускаю инструменты")' >/dev/null 2>&1 <<<"$template_probe_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must fail closed on observed template-and-skills-directory planning before text fallback turns it into queued Telegram-safe churn"
    fi

    test_start "component_after_llm_guard_blocks_exact_short_template_probe_phrase_poiuschu"
    local short_template_probe_output
    short_template_probe_output="$(
        run_hook_with_minimal_path \
            '{"event":"AfterLLMCall","data":{"session_key":"session:qsz2","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","text":"Поищу темплейт в системе:","tool_calls":[]}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$short_template_probe_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$short_template_probe_output" && \
       jq -e '.data.text | contains("не запускаю инструменты")' >/dev/null 2>&1 <<<"$short_template_probe_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must fail closed on the exact short 'Поищу темплейт в системе' leak seen in Telegram"
    fi

    test_start "component_after_llm_guard_blocks_exact_short_template_probe_phrase_ischu"
    local short_template_searching_output
    short_template_searching_output="$(
        run_hook_with_minimal_path \
            '{"event":"AfterLLMCall","data":{"session_key":"session:qsz3","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","text":"Ищу темплейт:","tool_calls":[]}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$short_template_searching_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$short_template_searching_output" && \
       jq -e '.data.text | contains("не запускаю инструменты")' >/dev/null 2>&1 <<<"$short_template_searching_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must fail closed on the exact short 'Ищу темплейт' leak seen in Telegram"
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
       jq -e '.data.text == "Статус: Online\nКанал: Telegram (@moltinger_bot)\nМодель: openai-codex::gpt-5.4\nПровайдер: openai-codex\nРежим: safe-text"' >/dev/null 2>&1 <<<"$message_sending_status_output" && \
       jq -e '.data.account_id == "moltis-bot"' >/dev/null 2>&1 <<<"$message_sending_status_output" && \
       jq -e '.data.to == "123456"' >/dev/null 2>&1 <<<"$message_sending_status_output" && \
       jq -e '.data.reply_to_message_id == 777' >/dev/null 2>&1 <<<"$message_sending_status_output" && \
       jq -e '.data.user_message == "/status"' >/dev/null 2>&1 <<<"$message_sending_status_output" && \
       jq -e 'has("data") and (.data | has("tool_calls") | not)' >/dev/null 2>&1 <<<"$message_sending_status_output"; then
        test_pass
    else
        test_fail "MessageSending guard must canonicalize final /status delivery so Telegram never sees status drift or appended Activity log traces"
    fi

    test_start "component_message_sending_guard_consumes_persisted_status_intent_after_final_delivery"
    local persisted_status_send_dir message_sending_persisted_status_output
    persisted_status_send_dir="$(secure_temp_dir telegram-safe-status-consume)"
    printf '%s\tstatus\n' "$(date +%s)" >"$persisted_status_send_dir/session_status-consume.intent"
    message_sending_persisted_status_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$persisted_status_send_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageSending","session_id":"session:status-consume","data":{"account_id":"moltis-bot","to":"123457","reply_to_message_id":778,"text":"**Статус системы**\nActivity log • Running: `uptime`"}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$message_sending_persisted_status_output" && \
       jq -e '.data.text == "Статус: Online\nКанал: Telegram (@moltinger_bot)\nМодель: openai-codex::gpt-5.4\nПровайдер: openai-codex\nРежим: safe-text"' >/dev/null 2>&1 <<<"$message_sending_persisted_status_output" && \
       [[ ! -f "$persisted_status_send_dir/session_status-consume.intent" ]]; then
        test_pass
    else
        test_fail "MessageSending guard must consume the persisted status intent after final canonical delivery so later turns are not contaminated by stale /status state"
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

    test_start "component_message_sending_guard_rewrites_tavily_validation_error_and_fetch_trace"
    local message_sending_tavily_validation_output
    message_sending_tavily_validation_output="$(
        run_hook_with_minimal_path \
            '{"event":"MessageSending","session_id":"session:vwy-tavily","data":{"text":"📋 Activity log • 🔧 mcp__tavily__tavily_search • ❌ MCP tool error: Internal error: 3 validation errors for call[tavily_search] • 🔗 Fetching github.com/openai/codex/releases/latest"}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$message_sending_tavily_validation_output" && \
       jq -e '.data.text | contains("не запускаю инструменты")' >/dev/null 2>&1 <<<"$message_sending_tavily_validation_output" && \
       jq -e 'has("data") and (.data | has("tool_calls") | not)' >/dev/null 2>&1 <<<"$message_sending_tavily_validation_output"; then
        test_pass
    else
        test_fail "MessageSending guard must strip Tavily validation errors and fetch traces from final Telegram-safe delivery"
    fi

    test_start "component_message_sending_guard_rewrites_skill_visibility_reply_from_user_message_when_messages_array_is_absent"
    local message_sending_skill_visibility_output
    message_sending_skill_visibility_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,post-close-task-classifier,telegram-learner' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageSending","session_id":"session:vwy-skillvis","data":{"account_id":"moltis-bot","to":"262872984","reply_to_message_id":955,"user_message":"А что у тебя с навыками/skills?","text":"У меня 3 навыка. Что ты хочешь сделать?"}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$message_sending_skill_visibility_output" && \
       jq -e '.data.text == "Навыки (3): codex-update, post-close-task-classifier, telegram-learner."' >/dev/null 2>&1 <<<"$message_sending_skill_visibility_output" && \
       jq -e '.data.account_id == "moltis-bot"' >/dev/null 2>&1 <<<"$message_sending_skill_visibility_output" && \
       jq -e '.data.to == "262872984"' >/dev/null 2>&1 <<<"$message_sending_skill_visibility_output" && \
       jq -e '.data.reply_to_message_id == 955' >/dev/null 2>&1 <<<"$message_sending_skill_visibility_output"; then
        test_pass
    else
        test_fail "MessageSending guard must use user_message as the current-turn intent source when the payload omits the messages array"
    fi

    test_start "component_message_sending_guard_rewrites_observed_skill_visibility_stop_phrase_without_user_message"
    local message_sending_skill_visibility_stop_output
    message_sending_skill_visibility_stop_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,post-close-task-classifier,telegram-learner' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageSending","session_id":"session:vwy-skillstop","data":{"account_id":"moltis-bot","to":"262872985","reply_to_message_id":956,"text":"3 навыка в конфиге, файлов нет в sandbox. Стоп."}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$message_sending_skill_visibility_stop_output" && \
       jq -e '.data.text == "Навыки (3): codex-update, post-close-task-classifier, telegram-learner."' >/dev/null 2>&1 <<<"$message_sending_skill_visibility_stop_output" && \
       jq -e '.data.account_id == "moltis-bot"' >/dev/null 2>&1 <<<"$message_sending_skill_visibility_stop_output" && \
       jq -e '.data.to == "262872985"' >/dev/null 2>&1 <<<"$message_sending_skill_visibility_stop_output" && \
       jq -e '.data.reply_to_message_id == 956' >/dev/null 2>&1 <<<"$message_sending_skill_visibility_stop_output"; then
        test_pass
    else
        test_fail "MessageSending guard must rewrite the observed config-and-sandbox stop phrase even when the runtime omits both messages[] and user_message"
    fi

    test_start "component_message_sending_guard_rewrites_observed_config_no_files_create_prompt_without_user_message"
    local message_sending_skill_visibility_no_files_output
    message_sending_skill_visibility_no_files_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,post-close-task-classifier,telegram-learner' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageSending","session_id":"session:vwy-skillnofiles","data":{"account_id":"moltis-bot","to":"262872986","reply_to_message_id":957,"text":"3 навыка в конфиге. Файлов нет. Хочешь создать — дай инструкцию."}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$message_sending_skill_visibility_no_files_output" && \
       jq -e '.data.text == "Навыки (3): codex-update, post-close-task-classifier, telegram-learner."' >/dev/null 2>&1 <<<"$message_sending_skill_visibility_no_files_output" && \
       jq -e '.data.account_id == "moltis-bot"' >/dev/null 2>&1 <<<"$message_sending_skill_visibility_no_files_output" && \
       jq -e '.data.to == "262872986"' >/dev/null 2>&1 <<<"$message_sending_skill_visibility_no_files_output" && \
       jq -e '.data.reply_to_message_id == 957' >/dev/null 2>&1 <<<"$message_sending_skill_visibility_no_files_output"; then
        test_pass
    else
        test_fail "MessageSending guard must rewrite the observed config-without-files create-prompt phrase even when the runtime omits both messages[] and user_message"
    fi

    test_start "component_message_sending_guard_reuses_persisted_skill_visibility_intent_when_delivery_payload_omits_turn_context"
    local persisted_intent_send_dir message_sending_skill_visibility_persisted_output
    persisted_intent_send_dir="$(mktemp -d)"
    env PATH="$MINIMAL_PATH" \
        MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,post-close-task-classifier,telegram-learner' \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$persisted_intent_send_dir" \
        bash "$HOOK_SCRIPT" <<'EOF' >/dev/null
{"event":"BeforeLLMCall","data":{"session_key":"session:skillpersist-send","provider":"custom-zai-telegram-safe","model":"custom-zai-telegram-safe::glm-5","messages":[{"role":"system","content":"base system"},{"role":"user","content":"А что у тебя с навыками/skills?"}],"tool_count":37,"iteration":1}}
EOF
    message_sending_skill_visibility_persisted_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,post-close-task-classifier,telegram-learner' \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$persisted_intent_send_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageSending","session_id":"session:skillpersist-send","data":{"account_id":"moltis-bot","to":"262872987","reply_to_message_id":958,"text":"3 навыка. Создать новый?"}}
EOF
    )"
    rm -rf "$persisted_intent_send_dir"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$message_sending_skill_visibility_persisted_output" && \
       jq -e '.data.text == "Навыки (3): codex-update, post-close-task-classifier, telegram-learner."' >/dev/null 2>&1 <<<"$message_sending_skill_visibility_persisted_output" && \
       jq -e '.data.account_id == "moltis-bot"' >/dev/null 2>&1 <<<"$message_sending_skill_visibility_persisted_output" && \
       jq -e '.data.to == "262872987"' >/dev/null 2>&1 <<<"$message_sending_skill_visibility_persisted_output" && \
       jq -e '.data.reply_to_message_id == 958' >/dev/null 2>&1 <<<"$message_sending_skill_visibility_persisted_output"; then
        test_pass
    else
        test_fail "MessageSending guard must reuse the persisted skill-visibility intent when delivery omits both messages[] and user_message and leaves only a short generic prompt"
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
