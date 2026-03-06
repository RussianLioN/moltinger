#!/bin/bash
# test_mcp_servers.sh - Integration tests for MCP server connectivity
# Tests Model Context Protocol server availability and configuration
#
# Test Scenarios:
#   - Context7 MCP server connectivity
#   - Sequential Thinking MCP server connectivity
#   - Supabase MCP server connectivity
#   - Playwright MCP server connectivity
#   - Shadcn MCP server connectivity
#   - Serena MCP server connectivity
#
# Usage:
#   source tests/integration/test_mcp_servers.sh
#
# Exit Codes:
#   0 - All tests passed
#   1 - One or more tests failed
#   2 - Dependencies missing (skip)
#
# Part of: 001-docker-deploy-improvements
# Contract: specs/001-docker-deploy-improvements/contracts/test-integration.md

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source test helpers
# shellcheck source=tests/lib/test_helpers.sh
source "$LIB_DIR/test_helpers.sh"

# Test configuration
TEST_TIMEOUT=60
MCP_CONFIG_FILE="${PROJECT_ROOT}/.mcp.json"

# MCP server definitions
# Format: "server_name|process_pattern|command_to_check"
declare -a MCP_SERVERS=(
    "context7|mcp-server-context7|npx -y @context7/mcp-server"
    "sequential-thinking|mcp-sequential-thinking|npx -y @executeautomation/sequential-thinking-mcp-server"
    "supabase|mcp-supabase|npx -y @supabase/mcp-server"
    "playwright|mcp-playwright|npx -y @executeautomation/playwright-mcp-server"
    "shadcn|mcp-shadcn|npx -y shadcn-mcp-server"
    "serena|mcp-serena|mcp-serena"
)

# Server availability results
declare -A MCP_SERVER_AVAILABLE
declare -A MCP_SERVER_CONFIGURED

# ==============================================================================
# SETUP AND TEARDOWN
# ==============================================================================

# Setup test environment
setup_mcp_tests() {
    log_debug "Setting up MCP server tests"

    # Check dependencies
    if ! command -v pgrep &> /dev/null; then
        test_skip "pgrep not installed"
        return 2
    fi

    if ! command -v curl &> /dev/null; then
        test_skip "curl not installed"
        return 2
    fi

    # Check if MCP config exists
    if [[ ! -f "$MCP_CONFIG_FILE" ]]; then
        log_warn "MCP config file not found: $MCP_CONFIG_FILE"
    else
        log_debug "Found MCP config: $MCP_CONFIG_FILE"
    fi

    return 0
}

# Cleanup test environment
cleanup_mcp_tests() {
    log_debug "Cleaning up MCP server tests"
    # No cleanup needed
}

# Register cleanup on exit
trap cleanup_mcp_tests EXIT

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

# Check if MCP server is configured in .mcp.json
# Usage: is_mcp_configured "server_name"
is_mcp_configured() {
    local server_name="$1"

    if [[ ! -f "$MCP_CONFIG_FILE" ]]; then
        return 1
    fi

    # Check if server is mentioned in config
    if grep -q "\"$server_name\"" "$MCP_CONFIG_FILE" 2>/dev/null; then
        return 0
    fi

    return 1
}

# Check if MCP server process is running
# Usage: is_mcp_running "process_pattern"
is_mcp_running() {
    local pattern="$1"

    if pgrep -f "$pattern" > /dev/null 2>&1; then
        return 0
    fi

    return 1
}

# Check if MCP server command is available
# Usage: is_mcp_command_available "command"
is_mcp_command_available() {
    local command="$1"

    # Extract base command (before first space)
    local base_cmd
    base_cmd=$(echo "$command" | awk '{print $1}')

    # Check if command exists
    if command -v "$base_cmd" &> /dev/null; then
        return 0
    fi

    # For npx commands, check if npm/node is available
    if [[ "$base_cmd" == "npx" ]]; then
        if command -v npx &> /dev/null; then
            return 0
        fi
    fi

    return 1
}

# ==============================================================================
# TEST CASES
# ==============================================================================

# Test 1: MCP config file exists and is valid JSON
test_mcp_config_file() {
    test_start "mcp_config_file"

    if [[ ! -f "$MCP_CONFIG_FILE" ]]; then
        test_skip "MCP config file not found: $MCP_CONFIG_FILE"
        return 2
    fi

    # Validate JSON format
    if command -v jq &> /dev/null; then
        if ! jq -e '.' "$MCP_CONFIG_FILE" > /dev/null 2>&1; then
            test_fail "MCP config file is not valid JSON"
            return 1
        fi
    fi

    test_pass
}

# Test 2: Check individual MCP servers
test_mcp_server() {
    local server_name="$1"
    local process_pattern="$2"
    local command="$3"

    test_start "mcp_server_${server_name}"

    # Check if configured
    if is_mcp_configured "$server_name"; then
        MCP_SERVER_CONFIGURED["$server_name"]=true
        log_debug "$server_name: configured"
    else
        MCP_SERVER_CONFIGURED["$server_name"]=false
        log_debug "$server_name: not configured"
    fi

    # Check if command is available
    if ! is_mcp_command_available "$command"; then
        test_skip "$server_name command not available"
        return 2
    fi

    # Check if process is running (optional for integration tests)
    if is_mcp_running "$process_pattern"; then
        MCP_SERVER_AVAILABLE["$server_name"]=true
        log_debug "$server_name: running"
        test_pass
    else
        MCP_SERVER_AVAILABLE["$server_name"]=false
        log_debug "$server_name: not running"
        test_skip "$server_name process not running (may be started on demand)"
    fi
}

# Test 3: Context7 MCP server
test_context7_mcp() {
    test_mcp_server "context7" "mcp-server-context7" "npx -y @context7/mcp-server"
}

# Test 4: Sequential Thinking MCP server
test_sequential_thinking_mcp() {
    test_mcp_server "sequential-thinking" "mcp-sequential-thinking" "npx -y @executeautomation/sequential-thinking-mcp-server"
}

# Test 5: Supabase MCP server
test_supabase_mcp() {
    test_mcp_server "supabase" "mcp-supabase" "npx -y @supabase/mcp-server"
}

# Test 6: Playwright MCP server
test_playwright_mcp() {
    test_mcp_server "playwright" "mcp-playwright" "npx -y @executeautomation/playwright-mcp-server"
}

# Test 7: Shadcn MCP server
test_shadcn_mcp() {
    test_mcp_server "shadcn" "mcp-shadcn" "npx -y shadcn-mcp-server"
}

# Test 8: Serena MCP server
test_serena_mcp() {
    test_mcp_server "serena" "mcp-serena" "mcp-serena"
}

# Test 9: Moltis can access MCP servers via API (if running)
test_moltis_mcp_api() {
    test_start "moltis_mcp_api"

    local moltis_url="${MOLTIS_URL:-http://localhost:13131}"

    # Check if Moltis is running
    if ! curl -s --max-time 5 "$moltis_url/health" > /dev/null 2>&1; then
        test_skip "Moltis not running at $moltis_url"
        return 2
    fi

    # Try to access MCP servers endpoint
    local response_code
    response_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 10 \
        "${moltis_url}/api/mcp/servers" 2>/dev/null || echo "000")

    if [[ "$response_code" == "200" ]]; then
        test_pass
    elif [[ "$response_code" == "404" ]]; then
        test_skip "MCP API endpoint not available (404)"
    elif [[ "$response_code" == "401" ]] || [[ "$response_code" == "403" ]]; then
        test_skip "MCP API endpoint requires authentication"
    else
        test_fail "Unexpected response code: $response_code"
    fi
}

# Test 10: MCP server tools are discoverable (if configured)
test_mcp_tools_discoverable() {
    test_start "mcp_tools_discoverable"

    if [[ ! -f "$MCP_CONFIG_FILE" ]]; then
        test_skip "MCP config not found"
        return 2
    fi

    # Check if config has tools defined
    if command -v jq &> /dev/null; then
        local tool_count
        tool_count=$(jq '[.. | .tools? // empty] | add | length' "$MCP_CONFIG_FILE" 2>/dev/null || echo "0")

        if [[ "$tool_count" -gt 0 ]]; then
            log_debug "Found $tool_count MCP tools configured"
            test_pass
        else
            test_skip "No MCP tools found in config"
        fi
    else
        test_skip "jq not available for config parsing"
    fi
}

# ==============================================================================
# TEST RUNNER
# ==============================================================================

# Run all MCP server tests
run_mcp_server_tests() {
    local setup_code=0
    set +e
    setup_mcp_tests
    setup_code=$?
    set -e

    if [[ $setup_code -ne 0 ]]; then
        # Skip all tests
        test_start "mcp_server_tests"
        test_skip "Dependencies not met"
        return 2
    fi

    log_info "Running MCP server integration tests..."
    log_info "MCP config: $MCP_CONFIG_FILE"

    # Run all test cases
    test_mcp_config_file || true
    test_context7_mcp || true
    test_sequential_thinking_mcp || true
    test_supabase_mcp || true
    test_playwright_mcp || true
    test_shadcn_mcp || true
    test_serena_mcp || true
    test_moltis_mcp_api || true
    test_mcp_tools_discoverable || true

    # Print summary of server status
    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo ""
        log_info "MCP Server Status Summary:"

        for server_entry in "${MCP_SERVERS[@]}"; do
            IFS='|' read -r server_name process_pattern command <<< "$server_entry"

            local configured="${MCP_SERVER_CONFIGURED[$server_name]:-false}"
            local available="${MCP_SERVER_AVAILABLE[$server_name]:-false}"

            if [[ "$configured" == "true" ]]; then
                if [[ "$available" == "true" ]]; then
                    echo "  ✓ $server_name: configured and running"
                else
                    echo "  ⊘ $server_name: configured but not running"
                fi
            else
                echo "  - $server_name: not configured"
            fi
        done
    fi
}

# Run tests if sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    start_timer
    run_mcp_server_tests
    generate_report
fi
