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
        assert_contains "$(jq -r '.discovery_runtime_state.normalized_answers.input_examples' "$tmpdir/upload-out.json")" "Контекст из прикреплённых файлов" "Input-examples answer should include the attachment context block"
        assert_contains "$(jq -r '.discovery_runtime_state.normalized_answers.input_examples' "$tmpdir/upload-out.json")" "input-example.txt" "Captured browser answer should keep the uploaded filename for traceability"
        assert_contains "$(jq -r '.discovery_runtime_state.normalized_answers.input_examples' "$tmpdir/upload-out.json")" "Счёт №42" "Captured browser answer should carry the extracted excerpt into discovery"
        if compgen -G "$tmpdir/state/uploads/web-demo-session-invoice-approval/*" >/dev/null; then
            test_pass
        else
            test_fail "Uploaded file bytes should be materialized under the adapter upload state root"
        fi
    else
        test_fail "Adapter should accept browser attachments and fold them into the current discovery answer"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_agent_factory_web_upload_tests
fi
