#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

WEB_ADAPTER_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-web-adapter.py"
BRIEF_FIXTURE="$PROJECT_ROOT/tests/fixtures/agent-factory/web-demo/session-awaiting-confirmation.json"

run_component_agent_factory_web_brief_tests() {
    start_timer
    require_commands_or_skip python3 jq || {
        test_start "component_agent_factory_web_brief_prereqs"
        test_skip "python3 and jq are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    if ! python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$BRIEF_FIXTURE" --state-root "$tmpdir/state" --output "$tmpdir/brief-out.json" >/dev/null; then
        test_start "component_agent_factory_web_brief_fixture_executes"
        test_fail "Browser brief fixture should render successfully through the web adapter"
        generate_report
        return
    fi

    test_start "component_agent_factory_web_brief_renders_chunked_review_sections"
    assert_eq "awaiting_confirmation" "$(jq -r '.status' "$tmpdir/brief-out.json")" "Brief review fixture should stay in awaiting confirmation state"
    assert_eq "awaiting_confirmation" "$(jq -r '.status_snapshot.user_visible_status' "$tmpdir/brief-out.json")" "Browser status should expose a safe awaiting-confirmation projection"
    assert_eq "Brief ждёт подтверждения" "$(jq -r '.status_snapshot.user_visible_status_label' "$tmpdir/brief-out.json")" "Browser label should stay business-readable"
    assert_eq "7" "$(jq -r '[.reply_cards[] | select(.card_kind == "brief_summary_section")] | length' "$tmpdir/brief-out.json")" "Awaiting-confirmation brief should be split into stable readable sections"
    assert_contains "$(jq -r '[.reply_cards[] | select(.card_kind == "brief_summary_section") | .title] | join(",")' "$tmpdir/brief-out.json")" "Версия brief 1.0" "Rendered cards should expose the exact brief version"
    assert_contains "$(jq -r '[.reply_cards[] | select(.card_kind == "brief_summary_section") | .title] | join(",")' "$tmpdir/brief-out.json")" "Пользователи и процесс" "Rendered cards should include the users/process chunk"
    assert_contains "$(jq -r '[.reply_cards[] | select(.card_kind == "brief_summary_section") | .title] | join(",")' "$tmpdir/brief-out.json")" "Примеры входов и выходов" "Rendered cards should include the examples chunk"
    assert_contains "$(jq -r '[.reply_cards[] | select(.card_kind == "brief_summary_section") | .title] | join(",")' "$tmpdir/brief-out.json")" "Правила, исключения и риски" "Rendered cards should include the rules/risk chunk"
    assert_contains "$(jq -r '[.reply_cards[] | select(.card_kind == "confirmation_prompt")][0].title' "$tmpdir/brief-out.json")" "1.0" "Confirmation prompt should show the exact reviewed brief version"
    test_pass

    test_start "component_agent_factory_web_brief_keeps_browser_copy_safe"
    local combined_body
    combined_body="$(jq -r '[.reply_cards[].body_text] | join("\n---\n")' "$tmpdir/brief-out.json")"
    assert_contains "$combined_body" "Превышение лимита требует дополнительного согласования" "Business rules should stay visible in the browser summary"
    assert_contains "$combined_body" "Срочные платежи CFO" "Risk and exception wording should stay visible in the browser summary"
    if [[ "$combined_body" == *"problem_statement"* || "$combined_body" == *"target_users"* || "$combined_body" == *"requirement_brief"* || "$combined_body" == *"discovery_session_id"* ]]; then
        test_fail "Browser brief summary should not leak raw internal field names"
    else
        test_pass
    fi

    local correction_payload
    correction_payload="$tmpdir/brief-correction-confirm-action.json"
    jq '
      .web_conversation_envelope.ui_action = "confirm_brief"
      | .web_conversation_envelope.user_text = "Добавь обязательную BPMN-схему текущего и целевого процесса и отдельный блок резюме на 1 слайд."
    ' "$BRIEF_FIXTURE" > "$correction_payload"

    if ! python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$correction_payload" --state-root "$tmpdir/state-correction" --output "$tmpdir/brief-correction-out.json" >/dev/null; then
        test_start "component_agent_factory_web_brief_non_confirmation_text_via_confirm_action_executes"
        test_fail "Confirm action with non-confirmation text should execute safely"
        generate_report
        return
    fi

    test_start "component_agent_factory_web_brief_non_confirmation_text_is_treated_as_correction"
    assert_eq "awaiting_confirmation" "$(jq -r '.status' "$tmpdir/brief-correction-out.json")" "Non-confirmation text must keep brief in review stage"
    assert_eq "request_explicit_confirmation" "$(jq -r '.next_action' "$tmpdir/brief-correction-out.json")" "After correction, the next step must still be explicit confirmation"
    assert_eq "1.1" "$(jq -r '.status_snapshot.brief_version' "$tmpdir/brief-correction-out.json")" "Correction text should produce a new brief version"
    assert_eq "0" "$(jq -r '[.reply_cards[] | select(.card_kind == "download_prompt")] | length' "$tmpdir/brief-correction-out.json")" "Correction text must not trigger download-ready cards"
    assert_contains "$(jq -r '[.reply_cards[] | select(.card_kind == "brief_summary_section") | .body_text] | join("\n")' "$tmpdir/brief-correction-out.json")" "BPMN-схему" "Correction text should be reflected in rendered brief sections"
    test_pass

    local input_examples_route_payload
    input_examples_route_payload="$tmpdir/brief-correction-input-examples-route.json"
    jq '
      .web_conversation_envelope.ui_action = "request_brief_correction"
      | .web_conversation_envelope.user_text = "Входные данные не фраза, а прикрепленный ранее файл с примерами выходных данных."
      | .uploaded_files = [
          {
            "upload_id": "upload-route-001",
            "name": "demo-client-data.csv",
            "content_type": "text/csv",
            "size_bytes": 11234,
            "excerpt": "synthetic rows"
          }
        ]
    ' "$BRIEF_FIXTURE" > "$input_examples_route_payload"

    if ! python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$input_examples_route_payload" --state-root "$tmpdir/state-input-examples-route" --output "$tmpdir/brief-correction-input-examples-route-out.json" >/dev/null; then
        test_start "component_agent_factory_web_brief_input_examples_correction_route_executes"
        test_fail "Input-examples correction request should execute safely"
        generate_report
        return
    fi

    test_start "component_agent_factory_web_brief_routes_input_examples_correction_without_expected_outputs_pollution"
    assert_eq "awaiting_confirmation" "$(jq -r '.status' "$tmpdir/brief-correction-input-examples-route-out.json")" "Input-examples correction should keep the brief in confirmation stage"
    assert_eq "1.1" "$(jq -r '.status_snapshot.brief_version' "$tmpdir/brief-correction-input-examples-route-out.json")" "Input-examples correction should bump brief version"
    assert_contains "$(jq -r '.discovery_runtime_state.requirement_brief.input_examples | join("\n")' "$tmpdir/brief-correction-input-examples-route-out.json")" "demo-client-data.csv" "Input-examples section should reference uploaded file evidence"
    assert_contains "$(jq -r '.discovery_runtime_state.requirement_brief.input_examples | join("\n")' "$tmpdir/brief-correction-input-examples-route-out.json")" "синтетически" "Input-examples section should keep synthetic-data disclaimer"
    assert_eq "false" "$(jq -r '[.discovery_runtime_state.requirement_brief.expected_outputs[] | contains("прикрепленный ранее файл")] | any' "$tmpdir/brief-correction-input-examples-route-out.json")" "Expected outputs section must not be polluted by input-examples correction text"
    test_pass

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_agent_factory_web_brief_tests
fi
