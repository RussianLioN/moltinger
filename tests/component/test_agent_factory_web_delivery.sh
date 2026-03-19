#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

WEB_ADAPTER_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-web-adapter.py"
DELIVERY_FIXTURE="$PROJECT_ROOT/tests/fixtures/agent-factory/web-demo/session-download-ready.json"
REVIEW_FIXTURE="$PROJECT_ROOT/tests/fixtures/agent-factory/web-demo/session-awaiting-confirmation.json"

run_component_agent_factory_web_delivery_tests() {
    start_timer
    require_commands_or_skip python3 jq || {
        test_start "component_agent_factory_web_delivery_prereqs"
        test_skip "python3 and jq are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    test_start "component_agent_factory_web_delivery_exposes_sanitized_browser_downloads"
    if python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$DELIVERY_FIXTURE" --state-root "$tmpdir/state" --output "$tmpdir/downloads-out.json" >/dev/null; then
        assert_eq "download_ready" "$(jq -r '.status' "$tmpdir/downloads-out.json")" "Ready handoff should turn into a download-ready browser response"
        assert_eq "download_artifact" "$(jq -r '.next_action' "$tmpdir/downloads-out.json")" "Browser response should point the user to artifact download"
        assert_eq "downloads_ready" "$(jq -r '.status_snapshot.user_visible_status' "$tmpdir/downloads-out.json")" "User-visible status should reflect ready downloads"
        assert_eq "Скачать артефакты" "$(jq -r '.status_snapshot.next_recommended_action_label' "$tmpdir/downloads-out.json")" "Browser next action should stay business-readable"
        assert_eq "5" "$(jq -r '.download_artifacts | length' "$tmpdir/downloads-out.json")" "Five concept-pack artifacts should be exposed to the browser (core pack + production simulation)"
        assert_eq "5" "$(jq -r '[.download_artifacts[] | select(.download_status == "ready")] | length' "$tmpdir/downloads-out.json")" "All browser downloads should be marked ready"
        assert_contains "$(jq -r '.download_artifacts[0].download_url' "$tmpdir/downloads-out.json")" "/api/download?session_id=web-demo-session-downloads&token=" "Download metadata should point to the browser download endpoint"
        assert_contains "$(jq -r '[.reply_cards[].card_kind] | join(",")' "$tmpdir/downloads-out.json")" "download_prompt" "Browser cards should include an explicit download prompt"
        assert_file_exists "$tmpdir/state/downloads/web-demo-session-downloads/delivery-index.json" "Server-side delivery index should be persisted for download resolution"
        local response_dump
        response_dump="$(cat "$tmpdir/downloads-out.json")"
        if [[ "$response_dump" == *"/Users/"* || "$response_dump" == *"download_ref"* || "$response_dump" == *"working_root"* || "$response_dump" == *"download_root"* ]]; then
            test_fail "Browser delivery response should not leak internal filesystem paths"
        else
            test_pass
        fi
    else
        test_fail "Ready handoff fixture should produce sanitized browser downloads"
    fi

    test_start "component_agent_factory_web_delivery_blocks_downloads_before_confirmation"
    if python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$REVIEW_FIXTURE" --state-root "$tmpdir/state" --output "$tmpdir/review-out.json" >/dev/null; then
        assert_eq "false" "$(jq -r 'has("download_artifacts")' "$tmpdir/review-out.json")" "Awaiting-confirmation brief should not expose browser downloads yet"
        assert_eq "awaiting_confirmation" "$(jq -r '.status' "$tmpdir/review-out.json")" "Review state should remain in confirmation mode before downstream launch"
        test_pass
    else
        test_fail "Awaiting-confirmation fixture should stay blocked from browser downloads"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_agent_factory_web_delivery_tests
fi
