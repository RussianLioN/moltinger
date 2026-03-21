#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

WEB_ADAPTER_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-web-adapter.py"
REVIEW_FIXTURE="$PROJECT_ROOT/tests/fixtures/agent-factory/web-demo/session-awaiting-confirmation.json"

run_integration_local_agent_factory_web_handoff_tests() {
    start_timer
    require_commands_or_skip python3 jq curl || {
        test_start "integration_local_agent_factory_web_handoff_prereqs"
        test_skip "python3, jq and curl are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    test_start "integration_local_agent_factory_web_handoff_turns_confirmed_brief_into_downloads"
    if python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$REVIEW_FIXTURE" --state-root "$tmpdir/state" --output "$tmpdir/review-out.json" >/dev/null &&
        jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-brief-review-010",
          "request_id": "web-request-brief-review-010",
          "transport_mode": "synthetic_fixture",
          "ui_action": "confirm_brief",
          "user_text": ""
        } | del(.demo_access_grant)' "$tmpdir/review-out.json" >"$tmpdir/confirm-source.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/confirm-source.json" --state-root "$tmpdir/state" --output "$tmpdir/confirmed-out.json" >/dev/null &&
        jq '.web_conversation_envelope = {
          "web_conversation_envelope_id": "web-envelope-brief-review-011",
          "request_id": "web-request-brief-review-011",
          "transport_mode": "synthetic_fixture",
          "ui_action": "request_status",
          "user_text": ""
        } | del(.demo_access_grant)' "$tmpdir/confirmed-out.json" >"$tmpdir/handoff-source.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/handoff-source.json" --state-root "$tmpdir/state" --output "$tmpdir/downloads-out.json" >/dev/null; then
        assert_eq "confirmed" "$(jq -r '.status' "$tmpdir/confirmed-out.json")" "Explicit browser confirmation should still return a confirmed brief before downstream launch"
        local confirmed_next_action
        confirmed_next_action="$(jq -r '.next_action' "$tmpdir/confirmed-out.json")"
        if [[ "$confirmed_next_action" == "start_concept_pack_handoff" || "$confirmed_next_action" == "download_artifact" ]]; then
            :
        else
            test_fail "Confirmed browser brief should either signal downstream handoff readiness or immediate download readiness"
        fi
        assert_eq "download_ready" "$(jq -r '.status' "$tmpdir/downloads-out.json")" "Status refresh should auto-launch downstream generation and expose browser downloads"
        assert_eq "download_artifact" "$(jq -r '.next_action' "$tmpdir/downloads-out.json")" "Download-ready browser response should point to artifact download"
        assert_eq "ready" "$(jq -r '.status_snapshot.download_readiness' "$tmpdir/downloads-out.json")" "Status snapshot should mark browser downloads as ready"
        assert_eq "one_page_summary" "$(jq -r '.ui_projection.primary_artifact' "$tmpdir/downloads-out.json")" "Primary artifact should point to one-page summary"
        assert_eq "completed" "$(jq -r '.production_simulation.status' "$tmpdir/downloads-out.json")" "Post-handoff flow should run production simulation and expose status"
        assert_true "$(jq -r '.download_artifacts | length >= 4' "$tmpdir/downloads-out.json")" "Concept pack + production simulation report should be exposed as browser downloads"
        assert_true "$(jq -r '[.download_artifacts[] | select(.artifact_kind == "one_page_summary")] | length == 1' "$tmpdir/downloads-out.json")" "Download list should include one-page summary artifact"
        assert_true "$(jq -r '[.download_artifacts[] | select(.artifact_kind == "production_simulation")] | length == 1' "$tmpdir/downloads-out.json")" "Download list should include production simulation artifact"
        assert_eq "1.0" "$(jq -r '.download_artifacts[0].brief_version' "$tmpdir/downloads-out.json")" "Browser download metadata should keep the confirmed brief version"
        assert_eq "false" "$(jq -r 'has("delivery_error")' "$tmpdir/downloads-out.json")" "Successful browser handoff should not emit a delivery error"
        assert_file_exists "$tmpdir/state/downloads/web-demo-session-brief-review/concept-pack.json" "Generated concept-pack manifest should be stored under the web-demo state root"
        assert_file_exists "$tmpdir/state/downloads/web-demo-session-brief-review/downloads/one-page-summary.md" "One-page summary should be downloadable from the web-demo state root"
        assert_file_exists "$tmpdir/state/downloads/web-demo-session-brief-review/downloads/project-doc.md" "Project doc should be downloadable from the web-demo state root"
        assert_file_exists "$tmpdir/state/downloads/web-demo-session-brief-review/downloads/agent-spec.md" "Agent spec should be downloadable from the web-demo state root"
        assert_file_exists "$tmpdir/state/downloads/web-demo-session-brief-review/downloads/presentation.md" "Presentation should be downloadable from the web-demo state root"
        assert_file_exists "$tmpdir/state/downloads/web-demo-session-brief-review/downloads/digital-employee-demo.md" "Production simulation report should be downloadable from the web-demo state root"
        assert_file_exists "$tmpdir/state/employees/digital-employees-registry.json" "Post-handoff production simulation should register a digital employee in registry"
        if compgen -G "$tmpdir/state/employees/executions/*.json" >/dev/null; then
            :
        else
            test_fail "Post-handoff production simulation should persist at least one execution record"
        fi
        assert_eq "web" "$(jq -r '.delivery_channel' "$tmpdir/state/downloads/web-demo-session-brief-review/concept-pack.json")" "Generated manifest should preserve the web delivery channel"
        assert_eq "$(jq -r '.discovery_runtime_state.factory_handoff_record.factory_handoff_id' "$tmpdir/downloads-out.json")" "$(jq -r '.source_provenance.factory_handoff_id' "$tmpdir/state/downloads/web-demo-session-brief-review/concept-pack.json")" "Generated manifest should keep exact handoff provenance"
        test_pass
    else
        test_fail "Browser status refresh after confirmation should automatically launch downstream handoff and expose concept-pack downloads"
    fi

    test_start "integration_local_agent_factory_web_handoff_download_endpoint_serves_artifact"
    local server_pid=""
    local download_url=""
    local preview_endpoint=""
    local http_body="$tmpdir/project-doc.md"
    local preview_body="$tmpdir/one-page-preview.html"
    local health_ready="false"
    download_url="$(jq -r '.download_artifacts[] | select(.artifact_kind == "project_doc") | .download_url' "$tmpdir/downloads-out.json")"
    preview_endpoint="$(jq -r '
      .web_demo_session.web_demo_session_id as $session_id
      | .download_artifacts[]
      | select(.artifact_kind == "one_page_summary")
      | "/api/preview/\($session_id)/\(.artifact_kind)"
    ' "$tmpdir/downloads-out.json")"
    if [[ -n "$download_url" ]]; then
        python3 "$WEB_ADAPTER_SCRIPT" serve --host 127.0.0.1 --port 18797 --state-root "$tmpdir/state" --assets-root "$PROJECT_ROOT/web/agent-factory-demo" >/dev/null 2>"$tmpdir/server.log" &
        server_pid=$!
        for _ in $(seq 1 40); do
            if curl -fsS "http://127.0.0.1:18797/health" >/dev/null 2>&1; then
                health_ready="true"
                break
            fi
            sleep 0.25
        done
        if [[ "$health_ready" != "true" ]] && grep -q "PermissionError: \[Errno 1\] Operation not permitted" "$tmpdir/server.log"; then
            test_skip "Sandbox denied local port bind for web adapter serve check"
        elif [[ "$health_ready" == "true" ]] &&
            curl -fsS "http://127.0.0.1:18797${download_url}" -o "$http_body"; then
            assert_contains "$(cat "$http_body")" "# Проектный документ:" "Download endpoint should serve the generated project doc content"
            test_pass
        else
            test_fail "Download endpoint should serve the generated browser artifact over HTTP"
        fi
    else
        test_fail "Download-ready response should expose a project-doc browser URL"
    fi
    if [[ -n "$server_pid" ]]; then
        kill "$server_pid" >/dev/null 2>&1 || true
        wait "$server_pid" 2>/dev/null || true
    fi

    test_start "integration_local_agent_factory_web_handoff_preview_endpoint_serves_rendered_html"
    server_pid=""
    health_ready="false"
    if [[ -n "$preview_endpoint" ]]; then
        python3 "$WEB_ADAPTER_SCRIPT" serve --host 127.0.0.1 --port 18797 --state-root "$tmpdir/state" --assets-root "$PROJECT_ROOT/web/agent-factory-demo" >/dev/null 2>"$tmpdir/server.log" &
        server_pid=$!
        for _ in $(seq 1 40); do
            if curl -fsS "http://127.0.0.1:18797/health" >/dev/null 2>&1; then
                health_ready="true"
                break
            fi
            sleep 0.25
        done
        if [[ "$health_ready" != "true" ]] && grep -q "PermissionError: \[Errno 1\] Operation not permitted" "$tmpdir/server.log"; then
            test_skip "Sandbox denied local port bind for web adapter serve check"
        elif [[ "$health_ready" == "true" ]] &&
            curl -fsS "http://127.0.0.1:18797${preview_endpoint}" -o "$preview_body"; then
            assert_contains "$(cat "$preview_body")" "<!doctype html>" "Preview endpoint should return an HTML document"
            assert_contains "$(cat "$preview_body")" "<main>" "Preview HTML should include rendered content container"
            assert_true "$(grep -qiE '<h1|<h2|<p|<pre' "$preview_body" && echo true || echo false)" "Preview HTML should contain rendered markdown blocks"
            assert_true "$(grep -qi '<pre>' "$preview_body" && echo false || echo true)" "Preview HTML should render markdown structure instead of raw <pre> block"
            test_pass
        else
            test_fail "Preview endpoint should serve rendered HTML for one-page summary"
        fi
    else
        test_fail "Download-ready response should expose session and one-page artifact needed to build preview endpoint"
    fi
    if [[ -n "$server_pid" ]]; then
        kill "$server_pid" >/dev/null 2>&1 || true
        wait "$server_pid" 2>/dev/null || true
    fi

    test_start "integration_local_agent_factory_web_handoff_request_demo_access_preserves_download_ready_state"
    if jq '{
          "web_demo_session": {
            "web_demo_session_id": .web_demo_session.web_demo_session_id
          },
          "browser_project_pointer": {
            "project_key": .browser_project_pointer.project_key
          },
          "web_conversation_envelope": {
            "web_conversation_envelope_id": "web-envelope-brief-review-012",
            "request_id": "web-request-brief-review-012",
            "transport_mode": "synthetic_fixture",
            "ui_action": "request_demo_access",
            "user_text": "",
            "linked_discovery_session_id": .web_demo_session.web_demo_session_id
          },
          "demo_access_grant": {
            "grant_value": "demo-access-token"
          }
        }' "$tmpdir/downloads-out.json" >"$tmpdir/reload-access-source.json" &&
        python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/reload-access-source.json" --state-root "$tmpdir/state" --output "$tmpdir/reload-access-out.json" >/dev/null; then
        assert_eq "download_ready" "$(jq -r '.status' "$tmpdir/reload-access-out.json")" "request_demo_access on restored session should preserve download-ready status"
        assert_eq "download_artifact" "$(jq -r '.next_action' "$tmpdir/reload-access-out.json")" "request_demo_access on restored session should keep download action"
        assert_eq "ready" "$(jq -r '.status_snapshot.download_readiness' "$tmpdir/reload-access-out.json")" "Reloaded status snapshot should keep downloads ready"
        assert_true "$(jq -r '.download_artifacts | length >= 4' "$tmpdir/reload-access-out.json")" "Reloaded session should keep generated downloads"
        assert_eq "one_page_summary" "$(jq -r '.download_artifacts[0].artifact_kind' "$tmpdir/reload-access-out.json")" "Reloaded session should keep one-page summary as primary artifact"
        test_pass
    else
        test_fail "request_demo_access on restored session should preserve download-ready artifacts"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_integration_local_agent_factory_web_handoff_tests
fi
