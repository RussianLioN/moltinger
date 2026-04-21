#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

DIAGNOSTIC_SCRIPT="$PROJECT_ROOT/scripts/moltis-search-memory-diagnostics.sh"
REAL_CONFIG="$PROJECT_ROOT/config/moltis.toml"

run_component_moltis_search_memory_diagnostics_tests() {
    start_timer

    local tmp_dir config_file log_file output_json
    tmp_dir="$(mktemp -d /tmp/moltis-search-memory-diagnostics.XXXXXX)"
    config_file="$tmp_dir/moltis.toml"
    log_file="$tmp_dir/logs.jsonl"
    output_json="$tmp_dir/report.json"

    cat > "$config_file" <<'EOF'
[tools.web.search]
enabled = false

[mcp.servers.tavily]
transport = "sse"
url = "https://mcp.tavily.com/mcp/?tavilyApiKey=${TAVILY_API_KEY}"

[memory]
llm_reranking = false
session_export = false
EOF

    cat > "$log_file" <<'EOF'
{"message":"MCP SSE initialize handshake failed"}
{"message":"MCP auto-restart failed"}
{"tool":"mcp__tavily__tavily_search","message":"tool invocation"}
{"tool":"memory_search","message":"tool execution failed"}
all embedding providers failed: openai: HTTP status client error (400 Bad Request) for url (https://open.bigmodel.cn/api/coding/paas/v4/embeddings); groq: HTTP status client error (401 Unauthorized) for url (https://api.groq.com/openai/v1/embeddings)
EOF

    test_start "component_diagnostics_script_parses_tavily_and_embedding_failure_taxonomy"
    if ! bash "$DIAGNOSTIC_SCRIPT" --config "$config_file" --log-file "$log_file" >"$output_json" 2>"$tmp_dir/stderr.log"; then
        test_fail "Diagnostic script failed on fixture config/log input"
        rm -rf "$tmp_dir"
        return
    fi

    if [[ "$(jq -r '.tracked.search.builtin_enabled' "$output_json")" != "false" ]] || \
       [[ "$(jq -r '.tracked.search.tavily_transport' "$output_json")" != "sse" ]] || \
       [[ "$(jq -r '.tracked.memory.provider_pinned' "$output_json")" != "false" ]] || \
       [[ "$(jq -r '.runtime_log_signals.tavily.mcp_sse_handshake_failures' "$output_json")" != "1" ]] || \
       [[ "$(jq -r '.runtime_log_signals.tavily.mcp_auto_restart_failures' "$output_json")" != "1" ]] || \
       [[ "$(jq -r '.runtime_log_signals.memory.legacy_bigmodel_embeddings_400' "$output_json")" != "1" ]] || \
       [[ "$(jq -r '.runtime_log_signals.memory.legacy_groq_embeddings_401' "$output_json")" != "1" ]] || \
       [[ "$(jq -r '.risk_summary.tavily_transport_unstable' "$output_json")" != "true" ]] || \
       [[ "$(jq -r '.risk_summary.memory_provider_autodetect' "$output_json")" != "true" ]] || \
       [[ "$(jq -r '.risk_summary.memory_embedding_provider_failures_present' "$output_json")" != "true" ]]; then
        test_fail "Diagnostic JSON did not capture the expected Tavily/embedding failure taxonomy"
        rm -rf "$tmp_dir"
        return
    fi
    test_pass

    test_start "component_diagnostics_script_handles_real_tracked_config_without_log_input"
    if ! bash "$DIAGNOSTIC_SCRIPT" --config "$REAL_CONFIG" >"$output_json" 2>"$tmp_dir/stderr-real.log"; then
        test_fail "Diagnostic script failed on the real tracked Moltis config"
        rm -rf "$tmp_dir"
        return
    fi

    if [[ "$(jq -r '.tracked.search.tavily_mcp_enabled' "$output_json")" != "true" ]] || \
       [[ "$(jq -r '.tracked.search.tavily_transport' "$output_json")" != "sse" ]] || \
       [[ "$(jq -r '.tracked.memory.provider_pinned' "$output_json")" != "true" ]] || \
       [[ "$(jq -r '.tracked.memory.provider' "$output_json")" != "ollama" ]] || \
       [[ "$(jq -r '.tracked.memory.model' "$output_json")" != "nomic-embed-text" ]] || \
       [[ "$(jq -r '.tracked.memory.watch_dirs_configured' "$output_json")" != "true" ]]; then
        test_fail "Real tracked config summary no longer reflects the expected pinned Tavily + memory provider contract"
        rm -rf "$tmp_dir"
        return
    fi
    test_pass

    rm -rf "$tmp_dir"
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_moltis_search_memory_diagnostics_tests
fi
