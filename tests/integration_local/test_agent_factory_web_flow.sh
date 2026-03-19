#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

WEB_ADAPTER_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-web-adapter.py"
SESSION_NEW_FIXTURE="$PROJECT_ROOT/tests/fixtures/agent-factory/web-demo/session-new.json"

run_integration_local_agent_factory_web_flow_tests() {
    start_timer
    require_commands_or_skip python3 jq || {
        test_start "integration_local_agent_factory_web_flow_prereqs"
        test_skip "python3 and jq are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    test_start "integration_local_agent_factory_web_flow_starts_browser_discovery_from_raw_idea"
    if python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$SESSION_NEW_FIXTURE" --state-root "$tmpdir/state" --output "$tmpdir/start-out.json" >/dev/null; then
        assert_eq "awaiting_user_reply" "$(jq -r '.status' "$tmpdir/start-out.json")" "New browser project should immediately enter guided discovery"
        assert_eq "ask_next_question" "$(jq -r '.next_action' "$tmpdir/start-out.json")" "First browser turn should route into the next useful discovery question"
        assert_eq "target_users" "$(jq -r '.next_topic' "$tmpdir/start-out.json")" "The first uncovered topic after the raw idea should be target users"
        assert_contains "$(jq -r '.next_question' "$tmpdir/start-out.json")" "Кто" "Browser reply should keep the business-readable discovery question"
        assert_eq "web" "$(jq -r '.web_conversation_envelope.normalized_payload.request_channel' "$tmpdir/start-out.json")" "Normalized browser payload should keep the web request channel"
        assert_eq "discovery_in_progress" "$(jq -r '.status_snapshot.user_visible_status' "$tmpdir/start-out.json")" "User-visible status should remain safe and browser-friendly"
        assert_file_exists "$tmpdir/state/sessions/web-demo-session-invoice-approval.json" "Browser turn should persist the session snapshot under the web-demo state root"
        if compgen -G "$tmpdir/state/history/web-demo-session-invoice-approval-*.json" >/dev/null; then
            test_pass
        else
            test_fail "Browser turn should persist at least one audit/history snapshot"
        fi
    else
        test_fail "Browser adapter should start discovery directly from the session-new fixture"
    fi

    test_start "integration_local_agent_factory_web_flow_reprompts_on_low_signal_start_idea"
    if jq '.web_conversation_envelope.user_text = "test"' "$SESSION_NEW_FIXTURE" >"$tmpdir/start-low-signal.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/start-low-signal.json" --state-root "$tmpdir/state-low-signal" --output "$tmpdir/start-low-signal-out.json" >/dev/null; then
        assert_eq "awaiting_user_reply" "$(jq -r '.status' "$tmpdir/start-low-signal-out.json")" "Low-signal start should keep discovery waiting for a valid idea"
        assert_eq "problem" "$(jq -r '.next_topic' "$tmpdir/start-low-signal-out.json")" "Low-signal start should keep focus on business problem topic"
        assert_contains "$(jq -r '.next_question' "$tmpdir/start-low-signal-out.json")" "Описание предмета автоматизации пока слишком общее" "Low-signal start should trigger an explicit reprompt"
        assert_eq "" "$(jq -r '.discovery_runtime_state.requirement_topics[] | select(.topic_name == "problem") | .summary' "$tmpdir/start-low-signal-out.json")" "Low-signal start must not be accepted as problem statement"
        assert_eq "low_signal_guard" "$(jq -r '.ui_projection.question_source' "$tmpdir/start-low-signal-out.json")" "UI projection should expose low-signal guard mode for start turn"
        test_pass
    else
        test_fail "Browser adapter should reject low-signal start messages as automation subject"
    fi

    test_start "integration_local_agent_factory_web_flow_reprompts_on_insufficient_start_context"
    if jq '.web_conversation_envelope.user_text = "хочу помощь"' "$SESSION_NEW_FIXTURE" >"$tmpdir/start-insufficient-context.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/start-insufficient-context.json" --state-root "$tmpdir/state-insufficient-context" --output "$tmpdir/start-insufficient-context-out.json" >/dev/null; then
        assert_eq "awaiting_user_reply" "$(jq -r '.status' "$tmpdir/start-insufficient-context-out.json")" "Insufficient start context should keep discovery waiting for valid automation subject"
        assert_eq "problem" "$(jq -r '.next_topic' "$tmpdir/start-insufficient-context-out.json")" "Insufficient start context should keep focus on business problem topic"
        assert_contains "$(jq -r '.next_question' "$tmpdir/start-insufficient-context-out.json")" "Описание предмета автоматизации пока слишком общее" "Insufficient start context should trigger problem-specific reprompt"
        assert_eq "" "$(jq -r '.discovery_runtime_state.requirement_topics[] | select(.topic_name == "problem") | .summary' "$tmpdir/start-insufficient-context-out.json")" "Insufficient start context must not be accepted as problem statement"
        assert_eq "low_signal_guard" "$(jq -r '.ui_projection.question_source' "$tmpdir/start-insufficient-context-out.json")" "UI projection should expose validation guard mode for insufficient start context"
        test_pass
    else
        test_fail "Browser adapter should reject insufficient context at start_project"
    fi

    test_start "integration_local_agent_factory_web_flow_advances_after_submit_turn"
    if jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-claims-routing-002",
          "request_id": "web-request-claims-routing-002",
          "transport_mode": "synthetic_fixture",
          "ui_action": "submit_turn",
          "user_text": "Оператор первой линии и руководитель смены."
        } | del(.demo_access_grant)' "$tmpdir/start-out.json" >"$tmpdir/turn-two.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/turn-two.json" --state-root "$tmpdir/state" --output "$tmpdir/turn-two-out.json" >/dev/null; then
        assert_eq "awaiting_user_reply" "$(jq -r '.status' "$tmpdir/turn-two-out.json")" "Second browser turn should keep the conversational loop active"
        assert_eq "current_workflow" "$(jq -r '.next_topic' "$tmpdir/turn-two-out.json")" "After target users are answered the flow should move to current workflow"
        assert_contains "$(jq -r '.next_question' "$tmpdir/turn-two-out.json")" "Как этот процесс работает" "The next browser question should advance to the current workflow topic"
        assert_eq "Оператор первой линии и руководитель смены." "$(jq -r '.discovery_runtime_state.requirement_topics[] | select(.topic_name == "target_users") | .summary' "$tmpdir/turn-two-out.json")" "Browser turn should persist the answer into the canonical discovery topics"
        assert_eq "current_workflow" "$(jq -r '.web_conversation_envelope.normalized_payload.current_topic' "$tmpdir/turn-two-out.json")" "Normalized browser payload should point to the next pending discovery topic"
        test_pass
    else
        test_fail "Browser adapter should resume the saved session and advance discovery after a follow-up answer"
    fi

    test_start "integration_local_agent_factory_web_flow_keeps_topic_on_low_signal_reply"
    if jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-claims-routing-004",
          "request_id": "web-request-claims-routing-004",
          "transport_mode": "synthetic_fixture",
          "ui_action": "submit_turn",
          "user_text": "ping"
        } | del(.demo_access_grant)' "$tmpdir/start-out.json" >"$tmpdir/turn-low-signal.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/turn-low-signal.json" --state-root "$tmpdir/state" --output "$tmpdir/turn-low-signal-out.json" >/dev/null; then
        assert_eq "awaiting_user_reply" "$(jq -r '.status' "$tmpdir/turn-low-signal-out.json")" "Low-signal browser reply should keep the dialog active"
        assert_eq "target_users" "$(jq -r '.next_topic' "$tmpdir/turn-low-signal-out.json")" "Low-signal reply should not advance discovery to the next topic"
        assert_contains "$(jq -r '.next_question' "$tmpdir/turn-low-signal-out.json")" "слишком общий" "Low-signal reply should trigger an architect reprompt"
        assert_eq "" "$(jq -r '.discovery_runtime_state.requirement_topics[] | select(.topic_name == "target_users") | .summary' "$tmpdir/turn-low-signal-out.json")" "Low-signal reply must not overwrite canonical topic summary"
        assert_eq "low_signal_guard" "$(jq -r '.ui_projection.question_source' "$tmpdir/turn-low-signal-out.json")" "UI projection should expose low-signal guard mode"
        test_pass
    else
        test_fail "Browser adapter should keep the same discovery topic when the user sends low-signal input"
    fi

    test_start "integration_local_agent_factory_web_flow_falls_back_when_llm_enabled_but_not_configured"
    if ASC_DEMO_LLM_ENABLED=true OPENAI_API_KEY= OPENAI_BASE_URL= MODEL_NAME= \
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$SESSION_NEW_FIXTURE" --state-root "$tmpdir/state-llm-unconfigured" --output "$tmpdir/start-llm-unconfigured-out.json" >/dev/null; then
        assert_eq "awaiting_user_reply" "$(jq -r '.status' "$tmpdir/start-llm-unconfigured-out.json")" "Unconfigured LLM mode must not break discovery flow"
        assert_eq "adaptive_architect" "$(jq -r '.ui_projection.question_source' "$tmpdir/start-llm-unconfigured-out.json")" "Adapter should fall back to deterministic adaptive question when LLM config is incomplete"
        assert_eq "true" "$(jq -r '.ui_projection.llm_enabled' "$tmpdir/start-llm-unconfigured-out.json")" "UI projection should expose that LLM mode is enabled"
        assert_eq "false" "$(jq -r '.ui_projection.llm_configured' "$tmpdir/start-llm-unconfigured-out.json")" "UI projection should expose missing provider configuration"
        test_pass
    else
        test_fail "Browser adapter should stay operational when LLM mode is enabled without provider credentials"
    fi

    test_start "integration_local_agent_factory_web_flow_skips_duplicate_expected_outputs_when_already_captured_in_business_effect"
    if jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-claims-routing-101",
          "request_id": "web-request-claims-routing-101",
          "transport_mode": "synthetic_fixture",
          "ui_action": "submit_turn",
          "user_text": "Оператор первой линии и руководитель смены."
        } | del(.demo_access_grant)' "$tmpdir/start-out.json" >"$tmpdir/dedupe-turn-1.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/dedupe-turn-1.json" --state-root "$tmpdir/state-dedupe" --output "$tmpdir/dedupe-turn-1-out.json" >/dev/null &&
        jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-claims-routing-102",
          "request_id": "web-request-claims-routing-102",
          "transport_mode": "synthetic_fixture",
          "ui_action": "submit_turn",
          "user_text": "Сейчас данные собираются вручную, one-page готовится в Word, затем экспортируется в PDF."
        } | del(.demo_access_grant)' "$tmpdir/dedupe-turn-1-out.json" >"$tmpdir/dedupe-turn-2.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/dedupe-turn-2.json" --state-root "$tmpdir/state-dedupe" --output "$tmpdir/dedupe-turn-2-out.json" >/dev/null &&
        jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-claims-routing-103",
          "request_id": "web-request-claims-routing-103",
          "transport_mode": "synthetic_fixture",
          "ui_action": "submit_turn",
          "user_text": "На выходе нужен готовый one-page PDF с рекомендацией по решению для кредитного комитета."
        } | del(.demo_access_grant)' "$tmpdir/dedupe-turn-2-out.json" >"$tmpdir/dedupe-turn-3.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/dedupe-turn-3.json" --state-root "$tmpdir/state-dedupe" --output "$tmpdir/dedupe-turn-3-out.json" >/dev/null &&
        jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-claims-routing-104",
          "request_id": "web-request-claims-routing-104",
          "transport_mode": "synthetic_fixture",
          "ui_action": "submit_turn",
          "user_text": "Агент должен помогать клиентскому менеджеру перед заседанием комитета."
        } | del(.demo_access_grant)' "$tmpdir/dedupe-turn-3-out.json" >"$tmpdir/dedupe-turn-4.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/dedupe-turn-4.json" --state-root "$tmpdir/state-dedupe" --output "$tmpdir/dedupe-turn-4-out.json" >/dev/null &&
        jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-claims-routing-105",
          "request_id": "web-request-claims-routing-105",
          "transport_mode": "synthetic_fixture",
          "ui_action": "submit_turn",
          "user_text": "Типовой вход: CSV-выгрузка по клиенту."
        } | del(.demo_access_grant)' "$tmpdir/dedupe-turn-4-out.json" >"$tmpdir/dedupe-turn-5.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/dedupe-turn-5.json" --state-root "$tmpdir/state-dedupe" --output "$tmpdir/dedupe-turn-5-out.json" >/dev/null; then
        assert_eq "constraints" "$(jq -r '.next_topic' "$tmpdir/dedupe-turn-5-out.json")" "Expected outputs question should be skipped when business effect already captured explicit output format"
        assert_contains "$(jq -r '.discovery_runtime_state.requirement_topics[] | select(.topic_name == "expected_outputs") | .summary' "$tmpdir/dedupe-turn-5-out.json")" "one-page PDF" "Expected outputs summary should be auto-filled from explicit business effect output"
        test_pass
    else
        test_fail "Browser adapter should dedupe expected outputs when desired outcome already includes concrete output artifact"
    fi

    test_start "integration_local_agent_factory_web_flow_syncs_topic_after_upload_bridge_and_handles_repeat_meta_reply"
    if jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-claims-routing-005",
          "request_id": "web-request-claims-routing-005",
          "transport_mode": "synthetic_fixture",
          "ui_action": "submit_turn",
          "user_text": "Сейчас данные собираются вручную из банковских систем и финальный материал готовится в Word."
        } | del(.demo_access_grant)' "$tmpdir/turn-two-out.json" >"$tmpdir/turn-three.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/turn-three.json" --state-root "$tmpdir/state" --output "$tmpdir/turn-three-out.json" >/dev/null &&
        jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-claims-routing-006",
          "request_id": "web-request-claims-routing-006",
          "transport_mode": "synthetic_fixture",
          "ui_action": "submit_turn",
          "user_text": "Нужно сократить время подготовки материалов минимум вдвое и повысить качество рекомендаций."
        } | del(.demo_access_grant)' "$tmpdir/turn-three-out.json" >"$tmpdir/turn-four.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/turn-four.json" --state-root "$tmpdir/state" --output "$tmpdir/turn-four-out.json" >/dev/null &&
        jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-claims-routing-007",
          "request_id": "web-request-claims-routing-007",
          "transport_mode": "synthetic_fixture",
          "ui_action": "submit_turn",
          "user_text": "Агент помогает клиентскому менеджеру перед заседанием коллегиального органа."
        } | del(.demo_access_grant)' "$tmpdir/turn-four-out.json" >"$tmpdir/turn-five.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/turn-five.json" --state-root "$tmpdir/state" --output "$tmpdir/turn-five-out.json" >/dev/null &&
        jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-claims-routing-008",
          "request_id": "web-request-claims-routing-008",
          "transport_mode": "synthetic_fixture",
          "ui_action": "submit_turn",
          "user_text": "Во вложении типовой CSV по клиенту."
        }
        | .uploaded_files = [{
          "upload_id": "upload-csv-01",
          "name": "demo-client-data.csv",
          "content_type": "text/csv",
          "content_base64": "aWQsc2NvcmUKMSw3NDIK",
          "size_bytes": 14,
          "original_size_bytes": 14,
          "truncated": false
        }]
        | del(.demo_access_grant)' "$tmpdir/turn-five-out.json" >"$tmpdir/turn-upload.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/turn-upload.json" --state-root "$tmpdir/state" --output "$tmpdir/turn-upload-out.json" >/dev/null &&
        jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-claims-routing-009",
          "request_id": "web-request-claims-routing-009",
          "transport_mode": "synthetic_fixture",
          "ui_action": "submit_turn",
          "user_text": "Я уже отвечал на этот вопрос, перефразируй."
        } | del(.demo_access_grant)' "$tmpdir/turn-upload-out.json" >"$tmpdir/turn-repeat-meta.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/turn-repeat-meta.json" --state-root "$tmpdir/state" --output "$tmpdir/turn-repeat-meta-out.json" >/dev/null &&
        jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-claims-routing-010",
          "request_id": "web-request-claims-routing-010",
          "transport_mode": "synthetic_fixture",
          "ui_action": "submit_turn",
          "user_text": "PDF с рекомендацией."
        } | del(.demo_access_grant)' "$tmpdir/turn-repeat-meta-out.json" >"$tmpdir/turn-expected-output-answer.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/turn-expected-output-answer.json" --state-root "$tmpdir/state" --output "$tmpdir/turn-expected-output-answer-out.json" >/dev/null &&
        jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-claims-routing-011",
          "request_id": "web-request-claims-routing-011",
          "transport_mode": "synthetic_fixture",
          "ui_action": "submit_turn",
          "user_text": "Нельзя использовать персональные данные и нужно сохранять аудит изменений."
        } | del(.demo_access_grant)' "$tmpdir/turn-expected-output-answer-out.json" >"$tmpdir/turn-constraints-answer.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/turn-constraints-answer.json" --state-root "$tmpdir/state" --output "$tmpdir/turn-constraints-answer-out.json" >/dev/null &&
        jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-claims-routing-012",
          "request_id": "web-request-claims-routing-012",
          "transport_mode": "synthetic_fixture",
          "ui_action": "submit_turn",
          "user_text": "Сократить время подготовки на 50% и снизить долю ошибок в one-page до 2%."
        } | del(.demo_access_grant)' "$tmpdir/turn-constraints-answer-out.json" >"$tmpdir/turn-success-metrics-answer.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/turn-success-metrics-answer.json" --state-root "$tmpdir/state" --output "$tmpdir/turn-success-metrics-answer-out.json" >/dev/null; then
        assert_eq "expected_outputs" "$(jq -r '.next_topic' "$tmpdir/turn-upload-out.json")" "Upload bridge should move discovery to expected outputs topic"
        assert_eq "expected_outputs" "$(jq -r '.web_conversation_envelope.normalized_payload.current_topic' "$tmpdir/turn-upload-out.json")" "Normalized payload topic should stay synchronized after upload bridge"
        assert_eq "expected_outputs" "$(jq -r '.discovery_runtime_state.discovery_session.current_topic' "$tmpdir/turn-upload-out.json")" "Discovery session current topic should stay synchronized after upload bridge"
        assert_contains "$(jq -r '.next_question' "$tmpdir/turn-repeat-meta-out.json")" "Зафиксировал целевой эффект" "Repeat marker for expected outputs should produce a semantic rephrase instead of looping back"
        assert_eq "repeat_marker_rephrase" "$(jq -r '.ui_projection.question_source' "$tmpdir/turn-repeat-meta-out.json")" "Repeat marker branch should be visible in UI projection source"
        assert_eq "constraints" "$(jq -r '.next_topic' "$tmpdir/turn-expected-output-answer-out.json")" "Short but valid expected output answer should advance to constraints"
        assert_contains "$(jq -r '.discovery_runtime_state.requirement_topics[] | select(.topic_name == "expected_outputs") | .summary' "$tmpdir/turn-expected-output-answer-out.json")" "PDF с рекомендацией." "Expected outputs topic should capture the short valid answer without regressing to partial status"
        assert_eq "success_metrics" "$(jq -r '.next_topic' "$tmpdir/turn-constraints-answer-out.json")" "Constraints answer should move flow to success metrics"
        assert_eq "awaiting_confirmation" "$(jq -r '.status' "$tmpdir/turn-success-metrics-answer-out.json")" "Success metrics answer should advance flow to brief confirmation stage"
        assert_eq "request_explicit_confirmation" "$(jq -r '.next_action' "$tmpdir/turn-success-metrics-answer-out.json")" "After success metrics the next action should request explicit brief confirmation"
        assert_true "$(jq -r '[.reply_cards[] | select(.card_kind == "confirmation_prompt")] | length == 1' "$tmpdir/turn-success-metrics-answer-out.json")" "Confirmation stage should include explicit confirmation prompt card"
        assert_contains "$(jq -r '.next_question' "$tmpdir/turn-success-metrics-answer-out.json")" "подтверди" "Confirmation stage question should explicitly ask for brief confirmation"
        test_pass
    else
        test_fail "Browser adapter should bridge uploads, handle repeat meta-replies, and complete discovery flow up to explicit brief confirmation"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_integration_local_agent_factory_web_flow_tests
fi
