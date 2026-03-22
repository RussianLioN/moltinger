#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

ADAPTER_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-telegram-adapter.py"
NEW_PROJECT_FIXTURE="$PROJECT_ROOT/tests/fixtures/agent-factory/telegram/update-new-project.json"

run_component_agent_factory_telegram_routing_tests() {
    start_timer
    require_commands_or_skip python3 jq || {
        test_start "component_agent_factory_telegram_routing_prereqs"
        test_skip "python3 and jq are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    test_start "component_agent_factory_telegram_routing_normalizes_and_routes_text_update"
    if python3 "$ADAPTER_SCRIPT" handle-update \
        --source "$NEW_PROJECT_FIXTURE" \
        --state-root "$tmpdir/state" \
        --output "$tmpdir/out.json" >/dev/null; then
        assert_eq "true" "$(jq -r '.ok' "$tmpdir/out.json")" "Adapter should return ok=true for valid text update"
        assert_eq "262872984" "$(jq -r '.telegram_update_envelope.chat_id' "$tmpdir/out.json")" "Envelope should keep Telegram chat id"
        assert_eq "262872984" "$(jq -r '.telegram_update_envelope.from_user_id' "$tmpdir/out.json")" "Envelope should keep Telegram user id"
        assert_eq "start_project" "$(jq -r '.telegram_intent.intent_type' "$tmpdir/out.json")" "First text turn should start a project"
        assert_contains "$(jq -r '.reply_payloads | map(.reply_kind) | join(",")' "$tmpdir/out.json")" "discovery_question" \
            "Adapter should return at least one discovery question payload"
        assert_false "$(jq -r '[.reply_payloads[].rendered_text | test("/Users/|/opt/|data/agent-factory|\\\\.beads/")] | any' "$tmpdir/out.json")" \
            "Telegram payloads must not leak internal filesystem paths"
        test_pass
    else
        test_fail "Adapter should normalize update and route it into discovery runtime"
    fi

    test_start "component_agent_factory_telegram_routing_returns_polite_fallback_for_unsupported_update"
    cat > "$tmpdir/unsupported.json" <<'JSON'
{
  "update_id": 880019999,
  "inline_query": {
    "id": "query-1",
    "query": "ping"
  }
}
JSON
    if python3 "$ADAPTER_SCRIPT" handle-update \
        --source "$tmpdir/unsupported.json" \
        --state-root "$tmpdir/state" \
        --output "$tmpdir/unsupported-out.json" >/dev/null; then
        assert_eq "false" "$(jq -r '.ok' "$tmpdir/unsupported-out.json")" "Unsupported update should return ok=false"
        assert_eq "error_message" "$(jq -r '.reply_payloads[0].reply_kind' "$tmpdir/unsupported-out.json")" \
            "Unsupported update should return explicit error_message payload"
        assert_contains "$(jq -r '.reply_payloads[0].rendered_text' "$tmpdir/unsupported-out.json")" "текст" \
            "Fallback should explain that adapter expects text messages"
        test_pass
    else
        test_fail "Adapter should return a safe fallback for unsupported Telegram updates"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_agent_factory_telegram_routing_tests
fi
