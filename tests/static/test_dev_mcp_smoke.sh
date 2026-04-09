#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

MCP_CONFIG_FILE="$PROJECT_ROOT/.mcp.json"

run_dev_mcp_smoke_tests() {
    start_timer

    test_start "dev_mcp_config_exists"
    if [[ -f "$MCP_CONFIG_FILE" ]]; then
        test_pass
    else
        test_fail "Missing .mcp.json"
    fi

    test_start "dev_mcp_config_valid_json"
    if jq -e '.mcpServers | type == "object"' "$MCP_CONFIG_FILE" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Invalid mcpServers object"
    fi

    test_start "dev_mcp_required_servers_present"
    local missing=()
    local server
    for server in context7 sequential-thinking supabase playwright shadcn serena mempalace; do
        jq -e --arg server "$server" '.mcpServers[$server]' "$MCP_CONFIG_FILE" >/dev/null 2>&1 || missing+=("$server")
    done
    if [[ ${#missing[@]} -eq 0 ]]; then
        test_pass
    else
        test_fail "Missing MCP servers: ${missing[*]}"
    fi

    test_start "dev_mcp_mempalace_uses_repo_wrapper"
    if jq -e '.mcpServers.mempalace.command == "./scripts/mempalace-mcp-server.sh"' "$MCP_CONFIG_FILE" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "MemPalace MCP entry must use repo wrapper"
    fi

    test_start "dev_mcp_entries_have_transport_definition"
    if jq -e '
        .mcpServers
        | to_entries
        | all(.value.command or (.value.transport == "sse" and .value.url))
      ' "$MCP_CONFIG_FILE" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "One or more MCP entries have no command or SSE transport definition"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_dev_mcp_smoke_tests
fi
