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
        assert_eq "Brief подтвержден" "$(jq -r '.status_snapshot.user_visible_status_label' "$tmpdir/confirmed-out.json")" "User-visible browser label should show that the brief is confirmed"
        assert_eq "Передать brief в фабрику" "$(jq -r '.status_snapshot.next_recommended_action_label' "$tmpdir/confirmed-out.json")" "Confirmed browser state should point to the downstream handoff step"
        assert_eq "request_status" "$(jq -r '.ui_projection.preferred_ui_action' "$tmpdir/confirmed-out.json")" "Browser shell should prefer a safe status refresh after confirmation"
        assert_contains "$(jq -r '[.reply_cards[].title] | join(",")' "$tmpdir/confirmed-out.json")" "Brief подтвержден" "Confirmed browser response should include an explicit confirmation card"
        test_pass
    else
        test_fail "Browser confirmation flow should move from reviewed brief to revised brief to confirmed state"
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
        assert_eq "start_concept_pack_handoff" "$(jq -r '.next_action' "$tmpdir/text-confirmed-out.json")" "Text confirmation should move flow to handoff action"
        assert_contains "$(jq -r '.discovery_runtime_state.confirmation_snapshot.confirmation_text' "$tmpdir/text-confirmed-out.json")" "Подтверждаю brief" "Confirmation snapshot should keep the textual user confirmation"
        test_pass
    else
        test_fail "Browser flow should map submit_turn text confirmation to confirm_brief behavior"
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

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_integration_local_agent_factory_web_confirmation_tests
fi
