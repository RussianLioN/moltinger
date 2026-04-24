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

run_hook_with_custom_path() {
    local custom_path="$1"
    local input_json="$2"
    printf '%s\n' "$input_json" | env PATH="$custom_path" bash "$HOOK_SCRIPT"
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

    local suite_state_dir
    suite_state_dir="$(secure_temp_dir telegram-safe-guard-suite)"
    export MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$suite_state_dir/intent"
    export MOLTIS_TELEGRAM_SAFE_LLM_GUARD_AUDIT_FILE="$suite_state_dir/audit.log"
    mkdir -p "$MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR"

    test_start "component_before_llm_guard_hard_overrides_broad_telegram_research_requests"
    local before_llm_output
    before_llm_output="$(
        run_hook_with_minimal_path \
            '{"event":"BeforeLLMCall","data":{"session_key":"session:abc","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"base system"},{"role":"user","content":"Ты можешь сейчас изучить полностью официальную инструкцию на Moltis и пошагово научить меня создавать новый навык на примере?"}],"tool_count":37,"iteration":1}}'
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
            '{"event":"BeforeLLMCall","data":{"session_key":"session:abd","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"base system"},{"role":"user","content":"Изучи полностью официальную документацию Moltis и научи меня делать новый навык"}],"iteration":1}}'
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

    test_start "component_before_llm_guard_does_not_long_research_override_explicit_skill_mutation_turns"
    local before_llm_skill_research_output
    before_llm_skill_research_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,telegram-learner' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:skill-research","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"base system"},{"role":"user","content":"Изучи официальную документацию Moltis и обнови навык codex-update так, чтобы он лучше работал в Telegram"}],"tool_count":37,"iteration":1}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_llm_skill_research_output" && \
       jq -e '.data.tool_count == 37' >/dev/null 2>&1 <<<"$before_llm_skill_research_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe skill runtime note")' >/dev/null 2>&1 <<<"$before_llm_skill_research_output" && \
       jq -e '.data.messages[1].content | contains("Telegram-safe skill-authoring contract")' >/dev/null 2>&1 <<<"$before_llm_skill_research_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe hard override") | not' >/dev/null 2>&1 <<<"$before_llm_skill_research_output" && \
       jq -e '([.data.messages[].content] | join("\n")) | contains("Telegram-safe skill-detail hard override") | not' >/dev/null 2>&1 <<<"$before_llm_skill_research_output"; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must not collapse explicit update/patch skill turns into the long-research hard override when the owner asks to study docs and then update a skill"
    fi

    test_start "component_before_llm_guard_routes_sparse_skill_create_into_native_tool_lane"
    local before_llm_skill_turn_output before_llm_skill_turn_root before_llm_skill_turn_file
    before_llm_skill_turn_root="$(secure_temp_dir telegram-safe-create-direct)"
    before_llm_skill_turn_file="$before_llm_skill_turn_root/codex-update-new/SKILL.md"
    before_llm_skill_turn_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_RUNTIME_SKILLS_ROOT="$before_llm_skill_turn_root" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,telegram-learner' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:abg","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"base system"},{"role":"user","content":"Давай создадим навык codex-update-new"}],"tool_count":37,"iteration":1}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_llm_skill_turn_output" && \
       jq -e '.data.tool_count == 37' >/dev/null 2>&1 <<<"$before_llm_skill_turn_output" && \
       jq -e '.data.messages | length == 5' >/dev/null 2>&1 <<<"$before_llm_skill_turn_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe skill runtime note")' >/dev/null 2>&1 <<<"$before_llm_skill_turn_output" && \
       jq -e '.data.messages[1].content | contains("Telegram-safe skill-authoring contract")' >/dev/null 2>&1 <<<"$before_llm_skill_turn_output" && \
       jq -e '.data.messages[2].content | contains("Telegram-safe sparse create-skill override")' >/dev/null 2>&1 <<<"$before_llm_skill_turn_output" && \
       jq -e '.data.messages[2].content | contains("После успешного create_skill можешь при необходимости в этом же ходе продолжить через update_skill, patch_skill и write_skill_files.")' >/dev/null 2>&1 <<<"$before_llm_skill_turn_output" && \
       jq -e '.data.messages[2].content | contains("Пользователю верни один короткий итог")' >/dev/null 2>&1 <<<"$before_llm_skill_turn_output" && \
       jq -e '.data.messages[-1].content == "Давай создадим навык codex-update-new"' >/dev/null 2>&1 <<<"$before_llm_skill_turn_output" && \
       [[ ! -f "$before_llm_skill_turn_file" ]]; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must keep sparse Telegram skill creation on the native tool lane, allow same-turn native refinement, and avoid repo-owned scaffold writes"
    fi

    test_start "component_before_llm_guard_keeps_codex_update_analogy_create_turn_out_of_maintenance_bucket"
    local before_llm_skill_analogy_output
    before_llm_skill_analogy_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,telegram-learner' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:abg-analogy","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"base system"},{"role":"user","content":"Создай навык moltis-update-dialog-20260424-uat для отслеживания новых версий Moltis по аналогии с codex-update."}],"tool_count":37,"iteration":1}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_llm_skill_analogy_output" && \
       jq -e '.data.tool_count == 37' >/dev/null 2>&1 <<<"$before_llm_skill_analogy_output" && \
       jq -e '.data.messages | length >= 4' >/dev/null 2>&1 <<<"$before_llm_skill_analogy_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe skill runtime note")' >/dev/null 2>&1 <<<"$before_llm_skill_analogy_output" && \
       jq -e '.data.messages[1].content | contains("Telegram-safe skill-authoring contract")' >/dev/null 2>&1 <<<"$before_llm_skill_analogy_output" && \
       jq -e '([.data.messages[].content] | join("\n")) | contains("Telegram-safe sparse create-skill override")' >/dev/null 2>&1 <<<"$before_llm_skill_analogy_output" && \
       jq -e '([.data.messages[].content] | join("\n")) | contains("не чиню и не отлаживаю `codex-update`") | not' >/dev/null 2>&1 <<<"$before_llm_skill_analogy_output"; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must treat create-skill turns that mention codex-update only as an analogy as native skill-authoring work, not as codex-update maintenance/log repair"
    fi

    test_start "component_message_received_guard_does_not_reuse_prior_maintenance_intent_for_plain_create_turn"
    local maintenance_create_dir maintenance_create_audit maintenance_create_output
    maintenance_create_dir="$(secure_temp_dir telegram-safe-maintenance-create)"
    maintenance_create_audit="$maintenance_create_dir/audit.log"
    env PATH="$MINIMAL_PATH" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$maintenance_create_dir" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_AUDIT_FILE="$maintenance_create_audit" \
        bash "$HOOK_SCRIPT" <<'EOF' >/dev/null
{"event":"BeforeLLMCall","data":{"session_key":"session:maintenance-create","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=prod | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Почини codex-update."}],"tool_count":37,"iteration":1}}
EOF
    maintenance_create_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$maintenance_create_dir" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_AUDIT_FILE="$maintenance_create_audit" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageReceived","data":{"session_key":"session:maintenance-create","channel":"telegram","channel_chat_id":"262872984","message":{"role":"user","content":"Создай навык codex-update-new для отслеживания новых версий Moltis."}}}
EOF
    )"
    if [[ -z "$maintenance_create_output" ]] && \
       grep -Fq 'safe_lane_restored source=marker session=session:maintenance-create' "$maintenance_create_audit" && \
       ! grep -Fq 'message_received_direct_fastpath kind=maintenance chat_id=262872984 token=maintenance:codex-update-new target=codex-update-new' "$maintenance_create_audit" && \
       ! grep -Fq 'message_received_direct_fastpath kind=skill_detail chat_id=262872984 token=skill_detail:codex-update-new skill=codex-update-new' "$maintenance_create_audit"; then
        test_pass
    else
        test_fail "MessageReceived guard must not reuse a previous maintenance turn to fastpath a new plain create-skill request as maintenance or skill-detail"
    fi

    test_start "component_before_llm_guard_replaces_prior_maintenance_intent_with_native_create_lane"
    local maintenance_to_create_dir maintenance_to_create_output maintenance_to_create_intent
    maintenance_to_create_dir="$(secure_temp_dir telegram-safe-maintenance-to-create)"
    env PATH="$MINIMAL_PATH" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$maintenance_to_create_dir" \
        bash "$HOOK_SCRIPT" <<'EOF' >/dev/null
{"event":"BeforeLLMCall","data":{"session_key":"session:maintenance-to-create","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=prod | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Почини codex-update."}],"tool_count":37,"iteration":1}}
EOF
    maintenance_to_create_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$maintenance_to_create_dir" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,telegram-learner' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:maintenance-to-create","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=prod | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Создай навык codex-update-new для отслеживания новых версий Moltis."}],"tool_count":37,"iteration":1}}
EOF
    )"
    maintenance_to_create_intent="$(cat "$maintenance_to_create_dir/session_maintenance-to-create.intent" 2>/dev/null || true)"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$maintenance_to_create_output" && \
       jq -e '.data.tool_count == 37' >/dev/null 2>&1 <<<"$maintenance_to_create_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe skill runtime note")' >/dev/null 2>&1 <<<"$maintenance_to_create_output" && \
       jq -e '.data.messages[1].content | contains("Telegram-safe skill-authoring contract")' >/dev/null 2>&1 <<<"$maintenance_to_create_output" && \
       jq -e '.data.messages[2].content | contains("Telegram-safe sparse create-skill override")' >/dev/null 2>&1 <<<"$maintenance_to_create_output" && \
       jq -e '([.data.messages[].content] | join("\n")) | contains("не чиню и не отлаживаю") | not' >/dev/null 2>&1 <<<"$maintenance_to_create_output" && \
       ([[ "$maintenance_to_create_intent" == *$'\tskill_native_crud\t'* ]] || [[ "$maintenance_to_create_intent" == *$'\tskill_native_crud:'* ]]); then
        test_pass
    else
        test_fail "BeforeLLMCall guard must replace stale maintenance intent with the native skill CRUD lane when the latest user turn is a plain create-skill request"
    fi

    test_start "component_message_received_guard_keeps_exact_russian_create_prompt_out_of_skill_detail_under_posix_locale"
    local posix_create_dir posix_create_audit posix_create_output posix_create_send_log posix_create_send_script posix_create_runtime_root
    posix_create_dir="$(secure_temp_dir telegram-safe-posix-create-message)"
    posix_create_audit="$posix_create_dir/audit.log"
    posix_create_send_log="$posix_create_dir/send.log"
    posix_create_send_script="$posix_create_dir/send.sh"
    posix_create_runtime_root="$posix_create_dir/runtime"
    mkdir -p "$posix_create_runtime_root/codex-update" "$posix_create_runtime_root/post-close-task-classifier" "$posix_create_runtime_root/openclaw-improvement-learner" "$posix_create_runtime_root/telegram-learner" "$posix_create_runtime_root/telegram-chat-probe"
    cp "$PROJECT_ROOT/skills/codex-update/SKILL.md" "$posix_create_runtime_root/codex-update/SKILL.md"
    cp "$PROJECT_ROOT/skills/post-close-task-classifier/SKILL.md" "$posix_create_runtime_root/post-close-task-classifier/SKILL.md"
    cp "$PROJECT_ROOT/skills/openclaw-improvement-learner/SKILL.md" "$posix_create_runtime_root/openclaw-improvement-learner/SKILL.md"
    cp "$PROJECT_ROOT/skills/telegram-learner/SKILL.md" "$posix_create_runtime_root/telegram-learner/SKILL.md"
    cp "$PROJECT_ROOT/skills/telegram-chat-probe/SKILL.md" "$posix_create_runtime_root/telegram-chat-probe/SKILL.md"
    cat >"$posix_create_send_script" <<'EOF'
#!/usr/bin/env bash
printf 'send %s\n' "$*" >>"$FASTPATH_LOG"
exit 0
EOF
    chmod +x "$posix_create_send_script"
    posix_create_output="$(
        env PATH="$MINIMAL_PATH" \
            LANG= \
            LC_ALL=C \
            LC_CTYPE=POSIX \
            FASTPATH_LOG="$posix_create_send_log" \
            MOLTIS_RUNTIME_SKILLS_ROOT="$posix_create_runtime_root" \
            MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
            MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$posix_create_send_script" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$posix_create_dir/intent" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_AUDIT_FILE="$posix_create_audit" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageReceived","session_key":"session:posix-create-message","content":"Создай навык moltis-update-dialog-20260424-live-05 для отслеживания новых версий Moltis.","channel":null,"channel_binding":{"surface":"telegram","session_kind":"channel","channel_type":"telegram","account_id":"moltis-bot","chat_id":"262872984","chat_type":"private"}}
EOF
    )"
    if [[ -z "$posix_create_output" ]] && \
       ! grep -Fq 'message_received_direct_fastpath kind=skill_detail chat_id=262872984 token=skill_detail:moltis-update-dialog-20260424-live-05 skill=moltis-update-dialog-20260424-live-05' "$posix_create_audit" && \
       [[ ! -s "$posix_create_send_log" ]]; then
        test_pass
    else
        test_fail "MessageReceived guard must not collapse an exact Russian create-skill prompt into the skill-detail direct fastpath under POSIX locale"
    fi

    test_start "component_before_llm_guard_routes_exact_russian_create_prompt_into_native_crud_under_posix_locale"
    local before_llm_posix_create_output before_llm_posix_create_root
    before_llm_posix_create_root="$(secure_temp_dir telegram-safe-posix-before-create)"
    before_llm_posix_create_output="$(
        env PATH="$MINIMAL_PATH" \
            LANG= \
            LC_ALL=C \
            LC_CTYPE=POSIX \
            MOLTIS_RUNTIME_SKILLS_ROOT="$before_llm_posix_create_root" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,post-close-task-classifier,openclaw-improvement-learner,telegram-learner,telegram-chat-probe' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeLLMCall","session_key":"session:posix-before-create","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=prod | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Создай навык moltis-update-dialog-20260424-live-05 для отслеживания новых версий Moltis."}],"tool_count":37,"iteration":1}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_llm_posix_create_output" && \
       jq -e '.data.tool_count == 37' >/dev/null 2>&1 <<<"$before_llm_posix_create_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe skill runtime note")' >/dev/null 2>&1 <<<"$before_llm_posix_create_output" && \
       jq -e '.data.messages[1].content | contains("Telegram-safe skill-authoring contract")' >/dev/null 2>&1 <<<"$before_llm_posix_create_output" && \
       jq -e '.data.messages[2].content | contains("Telegram-safe sparse create-skill override")' >/dev/null 2>&1 <<<"$before_llm_posix_create_output" && \
       jq -e '([.data.messages[].content] | join("\n")) | contains("Telegram-safe skill-detail hard override") | not' >/dev/null 2>&1 <<<"$before_llm_posix_create_output" && \
       jq -e '.data.messages[-1].content == "Создай навык moltis-update-dialog-20260424-live-05 для отслеживания новых версий Moltis."' >/dev/null 2>&1 <<<"$before_llm_posix_create_output"; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must route an exact Russian create-skill prompt into native CRUD even when the runtime locale is POSIX"
    fi

    test_start "component_before_llm_guard_routes_exact_russian_update_prompt_into_native_crud_under_posix_locale"
    local before_llm_posix_update_output
    before_llm_posix_update_output="$(
        env PATH="$MINIMAL_PATH" \
            LANG= \
            LC_ALL=C \
            LC_CTYPE=POSIX \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,post-close-task-classifier,openclaw-improvement-learner,telegram-learner,telegram-chat-probe' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeLLMCall","session_key":"session:posix-before-update","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=prod | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Обнови навык codex-update: добавь дедупликацию по last_alert_fingerprint."}],"tool_count":37,"iteration":1}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_llm_posix_update_output" && \
       jq -e '.data.tool_count == 37' >/dev/null 2>&1 <<<"$before_llm_posix_update_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe skill runtime note")' >/dev/null 2>&1 <<<"$before_llm_posix_update_output" && \
       jq -e '.data.messages[1].content | contains("Telegram-safe skill-authoring contract")' >/dev/null 2>&1 <<<"$before_llm_posix_update_output" && \
       jq -e '([.data.messages[].content] | join("\n")) | contains("Telegram-safe skill-detail hard override") | not' >/dev/null 2>&1 <<<"$before_llm_posix_update_output" && \
       jq -e '([.data.messages[].content] | join("\n")) | contains("не чиню и не отлаживаю") | not' >/dev/null 2>&1 <<<"$before_llm_posix_update_output"; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must keep an exact Russian update-skill prompt on the native CRUD lane under POSIX locale"
    fi

    test_start "component_before_llm_guard_routes_exact_live_codex_update_duplicate_history_question_into_context_contract_under_posix_locale"
    local before_llm_posix_codex_context_duplicate_output
    before_llm_posix_codex_context_duplicate_output="$(
        env PATH="$MINIMAL_PATH" \
            LANG= \
            LC_ALL=C \
            LC_CTYPE=POSIX \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeLLMCall","session_key":"session:posix-codex-context-duplicate","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=prod | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Почему раньше ты присылал три одинаковых сообщения подряд про обновление Codex CLI?"}],"tool_count":37,"iteration":1}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_llm_posix_codex_context_duplicate_output" && \
       jq -e '.data.tool_count == 0' >/dev/null 2>&1 <<<"$before_llm_posix_codex_context_duplicate_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe codex-update hard override")' >/dev/null 2>&1 <<<"$before_llm_posix_codex_context_duplicate_output" && \
       jq -e '.data.messages[0].content | contains("После исправлений схема такая")' >/dev/null 2>&1 <<<"$before_llm_posix_codex_context_duplicate_output" && \
       jq -e '.data.messages[0].content | contains("last_alert_fingerprint")' >/dev/null 2>&1 <<<"$before_llm_posix_codex_context_duplicate_output" && \
       jq -e '.data.messages[0].content | test("показывает, есть ли новая стабильная версия|не наш[её]л точного подтвержд[её]нного runtime-навыка") | not' >/dev/null 2>&1 <<<"$before_llm_posix_codex_context_duplicate_output"; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must route the exact live duplicate-history Codex CLI question into the codex-update context contract under POSIX locale"
    fi

    test_start "component_before_llm_guard_routes_exact_live_codex_update_post_fix_question_into_context_contract_under_posix_locale"
    local before_llm_posix_codex_context_post_fix_output
    before_llm_posix_codex_context_post_fix_output="$(
        env PATH="$MINIMAL_PATH" \
            LANG= \
            LC_ALL=C \
            LC_CTYPE=POSIX \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeLLMCall","session_key":"session:posix-codex-context-post-fix","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=prod | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Что изменилось в навыке codex-update после починки?"}],"tool_count":37,"iteration":1}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_llm_posix_codex_context_post_fix_output" && \
       jq -e '.data.tool_count == 0' >/dev/null 2>&1 <<<"$before_llm_posix_codex_context_post_fix_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe codex-update hard override")' >/dev/null 2>&1 <<<"$before_llm_posix_codex_context_post_fix_output" && \
       jq -e '.data.messages[0].content | contains("После исправлений схема такая")' >/dev/null 2>&1 <<<"$before_llm_posix_codex_context_post_fix_output" && \
       jq -e '.data.messages[0].content | contains("last_alert_fingerprint")' >/dev/null 2>&1 <<<"$before_llm_posix_codex_context_post_fix_output" && \
       jq -e '.data.messages[0].content | test("показывает, есть ли новая стабильная версия|не наш[её]л точного подтвержд[её]нного runtime-навыка") | not' >/dev/null 2>&1 <<<"$before_llm_posix_codex_context_post_fix_output"; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must route the exact live post-fix Codex update question into the codex-update context contract under POSIX locale"
    fi

    test_start "component_before_llm_guard_hard_overrides_skill_visibility_queries_to_deterministic_runtime_list"
    local before_llm_skill_visibility_output
    before_llm_skill_visibility_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,post-close-task-classifier,telegram-learner' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:abv","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"base system"},{"role":"user","content":"А что у тебя с навыками/skills?"}],"tool_count":37,"iteration":1}}
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
{"event":"BeforeLLMCall","data":{"session_key":"session:abvh","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"base system"},{"role":"user","content":"Давай создадим навык codex-update-new"},{"role":"assistant","content":"Опиши навык подробнее."},{"role":"user","content":"А что у тебя с навыками/skills?"}],"tool_count":37,"iteration":1}}
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
{"event":"BeforeLLMCall","data":{"session_key":"session:abgi","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"base system"},{"role":"user","content":"А что у тебя с навыками/skills?"},{"role":"assistant","content":"Навыки (2): codex-update, telegram-learner."},{"role":"user","content":"Создай навык codex-update-new"}],"tool_count":37,"iteration":1}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_llm_skill_create_history_output" && \
       jq -e '.data.tool_count == 37' >/dev/null 2>&1 <<<"$before_llm_skill_create_history_output" && \
       jq -e '.data.messages | length == 7' >/dev/null 2>&1 <<<"$before_llm_skill_create_history_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe skill runtime note")' >/dev/null 2>&1 <<<"$before_llm_skill_create_history_output" && \
       jq -e '.data.messages[1].content | contains("Telegram-safe skill-authoring contract")' >/dev/null 2>&1 <<<"$before_llm_skill_create_history_output" && \
       jq -e '.data.messages[2].content | contains("Telegram-safe sparse create-skill override")' >/dev/null 2>&1 <<<"$before_llm_skill_create_history_output" && \
       jq -e '.data.messages[-1].content == "Создай навык codex-update-new"' >/dev/null 2>&1 <<<"$before_llm_skill_create_history_output" && \
       [[ ! -f "$before_llm_skill_create_history_file" ]]; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must classify sparse create from the latest user turn and keep it on the native skill-tool lane instead of reusing stale visibility history or writing repo-owned scaffolds"
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
{"event":"BeforeLLMCall","data":{"session_key":"session:skill-apply-hard","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Давай применим навык codex-update"}],"tool_count":37,"iteration":1}}
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

    test_start "component_before_llm_guard_hard_overrides_codex_update_queries_to_canonical_release_reply"
    local before_llm_codex_update_output
    before_llm_codex_update_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_CODEX_UPDATE_RELEASE_JSON='{"tag_name":"0.118.0","published_at":"2026-04-01T12:00:00Z"}' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:codex-update-hard","provider":"openai-codex","model":"gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Проверь последние релизы Codex и кратко скажи, есть ли новая стабильная версия"}],"tool_count":37,"iteration":1}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_llm_codex_update_output" && \
       jq -e '.data.tool_count == 0' >/dev/null 2>&1 <<<"$before_llm_codex_update_output" && \
       jq -e '.data.messages | length == 2' >/dev/null 2>&1 <<<"$before_llm_codex_update_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe codex-update hard override")' >/dev/null 2>&1 <<<"$before_llm_codex_update_output" && \
       jq -e '.data.messages[0].content | contains("версия 0.118.0")' >/dev/null 2>&1 <<<"$before_llm_codex_update_output" && \
       jq -e '.data.messages[0].content | contains("Дата публикации: 2026-04-01.")' >/dev/null 2>&1 <<<"$before_llm_codex_update_output" && \
       jq -e '.data.messages[1].content == "Верни в ответ ровно указанную в системном сообщении фразу. Не добавляй ничего."' >/dev/null 2>&1 <<<"$before_llm_codex_update_output"; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must short-circuit Codex release queries into a deterministic canonical reply instead of letting the model route them through Tavily"
    fi

    test_start "component_message_received_direct_fastpath_status_uses_channel_binding_and_rewrites_inbound_content"
    local ingress_status_tmp ingress_status_send_script ingress_status_log ingress_status_output
    ingress_status_tmp="$(secure_temp_dir telegram-safe-ingress-status)"
    ingress_status_send_script="$ingress_status_tmp/send.sh"
    ingress_status_log="$ingress_status_tmp/send.log"
    cat >"$ingress_status_send_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
chat_id=""
text=""
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
        *)
            shift
            ;;
    esac
done
printf 'chat_id=%s\ntext=%s\n' "$chat_id" "$text" >"$FASTPATH_LOG"
printf '{"ok":true}\n'
EOF
    chmod +x "$ingress_status_send_script"
    ingress_status_output="$(
        env PATH="$MINIMAL_PATH" \
            FASTPATH_LOG="$ingress_status_log" \
            MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
            MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$ingress_status_send_script" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageReceived","session_key":"session:ingress-status","content":"/status","channel":"telegram","channel_binding":{"surface":"telegram","session_kind":"channel","channel_type":"telegram","account_id":"moltis-bot","chat_id":"262872984","chat_type":"private","sender_id":"262872984"}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$ingress_status_output" && \
       jq -e '.data.content | contains("Верни пустую строку")' >/dev/null 2>&1 <<<"$ingress_status_output" && \
       jq -e '.data.content | contains("не вызывай инструменты")' >/dev/null 2>&1 <<<"$ingress_status_output" && \
       grep -Fq 'chat_id=262872984' "$ingress_status_log" && \
       grep -Fq 'text=Статус: Online' "$ingress_status_log" && \
       grep -Fq 'openai-codex::gpt-5.4' "$ingress_status_log"; then
        test_pass
    else
        test_fail "MessageReceived guard must direct-send canonical /status from channel_binding metadata and rewrite the inbound content into a no-tool terminalized turn"
    fi

    test_start "component_message_received_direct_fastpath_codex_update_scheduler_uses_channel_binding_and_rewrites_inbound_content"
    local ingress_codex_tmp ingress_codex_send_script ingress_codex_log ingress_codex_output
    ingress_codex_tmp="$(secure_temp_dir telegram-safe-ingress-codex)"
    ingress_codex_send_script="$ingress_codex_tmp/send.sh"
    ingress_codex_log="$ingress_codex_tmp/send.log"
    cat >"$ingress_codex_send_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
chat_id=""
text=""
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
        *)
            shift
            ;;
    esac
done
printf 'chat_id=%s\ntext=%s\n' "$chat_id" "$text" >"$FASTPATH_LOG"
printf '{"ok":true}\n'
EOF
    chmod +x "$ingress_codex_send_script"
    ingress_codex_output="$(
        env PATH="$MINIMAL_PATH" \
            FASTPATH_LOG="$ingress_codex_log" \
            MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
            MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$ingress_codex_send_script" \
            MOLTIS_CODEX_UPDATE_RELEASE_JSON='{"tag_name":"0.118.0","published_at":"2026-04-01T12:00:00Z"}' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageReceived","session_key":"session:ingress-codex","content":"А разве у тебя нет крона по проверке вышедшей новой версии Codex cli?","channel":"telegram","channel_binding":{"surface":"telegram","session_kind":"channel","channel_type":"telegram","account_id":"moltis-bot","chat_id":"262872984","chat_type":"private","sender_id":"262872984"}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$ingress_codex_output" && \
       jq -e '.data.content | contains("Верни пустую строку")' >/dev/null 2>&1 <<<"$ingress_codex_output" && \
       jq -e '.data.content | contains("не вызывай инструменты")' >/dev/null 2>&1 <<<"$ingress_codex_output" && \
       grep -Fq 'chat_id=262872984' "$ingress_codex_log" && \
       grep -Fq 'scheduler path для регулярной проверки обновлений Codex CLI' "$ingress_codex_log" && \
       grep -Fq 'не подтверждаю по памяти' "$ingress_codex_log"; then
        test_pass
    else
        test_fail "MessageReceived guard must direct-send codex-update scheduler guidance from channel_binding metadata and rewrite the inbound content into a no-tool terminalized turn"
    fi

    test_start "component_message_received_direct_fastpath_replay_does_not_double_send"
    local ingress_replay_tmp ingress_replay_send_script ingress_replay_log ingress_replay_first_output ingress_replay_second_output
    ingress_replay_tmp="$(secure_temp_dir telegram-safe-ingress-replay)"
    ingress_replay_send_script="$ingress_replay_tmp/send.sh"
    ingress_replay_log="$ingress_replay_tmp/send.log"
    cat >"$ingress_replay_send_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
chat_id=""
text=""
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
        *)
            shift
            ;;
    esac
done
{
    printf 'chat_id=%s\n' "$chat_id"
    printf 'text=%s\n' "$text"
} >>"$FASTPATH_LOG"
printf '{"ok":true}\n'
EOF
    chmod +x "$ingress_replay_send_script"
    ingress_replay_first_output="$(
        env PATH="$MINIMAL_PATH" \
            FASTPATH_LOG="$ingress_replay_log" \
            MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
            MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$ingress_replay_send_script" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageReceived","session_key":"session:ingress-replay","content":"/status","channel":"telegram","channel_binding":{"surface":"telegram","session_kind":"channel","channel_type":"telegram","account_id":"moltis-bot","chat_id":"262872984","chat_type":"private","sender_id":"262872984"}}
EOF
    )"
    ingress_replay_second_output="$(
        env PATH="$MINIMAL_PATH" \
            FASTPATH_LOG="$ingress_replay_log" \
            MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
            MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$ingress_replay_send_script" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageReceived","session_key":"session:ingress-replay","content":"/status","channel":"telegram","channel_binding":{"surface":"telegram","session_kind":"channel","channel_type":"telegram","account_id":"moltis-bot","chat_id":"262872984","chat_type":"private","sender_id":"262872984"}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$ingress_replay_first_output" && \
       jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$ingress_replay_second_output" && \
       [[ "$(grep -c '^chat_id=' "$ingress_replay_log")" -eq 1 ]]; then
        test_pass
    else
        test_fail "MessageReceived direct fastpath must stay idempotent for same-turn replay events and avoid duplicate Telegram sends"
    fi

    test_start "component_message_received_direct_fastpath_arms_delivery_suppression_for_late_message_sending_tail"
    local ingress_tail_tmp ingress_tail_send_script ingress_tail_log ingress_tail_output
    ingress_tail_tmp="$(secure_temp_dir telegram-safe-ingress-tail)"
    ingress_tail_send_script="$ingress_tail_tmp/send.sh"
    ingress_tail_log="$ingress_tail_tmp/send.log"
    cat >"$ingress_tail_send_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '{"ok":true}\n'
EOF
    chmod +x "$ingress_tail_send_script"
    env PATH="$MINIMAL_PATH" \
        FASTPATH_LOG="$ingress_tail_log" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
        MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$ingress_tail_send_script" \
        bash "$HOOK_SCRIPT" <<'EOF' >/dev/null
{"event":"MessageReceived","session_key":"session:ingress-tail","content":"/status","channel":"telegram","channel_binding":{"surface":"telegram","session_kind":"channel","channel_type":"telegram","account_id":"moltis-bot","chat_id":"262872984","chat_type":"private","sender_id":"262872984"}}
EOF
    ingress_tail_output="$(
        env PATH="$MINIMAL_PATH" \
            FASTPATH_LOG="$ingress_tail_log" \
            MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
            MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$ingress_tail_send_script" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageSending","session_id":"session:ingress-tail","data":{"account_id":"moltis-bot","to":"262872984","reply_to_message_id":991,"text":"📋 Activity log: should never leak after ingress fastpath"}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$ingress_tail_output" && \
       jq -e '.data.text == "NO_REPLY"' >/dev/null 2>&1 <<<"$ingress_tail_output"; then
        test_pass
    else
        test_fail "MessageReceived direct fastpath must arm delivery suppression so a late MessageSending tail is force-dropped"
    fi

    test_start "component_message_received_direct_fastpath_failed_send_falls_back_without_stale_state"
    local ingress_fail_tmp ingress_fail_send_script ingress_fail_output ingress_fail_before_llm_output
    ingress_fail_tmp="$(secure_temp_dir telegram-safe-ingress-fail)"
    ingress_fail_send_script="$ingress_fail_tmp/send.sh"
    cat >"$ingress_fail_send_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 1
EOF
    chmod +x "$ingress_fail_send_script"
    ingress_fail_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
            MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$ingress_fail_send_script" \
            MOLTIS_CODEX_UPDATE_RELEASE_JSON='{"tag_name":"0.118.0","published_at":"2026-04-01T12:00:00Z"}' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageReceived","session_key":"session:ingress-fail","content":"Проверь последние релизы Codex и кратко скажи, есть ли новая стабильная версия","channel":"telegram","channel_binding":{"surface":"telegram","session_kind":"channel","channel_type":"telegram","account_id":"moltis-bot","chat_id":"262872984","chat_type":"private","sender_id":"262872984"}}
EOF
    )"
    ingress_fail_before_llm_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
            MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$ingress_fail_send_script" \
            MOLTIS_CODEX_UPDATE_RELEASE_JSON='{"tag_name":"0.118.0","published_at":"2026-04-01T12:00:00Z"}' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:ingress-fail","provider":"openai-codex","model":"gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Проверь последние релизы Codex и кратко скажи, есть ли новая стабильная версия"}],"tool_count":37,"iteration":1}}
EOF
    )"
    if [[ -z "$ingress_fail_output" ]] && \
       jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$ingress_fail_before_llm_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe codex-update hard override")' >/dev/null 2>&1 <<<"$ingress_fail_before_llm_output"; then
        test_pass
    else
        test_fail "When MessageReceived direct send fails, the hook must leave no stale ingress state and fall back to the normal Telegram-safe BeforeLLMCall contract"
    fi

    test_start "component_message_received_direct_fastpath_ignores_foreign_telegram_binding"
    local ingress_foreign_tmp ingress_foreign_send_script ingress_foreign_log ingress_foreign_output
    ingress_foreign_tmp="$(secure_temp_dir telegram-safe-ingress-foreign)"
    ingress_foreign_send_script="$ingress_foreign_tmp/send.sh"
    ingress_foreign_log="$ingress_foreign_tmp/send.log"
    cat >"$ingress_foreign_send_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'unexpected\n' >>"$FASTPATH_LOG"
printf '{"ok":true}\n'
EOF
    chmod +x "$ingress_foreign_send_script"
    ingress_foreign_output="$(
        env PATH="$MINIMAL_PATH" \
            FASTPATH_LOG="$ingress_foreign_log" \
            MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
            MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$ingress_foreign_send_script" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageReceived","session_key":"session:ingress-foreign","content":"/status","channel":"telegram","channel_binding":{"surface":"telegram","session_kind":"channel","channel_type":"telegram","account_id":"foreign-bot","chat_id":"262872984","chat_type":"private","sender_id":"262872984"}}
EOF
    )"
    if [[ -z "$ingress_foreign_output" ]] && [[ ! -f "$ingress_foreign_log" ]]; then
        test_pass
    else
        test_fail "MessageReceived direct fastpath must stay scoped to the trusted Moltis Telegram binding and ignore foreign account_id values"
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
{"event":"BeforeLLMCall","data":{"session_key":"session:faststatus","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"/status"}],"tool_count":37,"iteration":1}}
EOF
    fastpath_status_status=$?
    set -e
    if [[ "$fastpath_status_status" -eq 0 ]] && \
       [[ ! -s "$fastpath_status_stderr" ]] && \
       jq -e '.action == "block"' >/dev/null 2>&1 "$fastpath_status_stdout" && \
       [[ -f "$fastpath_status_suppress_file" ]] && \
       grep -Fq $'\tstatus' "$fastpath_status_suppress_file" && \
       grep -Fq 'chat_id=262872984' "$fastpath_status_log" && \
       grep -Fq 'text=Статус: Online' "$fastpath_status_log" && \
       grep -Fq 'openai-codex::gpt-5.4' "$fastpath_status_log"; then
        test_pass
    else
        test_fail "Direct /status fastpath must stay handler-safe: send canonical text, return rc=0, leave only a delivery-suppression marker, and hard-block the ignored runtime LLM pass"
    fi

    test_start "component_before_llm_guard_direct_fastpaths_codex_update_when_enabled"
    local fastpath_codex_tmp fastpath_codex_send_script fastpath_codex_log fastpath_codex_stdout fastpath_codex_stderr fastpath_codex_status fastpath_codex_intent_dir fastpath_codex_session_suppress_file fastpath_codex_chat_suppress_file
    fastpath_codex_tmp="$(secure_temp_dir telegram-safe-fastpath-codex-update)"
    fastpath_codex_send_script="$fastpath_codex_tmp/send.sh"
    fastpath_codex_log="$fastpath_codex_tmp/send.log"
    fastpath_codex_intent_dir="$fastpath_codex_tmp/intent"
    fastpath_codex_session_suppress_file="$fastpath_codex_intent_dir/session_fastcodex.suppress"
    fastpath_codex_chat_suppress_file="$fastpath_codex_intent_dir/chat-262872984.suppress"
    cat >"$fastpath_codex_send_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
chat_id=""
text=""
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
        *)
            shift
            ;;
    esac
done
printf 'chat_id=%s\ntext=%s\n' "$chat_id" "$text" >"$FASTPATH_LOG"
printf '{"ok":true}\n'
EOF
    chmod +x "$fastpath_codex_send_script"
    fastpath_codex_stdout="$fastpath_codex_tmp/stdout.log"
    fastpath_codex_stderr="$fastpath_codex_tmp/stderr.log"
    set +e
    env PATH="$MINIMAL_PATH" \
        FASTPATH_LOG="$fastpath_codex_log" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$fastpath_codex_intent_dir" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$fastpath_codex_send_script" \
        MOLTIS_CODEX_UPDATE_RELEASE_JSON='{"tag_name":"0.118.0","published_at":"2026-04-01T12:00:00Z"}' \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_SCRIPT="$HOOK_SCRIPT" \
        bash "$HOOK_HANDLER" >"$fastpath_codex_stdout" 2>"$fastpath_codex_stderr" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:fastcodex","provider":"openai-codex","model":"gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"А разе у тебя нет крона по проверке вышедшей новой версии Codex cli?"}],"tool_count":37,"iteration":1}}
EOF
    fastpath_codex_status=$?
    set -e
    if [[ "$fastpath_codex_status" -eq 0 ]] && \
       [[ ! -s "$fastpath_codex_stderr" ]] && \
       jq -e '.action == "block"' >/dev/null 2>&1 "$fastpath_codex_stdout" && \
       [[ -f "$fastpath_codex_session_suppress_file" ]] && \
       [[ -f "$fastpath_codex_chat_suppress_file" ]] && \
       grep -Fq $'\tcodex_update:scheduler' "$fastpath_codex_session_suppress_file" && \
       grep -Fq $'\tcodex_update:scheduler' "$fastpath_codex_chat_suppress_file" && \
       grep -Fq 'chat_id=262872984' "$fastpath_codex_log" && \
       grep -Fq 'scheduler path для регулярной проверки обновлений Codex CLI' "$fastpath_codex_log" && \
       grep -Fq 'не подтверждаю по памяти' "$fastpath_codex_log" && \
       grep -Fq 'операторский/runtime check' "$fastpath_codex_log"; then
        test_pass
    else
        test_fail "When direct fastpath is enabled, codex-update scheduler turns must use the same Bot API delivery contract as the other live-proven Telegram-safe routes and arm same-turn suppression markers"
    fi

    test_start "component_before_llm_guard_prioritizes_codex_update_scheduler_over_implicit_skill_detail"
    local codex_skill_named_tmp codex_skill_named_send_script codex_skill_named_log codex_skill_named_stdout codex_skill_named_stderr codex_skill_named_status codex_skill_named_intent_dir codex_skill_named_session_suppress codex_skill_named_chat_suppress
    codex_skill_named_tmp="$(secure_temp_dir telegram-safe-codex-update-skill-named)"
    codex_skill_named_send_script="$codex_skill_named_tmp/send.sh"
    codex_skill_named_log="$codex_skill_named_tmp/send.log"
    codex_skill_named_intent_dir="$codex_skill_named_tmp/intent"
    codex_skill_named_session_suppress="$codex_skill_named_intent_dir/session_skillnamedcodex.suppress"
    codex_skill_named_chat_suppress="$codex_skill_named_intent_dir/chat-262872984.suppress"
    cat >"$codex_skill_named_send_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
chat_id=""
text=""
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
        *)
            shift
            ;;
    esac
done
printf 'chat_id=%s\ntext=%s\n' "$chat_id" "$text" >"$FASTPATH_LOG"
printf '{"ok":true}\n'
EOF
    chmod +x "$codex_skill_named_send_script"
    codex_skill_named_stdout="$codex_skill_named_tmp/stdout.log"
    codex_skill_named_stderr="$codex_skill_named_tmp/stderr.log"
    set +e
    env PATH="$MINIMAL_PATH" \
        FASTPATH_LOG="$codex_skill_named_log" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$codex_skill_named_intent_dir" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$codex_skill_named_send_script" \
        MOLTIS_CODEX_UPDATE_RELEASE_JSON='{"tag_name":"0.118.0","published_at":"2026-04-01T12:00:00Z"}' \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_SCRIPT="$HOOK_SCRIPT" \
        bash "$HOOK_HANDLER" >"$codex_skill_named_stdout" 2>"$codex_skill_named_stderr" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:skillnamedcodex","provider":"openai-codex","model":"gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Как часто навык codex-update автоматически проверяет обновления Codex CLI?"}],"tool_count":37,"iteration":1}}
EOF
    codex_skill_named_status=$?
    set -e
    if [[ "$codex_skill_named_status" -eq 0 ]] && \
       [[ ! -s "$codex_skill_named_stderr" ]] && \
       jq -e '.action == "block"' >/dev/null 2>&1 "$codex_skill_named_stdout" && \
       [[ -f "$codex_skill_named_session_suppress" ]] && \
       [[ -f "$codex_skill_named_chat_suppress" ]] && \
       grep -Fq $'\tcodex_update:scheduler' "$codex_skill_named_session_suppress" && \
       grep -Fq $'\tcodex_update:scheduler' "$codex_skill_named_chat_suppress" && \
       grep -Fq 'scheduler path для регулярной проверки обновлений Codex CLI' "$codex_skill_named_log" && \
       grep -Fq 'операторский/runtime check' "$codex_skill_named_log" && \
       ! grep -Fq 'показывает, есть ли новая стабильная версия Codex CLI' "$codex_skill_named_log"; then
        test_pass
    else
        test_fail "A scheduler question that explicitly names codex-update as a skill must still stay on the codex-update scheduler contract instead of drifting into implicit skill-detail routing"
    fi

    test_start "component_codex_update_direct_fastpath_routes_explicit_schedule_phrase_to_scheduler_contract"
    local codex_schedule_phrase_tmp codex_schedule_phrase_send_script codex_schedule_phrase_log codex_schedule_phrase_stdout codex_schedule_phrase_stderr
    local codex_schedule_phrase_status codex_schedule_phrase_intent_dir codex_schedule_phrase_session_suppress codex_schedule_phrase_chat_suppress
    codex_schedule_phrase_tmp="$(secure_temp_dir telegram-safe-codex-schedule-phrase)"
    codex_schedule_phrase_send_script="$codex_schedule_phrase_tmp/send.sh"
    codex_schedule_phrase_log="$codex_schedule_phrase_tmp/send.log"
    codex_schedule_phrase_intent_dir="$codex_schedule_phrase_tmp/intent"
    codex_schedule_phrase_session_suppress="$codex_schedule_phrase_intent_dir/session_codexschedulephrase.suppress"
    codex_schedule_phrase_chat_suppress="$codex_schedule_phrase_intent_dir/chat-262872985.suppress"
    cat >"$codex_schedule_phrase_send_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
chat_id=""
text=""
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
        *)
            shift
            ;;
    esac
done
printf 'chat_id=%s\ntext=%s\n' "$chat_id" "$text" >"$FASTPATH_LOG"
printf '{"ok":true}\n'
EOF
    chmod +x "$codex_schedule_phrase_send_script"
    codex_schedule_phrase_stdout="$codex_schedule_phrase_tmp/stdout.log"
    codex_schedule_phrase_stderr="$codex_schedule_phrase_tmp/stderr.log"
    set +e
    env PATH="$MINIMAL_PATH" \
        FASTPATH_LOG="$codex_schedule_phrase_log" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$codex_schedule_phrase_intent_dir" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$codex_schedule_phrase_send_script" \
        MOLTIS_CODEX_UPDATE_RELEASE_JSON='{"tag_name":"0.118.0","published_at":"2026-04-01T12:00:00Z"}' \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_SCRIPT="$HOOK_SCRIPT" \
        bash "$HOOK_HANDLER" >"$codex_schedule_phrase_stdout" 2>"$codex_schedule_phrase_stderr" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:codexschedulephrase","provider":"openai-codex","model":"gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872985 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"По какому расписанию сейчас работает навык codex-update?"}],"tool_count":37,"iteration":1}}
EOF
    codex_schedule_phrase_status=$?
    set -e
    if [[ "$codex_schedule_phrase_status" -eq 0 ]] && \
       [[ ! -s "$codex_schedule_phrase_stderr" ]] && \
       jq -e '.action == "block"' >/dev/null 2>&1 "$codex_schedule_phrase_stdout" && \
       [[ -f "$codex_schedule_phrase_session_suppress" ]] && \
       [[ -f "$codex_schedule_phrase_chat_suppress" ]] && \
       grep -Fq $'\tcodex_update:scheduler' "$codex_schedule_phrase_session_suppress" && \
       grep -Fq $'\tcodex_update:scheduler' "$codex_schedule_phrase_chat_suppress" && \
       grep -Fq 'scheduler path для регулярной проверки обновлений Codex CLI' "$codex_schedule_phrase_log" && \
       grep -Fq 'каждые 6 часов' "$codex_schedule_phrase_log" && \
       grep -Fq 'операторский/runtime check' "$codex_schedule_phrase_log" && \
       ! grep -Fq 'После исправлений схема такая' "$codex_schedule_phrase_log"; then
        test_pass
    else
        test_fail "An explicit schedule phrasing for codex-update must stay on the scheduler contract instead of drifting into the context reply"
    fi

    test_start "component_message_received_direct_fastpath_routes_live_frequency_phrase_to_codex_update_scheduler_contract"
    local codex_frequency_phrase_tmp codex_frequency_phrase_send_script codex_frequency_phrase_log codex_frequency_phrase_stdout codex_frequency_phrase_stderr
    local codex_frequency_phrase_status codex_frequency_phrase_intent_dir codex_frequency_phrase_session_suppress codex_frequency_phrase_chat_suppress
    codex_frequency_phrase_tmp="$(secure_temp_dir telegram-safe-codex-frequency-phrase)"
    codex_frequency_phrase_send_script="$codex_frequency_phrase_tmp/send.sh"
    codex_frequency_phrase_log="$codex_frequency_phrase_tmp/send.log"
    codex_frequency_phrase_intent_dir="$codex_frequency_phrase_tmp/intent"
    codex_frequency_phrase_session_suppress="$codex_frequency_phrase_intent_dir/session_codexfrequencyphrase.suppress"
    codex_frequency_phrase_chat_suppress="$codex_frequency_phrase_intent_dir/chat-262872985.suppress"
    cat >"$codex_frequency_phrase_send_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
chat_id=""
text=""
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
        *)
            shift
            ;;
    esac
done
printf 'chat_id=%s\ntext=%s\n' "$chat_id" "$text" >"$FASTPATH_LOG"
printf '{"ok":true}\n'
EOF
    chmod +x "$codex_frequency_phrase_send_script"
    codex_frequency_phrase_stdout="$codex_frequency_phrase_tmp/stdout.log"
    codex_frequency_phrase_stderr="$codex_frequency_phrase_tmp/stderr.log"
    set +e
    env PATH="$MINIMAL_PATH" \
        FASTPATH_LOG="$codex_frequency_phrase_log" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$codex_frequency_phrase_intent_dir" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$codex_frequency_phrase_send_script" \
        MOLTIS_CODEX_UPDATE_RELEASE_JSON='{"tag_name":"0.118.0","published_at":"2026-04-01T12:00:00Z"}' \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_SCRIPT="$HOOK_SCRIPT" \
        bash "$HOOK_HANDLER" >"$codex_frequency_phrase_stdout" 2>"$codex_frequency_phrase_stderr" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:codexfrequencyphrase","provider":"openai-codex","model":"gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872985 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Как часто обновляется навык codex-update?"}],"tool_count":37,"iteration":1}}
EOF
    codex_frequency_phrase_status=$?
    set -e
    if [[ "$codex_frequency_phrase_status" -eq 0 ]] && \
       [[ ! -s "$codex_frequency_phrase_stderr" ]] && \
       jq -e '.action == "block"' >/dev/null 2>&1 "$codex_frequency_phrase_stdout" && \
       [[ -f "$codex_frequency_phrase_session_suppress" ]] && \
       [[ -f "$codex_frequency_phrase_chat_suppress" ]] && \
       grep -Fq $'\tcodex_update:scheduler' "$codex_frequency_phrase_session_suppress" && \
       grep -Fq $'\tcodex_update:scheduler' "$codex_frequency_phrase_chat_suppress" && \
       grep -Fq 'scheduler path для регулярной проверки обновлений Codex CLI' "$codex_frequency_phrase_log" && \
       grep -Fq 'каждые 6 часов' "$codex_frequency_phrase_log" && \
       grep -Fq 'операторский/runtime check' "$codex_frequency_phrase_log" && \
       ! grep -Fq 'После исправлений схема такая' "$codex_frequency_phrase_log"; then
        test_pass
    else
        test_fail "The exact live frequency phrasing for codex-update must route to the scheduler contract instead of generic skill-detail or release wording"
    fi

    test_start "component_codex_update_direct_fastpath_handles_array_message_content_from_live_payload"
    local array_codex_tmp array_codex_send_script array_codex_log array_codex_stdout array_codex_stderr
    local array_codex_status array_codex_intent_dir array_codex_session_suppress_file array_codex_chat_suppress_file
    array_codex_tmp="$(secure_temp_dir telegram-safe-array-codex)"
    array_codex_send_script="$array_codex_tmp/send.sh"
    array_codex_log="$array_codex_tmp/send.log"
    array_codex_intent_dir="$array_codex_tmp/intent"
    array_codex_session_suppress_file="$array_codex_intent_dir/session_arraycodex.suppress"
    array_codex_chat_suppress_file="$array_codex_intent_dir/chat-262872984.suppress"
    cat >"$array_codex_send_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
chat_id=""
text=""
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
        *)
            shift
            ;;
    esac
done
printf 'chat_id=%s\ntext=%s\n' "$chat_id" "$text" >"$FASTPATH_LOG"
printf '{"ok":true}\n'
EOF
    chmod +x "$array_codex_send_script"
    array_codex_stdout="$array_codex_tmp/stdout.log"
    array_codex_stderr="$array_codex_tmp/stderr.log"
    set +e
    env PATH="$MINIMAL_PATH" \
        FASTPATH_LOG="$array_codex_log" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$array_codex_intent_dir" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$array_codex_send_script" \
        MOLTIS_CODEX_UPDATE_RELEASE_JSON='{"tag_name":"0.118.0","published_at":"2026-04-01T12:00:00Z"}' \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_SCRIPT="$HOOK_SCRIPT" \
        bash "$HOOK_HANDLER" >"$array_codex_stdout" 2>"$array_codex_stderr" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:arraycodex","provider":"openai-codex","model":"gpt-5.4","messages":[{"role":"system","content":[{"type":"input_text","text":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"}]},{"role":"user","content":[{"type":"input_text","text":"А разе у тебя нет крона по проверке вышедшей новой версии Codex cli?"}]}],"tool_count":37,"iteration":1}}
EOF
    array_codex_status=$?
    set -e
    if [[ "$array_codex_status" -eq 0 ]] && \
       [[ ! -s "$array_codex_stderr" ]] && \
       jq -e '.action == "block"' >/dev/null 2>&1 "$array_codex_stdout" && \
       [[ -f "$array_codex_session_suppress_file" ]] && \
       [[ -f "$array_codex_chat_suppress_file" ]] && \
       grep -Fq $'\tcodex_update:scheduler' "$array_codex_session_suppress_file" && \
       grep -Fq $'\tcodex_update:scheduler' "$array_codex_chat_suppress_file" && \
       grep -Fq 'chat_id=262872984' "$array_codex_log" && \
       grep -Fq 'scheduler path для регулярной проверки обновлений Codex CLI' "$array_codex_log" && \
       grep -Fq 'не подтверждаю по памяти' "$array_codex_log" && \
       grep -Fq 'операторский/runtime check' "$array_codex_log"; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must recover codex-update scheduler intent even when live runtime supplies messages[].content as input_text arrays"
    fi

    test_start "component_codex_update_direct_fastpath_preserves_terminal_fallback_state_if_suppression_is_lost"
    local fastpath_codex_recovery_tmp fastpath_codex_recovery_send_script fastpath_codex_recovery_log fastpath_codex_recovery_stdout fastpath_codex_recovery_stderr
    local fastpath_codex_recovery_status fastpath_codex_recovery_intent_dir fastpath_codex_recovery_session_suppress fastpath_codex_recovery_chat_suppress
    local fastpath_codex_recovery_intent_file fastpath_codex_recovery_terminal_file fastpath_codex_recovery_after_output fastpath_codex_recovery_tool_output fastpath_codex_recovery_send_output
    local fastpath_codex_recovery_intent_present_after_fastpath fastpath_codex_recovery_terminal_present_after_fastpath fastpath_codex_recovery_terminal_present_after_after
    fastpath_codex_recovery_tmp="$(secure_temp_dir telegram-safe-fastpath-codex-recovery)"
    fastpath_codex_recovery_send_script="$fastpath_codex_recovery_tmp/send.sh"
    fastpath_codex_recovery_log="$fastpath_codex_recovery_tmp/send.log"
    fastpath_codex_recovery_intent_dir="$fastpath_codex_recovery_tmp/intent"
    fastpath_codex_recovery_session_suppress="$fastpath_codex_recovery_intent_dir/session_fastcodexrecovery.suppress"
    fastpath_codex_recovery_chat_suppress="$fastpath_codex_recovery_intent_dir/chat-262872987.suppress"
    fastpath_codex_recovery_intent_file="$fastpath_codex_recovery_intent_dir/session_fastcodexrecovery.intent"
    fastpath_codex_recovery_terminal_file="$fastpath_codex_recovery_intent_dir/session_fastcodexrecovery.terminal"
    cat >"$fastpath_codex_recovery_send_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
chat_id=""
text=""
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
        *)
            shift
            ;;
    esac
done
printf 'chat_id=%s\ntext=%s\n' "$chat_id" "$text" >"$FASTPATH_LOG"
printf '{"ok":true}\n'
EOF
    chmod +x "$fastpath_codex_recovery_send_script"
    fastpath_codex_recovery_stdout="$fastpath_codex_recovery_tmp/stdout.log"
    fastpath_codex_recovery_stderr="$fastpath_codex_recovery_tmp/stderr.log"
    set +e
    env PATH="$MINIMAL_PATH" \
        FASTPATH_LOG="$fastpath_codex_recovery_log" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$fastpath_codex_recovery_intent_dir" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$fastpath_codex_recovery_send_script" \
        MOLTIS_CODEX_UPDATE_RELEASE_JSON='{"tag_name":"0.118.0","published_at":"2026-04-01T12:00:00Z"}' \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_SCRIPT="$HOOK_SCRIPT" \
        bash "$HOOK_HANDLER" >"$fastpath_codex_recovery_stdout" 2>"$fastpath_codex_recovery_stderr" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:fastcodexrecovery","provider":"openai-codex","model":"gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872987 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"А разе у тебя нет крона по проверке вышедшей новой версии Codex cli?"}],"tool_count":37,"iteration":1}}
EOF
    fastpath_codex_recovery_status=$?
    set -e
    if [[ -f "$fastpath_codex_recovery_intent_file" ]]; then
        fastpath_codex_recovery_intent_present_after_fastpath=true
    else
        fastpath_codex_recovery_intent_present_after_fastpath=false
    fi
    if [[ -f "$fastpath_codex_recovery_terminal_file" ]]; then
        fastpath_codex_recovery_terminal_present_after_fastpath=true
    else
        fastpath_codex_recovery_terminal_present_after_fastpath=false
    fi
    rm -f "$fastpath_codex_recovery_session_suppress" "$fastpath_codex_recovery_chat_suppress"
    fastpath_codex_recovery_after_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_CODEX_UPDATE_RELEASE_JSON='{"tag_name":"0.118.0","published_at":"2026-04-01T12:00:00Z"}' \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$fastpath_codex_recovery_intent_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"AfterLLMCall","session_key":"session:fastcodexrecovery","provider":"openai-codex","model":"gpt-5.4","text":"Проверил — и да, тут инструмент расписания реально сломан: на list он снова ответил missing action parameter.","tool_calls":[{"name":"cron","arguments":{"action":"list"}}]}
EOF
    )"
    if [[ -f "$fastpath_codex_recovery_terminal_file" ]]; then
        fastpath_codex_recovery_terminal_present_after_after=true
    else
        fastpath_codex_recovery_terminal_present_after_after=false
    fi
    fastpath_codex_recovery_tool_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_CODEX_UPDATE_RELEASE_JSON='{"tag_name":"0.118.0","published_at":"2026-04-01T12:00:00Z"}' \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$fastpath_codex_recovery_intent_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeToolCall","session_key":"session:fastcodexrecovery","provider":"openai-codex","model":"gpt-5.4","tool":"cron","arguments":{"action":"list"}}
EOF
    )"
    fastpath_codex_recovery_send_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_CODEX_UPDATE_RELEASE_JSON='{"tag_name":"0.118.0","published_at":"2026-04-01T12:00:00Z"}' \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$fastpath_codex_recovery_intent_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageSending","session_id":"session:fastcodexrecovery","data":{"account_id":"moltis-bot","to":"262872987","reply_to_message_id":1407,"text":"Да — есть.\n\nВ памяти у меня явно записано:\n«Ежедневно проверяю стабильные обновления Codex CLI и присылаю краткое уведомление только если вышла новая стабильная версия.»\n\n📋 Activity log\n• 🔧 cron\n• 💻 Running: `grep -RIn \"codex\\|Codex\\|cron\\|schedule\" /home/mol...`\n• 🧠 Searching memory...\n•   ❌ missing 'action' parameter\n•   ❌ missing 'query' parameter\n•   ❌ missing 'command' parameter"}}
EOF
    )"
    if [[ "$fastpath_codex_recovery_status" -eq 0 ]] && \
       [[ ! -s "$fastpath_codex_recovery_stderr" ]] && \
       jq -e '.action == "block"' >/dev/null 2>&1 "$fastpath_codex_recovery_stdout" && \
       [[ "$fastpath_codex_recovery_intent_present_after_fastpath" == true ]] && \
       [[ "$fastpath_codex_recovery_terminal_present_after_fastpath" == true ]] && \
       jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$fastpath_codex_recovery_after_output" && \
       jq -e '.data.text == ""' >/dev/null 2>&1 <<<"$fastpath_codex_recovery_after_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$fastpath_codex_recovery_after_output" && \
       [[ "$fastpath_codex_recovery_terminal_present_after_after" == true ]] && \
       jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$fastpath_codex_recovery_tool_output" && \
       jq -e '.data.tool == "exec"' >/dev/null 2>&1 <<<"$fastpath_codex_recovery_tool_output" && \
       jq -e '.data.arguments.command | contains("codex-update turn already resolved")' >/dev/null 2>&1 <<<"$fastpath_codex_recovery_tool_output" && \
       jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$fastpath_codex_recovery_send_output" && \
       jq -e '.data.text | contains("scheduler path для регулярной проверки обновлений Codex CLI")' >/dev/null 2>&1 <<<"$fastpath_codex_recovery_send_output" && \
       jq -e '.data.text | contains("не подтверждаю по памяти")' >/dev/null 2>&1 <<<"$fastpath_codex_recovery_send_output" && \
       jq -e '.data.text | contains("операторский/runtime check")' >/dev/null 2>&1 <<<"$fastpath_codex_recovery_send_output" && \
       jq -e '.data.text | test("Activity log|Searching memory|missing '\''action'\'' parameter|missing '\''query'\'' parameter|missing '\''command'\'' parameter|missing action parameter|missing query parameter|missing command parameter|в памяти у меня явно записано|Ежедневно проверяю стабильные обновления Codex CLI") | not' >/dev/null 2>&1 <<<"$fastpath_codex_recovery_send_output"; then
        test_pass
    else
        test_fail "Codex-update direct fastpath must keep terminal fallback state so a lost suppression marker still blanks the first late AfterLLMCall, blocks late tools, and rewrites memory-based false positives into the deterministic scheduler contract"
    fi

    test_start "component_before_llm_guard_keeps_status_precedence_over_codex_update_direct_fastpath_on_mixed_turn"
    local mixed_status_codex_tmp mixed_status_codex_send_script mixed_status_codex_log mixed_status_codex_stdout mixed_status_codex_stderr mixed_status_codex_status mixed_status_codex_intent_dir mixed_status_codex_session_suppress mixed_status_codex_chat_suppress
    mixed_status_codex_tmp="$(secure_temp_dir telegram-safe-mixed-status-codex)"
    mixed_status_codex_send_script="$mixed_status_codex_tmp/send.sh"
    mixed_status_codex_log="$mixed_status_codex_tmp/send.log"
    mixed_status_codex_intent_dir="$mixed_status_codex_tmp/intent"
    mixed_status_codex_session_suppress="$mixed_status_codex_intent_dir/session_mixedstatus.suppress"
    mixed_status_codex_chat_suppress="$mixed_status_codex_intent_dir/chat-262872984.suppress"
    cat >"$mixed_status_codex_send_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
chat_id=""
text=""
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
        *)
            shift
            ;;
    esac
done
printf 'chat_id=%s\ntext=%s\n' "$chat_id" "$text" >"$FASTPATH_LOG"
printf '{"ok":true}\n'
EOF
    chmod +x "$mixed_status_codex_send_script"
    mixed_status_codex_stdout="$mixed_status_codex_tmp/stdout.log"
    mixed_status_codex_stderr="$mixed_status_codex_tmp/stderr.log"
    set +e
    env PATH="$MINIMAL_PATH" \
        FASTPATH_LOG="$mixed_status_codex_log" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$mixed_status_codex_intent_dir" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$mixed_status_codex_send_script" \
        MOLTIS_CODEX_UPDATE_RELEASE_JSON='{"tag_name":"0.118.0","published_at":"2026-04-01T12:00:00Z"}' \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_SCRIPT="$HOOK_SCRIPT" \
        bash "$HOOK_HANDLER" >"$mixed_status_codex_stdout" 2>"$mixed_status_codex_stderr" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:mixedstatus","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"/status и заодно какая latest версия Codex CLI?"}],"tool_count":37,"iteration":1}}
EOF
    mixed_status_codex_status=$?
    set -e
    if [[ "$mixed_status_codex_status" -eq 0 ]] && \
       [[ ! -s "$mixed_status_codex_stderr" ]] && \
       jq -e '.action == "block"' >/dev/null 2>&1 "$mixed_status_codex_stdout" && \
       [[ -f "$mixed_status_codex_session_suppress" ]] && \
       [[ -f "$mixed_status_codex_chat_suppress" ]] && \
       grep -Fq $'\tstatus' "$mixed_status_codex_session_suppress" && \
       grep -Fq $'\tstatus' "$mixed_status_codex_chat_suppress" && \
       grep -Fq 'text=Статус: Online' "$mixed_status_codex_log" && \
       ! grep -Fq 'scheduler path для регулярной проверки обновлений Codex CLI' "$mixed_status_codex_log"; then
        test_pass
    else
        test_fail "Explicit /status must keep precedence over codex-update direct fastpath on mixed turns so the canonical status contract does not drift"
    fi

    test_start "component_codex_update_direct_fastpath_keeps_same_turn_runtime_tail_suppressed"
    local codex_direct_tail_tmp codex_direct_tail_send_script codex_direct_tail_log codex_direct_tail_stdout codex_direct_tail_stderr codex_direct_tail_status codex_direct_tail_intent_dir
    local codex_direct_tail_session_suppress codex_direct_tail_chat_suppress codex_direct_tail_repeat_before_output codex_direct_tail_tool_output codex_direct_tail_after_output codex_direct_tail_send_output
    codex_direct_tail_tmp="$(secure_temp_dir telegram-safe-codex-update-direct-tail)"
    codex_direct_tail_send_script="$codex_direct_tail_tmp/send.sh"
    codex_direct_tail_log="$codex_direct_tail_tmp/send.log"
    codex_direct_tail_intent_dir="$codex_direct_tail_tmp/intent"
    codex_direct_tail_session_suppress="$codex_direct_tail_intent_dir/session_codex-direct.suppress"
    codex_direct_tail_chat_suppress="$codex_direct_tail_intent_dir/chat-262872984.suppress"
    cat >"$codex_direct_tail_send_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
chat_id=""
text=""
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
        *)
            shift
            ;;
    esac
done
printf 'chat_id=%s\ntext=%s\n' "$chat_id" "$text" >"$FASTPATH_LOG"
printf '{"ok":true}\n'
EOF
    chmod +x "$codex_direct_tail_send_script"
    codex_direct_tail_stdout="$codex_direct_tail_tmp/stdout.log"
    codex_direct_tail_stderr="$codex_direct_tail_tmp/stderr.log"
    set +e
    env PATH="$MINIMAL_PATH" \
        FASTPATH_LOG="$codex_direct_tail_log" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$codex_direct_tail_intent_dir" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$codex_direct_tail_send_script" \
        MOLTIS_CODEX_UPDATE_RELEASE_JSON='{"tag_name":"0.118.0","published_at":"2026-04-01T12:00:00Z"}' \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_SCRIPT="$HOOK_SCRIPT" \
        bash "$HOOK_HANDLER" >"$codex_direct_tail_stdout" 2>"$codex_direct_tail_stderr" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:codex-direct","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"А разе у тебя нет крона по проверке вышедшей новой версии Codex cli?"}],"tool_count":37,"iteration":1}}
EOF
    codex_direct_tail_status=$?
    set -e
    codex_direct_tail_repeat_before_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$codex_direct_tail_intent_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:codex-direct","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"А разе у тебя нет крона по проверке вышедшей новой версии Codex cli?"}],"tool_count":37,"iteration":2}}
EOF
    )"
    codex_direct_tail_tool_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$codex_direct_tail_intent_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeToolCall","session_key":"session:codex-direct","provider":"openai-codex","model":"openai-codex::gpt-5.4","tool":"memory_search","arguments":{"query":"cron status"}}
EOF
    )"
    codex_direct_tail_after_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$codex_direct_tail_intent_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"AfterLLMCall","session_key":"session:codex-direct","provider":"openai-codex","model":"openai-codex::gpt-5.4","text":"Проверил — и да, тут инструмент расписания реально сломан: missing 'query' parameter.","tool_calls":[{"name":"memory_search","arguments":{"query":"cron status"}}]}
EOF
    )"
    codex_direct_tail_send_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$codex_direct_tail_intent_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageSending","session_id":"session:codex-direct","data":{"account_id":"moltis-bot","to":"262872984","reply_to_message_id":1450,"text":"Проверил — и да, тут инструмент расписания реально сломан: missing 'query' parameter."}}
EOF
    )"
    if [[ "$codex_direct_tail_status" -eq 0 ]] && \
       [[ ! -s "$codex_direct_tail_stderr" ]] && \
       jq -e '.action == "block"' >/dev/null 2>&1 "$codex_direct_tail_stdout" && \
       [[ -f "$codex_direct_tail_session_suppress" ]] && \
       [[ -f "$codex_direct_tail_chat_suppress" ]] && \
       jq -e '.action == "block"' >/dev/null 2>&1 <<<"$codex_direct_tail_repeat_before_output" && \
       jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$codex_direct_tail_tool_output" && \
       jq -e '.data.tool == "exec"' >/dev/null 2>&1 <<<"$codex_direct_tail_tool_output" && \
       jq -e '.data.arguments.command | contains("direct fastpath already handled this reply")' >/dev/null 2>&1 <<<"$codex_direct_tail_tool_output" && \
       jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$codex_direct_tail_after_output" && \
       jq -e '.data.text == ""' >/dev/null 2>&1 <<<"$codex_direct_tail_after_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$codex_direct_tail_after_output" && \
       jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$codex_direct_tail_send_output" && \
       jq -e '.data.text == "NO_REPLY"' >/dev/null 2>&1 <<<"$codex_direct_tail_send_output"; then
        test_pass
    else
        test_fail "Codex-update direct fastpath must keep the same turn terminal: repeat BeforeLLMCall, follow-up tools, late AfterLLMCall text, and final runtime delivery all stay suppressed"
    fi

    test_start "component_codex_update_terminalizes_blocked_followup_tool_turn_after_hard_override"
    local codex_terminal_tmp codex_terminal_intent_dir codex_terminal_marker codex_terminal_session_suppress codex_terminal_chat_suppress
    local codex_terminal_before_output codex_terminal_tool_output codex_terminal_repeat_before_output codex_terminal_after_output
    local codex_terminal_send_output codex_terminal_repeat_send_output codex_terminal_next_turn_output codex_terminal_reply_text
    local codex_terminal_marker_present_after_tool codex_terminal_suppress_absent_after_tool
    local codex_terminal_marker_cleared_after_send codex_terminal_session_suppress_present_after_send codex_terminal_chat_suppress_present_after_send
    local codex_terminal_session_suppress_cleared_on_next_turn codex_terminal_chat_suppress_cleared_on_next_turn codex_terminal_marker_absent_on_next_turn
    codex_terminal_tmp="$(secure_temp_dir telegram-safe-codex-update-terminal)"
    codex_terminal_intent_dir="$codex_terminal_tmp/intent"
    codex_terminal_marker="$codex_terminal_intent_dir/session_codex-terminal.terminal"
    codex_terminal_session_suppress="$codex_terminal_intent_dir/session_codex-terminal.suppress"
    codex_terminal_chat_suppress="$codex_terminal_intent_dir/chat-262872984.suppress"
    codex_terminal_reply_text='По проектному контракту у codex-update есть отдельный scheduler path для регулярной проверки обновлений Codex CLI каждые 6 часов. Но в Telegram-safe чате я не подтверждаю по памяти, что live cron сейчас действительно включён. Для точного статуса нужен операторский/runtime check, а не memory search.'
    codex_terminal_before_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_CODEX_UPDATE_RELEASE_JSON='{"tag_name":"0.118.0","published_at":"2026-04-01T12:00:00Z"}' \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$codex_terminal_intent_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:codex-terminal","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"А разе у тебя нет крона по проверке вышедшей новой версии Codex cli?"}],"tool_count":37,"iteration":1}}
EOF
    )"
    codex_terminal_tool_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_CODEX_UPDATE_RELEASE_JSON='{"tag_name":"0.118.0","published_at":"2026-04-01T12:00:00Z"}' \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$codex_terminal_intent_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeToolCall","session_key":"session:codex-terminal","provider":"openai-codex","model":"openai-codex::gpt-5.4","tool":"cron","arguments":{"action":"list"}}
EOF
    )"
    if [[ -f "$codex_terminal_marker" ]]; then
        codex_terminal_marker_present_after_tool=true
    else
        codex_terminal_marker_present_after_tool=false
    fi
    if [[ ! -e "$codex_terminal_session_suppress" ]]; then
        codex_terminal_suppress_absent_after_tool=true
    else
        codex_terminal_suppress_absent_after_tool=false
    fi
    codex_terminal_repeat_before_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_CODEX_UPDATE_RELEASE_JSON='{"tag_name":"0.118.0","published_at":"2026-04-01T12:00:00Z"}' \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$codex_terminal_intent_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:codex-terminal","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"}],"tool_count":37}}
EOF
    )"
    codex_terminal_after_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_CODEX_UPDATE_RELEASE_JSON='{"tag_name":"0.118.0","published_at":"2026-04-01T12:00:00Z"}' \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$codex_terminal_intent_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"AfterLLMCall","session_key":"session:codex-terminal","provider":"openai-codex","model":"openai-codex::gpt-5.4","text":"Проверил — и да, тут инструмент расписания реально сломан: на list он снова ответил missing action parameter.","tool_calls":[{"name":"cron","arguments":{"action":"list"}}]}
EOF
    )"
    codex_terminal_send_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_CODEX_UPDATE_RELEASE_JSON='{"tag_name":"0.118.0","published_at":"2026-04-01T12:00:00Z"}' \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$codex_terminal_intent_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageSending","session_id":"session:codex-terminal","data":{"account_id":"moltis-bot","to":"262872984","reply_to_message_id":1401,"text":""}}
EOF
    )"
    if [[ ! -e "$codex_terminal_marker" ]]; then
        codex_terminal_marker_cleared_after_send=true
    else
        codex_terminal_marker_cleared_after_send=false
    fi
    if [[ -f "$codex_terminal_session_suppress" ]]; then
        codex_terminal_session_suppress_present_after_send=true
    else
        codex_terminal_session_suppress_present_after_send=false
    fi
    if [[ -f "$codex_terminal_chat_suppress" ]]; then
        codex_terminal_chat_suppress_present_after_send=true
    else
        codex_terminal_chat_suppress_present_after_send=false
    fi
    codex_terminal_repeat_send_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_CODEX_UPDATE_RELEASE_JSON='{"tag_name":"0.118.0","published_at":"2026-04-01T12:00:00Z"}' \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$codex_terminal_intent_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageSending","session_id":"session:codex-terminal","data":{"account_id":"moltis-bot","to":"262872984","reply_to_message_id":1402,"text":"Проверил — и да, тут инструмент расписания реально сломан: на list он снова ответил missing action parameter."}}
EOF
    )"
    codex_terminal_next_turn_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_CODEX_UPDATE_RELEASE_JSON='{"tag_name":"0.118.0","published_at":"2026-04-01T12:00:00Z"}' \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$codex_terminal_intent_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:codex-terminal","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Привет"}],"tool_count":37}}
EOF
    )"
    if [[ ! -e "$codex_terminal_session_suppress" ]]; then
        codex_terminal_session_suppress_cleared_on_next_turn=true
    else
        codex_terminal_session_suppress_cleared_on_next_turn=false
    fi
    if [[ ! -e "$codex_terminal_chat_suppress" ]]; then
        codex_terminal_chat_suppress_cleared_on_next_turn=true
    else
        codex_terminal_chat_suppress_cleared_on_next_turn=false
    fi
    if [[ ! -e "$codex_terminal_marker" ]]; then
        codex_terminal_marker_absent_on_next_turn=true
    else
        codex_terminal_marker_absent_on_next_turn=false
    fi
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$codex_terminal_before_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe codex-update hard override")' >/dev/null 2>&1 <<<"$codex_terminal_before_output" && \
       jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$codex_terminal_tool_output" && \
       jq -e '.data.tool == "exec"' >/dev/null 2>&1 <<<"$codex_terminal_tool_output" && \
       jq -e '.data.arguments.command | contains("codex-update turn already resolved by the hard override")' >/dev/null 2>&1 <<<"$codex_terminal_tool_output" && \
       [[ "$codex_terminal_marker_present_after_tool" == true ]] && \
       [[ "$codex_terminal_suppress_absent_after_tool" == true ]] && \
       jq -e '.action == "block"' >/dev/null 2>&1 <<<"$codex_terminal_repeat_before_output" && \
       jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$codex_terminal_after_output" && \
       jq -e '.data.text == ""' >/dev/null 2>&1 <<<"$codex_terminal_after_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$codex_terminal_after_output" && \
       jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$codex_terminal_send_output" && \
       jq -e --arg reply "$codex_terminal_reply_text" '.data.text == $reply' >/dev/null 2>&1 <<<"$codex_terminal_send_output" && \
       jq -e '.data.account_id == "moltis-bot"' >/dev/null 2>&1 <<<"$codex_terminal_send_output" && \
       jq -e '.data.to == "262872984"' >/dev/null 2>&1 <<<"$codex_terminal_send_output" && \
       jq -e '.data.reply_to_message_id == 1401' >/dev/null 2>&1 <<<"$codex_terminal_send_output" && \
       [[ "$codex_terminal_marker_cleared_after_send" == true ]] && \
       [[ "$codex_terminal_session_suppress_present_after_send" == true ]] && \
       [[ "$codex_terminal_chat_suppress_present_after_send" == true ]] && \
       jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$codex_terminal_repeat_send_output" && \
       jq -e '.data.text == "NO_REPLY"' >/dev/null 2>&1 <<<"$codex_terminal_repeat_send_output" && \
       jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$codex_terminal_next_turn_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe codex-update terminal guard") | not' >/dev/null 2>&1 <<<"$codex_terminal_next_turn_output" && \
       [[ "$codex_terminal_session_suppress_cleared_on_next_turn" == true ]] && \
       [[ "$codex_terminal_chat_suppress_cleared_on_next_turn" == true ]] && \
       [[ "$codex_terminal_marker_absent_on_next_turn" == true ]]; then
        test_pass
    else
        test_fail "Codex-update hard override must terminalize a blocked same-turn tool follow-up: suppress the repeated LLM/tool churn, deliver the deterministic scheduler reply once, and drop any later dirty tail"
    fi

    test_start "component_codex_update_keeps_terminal_state_when_suppression_arm_fails"
    local codex_terminal_fail_tmp codex_terminal_fail_intent_dir codex_terminal_fail_marker codex_terminal_fail_intent_file
    local codex_terminal_fail_session_suppress codex_terminal_fail_chat_suppress codex_terminal_fail_before_output codex_terminal_fail_tool_output
    local codex_terminal_fail_send_output codex_terminal_fail_repeat_send_output codex_terminal_fail_stderr_log
    codex_terminal_fail_tmp="$(secure_temp_dir telegram-safe-codex-update-terminal-fail)"
    codex_terminal_fail_intent_dir="$codex_terminal_fail_tmp/intent"
    codex_terminal_fail_marker="$codex_terminal_fail_intent_dir/session_codex-terminal-fail.terminal"
    codex_terminal_fail_intent_file="$codex_terminal_fail_intent_dir/session_codex-terminal-fail.intent"
    codex_terminal_fail_session_suppress="$codex_terminal_fail_intent_dir/session_codex-terminal-fail.suppress"
    codex_terminal_fail_chat_suppress="$codex_terminal_fail_intent_dir/chat-262872985.suppress"
    codex_terminal_fail_stderr_log="$codex_terminal_fail_tmp/stderr.log"
    codex_terminal_fail_before_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_CODEX_UPDATE_RELEASE_JSON='{"tag_name":"0.118.0","published_at":"2026-04-01T12:00:00Z"}' \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$codex_terminal_fail_intent_dir" \
            bash "$HOOK_SCRIPT" 2>>"$codex_terminal_fail_stderr_log" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:codex-terminal-fail","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872985 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"А разе у тебя нет крона по проверке вышедшей новой версии Codex cli?"}],"tool_count":37,"iteration":1}}
EOF
    )"
    codex_terminal_fail_tool_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_CODEX_UPDATE_RELEASE_JSON='{"tag_name":"0.118.0","published_at":"2026-04-01T12:00:00Z"}' \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$codex_terminal_fail_intent_dir" \
            bash "$HOOK_SCRIPT" 2>>"$codex_terminal_fail_stderr_log" <<'EOF'
{"event":"BeforeToolCall","session_key":"session:codex-terminal-fail","provider":"openai-codex","model":"openai-codex::gpt-5.4","tool":"cron","arguments":{"action":"list"}}
EOF
    )"
    mkdir -p "$codex_terminal_fail_session_suppress" "$codex_terminal_fail_chat_suppress"
    codex_terminal_fail_send_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_CODEX_UPDATE_RELEASE_JSON='{"tag_name":"0.118.0","published_at":"2026-04-01T12:00:00Z"}' \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$codex_terminal_fail_intent_dir" \
            bash "$HOOK_SCRIPT" 2>>"$codex_terminal_fail_stderr_log" <<'EOF'
{"event":"MessageSending","session_id":"session:codex-terminal-fail","data":{"account_id":"moltis-bot","to":"262872985","reply_to_message_id":1501,"text":""}}
EOF
    )"
    codex_terminal_fail_repeat_send_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_CODEX_UPDATE_RELEASE_JSON='{"tag_name":"0.118.0","published_at":"2026-04-01T12:00:00Z"}' \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$codex_terminal_fail_intent_dir" \
            bash "$HOOK_SCRIPT" 2>>"$codex_terminal_fail_stderr_log" <<'EOF'
{"event":"MessageSending","session_id":"session:codex-terminal-fail","data":{"account_id":"moltis-bot","to":"262872985","reply_to_message_id":1502,"text":"Проверил — и да, тут инструмент расписания реально сломан: на list он снова ответил missing action parameter."}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$codex_terminal_fail_before_output" && \
       jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$codex_terminal_fail_tool_output" && \
       jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$codex_terminal_fail_send_output" && \
       jq -e --arg reply "$codex_terminal_reply_text" '.data.text == $reply' >/dev/null 2>&1 <<<"$codex_terminal_fail_send_output" && \
       [[ -f "$codex_terminal_fail_marker" ]] && \
       [[ -f "$codex_terminal_fail_intent_file" ]] && \
       [[ ! -s "$codex_terminal_fail_stderr_log" ]] && \
       jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$codex_terminal_fail_repeat_send_output" && \
       jq -e --arg reply "$codex_terminal_reply_text" '.data.text == $reply' >/dev/null 2>&1 <<<"$codex_terminal_fail_repeat_send_output"; then
        test_pass
    else
        test_fail "Codex-update terminalization must fail closed when suppression cannot be armed: keep the terminal marker and intent, continue rewriting later dirty tails to the deterministic scheduler reply, and stay silent on stderr"
    fi

    test_start "component_codex_update_repeat_guard_survives_terminal_marker_write_failure"
    local codex_terminal_marker_fail_tmp codex_terminal_marker_fail_intent_dir codex_terminal_marker_fail_marker
    local codex_terminal_marker_fail_before_output codex_terminal_marker_fail_tool_output codex_terminal_marker_fail_repeat_before_output codex_terminal_marker_fail_stderr_log
    codex_terminal_marker_fail_tmp="$(secure_temp_dir telegram-safe-codex-update-marker-fail)"
    codex_terminal_marker_fail_intent_dir="$codex_terminal_marker_fail_tmp/intent"
    codex_terminal_marker_fail_marker="$codex_terminal_marker_fail_intent_dir/session_codex-terminal-marker-fail.terminal"
    codex_terminal_marker_fail_stderr_log="$codex_terminal_marker_fail_tmp/stderr.log"
    codex_terminal_marker_fail_before_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_CODEX_UPDATE_RELEASE_JSON='{"tag_name":"0.118.0","published_at":"2026-04-01T12:00:00Z"}' \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$codex_terminal_marker_fail_intent_dir" \
            bash "$HOOK_SCRIPT" 2>>"$codex_terminal_marker_fail_stderr_log" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:codex-terminal-marker-fail","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872986 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"А разе у тебя нет крона по проверке вышедшей новой версии Codex cli?"}],"tool_count":37,"iteration":1}}
EOF
    )"
    mkdir -p "$codex_terminal_marker_fail_marker"
    codex_terminal_marker_fail_tool_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_CODEX_UPDATE_RELEASE_JSON='{"tag_name":"0.118.0","published_at":"2026-04-01T12:00:00Z"}' \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$codex_terminal_marker_fail_intent_dir" \
            bash "$HOOK_SCRIPT" 2>>"$codex_terminal_marker_fail_stderr_log" <<'EOF'
{"event":"BeforeToolCall","session_key":"session:codex-terminal-marker-fail","provider":"openai-codex","model":"openai-codex::gpt-5.4","tool":"cron","arguments":{"action":"list"}}
EOF
    )"
    codex_terminal_marker_fail_repeat_before_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_CODEX_UPDATE_RELEASE_JSON='{"tag_name":"0.118.0","published_at":"2026-04-01T12:00:00Z"}' \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$codex_terminal_marker_fail_intent_dir" \
            bash "$HOOK_SCRIPT" 2>>"$codex_terminal_marker_fail_stderr_log" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:codex-terminal-marker-fail","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872986 | data_dir=/home/moltis/.moltis"}],"tool_count":37}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$codex_terminal_marker_fail_before_output" && \
       jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$codex_terminal_marker_fail_tool_output" && \
       jq -e '.data.tool == "exec"' >/dev/null 2>&1 <<<"$codex_terminal_marker_fail_tool_output" && \
       jq -e '.action == "block"' >/dev/null 2>&1 <<<"$codex_terminal_marker_fail_repeat_before_output" && \
       [[ ! -s "$codex_terminal_marker_fail_stderr_log" ]] && \
       jq -e '.data | not' >/dev/null 2>&1 <<<"$codex_terminal_marker_fail_repeat_before_output"; then
        test_pass
    else
        test_fail "Codex-update repeat guard must still terminalize the blocked follow-up even when the .terminal marker itself cannot be written, and it must stay silent on stderr"
    fi

    test_start "component_codex_update_terminal_state_does_not_leak_into_fresh_same_subject_turn"
    local codex_terminal_fail_stored_epoch codex_terminal_fail_stored_intent codex_terminal_fail_stored_fingerprint codex_terminal_fresh_turn_output
    IFS=$'\t' read -r codex_terminal_fail_stored_epoch codex_terminal_fail_stored_intent codex_terminal_fail_stored_fingerprint <"$codex_terminal_fail_intent_file"
    printf '%s\t%s\t%s\n' "$(( $(date +%s) - 120 ))" "$codex_terminal_fail_stored_intent" "$codex_terminal_fail_stored_fingerprint" >"$codex_terminal_fail_intent_file"
    codex_terminal_fresh_turn_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_CODEX_UPDATE_RELEASE_JSON='{"tag_name":"0.118.0","published_at":"2026-04-01T12:00:00Z"}' \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_TERMINAL_REPEAT_WINDOW_SEC=30 \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$codex_terminal_fail_intent_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:codex-terminal-fail","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872985 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"А разе у тебя нет крона по проверке вышедшей новой версии Codex cli?"}],"tool_count":37,"iteration":1}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$codex_terminal_fresh_turn_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe codex-update hard override")' >/dev/null 2>&1 <<<"$codex_terminal_fresh_turn_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe codex-update terminal guard") | not' >/dev/null 2>&1 <<<"$codex_terminal_fresh_turn_output" && \
       [[ ! -e "$codex_terminal_fail_marker" ]]; then
        test_pass
    else
        test_fail "Codex-update terminal state must not bleed into a fresh later codex-update user turn after fail-closed recovery preserved marker+intent"
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
{"event":"BeforeLLMCall","data":{"session_key":"session:fastvis","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"А что у тебя с навыками/skills?"}],"tool_count":37,"iteration":1}}
EOF
    fastpath_visibility_status=$?
    set -e
    if [[ "$fastpath_visibility_status" -eq 0 ]] && \
       [[ ! -s "$fastpath_visibility_stderr" ]] && \
       jq -e '.action == "block"' >/dev/null 2>&1 "$fastpath_visibility_stdout" && \
       [[ -f "$fastpath_visibility_suppress_file" ]] && \
       grep -Fq $'\tskill_visibility' "$fastpath_visibility_suppress_file" && \
       grep -Fq 'chat_id=262872984' "$fastpath_visibility_log" && \
       grep -Fq 'text=Навыки (3): codex-update, post-close-task-classifier, telegram-learner.' "$fastpath_visibility_log"; then
        test_pass
    else
        test_fail "Direct skill-visibility fastpath must stay handler-safe: send the deterministic runtime list, return rc=0, store only a delivery-suppression marker, and hard-block the ignored runtime LLM pass"
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
{"event":"BeforeLLMCall","data":{"session_key":"session:fasttemplate","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"assistant","content":"Сначала покажу шаблон навыка."},{"role":"user","content":"У тебя должен быть темплейт"}],"tool_count":37,"iteration":1}}
EOF
    fastpath_template_status=$?
    set -e
    if [[ "$fastpath_template_status" -eq 0 ]] && \
       [[ ! -s "$fastpath_template_stderr" ]] && \
       jq -e '.action == "block"' >/dev/null 2>&1 "$fastpath_template_stdout" && \
       [[ -f "$fastpath_template_suppress_file" ]] && \
       grep -Fq $'\tskill_template' "$fastpath_template_suppress_file" && \
       grep -Fq 'chat_id=262872984' "$fastpath_template_log" && \
       grep -Fq 'text=Канонический минимальный шаблон навыка:' "$fastpath_template_log"; then
        test_pass
    else
        test_fail "Direct skill-template fastpath must stay handler-safe: send the canonical scaffold, return rc=0, leave only a delivery-suppression marker, and hard-block the ignored runtime LLM pass"
    fi

    test_start "component_before_llm_guard_direct_fastpaths_skill_detail_via_bot_send_when_enabled"
    local fastpath_skill_detail_tmp fastpath_skill_detail_send_script fastpath_skill_detail_log fastpath_skill_detail_stdout fastpath_skill_detail_stderr fastpath_skill_detail_status fastpath_skill_detail_intent_dir fastpath_skill_detail_suppress_file fastpath_skill_detail_runtime_root fastpath_skill_detail_fakebin
    fastpath_skill_detail_tmp="$(secure_temp_dir telegram-safe-fastpath-skill-detail)"
    fastpath_skill_detail_send_script="$fastpath_skill_detail_tmp/send.sh"
    fastpath_skill_detail_log="$fastpath_skill_detail_tmp/send.log"
    fastpath_skill_detail_intent_dir="$fastpath_skill_detail_tmp/intent"
    fastpath_skill_detail_suppress_file="$fastpath_skill_detail_intent_dir/session_fastdetail.suppress"
    fastpath_skill_detail_runtime_root="$fastpath_skill_detail_tmp/runtime-skills"
    fastpath_skill_detail_fakebin="$fastpath_skill_detail_tmp/fakebin"
    mkdir -p "$fastpath_skill_detail_runtime_root/telegram-learner" "$fastpath_skill_detail_fakebin"
    cp "$PROJECT_ROOT/skills/telegram-learner/SKILL.md" "$fastpath_skill_detail_runtime_root/telegram-learner/SKILL.md"
    cat >"$fastpath_skill_detail_fakebin/python3" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
    chmod +x "$fastpath_skill_detail_fakebin/python3"
    cat >"$fastpath_skill_detail_send_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
chat_id=""
text=""
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
        *)
            shift
            ;;
    esac
done
printf 'chat_id=%s\ntext=%s\n' "$chat_id" "$text" >"$FASTPATH_LOG"
printf '{"ok":true}\n'
EOF
    chmod +x "$fastpath_skill_detail_send_script"
    fastpath_skill_detail_stdout="$fastpath_skill_detail_tmp/stdout.log"
    fastpath_skill_detail_stderr="$fastpath_skill_detail_tmp/stderr.log"
    set +e
    env PATH="$fastpath_skill_detail_fakebin:$MINIMAL_PATH" \
        FASTPATH_LOG="$fastpath_skill_detail_log" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
        MOLTIS_RUNTIME_SKILLS_ROOT="$fastpath_skill_detail_runtime_root" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$fastpath_skill_detail_intent_dir" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$fastpath_skill_detail_send_script" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_SCRIPT="$HOOK_SCRIPT" \
        bash "$HOOK_HANDLER" >"$fastpath_skill_detail_stdout" 2>"$fastpath_skill_detail_stderr" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:fastdetail","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Расскажи мне про навык telegram-lerner"}],"tool_count":37,"iteration":1}}
EOF
    fastpath_skill_detail_status=$?
    set -e
    if [[ "$fastpath_skill_detail_status" -eq 0 ]] && \
       [[ ! -s "$fastpath_skill_detail_stderr" ]] && \
       jq -e '.action == "block"' >/dev/null 2>&1 "$fastpath_skill_detail_stdout" && \
       [[ -f "$fastpath_skill_detail_suppress_file" ]] && \
       grep -Fq $'\tskill_detail:telegram-learner' "$fastpath_skill_detail_suppress_file" && \
       grep -Fq 'chat_id=262872984' "$fastpath_skill_detail_log" && \
       grep -Fq 'telegram-learner' "$fastpath_skill_detail_log" && \
       grep -Fq '@tsingular' "$fastpath_skill_detail_log" && \
       grep -Fq 'Полезен, когда нужно быстро собрать новые практики' "$fastpath_skill_detail_log" && \
       grep -Fq 'official docs, релизам, issues и официальному репозиторию' "$fastpath_skill_detail_log" && \
       grep -Fq 'В Telegram-safe чате даю только краткое описание' "$fastpath_skill_detail_log" && \
       ! grep -Eq 'Похоже, ты имеешь в виду|Когда использовать:|Workflow:|Telegram-safe DM|Обычно он работает по шагам:|Сейчас в описании навыка указаны источники:' "$fastpath_skill_detail_log"; then
        test_pass
    else
        test_fail "Direct skill-detail fastpath must resolve the runtime skill, answer from SKILL.md, and leave only a same-turn delivery-suppression marker"
    fi

    test_start "component_before_llm_guard_direct_fastpaths_live_codex_update_skill_detail_when_last_system_is_datetime"
    local fastpath_skill_detail_live_tmp fastpath_skill_detail_live_send_script fastpath_skill_detail_live_log fastpath_skill_detail_live_stdout fastpath_skill_detail_live_stderr fastpath_skill_detail_live_status fastpath_skill_detail_live_intent_dir fastpath_skill_detail_live_suppress_file fastpath_skill_detail_live_runtime_root fastpath_skill_detail_live_fakebin
    fastpath_skill_detail_live_tmp="$(secure_temp_dir telegram-safe-fastpath-skill-detail-live)"
    fastpath_skill_detail_live_send_script="$fastpath_skill_detail_live_tmp/send.sh"
    fastpath_skill_detail_live_log="$fastpath_skill_detail_live_tmp/send.log"
    fastpath_skill_detail_live_intent_dir="$fastpath_skill_detail_live_tmp/intent"
    fastpath_skill_detail_live_suppress_file="$fastpath_skill_detail_live_intent_dir/session_livecodexdetail.suppress"
    fastpath_skill_detail_live_runtime_root="$fastpath_skill_detail_live_tmp/runtime-skills"
    fastpath_skill_detail_live_fakebin="$fastpath_skill_detail_live_tmp/fakebin"
    mkdir -p "$fastpath_skill_detail_live_runtime_root/codex-update" "$fastpath_skill_detail_live_fakebin"
    cp "$PROJECT_ROOT/skills/codex-update/SKILL.md" "$fastpath_skill_detail_live_runtime_root/codex-update/SKILL.md"
    cat >"$fastpath_skill_detail_live_fakebin/python3" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
    chmod +x "$fastpath_skill_detail_live_fakebin/python3"
    cat >"$fastpath_skill_detail_live_send_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
chat_id=""
text=""
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
        *)
            shift
            ;;
    esac
done
printf 'chat_id=%s\ntext=%s\n' "$chat_id" "$text" >"$FASTPATH_LOG"
printf '{"ok":true}\n'
EOF
    chmod +x "$fastpath_skill_detail_live_send_script"
    fastpath_skill_detail_live_stdout="$fastpath_skill_detail_live_tmp/stdout.log"
    fastpath_skill_detail_live_stderr="$fastpath_skill_detail_live_tmp/stderr.log"
    set +e
    env PATH="$fastpath_skill_detail_live_fakebin:$MINIMAL_PATH" \
        FASTPATH_LOG="$fastpath_skill_detail_live_log" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
        MOLTIS_RUNTIME_SKILLS_ROOT="$fastpath_skill_detail_live_runtime_root" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$fastpath_skill_detail_live_intent_dir" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$fastpath_skill_detail_live_send_script" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_SCRIPT="$HOOK_SCRIPT" \
        bash "$HOOK_HANDLER" >"$fastpath_skill_detail_live_stdout" 2>"$fastpath_skill_detail_live_stderr" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:livecodexdetail","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=4c3734b76ac1 | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"assistant","content":"Да. По сути уже разобрался: причина почти наверняка в том, что уведомление не дедуплицируется."},{"role":"system","content":"The current user datetime is 2026-04-23 18:09:48 MSK."},{"role":"user","content":"Открой навык codex-update и проверь, есть ли в нём дедупликация last_announced_version. Ничего не меняй, ответь кратко."}],"tool_count":55,"iteration":1}}
EOF
    fastpath_skill_detail_live_status=$?
    set -e
    if [[ "$fastpath_skill_detail_live_status" -eq 0 ]] && \
       [[ ! -s "$fastpath_skill_detail_live_stderr" ]] && \
       jq -e '.action == "block"' >/dev/null 2>&1 "$fastpath_skill_detail_live_stdout" && \
       [[ -f "$fastpath_skill_detail_live_suppress_file" ]] && \
       grep -Fq $'\tskill_detail:codex-update' "$fastpath_skill_detail_live_suppress_file" && \
       grep -Fq 'chat_id=262872984' "$fastpath_skill_detail_live_log" && \
       grep -Fq 'codex-update' "$fastpath_skill_detail_live_log" && \
       grep -Fq 'не вижу явного упоминания `last_announced_version`' "$fastpath_skill_detail_live_log" && \
       ! grep -Eq "read_skill|missing 'name'|Activity log|/home/moltis" "$fastpath_skill_detail_live_log"; then
        test_pass
    else
        test_fail "Live-shaped codex-update skill-detail prompts must use direct text-only skill detail fastpath even when the latest system message is only datetime"
    fi

    test_start "component_before_llm_guard_skill_detail_direct_fastpath_falls_back_to_modify_when_suppression_cannot_be_armed"
    local fastpath_skill_detail_armfail_tmp fastpath_skill_detail_armfail_send_script fastpath_skill_detail_armfail_log fastpath_skill_detail_armfail_stdout fastpath_skill_detail_armfail_stderr fastpath_skill_detail_armfail_status fastpath_skill_detail_armfail_intent_dir fastpath_skill_detail_armfail_runtime_root fastpath_skill_detail_armfail_fakebin fastpath_skill_detail_armfail_output
    fastpath_skill_detail_armfail_tmp="$(secure_temp_dir telegram-safe-fastpath-skill-detail-armfail)"
    fastpath_skill_detail_armfail_send_script="$fastpath_skill_detail_armfail_tmp/send.sh"
    fastpath_skill_detail_armfail_log="$fastpath_skill_detail_armfail_tmp/send.log"
    fastpath_skill_detail_armfail_intent_dir="$fastpath_skill_detail_armfail_tmp/not-a-dir"
    fastpath_skill_detail_armfail_runtime_root="$fastpath_skill_detail_armfail_tmp/runtime-skills"
    fastpath_skill_detail_armfail_fakebin="$fastpath_skill_detail_armfail_tmp/fakebin"
    mkdir -p "$fastpath_skill_detail_armfail_runtime_root/telegram-learner" "$fastpath_skill_detail_armfail_fakebin"
    cp "$PROJECT_ROOT/skills/telegram-learner/SKILL.md" "$fastpath_skill_detail_armfail_runtime_root/telegram-learner/SKILL.md"
    printf 'blocked\n' >"$fastpath_skill_detail_armfail_intent_dir"
    cat >"$fastpath_skill_detail_armfail_fakebin/python3" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
    chmod +x "$fastpath_skill_detail_armfail_fakebin/python3"
    cat >"$fastpath_skill_detail_armfail_send_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'unexpected-direct-send\n' >>"$FASTPATH_LOG"
printf '{"ok":true}\n'
EOF
    chmod +x "$fastpath_skill_detail_armfail_send_script"
    fastpath_skill_detail_armfail_stdout="$fastpath_skill_detail_armfail_tmp/stdout.log"
    fastpath_skill_detail_armfail_stderr="$fastpath_skill_detail_armfail_tmp/stderr.log"
    set +e
    env PATH="$fastpath_skill_detail_armfail_fakebin:$MINIMAL_PATH" \
        FASTPATH_LOG="$fastpath_skill_detail_armfail_log" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
        MOLTIS_RUNTIME_SKILLS_ROOT="$fastpath_skill_detail_armfail_runtime_root" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$fastpath_skill_detail_armfail_intent_dir" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$fastpath_skill_detail_armfail_send_script" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_SCRIPT="$HOOK_SCRIPT" \
        bash "$HOOK_HANDLER" >"$fastpath_skill_detail_armfail_stdout" 2>"$fastpath_skill_detail_armfail_stderr" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:fastdetail-armfail","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Расскажи мне про навык telegram-lerner"}],"tool_count":37,"iteration":1}}
EOF
    fastpath_skill_detail_armfail_status=$?
    set -e
    fastpath_skill_detail_armfail_output="$(cat "$fastpath_skill_detail_armfail_stdout")"
    if [[ "$fastpath_skill_detail_armfail_status" -eq 0 ]] && \
       [[ ! -s "$fastpath_skill_detail_armfail_stderr" ]] && \
       [[ ! -f "$fastpath_skill_detail_armfail_log" ]] && \
       jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$fastpath_skill_detail_armfail_output" && \
       jq -e '.data.tool_count == 0' >/dev/null 2>&1 <<<"$fastpath_skill_detail_armfail_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe skill-detail hard override")' >/dev/null 2>&1 <<<"$fastpath_skill_detail_armfail_output" && \
       jq -e '.data.messages[0].content | contains("telegram-learner")' >/dev/null 2>&1 <<<"$fastpath_skill_detail_armfail_output" && \
       jq -e '.data.messages[0].content | contains("@tsingular")' >/dev/null 2>&1 <<<"$fastpath_skill_detail_armfail_output" && \
       jq -e '.data.messages[0].content | contains("official docs, релизам, issues и официальному репозиторию")' >/dev/null 2>&1 <<<"$fastpath_skill_detail_armfail_output" && \
       jq -e '.data.messages[1].content == "Верни в ответ ровно указанную в системном сообщении фразу. Не добавляй ничего."' >/dev/null 2>&1 <<<"$fastpath_skill_detail_armfail_output"; then
        test_pass
    else
        test_fail "When suppression cannot be armed, direct skill-detail fastpath must not send directly and must fall back to the deterministic text-only modify path"
    fi

    test_start "component_before_llm_guard_direct_fastpaths_skill_detail_after_prior_history_without_python3"
    local fastpath_skill_detail_history_tmp fastpath_skill_detail_history_send_script fastpath_skill_detail_history_log fastpath_skill_detail_history_stdout fastpath_skill_detail_history_stderr fastpath_skill_detail_history_status fastpath_skill_detail_history_intent_dir fastpath_skill_detail_history_suppress_file fastpath_skill_detail_history_runtime_root fastpath_skill_detail_history_fakebin
    fastpath_skill_detail_history_tmp="$(secure_temp_dir telegram-safe-fastpath-skill-detail-history)"
    fastpath_skill_detail_history_send_script="$fastpath_skill_detail_history_tmp/send.sh"
    fastpath_skill_detail_history_log="$fastpath_skill_detail_history_tmp/send.log"
    fastpath_skill_detail_history_intent_dir="$fastpath_skill_detail_history_tmp/intent"
    fastpath_skill_detail_history_suppress_file="$fastpath_skill_detail_history_intent_dir/session_historydetail.suppress"
    fastpath_skill_detail_history_runtime_root="$fastpath_skill_detail_history_tmp/runtime-skills"
    fastpath_skill_detail_history_fakebin="$fastpath_skill_detail_history_tmp/fakebin"
    mkdir -p "$fastpath_skill_detail_history_runtime_root/telegram-learner" "$fastpath_skill_detail_history_fakebin"
    cp "$PROJECT_ROOT/skills/telegram-learner/SKILL.md" "$fastpath_skill_detail_history_runtime_root/telegram-learner/SKILL.md"
    cat >"$fastpath_skill_detail_history_fakebin/python3" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
    chmod +x "$fastpath_skill_detail_history_fakebin/python3"
    cat >"$fastpath_skill_detail_history_send_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
chat_id=""
text=""
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
        *)
            shift
            ;;
    esac
done
printf 'chat_id=%s\ntext=%s\n' "$chat_id" "$text" >"$FASTPATH_LOG"
printf '{"ok":true}\n'
EOF
    chmod +x "$fastpath_skill_detail_history_send_script"
    fastpath_skill_detail_history_stdout="$fastpath_skill_detail_history_tmp/stdout.log"
    fastpath_skill_detail_history_stderr="$fastpath_skill_detail_history_tmp/stderr.log"
    set +e
    env PATH="$fastpath_skill_detail_history_fakebin:$MINIMAL_PATH" \
        FASTPATH_LOG="$fastpath_skill_detail_history_log" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
        MOLTIS_RUNTIME_SKILLS_ROOT="$fastpath_skill_detail_history_runtime_root" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$fastpath_skill_detail_history_intent_dir" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$fastpath_skill_detail_history_send_script" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_SCRIPT="$HOOK_SCRIPT" \
        bash "$HOOK_HANDLER" >"$fastpath_skill_detail_history_stdout" 2>"$fastpath_skill_detail_history_stderr" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:historydetail","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Что нового?"},{"role":"assistant","content":"Немногое, но по делу."},{"role":"user","content":"А какие навыки у тебя есть?"},{"role":"assistant","content":"Сейчас доступны навыки: `codex-update`, `post-close-task-classifier`, `telegram-learner`."},{"role":"user","content":"Расскажи мне про навык telegram-lerner"}],"tool_count":37,"iteration":1}}
EOF
    fastpath_skill_detail_history_status=$?
    set -e
    if [[ "$fastpath_skill_detail_history_status" -eq 0 ]] && \
       [[ ! -s "$fastpath_skill_detail_history_stderr" ]] && \
       jq -e '.action == "block"' >/dev/null 2>&1 "$fastpath_skill_detail_history_stdout" && \
       [[ -f "$fastpath_skill_detail_history_suppress_file" ]] && \
       grep -Fq $'\tskill_detail:telegram-learner' "$fastpath_skill_detail_history_suppress_file" && \
       grep -Fq 'chat_id=262872984' "$fastpath_skill_detail_history_log" && \
       grep -Fq 'telegram-learner' "$fastpath_skill_detail_history_log" && \
       grep -Fq '@tsingular' "$fastpath_skill_detail_history_log" && \
       grep -Fq 'Полезен, когда нужно быстро собрать новые практики' "$fastpath_skill_detail_history_log" && \
       grep -Fq 'В Telegram-safe чате даю только краткое описание' "$fastpath_skill_detail_history_log" && \
       ! grep -Eq 'Похоже, ты имеешь в виду|Когда использовать:|Workflow:|Telegram-safe DM|Обычно он работает по шагам:|Сейчас в описании навыка указаны источники:' "$fastpath_skill_detail_history_log"; then
        test_pass
    else
        test_fail "Direct skill-detail fastpath must remain deterministic even with prior chat history and no working python3 binary in PATH"
    fi

    test_start "component_before_llm_guard_direct_fastpaths_skill_detail_without_perl_or_python3"
    local fastpath_skill_detail_nolang_tmp fastpath_skill_detail_nolang_send_script fastpath_skill_detail_nolang_log fastpath_skill_detail_nolang_stdout fastpath_skill_detail_nolang_stderr fastpath_skill_detail_nolang_status fastpath_skill_detail_nolang_intent_dir fastpath_skill_detail_nolang_suppress_file fastpath_skill_detail_nolang_runtime_root fastpath_skill_detail_nolang_fakebin
    fastpath_skill_detail_nolang_tmp="$(secure_temp_dir telegram-safe-fastpath-skill-detail-nolang)"
    fastpath_skill_detail_nolang_send_script="$fastpath_skill_detail_nolang_tmp/send.sh"
    fastpath_skill_detail_nolang_log="$fastpath_skill_detail_nolang_tmp/send.log"
    fastpath_skill_detail_nolang_intent_dir="$fastpath_skill_detail_nolang_tmp/intent"
    fastpath_skill_detail_nolang_suppress_file="$fastpath_skill_detail_nolang_intent_dir/session_nolangdetail.suppress"
    fastpath_skill_detail_nolang_runtime_root="$fastpath_skill_detail_nolang_tmp/runtime-skills"
    fastpath_skill_detail_nolang_fakebin="$fastpath_skill_detail_nolang_tmp/fakebin"
    mkdir -p "$fastpath_skill_detail_nolang_runtime_root/telegram-learner" "$fastpath_skill_detail_nolang_fakebin"
    cp "$PROJECT_ROOT/skills/telegram-learner/SKILL.md" "$fastpath_skill_detail_nolang_runtime_root/telegram-learner/SKILL.md"
    cat >"$fastpath_skill_detail_nolang_fakebin/perl" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
    cat >"$fastpath_skill_detail_nolang_fakebin/python3" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
    chmod +x "$fastpath_skill_detail_nolang_fakebin/perl" "$fastpath_skill_detail_nolang_fakebin/python3"
    cat >"$fastpath_skill_detail_nolang_send_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
chat_id=""
text=""
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
        *)
            shift
            ;;
    esac
done
printf 'chat_id=%s\ntext=%s\n' "$chat_id" "$text" >"$FASTPATH_LOG"
printf '{"ok":true}\n'
EOF
    chmod +x "$fastpath_skill_detail_nolang_send_script"
    fastpath_skill_detail_nolang_stdout="$fastpath_skill_detail_nolang_tmp/stdout.log"
    fastpath_skill_detail_nolang_stderr="$fastpath_skill_detail_nolang_tmp/stderr.log"
    set +e
    env PATH="$fastpath_skill_detail_nolang_fakebin:$MINIMAL_PATH" \
        FASTPATH_LOG="$fastpath_skill_detail_nolang_log" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
        MOLTIS_RUNTIME_SKILLS_ROOT="$fastpath_skill_detail_nolang_runtime_root" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$fastpath_skill_detail_nolang_intent_dir" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$fastpath_skill_detail_nolang_send_script" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_SCRIPT="$HOOK_SCRIPT" \
        bash "$HOOK_HANDLER" >"$fastpath_skill_detail_nolang_stdout" 2>"$fastpath_skill_detail_nolang_stderr" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:nolangdetail","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Расскажи мне про навык telegram-lerner"}],"tool_count":37,"iteration":1}}
EOF
    fastpath_skill_detail_nolang_status=$?
    set -e
    if [[ "$fastpath_skill_detail_nolang_status" -eq 0 ]] && \
       [[ ! -s "$fastpath_skill_detail_nolang_stderr" ]] && \
       jq -e '.action == "block"' >/dev/null 2>&1 "$fastpath_skill_detail_nolang_stdout" && \
       [[ -f "$fastpath_skill_detail_nolang_suppress_file" ]] && \
       grep -Fq $'\tskill_detail:telegram-learner' "$fastpath_skill_detail_nolang_suppress_file" && \
       grep -Fq 'chat_id=262872984' "$fastpath_skill_detail_nolang_log" && \
       grep -Fq 'telegram-learner' "$fastpath_skill_detail_nolang_log" && \
       grep -Fq '@tsingular' "$fastpath_skill_detail_nolang_log" && \
       grep -Fq 'Полезен, когда нужно быстро собрать новые практики' "$fastpath_skill_detail_nolang_log" && \
       grep -Fq 'В Telegram-safe чате даю только краткое описание' "$fastpath_skill_detail_nolang_log" && \
       ! grep -Eq 'Похоже, ты имеешь в виду|Когда использовать:|Workflow:|Telegram-safe DM|Обычно он работает по шагам:|Сейчас в описании навыка указаны источники:' "$fastpath_skill_detail_nolang_log"; then
        test_pass
    else
        test_fail "Direct skill-detail fastpath must stay deterministic even when both perl and python3 are unavailable"
    fi

    test_start "component_before_llm_guard_does_not_repeat_direct_fastpath_on_same_turn_iteration_two"
    local repeat_fastpath_tmp repeat_fastpath_send_script repeat_fastpath_log repeat_fastpath_stdout repeat_fastpath_stderr repeat_fastpath_status repeat_fastpath_intent_dir repeat_fastpath_session_marker repeat_fastpath_chat_marker
    repeat_fastpath_tmp="$(secure_temp_dir telegram-safe-repeat-fastpath-before-llm)"
    repeat_fastpath_send_script="$repeat_fastpath_tmp/send.sh"
    repeat_fastpath_log="$repeat_fastpath_tmp/send.log"
    repeat_fastpath_intent_dir="$repeat_fastpath_tmp/intent"
    repeat_fastpath_session_marker="$repeat_fastpath_intent_dir/session_repeatdetail.suppress"
    repeat_fastpath_chat_marker="$repeat_fastpath_intent_dir/chat-262872984.suppress"
    mkdir -p "$repeat_fastpath_intent_dir"
    printf '%s\tskill_detail:telegram-learner\n' "$(date +%s)" >"$repeat_fastpath_session_marker"
    printf '%s\tskill_detail:telegram-learner\n' "$(date +%s)" >"$repeat_fastpath_chat_marker"
    cat >"$repeat_fastpath_send_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'unexpected-repeat-direct-send\n' >"$FASTPATH_LOG"
printf '{"ok":true}\n'
EOF
    chmod +x "$repeat_fastpath_send_script"
    repeat_fastpath_stdout="$repeat_fastpath_tmp/stdout.log"
    repeat_fastpath_stderr="$repeat_fastpath_tmp/stderr.log"
    set +e
    env PATH="$MINIMAL_PATH" \
        FASTPATH_LOG="$repeat_fastpath_log" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$repeat_fastpath_intent_dir" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$repeat_fastpath_send_script" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_SCRIPT="$HOOK_SCRIPT" \
        bash "$HOOK_HANDLER" >"$repeat_fastpath_stdout" 2>"$repeat_fastpath_stderr" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:repeatdetail","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Расскажи мне про навык telegram-lerner"}],"tool_count":37,"iteration":2}}
EOF
    repeat_fastpath_status=$?
    set -e
    if [[ "$repeat_fastpath_status" -eq 0 ]] && \
       [[ ! -s "$repeat_fastpath_stderr" ]] && \
       jq -e '.action == "block"' >/dev/null 2>&1 <"$repeat_fastpath_stdout" && \
       [[ -f "$repeat_fastpath_session_marker" ]] && \
       [[ -f "$repeat_fastpath_chat_marker" ]] && \
       [[ ! -e "$repeat_fastpath_log" ]]; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must treat iteration>1 with an active direct-fastpath marker as same-turn runtime churn: keep suppression, avoid a duplicate direct-send, and hard-block the repeated LLM pass"
    fi

    test_start "component_before_llm_guard_does_not_direct_fastpath_sparse_skill_create_anymore"
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
{"event":"BeforeLLMCall","data":{"session_key":"session:fastcreate","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Создай навык codex-update-new-fastpath"}],"tool_count":37,"iteration":1}}
EOF
    fastpath_create_status=$?
    set -e
    if [[ "$fastpath_create_status" -eq 0 ]] && \
       jq -e '.action == "modify"' >/dev/null 2>&1 <"$fastpath_create_stdout" && \
       jq -e '.data.tool_count == 37' >/dev/null 2>&1 <"$fastpath_create_stdout" && \
       [[ ! -s "$fastpath_create_stderr" ]] && \
       [[ ! -e "$fastpath_create_suppress_file" ]] && \
       [[ ! -f "$fastpath_created_skill" ]] && \
       [[ ! -e "$fastpath_create_log" ]]; then
        test_pass
    else
        test_fail "Sparse create must no longer use the direct Bot API fastpath or repo-owned runtime scaffold write when direct fastpath mode is enabled"
    fi

    test_start "component_before_tool_guard_allows_followup_create_skill_without_legacy_fastpath_marker"
    local direct_fastpath_tool_output
    direct_fastpath_tool_output="$(
        env PATH="$MINIMAL_PATH" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeToolCall","session_key":"session:fastcreate","provider":"openai-codex","model":"openai-codex::gpt-5.4","tool":"create_skill","arguments":{"name":"codex-update-new-fastpath"}}
EOF
    )"
    if [[ -z "$direct_fastpath_tool_output" ]]; then
        test_pass
    else
        test_fail "BeforeToolCall guard must allow native create_skill calls when there is no legacy direct-fastpath suppression marker"
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
       [[ -f "$direct_fastpath_delivery_marker" ]]; then
        test_pass
    else
        test_fail "MessageSending guard must suppress the runtime's trailing reply after a successful direct fastpath and keep the same-turn suppression marker alive"
    fi

    test_start "component_message_sending_guard_keeps_suppressing_repeated_same_turn_runtime_delivery_after_direct_fastpath"
    local direct_fastpath_delivery_repeat_output
    direct_fastpath_delivery_repeat_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$direct_fastpath_delivery_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageSending","session_id":"session:faststatus","data":{"account_id":"moltis-bot","to":"262872984","reply_to_message_id":1000,"text":"📋 Activity log • 🔧 mcp__tavily__tavily_search • ❌ MCP tool error: Internal error: 5 validation errors for call[tavily_search]"}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$direct_fastpath_delivery_repeat_output" && \
       jq -e '.data.text == "NO_REPLY"' >/dev/null 2>&1 <<<"$direct_fastpath_delivery_repeat_output" && \
       [[ -f "$direct_fastpath_delivery_marker" ]]; then
        test_pass
    else
        test_fail "MessageSending guard must keep suppressing repeated same-turn runtime deliveries after a direct fastpath instead of consuming the marker on the first tail"
    fi

    test_start "component_after_llm_guard_suppresses_late_llm_reply_after_direct_fastpath"
    local direct_fastpath_after_llm_output
    direct_fastpath_after_llm_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$direct_fastpath_delivery_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"AfterLLMCall","session_key":"session:faststatus","provider":"openai-codex","model":"openai-codex::gpt-5.4","text":"Да — новая стабильная версия есть: 0.118.0.","tool_calls":[{"name":"mcp__tavily__tavily_search","arguments":{"query":"OpenAI Codex latest stable release"}}]}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$direct_fastpath_after_llm_output" && \
       jq -e '.data.text == ""' >/dev/null 2>&1 <<<"$direct_fastpath_after_llm_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$direct_fastpath_after_llm_output" && \
       [[ -f "$direct_fastpath_delivery_marker" ]]; then
        test_pass
    else
        test_fail "AfterLLMCall guard must keep a direct-fastpath turn terminal by dropping late LLM text and tool calls for the same session"
    fi

    test_start "component_message_sending_guard_suppresses_late_delivery_by_chat_id_when_runtime_changes_session_key"
    local direct_fastpath_chat_delivery_dir direct_fastpath_chat_delivery_marker direct_fastpath_chat_delivery_output
    direct_fastpath_chat_delivery_dir="$(secure_temp_dir telegram-safe-direct-fastpath-chat-delivery)"
    direct_fastpath_chat_delivery_marker="$direct_fastpath_chat_delivery_dir/chat-262872984.suppress"
    mkdir -p "$direct_fastpath_chat_delivery_dir"
    printf '%s\tskill_detail:telegram-learner\n' "$(date +%s)" >"$direct_fastpath_chat_delivery_marker"
    direct_fastpath_chat_delivery_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$direct_fastpath_chat_delivery_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageSending","session_id":"session:late-skilldetail-tail","data":{"account_id":"moltis-bot","to":"262872984","reply_to_message_id":1294,"text":"Сейчас скажу честно и коротко: мультивызов инструментов сработал криво. 📋 Activity log • 💻 Running: `cat /home/moltis/.moltis/skills/telegram-learner/SKILL.md` • ❌ missing 'command' parameter • ❌ missing 'query' parameter"}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$direct_fastpath_chat_delivery_output" && \
       jq -e '.data.text == "NO_REPLY"' >/dev/null 2>&1 <<<"$direct_fastpath_chat_delivery_output" && \
       [[ -f "$direct_fastpath_chat_delivery_marker" ]]; then
        test_pass
    else
        test_fail "MessageSending guard must suppress a late dirty Telegram delivery by chat-scoped marker even when the runtime changes the session key after a direct fastpath"
    fi

    test_start "component_after_llm_guard_suppresses_late_reply_by_chat_id_when_runtime_changes_session_key"
    local direct_fastpath_chat_after_llm_output
    direct_fastpath_chat_after_llm_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$direct_fastpath_chat_delivery_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"AfterLLMCall","session_key":"session:late-skilldetail-tail","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Расскажи мне про навык telegram-lerner"}],"text":"Сейчас скажу честно и коротко: мультивызов инструментов отработал криво.","tool_calls":[{"name":"exec","arguments":{"command":"cat /home/moltis/.moltis/skills/telegram-learner/SKILL.md"}}]}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$direct_fastpath_chat_after_llm_output" && \
       jq -e '.data.text == ""' >/dev/null 2>&1 <<<"$direct_fastpath_chat_after_llm_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$direct_fastpath_chat_after_llm_output" && \
       [[ -f "$direct_fastpath_chat_delivery_marker" ]]; then
        test_pass
    else
        test_fail "AfterLLMCall guard must stay terminal by chat-scoped suppression even when the runtime changes the session key after a direct fastpath"
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

    test_start "component_message_sending_guard_direct_sends_clean_reply_when_chat_id_is_numeric"
    local direct_clean_delivery_numeric_tmp direct_clean_delivery_numeric_send_script direct_clean_delivery_numeric_log direct_clean_delivery_numeric_stdout direct_clean_delivery_numeric_stderr direct_clean_delivery_numeric_status
    direct_clean_delivery_numeric_tmp="$(secure_temp_dir telegram-safe-direct-clean-delivery-numeric)"
    direct_clean_delivery_numeric_send_script="$direct_clean_delivery_numeric_tmp/send.sh"
    direct_clean_delivery_numeric_log="$direct_clean_delivery_numeric_tmp/send.log"
    cat >"$direct_clean_delivery_numeric_send_script" <<'EOF'
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
    chmod +x "$direct_clean_delivery_numeric_send_script"
    direct_clean_delivery_numeric_stdout="$direct_clean_delivery_numeric_tmp/stdout.log"
    direct_clean_delivery_numeric_stderr="$direct_clean_delivery_numeric_tmp/stderr.log"
    set +e
    env PATH="$MINIMAL_PATH" \
        FASTPATH_LOG="$direct_clean_delivery_numeric_log" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
        MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$direct_clean_delivery_numeric_send_script" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$direct_clean_delivery_numeric_tmp/intent" \
        bash "$HOOK_SCRIPT" >"$direct_clean_delivery_numeric_stdout" 2>"$direct_clean_delivery_numeric_stderr" <<'EOF'
{"event":"MessageSending","session_id":"session:clean-delivery-numeric","data":{"account_id":"moltis-bot","to":262872984,"reply_to_message_id":1201,"text":"Да — новая стабильная версия есть: 0.118.0. Activity log • Searching memory... • missing 'query' parameter"}}
EOF
    direct_clean_delivery_numeric_status=$?
    set -e
    if [[ "$direct_clean_delivery_numeric_status" -eq 0 ]] && \
       [[ ! -s "$direct_clean_delivery_numeric_stderr" ]] && \
       jq -e '.action == "modify"' >/dev/null 2>&1 <"$direct_clean_delivery_numeric_stdout" && \
       jq -e '.data.text == "NO_REPLY"' >/dev/null 2>&1 <"$direct_clean_delivery_numeric_stdout" && \
       grep -Fq 'chat_id=262872984' "$direct_clean_delivery_numeric_log" && \
       grep -Fq 'text=Да — новая стабильная версия есть: 0.118.0.' "$direct_clean_delivery_numeric_log" && \
       grep -Fq 'reply_to=1201' "$direct_clean_delivery_numeric_log"; then
        test_pass
    else
        test_fail "MessageSending guard must also direct-send the cleaned final reply when the runtime emits numeric chat ids in the MessageSending payload"
    fi

    test_start "component_message_sending_guard_does_not_repeat_clean_delivery_direct_send_on_second_same_turn_tail"
    local direct_clean_delivery_repeat_stdout direct_clean_delivery_repeat_stderr direct_clean_delivery_repeat_status
    direct_clean_delivery_repeat_stdout="$direct_clean_delivery_tmp/stdout-repeat.log"
    direct_clean_delivery_repeat_stderr="$direct_clean_delivery_tmp/stderr-repeat.log"
    set +e
    env PATH="$MINIMAL_PATH" \
        FASTPATH_LOG="$direct_clean_delivery_log" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
        MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$direct_clean_delivery_send_script" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$direct_clean_delivery_tmp/intent" \
        bash "$HOOK_SCRIPT" >"$direct_clean_delivery_repeat_stdout" 2>"$direct_clean_delivery_repeat_stderr" <<'EOF'
{"event":"MessageSending","session_id":"session:clean-delivery","data":{"account_id":"moltis-bot","to":"262872984","reply_to_message_id":1202,"text":"📋 Activity log • 🔧 mcp__tavily__tavily_search • ❌ MCP tool error: Internal error: 5 validation errors for call[tavily_search]"}}
EOF
    direct_clean_delivery_repeat_status=$?
    set -e
    if [[ "$direct_clean_delivery_repeat_status" -eq 0 ]] && \
       [[ ! -s "$direct_clean_delivery_repeat_stderr" ]] && \
       jq -e '.action == "modify"' >/dev/null 2>&1 <"$direct_clean_delivery_repeat_stdout" && \
       jq -e '.data.text == "NO_REPLY"' >/dev/null 2>&1 <"$direct_clean_delivery_repeat_stdout" && \
       grep -Fq 'reply_to=1200' "$direct_clean_delivery_log" && \
       ! grep -Fq 'reply_to=1202' "$direct_clean_delivery_log"; then
        test_pass
    else
        test_fail "MessageSending guard must not repeat the cleaned direct-send when a second same-turn dirty tail arrives after clean_delivery"
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

    test_start "component_message_sending_guard_rewrites_clean_reply_when_direct_send_script_is_unavailable"
    local clean_delivery_modify_tmp clean_delivery_modify_stdout clean_delivery_modify_stderr clean_delivery_modify_status
    clean_delivery_modify_tmp="$(secure_temp_dir telegram-safe-clean-delivery-modify)"
    clean_delivery_modify_stdout="$clean_delivery_modify_tmp/stdout.log"
    clean_delivery_modify_stderr="$clean_delivery_modify_tmp/stderr.log"
    set +e
    env PATH="$MINIMAL_PATH" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
        MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$clean_delivery_modify_tmp/missing-send.sh" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$clean_delivery_modify_tmp/intent" \
        bash "$HOOK_SCRIPT" >"$clean_delivery_modify_stdout" 2>"$clean_delivery_modify_stderr" <<'EOF'
{"event":"MessageSending","session_id":"session:clean-delivery-modify","data":{"account_id":"moltis-bot","to":"262872984","reply_to_message_id":1201,"text":"Да — новая стабильная версия есть: 0.118.0. Activity log • mcp__tavily__tavily_search • Searching memory... • missing 'query' parameter"}}
EOF
    clean_delivery_modify_status=$?
    set -e
    if [[ "$clean_delivery_modify_status" -eq 0 ]] && \
       [[ ! -s "$clean_delivery_modify_stderr" ]] && \
       jq -e '.action == "modify"' >/dev/null 2>&1 <"$clean_delivery_modify_stdout" && \
       jq -e '.data.text == "Да — новая стабильная версия есть: 0.118.0."' >/dev/null 2>&1 <"$clean_delivery_modify_stdout" && \
       jq -e '.data.reply_to_message_id == 1201' >/dev/null 2>&1 <"$clean_delivery_modify_stdout"; then
        test_pass
    else
        test_fail "MessageSending guard must rewrite the cleaned final reply through the normal modify path when direct-send is unavailable instead of leaking the raw Activity log suffix"
    fi

    test_start "component_message_sending_guard_rewrites_clean_codex_update_scheduler_false_negative"
    local clean_codex_update_scheduler_output
    clean_codex_update_scheduler_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_CODEX_UPDATE_RELEASE_JSON='{"tag_name":"0.118.0","published_at":"2026-04-01T12:00:00Z"}' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageSending","session_id":"session:codex-update-scheduler-clean","data":{"account_id":"moltis-bot","to":"262872984","reply_to_message_id":1295,"user_message":"А разе у тебя нет крона по проверке вышедшей новой версии Codex cli?","text":"Навык есть, но автопроверка по крону не подтверждена."}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$clean_codex_update_scheduler_output" && \
       jq -e '.data.text == "По проектному контракту у codex-update есть отдельный scheduler path для регулярной проверки обновлений Codex CLI каждые 6 часов. Но в Telegram-safe чате я не подтверждаю по памяти, что live cron сейчас действительно включён. Для точного статуса нужен операторский/runtime check, а не memory search."' >/dev/null 2>&1 <<<"$clean_codex_update_scheduler_output" && \
       jq -e '.data.account_id == "moltis-bot"' >/dev/null 2>&1 <<<"$clean_codex_update_scheduler_output" && \
       jq -e '.data.to == "262872984"' >/dev/null 2>&1 <<<"$clean_codex_update_scheduler_output" && \
       jq -e '.data.reply_to_message_id == 1295' >/dev/null 2>&1 <<<"$clean_codex_update_scheduler_output"; then
        test_pass
    else
        test_fail "MessageSending guard must rewrite a clean codex-update scheduler false negative before the generic MessageSending short-circuit"
    fi

    test_start "component_message_sending_guard_rewrites_dirty_codex_update_scheduler_false_negative_before_clean_delivery_fastpath"
    local dirty_codex_update_scheduler_tmp dirty_codex_update_scheduler_send_script dirty_codex_update_scheduler_log dirty_codex_update_scheduler_stdout dirty_codex_update_scheduler_stderr dirty_codex_update_scheduler_status
    dirty_codex_update_scheduler_tmp="$(secure_temp_dir telegram-safe-codex-update-scheduler-dirty)"
    dirty_codex_update_scheduler_send_script="$dirty_codex_update_scheduler_tmp/send.sh"
    dirty_codex_update_scheduler_log="$dirty_codex_update_scheduler_tmp/send.log"
    cat >"$dirty_codex_update_scheduler_send_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'unexpected_direct_send\n' >>"$FASTPATH_LOG"
printf '{"ok":true}\n'
EOF
    chmod +x "$dirty_codex_update_scheduler_send_script"
    dirty_codex_update_scheduler_stdout="$dirty_codex_update_scheduler_tmp/stdout.log"
    dirty_codex_update_scheduler_stderr="$dirty_codex_update_scheduler_tmp/stderr.log"
    set +e
    env PATH="$MINIMAL_PATH" \
        FASTPATH_LOG="$dirty_codex_update_scheduler_log" \
        MOLTIS_CODEX_UPDATE_RELEASE_JSON='{"tag_name":"0.118.0","published_at":"2026-04-01T12:00:00Z"}' \
        MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
        MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$dirty_codex_update_scheduler_send_script" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$dirty_codex_update_scheduler_tmp/intent" \
        bash "$HOOK_SCRIPT" >"$dirty_codex_update_scheduler_stdout" 2>"$dirty_codex_update_scheduler_stderr" <<'EOF'
{"event":"MessageSending","session_id":"session:codex-update-scheduler-dirty","data":{"account_id":"moltis-bot","to":"262872984","reply_to_message_id":1296,"user_message":"А разе у тебя нет крона по проверке вышедшей новой версии Codex cli?","text":"Похоже, проверить не удалось. 📋 Activity log • 🔧 cron • ❌ missing 'action' parameter"}}
EOF
    dirty_codex_update_scheduler_status=$?
    set -e
    if [[ "$dirty_codex_update_scheduler_status" -eq 0 ]] && \
       [[ ! -s "$dirty_codex_update_scheduler_stderr" ]] && \
       jq -e '.action == "modify"' >/dev/null 2>&1 <"$dirty_codex_update_scheduler_stdout" && \
       jq -e '.data.text == "По проектному контракту у codex-update есть отдельный scheduler path для регулярной проверки обновлений Codex CLI каждые 6 часов. Но в Telegram-safe чате я не подтверждаю по памяти, что live cron сейчас действительно включён. Для точного статуса нужен операторский/runtime check, а не memory search."' >/dev/null 2>&1 <"$dirty_codex_update_scheduler_stdout" && \
       jq -e '.data.reply_to_message_id == 1296' >/dev/null 2>&1 <"$dirty_codex_update_scheduler_stdout" && \
       [[ ! -s "$dirty_codex_update_scheduler_log" ]]; then
        test_pass
    else
        test_fail "MessageSending codex-update override must run before the clean-delivery fastpath so dirty scheduler false negatives are rewritten instead of direct-sent as stripped text"
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
        MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=1 \
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

    test_start "component_message_sending_guard_preserves_legitimate_activity_log_mentions_when_scrubbing_suffix"
    local direct_activity_phrase_tmp direct_activity_phrase_send_script direct_activity_phrase_log direct_activity_phrase_stdout direct_activity_phrase_stderr direct_activity_phrase_status
    direct_activity_phrase_tmp="$(secure_temp_dir telegram-safe-direct-activity-phrase)"
    direct_activity_phrase_send_script="$direct_activity_phrase_tmp/send.sh"
    direct_activity_phrase_log="$direct_activity_phrase_tmp/send.log"
    cat >"$direct_activity_phrase_send_script" <<'EOF'
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
    chmod +x "$direct_activity_phrase_send_script"
    direct_activity_phrase_stdout="$direct_activity_phrase_tmp/stdout.log"
    direct_activity_phrase_stderr="$direct_activity_phrase_tmp/stderr.log"
    set +e
    env PATH="$MINIMAL_PATH" \
        FASTPATH_LOG="$direct_activity_phrase_log" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=1 \
        MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$direct_activity_phrase_send_script" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$direct_activity_phrase_tmp/intent" \
        bash "$HOOK_SCRIPT" >"$direct_activity_phrase_stdout" 2>"$direct_activity_phrase_stderr" <<'EOF'
{"event":"MessageSending","session_id":"session:activity-phrase","data":{"account_id":"moltis-bot","to":"262872984","reply_to_message_id":1202,"text":"Раздел Activity log показывает историю действий пользователя. Да — новая стабильная версия есть: 0.118.0. Activity log • mcp__tavily__tavily_search • mcp__tavily__tavily_search"}}
EOF
    direct_activity_phrase_status=$?
    set -e
    if [[ "$direct_activity_phrase_status" -eq 0 ]] && \
       [[ ! -s "$direct_activity_phrase_stderr" ]] && \
       jq -e '.action == "modify"' >/dev/null 2>&1 <"$direct_activity_phrase_stdout" && \
       jq -e '.data.text == "NO_REPLY"' >/dev/null 2>&1 <"$direct_activity_phrase_stdout" && \
       grep -Fq 'chat_id=262872984' "$direct_activity_phrase_log" && \
       grep -Fq 'text=Раздел Activity log показывает историю действий пользователя. Да — новая стабильная версия есть: 0.118.0.' "$direct_activity_phrase_log" && \
       grep -Fq 'reply_to=1202' "$direct_activity_phrase_log"; then
        test_pass
    else
        test_fail "MessageSending clean-delivery scrub must preserve legitimate in-text mentions of Activity log and remove only the actual internal telemetry suffix"
    fi

    test_start "component_message_sending_guard_does_not_direct_send_cleaned_progress_preface"
    local direct_dirty_prefix_tmp direct_dirty_prefix_send_script direct_dirty_prefix_log direct_dirty_prefix_stdout direct_dirty_prefix_stderr direct_dirty_prefix_status
    direct_dirty_prefix_tmp="$(secure_temp_dir telegram-safe-direct-dirty-prefix)"
    direct_dirty_prefix_send_script="$direct_dirty_prefix_tmp/send.sh"
    direct_dirty_prefix_log="$direct_dirty_prefix_tmp/send.log"
    cat >"$direct_dirty_prefix_send_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'unexpected_direct_send\n' >>"$FASTPATH_LOG"
printf '{"ok":true}\n'
EOF
    chmod +x "$direct_dirty_prefix_send_script"
    direct_dirty_prefix_stdout="$direct_dirty_prefix_tmp/stdout.log"
    direct_dirty_prefix_stderr="$direct_dirty_prefix_tmp/stderr.log"
    set +e
    env PATH="$MINIMAL_PATH" \
        FASTPATH_LOG="$direct_dirty_prefix_log" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
        MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$direct_dirty_prefix_send_script" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$direct_dirty_prefix_tmp/intent" \
        bash "$HOOK_SCRIPT" >"$direct_dirty_prefix_stdout" 2>"$direct_dirty_prefix_stderr" <<'EOF'
{"event":"MessageSending","session_id":"session:dirty-prefix","data":{"account_id":"moltis-bot","to":"262872984","reply_to_message_id":1201,"text":"Сейчас проверю последние релизы Codex. Activity log • mcp__tavily__tavily_search • mcp__tavily__tavily_search"}}
EOF
    direct_dirty_prefix_status=$?
    set -e
    if [[ "$direct_dirty_prefix_status" -eq 0 ]] && \
       [[ ! -s "$direct_dirty_prefix_stderr" ]] && \
       jq -e '.action == "modify"' >/dev/null 2>&1 <"$direct_dirty_prefix_stdout" && \
       jq -e '.data.text | contains("В Telegram-safe режиме я не запускаю инструменты")' >/dev/null 2>&1 <"$direct_dirty_prefix_stdout" && \
       [[ ! -s "$direct_dirty_prefix_log" ]]; then
        test_pass
    else
        test_fail "MessageSending clean-delivery fastpath must not direct-send a stripped progress-preface prefix; it must fall back to the normal Telegram-safe rewrite instead"
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
{"event":"BeforeLLMCall","data":{"session_key":"session:plain-followup","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Привет"}],"tool_count":37,"iteration":1}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$stale_direct_fastpath_output" && \
       [[ ! -f "$stale_direct_fastpath_marker" ]]; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must clear stale direct-fastpath suppression at the start of a new user turn so the next normal reply is not silenced"
    fi

    test_start "component_before_llm_guard_clears_chat_scoped_direct_fastpath_suppression_on_new_user_turn"
    local stale_chat_direct_fastpath_dir stale_chat_direct_fastpath_marker stale_chat_direct_fastpath_output
    stale_chat_direct_fastpath_dir="$(secure_temp_dir telegram-safe-stale-chat-direct-fastpath)"
    stale_chat_direct_fastpath_marker="$stale_chat_direct_fastpath_dir/chat-262872984.suppress"
    mkdir -p "$stale_chat_direct_fastpath_dir"
    printf '%s\tskill_detail:telegram-learner\n' "$(date +%s)" >"$stale_chat_direct_fastpath_marker"
    stale_chat_direct_fastpath_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$stale_chat_direct_fastpath_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:plain-chat-followup","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Привет"}],"tool_count":37,"iteration":1}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$stale_chat_direct_fastpath_output" && \
       [[ ! -f "$stale_chat_direct_fastpath_marker" ]]; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must clear stale chat-scoped direct-fastpath suppression at the start of a new user turn so a later normal reply in the same Telegram chat is not silenced"
    fi

    test_start "component_before_llm_guard_does_not_persist_stale_status_intent_for_template_followup"
    local stale_status_template_dir stale_status_template_output stale_status_template_intent
    stale_status_template_dir="$(secure_temp_dir telegram-safe-stale-status-template)"
    printf '%s\tstatus\n' "$(date +%s)" >"$stale_status_template_dir/session_template-followup.intent"
    stale_status_template_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$stale_status_template_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:template-followup","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"<available_skills>\n- codex-update\n</available_skills>"},{"role":"assistant","content":"Статус: Online\nКанал: Telegram (@moltinger_bot)\nМодель: openai-codex::gpt-5.4\nПровайдер: openai-codex\nРежим: safe-text"},{"role":"user","content":"У тебя должен быть темплейт"}],"tool_count":37,"iteration":1}}
EOF
    )"
    stale_status_template_intent="$(cat "$stale_status_template_dir/session_template-followup.intent" 2>/dev/null || true)"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$stale_status_template_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe skill-template hard override")' >/dev/null 2>&1 <<<"$stale_status_template_output" && \
       [[ "$stale_status_template_intent" == *$'\tskill_template\t'* ]]; then
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
{"event":"BeforeLLMCall","data":{"session_key":"session:template-after-visibility","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis\n<available_skills>\n- codex-update\n</available_skills>"},{"role":"assistant","content":"Навыки (3): codex-update, post-close-task-classifier, telegram-learner."},{"role":"user","content":"У тебя должен быть темплейт"}],"tool_count":37,"iteration":1}}
EOF
    )"
    stale_visibility_template_intent="$(cat "$stale_visibility_template_dir/session_template-after-visibility.intent" 2>/dev/null || true)"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$stale_visibility_template_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe skill-template hard override")' >/dev/null 2>&1 <<<"$stale_visibility_template_output" && \
       [[ "$stale_visibility_template_intent" == *$'\tskill_template\t'* ]]; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must let a template follow-up replace stale persisted skill-visibility intent instead of reusing the previous skills turn"
    fi

    test_start "component_before_llm_guard_clears_legacy_skill_create_intent_and_keeps_native_create_lane"
    local stale_visibility_create_dir stale_visibility_create_output stale_visibility_create_intent stale_visibility_create_file
    stale_visibility_create_dir="$(secure_temp_dir telegram-safe-stale-visibility-create)"
    stale_visibility_create_file="$stale_visibility_create_dir/runtime/codex-update-new-from-stale/SKILL.md"
    printf '%s\tskill_visibility\n' "$(date +%s)" >"$stale_visibility_create_dir/session_create-after-visibility.intent"
    stale_visibility_create_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_RUNTIME_SKILLS_ROOT="$stale_visibility_create_dir/runtime" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$stale_visibility_create_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:create-after-visibility","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"assistant","content":"Навыки (3): codex-update, post-close-task-classifier, telegram-learner."},{"role":"user","content":"Создай навык codex-update-new-from-stale"}],"tool_count":37,"iteration":1}}
EOF
    )"
    stale_visibility_create_intent="$(cat "$stale_visibility_create_dir/session_create-after-visibility.intent" 2>/dev/null || true)"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$stale_visibility_create_output" && \
       jq -e '.data.tool_count == 37' >/dev/null 2>&1 <<<"$stale_visibility_create_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe skill runtime note")' >/dev/null 2>&1 <<<"$stale_visibility_create_output" && \
       jq -e '.data.messages[1].content | contains("Telegram-safe skill-authoring contract")' >/dev/null 2>&1 <<<"$stale_visibility_create_output" && \
       jq -e '.data.messages[2].content | contains("Telegram-safe sparse create-skill override")' >/dev/null 2>&1 <<<"$stale_visibility_create_output" && \
       [[ ! -f "$stale_visibility_create_file" ]] && \
       ([[ "$stale_visibility_create_intent" == *$'\tskill_native_crud\t'* ]] || [[ "$stale_visibility_create_intent" == *$'\tskill_native_crud:'* ]]); then
        test_pass
    else
        test_fail "BeforeLLMCall guard must keep create follow-ups on the native tool lane, clear stale visibility intent, and persist only the current native CRUD lane without scaffold writes"
    fi

    test_start "component_before_llm_guard_resets_sparse_create_history_after_stale_create_failure"
    local stale_create_failure_output
    stale_create_failure_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,telegram-learner' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:create-history-regression","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Создай новый навык codex-update-old-failed"},{"role":"assistant","content":"Не смог создать: `create_skill` в этой сессии тоже сломан и вернул `missing 'name'` при корректном вызове."},{"role":"user","content":"Создай новый навык moltis-version-watch-20260424-tele-a1 для автоматического отслеживания новой версии Moltis."}],"tool_count":37,"iteration":1}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$stale_create_failure_output" && \
       jq -e '.data.tool_count == 37' >/dev/null 2>&1 <<<"$stale_create_failure_output" && \
       jq -e '.data.messages | length == 4' >/dev/null 2>&1 <<<"$stale_create_failure_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe skill runtime note")' >/dev/null 2>&1 <<<"$stale_create_failure_output" && \
       jq -e '.data.messages[1].content | contains("Telegram-safe skill-authoring contract")' >/dev/null 2>&1 <<<"$stale_create_failure_output" && \
       jq -e '.data.messages[2].content | contains("Telegram-safe sparse create-skill override")' >/dev/null 2>&1 <<<"$stale_create_failure_output" && \
       jq -e '.data.messages[3].content == "Создай новый навык moltis-version-watch-20260424-tele-a1 для автоматического отслеживания новой версии Moltis."' >/dev/null 2>&1 <<<"$stale_create_failure_output" && \
       jq -e '[.data.messages[].content] | any(contains("codex-update-old-failed")) | not' >/dev/null 2>&1 <<<"$stale_create_failure_output" && \
       jq -e '[.data.messages[].content] | any(contains("missing '\''name'\''")) | not' >/dev/null 2>&1 <<<"$stale_create_failure_output"; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must reset sparse create history when stale create_skill failure traces would contaminate the next native CRUD attempt"
    fi

    test_start "component_message_sending_guard_drops_legacy_skill_create_intent_rewrite"
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
       jq -e '.data.text == "В Telegram-safe режиме я не запускаю инструменты и не показываю внутренние логи. Для browser/search/process workflow продолжим в web UI или операторской сессии."' >/dev/null 2>&1 <<<"$skill_create_intent_output" && \
       [[ ! -f "$skill_create_intent_dir/session_skill_create.intent" ]]; then
        test_pass
    else
        test_fail "MessageSending guard must clear retired skill_create intents instead of rewriting delivery into a false repo-owned create confirmation"
    fi

    test_start "component_message_sending_guard_keeps_subsequent_deliveries_clean_after_legacy_skill_create_intent_cleanup"
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
       jq -e '.data.text == "В Telegram-safe режиме я не запускаю инструменты и не показываю внутренние логи. Для browser/search/process workflow продолжим в web UI или операторской сессии."' >/dev/null 2>&1 <<<"$skill_create_intent_first_output" && \
       [[ -z "$skill_create_intent_second_output" ]] && \
       [[ ! -f "$skill_create_intent_dir/session_skill_create.intent" ]]; then
        test_pass
    else
        test_fail "MessageSending guard must clear retired skill_create intents on first contact so later unrelated deliveries stay untouched"
    fi

    test_start "component_message_sending_guard_does_not_override_immediate_skill_visibility_followup_with_retired_create_intent"
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
        test_fail "MessageSending guard must not overwrite an immediate skill-visibility follow-up with any retired create confirmation and must clear the old create intent once encountered"
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
{"event":"BeforeLLMCall","data":{"session_key":"session:abgj","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"base system"},{"role":"user","content":"Создай навык codex-update-new"},{"role":"assistant","content":"Окей, создаём `codex-update-new`. Мне нужны детали: описание, тело инструкций и разрешённые инструменты. Что должен делать этот навык?"},{"role":"user","content":"Следить за версиями Codex CLI и уведомлять пользователя о новых релизах."}],"tool_count":37,"iteration":1}}
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
            '{"event":"BeforeLLMCall","data":{"session_key":"session:abf","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"base system"},{"role":"system","content":"Telegram-safe long-research guard: stale copy"},{"role":"user","content":"Изучи полностью официальную документацию Moltis и научи меня делать новый навык"}],"tool_count":37,"iteration":2}}'
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
            '{"event":"BeforeLLMCall","data":{"session_key":"session:abe","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"base system"},{"role":"user","content":"Ответь кратко, что умеет этот бот."}],"tool_count":37,"iteration":1}}'
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
{"event":"BeforeToolCall","data":{"session_key":"session:tool","provider":"openai-codex","model":"openai-codex::gpt-5.4","tool":"exec","arguments":{"command":"ls -la ~/.moltis/skills/"}}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_tool_exec_output" && \
       jq -e '.data.tool == "exec"' >/dev/null 2>&1 <<<"$before_tool_exec_output" && \
       jq -e '.data.arguments.command | contains("Telegram-safe runtime note for skills")' >/dev/null 2>&1 <<<"$before_tool_exec_output" && \
       jq -e '.data.arguments.command | contains("create_skill, update_skill, patch_skill, delete_skill, write_skill_files")' >/dev/null 2>&1 <<<"$before_tool_exec_output" && \
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
{"event":"BeforeToolCall","data":{"session_key":"session:toolq","provider":"openai-codex","model":"openai-codex::gpt-5.4","tool":"exec","arguments":{"command":"bash -lc \"ls -la ~/.moltis/skills/\""}}}
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
{"event":"BeforeLLMCall","data":{"session_key":"session:tooltop","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=test | channel_account=moltis-bot | channel_chat_id=262872984"},{"role":"user","content":"А что у тебя с навыками/skills?"}],"tool_count":37,"iteration":1}}
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
{"event":"BeforeLLMCall","data":{"session_key":"session:toolstatus","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=test | channel_account=moltis-bot | channel_chat_id=262872984"},{"role":"user","content":"/status"}],"tool_count":37,"iteration":1}}
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
            '{"event":"BeforeToolCall","data":{"session_key":"session:tool2","provider":"openai-codex","model":"openai-codex::gpt-5.4","tool":"create_skill","arguments":{"name":"codex-update-new"}}}'
    )"
    if [[ -z "$before_tool_create_output" ]]; then
        test_pass
    else
        test_fail "BeforeToolCall guard must not block dedicated skill tools such as create_skill"
    fi

    test_start "component_before_tool_guard_allows_update_patch_delete_and_sidecar_skill_tools"
    local before_tool_update_output before_tool_patch_output before_tool_delete_output before_tool_write_files_output
    before_tool_update_output="$(
        run_hook_with_minimal_path \
            '{"event":"BeforeToolCall","data":{"session_key":"session:tool-update","provider":"openai-codex","model":"openai-codex::gpt-5.4","tool":"update_skill","arguments":{"name":"codex-update","content":"---\nname: codex-update\ndescription: updated\n---\n# codex-update"}}}'
    )"
    before_tool_patch_output="$(
        run_hook_with_minimal_path \
            '{"event":"BeforeToolCall","data":{"session_key":"session:tool-patch","provider":"openai-codex","model":"openai-codex::gpt-5.4","tool":"patch_skill","arguments":{"name":"codex-update","patches":[{"find":"description: updated","replace":"description: refined"}]}}}'
        )"
    before_tool_delete_output="$(
        run_hook_with_minimal_path \
            '{"event":"BeforeToolCall","data":{"session_key":"session:tool-delete","provider":"openai-codex","model":"openai-codex::gpt-5.4","tool":"delete_skill","arguments":{"name":"codex-update-old"}}}'
    )"
    before_tool_write_files_output="$(
        run_hook_with_minimal_path \
            '{"event":"BeforeToolCall","data":{"session_key":"session:tool-write-files","provider":"openai-codex","model":"openai-codex::gpt-5.4","tool":"write_skill_files","arguments":{"name":"codex-update","files":[{"path":"notes.md","content":"hello"}]}}}'
    )"
    if [[ -z "$before_tool_update_output" ]] && \
       [[ -z "$before_tool_patch_output" ]] && \
       [[ -z "$before_tool_delete_output" ]] && \
       [[ -z "$before_tool_write_files_output" ]]; then
        test_pass
    else
        test_fail "BeforeToolCall guard must allow native update_skill, patch_skill, delete_skill, and write_skill_files passthrough for owner Telegram skill CRUD"
    fi

    test_start "component_before_tool_guard_canonicalizes_live_read_skill_envelope_without_blocking"
    local before_tool_read_skill_envelope_output
    before_tool_read_skill_envelope_output="$(
        run_hook_with_minimal_path \
            '{"event":"BeforeToolCall","data":{"session_key":"session:read-skill-envelope","provider":"openai-codex","model":"openai-codex::gpt-5.4","tool":"read_skill","arguments":{"_channel":{"account_id":"moltis-bot","channel_type":"telegram","chat_id":"262872984","surface":"telegram"},"_session_key":"session:read-skill-envelope","file_path":null,"name":"codex-update"}}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_tool_read_skill_envelope_output" && \
       jq -e '.data.session_key == "session:read-skill-envelope"' >/dev/null 2>&1 <<<"$before_tool_read_skill_envelope_output" && \
       jq -e '.data.tool == "read_skill"' >/dev/null 2>&1 <<<"$before_tool_read_skill_envelope_output" && \
       jq -e '.data.tool_name == "read_skill"' >/dev/null 2>&1 <<<"$before_tool_read_skill_envelope_output" && \
       jq -e '.data.arguments.name == "codex-update"' >/dev/null 2>&1 <<<"$before_tool_read_skill_envelope_output" && \
       jq -e '.data.arguments | has("_channel") | not' >/dev/null 2>&1 <<<"$before_tool_read_skill_envelope_output" && \
       jq -e '.data.arguments | has("_session_key") | not' >/dev/null 2>&1 <<<"$before_tool_read_skill_envelope_output" && \
       jq -e '.data.arguments | has("file_path") | not' >/dev/null 2>&1 <<<"$before_tool_read_skill_envelope_output"; then
        test_pass
    else
        test_fail "BeforeToolCall guard must normalize valid read_skill argument envelopes to the native tool instead of blocking or hiding them"
    fi

    test_start "component_before_tool_guard_canonicalizes_live_create_skill_envelope_with_content_alias"
    local before_tool_create_skill_envelope_output
    before_tool_create_skill_envelope_output="$(
        run_hook_with_minimal_path \
            '{"event":"BeforeToolCall","data":{"session_key":"session:create-skill-envelope","provider":"openai-codex","model":"openai-codex::gpt-5.4","tool":"create_skill","arguments":{"_channel":{"account_id":"moltis-bot","channel_type":"telegram","chat_id":"262872984"},"_session_key":"session:create-skill-envelope","name":"moltis-update-dialog","body":"---\nname: moltis-update-dialog\ndescription: demo\n---\n# moltis-update-dialog","description":"demo","allowed_tools":["exec"]}}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_tool_create_skill_envelope_output" && \
       jq -e '.data.tool == "create_skill"' >/dev/null 2>&1 <<<"$before_tool_create_skill_envelope_output" && \
       jq -e '.data.arguments.name == "moltis-update-dialog"' >/dev/null 2>&1 <<<"$before_tool_create_skill_envelope_output" && \
       jq -e '.data.arguments.content | contains("name: moltis-update-dialog")' >/dev/null 2>&1 <<<"$before_tool_create_skill_envelope_output" && \
       jq -e '.data.arguments.description == "demo"' >/dev/null 2>&1 <<<"$before_tool_create_skill_envelope_output" && \
       jq -e '.data.arguments | has("body") | not' >/dev/null 2>&1 <<<"$before_tool_create_skill_envelope_output" && \
       jq -e '.data.arguments | has("allowed_tools") | not' >/dev/null 2>&1 <<<"$before_tool_create_skill_envelope_output" && \
       jq -e '.data.arguments | has("_channel") | not' >/dev/null 2>&1 <<<"$before_tool_create_skill_envelope_output" && \
       jq -e '.data.arguments | has("_session_key") | not' >/dev/null 2>&1 <<<"$before_tool_create_skill_envelope_output"; then
        test_pass
    else
        test_fail "BeforeToolCall guard must normalize live create_skill envelopes to the official content-based contract instead of forwarding legacy body/allowed_tools fields"
    fi

    test_start "component_before_tool_guard_canonicalizes_valid_runtime_tool_envelopes_to_original_tools"
    local before_tool_memory_envelope_output before_tool_exec_envelope_output before_tool_cron_envelope_output before_tool_glob_envelope_output before_tool_fetch_envelope_output before_tool_browser_envelope_output
    before_tool_memory_envelope_output="$(
        run_hook_with_minimal_path \
            '{"event":"BeforeToolCall","data":{"session_key":"session:memory-envelope","provider":"openai-codex","model":"openai-codex::gpt-5.4","tool":"memory_search","arguments":{"_channel":{"account_id":"moltis-bot","channel_type":"telegram","chat_id":"262872984"},"_session_key":"session:memory-envelope","limit":10,"query":"codex-update last announced version","filter":null}}}'
    )"
    before_tool_exec_envelope_output="$(
        run_hook_with_minimal_path \
            '{"event":"BeforeToolCall","data":{"session_key":"session:exec-envelope","provider":"openai-codex","model":"openai-codex::gpt-5.4","tool":"exec","arguments":{"_channel":{"account_id":"moltis-bot","channel_type":"telegram","chat_id":"262872984"},"_session_key":"session:exec-envelope","command":"pwd","timeout":20000,"working_dir":"/home/moltis/.moltis","reason":null}}}'
    )"
    before_tool_cron_envelope_output="$(
        run_hook_with_minimal_path \
            '{"event":"BeforeToolCall","data":{"session_key":"session:cron-envelope","provider":"openai-codex","model":"openai-codex::gpt-5.4","tool":"cron","arguments":{"_channel":{"account_id":"moltis-bot","channel_type":"telegram","chat_id":"262872984"},"_session_key":"session:cron-envelope","action":"list","limit":50,"id":null,"job":null}}}'
    )"
    before_tool_glob_envelope_output="$(
        run_hook_with_minimal_path \
            '{"event":"BeforeToolCall","data":{"session_key":"session:glob-envelope","provider":"openai-codex","model":"openai-codex::gpt-5.4","tool":"Glob","arguments":{"_channel":{"account_id":"moltis-bot","channel_type":"telegram","chat_id":"262872984"},"_session_key":"session:glob-envelope","path":"/home/moltis/.moltis","pattern":"**/codex-update/**","exclude":null}}}'
    )"
    before_tool_fetch_envelope_output="$(
        run_hook_with_minimal_path \
            '{"event":"BeforeToolCall","data":{"session_key":"session:fetch-envelope","provider":"openai-codex","model":"openai-codex::gpt-5.4","tool":"web_fetch","arguments":{"_channel":{"account_id":"moltis-bot","channel_type":"telegram","chat_id":"262872984"},"_session_key":"session:fetch-envelope","url":"https://docs.moltis.org/skill-tools.html","extract_mode":"text","max_chars":12000,"selector":null}}}'
    )"
    before_tool_browser_envelope_output="$(
        run_hook_with_minimal_path \
            '{"event":"BeforeToolCall","data":{"session_key":"session:browser-envelope","provider":"openai-codex","model":"openai-codex::gpt-5.4","tool":"browser","arguments":{"_channel":{"account_id":"moltis-bot","channel_type":"telegram","chat_id":"262872984"},"_session_key":"session:browser-envelope","action":"open","url":"https://example.com","session_id":null}}}'
    )"
    if jq -e '.action == "modify" and .data.tool == "memory_search" and .data.arguments.query == "codex-update last announced version" and .data.arguments.limit == 10 and (.data.arguments | has("_channel") | not) and (.data.arguments | has("filter") | not)' >/dev/null 2>&1 <<<"$before_tool_memory_envelope_output" && \
       jq -e '.action == "modify" and .data.tool == "exec" and .data.arguments.command == "pwd" and .data.arguments.timeout == 20000 and .data.arguments.working_dir == "/home/moltis/.moltis" and (.data.arguments | has("_session_key") | not) and (.data.arguments | has("reason") | not)' >/dev/null 2>&1 <<<"$before_tool_exec_envelope_output" && \
       jq -e '.action == "modify" and .data.tool == "cron" and .data.arguments.action == "list" and .data.arguments.limit == 50 and (.data.arguments | has("id") | not) and (.data.arguments | has("job") | not)' >/dev/null 2>&1 <<<"$before_tool_cron_envelope_output" && \
       jq -e '.action == "modify" and .data.tool == "Glob" and .data.arguments.pattern == "**/codex-update/**" and .data.arguments.path == "/home/moltis/.moltis" and (.data.arguments | has("exclude") | not)' >/dev/null 2>&1 <<<"$before_tool_glob_envelope_output" && \
       jq -e '.action == "modify" and .data.tool == "web_fetch" and .data.arguments.url == "https://docs.moltis.org/skill-tools.html" and .data.arguments.max_chars == 12000 and (.data.arguments | has("selector") | not)' >/dev/null 2>&1 <<<"$before_tool_fetch_envelope_output" && \
       jq -e '.action == "modify" and .data.tool == "browser" and .data.arguments.action == "open" and .data.arguments.url == "https://example.com" and (.data.arguments | has("session_id") | not)' >/dev/null 2>&1 <<<"$before_tool_browser_envelope_output"; then
        test_pass
    else
        test_fail "BeforeToolCall guard must fix valid live runtime envelopes at the argument boundary and preserve the original tool identity"
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

    test_start "component_before_tool_guard_suppresses_non_telegram_malformed_known_tools"
    local before_tool_non_telegram_malformed_output
    before_tool_non_telegram_malformed_output="$(
        run_hook_with_minimal_path \
            '{"event":"BeforeToolCall","data":{"session_key":"session:nontelegram-tool-malformed","provider":"ollama","model":"ollama::gemini-3-flash-preview:cloud","tool":"exec","arguments":{"cmd":"cat /home/moltis/.moltis/skills/codex-update/SKILL.md"}}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_tool_non_telegram_malformed_output" && \
       jq -e '.data.session_key == "session:nontelegram-tool-malformed"' >/dev/null 2>&1 <<<"$before_tool_non_telegram_malformed_output" && \
       jq -e '.data.tool == "exec"' >/dev/null 2>&1 <<<"$before_tool_non_telegram_malformed_output" && \
       jq -e '.data.tool_name == "exec"' >/dev/null 2>&1 <<<"$before_tool_non_telegram_malformed_output" && \
       jq -e '.data.arguments.command == "true"' >/dev/null 2>&1 <<<"$before_tool_non_telegram_malformed_output"; then
        test_pass
    else
        test_fail "BeforeToolCall guard must rewrite malformed known-tool calls into a harmless exec no-op outside Telegram-safe lane as well"
    fi

    test_start "component_before_tool_guard_suppresses_malformed_skill_crud_calls"
    local before_tool_patch_malformed_output before_tool_write_files_malformed_output
    before_tool_patch_malformed_output="$(
        run_hook_with_minimal_path \
            '{"event":"BeforeToolCall","data":{"session_key":"session:tool-patch-malformed","provider":"openai-codex","model":"openai-codex::gpt-5.4","tool":"patch_skill","arguments":{"name":"codex-update"}}}'
    )"
    before_tool_write_files_malformed_output="$(
        run_hook_with_minimal_path \
            '{"event":"BeforeToolCall","data":{"session_key":"session:tool-write-files-malformed","provider":"openai-codex","model":"openai-codex::gpt-5.4","tool":"write_skill_files","arguments":{"name":"codex-update","files":[]}}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_tool_patch_malformed_output" && \
       jq -e '.data.tool == "exec"' >/dev/null 2>&1 <<<"$before_tool_patch_malformed_output" && \
       jq -e '.data.arguments.command == "true"' >/dev/null 2>&1 <<<"$before_tool_patch_malformed_output" && \
       jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_tool_write_files_malformed_output" && \
       jq -e '.data.tool == "exec"' >/dev/null 2>&1 <<<"$before_tool_write_files_malformed_output" && \
       jq -e '.data.arguments.command == "true"' >/dev/null 2>&1 <<<"$before_tool_write_files_malformed_output"; then
        test_pass
    else
        test_fail "BeforeToolCall guard must fail closed on malformed patch_skill/write_skill_files calls instead of letting raw validation errors leak back to Telegram"
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

    test_start "component_before_tool_guard_blocks_tavily_on_persisted_skill_native_crud_intent"
    local skill_mutation_before_tool_dir before_tool_skill_mutation_tavily_output
    skill_mutation_before_tool_dir="$(secure_temp_dir telegram-safe-before-tool-skill-mutation)"
    env PATH="$MINIMAL_PATH" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$skill_mutation_before_tool_dir" \
        MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,telegram-learner' \
        bash "$HOOK_SCRIPT" <<'EOF' >/dev/null
{"event":"BeforeLLMCall","data":{"session_key":"session:skillmutation-tool","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=test | channel_account=moltis-bot | channel_chat_id=262872984"},{"role":"user","content":"Обнови навык codex-update так, чтобы он лучше работал в Telegram"}],"tool_count":37,"iteration":1}}
EOF
    before_tool_skill_mutation_tavily_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$skill_mutation_before_tool_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeToolCall","session_key":"session:skillmutation-tool","tool_name":"mcp__tavily__tavily_search","arguments":{"query":"codex-update skill best practices"}}
EOF
    )"
    rm -rf "$skill_mutation_before_tool_dir"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_tool_skill_mutation_tavily_output" && \
       jq -e '.data.tool == "exec"' >/dev/null 2>&1 <<<"$before_tool_skill_mutation_tavily_output" && \
       jq -e '.data.tool_name == "exec"' >/dev/null 2>&1 <<<"$before_tool_skill_mutation_tavily_output" && \
       jq -e '.data.arguments.command | contains("Telegram skill-CRUD lane")' >/dev/null 2>&1 <<<"$before_tool_skill_mutation_tavily_output" && \
       jq -e '.data.arguments.command | contains("Do not call Tavily")' >/dev/null 2>&1 <<<"$before_tool_skill_mutation_tavily_output"; then
        test_pass
    else
        test_fail "BeforeToolCall guard must block Tavily on persisted native skill CRUD turns and keep those turns on dedicated skill tools only"
    fi

    test_start "component_before_tool_guard_blocks_allowlisted_tavily_when_skill_detail_intent_is_persisted"
    local skill_detail_before_tool_dir before_tool_skill_detail_tavily_output
    skill_detail_before_tool_dir="$(secure_temp_dir telegram-safe-before-tool-skill-detail)"
    env PATH="$MINIMAL_PATH" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$skill_detail_before_tool_dir" \
        MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,post-close-task-classifier,telegram-learner' \
        bash "$HOOK_SCRIPT" <<'EOF' >/dev/null
{"event":"BeforeLLMCall","data":{"session_key":"session:skilldetail-tool","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=test | channel_account=moltis-bot | channel_chat_id=262872984"},{"role":"user","content":"Расскажи мне про навык telegram-lerner"}],"tool_count":37,"iteration":1}}
EOF
    before_tool_skill_detail_tavily_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$skill_detail_before_tool_dir" \
            MOLTIS_RUNTIME_SKILLS_ROOT="$PROJECT_ROOT/skills" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,post-close-task-classifier,telegram-learner' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeToolCall","session_key":"session:skilldetail-tool","tool_name":"mcp__tavily__tavily_search","arguments":{"query":"telegram learner skill"}} 
EOF
    )"
    rm -rf "$skill_detail_before_tool_dir"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_tool_skill_detail_tavily_output" && \
       jq -e '.data.session_key == "session:skilldetail-tool"' >/dev/null 2>&1 <<<"$before_tool_skill_detail_tavily_output" && \
       jq -e '.data.tool == "exec"' >/dev/null 2>&1 <<<"$before_tool_skill_detail_tavily_output" && \
       jq -e '.data.tool_name == "exec"' >/dev/null 2>&1 <<<"$before_tool_skill_detail_tavily_output" && \
       jq -e '.data.arguments.command | contains("telegram-learner")' >/dev/null 2>&1 <<<"$before_tool_skill_detail_tavily_output" && \
       jq -e '.data.arguments.command | contains("@tsingular")' >/dev/null 2>&1 <<<"$before_tool_skill_detail_tavily_output"; then
        test_pass
    else
        test_fail "BeforeToolCall guard must suppress even allowlisted Tavily research when the persisted Telegram turn is a deterministic skill-detail reply"
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
            '{"event":"AfterLLMCall","data":{"session_key":"session:ghi","provider":"openai-codex","model":"openai-codex::gpt-5.4","text":"**Статус системы**\nПроцессы в tmux: нет\nМодель: openai-codex::gpt-5.4","tool_calls":[{"name":"process","arguments":{"action":"list"}},{"name":"cron","arguments":{"action":"list"}}]}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$after_status_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$after_status_output" && \
       jq -e '.data.text == "Статус: Online\nКанал: Telegram (@moltinger_bot)\nМодель: openai-codex::gpt-5.4\nПровайдер: openai-codex\nРежим: safe-text"' >/dev/null 2>&1 <<<"$after_status_output" && \
       jq -e '.data.provider == "openai-codex"' >/dev/null 2>&1 <<<"$after_status_output" && \
       jq -e '.data.model == "openai-codex::gpt-5.4"' >/dev/null 2>&1 <<<"$after_status_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must replace Telegram-safe status tool fallbacks with a canonical safe-text status reply without depending on jq in the runtime container"
    fi

    test_start "component_after_llm_guard_blocks_general_tool_fallbacks_for_telegram_safe_lane"
    local after_general_output
    after_general_output="$(
        run_hook_with_minimal_path \
            '{"event":"AfterLLMCall","data":{"session_key":"session:jkl","provider":"openai-codex","model":"openai-codex::gpt-5.4","text":"Сейчас проверю через browser и cron.","tool_calls":[{"name":"browser","arguments":{"action":"navigate"}}]}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$after_general_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$after_general_output" && \
       jq -e '.data.text | contains("не запускаю инструменты")' >/dev/null 2>&1 <<<"$after_general_output" && \
       jq -e '.data.text | contains("web UI")' >/dev/null 2>&1 <<<"$after_general_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must suppress general Telegram-safe tool fallbacks and replace them with a clean user-facing fallback"
    fi

    test_start "component_after_llm_guard_fail_closes_non_telegram_missing_required_argument_tool_calls"
    local after_non_telegram_malformed_output
    after_non_telegram_malformed_output="$(
        run_hook_with_minimal_path \
            '{"event":"AfterLLMCall","data":{"session_key":"session:nontelegram-malformed","provider":"ollama","model":"ollama::gemini-3-flash-preview:cloud","text":"Сейчас проверю память и потом покажу лог ошибки.","tool_calls":[{"name":"memory_search","arguments":{}}]}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$after_non_telegram_malformed_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$after_non_telegram_malformed_output" && \
       jq -e '.data.text | contains("Внутренний tool-path сформировал некорректный вызов")' >/dev/null 2>&1 <<<"$after_non_telegram_malformed_output" && \
       jq -e '.data.text | contains("не показываю сырые tool-ошибки")' >/dev/null 2>&1 <<<"$after_non_telegram_malformed_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must fail closed for non-Telegram malformed known-tool calls so web/UI lanes never surface raw missing-parameter cards"
    fi

    test_start "component_after_llm_guard_rewrites_generic_skill_count_reply_to_deterministic_runtime_skill_list"
    local after_skill_visibility_output
    after_skill_visibility_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,post-close-task-classifier,telegram-learner' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"AfterLLMCall","data":{"session_key":"session:skillvis","provider":"openai-codex","model":"openai-codex::gpt-5.4","text":"У меня 3 навыка. Ты спрашиваешь третий раз. Что ты хочешь сделать?","tool_calls":[],"messages":[{"role":"system","content":"base system"},{"role":"user","content":"А что у тебя с навыками/skills?"}]}}
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
{"event":"AfterLLMCall","data":{"session_key":"session:skillvish","provider":"openai-codex","model":"openai-codex::gpt-5.4","text":"У меня 3 навыка. Что ты хочешь сделать?","tool_calls":[],"messages":[{"role":"system","content":"base system"},{"role":"user","content":"Создай навык codex-update-new"},{"role":"assistant","content":"Опиши его подробнее."},{"role":"user","content":"А что у тебя с навыками/skills?"}]}}
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
{"event":"AfterLLMCall","data":{"session_key":"session:skillstop","provider":"openai-codex","model":"openai-codex::gpt-5.4","text":"3 навыка в конфиге, файлов нет в sandbox. Стоп.","tool_calls":[]}}
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
{"event":"AfterLLMCall","data":{"session_key":"session:skillnofiles","provider":"openai-codex","model":"openai-codex::gpt-5.4","text":"3 навыка в конфиге. Файлов нет. Хочешь создать — дай инструкцию.","tool_calls":[]}}
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
{"event":"BeforeLLMCall","data":{"session_key":"session:skillpersist-after","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"base system"},{"role":"user","content":"А что у тебя с навыками/skills?"}],"tool_count":37,"iteration":1}}
EOF
    after_skill_visibility_persisted_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,post-close-task-classifier,telegram-learner' \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$persisted_intent_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"AfterLLMCall","data":{"session_key":"session:skillpersist-after","provider":"openai-codex","model":"openai-codex::gpt-5.4","text":"3 навыка. Создать новый?","tool_calls":[]}}
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
{"event":"AfterLLMCall","data":{"session_key":"session:status-visibility","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"base system"},{"role":"assistant","content":"Статус: Online\nКанал: Telegram (@moltinger_bot)\nМодель: openai-codex::gpt-5.4\nПровайдер: openai-codex\nРежим: safe-text"},{"role":"user","content":"А что у тебя с навыками/skills?"}],"text":"**Навыки: 4 в конфиге, файлов нет в sandbox.** Ты 12-й раз спрашиваешь.","tool_calls":[]}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$after_skill_visibility_from_status_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$after_skill_visibility_from_status_output" && \
       jq -e '.data.text == "Навыки (3): codex-update, post-close-task-classifier, telegram-learner."' >/dev/null 2>&1 <<<"$after_skill_visibility_from_status_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must let the latest skill-visibility turn win over stale /status history and persisted status intent"
    fi

    test_start "component_after_llm_guard_rewrites_overbroad_skill_visibility_inventory_even_when_model_mentions_real_runtime_skills"
    local after_skill_visibility_overbroad_output
    after_skill_visibility_overbroad_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,telegram-learner' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"AfterLLMCall","data":{"session_key":"session:skill-visibility-overbroad","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"base system"},{"role":"user","content":"Какие у тебя сейчас есть навыки?"}],"text":"Навыки: codex-update, telegram-learner, docker-expert, prompt-engineer, devops-guardian. Могу показать ещё скрытые системные навыки.","tool_calls":[]}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$after_skill_visibility_overbroad_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$after_skill_visibility_overbroad_output" && \
       jq -e '.data.text == "Навыки (2): codex-update, telegram-learner."' >/dev/null 2>&1 <<<"$after_skill_visibility_overbroad_output"; then
        test_pass
    else
        test_fail "AfterLLMCall skill visibility override must ignore overbroad model inventories and always answer from the runtime skill snapshot"
    fi

    test_start "component_after_llm_guard_preserves_allowlisted_skill_tool_calls_while_rewriting_progress_text"
    local after_skill_tool_output
    after_skill_tool_output="$(
        run_hook_with_minimal_path \
            '{"event":"AfterLLMCall","data":{"session_key":"session:skilltool","provider":"openai-codex","model":"openai-codex::gpt-5.4","text":"Пользователь просит создать навык. У меня есть доступ к create_skill. Сначала найду шаблон.","tool_calls":[{"name":"create_skill","arguments":{"name":"codex-update-new"}}]}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$after_skill_tool_output" && \
       jq -e '.data.tool_calls[0].name == "create_skill"' >/dev/null 2>&1 <<<"$after_skill_tool_output" && \
       jq -e '.data.text | contains("через встроенные инструменты")' >/dev/null 2>&1 <<<"$after_skill_tool_output" && \
       jq -e '.data.text | contains("filesystem-проб")' >/dev/null 2>&1 <<<"$after_skill_tool_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must keep allowlisted create_skill tool calls reachable while replacing leaked internal planning with a safe progress line"
    fi

    test_start "component_after_llm_guard_direct_executes_native_skill_crud_when_direct_fastpath_is_available"
    local after_skill_crud_direct_dir after_skill_crud_direct_runtime after_skill_crud_direct_send after_skill_crud_direct_log after_skill_crud_direct_output after_skill_crud_direct_skill_file after_skill_crud_direct_sidecar
    after_skill_crud_direct_dir="$(secure_temp_dir telegram-safe-after-skill-crud-direct)"
    after_skill_crud_direct_runtime="$after_skill_crud_direct_dir/runtime"
    after_skill_crud_direct_send="$after_skill_crud_direct_dir/send.sh"
    after_skill_crud_direct_log="$after_skill_crud_direct_dir/send.log"
    after_skill_crud_direct_skill_file="$after_skill_crud_direct_runtime/moltis-update-dialog/SKILL.md"
    after_skill_crud_direct_sidecar="$after_skill_crud_direct_runtime/moltis-update-dialog/notes.md"
    cat >"$after_skill_crud_direct_send" <<'EOF'
#!/usr/bin/env bash
printf 'send %s\n' "$*" >>"$FASTPATH_LOG"
exit 0
EOF
    chmod +x "$after_skill_crud_direct_send"
    env PATH="$MINIMAL_PATH" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$after_skill_crud_direct_dir/intent" \
        MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,telegram-learner' \
        bash "$HOOK_SCRIPT" <<'EOF' >/dev/null
{"event":"BeforeLLMCall","data":{"session_key":"session:after-skill-crud-direct","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=test | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Создай навык moltis-update-dialog для отслеживания новых версий Moltis и добавь заметку notes.md"}],"tool_count":37,"iteration":1}}
EOF
    after_skill_crud_direct_output="$(
        env PATH="$MINIMAL_PATH:/usr/bin" \
            FASTPATH_LOG="$after_skill_crud_direct_log" \
            MOLTIS_RUNTIME_SKILLS_ROOT="$after_skill_crud_direct_runtime" \
            MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
            MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$after_skill_crud_direct_send" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$after_skill_crud_direct_dir/intent" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"AfterLLMCall","data":{"session_key":"session:after-skill-crud-direct","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=test | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Создай навык moltis-update-dialog для отслеживания новых версий Moltis и добавь заметку notes.md"}],"text":"Сначала создам навык, потом запишу notes.md.","tool_calls":[{"arguments":{"name":"moltis-update-dialog","body":"---\nname: moltis-update-dialog\ndescription: Следит за новыми версиями Moltis.\n---\n# moltis-update-dialog\n\n## Активация\nКогда пользователь просит следить за новыми версиями Moltis, используй навык.\n","description":"Следит за новыми версиями Moltis.","allowed_tools":["exec"]},"id":"call_live_create","name":"create_skill"},{"arguments":{"name":"moltis-update-dialog","files":[{"path":"notes.md","content":"watch Moltis releases"}]},"id":"call_live_write","name":"write_skill_files"}]}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$after_skill_crud_direct_output" && \
       jq -e '.data.text == ""' >/dev/null 2>&1 <<<"$after_skill_crud_direct_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$after_skill_crud_direct_output" && \
       [[ -f "$after_skill_crud_direct_skill_file" ]] && \
       [[ -f "$after_skill_crud_direct_sidecar" ]] && \
       grep -Fq 'description: Следит за новыми версиями Moltis.' "$after_skill_crud_direct_skill_file" && \
       grep -Fq 'watch Moltis releases' "$after_skill_crud_direct_sidecar" && \
       grep -Fq -- '--chat-id 262872984' "$after_skill_crud_direct_log" && \
       grep -Fq 'Создал навык `moltis-update-dialog` и сразу доработал его.' "$after_skill_crud_direct_log"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must directly execute Telegram-safe native skill CRUD, send one clean user-facing summary, and suppress the later raw tool tail"
    fi

    test_start "component_after_llm_guard_restores_session_chat_id_for_live_shaped_direct_skill_crud_payload"
    local after_skill_crud_live_dir after_skill_crud_live_runtime after_skill_crud_live_send after_skill_crud_live_log after_skill_crud_live_output after_skill_crud_live_skill_file
    after_skill_crud_live_dir="$(secure_temp_dir telegram-safe-after-skill-crud-live)"
    after_skill_crud_live_runtime="$after_skill_crud_live_dir/runtime"
    after_skill_crud_live_send="$after_skill_crud_live_dir/send.sh"
    after_skill_crud_live_log="$after_skill_crud_live_dir/send.log"
    after_skill_crud_live_skill_file="$after_skill_crud_live_runtime/moltis-live-shaped/SKILL.md"
    cat >"$after_skill_crud_live_send" <<'EOF'
#!/usr/bin/env bash
printf 'send %s\n' "$*" >>"$FASTPATH_LOG"
exit 0
EOF
    chmod +x "$after_skill_crud_live_send"
    env PATH="$MINIMAL_PATH" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$after_skill_crud_live_dir/intent" \
        MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,telegram-learner' \
        bash "$HOOK_SCRIPT" <<'EOF' >/dev/null
{"event":"BeforeLLMCall","data":{"session_key":"session:after-skill-crud-live","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=test | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Создай навык moltis-live-shaped для проверки live-shaped AfterLLM payload."}],"tool_count":37,"iteration":1}}
EOF
    after_skill_crud_live_output="$(
        env PATH="$MINIMAL_PATH:/usr/bin" \
            FASTPATH_LOG="$after_skill_crud_live_log" \
            MOLTIS_RUNTIME_SKILLS_ROOT="$after_skill_crud_live_runtime" \
            MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
            MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$after_skill_crud_live_send" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$after_skill_crud_live_dir/intent" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"AfterLLMCall","data":{"session_key":"session:after-skill-crud-live","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"The current user datetime is 2026-04-24 06:07:59 MSK."}],"text":"Сначала создам навык, потом дам краткий итог.","tool_calls":[{"arguments":{"name":"moltis-live-shaped","body":"---\nname: moltis-live-shaped\ndescription: Проверка live-shaped AfterLLM payload.\n---\n# moltis-live-shaped\n"},"id":"call_live_shaped_create","name":"create_skill"}]}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$after_skill_crud_live_output" && \
       jq -e '.data.text == ""' >/dev/null 2>&1 <<<"$after_skill_crud_live_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$after_skill_crud_live_output" && \
       [[ -f "$after_skill_crud_live_skill_file" ]] && \
       grep -Fq 'name: moltis-live-shaped' "$after_skill_crud_live_skill_file" && \
       grep -Fq -- '--chat-id 262872984' "$after_skill_crud_live_log" && \
       grep -Fq 'Создал базовый шаблон навыка `moltis-live-shaped`.' "$after_skill_crud_live_log"; then
        test_pass
    else
        test_fail "AfterLLMCall direct skill CRUD must restore the Telegram chat_id from persisted session state when the live-shaped payload omits chat metadata"
    fi

    test_start "component_after_llm_guard_recovers_sparse_skill_create_when_live_after_llm_payload_omits_user_message"
    local after_sparse_create_empty_dir after_sparse_create_empty_runtime after_sparse_create_empty_send after_sparse_create_empty_log after_sparse_create_empty_output after_sparse_create_empty_skill_file after_sparse_create_empty_before_intent
    after_sparse_create_empty_dir="$(secure_temp_dir telegram-safe-after-sparse-create-empty)"
    after_sparse_create_empty_runtime="$after_sparse_create_empty_dir/runtime"
    after_sparse_create_empty_send="$after_sparse_create_empty_dir/send.sh"
    after_sparse_create_empty_log="$after_sparse_create_empty_dir/send.log"
    after_sparse_create_empty_skill_file="$after_sparse_create_empty_runtime/moltis-version-watch-20260424/SKILL.md"
    cat >"$after_sparse_create_empty_send" <<'EOF'
#!/usr/bin/env bash
printf 'send %s\n' "$*" >>"$FASTPATH_LOG"
exit 0
EOF
    chmod +x "$after_sparse_create_empty_send"
    env PATH="$MINIMAL_PATH" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$after_sparse_create_empty_dir/intent" \
        MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,telegram-learner' \
        bash "$HOOK_SCRIPT" <<'EOF' >/dev/null
{"event":"BeforeLLMCall","data":{"session_key":"session:after-sparse-create-empty","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=test | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Создай новый навык moltis-version-watch-20260424 для автоматического отслеживания новой версии Moltis."}],"tool_count":37,"iteration":1}}
EOF
    after_sparse_create_empty_before_intent="$(cat "$after_sparse_create_empty_dir/intent/session_after-sparse-create-empty.intent" 2>/dev/null || true)"
    after_sparse_create_empty_output="$(
        env PATH="$MINIMAL_PATH:/usr/bin" \
            FASTPATH_LOG="$after_sparse_create_empty_log" \
            MOLTIS_RUNTIME_SKILLS_ROOT="$after_sparse_create_empty_runtime" \
            MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
            MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$after_sparse_create_empty_send" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$after_sparse_create_empty_dir/intent" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"AfterLLMCall","data":{"session_key":"session:after-sparse-create-empty","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=test | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"system","content":"The current user datetime is 2026-04-24 06:07:59 MSK."}],"text":"","tool_calls":[]}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$after_sparse_create_empty_output" && \
       jq -e '.data.text == ""' >/dev/null 2>&1 <<<"$after_sparse_create_empty_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$after_sparse_create_empty_output" && \
       [[ -f "$after_sparse_create_empty_skill_file" ]] && \
       [[ "$after_sparse_create_empty_before_intent" == *$'\tskill_native_crud:create:moltis-version-watch-20260424\t'* ]] && \
       grep -Fq 'name: moltis-version-watch-20260424' "$after_sparse_create_empty_skill_file" && \
       grep -Fq 'Создал базовый шаблон навыка `moltis-version-watch-20260424`.' "$after_sparse_create_empty_log"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must recover sparse Telegram skill creation even when the live-shaped AfterLLMCall payload omits the user message, so valid create requests do not end in a silent hole"
    fi

    test_start "component_after_llm_guard_direct_executes_update_and_delete_skill_crud_when_direct_fastpath_is_available"
    local after_skill_crud_edit_dir after_skill_crud_edit_runtime after_skill_crud_edit_send after_skill_crud_edit_log after_skill_crud_edit_update_output after_skill_crud_edit_delete_output after_skill_crud_edit_skill_file
    after_skill_crud_edit_dir="$(secure_temp_dir telegram-safe-after-skill-crud-edit)"
    after_skill_crud_edit_runtime="$after_skill_crud_edit_dir/runtime"
    after_skill_crud_edit_send="$after_skill_crud_edit_dir/send.sh"
    after_skill_crud_edit_log="$after_skill_crud_edit_dir/send.log"
    after_skill_crud_edit_skill_file="$after_skill_crud_edit_runtime/moltis-update-dialog/SKILL.md"
    mkdir -p "$after_skill_crud_edit_runtime/moltis-update-dialog"
    cat >"$after_skill_crud_edit_skill_file" <<'EOF'
---
name: moltis-update-dialog
description: Старая версия описания.
---
# moltis-update-dialog

## Workflow
- Старый текст.
EOF
    cat >"$after_skill_crud_edit_send" <<'EOF'
#!/usr/bin/env bash
printf 'send %s\n' "$*" >>"$FASTPATH_LOG"
exit 0
EOF
    chmod +x "$after_skill_crud_edit_send"
    env PATH="$MINIMAL_PATH" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$after_skill_crud_edit_dir/intent" \
        MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,moltis-update-dialog,telegram-learner' \
        bash "$HOOK_SCRIPT" <<'EOF' >/dev/null
{"event":"BeforeLLMCall","data":{"session_key":"session:after-skill-crud-edit","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=test | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Обнови навык moltis-update-dialog и потом удали его"}],"tool_count":37,"iteration":1}}
EOF
    after_skill_crud_edit_update_output="$(
        env PATH="$MINIMAL_PATH:/usr/bin" \
            FASTPATH_LOG="$after_skill_crud_edit_log" \
            MOLTIS_RUNTIME_SKILLS_ROOT="$after_skill_crud_edit_runtime" \
            MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
            MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$after_skill_crud_edit_send" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$after_skill_crud_edit_dir/intent" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"AfterLLMCall","data":{"session_key":"session:after-skill-crud-edit","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=test | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Обнови навык moltis-update-dialog и потом удали его"}],"text":"Сейчас обновлю навык.","tool_calls":[{"name":"update_skill","arguments":{"name":"moltis-update-dialog","description":"Новая версия описания."}}]}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$after_skill_crud_edit_update_output" && \
       jq -e '.data.text == ""' >/dev/null 2>&1 <<<"$after_skill_crud_edit_update_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$after_skill_crud_edit_update_output" && \
       grep -Fq 'description: Новая версия описания.' "$after_skill_crud_edit_skill_file" && \
       grep -Fq 'Обновил навык `moltis-update-dialog`.' "$after_skill_crud_edit_log"; then
        test_pass
    else
        test_fail "AfterLLMCall direct skill CRUD path must support update_skill edits without falling back to the broken Telegram tool boundary"
    fi
    env PATH="$MINIMAL_PATH" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$after_skill_crud_edit_dir/intent" \
        MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,moltis-update-dialog,telegram-learner' \
        bash "$HOOK_SCRIPT" <<'EOF' >/dev/null
{"event":"BeforeLLMCall","data":{"session_key":"session:after-skill-crud-delete","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=test | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Удали навык moltis-update-dialog"}],"tool_count":37,"iteration":1}}
EOF
    after_skill_crud_edit_delete_output="$(
        env PATH="$MINIMAL_PATH:/usr/bin" \
            FASTPATH_LOG="$after_skill_crud_edit_log" \
            MOLTIS_RUNTIME_SKILLS_ROOT="$after_skill_crud_edit_runtime" \
            MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
            MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$after_skill_crud_edit_send" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$after_skill_crud_edit_dir/intent" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"AfterLLMCall","data":{"session_key":"session:after-skill-crud-delete","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=test | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Удали навык moltis-update-dialog"}],"text":"Теперь удалю навык.","tool_calls":[{"name":"delete_skill","arguments":{"name":"moltis-update-dialog"}}]}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$after_skill_crud_edit_delete_output" && \
       jq -e '.data.text == ""' >/dev/null 2>&1 <<<"$after_skill_crud_edit_delete_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$after_skill_crud_edit_delete_output" && \
       [[ ! -e "$after_skill_crud_edit_runtime/moltis-update-dialog" ]] && \
       grep -Fq 'Удалил навык `moltis-update-dialog`.' "$after_skill_crud_edit_log"; then
        test_pass
    else
        test_fail "AfterLLMCall direct skill CRUD path must support delete_skill and leave no runtime skill directory behind"
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

    test_start "component_after_llm_guard_fails_closed_on_tavily_for_persisted_skill_native_crud_turn"
    local after_skill_tavily_dir after_skill_tavily_output
    after_skill_tavily_dir="$(secure_temp_dir telegram-safe-after-skill-tavily)"
    env PATH="$MINIMAL_PATH" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$after_skill_tavily_dir" \
        MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,telegram-learner' \
        bash "$HOOK_SCRIPT" <<'EOF' >/dev/null
{"event":"BeforeLLMCall","data":{"session_key":"session:skill-tavily-after","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=test | channel_account=moltis-bot | channel_chat_id=262872984"},{"role":"user","content":"Обнови навык codex-update так, чтобы он лучше работал в Telegram"}],"tool_count":37,"iteration":1}}
EOF
    after_skill_tavily_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$after_skill_tavily_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"AfterLLMCall","data":{"session_key":"session:skill-tavily-after","provider":"openai-codex","model":"gpt-5.4","text":"Сейчас обновлю навык и параллельно проверю best practices через Tavily.","tool_calls":[{"name":"mcp__tavily__tavily_search","arguments":{"query":"codex-update skill best practices"}}]}}
EOF
    )"
    rm -rf "$after_skill_tavily_dir"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$after_skill_tavily_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$after_skill_tavily_output" && \
       jq -e '.data.text | contains("не запускаю инструменты")' >/dev/null 2>&1 <<<"$after_skill_tavily_output" && \
       jq -e '.data.text | contains("web UI")' >/dev/null 2>&1 <<<"$after_skill_tavily_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must fail closed when a persisted native skill CRUD turn drifts into Tavily instead of preserving that Tavily plan"
    fi

    test_start "component_after_llm_guard_uses_generic_progress_text_for_mixed_skill_and_tavily_tool_calls"
    local after_mixed_tool_dir after_mixed_tool_output
    after_mixed_tool_dir="$(secure_temp_dir telegram-safe-after-mixedtool)"
    after_mixed_tool_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$after_mixed_tool_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"AfterLLMCall","data":{"session_key":"session:mixedtool","provider":"openai-codex","model":"gpt-5.4","text":"Сейчас создам навык и параллельно проверю релизы Codex через Tavily.","tool_calls":[{"name":"create_skill","arguments":{"name":"codex-update-new"}},{"name":"mcp__tavily__tavily_search","arguments":{"query":"Codex CLI latest stable release"}}]}}
EOF
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
{"event":"AfterLLMCall","data":{"session_key":"session:skilltoolstop","provider":"openai-codex","model":"openai-codex::gpt-5.4","text":"3 навыка в конфиге, файлов нет в sandbox. Стоп.","tool_calls":[{"name":"create_skill","arguments":{"name":"codex-update-new"}}]}}
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
            '{"event":"AfterLLMCall","data":{"session_key":"session:false","provider":"openai-codex","model":"openai-codex::gpt-5.4","text":"По факту: папки /home/moltis/.moltis/skills/ не существует. Навыки либо были удалены, либо ещё не созданы.","tool_calls":[]}}'
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
        '{"event":"AfterLLMCall","data":{"session_key":"session:jkm","provider":"openai-codex","model":"openai-codex::gpt-5.4","text":"Хорошо, Сергей! Начинаю прямо сейчас. Сначала найду официальную документацию Moltis и изучу существующий навык `codex-update`:","tool_calls":[]}}' \
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
            '{"event":"AfterLLMCall","data":{"session_key":"session:pqr","provider":"openai-codex","model":"openai-codex::gpt-5.4","text":"📋 Activity log • 💻 Running: `find /home/moltis/.moltis/skills` • 🧠 Searching memory...","tool_calls":[]}}'
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
            '{"event":"AfterLLMCall","data":{"session_key":"session:qrs","provider":"openai-codex","model":"openai-codex::gpt-5.4","text":"No remote nodes available. Let me check the available skills and search the Moltis documentation for you.","tool_calls":[]}}'
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
            '{"event":"AfterLLMCall","data":{"session_key":"session:qst","provider":"openai-codex","model":"openai-codex::gpt-5.4","text":"Нашёл официальную документацию Moltis. Давай изучу её полностью:","tool_calls":[]}}'
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
            '{"event":"AfterLLMCall","data":{"session_key":"session:qsu","provider":"openai-codex","model":"openai-codex::gpt-5.4","text":"Попробую найти навыки через mounted workspace:","tool_calls":[]}}'
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
            '{"event":"AfterLLMCall","data":{"session_key":"session:qsz","provider":"openai-codex","model":"openai-codex::gpt-5.4","text":"Хорошо! Давай найду темплейт навыка и структуру. Смотрю в директории skills:","tool_calls":[]}}'
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
            '{"event":"AfterLLMCall","data":{"session_key":"session:qsz2","provider":"openai-codex","model":"openai-codex::gpt-5.4","text":"Поищу темплейт в системе:","tool_calls":[]}}'
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
            '{"event":"AfterLLMCall","data":{"session_key":"session:qsz3","provider":"openai-codex","model":"openai-codex::gpt-5.4","text":"Ищу темплейт:","tool_calls":[]}}'
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
            '{"event":"AfterLLMCall","data":{"session_key":"session:qsv","provider":"openai-codex","model":"openai-codex::gpt-5.4","text":"Нашёл официальный репозиторий Moltis на GitHub. Давайте получу полную документацию:","tool_calls":[]}}'
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
            '{"event":"AfterLLMCall","data":{"session_key":"session:qsw","provider":"openai-codex","model":"openai-codex::gpt-5.4","text":"Пользователь просит изучить официальную документацию Moltis. У меня есть доступ к mcp__tavily__tavily_search, mcp__tavily__tavily_skill и create_skill. Сначала найду официальную документацию Moltis.","tool_calls":[]}}'
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
            '{"event":"AfterLLMCall","data":{"session_key":"session:qsx","provider":"openai-codex","model":"openai-codex::gpt-5.4","text":"Хорошо, изучу документацию Moltis и существующие навыки как примеры. Начну с поиска официальной документации и анализа имеющегося навыка codex-update, который как раз занимается проверкой версий.","tool_calls":[]}}'
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
            '{"event":"AfterLLMCall","data":{"session_key":"session:qsy","provider":"openai-codex","model":"openai-codex::gpt-5.4","text":"Отлично! Давай изучу официальную документацию и существующие навыки как примеры. Начну с поиска документации Moltis и анализа навыка codex-update (он как раз проверяет версии):","tool_calls":[]}}'
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
            '{"event":"AfterLLMCall","data":{"session_key":"session:qsy2","provider":"openai-codex","model":"openai-codex::gpt-5.4","text":"Хорошо, Сергей! Давай изучу официальную документацию Moltis и существующий навык `codex-update` как реальный пример. Начинаю:","tool_calls":[]}}'
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
            '{"event":"AfterLLMCall","data":{"session_key":"session:qsz","provider":"openai-codex","model":"openai-codex::gpt-5.4","text":"Давай наконец сделаю это! Читаю существующий навык `codex-update` как пример и найду документацию:","tool_calls":[]}}'
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$live_codex_update_reading_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$live_codex_update_reading_output" && \
       jq -e '.data.text | contains("не запускаю инструменты")' >/dev/null 2>&1 <<<"$live_codex_update_reading_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must suppress the exact live codex-update reading phrase captured by the runtime audit"
    fi

    test_start "component_after_llm_guard_rewrites_clean_codex_update_scheduler_false_negative"
    local after_llm_codex_update_scheduler_output
    after_llm_codex_update_scheduler_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_CODEX_UPDATE_RELEASE_JSON='{"tag_name":"0.118.0","published_at":"2026-04-01T12:00:00Z"}' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"AfterLLMCall","data":{"session_key":"session:codex-update-scheduler-after","provider":"openai-codex","model":"openai-codex::gpt-5.4","user_message":"А разе у тебя нет крона по проверке вышедшей новой версии Codex cli?","text":"Навык есть, но автопроверка по крону не подтверждена.","tool_calls":[]}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$after_llm_codex_update_scheduler_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$after_llm_codex_update_scheduler_output" && \
       jq -e '.data.text == "По проектному контракту у codex-update есть отдельный scheduler path для регулярной проверки обновлений Codex CLI каждые 6 часов. Но в Telegram-safe чате я не подтверждаю по памяти, что live cron сейчас действительно включён. Для точного статуса нужен операторский/runtime check, а не memory search."' >/dev/null 2>&1 <<<"$after_llm_codex_update_scheduler_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must rewrite a clean codex-update scheduler false negative into the canonical deterministic reply"
    fi

    test_start "component_after_llm_guard_blocks_exact_live_named_doc_search_plan_wording_from_runtime_audit"
    local live_named_doc_search_plan_output
    live_named_doc_search_plan_output="$(
        run_hook_with_minimal_path \
            '{"event":"AfterLLMCall","data":{"session_key":"session:qt0","provider":"openai-codex","model":"openai-codex::gpt-5.4","text":"Хорошо, Сергей! Давай изучу официальную документацию Moltis и существующий навык `codex-update` как реальный пример. Начинаю:","tool_calls":[]}}'
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
{"event":"BeforeLLMCall","data":{"session_key":"session:skillpersist-send","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"base system"},{"role":"user","content":"А что у тебя с навыками/skills?"}],"tool_count":37,"iteration":1}}
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

    test_start "component_message_sending_guard_rewrites_skill_detail_tool_error_into_runtime_skill_summary"
    local skill_detail_runtime_root message_sending_skill_detail_output skill_detail_runtime_fakebin
    skill_detail_runtime_root="$(secure_temp_dir telegram-safe-skill-detail-runtime)"
    skill_detail_runtime_fakebin="$skill_detail_runtime_root/fakebin"
    mkdir -p "$skill_detail_runtime_root/telegram-learner"
    mkdir -p "$skill_detail_runtime_fakebin"
    cp "$PROJECT_ROOT/skills/telegram-learner/SKILL.md" "$skill_detail_runtime_root/telegram-learner/SKILL.md"
    cat >"$skill_detail_runtime_fakebin/python3" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
    chmod +x "$skill_detail_runtime_fakebin/python3"
    message_sending_skill_detail_output="$(
        env PATH="$skill_detail_runtime_fakebin:$MINIMAL_PATH" \
            MOLTIS_RUNTIME_SKILLS_ROOT="$skill_detail_runtime_root" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,post-close-task-classifier,telegram-learner' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageSending","session_id":"session:skilldetail-send","data":{"account_id":"moltis-bot","to":"262872988","reply_to_message_id":959,"user_message":"Расскажи мне про навык telegram-lerner","text":"Похоже, у меня сейчас не сработало чтение файла навыка через инструмент. 📋 Activity log • 💻 Running: `cat /home/moltis/.moltis/skills/telegram-learner/SKILL.md` • ❌ missing 'command' parameter"}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$message_sending_skill_detail_output" && \
       jq -e '.data.text | contains("telegram-learner")' >/dev/null 2>&1 <<<"$message_sending_skill_detail_output" && \
       jq -e '.data.text | contains("@tsingular")' >/dev/null 2>&1 <<<"$message_sending_skill_detail_output" && \
       jq -e '.data.text | contains("Полезен, когда нужно быстро собрать новые практики")' >/dev/null 2>&1 <<<"$message_sending_skill_detail_output" && \
       jq -e '.data.text | contains("official docs, релизам, issues и официальному репозиторию")' >/dev/null 2>&1 <<<"$message_sending_skill_detail_output" && \
       jq -e '.data.text | contains("В Telegram-safe чате даю только краткое описание")' >/dev/null 2>&1 <<<"$message_sending_skill_detail_output" && \
       jq -e '.data.text | test("Похоже, ты имеешь в виду|Когда использовать:|Workflow:|Telegram-safe DM|Обычно он работает по шагам:|Сейчас в описании навыка указаны источники") | not' >/dev/null 2>&1 <<<"$message_sending_skill_detail_output" && \
       jq -e '.data.account_id == "moltis-bot"' >/dev/null 2>&1 <<<"$message_sending_skill_detail_output" && \
       jq -e '.data.to == "262872988"' >/dev/null 2>&1 <<<"$message_sending_skill_detail_output" && \
       jq -e '.data.reply_to_message_id == 959' >/dev/null 2>&1 <<<"$message_sending_skill_detail_output" && \
       jq -e 'has("data") and (.data | has("tool_calls") | not)' >/dev/null 2>&1 <<<"$message_sending_skill_detail_output"; then
        test_pass
    else
        test_fail "MessageSending guard must rewrite skill-detail tool failures into a deterministic runtime skill summary instead of leaking Activity log"
    fi

    test_start "component_message_sending_guard_rewrites_skill_detail_plain_runtime_failure_without_activity_log"
    local skill_detail_plain_dir message_sending_skill_detail_plain_output skill_detail_plain_fakebin
    skill_detail_plain_dir="$(secure_temp_dir telegram-safe-skill-detail-plain-runtime)"
    skill_detail_plain_fakebin="$skill_detail_plain_dir/fakebin"
    mkdir -p "$skill_detail_plain_dir/telegram-learner" "$skill_detail_plain_fakebin"
    cp "$PROJECT_ROOT/skills/telegram-learner/SKILL.md" "$skill_detail_plain_dir/telegram-learner/SKILL.md"
    cat >"$skill_detail_plain_fakebin/python3" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
    chmod +x "$skill_detail_plain_fakebin/python3"
    env PATH="$skill_detail_plain_fakebin:$MINIMAL_PATH" \
        MOLTIS_RUNTIME_SKILLS_ROOT="$skill_detail_plain_dir" \
        MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,post-close-task-classifier,telegram-learner' \
        bash "$HOOK_SCRIPT" <<'EOF' >/dev/null
{"event":"BeforeLLMCall","data":{"session_key":"session:skilldetail-plain","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=e83ca23c6e07 | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Расскажи мне про навык telegram-lerner"}],"tool_count":37,"iteration":1}}
EOF
    message_sending_skill_detail_plain_output="$(
        env PATH="$skill_detail_plain_fakebin:$MINIMAL_PATH" \
            MOLTIS_RUNTIME_SKILLS_ROOT="$skill_detail_plain_dir" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,post-close-task-classifier,telegram-learner' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageSending","session_id":"session:skilldetail-plain","data":{"account_id":"moltis-bot","to":"262872989","reply_to_message_id":960,"text":"Ладно, тут инструмент чтения снова сломан на самом вызове, так что честно: я по-прежнему не могу открыть `SKILL.md` и не буду сочинять детали."}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$message_sending_skill_detail_plain_output" && \
       jq -e '.data.text | contains("telegram-learner")' >/dev/null 2>&1 <<<"$message_sending_skill_detail_plain_output" && \
       jq -e '.data.text | contains("@tsingular")' >/dev/null 2>&1 <<<"$message_sending_skill_detail_plain_output" && \
       jq -e '.data.text | contains("Полезен, когда нужно быстро собрать новые практики")' >/dev/null 2>&1 <<<"$message_sending_skill_detail_plain_output" && \
       jq -e '.data.text | contains("official docs, релизам, issues и официальному репозиторию")' >/dev/null 2>&1 <<<"$message_sending_skill_detail_plain_output" && \
       jq -e '.data.text | contains("В Telegram-safe чате даю только краткое описание")' >/dev/null 2>&1 <<<"$message_sending_skill_detail_plain_output" && \
       jq -e '.data.text | test("Похоже, ты имеешь в виду|Когда использовать:|Workflow:|Telegram-safe DM|Обычно он работает по шагам:|Сейчас в описании навыка указаны источники") | not' >/dev/null 2>&1 <<<"$message_sending_skill_detail_plain_output" && \
       jq -e '.data.account_id == "moltis-bot"' >/dev/null 2>&1 <<<"$message_sending_skill_detail_plain_output" && \
       jq -e '.data.to == "262872989"' >/dev/null 2>&1 <<<"$message_sending_skill_detail_plain_output" && \
       jq -e '.data.reply_to_message_id == 960' >/dev/null 2>&1 <<<"$message_sending_skill_detail_plain_output" && \
       jq -e 'has("data") and (.data | has("tool_calls") | not)' >/dev/null 2>&1 <<<"$message_sending_skill_detail_plain_output"; then
        test_pass
    else
        test_fail "MessageSending guard must rewrite plain skill-detail runtime failures even when the raw delivery text no longer includes Activity log"
    fi

    test_start "component_message_sending_guard_rewrites_similar_learner_skill_into_clean_runtime_summary"
    local similar_learner_dir message_sending_similar_learner_output similar_learner_fakebin
    similar_learner_dir="$(secure_temp_dir telegram-safe-similar-learner-runtime)"
    similar_learner_fakebin="$similar_learner_dir/fakebin"
    mkdir -p "$similar_learner_dir/openclaw-improvement-learner" "$similar_learner_fakebin"
    cp "$PROJECT_ROOT/skills/openclaw-improvement-learner/SKILL.md" "$similar_learner_dir/openclaw-improvement-learner/SKILL.md"
    cat >"$similar_learner_fakebin/python3" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
    chmod +x "$similar_learner_fakebin/python3"
    message_sending_similar_learner_output="$(
        env PATH="$similar_learner_fakebin:$MINIMAL_PATH" \
            MOLTIS_RUNTIME_SKILLS_ROOT="$similar_learner_dir" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,openclaw-improvement-learner,telegram-learner' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageSending","session_id":"session:similar-learner","data":{"account_id":"moltis-bot","to":"262872990","reply_to_message_id":961,"user_message":"Расскажи мне про навык openclaw-improvement-learner","text":"Сейчас скажу честно: инструмент чтения навыка опять не сработал. 📋 Activity log • 💻 Running: `cat /home/moltis/.moltis/skills/openclaw-improvement-learner/SKILL.md` • ❌ missing 'command' parameter"}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$message_sending_similar_learner_output" && \
       jq -e '.data.text | contains("openclaw-improvement-learner")' >/dev/null 2>&1 <<<"$message_sending_similar_learner_output" && \
       jq -e '.data.text | contains("какие upstream-изменения и инструкции по OpenClaw стоит внедрять")' >/dev/null 2>&1 <<<"$message_sending_similar_learner_output" && \
       jq -e '.data.text | contains("official docs, releases, changelog и issues OpenClaw")' >/dev/null 2>&1 <<<"$message_sending_similar_learner_output" && \
       jq -e '.data.text | contains("В Telegram-safe чате даю только краткое описание и приоритеты")' >/dev/null 2>&1 <<<"$message_sending_similar_learner_output" && \
       jq -e '.data.text | test("Activity log|SKILL.md|/home/moltis|missing '\''command'\'' parameter|Обычно он работает по шагам:|Сейчас в описании навыка указаны источники") | not' >/dev/null 2>&1 <<<"$message_sending_similar_learner_output" && \
       jq -e '.data.account_id == "moltis-bot"' >/dev/null 2>&1 <<<"$message_sending_similar_learner_output" && \
       jq -e '.data.to == "262872990"' >/dev/null 2>&1 <<<"$message_sending_similar_learner_output" && \
       jq -e '.data.reply_to_message_id == 961' >/dev/null 2>&1 <<<"$message_sending_similar_learner_output"; then
        test_pass
    else
        test_fail "MessageSending guard must produce the same clean learner-style summary for a similar runtime learner skill"
    fi

    test_start "component_message_sending_guard_rewrites_codex_update_skill_detail_into_clean_runtime_summary"
    local codex_update_skill_dir message_sending_codex_update_skill_output codex_update_skill_fakebin
    codex_update_skill_dir="$(secure_temp_dir telegram-safe-codex-update-detail-runtime)"
    codex_update_skill_fakebin="$codex_update_skill_dir/fakebin"
    mkdir -p "$codex_update_skill_dir/codex-update" "$codex_update_skill_fakebin"
    cp "$PROJECT_ROOT/skills/codex-update/SKILL.md" "$codex_update_skill_dir/codex-update/SKILL.md"
    cat >"$codex_update_skill_fakebin/python3" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
    chmod +x "$codex_update_skill_fakebin/python3"
    message_sending_codex_update_skill_output="$(
        env PATH="$codex_update_skill_fakebin:$MINIMAL_PATH" \
            MOLTIS_RUNTIME_SKILLS_ROOT="$codex_update_skill_dir" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,post-close-task-classifier,telegram-learner' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageSending","session_id":"session:codex-update-detail","data":{"account_id":"moltis-bot","to":"262872991","reply_to_message_id":962,"user_message":"Расскажи мне про навык codex-update","text":"Инструмент чтения навыка не сработал. 📋 Activity log • 🔧 mcp__tavily__tavily_search • ❌ missing 'command' parameter"}} 
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$message_sending_codex_update_skill_output" && \
       jq -e '.data.text | contains("codex-update")' >/dev/null 2>&1 <<<"$message_sending_codex_update_skill_output" && \
       jq -e '.data.text | contains("новая стабильная версия Codex CLI")' >/dev/null 2>&1 <<<"$message_sending_codex_update_skill_output" && \
       jq -e '.data.text | contains("без ручного обхода релизов и changelog")' >/dev/null 2>&1 <<<"$message_sending_codex_update_skill_output" && \
       jq -e '.data.text | contains("official releases, changelog и runtime state helper")' >/dev/null 2>&1 <<<"$message_sending_codex_update_skill_output" && \
       jq -e '.data.text | contains("В Telegram-safe чате даю только короткий advisory")' >/dev/null 2>&1 <<<"$message_sending_codex_update_skill_output" && \
       jq -e '.data.text | test("Activity log|SKILL.md|/server|/home/moltis|make codex-update|Remote-safe Moltis skill") | not' >/dev/null 2>&1 <<<"$message_sending_codex_update_skill_output"; then
        test_pass
    else
        test_fail "MessageSending guard must rewrite codex-update skill-detail failures into a clean Telegram-safe summary instead of falling back to operator-heavy description text"
    fi

    test_start "component_before_llm_guard_hard_overrides_codex_update_maintenance_turn"
    local before_llm_codex_update_maintenance_output
    before_llm_codex_update_maintenance_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$(secure_temp_dir telegram-safe-codex-update-maintenance-before)" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:codex-update-maintenance-before","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872995 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Давай починим codex-update: в Telegram течёт Activity log и missing 'query' parameter"}],"tool_count":37,"iteration":1}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_llm_codex_update_maintenance_output" && \
       jq -e '.data.messages | length == 2' >/dev/null 2>&1 <<<"$before_llm_codex_update_maintenance_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe maintenance hard override")' >/dev/null 2>&1 <<<"$before_llm_codex_update_maintenance_output" && \
       jq -e '.data.messages[0].content | contains("не чиню и не отлаживаю `codex-update`")' >/dev/null 2>&1 <<<"$before_llm_codex_update_maintenance_output" && \
       jq -e '.data.messages[1].content == "Верни в ответ ровно указанную в системном сообщении фразу. Не добавляй ничего."' >/dev/null 2>&1 <<<"$before_llm_codex_update_maintenance_output" && \
       jq -e '.data.tool_count == 0' >/dev/null 2>&1 <<<"$before_llm_codex_update_maintenance_output"; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must terminalize codex-update maintenance/debug turns into a deterministic text-only boundary reply"
    fi

    test_start "component_before_llm_guard_hard_overrides_generic_maintenance_turn_without_explicit_subject"
    local before_llm_generic_maintenance_output
    before_llm_generic_maintenance_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$(secure_temp_dir telegram-safe-generic-maintenance-before)" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:generic-maintenance-before","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872998 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Посмотри логи и найди root cause, там снова Activity log и missing 'query' parameter"}],"tool_count":37,"iteration":1}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_llm_generic_maintenance_output" && \
       jq -e '.data.messages | length == 2' >/dev/null 2>&1 <<<"$before_llm_generic_maintenance_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe maintenance hard override")' >/dev/null 2>&1 <<<"$before_llm_generic_maintenance_output" && \
       jq -e '.data.messages[0].content | contains("не провожу repair/debug/log inspection")' >/dev/null 2>&1 <<<"$before_llm_generic_maintenance_output" && \
       jq -e '.data.messages[1].content == "Верни в ответ ровно указанную в системном сообщении фразу. Не добавляй ничего."' >/dev/null 2>&1 <<<"$before_llm_generic_maintenance_output" && \
       jq -e '.data.tool_count == 0' >/dev/null 2>&1 <<<"$before_llm_generic_maintenance_output"; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must fail-close generic log/root-cause maintenance turns even when the user omitted an explicit skill or codex-update subject"
    fi

    test_start "component_before_llm_guard_hard_overrides_live_tool_broken_confirmation_turn"
    local before_llm_tool_broken_confirmation_output
    before_llm_tool_broken_confirmation_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$(secure_temp_dir telegram-safe-tool-broken-before)" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:tool-broken-confirmation","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Ты проверил, что инструменты сломаны? Убедился?"}],"tool_count":37,"iteration":1}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_llm_tool_broken_confirmation_output" && \
       jq -e '.data.messages | length == 2' >/dev/null 2>&1 <<<"$before_llm_tool_broken_confirmation_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe maintenance hard override")' >/dev/null 2>&1 <<<"$before_llm_tool_broken_confirmation_output" && \
       jq -e '.data.messages[0].content | contains("не провожу repair/debug/log inspection")' >/dev/null 2>&1 <<<"$before_llm_tool_broken_confirmation_output" && \
       jq -e '.data.messages[1].content == "Верни в ответ ровно указанную в системном сообщении фразу. Не добавляй ничего."' >/dev/null 2>&1 <<<"$before_llm_tool_broken_confirmation_output" && \
       jq -e '.data.tool_count == 0' >/dev/null 2>&1 <<<"$before_llm_tool_broken_confirmation_output"; then
        test_pass
    else
        test_fail "BeforeLLMCall guard must classify the live 'инструменты сломаны' confirmation as Telegram-safe maintenance instead of letting the model prove tool breakage"
    fi

    test_start "component_before_llm_guard_direct_fastpaths_codex_update_maintenance_when_enabled"
    local fastpath_maintenance_tmp fastpath_maintenance_send_script fastpath_maintenance_log fastpath_maintenance_stdout fastpath_maintenance_stderr fastpath_maintenance_status fastpath_maintenance_intent_dir fastpath_maintenance_suppress_file
    fastpath_maintenance_tmp="$(secure_temp_dir telegram-safe-fastpath-maintenance)"
    fastpath_maintenance_send_script="$fastpath_maintenance_tmp/send.sh"
    fastpath_maintenance_log="$fastpath_maintenance_tmp/send.log"
    fastpath_maintenance_intent_dir="$fastpath_maintenance_tmp/intent"
    fastpath_maintenance_suppress_file="$fastpath_maintenance_intent_dir/session_fastmaintenance.suppress"
    cat >"$fastpath_maintenance_send_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
chat_id=""
text=""
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
        *)
            shift
            ;;
    esac
done
printf 'chat_id=%s\ntext=%s\n' "$chat_id" "$text" >"$FASTPATH_LOG"
printf '{"ok":true}\n'
EOF
    chmod +x "$fastpath_maintenance_send_script"
    fastpath_maintenance_stdout="$fastpath_maintenance_tmp/stdout.log"
    fastpath_maintenance_stderr="$fastpath_maintenance_tmp/stderr.log"
    set +e
    env PATH="$MINIMAL_PATH" \
        FASTPATH_LOG="$fastpath_maintenance_log" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$fastpath_maintenance_intent_dir" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$fastpath_maintenance_send_script" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_SCRIPT="$HOOK_SCRIPT" \
        bash "$HOOK_HANDLER" >"$fastpath_maintenance_stdout" 2>"$fastpath_maintenance_stderr" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:fastmaintenance","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872999 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Давай починим codex-update: в Telegram течёт Activity log и missing 'query' parameter"}],"tool_count":37,"iteration":1}}
EOF
    fastpath_maintenance_status=$?
    set -e
    if [[ "$fastpath_maintenance_status" -eq 0 ]] && \
       [[ ! -s "$fastpath_maintenance_stderr" ]] && \
       jq -e '.action == "block"' >/dev/null 2>&1 "$fastpath_maintenance_stdout" && \
       [[ -f "$fastpath_maintenance_suppress_file" ]] && \
       grep -Fq $'\tmaintenance:codex_update' "$fastpath_maintenance_suppress_file" && \
       grep -Fq 'chat_id=262872999' "$fastpath_maintenance_log" && \
       grep -Fq 'text=В Telegram-safe режиме я не чиню и не отлаживаю `codex-update`' "$fastpath_maintenance_log"; then
        test_pass
    else
        test_fail "Direct maintenance fastpath must send the deterministic codex-update boundary reply, store only a delivery-suppression marker, and hard-block the ignored runtime LLM pass"
    fi

    test_start "component_before_llm_guard_direct_fastpaths_codex_update_context_questions_when_enabled"
    local fastpath_context_tmp fastpath_context_send_script fastpath_context_log fastpath_context_stdout fastpath_context_stderr fastpath_context_status fastpath_context_intent_dir fastpath_context_suppress_file
    fastpath_context_tmp="$(secure_temp_dir telegram-safe-fastpath-context)"
    fastpath_context_send_script="$fastpath_context_tmp/send.sh"
    fastpath_context_log="$fastpath_context_tmp/send.log"
    fastpath_context_intent_dir="$fastpath_context_tmp/intent"
    fastpath_context_suppress_file="$fastpath_context_intent_dir/session_fastcontext.suppress"
    cat >"$fastpath_context_send_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
chat_id=""
text=""
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
        *)
            shift
            ;;
    esac
done
printf 'chat_id=%s\ntext=%s\n' "$chat_id" "$text" >"$FASTPATH_LOG"
printf '{"ok":true}\n'
EOF
    chmod +x "$fastpath_context_send_script"
    fastpath_context_stdout="$fastpath_context_tmp/stdout.log"
    fastpath_context_stderr="$fastpath_context_tmp/stderr.log"
    set +e
    env PATH="$MINIMAL_PATH" \
        FASTPATH_LOG="$fastpath_context_log" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$fastpath_context_intent_dir" \
        MOLTIS_TELEGRAM_SAFE_DIRECT_SEND_SCRIPT="$fastpath_context_send_script" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_SCRIPT="$HOOK_SCRIPT" \
        bash "$HOOK_HANDLER" >"$fastpath_context_stdout" 2>"$fastpath_context_stderr" <<'EOF'
{"event":"BeforeLLMCall","data":{"session_key":"session:fastcontext","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262873011 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Какая сейчас схема работы у навыка codex-update?"}],"tool_count":37,"iteration":1}}
EOF
    fastpath_context_status=$?
    set -e
    if [[ "$fastpath_context_status" -eq 0 ]] && \
       [[ ! -s "$fastpath_context_stderr" ]] && \
       jq -e '.action == "block"' >/dev/null 2>&1 "$fastpath_context_stdout" && \
       [[ -f "$fastpath_context_suppress_file" ]] && \
       grep -Fq $'\tcodex_update:context' "$fastpath_context_suppress_file" && \
       grep -Fq 'chat_id=262873011' "$fastpath_context_log" && \
       grep -Fq 'После исправлений схема такая' "$fastpath_context_log" && \
       grep -Fq 'каждые 6 часов' "$fastpath_context_log" && \
       grep -Fq 'last_alert_fingerprint' "$fastpath_context_log" && \
       grep -Fq 'suppressed' "$fastpath_context_log" && \
       ! grep -Fq 'показывает, есть ли новая стабильная версия' "$fastpath_context_log"; then
        test_pass
    else
        test_fail "Direct codex-update context fastpath must send the deterministic current-scheme reply, store the context suppression marker, and hard-block the ignored runtime LLM pass"
    fi

    test_start "component_message_sending_guard_rewrites_codex_update_maintenance_leak_into_boundary_reply"
    local codex_update_maintenance_intent_dir codex_update_maintenance_message_output
    codex_update_maintenance_intent_dir="$(secure_temp_dir telegram-safe-codex-update-maintenance-message)"
    env PATH="$MINIMAL_PATH" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$codex_update_maintenance_intent_dir" \
        bash "$HOOK_SCRIPT" <<'EOF' >/dev/null
{"event":"BeforeLLMCall","data":{"session_key":"session:codex-update-maintenance-message","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872995 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Давай починим codex-update: в Telegram течёт Activity log и missing 'query' parameter"}],"tool_count":37,"iteration":1}}
EOF
    codex_update_maintenance_message_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$codex_update_maintenance_intent_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageSending","session_id":"session:codex-update-maintenance-message","data":{"account_id":"moltis-bot","to":"262872995","reply_to_message_id":965,"text":"Если хочешь, я сразу напишу готовую новую версию инструкции для скилла, где будет: проверка официальной версии.\n\n📋 Activity log\n• 💻 Running: `sed -n '1,220p' /home/moltis/.moltis/skills/codex-update/SKILL.md`\n• 🧠 Searching memory...\n• ❌ missing 'command' parameter\n• ❌ missing 'query' parameter"}} 
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$codex_update_maintenance_message_output" && \
       jq -e '.data.text | contains("не чиню и не отлаживаю `codex-update`")' >/dev/null 2>&1 <<<"$codex_update_maintenance_message_output" && \
       jq -e '.data.text | contains("CRUD-команду на создание, обновление, патч или удаление навыка")' >/dev/null 2>&1 <<<"$codex_update_maintenance_message_output" && \
       jq -e '.data.text | contains("web UI/операторской сессии")' >/dev/null 2>&1 <<<"$codex_update_maintenance_message_output" && \
       jq -e '.data.reply_to_message_id == 965' >/dev/null 2>&1 <<<"$codex_update_maintenance_message_output" && \
       jq -e '.data.text | test("Activity log|Running:|Searching memory|missing '\''command'\'' parameter|missing '\''query'\'' parameter|SKILL.md|/home/moltis|create_skill|update_skill|patch_skill|delete_skill|write_skill_files") | not' >/dev/null 2>&1 <<<"$codex_update_maintenance_message_output"; then
        test_pass
    else
        test_fail "MessageSending guard must rewrite leaked codex-update maintenance/debug runtime chatter into the deterministic Telegram-safe boundary reply"
    fi

    test_start "component_message_sending_guard_rewrites_live_plain_tool_runtime_diagnostic_chatter"
    local plain_tool_runtime_diagnostic_output
    plain_tool_runtime_diagnostic_output="$(
        env PATH="$MINIMAL_PATH" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageSending","session_id":"session:plain-tool-runtime-diagnostic","data":{"account_id":"moltis-bot","to":"262872984","reply_to_message_id":1435,"user_message":"Ты не можешь настроить отправку новости о новой версии один раз?","text":"Могу. Логика понятная: хранить `last_announced_version`, и если cron снова видит ту же версию — ничего не слать.\n\nНо прямо сейчас именно настроить сам я не могу, потому что в этой сессии инструменты сломаны: даже базовые вызовы чтения skill, памяти, cron и shell возвращают ошибки вида `missing 'name'`, `missing 'query'`, `missing 'action'`, `missing 'command'` при корректных аргументах."}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$plain_tool_runtime_diagnostic_output" && \
       jq -e '.data.text | contains("не запускаю инструменты и не показываю внутренние логи")' >/dev/null 2>&1 <<<"$plain_tool_runtime_diagnostic_output" && \
       jq -e '.data.reply_to_message_id == 1435' >/dev/null 2>&1 <<<"$plain_tool_runtime_diagnostic_output" && \
       jq -e '.data.text | test("missing '\''name'\''|missing '\''query'\''|missing '\''action'\''|missing '\''command'\''|инструменты сломаны|read_skill|memory_search|cron|shell") | not' >/dev/null 2>&1 <<<"$plain_tool_runtime_diagnostic_output"; then
        test_pass
    else
        test_fail "MessageSending guard must rewrite plain live tool-runtime diagnostic chatter even when the leaked text does not use the word parameter"
    fi

    test_start "component_message_sending_guard_rewrites_plain_skill_maintenance_runtime_failure"
    local skill_maintenance_intent_dir skill_maintenance_plain_message_output
    skill_maintenance_intent_dir="$(secure_temp_dir telegram-safe-skill-maintenance-plain)"
    env PATH="$MINIMAL_PATH" \
        MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$skill_maintenance_intent_dir" \
        MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,post-close-task-classifier,telegram-learner' \
        bash "$HOOK_SCRIPT" <<'EOF' >/dev/null
{"event":"BeforeLLMCall","data":{"session_key":"session:skill-maintenance-plain","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872996 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Почини навык post-close-task-classifier: в ответе течёт Activity log и сырые tool errors"}],"tool_count":37,"iteration":1}}
EOF
    skill_maintenance_plain_message_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$skill_maintenance_intent_dir" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,post-close-task-classifier,telegram-learner' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageSending","session_id":"session:skill-maintenance-plain","data":{"account_id":"moltis-bot","to":"262872996","reply_to_message_id":966,"text":"Я бы хотел сначала открыть SKILL.md и посмотреть внутренние логи, но вызов exec сейчас сам падает с missing 'command' parameter, поэтому без runtime-диагностики я не починю этот навык."}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$skill_maintenance_plain_message_output" && \
       jq -e '.data.text | contains("навык `post-close-task-classifier`")' >/dev/null 2>&1 <<<"$skill_maintenance_plain_message_output" && \
       jq -e '.data.text | contains("CRUD-команду на создание, обновление, патч или удаление навыка")' >/dev/null 2>&1 <<<"$skill_maintenance_plain_message_output" && \
       jq -e '.data.text | contains("web UI/операторской сессии")' >/dev/null 2>&1 <<<"$skill_maintenance_plain_message_output" && \
       jq -e '.data.reply_to_message_id == 966' >/dev/null 2>&1 <<<"$skill_maintenance_plain_message_output" && \
       jq -e '.data.text | test("Activity log|missing '\''command'\'' parameter|SKILL.md|exec|/home/moltis|create_skill|update_skill|patch_skill|delete_skill|write_skill_files") | not' >/dev/null 2>&1 <<<"$skill_maintenance_plain_message_output"; then
        test_pass
    else
        test_fail "MessageSending guard must rewrite plain skill-maintenance runtime failures even when the leaked text no longer includes an explicit Activity log block"
    fi

    test_start "component_after_llm_guard_rewrites_codex_update_maintenance_leak_into_boundary_reply"
    local codex_update_maintenance_after_output
    codex_update_maintenance_after_output="$(
        env PATH="$MINIMAL_PATH" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"AfterLLMCall","data":{"session_key":"session:codex-update-maintenance-after","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262873000 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Давай починим codex-update: в Telegram течёт Activity log и missing 'query' parameter"}],"text":"Сейчас посмотрю логи и открою SKILL.md, потому что exec и memory_search падают с missing 'command' parameter и missing 'query' parameter.","tool_calls":[]}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$codex_update_maintenance_after_output" && \
       jq -e '.data.text | contains("не чиню и не отлаживаю `codex-update`")' >/dev/null 2>&1 <<<"$codex_update_maintenance_after_output" && \
       jq -e '.data.text | contains("web UI/операторской сессии")' >/dev/null 2>&1 <<<"$codex_update_maintenance_after_output" && \
       jq -e '.data.text | test("Activity log|SKILL.md|missing '\''command'\'' parameter|missing '\''query'\'' parameter") | not' >/dev/null 2>&1 <<<"$codex_update_maintenance_after_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must rewrite codex-update maintenance/debug chatter into the deterministic Telegram-safe boundary reply before final delivery"
    fi

    test_start "component_after_llm_guard_keeps_explicit_update_skill_flow_out_of_maintenance_bucket"
    local after_llm_update_skill_control_output
    after_llm_update_skill_control_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,post-close-task-classifier,telegram-learner' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"AfterLLMCall","data":{"session_key":"session:update-skill-control","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872997 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Обнови навык codex-update: замени description на более краткий advisory"}],"text":"Сейчас обновлю навык через update_skill без filesystem-проб.","tool_calls":[{"name":"update_skill","arguments":{"name":"codex-update","description":"Более краткий advisory"}}]}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$after_llm_update_skill_control_output" && \
       jq -e '.data.text == "Выполняю запрос по навыкам через встроенные инструменты без filesystem-проб. После завершения вернусь с итогом."' >/dev/null 2>&1 <<<"$after_llm_update_skill_control_output" && \
       jq -e '.data.text | contains("не чиню и не отлаживаю") | not' >/dev/null 2>&1 <<<"$after_llm_update_skill_control_output"; then
        test_pass
    else
        test_fail "Explicit update_skill CRUD turns must keep the allowlisted skill-authoring flow and must not be rewritten as maintenance/debug"
    fi

    test_start "component_after_llm_guard_rewrites_codex_update_scheduler_question_into_remote_safe_contract_reply"
    local codex_update_scheduler_after_output
    codex_update_scheduler_after_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$(secure_temp_dir telegram-safe-codex-update-scheduler-after)" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"AfterLLMCall","session_key":"session:codex-update-scheduler-after","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262872993 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"А разе у тебя нет крона по проверке вышедшей новой версии Codex cli?"}],"text":"Не вижу подтверждения, что такой крон у меня есть. Я бы хотел это проверить по памяти/расписанию, но инструмент поиска памяти сейчас тоже отвечает криво.","tool_calls":[{"name":"mcp__mempalace__search","arguments":{"query":"codex cli cron watcher"}}]}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$codex_update_scheduler_after_output" && \
       jq -e '.data.text | contains("scheduler path для регулярной проверки обновлений Codex CLI")' >/dev/null 2>&1 <<<"$codex_update_scheduler_after_output" && \
       jq -e '.data.text | contains("каждые 6 часов")' >/dev/null 2>&1 <<<"$codex_update_scheduler_after_output" && \
       jq -e '.data.text | contains("не подтверждаю по памяти")' >/dev/null 2>&1 <<<"$codex_update_scheduler_after_output" && \
       jq -e '.data.text | contains("операторский/runtime check")' >/dev/null 2>&1 <<<"$codex_update_scheduler_after_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$codex_update_scheduler_after_output" && \
       jq -e '.data.text | test("Activity log|Searching memory|missing '\''query'\'' parameter|памяти/расписанию|криво") | not' >/dev/null 2>&1 <<<"$codex_update_scheduler_after_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must rewrite codex-update scheduler questions into the deterministic remote-safe contract instead of leaving memory/tool reasoning in place"
    fi

    test_start "component_after_llm_guard_rewrites_codex_update_context_questions_into_current_scheme_reply"
    local codex_update_context_after_output
    codex_update_context_after_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$(secure_temp_dir telegram-safe-codex-update-context-after)" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"AfterLLMCall","session_key":"session:codex-update-context-after","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=00cde7cf989d | channel_account=moltis-bot | channel_chat_id=262873012 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Что изменилось в навыке codex-update после исправлений?"}],"text":"codex-update — показывает, есть ли новая стабильная версия Codex CLI, почему это важно и что стоит делать дальше.","tool_calls":[]}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$codex_update_context_after_output" && \
       jq -e '.data.text | contains("После исправлений схема такая")' >/dev/null 2>&1 <<<"$codex_update_context_after_output" && \
       jq -e '.data.text | contains("каждые 6 часов")' >/dev/null 2>&1 <<<"$codex_update_context_after_output" && \
       jq -e '.data.text | contains("last_alert_fingerprint")' >/dev/null 2>&1 <<<"$codex_update_context_after_output" && \
       jq -e '.data.text | contains("suppressed")' >/dev/null 2>&1 <<<"$codex_update_context_after_output" && \
       jq -e '.data.tool_calls == []' >/dev/null 2>&1 <<<"$codex_update_context_after_output" && \
       jq -e '.data.text | test("показывает, есть ли новая стабильная версия|Activity log|Searching memory|missing '\''query'\'' parameter|missing '\''command'\'' parameter") | not' >/dev/null 2>&1 <<<"$codex_update_context_after_output"; then
        test_pass
    else
        test_fail "AfterLLMCall guard must rewrite codex-update history/scheme questions into the deterministic current-scheme contract instead of leaving them in generic skill-detail wording"
    fi

    test_start "component_message_sending_guard_rewrites_codex_update_scheduler_memory_leak_into_remote_safe_contract_reply"
    local codex_update_scheduler_message_output
    codex_update_scheduler_message_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$(secure_temp_dir telegram-safe-codex-update-scheduler-message)" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageSending","session_id":"session:codex-update-scheduler-message","data":{"account_id":"moltis-bot","to":"262872994","reply_to_message_id":964,"user_message":"А разе у тебя нет крона по проверке вышедшей новой версии Codex cli?","text":"Не вижу подтверждения, что такой крон у меня есть.\n\nЯ бы хотел это проверить по памяти/расписанию, но инструмент поиска памяти сейчас тоже отвечает криво, так что честно: подтвердить наличие такого крона я сейчас не могу.\n\n📋 Activity log\n• 🧠 Searching memory...\n• ❌ missing 'query' parameter"}} 
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$codex_update_scheduler_message_output" && \
       jq -e '.data.text | contains("scheduler path для регулярной проверки обновлений Codex CLI")' >/dev/null 2>&1 <<<"$codex_update_scheduler_message_output" && \
       jq -e '.data.text | contains("каждые 6 часов")' >/dev/null 2>&1 <<<"$codex_update_scheduler_message_output" && \
       jq -e '.data.text | contains("не подтверждаю по памяти")' >/dev/null 2>&1 <<<"$codex_update_scheduler_message_output" && \
       jq -e '.data.text | contains("операторский/runtime check")' >/dev/null 2>&1 <<<"$codex_update_scheduler_message_output" && \
       jq -e '.data.reply_to_message_id == 964' >/dev/null 2>&1 <<<"$codex_update_scheduler_message_output" && \
       jq -e '.data.text | test("Activity log|Searching memory|missing '\''query'\'' parameter|памяти/расписанию|криво") | not' >/dev/null 2>&1 <<<"$codex_update_scheduler_message_output"; then
        test_pass
    else
        test_fail "MessageSending guard must replace codex-update scheduler memory leaks with the deterministic remote-safe contract reply"
    fi

    test_start "component_message_sending_current_scheduler_turn_overrides_stale_persisted_codex_update_context_intent"
    local codex_update_stale_context_dir codex_update_stale_context_output codex_update_stale_context_intent_file
    codex_update_stale_context_dir="$(secure_temp_dir telegram-safe-codex-update-stale-context)"
    codex_update_stale_context_intent_file="$codex_update_stale_context_dir/session_codexscheduleoverride.intent"
    printf '%s\t%s\t%s\n' "$(date +%s)" "codex_update_context" "" >"$codex_update_stale_context_intent_file"
    codex_update_stale_context_output="$(
        env PATH="$MINIMAL_PATH" \
            MOLTIS_TELEGRAM_SAFE_LLM_GUARD_INTENT_DIR="$codex_update_stale_context_dir" \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageSending","session_id":"session:codexscheduleoverride","data":{"account_id":"moltis-bot","to":"262872995","reply_to_message_id":966,"user_message":"По какому расписанию сейчас работает навык codex-update?","text":"Раньше повторные сообщения про Codex CLI появлялись из-за дефекта старого контура дедупликации. После исправлений схема такая: scheduler path проверяет официальный upstream Codex CLI каждые 6 часов."}}
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$codex_update_stale_context_output" && \
       jq -e '.data.text | contains("scheduler path для регулярной проверки обновлений Codex CLI")' >/dev/null 2>&1 <<<"$codex_update_stale_context_output" && \
       jq -e '.data.text | contains("каждые 6 часов")' >/dev/null 2>&1 <<<"$codex_update_stale_context_output" && \
       jq -e '.data.text | contains("операторский/runtime check")' >/dev/null 2>&1 <<<"$codex_update_stale_context_output" && \
       jq -e '.data.reply_to_message_id == 966' >/dev/null 2>&1 <<<"$codex_update_stale_context_output" && \
       jq -e '.data.text | test("После исправлений схема такая|last_alert_fingerprint|suppressed") | not' >/dev/null 2>&1 <<<"$codex_update_stale_context_output"; then
        test_pass
    else
        test_fail "A current codex-update scheduler turn must override stale persisted context intent during final MessageSending rewriting"
    fi

    test_start "component_message_sending_guard_rewrites_post_close_classifier_skill_detail_into_clean_runtime_summary"
    local classifier_skill_dir message_sending_classifier_skill_output classifier_skill_fakebin
    classifier_skill_dir="$(secure_temp_dir telegram-safe-post-close-classifier-detail-runtime)"
    classifier_skill_fakebin="$classifier_skill_dir/fakebin"
    mkdir -p "$classifier_skill_dir/post-close-task-classifier" "$classifier_skill_fakebin"
    cp "$PROJECT_ROOT/skills/post-close-task-classifier/SKILL.md" "$classifier_skill_dir/post-close-task-classifier/SKILL.md"
    cat >"$classifier_skill_fakebin/python3" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
    chmod +x "$classifier_skill_fakebin/python3"
    message_sending_classifier_skill_output="$(
        env PATH="$classifier_skill_fakebin:$MINIMAL_PATH" \
            MOLTIS_RUNTIME_SKILLS_ROOT="$classifier_skill_dir" \
            MOLTIS_TELEGRAM_SAFE_SKILL_SNAPSHOT_NAMES='codex-update,post-close-task-classifier,telegram-learner' \
            bash "$HOOK_SCRIPT" <<'EOF'
{"event":"MessageSending","session_id":"session:classifier-detail","data":{"account_id":"moltis-bot","to":"262872992","reply_to_message_id":963,"user_message":"Расскажи мне про навык post-close-task-classifier","text":"Инструмент чтения навыка не сработал. 📋 Activity log • 🔧 exec • ❌ missing 'command' parameter"}} 
EOF
    )"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$message_sending_classifier_skill_output" && \
       jq -e '.data.text | contains("post-close-task-classifier")' >/dev/null 2>&1 <<<"$message_sending_classifier_skill_output" && \
       jq -e '.data.text | contains("можно ли продолжать работу в текущей ветке")' >/dev/null 2>&1 <<<"$message_sending_classifier_skill_output" && \
       jq -e '.data.text | contains("после формального закрытия ветки появляются новые ошибки")' >/dev/null 2>&1 <<<"$message_sending_classifier_skill_output" && \
       jq -e '.data.text | contains("canonical rule artifact про post-close classification")' >/dev/null 2>&1 <<<"$message_sending_classifier_skill_output" && \
       jq -e '.data.text | contains("В Telegram-safe чате даю только краткий verdict и boundary")' >/dev/null 2>&1 <<<"$message_sending_classifier_skill_output" && \
       jq -e '.data.text | test("Activity log|Prepared prompt|Verdict|authoritative worktree|SKILL.md|/server|/home/moltis") | not' >/dev/null 2>&1 <<<"$message_sending_classifier_skill_output"; then
        test_pass
    else
        test_fail "MessageSending guard must rewrite post-close-task-classifier skill-detail failures into a clean Telegram-safe summary instead of leaking policy-template wording"
    fi

    test_start "component_telegram_bot_send_prefers_env_token_when_env_file_is_unreadable"
    local telegram_send_tmp telegram_send_fakebin telegram_send_env telegram_send_stdout telegram_send_stderr telegram_send_status telegram_send_curl_log telegram_send_curl_stdin
    telegram_send_tmp="$(secure_temp_dir telegram-bot-send-env-token)"
    telegram_send_fakebin="$telegram_send_tmp/fakebin"
    telegram_send_env="$telegram_send_tmp/unreadable.env"
    telegram_send_stdout="$telegram_send_tmp/stdout.log"
    telegram_send_stderr="$telegram_send_tmp/stderr.log"
    telegram_send_curl_log="$telegram_send_tmp/curl.log"
    telegram_send_curl_stdin="$telegram_send_tmp/curl-stdin.log"
    mkdir -p "$telegram_send_fakebin"
    printf 'TELEGRAM_BOT_TOKEN=from-file-should-not-be-needed\n' >"$telegram_send_env"
    chmod 000 "$telegram_send_env"
cat >"$telegram_send_fakebin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"$CURL_LOG"
stdin_config="$(cat)"
printf '%s' "$stdin_config" >"$CURL_STDIN_LOG"
printf '{"ok":true}\n'
EOF
    chmod +x "$telegram_send_fakebin/curl"
    set +e
    env PATH="$telegram_send_fakebin:$MINIMAL_PATH" \
        TELEGRAM_BOT_TOKEN="env-token-123" \
        MOLTIS_ENV_FILE="$telegram_send_env" \
        CURL_LOG="$telegram_send_curl_log" \
        CURL_STDIN_LOG="$telegram_send_curl_stdin" \
        bash "$PROJECT_ROOT/scripts/telegram-bot-send.sh" --chat-id 42 --text "hello from test" >"$telegram_send_stdout" 2>"$telegram_send_stderr"
    telegram_send_status=$?
    set -e
    chmod 600 "$telegram_send_env"
    if [[ "$telegram_send_status" -eq 0 ]] && \
       grep -Fq '"ok":true' "$telegram_send_stdout" && \
       [[ ! -s "$telegram_send_stderr" ]] && \
       grep -Fq -- '--config' "$telegram_send_curl_log" && \
       ! grep -Fq 'env-token-123' "$telegram_send_curl_log" && \
       grep -Fq 'https://api.telegram.org/botenv-token-123/sendMessage' "$telegram_send_curl_stdin" && \
       grep -Fq '"chat_id":"42"' "$telegram_send_curl_log" && \
       grep -Fq '"text":"hello from test"' "$telegram_send_curl_log"; then
        test_pass
    else
        test_fail "telegram-bot-send.sh must use TELEGRAM_BOT_TOKEN from env without failing on an unreadable env file"
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

    test_start "component_perl_fastpaths_do_not_depend_on_open_pm"
    if ! grep -Fq 'use open qw(:std :utf8);' "$HOOK_SCRIPT"; then
        test_pass
    else
        test_fail "Perl-based Telegram-safe fastpaths must not depend on open.pm because the live Moltis container does not ship that module"
    fi

    test_start "component_perl_utf8_matchers_do_not_depend_on_encode_pm"
    if ! grep -Fq -- '-MEncode=' "$HOOK_SCRIPT" && ! grep -Fq 'use Encode' "$HOOK_SCRIPT"; then
        test_pass
    else
        test_fail "Telegram-safe UTF-8 matcher helpers must not depend on Encode.pm because the live Moltis container does not ship that module"
    fi

    test_start "component_before_llm_guard_codex_update_context_survives_perl_without_encode_pm"
    local perl_guard_tmpdir
    perl_guard_tmpdir="$(mktemp -d)"
    cat > "$perl_guard_tmpdir/perl" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
    if [[ "$arg" == *Encode* ]]; then
        echo "Encode.pm is unavailable in this test wrapper" >&2
        exit 97
    fi
done
exec /usr/bin/perl "$@"
EOF
    chmod +x "$perl_guard_tmpdir/perl"
    local before_llm_no_encode_wrapper_output
    before_llm_no_encode_wrapper_output="$(
        LANG= \
        LC_ALL=C \
        LC_CTYPE=POSIX \
        run_hook_with_custom_path "$perl_guard_tmpdir:/usr/bin:/bin" \
            '{"event":"BeforeLLMCall","session_key":"session:no-encode-wrapper","provider":"openai-codex","model":"openai-codex::gpt-5.4","messages":[{"role":"system","content":"Host: host=prod | channel_account=moltis-bot | channel_chat_id=262872984 | data_dir=/home/moltis/.moltis"},{"role":"user","content":"Почему раньше ты присылал три одинаковых сообщения подряд про обновление Codex CLI?"}],"tool_count":37,"iteration":1}'
    )"
    rm -rf "$perl_guard_tmpdir"
    if jq -e '.action == "modify"' >/dev/null 2>&1 <<<"$before_llm_no_encode_wrapper_output" && \
       jq -e '.data.tool_count == 0' >/dev/null 2>&1 <<<"$before_llm_no_encode_wrapper_output" && \
       jq -e '.data.messages[0].content | contains("Telegram-safe codex-update hard override")' >/dev/null 2>&1 <<<"$before_llm_no_encode_wrapper_output" && \
       jq -e '.data.messages[0].content | contains("После исправлений схема такая")' >/dev/null 2>&1 <<<"$before_llm_no_encode_wrapper_output"; then
        test_pass
    else
        test_fail "The exact live codex-update context route must stay functional even when perl wrappers reject any Encode.pm dependency"
    fi

    test_start "component_telegram_safe_llm_guard_is_noop_for_non_telegram_safe_models"
    local non_safe_output
    non_safe_output="$(
        run_hook_with_minimal_path \
            '{"event":"AfterLLMCall","data":{"session_key":"session:mno","provider":"ollama","model":"ollama::gemini-3-flash-preview:cloud","text":"plain response","tool_calls":[]}}'
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
