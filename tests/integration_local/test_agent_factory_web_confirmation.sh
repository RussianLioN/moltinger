#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

WEB_ADAPTER_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-web-adapter.py"
BRIEF_FIXTURE="$PROJECT_ROOT/tests/fixtures/agent-factory/web-demo/session-awaiting-confirmation.json"

run_integration_local_agent_factory_web_confirmation_tests() {
    start_timer
    require_commands_or_skip python3 jq || {
        test_start "integration_local_agent_factory_web_confirmation_prereqs"
        test_skip "python3 and jq are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    test_start "integration_local_agent_factory_web_confirmation_revises_and_confirms_brief_in_browser_flow"
    if python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$BRIEF_FIXTURE" --state-root "$tmpdir/state" --output "$tmpdir/review-out.json" >/dev/null &&
        jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-brief-review-002",
          "request_id": "web-request-brief-review-002",
          "transport_mode": "synthetic_fixture",
          "ui_action": "request_brief_correction",
          "user_text": "Уточни, что срочные платежи CFO остаются вне первого прототипа и требуют отдельного процесса согласования."
        } | .brief_section_updates = {
          "exceptions": [
            "Срочные платежи CFO идут по отдельному сценарию и требуют отдельного процесса согласования"
          ],
          "open_risks": [
            "Отдельный сценарий для срочных платежей CFO останется вне первого прототипа"
          ]
        } | del(.demo_access_grant)' "$tmpdir/review-out.json" >"$tmpdir/revision-source.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/revision-source.json" --state-root "$tmpdir/state" --output "$tmpdir/revised-out.json" >/dev/null &&
        jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-brief-review-003",
          "request_id": "web-request-brief-review-003",
          "transport_mode": "synthetic_fixture",
          "ui_action": "confirm_brief",
          "user_text": ""
        } | del(.demo_access_grant)' "$tmpdir/revised-out.json" >"$tmpdir/confirm-source.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/confirm-source.json" --state-root "$tmpdir/state" --output "$tmpdir/confirmed-out.json" >/dev/null; then
        assert_eq "awaiting_confirmation" "$(jq -r '.status' "$tmpdir/revised-out.json")" "Correction request should keep the browser flow in awaiting-confirmation state"
        assert_eq "1.1" "$(jq -r '.discovery_runtime_state.requirement_brief.version' "$tmpdir/revised-out.json")" "Conversational browser correction should create the next brief version"
        assert_eq "1.1" "$(jq -r '.status_snapshot.brief_version' "$tmpdir/revised-out.json")" "Browser status snapshot should expose the revised brief version"
        assert_eq "1.1" "$(jq -r '.browser_project_pointer.linked_brief_version' "$tmpdir/revised-out.json")" "Project pointer should move to the revised brief version"
        assert_contains "$(jq -r '[.reply_cards[] | select(.card_kind == "confirmation_prompt")][0].title' "$tmpdir/revised-out.json")" "1.1" "Confirmation prompt should refresh to the revised brief version"
        assert_contains "$(jq -r '[.reply_cards[].body_text] | join("\n")' "$tmpdir/revised-out.json")" "отдельного процесса согласования" "Browser review should include the corrected business wording"
        assert_eq "confirmed" "$(jq -r '.status' "$tmpdir/confirmed-out.json")" "Explicit browser confirmation should finalize the brief"
        assert_eq "confirmed" "$(jq -r '.discovery_runtime_state.requirement_brief.status' "$tmpdir/confirmed-out.json")" "Confirmed browser response should preserve the confirmed brief state"
        assert_eq "Артефакты готовы" "$(jq -r '.status_snapshot.user_visible_status_label' "$tmpdir/confirmed-out.json")" "After confirmation the browser shell should immediately expose ready artifacts"
        assert_eq "Скачать артефакты" "$(jq -r '.status_snapshot.next_recommended_action_label' "$tmpdir/confirmed-out.json")" "Confirmed browser state should point directly to artifact download step"
        assert_eq "Brief подтвержден" "$(jq -r '.status_snapshot.brief_status_label' "$tmpdir/confirmed-out.json")" "Brief confirmation label should remain visible in status snapshot"
        assert_eq "request_status" "$(jq -r '.ui_projection.preferred_ui_action' "$tmpdir/confirmed-out.json")" "Browser shell should prefer a safe status refresh after confirmation"
        assert_contains "$(jq -r '[.reply_cards[].title] | join(",")' "$tmpdir/confirmed-out.json")" "One-page и артефакты готовы" "Confirmed browser response should include ready-artifacts card"
        test_pass
    else
        test_fail "Browser confirmation flow should move from reviewed brief to revised brief to confirmed state"
    fi

    test_start "integration_local_agent_factory_web_confirmation_sanitizes_literal_brief_correction_prefixes"
    if python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$BRIEF_FIXTURE" --state-root "$tmpdir/sanitize-state" --output "$tmpdir/sanitize-review-out.json" >/dev/null &&
        jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-brief-review-008",
          "request_id": "web-request-brief-review-008",
          "transport_mode": "synthetic_fixture",
          "ui_action": "request_brief_correction",
          "user_text": "Нужно исправить brief: ожидаемый выход: один финальный PDF-документ без лишних списков."
        } | del(.brief_section_updates) | del(.demo_access_grant)' "$tmpdir/sanitize-review-out.json" >"$tmpdir/sanitize-source.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/sanitize-source.json" --state-root "$tmpdir/sanitize-state" --output "$tmpdir/sanitize-out.json" >/dev/null; then
        assert_eq "awaiting_confirmation" "$(jq -r '.status' "$tmpdir/sanitize-out.json")" "Correction through free-form feedback should keep browser flow in review mode"
        assert_eq "один финальный PDF-документ без лишних списков." "$(jq -r '.discovery_runtime_state.requirement_brief.expected_outputs[0]' "$tmpdir/sanitize-out.json")" "Expected output should store sanitized correction text without service prefixes"
        test_pass
    else
        test_fail "Browser correction parser should strip service prefixes from free-form feedback"
    fi

    test_start "integration_local_agent_factory_web_confirmation_sanitizes_targeted_section_command_prefixes"
    if python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$BRIEF_FIXTURE" --state-root "$tmpdir/targeted-sanitize-state" --output "$tmpdir/targeted-sanitize-review-out.json" >/dev/null &&
        jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-brief-review-008b",
          "request_id": "web-request-brief-review-008b",
          "transport_mode": "synthetic_fixture",
          "ui_action": "request_brief_correction",
          "user_text": "Исправь раздел expected_outputs: один финальный PDF-документ с рекомендацией для кредитного комитета."
        } | .brief_feedback_target = "expected_outputs" | del(.brief_section_updates) | del(.demo_access_grant)' "$tmpdir/targeted-sanitize-review-out.json" >"$tmpdir/targeted-sanitize-source.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/targeted-sanitize-source.json" --state-root "$tmpdir/targeted-sanitize-state" --output "$tmpdir/targeted-sanitize-out.json" >/dev/null; then
        assert_eq "один финальный PDF-документ с рекомендацией для кредитного комитета." "$(jq -r '.discovery_runtime_state.requirement_brief.expected_outputs[0]' "$tmpdir/targeted-sanitize-out.json")" "Targeted section correction should strip command prefix before persisting expected_outputs"
        test_pass
    else
        test_fail "Browser correction parser should strip targeted section command prefixes before storing expected outputs"
    fi

    test_start "integration_local_agent_factory_web_confirmation_parses_section_command_with_input_and_output_short_markers"
    if python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$BRIEF_FIXTURE" --state-root "$tmpdir/section-io-state" --output "$tmpdir/section-io-review-out.json" >/dev/null &&
        jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-brief-review-008c",
          "request_id": "web-request-brief-review-008c",
          "transport_mode": "synthetic_fixture",
          "ui_action": "request_brief_correction",
          "user_text": "Исправь раздел Примеры входов и выходов: Вход — табличная выгрузка demo-client-data.csv с KPI клиента. Выход — one-page PDF с рекомендацией для кредитного комитета."
        } | del(.brief_feedback_target) | del(.brief_section_updates) | del(.demo_access_grant)' "$tmpdir/section-io-review-out.json" >"$tmpdir/section-io-source.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/section-io-source.json" --state-root "$tmpdir/section-io-state" --output "$tmpdir/section-io-out.json" >/dev/null; then
        assert_eq "табличная выгрузка demo-client-data.csv с KPI клиента." "$(jq -r '.discovery_runtime_state.requirement_brief.input_examples[0]' "$tmpdir/section-io-out.json")" "Section command with short marker 'Вход —' should update input_examples only with fragment"
        assert_eq "one-page PDF с рекомендацией для кредитного комитета." "$(jq -r '.discovery_runtime_state.requirement_brief.expected_outputs[0]' "$tmpdir/section-io-out.json")" "Section command with short marker 'Выход —' should update expected_outputs only with fragment"
        test_pass
    else
        test_fail "Browser correction parser should split section command with short input/output markers into two clean brief fields"
    fi

    test_start "integration_local_agent_factory_web_confirmation_routes_users_and_process_section_to_current_process"
    if python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$BRIEF_FIXTURE" --state-root "$tmpdir/users-process-state" --output "$tmpdir/users-process-review-out.json" >/dev/null &&
        jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-brief-review-008d",
          "request_id": "web-request-brief-review-008d",
          "transport_mode": "synthetic_fixture",
          "ui_action": "request_brief_correction",
          "user_text": "Исправь раздел Пользователи и процесс: добавь BPMN-схему текущего и целевого процесса."
        } | del(.brief_feedback_target) | del(.brief_section_updates) | del(.demo_access_grant)' "$tmpdir/users-process-review-out.json" >"$tmpdir/users-process-source.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/users-process-source.json" --state-root "$tmpdir/users-process-state" --output "$tmpdir/users-process-out.json" >/dev/null; then
        assert_contains "$(jq -r '.discovery_runtime_state.brief_revisions[-1].changed_sections | join(",")' "$tmpdir/users-process-out.json")" "current_process" "Section command 'Пользователи и процесс' must mutate current_process"
        assert_eq "false" "$(jq -r '(.discovery_runtime_state.brief_revisions[-1].changed_sections | index("scope_boundaries")) != null' "$tmpdir/users-process-out.json")" "Users/process correction must not fallback to scope_boundaries"
        assert_contains "$(jq -r '.discovery_runtime_state.requirement_brief.current_process' "$tmpdir/users-process-out.json")" "BPMN-схему" "Current process should include BPMN correction text"
        test_pass
    else
        test_fail "Section command 'Пользователи и процесс' should route to current_process without fallback"
    fi

    test_start "integration_local_agent_factory_web_confirmation_routes_business_rules_feedback_without_overwriting_expected_outputs"
    if python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$BRIEF_FIXTURE" --state-root "$tmpdir/business-rules-state" --output "$tmpdir/business-rules-review-out.json" >/dev/null &&
        jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-brief-review-008e",
          "request_id": "web-request-brief-review-008e",
          "transport_mode": "synthetic_fixture",
          "ui_action": "request_brief_correction",
          "user_text": "Добавь правила: итоговый one-page должен быть на русском языке, не больше 1 страницы A4, с блоками «Ключевые факты», «Риски», «Рекомендация»."
        } | del(.brief_feedback_target) | del(.brief_section_updates) | del(.demo_access_grant)' "$tmpdir/business-rules-review-out.json" >"$tmpdir/business-rules-source.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/business-rules-source.json" --state-root "$tmpdir/business-rules-state" --output "$tmpdir/business-rules-out.json" >/dev/null; then
        local expected_outputs_before expected_outputs_after
        expected_outputs_before="$(jq -c '.discovery_runtime_state.requirement_brief.expected_outputs' "$tmpdir/business-rules-review-out.json")"
        expected_outputs_after="$(jq -c '.discovery_runtime_state.requirement_brief.expected_outputs' "$tmpdir/business-rules-out.json")"
        assert_eq "$expected_outputs_before" "$expected_outputs_after" "Business rules correction must not overwrite expected_outputs"
        assert_contains "$(jq -r '.discovery_runtime_state.requirement_brief.business_rules[0]' "$tmpdir/business-rules-out.json")" "итоговый one-page должен быть на русском языке" "Business rules correction should be persisted in business_rules section"
        test_pass
    else
        test_fail "Business-rules correction should route to business_rules and keep expected_outputs unchanged"
    fi

    test_start "integration_local_agent_factory_web_confirmation_reopens_confirmed_version_without_losing_history"
    if jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-brief-review-004",
          "request_id": "web-request-brief-review-004",
          "transport_mode": "synthetic_fixture",
          "ui_action": "reopen_brief",
          "user_text": "Переоткрой brief и добавь, что исключения для срочных платежей CFO надо согласовать отдельно перед handoff."
        } | .brief_section_updates = {
          "open_risks": [
            "Нужно отдельно согласовать handoff для сценария срочных платежей CFO"
          ]
        } | del(.demo_access_grant)' "$tmpdir/confirmed-out.json" >"$tmpdir/reopen-source.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/reopen-source.json" --state-root "$tmpdir/state" --output "$tmpdir/reopened-out.json" >/dev/null; then
        assert_eq "reopened" "$(jq -r '.status' "$tmpdir/reopened-out.json")" "Reopen action should put the browser flow back into reopened state"
        assert_eq "awaiting_confirmation" "$(jq -r '.status_snapshot.user_visible_status' "$tmpdir/reopened-out.json")" "Browser-visible status should return to confirmation mode after reopen"
        assert_eq "1.2" "$(jq -r '.discovery_runtime_state.requirement_brief.version' "$tmpdir/reopened-out.json")" "Reopen should create a new brief version instead of mutating the confirmed one in place"
        assert_eq "1" "$(jq -r '.discovery_runtime_state.confirmation_history | length' "$tmpdir/reopened-out.json")" "Reopen should preserve the prior confirmation snapshot in history"
        assert_eq "1.2" "$(jq -r '.status_snapshot.brief_version' "$tmpdir/reopened-out.json")" "Browser status snapshot should move to the reopened version"
        assert_eq "confirm_brief" "$(jq -r '.ui_projection.preferred_ui_action' "$tmpdir/reopened-out.json")" "After reopen the shell should return to the confirmation-focused action set"
        assert_contains "$(jq -r '[.reply_cards[] | select(.card_kind == "confirmation_prompt")][0].title' "$tmpdir/reopened-out.json")" "1.2" "Reopened browser prompt should expose the new exact version"
        test_pass
    else
        test_fail "Browser reopen should preserve confirmation history and return the user to a new reviewable brief version"
    fi

    test_start "integration_local_agent_factory_web_confirmation_accepts_text_confirmation_from_submit_turn"
    if python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$BRIEF_FIXTURE" --state-root "$tmpdir/state" --output "$tmpdir/text-confirm-review-out.json" >/dev/null &&
        jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-brief-review-005",
          "request_id": "web-request-brief-review-005",
          "transport_mode": "synthetic_fixture",
          "ui_action": "submit_turn",
          "user_text": "Подтверждаю brief, можно передавать дальше."
        } | del(.demo_access_grant)' "$tmpdir/text-confirm-review-out.json" >"$tmpdir/text-confirm-source.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/text-confirm-source.json" --state-root "$tmpdir/state" --output "$tmpdir/text-confirmed-out.json" >/dev/null; then
        assert_eq "confirmed" "$(jq -r '.status' "$tmpdir/text-confirmed-out.json")" "Text confirmation from submit_turn should finalize the brief"
        assert_eq "confirmed" "$(jq -r '.discovery_runtime_state.requirement_brief.status' "$tmpdir/text-confirmed-out.json")" "Runtime brief should be marked confirmed after text confirmation"
        assert_eq "download_artifact" "$(jq -r '.next_action' "$tmpdir/text-confirmed-out.json")" "Text confirmation should immediately switch flow to artifact delivery"
        assert_eq "ready" "$(jq -r '.status_snapshot.download_readiness' "$tmpdir/text-confirmed-out.json")" "Text confirmation should produce download-ready status snapshot"
        assert_contains "$(jq -r '.discovery_runtime_state.confirmation_snapshot.confirmation_text' "$tmpdir/text-confirmed-out.json")" "Подтверждаю brief" "Confirmation snapshot should keep the textual user confirmation"
        test_pass
    else
        test_fail "Browser flow should map submit_turn text confirmation to confirm_brief behavior"
    fi

    test_start "integration_local_agent_factory_web_confirmation_treats_short_ack_as_explicit_confirm_action"
    if python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$BRIEF_FIXTURE" --state-root "$tmpdir/short-ack-state" --output "$tmpdir/short-ack-review-out.json" >/dev/null &&
        jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-brief-review-005aa",
          "request_id": "web-request-brief-review-005aa",
          "transport_mode": "synthetic_fixture",
          "ui_action": "confirm_brief",
          "user_text": "да"
        } | del(.demo_access_grant)' "$tmpdir/short-ack-review-out.json" >"$tmpdir/short-ack-source.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/short-ack-source.json" --state-root "$tmpdir/short-ack-state" --output "$tmpdir/short-ack-out.json" >/dev/null; then
        assert_eq "confirmed" "$(jq -r '.status' "$tmpdir/short-ack-out.json")" "Short acknowledgement in explicit confirm action should finalize brief"
        assert_eq "confirmed" "$(jq -r '.discovery_runtime_state.requirement_brief.status' "$tmpdir/short-ack-out.json")" "Runtime brief should remain confirmed for short explicit confirmation ack"
        assert_eq "download_artifact" "$(jq -r '.next_action' "$tmpdir/short-ack-out.json")" "Short explicit confirmation ack should move flow to artifact delivery"
        test_pass
    else
        test_fail "Explicit confirm action should not reinterpret short acknowledgement as brief correction"
    fi

    test_start "integration_local_agent_factory_web_confirmation_request_status_keeps_review_mode_when_brief_is_complete"
    if jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-brief-review-005ab",
          "request_id": "web-request-brief-review-005ab",
          "transport_mode": "synthetic_fixture",
          "ui_action": "request_status",
          "user_text": ""
        } | del(.discovery_runtime_state.requirement_topics) | del(.demo_access_grant)' "$BRIEF_FIXTURE" >"$tmpdir/request-status-complete-source.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/request-status-complete-source.json" --state-root "$tmpdir/request-status-complete-state" --output "$tmpdir/request-status-complete-out.json" >/dev/null; then
        assert_eq "awaiting_confirmation" "$(jq -r '.status' "$tmpdir/request-status-complete-out.json")" "Status refresh should stay in confirmation mode when requirement_brief already has required sections"
        assert_eq "awaiting_confirmation" "$(jq -r '.status_snapshot.user_visible_status' "$tmpdir/request-status-complete-out.json")" "Browser-visible status should remain in confirmation mode for complete brief"
        assert_eq "request_explicit_confirmation" "$(jq -r '.next_action' "$tmpdir/request-status-complete-out.json")" "Status refresh should continue waiting for explicit confirmation"
        test_pass
    else
        test_fail "Status refresh in review mode should not regress to discovery questions when brief sections are already populated"
    fi

    test_start "integration_local_agent_factory_web_confirmation_confirm_brief_ignores_stale_section_updates"
    if jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-brief-review-005a",
          "request_id": "web-request-brief-review-005a",
          "transport_mode": "synthetic_fixture",
          "ui_action": "confirm_brief",
          "user_text": ""
        } | .brief_section_updates = {
          "expected_outputs": [
            "Старый промежуточный апдейт, который не должен блокировать подтверждение."
          ]
        } | .brief_feedback_text = "Историческая правка из прошлого хода" | del(.demo_access_grant)' "$BRIEF_FIXTURE" >"$tmpdir/stale-confirm-source.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/stale-confirm-source.json" --state-root "$tmpdir/stale-confirm-state" --output "$tmpdir/stale-confirm-out.json" >/dev/null; then
        assert_eq "confirmed" "$(jq -r '.status' "$tmpdir/stale-confirm-out.json")" "Explicit confirm_brief should not get stuck in awaiting_confirmation because of stale section updates"
        assert_eq "confirmed" "$(jq -r '.discovery_runtime_state.requirement_brief.status' "$tmpdir/stale-confirm-out.json")" "Runtime brief should stay confirmed when confirm_brief is explicit"
        assert_eq "download_artifact" "$(jq -r '.next_action' "$tmpdir/stale-confirm-out.json")" "Successful confirmation should move browser flow directly to artifact delivery"
        assert_eq "ready" "$(jq -r '.status_snapshot.download_readiness' "$tmpdir/stale-confirm-out.json")" "Confirm flow with stale fields should still provide ready downloads"
        test_pass
    else
        test_fail "confirm_brief should finalize brief even when previous stale correction payload fields are present"
    fi

    test_start "integration_local_agent_factory_web_confirmation_maps_submit_turn_freeform_review_text_to_correction"
    if python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$BRIEF_FIXTURE" --state-root "$tmpdir/submit-correction-state" --output "$tmpdir/submit-correction-review-out.json" >/dev/null &&
        jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-brief-review-005b",
          "request_id": "web-request-brief-review-005b",
          "transport_mode": "synthetic_fixture",
          "ui_action": "submit_turn",
          "user_text": "На выходе нужен один финальный PDF-документ для кредитного комитета без черновых блоков."
        } | del(.demo_access_grant)' "$tmpdir/submit-correction-review-out.json" >"$tmpdir/submit-correction-source.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/submit-correction-source.json" --state-root "$tmpdir/submit-correction-state" --output "$tmpdir/submit-correction-out.json" >/dev/null; then
        assert_eq "awaiting_confirmation" "$(jq -r '.status' "$tmpdir/submit-correction-out.json")" "Free-form review text in submit_turn should keep browser flow in confirmation mode"
        assert_eq "1.1" "$(jq -r '.discovery_runtime_state.requirement_brief.version' "$tmpdir/submit-correction-out.json")" "Free-form review text should create the next brief version"
        assert_eq "один финальный PDF-документ для кредитного комитета без черновых блоков." "$(jq -r '.discovery_runtime_state.requirement_brief.expected_outputs[0]' "$tmpdir/submit-correction-out.json")" "Free-form submit_turn review text should map to expected output correction"
        assert_contains "$(jq -r '.next_question' "$tmpdir/submit-correction-out.json")" "Правку применил" "Review response should acknowledge applied correction only after effective mutation"
        test_pass
    else
        test_fail "Browser flow should treat substantive submit_turn text in review stage as brief correction"
    fi

    test_start "integration_local_agent_factory_web_confirmation_parses_combined_input_and_output_correction_without_literal_prefix"
    if python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$BRIEF_FIXTURE" --state-root "$tmpdir/combined-correction-state" --output "$tmpdir/combined-correction-review-out.json" >/dev/null &&
        jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-brief-review-005c",
          "request_id": "web-request-brief-review-005c",
          "transport_mode": "synthetic_fixture",
          "ui_action": "request_brief_correction",
          "user_text": "Входные примеры: пример CSV-выгрузки по клиенту. Ожидаемый выход: итоговый one-page PDF с рекомендацией для кредитного комитета."
        } | del(.brief_section_updates) | del(.demo_access_grant)' "$tmpdir/combined-correction-review-out.json" >"$tmpdir/combined-correction-source.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/combined-correction-source.json" --state-root "$tmpdir/combined-correction-state" --output "$tmpdir/combined-correction-out.json" >/dev/null; then
        assert_eq "пример CSV-выгрузки по клиенту." "$(jq -r '.discovery_runtime_state.requirement_brief.input_examples[0]' "$tmpdir/combined-correction-out.json")" "Combined correction should extract only the input_examples fragment"
        assert_eq "итоговый one-page PDF с рекомендацией для кредитного комитета." "$(jq -r '.discovery_runtime_state.requirement_brief.expected_outputs[0]' "$tmpdir/combined-correction-out.json")" "Combined correction should extract expected_outputs without command prefix or input fragment"
        test_pass
    else
        test_fail "Combined correction parser should split input_examples and expected_outputs into clean brief values"
    fi

    test_start "integration_local_agent_factory_web_confirmation_routes_input_examples_file_feedback_without_touching_target_users"
    if python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$BRIEF_FIXTURE" --state-root "$tmpdir/file-feedback-state" --output "$tmpdir/file-feedback-review-out.json" >/dev/null &&
        jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-brief-review-005d",
          "request_id": "web-request-brief-review-005d",
          "transport_mode": "synthetic_fixture",
          "ui_action": "request_brief_correction",
          "user_text": "Входные данные не \"- Это и есть обезличенный пример\", а прикрепленный ранее файл с примерами выходных данных, а не фраза пользователя."
        } | .uploaded_files = [
          {
            "upload_id": "upload-demo-client-data",
            "name": "demo-client-data.csv",
            "content_type": "text/csv",
            "size_bytes": 11264,
            "content_base64": "Y2xpZW50X2lkLG5hbWUsc2VnbWVudAoxLEFjbWUgQ28sQ29ycG9yYXRlCg=="
          }
        ] | del(.brief_section_updates) | del(.demo_access_grant)' "$tmpdir/file-feedback-review-out.json" >"$tmpdir/file-feedback-source.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/file-feedback-source.json" --state-root "$tmpdir/file-feedback-state" --output "$tmpdir/file-feedback-out.json" >/dev/null; then
        assert_contains "$(jq -r '.discovery_runtime_state.requirement_brief.input_examples[0]' "$tmpdir/file-feedback-out.json")" "Входные примеры приложены файлами (demo-client-data.csv)." "Input examples should be rewritten to canonical uploaded file summary"
        assert_eq "Финансовый контролер" "$(jq -r '.discovery_runtime_state.requirement_brief.target_users[0]' "$tmpdir/file-feedback-out.json")" "Target users should not be overwritten by unrelated input examples correction text"
        assert_eq "Руководитель подразделения" "$(jq -r '.discovery_runtime_state.requirement_brief.target_users[1]' "$tmpdir/file-feedback-out.json")" "Second target user should remain untouched after input examples correction"
        test_pass
    else
        test_fail "Input examples file correction should not leak into target_users section"
    fi

    test_start "integration_local_agent_factory_web_confirmation_keeps_expected_outputs_when_input_examples_are_corrected"
    if python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$BRIEF_FIXTURE" --state-root "$tmpdir/section-misroute-state" --output "$tmpdir/section-misroute-review-out.json" >/dev/null &&
        jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-brief-review-005e",
          "request_id": "web-request-brief-review-005e",
          "transport_mode": "synthetic_fixture",
          "ui_action": "request_brief_correction",
          "user_text": "Входные данные не \"- Это и есть обезличенный пример\", а прикрепленный ранее файл с примерами выходных данных, а не фраза пользователя."
        } | .uploaded_files = [
          {
            "upload_id": "upload-demo-client-data-expected-output-guard",
            "name": "demo-client-data.csv",
            "content_type": "text/csv",
            "size_bytes": 11264,
            "content_base64": "Y2xpZW50X2lkLG5hbWUsc2VnbWVudAoxLEFjbWUgQ28sQ29ycG9yYXRlCg=="
          }
        ] | del(.brief_section_updates) | del(.demo_access_grant)' "$tmpdir/section-misroute-review-out.json" >"$tmpdir/section-misroute-source.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/section-misroute-source.json" --state-root "$tmpdir/section-misroute-state" --output "$tmpdir/section-misroute-out.json" >/dev/null; then
        local expected_outputs_before expected_outputs_after
        expected_outputs_before="$(jq -c '.discovery_runtime_state.requirement_brief.expected_outputs' "$tmpdir/section-misroute-review-out.json")"
        expected_outputs_after="$(jq -c '.discovery_runtime_state.requirement_brief.expected_outputs' "$tmpdir/section-misroute-out.json")"
        assert_eq "$expected_outputs_before" "$expected_outputs_after" "Input examples correction should not overwrite expected_outputs section"
        assert_contains "$(jq -r '.discovery_runtime_state.requirement_brief.input_examples[0]' "$tmpdir/section-misroute-out.json")" "Входные примеры приложены файлами (demo-client-data.csv)." "Input examples correction should still apply canonical file summary"
        test_pass
    else
        test_fail "Input examples correction should not drift into expected_outputs even when user text mentions output data"
    fi

    test_start "integration_local_agent_factory_web_confirmation_prefers_inferred_input_examples_over_conflicting_expected_outputs_target"
    if python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$BRIEF_FIXTURE" --state-root "$tmpdir/section-target-conflict-state" --output "$tmpdir/section-target-conflict-review-out.json" >/dev/null &&
        jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-brief-review-005f",
          "request_id": "web-request-brief-review-005f",
          "transport_mode": "synthetic_fixture",
          "ui_action": "request_brief_correction",
          "user_text": "Входные данные не \"- Это и есть обезличенный пример\", а прикрепленный ранее файл с примерами выходных данных, а не фраза пользователя."
        } | .brief_feedback_target = "expected_outputs" | .uploaded_files = [
          {
            "upload_id": "upload-demo-client-data-expected-output-conflict-guard",
            "name": "demo-client-data.csv",
            "content_type": "text/csv",
            "size_bytes": 11264,
            "content_base64": "Y2xpZW50X2lkLG5hbWUsc2VnbWVudAoxLEFjbWUgQ28sQ29ycG9yYXRlCg=="
          }
        ] | del(.brief_section_updates) | del(.demo_access_grant)' "$tmpdir/section-target-conflict-review-out.json" >"$tmpdir/section-target-conflict-source.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/section-target-conflict-source.json" --state-root "$tmpdir/section-target-conflict-state" --output "$tmpdir/section-target-conflict-out.json" >/dev/null; then
        local expected_outputs_before expected_outputs_after
        expected_outputs_before="$(jq -c '.discovery_runtime_state.requirement_brief.expected_outputs' "$tmpdir/section-target-conflict-review-out.json")"
        expected_outputs_after="$(jq -c '.discovery_runtime_state.requirement_brief.expected_outputs' "$tmpdir/section-target-conflict-out.json")"
        assert_eq "$expected_outputs_before" "$expected_outputs_after" "Conflicting expected_outputs feedback target must not overwrite expected_outputs when text clearly describes input examples"
        assert_contains "$(jq -r '.discovery_runtime_state.requirement_brief.input_examples[0]' "$tmpdir/section-target-conflict-out.json")" "Входные примеры приложены файлами (demo-client-data.csv)." "Conflicting target should still resolve to canonical input_examples summary"
        test_pass
    else
        test_fail "Conflicting expected_outputs target should not override inferred input_examples correction"
    fi

    test_start "integration_local_agent_factory_web_confirmation_keeps_download_mode_for_simulation_requests_after_confirm"
    if jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-brief-review-006",
          "request_id": "web-request-brief-review-006",
          "transport_mode": "synthetic_fixture",
          "ui_action": "request_status",
          "user_text": ""
        } | del(.demo_access_grant)' "$tmpdir/confirmed-out.json" >"$tmpdir/download-ready-source.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/download-ready-source.json" --state-root "$tmpdir/state" --output "$tmpdir/download-ready-out.json" >/dev/null &&
        jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-brief-review-007",
          "request_id": "web-request-brief-review-007",
          "transport_mode": "synthetic_fixture",
          "ui_action": "submit_turn",
          "user_text": "Запусти имитацию производства цифровой сущности и покажи стартовый результат."
        } | del(.demo_access_grant)' "$tmpdir/download-ready-out.json" >"$tmpdir/simulation-request-source.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/simulation-request-source.json" --state-root "$tmpdir/state" --output "$tmpdir/simulation-request-out.json" >/dev/null; then
        assert_eq "download_ready" "$(jq -r '.status' "$tmpdir/simulation-request-out.json")" "Simulation request after confirmation should stay in download-ready mode"
        assert_eq "download_artifact" "$(jq -r '.next_action' "$tmpdir/simulation-request-out.json")" "Simulation request should keep artifact download action as the next step"
        assert_eq "downloads" "$(jq -r '.ui_projection.side_panel_mode' "$tmpdir/simulation-request-out.json")" "Side panel should remain in downloads mode after simulation request"
        assert_eq "$(jq -r '.discovery_runtime_state.requirement_brief.version' "$tmpdir/download-ready-out.json")" "$(jq -r '.discovery_runtime_state.requirement_brief.version' "$tmpdir/simulation-request-out.json")" "Simulation request should not reopen brief or bump brief version"
        assert_contains "$(jq -r '.next_question' "$tmpdir/simulation-request-out.json")" "Имитация" "Simulation request response should return simulation-focused status message"
        test_pass
    else
        test_fail "Simulation request in post-handoff mode should not reopen brief review"
    fi

    test_start "integration_local_agent_factory_web_confirmation_does_not_overwrite_expected_outputs_with_editorial_one_page_feedback"
    if python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$BRIEF_FIXTURE" --state-root "$tmpdir/editorial-one-page-state" --output "$tmpdir/editorial-one-page-review-out.json" >/dev/null &&
        jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-brief-review-008",
          "request_id": "web-request-brief-review-008",
          "transport_mode": "synthetic_fixture",
          "ui_action": "request_brief_correction",
          "user_text": "Сделай правку: в one-page добавь отдельный блок с краткой рекомендацией в самом начале."
        } | del(.brief_section_updates) | del(.demo_access_grant)' "$tmpdir/editorial-one-page-review-out.json" >"$tmpdir/editorial-one-page-source.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/editorial-one-page-source.json" --state-root "$tmpdir/editorial-one-page-state" --output "$tmpdir/editorial-one-page-out.json" >/dev/null; then
        local expected_outputs_before expected_outputs_after
        expected_outputs_before="$(jq -c '.discovery_runtime_state.requirement_brief.expected_outputs' "$tmpdir/editorial-one-page-review-out.json")"
        expected_outputs_after="$(jq -c '.discovery_runtime_state.requirement_brief.expected_outputs' "$tmpdir/editorial-one-page-out.json")"
        assert_eq "$expected_outputs_before" "$expected_outputs_after" "Editorial one-page correction should not overwrite expected_outputs with command text"
        assert_contains "$(jq -r '.next_question' "$tmpdir/editorial-one-page-out.json")" "Правку применил" "Editorial correction should still be acknowledged as applied"
        test_pass
    else
        test_fail "Editorial one-page correction should preserve expected_outputs semantics"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_integration_local_agent_factory_web_confirmation_tests
fi
