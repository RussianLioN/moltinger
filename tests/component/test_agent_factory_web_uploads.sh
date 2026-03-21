#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

WEB_ADAPTER_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-web-adapter.py"
SESSION_NEW_FIXTURE="$PROJECT_ROOT/tests/fixtures/agent-factory/web-demo/session-new.json"
DISCOVERY_INPUT_FIXTURE="$PROJECT_ROOT/tests/fixtures/agent-factory/discovery/session-awaiting-clarification.json"

run_component_agent_factory_web_upload_tests() {
    start_timer
    require_commands_or_skip python3 jq || {
        test_start "component_agent_factory_web_uploads_prereqs"
        test_skip "python3 and jq are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    test_start "component_agent_factory_web_uploads_extracts_safe_excerpt_for_input_examples"
    local upload_base64
    upload_base64="$(
        python3 -c 'import base64; payload = "Счёт №42 от тестового поставщика\nСумма: 125000\nНужно проверить лимит и маршрут согласования.".encode("utf-8"); print(base64.b64encode(payload).decode("ascii"))'
    )"

    if jq --slurpfile runtime "$DISCOVERY_INPUT_FIXTURE" --arg upload "$upload_base64" '
        .project_key = $runtime[0].project_key
        | .browser_project_pointer.project_key = $runtime[0].project_key
        | .browser_project_pointer.linked_discovery_session_id = $runtime[0].discovery_session.discovery_session_id
        | .browser_project_pointer.selection_mode = "continue_active"
        | .web_demo_session.status = "awaiting_user_reply"
        | .web_conversation_envelope = {
            "web_conversation_envelope_id": "web-envelope-input-upload-001",
            "request_id": "web-request-input-upload-001",
            "transport_mode": "synthetic_fixture",
            "ui_action": "submit_turn",
            "user_text": "Примеры приложил файлами. Возьми обезличенный кейс.",
            "received_at": "2026-03-15T12:00:00Z"
          }
        | .discovery_runtime_state = $runtime[0]
        | .uploaded_files = [
            {
              "upload_id": "upload-input-example-001",
              "name": "input-example.txt",
              "content_type": "text/plain",
              "size_bytes": 96,
              "original_size_bytes": 96,
              "truncated": false,
              "content_base64": $upload
            }
          ]
      ' "$SESSION_NEW_FIXTURE" >"$tmpdir/upload-request.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/upload-request.json" --state-root "$tmpdir/state" --output "$tmpdir/upload-out.json" >/dev/null; then
        assert_eq "1" "$(jq -r '.uploaded_files | length' "$tmpdir/upload-out.json")" "Adapter should project one sanitized uploaded file back to the browser"
        assert_eq "excerpt_ready" "$(jq -r '.uploaded_files[0].ingest_status' "$tmpdir/upload-out.json")" "Text attachments should expose an extracted excerpt"
        assert_eq "1" "$(jq -r '.status_snapshot.uploaded_file_count' "$tmpdir/upload-out.json")" "Status snapshot should count uploaded files for browser rendering"
        assert_eq "1" "$(jq -r '.ui_projection.uploaded_file_count' "$tmpdir/upload-out.json")" "UI projection should surface the uploaded-file count"
        assert_eq "false" "$(jq -r '.uploaded_files[0] | has("content_base64")' "$tmpdir/upload-out.json")" "Browser response must not leak raw file payloads back to the client"
        assert_contains "$(jq -r '.uploaded_files[0].excerpt' "$tmpdir/upload-out.json")" "Счёт №42" "Uploaded text file should be excerpted for safe discovery use"
        assert_contains "$(jq -r '.discovery_runtime_state.normalized_answers.input_examples' "$tmpdir/upload-out.json")" "Входные примеры приложены файлами" "Input-examples answer should confirm that examples were accepted from attachments"
        assert_contains "$(jq -r '.discovery_runtime_state.normalized_answers.input_examples' "$tmpdir/upload-out.json")" "синтетически сгенерированными" "Attachment context should always include synthetic-data disclaimer for LLM analysis"
        assert_contains "$(jq -r '.discovery_runtime_state.normalized_answers.input_examples' "$tmpdir/upload-out.json")" "input-example.txt" "Captured browser answer should keep the uploaded filename for traceability"
        if compgen -G "$tmpdir/state/uploads/web-demo-session-invoice-approval/*" >/dev/null; then
            test_pass
        else
            test_fail "Uploaded file bytes should be materialized under the adapter upload state root"
        fi
    else
        test_fail "Adapter should accept browser attachments and fold them into the current discovery answer"
    fi

    test_start "component_agent_factory_web_uploads_auto_resolves_unsafe_clarification_with_meaningful_reply"
    if jq --slurpfile runtime "$DISCOVERY_INPUT_FIXTURE" '
        .project_key = $runtime[0].project_key
        | .browser_project_pointer.project_key = $runtime[0].project_key
        | .browser_project_pointer.linked_discovery_session_id = $runtime[0].discovery_session.discovery_session_id
        | .browser_project_pointer.selection_mode = "continue_active"
        | .web_demo_session.status = "awaiting_user_reply"
        | .web_conversation_envelope = {
            "web_conversation_envelope_id": "web-envelope-input-upload-002",
            "request_id": "web-request-input-upload-002",
            "transport_mode": "synthetic_fixture",
            "ui_action": "submit_turn",
            "user_text": "Файл уже приложил, можем продолжать к следующему шагу."
          }
        | .discovery_runtime_state = $runtime[0]
      ' "$SESSION_NEW_FIXTURE" >"$tmpdir/clarification-reply-request.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/clarification-reply-request.json" --state-root "$tmpdir/state" --output "$tmpdir/clarification-reply-out.json" >/dev/null; then
        assert_eq "0" "$(jq -r '[.discovery_runtime_state.clarification_items[] | select(.reason == "unsafe_data_example" and .status == "open")] | length' "$tmpdir/clarification-reply-out.json")" "Unsafe input clarification should be resolved after meaningful user reply"
        assert_ne "awaiting_clarification" "$(jq -r '.status' "$tmpdir/clarification-reply-out.json")" "Flow should leave clarification deadlock state after auto-resolution"
        assert_contains "$(jq -r '.discovery_runtime_state.normalized_answers.input_examples' "$tmpdir/clarification-reply-out.json")" "Входные примеры приложены файлами" "Resolved clarification should keep canonical attachment-based input summary in normalized answers"
        test_pass
    else
        test_fail "Adapter should auto-resolve unsafe clarification once user gives a meaningful continuation reply"
    fi

    test_start "component_agent_factory_web_uploads_auto_resolves_multiple_unsafe_clarifications_from_synthetic_ack"
    if jq --slurpfile runtime "$DISCOVERY_INPUT_FIXTURE" '
        def unsafe_item($id; $question):
          ($runtime[0].clarification_items[0]
            | .clarification_item_id = $id
            | .question_text = $question
            | .status = "open"
            | .reason = "unsafe_data_example"
            | .topic_name = "input_examples");
        def unsafe_case($id; $summary):
          ($runtime[0].example_cases[0]
            | .example_case_id = $id
            | .input_summary = $summary
            | .data_safety_status = "needs_redaction");
        .project_key = $runtime[0].project_key
        | .browser_project_pointer.project_key = $runtime[0].project_key
        | .browser_project_pointer.linked_discovery_session_id = $runtime[0].discovery_session.discovery_session_id
        | .browser_project_pointer.selection_mode = "continue_active"
        | .web_demo_session.status = "awaiting_user_reply"
        | .web_conversation_envelope = {
            "web_conversation_envelope_id": "web-envelope-input-upload-002b",
            "request_id": "web-request-input-upload-002b",
            "transport_mode": "synthetic_fixture",
            "ui_action": "submit_turn",
            "user_text": "Все данные в приложенном файле синтетические и не относятся к реальным контрагентам. Продолжаем по этому примеру."
          }
        | .discovery_runtime_state = (
            $runtime[0]
            | .clarification_items = [
                unsafe_item("clarification-unsafe-example-case-001"; "Можешь прислать пример '\''ИНН'\'' без реальных реквизитов?"),
                unsafe_item("clarification-unsafe-example-case-006"; "Можешь прислать пример '\''5503815527'\'' без реальных реквизитов?"),
                unsafe_item("clarification-unsafe-example-case-007"; "Можешь прислать пример '\''2100293800/2459831000/2606131000/2442520300'\'' без реальных реквизитов?")
              ]
            | .example_cases = [
                unsafe_case("example-case-001"; "ИНН"),
                unsafe_case("example-case-006"; "5503815527"),
                unsafe_case("example-case-007"; "2100293800/2459831000/2606131000/2442520300")
              ]
          )
      ' "$SESSION_NEW_FIXTURE" >"$tmpdir/clarification-multi-request.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/clarification-multi-request.json" --state-root "$tmpdir/state" --output "$tmpdir/clarification-multi-out.json" >/dev/null; then
        assert_eq "0" "$(jq -r '[.discovery_runtime_state.clarification_items[] | select(.reason == "unsafe_data_example" and .status == "open")] | length' "$tmpdir/clarification-multi-out.json")" "Synthetic acknowledgement should close all open unsafe clarification items"
        assert_eq "3" "$(jq -r '[.discovery_runtime_state.clarification_items[] | select(.reason == "unsafe_data_example" and .status == "resolved")] | length' "$tmpdir/clarification-multi-out.json")" "All unsafe clarification items should be marked resolved"
        assert_ne "awaiting_clarification" "$(jq -r '.status' "$tmpdir/clarification-multi-out.json")" "Flow should leave clarification state after synthetic-data acknowledgement"
        assert_contains "$(jq -r '.discovery_runtime_state.captured_answers.input_examples' "$tmpdir/clarification-multi-out.json")" "синтетически" "Captured input-examples answer should preserve synthetic-data safety marker"
        test_pass
    else
        test_fail "Adapter should resolve multiple open unsafe clarifications after explicit synthetic-data acknowledgement"
    fi

    test_start "component_agent_factory_web_uploads_accepts_sensitive_structured_example_under_default_synthetic_policy"
    if jq --slurpfile runtime "$DISCOVERY_INPUT_FIXTURE" '
        .project_key = $runtime[0].project_key
        | .browser_project_pointer.project_key = $runtime[0].project_key
        | .browser_project_pointer.linked_discovery_session_id = $runtime[0].discovery_session.discovery_session_id
        | .browser_project_pointer.selection_mode = "continue_active"
        | .web_demo_session.status = "awaiting_user_reply"
        | .web_conversation_envelope = {
            "web_conversation_envelope_id": "web-envelope-input-upload-003",
            "request_id": "web-request-input-upload-003",
            "transport_mode": "synthetic_fixture",
            "ui_action": "submit_turn",
            "user_text": "1234567890,742,500000"
          }
        | .discovery_runtime_state = $runtime[0]
      ' "$SESSION_NEW_FIXTURE" >"$tmpdir/clarification-structured-request.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/clarification-structured-request.json" --state-root "$tmpdir/state" --output "$tmpdir/clarification-structured-out.json" >/dev/null; then
        assert_eq "0" "$(jq -r '[.discovery_runtime_state.clarification_items[] | select(.reason == "unsafe_data_example" and .status == "open")] | length' "$tmpdir/clarification-structured-out.json")" "Default synthetic-data policy should auto-close unsafe clarification items"
        assert_ne "awaiting_clarification" "$(jq -r '.status' "$tmpdir/clarification-structured-out.json")" "Structured sample should not deadlock in clarification stage under default synthetic policy"
        assert_ne "resolve_clarification" "$(jq -r '.next_action' "$tmpdir/clarification-structured-out.json")" "Flow should continue without explicit unsafe-input resolution under default synthetic policy"
        assert_contains "$(jq -r '.discovery_runtime_state.captured_answers.input_examples' "$tmpdir/clarification-structured-out.json")" "синтетически" "Captured input-examples answer should keep synthetic-data disclaimer"
        test_pass
    else
        test_fail "Adapter should auto-resolve unsafe clarification for structured samples under default synthetic-data policy"
    fi

    test_start "component_agent_factory_web_uploads_auto_resolves_low_signal_clarification_reply_under_default_policy"
    if jq --slurpfile runtime "$DISCOVERY_INPUT_FIXTURE" '
        .project_key = $runtime[0].project_key
        | .browser_project_pointer.project_key = $runtime[0].project_key
        | .browser_project_pointer.linked_discovery_session_id = $runtime[0].discovery_session.discovery_session_id
        | .browser_project_pointer.selection_mode = "continue_active"
        | .web_demo_session.status = "awaiting_user_reply"
        | .web_conversation_envelope = {
            "web_conversation_envelope_id": "web-envelope-input-upload-004",
            "request_id": "web-request-input-upload-004",
            "transport_mode": "synthetic_fixture",
            "ui_action": "submit_turn",
            "user_text": "давай продолжим"
          }
        | .discovery_runtime_state = $runtime[0]
      ' "$SESSION_NEW_FIXTURE" >"$tmpdir/clarification-low-signal-request.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/clarification-low-signal-request.json" --state-root "$tmpdir/state-low-signal" --output "$tmpdir/clarification-low-signal-out.json" >/dev/null; then
        assert_ne "awaiting_clarification" "$(jq -r '.status' "$tmpdir/clarification-low-signal-out.json")" "Default synthetic policy must not keep unsafe-clarification deadlock on low-signal replies"
        assert_ne "resolve_clarification" "$(jq -r '.next_action' "$tmpdir/clarification-low-signal-out.json")" "Flow should proceed to the next discovery step instead of repeating unsafe clarification"
        assert_eq "0" "$(jq -r '[.discovery_runtime_state.clarification_items[] | select(.reason == "unsafe_data_example" and .status == "open")] | length' "$tmpdir/clarification-low-signal-out.json")" "Unsafe clarification items should be closed under default synthetic policy"
        assert_contains "$(jq -r '.discovery_runtime_state.normalized_answers.input_examples' "$tmpdir/clarification-low-signal-out.json")" "синтетически" "Input examples should include synthetic-data disclaimer after auto-resolution"
        test_pass
    else
        test_fail "Adapter should auto-resolve low-signal unsafe clarification reply under default synthetic-data policy"
    fi

    test_start "component_agent_factory_web_uploads_breaks_stale_redaction_retry_loop_when_file_already_attached"
    local stale_upload_base64
    stale_upload_base64="$(
        python3 -c 'import base64; payload = "client_id,score,limit\nSYN-100,701,250000\n".encode("utf-8"); print(base64.b64encode(payload).decode("ascii"))'
    )"
    if jq --slurpfile runtime "$DISCOVERY_INPUT_FIXTURE" --arg upload "$stale_upload_base64" '
        .project_key = $runtime[0].project_key
        | .browser_project_pointer.project_key = $runtime[0].project_key
        | .browser_project_pointer.linked_discovery_session_id = $runtime[0].discovery_session.discovery_session_id
        | .browser_project_pointer.selection_mode = "continue_active"
        | .web_demo_session.web_demo_session_id = "web-demo-session-stale-redaction-loop"
        | .web_demo_session.status = "awaiting_user_reply"
        | .web_conversation_envelope = {
            "web_conversation_envelope_id": "web-envelope-stale-redaction-loop-001",
            "request_id": "web-request-stale-redaction-loop-001",
            "transport_mode": "synthetic_fixture",
            "ui_action": "submit_turn",
            "user_text": "табличка - выгрузка по клиенту в приложении"
          }
        | .discovery_runtime_state = (
            $runtime[0]
            | .status = "awaiting_user_reply"
            | .next_action = "ask_next_question"
            | .next_topic = "input_examples"
            | .next_question = "Можешь прислать обезличенный пример входных данных (example-case-007) без реальных реквизитов, номеров и названий контрагентов?"
            | .discovery_session.current_topic = "input_examples"
            | .clarification_items = []
          )
        | .uploaded_files = [
            {
              "upload_id": "upload-stale-redaction-loop-001",
              "name": "demo-client-data.csv",
              "content_type": "text/csv",
              "size_bytes": 56,
              "original_size_bytes": 56,
              "truncated": false,
              "content_base64": $upload
            }
          ]
      ' "$SESSION_NEW_FIXTURE" >"$tmpdir/stale-redaction-loop-step1.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/stale-redaction-loop-step1.json" --state-root "$tmpdir/state-stale-redaction-loop" --output "$tmpdir/stale-redaction-loop-step1-out.json" >/dev/null &&
        jq '
          .web_conversation_envelope.request_id = "web-request-stale-redaction-loop-002"
          | .web_conversation_envelope.web_conversation_envelope_id = "web-envelope-stale-redaction-loop-002"
          | .web_conversation_envelope.ui_action = "submit_turn"
          | .web_conversation_envelope.user_text = "уже прикрепил"
          | .uploaded_files = []
          | .discovery_runtime_state = (
              .discovery_runtime_state
              | .status = "awaiting_user_reply"
              | .next_action = "ask_next_question"
              | .next_topic = "input_examples"
              | .next_question = "Можешь прислать обезличенный пример входных данных (example-case-007) без реальных реквизитов, номеров и названий контрагентов?"
              | .discovery_session.current_topic = "input_examples"
              | .clarification_items = []
            )
        ' "$tmpdir/stale-redaction-loop-step1-out.json" >"$tmpdir/stale-redaction-loop-step2.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/stale-redaction-loop-step2.json" --state-root "$tmpdir/state-stale-redaction-loop" --output "$tmpdir/stale-redaction-loop-step2-out.json" >/dev/null; then
        local stale_question_before_retry stale_next_question
        stale_question_before_retry="$(jq -r '.discovery_runtime_state.next_question' "$tmpdir/stale-redaction-loop-step2.json")"
        stale_next_question="$(jq -r '.next_question' "$tmpdir/stale-redaction-loop-step2-out.json")"
        assert_ne "$stale_question_before_retry" "$stale_next_question" "After a valid attachment the adapter should not ask the same input_examples question again"
        if [[ "$stale_next_question" == *"example-case-007"* ]]; then
            test_fail "Adapter should break stale redaction retry loop after uploaded evidence is already present"
        elif [[ "$stale_next_question" == *"обезличенный пример"* ]]; then
            test_fail "Adapter should not repeat anonymization request once input examples are accepted"
        fi
        assert_ne "input_examples" "$(jq -r '.next_topic' "$tmpdir/stale-redaction-loop-step2-out.json")" "Flow should advance beyond input_examples after stale redaction loop is auto-resolved"
        test_pass
    else
        test_fail "Adapter should auto-resolve stale redaction retry loop and advance to the next topic"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_agent_factory_web_upload_tests
fi
