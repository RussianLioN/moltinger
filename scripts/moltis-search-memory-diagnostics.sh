#!/usr/bin/env bash
set -euo pipefail

CONFIG_PATH="config/moltis.toml"
LOG_PATH=""

usage() {
    cat <<'EOF'
Usage: moltis-search-memory-diagnostics.sh [--config <path>] [--log-file <path>]

Emit a JSON summary of the tracked Tavily search + memory/embeddings contract and,
optionally, a runtime-log failure taxonomy for Tavily SSE and memory_search errors.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)
            CONFIG_PATH="${2:-}"
            shift 2
            ;;
        --log-file)
            LOG_PATH="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "moltis-search-memory-diagnostics.sh: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ ! -f "$CONFIG_PATH" ]]; then
    echo "moltis-search-memory-diagnostics.sh: config file not found: $CONFIG_PATH" >&2
    exit 2
fi

if [[ -n "$LOG_PATH" && ! -f "$LOG_PATH" ]]; then
    echo "moltis-search-memory-diagnostics.sh: log file not found: $LOG_PATH" >&2
    exit 2
fi

python3 - "$CONFIG_PATH" "$LOG_PATH" <<'PY'
import json
from pathlib import Path
import sys

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover
    import tomli as tomllib


config_path = Path(sys.argv[1])
log_path = Path(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2] else None

with config_path.open("rb") as fh:
    config = tomllib.load(fh)

tools = config.get("tools") or {}
web_tools = tools.get("web") or {}
search = web_tools.get("search") or {}
mcp_servers = ((config.get("mcp") or {}).get("servers") or {})
tavily = mcp_servers.get("tavily") or {}
memory = config.get("memory") or {}

watch_dirs = memory.get("watch_dirs") or []
if isinstance(watch_dirs, str):
    watch_dirs = [watch_dirs]

tracked = {
    "config_path": str(config_path),
    "search": {
        "builtin_enabled": bool(search.get("enabled", True)),
        "tavily_mcp_enabled": bool(tavily),
        "tavily_transport": tavily.get("transport"),
        "tavily_url_present": bool(tavily.get("url")),
        "tavily_url_uses_query_api_key": "tavilyApiKey=" in str(tavily.get("url", "")),
    },
    "memory": {
        "disable_rag": memory.get("disable_rag"),
        "provider": memory.get("provider"),
        "model": memory.get("model"),
        "provider_pinned": bool(memory.get("provider")),
        "watch_dirs": watch_dirs,
        "watch_dirs_configured": bool(watch_dirs),
    },
}

runtime = {
    "log_path": str(log_path) if log_path else None,
    "tavily": {
        "tavily_search_invocations": 0,
        "mcp_sse_handshake_failures": 0,
        "mcp_auto_restart_failures": 0,
    },
    "memory": {
        "memory_search_invocations": 0,
        "memory_search_tool_failures": 0,
        "legacy_bigmodel_embeddings_400": 0,
        "legacy_groq_embeddings_401": 0,
    },
}

if log_path:
    text = log_path.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()

    def count_lines(predicate) -> int:
        return sum(1 for line in lines if predicate(line))

    runtime["tavily"]["tavily_search_invocations"] = count_lines(lambda line: "mcp__tavily__tavily_search" in line)
    runtime["tavily"]["mcp_sse_handshake_failures"] = count_lines(lambda line: "MCP SSE initialize handshake failed" in line)
    runtime["tavily"]["mcp_auto_restart_failures"] = count_lines(lambda line: "MCP auto-restart failed" in line)
    runtime["memory"]["memory_search_invocations"] = count_lines(lambda line: "memory_search" in line)
    runtime["memory"]["memory_search_tool_failures"] = count_lines(
        lambda line: "memory_search" in line and ("tool execution failed" in line or "all embedding providers failed" in line)
    )
    runtime["memory"]["legacy_bigmodel_embeddings_400"] = count_lines(
        lambda line: "https://open.bigmodel.cn/api/coding/paas/v4/embeddings" in line or "https://api.z.ai/api/coding/paas/v4/embeddings" in line or "openai: HTTP status client error (400 Bad Request)" in line
    )
    runtime["memory"]["legacy_groq_embeddings_401"] = count_lines(
        lambda line: "https://api.groq.com/openai/v1/embeddings" in line or "groq: HTTP status client error (401 Unauthorized)" in line
    )

keyword_only_mode = tracked["memory"]["disable_rag"] is True
provider_pinned = tracked["memory"]["provider_pinned"]
watch_dirs_configured = tracked["memory"]["watch_dirs_configured"]

risk_summary = {
    "tavily_relies_on_remote_sse": (not tracked["search"]["builtin_enabled"]) and tracked["search"]["tavily_transport"] == "sse",
    "tavily_transport_unstable": runtime["tavily"]["mcp_sse_handshake_failures"] > 0 or runtime["tavily"]["mcp_auto_restart_failures"] > 0,
    "memory_provider_autodetect": (not keyword_only_mode) and not provider_pinned,
    "memory_missing_watch_dirs": not watch_dirs_configured,
    "memory_embedding_provider_failures_present": runtime["memory"]["legacy_bigmodel_embeddings_400"] > 0 or runtime["memory"]["legacy_groq_embeddings_401"] > 0 or runtime["memory"]["memory_search_tool_failures"] > 0,
    "legacy_bigmodel_embedding_drift_suspected": runtime["memory"]["legacy_bigmodel_embeddings_400"] > 0,
    "legacy_groq_embedding_drift_suspected": runtime["memory"]["legacy_groq_embeddings_401"] > 0,
}

print(
    json.dumps(
        {
            "tracked": tracked,
            "runtime_log_signals": runtime,
            "risk_summary": risk_summary,
        },
        indent=2,
        ensure_ascii=False,
    )
)
PY
