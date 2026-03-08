#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

MCP_CONFIG_FILE="$PROJECT_ROOT/.mcp.json"

run_live_mcp_real_tests() {
    start_timer

    if ! is_live_mode; then
        test_start "live_mcp_requires_live_mode"
        test_skip "Suite requires --live"
        generate_report
        return
    fi

    require_commands_or_skip jq pgrep || {
        test_start "live_mcp_setup"
        test_skip "Dependencies unavailable"
        generate_report
        return
    }

    test_start "live_mcp_config_exists"
    if [[ -f "$MCP_CONFIG_FILE" ]]; then
        test_pass
    else
        test_fail "Missing .mcp.json"
    fi

    test_start "live_mcp_config_valid_json"
    if jq -e '.mcpServers | type == "object"' "$MCP_CONFIG_FILE" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Invalid mcpServers object"
    fi

    local server
    for server in context7 sequential-thinking supabase playwright shadcn serena; do
        test_start "live_mcp_${server}_configured"
        if jq -e --arg server "$server" '.mcpServers[$server]' "$MCP_CONFIG_FILE" >/dev/null 2>&1; then
            test_pass
        else
            test_skip "${server} not configured in .mcp.json"
        fi

        test_start "live_mcp_${server}_running"
        if pgrep -f "$server" >/dev/null 2>&1; then
            test_pass
        else
            test_skip "${server} process not running in current environment"
        fi
    done

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_live_mcp_real_tests
fi
