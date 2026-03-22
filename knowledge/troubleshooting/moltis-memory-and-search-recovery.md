---
title: "Moltis Memory And Search Recovery"
category: "troubleshooting"
tags: ["moltis", "memory", "search", "tavily", "embeddings", "deploy"]
source: "original"
date: "2026-03-22"
confidence: "high"
---

# Moltis Memory And Search Recovery

## Summary

If `memory_search` starts failing with embedding-provider errors or Tavily
search disappears, first verify that the live Moltis process was recreated after
config changes and that the current tool surface matches the tracked runtime.

## Symptoms

- `memory_search` reports `all embedding providers failed`.
- Logs show `https://api.z.ai/.../embeddings` with `400 Bad Request`.
- Logs show `https://api.groq.com/openai/v1/embeddings` with `401 Unauthorized`.
- Tavily tools are missing from the registered tool list.
- Logs show `MCP SSE initialize handshake failed`.

## Diagnosis

1. Confirm the container start time is newer than the config update time.
2. Check startup logs for the active memory provider and model.
3. Check whether Tavily MCP initialized and synced tools into the registry.
4. Inspect live canary runs, not only `/health`.

## Actions

1. Recreate Moltis during deploy so runtime config changes are applied immediately.
2. Pin `memory.provider = "ollama"` and `model = "nomic-embed-text"` to stop
   embeddings from auto-detecting chat-oriented providers.
3. Exercise `memory_search` after restart and ensure it succeeds without `z.ai`
   or `groq` embedding fallback errors.
4. Exercise `mcp__tavily__tavily_search` after restart and ensure it succeeds
   without fresh SSE handshake failures.
5. Mirror tracked project knowledge into `~/.moltis/memory/*.md` so the built-in
   backend can index repository knowledge through the officially supported path.

## Expected Healthy Signals

- Startup logs show `memory: fallback chain configured` with `active":"ollama"`.
- Startup logs show `memory: status` with `model":"nomic-embed-text"`.
- A live `memory_search` tool call finishes with `tool execution succeeded`.
- A live `mcp__tavily__tavily_search` tool call finishes with `tool execution succeeded`.
